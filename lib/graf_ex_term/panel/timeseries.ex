defmodule GrafExTerm.Panel.Timeseries do
  @moduledoc false
  import Drafter.App, only: [chart: 2, placeholder: 1]

  @palette [
    {100, 200, 255},
    {255, 130, 80},
    {80, 255, 150},
    {255, 100, 180},
    {200, 180, 60},
    {180, 100, 255}
  ]

  @spec prepare(map(), {:ok, list()} | any()) :: {:prepared_ts, map()} | any()
  def prepare(panel, {:ok, series}) do
    unit = get_in(panel.field_config, ["defaults", "unit"]) || ""
    {scaled_series, unit_axis_opts} = scale_for_unit(series, unit)
    sorted = sort_largest_first(scaled_series)
    values = extract_values(sorted)
    type = chart_type(panel)

    has_weights = Enum.any?(sorted, fn s -> Map.get(s, :weight, 1) > 1 end)
    num_series = length(sorted)

    braille_opts =
      if type == :braille_area do
        fill = cond do
          has_weights -> 0.6
          num_series > 3 -> 0.6
          true -> 1.0
        end

        [show_baseline: true, fill_opacity: fill, zero_center: :independent]
      else
        []
      end

    opts =
      [chart_type: type] ++
        braille_opts ++
        [show_axes: true, title: panel.title, colors: @palette] ++
        base_axis_opts(panel, unit) ++
        unit_axis_opts

    {:prepared_ts, %{values: values, opts: opts}}
  end

  def prepare(_panel, other), do: other

  def render(panel, {:prepared_ts, %{values: values, opts: opts}}, height) do
    chart(values, [{:id, :"chart_#{panel.id}"}, {:height, height} | opts])
  end

  def render(panel, {:ok, series}, height) do
    prepared = prepare(panel, {:ok, series})
    render(panel, prepared, height)
  end

  def render(_panel, _, height) do
    placeholder(label: "No data", height: height)
  end

  defp chart_type(panel) do
    draw_style = get_in(panel.field_config, ["defaults", "custom", "drawStyle"])

    case draw_style do
      "bars" -> :bar
      _ -> :braille_area
    end
  end

  defp base_axis_opts(panel, unit) do
    defaults = get_in(panel.field_config, ["defaults"]) || %{}
    min = Map.get(defaults, "min")
    max = Map.get(defaults, "max")

    opts = []

    opts =
      if is_number(min) and unit not in ["percentunit"],
        do: Keyword.put(opts, :min_value, min),
        else: opts

    opts =
      if is_number(max) and unit not in ["percentunit"],
        do: Keyword.put(opts, :max_value, max),
        else: opts

    opts
  end

  defp scale_for_unit(series, "percentunit") do
    scaled = multiply_series(series, 100.0)
    labels = Enum.map([0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100], &"#{&1}%")
    {scaled, [min_value: 0, max_value: 100, y_labels: labels]}
  end

  defp scale_for_unit(series, unit) when unit in ["percent"] do
    labels = Enum.map([0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100], &"#{&1}%")
    {series, [min_value: 0, max_value: 100, y_labels: labels]}
  end

  defp scale_for_unit(series, unit) when unit in ["bytes", "decbytes", "Bps", "binBps"] do
    {factor, suffix} = byte_si_scale(peak_value(series))
    scaled = multiply_series(series, 1.0 / factor)
    {scaled, [y_labels: si_labels(peak_value(scaled), suffix)]}
  end

  defp scale_for_unit(series, unit) when unit in ["bps", "bits"] do
    {factor, suffix} = bit_si_scale(peak_value(series))
    scaled = multiply_series(series, 1.0 / factor)
    {scaled, [y_labels: si_labels(peak_value(scaled), suffix)]}
  end

  defp scale_for_unit(series, _unit), do: {series, []}

  defp multiply_series(series, factor) do
    Enum.map(series, fn s ->
      %{s | values: Enum.map(s.values, fn {ts, v} -> {ts, v * factor} end)}
    end)
  end

  defp peak_value([]), do: 0.0

  defp peak_value(series) do
    series
    |> Enum.flat_map(fn s -> Enum.map(s.values, fn {_ts, v} -> abs(v) end) end)
    |> Enum.max(fn -> 0.0 end)
  end

  defp byte_si_scale(peak) when peak >= 1.0e9, do: {1.0e9, "GB/s"}
  defp byte_si_scale(peak) when peak >= 1.0e6, do: {1.0e6, "MB/s"}
  defp byte_si_scale(peak) when peak >= 1.0e3, do: {1.0e3, "KB/s"}
  defp byte_si_scale(_peak), do: {1.0, "B/s"}

  defp bit_si_scale(peak) when peak >= 1.0e9, do: {1.0e9, "Gb/s"}
  defp bit_si_scale(peak) when peak >= 1.0e6, do: {1.0e6, "Mb/s"}
  defp bit_si_scale(peak) when peak >= 1.0e3, do: {1.0e3, "Kb/s"}
  defp bit_si_scale(_peak), do: {1.0, "b/s"}

  defp si_labels(peak, suffix) do
    step = Float.round(peak / 4, 1)

    if step > 0 do
      Enum.map(0..4, fn i -> "#{Float.round(i * step, 1)} #{suffix}" end)
    else
      ["0 #{suffix}"]
    end
  end

  defp sort_largest_first(series) when length(series) <= 1, do: series

  defp sort_largest_first(series) do
    Enum.sort_by(series, &series_average(&1.values), :asc)
  end

  defp series_average([]), do: 0.0

  defp series_average(values) do
    sum = Enum.reduce(values, 0.0, fn {_ts, v}, acc -> acc + abs(v) end)
    sum / length(values)
  end

  defp extract_values([]), do: []

  defp extract_values(series) do
    max_weight = series |> Enum.map(&Map.get(&1, :weight, 1)) |> Enum.max(fn -> 1 end) |> max(1)
    has_weights = max_weight > 1
    Enum.map(series, &extract_series_values(&1, has_weights, max_weight))
  end

  defp extract_series_values(s, true, max_weight) do
    normalized = min(1.0, Map.get(s, :weight, 1) / max_weight)
    Enum.map(s.values, fn {_ts, val} -> {val, normalized} end)
  end

  defp extract_series_values(s, false, _max_weight) do
    Enum.map(s.values, fn {_ts, val} -> val end)
  end
end
