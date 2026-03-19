defmodule GrafExTerm.Datasource.Prometheus do
  @behaviour GrafExTerm.Datasource.Behaviour

  @impl true
  def query(config, expr, {from, to}, step) do
    url = Map.fetch!(config, :url) <> "/api/v1/query_range"

    params = [
      query: expr,
      start: from,
      end: to,
      step: step
    ]

    require Logger
    Logger.debug("Prometheus query url=#{url} expr=#{inspect(expr)} from=#{from} to=#{to} step=#{step}")

    with {:ok, response} <- Req.get(url, params: params),
         %{"data" => %{"result" => results}} <- response.body do
      Logger.debug("Prometheus ok count=#{length(results)} expr=#{expr}")
      {:ok, Enum.map(results, &parse_result/1)}
    else
      {:ok, response} ->
        Logger.warning("Prometheus unexpected response url=#{url} expr=#{inspect(expr)} status=#{response.status} body=#{inspect(response.body)}")
        {:error, {:unexpected_response, response.body}}
      {:error, reason} ->
        Logger.warning("Prometheus request failed url=#{url} expr=#{inspect(expr)} reason=#{inspect(reason)}")
        {:error, reason}
      other ->
        Logger.warning("Prometheus unexpected result url=#{url} expr=#{inspect(expr)} other=#{inspect(other)}")
        {:error, {:unexpected, other}}
    end
  end

  @impl true
  def instant_query(config, expr, time) do
    url = Map.fetch!(config, :url) <> "/api/v1/query"
    params = [query: expr, time: time]

    require Logger
    Logger.debug("Prometheus instant query url=#{url} expr=#{inspect(expr)} time=#{time}")

    with {:ok, response} <- Req.get(url, params: params),
         %{"data" => %{"result" => results}} <- response.body do
      {:ok, Enum.map(results, &parse_instant_result/1)}
    else
      {:ok, response} ->
        Logger.warning("Prometheus unexpected response url=#{url} expr=#{inspect(expr)} status=#{response.status} body=#{inspect(response.body)}")
        {:error, {:unexpected_response, response.body}}
      {:error, reason} ->
        Logger.warning("Prometheus request failed url=#{url} expr=#{inspect(expr)} reason=#{inspect(reason)}")
        {:error, reason}
      other ->
        Logger.warning("Prometheus unexpected result url=#{url} expr=#{inspect(expr)} other=#{inspect(other)}")
        {:error, {:unexpected, other}}
    end
  end

  defp parse_instant_result(%{"metric" => labels, "value" => [_ts, val]}) do
    %{labels: labels, value: parse_float(val)}
  end

  defp parse_result(%{"metric" => labels, "values" => values}) do
    %{
      labels: labels,
      values: Enum.map(values, fn [ts, val] ->
        {round(ts), parse_float(val)}
      end)
    }
  end

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val + 0.0
end
