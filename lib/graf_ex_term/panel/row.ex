defmodule GrafExTerm.Panel.Row do
  @moduledoc false
  import Drafter.App, only: [collapsible: 3]

  def render(panel, collapsed, panel_count \\ 0, children \\ [], content_height \\ 0) do
    title =
      if collapsed and panel_count > 0 do
        "#{panel.title}  (#{panel_count} panels)"
      else
        panel.title
      end

    collapsible(
      title,
      children,
      id: :"row_#{panel.id}",
      content_height: content_height,
      expanded: not collapsed,
      on_toggle: fn expanded ->
        send(:tui_app_loop, {:app_event, {:toggle_row, panel.id}, not expanded})
      end
    )
  end
end
