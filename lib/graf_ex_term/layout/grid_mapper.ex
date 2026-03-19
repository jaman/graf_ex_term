defmodule GrafExTerm.Layout.GridMapper do
  import Drafter.App, only: [horizontal: 2, vertical: 2]

  alias GrafExTerm.Panel.{Renderer, Row}

  def to_tui_layout(panels, panel_data, _variables \\ %{}, column_visibility \\ %{}, collapsed_rows \\ MapSet.new(), table_layouts \\ %{}) do
    height_ratio = Application.get_env(:graf_ex_term, :height_ratio, 3)

    panels
    |> Enum.sort_by(fn p -> {p.grid_pos.y, p.grid_pos.x} end)
    |> group_by_row_section()
    |> Enum.flat_map(fn section ->
      build_section_widgets(section, panel_data, height_ratio, column_visibility, collapsed_rows, table_layouts)
    end)
  end

  defp group_by_row_section(panels) do
    {sections, current_row, current_panels} =
      Enum.reduce(panels, {[], nil, []}, fn panel, {sections, current_row, current_panels} ->
        if panel.type == "row" do
          finished = if current_row || current_panels != [], do: [{current_row, current_panels}], else: []
          {sections ++ finished, panel, []}
        else
          {sections, current_row, current_panels ++ [panel]}
        end
      end)

    sections ++ [{current_row, current_panels}]
  end

  defp build_section_widgets({nil, panels}, panel_data, height_ratio, column_visibility, _collapsed_rows, table_layouts) do
    build_panel_row_widgets(panels, panel_data, height_ratio, column_visibility, table_layouts)
  end

  defp build_section_widgets({row_panel, panels}, panel_data, height_ratio, column_visibility, collapsed_rows, table_layouts) do
    collapsed = MapSet.member?(collapsed_rows, row_panel.id)
    row_widget = Row.render(row_panel, collapsed)

    if collapsed do
      [row_widget]
    else
      [row_widget | build_panel_row_widgets(panels, panel_data, height_ratio, column_visibility, table_layouts)]
    end
  end

  defp build_panel_row_widgets([], _panel_data, _height_ratio, _column_visibility, _table_layouts), do: []

  defp build_panel_row_widgets(panels, panel_data, height_ratio, column_visibility, table_layouts) do
    panels
    |> Enum.sort_by(fn p -> p.grid_pos.x end)
    |> Enum.group_by(fn p -> p.grid_pos.y end)
    |> Enum.sort_by(fn {y, _} -> y end)
    |> Enum.map(fn {_, row_panels} ->
      row_height =
        row_panels
        |> Enum.map(fn p -> p.grid_pos.h end)
        |> Enum.max(fn -> 8 end)
        |> Kernel.*(height_ratio)

      widgets =
        Enum.map(row_panels, fn panel ->
          data = Map.get(panel_data, panel.id, {:error, :no_data})
          widget = Renderer.render(panel, data, column_visibility, table_layouts)
          vertical([widget], colspan: panel.grid_pos.w)
        end)

      horizontal(widgets, gap: 1, height: row_height)
    end)
  end
end
