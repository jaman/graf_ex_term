defmodule GrafExTerm.Screen.AddDashboardModal do
  @moduledoc """
  Two-step Drafter modal for registering a dashboard.

  The first step takes a `file://` or `http(s)://` URI, typed or chosen with
  the file picker, and hands it to `GrafExTerm.Dashboard.Store.add/1`. A load
  or parse failure is shown inline and the modal stays open.

  The dashboard is registered as soon as the first step succeeds. The second
  step only collects datasource URLs: a Prometheus base URL overriding the
  global default, and one URL per datasource template variable the dashboard
  uses. Skipping it leaves the dashboard registered with no overrides.

  Both exits from the second step send `:refresh_dashboards` to the
  application loop so the list behind the modal reloads. Pops `:done` when
  saved or skipped, and `:cancelled` on `Esc` or the cancel button.
  """

  use Drafter.Screen

  alias Drafter.Widget.FilePicker
  alias GrafExTerm.Dashboard.Store

  def mount(_props) do
    %{
      uri: "",
      source: "",
      error: nil,
      loading: false,
      step: :uri_input,
      dashboard_uid: nil,
      datasource_vars: [],
      datasource_inputs: %{}
    }
  end

  def render(%{step: :uri_input} = state) do
    vertical(
      [
        label("Enter a dashboard URI or browse for a file:"),
        label("  file:///path/to/dashboard.json", class: :muted),
        label("  http://grafana:3000/api/dashboards/uid/abc", class: :muted),
        label(""),
        text_input(
          value: state.uri,
          placeholder: "URI...",
          on_change: :uri_changed,
          on_submit: :confirm
        ),
        label(""),
        if state.error do
          label("Error: #{state.error}", class: :error)
        else
          label("")
        end,
        label(""),
        horizontal(
          [
            button("Add", on_click: :confirm, variant: :primary),
            button("Browse...", on_click: :browse_file),
            button("Cancel", on_click: :cancel)
          ],
          gap: 2
        )
      ],
      padding: 1
    )
  end

  def render(%{step: :datasource_config} = state) do
    var_inputs =
      Enum.flat_map(state.datasource_vars, fn var_name ->
        [
          label("#{var_name}:"),
          text_input(
            placeholder: "http://prometheus:9090",
            on_change: {:datasource_url_changed, var_name},
            on_submit: :save_datasources
          ),
          label("")
        ]
      end)

    vertical(
      [
        label("Prometheus source (overrides global default):", style: %{bold: true}),
        text_input(
          value: state.source,
          placeholder: "http://prometheus:9090 (leave blank for global)",
          on_change: :source_changed,
          on_submit: :save_datasources
        ),
        label(""),
        if state.datasource_vars != [] do
          vertical([
            label("Additional datasource variables:", style: %{bold: true}),
            label(""),
            vertical(var_inputs)
          ])
        else
          label("")
        end,
        if state.error do
          label("Error: #{state.error}", class: :error)
        else
          label("")
        end,
        horizontal(
          [
            button("Save", on_click: :save_datasources, variant: :primary),
            button("Skip", on_click: :skip_datasources)
          ],
          gap: 2
        )
      ],
      padding: 1
    )
  end

  def handle_event(:uri_changed, {uri, _}, state) do
    {:ok, %{state | uri: uri, error: nil}}
  end

  def handle_event(:browse_file, _data, _state) do
    FilePicker.show(
      on_select: :file_picked,
      on_cancel: :browse_cancelled,
      filter: [".json"],
      title: "Open Dashboard JSON"
    )
  end

  def handle_event(:file_picked, path, state) do
    {:ok, %{state | uri: "file://#{path}", error: nil}}
  end

  def handle_event(:browse_cancelled, _data, state) do
    {:noreply, state}
  end

  def handle_event(:confirm, _data, state) do
    case String.trim(state.uri) do
      "" ->
        {:ok, %{state | error: "URI cannot be empty"}}

      uri ->
        case Store.add(uri) do
          {:ok, %{datasource_vars: vars, uid: uid}} ->
            {:ok, %{state | step: :datasource_config, datasource_vars: vars, dashboard_uid: uid}}

          {:error, reason} ->
            {:ok, %{state | error: inspect(reason)}}
        end
    end
  end

  def handle_event(:source_changed, {url, _}, state) do
    {:ok, %{state | source: url, error: nil}}
  end

  def handle_event({:datasource_url_changed, var_name}, {url, _}, state) do
    {:ok,
     %{state | datasource_inputs: Map.put(state.datasource_inputs, var_name, url), error: nil}}
  end

  def handle_event(:save_datasources, _data, state) do
    source = String.trim(state.source)

    if source != "" do
      Store.save_source(state.dashboard_uid, source)
    end

    if state.datasource_inputs != %{} do
      Store.save_datasource_map(state.dashboard_uid, state.datasource_inputs)
    end

    Drafter.AppRegistry.send_to_loop({:app_event, :refresh_dashboards, nil})
    {:pop, :done}
  end

  def handle_event(:skip_datasources, _data, _state) do
    Drafter.AppRegistry.send_to_loop({:app_event, :refresh_dashboards, nil})
    {:pop, :done}
  end

  def handle_event(:cancel, _data, _state) do
    {:pop, :cancelled}
  end

  def handle_event({:key, :escape}, _data, _state) do
    {:pop, :cancelled}
  end

  def handle_event(_event, _data, state) do
    {:noreply, state}
  end
end
