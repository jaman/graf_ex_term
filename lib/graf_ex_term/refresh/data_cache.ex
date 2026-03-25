defmodule GrafExTerm.Refresh.DataCache do
  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def put(dashboard_uid, panel_data) do
    GenServer.cast(__MODULE__, {:put, dashboard_uid, panel_data})
  end

  def get(dashboard_uid) do
    GenServer.call(__MODULE__, {:get, dashboard_uid})
  end

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
    downsampled = Map.new(panel_data, fn {panel_id, data} -> {panel_id, downsample_panel(data)} end)
    entry = %{panel_data: downsampled, version: version}
    {:noreply, Map.put(state, uid, entry)}
  end

  defp downsample_panel({:ok, series}) do
    {:ok, Enum.map(series, fn s -> %{s | values: downsample_values(s.values)} end)}
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
