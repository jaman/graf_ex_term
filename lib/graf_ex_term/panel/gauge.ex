defmodule GrafExTerm.Panel.Gauge do
  @moduledoc """
  Draws a Grafana `gauge` panel as one dial per series, side by side.
  """

  import Drafter.App, only: [gauge: 1, horizontal: 2, placeholder: 1]

  alias GrafExTerm.Panel.Graphics

  @doc """
  Builds the gauge widgets for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`. `data` must be
  `{:ok, series}` with at least one series; every other value, including
  `{:ok, []}`, draws a "No data" placeholder of `height` rows.

  Each series contributes one dial showing its last sample as a fraction of
  the panel's `fieldConfig.defaults.max`, which defaults to `100.0`. A max of
  zero or less renders every dial at zero rather than dividing by it. The dial
  is labelled with the series `:name`, falling back to the panel title when
  the series has none.

  `height` is used only for the placeholder; dials are a fixed 8 rows tall.
  """
  @spec render(GrafExTerm.Dashboard.Types.Panel.t(), term(), non_neg_integer()) :: tuple()
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

        gauge(
          value: ratio,
          label: label,
          flex: 1,
          height: 8,
          renderer: Graphics.renderer()
        )
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
