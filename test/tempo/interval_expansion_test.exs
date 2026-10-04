defmodule Tempo.IntervalExpansion.Test do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  # Tests for the two expansion paths added alongside
  # `Tempo.Math` arithmetic:
  #
  #   1. Non-contiguous masks — `1985-XX-15` expands to 12
  #      disjoint day-intervals.
  #   2. Bounded recurrence (`R3/1985-01/P1M`) expands to N
  #      disjoint occurrences.
  #   3. `from + duration` and `duration + to` intervals
  #      materialise to concrete closed intervals via
  #      `Tempo.Math.add/2` and `subtract/2`.

  describe "non-contiguous masks" do
    test "year-month-masked-day expands to 12 day-intervals" do
      {:ok, tempo} = Tempo.from_iso8601("1985-XX-15")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(tempo)

      assert Enum.count(intervals) == 12
      assert Enum.map(intervals, & &1.from.time[:month]) == 1..12 |> Enum.to_list()

      assert Enum.all?(intervals, fn i ->
               i.from.time[:day] == 15 and i.to.time[:day] == 16
             end)
    end

    test "partial mask narrowing — `1985-X5-15`" do
      # Mask `[:X, 5]` on month: valid months ending in 5 in the
      # range 1..12 → only 5.
      {:ok, tempo} = Tempo.from_iso8601("1985-X5-15")
      {:ok, %Tempo.Interval{from: from}} = Tempo.to_interval(tempo)
      assert from.time[:month] == 5
      assert from.time[:day] == 15
    end

    test "first-of-each-month — `1985-XX-01`" do
      {:ok, tempo} = Tempo.from_iso8601("1985-XX-01")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(tempo)
      assert Enum.count(intervals) == 12
      assert Enum.all?(intervals, fn i -> i.from.time[:day] == 1 end)
    end

    test "fully masked (`1985-XX-XX`) still widens to year (contiguous path)" do
      # All tail units are masks, no concrete pins the sub-span →
      # widen to the coarsest un-masked prefix as before.
      {:ok, tempo} = Tempo.from_iso8601("1985-XX-XX")
      {:ok, %Tempo.Interval{from: from, to: to}} = Tempo.to_interval(tempo)
      assert from.time == [year: 1985]
      assert to.time == [year: 1986]
    end

    test "month-masked with no day (`1985-XX`)" do
      # No tail concrete value → contiguous widening (year-level).
      {:ok, tempo} = Tempo.from_iso8601("1985-XX")
      {:ok, %Tempo.Interval{from: from, to: to}} = Tempo.to_interval(tempo)
      assert from.time == [year: 1985]
      assert to.time == [year: 1986]
    end
  end

  describe "bounded recurrence" do
    test "`R3/1985-01/P1M` expands to 3 distinct month members" do
      {:ok, interval} = Tempo.from_iso8601("R3/1985-01/P1M")
      {:ok, set} = Tempo.to_interval(interval)

      # Under member-preserving default, each occurrence is a
      # distinct member. Call `coalesce/1` for the canonical span.
      assert IntervalSet.count(set) == 3
      assert Enum.map(set.intervals, & &1.from.time[:month]) == [1, 2, 3]

      coalesced = IntervalSet.coalesce(set)
      [span] = coalesced.intervals
      assert span.from.time == [year: 1985, month: 1]
      assert span.to.time == [year: 1985, month: 4]
    end

    test "`R5/1985-01-01/P1D` — 5 distinct day members" do
      {:ok, interval} = Tempo.from_iso8601("R5/1985-01-01/P1D")
      {:ok, set} = Tempo.to_interval(interval)
      assert IntervalSet.count(set) == 5

      coalesced = IntervalSet.coalesce(set)
      [span] = coalesced.intervals
      assert span.from.time == [year: 1985, month: 1, day: 1]
      assert span.to.time == [year: 1985, month: 1, day: 6]
    end

    test "`R2/1985-01/P1Y` — two distinct year members; coalesce to a 2-year span" do
      {:ok, interval} = Tempo.from_iso8601("R2/1985-01/P1Y")
      {:ok, set} = Tempo.to_interval(interval)
      assert IntervalSet.count(set) == 2

      coalesced = IntervalSet.coalesce(set)
      [span] = coalesced.intervals
      assert span.from.time == [year: 1985, month: 1]
      assert span.to.time == [year: 1987, month: 1]
    end

    # A quarter is a group of months, which a month could not be added to,
    # so the recurrence was refused. It is counted from the point the quarter
    # starts at, as an interval that starts with a quarter is.
    test "a start that names a span is counted from the point the span starts at" do
      {:ok, quarters} = Tempo.from_iso8601("R3/2026-33/P3M")
      {:ok, set} = Tempo.to_interval(quarters)

      # `2026-33` is the first quarter of 2026.
      assert set |> IntervalSet.members() |> Enum.map(&{&1.from, &1.to}) == [
               {~o"2026Y1M", ~o"2026Y4M"},
               {~o"2026Y4M", ~o"2026Y7M"},
               {~o"2026Y7M", ~o"2026Y10M"}
             ]
    end
  end

  describe "from + duration" do
    test "`1985-01/P3M` materialises to `[1985-01, 1985-04)`" do
      {:ok, interval} = Tempo.from_iso8601("1985-01/P3M")
      {:ok, %Tempo.Interval{from: from, to: to}} = Tempo.to_interval(interval)
      assert from.time == [year: 1985, month: 1]
      assert to.time == [year: 1985, month: 4]
    end

    test "`1985-01-15/P1W` materialises with day-level endpoints" do
      {:ok, interval} = Tempo.from_iso8601("1985-01-15/P1W")
      {:ok, %Tempo.Interval{from: from, to: to}} = Tempo.to_interval(interval)
      assert from.time == [year: 1985, month: 1, day: 15]
      assert to.time == [year: 1985, month: 1, day: 22]
    end

    test "Enum.to_list respects the duration bound" do
      {:ok, interval} = Tempo.from_iso8601("1985-01/P3M")
      list = Enum.to_list(interval)
      assert [_, _, _] = list
      assert Enum.map(list, & &1.time[:month]) == [1, 2, 3]
    end
  end

  describe "duration + to" do
    test "`P1M/1985-06` materialises to `[1985-05, 1985-06)`" do
      {:ok, interval} = Tempo.from_iso8601("P1M/1985-06")
      {:ok, %Tempo.Interval{from: from, to: to}} = Tempo.to_interval(interval)
      assert from.time == [year: 1985, month: 5]
      assert to.time == [year: 1985, month: 6]
    end

    test "Enum.to_list on duration+to walks the computed range" do
      {:ok, interval} = Tempo.from_iso8601("P3D/1985-01-10")
      list = Enum.to_list(interval)
      # 1985-01-10 minus P3D = 1985-01-07. Interval [1985-01-07, 1985-01-10) yields 3 days.
      assert Enum.map(list, & &1.time[:day]) == [7, 8, 9]
    end
  end
end
