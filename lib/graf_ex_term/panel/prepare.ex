defmodule GrafExTerm.Panel.Prepare do
  @moduledoc """
  Turns cached panel data into what the panel renderers draw, once per data
  arrival rather than once per frame.

  Visible table panels become `{:prepared, rows, columns}` via
  `GrafExTerm.Panel.Table.prepare/3`; visible timeseries and graph panels
  become `{:prepared_ts, map}` via `GrafExTerm.Panel.Timeseries.prepare/2`,
  heatmap panels `{:prepared_heatmap, matrix}` and logs panels
  `{:prepared_logs, lines}`. Other visible panels and every hidden panel keep
  their cached value.

  `windows` maps panel id to the `GrafExTerm.Refresh.QueryWindow` its series
  were fetched over; a timeseries panel with no window is laid out on the
  timestamps its series have.

  A row filter is a list of label maps, string keys to string values. When one
  is given, series-based panels other than tables keep only the series whose
  labels contain every pair of at least one of the maps.
  """

  alias GrafExTerm.Dashboard.Visibility
  alias GrafExTerm.Panel.{Heatmap, Logs, Table, Timeseries}

  @type row_filter :: [%{String.t() => String.t()}] | nil

  @doc """
  Prepares every entry of `panel_data`, which maps panel id to cached data.

  `panels` is the dashboard's panel list and `collapsed_rows` a `MapSet` of
  collapsed row ids; panels hidden by a collapsed row are not prepared.
  """
  @spec all(map(), [GrafExTerm.Dashboard.Types.Panel.t()], row_filter(), MapSet.t(), map()) ::
          map()
  def all(panel_data, panels, row_filter, collapsed_rows, windows \\ %{}) do
    panel_map = Map.new(panels, &{&1.id, &1})
    active_ids = Visibility.active_panel_ids(panels, collapsed_rows)

    Map.new(panel_data, fn {panel_id, data} ->
      case {MapSet.member?(active_ids, panel_id), Map.get(panel_map, panel_id)} do
        {true, %{} = panel} ->
          {panel_id, single(panel, data, row_filter, Map.get(windows, panel_id))}

        _ ->
          {panel_id, data}
      end
    end)
  end

  @doc """
  Re-prepares the series-based entries of `prepared` from `panel_data` under a
  new `row_filter`, leaving prepared tables as they are.
  """
  @spec refilter(map(), map(), [GrafExTerm.Dashboard.Types.Panel.t()], row_filter(), map()) ::
          map()
  def refilter(prepared, panel_data, panels, row_filter, windows \\ %{}) do
    panel_map = Map.new(panels, &{&1.id, &1})

    Map.new(prepared, fn
      {panel_id, {:prepared, _, _} = table} ->
        {panel_id, table}

      {panel_id, {:prepared_logs, _} = logs} ->
        {panel_id, logs}

      {panel_id, _value} ->
        raw = Map.get(panel_data, panel_id, {:error, :no_data})
        panel = Map.get(panel_map, panel_id)
        {panel_id, single(panel, raw, row_filter, Map.get(windows, panel_id))}
    end)
  end

  @doc """
  Prepares one panel's data; `window` is the query window it was fetched over,
  or `nil`.
  """
  @spec single(
          GrafExTerm.Dashboard.Types.Panel.t() | nil,
          term(),
          row_filter(),
          GrafExTerm.Refresh.QueryWindow.t() | nil
        ) :: term()
  def single(panel, data, row_filter, window \\ nil)

  def single(%{type: "table"} = panel, data, _row_filter, _window) do
    {rows, cols} = Table.prepare(data, panel.organize, panel.field_config)
    {:prepared, rows, cols}
  end

  def single(%{type: type} = panel, data, row_filter, window)
      when type in ["timeseries", "graph"] do
    Timeseries.prepare(panel, apply_row_filter(data, row_filter), window)
  end

  def single(%{type: "heatmap"} = panel, data, row_filter, _window) do
    Heatmap.prepare(panel, apply_row_filter(data, row_filter))
  end

  def single(%{type: "logs"} = panel, data, _row_filter, _window), do: Logs.prepare(panel, data)

  def single(_panel, data, row_filter, _window), do: apply_row_filter(data, row_filter)

  defp apply_row_filter(data, nil), do: data

  defp apply_row_filter({:ok, series}, filters) do
    {:ok, Enum.filter(series, &matches_any_filter?(&1, filters))}
  end

  defp apply_row_filter(data, _filters), do: data

  defp matches_any_filter?(series, filters) do
    Enum.any?(filters, fn filter ->
      Enum.all?(filter, fn {key, val} -> Map.get(series.labels, key) == val end)
    end)
  end
end
