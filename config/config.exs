import Config

config :graf_ex_term,
  datasources: %{
    "prometheus" => %{
      type: :prometheus,
      url: System.get_env("PROMETHEUS", "http://localhost:9090")
    }
  },
  theme: System.get_env("GRAF_EX_TERM_THEME", "gruvbox-dark"),
  invert_area_charts: true,
  height_ratio: 3,
  default_refresh_ms: 30_000,
  time_range_seconds: 3600,
  chart_resolution: 300
