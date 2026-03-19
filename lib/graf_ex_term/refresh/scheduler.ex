defmodule GrafExTerm.Refresh.Scheduler do
  use GenServer

  alias GrafExTerm.Variable.{Manager, Substitution}
  alias GrafExTerm.Datasource.Prometheus

  def start_link(dashboard) do
    name = {:via, Registry, {GrafExTerm.RefreshRegistry, dashboard.uid}}
    GenServer.start_link(__MODULE__, dashboard, name: name)
  end

  def refresh_now(dashboard_uid) do
    name = {:via, Registry, {GrafExTerm.RefreshRegistry, dashboard_uid}}
    GenServer.cast(name, :refresh_now)
  end

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

    {:ok, %{dashboard: dashboard, interval_ms: interval_ms, collapsed_rows: MapSet.new()}, {:continue, :initial_fetch}}
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
    app_datasources = Application.get_env(:graf_ex_term, :datasources, %{})
    stored_datasource_map = GrafExTerm.Dashboard.Store.get_datasource_map(dashboard.uid)
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
        results = fetch_panel_data(panel, vars, app_datasources, stored_datasource_map, from, now, step)
        {panel.id, results}
      end)
      |> Map.new()

    GrafExTerm.Refresh.DataCache.put(dashboard.uid, panel_data)

    Phoenix.PubSub.broadcast(
      GrafExTerm.PubSub,
      "dashboard:#{dashboard.uid}",
      {:data_refreshed, dashboard.uid, panel_data}
    )
  end

  defp active_panel_ids(panels, collapsed_rows) do
    panels
    |> Enum.sort_by(fn p -> {p.grid_pos.y, p.grid_pos.x} end)
    |> Enum.reduce({MapSet.new(), false}, fn panel, {acc, in_collapsed} ->
      case panel.type do
        "row" ->
          {acc, MapSet.member?(collapsed_rows, panel.id)}
        _ ->
          if in_collapsed, do: {acc, true}, else: {MapSet.put(acc, panel.id), false}
      end
    end)
    |> elem(0)
  end

  defp fetch_vars(dashboard_uid) do
    try do
      Manager.get_values(dashboard_uid)
    catch
      _, _ -> %{}
    end
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
    results =
      panel.targets
      |> Enum.map(fn target ->
        expr = Substitution.substitute(target.expr, vars)
        config = resolve_datasource(target.datasource_ref, vars, app_datasources, stored_datasource_map)
        Prometheus.query(config, expr, {from, to}, step)
      end)

    successful = Enum.filter(results, fn
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

  defp fetch_instant_table(panel, vars, app_datasources, stored_datasource_map) do
    now = System.system_time(:second)

    target_results =
      Enum.map(panel.targets, fn target ->
        expr = Substitution.substitute(target.expr, vars)
        config = resolve_datasource(target.datasource_ref, vars, app_datasources, stored_datasource_map)
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
        col = col_name(target, multi)

        Enum.reduce(results, acc, fn %{labels: labels, value: val}, row_acc ->
          Map.update(row_acc, labels, %{col => val, :_labels => labels}, fn row ->
            Map.put(row, col, val)
          end)
        end)
      end)

    rows = Map.values(row_map)

    if Enum.empty?(rows) do
      {:error, :no_data}
    else
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

      formatted_rows =
        Enum.map(rows, fn row ->
          label_fields = Map.new(row[:_labels], fn {k, v} -> {String.to_atom(k), v} end)
          value_fields = Map.new(col_names, fn name ->
            val = Map.get(row, name)
            {String.to_atom(name), if(is_float(val), do: Float.round(val, 2), else: val)}
          end)
          Map.merge(label_fields, value_fields)
        end)

      {:table, columns, formatted_rows}
    end
  end

  defp col_name(%{legend_format: lf}, _multi) when is_binary(lf) and lf != "", do: lf
  defp col_name(%{ref_id: ref}, true), do: "Value ##{ref}"
  defp col_name(_target, false), do: "Value"

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
        case Regex.run(~r/^\$\{?(\w+)\}?$/, resolved) do
          [_, var_name] ->
            case Map.get(stored_datasource_map, var_name) do
              nil -> default_datasource(app_datasources)
              url -> %{url: url}
            end
          _ -> default_datasource(app_datasources)
        end

      Map.has_key?(app_datasources, resolved) ->
        Map.get(app_datasources, resolved)

      true ->
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
