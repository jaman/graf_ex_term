defmodule GrafExTerm.Panel.Table do
  @moduledoc """
  Draws a Grafana `table` panel as a Drafter data table.

  Preparation and rendering are split. `prepare/3` derives rows and columns
  from fetched data, applies the panel's `organize` transformation and
  attaches colour functions; `render/6` turns that into a widget. A screen is
  expected to prepare once when data arrives and render every frame — and
  `prepare/3` is the only path that applies organize and colouring, so a
  caller that skips it gets an uncoloured table with unmodified columns.

  Rows are selectable, and selection is reported to the screen as
  `{:table_row_selected, panel_id}` carrying the selected row maps. Column
  widths and order changed by the user are reported as
  `{:table_layout_changed, panel_id}`.
  """

  alias GrafExTerm.Panel.ColorRules

  import Drafter.App,
    only: [
      data_table: 1,
      placeholder: 1,
      vertical: 2,
      collapsible: 3,
      checkbox: 2
    ]

  @doc """
  Derives the rows and columns to display from fetched panel data.

  `data` is one of:

    * `{:table, columns, rows}` — an instant table already shaped by
      `GrafExTerm.Refresh.Scheduler`; columns and rows are used as given
    * `{:ok, series}` — range series, which are flattened to one row per
      sample with a formatted `:time`, a `:value` rounded to two decimals, and
      one column per metric label. The result is capped at 100 rows.
    * anything else — yields `{[], []}`

  `organize` is a panel's `:organize` map, `%{exclude: map, rename: map,
  index: map}`, keyed by lowercased column name. Columns marked `true` under
  `exclude` are dropped, `rename` replaces labels, and `index` sets the order,
  with unlisted columns sorted to the end. Defaults to `nil`, which leaves
  columns as derived.

  `field_config` is the panel's raw Grafana `fieldConfig`, used to attach a
  `:color_fn` to each column that has thresholds or value mappings. Defaults
  to `%{}`, which attaches none.

  Returns `{rows, columns}`. Rows are maps keyed by column key; columns are
  maps with `:key`, `:label`, `:width` and optionally `:color_fn`.
  """
  @spec prepare(term(), map() | nil, map()) :: {[map()], [map()]}
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

  @doc """
  Builds the table widget for `panel`.

  `panel` is a `GrafExTerm.Dashboard.Types.Panel`; its `:id` becomes the
  widget id `:"data_table_<id>"`. `data` is either `{:prepared, rows,
  columns}` wrapping the output of `prepare/3`, or a raw `{:ok, series}`,
  which is prepared inline without organize or colouring; anything else draws
  a "No data" placeholder. `height` is the widget height in terminal rows.

  `visible_columns` is a `MapSet` of column keys to show. `nil` or an empty
  set shows every column. Defaults to `nil`.

  `layout` is `%{col_widths: widths, col_order: order}` restoring a user's
  column sizing, or `nil` to let the table size itself. Defaults to `nil`.

  `column_filter` adds a collapsible "Columns" checkbox list above the table.
  It consumes up to 8 rows of `height`, and the table is never left with fewer
  than 3. Defaults to `false`.
  """
  @spec render(
          GrafExTerm.Dashboard.Types.Panel.t(),
          term(),
          non_neg_integer(),
          MapSet.t() | nil,
          map() | nil,
          boolean()
        ) :: tuple()
  def render(panel, data, height, visible_columns \\ nil, layout \\ nil, column_filter \\ false)

  def render(
        panel,
        {:prepared, rows, all_columns},
        height,
        visible_columns,
        layout,
        column_filter
      ) do
    render_table(panel, rows, all_columns, height, visible_columns, layout, column_filter)
  end

  def render(panel, {:ok, series}, height, visible_columns, layout, column_filter) do
    {rows, all_columns} = prepare({:ok, series})
    render_table(panel, rows, all_columns, height, visible_columns, layout, column_filter)
  end

  def render(_panel, _, height, _visible_columns, _layout, _column_filter) do
    placeholder(label: "No data", height: height)
  end

  defp render_table(panel, rows, all_columns, height, visible_columns, layout, column_filter) do
    active_columns =
      if visible_columns == nil or MapSet.size(visible_columns) == 0 do
        all_columns
      else
        Enum.filter(all_columns, fn c -> MapSet.member?(visible_columns, c.key) end)
      end

    layout_opts =
      if layout do
        [col_widths: layout.col_widths, col_order: layout.col_order]
      else
        []
      end

    if column_filter do
      render_table_with_filter(
        panel,
        rows,
        all_columns,
        active_columns,
        height,
        visible_columns,
        layout_opts
      )
    else
      render_table_plain(panel, rows, active_columns, height, layout_opts)
    end
  end

  defp render_table_with_filter(
         panel,
         rows,
         all_columns,
         active_columns,
         height,
         visible_columns,
         layout_opts
       ) do
    col_count = length(all_columns)

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

    col_selector_height = min(col_count, 6)
    table_height = max(3, height - col_selector_height - 2)

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

    vertical([col_toggle, table_widget], [])
  end

  defp render_table_plain(panel, rows, active_columns, height, layout_opts) do
    table_widget =
      data_table(
        [
          id: :"data_table_#{panel.id}",
          columns: active_columns,
          data: rows,
          show_header: true,
          zebra_stripes: true,
          height: height,
          selection_mode: :multiple,
          on_select: {:table_row_selected, panel.id},
          on_layout_change: {:table_layout_changed, panel.id}
        ] ++ layout_opts
      )

    table_widget
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
