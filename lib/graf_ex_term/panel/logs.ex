defmodule GrafExTerm.Panel.Logs do
  @moduledoc """
  Draws a Grafana `logs` panel as a scrolling log, newest line at the bottom.

  Lines carry a `HH:MM:SS` UTC time prefix when the panel's `options.showTime`
  is `true`, and wrap when `options.wrapLogMessage` is `true`; otherwise long
  lines are cut at the panel edge.
  """

  import Drafter.App, only: [log: 1, placeholder: 1]

  @doc """
  Formats fetched entries into display lines.

  `data` is `{:logs, entries}` as the scheduler stores it, each entry a map
  with `:time` in Unix nanoseconds and `:line`; anything else is returned
  unchanged. Returns `{:prepared_logs, lines}`.
  """
  @spec prepare(GrafExTerm.Dashboard.Types.Panel.t(), term()) ::
          {:prepared_logs, [String.t()]} | term()
  def prepare(panel, {:logs, entries}) do
    show_time = get_in(panel.options, ["showTime"]) == true
    {:prepared_logs, Enum.map(entries, &format_entry(&1, show_time))}
  end

  def prepare(_panel, other), do: other

  @doc """
  Builds the log widget for `panel`.

  `data` is `{:prepared_logs, lines}` from `prepare/2` or raw `{:logs,
  entries}`, which is prepared inline; anything else, or no lines, draws a
  "No data" placeholder of `height` rows.
  """
  @spec render(GrafExTerm.Dashboard.Types.Panel.t(), term(), non_neg_integer()) :: tuple()
  def render(_panel, {:prepared_logs, []}, height),
    do: placeholder(label: "No data", height: height)

  def render(panel, {:prepared_logs, lines}, height) do
    log(
      id: :"logs_#{panel.id}",
      lines: lines,
      max_lines: max(length(lines), 1),
      auto_scroll: true,
      wrap: get_in(panel.options, ["wrapLogMessage"]) == true,
      border: false,
      height: height
    )
  end

  def render(panel, {:logs, _} = data, height), do: render(panel, prepare(panel, data), height)
  def render(_panel, _, height), do: placeholder(label: "No data", height: height)

  defp format_entry(%{line: line}, false), do: line

  defp format_entry(%{time: time, line: line}, true) do
    clock =
      time |> DateTime.from_unix!(:nanosecond) |> DateTime.to_time() |> Time.truncate(:second)

    "#{Time.to_string(clock)} #{line}"
  end
end
