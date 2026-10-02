defmodule GrafExTerm.Panel.Renderer do
  @moduledoc """
  Dispatches a panel to the module that draws its type.

  This is the single place that maps a Grafana panel type onto a widget
  module, and the place that converts Grafana grid height into terminal rows.
  An unrecognised type draws a placeholder naming the type and title rather
  than failing.
  """

  import Drafter.App, only: [collapsible: 3, label: 2, vertical: 2, placeholder: 1]

  alias GrafExTerm.Panel.{Bargauge, Gauge, Row, Stat, Table, Timeseries}

  @doc """
  Builds the widget for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`. `data` is that panel's
  entry from the cache: `{:ok, series}`, `{:table, columns, rows}`,
  `{:prepared, rows, columns}`, `{:prepared_ts, map}`, or an `{:error,
  reason}` which every renderer draws as a "No data" placeholder.

  The remaining arguments only affect table panels:

    * `column_visibility` — map of panel id to a `MapSet` of column keys to
      show. A panel absent from the map, or mapped to an empty set, shows all
      its columns. Defaults to `%{}`.
    * `table_layouts` — map of panel id to `%{col_widths: ..., col_order:
      ...}` captured from user resizing. Defaults to `%{}`.
    * `table_expanded` — whether the table's collapsible wrapper starts open.
      Defaults to `true`.
    * `column_filter` — whether to draw the per-column checkbox selector above
      the table, which costs rows from the table's own height. Defaults to
      `false`.

  Panel height is `panel.grid_pos.h` multiplied by the `:height_ratio`
  application environment value, which defaults to `3`.

  Returns a Drafter widget tuple.
  """
  @spec render(
          GrafExTerm.Dashboard.Types.Panel.t(),
          term(),
          map(),
          map(),
          boolean(),
          boolean()
        ) :: tuple()
  def render(
        panel,
        data,
        column_visibility \\ %{},
        table_layouts \\ %{},
        table_expanded \\ true,
        column_filter \\ false
      ) do
    height_ratio = Application.get_env(:graf_ex_term, :height_ratio, 3)
    height = panel.grid_pos.h * height_ratio

    render_panel(
      panel,
      data,
      height,
      column_visibility,
      table_layouts,
      table_expanded,
      column_filter
    )
  end

  defp render_panel(%{type: "stat"} = panel, data, height, _, _, _, _),
    do: Stat.render(panel, data, height)

  defp render_panel(%{type: "row"} = panel, _, _, _, _, _, _), do: Row.render(panel, false)

  defp render_panel(%{type: "timeseries"} = panel, data, height, _, _, _, _),
    do: Timeseries.render(panel, data, height)

  defp render_panel(%{type: "graph"} = panel, data, height, _, _, _, _),
    do: Timeseries.render(panel, data, height)

  defp render_panel(%{type: "gauge"} = panel, data, height, _, _, _, _),
    do: Gauge.render(panel, data, height)

  defp render_panel(%{type: "bargauge"} = panel, data, height, _, _, _, _),
    do: Bargauge.render(panel, data, height)

  defp render_panel(%{type: "text"} = panel, _, height, _, _, _, _),
    do: render_text(panel, height)

  defp render_panel(
         %{type: "table"} = panel,
         data,
         height,
         column_visibility,
         table_layouts,
         table_expanded,
         column_filter
       ) do
    inner =
      Table.render(
        panel,
        data,
        height,
        Map.get(column_visibility, panel.id),
        Map.get(table_layouts, panel.id),
        column_filter
      )

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
