defmodule Tempo.Interval.CycleTest do
  @moduledoc """
  A span with no year lies on a cycle, and one whose end is not after its
  start runs through the cycle's end. Every operation reads it so.
  """

  use ExUnit.Case, async: true

  # Doctests evaluate the expected output as code; `~o"…"` requires
  # `sigil_o` to be in scope.
  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.Interval.Cycle
  alias Tempo.IntervalSet

  doctest Tempo.Interval.Cycle

  describe "parts/1" do
    test "a span that ends where its cycle does is one part, up to the cycle's end" do
      {:ok, last_hour} = Tempo.to_interval(~o"T23H")

      assert {:ok, [part]} = Cycle.parts(last_hour)
      assert {Tempo.hour(part.from), Tempo.hour(part.to)} == {23, 24}
    end

    test "the cycle is the year for a month, and the week for a day of the week" do
      {:ok, [december]} = Cycle.parts(Tempo.to_interval!(~o"12M"))
      {:ok, [sunday]} = Cycle.parts(Tempo.to_interval!(~o"7K"))

      assert december.to.time == [month: 13]
      assert sunday.to.time == [day_of_week: 8]
    end

    test "an unspecified year is no year" do
      {:ok, [new_years_eve]} = Cycle.parts(Tempo.to_interval!(~o"X*Y12M31D"))

      assert new_years_eve.to.time == [year: :any, month: 13, day: 1]
    end

    test "a span with a year is its one part, whatever its ends" do
      inverted = %Interval{from: ~o"2026-06-20", to: ~o"2026-06-15"}

      assert Cycle.parts(inverted) == {:ok, [inverted]}
      refute Cycle.cyclic?(inverted)
    end

    test "a bare day has no cycle of one length to be cut at" do
      crossing = %Interval{from: ~o"28D", to: ~o"3D"}

      assert {:error, %Tempo.UnanchoredError{}} = Cycle.parts(crossing)
    end
  end

  describe "wrapped/1 and joined/1" do
    test "a part that ends at the cycle's end is written as the span it came from" do
      for text <- ["T23H", "12M", "12M31D", "7K"] do
        {:ok, span} = Tempo.to_interval(Tempo.from_iso8601!(text))
        {:ok, [part]} = Cycle.parts(span)

        assert Cycle.wrapped(part) == span
      end
    end

    test "the two parts of a span that runs through the cycle's end are joined" do
      {:ok, parts} = Cycle.parts(~o"12M/2M")

      assert parts |> Enum.reverse() |> Cycle.joined() == [~o"12M/2M"]
    end
  end

  # Each of these read the end of such a span as before its start.
  describe "what reads a span with no year" do
    test "it is not empty" do
      refute Tempo.empty?(~o"T23H")
      refute Tempo.empty?(~o"T22H/T2H")
      refute Tempo.empty?(~o"12M")
      refute Tempo.empty?(~o"7K")
    end

    test "its relation is that of the span up to the cycle's end" do
      assert Tempo.relation(~o"T23H", ~o"T23:30") == :contains
      assert Tempo.relation(~o"12M", ~o"12M31D") == :finished_by
      assert Tempo.relation(~o"7K", ~o"7K") == :equals
      refute Tempo.before?(~o"7K", ~o"7K")
    end

    test "one that runs past the cycle's end has no one relation, and the set operations answer" do
      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.relation(~o"T22H/T2H", ~o"T23H")
      assert Tempo.overlaps?(~o"T22H/T2H", ~o"T1H")
      refute Tempo.overlaps?(~o"T22H/T2H", ~o"T12H")
    end

    test "its length is measured round the clock" do
      assert Tempo.at_least?(~o"T23H", ~o"PT30M")
      refute Tempo.at_least?(~o"T23H", ~o"PT2H")
      assert Tempo.exactly?(~o"T22H/T2H", ~o"PT4H")
      assert Tempo.longer_than?(~o"7K", ~o"PT1H")
    end

    test "a day, a month or a year is longer than any time of day" do
      refute Tempo.at_least?(~o"T10H", ~o"P1D")
      assert Tempo.at_most?(~o"T10H", ~o"P1D")
      assert Tempo.shorter_than?(~o"T10H", ~o"P1M")
    end

    test "a span of months has the length of a year it has not got" do
      assert_raise Tempo.UnanchoredError, fn -> Tempo.at_least?(~o"12M", ~o"P1D") end
    end

    test "coalescing keeps the last hour, and joins a span through the cycle's end" do
      {:ok, late} = Tempo.to_interval_set(~o"T{22,23}H")
      [evening] = late |> IntervalSet.coalesce() |> IntervalSet.members()

      assert {Tempo.hour(evening.from), Tempo.hour(evening.to)} == {22, 0}

      night = IntervalSet.new!([~o"T22H/T2H", ~o"T1H/T3H"])

      assert night |> IntervalSet.coalesce() |> IntervalSet.members() == [~o"T22H/T3H"]
    end

    test "Interval.new/2 takes what the parser reads, and with a year refuses what has no extent" do
      assert Interval.new(~o"T23H", ~o"T1H") == {:ok, ~o"T23H/T1H"}
      assert Interval.new(~o"T10H", ~o"T10H") == {:ok, ~o"T10H/T10H"}

      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Interval.new(~o"2026-06-16", ~o"2026-06-15")

      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Interval.new(~o"2026-06-15", ~o"2026-06-15")
    end
  end

  # The user's decision of 2026-10-03: with no year a span lies on a cycle,
  # so one that ends where it starts is once round it.
  describe "a span that ends where it starts is a whole turn" do
    test "it is not empty, and is as long as its cycle" do
      refute Tempo.empty?(~o"T10H/T10H")
      refute Tempo.empty?(~o"T0H/T0H")
      refute Tempo.empty?(~o"12-01/12-01")

      assert Tempo.exactly?(~o"T10H/T10H", ~o"PT24H")
      assert Cycle.microseconds(~o"1K/1K") == {:ok, 7 * 86_400_000_000}
    end

    test "with a year it is still empty" do
      assert Tempo.empty?(~o"2026-06-15/2026-06-15")
    end

    test "it is walked once round, from its start" do
      assert Enum.count(~o"T0H/T0H") == 24
      assert Enum.count(~o"T10H30M/T10H30M") == 1440
      assert Enum.count(~o"1K/1K") == 7

      assert ~o"T22H/T22H" |> Enum.map(&Tempo.hour/1) |> Enum.take(4) == [22, 23, 0, 1]
      assert Enum.member?(~o"T10H/T10H", ~o"T5H")
    end

    test "it is one part when it starts with its cycle, and otherwise two" do
      assert {:ok, [day]} = Cycle.parts(~o"T0H/T0H")
      assert Cycle.wrapped(day) == ~o"T0H/T0H"

      assert {:ok, [first, second]} = Cycle.parts(~o"T10H/T10H")
      assert {Tempo.hour(first.from), Tempo.hour(second.to)} == {10, 10}
    end

    test "the set operations and the relations read it so" do
      assert Tempo.relation(~o"T0H/T0H", ~o"T10H") == :contains
      assert Tempo.overlaps?(~o"T10H/T10H", ~o"T3H")

      assert {:ok, free} = Tempo.difference(~o"T0H/T0H", ~o"T10H/T12H")
      assert IntervalSet.members(free) == [~o"T0H/T10H", ~o"T12H/T0H"]
    end

    test "coalesce/1 writes a set that covers the cycle as it" do
      halves = IntervalSet.new!([~o"T0H/T12H", ~o"T12H/T0H"])

      assert halves |> IntervalSet.coalesce() |> IntervalSet.members() == [~o"T0H/T0H"]
    end
  end

  describe "the set operations" do
    test "write a span that ends where its cycle does as to_interval/2 writes it" do
      {:ok, both} = Tempo.union(~o"T23H", ~o"T10H")
      {:ok, last_hour} = Tempo.to_interval(~o"T23H")

      assert List.last(IntervalSet.members(both)) == last_hour
    end

    test "cut a span of months and days at the turn of the year" do
      {:ok, both} = Tempo.union(~o"12M31D", ~o"12M25D")
      {:ok, shared} = Tempo.intersection(~o"12M", ~o"12M31D")

      assert Enum.map(IntervalSet.members(both), &Tempo.day(&1.from)) == [25, 31]
      assert [~o"12M31D/1M1D"] = IntervalSet.members(shared)
    end

    test "cut a span that runs through midnight in two" do
      {:ok, rest} = Tempo.difference(~o"T22H/T2H", ~o"T23H")

      assert IntervalSet.members(rest) == [~o"T0H/T2H", ~o"T22H/T23H"]
    end
  end
end
