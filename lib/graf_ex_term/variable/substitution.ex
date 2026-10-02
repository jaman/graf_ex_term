defmodule GrafExTerm.Variable.Substitution do
  @moduledoc """
  Replaces Grafana `$var` placeholders in a query expression with values.

      GrafExTerm.Variable.Substitution.substitute(
        "rate(http_requests_total{job=\\"$job\\"}[$__interval])",
        %{"job" => "api"}
      )
  """

  @grafana_builtins %{
    "__all" => ".*",
    "__interval" => "1m",
    "__interval_ms" => "60000",
    "__range" => "1h",
    "__range_s" => "3600",
    "__range_ms" => "3600000"
  }

  @doc """
  Expands every `$name` and `${name}` in `expr`.

  `expr` must be a binary. `vars` must be a map of variable name (without the
  sigil) to replacement string; names it does not carry fall back to the
  built-in table `__all`, `__interval`, `__interval_ms`, `__range`,
  `__range_s` and `__range_ms`. A placeholder matching neither is left as
  `$name`, so an unresolvable expression reaches the datasource intact rather
  than becoming silently malformed.

  Substitution repeats until the string stops changing, so a value that itself
  contains a placeholder is expanded too. Later passes see no variables, only
  the built-ins, so a value cannot reintroduce a caller-supplied name.

  Returns the expanded binary.
  """
  @spec substitute(String.t(), %{String.t() => String.t()}) :: String.t()
  def substitute(expr, vars) when is_binary(expr) and is_map(vars) do
    result =
      Regex.replace(~r/\$\{?(\w+)\}?/, expr, fn _, name ->
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
