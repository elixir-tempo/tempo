defmodule Tempo.ShiftTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Math

  describe "Tempo.shift/2" do
    test "mixed units apply largest-to-smallest" do
      assert Tempo.shift(~o"2026-06-15", month: 1, day: -5) == ~o"2026Y7M10D"
    end

    test "negative values move the Tempo backwards" do
      assert Tempo.shift(~o"2026-06-15", day: -10) == ~o"2026Y6M5D"
    end

    test "rolls a year boundary backwards" do
      assert Tempo.shift(~o"2026-01-05", day: -10) == ~o"2025Y12M26D"
    end

    test "clamps the day-of-month after month arithmetic" do
      # Jan 31 + 1 month in a non-leap year is Feb 28, not Feb 31.
      assert Tempo.shift(~o"2026-01-31", month: 1) == ~o"2026Y2M28D"
      # Leap year gives Feb 29.
      assert Tempo.shift(~o"2024-01-31", month: 1) == ~o"2024Y2M29D"
    end

    test "time-of-day shifts work" do
      assert Tempo.shift(~o"2026-06-15T10:00:00", hour: -3) ==
               ~o"2026Y6M15DT7H0M0S"

      assert Tempo.shift(~o"2026-06-15T10:00:00", minute: 45, second: 30) ==
               ~o"2026Y6M15DT10H45M30S"
    end

    test "week is normalised to days" do
      assert Tempo.shift(~o"2026-06-15", week: 2) == ~o"2026Y6M29D"
    end

    test "empty keyword list is a no-op" do
      assert Tempo.shift(~o"2026-06-15", []) == ~o"2026Y6M15D"
    end
  end

  describe "Tempo.shift/2 with a duration value" do
    test "accepts a Tempo.Duration directly" do
      assert Tempo.shift(~o"2026", ~o"P2Y") == ~o"2028Y"
      assert Tempo.shift(~o"2026-06-15", ~o"P1M") == ~o"2026Y7M15D"
    end

    test "agrees with the keyword-list form and with Tempo.Math.add/2" do
      assert Tempo.shift(~o"2026-06-15", ~o"P1M") == Tempo.shift(~o"2026-06-15", month: 1)
      assert Tempo.shift(~o"2026-06-15", ~o"P1M") == Math.add(~o"2026-06-15", ~o"P1M")
    end

    test "month-end clamping applies the same as the keyword form" do
      assert Tempo.shift(~o"2026-01-31", ~o"P1M") == ~o"2026Y2M28D"
    end
  end

  describe "Tempo.shift/2 on un-anchored values (no :year)" do
    # A value with no year lives on a repeating month/day axis. Cases
    # the calendar can resolve without a year are computed; cases that
    # depend on the missing year return {:error, %RequiresAnchorError{}}
    # — never a raise.

    test "day arithmetic that stays within a month is computed" do
      assert Tempo.shift(~o"2M15D", ~o"P1D") == ~o"2M16D"
      assert Tempo.shift(~o"2M15D", day: -1) == ~o"2M14D"
    end

    test "a month-crossing carry into a fixed-length month is computed" do
      assert Tempo.shift(~o"1M31D", ~o"P1D") == ~o"2M1D"
      assert Tempo.shift(~o"2M1D", day: -1) == ~o"1M31D"
    end

    test "a year-boundary carry wraps the month (the year is immaterial)" do
      assert Tempo.shift(~o"12M31D", ~o"P1D") == ~o"1M1D"
      assert Tempo.shift(~o"1M1D", day: -1) == ~o"12M31D"
    end

    test "arithmetic that depends on the missing year returns an error, not a raise" do
      assert {:error, %Tempo.RequiresAnchorError{}} = Tempo.shift(~o"1M31D", ~o"P1M")
      assert {:error, %Tempo.RequiresAnchorError{}} = Tempo.shift(~o"2M28D", ~o"P1D")
      assert {:error, %Tempo.RequiresAnchorError{}} = Tempo.shift(~o"3M1D", day: -1)
    end

    test "a whole-year step is a no-op — the untracked year moves, the date does not" do
      assert Tempo.shift(~o"1M31D", ~o"P1Y") == ~o"1M31D"
      assert Tempo.shift(~o"6M15D", year: -1) == ~o"6M15D"
    end

    test "a year step on Feb 29 needs an anchor — next year may not be a leap year" do
      assert {:error, %Tempo.RequiresAnchorError{}} = Tempo.shift(~o"2M29D", ~o"P1Y")
    end

    test "a month step that keeps a valid day is computed, and wraps the year" do
      assert Tempo.shift(~o"1M15D", ~o"P1M") == ~o"2M15D"
      assert Tempo.shift(~o"3M31D", ~o"P1M") == ~o"4M30D"
      assert Tempo.shift(~o"12M31D", ~o"P1M") == ~o"1M31D"
      assert Tempo.shift(~o"1M15D", month: -1) == ~o"12M15D"
    end

    test "a time step never spuriously requires an anchor for an ambiguous day" do
      # `2M29D` sits on an ambiguous day, but a time shift doesn't touch it.
      assert Tempo.shift(~o"2M29D", ~o"PT1H") == ~o"2M29DT1H"
    end

    test "a fractional week counts whole days, truncated" do
      assert Tempo.shift(~o"2026-01-01", ~o"P1.5W") == ~o"2026-01-11"
    end

    test "a month-only value carries a month/year step and extends for finer steps" do
      assert Tempo.shift(~o"3M", ~o"P1M") == ~o"4M"
      assert Tempo.shift(~o"3M", ~o"P1Y") == ~o"3M"
      assert Tempo.shift(~o"3M", ~o"P1D") == ~o"3M2D"
      assert Tempo.shift(~o"3M", ~o"P1W") == ~o"3M8D"
    end

    test "a day-only value advances while every month has that day, else errors" do
      assert Tempo.shift(~o"15D", ~o"P1D") == ~o"16D"
      assert Tempo.shift(~o"15D", ~o"P1W") == ~o"22D"
      assert Tempo.shift(~o"27D", ~o"P1D") == ~o"28D"
      assert Tempo.shift(~o"15D", day: -1) == ~o"14D"
      # A month/year step leaves a bare day untouched.
      assert Tempo.shift(~o"15D", ~o"P1M") == ~o"15D"
      # The 29th isn't in every month, and the 1st's predecessor is unknown.
      assert {:error, %Tempo.RequiresAnchorError{}} = Tempo.shift(~o"28D", ~o"P1D")
      assert {:error, %Tempo.RequiresAnchorError{}} = Tempo.shift(~o"1D", day: -1)
    end
  end
end
