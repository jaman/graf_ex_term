defmodule GrafExTerm.Dashboard.Parser do
  alias GrafExTerm.Dashboard.Types.{Dashboard, Panel, Target, TemplateVar}

  def parse(%{"dashboard" => nested}) when is_map(nested), do: parse(nested)

  def parse(raw) when is_map(raw) do
    panels =
      raw
      |> Map.get("panels", [])
      |> Enum.flat_map(&flatten_panel/1)

    templating =
      raw
      |> get_in(["templating", "list"])
      |> List.wrap()
      |> Enum.map(&parse_template_var/1)

    dashboard = %Dashboard{
      uid: Map.get(raw, "uid", ""),
      title: Map.get(raw, "title", "Untitled"),
      description: Map.get(raw, "description", ""),
      panels: panels,
      templating: templating,
      refresh: Map.get(raw, "refresh", false)
    }

    {:ok, dashboard}
  end

  defp flatten_panel(%{"type" => "row", "panels" => nested} = row_panel) when is_list(nested) do
    row = parse_panel(row_panel)
    [row | Enum.map(nested, &parse_panel/1)]
  end

  defp flatten_panel(panel), do: [parse_panel(panel)]

  defp parse_panel(raw) do
    %Panel{
      id: Map.get(raw, "id"),
      title: Map.get(raw, "title", ""),
      type: Map.get(raw, "type", "unknown"),
      grid_pos: parse_grid_pos(Map.get(raw, "gridPos", %{})),
      targets: parse_targets(Map.get(raw, "targets", [])),
      field_config: Map.get(raw, "fieldConfig", %{}),
      options: Map.get(raw, "options", %{}),
      panels: Map.get(raw, "panels", []),
      organize: parse_organize(Map.get(raw, "transformations", []))
    }
  end

  defp parse_grid_pos(gp) do
    %{
      x: Map.get(gp, "x", 0),
      y: Map.get(gp, "y", 0),
      w: Map.get(gp, "w", 12),
      h: Map.get(gp, "h", 8)
    }
  end

  defp parse_targets(targets) when is_list(targets) do
    Enum.map(targets, fn t ->
      %Target{
        expr: Map.get(t, "expr", ""),
        legend_format: Map.get(t, "legendFormat", ""),
        ref_id: Map.get(t, "refId", "A"),
        datasource_ref: parse_datasource_ref(Map.get(t, "datasource")),
        instant: Map.get(t, "instant", false),
        format: Map.get(t, "format")
      }
    end)
  end

  defp parse_datasource_ref(%{"uid" => uid}), do: uid
  defp parse_datasource_ref(ref) when is_binary(ref), do: ref
  defp parse_datasource_ref(_), do: nil

  @spec datasource_vars(Dashboard.t()) :: [String.t()]
  def datasource_vars(%Dashboard{panels: panels}) do
    panels
    |> Enum.flat_map(fn panel -> panel.targets end)
    |> Enum.flat_map(fn target ->
      case target.datasource_ref do
        nil -> []
        ref -> extract_var_name(ref)
      end
    end)
    |> Enum.uniq()
  end

  defp parse_organize(transforms) do
    Enum.find_value(transforms, nil, fn
      %{"id" => "organize", "options" => opts} ->
        %{
          exclude: Map.get(opts, "excludeByName", %{}),
          rename: Map.get(opts, "renameByName", %{}),
          index: Map.get(opts, "indexByName", %{})
        }
      _ -> nil
    end)
  end

  defp extract_var_name(ref) do
    case Regex.run(~r/^\$\{?(\w+)\}?$/, ref) do
      [_, name] -> [name]
      _ -> []
    end
  end

  defp parse_template_var(raw) do
    current_value =
      raw
      |> Map.get("current", %{})
      |> Map.get("value", "")

    options_list =
      raw
      |> Map.get("options", [])
      |> Enum.map(&Map.get(&1, "value", ""))

    %TemplateVar{
      name: Map.get(raw, "name", ""),
      type: Map.get(raw, "type", "query"),
      current_value: current_value,
      options_list: options_list,
      query: parse_var_query(Map.get(raw, "query", ""))
    }
  end

  defp parse_var_query(%{"query" => q}), do: q
  defp parse_var_query(q) when is_binary(q), do: q
  defp parse_var_query(_), do: ""
end
