defmodule GrafExTerm.Refresh.SeriesWindow do
  @moduledoc """
  Appends freshly fetched samples to series already held for a panel.

  A series is a map with `:labels`, `:values` (a list of `{unix_seconds,
  number}`, oldest first) and optionally `:ref_id`, the target it came from.
  Series are matched by `{ref_id, labels}`.

  `merge/4` keeps each held series' samples from `from` up to, but not
  including, `tail_from`, then appends the matching tail series' samples. Held
  series with no tail keep their remaining samples; tail series with no held
  counterpart are added after the held ones. Series left with no samples are
  dropped. Every other field is taken from the tail series when there is one,
  otherwise from the held series.
  """

  @type series :: %{
          required(:labels) => map(),
          required(:values) => list(),
          optional(atom()) => term()
        }

  @doc """
  Merges `tail` into `held` for the window starting at `from`.

  `tail_from` is the first timestamp the tail query covered; held samples at
  or after it are replaced by the tail's.

  ## Examples

      iex> held = [%{labels: %{"job" => "a"}, values: [{0, 1.0}, {10, 2.0}, {20, 3.0}]}]
      iex> tail = [%{labels: %{"job" => "a"}, values: [{20, 4.0}, {30, 5.0}]}]
      iex> GrafExTerm.Refresh.SeriesWindow.merge(held, tail, 10, 20)
      [%{labels: %{"job" => "a"}, values: [{10, 2.0}, {20, 4.0}, {30, 5.0}]}]

  """
  @spec merge([series()], [series()], integer(), integer()) :: [series()]
  def merge(held, tail, from, tail_from) do
    tail_by_key = Map.new(tail, &{key(&1), &1})
    held_keys = MapSet.new(held, &key/1)

    merged = Enum.map(held, &merge_one(&1, Map.get(tail_by_key, key(&1)), from, tail_from))
    added = Enum.reject(tail, &MapSet.member?(held_keys, key(&1)))

    Enum.reject(merged ++ added, &(&1.values == []))
  end

  defp merge_one(series, nil, from, tail_from) do
    %{series | values: kept_values(series.values, from, tail_from)}
  end

  defp merge_one(series, tail_series, from, tail_from) do
    %{tail_series | values: kept_values(series.values, from, tail_from) ++ tail_series.values}
  end

  defp kept_values(values, from, tail_from) do
    values
    |> Enum.drop_while(fn {ts, _} -> ts < from end)
    |> Enum.take_while(fn {ts, _} -> ts < tail_from end)
  end

  defp key(series), do: {Map.get(series, :ref_id), series.labels}
end
