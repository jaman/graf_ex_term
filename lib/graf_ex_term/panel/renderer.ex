defmodule GrafExTerm.Panel.Renderer do
  @moduledoc """
  Dispatches a panel to the module that draws its type.

  This is the single place that maps a Grafana panel type onto a widget
  module. An unrecognised type draws a placeholder naming the type and title
  rather than failing.

  Every panel except rows and tables is drawn inside a rounded frame carrying
  the panel title in its top border; the frame takes two of the panel's rows,
  and is drawn in the theme's primary colour while the panel has focus.
  Rows and tables keep their collapsible header as their title.
  """

  import Drafter.App, only: [box: 2, collapsible: 3, label: 2, placeholder: 1]

  alias GrafExTerm.Panel.{Bargauge, Gauge, Heatmap, Logs, Piechart, Row, Stat, Table, Timeseries}

  @doc """
  Builds the widget for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`. `data` is that panel's
  entry from the cache or from `GrafExTerm.Panel.Prepare`: `{:ok, series}`,
  `{:table, columns, rows}`, `{:logs, entries}`, one of the `:prepared*`
  forms, or an `{:error, reason}` which every renderer draws as a "No data"
  placeholder.

  Options:

    * `:height` — widget height in terminal rows. Defaults to
      `panel.grid_pos.h` times the `:height_ratio` application environment
      value, which defaults to `3`.
    * `:column_visibility` — map of panel id to a `MapSet` of column keys to
      show. A panel absent from the map, or mapped to an empty set, shows all
      its columns. Defaults to `%{}`.
    * `:table_layouts` — map of panel id to `%{col_widths: ..., col_order:
      ...}` captured from user resizing. Defaults to `%{}`.
    * `:table_expanded` — whether a table's collapsible wrapper starts open.
      Defaults to `true`.
    * `:column_filter` — whether to draw the per-column checkbox selector above
      a table, which costs rows from the table's own height. Defaults to
      `false`.

  Returns a Drafter widget tuple.
  """
  @spec render(GrafExTerm.Dashboard.Types.Panel.t(), term(), keyword()) :: tuple()
  def render(panel, data, opts \\ []) do
    height =
      Keyword.get_lazy(opts, :height, fn ->
        panel.grid_pos.h * Application.get_env(:graf_ex_term, :height_ratio, 3)
      end)

    frame(panel, data, height, opts)
  end

  @frame_rows 2

  defp frame(%{type: type} = panel, data, height, opts) when type in ["row", "table"],
    do: render_panel(panel, data, height, opts)

  defp frame(panel, data, height, opts) do
    box([render_panel(panel, data, max(1, height - @frame_rows), opts)],
      title: " #{panel.title} ",
      border: :rounded,
      padding: 0,
      highlight_focus: true
    )
  end

  defp render_panel(%{type: "stat"} = panel, data, height, _opts),
    do: Stat.render(panel, data, height)

  defp render_panel(%{type: "row"} = panel, _data, _height, _opts), do: Row.render(panel, false)

  defp render_panel(%{type: type} = panel, data, height, _opts)
       when type in ["timeseries", "graph"],
       do: Timeseries.render(panel, data, height)

  defp render_panel(%{type: "gauge"} = panel, data, height, _opts),
    do: Gauge.render(panel, data, height)

  defp render_panel(%{type: "bargauge"} = panel, data, height, _opts),
    do: Bargauge.render(panel, data, height)

  defp render_panel(%{type: "piechart"} = panel, data, height, _opts),
    do: Piechart.render(panel, data, height)

  defp render_panel(%{type: "heatmap"} = panel, data, height, _opts),
    do: Heatmap.render(panel, data, height)

  defp render_panel(%{type: "logs"} = panel, data, height, _opts),
    do: Logs.render(panel, data, height)

  defp render_panel(%{type: "text"} = panel, _data, height, _opts), do: render_text(panel, height)

  defp render_panel(%{type: "table"} = panel, data, height, opts) do
    inner =
      Table.render(
        panel,
        data,
        height,
        opts |> Keyword.get(:column_visibility, %{}) |> Map.get(panel.id),
        opts |> Keyword.get(:table_layouts, %{}) |> Map.get(panel.id),
        Keyword.get(opts, :column_filter, false)
      )

    collapsible(panel.title, [inner],
      id: :"table_panel_#{panel.id}",
      content_height: height,
      expanded: Keyword.get(opts, :table_expanded, true),
      on_toggle: {:toggle_table_panel, panel.id}
    )
  end

  defp render_panel(panel, _data, height, _opts) do
    placeholder(label: "#{panel.type}: #{panel.title}", height: height)
  end

  defp render_text(panel, height) do
    content = get_in(panel.options, ["content"]) || ""
    text = content |> String.replace(~r/<[^>]+>/, "") |> String.trim()
    label(text, height: height)
  end
end
