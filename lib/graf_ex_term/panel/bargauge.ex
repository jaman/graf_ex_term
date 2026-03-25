defmodule GrafExTerm.Panel.Bargauge do
  @moduledoc false
  import Drafter.App, only: [vertical: 1, horizontal: 2, label: 1, progress_bar: 1, placeholder: 1]

  def render(panel, {:ok, series}, height) when series != [] do
    max_val = get_max(panel.field_config)

    bars =
      series
      |> Enum.take(height)
      |> Enum.map(fn s ->
        value = last_value(s.values)
        series_label = case Map.get(s, :name) do
          name when is_binary(name) and name != "" -> name
          _ -> s.labels |> Map.values() |> Enum.join(", ")
        end

        horizontal([
          label(series_label),
          progress_bar(progress: value, max_value: max_val, show_percentage: true)
        ], gap: 1)
      end)

    vertical(bars)
  end

  def render(_panel, _, height) do
    placeholder(label: "No data", height: height)
  end

  defp last_value([]), do: 0.0

  defp last_value(values) do
    {_ts, val} = List.last(values)
    val
  end

  defp get_max(field_config) do
    field_config
    |> get_in(["defaults", "max"])
    |> case do
      nil -> 100
      max -> max
    end
  end
end
