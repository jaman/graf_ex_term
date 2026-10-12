defmodule GrafExTerm.Datasource.Loki do
  @moduledoc """
  Reads log lines from the Loki HTTP API for `logs` panels.

  `query/4` calls `/loki/api/v1/query_range` relative to the `:url` in the
  config map, newest lines first, and returns them oldest first so they read
  top to bottom. Every non-success logs at `:warning` with the URL and
  expression.

      GrafExTerm.Datasource.Loki.query(
        %{url: "http://localhost:3100"},
        ~s({job="api"}),
        {from, to},
        500
      )
  """

  require Logger

  @type entry :: %{time: integer(), labels: %{String.t() => String.t()}, line: String.t()}

  @doc """
  Fetches up to `limit` of the newest lines matching the LogQL `expr` between
  `from` and `to`, Unix seconds.

  Returns `{:ok, entries}` oldest first, each entry carrying `:time` in Unix
  nanoseconds, the stream `:labels` and the `:line`, or `{:error, reason}`.
  """
  @spec query(map(), String.t(), {integer(), integer()}, pos_integer()) ::
          {:ok, [entry()]} | {:error, term()}
  def query(config, expr, {from, to}, limit) do
    url = Map.fetch!(config, :url) <> "/loki/api/v1/query_range"

    params = [
      query: expr,
      start: from * 1_000_000_000,
      end: to * 1_000_000_000,
      limit: limit,
      direction: "backward"
    ]

    with {:ok, response} <- Req.get(url, params: params),
         %{"data" => %{"result" => streams}} <- response.body do
      {:ok,
       streams |> Enum.flat_map(&stream_entries/1) |> Enum.sort_by(& &1.time) |> Enum.take(-limit)}
    else
      {:ok, response} ->
        Logger.warning(
          "Loki unexpected response url=#{url} expr=#{inspect(expr)} status=#{response.status} body=#{inspect(response.body)}"
        )

        {:error, {:unexpected_response, response.body}}

      {:error, reason} ->
        Logger.warning(
          "Loki request failed url=#{url} expr=#{inspect(expr)} reason=#{inspect(reason)}"
        )

        {:error, reason}

      other ->
        Logger.warning(
          "Loki unexpected result url=#{url} expr=#{inspect(expr)} other=#{inspect(other)}"
        )

        {:error, {:unexpected, other}}
    end
  end

  defp stream_entries(%{"stream" => labels, "values" => values}) do
    for [time, line] <- values do
      %{time: String.to_integer(time), labels: labels, line: line}
    end
  end

  defp stream_entries(_other), do: []
end
