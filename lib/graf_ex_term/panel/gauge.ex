defmodule GrafExTerm.Panel.Gauge do
  import Drafter.App, only: [progress_bar: 1, placeholder: 1]

  def render(panel, {:ok, series}, _height) do
    value = extract_last_value(series)
    max_val = get_max(panel.field_config)
    unit = get_in(panel.field_config, ["defaults", "unit"]) || ""
    formatted = format_value(value, unit)

    progress_bar(
      progress: value,
      max_value: max_val,
      label: "#{panel.title}: #{formatted}",
      show_percentage: true
    )
  end

  def render(_panel, _, height) do
    placeholder(label: "No data", height: height)
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

  defp get_max(field_config) do
    field_config
    |> get_in(["defaults", "max"])
    |> case do
      nil -> 100
      max -> max
    end
  end

  defp format_value(value, "") when is_float(value), do: Float.round(value, 2) |> to_string()
  defp format_value(value, unit) when is_float(value), do: "#{Float.round(value, 2)} #{unit}"
  defp format_value(value, ""), do: to_string(value)
  defp format_value(value, unit), do: "#{value} #{unit}"
end
