defmodule GrafExTerm.Screen.VariableBar do
  @moduledoc """
  Draws a dashboard's template variables as a row of labelled selectors.
  """

  import Drafter.App, only: [horizontal: 2, label: 2, option_list: 2]

  @doc """
  Builds the variable selector row.

  `template_vars` is a dashboard's `:templating` list of
  `GrafExTerm.Dashboard.Types.TemplateVar` structs; an empty list produces an
  empty horizontal layout. `values` maps variable name to the currently
  selected value, and a variable absent from it falls back to its
  `:current_value`.

  Choosing an option emits `{:var_changed, var_name}` carrying the new value,
  which the screen is expected to forward to
  `GrafExTerm.Variable.Manager.set_value/3`.
  """
  @spec render([GrafExTerm.Dashboard.Types.TemplateVar.t()], map()) :: tuple()

  def render([], _values), do: horizontal([], gap: 0)

  def render(template_vars, values) do
    items =
      Enum.map(template_vars, fn var ->
        current = Map.get(values, var.name, var.current_value)
        options = var.options_list

        horizontal(
          [
            label("#{var.name}:", style: %{bold: true}),
            option_list(options,
              selected: current,
              height: 1,
              on_select: {:var_changed, var.name}
            )
          ],
          gap: 1
        )
      end)

    horizontal(items, gap: 2)
  end
end
