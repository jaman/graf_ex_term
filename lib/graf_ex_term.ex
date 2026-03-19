defmodule GrafExTerm do
  def run(opts \\ []) do
    Drafter.run(GrafExTerm.Screen.Main, opts)
  end
end
