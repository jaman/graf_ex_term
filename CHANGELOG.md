# Changelog

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
- `GrafExTerm.Layout.GridMapper`: maps Grafana grid positions to a Drafter layout.
- Configuration under `:graf_ex_term`: `:datasources`, `:theme`, `:height_ratio`, `:time_range_seconds`, `:chart_resolution`, `:default_refresh_ms`. `config/runtime.exs` reads them from `PROMETHEUS`, `GRAF_EX_TERM_THEME`, `GRAF_EX_TERM_HEIGHT_RATIO`, `GRAF_EX_TERM_REFRESH_MS`, `GRAF_EX_TERM_TIME_RANGE` and `GRAF_EX_TERM_CHART_RESOLUTION`.
- `mix dump_layout path/to/dashboard.json`: writes `generated_layout.exs`, a standalone Drafter script reproducing a dashboard's layout with placeholder panels.
- Standalone binaries through Burrito (`MIX_ENV=prod mix release`) for Linux x86_64 and aarch64 and macOS aarch64 and x86_64; the binary starts the UI on launch and exits when it closes. A `Dockerfile` builds an Alpine release image.
