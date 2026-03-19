defmodule GrafExTerm.Dashboard.Registry do
  use GenServer

  alias GrafExTerm.Dashboard.{Loader, Parser}

  defstruct dashboards: %{}, uris: []

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register(uri) do
    GenServer.call(__MODULE__, {:register, uri})
  end

  def list do
    GenServer.call(__MODULE__, :list)
  end

  def get(uid) do
    GenServer.call(__MODULE__, {:get, uid})
  end

  @impl GenServer
  def init(_opts) do
    uris = Application.get_env(:graf_ex_term, :dashboards, [])
    state = Enum.reduce(uris, %__MODULE__{}, &load_and_register/2)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register, uri}, _from, state) do
    new_state = load_and_register(uri, state)
    {:reply, :ok, new_state}
  end

  def handle_call(:list, _from, state) do
    dashboards = Enum.map(state.uris, fn uri ->
      state.dashboards[uri]
    end) |> Enum.reject(&is_nil/1)

    {:reply, dashboards, state}
  end

  def handle_call({:get, uid}, _from, state) do
    result =
      state.dashboards
      |> Map.values()
      |> Enum.find(fn d -> d.uid == uid end)

    {:reply, result, state}
  end

  defp load_and_register(uri, state) do
    with {:ok, raw} <- Loader.load(uri),
         {:ok, dashboard} <- Parser.parse(raw) do
      %{state |
        dashboards: Map.put(state.dashboards, uri, dashboard),
        uris: state.uris ++ [uri]
      }
    else
      _ -> state
    end
  end
end
