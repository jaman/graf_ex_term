defmodule GrafExTerm.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: GrafExTerm.PubSub},
        {Cachex, name: :graf_ex_term_dashboards},
        {Registry, keys: :unique, name: GrafExTerm.VarRegistry},
        {Registry, keys: :unique, name: GrafExTerm.RefreshRegistry},
        {DynamicSupervisor, name: GrafExTerm.VarSupervisor, strategy: :one_for_one},
        {DynamicSupervisor, name: GrafExTerm.RefreshSupervisor, strategy: :one_for_one},
        GrafExTerm.Refresh.DataCache,
        GrafExTerm.Dashboard.Store
      ] ++ entry_child()

    Supervisor.start_link(children, strategy: :one_for_one, name: GrafExTerm.Supervisor)
  end

  defp entry_child do
    if release?(), do: [{GrafExTerm.Entry, []}], else: []
  end

  defp release? do
    not Code.ensure_loaded?(Mix)
  end
end
