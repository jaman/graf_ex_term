defmodule GrafExTerm.Test.Headless do
  @moduledoc false

  alias Drafter.Supervisor, as: DrafterSupervisor
  alias Drafter.Test.Harness
  alias Drafter.ThemeManager

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
