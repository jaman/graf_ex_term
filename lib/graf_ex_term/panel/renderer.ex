defmodule GrafExTerm.Panel.Renderer do
  @moduledoc false
  import Drafter.App, only: [collapsible: 3, label: 2, vertical: 2, placeholder: 1]

  alias GrafExTerm.Panel.{Bargauge, Gauge, Row, Stat, Table, Timeseries}

  def render(panel, data, column_visibility \\ %{}, table_layouts \\ %{}, table_expanded \\ true, column_filter \\ false) do
    height_ratio = Application.get_env(:graf_ex_term, :height_ratio, 3)
    height = panel.grid_pos.h * height_ratio
    render_panel(panel, data, height, column_visibility, table_layouts, table_expanded, column_filter)
  end

  defp render_panel(%{type: "stat"} = panel, data, height, _, _, _, _), do: Stat.render(panel, data, height)
  defp render_panel(%{type: "row"} = panel, _, _, _, _, _, _), do: Row.render(panel, false)
  defp render_panel(%{type: "timeseries"} = panel, data, height, _, _, _, _), do: Timeseries.render(panel, data, height)
  defp render_panel(%{type: "graph"} = panel, data, height, _, _, _, _), do: Timeseries.render(panel, data, height)
  defp render_panel(%{type: "gauge"} = panel, data, height, _, _, _, _), do: Gauge.render(panel, data, height)
  defp render_panel(%{type: "bargauge"} = panel, data, height, _, _, _, _), do: Bargauge.render(panel, data, height)
  defp render_panel(%{type: "text"} = panel, _, height, _, _, _, _), do: render_text(panel, height)

  defp render_panel(%{type: "table"} = panel, data, height, column_visibility, table_layouts, table_expanded, column_filter) do
    inner = Table.render(panel, data, height, Map.get(column_visibility, panel.id), Map.get(table_layouts, panel.id), column_filter)

    collapsible(panel.title, [inner],
      id: :"table_panel_#{panel.id}",
      content_height: height,
      expanded: table_expanded,
      on_toggle: {:toggle_table_panel, panel.id}
    )
  end

  defp render_panel(panel, _, height, _, _, _, _) do
    placeholder(label: "#{panel.type}: #{panel.title}", height: height)
  end

  defp render_text(panel, height) do
    content = get_in(panel.options, ["content"]) || ""
    text = content |> String.replace(~r/<[^>]+>/, "") |> String.trim()
    vertical([label(panel.title, style: %{bold: true}), label(text, [])], height: height)
  end
end
