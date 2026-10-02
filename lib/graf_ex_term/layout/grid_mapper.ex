defmodule GrafExTerm.Layout.GridMapper do
  @moduledoc """
  Maps a Grafana panel grid onto a stack of Drafter layout widgets.

  Grafana positions panels on a 24-column grid by `x`, `y`, `w` and `h`. This
  module reproduces that: panels sharing a `y` become one horizontal band, in
  `x` order, each wrapped in a vertical carrying its `w` as a colspan so the
  terminal splits width in the same proportions. Bands are emitted in `y`
  order.

  Rows partition the list. Panels following a row panel, up to the next row,
  are built as that row's collapsible children; panels before any row are
  emitted at the top level. A collapsed row's children are not built at all.
  """

  import Drafter.App, only: [horizontal: 2, vertical: 2]

  alias GrafExTerm.Panel.{Renderer, Row}

  @doc """
  Builds the widget list for `panels`.

  `panels` is a dashboard's flat panel list, rows inline, as
  `GrafExTerm.Dashboard.Parser` produces it. `panel_data` maps panel id to
  that panel's cached data; a panel with no entry is rendered from
  `{:error, :no_data}`.

  The remaining arguments are optional:

    * `_variables` — accepted and ignored.
    * `column_visibility` — map of panel id to a `MapSet` of table column keys
      to show. Defaults to `%{}`, showing all.
    * `collapsed_rows` — `MapSet` of row panel ids that are collapsed.
      Defaults to an empty set.
    * `table_layouts` — map of panel id to saved column widths and order.
      Defaults to `%{}`.
    * `collapsed_table_panels` — `MapSet` of table panel ids drawn collapsed.
      Defaults to an empty set.
    * `all_tables_collapsed` — when `true`, collapses every table panel
      regardless of `collapsed_table_panels`. Defaults to `false`.
    * `column_filter` — draws the per-column checkbox selector above each
      table. Defaults to `false`.

  Row height is the tallest `grid_pos.h` in the band multiplied by the
  `:height_ratio` application environment value, which defaults to `3`.

  Returns a list of Drafter widget tuples, ready to place inside a scrollable.
  """
  @spec to_tui_layout(
          [GrafExTerm.Dashboard.Types.Panel.t()],
          map(),
          map(),
          map(),
          MapSet.t(),
          map(),
          MapSet.t(),
          boolean(),
          boolean()
        ) :: [tuple()]
  def to_tui_layout(
        panels,
        panel_data,
        _variables \\ %{},
        column_visibility \\ %{},
        collapsed_rows \\ MapSet.new(),
        table_layouts \\ %{},
        collapsed_table_panels \\ MapSet.new(),
        all_tables_collapsed \\ false,
        column_filter \\ false
      ) do
    height_ratio = Application.get_env(:graf_ex_term, :height_ratio, 3)

    panels
    |> group_by_row_section()
    |> Enum.flat_map(fn section ->
      build_section_widgets(
        section,
        panel_data,
        height_ratio,
        column_visibility,
        collapsed_rows,
        table_layouts,
        collapsed_table_panels,
        all_tables_collapsed,
        column_filter
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
         {nil, panels},
         panel_data,
         height_ratio,
         column_visibility,
         _collapsed_rows,
         table_layouts,
         collapsed_table_panels,
         all_tables_collapsed,
         column_filter
       ) do
    build_panel_row_widgets(
      panels,
      panel_data,
      height_ratio,
      column_visibility,
      table_layouts,
      collapsed_table_panels,
      all_tables_collapsed,
      column_filter
    )
  end

  defp build_section_widgets(
         {row_panel, panels},
         panel_data,
         height_ratio,
         column_visibility,
         collapsed_rows,
         table_layouts,
         collapsed_table_panels,
         all_tables_collapsed,
         column_filter
       ) do
    collapsed = MapSet.member?(collapsed_rows, row_panel.id)

    {children, content_height} =
      build_panel_row_widgets_with_height(
        panels,
        panel_data,
        height_ratio,
        column_visibility,
        table_layouts,
        collapsed_table_panels,
        all_tables_collapsed,
        column_filter
      )

    [Row.render(row_panel, collapsed, length(panels), children, content_height)]
  end

  defp build_panel_row_widgets(
         [],
         _panel_data,
         _height_ratio,
         _column_visibility,
         _table_layouts,
         _collapsed_table_panels,
         _all_tables_collapsed,
         _column_filter
       ),
       do: []

  defp build_panel_row_widgets(
         panels,
         panel_data,
         height_ratio,
         column_visibility,
         table_layouts,
         collapsed_table_panels,
         all_tables_collapsed,
         column_filter
       ) do
    {widgets, _} =
      build_panel_row_widgets_with_height(
        panels,
        panel_data,
        height_ratio,
        column_visibility,
        table_layouts,
        collapsed_table_panels,
        all_tables_collapsed,
        column_filter
      )

    widgets
  end

  defp build_panel_row_widgets_with_height(
         [],
         _panel_data,
         _height_ratio,
         _column_visibility,
         _table_layouts,
         _collapsed_table_panels,
         _all_tables_collapsed,
         _column_filter
       ),
       do: {[], 0}

  defp build_panel_row_widgets_with_height(
         panels,
         panel_data,
         height_ratio,
         column_visibility,
         table_layouts,
         collapsed_table_panels,
         all_tables_collapsed,
         column_filter
       ) do
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

            table_expanded =
              not (all_tables_collapsed or MapSet.member?(collapsed_table_panels, panel.id))

            widget =
              Renderer.render(
                panel,
                data,
                column_visibility,
                table_layouts,
                table_expanded,
                column_filter
              )

            vertical([widget], colspan: panel.grid_pos.w)
          end)

        {horizontal(widgets, gap: 1), row_height}
      end)

    {Enum.map(rows, &elem(&1, 0)), rows |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
  end
end
