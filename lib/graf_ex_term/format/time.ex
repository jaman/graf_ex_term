defmodule GrafExTerm.Format.Time do
  @moduledoc """
  Grafana's time units: durations scaled to the largest fitting unit (`s`, `ms`,
  `µs`, `ns`, `m`, `h`, `d`), spelled-out durations, clock readings and dates, as
  Grafana's `dateTimeFormatters.ts` writes them.

  Every function returns a `t:GrafExTerm.Format.formatted/0`. Dates are read as
  Unix milliseconds and written in the machine's local time zone.
  """

  alias GrafExTerm.Format

  @intervals [
    {"year", 31_536_000},
    {"month", 2_592_000},
    {"week", 604_800},
    {"day", 86_400},
    {"hour", 3600},
    {"minute", 60},
    {"second", 1},
    {"millisecond", 0.001}
  ]

  @doc "Formats `value` for one of the time units named by atom in `GrafExTerm.Format.Units`."
  @spec format(atom() | tuple(), number(), non_neg_integer() | nil) :: Format.formatted()
  def format(:s, value, decimals), do: seconds(value, decimals)
  def format(:ms, value, decimals), do: milliseconds(value, decimals)
  def format(:us, value, decimals), do: microseconds(value, decimals)
  def format(:ns, value, decimals), do: nanoseconds(value, decimals)
  def format(:m, value, decimals), do: minutes(value, decimals)
  def format(:h, value, decimals), do: hours(value, decimals)
  def format(:d, value, decimals), do: days(value, decimals)
  def format(:timeticks, value, decimals), do: seconds(value / 100, decimals)
  def format({:duration, interval}, value, decimals), do: duration(value, decimals, interval)
  def format(:hms, value, _decimals), do: hms(value)
  def format(:dhms, value, _decimals), do: dhms(value)
  def format(:clockms, value, decimals), do: clock(value, decimals)
  def format(:clocks, value, decimals), do: clock(value * 1000, decimals)
  def format({:date, style, today?}, value, _decimals), do: date(value, style, today?)
  def format(:from_now, value, _decimals), do: from_now(value)

  defp seconds(value, _decimals) when value == 0, do: Format.formatted("0", " s")

  defp seconds(value, decimals) when abs(value) < 0.000001,
    do: Format.fixed_scaled(value * 1.0e9, decimals, " ns")

  defp seconds(value, decimals) when abs(value) < 0.001,
    do: Format.fixed_scaled(value * 1.0e6, decimals, " µs")

  defp seconds(value, decimals) when abs(value) < 1,
    do: Format.fixed_scaled(value * 1.0e3, decimals, " ms")

  defp seconds(value, decimals) when abs(value) < 60,
    do: Format.formatted(Format.to_fixed(value, decimals), " s")

  defp seconds(value, decimals) when abs(value) < 3600,
    do: Format.fixed_scaled(value / 60, decimals, " min")

  defp seconds(value, decimals) when abs(value) < 86_400,
    do: Format.fixed_scaled(value / 3600, decimals, " hour")

  defp seconds(value, decimals) when abs(value) < 604_800,
    do: Format.fixed_scaled(value / 86_400, decimals, " day")

  defp seconds(value, decimals) when abs(value) < 31_536_000,
    do: Format.fixed_scaled(value / 604_800, decimals, " week")

  defp seconds(value, decimals), do: Format.fixed_scaled(value / 31_556_900.0, decimals, " year")

  defp milliseconds(value, decimals) do
    size = abs(value)

    cond do
      size < 1000 -> Format.formatted(Format.to_fixed(value, decimals), " ms")
      size < 60_000 -> Format.fixed_scaled(value / 1000, decimals, " s")
      size < 3_600_000 -> Format.fixed_scaled(value / 60_000, decimals, " min")
      size < 86_400_000 -> Format.fixed_scaled(value / 3_600_000, decimals, " hour")
      size < 31_536_000_000 -> Format.fixed_scaled(value / 86_400_000, decimals, " day")
      true -> Format.fixed_scaled(value / 31_536_000_000, decimals, " year")
    end
  end

  defp microseconds(value, decimals) do
    size = abs(value)

    cond do
      size < 1000 -> Format.formatted(Format.to_fixed(value, decimals), " µs")
      size < 1_000_000 -> Format.fixed_scaled(value / 1000, decimals, " ms")
      true -> Format.fixed_scaled(value / 1_000_000, decimals, " s")
    end
  end

  defp nanoseconds(value, decimals) do
    size = abs(value)

    cond do
      size < 1000 ->
        Format.formatted(Format.to_fixed(value, decimals), " ns")

      size < 1_000_000 ->
        Format.fixed_scaled(value / 1000, decimals, " µs")

      size < 1_000_000_000 ->
        Format.fixed_scaled(value / 1_000_000, decimals, " ms")

      size < 60_000_000_000 ->
        Format.fixed_scaled(value / 1_000_000_000, decimals, " s")

      size < 3_600_000_000_000 ->
        Format.fixed_scaled(value / 60_000_000_000, decimals, " min")

      size < 86_400_000_000_000 ->
        Format.fixed_scaled(value / 3_600_000_000_000, decimals, " hour")

      true ->
        Format.fixed_scaled(value / 86_400_000_000_000, decimals, " day")
    end
  end

  defp minutes(value, decimals) do
    size = abs(value)

    cond do
      size < 60 -> Format.formatted(Format.to_fixed(value, decimals), " min")
      size < 1440 -> Format.fixed_scaled(value / 60, decimals, " hour")
      size < 10_080 -> Format.fixed_scaled(value / 1440, decimals, " day")
      size < 604_800 -> Format.fixed_scaled(value / 10_080, decimals, " week")
      true -> Format.fixed_scaled(value / 525_948.0, decimals, " year")
    end
  end

  defp hours(value, decimals) do
    size = abs(value)

    cond do
      size < 24 -> Format.formatted(Format.to_fixed(value, decimals), " hour")
      size < 168 -> Format.fixed_scaled(value / 24, decimals, " day")
      size < 8760 -> Format.fixed_scaled(value / 168, decimals, " week")
      true -> Format.fixed_scaled(value / 8760, decimals, " year")
    end
  end

  defp days(value, decimals) do
    size = abs(value)

    cond do
      size < 7 -> Format.fixed_scaled(value, decimals, " day")
      size < 365 -> Format.fixed_scaled(value / 7, decimals, " week")
      true -> Format.fixed_scaled(value / 365, decimals, " year")
    end
  end

  defp duration(value, _decimals, interval) when value == 0,
    do: Format.formatted("0", " #{interval}s")

  defp duration(value, decimals, interval) when value < 0,
    do: ago(duration(-value, decimals, interval))

  defp duration(value, decimals, interval) do
    {_name, scale} = List.keyfind(@intervals, Atom.to_string(interval), 0)
    millis = value * scale * 1000

    {parts, _rest, _started, _left} =
      Enum.reduce(@intervals, {[], millis, false, decimals || 0}, &duration_part/2)

    Format.formatted(parts |> Enum.reverse() |> Enum.join(", "))
  end

  defp duration_part(_interval, {parts, rest, started, left}) when left < 0,
    do: {parts, rest, started, left}

  defp duration_part({name, seconds}, {parts, rest, started, left}) do
    length = seconds * 1000
    count = rest / length

    if count >= 1 or started do
      whole = floor(count)
      unit = if whole != 1, do: name <> "s", else: name
      {["#{whole} #{unit}" | parts], fmod(rest, length), true, left - 1}
    else
      {parts, rest, started, left}
    end
  end

  defp hms(value) when value < 0, do: ago(hms(-value))

  defp hms(value) do
    hours = floor(value / 3600)
    minutes = floor(fmod(value, 3600) / 60)
    seconds = floor(fmod(fmod(value, 3600), 60))
    Format.formatted(Enum.map_join([hours, minutes, seconds], ":", &two_digits/1))
  end

  defp dhms(value) when value < 0, do: ago(dhms(-value))

  defp dhms(value) do
    days = floor(value / 86_400)
    day_text = if days > 0, do: "#{days} d ", else: ""
    Format.formatted(day_text <> hms(value - days * 86_400).text)
  end

  defp clock(value, _decimals) when value < 1000, do: Format.formatted(clock_ms(value) <> "ms")
  defp clock(value, 0) when value < 60_000, do: Format.formatted(clock_s(value) <> "s")

  defp clock(value, _decimals) when value < 60_000,
    do: Format.formatted(clock_s(value) <> "s:" <> clock_ms(value) <> "ms")

  defp clock(value, 0) when value < 3_600_000, do: Format.formatted(clock_m(value) <> "m")

  defp clock(value, 1) when value < 3_600_000,
    do: Format.formatted(clock_m(value) <> "m:" <> clock_s(value) <> "s")

  defp clock(value, _decimals) when value < 3_600_000,
    do:
      Format.formatted(
        clock_m(value) <> "m:" <> clock_s(value) <> "s:" <> clock_ms(value) <> "ms"
      )

  defp clock(value, decimals) do
    hours = "#{floor(value / 3_600_000)}h"

    case decimals do
      0 ->
        Format.formatted(hours)

      1 ->
        Format.formatted(hours <> ":" <> clock_m(value) <> "m")

      2 ->
        Format.formatted(hours <> ":" <> clock_m(value) <> "m:" <> clock_s(value) <> "s")

      _more ->
        Format.formatted(
          hours <>
            ":" <> clock_m(value) <> "m:" <> clock_s(value) <> "s:" <> clock_ms(value) <> "ms"
        )
    end
  end

  defp clock_ms(millis),
    do: millis |> trunc() |> rem(1000) |> Integer.to_string() |> String.pad_leading(3, "0")

  defp clock_s(millis), do: millis |> trunc() |> div(1000) |> rem(60) |> two_digits()
  defp clock_m(millis), do: millis |> trunc() |> div(60_000) |> rem(60) |> two_digits()

  defp date(millis, style, today?) do
    moment = local(millis)

    time_only? =
      today? and
        NaiveDateTime.to_date(moment) ==
          NaiveDateTime.to_date(local(System.os_time(:millisecond)))

    Format.formatted(date_text(moment, style, time_only?))
  end

  defp date_text(moment, :iso, true), do: Calendar.strftime(moment, "%H:%M:%S")
  defp date_text(moment, :iso, false), do: Calendar.strftime(moment, "%Y-%m-%d %H:%M:%S")

  defp date_text(moment, :us, true),
    do: Calendar.strftime(moment, "%-I:%M:%S ") <> meridiem(moment)

  defp date_text(moment, :us, false),
    do: Calendar.strftime(moment, "%m/%d/%Y %-I:%M:%S ") <> meridiem(moment)

  defp meridiem(moment), do: if(moment.hour < 12, do: "am", else: "pm")

  defp local(millis) do
    millis
    |> trunc()
    |> div(1000)
    |> :calendar.system_time_to_local_time(:second)
    |> NaiveDateTime.from_erl!()
  end

  defp from_now(millis) do
    seconds = (System.os_time(:millisecond) - millis) / 1000
    phrase = relative(abs(seconds))
    Format.formatted(if seconds >= 0, do: phrase <> " ago", else: "in " <> phrase)
  end

  defp relative(seconds) when seconds < 45, do: "a few seconds"
  defp relative(seconds) when seconds < 90, do: "a minute"
  defp relative(seconds) when seconds < 45 * 60, do: "#{round(seconds / 60)} minutes"
  defp relative(seconds) when seconds < 90 * 60, do: "an hour"
  defp relative(seconds) when seconds < 22 * 3600, do: "#{round(seconds / 3600)} hours"
  defp relative(seconds) when seconds < 36 * 3600, do: "a day"
  defp relative(seconds) when seconds < 26 * 86_400, do: "#{round(seconds / 86_400)} days"
  defp relative(seconds) when seconds < 45 * 86_400, do: "a month"

  defp relative(seconds) when seconds < 320 * 86_400,
    do: "#{round(seconds / (30 * 86_400))} months"

  defp relative(seconds) when seconds < 548 * 86_400, do: "a year"
  defp relative(seconds), do: "#{round(seconds / (365 * 86_400))} years"

  defp ago(formatted), do: %{formatted | suffix: formatted.suffix <> " ago"}

  defp two_digits(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  defp fmod(a, b), do: a - b * floor(a / b)
end
