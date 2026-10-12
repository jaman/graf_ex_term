defmodule GrafExTerm.DoctestTest do
  use ExUnit.Case, async: true

  doctest GrafExTerm.Format
  doctest GrafExTerm.Format.Units
  doctest GrafExTerm.Dashboard.TimeRange
  doctest GrafExTerm.Dashboard.GraphMigration
  doctest GrafExTerm.Panel.ValueMapping
  doctest GrafExTerm.Panel.Reduce
  doctest GrafExTerm.Panel.Stat.Reading
  doctest GrafExTerm.Refresh.QueryWindow
  doctest GrafExTerm.Refresh.SeriesWindow
  doctest GrafExTerm.Screen.StatusBar
end
