defmodule GrafExTerm.Test.Headless do
  @moduledoc false

  def start(app_module, props \\ %{}, opts \\ []) do
    Supervisor.terminate_child(Drafter.Supervisor, Drafter.ThemeManager)

    case Drafter.Test.Harness.start_app(app_module, props, opts) do
      {:ok, ctx} ->
        Process.sleep(50)
        ctx

      {:error, reason} ->
        Supervisor.restart_child(Drafter.Supervisor, Drafter.ThemeManager)
        raise "Failed to start headless app: #{inspect(reason)}"
    end
  end

  def stop(ctx) do
    try do
      Drafter.Test.Harness.stop_app(ctx)
    catch
      :exit, _ -> :ok
    end

    Supervisor.restart_child(Drafter.Supervisor, Drafter.ThemeManager)
    :ok
  end
end
