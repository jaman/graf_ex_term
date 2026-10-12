defmodule GrafExTerm.Panel.Row do
  @moduledoc """
  Draws a Grafana row panel as a collapsible section header.

  A row owns the panels that follow it in the dashboard until the next row,
  and collapsing one both hides those panels and stops them being queried —
  the toggle is forwarded to `GrafExTerm.Refresh.Scheduler`, which skips
  panels under a collapsed row.
  """

  import Drafter.App, only: [collapsible: 3]

  @doc """
  Builds the collapsible widget for a row panel.

  `panel` is the row's `GrafExTerm.Dashboard.Types.Panel`; its `:id` becomes
  the widget id `:"row_<id>"`. `collapsed` is the row's current state, and the
  widget is drawn expanded when it is `false`.

  The header is drawn as the title followed by a line across the row, with the
  panel count at its right end. `panel_count` is how many panels the row
  contains; `0`, the default, shows no count.

  `children` are the already-built widgets for those panels, and
  `content_height` is their combined height in terminal rows. Both default to
  empty, which is what a collapsed row is given, since its children are not
  built at all.

  Toggling sends `{:app_event, {:toggle_row, panel.id}, collapsed?}` to the
  Drafter loop, so the screen must handle a `{:toggle_row, id}` event to make
  the toggle stick.
  """
  @spec render(
          GrafExTerm.Dashboard.Types.Panel.t(),
          boolean(),
          non_neg_integer(),
          list(),
          non_neg_integer()
        ) :: tuple()
  def render(panel, collapsed, panel_count \\ 0, children \\ [], content_height \\ 0) do
    collapsible(
      panel.title,
      children,
      id: :"row_#{panel.id}",
      rule: true,
      summary: panel_summary(panel_count),
      content_height: content_height,
      expanded: not collapsed,
      on_toggle: fn expanded ->
        Drafter.AppRegistry.send_to_loop({:app_event, {:toggle_row, panel.id}, not expanded})
      end
    )
  end

  defp panel_summary(0), do: nil
  defp panel_summary(1), do: "1 panel"
  defp panel_summary(count), do: "#{count} panels"
end
