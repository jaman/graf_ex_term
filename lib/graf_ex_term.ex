defmodule GrafExTerm do
  @moduledoc false
  def run(opts \\ []) do
    Drafter.run(GrafExTerm.Screen.Main, opts)
  end
end
