defmodule GrafExTerm.Variable.Manager do
  @moduledoc """
  Per-dashboard process holding the current value of each template variable.

  One is started under `GrafExTerm.VarSupervisor` for each dashboard the user
  opens and registered in `GrafExTerm.VarRegistry` under the dashboard uid, so
  callers address it by uid rather than pid. Opening a dashboard starts it and
  leaving stops it; calling into it for a dashboard that is not open exits.

  At start every `"query"` variable whose saved value is empty is resolved
  against Prometheus, or against `GrafExTerm.Datasource.Demo` when the
  `"prometheus"` datasource config has `type: :demo`. Only the
  `label_values(selector, label)` and
  `label_values(label)` forms are understood, and the first returned value is
  taken; any other query, or a failed lookup, leaves the variable empty.
  Variables resolve in declaration order and each sees the ones before it, so
  a variable may reference an earlier one.

  Changing a value broadcasts `{:variables_changed, uid, values}` on the
  `"dashboard:<uid>"` PubSub topic. It does not trigger a refetch;
  `GrafExTerm.Refresh.Scheduler` picks the new values up on its next fetch.
  """

  use GenServer

  alias GrafExTerm.Datasource.Demo
  alias GrafExTerm.Variable.Substitution

  require Logger

  @doc """
  Starts a manager for `dashboard` and resolves its variables.

  `dashboard` is a `GrafExTerm.Dashboard.Types.Dashboard`. The process is
  registered under `dashboard.uid`, so starting a second one for the same uid
  returns `{:error, {:already_started, pid}}`.

  Resolution happens in `init/1`, which issues HTTP requests, so this call
  blocks for as long as those take.
  """
  @spec start_link(GrafExTerm.Dashboard.Types.Dashboard.t()) :: GenServer.on_start()
  def start_link(dashboard) do
    name = {:via, Registry, {GrafExTerm.VarRegistry, dashboard.uid}}
    GenServer.start_link(__MODULE__, dashboard, name: name)
  end

  @doc """
  Returns the current variable values for `dashboard_uid` as a map of name to
  string.

  Exits if no manager is running for that dashboard.
  """
  @spec get_values(String.t()) :: %{String.t() => String.t()}
  def get_values(dashboard_uid) do
    name = {:via, Registry, {GrafExTerm.VarRegistry, dashboard_uid}}
    GenServer.call(name, :get_values)
  end

  @doc """
  Sets `var_name` to `value` and broadcasts the change.

  `var_name` is the variable name without the `$` sigil and `value` is the
  replacement string. A name the dashboard never declared is accepted and
  stored.

  Subscribers to `"dashboard:<uid>"` receive
  `{:variables_changed, uid, values}` carrying the full map. Exits if no
  manager is running for that dashboard.
  """
  @spec set_value(String.t(), String.t(), String.t()) :: :ok
  def set_value(dashboard_uid, var_name, value) do
    name = {:via, Registry, {GrafExTerm.VarRegistry, dashboard_uid}}
    GenServer.call(name, {:set_value, var_name, value})
  end

  @impl GenServer
  def init(dashboard) do
    datasources = Application.get_env(:graf_ex_term, :datasources, %{})
    values = resolve_vars(dashboard.templating, datasources)
    Logger.debug("Variable.Manager initialized values=#{inspect(values)}")
    {:ok, %{dashboard_uid: dashboard.uid, values: values}}
  end

  @impl GenServer
  def handle_call(:get_values, _from, state) do
    {:reply, state.values, state}
  end

  def handle_call({:set_value, var_name, value}, _from, state) do
    new_values = Map.put(state.values, var_name, value)
    new_state = %{state | values: new_values}

    Phoenix.PubSub.broadcast(
      GrafExTerm.PubSub,
      "dashboard:#{state.dashboard_uid}",
      {:variables_changed, state.dashboard_uid, new_values}
    )

    {:reply, :ok, new_state}
  end

  defp resolve_vars(template_vars, datasources) do
    Enum.reduce(template_vars, %{}, fn var, acc ->
      value = resolve_var(var, acc, datasources)
      Map.put(acc, var.name, value)
    end)
  end

  defp resolve_var(%{type: "query", current_value: "", query: query}, acc, datasources)
       when is_binary(query) and query != "" do
    substituted = Substitution.substitute(query, acc)

    case fetch_label_values(substituted, datasources) do
      {:ok, [first | _]} ->
        Logger.debug("Variable resolved query=#{query} value=#{first}")
        first

      other ->
        Logger.debug("Variable unresolved query=#{query} result=#{inspect(other)}")
        ""
    end
  end

  defp resolve_var(var, _acc, _datasources), do: var.current_value

  defp fetch_label_values(query, datasources) do
    config = Map.get(datasources, "prometheus", %{url: "http://localhost:9090"})

    with {:ok, metric_selector, label_name} <- parse_label_values(query) do
      label_values(config, metric_selector, label_name)
    end
  end

  defp label_values(%{type: :demo}, _metric_selector, label_name) do
    {:ok, Demo.label_values(label_name)}
  end

  defp label_values(config, metric_selector, label_name) do
    url = Map.fetch!(config, :url) <> "/api/v1/label/#{label_name}/values"
    params = if metric_selector != "", do: ["match[]": metric_selector], else: []

    case Req.get(url, params: params) do
      {:ok, %{body: %{"data" => values}}} when is_list(values) ->
        {:ok, values}

      other ->
        Logger.debug("Label values fetch failed url=#{url} result=#{inspect(other)}")
        {:error, :failed}
    end
  end

  defp parse_label_values(query) do
    case Regex.run(~r/^label_values\((.+),\s*(\w+)\)\s*$/, String.trim(query)) do
      [_, metric_selector, label_name] ->
        {:ok, String.trim(metric_selector), label_name}

      _ ->
        case Regex.run(~r/^label_values\((\w+)\)\s*$/, String.trim(query)) do
          [_, label_name] -> {:ok, "", label_name}
          _ -> {:error, :not_label_values}
        end
    end
  end
end
