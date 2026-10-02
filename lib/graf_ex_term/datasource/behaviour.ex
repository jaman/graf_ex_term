defmodule GrafExTerm.Datasource.Behaviour do
  @moduledoc """
  Contract a metrics backend must satisfy to serve panel targets.

  `GrafExTerm.Datasource.Prometheus` is the only implementation.
  """

  @doc """
  Samples `expr` repeatedly across a time window.

  `config` must contain a `:url` key giving the base URL of the backend;
  fetching it is expected to raise if absent. `expr` is the query string,
  already variable-substituted. `time_range` is `{from, to}` as Unix seconds.
  `step` is the sampling interval in seconds.

  Returns `{:ok, series}` where each series is a map with `:labels` (string
  key to string value) and `:values` (a list of `{unix_seconds, float}`
  ordered oldest first), or `{:error, reason}`.
  """
  @callback query(
              config :: map(),
              expr :: String.t(),
              time_range :: {integer(), integer()},
              step :: integer()
            ) ::
              {:ok, list()} | {:error, term()}

  @doc """
  Evaluates `expr` at a single instant.

  `config` and `expr` are as for `c:query/4`. `time` is the evaluation instant
  as Unix seconds.

  Returns `{:ok, results}` where each result is a map with `:labels` and a
  single `:value` float, or `{:error, reason}`.
  """
  @callback instant_query(config :: map(), expr :: String.t(), time :: integer()) ::
              {:ok, list()} | {:error, term()}
end
