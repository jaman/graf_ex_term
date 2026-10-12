defmodule GrafExTerm.Demo do
  @moduledoc """
  Runs GrafExTerm on the showcase dashboard with generated data, no Prometheus
  or Loki needed.

  Every datasource is pointed at `GrafExTerm.Datasource.Demo`, the dashboard
  store is moved to a directory under the system temp dir so the user's own
  dashboard list is neither read nor written, and
  `priv/demo/showcase.json` — one or more of every panel type GrafExTerm
  draws — is registered before the UI starts.

      mix graf_ex_term.demo

  or, from `iex -S mix run --no-start`:

      GrafExTerm.Demo.run()
  """

  alias GrafExTerm.Dashboard.Store

  @doc """
  Configures the demo, starts `:graf_ex_term` and runs the UI until the user
  quits.

  Must be called before `:graf_ex_term` is started, since the store directory
  and datasources are read at start. `opts` is forwarded to `GrafExTerm.run/1`.
  Raises when the application is already running or the showcase cannot be
  registered.
  """
  @spec run(keyword()) :: term()
  def run(opts \\ []) do
    configure()
    {:ok, _apps} = Application.ensure_all_started(:graf_ex_term)
    {:ok, _dashboard} = Store.add("file://" <> showcase_path())
    GrafExTerm.run(opts)
  end

  @doc """
  The absolute path of the showcase dashboard JSON.
  """
  @spec showcase_path() :: String.t()
  def showcase_path, do: Application.app_dir(:graf_ex_term, "priv/demo/showcase.json")

  defp configure do
    if Enum.any?(Application.started_applications(), &(elem(&1, 0) == :graf_ex_term)) do
      raise "GrafExTerm.Demo.run/1 must be called before :graf_ex_term is started"
    end

    Application.put_env(
      :graf_ex_term,
      :store_dir,
      Path.join(System.tmp_dir!(), "graf_ex_term_demo")
    )

    Application.put_env(:graf_ex_term, :datasources, %{
      "prometheus" => %{type: :demo},
      "loki" => %{type: :demo}
    })
  end
end
