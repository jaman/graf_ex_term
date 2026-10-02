defmodule GrafExTerm.Screen.Viewer do
  @moduledoc """
  Full-screen Drafter screen showing one dashboard, pushed onto the stack by
  `GrafExTerm.Screen.Browser`.

  Mounting starts a `GrafExTerm.Variable.Manager` and a
  `GrafExTerm.Refresh.Scheduler` for the dashboard; leaving the screen, by
  `Esc` or unmount, stops both.

  Data is polled from `GrafExTerm.Refresh.DataCache` every 500 ms rather than
  driven by PubSub, and only rebuilt when the cache version changes. Table
  panels are prepared on arrival; other panel types are rendered from raw
  cache data.

  Props: `%{dashboard: dashboard}`, a parsed
  `GrafExTerm.Dashboard.Types.Dashboard`.

  Key bindings: `r` refreshes, `Esc` returns to the caller, `q` quits.

  Column visibility, collapsed rows and collapsed tables live only in screen
  state; nothing here is persisted to `GrafExTerm.Dashboard.Store`.
  """

  use Drafter.App

  alias GrafExTerm.Layout.GridMapper
  alias GrafExTerm.Panel.Table
  alias GrafExTerm.Refresh.{DataCache, Scheduler}
  alias GrafExTerm.Variable.Manager

  def mount(%{dashboard: dashboard}) do
    DynamicSupervisor.start_child(
      GrafExTerm.VarSupervisor,
      {Manager, dashboard}
    )

    DynamicSupervisor.start_child(
      GrafExTerm.RefreshSupervisor,
      {Scheduler, dashboard}
    )

    %{
      dashboard: dashboard,
      panel_data: %{},
      prepared_panel_data: %{},
      variables: initial_variables(dashboard),
      loading: true,
      data_version: nil,
      column_visibility: %{},
      collapsed_rows: MapSet.new(),
      collapsed_table_panels: MapSet.new(),
      all_tables_collapsed: false
    }
  end

  def on_ready(state) do
    send(self(), {:set_interval, 500, :poll_data})
    state
  end

  def on_timer(:poll_data, state) do
    uid = state.dashboard.uid

    case DataCache.take_if_updated(uid, state.data_version) do
      :unchanged ->
        state

      {:updated, %{panel_data: panel_data, version: version}} ->
        vars = fetch_vars(uid)
        prepared = prepare_panel_data(panel_data, state.dashboard.panels)

        %{
          state
          | panel_data: panel_data,
            prepared_panel_data: prepared,
            variables: vars,
            loading: false,
            data_version: version
        }
    end
  end

  def on_timer(_timer_id, state), do: state

  def render(state) do
    content =
      if state.loading do
        [loading_indicator(running: true)]
      else
        [
          GridMapper.to_tui_layout(
            state.dashboard.panels,
            state.prepared_panel_data,
            state.variables,
            state.column_visibility,
            state.collapsed_rows,
            %{},
            state.collapsed_table_panels,
            state.all_tables_collapsed
          )
        ]
      end

    vertical([
      header("graf_ex_term  ▸  #{state.dashboard.title}"),
      checkbox("Collapse all tables",
        id: :collapse_all_tables,
        checked: state.all_tables_collapsed,
        on_change: :toggle_all_tables
      ),
      scrollable(content, flex: 1),
      footer(
        bindings: [
          {"r", "refresh"},
          {"Esc", "back"},
          {"q", "quit"}
        ]
      )
    ])
  end

  def handle_event({:var_changed, var_name}, value, state) do
    Manager.set_value(state.dashboard.uid, var_name, value)
    {:noreply, %{state | variables: Map.put(state.variables, var_name, value)}}
  end

  def handle_event({:toggle_column, panel_id, col_key}, checked, state) do
    current = current_column_set(state, panel_id)
    new_set = if checked, do: MapSet.put(current, col_key), else: MapSet.delete(current, col_key)
    {:noreply, %{state | column_visibility: Map.put(state.column_visibility, panel_id, new_set)}}
  end

  def handle_event(:toggle_all_tables, checked, state) do
    {:noreply, %{state | all_tables_collapsed: checked, collapsed_table_panels: MapSet.new()}}
  end

  def handle_event({:toggle_table_panel, panel_id}, collapsed, state) do
    new_set =
      if collapsed,
        do: MapSet.put(state.collapsed_table_panels, panel_id),
        else: MapSet.delete(state.collapsed_table_panels, panel_id)

    {:noreply, %{state | collapsed_table_panels: new_set}}
  end

  def handle_event({:toggle_row, row_id}, collapsed, state) do
    new_collapsed =
      if collapsed,
        do: MapSet.put(state.collapsed_rows, row_id),
        else: MapSet.delete(state.collapsed_rows, row_id)

    {:noreply, %{state | collapsed_rows: new_collapsed}}
  end

  def handle_event(event, _data, state) when is_tuple(event), do: handle_event(event, state)
  def handle_event(_event, _data, state), do: {:noreply, state}

  def handle_event({:key, ?r}, state), do: handle_event({:key, :r}, state)

  def handle_event({:key, :r}, state) do
    Scheduler.refresh_now(state.dashboard.uid)
    {:noreply, %{state | loading: true}}
  end

  def handle_event({:key, :escape}, state) do
    stop_children(state.dashboard.uid)
    {:pop, nil}
  end

  def handle_event({:key, :escape, _mods}, state) do
    stop_children(state.dashboard.uid)
    {:pop, nil}
  end

  def handle_event({:key, ?q}, _state), do: {:stop, :normal}
  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  def unmount(state) do
    stop_children(state.dashboard.uid)
    :ok
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

  defp prepare_panel_data(panel_data, panels) do
    table_ids =
      panels
      |> Enum.filter(fn p -> p.type in ["table"] end)
      |> MapSet.new(fn p -> p.id end)

    Map.new(panel_data, fn {panel_id, data} ->
      if MapSet.member?(table_ids, panel_id) do
        {rows, cols} = Table.prepare(data)
        {panel_id, {:prepared, rows, cols}}
      else
        {panel_id, data}
      end
    end)
  end

  defp fetch_vars(dashboard_uid) do
    Manager.get_values(dashboard_uid)
  catch
    _, _ -> %{}
  end

  defp stop_children(dashboard_uid) do
    case Registry.lookup(GrafExTerm.RefreshRegistry, dashboard_uid) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(GrafExTerm.RefreshSupervisor, pid)
      _ -> :ok
    end

    case Registry.lookup(GrafExTerm.VarRegistry, dashboard_uid) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(GrafExTerm.VarSupervisor, pid)
      _ -> :ok
    end
  end
end
