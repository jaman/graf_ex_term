defmodule GrafExTerm.Panel.Graphics do
  @moduledoc """
  The renderer graphical panels (timeseries, heatmap, pie chart and gauge) draw
  with.

  It is the `:chart_renderer` application environment value (`GRAF_EX_TERM_RENDERER`),
  or `:auto` when that is unset: an image on a terminal with kitty, iTerm2 or sixel
  graphics, braille elsewhere. See `Drafter.Widget.Chart` for the values.
  """

  @doc "The renderer graphical panels pass to their Drafter widget as `:renderer`."
  @spec renderer() :: atom()
  def renderer, do: Application.get_env(:graf_ex_term, :chart_renderer) || :auto
end
