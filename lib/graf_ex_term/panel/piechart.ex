defmodule GrafExTerm.Panel.Piechart do
  @moduledoc """
  Draws a Grafana `piechart` panel: one slice per series, sized by the series
  reduced with the panel's `options.reduceOptions.calcs` (see
  `GrafExTerm.Panel.Reduce`).

  Slices whose value is not positive are left out. The legend is drawn unless
  the panel's `options.legend.showLegend` is `false` or its `displayMode` is
  `"hidden"`, and carries percentages when `options.legend.values` includes
  `"percent"`.
  """

  import Drafter.App, only: [pie_chart: 2, placeholder: 1]

  alias GrafExTerm.Panel.Reduce

  @doc """
  Builds the pie widget for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`. `data` must be
  `{:ok, series}` with at least one positive slice; anything else draws a
  "No data" placeholder of `height` rows. Slices are labelled with the series
  `:name`, falling back to its label values joined with `", "`.
  """
  @spec render(GrafExTerm.Dashboard.Types.Panel.t(), term(), non_neg_integer()) :: tuple()
  def render(panel, {:ok, series}, height) do
    calc = Reduce.calc(panel)

    slices =
      for s <- series,
          value = Reduce.value(s.values, calc),
          value > 0,
          do: {series_label(s), value}

    render_slices(panel, slices, height)
  end

  def render(_panel, _, height), do: placeholder(label: "No data", height: height)

  defp render_slices(_panel, [], height), do: placeholder(label: "No data", height: height)

  defp render_slices(panel, slices, height) do
    legend = get_in(panel.options, ["legend"]) || %{}

    pie_chart(slices,
      id: :"pie_#{panel.id}",
      height: height,
      show_legend: legend_visible?(legend),
      show_percentages: "percent" in (Map.get(legend, "values") || [])
    )
  end

  defp legend_visible?(%{"showLegend" => false}), do: false
  defp legend_visible?(%{"displayMode" => "hidden"}), do: false
  defp legend_visible?(_legend), do: true

  defp series_label(s) do
    case Map.get(s, :name) do
      name when is_binary(name) and name != "" -> name
      _ -> s.labels |> Map.values() |> Enum.join(", ")
    end
  end
end
