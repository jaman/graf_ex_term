defmodule GrafExTerm.Panel.Renderer do
  alias GrafExTerm.Panel.{Stat, Table, Row, Timeseries, Gauge, Bargauge}

  def render(panel, data, column_visibility \\ %{}, table_layouts \\ %{}) do
    height_ratio = Application.get_env(:graf_ex_term, :height_ratio, 3)
    height = panel.grid_pos.h * height_ratio

    case panel.type do
      "stat" -> Stat.render(panel, data, height)
      "table" -> Table.render(panel, data, height, Map.get(column_visibility, panel.id), Map.get(table_layouts, panel.id))
      "row" -> Row.render(panel, false)
      "timeseries" -> Timeseries.render(panel, data, height)
      "graph" -> Timeseries.render(panel, data, height)
      "gauge" -> Gauge.render(panel, data, height)
      "bargauge" -> Bargauge.render(panel, data, height)
      _ -> render_unknown(panel, height)
    end
  end

  defp render_unknown(panel, height) do
    import Drafter.App, only: [placeholder: 1]
    placeholder(label: "#{panel.type}: #{panel.title}", height: height)
  end
end
