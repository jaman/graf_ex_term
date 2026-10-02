defmodule GrafExTerm.Refresh.Scheduler do
  @moduledoc """
  Per-dashboard process that queries every visible panel on a timer and
  publishes the results.

  One is started under `GrafExTerm.RefreshSupervisor` for each dashboard the
  user opens and registered in `GrafExTerm.RefreshRegistry` under the
  dashboard uid, so callers address it by uid. It fetches once immediately on
  start and then on its interval.

  Each fetch writes to `GrafExTerm.Refresh.DataCache` and broadcasts
  `{:data_refreshed, uid, panel_data}` on the `"dashboard:<uid>"` PubSub
  topic. `panel_data` maps panel id to `{:ok, series}`, `{:table, columns,
  rows}` or `{:error, :no_data}`.

  Only panels that are actually visible are queried. Row panels are never
  queried, and panels under a collapsed row are skipped, so a caller must keep
  the scheduler's idea of collapsed rows current with `set_collapsed_rows/2`
  or it will keep querying panels the user cannot see. The set starts empty,
  meaning everything is queried, even if the screen opens with rows collapsed.

  Query window and step come from the application environment:
  `:time_range_seconds` (default 3600) back from now, divided into
  `:chart_resolution` (default 300) samples, with a step of at least one
  second. The Grafana built-ins `__rate_interval`, `__interval`,
  `__interval_ms`, `__range`, `__range_s`, `__range_ms`, `__from` and `__to`
  are derived from that window and merged under the user's variable values, so
  a dashboard variable of the same name wins.

  A target is fetched as an instant table when it is marked `instant` with
  format `"table"`; several such targets on one panel are joined on their
  label sets into a single table, one value column per target. Everything else
  is a range query producing series named from the target's legend format.
  Panel `overrides` carrying a `negative-Y` transform negate the matching
  series, by exact name or by regexp.

  A panel whose targets all fail yields `{:error, :no_data}`; partial failure
  keeps the successful targets.
  """

  use GenServer

  alias GrafExTerm.Dashboard.Store
  alias GrafExTerm.Datasource.Prometheus
  alias GrafExTerm.Refresh.DataCache
  alias GrafExTerm.Variable.{Manager, Substitution}

  @doc """
  Starts a scheduler for `dashboard` and performs the first fetch.

  `dashboard` is a `GrafExTerm.Dashboard.Types.Dashboard`. The process is
  registered under `dashboard.uid`, so starting a second one for the same uid
  returns `{:error, {:already_started, pid}}`.

  The interval comes from `dashboard.refresh`, parsed from a trailing `s`, `m`
  or `h`. `false`, `nil`, `""` and anything unparseable fall back to the
  `:default_refresh_ms` application environment value, which defaults to
  30_000.

  The first fetch runs in `handle_continue/2`, so this call returns before any
  data is available.
  """
  @spec start_link(GrafExTerm.Dashboard.Types.Dashboard.t()) :: GenServer.on_start()
  def start_link(dashboard) do
    name = {:via, Registry, {GrafExTerm.RefreshRegistry, dashboard.uid}}
    GenServer.start_link(__MODULE__, dashboard, name: name)
  end

  @doc """
  Triggers an immediate fetch for `dashboard_uid` without disturbing the
  timer.

  Asynchronous — returns before the fetch runs. Exits if no scheduler is
  running for that dashboard.
  """
  @spec refresh_now(String.t()) :: :ok
  def refresh_now(dashboard_uid) do
    name = {:via, Registry, {GrafExTerm.RefreshRegistry, dashboard_uid}}
    GenServer.cast(name, :refresh_now)
  end

  @doc """
  Tells the scheduler which rows are collapsed so their panels stop being
  queried.

  `collapsed_rows` is a `MapSet` of row panel ids and replaces the previous
  set entirely. It takes effect on the next fetch, not immediately; pair it
  with `refresh_now/1` to repopulate panels a row has just revealed.

  Asynchronous. Exits if no scheduler is running for that dashboard.
  """
  @spec set_collapsed_rows(String.t(), MapSet.t()) :: :ok
  def set_collapsed_rows(dashboard_uid, collapsed_rows) do
    name = {:via, Registry, {GrafExTerm.RefreshRegistry, dashboard_uid}}
    GenServer.cast(name, {:set_collapsed_rows, collapsed_rows})
  end

  @impl GenServer
  def init(dashboard) do
    interval_ms = parse_interval(dashboard.refresh)

    if interval_ms do
      Process.send_after(self(), :tick, interval_ms)
    end

    {:ok, %{dashboard: dashboard, interval_ms: interval_ms, collapsed_rows: MapSet.new()},
     {:continue, :initial_fetch}}
  end

  @impl GenServer
  def handle_continue(:initial_fetch, state) do
    fetch_and_broadcast(state.dashboard, state.collapsed_rows)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:refresh_now, state) do
    fetch_and_broadcast(state.dashboard, state.collapsed_rows)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:set_collapsed_rows, collapsed_rows}, state) do
    {:noreply, %{state | collapsed_rows: collapsed_rows}}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    fetch_and_broadcast(state.dashboard, state.collapsed_rows)

    if state.interval_ms do
      Process.send_after(self(), :tick, state.interval_ms)
    end

    {:noreply, state}
  end

  defp fetch_and_broadcast(dashboard, collapsed_rows) do
    user_vars = fetch_vars(dashboard.uid)
    app_datasources = merge_source_override(dashboard.uid)
    stored_datasource_map = Store.get_datasource_map(dashboard.uid)
    now = System.system_time(:second)
    time_range = Application.get_env(:graf_ex_term, :time_range_seconds, 3600)
    resolution = Application.get_env(:graf_ex_term, :chart_resolution, 300)
    from = now - time_range
    step = max(1, div(time_range, resolution))
    vars = Map.merge(builtin_vars(from, now, step), user_vars)

    active_panel_ids = active_panel_ids(dashboard.panels, collapsed_rows)

    panel_data =
      dashboard.panels
      |> Enum.reject(fn p -> p.type == "row" end)
      |> Enum.filter(fn p -> MapSet.member?(active_panel_ids, p.id) end)
      |> Enum.map(fn panel ->
        results =
          fetch_panel_data(panel, vars, app_datasources, stored_datasource_map, from, now, step)

        {panel.id, results}
      end)
      |> Map.new()

    DataCache.put(dashboard.uid, panel_data)

    Phoenix.PubSub.broadcast(
      GrafExTerm.PubSub,
      "dashboard:#{dashboard.uid}",
      {:data_refreshed, dashboard.uid, panel_data}
    )
  end

  defp active_panel_ids(panels, collapsed_rows) do
    panels
    |> Enum.sort_by(fn p -> {p.grid_pos.y, p.grid_pos.x} end)
    |> Enum.reduce({MapSet.new(), false}, &classify_panel(&1, &2, collapsed_rows))
    |> elem(0)
  end

  defp classify_panel(%{type: "row"} = panel, {acc, _}, collapsed_rows) do
    {acc, MapSet.member?(collapsed_rows, panel.id)}
  end

  defp classify_panel(_panel, {acc, true}, _collapsed_rows), do: {acc, true}

  defp classify_panel(panel, {acc, false}, _collapsed_rows),
    do: {MapSet.put(acc, panel.id), false}

  defp fetch_vars(dashboard_uid) do
    Manager.get_values(dashboard_uid)
  catch
    _, _ -> %{}
  end

  defp fetch_panel_data(panel, vars, app_datasources, stored_datasource_map, from, to, step) do
    if instant_table_panel?(panel) do
      fetch_instant_table(panel, vars, app_datasources, stored_datasource_map)
    else
      fetch_range_series(panel, vars, app_datasources, stored_datasource_map, from, to, step)
    end
  end

  defp instant_table_panel?(%{type: "table", targets: targets}) do
    Enum.any?(targets, fn t -> t.instant == true and t.format == "table" end)
  end

  defp instant_table_panel?(_), do: false

  defp fetch_range_series(panel, vars, app_datasources, stored_datasource_map, from, to, step) do
    overrides = get_in(panel.field_config, ["overrides"]) || []

    results =
      panel.targets
      |> Enum.map(fn target ->
        fetch_target_series(
          target,
          vars,
          app_datasources,
          stored_datasource_map,
          from,
          to,
          step,
          overrides
        )
      end)

    successful =
      Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    if Enum.empty?(successful) do
      {:error, :no_data}
    else
      all_series = Enum.flat_map(successful, fn {:ok, series} -> series end)
      {:ok, all_series}
    end
  end

  defp fetch_target_series(
         target,
         vars,
         app_datasources,
         stored_datasource_map,
         from,
         to,
         step,
         overrides
       ) do
    expr = Substitution.substitute(target.expr, vars)

    config =
      resolve_datasource(target.datasource_ref, vars, app_datasources, stored_datasource_map)

    case Prometheus.query(config, expr, {from, to}, step) do
      {:ok, series} ->
        named =
          Enum.map(series, fn s ->
            Map.put(s, :name, format_series_name(target.legend_format, s.labels))
          end)

        {:ok, apply_series_overrides(named, overrides)}

      error ->
        error
    end
  end

  defp format_series_name("", labels) do
    labels
    |> Map.delete("__name__")
    |> Map.delete("instance")
    |> Map.delete("job")
    |> Map.values()
    |> case do
      [] -> Map.get(labels, "__name__", "")
      values -> Enum.join(values, ", ")
    end
  end

  defp format_series_name(fmt, labels) do
    Regex.replace(~r/\{\{(\w+)\}\}/, fmt, fn _, key -> Map.get(labels, key, "") end)
  end

  defp apply_series_overrides(series, overrides) do
    negative_matchers = Enum.flat_map(overrides, &extract_negative_matcher/1)

    if Enum.empty?(negative_matchers) do
      series
    else
      Enum.map(series, &maybe_negate_series(&1, negative_matchers))
    end
  end

  defp maybe_negate_series(s, matchers) do
    if matches_any?(s.name, matchers) do
      %{s | values: Enum.map(s.values, fn {ts, v} -> {ts, -v} end)}
    else
      s
    end
  end

  defp extract_negative_matcher(override) do
    has_negative_y =
      Enum.any?(override["properties"] || [], fn p ->
        p["id"] == "custom.transform" and p["value"] == "negative-Y"
      end)

    if has_negative_y do
      case get_in(override, ["matcher", "id"]) do
        "byName" ->
          [{:exact, get_in(override, ["matcher", "options"])}]

        "byRegexp" ->
          pattern = get_in(override, ["matcher", "options"])
          [{:regex, Regex.compile!(String.slice(pattern, 1..-2//1))}]

        _ ->
          []
      end
    else
      []
    end
  end

  defp matches_any?(name, matchers) do
    Enum.any?(matchers, fn
      {:exact, n} -> name == n
      {:regex, r} -> Regex.match?(r, name)
    end)
  end

  defp fetch_instant_table(panel, vars, app_datasources, stored_datasource_map) do
    now = System.system_time(:second)

    target_results =
      Enum.map(panel.targets, fn target ->
        expr = Substitution.substitute(target.expr, vars)

        config =
          resolve_datasource(target.datasource_ref, vars, app_datasources, stored_datasource_map)

        {target, Prometheus.instant_query(config, expr, now)}
      end)

    successful = Enum.filter(target_results, fn {_, r} -> match?({:ok, _}, r) end)

    if Enum.empty?(successful) do
      {:error, :no_data}
    else
      join_instant_table(successful)
    end
  end

  defp join_instant_table(target_results) do
    multi = length(target_results) > 1

    row_map =
      Enum.reduce(target_results, %{}, fn {target, {:ok, results}}, acc ->
        merge_target_results(acc, target, results, multi)
      end)

    rows = Map.values(row_map)

    if Enum.empty?(rows) do
      {:error, :no_data}
    else
      build_instant_table(target_results, rows, multi)
    end
  end

  defp merge_target_results(acc, target, results, multi) do
    col = col_name(target, multi)

    Enum.reduce(results, acc, fn %{labels: labels, value: val}, row_acc ->
      Map.update(row_acc, labels, %{col => val, :_labels => labels}, fn row ->
        Map.put(row, col, val)
      end)
    end)
  end

  defp build_instant_table(target_results, rows, multi) do
    col_names = Enum.map(target_results, fn {target, _} -> col_name(target, multi) end)
    first_labels = hd(rows)[:_labels]
    label_keys = first_labels |> Map.keys() |> Enum.sort()

    label_cols =
      Enum.map(label_keys, fn k ->
        %{key: String.to_atom(k), label: String.capitalize(k), width: :auto}
      end)

    value_cols =
      Enum.map(col_names, fn name ->
        %{key: String.to_atom(name), label: name, width: 10}
      end)

    columns = label_cols ++ value_cols
    formatted_rows = Enum.map(rows, &format_instant_row(&1, col_names))
    {:table, columns, formatted_rows}
  end

  defp format_instant_row(row, col_names) do
    label_fields = Map.new(row[:_labels], fn {k, v} -> {String.to_atom(k), v} end)

    value_fields =
      Map.new(col_names, fn name ->
        val = Map.get(row, name)
        {String.to_atom(name), if(is_float(val), do: Float.round(val, 2), else: val)}
      end)

    Map.merge(label_fields, value_fields)
  end

  defp col_name(%{legend_format: lf}, _multi) when is_binary(lf) and lf != "", do: lf
  defp col_name(%{ref_id: ref}, true), do: "Value ##{ref}"
  defp col_name(_target, false), do: "Value"

  defp merge_source_override(dashboard_uid) do
    app_datasources = Application.get_env(:graf_ex_term, :datasources, %{})

    case Store.get_source(dashboard_uid) do
      nil -> app_datasources
      "" -> app_datasources
      url -> Map.put(app_datasources, "prometheus", %{type: :prometheus, url: url})
    end
  end

  defp default_datasource(app_datasources) do
    Map.get(app_datasources, "prometheus", %{url: "http://localhost:9090"})
  end

  defp resolve_datasource(nil, _vars, app_datasources, _stored) do
    default_datasource(app_datasources)
  end

  defp resolve_datasource(ref, vars, app_datasources, stored_datasource_map) do
    resolved = Substitution.substitute(ref, vars)

    cond do
      Map.has_key?(stored_datasource_map, resolved) ->
        %{url: Map.get(stored_datasource_map, resolved)}

      Regex.match?(~r/^\$\{?(\w+)\}?$/, resolved) ->
        resolve_variable_datasource(resolved, app_datasources, stored_datasource_map)

      Map.has_key?(app_datasources, resolved) ->
        Map.get(app_datasources, resolved)

      true ->
        default_datasource(app_datasources)
    end
  end

  defp resolve_variable_datasource(resolved, app_datasources, stored_datasource_map) do
    case Regex.run(~r/^\$\{?(\w+)\}?$/, resolved) do
      [_, var_name] ->
        case Map.get(stored_datasource_map, var_name) do
          nil -> default_datasource(app_datasources)
          url -> %{url: url}
        end

      _ ->
        default_datasource(app_datasources)
    end
  end

  defp builtin_vars(from, to, step) do
    range_s = to - from
    rate_interval = max(step * 4, 60)

    %{
      "__rate_interval" => "#{rate_interval}s",
      "__interval" => "#{step}s",
      "__interval_ms" => "#{step * 1000}",
      "__range" => "#{range_s}s",
      "__range_s" => "#{range_s}",
      "__range_ms" => "#{range_s * 1000}",
      "__from" => "#{from * 1000}",
      "__to" => "#{to * 1000}"
    }
  end

  defp parse_interval(false), do: Application.get_env(:graf_ex_term, :default_refresh_ms, 30_000)
  defp parse_interval(nil), do: Application.get_env(:graf_ex_term, :default_refresh_ms, 30_000)
  defp parse_interval(""), do: Application.get_env(:graf_ex_term, :default_refresh_ms, 30_000)

  defp parse_interval(interval) when is_binary(interval) do
    cond do
      String.ends_with?(interval, "s") ->
        interval |> String.trim_trailing("s") |> Integer.parse() |> elem(0) |> Kernel.*(1000)

      String.ends_with?(interval, "m") ->
        interval |> String.trim_trailing("m") |> Integer.parse() |> elem(0) |> Kernel.*(60_000)

      String.ends_with?(interval, "h") ->
        interval |> String.trim_trailing("h") |> Integer.parse() |> elem(0) |> Kernel.*(3_600_000)

      true ->
        Application.get_env(:graf_ex_term, :default_refresh_ms, 30_000)
    end
  end

  defp parse_interval(_), do: Application.get_env(:graf_ex_term, :default_refresh_ms, 30_000)
end
