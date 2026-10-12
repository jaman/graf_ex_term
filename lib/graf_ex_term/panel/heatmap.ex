defmodule GrafExTerm.Panel.Heatmap do
  @moduledoc """
  Draws a Grafana `heatmap` panel as a coloured grid: one row per bucket, one
  column per sample time, coloured from low to high.

  When every series carries a Prometheus `le` label the series are treated as
  cumulative histogram buckets: they are ordered by bound, each bucket's count
  becomes its own share (its value minus the bucket below it at the same
  time), and the widest bound is the top row. Otherwise each series is one
  row, in the order given, first at the top.

  Columns follow the sample times of the longest series; a series missing a
  time contributes `0.0` there.
  """

  import Drafter.App, only: [chart: 2, placeholder: 1]

  @doc """
  Converts fetched series into the heatmap matrix.

  `data` is `{:ok, series}`; anything else is returned unchanged. Returns
  `{:prepared_heatmap, matrix}`, where `matrix` is a list of rows, top first,
  each a list of numbers.
  """
  @spec prepare(GrafExTerm.Dashboard.Types.Panel.t(), term()) ::
          {:prepared_heatmap, [[number()]]} | term()
  def prepare(_panel, {:ok, []}), do: {:prepared_heatmap, []}

  def prepare(_panel, {:ok, series}) do
    times =
      series |> Enum.max_by(&length(&1.values)) |> Map.fetch!(:values) |> Enum.map(&elem(&1, 0))

    {:prepared_heatmap, series |> rows(times) |> Enum.reverse()}
  end

  def prepare(_panel, other), do: other

  @doc """
  Builds the heatmap widget for `panel`.

  `data` is `{:prepared_heatmap, matrix}` from `prepare/2` or a raw
  `{:ok, series}`, which is prepared inline; anything else, or an empty matrix,
  draws a "No data" placeholder of `height` rows.
  """
  @spec render(GrafExTerm.Dashboard.Types.Panel.t(), term(), non_neg_integer()) :: tuple()
  def render(_panel, {:prepared_heatmap, []}, height),
    do: placeholder(label: "No data", height: height)

  def render(panel, {:prepared_heatmap, matrix}, height) do
    chart(matrix,
      id: :"heatmap_#{panel.id}",
      chart_type: :heatmap,
      height: height
    )
  end

  def render(panel, {:ok, _} = data, height), do: render(panel, prepare(panel, data), height)
  def render(_panel, _, height), do: placeholder(label: "No data", height: height)

  defp rows(series, times) do
    if Enum.all?(series, &Map.has_key?(&1.labels, "le")) do
      series
      |> Enum.sort_by(&bound(&1.labels["le"]))
      |> Enum.map(&aligned(&1, times))
      |> deaccumulate()
    else
      series |> Enum.map(&aligned(&1, times)) |> Enum.reverse()
    end
  end

  defp aligned(series, times) do
    by_time = Map.new(series.values)
    Enum.map(times, &Map.get(by_time, &1, 0.0))
  end

  defp deaccumulate(cumulative_rows) do
    {rows, _below} =
      Enum.map_reduce(cumulative_rows, nil, fn row, below ->
        {subtract(row, below), row}
      end)

    rows
  end

  defp subtract(row, nil), do: row
  defp subtract(row, below), do: Enum.zip_with(row, below, &max(&1 - &2, 0.0))

  defp bound("+Inf"), do: :infinity

  defp bound(le) do
    case Float.parse(le) do
      {value, _} -> value
      :error -> :infinity
    end
  end
end
