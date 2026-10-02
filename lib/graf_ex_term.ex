defmodule GrafExTerm do
  @moduledoc """
  Entry point for the Grafana dashboard terminal UI.

  A Grafana dashboard JSON is loaded from a file or a Grafana HTTP API, parsed
  into panels, and rendered as an interactive Drafter screen. Panel targets are
  queried against Prometheus on a refresh interval and the results drawn as
  charts, tables, stats and gauges.

  Dashboards are registered through `GrafExTerm.Dashboard.Store`, which
  persists them and their per-dashboard settings to
  `$XDG_CONFIG_HOME/graf_ex_term/dashboards.json`. The `:graf_ex_term`
  application must be running before `run/1` is called; the supervision tree
  owns the store, the refresh caches and the per-dashboard workers.

  Application environment keys read at runtime:

    * `:datasources` — map of datasource name to config, each `%{url: url}`.
      Defaults to `%{}`, with `"prometheus"` falling back to
      `http://localhost:9090`.
    * `:theme` — Drafter theme name. Defaults to `"tokyo-night"`.
    * `:height_ratio` — terminal rows per Grafana grid unit. Defaults to `3`.
    * `:time_range_seconds` — width of the query window. Defaults to `3600`.
    * `:chart_resolution` — target sample count per series, which sets the
      query step. Defaults to `300`.
    * `:default_refresh_ms` — interval used when a dashboard declares no
      refresh. Defaults to `30_000`.

      GrafExTerm.run()
  """

  @doc """
  Starts the terminal UI and blocks until the user quits.

  `opts` is passed through to `Drafter.run/2`. Takes over the terminal for the
  lifetime of the call.
  """
  @spec run(keyword()) :: term()
  def run(opts \\ []) do
    Drafter.run(GrafExTerm.Screen.Main, opts)
  end
end
