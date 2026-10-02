defmodule GrafExTerm.Dashboard.Registry do
  @moduledoc """
  In-memory, non-persistent registry of parsed dashboards, seeded from
  configuration.

  Loads every URI in the `:dashboards` application environment list at start
  and keeps the parsed results in process state, keyed by URI. Unlike
  `GrafExTerm.Dashboard.Store` it writes nothing to disk and does not survive
  a restart.

  It is not part of the application's supervision tree, so a caller must start
  it explicitly before using it.

  Loading is silent about failure: a URI that cannot be fetched or parsed is
  skipped and simply does not appear in `list/0`.
  """

  use GenServer

  alias GrafExTerm.Dashboard.{Loader, Parser}

  defstruct dashboards: %{}, uris: []

  @doc """
  Starts the registry and loads the dashboards named in the `:dashboards`
  application environment.

  `opts` is ignored. Registered under the module name, so only one may run per
  node. Loading is synchronous, so this blocks on network I/O for HTTP URIs.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Loads and registers the dashboard at `uri`.

  `uri` is a `file://` or `http(s)://` URI as accepted by
  `GrafExTerm.Dashboard.Loader.load/1`. Registering a URI already present
  re-fetches it and appends the URI to the ordering a second time.

  Returns `:ok` whether or not the load succeeded; check `list/0` to confirm.
  """
  @spec register(String.t()) :: :ok
  def register(uri) do
    GenServer.call(__MODULE__, {:register, uri})
  end

  @doc """
  Returns the successfully loaded dashboards, in URI registration order.
  """
  @spec list() :: [GrafExTerm.Dashboard.Types.Dashboard.t()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Returns the dashboard whose `:uid` is `uid`, or `nil`.

  Uids are not enforced to be unique across URIs; when two loaded dashboards
  share one, which is returned is unspecified.
  """
  @spec get(String.t()) :: GrafExTerm.Dashboard.Types.Dashboard.t() | nil
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
    dashboards =
      Enum.map(state.uris, fn uri ->
        state.dashboards[uri]
      end)
      |> Enum.reject(&is_nil/1)

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
      %{state | dashboards: Map.put(state.dashboards, uri, dashboard), uris: state.uris ++ [uri]}
    else
      _ -> state
    end
  end
end
