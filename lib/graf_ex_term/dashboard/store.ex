defmodule GrafExTerm.Dashboard.Store do
  @moduledoc false
  use GenServer

  alias GrafExTerm.Dashboard.{Loader, Parser}

  @cache :graf_ex_term_dashboards

  @serializers %{
    column_visibility: {&__MODULE__.serialize_column_visibility/1, &__MODULE__.deserialize_column_visibility/1},
    table_layouts: {&__MODULE__.serialize_table_layouts/1, &__MODULE__.deserialize_table_layouts/1},
    collapsed_rows: {&__MODULE__.serialize_id_set/1, &__MODULE__.deserialize_id_set/1},
    collapsed_table_panels: {&__MODULE__.serialize_id_set/1, &__MODULE__.deserialize_id_set/1}
  }

  @defaults %{
    datasource_map: %{},
    column_visibility: %{},
    table_layouts: %{},
    collapsed_rows: MapSet.new(),
    collapsed_table_panels: MapSet.new(),
    column_filter: false
  }

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def list, do: GenServer.call(__MODULE__, :list)
  def add(uri), do: GenServer.call(__MODULE__, {:add, uri}, 30_000)
  def remove(uid), do: GenServer.call(__MODULE__, {:remove, uid})

  @spec save_setting(String.t(), atom(), term()) :: :ok
  def save_setting(uid, key, value), do: GenServer.cast(__MODULE__, {:save_setting, uid, key, value})

  @spec get_setting(String.t(), atom()) :: term()
  def get_setting(uid, key), do: GenServer.call(__MODULE__, {:get_setting, uid, key})

  def save_datasource_map(uid, value), do: GenServer.call(__MODULE__, {:save_datasource_map, uid, value})
  def get_datasource_map(uid), do: get_setting(uid, :datasource_map)

  def save_column_visibility(uid, value), do: save_setting(uid, :column_visibility, value)
  def get_column_visibility(uid), do: get_setting(uid, :column_visibility)

  def save_table_layout(uid, panel_id, layout) do
    GenServer.cast(__MODULE__, {:save_table_layout, uid, panel_id, layout})
  end

  def get_table_layouts(uid), do: get_setting(uid, :table_layouts)
  def save_collapsed_rows(uid, value), do: save_setting(uid, :collapsed_rows, value)
  def get_collapsed_rows(uid), do: get_setting(uid, :collapsed_rows)
  def save_collapsed_table_panels(uid, value), do: save_setting(uid, :collapsed_table_panels, value)
  def get_collapsed_table_panels(uid), do: get_setting(uid, :collapsed_table_panels)
  def save_column_filter(uid, value), do: save_setting(uid, :column_filter, value)
  def get_column_filter(uid), do: get_setting(uid, :column_filter)

  def get_dashboard(uid) do
    case Cachex.get(@cache, uid) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, dashboard} -> {:ok, dashboard}
      _ -> {:error, :not_found}
    end
  end

  def init(_) do
    entries = load_persisted()
    Enum.each(entries, fn entry -> Cachex.put(@cache, entry.uid, entry.dashboard) end)
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
    new_entries = update_entry(state.entries, uid, :datasource_map, datasource_map)
    persist(new_entries)
    {:reply, :ok, %{state | entries: new_entries}}
  end

  def handle_call({:get_setting, uid, key}, _from, state) do
    default = Map.get(@defaults, key)

    raw =
      case Enum.find(state.entries, fn e -> e.uid == uid end) do
        nil -> default
        entry -> Map.get(entry, key, default)
      end

    {:reply, deserialize(key, raw), state}
  end

  def handle_cast({:save_setting, uid, key, value}, state) do
    serialized = serialize(key, value)
    new_entries = update_entry(state.entries, uid, key, serialized)
    persist(new_entries)
    {:noreply, %{state | entries: new_entries}}
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

    json_defaults = %{
      column_visibility: %{},
      table_layouts: %{},
      collapsed_rows: [],
      collapsed_table_panels: [],
      column_filter: false
    }

    settings =
      Enum.reduce(json_defaults, %{}, fn {key, json_default}, acc ->
        json_key = to_string(key)
        Map.put(acc, key, Map.get(entry, json_key, json_default))
      end)

    with {:ok, raw} <- Loader.load(uri),
         {:ok, dashboard} <- Parser.parse(raw) do
      [Map.merge(settings, %{uid: dashboard.uid, uri: uri, dashboard: dashboard, datasource_map: datasource_map})]
    else
      _ -> []
    end
  end

  @persisted_keys [:datasource_map, :column_visibility, :table_layouts, :collapsed_rows, :collapsed_table_panels, :column_filter]

  defp persist(entries) do
    data = Enum.map(entries, fn e ->
      Enum.reduce(@persisted_keys, %{uid: e.uid, uri: e.uri}, fn key, acc ->
        Map.put(acc, key, Map.get(e, key, Map.get(@defaults, key)))
      end)
    end)
    File.write!(store_path(), Jason.encode!(data))
  end

  defp serialize(key, value) do
    case Map.get(@serializers, key) do
      {serializer, _} -> serializer.(value)
      nil -> value
    end
  end

  defp deserialize(key, value) do
    case Map.get(@serializers, key) do
      {_, deserializer} -> deserializer.(value)
      nil -> value
    end
  end

  def serialize_column_visibility(column_visibility) when is_map(column_visibility) do
    Map.new(column_visibility, fn {panel_id, keys} ->
      list = case keys do
        %MapSet{} -> MapSet.to_list(keys)
        list when is_list(list) -> list
        _ -> []
      end
      {to_string(panel_id), Enum.map(list, &to_string/1)}
    end)
  end

  def serialize_column_visibility(val), do: val

  def deserialize_column_visibility(raw) when is_map(raw) do
    Map.new(raw, fn {panel_id_str, keys} ->
      panel_id = parse_panel_id(panel_id_str)
      {panel_id, MapSet.new(keys, fn k -> if is_atom(k), do: k, else: String.to_atom(k) end)}
    end)
  end

  def deserialize_column_visibility(_), do: %{}

  def serialize_table_layouts(table_layouts) when is_map(table_layouts) do
    Map.new(table_layouts, fn {panel_id, layout} ->
      {to_string(panel_id), %{col_widths: layout.col_widths, col_order: layout.col_order}}
    end)
  end

  def serialize_table_layouts(val), do: val

  def deserialize_table_layouts(raw) when is_map(raw) do
    Map.new(raw, fn {panel_id_str, layout} ->
      panel_id = parse_panel_id(panel_id_str)
      {panel_id, %{col_widths: layout["col_widths"], col_order: layout["col_order"]}}
    end)
  end

  def deserialize_table_layouts(_), do: %{}

  def serialize_id_set(%MapSet{} = set), do: MapSet.to_list(set) |> Enum.map(&to_string/1)
  def serialize_id_set(list) when is_list(list), do: Enum.map(list, &to_string/1)
  def serialize_id_set(_), do: []

  def deserialize_id_set(list) when is_list(list) do
    MapSet.new(list, fn id ->
      case Integer.parse(to_string(id)) do
        {n, ""} -> n
        _ -> id
      end
    end)
  end

  def deserialize_id_set(_), do: MapSet.new()

  defp parse_panel_id(id) when is_integer(id), do: id

  defp parse_panel_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> id
    end
  end

  defp parse_panel_id(id), do: id

  defp update_entry(entries, uid, key, value) do
    Enum.map(entries, fn e ->
      if e.uid == uid, do: Map.put(e, key, value), else: e
    end)
  end
end
