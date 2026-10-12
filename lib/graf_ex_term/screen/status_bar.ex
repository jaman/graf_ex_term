defmodule GrafExTerm.Screen.StatusBar do
  @moduledoc """
  The one-line bar at the top of the main screen: the app name, then the open
  dashboard's title, time range, refresh interval and when data last arrived.

      StatusBar.render(%{title: "Node Exporter", range_seconds: 3600, refresh: "30s",
        loading: false, updated_at: ~T[12:41:07]})
      #=> " GrafExTerm  ▸ Node Exporter · last 1h · ⟳ 30s · updated 12:41:07"
  """

  import Drafter.App, only: [horizontal: 2, label: 2]

  @app_name " GrafExTerm "

  @type info :: %{
          title: String.t() | nil,
          range_seconds: pos_integer(),
          refresh: String.t() | false | nil,
          loading: boolean(),
          updated_at: Time.t() | nil
        }

  @doc """
  Builds the bar from `info`. A `nil` title shows that no dashboard is open.
  A refresh of `false`, `nil` or `""` shows the `:default_refresh_ms`
  application environment value (default 30 000 ms).
  """
  @spec render(info()) :: tuple()
  def render(info) do
    horizontal(
      [
        label(@app_name, class: :primary, style: %{bold: true}, width: String.length(@app_name)),
        label(" " <> text(info), class: :muted, flex: 1)
      ],
      height: 1
    )
  end

  @doc """
  The bar's text after the app name.

  ## Examples

      iex> GrafExTerm.Screen.StatusBar.text(%{title: "Nodes", range_seconds: 3600, refresh: "30s", loading: true, updated_at: nil})
      "▸ Nodes · last 1h · ⟳ 30s · fetching…"

      iex> GrafExTerm.Screen.StatusBar.text(%{title: nil, range_seconds: 3600, refresh: nil, loading: false, updated_at: nil})
      "▸ no dashboard open"

  """
  @spec text(info()) :: String.t()
  def text(%{title: nil}), do: "▸ no dashboard open"

  def text(info) do
    [
      "▸ " <> info.title,
      "last " <> duration(info.range_seconds),
      "⟳ " <> refresh(info.refresh),
      freshness(info)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp freshness(%{loading: true}), do: "fetching…"
  defp freshness(%{updated_at: nil}), do: nil
  defp freshness(%{updated_at: time}), do: "updated " <> Time.to_string(time)

  defp refresh(interval) when is_binary(interval) and interval != "", do: interval

  defp refresh(_interval) do
    Application.get_env(:graf_ex_term, :default_refresh_ms, 30_000) |> div(1000) |> duration()
  end

  defp duration(seconds) when rem(seconds, 86_400) == 0, do: "#{div(seconds, 86_400)}d"
  defp duration(seconds) when rem(seconds, 3600) == 0, do: "#{div(seconds, 3600)}h"
  defp duration(seconds) when rem(seconds, 60) == 0, do: "#{div(seconds, 60)}m"
  defp duration(seconds), do: "#{seconds}s"
end
