defmodule GrafExTerm.Test.Headless do
  @moduledoc """
  Starts and stops a Drafter app in tests without a terminal.

  Drafter's `ThemeManager` writes to the terminal, so it is terminated for the
  duration of the app under test and restarted afterwards. Tests using this
  must run with `async: false`, since the theme manager is global.

  Always pair `start/3` with `stop/1`, normally through `on_exit/1`, or the
  theme manager stays down for the rest of the run.

      setup do
        ctx = GrafExTerm.Test.Headless.start(MyScreen, %{}, size: {200, 50})
        on_exit(fn -> GrafExTerm.Test.Headless.stop(ctx) end)
        %{ctx: ctx}
      end
  """

  alias Drafter.Supervisor, as: DrafterSupervisor
  alias Drafter.Test.Harness
  alias Drafter.ThemeManager

  @doc """
  Starts `app_module` headlessly and returns the harness context.

  `props` is the mount props map, defaulting to `%{}`. `opts` is passed to
  `Drafter.Test.Harness.start_app/3`; `size: {cols, rows}` sets the virtual
  terminal size. Defaults to `[]`.

  Sleeps 50 ms after starting so the app's `on_ready/1` has run before the
  context is returned. Restores the theme manager and raises if the app fails
  to start.
  """
  def start(app_module, props \\ %{}, opts \\ []) do
    Supervisor.terminate_child(DrafterSupervisor, ThemeManager)

    case Harness.start_app(app_module, props, opts) do
      {:ok, ctx} ->
        Process.sleep(50)
        ctx

      {:error, reason} ->
        Supervisor.restart_child(DrafterSupervisor, ThemeManager)
        raise "Failed to start headless app: #{inspect(reason)}"
    end
  end

  @doc """
  Stops the app in `ctx` and restarts Drafter's theme manager.

  Returns `:ok`. An app that has already exited is not an error.
  """
  def stop(ctx) do
    try do
      Harness.stop_app(ctx)
    catch
      :exit, _ -> :ok
    end

    Supervisor.restart_child(DrafterSupervisor, ThemeManager)
    :ok
  end
end
