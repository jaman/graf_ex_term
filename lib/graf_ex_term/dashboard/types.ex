defmodule GrafExTerm.Dashboard.Types do
  @moduledoc """
  Structs a Grafana dashboard JSON document is parsed into.

  `GrafExTerm.Dashboard.Parser` is the only thing that builds them; everything
  downstream reads them. Every field is populated by the parser, which
  substitutes a default rather than leaving a field `nil`, so consumers may
  assume the fields are present.
  """

  defmodule Target do
    @moduledoc """
    One query belonging to a panel.

    Fields:

      * `:expr` — the PromQL string, still containing `$var` placeholders.
        Empty string when the panel declared no expression.
      * `:legend_format` — Grafana legend template such as `"{{instance}}"`,
        used to name the resulting series. Empty string means the series name
        is derived from its labels.
      * `:ref_id` — the target's letter within the panel, defaulting to
        `"A"`. Used to label value columns when a table panel has several
        targets.
      * `:datasource_ref` — datasource uid, or a `$var` reference to one, or
        `nil` to use the default datasource.
      * `:instant` — `true` when the target is evaluated at a single point in
        time rather than over a range. Defaults to `false`.
      * `:format` — Grafana result format, `"table"` for tabular results and
        `nil` otherwise.

    A target is fetched as an instant table only when `:instant` is `true` and
    `:format` is `"table"`; otherwise it is fetched as a range query.
    """
    defstruct [:expr, :legend_format, :ref_id, :datasource_ref, :instant, :format]

    @type t :: %__MODULE__{
            expr: String.t(),
            legend_format: String.t(),
            ref_id: String.t(),
            datasource_ref: String.t() | nil,
            instant: boolean(),
            format: String.t() | nil
          }
  end

  defmodule TemplateVar do
    @moduledoc """
    A dashboard template variable that panel expressions interpolate.

    Fields:

      * `:name` — the variable name without the `$` sigil.
      * `:type` — Grafana variable type, defaulting to `"query"`. Only
        `"query"` variables are resolved against the datasource; every other
        type keeps `:current_value`.
      * `:current_value` — the selected value, or empty string when the
        dashboard saved none.
      * `:options_list` — the selectable values, possibly empty.
      * `:query` — for a `"query"` variable, the expression that produces the
        options. `GrafExTerm.Variable.Manager` understands the
        `label_values(...)` form and returns the first result; anything else
        leaves the variable at `:current_value`.
    """
    defstruct [:name, :type, :current_value, :options_list, :query]

    @type t :: %__MODULE__{
            name: String.t(),
            type: String.t(),
            current_value: String.t(),
            options_list: [String.t()],
            query: String.t()
          }
  end

  defmodule Panel do
    @moduledoc """
    A single dashboard panel.

    Fields:

      * `:id` — the panel id, unique within the dashboard, and the key under
        which its fetched data is cached.
      * `:title` — display title, possibly empty.
      * `:type` — Grafana panel type. `"stat"`, `"timeseries"`, `"graph"`,
        `"gauge"`, `"bargauge"`, `"table"`, `"text"` and `"row"` render as
        themselves; anything else renders as a placeholder.
      * `:grid_pos` — `%{x: x, y: y, w: w, h: h}` in Grafana grid units, where
        the grid is 24 columns wide. Defaults to a half-width, 8-unit-tall
        panel at the origin.
      * `:targets` — list of `Target` structs, possibly empty.
      * `:field_config` — the raw Grafana `fieldConfig` map, string-keyed,
        holding units, min/max, thresholds, value mappings and per-field
        overrides.
      * `:options` — the raw Grafana `options` map, string-keyed.
      * `:panels` — the raw nested panel maps of a collapsed row, kept
        undecoded. The parser also lifts these to the top level, so reading
        this field is not needed to reach them.
      * `:organize` — `nil`, or `%{exclude: map, rename: map, index: map}`
        from an `organize` transformation, applied to table columns.

    A `"row"` panel is a section header rather than a visualisation: the
    panels that follow it, up to the next row, belong to it.
    """
    defstruct [
      :id,
      :title,
      :type,
      :grid_pos,
      :targets,
      :field_config,
      :options,
      :panels,
      :organize
    ]

    @type grid_pos :: %{
            x: non_neg_integer(),
            y: non_neg_integer(),
            w: non_neg_integer(),
            h: non_neg_integer()
          }

    @type organize :: %{exclude: map(), rename: map(), index: map()}

    @type t :: %__MODULE__{
            id: integer() | nil,
            title: String.t(),
            type: String.t(),
            grid_pos: grid_pos(),
            targets: [GrafExTerm.Dashboard.Types.Target.t()],
            field_config: map(),
            options: map(),
            panels: [map()],
            organize: organize() | nil
          }
  end

  defmodule Dashboard do
    @moduledoc """
    A parsed dashboard.

    Fields:

      * `:uid` — the Grafana uid, used as the key for the data cache, the
        PubSub topic, the persisted settings and the per-dashboard worker
        registries. Empty string when the source declared none.
      * `:title` — display title, defaulting to `"Untitled"`.
      * `:description` — free text, possibly empty.
      * `:panels` — a flat list of `Panel` structs in document order. Panels
        nested inside a collapsed row are lifted out and follow their row.
      * `:templating` — list of `TemplateVar` structs, possibly empty.
      * `:refresh` — the Grafana refresh string such as `"30s"`, `"5m"` or
        `"1h"`. `false` or an unparseable value means the application's
        `:default_refresh_ms` is used instead.
    """
    defstruct [:uid, :title, :description, :panels, :templating, :refresh]

    @type t :: %__MODULE__{
            uid: String.t(),
            title: String.t(),
            description: String.t(),
            panels: [GrafExTerm.Dashboard.Types.Panel.t()],
            templating: [GrafExTerm.Dashboard.Types.TemplateVar.t()],
            refresh: String.t() | false
          }
  end
end
