defmodule GrafExTerm.Screen.Main do
  use Drafter.App
  import Drafter.App

  alias GrafExTerm.Dashboard.Store
  alias GrafExTerm.Layout.GridMapper
  alias GrafExTerm.Variable.Manager
  alias GrafExTerm.Refresh.{Scheduler, DataCache}
  alias GrafExTerm.Panel.Table

  def mount(_props) do
    %{
      dashboards: [],
      selected_uid: nil,
      selected_panels: [],
      panel_data: %{},
      prepared_panel_data: %{},
      variables: %{},
      loading: false,
      data_version: nil,
      column_visibility: %{},
      collapsed_rows: MapSet.new(),
      row_filter: nil,
      table_layouts: %{},
      scrolling: false,
      pending_data: nil
    }
  end

  def on_ready(state) do
    theme = Application.get_env(:graf_ex_term, :theme, "tokyo-night")
    Drafter.ThemeManager.set_theme(theme)
    %{state | dashboards: Store.list()}
  end

  def on_message({:data_refreshed, uid, _}, %{selected_uid: uid} = state) do
    send(self(), {:timer, :data_ready})
    state
  end

  def on_message(_msg, state), do: state

  def on_timer(:data_ready, %{selected_uid: nil} = state), do: state

  def on_timer(:data_ready, %{scrolling: true} = state) do
    case DataCache.take_if_updated(state.selected_uid, state.data_version) do
      :unchanged -> state
      {:updated, %{panel_data: panel_data, version: version}} ->
        %{state | pending_data: {panel_data, version}}
    end
  end

  def on_timer(:data_ready, state) do
    case DataCache.take_if_updated(state.selected_uid, state.data_version) do
      :unchanged -> state
      {:updated, %{panel_data: panel_data, version: version}} ->
        vars = fetch_vars(state.selected_uid)
        prepared = prepare_panel_data(panel_data, state.selected_panels, state.row_filter, state.collapsed_rows)
        %{state | panel_data: panel_data, prepared_panel_data: prepared, variables: vars, loading: false, data_version: version}
    end
  end

  def on_timer(_timer_id, state), do: state

  def on_scroll_active(state), do: %{state | scrolling: true}

  def on_scroll_idle(%{pending_data: nil} = state), do: %{state | scrolling: false}

  def on_scroll_idle(%{pending_data: {panel_data, version}} = state) do
    vars = fetch_vars(state.selected_uid)
    prepared = prepare_panel_data(panel_data, state.selected_panels, state.row_filter, state.collapsed_rows)
    %{state | scrolling: false, pending_data: nil, panel_data: panel_data, prepared_panel_data: prepared, variables: vars, loading: false, data_version: version}
  end

  defp unsubscribe(nil), do: :ok
  defp unsubscribe(uid), do: Phoenix.PubSub.unsubscribe(GrafExTerm.PubSub, "dashboard:#{uid}")

  def render(state) do
    vertical([
      header("GrafExTerm"),
      horizontal(
        [
          vertical(left_panel_items(state), width: 32),
          scrollable(right_panel_items(state), flex: 1, click_to_scroll: true)
        ],
        flex: 1
      ),
      footer(
        bindings: [
          {"a", "add"},
          {"r", "refresh"},
          {"q", "quit"}
        ]
      )
    ])
  end

  def handle_event(:select_dashboard, nil, state) do
    stop_active_children(state.selected_uid)
    unsubscribe(state.selected_uid)
    {:ok, %{state | selected_uid: nil, selected_panels: [], panel_data: %{}, prepared_panel_data: %{}, loading: false, row_filter: nil, table_layouts: %{}, scrolling: false, pending_data: nil}}
  end

  def handle_event(:select_dashboard, uid, state) do
    case Store.get_dashboard(uid) do
      {:ok, dashboard} ->
        stop_active_children(state.selected_uid)
        unsubscribe(state.selected_uid)
        Phoenix.PubSub.subscribe(GrafExTerm.PubSub, "dashboard:#{uid}")
        start_children(dashboard)

        {:ok,
         %{
           state
           | selected_uid: uid,
             selected_panels: dashboard.panels,
             panel_data: %{},
             prepared_panel_data: %{},
             variables: initial_variables(dashboard),
             column_visibility: Store.get_column_visibility(uid),
             table_layouts: Store.get_table_layouts(uid),
             loading: true,
             data_version: nil,
             row_filter: nil,
             scrolling: false,
             pending_data: nil
         }}

      {:error, _} ->
        {:noreply, state}
    end
  end

  def handle_event(:add_dashboard, _data, _state) do
    {:show_modal, GrafExTerm.Screen.AddDashboardModal, %{},
     [title: "Add Dashboard", width: 60, height: 16]}
  end

  def handle_event(:refresh_dashboards, _data, state) do
    {:ok, %{state | dashboards: Store.list()}}
  end

  def handle_event({:toggle_column, panel_id, col_key}, checked, state) do
    current = current_column_set(state, panel_id)
    new_set = if checked, do: MapSet.put(current, col_key), else: MapSet.delete(current, col_key)
    new_visibility = Map.put(state.column_visibility, panel_id, new_set)
    Store.save_column_visibility(state.selected_uid, new_visibility)
    {:noreply, %{state | column_visibility: new_visibility}}
  end

  def handle_event({:table_layout_changed, panel_id}, layout, state) do
    new_layouts = Map.put(state.table_layouts, panel_id, layout)
    Store.save_table_layout(state.selected_uid, panel_id, layout)
    {:noreply, %{state | table_layouts: new_layouts}}
  end

  def handle_event({:table_row_selected, _panel_id}, [], state) do
    prepared = refilter_series(state.prepared_panel_data, state.panel_data, nil)
    {:noreply, %{state | prepared_panel_data: prepared, row_filter: nil}}
  end

  def handle_event({:table_row_selected, _panel_id}, rows, state) do
    filter = extract_label_filter(rows)
    prepared = refilter_series(state.prepared_panel_data, state.panel_data, filter)
    {:noreply, %{state | prepared_panel_data: prepared, row_filter: filter}}
  end

  def handle_event({:toggle_row, row_id}, collapsed, state) do
    new_collapsed =
      if collapsed,
        do: MapSet.put(state.collapsed_rows, row_id),
        else: MapSet.delete(state.collapsed_rows, row_id)

    if state.selected_uid do
      Scheduler.set_collapsed_rows(state.selected_uid, new_collapsed)

      unless collapsed do
        Scheduler.refresh_now(state.selected_uid)
      end
    end

    {:noreply, %{state | collapsed_rows: new_collapsed}}
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  def handle_event({:key, :a}, _state) do
    {:show_modal, GrafExTerm.Screen.AddDashboardModal, %{},
     [title: "Add Dashboard", width: 60, height: 16]}
  end

  def handle_event({:key, :r}, %{selected_uid: nil} = state), do: {:noreply, state}
  def handle_event({:key, :r}, state) do
    Scheduler.refresh_now(state.selected_uid)
    {:noreply, %{state | loading: true}}
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  def unmount(state) do
    stop_active_children(state.selected_uid)
    :ok
  end

  defp left_panel_items(state) do
    items = [{"— none —", nil} | Enum.map(state.dashboards, fn d -> {d.title, d.uid} end)]

    [
      label("Dashboards", class: :primary, style: %{bold: true}),
      radio_set(items,
        id: :dashboard_selector,
        selected: state.selected_uid,
        on_change: :select_dashboard,
        height: length(items)
      ),
      button("[+] Add", on_click: :add_dashboard, variant: :primary)
    ]
  end

  defp right_panel_items(%{selected_uid: nil}) do
    [label("Select a dashboard from the left panel", class: :muted)]
  end

  defp right_panel_items(%{loading: true}) do
    [loading_indicator(running: true)]
  end

  defp right_panel_items(state) do
    case Store.get_dashboard(state.selected_uid) do
      {:ok, dashboard} ->
        GridMapper.to_tui_layout(dashboard.panels, state.prepared_panel_data, state.variables, state.column_visibility, state.collapsed_rows, state.table_layouts)

      {:error, _} ->
        [label("Dashboard unavailable", class: :error)]
    end
  end

  defp start_children(dashboard) do
    DynamicSupervisor.start_child(GrafExTerm.VarSupervisor, {Manager, dashboard})
    DynamicSupervisor.start_child(GrafExTerm.RefreshSupervisor, {Scheduler, dashboard})
  end

  defp stop_active_children(nil), do: :ok

  defp stop_active_children(uid) do
    case Registry.lookup(GrafExTerm.RefreshRegistry, uid) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(GrafExTerm.RefreshSupervisor, pid)
      _ -> :ok
    end

    case Registry.lookup(GrafExTerm.VarRegistry, uid) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(GrafExTerm.VarSupervisor, pid)
      _ -> :ok
    end

  end

  defp initial_variables(dashboard) do
    Enum.reduce(dashboard.templating, %{}, fn var, acc ->
      Map.put(acc, var.name, var.current_value)
    end)
  end

  defp current_column_set(state, panel_id) do
    case Map.get(state.column_visibility, panel_id) do
      nil ->
        case Map.get(state.prepared_panel_data, panel_id) do
          {:prepared, _, all_cols} -> MapSet.new(all_cols, fn c -> c.key end)
          _ -> MapSet.new()
        end
      existing -> existing
    end
  end

  defp prepare_panel_data(panel_data, panels, row_filter, collapsed_rows) do
    table_panels =
      panels
      |> Enum.filter(fn p -> p.type == "table" end)
      |> Map.new(fn p -> {p.id, p} end)

    active_ids = active_panel_ids(panels, collapsed_rows)

    Map.new(panel_data, fn {panel_id, data} ->
      if not MapSet.member?(active_ids, panel_id) do
        {panel_id, data}
      else
        case Map.get(table_panels, panel_id) do
          nil ->
            {panel_id, apply_row_filter(data, row_filter)}
          panel ->
            {rows, cols} = Table.prepare(data, panel.organize, panel.field_config)
            {panel_id, {:prepared, rows, cols}}
        end
      end
    end)
  end

  defp active_panel_ids(panels, collapsed_rows) do
    panels
    |> Enum.sort_by(fn p -> {p.grid_pos.y, p.grid_pos.x} end)
    |> Enum.reduce({MapSet.new(), false}, fn panel, {acc, in_collapsed} ->
      case panel.type do
        "row" -> {acc, MapSet.member?(collapsed_rows, panel.id)}
        _ -> if in_collapsed, do: {acc, true}, else: {MapSet.put(acc, panel.id), false}
      end
    end)
    |> elem(0)
  end

  defp refilter_series(prepared, raw_panel_data, filter) do
    Map.new(prepared, fn {panel_id, value} ->
      case value do
        {:prepared, _, _} ->
          {panel_id, value}
        _ ->
          raw = Map.get(raw_panel_data, panel_id, {:error, :no_data})
          {panel_id, apply_row_filter(raw, filter)}
      end
    end)
  end

  defp apply_row_filter(data, nil), do: data

  defp apply_row_filter({:ok, series}, filters) do
    filtered =
      Enum.filter(series, fn s ->
        Enum.any?(filters, fn filter ->
          Enum.all?(filter, fn {key, val} ->
            Map.get(s.labels, key) == val
          end)
        end)
      end)
    {:ok, filtered}
  end

  defp apply_row_filter(data, _filters), do: data

  defp extract_label_filter(rows) do
    excluded_keys = [:time, :value]

    Enum.map(rows, fn row ->
      row
      |> Map.drop(excluded_keys)
      |> Map.new(fn {key, val} -> {to_string(key), to_string(val)} end)
    end)
  end

  defp fetch_vars(uid) do
    try do
      Manager.get_values(uid)
    catch
      _, _ -> %{}
    end
  end
end
