defmodule GrafExTerm.Panel.Stat do
  @moduledoc """
  Draws a Grafana `stat` panel, either as a large formatted number or as a row
  of on/off switches.

  The switch form is chosen automatically: when the panel's value mappings
  define exactly two texts that form a known boolean pair — true/false,
  yes/no, on/off, up/down, enabled/disabled, active/inactive, or 1/0 — each
  series is drawn as a switch rather than a number. Which of the two is "on"
  is decided by the mapped value, not the text, so a mapping of `1` to
  `"Down"` renders `"Down"` as the on state.

  Otherwise the first series' last sample is drawn as digits, formatted for
  the panel's unit and coloured by its thresholds, in the first font of the
  `:stat_fonts` application environment list that fits the panel. Names that
  are not in `Drafter.Widget.Digits.Font.names/0` are skipped; with none left
  the list is `[:braille, :mini, :compact]`. Panels whose `graphMode` is
  `"area"` also get that series' history as a darker sparkline behind the
  digits. Numbers are centred in the panel.

  Recognised units are `percent`, `percentunit`, `bytes`, `decbytes`, `bits`,
  `short`, and the durations `s`, `ms` and `ns`; anything else is formatted
  compactly. Durations are scaled to the largest of weeks, days, hours,
  minutes or seconds that the value reaches.
  """

  import Drafter.App,
    only: [vertical: 2, horizontal: 2, digits: 2, switch: 1, placeholder: 1]

  alias Drafter.Format
  alias Drafter.Widget.Digits.Font
  alias GrafExTerm.Panel.ColorRules

  @doc """
  Builds the stat widget for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`. `data` must be
  `{:ok, series}`; anything else draws a "No data" placeholder. `height` is
  the widget height in terminal rows.

  An empty series list is valid and renders as zero. The numeric form reads
  only the first series; the switch form draws one switch per series.

  Threshold colouring falls back to `{200, 200, 200}` when the panel defines
  no thresholds or the reached step's colour names no colour (`"transparent"`,
  `"text"`), and a step with no colour defaults to green.
  """
  @spec render(GrafExTerm.Dashboard.Types.Panel.t(), term(), non_neg_integer()) :: tuple()
  def render(panel, {:ok, series}, height) do
    case boolean_mappings(panel.field_config) do
      {:boolean, on_text, off_text, on_color, off_color} ->
        render_boolean(panel, series, height, on_text, off_text, on_color, off_color)

      :not_boolean ->
        render_numeric(panel, series, height)
    end
  end

  def render(_panel, _, _height) do
    vertical(
      [placeholder(label: "No data")],
      []
    )
  end

  defp render_boolean(panel, series, height, on_text, off_text, on_color, off_color) do
    switches =
      Enum.map(series, fn s ->
        value = last_value(s.values)
        is_on = value >= 1.0
        series_label = series_display_name(s, panel.title)
        text = if is_on, do: on_text, else: off_text

        horizontal(
          [
            switch(
              enabled: is_on,
              label: "#{series_label}: #{text}",
              size: :compact,
              on_color: on_color,
              off_color: off_color
            )
          ],
          []
        )
      end)

    vertical(
      switches,
      height: height
    )
  end

  defp render_numeric(panel, series, height) do
    value = extract_last_value(series)
    unit = get_in(panel.field_config, ["defaults", "unit"]) || ""
    formatted = format_value(value, unit)
    color = threshold_color(panel.field_config, value)
    graph_mode = get_in(panel.options, ["graphMode"]) || "none"

    digit_opts =
      if graph_mode == "area" do
        hist = extract_history(series)
        {bg_min, bg_max} = data_range(panel.field_config)

        [
          fit: number_fonts(),
          flex: 1,
          align: :center,
          style: %{fg: color},
          bg_data: hist,
          color: dim(color),
          bg_min: bg_min,
          bg_max: bg_max
        ]
      else
        [fit: number_fonts(), flex: 1, align: :center, style: %{fg: color}]
      end

    vertical(
      [digits(formatted, digit_opts)],
      height: height
    )
  end

  @default_color {200, 200, 200}
  @default_number_fonts [:braille, :mini, :compact]

  defp number_fonts do
    known = Font.names()

    case :graf_ex_term
         |> Application.get_env(:stat_fonts)
         |> List.wrap()
         |> Enum.filter(&(&1 in known)) do
      [] -> @default_number_fonts
      fonts -> fonts
    end
  end

  @sparkline_brightness 0.45

  defp dim({r, g, b}),
    do:
      {round(r * @sparkline_brightness), round(g * @sparkline_brightness),
       round(b * @sparkline_brightness)}

  defp extract_last_value([]), do: 0.0

  defp extract_last_value(series) do
    series
    |> List.first()
    |> Map.get(:values, [])
    |> List.last()
    |> case do
      nil -> 0.0
      {_, val} -> val
    end
  end

  defp extract_history([]), do: []

  defp extract_history(series) do
    series
    |> List.first()
    |> Map.get(:values, [])
    |> Enum.map(fn {_, val} -> val end)
  end

  defp data_range(field_config) do
    defaults = get_in(field_config, ["defaults"]) || %{}
    min = Map.get(defaults, "min")
    max = Map.get(defaults, "max")
    {if(is_number(min), do: min, else: 0), if(is_number(max), do: max, else: nil)}
  end

  defp format_value(value, _unit) when not is_number(value), do: to_string(value)
  defp format_value(value, "percent"), do: Format.percent(value, decimals: 1)
  defp format_value(value, "percentunit"), do: Format.percent(value, as_ratio: true, decimals: 1)
  defp format_value(value, "bytes"), do: Format.bytes(value)
  defp format_value(value, "decbytes"), do: Format.bytes(value)
  defp format_value(value, "bits"), do: Format.bytes(trunc(value / 8))
  defp format_value(value, "short"), do: Format.compact(value)
  defp format_value(value, "s"), do: format_duration(value)
  defp format_value(value, "ms"), do: format_duration(value / 1000)
  defp format_value(value, "ns"), do: format_duration(value / 1_000_000_000)
  defp format_value(value, _unit), do: Format.compact(value)

  defp format_duration(seconds) when is_number(seconds) do
    cond do
      seconds >= 7 * 24 * 3600 -> "#{Float.round(seconds / (7 * 24 * 3600), 1)}w"
      seconds >= 24 * 3600 -> "#{Float.round(seconds / (24 * 3600), 1)}d"
      seconds >= 3600 -> "#{Float.round(seconds / 3600, 1)}h"
      seconds >= 60 -> "#{Float.round(seconds / 60, 1)}m"
      true -> "#{Float.round(seconds * 1.0, 1)}s"
    end
  end

  defp last_value([]), do: 0.0
  defp last_value(values), do: values |> List.last() |> elem(1)

  defp series_display_name(s, fallback) do
    case Map.get(s, :name) do
      name when is_binary(name) and name != "" -> name
      _ -> fallback
    end
  end

  @boolean_pairs MapSet.new([
                   {"true", "false"},
                   {"yes", "no"},
                   {"on", "off"},
                   {"up", "down"},
                   {"enabled", "disabled"},
                   {"active", "inactive"},
                   {"1", "0"}
                 ])

  defp boolean_mappings(field_config) do
    mappings = get_in(field_config, ["defaults", "mappings"]) || []
    text_map = Enum.reduce(mappings, %{}, &extract_mapping_entries/2)
    classify_boolean_pair(text_map)
  end

  defp extract_mapping_entries(%{"type" => "value", "options" => options}, acc)
       when is_map(options) do
    Enum.reduce(options, acc, &extract_value_option/2)
  end

  defp extract_mapping_entries(%{"type" => type} = mapping, acc) when type in [1, 2] do
    val = to_string(Map.get(mapping, "value", ""))
    text = Map.get(mapping, "text")

    if is_binary(text) and val != "" do
      Map.put(acc, val, {text, Map.get(mapping, "color")})
    else
      acc
    end
  end

  defp extract_mapping_entries(_mapping, acc), do: acc

  defp extract_value_option({key, config}, acc) do
    case Map.get(config, "text") do
      text when is_binary(text) -> Map.put(acc, key, {text, Map.get(config, "color")})
      _ -> acc
    end
  end

  defp classify_boolean_pair(text_map) do
    keys = Map.keys(text_map)

    if length(keys) == 2 do
      [{_k1, {t1, c1}}, {k2, {t2, c2}}] = Enum.sort_by(text_map, fn {k, _} -> k end)
      pair = {String.downcase(t1), String.downcase(t2)}
      reverse_pair = {String.downcase(t2), String.downcase(t1)}

      if MapSet.member?(@boolean_pairs, pair) or MapSet.member?(@boolean_pairs, reverse_pair) do
        build_boolean_result(k2, t1, c1, t2, c2)
      else
        :not_boolean
      end
    else
      :not_boolean
    end
  end

  defp build_boolean_result(k2, t1, c1, t2, c2) do
    {on_text, on_color} =
      if truthy_key?(k2), do: {t2, resolve_color(c2)}, else: {t1, resolve_color(c1)}

    {off_text, off_color} =
      if truthy_key?(k2), do: {t1, resolve_color(c1)}, else: {t2, resolve_color(c2)}

    {:boolean, on_text, off_text, on_color, off_color}
  end

  defp truthy_key?("1"), do: true

  defp truthy_key?(k) do
    String.to_float(k) >= 1.0
  rescue
    _ -> false
  end

  defp resolve_color(nil), do: nil
  defp resolve_color(color), do: ColorRules.resolve_named_color(color)

  defp threshold_color(field_config, value) do
    steps =
      field_config
      |> get_in(["defaults", "thresholds", "steps"])
      |> List.wrap()

    steps
    |> Enum.filter(fn step ->
      threshold = Map.get(step, "value")
      is_nil(threshold) or value >= threshold
    end)
    |> List.last()
    |> case do
      nil -> @default_color
      step -> ColorRules.resolve_named_color(Map.get(step, "color", "green")) || @default_color
    end
  end
end
