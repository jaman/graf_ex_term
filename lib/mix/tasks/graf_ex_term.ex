defmodule Mix.Tasks.GrafExTerm do
  @moduledoc """
  Runs the GrafExTerm terminal UI on your saved dashboards.

      mix graf_ex_term

  Starts the `:graf_ex_term` application and runs `GrafExTerm.run/1` until you
  quit. Datasources and settings come from `config/runtime.exs` and its
  environment variables (`PROMETHEUS`, `LOKI`, `GRAF_EX_TERM_*`). To try it
  without Prometheus, run `mix graf_ex_term.demo` instead.
  """

  use Mix.Task

  @shortdoc "Run the GrafExTerm terminal UI"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    GrafExTerm.run()
  end
end
