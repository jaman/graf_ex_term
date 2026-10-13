defmodule GrafExTerm.Panel.Timeseries do
  @moduledoc """
  Draws Grafana `timeseries` and `graph` panels as line, area or bar charts.

  Preparation and rendering are split. `prepare/3` does the work that depends
  only on the data — unit scaling, time alignment, ordering, axis options — so a
  screen can do it once when data arrives rather than on every frame;
  `render/3` turns the prepared result into a widget. Calling `render/3` on raw
  `{:ok, series}` prepares it first.

  Every series is placed on one time grid: the query window's steps when the
  window is given, else every timestamp any series has. A step a series has no
  sample for is a gap, drawn as nothing, so a series that starts or stops partway
  through the window sits at its true time. `custom.spanNulls` joins gaps as
  Grafana does: `true` joins every gap between two samples, a number of
  milliseconds joins gaps no longer than that.

  The panel's `fieldConfig.defaults.custom` picks the drawing, with Grafana's
  defaults (`drawStyle` `"line"`, `fillOpacity` 0):

    * `drawStyle` `"bars"` — a `:bar` chart for one series, `:clustered_bar`
      for several, `:stacked_bar` when `stacking.mode` is `"normal"`; gaps are zero
    * `drawStyle` `"points"` — a `:line` chart of unjoined points
    * `fillOpacity` above 0, or `stacking.mode` `"normal"` — a `:braille_area`
      chart, stacked when `stacking.mode` is `"normal"`, smallest average
      magnitude at the bottom; otherwise each area is drawn from the baseline,
      largest first, so larger areas do not hide smaller ones
    * anything else — a `:line` chart

  A series carrying a `:weight` above 1 — the marker
  `GrafExTerm.Refresh.SeriesClusterer` puts on a merged cluster — is drawn as an
  area with an opacity proportional to how many series it stands for.

  Units drive the y-axis. `percentunit` values are multiplied by 100 and the
  axis pinned to 0..100; `percent` is pinned without scaling; byte and bit
  units are divided down to the largest SI step the peak reaches and labelled
  with the matching per-second suffix. Explicit `min`/`max` from the panel's
  `fieldConfig` are applied for every unit except `percentunit`.

  Each grid time becomes an x label, local `HH:MM:SS`. The chart's value
  readout lists every series by name with its value formatted for the panel's
  unit and decimals (`GrafExTerm.Format`), ordered by `options.tooltip.sort`.
  Charts draw with `GrafExTerm.Panel.Graphics.renderer/0`.
  """

  import Drafter.App, only: [chart: 2, placeholder: 1]

  alias GrafExTerm.Format
  alias GrafExTerm.Panel.Graphics
  alias GrafExTerm.Refresh.QueryWindow

  @palette [
    {100, 200, 255},
    {255, 130, 80},
    {80, 255, 150},
    {255, 100, 180},
    {200, 180, 60},
    {180, 100, 255}
  ]

  @doc """
  Converts fetched series into the values and chart options `render/3` needs.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`. `data` is `{:ok, series}`;
  anything else is returned unchanged, so error tuples pass through to
  `render/3` and become a placeholder there. `window` is the
  `GrafExTerm.Refresh.QueryWindow` the series were fetched over, or `nil`.

  Returns `{:prepared_ts, %{values: values, opts: opts}}`.
  """
  @spec prepare(map(), {:ok, list()} | any(), QueryWindow.t() | nil) ::
          {:prepared_ts, map()} | any()
  def prepare(panel, data, window \\ nil)

  def prepare(panel, {:ok, series}, window) do
    defaults = get_in(panel.field_config, ["defaults"]) || %{}
    custom = defaults["custom"] || %{}
    unit = defaults["unit"] || ""
    {scaled_series, unit_axis_opts, scale} = scale_for_unit(series, unit)
    stacked? = stacked?(custom)
    grid = time_grid(scaled_series, window)

    ordered =
      scaled_series
      |> sort_largest_first()
      |> draw_order(stacked?)
      |> Enum.map(&on_grid(&1, grid, window, custom["spanNulls"]))

    {type, values} = chart_data(custom, ordered)

    opts =
      [chart_type: type] ++
        style_opts(type, custom, ordered, stacked?) ++
        [show_axes: true, colors: @palette, x_labels: time_labels(grid)] ++
        readout_opts(panel, ordered, defaults, scale) ++
        renderer_opts() ++
        base_axis_opts(defaults, unit) ++
        unit_axis_opts

    {:prepared_ts, %{values: values, opts: opts}}
  end

  def prepare(_panel, other, _window), do: other

  @doc """
  Builds the chart widget for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`, and its `:id` becomes the
  widget id `:"chart_<id>"`. `data` is either a `{:prepared_ts, map}` from
  `prepare/3` or a raw `{:ok, series}`, which is prepared inline; anything
  else draws a "No data" placeholder. `height` is the widget height in
  terminal rows.
  """
  @spec render(GrafExTerm.Dashboard.Types.Panel.t(), term(), non_neg_integer()) :: tuple()
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

  defp time_grid(_series, %QueryWindow{from: from, to: to, step: step}),
    do: Enum.to_list(from..to//step)

  defp time_grid(series, nil) do
    series
    |> Enum.flat_map(fn s -> Enum.map(s.values, &elem(&1, 0)) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp on_grid(series, grid, window, span_nulls) do
    by_time = Map.new(series.values, fn {ts, value} -> {snap(ts, window), value} end)

    values =
      grid
      |> Enum.map(&{&1, Map.get(by_time, &1)})
      |> span_gaps(span_nulls)

    %{series | values: values}
  end

  defp snap(ts, nil), do: ts
  defp snap(ts, %QueryWindow{from: from, step: step}), do: from + round((ts - from) / step) * step

  defp span_gaps(points, limit) when limit == true or (is_number(limit) and limit > 0) do
    points
    |> Enum.chunk_by(fn {_ts, value} -> is_nil(value) end)
    |> join_gaps(nil, limit, [])
  end

  defp span_gaps(points, _limit), do: points

  defp join_gaps([], _previous, _limit, done), do: done |> Enum.reverse() |> Enum.concat()

  defp join_gaps([[{_, nil} | _] = gap, [next | _] = known | rest], previous, limit, done)
       when previous != nil do
    joined = if joinable?(previous, next, limit), do: interpolate(gap, previous, next), else: gap
    join_gaps(rest, List.last(known), limit, [known, joined | done])
  end

  defp join_gaps([run | rest], _previous, limit, done),
    do: join_gaps(rest, last_sample(run), limit, [run | done])

  defp last_sample(run) do
    case List.last(run) do
      {_ts, nil} -> nil
      sample -> sample
    end
  end

  defp joinable?(_previous, _next, true), do: true
  defp joinable?({from, _}, {to, _}, limit_ms), do: (to - from) * 1000 <= limit_ms

  defp interpolate(gap, {t0, v0}, {t1, v1}) do
    Enum.map(gap, fn {ts, nil} -> {ts, v0 + (v1 - v0) * (ts - t0) / (t1 - t0)} end)
  end

  defp time_labels(grid) do
    Enum.map(grid, fn ts -> ts |> local_time() |> Time.to_string() end)
  end

  defp local_time(unix_seconds) do
    {_date, time} = :calendar.system_time_to_local_time(unix_seconds, :second)
    Time.from_erl!(time)
  end

  defp renderer_opts, do: [renderer: Graphics.renderer()]

  defp stacked?(custom), do: get_in(custom, ["stacking", "mode"]) == "normal"

  defp draw_order(series, true), do: series
  defp draw_order(series, false), do: Enum.reverse(series)

  defp chart_data(%{"drawStyle" => "bars"} = custom, series),
    do: bar_data(Enum.map(series, &bar_values/1), get_in(custom, ["stacking", "mode"]))

  defp chart_data(custom, series) do
    if area?(custom, series),
      do: {:braille_area, area_values(series)},
      else: {:line, Enum.map(series, &line_values/1)}
  end

  defp area?(custom, series) do
    fill_opacity(custom) > 0 or stacked?(custom) or Enum.any?(series, &weighted?/1)
  end

  defp fill_opacity(%{"fillOpacity" => opacity}) when is_number(opacity), do: opacity
  defp fill_opacity(_custom), do: 0

  defp weighted?(series), do: Map.get(series, :weight, 1) > 1

  defp style_opts(:braille_area, _custom, series, stacked?) do
    fill = if Enum.any?(series, &weighted?/1) or length(series) > 3, do: 0.6, else: 1.0
    [show_baseline: true, fill_opacity: fill, zero_center: :linear, stacked: stacked?]
  end

  defp style_opts(:line, custom, _series, _stacked?),
    do: [connect_lines: custom["drawStyle"] != "points"]

  defp style_opts(_bars, _custom, _series, _stacked?), do: []

  defp bar_data([only], _stacking), do: {:bar, only}
  defp bar_data([], _stacking), do: {:bar, []}
  defp bar_data(series, "normal"), do: {:stacked_bar, series}
  defp bar_data(series, _stacking), do: {:clustered_bar, series}

  defp bar_values(series), do: Enum.map(series.values, fn {_ts, value} -> value || 0 end)
  defp line_values(series), do: Enum.map(series.values, &elem(&1, 1))

  defp readout_opts(panel, series, defaults, scale) do
    [
      series_names: Enum.map(series, &Map.get(&1, :name)),
      readout_format: readout_format(defaults["unit"], decimals(defaults["decimals"]), scale),
      readout_sort: readout_sort(get_in(panel.options || %{}, ["tooltip", "sort"]))
    ]
  end

  defp readout_format(unit, decimals, scale) do
    fn value -> (value / scale) |> Format.format(unit, decimals) |> Format.to_string() end
  end

  defp decimals(decimals) when is_integer(decimals), do: decimals
  defp decimals(_automatic), do: nil

  defp readout_sort("asc"), do: :asc
  defp readout_sort("desc"), do: :desc
  defp readout_sort(_none), do: :none

  defp base_axis_opts(defaults, unit) do
    [min_value: defaults["min"], max_value: defaults["max"]]
    |> Enum.filter(fn {_key, limit} -> is_number(limit) and unit != "percentunit" end)
  end

  defp scale_for_unit(series, "percentunit") do
    scaled = multiply_series(series, 100.0)
    labels = Enum.map([0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100], &"#{&1}%")
    {scaled, [min_value: 0, max_value: 100, y_labels: labels], 100.0}
  end

  defp scale_for_unit(series, unit) when unit in ["percent"] do
    labels = Enum.map([0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100], &"#{&1}%")
    {series, [min_value: 0, max_value: 100, y_labels: labels], 1.0}
  end

  defp scale_for_unit(series, unit) when unit in ["bytes", "decbytes", "Bps", "binBps"] do
    {factor, suffix} = byte_si_scale(peak_value(series))
    scaled = multiply_series(series, 1.0 / factor)
    {scaled, [y_labels: si_labels(peak_value(scaled), suffix)], 1.0 / factor}
  end

  defp scale_for_unit(series, unit) when unit in ["bps", "bits"] do
    {factor, suffix} = bit_si_scale(peak_value(series))
    scaled = multiply_series(series, 1.0 / factor)
    {scaled, [y_labels: si_labels(peak_value(scaled), suffix)], 1.0 / factor}
  end

  defp scale_for_unit(series, _unit), do: {series, [], 1.0}

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

  defp area_values(series) do
    max_weight = series |> Enum.map(&Map.get(&1, :weight, 1)) |> Enum.max(fn -> 1 end) |> max(1)
    Enum.map(series, &area_series_values(&1, max_weight > 1, max_weight))
  end

  defp area_series_values(series, true, max_weight) do
    normalized = min(1.0, Map.get(series, :weight, 1) / max_weight)

    Enum.map(series.values, fn
      {_ts, nil} -> nil
      {_ts, value} -> {value, normalized}
    end)
  end

  defp area_series_values(series, false, _max_weight), do: line_values(series)
end
