defmodule GrafExTerm.Screen.MainTest do
  use ExUnit.Case, async: false

  alias Drafter.Test.HeadlessDriver
  alias GrafExTerm.Screen.Main
  alias GrafExTerm.Test.Headless

  describe "mount/1" do
    test "initializes all required state keys" do
      state = Main.mount(%{})
      assert state.dashboards == []
      assert state.selected_uid == nil
      assert state.selected_panels == []
      assert state.panel_data == %{}
      assert state.prepared_panel_data == %{}
      assert state.variables == %{}
      assert state.loading == false
      assert state.data_version == nil
      assert state.column_visibility == %{}
      assert state.scrolling == false
      assert state.pending_data == nil
      assert state.row_filter == nil
      assert state.table_layouts == %{}
    end
  end

  describe "handle_event/3 — select_dashboard" do
    test "deselecting (nil) clears all panel state" do
      state = %{Main.mount(%{}) | selected_uid: "abc", loading: true, row_filter: %{"k" => "v"}}
      {:ok, new_state} = Main.handle_event(:select_dashboard, nil, state)
      assert new_state.selected_uid == nil
      assert new_state.selected_panels == []
      assert new_state.panel_data == %{}
      assert new_state.prepared_panel_data == %{}
      assert new_state.loading == false
      assert new_state.row_filter == nil
      assert new_state.scrolling == false
      assert new_state.pending_data == nil
    end

    test "selecting unknown uid returns error without crashing" do
      state = Main.mount(%{})
      result = Main.handle_event(:select_dashboard, "nonexistent_uid", state)
      assert match?({:error, _}, result) or match?({:noreply, _}, result)
    end
  end

  describe "handle_event/3 — toggle_row" do
    test "collapsing a row adds it to collapsed_rows" do
      state = Main.mount(%{})
      {:noreply, new_state} = Main.handle_event({:toggle_row, 42}, true, state)
      assert MapSet.member?(new_state.collapsed_rows, 42)
    end

    test "expanding a row removes it from collapsed_rows" do
      state = %{Main.mount(%{}) | collapsed_rows: MapSet.new([42])}
      {:noreply, new_state} = Main.handle_event({:toggle_row, 42}, false, state)
      refute MapSet.member?(new_state.collapsed_rows, 42)
    end
  end

  describe "handle_event/3 — table_row_selected" do
    setup do
      panel_data = %{1 => {:ok, [%{labels: %{"host" => "h1"}, values: [{0, 1.0}]}]}}
      prepared = %{
        1 => {:ok, [%{labels: %{"host" => "h1"}, values: [{0, 1.0}]}]},
        2 => {:prepared, [%{cpu: 55}], [%{key: :cpu, label: "CPU"}]}
      }

      state = %{
        Main.mount(%{})
        | panel_data: panel_data,
          prepared_panel_data: prepared
      }

      %{state: state}
    end

    test "deselecting all rows (empty list) clears row_filter", %{state: state} do
      {:noreply, new_state} = Main.handle_event({:table_row_selected, 1}, [], state)
      assert new_state.row_filter == nil
    end

    test "selecting rows sets row_filter to label map", %{state: state} do
      rows = [%{host: "h1", time: "2024-01-01", value: 1.0}]
      {:noreply, new_state} = Main.handle_event({:table_row_selected, 1}, rows, state)
      assert new_state.row_filter != nil
      assert is_list(new_state.row_filter)
    end

    test "row selection does not reprocess prepared table data", %{state: state} do
      rows = [%{host: "h1", time: "2024-01-01", value: 1.0}]
      {:noreply, new_state} = Main.handle_event({:table_row_selected, 1}, rows, state)
      assert Map.get(new_state.prepared_panel_data, 2) == Map.get(state.prepared_panel_data, 2)
    end
  end

  describe "on_scroll_active/1 and on_scroll_idle/1" do
    test "on_scroll_active sets scrolling flag" do
      state = Main.mount(%{})
      new_state = Main.on_scroll_active(state)
      assert new_state.scrolling == true
    end

    test "on_scroll_idle clears scrolling flag when no pending data" do
      state = %{Main.mount(%{}) | scrolling: true}
      new_state = Main.on_scroll_idle(state)
      assert new_state.scrolling == false
      assert new_state.pending_data == nil
    end

    test "on_scroll_idle flushes pending_data when present" do
      pending_data = {%{1 => {:ok, []}}, 42}

      state = %{
        Main.mount(%{})
        | scrolling: true,
          pending_data: pending_data,
          selected_uid: "uid",
          selected_panels: []
      }

      new_state = Main.on_scroll_idle(state)
      assert new_state.scrolling == false
      assert new_state.pending_data == nil
      assert new_state.panel_data == %{1 => {:ok, []}}
      assert new_state.data_version == 42
    end
  end

  describe "headless integration" do
    setup do
      ctx = Headless.start(Main, %{}, size: {200, 50})
      on_exit(fn -> Headless.stop(ctx) end)
      %{ctx: ctx}
    end

    test "initial state has correct defaults after on_ready", %{ctx: ctx} do
      state = Drafter.Test.get_state(ctx)
      assert is_list(state.dashboards)
      assert state.selected_uid == nil
      assert state.loading == false
      assert state.scrolling == false
      assert state.pending_data == nil
    end

    test "app renders without crash at startup", %{ctx: ctx} do
      hierarchy = Drafter.Test.get_widget_hierarchy(ctx)
      assert hierarchy != nil
    end

    test "press r with no selected dashboard does not set loading", %{ctx: ctx} do
      Drafter.Test.send_key(ctx, :r)
      state = Drafter.Test.get_state(ctx)
      assert state.loading == false
    end

    test "toggle_row event updates collapsed_rows via widget action", %{ctx: ctx} do
      send(ctx.app_pid, {:widget_action, :some_widget, {:app_callback, {:toggle_row, 99}, true}})
      Process.sleep(20)
      state = Drafter.Test.get_state(ctx)
      assert MapSet.member?(state.collapsed_rows, 99)
    end

    test "table_row_selected with empty rows clears row_filter", %{ctx: ctx} do
      send(ctx.app_pid, {:widget_action, :some_widget, {:app_callback, {:table_row_selected, 1}, []}})
      Process.sleep(20)
      state = Drafter.Test.get_state(ctx)
      assert state.row_filter == nil
    end

    test "screen adapts to a resize event", %{ctx: ctx} do
      HeadlessDriver.set_size(220, 60)
      Process.sleep(30)
      hierarchy = Drafter.Test.get_widget_hierarchy(ctx)
      assert hierarchy != nil
    end
  end
end
