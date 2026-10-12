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

  Otherwise the first series, reduced by the panel's `reduceOptions.calcs`
  (`GrafExTerm.Panel.Reduce`), is drawn as `GrafExTerm.Panel.Stat.Reading`
  describes it: a value mapping's text, or the number formatted for the panel's
  unit and decimals with the unit on its own line beneath, in the first font of the
  `:stat_fonts` application environment list that fits the panel. Names that
  are not in `Drafter.Widget.Digits.Font.names/0` are skipped; with none left
  the list is `[:braille, :mini, :compact]`. Text no font fits is written plainly
  on one row. Panels whose `graphMode` is
  `"area"` also get that series' history as a darker sparkline behind the
  digits. Numbers are centred in the panel.

  `options.colorMode` decides where the reading's colour goes: `"value"` (the
  default) colours the text, `"background"` and `"background_solid"` fill the
  panel (see `background/2`) under a contrasting text colour, `"none"` leaves
  both uncoloured.
  """

  import Drafter.App,
    only: [vertical: 2, horizontal: 2, digits: 2, label: 2, switch: 1, placeholder: 1]

  alias Drafter.Widget.Digits.Font
  alias GrafExTerm.Panel.{ColorRules, Reduce}
  alias GrafExTerm.Panel.Stat.Reading

  @doc """
  Builds the stat widget for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`. `data` must be
  `{:ok, series}`; anything else draws a "No data" placeholder. `height` is
  the widget height in terminal rows.

  An empty series list is valid and renders as zero. The numeric form reads
  only the first series; the switch form draws one switch per series.

  The colour comes from a matching value mapping, else the last threshold step
  reached, else `{200, 200, 200}`; a step with no colour is green.
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
    reading = Reading.of(panel, reduced_value(panel, series))
    {fg, bg} = colors(color_mode(panel), reading.color)
    style = if bg, do: %{fg: fg, bg: bg}, else: %{fg: fg}

    number =
      digits(
        reading.text,
        [fit: number_fonts(), flex: 1, align: :center, style: style] ++
          sparkline(panel, series, reading.color)
      )

    vertical([number | unit_label(reading.unit, style)], height: height)
  end

  @doc """
  The colour a stat panel fills its frame with: the reading's colour when the
  panel's `options.colorMode` is `"background"` or `"background_solid"`, else `nil`.
  """
  @spec background(GrafExTerm.Dashboard.Types.Panel.t(), term()) :: {byte(), byte(), byte()} | nil
  def background(panel, {:ok, series}) do
    case {color_mode(panel), boolean_mappings(panel.field_config)} do
      {:background, :not_boolean} -> Reading.of(panel, reduced_value(panel, series)).color
      _other -> nil
    end
  end

  def background(_panel, _data), do: nil

  defp color_mode(panel) do
    case get_in(panel.options, ["colorMode"]) do
      mode when mode in ["background", "background_solid"] -> :background
      "none" -> :none
      _value -> :value
    end
  end

  defp colors(:background, color), do: {ColorRules.contrasting_fg(color), color}
  defp colors(:none, _color), do: {nil, nil}
  defp colors(:value, color), do: {color, nil}

  defp unit_label("", _style), do: []
  defp unit_label(unit, style), do: [label(unit, align: :center, style: style)]

  defp sparkline(panel, series, color) do
    if get_in(panel.options, ["graphMode"]) == "area" do
      {bg_min, bg_max} = data_range(panel.field_config)
      [bg_data: extract_history(series), color: dim(color), bg_min: bg_min, bg_max: bg_max]
    else
      []
    end
  end

  defp reduced_value(_panel, []), do: 0.0
  defp reduced_value(panel, [first | _]), do: Reduce.value(first.values, Reduce.calc(panel))
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
end
