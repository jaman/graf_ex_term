defmodule GrafExTerm.Screen.Main do
  @moduledoc """
  The application's root Drafter screen: a dashboard list on the left, the
  selected dashboard's panels on the right.

  Selecting a dashboard starts a `GrafExTerm.Variable.Manager` and a
  `GrafExTerm.Refresh.Scheduler` for it and subscribes to its
  `"dashboard:<uid>"` PubSub topic; deselecting or selecting another stops
  them again, so at most one dashboard is being queried at a time.

  Refresh announcements only schedule a poll of
  `GrafExTerm.Refresh.DataCache`; the cache's version decides whether anything
  is rebuilt. A refresh announced while the user is scrolling sets `:pending`
  and is applied when scrolling stops, so a refresh never reflows the view
  under the user's cursor.

  Fetched data is prepared once per arrival with `GrafExTerm.Panel.Prepare`,
  and only the prepared form is held in screen state; the raw data stays in
  the cache.

  The scheduler is told how many terminal columns the dashboard pane has, at
  start and on every resize, so it can size each panel's query step.

  Selecting rows in a table filters every timeseries panel on the dashboard to
  the series whose labels match the selected rows; selecting none clears the
  filter.

  The top line is a `GrafExTerm.Screen.StatusBar`. Key bindings: `a` adds a
  dashboard, `f` toggles the per-column table selector, `b` hides or shows the
  dashboard list, `r` refreshes the selected dashboard, `q` quits. Clicking a
  footer hint does the same as its key.

  Per-dashboard settings — visible columns, table layouts, collapsed rows and
  the column filter — are read from and written back to
  `GrafExTerm.Dashboard.Store`. A dashboard with no stored collapsed rows
  opens with every row collapsed.
  """

  use Drafter.App, mouse_hover: false
  import Drafter.App

  alias GrafExTerm.Dashboard.Store
  alias GrafExTerm.Layout.GridMapper
  alias GrafExTerm.Panel.Prepare
  alias GrafExTerm.Refresh.{DataCache, Scheduler}
  alias GrafExTerm.Screen.StatusBar
  alias GrafExTerm.Variable.Manager

  def mount(_props) do
    %{
      dashboards: [],
      selected_uid: nil,
      selected_panels: [],
      prepared_panel_data: %{},
      variables: %{},
      loading: false,
      data_version: nil,
      column_visibility: %{},
      collapsed_rows: MapSet.new(),
      row_filter: nil,
      table_layouts: %{},
      column_filter: false,
      scrolling: false,
      pending: false,
      columns: nil,
      width: nil,
      sidebar: true,
      dashboard_title: nil,
      dashboard_refresh: nil,
      updated_at: nil
    }
  end

  @sidebar_width 28

  def refresh_rate, do: :unlimited

  def on_ready(state) do
    theme = Application.get_env(:graf_ex_term, :theme, "tokyo-night")
    Drafter.ThemeManager.set_theme(theme)
    Drafter.set_interval(1000, :clock_tick)
    {width, _height} = Drafter.Compositor.get_screen_size()
    %{state | dashboards: Store.list(), width: width, columns: pane_columns(width, true)}
  end

  def on_message({:data_refreshed, uid}, %{selected_uid: uid} = state) do
    send(self(), {:timer, :data_ready})
    state
  end

  def on_message(_msg, state), do: state

  def on_timer(:data_ready, %{selected_uid: nil} = state), do: state

  def on_timer(:data_ready, %{scrolling: true} = state), do: %{state | pending: true}
  def on_timer(:data_ready, state), do: apply_cached_data(state)

  def on_timer(:clock_tick, state), do: state
  def on_timer(_timer_id, state), do: state

  def on_scroll_active(state), do: %{state | scrolling: true}

  def on_scroll_idle(%{pending: false} = state), do: %{state | scrolling: false}

  def on_scroll_idle(state) do
    apply_cached_data(%{state | scrolling: false, pending: false})
  end

  defp apply_cached_data(%{selected_uid: nil} = state), do: state

  defp apply_cached_data(state) do
    case DataCache.take_if_updated(state.selected_uid, state.data_version) do
      :unchanged ->
        state

      {:updated, %{panel_data: panel_data, version: version}} ->
        prepared =
          Prepare.all(panel_data, state.selected_panels, state.row_filter, state.collapsed_rows)

        %{
          state
          | prepared_panel_data: prepared,
            variables: fetch_vars(state.selected_uid),
            loading: false,
            data_version: version,
            updated_at: local_time()
        }
    end
  end

  defp unsubscribe(nil), do: :ok
  defp unsubscribe(uid), do: Phoenix.PubSub.unsubscribe(GrafExTerm.PubSub, "dashboard:#{uid}")

  def render(state) do
    vertical([
      StatusBar.render(%{
        title: state.dashboard_title,
        range_seconds: Application.get_env(:graf_ex_term, :time_range_seconds, 3600),
        refresh: state.dashboard_refresh,
        loading: state.loading,
        updated_at: state.updated_at
      }),
      horizontal(
        sidebar(state) ++
          [scrollable(right_panel_items(state), flex: 1, click_to_scroll: true, scrollbar: :thin)],
        flex: 1,
        gap: 1
      ),
      footer(
        bindings: [
          {"a", "add"},
          {"f", "filter"},
          {"b", "sidebar"},
          {"r", "refresh"},
          {"q", "quit"}
        ]
      )
    ])
  end

  def handle_event(:select_dashboard, uid, state) do
    case Store.get_dashboard(uid) do
      {:ok, dashboard} ->
        stop_active_children(state.selected_uid)
        unsubscribe(state.selected_uid)
        Phoenix.PubSub.subscribe(GrafExTerm.PubSub, "dashboard:#{uid}")
        start_children(dashboard, state.columns)

        {:ok,
         %{
           state
           | selected_uid: uid,
             selected_panels: dashboard.panels,
             dashboard_title: dashboard.title,
             dashboard_refresh: dashboard.refresh,
             updated_at: nil,
             prepared_panel_data: %{},
             variables: initial_variables(dashboard),
             column_visibility: Store.get_column_visibility(uid),
             table_layouts: Store.get_table_layouts(uid),
             collapsed_rows: initial_collapsed_rows(uid, dashboard.panels),
             column_filter: Store.get_column_filter(uid),
             loading: true,
             data_version: nil,
             row_filter: nil,
             scrolling: false,
             pending: false
         }}

      {:error, _} ->
        {:noreply, state}
    end
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
    {:noreply, refilter(state, nil)}
  end

  def handle_event({:table_row_selected, _panel_id}, rows, state) do
    {:noreply, refilter(state, extract_label_filter(rows))}
  end

  def handle_event({:toggle_row, row_id}, collapsed, state) do
    new_collapsed =
      if collapsed,
        do: MapSet.put(state.collapsed_rows, row_id),
        else: MapSet.delete(state.collapsed_rows, row_id)

    if state.selected_uid do
      Scheduler.set_collapsed_rows(state.selected_uid, new_collapsed)
      Store.save_collapsed_rows(state.selected_uid, new_collapsed)

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

  def handle_event({:key, :f}, state) do
    new_filter = not state.column_filter
    if state.selected_uid, do: Store.save_column_filter(state.selected_uid, new_filter)
    {:ok, %{state | column_filter: new_filter}}
  end

  def handle_event({:key, :b}, state) do
    sidebar = not state.sidebar
    {:ok, resize_pane(%{state | sidebar: sidebar}, state.width)}
  end

  def handle_event({:key, :r}, %{selected_uid: nil} = state), do: {:noreply, state}

  def handle_event({:key, :r}, state) do
    Scheduler.refresh_now(state.selected_uid)
    {:noreply, %{state | loading: true}}
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}

  def handle_event({:resize, {width, _height}}, state), do: {:ok, resize_pane(state, width)}

  def handle_event(_event, state), do: {:noreply, state}

  def unmount(state) do
    stop_active_children(state.selected_uid)
    :ok
  end

  defp sidebar(%{sidebar: false}), do: []

  defp sidebar(state) do
    [
      vertical(
        [
          label(" Dashboards", class: :muted),
          option_list(Enum.map(state.dashboards, &{&1.title, &1.uid}),
            id: :dashboard_selector,
            selected: state.selected_uid,
            on_select: :select_dashboard,
            flex: 1
          )
        ],
        width: @sidebar_width
      )
    ]
  end

  defp right_panel_items(%{selected_uid: nil}) do
    [label("Select a dashboard from the left panel", class: :muted)]
  end

  defp right_panel_items(%{loading: true}) do
    [loading_indicator(running: true)]
  end

  defp right_panel_items(state) do
    GridMapper.to_tui_layout(state.selected_panels, state.prepared_panel_data,
      column_visibility: state.column_visibility,
      collapsed_rows: state.collapsed_rows,
      table_layouts: state.table_layouts,
      column_filter: state.column_filter
    )
  end

  defp pane_columns(width, true), do: max(1, width - @sidebar_width - 2)
  defp pane_columns(width, false), do: max(1, width - 1)

  defp resize_pane(state, nil), do: state

  defp resize_pane(state, width) do
    columns = pane_columns(width, state.sidebar)
    if state.selected_uid, do: Scheduler.set_columns(state.selected_uid, columns)
    %{state | width: width, columns: columns}
  end

  defp local_time do
    NaiveDateTime.local_now() |> NaiveDateTime.to_time() |> Time.truncate(:second)
  end

  defp start_children(dashboard, columns) do
    DynamicSupervisor.start_child(GrafExTerm.VarSupervisor, {Manager, dashboard})

    DynamicSupervisor.start_child(
      GrafExTerm.RefreshSupervisor,
      {Scheduler, {dashboard, columns: columns}}
    )
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

  defp initial_collapsed_rows(uid, panels) do
    stored = Store.get_collapsed_rows(uid)

    if MapSet.size(stored) > 0 do
      stored
    else
      panels
      |> Enum.filter(fn p -> p.type == "row" end)
      |> MapSet.new(fn p -> p.id end)
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

      existing ->
        existing
    end
  end

  defp refilter(state, filter) do
    panel_data =
      case DataCache.get(state.selected_uid) do
        %{panel_data: panel_data} -> panel_data
        nil -> %{}
      end

    prepared =
      Prepare.refilter(state.prepared_panel_data, panel_data, state.selected_panels, filter)

    %{state | prepared_panel_data: prepared, row_filter: filter}
  end

  defp extract_label_filter(rows) do
    excluded_keys = [:time, :value]

    Enum.map(rows, fn row ->
      row
      |> Map.drop(excluded_keys)
      |> Map.new(fn {key, val} -> {to_string(key), to_string(val)} end)
    end)
  end

  defp fetch_vars(uid) do
    Manager.get_values(uid)
  catch
    _, _ -> %{}
  end
end
