defmodule GrafExTerm.Panel.Table do
  @moduledoc false
  alias GrafExTerm.Panel.ColorRules

  import Drafter.App, only: [
    data_table: 1,
    placeholder: 1,
    vertical: 2,
    collapsible: 3,
    checkbox: 2
  ]

  def prepare(data, organize \\ nil, field_config \\ %{})

  def prepare({:table, columns, rows}, organize, field_config) do
    {rows, cols} = apply_organize(columns, rows, organize)
    {rows, attach_color_fns(cols, field_config)}
  end

  def prepare({:ok, series}, organize, field_config) do
    rows = series_to_rows(series)
    {rows, cols} = apply_organize(derive_columns(rows), rows, organize)
    {rows, attach_color_fns(cols, field_config)}
  end

  def prepare(_, _, _), do: {[], []}

  def render(panel, data, height, visible_columns \\ nil, layout \\ nil)

  def render(panel, {:prepared, rows, all_columns}, height, visible_columns, layout) do
    render_table(panel, rows, all_columns, height, visible_columns, layout)
  end

  def render(panel, {:ok, series}, height, visible_columns, layout) do
    {rows, all_columns} = prepare({:ok, series})
    render_table(panel, rows, all_columns, height, visible_columns, layout)
  end

  def render(_panel, _, height, _visible_columns, _layout) do
    placeholder(label: "No data", height: height)
  end

  defp render_table(panel, rows, all_columns, height, visible_columns, layout) do
    active_columns =
      if visible_columns == nil or MapSet.size(visible_columns) == 0 do
        all_columns
      else
        Enum.filter(all_columns, fn c -> MapSet.member?(visible_columns, c.key) end)
      end

    col_count = length(all_columns)
    col_selector_height = min(col_count, 6)

    checkboxes =
      Enum.map(all_columns, fn c ->
        checked = visible_columns == nil or MapSet.member?(visible_columns, c.key)
        checkbox(c.label,
          id: :"col_#{panel.id}_#{c.key}",
          checked: checked,
          on_change: {:toggle_column, panel.id, c.key}
        )
      end)

    col_toggle =
      collapsible(
        "Columns",
        checkboxes,
        id: :"col_toggle_#{panel.id}",
        content_height: col_count,
        expanded: false
      )

    table_height = max(3, height - col_selector_height - 2)

    layout_opts = if layout do
      [col_widths: layout.col_widths, col_order: layout.col_order]
    else
      []
    end

    table_widget =
      data_table(
        [
          id: :"data_table_#{panel.id}",
          columns: active_columns,
          data: rows,
          show_header: true,
          zebra_stripes: true,
          height: table_height,
          selection_mode: :multiple,
          on_select: {:table_row_selected, panel.id},
          on_layout_change: {:table_layout_changed, panel.id}
        ] ++ layout_opts
      )

    vertical([col_toggle, table_widget], height: height)
  end

  defp attach_color_fns(columns, field_config) when map_size(field_config) == 0, do: columns
  defp attach_color_fns(columns, field_config) do
    color_map = ColorRules.build(field_config, columns)
    Enum.map(columns, fn col ->
      case Map.get(color_map, col.key) do
        nil -> col
        f -> Map.put(col, :color_fn, f)
      end
    end)
  end

  defp apply_organize(columns, rows, nil), do: {rows, columns}

  defp apply_organize(columns, rows, organize) do
    exclude = normalize_keys(organize.exclude)
    rename = normalize_keys(organize.rename)
    index = normalize_keys(organize.index)

    organized =
      columns
      |> Enum.reject(fn col ->
        Map.get(exclude, normalize(col), false) == true
      end)
      |> Enum.map(fn col ->
        new_label = Map.get(rename, normalize(col), col.label)
        %{col | label: new_label}
      end)
      |> Enum.sort_by(fn col ->
        Map.get(index, normalize(col), 999)
      end)

    {rows, organized}
  end

  defp normalize_keys(map) do
    Map.new(map, fn {k, v} -> {String.downcase(k), v} end)
  end

  defp normalize(%{key: key}), do: key |> to_string() |> String.downcase()

  defp series_to_rows([]), do: []

  defp series_to_rows(series) do
    series
    |> Enum.flat_map(&series_entry_to_rows/1)
    |> Enum.take(100)
  end

  defp series_entry_to_rows(s) do
    label_fields = Map.new(s.labels, fn {k, v} -> {String.to_atom(k), v} end)

    Enum.map(s.values, fn {ts, val} ->
      Map.merge(label_fields, %{time: format_time(ts), value: Float.round(val * 1.0, 2)})
    end)
  end

  defp derive_columns([]), do: []

  defp derive_columns([first | _]) do
    fixed = [
      %{key: :time, label: "Time", width: 20},
      %{key: :value, label: "Value", width: 12}
    ]

    label_keys =
      first
      |> Map.drop([:time, :value])
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(fn key ->
        %{key: key, label: key |> to_string() |> String.capitalize(), width: :auto}
      end)

    fixed ++ label_keys
  end

  defp format_time(unix_ts) do
    case DateTime.from_unix(unix_ts) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      _ -> to_string(unix_ts)
    end
  end
end
