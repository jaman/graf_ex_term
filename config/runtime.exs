import Config

config :graf_ex_term,
  datasources: %{
    "prometheus" => %{
      type: :prometheus,
      url: System.get_env("PROMETHEUS", "http://localhost:9090")
    }
  },
  theme: System.get_env("GRAF_EX_TERM_THEME", "gruvbox-dark"),
  height_ratio: String.to_integer(System.get_env("GRAF_EX_TERM_HEIGHT_RATIO", "3")),
  default_refresh_ms: String.to_integer(System.get_env("GRAF_EX_TERM_REFRESH_MS", "30000")),
  time_range_seconds: String.to_integer(System.get_env("GRAF_EX_TERM_TIME_RANGE", "3600")),
  chart_resolution: String.to_integer(System.get_env("GRAF_EX_TERM_CHART_RESOLUTION", "300"))
