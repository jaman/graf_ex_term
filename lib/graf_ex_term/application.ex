defmodule GrafExTerm.Application do
  @moduledoc """
  OTP application callback for `:graf_ex_term`.

  Starts the PubSub used to announce refreshes, the registries and dynamic
  supervisors under which per-dashboard variable managers and refresh
  schedulers run, the data cache, and the dashboard store, which owns the
  table of parsed dashboards. Drafter's bundled FIGlet fonts are registered
  first, so stat panels can size their numbers with them.

  `GrafExTerm.Entry` is started only when the `__BURRITO` environment variable
  is set, which is how a packaged release launches the UI on boot. Under `mix`
  the tree comes up without it and a caller invokes `GrafExTerm.run/1`.

  Startup progress is appended to `/tmp/graf_ex_term_debug.log`.
  """

  use Application

  alias Drafter.Widget.Digits.Figlet

  @debug_log "/tmp/graf_ex_term_debug.log"

  @impl true
  def start(_type, _args) do
    Figlet.register_bundled()

    debug(
      "Application.start called, __BURRITO=#{inspect(System.get_env("__BURRITO"))}, release?=#{release?()}"
    )

    children =
      [
        {Phoenix.PubSub, name: GrafExTerm.PubSub},
        {Registry, keys: :unique, name: GrafExTerm.VarRegistry},
        {Registry, keys: :unique, name: GrafExTerm.RefreshRegistry},
        {DynamicSupervisor, name: GrafExTerm.VarSupervisor, strategy: :one_for_one},
        {DynamicSupervisor, name: GrafExTerm.RefreshSupervisor, strategy: :one_for_one},
        GrafExTerm.Refresh.DataCache,
        GrafExTerm.Dashboard.Store
      ] ++ entry_child()

    debug("children=#{inspect(length(children))}, entry_included?=#{release?()}")

    Supervisor.start_link(children, strategy: :one_for_one, name: GrafExTerm.Supervisor)
  end

  defp entry_child do
    if release?(), do: [{GrafExTerm.Entry, []}], else: []
  end

  defp release? do
    System.get_env("__BURRITO") != nil
  end

  defp debug(msg) do
    File.write!(@debug_log, "#{DateTime.utc_now()} #{msg}\n", [:append])
  end
end
