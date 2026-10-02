defmodule GrafExTerm.Dashboard.Store do
  @moduledoc """
  Singleton process owning the set of registered dashboards and each one's
  user settings, persisted to disk.

  Registering a dashboard fetches and parses it, caches the parsed
  `GrafExTerm.Dashboard.Types.Dashboard` in Cachex under its uid, and appends
  an entry to `$XDG_CONFIG_HOME/graf_ex_term/dashboards.json`
  (`~/.config/graf_ex_term/dashboards.json` when that variable is unset). The
  file records the source URI and settings, not the dashboard itself, so every
  dashboard is re-fetched and re-parsed at startup and a source that has
  become unreachable is silently dropped from the list.

  Settings are per dashboard uid: `:datasource_map`, `:source`,
  `:column_visibility`, `:table_layouts`, `:collapsed_rows`,
  `:collapsed_table_panels` and `:column_filter`. `MapSet` and atom-keyed
  values are converted to JSON-safe forms on write and back on read, so
  callers always see the in-memory shape.

  Every write rewrites the whole file. Writes for an unregistered uid are
  accepted and discarded.

      {:ok, %{uid: uid}} = GrafExTerm.Dashboard.Store.add("file:///tmp/node.json")
      {:ok, dashboard} = GrafExTerm.Dashboard.Store.get_dashboard(uid)
  """

  use GenServer

  alias GrafExTerm.Dashboard.{Loader, Parser}

  @cache :graf_ex_term_dashboards

  @serializers %{
    column_visibility:
      {&__MODULE__.serialize_column_visibility/1, &__MODULE__.deserialize_column_visibility/1},
    table_layouts:
      {&__MODULE__.serialize_table_layouts/1, &__MODULE__.deserialize_table_layouts/1},
    collapsed_rows: {&__MODULE__.serialize_id_set/1, &__MODULE__.deserialize_id_set/1},
    collapsed_table_panels: {&__MODULE__.serialize_id_set/1, &__MODULE__.deserialize_id_set/1}
  }

  @defaults %{
    datasource_map: %{},
    source: nil,
    column_visibility: %{},
    table_layouts: %{},
    collapsed_rows: MapSet.new(),
    collapsed_table_panels: MapSet.new(),
    column_filter: false
  }

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc """
  Lists the registered dashboards as `%{uid: uid, title: title, uri: uri}`
  summaries, in registration order.
  """
  @spec list() :: [%{uid: String.t(), title: String.t(), uri: String.t()}]
  def list, do: GenServer.call(__MODULE__, :list)

  @doc """
  Registers the dashboard at `uri`, replacing any existing entry with the same
  uid.

  `uri` is a `file://` or `http(s)://` URI as accepted by
  `GrafExTerm.Dashboard.Loader.load/1`. The dashboard is fetched and parsed
  synchronously, so this blocks on network I/O; the call allows 30 seconds.

  Returns `{:ok, %{uid: uid, title: title, datasource_vars: names}}`, where
  `datasource_vars` lists the template variables the dashboard uses to select
  a datasource and for which the caller should collect URLs. Returns the
  loader's or parser's `{:error, reason}` unchanged on failure, leaving the
  store untouched.
  """
  @spec add(String.t()) ::
          {:ok, %{uid: String.t(), title: String.t(), datasource_vars: [String.t()]}}
          | {:error, term()}
  def add(uri), do: GenServer.call(__MODULE__, {:add, uri}, 30_000)

  @doc """
  Removes the dashboard `uid` and its settings.

  Always returns `:ok`, including for a uid that was never registered.
  """
  @spec remove(String.t()) :: :ok
  def remove(uid), do: GenServer.call(__MODULE__, {:remove, uid})

  @doc """
  Stores `value` under `key` for dashboard `uid` and rewrites the settings
  file.

  `key` must be one of `:datasource_map`, `:source`, `:column_visibility`,
  `:table_layouts`, `:collapsed_rows`, `:collapsed_table_panels` or
  `:column_filter`; other keys are stored but never persisted or read back.

  Asynchronous — returns before the value is stored, so a `get_setting/2`
  issued from another process may still see the old value.
  """
  @spec save_setting(String.t(), atom(), term()) :: :ok
  def save_setting(uid, key, value),
    do: GenServer.cast(__MODULE__, {:save_setting, uid, key, value})

  @doc """
  Reads the setting `key` for dashboard `uid`.

  Returns the stored value, deserialised to its in-memory shape. An unknown
  uid or an unset key yields that key's default: `%{}` for `:datasource_map`,
  `:column_visibility` and `:table_layouts`, an empty `MapSet` for
  `:collapsed_rows` and `:collapsed_table_panels`, `nil` for `:source`, and
  `false` for `:column_filter`. A key outside that set yields `nil`.
  """
  @spec get_setting(String.t(), atom()) :: term()
  def get_setting(uid, key), do: GenServer.call(__MODULE__, {:get_setting, uid, key})

  @doc """
  Stores the datasource variable to URL map for dashboard `uid`.

  `value` maps a template variable name, as returned in `add/1`'s
  `:datasource_vars`, to the base URL to query for targets referencing it.
  Unlike the other setters this is synchronous and returns once persisted.
  """
  @spec save_datasource_map(String.t(), %{String.t() => String.t()}) :: :ok
  def save_datasource_map(uid, value),
    do: GenServer.call(__MODULE__, {:save_datasource_map, uid, value})

  @doc """
  Returns the datasource variable to URL map for dashboard `uid`, or `%{}`.
  """
  @spec get_datasource_map(String.t()) :: %{String.t() => String.t()}
  def get_datasource_map(uid), do: get_setting(uid, :datasource_map)

  @doc """
  Stores which table columns are visible for dashboard `uid`.

  `value` maps panel id to a `MapSet` of column keys. Asynchronous.
  """
  @spec save_column_visibility(String.t(), map()) :: :ok
  def save_column_visibility(uid, value), do: save_setting(uid, :column_visibility, value)

  @doc """
  Returns the panel id to visible column `MapSet` map for dashboard `uid`, or
  `%{}`.
  """
  @spec get_column_visibility(String.t()) :: map()
  def get_column_visibility(uid), do: get_setting(uid, :column_visibility)

  @doc """
  Stores one table panel's column layout for dashboard `uid`.

  `panel_id` is the panel's id and `layout` is `%{col_widths: widths,
  col_order: order}`. Merges into the dashboard's existing layouts rather than
  replacing them. Asynchronous.
  """
  @spec save_table_layout(String.t(), term(), map()) :: :ok
  def save_table_layout(uid, panel_id, layout) do
    GenServer.cast(__MODULE__, {:save_table_layout, uid, panel_id, layout})
  end

  @doc """
  Returns the panel id to layout map for dashboard `uid`, or `%{}`.
  """
  @spec get_table_layouts(String.t()) :: map()
  def get_table_layouts(uid), do: get_setting(uid, :table_layouts)

  @doc """
  Stores the `MapSet` of collapsed row panel ids for dashboard `uid`.
  Asynchronous.
  """
  @spec save_collapsed_rows(String.t(), MapSet.t()) :: :ok
  def save_collapsed_rows(uid, value), do: save_setting(uid, :collapsed_rows, value)

  @doc """
  Returns the `MapSet` of collapsed row panel ids for dashboard `uid`, or an
  empty set.
  """
  @spec get_collapsed_rows(String.t()) :: MapSet.t()
  def get_collapsed_rows(uid), do: get_setting(uid, :collapsed_rows)

  @doc """
  Stores the `MapSet` of collapsed table panel ids for dashboard `uid`.
  Asynchronous.
  """
  @spec save_collapsed_table_panels(String.t(), MapSet.t()) :: :ok
  def save_collapsed_table_panels(uid, value),
    do: save_setting(uid, :collapsed_table_panels, value)

  @doc """
  Returns the `MapSet` of collapsed table panel ids for dashboard `uid`, or an
  empty set.
  """
  @spec get_collapsed_table_panels(String.t()) :: MapSet.t()
  def get_collapsed_table_panels(uid), do: get_setting(uid, :collapsed_table_panels)

  @doc """
  Stores whether the per-column checkbox selector is shown for dashboard
  `uid`. Asynchronous.
  """
  @spec save_column_filter(String.t(), boolean()) :: :ok
  def save_column_filter(uid, value), do: save_setting(uid, :column_filter, value)

  @doc """
  Returns whether the per-column selector is shown for dashboard `uid`;
  `false` when unset.
  """
  @spec get_column_filter(String.t()) :: boolean()
  def get_column_filter(uid), do: get_setting(uid, :column_filter)

  @doc """
  Stores a Prometheus base URL that overrides the global default for
  dashboard `uid`.

  `value` is a base URL, or `""`/`nil` to fall back to the application's
  `:datasources` configuration. Asynchronous.
  """
  @spec save_source(String.t(), String.t() | nil) :: :ok
  def save_source(uid, value), do: save_setting(uid, :source, value)

  @doc """
  Returns the Prometheus URL override for dashboard `uid`, or `nil`.
  """
  @spec get_source(String.t()) :: String.t() | nil
  def get_source(uid), do: get_setting(uid, :source)

  @doc """
  Returns the parsed dashboard `uid` from the cache.

  Returns `{:ok, dashboard}` or `{:error, :not_found}`. Reads Cachex directly
  rather than the store process, so it does not queue behind a pending
  `add/1`.
  """
  @spec get_dashboard(String.t()) ::
          {:ok, GrafExTerm.Dashboard.Types.Dashboard.t()} | {:error, :not_found}
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
    summaries =
      Enum.map(state.entries, fn e ->
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

      {:reply,
       {:ok, %{uid: dashboard.uid, title: dashboard.title, datasource_vars: datasource_vars}},
       %{state | entries: new_entries}}
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
      source: nil,
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
      [
        Map.merge(settings, %{
          uid: dashboard.uid,
          uri: uri,
          dashboard: dashboard,
          datasource_map: datasource_map
        })
      ]
    else
      _ -> []
    end
  end

  @persisted_keys [
    :datasource_map,
    :source,
    :column_visibility,
    :table_layouts,
    :collapsed_rows,
    :collapsed_table_panels,
    :column_filter
  ]

  defp persist(entries) do
    data =
      Enum.map(entries, fn e ->
        Enum.reduce(@persisted_keys, %{uid: e.uid, uri: e.uri}, fn key, acc ->
          value = Map.get(e, key, Map.get(@defaults, key))
          Map.put(acc, key, serialize(key, value))
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

  @doc false
  def serialize_column_visibility(column_visibility) when is_map(column_visibility) do
    Map.new(column_visibility, fn {panel_id, keys} ->
      list =
        case keys do
          %MapSet{} -> MapSet.to_list(keys)
          list when is_list(list) -> list
          _ -> []
        end

      {to_string(panel_id), Enum.map(list, &to_string/1)}
    end)
  end

  def serialize_column_visibility(val), do: val

  @doc false
  def deserialize_column_visibility(raw) when is_map(raw) do
    Map.new(raw, fn {panel_id_str, keys} ->
      panel_id = parse_panel_id(panel_id_str)
      {panel_id, MapSet.new(keys, fn k -> if is_atom(k), do: k, else: String.to_atom(k) end)}
    end)
  end

  def deserialize_column_visibility(_), do: %{}

  @doc false
  def serialize_table_layouts(table_layouts) when is_map(table_layouts) do
    Map.new(table_layouts, fn {panel_id, layout} ->
      col_widths = layout[:col_widths] || layout["col_widths"]
      col_order = layout[:col_order] || layout["col_order"]
      {to_string(panel_id), %{col_widths: col_widths, col_order: col_order}}
    end)
  end

  def serialize_table_layouts(val), do: val

  @doc false
  def deserialize_table_layouts(raw) when is_map(raw) do
    Map.new(raw, fn {panel_id_str, layout} ->
      panel_id = parse_panel_id(panel_id_str)
      {panel_id, %{col_widths: layout["col_widths"], col_order: layout["col_order"]}}
    end)
  end

  def deserialize_table_layouts(_), do: %{}

  @doc false
  def serialize_id_set(%MapSet{} = set), do: MapSet.to_list(set) |> Enum.map(&to_string/1)
  def serialize_id_set(list) when is_list(list), do: Enum.map(list, &to_string/1)
  def serialize_id_set(_), do: []

  @doc false
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
