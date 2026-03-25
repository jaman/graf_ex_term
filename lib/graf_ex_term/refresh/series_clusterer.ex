defmodule GrafExTerm.Refresh.SeriesClusterer do
  @max_series 30
  @min_series_for_clustering 25

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

    cond do
      length(groups) <= target_k ->
        groups

      true ->
        merge_smallest_gaps(groups, target_k)
    end
  end

  defp do_epsilon_group([], _epsilon), do: []

  defp do_epsilon_group([first | rest], epsilon) do
    {current_group, groups} =
      Enum.reduce(rest, {[first], []}, fn {mean, _s} = item, {current, acc} ->
        {prev_mean, _} = List.last(current)

        if abs(mean - prev_mean) <= epsilon do
          {current ++ [item], acc}
        else
          {[item], acc ++ [current]}
        end
      end)

    groups ++ [current_group]
  end

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
    sorted = Enum.sort(vals)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 0 do
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2.0
    else
      Enum.at(sorted, mid) * 1.0
    end
  end
end
