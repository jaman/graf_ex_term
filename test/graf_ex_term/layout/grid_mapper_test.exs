defmodule GrafExTerm.Layout.GridMapperTest do
  use ExUnit.Case, async: true

  alias GrafExTerm.Layout.GridMapper

  defp panel(id, type, x, y, w, h, title \\ "Panel") do
    %{
      id: id,
      type: type,
      title: title,
      grid_pos: %{x: x, y: y, w: w, h: h},
      field_config: %{},
      organize: nil,
      templating: []
    }
  end

  describe "to_tui_layout/2 basic structure" do
    test "returns a list of widget tuples" do
      panels = [panel(1, "timeseries", 0, 0, 24, 8)]
      result = GridMapper.to_tui_layout(panels, %{})
      assert is_list(result)
      assert result != []
    end

    test "groups panels on the same y-row into a single horizontal layout" do
      panels = [
        panel(1, "timeseries", 0, 0, 12, 8),
        panel(2, "timeseries", 12, 0, 12, 8)
      ]

      result = GridMapper.to_tui_layout(panels, %{})
      assert length(result) == 1
      [{:layout, :horizontal, children, _opts}] = result
      assert length(children) == 2
    end

    test "panels on different y rows produce multiple horizontal groups" do
      panels = [
        panel(1, "timeseries", 0, 0, 24, 8),
        panel(2, "timeseries", 0, 8, 24, 8)
      ]

      result = GridMapper.to_tui_layout(panels, %{})
      assert length(result) == 2
    end
  end

  describe "colspan proportional sizing" do
    test "full-width panel (w: 24) gets colspan 24" do
      panels = [panel(1, "timeseries", 0, 0, 24, 8)]
      result = GridMapper.to_tui_layout(panels, %{})
      [{:layout, :horizontal, [child], _}] = result
      {:layout, :vertical, _, opts} = child
      assert Keyword.get(opts, :colspan) == 24
    end

    test "panels share colspan proportional to grid_pos.w" do
      panels = [
        panel(1, "stat", 0, 0, 6, 4),
        panel(2, "timeseries", 6, 0, 18, 4)
      ]

      result = GridMapper.to_tui_layout(panels, %{})
      [{:layout, :horizontal, [stat_wrapper, ts_wrapper], _}] = result

      {:layout, :vertical, _, stat_opts} = stat_wrapper
      {:layout, :vertical, _, ts_opts} = ts_wrapper

      assert Keyword.get(stat_opts, :colspan) == 6
      assert Keyword.get(ts_opts, :colspan) == 18
    end

    test "equal panels get equal colspan" do
      panels = [
        panel(1, "stat", 0, 0, 8, 4),
        panel(2, "stat", 8, 0, 8, 4),
        panel(3, "stat", 16, 0, 8, 4)
      ]

      result = GridMapper.to_tui_layout(panels, %{})
      [{:layout, :horizontal, children, _}] = result

      colspans =
        Enum.map(children, fn {:layout, :vertical, _, opts} -> Keyword.get(opts, :colspan) end)

      assert colspans == [8, 8, 8]
    end
  end

  describe "row panels" do
    test "row panel is a collapsible holding its child panels" do
      row_panel = panel(0, "row", 0, 0, 24, 1, "My Section")
      child_panel = panel(1, "timeseries", 0, 1, 24, 8)

      assert [{:collapsible, "My Section", [{:layout, :horizontal, [_child], _}], _}] =
               GridMapper.to_tui_layout([row_panel, child_panel], %{})
    end

    test "collapsed row omits child panels" do
      row_panel = panel(0, "row", 0, 0, 24, 1, "Collapsed")
      child_panel = panel(1, "timeseries", 0, 1, 24, 8)
      collapsed = MapSet.new([0])

      result = GridMapper.to_tui_layout([row_panel, child_panel], %{}, collapsed_rows: collapsed)
      assert length(result) == 1
    end
  end

  describe "unknown panel types" do
    test "renders unknown panel types without crashing" do
      panels = [panel(1, "unknown_type", 0, 0, 24, 8)]
      assert is_list(GridMapper.to_tui_layout(panels, %{}))
    end
  end
end
