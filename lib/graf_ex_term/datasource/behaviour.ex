defmodule GrafExTerm.Datasource.Behaviour do
  @callback query(config :: map(), expr :: String.t(), time_range :: {integer(), integer()}, step :: integer()) ::
              {:ok, list()} | {:error, term()}

  @callback instant_query(config :: map(), expr :: String.t(), time :: integer()) ::
              {:ok, list()} | {:error, term()}
end
