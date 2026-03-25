defmodule GrafExTerm.Dashboard.Store do
  @moduledoc false
  use GenServer

  alias GrafExTerm.Dashboard.{Loader, Parser}

  @cache :graf_ex_term_dashboards

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list do
    GenServer.call(__MODULE__, :list)
  end

  def add(uri) do
    GenServer.call(__MODULE__, {:add, uri}, 30_000)
  end

  def remove(uid) do
    GenServer.call(__MODULE__, {:remove, uid})
  end

  def save_datasource_map(uid, datasource_map) do
    GenServer.call(__MODULE__, {:save_datasource_map, uid, datasource_map})
  end

  def get_datasource_map(uid) do
    GenServer.call(__MODULE__, {:get_datasource_map, uid})
  end

  def save_column_visibility(uid, column_visibility) do
    GenServer.call(__MODULE__, {:save_column_visibility, uid, column_visibility})
  end

  def get_column_visibility(uid) do
    GenServer.call(__MODULE__, {:get_column_visibility, uid})
  end

  def save_table_layout(uid, panel_id, layout) do
    GenServer.cast(__MODULE__, {:save_table_layout, uid, panel_id, layout})
  end

  def get_table_layouts(uid) do
    GenServer.call(__MODULE__, {:get_table_layouts, uid})
  end

  def get_dashboard(uid) do
    case Cachex.get(@cache, uid) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, dashboard} -> {:ok, dashboard}
      _ -> {:error, :not_found}
    end
  end

  def init(_) do
    entries = load_persisted()
    Enum.each(entries, fn entry ->
      Cachex.put(@cache, entry.uid, entry.dashboard)
    end)
    {:ok, %{entries: entries}}
  end

  def handle_call(:list, _from, state) do
    summaries = Enum.map(state.entries, fn e ->
      %{uid: e.uid, title: e.dashboard.title, uri: e.uri}
    end)
    {:reply, summaries, state}
  end

  def handle_call({:add, uri}, _from, state) do
    with {:ok, raw} <- Loader.load(uri),
         {:ok, dashboard} <- Parser.parse(raw) do
      entry = %{uid: dashboard.uid, uri: uri, dashboard: dashboard, datasource_map: %{}}
      new_entries = Enum.reject(state.entries, fn e -> e.uid == dashboard.uid end) ++ [entry]
      Cachex.put(@cache, dashboard.uid, dashboard)
      persist(new_entries)
      datasource_vars = Parser.datasource_vars(dashboard)
      {:reply, {:ok, %{uid: dashboard.uid, title: dashboard.title, datasource_vars: datasource_vars}}, %{state | entries: new_entries}}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:remove, uid}, _from, state) do
    new_entries = Enum.reject(state.entries, fn e -> e.uid == uid end)
    Cachex.del(@cache, uid)
    persist(new_entries)
    {:reply, :ok, %{state | entries: new_entries}}
  end

  def handle_call({:save_datasource_map, uid, datasource_map}, _from, state) do
    new_entries =
      Enum.map(state.entries, fn e ->
        if e.uid == uid, do: Map.put(e, :datasource_map, datasource_map), else: e
      end)
    persist(new_entries)
    {:reply, :ok, %{state | entries: new_entries}}
  end

  def handle_call({:get_datasource_map, uid}, _from, state) do
    case Enum.find(state.entries, fn e -> e.uid == uid end) do
      nil -> {:reply, %{}, state}
      entry -> {:reply, Map.get(entry, :datasource_map, %{}), state}
    end
  end

  def handle_call({:save_column_visibility, uid, column_visibility}, _from, state) do
    serializable = serialize_column_visibility(column_visibility)
    new_entries =
      Enum.map(state.entries, fn e ->
        if e.uid == uid, do: Map.put(e, :column_visibility, serializable), else: e
      end)
    persist(new_entries)
    {:reply, :ok, %{state | entries: new_entries}}
  end

  def handle_call({:get_column_visibility, uid}, _from, state) do
    case Enum.find(state.entries, fn e -> e.uid == uid end) do
      nil -> {:reply, %{}, state}
      entry -> {:reply, deserialize_column_visibility(Map.get(entry, :column_visibility, %{})), state}
    end
  end

  def handle_call({:get_table_layouts, uid}, _from, state) do
    case Enum.find(state.entries, fn e -> e.uid == uid end) do
      nil -> {:reply, %{}, state}
      entry -> {:reply, Map.get(entry, :table_layouts, %{}), state}
    end
  end

  def handle_cast({:save_table_layout, uid, panel_id, layout}, state) do
    new_entries =
      Enum.map(state.entries, fn e ->
        if e.uid == uid do
          existing = Map.get(e, :table_layouts, %{})
          Map.put(e, :table_layouts, Map.put(existing, panel_id, layout))
        else
          e
        end
      end)
    persist(new_entries)
    {:noreply, %{state | entries: new_entries}}
  end

  defp store_path do
    base = System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
    dir = Path.join(base, "graf_ex_term")
    File.mkdir_p!(dir)
    Path.join(dir, "dashboards.json")
  end

  defp load_persisted do
    path = store_path()

    with true <- File.exists?(path),
         {:ok, contents} <- File.read(path),
         {:ok, raw_list} <- Jason.decode(contents) do
      Enum.flat_map(raw_list, &load_persisted_entry/1)
    else
      _ -> []
    end
  end

  defp load_persisted_entry(%{"uri" => uri} = entry) do
    datasource_map =
      entry
      |> Map.get("datasource_map", %{})
      |> Enum.into(%{}, fn {k, v} -> {k, v} end)

    column_visibility = deserialize_column_visibility(Map.get(entry, "column_visibility", %{}))
    table_layouts = deserialize_table_layouts(Map.get(entry, "table_layouts", %{}))

    with {:ok, raw} <- Loader.load(uri),
         {:ok, dashboard} <- Parser.parse(raw) do
      [%{uid: dashboard.uid, uri: uri, dashboard: dashboard, datasource_map: datasource_map, column_visibility: column_visibility, table_layouts: table_layouts}]
    else
      _ -> []
    end
  end

  defp persist(entries) do
    data = Enum.map(entries, fn e ->
      %{
        uid: e.uid,
        uri: e.uri,
        datasource_map: Map.get(e, :datasource_map, %{}),
        column_visibility: serialize_column_visibility(Map.get(e, :column_visibility, %{})),
        table_layouts: serialize_table_layouts(Map.get(e, :table_layouts, %{}))
      }
    end)
    File.write!(store_path(), Jason.encode!(data))
  end

  defp serialize_column_visibility(column_visibility) do
    Map.new(column_visibility, fn {panel_id, keys} ->
      list = case keys do
        %MapSet{} -> MapSet.to_list(keys)
        list when is_list(list) -> list
        _ -> []
      end
      {to_string(panel_id), Enum.map(list, &to_string/1)}
    end)
  end

  defp deserialize_column_visibility(raw) when is_map(raw) do
    Map.new(raw, fn {panel_id_str, keys} ->
      panel_id = parse_panel_id(panel_id_str)
      {panel_id, MapSet.new(keys, fn k -> if is_atom(k), do: k, else: String.to_atom(k) end)}
    end)
  end

  defp deserialize_column_visibility(_), do: %{}

  defp parse_panel_id(id) when is_integer(id), do: id

  defp parse_panel_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> id
    end
  end

  defp parse_panel_id(id), do: id

  defp serialize_table_layouts(table_layouts) do
    Map.new(table_layouts, fn {panel_id, layout} ->
      {to_string(panel_id), %{col_widths: layout.col_widths, col_order: layout.col_order}}
    end)
  end

  defp deserialize_table_layouts(raw) when is_map(raw) do
    Map.new(raw, fn {panel_id_str, layout} ->
      panel_id = parse_panel_id(panel_id_str)
      {panel_id, %{col_widths: layout["col_widths"], col_order: layout["col_order"]}}
    end)
  end

  defp deserialize_table_layouts(_), do: %{}
end
