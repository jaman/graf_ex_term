defmodule GrafExTerm.Dashboard.GraphMigration do
  @moduledoc """
  Converts a legacy `graph` panel's settings into the `fieldConfig` and `options`
  a `timeseries` panel reads, following Grafana's graph-to-timeseries migration.

  Settings missing from the panel take the graph panel's defaults: lines on,
  `fill` 1, `linewidth` 1, no bars, points or stacking, `nullPointMode`
  `"null"`, and a shared tooltip with `sort` 0.

  Carried over:

    * the first of `yaxes` — `format` as the unit, `decimals`, `min` and `max`
    * `bars`, `lines` and `points` as `custom.drawStyle` (`"bars"`, `"line"` or
      `"points"`)
    * `linewidth` as `custom.lineWidth`
    * `fill` (0–10) as `custom.fillOpacity` (0–100), or `fillGradient` when
      above 0; bars are always 100
    * `nullPointMode` `"connected"` as `custom.spanNulls` `true`
    * `steppedLine` as `custom.lineInterpolation` `"stepAfter"`
    * `stack` as `custom.stacking`, mode `"percent"` with `percentage`, else
      `"normal"`
    * `tooltip.shared` and `tooltip.sort` (1 ascending, 2 descending) as
      `options.tooltip`
    * `seriesOverrides` `transform` values as `custom.transform` overrides,
      matched by name, or by regexp when the alias is written `/.../`

      iex> migrated = GrafExTerm.Dashboard.GraphMigration.migrate(%{"fill" => 0, "stack" => true})
      iex> migrated.field_config["defaults"]["custom"]["fillOpacity"]
      0
      iex> migrated.field_config["defaults"]["custom"]["stacking"]
      %{"mode" => "normal", "group" => "A"}

  """

  @graph_defaults %{
    "lines" => true,
    "fill" => 1,
    "fillGradient" => 0,
    "linewidth" => 1,
    "points" => false,
    "bars" => false,
    "stack" => false,
    "percentage" => false,
    "nullPointMode" => "null",
    "steppedLine" => false,
    "tooltip" => %{"shared" => true, "sort" => 0}
  }

  @regex_alias ~r/^([\/~@;%#'])(.*?)\1([gimsuy]*)$/

  @doc """
  The `fieldConfig` and `options` of the timeseries panel equivalent to `raw`, a
  `graph` panel's JSON map.
  """
  @spec migrate(map()) :: %{field_config: map(), options: map()}
  def migrate(raw) do
    angular = Map.merge(@graph_defaults, raw)
    field_config = Map.get(raw, "fieldConfig") || %{}
    defaults = Map.merge(Map.get(field_config, "defaults") || %{}, axis(first_axis(raw)))
    custom = Map.merge(Map.get(defaults, "custom") || %{}, custom(angular))
    overrides = (Map.get(field_config, "overrides") || []) ++ transform_overrides(raw)

    %{
      field_config: %{"defaults" => Map.put(defaults, "custom", custom), "overrides" => overrides},
      options: Map.put(Map.get(raw, "options") || %{}, "tooltip", tooltip(angular["tooltip"]))
    }
  end

  defp first_axis(%{"yaxes" => [axis | _]}) when is_map(axis), do: axis
  defp first_axis(_raw), do: %{}

  defp axis(axis) do
    %{
      "unit" => axis["format"],
      "decimals" => number(axis["decimals"]),
      "min" => number(axis["min"]),
      "max" => number(axis["max"])
    }
    |> reject_nil()
  end

  defp custom(angular) do
    draw_style = draw_style(angular)

    %{
      "drawStyle" => draw_style,
      "lineWidth" => angular["linewidth"],
      "fillOpacity" => fill_opacity(draw_style, angular),
      "spanNulls" => angular["nullPointMode"] == "connected",
      "lineInterpolation" => if(angular["steppedLine"], do: "stepAfter"),
      "stacking" => stacking(angular)
    }
    |> reject_nil()
  end

  defp draw_style(%{"bars" => true}), do: "bars"
  defp draw_style(%{"lines" => true}), do: "line"
  defp draw_style(_angular), do: "points"

  defp fill_opacity("bars", _angular), do: 100

  defp fill_opacity(_draw_style, %{"fillGradient" => gradient})
       when is_number(gradient) and gradient > 0,
       do: gradient * 10

  defp fill_opacity(_draw_style, %{"fill" => fill}) when is_number(fill), do: fill * 10
  defp fill_opacity(_draw_style, _angular), do: nil

  defp stacking(%{"stack" => true, "percentage" => true}),
    do: %{"mode" => "percent", "group" => "A"}

  defp stacking(%{"stack" => true}), do: %{"mode" => "normal", "group" => "A"}
  defp stacking(_angular), do: nil

  defp tooltip(%{"shared" => shared} = tooltip) do
    %{"mode" => if(shared, do: "multi", else: "single"), "sort" => sort(shared, tooltip["sort"])}
  end

  defp tooltip(_tooltip), do: %{"mode" => "single", "sort" => "none"}

  defp sort(true, 1), do: "asc"
  defp sort(true, 2), do: "desc"
  defp sort(_shared, _sort), do: "none"

  defp transform_overrides(raw) do
    for %{"alias" => alias_name, "transform" => transform} <- List.wrap(raw["seriesOverrides"]),
        is_binary(alias_name) and alias_name != "" do
      %{
        "matcher" => %{"id" => matcher_id(alias_name), "options" => alias_name},
        "properties" => [%{"id" => "custom.transform", "value" => transform_value(transform)}]
      }
    end
  end

  defp matcher_id(alias_name),
    do: if(Regex.match?(@regex_alias, alias_name), do: "byRegexp", else: "byName")

  defp transform_value("negative-Y"), do: "negative-Y"
  defp transform_value(_other), do: "constant"

  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case String.trim(value) do
      "" -> 0
      trimmed -> parsed_number(Float.parse(trimmed))
    end
  end

  defp number(_value), do: nil

  defp parsed_number({number, ""}), do: number
  defp parsed_number(_unparseable), do: nil

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
end
