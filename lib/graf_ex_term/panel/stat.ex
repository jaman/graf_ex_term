defmodule GrafExTerm.Panel.Stat do
  import Drafter.App, only: [vertical: 2, label: 2, digits: 2, placeholder: 1]

  alias Drafter.Format
  alias GrafExTerm.Panel.ColorRules

  def render(panel, {:ok, series}, height) do
    value = extract_last_value(series)
    unit = get_in(panel.field_config, ["defaults", "unit"]) || ""
    formatted = format_value(value, unit)
    color = threshold_color(panel.field_config, value)
    graph_mode = get_in(panel.options, ["graphMode"]) || "none"

    digit_opts =
      if graph_mode == "area" do
        hist = extract_history(series)
        {bg_min, bg_max} = data_range(panel.field_config)
        [size: :small, style: %{fg: color}, bg_data: hist, color: color, bg_min: bg_min, bg_max: bg_max]
      else
        [size: :small, style: %{fg: color}]
      end

    vertical([
      label(panel.title, style: %{bold: true}),
      digits(formatted, digit_opts)
    ], height: height)
  end

  def render(panel, _, height) do
    vertical([
      label(panel.title, style: %{bold: true}),
      placeholder(label: "No data", height: height - 1)
    ], height: height)
  end

  defp extract_last_value([]), do: 0.0

  defp extract_last_value(series) do
    series
    |> List.first()
    |> Map.get(:values, [])
    |> List.last()
    |> case do
      nil -> 0.0
      {_, val} -> val
    end
  end

  defp extract_history([]), do: []

  defp extract_history(series) do
    series
    |> List.first()
    |> Map.get(:values, [])
    |> Enum.map(fn {_, val} -> val end)
  end

  defp data_range(field_config) do
    defaults = get_in(field_config, ["defaults"]) || %{}
    min = Map.get(defaults, "min")
    max = Map.get(defaults, "max")
    {if(is_number(min), do: min, else: 0), if(is_number(max), do: max, else: nil)}
  end

  defp format_value(value, unit) when is_number(value) do
    case unit do
      "percent" -> Format.percent(value, decimals: 1)
      "percentunit" -> Format.percent(value, as_ratio: true, decimals: 1)
      "bytes" -> Format.bytes(value)
      "decbytes" -> Format.bytes(value)
      "bits" -> Format.bytes(trunc(value / 8))
      "short" -> Format.compact(value)
      "s" -> format_duration(value)
      "ms" -> format_duration(value / 1000)
      "ns" -> format_duration(value / 1_000_000_000)
      _ -> Format.compact(value)
    end
  end

  defp format_duration(seconds) when is_number(seconds) do
    cond do
      seconds >= 7 * 24 * 3600 -> "#{Float.round(seconds / (7 * 24 * 3600), 1)}w"
      seconds >= 24 * 3600 -> "#{Float.round(seconds / (24 * 3600), 1)}d"
      seconds >= 3600 -> "#{Float.round(seconds / 3600, 1)}h"
      seconds >= 60 -> "#{Float.round(seconds / 60, 1)}m"
      true -> "#{Float.round(seconds * 1.0, 1)}s"
    end
  end

  defp format_value(value, _unit), do: to_string(value)

  defp threshold_color(field_config, value) do
    steps =
      field_config
      |> get_in(["defaults", "thresholds", "steps"])
      |> List.wrap()

    steps
    |> Enum.filter(fn step ->
      threshold = Map.get(step, "value")
      is_nil(threshold) or value >= threshold
    end)
    |> List.last()
    |> case do
      nil -> {200, 200, 200}
      step -> ColorRules.resolve_named_color(Map.get(step, "color", "green"))
    end
  end
end
