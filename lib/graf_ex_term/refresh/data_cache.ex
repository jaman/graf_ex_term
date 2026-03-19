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

  @impl GenServer
  def handle_cast({:put, uid, panel_data}, state) do
    version = System.monotonic_time()
    entry = %{panel_data: panel_data, version: version}
    {:noreply, Map.put(state, uid, entry)}
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
