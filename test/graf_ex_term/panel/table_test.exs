defmodule GrafExTerm.Panel.TableTest do
  use ExUnit.Case, async: true

  alias GrafExTerm.Panel.Table

  @sample_series [
    %{
      labels: %{"instance" => "host1", "job" => "node"},
      values: [{1_700_000_000, 42.5}, {1_700_000_060, 43.1}]
    },
    %{
      labels: %{"instance" => "host2", "job" => "node"},
      values: [{1_700_000_000, 12.0}]
    }
  ]

  describe "prepare/3 with series data" do
    test "produces rows from all series values" do
      {rows, _cols} = Table.prepare({:ok, @sample_series})
      assert length(rows) == 3
    end

    test "produces fixed time/value columns plus label columns" do
      {_rows, cols} = Table.prepare({:ok, @sample_series})
      keys = Enum.map(cols, & &1.key)
      assert :time in keys
      assert :value in keys
      assert :instance in keys
      assert :job in keys
    end

    test "rounds float values to 2 decimal places" do
      {rows, _cols} = Table.prepare({:ok, @sample_series})
      values = Enum.map(rows, & &1.value)
      assert 42.5 in values
      assert 43.1 in values
      assert 12.0 in values
    end

    test "formats timestamps as human-readable strings" do
      {rows, _cols} = Table.prepare({:ok, @sample_series})
      assert Enum.all?(rows, fn r -> is_binary(r.time) end)
    end

    test "caps rows at 100" do
      large_series = [
        %{
          labels: %{},
          values: for(i <- 1..150, do: {1_700_000_000 + i, i * 1.0})
        }
      ]

      {rows, _cols} = Table.prepare({:ok, large_series})
      assert length(rows) <= 100
    end
  end

  describe "prepare/3 with table data" do
    test "passes through columns and rows unchanged" do
      cols = [%{key: :host, label: "Host"}, %{key: :cpu, label: "CPU"}]
      rows = [%{host: "server1", cpu: 55.0}, %{host: "server2", cpu: 22.0}]

      {result_rows, result_cols} = Table.prepare({:table, cols, rows})
      assert result_rows == rows
      assert Enum.map(result_cols, & &1.key) == [:host, :cpu]
    end
  end

  describe "prepare/3 with bad data" do
    test "returns empty rows and columns for error tuples" do
      assert Table.prepare({:error, :no_data}) == {[], []}
    end

    test "returns empty rows and columns for nil" do
      assert Table.prepare(nil) == {[], []}
    end
  end

  describe "prepare/3 with organize config" do
    @cols [
      %{key: :host, label: "Host"},
      %{key: :cpu, label: "CPU"},
      %{key: :mem, label: "Mem"},
      %{key: :disk, label: "Disk"}
    ]
    @rows [%{host: "s1", cpu: 10, mem: 20, disk: 30}]

    test "excludes listed columns" do
      organize = %{exclude: %{"disk" => true}, rename: %{}, index: %{}}
      {_rows, cols} = Table.prepare({:table, @cols, @rows}, organize)
      keys = Enum.map(cols, & &1.key)
      refute :disk in keys
      assert :host in keys
      assert :cpu in keys
      assert :mem in keys
    end

    test "renames columns" do
      organize = %{exclude: %{}, rename: %{"cpu" => "CPU %", "mem" => "Memory"}, index: %{}}
      {_rows, cols} = Table.prepare({:table, @cols, @rows}, organize)
      labels = Enum.map(cols, & &1.label)
      assert "CPU %" in labels
      assert "Memory" in labels
    end

    test "reorders columns by index" do
      organize = %{
        exclude: %{},
        rename: %{},
        index: %{"disk" => 0, "mem" => 1, "cpu" => 2, "host" => 3}
      }

      {_rows, cols} = Table.prepare({:table, @cols, @rows}, organize)
      assert Enum.map(cols, & &1.key) == [:disk, :mem, :cpu, :host]
    end
  end

  describe "prepare/3 with field_config color rules" do
    test "attaches color_fn to columns with thresholds" do
      field_config = %{
        "defaults" => %{
          "thresholds" => %{
            "steps" => [
              %{"color" => "green", "value" => nil},
              %{"color" => "red", "value" => 90}
            ]
          }
        },
        "overrides" => []
      }

      cols = [%{key: :cpu, label: "CPU"}]
      rows = [%{cpu: 95}]

      {_rows, result_cols} = Table.prepare({:table, cols, rows}, nil, field_config)
      cpu_col = Enum.find(result_cols, fn c -> c.key == :cpu end)
      assert is_function(cpu_col.color_fn, 1)
    end

    test "does not attach color_fn when no thresholds or mappings" do
      cols = [%{key: :name, label: "Name"}]
      rows = [%{name: "server1"}]

      {_rows, result_cols} = Table.prepare({:table, cols, rows}, nil, %{})
      name_col = Enum.find(result_cols, fn c -> c.key == :name end)
      refute Map.has_key?(name_col, :color_fn)
    end
  end
end
