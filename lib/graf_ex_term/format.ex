defmodule GrafExTerm.Format do
  @moduledoc """
  Formats numbers the way Grafana does for a panel's unit and decimals, ported from
  Grafana's `valueFormats` (`toFixed`, its automatic decimals, scaled and prefixed
  units, durations, percentages).

  The result keeps the number apart from its prefix and suffix, so a panel can draw
  the number large and the unit beside it:

      iex> GrafExTerm.Format.format(49.37, "s", nil)
      %{prefix: "", text: "49.4", suffix: " s"}

      iex> GrafExTerm.Format.format(49, "s", nil)
      %{prefix: "", text: "49", suffix: " s"}

      iex> GrafExTerm.Format.format(1536, "bytes", nil)
      %{prefix: "", text: "1.50", suffix: " KiB"}

      iex> GrafExTerm.Format.format(0.4213, "percentunit", 1)
      %{prefix: "", text: "42.1", suffix: "%"}

      iex> GrafExTerm.Format.format(23308, "short", nil)
      %{prefix: "", text: "23.3", suffix: " K"}

  Units are Grafana's unit ids (`GrafExTerm.Format.Units`). An id Grafana does not
  know is written after the number, as Grafana writes a custom unit. `decimals` is
  the panel's `fieldConfig.defaults.decimals`, or `nil` for Grafana's automatic
  choice.
  """

  alias GrafExTerm.Format.{Time, Units}

  @type formatted :: %{prefix: String.t(), text: String.t(), suffix: String.t()}

  @si_prefixes ["f", "p", "n", "µ", "m", "", "k", "M", "G", "T", "P", "E", "Z", "Y"]
  @si_base 5
  @binary_prefixes ["", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi", "Yi"]
  @count_prefixes ["", "K", "M", "B", "T"]
  @plural_suffixes [" min", " hour", " day", " week", " year"]

  @doc "Formats `value` for Grafana unit id `unit` with `decimals` (or `nil` for automatic)."
  @spec format(number(), String.t() | nil, non_neg_integer() | nil) :: formatted()
  def format(value, unit, decimals) when is_number(value) do
    case Units.spec(unit || "none") do
      nil -> fixed_unit(value, decimals, unit, false)
      spec -> apply_spec(spec, value, decimals)
    end
  end

  @doc "The number, prefix and suffix joined, as Grafana displays them."
  @spec to_string(formatted()) :: String.t()
  def to_string(%{prefix: prefix, text: text, suffix: suffix}), do: prefix <> text <> suffix

  @doc false
  @spec formatted(String.t(), String.t(), String.t()) :: formatted()
  def formatted(text, suffix \\ "", prefix \\ ""),
    do: %{prefix: prefix, text: text, suffix: suffix}

  @doc """
  Grafana's `toFixed`: `value` with `decimals` places, or with the places Grafana
  picks for its magnitude when `decimals` is `nil`.

      iex> GrafExTerm.Format.to_fixed(49.37, nil)
      "49.4"

      iex> GrafExTerm.Format.to_fixed(2.5, 2)
      "2.50"

  """
  @spec to_fixed(number(), non_neg_integer() | nil) :: String.t()
  def to_fixed(value, nil), do: to_fixed(value, decimals_for(value))

  def to_fixed(value, decimals) do
    decimals = decimals |> max(0) |> min(100)

    if value == 0 do
      zero(decimals)
    else
      factor = if decimals > 0, do: :math.pow(10, decimals), else: 1
      value |> Kernel.*(factor) |> js_round() |> Kernel./(factor) |> js_string() |> pad(decimals)
    end
  end

  @doc false
  @spec fixed_scaled(number(), non_neg_integer() | nil, String.t()) :: formatted()
  def fixed_scaled(value, decimals, suffix) do
    formatted(to_fixed(value, decimals), plural(suffix, abs(value) > 1))
  end

  defp apply_spec({:fixed, unit, as_prefix?}, value, decimals),
    do: fixed_unit(value, decimals, unit, as_prefix?)

  defp apply_spec({:si, unit, offset}, value, decimals),
    do:
      scaled(
        value,
        decimals,
        1000,
        Enum.map(@si_prefixes, &(" " <> &1 <> unit)),
        @si_base + offset
      )

  defp apply_spec({:binary, unit, offset}, value, decimals),
    do: scaled(value, decimals, 1024, Enum.map(@binary_prefixes, &(" " <> &1 <> unit)), offset)

  defp apply_spec({:scaled, factor, suffixes}, value, decimals),
    do: scaled(value, decimals, factor, suffixes, 0)

  defp apply_spec({:count, symbol}, value, decimals) do
    result = scaled(value, decimals, 1000, @count_prefixes, 0)
    %{result | suffix: result.suffix <> " " <> symbol}
  end

  defp apply_spec({:currency, symbol, as_suffix?}, value, decimals) do
    result = scaled(abs(value), decimals, 1000, @count_prefixes, 0)

    result =
      if as_suffix?,
        do: %{result | suffix: result.suffix <> symbol},
        else: %{result | prefix: symbol}

    if value < 0, do: %{result | prefix: "-" <> result.prefix}, else: result
  end

  defp apply_spec({:bool, true_text, false_text}, value, _decimals),
    do: formatted(if(value != 0, do: true_text, else: false_text))

  defp apply_spec(:percent, value, decimals), do: formatted(to_fixed(value, decimals), "%")

  defp apply_spec(:percentunit, value, decimals),
    do: formatted(to_fixed(100 * value, decimals), "%")

  defp apply_spec(:string, value, _decimals), do: formatted(js_string(value))
  defp apply_spec(:hex, value, decimals), do: formatted(hex(value, decimals))

  defp apply_spec(:hex0x, value, decimals) do
    case hex(value, decimals) do
      "-" <> digits -> formatted("-0x" <> digits)
      digits -> formatted("0x" <> digits)
    end
  end

  defp apply_spec(:sci, value, decimals), do: formatted(exponential(value, decimals))
  defp apply_spec(:locale, value, decimals), do: formatted(grouped(value, decimals || 3))
  defp apply_spec(spec, value, decimals), do: Time.format(spec, value, decimals)

  defp fixed_unit(value, decimals, unit, _as_prefix?) when unit in [nil, ""],
    do: formatted(to_fixed(value, decimals))

  defp fixed_unit(value, decimals, unit, true), do: formatted(to_fixed(value, decimals), "", unit)

  defp fixed_unit(value, decimals, unit, false),
    do: formatted(to_fixed(value, decimals), " " <> unit)

  defp scaled(value, decimals, factor, suffixes, offset) do
    count = length(suffixes)
    index = if value == 0, do: 0, else: floor(:math.log10(abs(value)) / :math.log10(factor))
    suffix = Enum.at(suffixes, clamp(offset + index, 0, count - 1))
    power = clamp(index, -offset, count - offset - 1)
    formatted(to_fixed(value / :math.pow(factor, power), decimals), suffix)
  end

  defp decimals_for(value) when value == 0, do: 0

  defp decimals_for(value) do
    size = abs(value)
    log10 = floor(:math.log(size) / :math.log(10))
    dec = -log10 + 1
    norm = size / :math.pow(10, -dec)
    dec = if norm > 2.25, do: dec + 1, else: dec
    if integral?(value), do: 0, else: max(0, dec)
  end

  defp integral?(value), do: value == trunc(value)

  defp plural(suffix, true) when suffix in @plural_suffixes, do: suffix <> "s"
  defp plural(suffix, _condition), do: suffix

  defp zero(0), do: "0"
  defp zero(decimals), do: "0." <> String.duplicate("0", decimals)

  defp pad(formatted, decimals) do
    if String.contains?(formatted, "e"),
      do: formatted,
      else: pad_fraction(formatted, decimals, precision(formatted))
  end

  defp precision(formatted) do
    case String.split(formatted, ".") do
      [_whole] -> 0
      [_whole, fraction] -> String.length(fraction)
    end
  end

  defp pad_fraction(formatted, decimals, precision) when precision >= decimals, do: formatted

  defp pad_fraction(formatted, decimals, 0),
    do: formatted <> "." <> String.duplicate("0", decimals)

  defp pad_fraction(formatted, decimals, precision),
    do: formatted <> String.duplicate("0", decimals - precision)

  defp js_round(value), do: floor(value + 0.5)

  defp js_string(value) when is_integer(value), do: Integer.to_string(value)

  defp js_string(value) when value == trunc(value) and abs(value) < 1.0e21,
    do: Integer.to_string(trunc(value))

  defp js_string(value) do
    value
    |> Float.to_string()
    |> String.replace(~r/\.0e/, "e")
    |> String.replace(~r/e(\d)/, "e+\\1")
  end

  defp hex(value, decimals) do
    number = value |> to_fixed(decimals) |> parse_number()
    sign = if number < 0, do: "-", else: ""
    whole = number |> abs() |> trunc()
    fraction = abs(number) - whole
    sign <> Integer.to_string(whole, 16) <> hex_fraction(fraction, "")
  end

  defp parse_number(text) do
    {number, _rest} = Float.parse(text)
    if integral?(number), do: trunc(number), else: number
  end

  defp hex_fraction(fraction, acc) when fraction == 0 or byte_size(acc) >= 13,
    do: if(acc == "", do: "", else: "." <> acc)

  defp hex_fraction(fraction, acc) do
    scaled = fraction * 16
    digit = trunc(scaled)
    hex_fraction(scaled - digit, acc <> Integer.to_string(digit, 16))
  end

  defp exponential(value, nil) do
    {digits, exponent} = shortest_digits(abs(value))
    mantissa = mantissa(digits)
    sign(value) <> mantissa <> exponent_text(exponent)
  end

  defp exponential(value, decimals) do
    [mantissa, exponent] =
      value
      |> abs()
      |> Kernel.*(1.0)
      |> :erlang.float_to_binary(scientific: decimals)
      |> String.split("e")

    sign(value) <> mantissa <> exponent_text(String.to_integer(exponent))
  end

  defp shortest_digits(value) when value == 0, do: {"0", 0}

  defp shortest_digits(value) do
    exponent = floor(:math.log10(value))
    text = Float.to_string(value * 1.0)

    digits =
      text
      |> String.split("e")
      |> hd()
      |> String.replace(".", "")
      |> String.trim_leading("0")
      |> String.trim_trailing("0")

    {if(digits == "", do: "0", else: digits), exponent}
  end

  defp mantissa(<<first::binary-size(1)>>), do: first
  defp mantissa(<<first::binary-size(1), rest::binary>>), do: first <> "." <> rest

  defp exponent_text(exponent) when exponent < 0, do: "e" <> Integer.to_string(exponent)
  defp exponent_text(exponent), do: "e+" <> Integer.to_string(exponent)

  defp sign(value) when value < 0, do: "-"
  defp sign(_value), do: ""

  defp grouped(value, decimals) do
    rounded = Float.round(value * 1.0, decimals)
    [whole | fraction] = rounded |> abs() |> js_string() |> String.split(".")

    groups =
      whole
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    sign(rounded) <> groups <> Enum.map_join(fraction, &("." <> &1))
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
