defmodule GrafExTerm.Panel.Reduce do
  @moduledoc """
  Reduces a series to one number the way a Grafana panel's
  `options.reduceOptions.calcs` asks.

  Supported calculations are `lastNotNull`, `last`, `firstNotNull`, `first`,
  `mean`, `max`, `min`, `sum`, `count`, `range` and `delta`. Values are
  `{unix_seconds, number}` samples. Anything unrecognised is treated as
  `lastNotNull`, which is also Grafana's default.
  """

  @type samples :: [{integer(), number()}]

  @doc """
  The calculation named first in the panel's `reduceOptions.calcs`, or
  `"lastNotNull"` when none is set.
  """
  @spec calc(GrafExTerm.Dashboard.Types.Panel.t()) :: String.t()
  def calc(panel) do
    case get_in(panel.options, ["reduceOptions", "calcs"]) do
      [name | _] when is_binary(name) -> name
      _ -> "lastNotNull"
    end
  end

  @doc """
  Applies `calc` to `samples`. Returns `0.0` for an empty list.

  ## Examples

      iex> GrafExTerm.Panel.Reduce.value([{0, 1.0}, {1, 5.0}, {2, 3.0}], "max")
      5.0

      iex> GrafExTerm.Panel.Reduce.value([{0, 1.0}, {1, 5.0}, {2, 3.0}], "lastNotNull")
      3.0

  """
  @spec value(samples(), String.t()) :: float()
  def value([], _calc), do: 0.0
  def value(samples, calc), do: samples |> Enum.map(&elem(&1, 1)) |> reduce(calc) |> to_float()

  defp reduce(numbers, calc) when calc in ["first", "firstNotNull"], do: hd(numbers)
  defp reduce(numbers, "mean"), do: Enum.sum(numbers) / length(numbers)
  defp reduce(numbers, "max"), do: Enum.max(numbers)
  defp reduce(numbers, "min"), do: Enum.min(numbers)
  defp reduce(numbers, "sum"), do: Enum.sum(numbers)
  defp reduce(numbers, "count"), do: length(numbers)
  defp reduce(numbers, "range"), do: Enum.max(numbers) - Enum.min(numbers)
  defp reduce(numbers, "delta"), do: List.last(numbers) - hd(numbers)
  defp reduce(numbers, _last), do: List.last(numbers)

  defp to_float(number), do: number * 1.0
end
