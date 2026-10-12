defmodule GrafExTerm.Panel.ColorRulesTest do
  use ExUnit.Case, async: true

  alias GrafExTerm.Panel.ColorRules

  describe "resolve_named_color/1" do
    test "returns RGB tuple for known grafana color names" do
      assert ColorRules.resolve_named_color("green") == {115, 191, 105}
      assert ColorRules.resolve_named_color("red") == {242, 73, 92}
      assert ColorRules.resolve_named_color("blue") == {87, 148, 242}
    end

    test "returns nil for transparent" do
      assert ColorRules.resolve_named_color("transparent") == nil
    end

    test "returns nil for unknown names" do
      assert ColorRules.resolve_named_color("not-a-color") == nil
    end
  end

  describe "contrasting_fg/1" do
    test "returns dark foreground for bright backgrounds" do
      assert ColorRules.contrasting_fg({255, 255, 255}) == {15, 15, 15}
      assert ColorRules.contrasting_fg({242, 204, 12}) == {15, 15, 15}
    end

    test "returns light foreground for dark backgrounds" do
      assert ColorRules.contrasting_fg({0, 0, 0}) == {240, 240, 240}
      assert ColorRules.contrasting_fg({31, 96, 196}) == {240, 240, 240}
    end

    test "uses contrast cache for named grafana colors" do
      green = {115, 191, 105}
      {fg_r, _, _} = ColorRules.contrasting_fg(green)
      assert fg_r in [15, 240]
    end
  end

  describe "build/2" do
    test "returns map of nil color_fns when field_config has no thresholds or mappings" do
      columns = [%{key: :value, label: "Value"}, %{key: :status, label: "Status"}]
      result = ColorRules.build(%{}, columns)
      assert result[:value] == nil
      assert result[:status] == nil
    end

    test "builds threshold-based color_fn for numeric values" do
      field_config = %{
        "defaults" => %{
          "thresholds" => %{
            "steps" => [
              %{"color" => "green", "value" => nil},
              %{"color" => "yellow", "value" => 70},
              %{"color" => "red", "value" => 90}
            ]
          }
        },
        "overrides" => []
      }

      columns = [%{key: :cpu, label: "CPU"}]
      result = ColorRules.build(field_config, columns)
      color_fn = result[:cpu]
      assert is_function(color_fn, 1)

      assert color_fn.(50) == %{bg: {115, 191, 105}, fg: {15, 15, 15}}
      assert color_fn.(75) == %{bg: {250, 222, 42}, fg: {15, 15, 15}}
      assert color_fn.(95) == %{bg: {242, 73, 92}, fg: {240, 240, 240}}
    end

    test "builds value-mapping color_fn" do
      field_config = %{
        "defaults" => %{
          "mappings" => [
            %{
              "type" => "value",
              "options" => %{
                "OK" => %{"color" => "green"},
                "ERROR" => %{"color" => "red"}
              }
            }
          ]
        },
        "overrides" => []
      }

      columns = [%{key: :status, label: "Status"}]
      result = ColorRules.build(field_config, columns)
      color_fn = result[:status]
      assert is_function(color_fn, 1)

      assert color_fn.("OK") == %{bg: {115, 191, 105}, fg: {15, 15, 15}}
      assert color_fn.("ERROR") == %{bg: {242, 73, 92}, fg: {240, 240, 240}}
      assert color_fn.("UNKNOWN") == nil
    end

    test "per-column override takes precedence over defaults" do
      field_config = %{
        "defaults" => %{
          "thresholds" => %{
            "steps" => [%{"color" => "green", "value" => nil}]
          }
        },
        "overrides" => [
          %{
            "matcher" => %{"id" => "byName", "options" => "Errors"},
            "properties" => [
              %{
                "id" => "thresholds",
                "value" => %{
                  "steps" => [
                    %{"color" => "green", "value" => nil},
                    %{"color" => "red", "value" => 1}
                  ]
                }
              }
            ]
          }
        ]
      }

      columns = [
        %{key: :errors, label: "Errors"},
        %{key: :requests, label: "Requests"}
      ]

      result = ColorRules.build(field_config, columns)
      errors_fn = result[:errors]
      requests_fn = result[:requests]

      assert errors_fn.(0) == %{bg: {115, 191, 105}, fg: {15, 15, 15}}
      assert errors_fn.(5) == %{bg: {242, 73, 92}, fg: {240, 240, 240}}
      assert requests_fn == nil
    end

    test "returns nil color_fn when thresholds have no valued steps" do
      field_config = %{
        "defaults" => %{
          "thresholds" => %{
            "steps" => [%{"color" => "green", "value" => nil}]
          }
        },
        "overrides" => []
      }

      columns = [%{key: :value, label: "Value"}]
      result = ColorRules.build(field_config, columns)
      assert result[:value] == nil
    end

    test "parses hex colors" do
      field_config = %{
        "defaults" => %{
          "thresholds" => %{
            "steps" => [
              %{"color" => "#73bf69", "value" => nil},
              %{"color" => "#f2495c", "value" => 90}
            ]
          }
        },
        "overrides" => []
      }

      columns = [%{key: :cpu, label: "CPU"}]
      result = ColorRules.build(field_config, columns)
      color_fn = result[:cpu]

      assert %{bg: {115, 191, 105}, fg: _} = color_fn.(50)
      assert %{bg: {242, 73, 92}, fg: _} = color_fn.(95)
    end
  end
end
