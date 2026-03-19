defmodule GrafExTerm.Dashboard.Types do
  defmodule Target do
    defstruct [:expr, :legend_format, :ref_id, :datasource_ref, :instant, :format]
  end

  defmodule TemplateVar do
    defstruct [:name, :type, :current_value, :options_list, :query]
  end

  defmodule Panel do
    defstruct [:id, :title, :type, :grid_pos, :targets, :field_config, :options, :panels, :organize]
  end

  defmodule Dashboard do
    defstruct [:uid, :title, :description, :panels, :templating, :refresh]
  end
end
