defmodule GrafExTerm.Panel.Bargauge do
  @moduledoc """
  Draws a Grafana `bargauge` panel as one labelled progress bar per series,
  stacked vertically.
  """

  import Drafter.App,
    only: [vertical: 1, horizontal: 2, label: 1, progress_bar: 1, placeholder: 1]

  @doc """
  Builds the bar widgets for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`. `data` must be
  `{:ok, series}` with at least one series; every other value, including
  `{:ok, []}`, draws a "No data" placeholder of `height` rows.

  `height` also caps how many series are drawn: one bar per row, so series
  beyond the first `height` are dropped rather than overflowing.

  Each bar shows the series' last sample against the panel's
  `fieldConfig.defaults.max`, which defaults to `100`, with the percentage
  written alongside. Bars are labelled with the series `:name`, falling back
  to its label values joined with `", "`.
  """
  @spec render(GrafExTerm.Dashboard.Types.Panel.t(), term(), non_neg_integer()) :: tuple()
  def render(panel, {:ok, series}, height) when series != [] do
    max_val = get_max(panel.field_config)

    bars =
      series
      |> Enum.take(height)
      |> Enum.map(fn s ->
        value = last_value(s.values)

        series_label =
          case Map.get(s, :name) do
            name when is_binary(name) and name != "" -> name
            _ -> s.labels |> Map.values() |> Enum.join(", ")
          end

        horizontal(
          [
            label(series_label),
            progress_bar(progress: value, max_value: max_val, show_percentage: true)
          ],
          gap: 1
        )
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
