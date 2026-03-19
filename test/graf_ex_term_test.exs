defmodule GrafExTermTest do
  use ExUnit.Case, async: true

  test "GrafExTerm module is available" do
    assert Code.ensure_loaded?(GrafExTerm)
  end
end
