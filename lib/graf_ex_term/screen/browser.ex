defmodule GrafExTerm.Screen.Browser do
  @moduledoc """
  Drafter screen listing the dashboards held by
  `GrafExTerm.Dashboard.Registry` and opening the chosen one.

  Selecting an entry pushes `GrafExTerm.Screen.Viewer` with the parsed
  dashboard. `r` reloads the list from the registry and `q` quits.

  The registry is not supervised by `GrafExTerm.Application`, so it must
  already be running; the list is empty otherwise.
  """

  use Drafter.App

  def mount(_props) do
    dashboards = GrafExTerm.Dashboard.Registry.list()
    %{dashboards: dashboards}
  end

  def render(state) do
    items = Enum.map(state.dashboards, fn d -> {d.title, d.uid} end)

    vertical([
      header("graf_ex_term  ▸  Dashboards"),
      scrollable(
        [
          radio_set(items,
            id: :dashboard_browser,
            on_change: :open_dashboard,
            height: length(items)
          )
        ],
        flex: 1
      ),
      footer(
        bindings: [
          {"Enter", "open"},
          {"r", "refresh"},
          {"q", "quit"}
        ]
      )
    ])
  end

  def handle_event(:open_dashboard, uid, state) do
    dashboard = Enum.find(state.dashboards, fn d -> d.uid == uid end)

    case dashboard do
      nil -> {:noreply, state}
      d -> push_screen(GrafExTerm.Screen.Viewer, %{dashboard: d})
    end
  end

  def handle_event(event, _data, state) when is_tuple(event), do: handle_event(event, state)
  def handle_event(_event, _data, state), do: {:noreply, state}

  def handle_event({:key, :r}, state) do
    dashboards = GrafExTerm.Dashboard.Registry.list()
    {:ok, %{state | dashboards: dashboards}}
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end
