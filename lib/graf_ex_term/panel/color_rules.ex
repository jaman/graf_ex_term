defmodule GrafExTerm.Panel.ColorRules do
  @moduledoc """
  Turns a Grafana `fieldConfig` into per-column functions that colour a table
  cell from its value.

  Two Grafana mechanisms are supported and combined. Value mappings match a
  cell's string form exactly and win outright. Thresholds are ordered steps,
  and the colour is that of the last step whose value the cell reaches; the
  base step, whose value is `null`, is never enough on its own — a
  `fieldConfig` with only a base step produces no colouring at all.

  Colours may be Grafana palette names such as `"green"` or `"semi-dark-blue"`,
  or `#rrggbb` hex. `"transparent"` and unrecognised names resolve to no
  colour. Each background is paired with a foreground chosen for contrast, so
  a caller gets a legible pair rather than having to compute one.

      %{cpu: color_fn} = GrafExTerm.Panel.ColorRules.build(field_config, columns)
      color_fn.(95)
  """

  import Bitwise

  @grafana_colors %{
    "green" => {115, 191, 105},
    "dark-green" => {55, 135, 45},
    "light-green" => {150, 217, 141},
    "yellow" => {242, 204, 12},
    "orange" => {250, 150, 0},
    "dark-orange" => {187, 111, 0},
    "red" => {242, 73, 92},
    "dark-red" => {196, 22, 42},
    "light-red" => {255, 115, 131},
    "blue" => {100, 149, 237},
    "dark-blue" => {31, 96, 196},
    "semi-dark-blue" => {50, 116, 217},
    "light-blue" => {138, 184, 255},
    "purple" => {163, 82, 204},
    "dark-purple" => {123, 52, 164},
    "light-purple" => {196, 175, 255},
    "transparent" => nil
  }

  @contrast_cache Map.new(@grafana_colors, fn
                    {_name, nil} ->
                      {nil, {240, 240, 240}}

                    {_name, {r, g, b} = bg} ->
                      luma = 0.299 * r + 0.587 * g + 0.114 * b
                      fg = if luma > 128, do: {15, 15, 15}, else: {240, 240, 240}
                      {bg, fg}
                  end)

  @doc """
  Resolves a Grafana colour to `{r, g, b}`.

  `name` is a palette name such as `"green"`, `"dark-orange"` or
  `"semi-dark-blue"`, or a `#rrggbb` hex string. Returns `nil` for
  `"transparent"`, for a name outside the palette, and for hex that is not
  exactly six valid hex digits.
  """
  @spec resolve_named_color(String.t()) :: {byte(), byte(), byte()} | nil
  def resolve_named_color(name), do: resolve_color(name)

  @doc """
  Picks a legible foreground for the background `bg`.

  `bg` is an `{r, g, b}` tuple of 0..255 integers. Returns `{15, 15, 15}` when
  the background's luma exceeds 128 and `{240, 240, 240}` otherwise.
  """
  @spec contrasting_fg({byte(), byte(), byte()}) :: {byte(), byte(), byte()}
  def contrasting_fg({r, g, b} = bg) do
    case Map.get(@contrast_cache, bg) do
      nil ->
        luma = 0.299 * r + 0.587 * g + 0.114 * b
        if luma > 128, do: {15, 15, 15}, else: {240, 240, 240}

      fg ->
        fg
    end
  end

  @doc """
  Builds a colouring function for each column.

  `field_config` is a panel's raw Grafana `fieldConfig` map: `"defaults"`
  supplies the mappings and thresholds every column starts from, and
  `"overrides"` may replace either for a named column. Only `byName` matchers
  are honoured; the name is matched case-insensitively against the column's
  `:label` first and its `:key` second.

  `columns` is a list of column maps, each with at least `:key` (an atom) and
  `:label` (a string).

  Returns a map from column key to either `nil`, meaning that column is never
  coloured, or a one-argument function. That function takes a cell value and
  returns `%{bg: {r, g, b}, fg: {r, g, b}}` or `nil` when nothing matches.
  Values are compared as strings against mappings and coerced to numbers for
  thresholds, so a numeric string works either way; a value that is neither
  number nor numeric string never satisfies a threshold.
  """
  @spec build(map(), [map()]) :: %{atom() => (term() -> {byte(), byte(), byte()} | nil) | nil}
  def build(field_config, columns) do
    defaults = Map.get(field_config, "defaults", %{})
    overrides = Map.get(field_config, "overrides", [])

    default_mappings = parse_value_mappings(Map.get(defaults, "mappings", []))
    default_thresholds = parse_thresholds(Map.get(defaults, "thresholds", %{}))
    override_map = build_override_map(overrides)

    Map.new(columns, fn col ->
      col_overrides = find_column_overrides(col, override_map)
      mappings = Map.get(col_overrides, :mappings, default_mappings)
      thresholds = Map.get(col_overrides, :thresholds, default_thresholds)
      {col.key, build_color_fn(mappings, thresholds)}
    end)
  end

  @doc """
  Returns the default threshold steps of `field_config`, lowest first.

  Each step is `{value, color}`: `value` is the number the step starts at, or
  `nil` for the base step, which always comes first; `color` is `{r, g, b}`
  or `nil` when the step's colour does not resolve. Returns `[]` when the
  panel defines no thresholds.
  """
  @spec threshold_steps(map()) :: [{number() | nil, {byte(), byte(), byte()} | nil}]
  def threshold_steps(field_config) do
    field_config
    |> get_in(["defaults", "thresholds"])
    |> parse_thresholds()
  end

  defp parse_value_mappings(mappings) when is_list(mappings) do
    Enum.flat_map(mappings, fn
      %{"type" => "value", "options" => options} when is_map(options) ->
        extract_value_colors(options)

      _ ->
        []
    end)
  end

  defp parse_value_mappings(_), do: []

  defp extract_value_colors(options) do
    Enum.flat_map(options, fn {value, config} ->
      case resolve_color(Map.get(config, "color")) do
        nil -> []
        color -> [{value, color}]
      end
    end)
  end

  defp parse_thresholds(%{"steps" => steps}) when is_list(steps) do
    steps
    |> Enum.map(fn step ->
      {Map.get(step, "value"), resolve_color(Map.get(step, "color"))}
    end)
    |> Enum.sort_by(fn {v, _} -> if is_nil(v), do: {0, 0}, else: {1, v} end)
  end

  defp parse_thresholds(_), do: []

  defp build_override_map(overrides) do
    Enum.reduce(overrides, %{}, &accumulate_override/2)
  end

  defp accumulate_override(override, acc) do
    case get_in(override, ["matcher", "id"]) do
      "byName" ->
        name = get_in(override, ["matcher", "options"])
        entry = parse_override_properties(Map.get(override, "properties", []))
        Map.put(acc, String.downcase(name), entry)

      _ ->
        acc
    end
  end

  defp parse_override_properties(properties) do
    props = Map.new(properties, fn p -> {p["id"], p["value"]} end)

    entry = %{}

    entry =
      case props["thresholds"] do
        nil -> entry
        t -> Map.put(entry, :thresholds, parse_thresholds(t))
      end

    case props["mappings"] do
      nil -> entry
      m -> Map.put(entry, :mappings, parse_value_mappings(m))
    end
  end

  defp find_column_overrides(col, override_map) do
    key_str = col.key |> to_string() |> String.downcase()
    label_str = col.label |> String.downcase()

    Map.get(override_map, label_str) ||
      Map.get(override_map, key_str) ||
      %{}
  end

  defp build_color_fn([], []), do: nil

  defp build_color_fn([], thresholds) do
    if has_valued_steps?(thresholds) do
      fn value -> with_contrast(apply_thresholds(value, thresholds)) end
    else
      nil
    end
  end

  defp build_color_fn(mappings, thresholds) do
    fn value -> resolve_cell_color(value, mappings, thresholds) end
  end

  defp resolve_cell_color(value, mappings, thresholds) do
    str_val = to_string(value)

    case Enum.find(mappings, fn {k, _} -> k == str_val end) do
      {_, color} ->
        with_contrast(color)

      nil ->
        if has_valued_steps?(thresholds), do: with_contrast(apply_thresholds(value, thresholds))
    end
  end

  defp with_contrast(nil), do: nil
  defp with_contrast(bg), do: %{bg: bg, fg: contrasting_fg(bg)}

  defp has_valued_steps?(steps) do
    Enum.any?(steps, fn {v, _} -> v != nil end)
  end

  defp apply_thresholds(value, steps) do
    num = to_number(value)

    if num == nil do
      nil
    else
      steps
      |> Enum.filter(fn {v, _} -> v == nil or num >= v end)
      |> List.last()
      |> case do
        nil -> nil
        {_, color} -> color
      end
    end
  end

  defp to_number(v) when is_number(v), do: v

  defp to_number(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp to_number(_), do: nil

  defp resolve_color(nil), do: nil
  defp resolve_color("transparent"), do: nil

  defp resolve_color("#" <> hex) do
    case Integer.parse(hex, 16) do
      {n, ""} when byte_size(hex) == 6 ->
        r = Bitwise.bsr(n, 16) &&& 0xFF
        g = Bitwise.bsr(n, 8) &&& 0xFF
        b = n &&& 0xFF
        {r, g, b}

      _ ->
        nil
    end
  end

  defp resolve_color(name) when is_binary(name), do: Map.get(@grafana_colors, name)
  defp resolve_color(_), do: nil
end
