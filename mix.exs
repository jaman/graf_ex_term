defmodule GrafExTerm.MixProject do
  use Mix.Project

  def project do
    [
      app: :graf_ex_term,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description:
        "Terminal UI for Grafana dashboards — live Prometheus queries rendered as interactive TUI panels",
      package: package(),
      docs: docs(),
      releases: releases(),
      source_url: "https://github.com/your-org/graf_ex_term",
      homepage_url: "https://github.com/your-org/graf_ex_term"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {GrafExTerm.Application, []}
    ]
  end

  defp deps do
    [
      {:drafter, github: "jaman/drafter"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},
      {:cachex, "~> 3.6"},
      {:burrito, "~> 1.0", only: :prod, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp releases do
    base = [strip_beams: Mix.env() == :prod]

    if Mix.env() == :prod do
      [
        graf_ex_term:
          base ++
            [
              steps: [:assemble, &Burrito.wrap/1],
              burrito: [targets: burrito_targets()]
            ]
      ]
    else
      [graf_ex_term: base]
    end
  end

  defp burrito_targets do
    [
      linux_x86_64: [os: :linux, cpu: :x86_64, skip_nifs: true],
      linux_aarch64: [os: :linux, cpu: :aarch64, skip_nifs: true],
      macos_aarch64: [os: :darwin, cpu: :aarch64],
      macos_x86_64: [os: :darwin, cpu: :x86_64]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/your-org/graf_ex_term"},
      files: ~w(lib config mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      groups_for_modules: [
        Dashboard: [
          GrafExTerm.Dashboard.Loader,
          GrafExTerm.Dashboard.Parser,
          GrafExTerm.Dashboard.Store,
          GrafExTerm.Dashboard.Types
        ],
        Datasource: [
          GrafExTerm.Datasource.Prometheus,
          GrafExTerm.Datasource.Behaviour
        ],
        Refresh: [
          GrafExTerm.Refresh.Scheduler,
          GrafExTerm.Refresh.DataCache
        ],
        Panels: [
          GrafExTerm.Panel.Renderer,
          GrafExTerm.Panel.Table,
          GrafExTerm.Panel.Stat,
          GrafExTerm.Panel.Timeseries,
          GrafExTerm.Panel.ColorRules,
          GrafExTerm.Panel.Gauge,
          GrafExTerm.Panel.Bargauge,
          GrafExTerm.Panel.Row
        ],
        Layout: [GrafExTerm.Layout.GridMapper],
        Variables: [
          GrafExTerm.Variable.Manager,
          GrafExTerm.Variable.Substitution
        ],
        Screens: [
          GrafExTerm.Screen.Main
        ]
      ]
    ]
  end
end
