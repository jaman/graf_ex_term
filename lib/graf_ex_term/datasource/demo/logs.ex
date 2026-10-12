defmodule GrafExTerm.Datasource.Demo.Logs do
  @moduledoc """
  Generated log lines for `logs` panels on a `:demo` datasource, with the same
  call shape as `GrafExTerm.Datasource.Loki.query/4`.

  One line is produced every two seconds of the window, each a pure function
  of its timestamp: a level (mostly `info`, some `warn`, a few `error`), a
  service and a request or job message. Label matchers in the expression on
  `level` or `service` filter the lines as
  `GrafExTerm.Datasource.Demo` filters series.
  """

  @interval 2
  @services ~w(api web worker db cache)
  @paths ~w(/api/users /api/orders /api/search /health /login /api/cart)
  @methods ~w(GET GET GET POST PUT DELETE)

  @doc """
  Returns up to `limit` of the newest generated lines between `from` and `to`,
  Unix seconds, oldest first, as `{:ok, entries}` shaped like
  `GrafExTerm.Datasource.Loki.query/4`'s.
  """
  @spec query(map(), String.t(), {integer(), integer()}, pos_integer()) ::
          {:ok, [GrafExTerm.Datasource.Loki.entry()]}
  def query(_config, expr, {from, to}, limit) do
    last = div(to, @interval) * @interval
    first = max(from, last - (limit * 4 - 1) * @interval)
    matchers = Regex.scan(~r/(\w+)\s*(=~|=)\s*"([^"]*)"/, expr, capture: :all_but_first)

    entries =
      last..first//-@interval
      |> Stream.map(&entry/1)
      |> Stream.filter(&selected?(&1, matchers))
      |> Enum.take(limit)
      |> Enum.reverse()

    {:ok, entries}
  end

  defp entry(ts) do
    roll = hash({:roll, ts}, 100)
    level = level(roll)
    service = Enum.at(@services, hash({:service, ts}, length(@services)))
    labels = %{"level" => level, "service" => service}

    %{
      time: ts * 1_000_000_000,
      labels: labels,
      line: "level=#{level} service=#{service} #{message(level, ts)}"
    }
  end

  defp level(roll) when roll < 4, do: "error"
  defp level(roll) when roll < 15, do: "warn"
  defp level(_roll), do: "info"

  defp message("error", ts),
    do:
      "msg=\"upstream timeout\" path=#{pick(@paths, ts)} after_ms=#{1000 + hash({:ms, ts}, 4000)}"

  defp message("warn", ts),
    do: "msg=\"slow request\" path=#{pick(@paths, ts)} duration_ms=#{400 + hash({:ms, ts}, 900)}"

  defp message("info", ts) do
    status = if hash({:status, ts}, 10) == 0, do: 404, else: 200

    "method=#{pick(@methods, ts)} path=#{pick(@paths, ts)} status=#{status} duration_ms=#{3 + hash({:ms, ts}, 120)}"
  end

  defp selected?(entry, matchers) do
    Enum.all?(matchers, fn
      [label, "=", wanted] -> Map.get(entry.labels, label) == wanted
      [label, "=~", pattern] -> regex_match?(pattern, Map.get(entry.labels, label, ""))
    end)
  end

  defp regex_match?(pattern, value) do
    case Regex.compile("^(?:#{pattern})$") do
      {:ok, regex} -> Regex.match?(regex, value)
      {:error, _} -> false
    end
  end

  defp pick(list, ts), do: Enum.at(list, hash({:pick, length(list), ts}, length(list)))
  defp hash(term, range), do: :erlang.phash2(term, range)
end
