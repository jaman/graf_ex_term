defmodule GrafExTerm.Datasource.Demo do
  @moduledoc """
  A `GrafExTerm.Datasource.Behaviour` implementation that generates metrics
  instead of querying a server, for the showcase dashboard and for trying the
  UI without Prometheus.

  A datasource config whose `:type` is `:demo` is served by this module. An
  expression is answered by the first known metric name it mentions:

    * `demo_cpu_usage` — fraction 0..1 per `instance` (`web-1`..`web-4`)
    * `demo_memory_bytes` — bytes per `instance`
    * `demo_http_requests` — requests per second per `status`
    * `demo_network_bytes` — bytes per second per `direction` (`rx`, `tx`)
    * `demo_disk_usage` — percent per `mount`
    * `demo_up` — `1` or `0` per `service`, each down now and then
    * `demo_queue_depth` — one series
    * `demo_temperature` — degrees Celsius, one series
    * `demo_errors` — errors per second per `service`
    * `demo_request_duration_bucket` — a cumulative latency histogram, one
      series per `le` bound

  Any other expression yields one wave named after it. Label matchers in the
  expression (`label="v"`, `label!="v"`, `label=~"re"`, `label!~"re"`) filter
  the series; functions and aggregations are ignored.

  Values are a pure function of metric, labels and timestamp, so the same
  window always returns the same samples and successive windows join without
  seams.
  """

  @behaviour GrafExTerm.Datasource.Behaviour

  @instances for i <- 1..4, do: %{"instance" => "web-#{i}", "job" => "web"}
  @statuses for code <- ~w(200 301 404 500), do: %{"status" => code}
  @services for name <- ~w(api web worker db cache), do: %{"service" => name}
  @buckets ~w(0.05 0.1 0.25 0.5 1 2.5 5 +Inf)

  @scenarios [
    {"demo_request_duration_bucket", :histogram, Enum.map(@buckets, &%{"le" => &1}), %{}},
    {"demo_cpu_usage", :wave, @instances,
     %{base: 0.35, spread: 0.12, amplitude: 0.22, period: 900, noise: 0.06, min: 0.0, max: 1.0}},
    {"demo_memory_bytes", :wave, @instances,
     %{base: 2.4e9, spread: 6.0e8, amplitude: 4.0e8, period: 2400, noise: 5.0e7, min: 0.0}},
    {"demo_http_requests", :wave, @statuses,
     %{base: 180.0, spread: -55.0, amplitude: 60.0, period: 600, noise: 12.0, min: 0.0}},
    {"demo_network_bytes", :wave, [%{"direction" => "rx"}, %{"direction" => "tx"}],
     %{base: 3.0e6, spread: -1.2e6, amplitude: 1.5e6, period: 420, noise: 3.0e5, min: 0.0}},
    {"demo_disk_usage", :wave, for(m <- ~w(/ /var /data /home), do: %{"mount" => m}),
     %{base: 42.0, spread: 14.0, amplitude: 3.0, period: 7200, noise: 0.5, min: 0.0, max: 100.0}},
    {"demo_up", :up, @services, %{}},
    {"demo_queue_depth", :wave, [%{}],
     %{base: 40.0, spread: 0.0, amplitude: 35.0, period: 300, noise: 6.0, min: 0.0}},
    {"demo_temperature", :wave, [%{"sensor" => "cpu"}],
     %{base: 58.0, spread: 0.0, amplitude: 14.0, period: 1500, noise: 1.5, min: 0.0}},
    {"demo_errors", :wave, @services,
     %{base: 2.0, spread: 1.1, amplitude: 1.5, period: 500, noise: 0.8, min: 0.0}}
  ]

  @fallback_params %{base: 50.0, spread: 0.0, amplitude: 30.0, period: 600, noise: 5.0}

  @impl true
  def query(_config, expr, {from, to}, step) do
    times = Enum.to_list(from..to//step)

    series =
      for {name, kind, label_sets, params} <- [scenario(expr)],
          {labels, index} <- label_sets |> Enum.with_index() |> filter(expr) do
        %{
          labels: Map.put(labels, "__name__", name),
          values: Enum.map(times, &{&1, value(kind, name, params, labels, index, &1)})
        }
      end

    {:ok, series}
  end

  @impl true
  def instant_query(config, expr, time) do
    {:ok, series} = query(config, expr, {time, time}, 1)

    {:ok,
     Enum.map(series, fn %{labels: labels, values: [{_, v}]} -> %{labels: labels, value: v} end)}
  end

  @doc """
  The values of `label` across every generated series, sorted, for
  `label_values(...)` template variables.
  """
  @spec label_values(String.t()) :: [String.t()]
  def label_values(label) do
    @scenarios
    |> Enum.flat_map(fn {_name, _kind, label_sets, _params} -> label_sets end)
    |> Enum.flat_map(fn labels -> labels |> Map.get(label) |> List.wrap() end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp scenario(expr) do
    Enum.find(@scenarios, fn {name, _, _, _} -> String.contains?(expr, name) end) ||
      {String.trim(expr), :wave, [%{}], @fallback_params}
  end

  defp filter(indexed_labels, expr) do
    matchers = Regex.scan(~r/(\w+)\s*(=~|!~|!=|=)\s*"([^"]*)"/, expr, capture: :all_but_first)
    Enum.filter(indexed_labels, fn {labels, _} -> Enum.all?(matchers, &matches?(labels, &1)) end)
  end

  defp matches?(labels, [label, "=", wanted]), do: Map.get(labels, label, "") == wanted
  defp matches?(labels, [label, "!=", wanted]), do: Map.get(labels, label, "") != wanted

  defp matches?(labels, [label, "=~", pattern]),
    do: regex_match?(pattern, Map.get(labels, label, ""))

  defp matches?(labels, [label, "!~", pattern]),
    do: not regex_match?(pattern, Map.get(labels, label, ""))

  defp regex_match?(pattern, value) do
    case Regex.compile("^(?:#{pattern})$") do
      {:ok, regex} -> Regex.match?(regex, value)
      {:error, _} -> false
    end
  end

  defp value(:wave, name, params, _labels, index, ts) do
    phase = index * 1.3
    wave = :math.sin(2 * :math.pi() * ts / params.period + phase)
    noise = (unit_hash({name, index, ts}) - 0.5) * 2 * params.noise
    raw = params.base + params.spread * index + params.amplitude * wave + noise
    raw |> clamp(Map.get(params, :min), Map.get(params, :max)) |> Kernel.*(1.0)
  end

  defp value(:up, name, _params, _labels, index, ts) do
    if rem(div(ts, 240) + index * 3, 11) == 0 and unit_hash({name, index, div(ts, 240)}) > 0.3,
      do: 0.0,
      else: 1.0
  end

  defp value(:histogram, _name, _params, %{"le" => le}, _index, ts) do
    total = 120.0 + 45.0 * :math.sin(2 * :math.pi() * ts / 700)
    median = 0.35 + 0.25 * :math.sin(2 * :math.pi() * ts / 1800)
    total * share_below(le, median)
  end

  defp share_below("+Inf", _median), do: 1.0

  defp share_below(le, median) do
    {bound, _} = Float.parse(le)
    1.0 / (1.0 + :math.pow(median / bound, 3))
  end

  defp clamp(value, low, high), do: value |> at_least(low) |> at_most(high)

  defp at_least(value, nil), do: value
  defp at_least(value, low), do: max(value, low)

  defp at_most(value, nil), do: value
  defp at_most(value, high), do: min(value, high)

  defp unit_hash(term), do: :erlang.phash2(term, 10_000) / 10_000
end
