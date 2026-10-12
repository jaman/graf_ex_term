defmodule GrafExTerm.Refresh.QueryWindow do
  @moduledoc """
  The `from`, `to` and `step` of one panel's range query, sized to the panel.

  The step is chosen so the query returns about as many samples as the panel
  can draw: the panel's share of the terminal width, times `points_per_column`
  samples per terminal column. The panel's `maxDataPoints` lowers that count
  further, and its `interval` sets the smallest step allowed. The step is
  always at least one second.

  `to` is `now` rounded down to a multiple of the step and `from` lies a whole
  number of steps before it, so successive windows share sample timestamps and
  a later window can be appended to an earlier one.

      QueryWindow.for_panel(panel, now: 1_700_000_000, range: 3600, columns: 200)
      #=> %QueryWindow{from: 1_699_996_392, to: 1_699_999_992, step: 9} for a full-width panel
  """

  alias GrafExTerm.Dashboard.Types.Panel

  @enforce_keys [:from, :to, :step]
  defstruct [:from, :to, :step]

  @type t :: %__MODULE__{from: integer(), to: integer(), step: pos_integer()}

  @grid_columns 24
  @default_points_per_column 2
  @default_fallback_points 300

  @doc """
  Returns the window for `panel`.

  Options:

    * `:now` — Unix seconds the window ends at, before rounding. Required.
    * `:range` — window length in seconds. Required.
    * `:columns` — terminal columns the dashboard is laid out across, or
      `nil` when unknown. Defaults to `nil`.
    * `:points_per_column` — samples per terminal column. Defaults to `2`, one
      per braille dot column.
    * `:fallback_points` — sample count used when `:columns` is `nil`.
      Defaults to `300`.
  """
  @spec for_panel(Panel.t(), keyword()) :: t()
  def for_panel(%Panel{} = panel, opts) do
    now = Keyword.fetch!(opts, :now)
    range = Keyword.fetch!(opts, :range)
    points = panel |> drawable_points(opts) |> cap(panel.max_data_points)
    step = Enum.max([ceil_div(range, points), interval_seconds(panel.min_interval), 1])
    to = div(now, step) * step
    %__MODULE__{from: to - ceil_div(range, step) * step, to: to, step: step}
  end

  @doc """
  Parses a Grafana interval string such as `"30s"`, `">1m"` or `"500ms"` into
  whole seconds, rounding up.

  A leading `>` is ignored. Units are `ms`, `s`, `m`, `h`, `d` and `w`; a bare
  number is seconds. Returns `0` for `nil` or anything unparseable.

  ## Examples

      iex> GrafExTerm.Refresh.QueryWindow.interval_seconds(">2m")
      120

      iex> GrafExTerm.Refresh.QueryWindow.interval_seconds("1500ms")
      2

  """
  @spec interval_seconds(String.t() | nil) :: non_neg_integer()
  def interval_seconds(nil), do: 0

  def interval_seconds(interval) when is_binary(interval) do
    case Regex.run(~r/^>?\s*(\d+(?:\.\d+)?)\s*(ms|s|m|h|d|w)?$/, String.trim(interval)) do
      [_, amount, unit] -> amount |> Float.parse() |> elem(0) |> to_seconds(unit)
      [_, amount] -> amount |> Float.parse() |> elem(0) |> to_seconds("s")
      nil -> 0
    end
  end

  defp drawable_points(panel, opts) do
    case Keyword.get(opts, :columns) do
      nil ->
        Keyword.get(opts, :fallback_points, @default_fallback_points)

      columns ->
        per_column = Keyword.get(opts, :points_per_column, @default_points_per_column)
        max(1, div(columns * panel.grid_pos.w, @grid_columns)) * per_column
    end
  end

  defp cap(points, nil), do: points
  defp cap(points, max_points), do: min(points, max_points)

  defp to_seconds(amount, "ms"), do: ceil(amount / 1000)
  defp to_seconds(amount, "s"), do: ceil(amount)
  defp to_seconds(amount, "m"), do: ceil(amount * 60)
  defp to_seconds(amount, "h"), do: ceil(amount * 3600)
  defp to_seconds(amount, "d"), do: ceil(amount * 86_400)
  defp to_seconds(amount, "w"), do: ceil(amount * 604_800)

  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)
end
