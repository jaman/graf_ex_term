defmodule GrafExTerm.Layout.GridMapper do
  @moduledoc false
  import Drafter.App, only: [horizontal: 2, vertical: 2]

  alias GrafExTerm.Panel.{Renderer, Row}

  def to_tui_layout(
        panels,
        panel_data,
        _variables \\ %{},
        column_visibility \\ %{},
        collapsed_rows \\ MapSet.new(),
        table_layouts \\ %{},
        collapsed_table_panels \\ MapSet.new(),
        all_tables_collapsed \\ false
      ) do
    height_ratio = Application.get_env(:graf_ex_term, :height_ratio, 3)

    panels
    |> group_by_row_section()
    |> Enum.flat_map(fn section ->
      build_section_widgets(
        section, panel_data, height_ratio, column_visibility,
        collapsed_rows, table_layouts, collapsed_table_panels,
        all_tables_collapsed
      )
    end)
  end

  defp group_by_row_section(panels) do
    {sections, current_row, current_panels} =
      Enum.reduce(panels, {[], nil, []}, fn panel, {sections, current_row, current_panels} ->
        classify_panel(panel, sections, current_row, current_panels)
      end)

    sections ++ [{current_row, current_panels}]
  end

  defp classify_panel(%{type: "row"} = panel, sections, current_row, current_panels) do
    finished =
      if current_row || current_panels != [],
        do: [{current_row, current_panels}],
        else: []

    {sections ++ finished, panel, []}
  end

  defp classify_panel(panel, sections, current_row, current_panels) do
    {sections, current_row, current_panels ++ [panel]}
  end

  defp build_section_widgets(
         {nil, panels}, panel_data, height_ratio, column_visibility,
         _collapsed_rows, table_layouts, collapsed_table_panels,
         all_tables_collapsed
       ) do
    build_panel_row_widgets(
      panels, panel_data, height_ratio, column_visibility,
      table_layouts, collapsed_table_panels, all_tables_collapsed
    )
  end

  defp build_section_widgets(
         {row_panel, panels}, panel_data, height_ratio, column_visibility,
         collapsed_rows, table_layouts, collapsed_table_panels,
         all_tables_collapsed
       ) do
    collapsed = MapSet.member?(collapsed_rows, row_panel.id)

    {children, content_height} =
      build_panel_row_widgets_with_height(
        panels, panel_data, height_ratio, column_visibility,
        table_layouts, collapsed_table_panels, all_tables_collapsed
      )
    [Row.render(row_panel, collapsed, length(panels), children, content_height)]
  end

  defp build_panel_row_widgets([], _panel_data, _height_ratio, _column_visibility, _table_layouts, _collapsed_table_panels, _all_tables_collapsed), do: []

  defp build_panel_row_widgets(
         panels, panel_data, height_ratio, column_visibility,
         table_layouts, collapsed_table_panels, all_tables_collapsed
       ) do
    {widgets, _} =
      build_panel_row_widgets_with_height(
        panels, panel_data, height_ratio, column_visibility,
        table_layouts, collapsed_table_panels, all_tables_collapsed
      )
    widgets
  end

  defp build_panel_row_widgets_with_height([], _panel_data, _height_ratio, _column_visibility, _table_layouts, _collapsed_table_panels, _all_tables_collapsed), do: {[], 0}

  defp build_panel_row_widgets_with_height(panels, panel_data, height_ratio, column_visibility, table_layouts, collapsed_table_panels, all_tables_collapsed) do
    rows =
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
            table_expanded = not (all_tables_collapsed or MapSet.member?(collapsed_table_panels, panel.id))
            widget = Renderer.render(panel, data, column_visibility, table_layouts, table_expanded)
            vertical([widget], colspan: panel.grid_pos.w)
          end)

        {horizontal(widgets, gap: 1, height: row_height), row_height}
      end)

    {Enum.map(rows, &elem(&1, 0)), rows |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
  end
end
