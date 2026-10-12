# Changelog

## [Unreleased]

### Added

- `GrafExTerm.Refresh.QueryWindow`: each panel's query step is sized to its share of the terminal width (two samples per column), capped by the panel's `maxDataPoints` and floored by its `interval`. Screens report the width at start and on resize with `GrafExTerm.Refresh.Scheduler.set_columns/2`.
- Incremental refresh: after a panel's first fetch, later fetches query only from two steps before the previous end and append with `GrafExTerm.Refresh.SeriesWindow.merge/4`. Range series carry the `:ref_id` of their target.
- Panels are queried concurrently, bounded by `:max_concurrent_queries` (default 8) and `:query_timeout_ms` (default 30_000); a timed-out panel yields `{:error, :timeout}`.
- Panel types: `piechart`, `heatmap` (Prometheus histogram buckets), `logs` (Loki, `GrafExTerm.Datasource.Loki`). `bargauge` draws Drafter meters with threshold colours and `reduceOptions.calcs` (`GrafExTerm.Panel.Reduce`).
- `GrafExTerm.Panel.Prepare` and `GrafExTerm.Dashboard.Visibility`, shared by the main screen, the viewer and the scheduler.
- Timeseries charts carry sample times as x labels for the chart value readout; `GRAF_EX_TERM_RENDERER` (`:chart_renderer`) picks the chart renderer. `LOKI` sets the default Loki URL.
- Panel structs carry `:max_data_points` and `:min_interval`.
- `mix graf_ex_term.demo` (`GrafExTerm.Demo.run/1`): the showcase dashboard `priv/demo/showcase.json` on generated data from `GrafExTerm.Datasource.Demo` and `GrafExTerm.Datasource.Demo.Logs`, with a dashboard store under the system temp dir. A datasource config with `type: :demo` uses the generator anywhere.
- `:store_dir` sets the directory the dashboard store writes under.
- Stat numbers use the first font of `:stat_fonts` (`GRAF_EX_TERM_STAT_FONTS`, default `[:braille, :mini, :compact]`) that fits the panel; Drafter's bundled FIGlet fonts are registered at start.
- Timeseries areas stack only when the panel's `custom.stacking.mode` is `"normal"`; otherwise series are drawn from the baseline, largest first.

### Changed

- `{:data_refreshed, uid}` is broadcast without the data; screens read it from `GrafExTerm.Refresh.DataCache`, and screen state holds only prepared panel data.
- `GrafExTerm.Refresh.DataCache` no longer downsamples; sample counts come from the query step.
- `GrafExTerm.Panel.Renderer.render/3` takes the height and table options as a keyword list.
- Main screen layout: a one-line `GrafExTerm.Screen.StatusBar` (dashboard, time range, refresh interval, last update) replaces the header; the dashboard list is a plain list without a "none" entry and `b` hides it; the `+Add` button and `Filter` checkbox are gone in favour of the `a` and `f` keys shown in the footer.
- Every panel except rows and tables is drawn in a rounded frame with its title in the top border; panels no longer draw their own title. Stat numbers are centred over a darker sparkline.
- A panel's frame is drawn in the theme's primary colour while the panel has focus.
- Row headers read `▶ Title ─────── N panels`; the panel area uses Drafter's thin scrollbar; clicking a footer hint runs its key.
- Timeseries areas crossing zero use one linear axis (`zero_center: :linear`).
- Parsed dashboards are held in an ETS table owned by `GrafExTerm.Dashboard.Store`; the `cachex` dependency is removed.

### Fixed

- A timeseries panel with `drawStyle: "bars"` no longer crashes the screen: one series draws as a `:bar` chart of numbers, several as `:clustered_bar`, or `:stacked_bar` with `stacking.mode: "normal"`.
- Panels without targets are not queried.
- The demo generator no longer returns negative values for metrics with a minimum and no maximum.
- Removed `{:key, ?r}` and `{:key, ?q}` clauses from the browser and viewer screens, which never matched (keys arrive as atoms); their `{:key, :r}` and `{:key, :q}` clauses handle the keys.

## [0.1.0]

### Added

- `GrafExTerm.run/1`: starts the terminal UI for Grafana dashboards on Drafter and blocks until the user quits. The `:graf_ex_term` application must be running first.
- Dashboard loading from `file://` paths and `http(s)://` URLs (`GrafExTerm.Dashboard.Loader.load/1`), parsed into typed structs by `GrafExTerm.Dashboard.Parser`.
- `GrafExTerm.Dashboard.Store`: registers dashboards with `add/1` and `remove/1`, and saves the list plus per-dashboard settings (datasource mapping, column visibility, table layouts, collapsed rows and tables, column filter) to `$XDG_CONFIG_HOME/graf_ex_term/dashboards.json`, or `~/.config/graf_ex_term/dashboards.json` when that variable is unset. Dashboards are fetched again at startup.
- Main screen: dashboard list on the left, the selected dashboard's panels on the right. Keys: `a` add a dashboard, `f` toggle the per-column table selector, `r` refresh, `q` quit, `Tab`/`Shift+Tab` move between panels.
- Add-dashboard modal: takes a URI typed or picked from a file picker, then optionally a Prometheus base URL and one URL per datasource template variable such as `DS_PROMETHEUS`.
- `GrafExTerm.Datasource.Prometheus`: range queries (`query/4`) and instant queries (`instant_query/3`), behind the `GrafExTerm.Datasource.Behaviour` contract.
- `GrafExTerm.Refresh.Scheduler`: one process per open dashboard that queries its panels on the dashboard's refresh interval, with `refresh_now/1`. Results go to `GrafExTerm.Refresh.DataCache`, an ETS cache with a version number the screen polls.
- `GrafExTerm.Refresh.SeriesClusterer`: merges many similar series into fewer representative ones (median per timestamp, weighted by member count) so dense charts stay readable.
- Template variables: `GrafExTerm.Variable.Manager` resolves `label_values(selector, label)` and `label_values(label)` queries against Prometheus; `GrafExTerm.Variable.Substitution.substitute/2` fills `$var` and `${var}` in query expressions.
- Panels:
  - `table` — instant queries, multi-target join with one column per `refId` (`Value #B`), Grafana `organize` transform (exclude, rename, reorder), value mappings and threshold colours per cell with contrast correction, sortable columns (click header), `+`/`-` to resize and `Shift+←`/`Shift+→` to reorder columns, per-column visibility.
  - Selecting table rows (`Enter`, `Space` or click) filters every timeseries panel to series whose labels match the selection; clearing it restores the full view.
  - `timeseries` / `graph` — braille area or bar charts, multi-series, unit-aware y-axis (`percentunit`, `percent`, byte and bit units), panel `min`/`max`.
  - `stat` — threshold colour, unit formatting, braille sparkline behind the number when `graphMode: area`.
  - `gauge` — one dial per series. `bargauge` — one bar per series.
  - `row` — collapsible section headers; collapse state is saved per dashboard.
  - Other panel types show a placeholder.
- `GrafExTerm.Layout.GridMapper.to_tui_layout/3`: maps Grafana grid positions to a Drafter layout; options `:column_visibility`, `:collapsed_rows`, `:table_layouts`, `:collapsed_table_panels`, `:all_tables_collapsed`, `:column_filter`.
- Configuration under `:graf_ex_term`: `:datasources`, `:theme`, `:height_ratio`, `:time_range_seconds`, `:chart_resolution`, `:default_refresh_ms`. `config/runtime.exs` reads them from `PROMETHEUS`, `GRAF_EX_TERM_THEME`, `GRAF_EX_TERM_HEIGHT_RATIO`, `GRAF_EX_TERM_REFRESH_MS`, `GRAF_EX_TERM_TIME_RANGE` and `GRAF_EX_TERM_CHART_RESOLUTION`.
- `mix dump_layout path/to/dashboard.json`: writes `generated_layout.exs`, a standalone Drafter script reproducing a dashboard's layout with placeholder panels.
- Standalone binaries through Burrito (`MIX_ENV=prod mix release`) for Linux x86_64 and aarch64 and macOS aarch64 and x86_64; the binary starts the UI on launch and exits when it closes. A `Dockerfile` builds an Alpine release image.
