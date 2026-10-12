defmodule GrafExTerm.Dashboard.Visibility do
  @moduledoc """
  Which panels of a dashboard are on screen, given its collapsed rows.

  Panels are taken in grid order (`y`, then `x`). A row panel opens a section
  that runs to the next row panel; every panel in a collapsed row's section is
  hidden. Panels before the first row are always visible. Row panels themselves
  are never in the result.
  """

  alias GrafExTerm.Dashboard.Types.Panel

  @doc """
  Returns the `MapSet` of ids of the visible, non-row panels in `panels`.

  `collapsed_rows` is a `MapSet` of row panel ids.
  """
  @spec active_panel_ids([Panel.t()], MapSet.t()) :: MapSet.t()
  def active_panel_ids(panels, collapsed_rows) do
    panels
    |> Enum.sort_by(fn p -> {p.grid_pos.y, p.grid_pos.x} end)
    |> Enum.reduce({MapSet.new(), false}, &classify_panel(&1, &2, collapsed_rows))
    |> elem(0)
  end

  defp classify_panel(%{type: "row"} = panel, {acc, _}, collapsed_rows) do
    {acc, MapSet.member?(collapsed_rows, panel.id)}
  end

  defp classify_panel(_panel, {acc, true}, _collapsed_rows), do: {acc, true}

  defp classify_panel(panel, {acc, false}, _collapsed_rows),
    do: {MapSet.put(acc, panel.id), false}
end
