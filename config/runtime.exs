import Config

config :graf_ex_term,
  datasources: %{
    "prometheus" => %{
      type: :prometheus,
      url: System.get_env("PROMETHEUS", "http://localhost:9090")
    },
    "loki" => %{
      type: :loki,
      url: System.get_env("LOKI", "http://localhost:3100")
    }
  },
  theme: System.get_env("GRAF_EX_TERM_THEME", "gruvbox-dark"),
  height_ratio: String.to_integer(System.get_env("GRAF_EX_TERM_HEIGHT_RATIO", "3")),
  default_refresh_ms: String.to_integer(System.get_env("GRAF_EX_TERM_REFRESH_MS", "30000")),
  time_range_seconds: String.to_integer(System.get_env("GRAF_EX_TERM_TIME_RANGE", "3600")),
  chart_resolution: String.to_integer(System.get_env("GRAF_EX_TERM_CHART_RESOLUTION", "300")),
  stat_fonts:
    (case System.get_env("GRAF_EX_TERM_STAT_FONTS") do
       nil ->
         nil

       names ->
         names
         |> String.split(",", trim: true)
         |> Enum.map(&(&1 |> String.trim() |> String.to_atom()))
     end),
  chart_renderer:
    (case System.get_env("GRAF_EX_TERM_RENDERER") do
       renderer
       when renderer in ~w(text braille half quad sextant octant auto pixel kitty iterm2 sixel) ->
         String.to_atom(renderer)

       _ ->
         nil
     end)
