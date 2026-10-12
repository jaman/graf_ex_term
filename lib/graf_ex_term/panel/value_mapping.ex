defmodule GrafExTerm.Panel.ValueMapping do
  @moduledoc """
  Applies a panel's `fieldConfig.defaults.mappings` to a value, as Grafana's
  `getValueMappingResult` does: the first mapping that matches wins.

    * `"value"` — `options` maps the value, written as Grafana writes a number
      (`1`, `0.5`), to a result
    * `"range"` — `options.from`..`options.to`, either end optional, inclusive
    * `"regex"` — `options.pattern` (`/re/flags` or a plain pattern) against a string
      value; the result text may use `$1`-style groups
    * `"special"` — `options.match` of `"null"`, `"nan"`, `"null+nan"`, `"true"`,
      `"false"` or `"empty"`

  A result is the mapping's `%{"text" => ..., "color" => ...}` map, either key
  possibly absent.

      iex> mappings = [%{"type" => "value", "options" => %{"1" => %{"text" => "SUBSCRIBED", "color" => "green"}}}]
      iex> GrafExTerm.Panel.ValueMapping.result(mappings, 1.0)
      %{"text" => "SUBSCRIBED", "color" => "green"}

      iex> mappings = [%{"type" => "range", "options" => %{"from" => 90, "to" => nil, "result" => %{"text" => "HIGH"}}}]
      iex> GrafExTerm.Panel.ValueMapping.result(mappings, 95)
      %{"text" => "HIGH"}

  """

  @doc "The result of the first mapping in `mappings` matching `value`, or `nil`."
  @spec result([map()] | nil, term()) :: map() | nil
  def result(mappings, value) when is_list(mappings) do
    Enum.find_value(mappings, &match(&1, value))
  end

  def result(_mappings, _value), do: nil

  defp match(%{"type" => "value", "options" => options}, value)
       when value != nil and is_map(options),
       do: Map.get(options, key(value))

  defp match(%{"type" => "range", "options" => options}, value)
       when value != nil and is_map(options) do
    with number when is_number(number) <- to_number(value),
         true <- above?(number, options["from"]),
         true <- below?(number, options["to"]) do
      options["result"]
    else
      _no_match -> nil
    end
  end

  defp match(%{"type" => "regex", "options" => %{"pattern" => pattern} = options}, value)
       when is_binary(value) and is_binary(pattern) do
    with {:ok, regex} <- js_regex(pattern),
         true <- Regex.match?(regex, value) do
      replaced(options["result"] || %{}, regex, value)
    else
      _no_match -> nil
    end
  end

  defp match(%{"type" => "special", "options" => %{"match" => kind} = options}, value) do
    if special?(kind, value), do: options["result"]
  end

  defp match(_mapping, _value), do: nil

  defp special?("null", value), do: value == nil
  defp special?("nan", value), do: value == :nan
  defp special?("null+nan", value), do: value in [nil, :nan]
  defp special?("true", value), do: value in [true, "true"]
  defp special?("false", value), do: value in [false, "false"]
  defp special?("empty", value), do: value == ""
  defp special?(_kind, _value), do: false

  defp above?(_number, nil), do: true
  defp above?(number, from) when is_number(from), do: number >= from
  defp above?(_number, _from), do: true

  defp below?(_number, nil), do: true
  defp below?(number, to) when is_number(to), do: number <= to
  defp below?(_number, _to), do: true

  defp key(value) when is_float(value) and value == trunc(value),
    do: Integer.to_string(trunc(value))

  defp key(value) when is_number(value), do: to_string(value)
  defp key(value), do: to_string(value)

  defp to_number(value) when is_number(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp to_number(_value), do: nil

  defp js_regex("/" <> rest = pattern) do
    case Regex.run(~r{^(.*)/([a-z]*)$}s, rest) do
      [_, body, flags] -> Regex.compile(body, String.replace(flags, ~r/[^imsux]/, ""))
      nil -> Regex.compile(pattern)
    end
  end

  defp js_regex(pattern), do: Regex.compile(pattern)

  defp replaced(%{"text" => text} = result, regex, value) when is_binary(text) do
    %{result | "text" => Regex.replace(regex, value, String.replace(text, ~r/\$(\d)/, "\\\\\\1"))}
  end

  defp replaced(result, _regex, _value), do: result
end
