defmodule GrafExTerm.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: GrafExTerm.PubSub},
      {Cachex, name: :graf_ex_term_dashboards},
      {Registry, keys: :unique, name: GrafExTerm.VarRegistry},
      {Registry, keys: :unique, name: GrafExTerm.RefreshRegistry},
      {DynamicSupervisor, name: GrafExTerm.VarSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: GrafExTerm.RefreshSupervisor, strategy: :one_for_one},
      GrafExTerm.Refresh.DataCache,
      GrafExTerm.Dashboard.Store
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: GrafExTerm.Supervisor)
  end
end
