defmodule Mix.Tasks.GrafExTerm.Demo do
  @moduledoc """
  Runs GrafExTerm on the showcase dashboard with generated data.

      mix graf_ex_term.demo

  No Prometheus or Loki is needed and the saved dashboard list is left alone;
  see `GrafExTerm.Demo`.
  """

  use Mix.Task

  @shortdoc "Run GrafExTerm on a showcase dashboard with generated data"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    GrafExTerm.Demo.run()
  end
end
