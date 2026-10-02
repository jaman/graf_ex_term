# GrafExTerm

A terminal UI for Grafana dashboards, built on [Drafter](https://github.com/jaman/drafter).

GrafExTerm reads Grafana dashboard JSON directly — no Grafana server required at runtime for layout — and queries your Prometheus datasources live. It renders panels as interactive terminal widgets: tables with sortable/resizable columns, timeseries charts, stat panels with sparkline backgrounds, gauges, and more.

> **Work in progress.** Core functionality is stable; some panel types and Grafana features are not yet implemented.

## Features

- Load dashboards from local JSON files or HTTP URLs
- Live Prometheus querying with configurable refresh intervals
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
| `timeseries` / `graph` | Full — multi-series, axes, percent scaling |
| `gauge` | Rendered |
| `bargauge` | Rendered |
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

## Configuration

`config/config.exs`:

```elixir
config :graf_ex_term,
  theme: "tokyo-night",   # any Drafter theme name
  height_ratio: 3         # terminal rows per Grafana grid unit
```

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
│   └── Prometheus   — range_query/3, instant_query/3
├── Refresh
│   ├── Scheduler    — per-dashboard GenServer; drives periodic fetches
│   └── DataCache    — ETS-backed cache; version-stamped for poll-based diffing
├── Variable
│   ├── Manager      — resolves Grafana template variables
│   └── Substitution — interpolates $var / ${var} in query expressions
├── Panel
│   ├── Renderer     — dispatches to type-specific renderers
│   ├── Table        — prepare/3, render/5; organize transform, color rules
│   ├── Stat         — threshold color, Format-based unit display, sparkline
│   ├── Timeseries   — multi-series chart, axis scaling
│   ├── ColorRules   — builds color_fn closures from fieldConfig
│   └── ...
├── Layout
│   └── GridMapper   — maps Grafana grid positions to Drafter layout tree
└── Screen
    └── Main         — top-level Drafter.App; state, event handling, rendering
```
