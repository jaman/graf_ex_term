defmodule GrafExTerm.Refresh.DataCache do
  @moduledoc """
  Singleton process holding the most recent query results for every dashboard,
  downsampled for display.

  `GrafExTerm.Refresh.Scheduler` writes here after each fetch and screens poll
  with `take_if_updated/2`, which lets a screen skip re-rendering when nothing
  has changed. Only the latest result per dashboard is kept; there is no
  history.

  Stored data is not the raw query result. Each series is reduced to at most
  200 points by min/max bucketing — the extremes of each bucket are kept in
  timestamp order, so spikes survive downsampling — and the series set is then
  passed through `GrafExTerm.Refresh.SeriesClusterer`. Consumers therefore see
  fewer points and possibly fewer series than the datasource returned, and
  series may carry a `:weight`.

  Versions are `System.monotonic_time/0` values, meaningful only for equality
  against a previously observed version.
  """

  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Stores the results for `dashboard_uid`, replacing any previous entry.

  `panel_data` maps panel id to that panel's result: `{:ok, series}`,
  `{:table, columns, rows}`, or an `{:error, reason}`. Only `{:ok, series}`
  entries are downsampled and clustered; everything else is stored as given.

  Asynchronous — returns before the data is stored.
  """
  @spec put(String.t(), map()) :: :ok
  def put(dashboard_uid, panel_data) do
    GenServer.cast(__MODULE__, {:put, dashboard_uid, panel_data})
  end

  @doc """
  Returns the stored entry for `dashboard_uid`.

  The entry is `%{panel_data: map, version: integer}`, or `nil` when nothing
  has been stored for that dashboard yet.
  """
  @spec get(String.t()) :: %{panel_data: map(), version: integer()} | nil
  def get(dashboard_uid) do
    GenServer.call(__MODULE__, {:get, dashboard_uid})
  end

  @doc """
  Returns the stored entry for `dashboard_uid` only if it is newer than
  `last_version`.

  `last_version` is the `:version` of the entry the caller already has, or
  `nil` on the first poll.

  Returns `{:updated, %{panel_data: map, version: integer}}` when the stored
  version differs, and `:unchanged` when it matches or when nothing has been
  stored for that dashboard. Callers must keep the returned version and pass
  it back on the next poll.
  """
  @spec take_if_updated(String.t(), integer() | nil) ::
          {:updated, %{panel_data: map(), version: integer()}} | :unchanged
  def take_if_updated(dashboard_uid, last_version) do
    GenServer.call(__MODULE__, {:take_if_updated, dashboard_uid, last_version})
  end

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @max_points_per_series 200

  @impl GenServer
  def handle_cast({:put, uid, panel_data}, state) do
    version = System.monotonic_time()

    downsampled =
      Map.new(panel_data, fn {panel_id, data} -> {panel_id, downsample_panel(data)} end)

    entry = %{panel_data: downsampled, version: version}
    {:noreply, Map.put(state, uid, entry)}
  end

  alias GrafExTerm.Refresh.SeriesClusterer

  defp downsample_panel({:ok, series}) do
    downsampled = Enum.map(series, fn s -> %{s | values: downsample_values(s.values)} end)
    clustered = SeriesClusterer.cluster(downsampled)
    {:ok, clustered}
  end

  defp downsample_panel(other), do: other

  defp downsample_values(values) when length(values) <= @max_points_per_series, do: values

  defp downsample_values(values) do
    n = length(values)
    bucket_count = max(1, div(@max_points_per_series, 2))
    bucket_size = n / bucket_count

    for i <- 0..(bucket_count - 1) do
      start_idx = round(i * bucket_size)
      end_idx = round((i + 1) * bucket_size)
      bucket = Enum.slice(values, start_idx, max(1, end_idx - start_idx))
      {min_pt, max_pt} = Enum.min_max_by(bucket, fn {_ts, v} -> v end)
      if elem(min_pt, 0) <= elem(max_pt, 0), do: [min_pt, max_pt], else: [max_pt, min_pt]
    end
    |> List.flatten()
  end

  @impl GenServer
  def handle_call({:get, uid}, _from, state) do
    result = Map.get(state, uid)
    {:reply, result, state}
  end

  def handle_call({:take_if_updated, uid, last_version}, _from, state) do
    case Map.get(state, uid) do
      nil -> {:reply, :unchanged, state}
      %{version: v} when v == last_version -> {:reply, :unchanged, state}
      entry -> {:reply, {:updated, entry}, state}
    end
  end
end
