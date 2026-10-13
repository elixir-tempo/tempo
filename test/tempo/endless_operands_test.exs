defmodule Tempo.EndlessOperandsTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{Algebra, ConversionError, IntervalSet}

  # A set operation with an operand that has no end, a recurrence or a set
  # read from a stream, is as bounded as the operation makes it
  # (`plans/decisions.md`, 9): within the bounded operand where the answer
  # lies within it, and a set with no end, in the order of time, where it
  # does not.

  @weeks ~o"R/2026-06-01/P1W"
  @other_days ~o"R/2026-06-03/P2D"
  @busy ~o"2026-06-10/2026-06-20"

  defp fifteenths do
    {:ok, set} = Tempo.select(~o"2026-06-01/..", ~o"15D")
    set
  end

  defp in_june(set) do
    {:ok, members} = Tempo.members(set, within: ~o"2026-06")
    Enum.map(members, &Tempo.to_iso8601!/1)
  end

  describe "an answer that lies within the bounded operand" do
    test "is bounded: an intersection, in either order" do
      assert Tempo.intersection(@weeks, @busy) == {:ok, ~o"{2026-06-10/2026-06-20}"}
      assert Tempo.intersection(@busy, @weeks) == {:ok, ~o"{2026-06-10/2026-06-20}"}
      assert Tempo.intersection(fifteenths(), @busy) == {:ok, ~o"{2026-06-15/2026-06-15}"}
    end

    test "is bounded: a difference from the bounded operand" do
      assert Tempo.difference(@busy, @weeks) == {:ok, ~o"{}"}

      assert Tempo.difference(@busy, fifteenths()) ==
               {:ok, ~o"{2026-06-10/2026-06-14,2026-06-16/2026-06-20}"}
    end
  end

  describe "an answer that does not" do
    test "is a set with no end: a union, in either order" do
      for {:ok, union} <- [Tempo.union(@weeks, @busy), Tempo.union(@busy, @weeks)] do
        refute Tempo.bounded?(union)

        assert Enum.take(in_june(union), 4) ==
                 ["2026Y6M1D/7D", "2026Y6M8D/14D", "2026Y6M10D/20D", "2026Y6M15D/21D"]
      end
    end

    test "is a set with no end: a difference from the operand with no end" do
      {:ok, free} = Tempo.difference(@weeks, @busy)
      refute Tempo.bounded?(free)

      assert in_june(free) ==
               [
                 "2026Y6M1D/7D",
                 "2026Y6M8D/9D",
                 "2026Y6M21D/2026Y6M21D",
                 "2026Y6M22D/28D",
                 "2026Y6M29D/7M5D"
               ]
    end

    test "is a set with no end: a symmetric difference, in either order" do
      {:ok, one} = Tempo.symmetric_difference(@weeks, @busy)
      {:ok, other} = Tempo.symmetric_difference(@busy, @weeks)
      assert in_june(one) == in_june(other)
      assert "2026Y6M8D/9D" in in_june(one)
    end

    test "is the same for a set read from a stream" do
      {:ok, kept} = Tempo.difference(fifteenths(), ~o"2026-07")
      refute Tempo.bounded?(kept)
      assert Enum.take(kept, 2) == [~o"2026-06-15/2026-06-15", ~o"2026-08-15/2026-08-15"]

      {:ok, both} = Tempo.union(fifteenths(), ~o"2026-07-01")

      assert Enum.take(both, 3) == [
               ~o"2026-06-15/2026-06-15",
               ~o"2026-07-01/2026-07-01",
               ~o"2026-07-15/2026-07-15"
             ]
    end

    # A window takes each occurrence that begins in it whole, so the two are
    # compared over the window itself.
    test "is what the window gives, where one is given" do
      {:ok, free} = Tempo.difference(@weeks, @busy)
      {:ok, windowed} = Tempo.difference(@weeks, @busy, within: ~o"2026-06")
      {:ok, in_june} = Tempo.intersection(free, ~o"2026-06")
      {:ok, windowed_in_june} = Tempo.intersection(windowed, ~o"2026-06")

      assert covered(in_june) == covered(windowed_in_june)
    end
  end

  describe "two operands with no end" do
    test "have a union, in the order of time" do
      {:ok, union} = Tempo.union(@weeks, @other_days)
      assert Enum.take(in_june(union), 3) == ["2026Y6M1D/7D", "2026Y6M3D/4D", "2026Y6M5D/6D"]
    end

    test "have no other answer without a window: one may cover the other for ever" do
      for operation <- [
            &Tempo.intersection/2,
            &Tempo.difference/2,
            &Tempo.symmetric_difference/2
          ] do
        assert {:error, %ConversionError{reason: :unbounded}} = operation.(@weeks, @other_days)
      end

      assert {:ok, met} =
               Tempo.intersection(@weeks, @other_days, within: ~o"2026-06-01/2026-06-07")

      assert IntervalSet.count(met) > 0
    end
  end

  describe "the sweep one result at a time" do
    # The same operands swept whole and swept one result at a time cover the
    # same time: the second keeps apart what the first joins where members
    # abut, and nothing else differs.
    test "covers what the whole sweep covers" do
      pairs = [
        {~o"{2026-06-01/2026-06-07,2026-06-08/2026-06-14,2026-06-20/2026-06-25}", @busy},
        {~o"2026-06", ~o"{2026-06-05,2026-06-06,2026-06-28/2026-07-02}"},
        {~o"{2026-06-01T09/2026-06-01T17,2026-06-02T09/2026-06-02T17}",
         ~o"2026-06-01T12/2026-06-02T10"},
        {~o"2026-06-10/2026-06-12", ~o"2026-06-01/2026-06-30"}
      ]

      for {a, b} <- pairs,
          {x, y} <- [{a, b}, {b, a}],
          operation <- [:difference, :symmetric_difference] do
        {:ok, frame, pa, pb} = Algebra.aligned(x, y, [])
        whole = apply(Algebra, operation, [pa, pb, frame])
        one_at_a_time = operation |> Algebra.swept(pa, pb) |> Enum.to_list()

        assert joined(one_at_a_time) == joined(whole)
      end
    end
  end

  defp covered(set) do
    {:ok, frame, positioned} = Algebra.positioned(set, [])
    positioned |> Algebra.covered(1, frame) |> Enum.map(&{&1.start, &1.stop})
  end

  # Extents in order, with those that abut made one.
  defp joined(results) do
    results
    |> Enum.map(&{&1.start, &1.stop})
    |> Enum.sort()
    |> Enum.reduce([], fn
      {start, stop}, [{earlier, start} | rest] -> [{earlier, stop} | rest]
      extent, done -> [extent | done]
    end)
    |> Enum.reverse()
  end
end
