defmodule GrafExTerm.Variable.Manager do
  use GenServer

  alias GrafExTerm.Variable.Substitution

  require Logger

  def start_link(dashboard) do
    name = {:via, Registry, {GrafExTerm.VarRegistry, dashboard.uid}}
    GenServer.start_link(__MODULE__, dashboard, name: name)
  end

  def get_values(dashboard_uid) do
    name = {:via, Registry, {GrafExTerm.VarRegistry, dashboard_uid}}
    GenServer.call(name, :get_values)
  end

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
    with {:ok, metric_selector, label_name} <- parse_label_values(query) do
      config = Map.get(datasources, "prometheus", %{url: "http://localhost:9090"})
      url = Map.fetch!(config, :url) <> "/api/v1/label/#{label_name}/values"
      params = if metric_selector != "", do: ["match[]": metric_selector], else: []

      case Req.get(url, params: params) do
        {:ok, %{body: %{"data" => values}}} when is_list(values) -> {:ok, values}
        other ->
          Logger.debug("Label values fetch failed url=#{url} result=#{inspect(other)}")
          {:error, :failed}
      end
    end
  end

  defp parse_label_values(query) do
    case Regex.run(~r/^label_values\((.+),\s*(\w+)\)\s*$/, String.trim(query)) do
      [_, metric_selector, label_name] -> {:ok, String.trim(metric_selector), label_name}
      _ ->
        case Regex.run(~r/^label_values\((\w+)\)\s*$/, String.trim(query)) do
          [_, label_name] -> {:ok, "", label_name}
          _ -> {:error, :not_label_values}
        end
    end
  end
end
