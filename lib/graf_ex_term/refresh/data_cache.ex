defmodule GrafExTerm.Refresh.DataCache do
  @moduledoc """
  Singleton process holding the most recent query results for every dashboard.

  `GrafExTerm.Refresh.Scheduler` writes here after each fetch and screens poll
  with `take_if_updated/2`, which lets a screen skip re-rendering when nothing
  has changed. Only the latest result per dashboard is kept; there is no
  history.

  Stored data is not the raw query result: each panel's series set is passed
  through `GrafExTerm.Refresh.SeriesClusterer`, so consumers may see fewer
  series than the datasource returned, and series may carry a `:weight`.
  Sample counts are already sized to the panel by the scheduler's query step.

  Versions are `System.monotonic_time/0` values, meaningful only for equality
  against a previously observed version.
  """

  use GenServer

  alias GrafExTerm.Refresh.SeriesClusterer

  @type entry :: %{panel_data: map(), windows: map(), version: integer()}

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Stores the results for `dashboard_uid`, replacing any previous entry.

  `panel_data` maps panel id to that panel's result: `{:ok, series}`,
  `{:table, columns, rows}`, or an `{:error, reason}`. Only `{:ok, series}`
  entries are clustered; everything else is stored as given. `windows` maps
  panel id to the `GrafExTerm.Refresh.QueryWindow` that panel's series were
  fetched over.

  Asynchronous — returns before the data is stored.
  """
  @spec put(String.t(), map(), map()) :: :ok
  def put(dashboard_uid, panel_data, windows \\ %{}) do
    GenServer.cast(__MODULE__, {:put, dashboard_uid, panel_data, windows})
  end

  @doc """
  Returns the stored entry for `dashboard_uid`.

  The entry is `%{panel_data: map, windows: map, version: integer}`, or `nil`
  when nothing has been stored for that dashboard yet.
  """
  @spec get(String.t()) :: entry() | nil
  def get(dashboard_uid) do
    GenServer.call(__MODULE__, {:get, dashboard_uid})
  end

  @doc """
  Returns the stored entry for `dashboard_uid` only if it is newer than
  `last_version`.

  `last_version` is the `:version` of the entry the caller already has, or
  `nil` on the first poll.

  Returns `{:updated, entry}` when the stored
  version differs, and `:unchanged` when it matches or when nothing has been
  stored for that dashboard. Callers must keep the returned version and pass
  it back on the next poll.
  """
  @spec take_if_updated(String.t(), integer() | nil) :: {:updated, entry()} | :unchanged
  def take_if_updated(dashboard_uid, last_version) do
    GenServer.call(__MODULE__, {:take_if_updated, dashboard_uid, last_version})
  end

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:put, uid, panel_data, windows}, state) do
    clustered = Map.new(panel_data, fn {panel_id, data} -> {panel_id, cluster_panel(data)} end)
    entry = %{panel_data: clustered, windows: windows, version: System.monotonic_time()}
    {:noreply, Map.put(state, uid, entry)}
  end

  defp cluster_panel({:ok, series}), do: {:ok, SeriesClusterer.cluster(series)}
  defp cluster_panel(other), do: other

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
