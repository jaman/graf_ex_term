defmodule GrafExTerm.Dashboard.Types do
  @moduledoc false

  defmodule Target do
    @moduledoc false
    defstruct [:expr, :legend_format, :ref_id, :datasource_ref, :instant, :format]
  end

  defmodule TemplateVar do
    @moduledoc false
    defstruct [:name, :type, :current_value, :options_list, :query]
  end

  defmodule Panel do
    @moduledoc false
    defstruct [:id, :title, :type, :grid_pos, :targets, :field_config, :options, :panels, :organize]
  end

  defmodule Dashboard do
    @moduledoc false
    defstruct [:uid, :title, :description, :panels, :templating, :refresh]
  end
end
