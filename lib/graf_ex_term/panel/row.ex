defmodule GrafExTerm.Panel.Row do
  import Drafter.App, only: [collapsible: 3]

  def render(panel, collapsed, panel_count \\ 0) do
    title =
      if collapsed and panel_count > 0 do
        "#{panel.title}  (#{panel_count} panels)"
      else
        panel.title
      end

    collapsible(
      title,
      [],
      id: :"row_#{panel.id}",
      content_height: 0,
      expanded: not collapsed,
      on_toggle: fn expanded ->
        send(:tui_app_loop, {:app_event, {:toggle_row, panel.id}, not expanded})
      end
    )
  end
end
