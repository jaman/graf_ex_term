defmodule GrafExTerm.Panel.StatTest do
  use ExUnit.Case, async: true

  alias GrafExTerm.Dashboard.Types.Panel
  alias GrafExTerm.Panel.Stat

  doctest GrafExTerm.Panel.GrafanaColor

  defp panel(step_color, graph_mode) do
    %Panel{
      id: 1,
      title: "Load",
      type: "stat",
      grid_pos: %{x: 0, y: 0, w: 6, h: 4},
      targets: [],
      options: %{"graphMode" => graph_mode},
      field_config: %{
        "defaults" => %{
          "thresholds" => %{
            "steps" => [%{"value" => nil, "color" => step_color}]
          }
        }
      }
    }
  end

  @series [%{labels: %{}, values: [{0, 1.0}, {15, 2.0}]}]

  test "a threshold colour that names no colour draws the number instead of crashing" do
    for graph_mode <- ["area", "none"] do
      assert is_tuple(Stat.render(panel("text", graph_mode), {:ok, @series}, 6))
    end
  end

  test "a threshold colour written as rgba() draws in that colour" do
    widget = Stat.render(panel("rgba(50, 172, 45, 0.97)", "none"), {:ok, @series}, 6)
    assert inspect(widget) =~ "{50, 172, 45}"
  end
end
