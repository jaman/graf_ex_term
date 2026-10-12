defmodule GrafExTerm.Panel.Stat.Reading do
  @moduledoc """
  What a stat panel shows for a value: the text, the unit beside it and the
  colour, as Grafana works them out.

  A value mapping that matches (`GrafExTerm.Panel.ValueMapping`) supplies the
  text and, when it has one, the colour. Otherwise the value is formatted for
  the panel's `fieldConfig.defaults.unit` and `decimals` by
  `GrafExTerm.Format`, the unit kept apart from the number. The colour is the
  mapping's, else that of the last threshold step the value reaches, else
  `{200, 200, 200}`.

      iex> panel = %{field_config: %{"defaults" => %{"unit" => "s"}}}
      iex> GrafExTerm.Panel.Stat.Reading.of(panel, 49)
      %{text: "49", unit: "s", color: {200, 200, 200}}

  """

  alias GrafExTerm.Format
  alias GrafExTerm.Panel.{ColorRules, ValueMapping}

  @default_color {200, 200, 200}

  @type t :: %{text: String.t(), unit: String.t(), color: {byte(), byte(), byte()}}

  @doc "The reading for `value` on `panel`, a map with a `:field_config`."
  @spec of(map(), number()) :: t()
  def of(panel, value) do
    defaults = get_in(panel.field_config, ["defaults"]) || %{}
    mapping = ValueMapping.result(defaults["mappings"], value)

    {text, unit} = text_and_unit(mapping, value, defaults)
    color = mapped_color(mapping) || threshold_color(defaults, value)
    %{text: text, unit: unit, color: color}
  end

  defp text_and_unit(%{"text" => text}, _value, _defaults) when is_binary(text) and text != "",
    do: {text, ""}

  defp text_and_unit(_mapping, value, defaults) do
    formatted = Format.format(value, defaults["unit"], decimals(defaults["decimals"]))
    {formatted.prefix <> formatted.text, String.trim(formatted.suffix)}
  end

  defp decimals(decimals) when is_integer(decimals), do: decimals
  defp decimals(_none), do: nil

  defp mapped_color(%{"color" => color}), do: ColorRules.resolve_named_color(color)
  defp mapped_color(_mapping), do: nil

  defp threshold_color(defaults, value) do
    defaults
    |> get_in(["thresholds", "steps"])
    |> List.wrap()
    |> Enum.filter(fn step -> reached?(Map.get(step, "value"), value) end)
    |> List.last()
    |> case do
      nil -> @default_color
      step -> ColorRules.resolve_named_color(Map.get(step, "color", "green")) || @default_color
    end
  end

  defp reached?(nil, _value), do: true
  defp reached?(threshold, value) when is_number(threshold), do: value >= threshold
  defp reached?(_threshold, _value), do: false
end
