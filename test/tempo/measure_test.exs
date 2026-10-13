defmodule Tempo.MeasureTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.IntervalSet

  # Lengths: durations covered, durations between, the length predicates
  # and slots (`plans/architecture-redesign.md`, section 17).

  describe "duration/1" do
    test "a value is one unit of its resolution" do
      assert Tempo.duration(~o"2026") == ~o"P1Y"
      assert Tempo.duration(~o"6M") == ~o"P1M"
      assert Tempo.duration(~o"2026-W25") == ~o"P1W"
      assert Tempo.duration(~o"2026Y2G3MU") == ~o"P3M"
      assert Tempo.duration(~o"2026-06-15T10:30:45.5") == ~o"PT0.1S"
    end

    test "a span is measured between its ends in their finer unit" do
      assert Tempo.duration(~o"2026-01/2026-03") == ~o"P3M"
      assert Tempo.duration(~o"2026-06-15/2026-06-20") == ~o"P6D"
      assert Tempo.duration(~o"T22/T02") == ~o"PT4H"
      assert Tempo.duration(~o"2026-03-29T00/2026-03-30T00[Europe/Paris]") == ~o"PT23H"
    end

    test "a set, a recurrence or a plural value is the time it covers once" do
      assert Tempo.duration(~o"2026Y6MXD") == ~o"P9D"
      assert Tempo.duration(~o"{2026-01,2026-03}") == ~o"P2M"
      assert Tempo.duration(~o"R3/2026-06-01/P1D") == ~o"P3D"
      assert Tempo.duration(~o"2026Y{1..-1}M15DT10HZ") == ~o"PT12H"
    end

    test "an open end and a recurrence with none are infinite" do
      assert Tempo.duration(~o"2026-01-15/..") == :infinity
      assert Tempo.duration(~o"R/2026-06-01/P1D") == :infinity
    end

    test "a span of dates with no year has no length" do
      assert {:error, %ConversionError{reason: :needs_a_year}} = Tempo.duration(~o"6M15D/7M20D")
      assert {:error, %ConversionError{reason: :bare_duration}} = Tempo.duration(~o"P1D")
    end
  end

  describe "duration/2" do
    test "measures start to start" do
      assert Tempo.duration(~o"2026-09-28", ~o"2026-11-03") == {:ok, ~o"P36D"}
      assert Tempo.duration(~o"2026-09-28T10", ~o"2026-09-29") == {:ok, ~o"PT14H"}
    end

    test "wants its ends in order and on one frame" do
      assert {:error, %Tempo.IntervalEndpointsError{reason: :order}} =
               Tempo.duration(~o"2026-11-03", ~o"2026-09-28")

      assert {:error, %Tempo.FrameError{}} = Tempo.duration(~o"2026-09-28", ~o"2026-11-03T10Z")
    end
  end

  describe "the length predicates" do
    @meeting ~o"2026-06-15T09:00/2026-06-15T10:30"

    test "compare the covered time with the duration laid from the start" do
      assert Tempo.at_least?(@meeting, ~o"PT1H")
      refute Tempo.at_least?(@meeting, ~o"PT2H")
      assert Tempo.at_most?(@meeting, ~o"PT2H")
      assert Tempo.exactly?(@meeting, ~o"PT90M")
      assert Tempo.longer_than?(@meeting, ~o"PT1H")
      refute Tempo.longer_than?(@meeting, ~o"PT90M")
      assert Tempo.shorter_than?(@meeting, ~o"PT2H")
    end

    test "a month is as long as the month it starts in" do
      refute Tempo.shorter_than?(~o"2026-02", ~o"P1M")
      assert Tempo.exactly?(~o"2026-02", ~o"P1M")
      assert Tempo.shorter_than?(~o"2026-02", ~o"P30D")
    end

    test "an open end is longer than any duration" do
      assert Tempo.at_least?(~o"2026-01-15/..", ~o"P1Y")
      refute Tempo.shorter_than?(~o"2026-01-15/..", ~o"P1Y")
    end

    test "a value with no year is measured by an exact duration" do
      assert Tempo.at_least?(~o"6M", ~o"P1D")
      assert Tempo.at_least?(~o"2026Y6MXD", ~o"P1W")
    end
  end

  describe "IntervalSet.slots/3" do
    test "cuts a span into slots that fit" do
      {:ok, slots} = IntervalSet.slots(~o"2026-06-15T09:00/2026-06-15T12:00", ~o"PT1H")

      assert slots ==
               ~o"{2026-06-15T09:00/2026-06-15T10:00,2026-06-15T10:00/2026-06-15T11:00,2026-06-15T11:00/2026-06-15T12:00}"
    end

    test "spaces slots by :every" do
      {:ok, slots} =
        IntervalSet.slots(~o"2026-06-15T09:00/2026-06-15T12:00", ~o"PT1H", every: ~o"PT30M")

      assert IntervalSet.count(slots) == 5
    end

    test "writes a date's slots at the duration's resolution" do
      assert IntervalSet.slots(~o"2026-06-01/2026-06-10", ~o"P3D") ==
               {:ok, ~o"{2026-06-01/2026-06-03,2026-06-04/2026-06-06,2026-06-07/2026-06-09}"}

      {:ok, quarters} = IntervalSet.slots(~o"2026-06-15", ~o"PT6H")
      assert IntervalSet.count(quarters) == 4
    end

    test "keeps the members distinct and wants an exact duration" do
      {:ok, slots} =
        IntervalSet.slots(~o"{2026-06-15T09/2026-06-15T11,2026-06-16T09/2026-06-16T10}", ~o"PT1H")

      assert IntervalSet.count(slots) == 3

      assert {:error, %ArgumentError{}} =
               IntervalSet.slots(~o"2026-06-15T09:00/2026-06-15T12:00", ~o"P1M")
    end
  end

  describe "fractions of a second" do
    test "a length between two fractions is seconds and their fraction" do
      assert Tempo.duration(~o"2024-06-15T12:00:00.1", ~o"2024-06-15T12:00:00.9") ==
               {:ok, ~o"PT0.8S"}

      assert Tempo.duration(~o"2024-06-15T12:00:00.1", ~o"2024-06-15T12:00:02.9") ==
               {:ok, ~o"PT2.8S"}

      assert Tempo.duration(~o"2024-06-15T12:00:00.25/2024-06-15T12:00:01.75") == ~o"PT1.50S"
    end

    test "a fraction carries into its second, and is written with one sign" do
      assert Duration.multiply(~o"PT0.5S", 3) == ~o"PT1.5S"
      assert Duration.add(~o"PT0.7S", ~o"PT0.6S") == ~o"PT1.3S"
      assert inspect(Duration.negate(~o"PT1.5S")) == ~s(~o"PT-1.5S")
      assert Tempo.from_iso8601("PT-1.5S") == {:ok, Duration.negate(~o"PT1.5S")}
    end

    test "a fraction of another unit is written as it is read" do
      for text <- ["PT1.5H", "PT-1.5H", "P-0.5D", "P0.25Y"] do
        {:ok, duration} = Tempo.from_iso8601(text)
        assert Tempo.to_iso8601(duration) == {:ok, text}
      end
    end

    test "the alternative format is read, by month and by day of the year" do
      assert Tempo.from_iso8601("P0002-01-10T22:33:55") == {:ok, ~o"P2Y1M10DT22H33M55S"}
      assert Tempo.from_iso8601("P00020110T223355") == {:ok, ~o"P2Y1M10DT22H33M55S"}
      assert Tempo.from_iso8601("P0002-178T22:33:55") == {:ok, ~o"P2Y178DT22H33M55S"}
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("P0002-01-10")
    end

    test "a microsecond is given with its precision" do
      assert {:error, %ArgumentError{}} = Duration.new(second: 1, microsecond: 500_000)
      assert Duration.new(second: 1, microsecond: {500_000, 1}) == {:ok, ~o"PT1.5S"}
    end
  end
end
