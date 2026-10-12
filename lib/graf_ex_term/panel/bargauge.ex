defmodule GrafExTerm.Panel.Bargauge do
  @moduledoc """
  Draws a Grafana `bargauge` panel as one labelled meter per series, stacked
  vertically.

  Each meter shows the series reduced by the panel's
  `options.reduceOptions.calcs` (see `GrafExTerm.Panel.Reduce`) as a fraction
  of `fieldConfig.defaults.min`..`max`, which default to `0`..`100`. The fill
  is coloured by the panel's threshold steps; a panel without thresholds uses
  the meter's own green, amber and red bands.
  """

  import Drafter.App, only: [vertical: 1, meter: 1, placeholder: 1]

  alias GrafExTerm.Panel.{ColorRules, Reduce}

  @rows_per_meter 2

  @doc """
  Builds the meter widgets for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`. `data` must be
  `{:ok, series}` with at least one series; every other value, including
  `{:ok, []}`, draws a "No data" placeholder of `height` rows.

  Each meter takes two rows, so `height` caps the number of series drawn and
  series beyond that are dropped rather than overflowing. Meters are labelled
  with the series `:name`, falling back to its label values joined with
  `", "`.
  """
  @spec render(GrafExTerm.Dashboard.Types.Panel.t(), term(), non_neg_integer()) :: tuple()
  def render(panel, {:ok, series}, height) when series != [] do
    {min_val, max_val} = bounds(panel.field_config)
    calc = Reduce.calc(panel)
    thresholds = meter_thresholds(panel.field_config, min_val, max_val)

    series
    |> Enum.take(max(1, div(height, @rows_per_meter)))
    |> Enum.map(fn s ->
      value = Reduce.value(s.values, calc)

      meter(
        [
          value: fraction(value, min_val, max_val),
          label: "#{series_label(s)}  #{format_value(value)}"
        ] ++ thresholds
      )
    end)
    |> vertical()
  end

  def render(_panel, _, height) do
    placeholder(label: "No data", height: height)
  end

  defp bounds(field_config) do
    defaults = Map.get(field_config, "defaults", %{})
    min_val = number_or(Map.get(defaults, "min"), 0)
    max_val = number_or(Map.get(defaults, "max"), 100)
    if max_val > min_val, do: {min_val, max_val}, else: {min_val, min_val + 1}
  end

  defp number_or(value, _default) when is_number(value), do: value
  defp number_or(_value, default), do: default

  defp fraction(value, min_val, max_val), do: (value - min_val) / (max_val - min_val)

  defp meter_thresholds(field_config, min_val, max_val) do
    steps = ColorRules.threshold_steps(field_config)

    if Enum.any?(steps, fn {value, color} -> is_number(value) and color != nil end) do
      [thresholds: step_bands(steps, min_val, max_val)]
    else
      []
    end
  end

  defp step_bands(steps, min_val, max_val) do
    colors = Enum.map(steps, fn {_value, color} -> color || {115, 191, 105} end)

    starts =
      steps |> tl() |> Enum.map(fn {value, _} -> fraction(value || min_val, min_val, max_val) end)

    Enum.zip(starts ++ [1.0], colors)
  end

  defp series_label(s) do
    case Map.get(s, :name) do
      name when is_binary(name) and name != "" -> name
      _ -> s.labels |> Map.values() |> Enum.join(", ")
    end
  end

  defp format_value(value) when abs(value) >= 100, do: :erlang.float_to_binary(value, decimals: 0)
  defp format_value(value), do: :erlang.float_to_binary(value, decimals: 2)
end
