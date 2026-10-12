defmodule GrafExTerm.Dashboard.TimeRange do
  @moduledoc """
  A dashboard's `time` setting, `%{"from" => ..., "to" => ...}`, in Grafana's date
  math, and its resolution to Unix seconds.

  Each end is one of:

    * `"now"` followed by any number of operations: `+N<unit>` or `-N<unit>` to
      add or subtract, `/<unit>` to round to the start of that unit (to its end
      on the `to` side). Units are `s`, `m`, `h`, `d`, `w`, `M` and `y`; rounding
      and calendar units use local time
    * an ISO 8601 date-time such as `"2026-10-13T08:00:00Z"`
    * Unix milliseconds, as a number or a string of digits

      iex> range = GrafExTerm.Dashboard.TimeRange.parse(%{"from" => "now-6h", "to" => "now"})
      iex> GrafExTerm.Dashboard.TimeRange.resolve(range, 1_700_000_000)
      {1_699_978_400, 1_700_000_000}

  """

  @enforce_keys [:from, :to]
  defstruct [:from, :to]

  @type unit :: :second | :minute | :hour | :day | :week | :month | :year
  @type operation :: {:shift, integer(), unit()} | {:round, unit()}
  @type point :: {:now, [operation()]} | {:absolute, integer()}
  @type t :: %__MODULE__{from: point(), to: point()}

  @units %{
    "s" => :second,
    "m" => :minute,
    "h" => :hour,
    "d" => :day,
    "w" => :week,
    "M" => :month,
    "y" => :year
  }
  @fixed_seconds %{second: 1, minute: 60, hour: 3600, day: 86_400, week: 604_800}

  @doc """
  The range in `time`, or `nil` when `time` is not a map with a readable `from`
  and `to`.
  """
  @spec parse(term()) :: t() | nil
  def parse(%{"from" => from, "to" => to}) do
    with {:ok, from_point} <- parse_point(from),
         {:ok, to_point} <- parse_point(to) do
      %__MODULE__{from: from_point, to: to_point}
    else
      :error -> nil
    end
  end

  def parse(_time), do: nil

  @doc "The range's `{from, to}` in Unix seconds, taking `now` as the current time."
  @spec resolve(t(), integer()) :: {integer(), integer()}
  def resolve(%__MODULE__{from: from, to: to}, now) do
    {resolve_point(from, now, :down), resolve_point(to, now, :up)}
  end

  defp parse_point("now" <> operations) do
    ~r/([+-])(\d+)([smhdwMy])|\/([smhdwMy])|(.)/
    |> Regex.scan(operations)
    |> parse_operations([])
  end

  defp parse_point(millis) when is_integer(millis), do: {:ok, {:absolute, div(millis, 1000)}}

  defp parse_point(text) when is_binary(text) do
    if text =~ ~r/^\d+$/,
      do: {:ok, {:absolute, div(String.to_integer(text), 1000)}},
      else: parse_datetime(text)
  end

  defp parse_point(_other), do: :error

  defp parse_operations([], operations), do: {:ok, {:now, Enum.reverse(operations)}}

  defp parse_operations([[_, sign, count, unit] | rest], operations) do
    amount = String.to_integer(count) * if(sign == "-", do: -1, else: 1)
    parse_operations(rest, [{:shift, amount, @units[unit]} | operations])
  end

  defp parse_operations([[_, "", "", "", unit] | rest], operations),
    do: parse_operations(rest, [{:round, @units[unit]} | operations])

  defp parse_operations(_unreadable, _operations), do: :error

  defp parse_datetime(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} -> {:ok, {:absolute, DateTime.to_unix(datetime)}}
      {:error, _reason} -> :error
    end
  end

  defp resolve_point({:absolute, unix}, _now, _direction), do: unix

  defp resolve_point({:now, operations}, now, direction) do
    operations
    |> Enum.reduce(local(now), &apply_operation(&1, &2, direction))
    |> unix()
  end

  defp apply_operation({:shift, amount, unit}, time, _direction)
       when is_map_key(@fixed_seconds, unit),
       do: NaiveDateTime.add(time, amount * @fixed_seconds[unit], :second)

  defp apply_operation({:shift, amount, unit}, time, _direction),
    do: NaiveDateTime.shift(time, [{unit, amount}])

  defp apply_operation({:round, unit}, time, :down), do: start_of(time, unit)

  defp apply_operation({:round, unit}, time, :up),
    do: time |> start_of(unit) |> NaiveDateTime.shift([{unit, 1}]) |> NaiveDateTime.add(-1)

  defp start_of(time, :second), do: %{time | microsecond: {0, 0}}
  defp start_of(time, :minute), do: %{start_of(time, :second) | second: 0}
  defp start_of(time, :hour), do: %{start_of(time, :minute) | minute: 0}
  defp start_of(time, :day), do: %{start_of(time, :hour) | hour: 0}

  defp start_of(time, :week) do
    day = start_of(time, :day)
    NaiveDateTime.add(day, -(Date.day_of_week(day, :sunday) - 1) * 86_400, :second)
  end

  defp start_of(time, :month), do: %{start_of(time, :day) | day: 1}
  defp start_of(time, :year), do: %{start_of(time, :month) | month: 1}

  defp local(unix) do
    unix
    |> :calendar.system_time_to_local_time(:second)
    |> NaiveDateTime.from_erl!()
  end

  defp unix(local_time) do
    local_time
    |> NaiveDateTime.to_erl()
    |> :erlang.localtime_to_universaltime()
    |> NaiveDateTime.from_erl!()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end
end
