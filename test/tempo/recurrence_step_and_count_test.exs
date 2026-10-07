defmodule Tempo.RecurrenceStepAndCountTest do
  @moduledoc """
  A recurrence whose step is no step, or whose count is no count.

  A recurrence is counted in occurrences, none or more, and each is a step
  of its cadence on from the one before. A rule read with `INTERVAL=0` gave
  its start again for each of its count, one with `INTERVAL=-1` was walked
  back to its cap, a count below none was handed back unconverted as
  success, `R3/2026-06-01/P0D` gave three intervals of no length, and a
  JSCalendar rule with a count of none was read as one with no count
  (`test/tempo/jscalendar_test.exs` has the JSCalendar rules).
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  defp starts({:ok, %IntervalSet{} = set}),
    do: Enum.map(IntervalSet.members(set), &Interval.from/1)

  defp starts(other), do: other

  describe "an RRULE" do
    test "that steps by nothing or backwards is refused where it is read" do
      for interval <- ["0", "-1", "-7"] do
        assert {interval,
                RRule.parse("FREQ=MONTHLY;INTERVAL=#{interval};COUNT=3", from: ~o"2026-06-01")} ==
                 {interval, {:error, {:invalid_interval, interval}}}
      end

      assert {:ok, %Interval{}} =
               RRule.parse("FREQ=MONTHLY;INTERVAL=2;COUNT=3", from: ~o"2026-06-01")
    end

    test "with a count below none is refused, and with a count of none has no occurrences" do
      assert RRule.parse("FREQ=DAILY;COUNT=-2", from: ~o"2026-06-01") ==
               {:error, {:invalid_count, "-2"}}

      {:ok, none} = RRule.parse("FREQ=DAILY;COUNT=0", from: ~o"2026-06-01")
      assert starts(Tempo.to_interval(none)) == []

      {:ok, three} = RRule.parse("FREQ=DAILY;COUNT=3", from: ~o"2026-06-01")
      assert starts(Tempo.to_interval(three)) == [~o"2026-06-01", ~o"2026-06-02", ~o"2026-06-03"]
    end
  end

  describe "a rule given as a struct" do
    test "steps by one or more, and is refused where it does not" do
      for interval <- [0, -1, 1.5, "2"] do
        rule = %Rule{freq: :day, interval: interval, count: 3}

        assert {interval, Expander.to_ast(rule, ~o"2026-06-01")} ==
                 {interval, {:error, {:invalid_interval, interval}}}

        assert {interval, Expander.expand(rule, ~o"2026-06-01")} ==
                 {interval, {:error, {:invalid_interval, interval}}}
      end

      # One that names no step steps by one.
      assert {:ok, %Interval{duration: %Tempo.Duration{time: [day: 1]}}} =
               Expander.to_ast(%Rule{freq: :day, interval: nil, count: 3}, ~o"2026-06-01")
    end

    test "has the occurrences it counts, none where its count is none, and no end with no count" do
      assert Expander.expand(%Rule{freq: :day, interval: 1, count: 0}, ~o"2026-06-01") ==
               {:ok, []}

      assert {:ok, [_one, _two]} =
               Expander.expand(%Rule{freq: :day, interval: 1, count: 2}, ~o"2026-06-01")

      assert Expander.to_ast(%Rule{freq: :day, interval: 1, count: -1}, ~o"2026-06-01") ==
               {:error, {:invalid_count, -1}}

      assert {:ok, %Interval{recurrence: :infinity}} =
               Expander.to_ast(%Rule{freq: :day, interval: 1, count: nil}, ~o"2026-06-01")
    end
  end

  describe "a recurrence written with a cadence of no length" do
    test "is refused where it is converted" do
      for text <- [
            "R3/2026-06-01/P0D",
            "R3/2026-06-01/PT0S",
            "R3/2026-06-01/P0M",
            "R3/2026-06-01T10/PT0H0M",
            "R3/2026-06-01/P0D/FL1KN",
            "R/2026-06-01/P0D"
          ] do
        assert {^text, {:error, %ConversionError{} = error}} =
                 {text, Tempo.to_interval(Tempo.from_iso8601!(text), within: ~o"2026-06")}

        assert Exception.message(error) =~ "is no length of time"
      end
    end

    test "has no occurrences where its count is none, and its occurrences where it steps" do
      assert starts(Tempo.to_interval(Tempo.from_iso8601!("R0/2026-06-01/P1D"))) == []

      assert starts(Tempo.to_interval(Tempo.from_iso8601!("R3/2026-06-01/P1D"))) ==
               [~o"2026-06-01", ~o"2026-06-02", ~o"2026-06-03"]
    end
  end

  describe "the count of a recurrence" do
    test "is a number of occurrences, none or more, or none at all" do
      for count <- [-1, -3, 1.5, "3", nil] do
        assert {^count, {:error, %ArgumentError{} = error}} =
                 {count, Interval.new(from: ~o"2026-06-01", duration: ~o"P1D", recurrence: count)}

        assert Exception.message(error) =~ ":recurrence"
      end

      for count <- [0, 1, 3, :infinity] do
        assert {^count, {:ok, %Interval{recurrence: ^count}}} =
                 {count, Interval.new(from: ~o"2026-06-01", duration: ~o"P1D", recurrence: count)}
      end
    end

    test "below none is refused where an interval built by hand is converted" do
      # It was handed back as it was given, as if it were one span.
      built = %Interval{from: ~o"2026-06-01", duration: ~o"P1D", recurrence: -3}

      assert {:error, %ConversionError{} = error} = Tempo.to_interval(built)
      assert Exception.message(error) =~ "none or more"
    end
  end
end
