defmodule GrafExTerm.Panel.Row do
  import Drafter.App, only: [collapsible: 3]

  def render(panel, collapsed) do
    collapsible(
      panel.title,
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
