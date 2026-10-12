defmodule GrafExTerm.Refresh.Scheduler do
  @moduledoc """
  Per-dashboard process that queries every visible panel on a timer and
  publishes the results.

  One is started under `GrafExTerm.RefreshSupervisor` for each dashboard the
  user opens and registered in `GrafExTerm.RefreshRegistry` under the
  dashboard uid, so callers address it by uid. It fetches once immediately on
  start and then on its interval.

  Each fetch writes to `GrafExTerm.Refresh.DataCache` and broadcasts
  `{:data_refreshed, uid}` on the `"dashboard:<uid>"` PubSub topic; the data
  itself is read from the cache. Cached panel data maps panel id to
  `{:ok, series}`, `{:table, columns, rows}` or `{:error, reason}`.

  Panels are queried concurrently, at most `:max_concurrent_queries`
  (default 8) at a time, each within `:query_timeout_ms` (default 30_000). A
  panel that times out yields `{:error, :timeout}`.

  Only panels that are actually visible are queried. Row panels are never
  queried, and panels under a collapsed row are skipped, so a caller must keep
  the scheduler's idea of collapsed rows current with `set_collapsed_rows/2`
  or it will keep querying panels the user cannot see. The set starts empty,
  meaning everything is queried, even if the screen opens with rows collapsed.

  Each panel's window and step come from `GrafExTerm.Refresh.QueryWindow`:
  `:time_range_seconds` (default 3600) back from now, sampled about twice per
  terminal column the panel occupies. The column count is the `:columns`
  start option, kept current with `set_columns/2`; until it is known,
  `:chart_resolution` (default 300) samples are fetched per panel. The Grafana
  built-ins `__rate_interval`, `__interval`, `__interval_ms`, `__range`,
  `__range_s`, `__range_ms`, `__from` and `__to` are derived from the panel's
  window and merged under the user's variable values, so a dashboard variable
  of the same name wins.

  After the first fetch of a panel, later fetches query only the samples since
  the previous one, from two steps back, and append them with
  `GrafExTerm.Refresh.SeriesWindow`. A change of step, variable values or
  datasources, or a failed fetch, makes the next fetch of that panel a full
  one.

  A target is fetched as an instant table when it is marked `instant` with
  format `"table"`; several such targets on one panel are joined on their
  label sets into a single table, one value column per target. Everything else
  is a range query producing series named from the target's legend format and
  tagged with the target's `:ref_id`. Panel `overrides` carrying a
  `negative-Y` transform negate the matching series, by exact name or by
  regexp.

  A panel whose targets all fail yields `{:error, :no_data}`; partial failure
  keeps the successful targets.

  A resolved datasource config with `type: :demo` is answered by
  `GrafExTerm.Datasource.Demo` (and `GrafExTerm.Datasource.Demo.Logs` for
  logs panels) instead of Prometheus or Loki.
  """

  use GenServer

  alias GrafExTerm.Dashboard.Store
  alias GrafExTerm.Dashboard.Types.Dashboard
  alias GrafExTerm.Dashboard.Visibility
  alias GrafExTerm.Datasource.{Demo, Loki, Prometheus}
  alias GrafExTerm.Refresh.{DataCache, QueryWindow, SeriesWindow}
  alias GrafExTerm.Variable.{Manager, Substitution}

  @overlap_steps 2
  @default_log_lines 1000
  @resize_settle_ms 300

  @doc """
  Starts a scheduler and performs the first fetch.

  Takes a `GrafExTerm.Dashboard.Types.Dashboard`, or `{dashboard, opts}` where
  `opts` may hold `:columns`, the terminal columns the dashboard is drawn
  across. The process is registered under `dashboard.uid`, so starting a
  second one for the same uid returns `{:error, {:already_started, pid}}`.

  The interval comes from `dashboard.refresh`, parsed from a trailing `s`, `m`
  or `h`. `false`, `nil`, `""` and anything unparseable fall back to the
  `:default_refresh_ms` application environment value, which defaults to
  30_000.

  The first fetch runs in `handle_continue/2`, so this call returns before any
  data is available.
  """
  @spec start_link(Dashboard.t() | {Dashboard.t(), keyword()}) :: GenServer.on_start()
  def start_link(%Dashboard{} = dashboard), do: start_link({dashboard, []})

  def start_link({%Dashboard{} = dashboard, opts}) do
    name = {:via, Registry, {GrafExTerm.RefreshRegistry, dashboard.uid}}
    GenServer.start_link(__MODULE__, {dashboard, opts}, name: name)
  end

  @doc """
  Triggers an immediate fetch for `dashboard_uid` without disturbing the
  timer.

  Asynchronous — returns before the fetch runs. Exits if no scheduler is
  running for that dashboard.
  """
  @spec refresh_now(String.t()) :: :ok
  def refresh_now(dashboard_uid) do
    GenServer.cast(via(dashboard_uid), :refresh_now)
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
    GenServer.cast(via(dashboard_uid), {:set_collapsed_rows, collapsed_rows})
  end

  @doc """
  Sets the terminal columns the dashboard is drawn across.

  A changed count refetches every visible panel at the new resolution once
  the count has stayed the same for 300 ms, so a drag-resize costs one fetch.
  Asynchronous; does nothing when no scheduler is running for that dashboard.
  """
  @spec set_columns(String.t(), pos_integer()) :: :ok
  def set_columns(dashboard_uid, columns) when is_integer(columns) and columns > 0 do
    case Registry.lookup(GrafExTerm.RefreshRegistry, dashboard_uid) do
      [{pid, _}] -> GenServer.cast(pid, {:set_columns, columns})
      [] -> :ok
    end
  end

  @impl GenServer
  def init({dashboard, opts}) do
    interval_ms = parse_interval(dashboard.refresh)

    if interval_ms do
      Process.send_after(self(), :tick, interval_ms)
    end

    state = %{
      dashboard: dashboard,
      interval_ms: interval_ms,
      collapsed_rows: MapSet.new(),
      columns: Keyword.get(opts, :columns),
      held: %{}
    }

    {:ok, state, {:continue, :initial_fetch}}
  end

  @impl GenServer
  def handle_continue(:initial_fetch, state) do
    {:noreply, fetch_and_broadcast(state)}
  end

  @impl GenServer
  def handle_cast(:refresh_now, state) do
    {:noreply, fetch_and_broadcast(state)}
  end

  def handle_cast({:set_collapsed_rows, collapsed_rows}, state) do
    {:noreply, %{state | collapsed_rows: collapsed_rows}}
  end

  def handle_cast({:set_columns, columns}, %{columns: columns} = state), do: {:noreply, state}

  def handle_cast({:set_columns, columns}, state) do
    Process.send_after(self(), {:columns_settled, columns}, @resize_settle_ms)
    {:noreply, %{state | columns: columns}}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    state = fetch_and_broadcast(state)

    if state.interval_ms do
      Process.send_after(self(), :tick, state.interval_ms)
    end

    {:noreply, state}
  end

  def handle_info({:columns_settled, columns}, %{columns: columns} = state) do
    {:noreply, fetch_and_broadcast(state)}
  end

  def handle_info({:columns_settled, _stale}, state), do: {:noreply, state}

  def handle_info(_message, state), do: {:noreply, state}

  defp via(dashboard_uid), do: {:via, Registry, {GrafExTerm.RefreshRegistry, dashboard_uid}}

  defp fetch_and_broadcast(state) do
    dashboard = state.dashboard
    context = fetch_context(state)
    active_panel_ids = Visibility.active_panel_ids(dashboard.panels, state.collapsed_rows)

    panels =
      Enum.filter(
        dashboard.panels,
        &(&1.targets != [] and MapSet.member?(active_panel_ids, &1.id))
      )

    fetched =
      panels
      |> Task.async_stream(&fetch_panel(&1, context, Map.get(state.held, &1.id)),
        max_concurrency: Application.get_env(:graf_ex_term, :max_concurrent_queries, 8),
        timeout: Application.get_env(:graf_ex_term, :query_timeout_ms, 30_000),
        on_timeout: :kill_task
      )
      |> Enum.zip(panels)
      |> Enum.map(fn
        {{:ok, {result, held}}, panel} -> {panel.id, result, held}
        {{:exit, _reason}, panel} -> {panel.id, {:error, :timeout}, nil}
      end)

    panel_data = Map.new(fetched, fn {id, result, _held} -> {id, result} end)
    held = for {id, _result, entry} <- fetched, entry != nil, into: %{}, do: {id, entry}

    DataCache.put(dashboard.uid, panel_data)

    Phoenix.PubSub.broadcast(
      GrafExTerm.PubSub,
      "dashboard:#{dashboard.uid}",
      {:data_refreshed, dashboard.uid}
    )

    %{state | held: held}
  end

  defp fetch_context(state) do
    uid = state.dashboard.uid
    user_vars = fetch_vars(uid)
    app_datasources = merge_source_override(uid)
    stored_datasource_map = Store.get_datasource_map(uid)

    %{
      user_vars: user_vars,
      app_datasources: app_datasources,
      stored_datasource_map: stored_datasource_map,
      fingerprint: :erlang.phash2({user_vars, app_datasources, stored_datasource_map}),
      now: System.system_time(:second),
      range: Application.get_env(:graf_ex_term, :time_range_seconds, 3600),
      columns: state.columns,
      fallback_points: Application.get_env(:graf_ex_term, :chart_resolution, 300)
    }
  end

  defp fetch_panel(panel, context, held) do
    window =
      QueryWindow.for_panel(panel,
        now: context.now,
        range: context.range,
        columns: context.columns,
        fallback_points: context.fallback_points
      )

    vars = Map.merge(builtin_vars(window), context.user_vars)

    cond do
      panel.type == "logs" -> {fetch_logs(panel, window, vars, context), nil}
      instant_table_panel?(panel) -> {fetch_instant_table(panel, vars, context), nil}
      true -> fetch_range_panel(panel, window, vars, context, held)
    end
  end

  defp fetch_range_panel(panel, window, vars, context, held) do
    key = {window.step, context.fingerprint}

    case tail_start(held, key, window) do
      nil ->
        result = fetch_range_series(panel, vars, context, window.from, window.to, window.step)
        {result, held_entry(result, key, window)}

      tail_from ->
        tail = fetch_range_series(panel, vars, context, tail_from, window.to, window.step)
        result = append_tail(held.result, tail, window.from, tail_from)
        {result, held_entry(result, key, window)}
    end
  end

  defp tail_start(%{key: key, window: previous}, key, window) when previous.to >= window.from do
    max(window.from, previous.to - @overlap_steps * window.step)
  end

  defp tail_start(_held, _key, _window), do: nil

  defp append_tail({:ok, held_series}, {:ok, tail_series}, from, tail_from) do
    {:ok, SeriesWindow.merge(held_series, tail_series, from, tail_from)}
  end

  defp append_tail(_held, tail_error, _from, _tail_from), do: tail_error

  defp held_entry({:ok, _} = result, key, window), do: %{key: key, window: window, result: result}
  defp held_entry(_result, _key, _window), do: nil

  defp fetch_vars(dashboard_uid) do
    Manager.get_values(dashboard_uid)
  catch
    _, _ -> %{}
  end

  defp fetch_logs(panel, window, vars, context) do
    limit = panel.max_data_points || @default_log_lines
    fallback = default_datasource(context.app_datasources, "loki")

    results =
      Enum.map(panel.targets, fn target ->
        config =
          resolve_datasource(
            target.datasource_ref,
            vars,
            context.app_datasources,
            context.stored_datasource_map,
            fallback
          )

        logs_backend(config).query(
          config,
          Substitution.substitute(target.expr, vars),
          {window.from, context.now},
          limit
        )
      end)

    case for({:ok, entries} <- results, do: entries) do
      [] -> {:error, :no_data}
      found -> {:logs, found |> List.flatten() |> Enum.sort_by(& &1.time) |> Enum.take(-limit)}
    end
  end

  defp metrics_backend(%{type: :demo}), do: Demo
  defp metrics_backend(_config), do: Prometheus

  defp logs_backend(%{type: :demo}), do: Demo.Logs
  defp logs_backend(_config), do: Loki

  defp instant_table_panel?(%{type: "table", targets: targets}) do
    Enum.any?(targets, fn t -> t.instant == true and t.format == "table" end)
  end

  defp instant_table_panel?(_), do: false

  defp fetch_range_series(panel, vars, context, from, to, step) do
    overrides = get_in(panel.field_config, ["overrides"]) || []

    results =
      Enum.map(panel.targets, fn target ->
        fetch_target_series(target, vars, context, {from, to}, step, overrides)
      end)

    successful = Enum.filter(results, &match?({:ok, _}, &1))

    if Enum.empty?(successful) do
      {:error, :no_data}
    else
      {:ok, Enum.flat_map(successful, fn {:ok, series} -> series end)}
    end
  end

  defp fetch_target_series(target, vars, context, time_range, step, overrides) do
    expr = Substitution.substitute(target.expr, vars)

    config =
      resolve_datasource(
        target.datasource_ref,
        vars,
        context.app_datasources,
        context.stored_datasource_map,
        default_datasource(context.app_datasources, "prometheus")
      )

    case metrics_backend(config).query(config, expr, time_range, step) do
      {:ok, series} ->
        named =
          Enum.map(series, fn s ->
            s
            |> Map.put(:name, format_series_name(target.legend_format, s.labels))
            |> Map.put(:ref_id, target.ref_id)
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

  defp fetch_instant_table(panel, vars, context) do
    target_results =
      Enum.map(panel.targets, fn target ->
        expr = Substitution.substitute(target.expr, vars)

        config =
          resolve_datasource(
            target.datasource_ref,
            vars,
            context.app_datasources,
            context.stored_datasource_map,
            default_datasource(context.app_datasources, "prometheus")
          )

        {target, metrics_backend(config).instant_query(config, expr, context.now)}
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

  @fallback_urls %{"prometheus" => "http://localhost:9090", "loki" => "http://localhost:3100"}

  defp default_datasource(app_datasources, kind) do
    Map.get(app_datasources, kind, %{url: Map.fetch!(@fallback_urls, kind)})
  end

  defp resolve_datasource(nil, _vars, _app_datasources, _stored, fallback), do: fallback

  defp resolve_datasource(ref, vars, app_datasources, stored_datasource_map, fallback) do
    resolved = Substitution.substitute(ref, vars)

    cond do
      Map.has_key?(stored_datasource_map, resolved) ->
        %{url: Map.get(stored_datasource_map, resolved)}

      Regex.match?(~r/^\$\{?(\w+)\}?$/, resolved) ->
        resolve_variable_datasource(resolved, stored_datasource_map, fallback)

      Map.has_key?(app_datasources, resolved) ->
        Map.get(app_datasources, resolved)

      true ->
        fallback
    end
  end

  defp resolve_variable_datasource(resolved, stored_datasource_map, fallback) do
    case Regex.run(~r/^\$\{?(\w+)\}?$/, resolved) do
      [_, var_name] ->
        case Map.get(stored_datasource_map, var_name) do
          nil -> fallback
          url -> %{url: url}
        end

      _ ->
        fallback
    end
  end

  defp builtin_vars(%QueryWindow{from: from, to: to, step: step}) do
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
