defmodule Mix.Tasks.DumpLayout do
  use Mix.Task

  alias GrafExTerm.Dashboard.Parser

  @shortdoc "Generate a standalone Drafter .exs from a Grafana dashboard JSON"

  @impl Mix.Task
  def run([json_path | _]) do
    raw = json_path |> File.read!() |> Jason.decode!()
    {:ok, dashboard} = Parser.parse(raw)

    height_ratio = Application.get_env(:graf_ex_term, :height_ratio, 3)
    sections = group_by_row_section(dashboard.panels)
    section_code = Enum.map_join(sections, ",\n", &section_to_code(&1, height_ratio))

    output = exs_template(dashboard.title, section_code)
    out_path = "generated_layout.exs"
    File.write!(out_path, output)
    Mix.shell().info("Written to #{out_path}")
  end

  def run(_) do
    Mix.shell().error("Usage: mix dump_layout path/to/dashboard.json")
  end

  defp group_by_row_section(panels) do
    {sections, current_row, current_panels} =
      Enum.reduce(panels, {[], nil, []}, fn panel, {sections, current_row, current_panels} ->
        if panel.type == "row" do
          finished = if current_row || current_panels != [], do: [{current_row, current_panels}], else: []
          {sections ++ finished, panel, []}
        else
          {sections, current_row, current_panels ++ [panel]}
        end
      end)

    sections ++ [{current_row, current_panels}]
  end

  defp section_to_code({nil, panels}, height_ratio) do
    panels_code = panel_rows_to_code(panels, height_ratio)
    panels_code
  end

  defp section_to_code({row_panel, panels}, height_ratio) do
    children_code = panel_rows_to_code(panels, height_ratio)
    content_height = compute_content_height(panels, height_ratio)

    """
          collapsible(
            #{inspect(row_panel.title)},
            [
    #{indent(children_code, 10)}
            ],
            id: #{inspect(:"row_#{row_panel.id}")},
            content_height: #{content_height},
            expanded: false,
            on_toggle: fn _expanded -> :ok end
          )\
    """
  end

  defp panel_rows_to_code(panels, height_ratio) do
    panels
    |> Enum.sort_by(fn p -> p.grid_pos.x end)
    |> Enum.group_by(fn p -> p.grid_pos.y end)
    |> Enum.sort_by(fn {y, _} -> y end)
    |> Enum.map_join(",\n", fn {_, row_panels} ->
      row_height = row_panels |> Enum.map(fn p -> p.grid_pos.h end) |> Enum.max(fn -> 8 end) |> Kernel.*(height_ratio)

      widgets_code =
        row_panels
        |> Enum.sort_by(fn p -> p.grid_pos.x end)
        |> Enum.map_join(",\n", fn panel ->
          """
                    vertical([
                      #{panel_to_code(panel, row_height)}
                    ], colspan: #{panel.grid_pos.w})\
          """
        end)

      """
                horizontal(
                  [
          #{widgets_code}
                  ],
                  gap: 1,
                  height: #{row_height}
                )\
      """
    end)
  end

  defp panel_to_code(panel, height) do
    case panel.type do
      "stat" -> ~s|placeholder(label: "stat: #{esc(panel.title)}", height: #{height})|
      "table" -> ~s|placeholder(label: "table: #{esc(panel.title)}", height: #{height})|
      "gauge" -> ~s|placeholder(label: "gauge: #{esc(panel.title)}", height: #{height})|
      "bargauge" -> ~s|placeholder(label: "bargauge: #{esc(panel.title)}", height: #{height})|
      "text" -> ~s|placeholder(label: "text: #{esc(panel.title)}", height: #{height})|
      "row" -> ~s|placeholder(label: "row: #{esc(panel.title)}", height: 1)|
      type when type in ["timeseries", "graph"] ->
        ~s|chart(@chart_data, chart_type: :braille_area, show_baseline: true, title: "#{esc(panel.title)}", height: #{height})|
      _ -> ~s|placeholder(label: "#{esc(panel.type)}: #{esc(panel.title)}", height: #{height})|
    end
  end

  defp compute_content_height(panels, height_ratio) do
    panels
    |> Enum.group_by(fn p -> p.grid_pos.y end)
    |> Enum.map(fn {_, row_panels} ->
      row_panels |> Enum.map(fn p -> p.grid_pos.h end) |> Enum.max(fn -> 8 end) |> Kernel.*(height_ratio)
    end)
    |> Enum.sum()
  end

  defp esc(str), do: String.replace(to_string(str), ~s|"|, ~s|\\"|)

  defp indent(str, n) do
    pad = String.duplicate(" ", n)
    str |> String.split("\n") |> Enum.join("\n" <> pad)
  end

  defp exs_template(title, sections) do
    """
    Mix.install([{:drafter, path: Path.join(__DIR__, "../drafter")}, {:elixir_make, "~> 0.9"}])

    defmodule GeneratedDashboard do
      use Drafter.App
      import Drafter.App

      @chart_data Enum.map(1..60, fn i -> 50 + 30 * :math.sin(i * 0.2) end)

      def mount(_props), do: %{}

      def keybindings, do: [{"q", "quit"}]

      def render(_state) do
        vertical([
          header(#{inspect(title)}),
          scrollable(
            [
    #{sections}
            ],
            flex: 1,
            click_to_scroll: true
          ),
          footer(bindings: [{"q", "quit"}])
        ])
      end

      def handle_event({:key, :q}, _state), do: {:stop, :normal}
      def handle_event(_event, _data, state), do: {:noreply, state}
      def handle_event(_event, state), do: {:noreply, state}
    end

    Drafter.run(GeneratedDashboard)
    """
  end
end
