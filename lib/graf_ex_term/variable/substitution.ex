defmodule GrafExTerm.Variable.Substitution do
  @grafana_builtins %{
    "__all" => ".*",
    "__interval" => "1m",
    "__interval_ms" => "60000",
    "__range" => "1h",
    "__range_s" => "3600",
    "__range_ms" => "3600000"
  }

  def substitute(expr, vars) when is_binary(expr) and is_map(vars) do
    result = Regex.replace(~r/\$\{?(\w+)\}?/, expr, fn _, name ->
      case Map.get(vars, name) do
        nil -> Map.get(@grafana_builtins, name, "$#{name}")
        value -> value
      end
    end)

    if result == expr do
      result
    else
      substitute(result, %{})
    end
  end
end
