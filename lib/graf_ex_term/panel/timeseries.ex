defmodule GrafExTerm.Panel.Timeseries do
  import Drafter.App, only: [chart: 2, placeholder: 1]

  @palette [
    {100, 200, 255},
    {255, 130,  80},
    { 80, 255, 150},
    {255, 100, 180},
    {200, 180,  60},
    {180, 100, 255}
  ]

  @max_data_points 2000

  def render(panel, {:ok, series}, height) do
    values = series_to_values(series)
    type = chart_type(panel)

    area_fill = if type == :area and Application.get_env(:graf_ex_term, :invert_area_charts, true), do: :inverted, else: :below

    opts =
      [
        id: :"chart_#{panel.id}",
        chart_type: type,
        area_fill: area_fill,
        show_axes: true,
        title: panel.title,
        colors: @palette,
        height: height
      ] ++ axis_options(panel)

    chart(values, opts)
  end

  def render(_panel, _, height) do
    placeholder(label: "No data", height: height)
  end

  defp chart_type(%{type: "graph"}), do: :area
  defp chart_type(_), do: :area

  defp axis_options(panel) do
    defaults = get_in(panel.field_config, ["defaults"]) || %{}
    min = Map.get(defaults, "min")
    max = Map.get(defaults, "max")
    unit = Map.get(defaults, "unit")

    opts = []
    opts = if is_number(min), do: Keyword.put(opts, :min_value, min), else: opts
    opts = if is_number(max), do: Keyword.put(opts, :max_value, max), else: opts

    if unit == "percent" and min == 0 and max == 100 do
      labels = ["0%", "20%", "40%", "60%", "80%", "100%"]
      Keyword.put(opts, :y_labels, labels)
    else
      opts
    end
  end

  defp series_to_values([]), do: []

  defp series_to_values([single]) do
    single.values
    |> Enum.map(fn {_ts, val} -> val end)
    |> m4_downsample(@max_data_points)
  end

  defp series_to_values(series) do
    Enum.map(series, fn s ->
      s.values
      |> Enum.map(fn {_ts, val} -> val end)
      |> m4_downsample(@max_data_points)
    end)
  end

  defp m4_downsample(values, max_points) when length(values) <= max_points, do: values

  defp m4_downsample(values, max_points) do
    n = length(values)
    bucket_count = div(max_points, 2)
    bucket_size = n / bucket_count

    for i <- 0..(bucket_count - 1) do
      start_idx = round(i * bucket_size)
      end_idx = round((i + 1) * bucket_size)
      bucket = Enum.slice(values, start_idx, max(1, end_idx - start_idx))
      {Enum.min(bucket), Enum.max(bucket)}
    end
    |> Enum.flat_map(fn {mn, mx} -> [mn, mx] end)
  end
end
