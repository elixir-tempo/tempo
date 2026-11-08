defmodule Tempo.TableReaderTest do
  use ExUnit.Case, async: true

  # A bounded plural expression is a table of its members (`Table.Reader`):
  # each member's `from` and `to`, then a column for each metadata key the
  # members carry. A singular or unbounded expression is not tabular.

  import Tempo.Sigils

  alias Table.Reader
  alias Tempo.Interval
  alias Tempo.IntervalSet

  defp holidays do
    IntervalSet.new!([
      Interval.new!(
        from: ~o"2026-12-25",
        to: ~o"2026-12-25",
        metadata: %{name: "Christmas Day"}
      ),
      Interval.new!(
        from: ~o"2026-12-28",
        to: ~o"2026-12-28",
        metadata: %{name: "Boxing Day", substitute: true}
      )
    ])
  end

  describe "a set as a table" do
    test "has a row for each member: its from, its to and its metadata" do
      assert holidays()
             |> Table.to_rows()
             |> Enum.to_list() == [
               %{
                 from: ~o"2026-12-25",
                 to: ~o"2026-12-25",
                 name: "Christmas Day",
                 substitute: nil
               },
               %{from: ~o"2026-12-28", to: ~o"2026-12-28", name: "Boxing Day", substitute: true}
             ]
    end

    test "has the columns from and to, then each metadata key as it first appears" do
      assert {:rows, %{columns: [:from, :to, :name, :substitute], count: 2}, _rows} =
               Reader.init(holidays())
    end

    test "writes a member that is a value by the ends of its interval" do
      assert ~o"{2026-06,2026-06-15T10}"
             |> Table.to_rows()
             |> Enum.to_list() == [
               %{from: ~o"2026-06", to: ~o"2026-06"},
               %{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}
             ]
    end

    test "has the members a set's exclusions leave" do
      assert ~o"{2026-06,2026-07,^2026-06-15}"
             |> Table.to_rows()
             |> Enum.to_list() == [
               %{from: ~o"2026-06-01", to: ~o"2026-06-14"},
               %{from: ~o"2026-06-16", to: ~o"2026-06-30"},
               %{from: ~o"2026-07", to: ~o"2026-07"}
             ]
    end

    test "leaves out a metadata key that is the name of an end" do
      set =
        IntervalSet.new!([
          Interval.new!(from: ~o"2026-06-15", to: ~o"2026-06-16", metadata: %{from: :import})
        ])

      assert {:rows, %{columns: [:from, :to], count: 1}, rows} = Reader.init(set)
      assert Enum.to_list(rows) == [[~o"2026-06-15", ~o"2026-06-16"]]
    end
  end

  describe "other plural expressions as tables" do
    test "a recurrence with an end has a row for each occurrence" do
      assert {:rows, %{columns: [:from, :to], count: 3}, _rows} =
               Reader.init(~o"R3/2026-01-01/P1D")
    end

    test "a one-of set and a value with a list have a row for each member" do
      assert {:rows, %{count: 2}, _rows} = Reader.init(~o"[2026-06-15,2026-06-20]")
      assert {:rows, %{count: 2}, _rows} = Reader.init(~o"2026Y{1,3}M")
    end
  end

  describe "expressions that are not tables" do
    test "a single value or span is not tabular" do
      assert Reader.init(~o"2026-06") == :none
      assert Reader.init(~o"2026-06-15/2026-06-20") == :none
    end

    test "an unbounded expression is not tabular" do
      assert Reader.init(~o"R/2026-01-01/P1D") == :none
      assert Reader.init(~o"{2017Y..,^2020Y}") == :none
    end
  end
end
