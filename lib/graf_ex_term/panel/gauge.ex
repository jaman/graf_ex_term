defmodule GrafExTerm.Panel.Gauge do
  import Drafter.App, only: [gauge: 1, horizontal: 2, placeholder: 1]

  def render(panel, {:ok, series}, _height) when series != [] do
    max_val = get_max(panel.field_config)

    gauges =
      Enum.map(series, fn s ->
        value = last_value(s.values)

        label =
          case Map.get(s, :name) do
            name when is_binary(name) and name != "" -> name
            _ -> panel.title
          end

        ratio = if max_val > 0, do: value / max_val, else: 0.0

        gauge(value: ratio, label: label, flex: 1, height: 8)
      end)

    horizontal(gauges, gap: 1)
  end

  def render(_panel, _, height) do
    placeholder(label: "No data", height: height)
  end

  defp last_value([]), do: 0.0

  defp last_value(values) do
    {_ts, val} = List.last(values)
    val * 1.0
  end

  defp get_max(field_config) do
    case get_in(field_config, ["defaults", "max"]) do
      nil -> 100.0
      max -> max * 1.0
    end
  end
end
