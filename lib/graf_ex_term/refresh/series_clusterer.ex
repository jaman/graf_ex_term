defmodule GrafExTerm.Refresh.SeriesClusterer do
  @moduledoc """
  Collapses a large set of similar series into a smaller set of representative
  ones so a chart stays readable.

  Series are clustered by their mean value: sorted by mean, split wherever
  consecutive means differ by more than the value range divided by the target
  count, and then the closest neighbouring groups merged until the target is
  met.

  A cluster is represented by its first member with its samples replaced by
  the per-timestamp median of the group, its name suffixed with the number of
  other members, and a `:weight` field set to the member count.
  `GrafExTerm.Panel.Timeseries` reads that weight to scale a cluster's opacity.
  Single-member clusters keep their own values and get a weight of 1.

  Timestamps come from the first member of each cluster; a member missing a
  timestamp contributes `0.0` at that point, so series that do not share a
  time base drag the median down.
  """

  @max_series 30
  @min_series_for_clustering 25

  @doc """
  Reduces `series` to at most `max_series` representatives.

  `series` is a list of maps with `:values`, each a list of
  `{timestamp, number}`. `max_series` is the target count and defaults to 30.

  Lists of 25 series or fewer are returned untouched, without the `:weight`
  field, whatever `max_series` says.

  Returns the clustered list, each entry carrying a `:weight` giving how many
  input series it stands for.
  """
  @spec cluster(list(), non_neg_integer()) :: list()
  def cluster(series, max_series \\ @max_series)

  def cluster(series, _max_series) when length(series) <= @min_series_for_clustering, do: series

  def cluster(series, max_series) do
    scored = Enum.map(series, fn s -> {series_mean(s.values), s} end)
    sorted = Enum.sort_by(scored, &elem(&1, 0))
    clusters = epsilon_group(sorted, max_series)
    Enum.map(clusters, &merge_cluster/1)
  end

  defp epsilon_group(sorted_scored, target_k) do
    range = compute_range(sorted_scored)
    epsilon = range / max(target_k, 1)
    groups = do_epsilon_group(sorted_scored, epsilon)

    if length(groups) <= target_k do
      groups
    else
      merge_smallest_gaps(groups, target_k)
    end
  end

  defp do_epsilon_group(sorted_scored, epsilon) do
    Enum.chunk_while(sorted_scored, nil, &extend_group(&1, &2, epsilon), &close_group/1)
  end

  defp extend_group({mean, _} = item, nil, _epsilon), do: {:cont, {mean, [item]}}

  defp extend_group({mean, _} = item, {prev_mean, group}, epsilon)
       when abs(mean - prev_mean) <= epsilon,
       do: {:cont, {mean, [item | group]}}

  defp extend_group({mean, _} = item, {_prev_mean, group}, _epsilon),
    do: {:cont, Enum.reverse(group), {mean, [item]}}

  defp close_group(nil), do: {:cont, nil}
  defp close_group({_mean, group}), do: {:cont, Enum.reverse(group), nil}

  defp merge_smallest_gaps(groups, target_k) when length(groups) <= target_k, do: groups

  defp merge_smallest_gaps(groups, target_k) do
    gaps =
      groups
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index()
      |> Enum.map(fn {[a, b], idx} ->
        a_mean = a |> Enum.map(&elem(&1, 0)) |> mean()
        b_mean = b |> Enum.map(&elem(&1, 0)) |> mean()
        {abs(b_mean - a_mean), idx}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    {_, merge_idx} = hd(gaps)
    merged = merge_at(groups, merge_idx)
    merge_smallest_gaps(merged, target_k)
  end

  defp merge_at(groups, idx) do
    {head, [a, b | tail]} = Enum.split(groups, idx)
    head ++ [a ++ b | tail]
  end

  defp merge_cluster([{_mean, single}]), do: Map.put(single, :weight, 1)

  defp merge_cluster(members) do
    count = length(members)
    series_list = Enum.map(members, &elem(&1, 1))
    reference = hd(series_list)
    timestamps = Enum.map(reference.values, &elem(&1, 0))

    indexed_series =
      Enum.map(series_list, fn s ->
        Map.new(s.values, fn {ts, v} -> {ts, v} end)
      end)

    merged_values =
      Enum.map(timestamps, fn ts ->
        vals = Enum.map(indexed_series, fn idx -> Map.get(idx, ts, 0.0) end)
        {ts, median(vals)}
      end)

    cluster_name = build_cluster_name(series_list, count)

    reference
    |> Map.put(:values, merged_values)
    |> Map.put(:name, cluster_name)
    |> Map.put(:weight, count)
  end

  defp build_cluster_name(series_list, count) do
    first_name =
      case hd(series_list) do
        %{name: name} when is_binary(name) and name != "" -> name
        _ -> "cluster"
      end

    "#{first_name} (+#{count - 1})"
  end

  defp series_mean(values) when values == [], do: 0.0

  defp series_mean(values) do
    sum = Enum.reduce(values, 0.0, fn {_ts, v}, acc -> acc + v end)
    sum / length(values)
  end

  defp compute_range([]), do: 1.0

  defp compute_range(sorted) do
    {min_val, _} = hd(sorted)
    {max_val, _} = List.last(sorted)
    max(max_val - min_val, 0.001)
  end

  defp mean([]), do: 0.0
  defp mean(vals), do: Enum.sum(vals) / length(vals)

  defp median([]), do: 0.0

  defp median(vals) do
    sorted = vals |> Enum.sort() |> List.to_tuple()
    n = tuple_size(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 0 do
      (elem(sorted, mid - 1) + elem(sorted, mid)) / 2.0
    else
      elem(sorted, mid) * 1.0
    end
  end
end
