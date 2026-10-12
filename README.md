# GrafExTerm

A terminal UI for Grafana dashboards, built on [Drafter](https://github.com/jaman/drafter).

GrafExTerm reads Grafana dashboard JSON directly — no Grafana server required at runtime for layout — and queries your Prometheus (and Loki, for logs panels) datasources live. It renders panels as interactive terminal widgets: tables with sortable/resizable columns, timeseries charts, heatmaps, pie charts, bar gauges, logs, stat panels with sparkline backgrounds, gauges, and more.

> **Work in progress.** Core functionality is stable; some panel types and Grafana features are not yet implemented.

## Features

- Load dashboards from local JSON files or HTTP URLs
- Live Prometheus querying with configurable refresh intervals
- Query resolution sized to each panel: the step is chosen so a query returns about two samples per terminal column the panel occupies, honouring the panel's `maxDataPoints` and minimum `interval`, and recomputed when the terminal is resized
- Incremental refresh: after the first fetch only the newest samples are queried and appended; panels are queried concurrently
- Loki-backed `logs` panels
- Supports instant queries (table panels) and range queries (timeseries/stat/gauge)
- Multi-target instant query join — columns named per `refId` (`Value #B`, `Value #C`)
- Grafana `organize` transformation: column exclude, rename, and reorder
- Grafana `fieldConfig` color rules: value mappings and threshold steps with per-cell coloring
- Automatic contrast correction on colored table cells (WCAG luminance)
- Stat panels with braille sparkline background (`graphMode: area`)
- Table row selection filters all chart panels to matching label sets (single or multi-select)
- Column visibility, widths, and order persisted per panel per dashboard
- Collapsible dashboard row sections
- Theme support via Drafter theme system

## Panel support

| Grafana type | Status |
|---|---|
| `table` | Full — instant queries, organize transform, color rules, column management |
| `stat` | Full — threshold color, unit formatting, sparkline background |
| `timeseries` / `graph` | Full — multi-series, axes, percent scaling, value readout |
| `gauge` | Rendered |
| `bargauge` | One meter per series, `reduceOptions.calcs`, `min`/`max`, threshold colours |
| `piechart` | One slice per series, `reduceOptions.calcs`, legend and percentages |
| `heatmap` | Prometheus histogram buckets (`le`) de-accumulated per bucket, or one row per series |
| `logs` | Loki `query_range`, `showTime`, `wrapLogMessage`, `maxDataPoints` as the line limit |
| `row` | Collapsible section headers |
| Others | Placeholder shown |

## Requirements

- Elixir ~> 1.18
- A Prometheus-backed Grafana dashboard exported as JSON

## Installation

Add GrafExTerm to a project:

```elixir
def deps do
  [
    {:graf_ex_term, "~> 0.1.0"}
  ]
end
```

Or run it from a clone:

```
git clone https://github.com/jaman/graf_ex_term
cd graf_ex_term
mix deps.get
mix run --no-halt
```

When a `drafter` checkout sits next to `graf_ex_term`, it is used in place of the Hex package.

## Try it without Prometheus

```
mix graf_ex_term.demo
```

Opens the showcase dashboard, which uses every panel type GrafExTerm draws, on generated data. Nothing is read from or written to your saved dashboard list. Any dashboard can use the generator by pointing a datasource at `%{type: :demo}`; see `GrafExTerm.Datasource.Demo` for the metric names it answers.

## Configuration

`config/config.exs`:

```elixir
config :graf_ex_term,
  theme: "tokyo-night",   # any Drafter theme name
  height_ratio: 3         # terminal rows per Grafana grid unit
```

`config/runtime.exs` reads these environment variables:

| Variable | Setting | Default |
|---|---|---|
| `PROMETHEUS` | default Prometheus URL | `http://localhost:9090` |
| `LOKI` | default Loki URL for `logs` panels | `http://localhost:3100` |
| `GRAF_EX_TERM_THEME` | Drafter theme | `gruvbox-dark` |
| `GRAF_EX_TERM_HEIGHT_RATIO` | terminal rows per Grafana grid unit | `3` |
| `GRAF_EX_TERM_REFRESH_MS` | refresh interval when the dashboard sets none | `30000` |
| `GRAF_EX_TERM_TIME_RANGE` | seconds of history shown | `3600` |
| `GRAF_EX_TERM_CHART_RESOLUTION` | samples per panel before the terminal width is known | `300` |
| `GRAF_EX_TERM_STAT_FONTS` | fonts for stat numbers, largest first, comma separated; the first that fits the panel is used. Built-in: `block`, `compact`, `tall`, `pixel`, `braille`; bundled FIGlet: `banner`, `big`, `blocks`, `bubble`, `digital`, `ivrit`, `lean`, `mini`, `script`, `shadow`, `slant`, `small`, `smscript`, `standard`, `term` | `braille,mini,compact` |
| `GRAF_EX_TERM_RENDERER` | chart renderer: `text`, `braille`, `half`, `quad`, `sextant`, `octant`, `auto`, `pixel`, `kitty`, `iterm2`, `sixel` | Drafter's choice (`text`) |

`:max_concurrent_queries` (default `8`) and `:query_timeout_ms` (default `30000`) bound the scheduler's parallel panel queries.

## Adding dashboards

1. Export your Grafana dashboard as JSON (Dashboard settings → JSON model).
2. Save it locally or host it at an HTTP URL.
3. Press `a` in GrafExTerm and enter the path or URL:
   - Local file: `file:///path/to/dashboard.json`
   - HTTP: `http://grafana.internal/api/dashboards/uid/abc123`
4. If the dashboard uses named datasource variables (e.g. `DS_PROMETHEUS`), you will be prompted to map them to actual Prometheus URLs.

Dashboard list and datasource mappings are saved to `~/.config/graf_ex_term/dashboards.json`.

## Usage

### Global keys

| Key | Action |
|---|---|
| `Tab` / `Shift+Tab` | Move focus between panels |
| `a` | Add a dashboard |
| `f` | Toggle the per-column table selector |
| `b` | Hide or show the dashboard list |
| `r` | Force-refresh the active dashboard |
| `q` | Quit |

### Tables

| Action | Effect |
|---|---|
| `↑` / `↓` | Navigate rows |
| `Enter` or click row | Select/deselect row (toggles) |
| `Space` | Toggle selection on highlighted row |
| Select multiple rows | Charts filter to union of matching series |
| Deselect all | Charts return to full view |
| Click column header | Sort ascending → descending → unsorted |
| `+` / `-` | Resize focused column |
| `Shift+←` / `Shift+→` | Reorder focused column |
| Expand **Columns** section | Toggle individual column visibility |

Column visibility, widths, and column order are saved automatically and restored on next launch.

### Charts

Click a timeseries chart (or hover over it, in apps with hover enabled) to place a cursor: the column is highlighted and the title row shows the sample time and each series' value there. `Esc` hides it. With `GRAF_EX_TERM_RENDERER=auto` charts are drawn as images on terminals that support kitty, iTerm2 or sixel graphics, with the axes and title drawn as text around them.

### Stat panels

Panels configured with `graphMode: area` in Grafana show the metric's recent history as a braille sparkline rendered behind the large number. The sparkline and number color both reflect the active threshold.

## Architecture

```
GrafExTerm
├── Dashboard
│   ├── Loader       — fetch JSON from file:// or http://
│   ├── Parser       — Grafana JSON → typed structs
│   ├── Store        — GenServer; persists dashboard list and per-panel settings
│   └── Types        — Panel, Target, GridPos, etc.
├── Datasource
│   ├── Prometheus   — query/4, instant_query/3
│   └── Loki         — query/4 for logs panels
├── Refresh
│   ├── Scheduler    — per-dashboard GenServer; concurrent, incremental fetches
│   ├── QueryWindow  — per-panel from/to/step sized to the panel's width
│   ├── SeriesWindow — appends a fetched tail to held series
│   └── DataCache    — version-stamped cache for poll-based diffing
├── Variable
│   ├── Manager      — resolves Grafana template variables
│   └── Substitution — interpolates $var / ${var} in query expressions
├── Panel
│   ├── Renderer     — dispatches to type-specific renderers
│   ├── Table        — prepare/3, render/5; organize transform, color rules
│   ├── Stat         — threshold color, Format-based unit display, sparkline
│   ├── Prepare      — turns cached data into render-ready form once per arrival
│   ├── Timeseries   — multi-series chart, axis scaling, time labels
│   ├── Heatmap      — bucket matrix from histogram series
│   ├── Piechart / Bargauge / Logs
│   ├── Reduce       — Grafana reduceOptions.calcs
│   ├── ColorRules   — builds color_fn closures from fieldConfig
│   └── ...
├── Layout
│   └── GridMapper   — maps Grafana grid positions to Drafter layout tree
└── Screen
    └── Main         — top-level Drafter.App; state, event handling, rendering
```
