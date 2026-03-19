defmodule GrafExTerm.Screen.VariableBar do
  import Drafter.App, only: [horizontal: 2, label: 2, option_list: 2]

  def render([], _values), do: horizontal([], gap: 0)

  def render(template_vars, values) do
    items =
      Enum.map(template_vars, fn var ->
        current = Map.get(values, var.name, var.current_value)
        options = var.options_list

        horizontal([
          label("#{var.name}:", style: %{bold: true}),
          option_list(options,
            selected: current,
            height: 1,
            on_select: {:var_changed, var.name}
          )
        ], gap: 1)
      end)

    horizontal(items, gap: 2)
  end
end
