defmodule Tempo.IntervalSetTreeTest do
  @moduledoc """
  The interval-tree backend: agreement with the list backend on every
  accessor, pruning soundness of `overlapping/2`, and the
  anchored-members precondition.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.IntervalSet
  alias Tempo.IntervalSet.Backend.Tree

  @base ~o"2020-01-01"

  defp day(offset), do: Tempo.shift(@base, day: offset)

  defp interval(offset, span) do
    %Tempo.Interval{from: day(offset), to: day(offset + span)}
  end

  defp both_backends(specs) do
    intervals = for {offset, span} <- specs, do: interval(offset, span)
    {:ok, tree} = IntervalSet.new(intervals, backend: :tree)
    {:ok, list} = IntervalSet.new(intervals)
    {tree, list}
  end

  describe "construction" do
    test "the :tree shorthand selects the tree backend" do
      {:ok, set} = IntervalSet.new([interval(0, 5)], backend: :tree)
      assert set.backend == Tree
      assert {:tree, 1, _root} = set.intervals
    end

    test "an empty tree set answers like an empty list set" do
      {:ok, set} = IntervalSet.new([], backend: :tree)
      assert IntervalSet.empty?(set)
      assert IntervalSet.count(set) == 0
      assert IntervalSet.first(set) == nil
      assert IntervalSet.to_list(set) == []
    end

    test "unanchored members are rejected with direction" do
      {:ok, time_of_day} = Tempo.to_interval(~o"T10:00/T11:00")

      assert_raise ArgumentError, ~r/requires anchored/, fn ->
        IntervalSet.new!([time_of_day], backend: :tree)
      end
    end
  end

  describe "covered?/2 through the tree" do
    test "a covered day and an uncovered day" do
      {tree, list} = both_backends([{0, 10}, {50, 5}])

      assert IntervalSet.covered?(tree, day(3))
      assert IntervalSet.covered?(list, day(3))
      refute IntervalSet.covered?(tree, day(20))
      refute IntervalSet.covered?(list, day(20))
    end

    test "the half-open exclusive end is not covered" do
      {tree, _list} = both_backends([{0, 10}])
      refute IntervalSet.covered?(tree, day(10))
      assert IntervalSet.covered?(tree, day(9))
    end
  end

  describe "overlapping/2 pruning" do
    test "returns exactly the intersecting members" do
      {tree, _list} = both_backends([{0, 10}, {20, 10}, {40, 10}])
      lo = Compare.to_utc_seconds(day(25))
      hi = Compare.to_utc_seconds(day(45))

      candidates = Tree.overlapping(tree.intervals, {lo, hi})
      assert Enum.map(candidates, &(&1.from.time[:day] || 1)) |> length() == 2

      assert candidates ==
               Enum.filter(IntervalSet.to_list(tree), fn iv ->
                 Compare.to_utc_seconds(iv.from) < hi and Compare.to_utc_seconds(iv.to) > lo
               end)
    end
  end

  describe "property: tree ≡ list" do
    property "every accessor agrees on random member sets" do
      check all(
              specs <- list_of(tuple({integer(0..3650), integer(1..30)}), max_length: 30),
              probe_offset <- integer(0..3700)
            ) do
        {tree, list} = both_backends(specs)

        assert IntervalSet.to_list(tree) == IntervalSet.to_list(list)
        assert IntervalSet.count(tree) == IntervalSet.count(list)
        assert IntervalSet.first(tree) == IntervalSet.first(list)
        assert IntervalSet.empty?(tree) == IntervalSet.empty?(list)
        assert Enum.to_list(IntervalSet.walk(tree)) == Enum.to_list(IntervalSet.walk(list))

        probe = day(probe_offset)
        assert IntervalSet.covered?(tree, probe) == IntervalSet.covered?(list, probe)
      end
    end

    property "overlapping returns exactly the intersecting members" do
      check all(
              specs <- list_of(tuple({integer(0..3650), integer(1..30)}), max_length: 30),
              lo_offset <- integer(0..3650),
              width <- integer(1..60)
            ) do
        {tree, _list} = both_backends(specs)
        lo = Compare.to_utc_seconds(day(lo_offset))
        hi = Compare.to_utc_seconds(day(lo_offset + width))

        expected =
          Enum.filter(IntervalSet.to_list(tree), fn iv ->
            Compare.to_utc_seconds(iv.from) < hi and Compare.to_utc_seconds(iv.to) > lo
          end)

        assert Tree.overlapping(tree.intervals, {lo, hi}) == expected
      end
    end
  end
end
