defmodule Tempo.ValueSpansTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  # A value is the span it names, so what reads an interval's length or ends
  # reads a value's too, and a set's length is the time it covers.

  describe "duration/1" do
    test "measures the span a value names" do
      assert Tempo.duration(~o"2026-06") == ~o"P1M"
      assert Tempo.duration(~o"2026-06-15") == ~o"P1D"
      assert Tempo.duration(~o"2026-06-15/2026-06-18") == ~o"P3D"
    end

    test "is an error, not a raise, for what has no length to measure" do
      assert {:error, %Tempo.UnanchoredError{operation: :duration}} = Tempo.duration(~o"T09")
      assert {:error, %Tempo.UnanchoredError{operation: :duration}} = Tempo.duration(~o"T09/T17")
      assert {:error, %Tempo.UnanchoredError{operation: :duration}} = Tempo.duration(~o"6M/8M")

      assert {:error, %Tempo.ConversionError{reason: :recurring_duration}} =
               Tempo.duration(~o"R3/2026-06-15/P1D")

      for value <- [nil, "", :"", 42, "2026-06"] do
        assert {:error, %ArgumentError{}} = Tempo.duration(value)
      end
    end
  end

  describe "the duration predicates" do
    test "measure an interval set by the time it covers" do
      {:ok, weekends} = Tempo.select(~o"2026-06", Tempo.weekends(:AU))

      assert Tempo.exactly?(weekends, ~o"P8D")
      assert Tempo.at_least?(weekends, ~o"P8D")
      assert Tempo.at_most?(weekends, ~o"P8D")
      assert Tempo.longer_than?(weekends, ~o"P7D")
      assert Tempo.shorter_than?(weekends, ~o"P9D")

      # A month is compared from the set's first day: 6 June to 6 July.
      assert Tempo.shorter_than?(weekends, ~o"P1M")
    end

    test "measure the span a value names" do
      assert Tempo.exactly?(~o"2026-02", ~o"P28D")
      assert Tempo.longer_than?(~o"2024-02", ~o"P28D")
      assert Tempo.at_least?(~o"2026-06", ~o"P1M")
    end

    test "an empty set has no length, and an unbounded one outlasts any" do
      {:ok, empty} = IntervalSet.new([])

      assert Tempo.exactly?(empty, ~o"PT0S")
      assert Tempo.shorter_than?(empty, ~o"P1D")
      assert Tempo.shorter_than?(empty, ~o"P1M")
      refute Tempo.at_least?(empty, ~o"P1D")

      {:ok, weekends} = Tempo.select(~o"2026-06-15/..", Tempo.weekends(:AU))

      assert Tempo.longer_than?(weekends, ~o"P100Y")
      refute Tempo.at_most?(weekends, ~o"P100Y")
    end

    test "an interval is measured between its endpoints, as before" do
      meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"

      assert Tempo.at_least?(meeting, ~o"PT1H")
      refute Tempo.at_least?(meeting, ~o"PT2H")
      assert Tempo.exactly?(meeting, ~o"PT90M")
    end
  end

  describe "Interval.from/1 and to/1 on a value" do
    test "read the span the value names" do
      assert Interval.from(~o"2026-06") == ~o"2026Y6M"
      assert Interval.to(~o"2026-06") == ~o"2026Y7M"
      assert Interval.to(~o"2027-04-09") == ~o"2027Y4M10D"
      assert Interval.to(~o"2026-06-15T10:30") == ~o"2026Y6M15DT10H31M"
      assert Interval.to(~o"4M9D") == ~o"4M10D"
    end

    test "are an error for a value naming no single span" do
      assert {:error, %Tempo.UnanchoredError{}} = Interval.to(~o"2M28D")
      assert {:error, %ArgumentError{}} = Interval.to(~o"{2026,2027}Y")
    end
  end

  describe "Interval.new/1's :through" do
    test "ends the interval where the last value's span ends" do
      assert Interval.new(from: ~o"2027-01-28", through: ~o"2027-04-09") ==
               {:ok, ~o"2027Y1M28D/4M10D"}

      assert Interval.new(from: ~o"2027-01", through: ~o"2027-03") == {:ok, ~o"2027Y1M/4M"}

      assert Interval.new(from: ~o"2027-01-28", through: ~o"2027-04-05/2027-04-10") ==
               {:ok, ~o"2027Y1M28D/4M10D"}

      assert Interval.new(through: ~o"2027-04-09") == {:ok, ~o"../2027Y4M10D"}
    end

    test "is one of the ways to close an interval, not an addition to another" do
      assert {:error, %ArgumentError{}} =
               Interval.new(from: ~o"2027-01-28", through: ~o"2027-04-09", to: ~o"2027-04-10")

      assert {:error, %ArgumentError{}} =
               Interval.new(from: ~o"2027-01-28", through: ~o"2027-04-09", duration: ~o"P1D")

      assert {:error, %ArgumentError{}} =
               Interval.new(from: ~o"2027-01-28", through: "2027-04-09")

      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Interval.new(from: ~o"2027-04-28", through: ~o"2027-04-09")
    end
  end
end
