defmodule Tempo.Interval.LeapSecondTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Interval

  # Parse-time rejection of `:60` puts Tempo in sync with Elixir
  # stdlib. Leap-second information is preserved at the interval
  # level so scientific / financial workflows that need exact
  # elapsed time can still account for them.

  describe "spans_leap_second?/1 — boundary cases" do
    # The leap second 23:59:60Z is conceptually *between* 23:59:59
    # of day X and 00:00:00 of day X+1. A half-open interval
    # `[from, to)` contains the leap second iff `from` is at or
    # before 23:59:59Z of day X AND `to` is strictly after that
    # same 23:59:59Z position.

    test "exactly [23:59:59Z, next 00:00:00Z) spans the leap second" do
      iv = %Interval{
        from: ~o"2016-12-31T23:59:59Z",
        to: ~o"2017-01-01T00:00:00Z"
      }

      assert Interval.spans_leap_second?(iv),
             "the canonical single-second interval bracketing a leap must span it"
    end

    test "[23:00:00Z, 23:59:59Z) — ending exactly at the leap boundary — does NOT span" do
      iv = %Interval{
        from: ~o"2016-12-31T23:00:00Z",
        to: ~o"2016-12-31T23:59:59Z"
      }

      refute Interval.spans_leap_second?(iv)
    end

    test "[next 00:00:00Z, later) does NOT span (interval wholly after the leap)" do
      iv = %Interval{
        from: ~o"2017-01-01T00:00:00Z",
        to: ~o"2017-01-01T00:01:00Z"
      }

      refute Interval.spans_leap_second?(iv)
    end
  end

  describe "spans_leap_second?/1" do
    test "interval containing 2016-12-31 23:59:60Z returns true" do
      iv = %Interval{
        from: ~o"2016-12-31T23:00:00Z",
        to: ~o"2017-01-01T01:00:00Z"
      }

      assert Interval.spans_leap_second?(iv)
    end

    test "interval wholly after the leap second returns false" do
      iv = %Interval{from: ~o"2017-01-01T01:00:00Z", to: ~o"2017-01-02T00:00:00Z"}
      refute Interval.spans_leap_second?(iv)
    end

    test "interval wholly before the leap second returns false" do
      iv = %Interval{from: ~o"2016-12-31T12:00:00Z", to: ~o"2016-12-31T23:00:00Z"}
      refute Interval.spans_leap_second?(iv)
    end

    test "interval spanning multiple leap seconds returns true" do
      iv = %Interval{from: ~o"2015-01-01T00:00:00Z", to: ~o"2017-12-31T00:00:00Z"}
      assert Interval.spans_leap_second?(iv)
    end

    test "modern interval with no leap seconds (post-2016) returns false" do
      iv = %Interval{from: ~o"2024-06-15T00:00:00Z", to: ~o"2024-06-16T00:00:00Z"}
      refute Interval.spans_leap_second?(iv)
    end

    test "unbounded interval returns false" do
      iv = %Interval{from: :undefined, to: ~o"2017-01-01T00:00:00Z"}
      refute Interval.spans_leap_second?(iv)
    end
  end

  describe "leap_seconds_spanned/1" do
    test "empty list when no leap seconds fall inside" do
      iv = %Interval{from: ~o"2024-06-15", to: ~o"2024-06-16"}
      assert Interval.leap_seconds_spanned(iv) == []
    end

    test "single leap second returns one entry" do
      iv = %Interval{
        from: ~o"2016-12-31T00:00:00Z",
        to: ~o"2017-01-01T12:00:00Z"
      }

      assert Interval.leap_seconds_spanned(iv) == [{2016, 12, 31}]
    end

    test "multi-year span lists all leap seconds in sort order" do
      iv = %Interval{from: ~o"2015-01-01", to: ~o"2017-12-31"}
      assert Interval.leap_seconds_spanned(iv) == [{2015, 6, 30}, {2016, 12, 31}]
    end

    test "unbounded interval returns empty list" do
      iv = %Interval{from: ~o"2015-01-01", to: :undefined}
      assert Interval.leap_seconds_spanned(iv) == []
    end
  end

  describe "duration/2 with leap_seconds: true" do
    test "120s becomes 121s when the interval spans a leap second" do
      iv = %Interval{
        from: ~o"2016-12-31T23:59:00Z",
        to: ~o"2017-01-01T00:01:00Z"
      }

      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 120]}

      assert Interval.duration(iv, leap_seconds: true) ==
               %Tempo.Duration{time: [second: 121]}
    end

    test "no adjustment when the interval contains no leap seconds" do
      iv = %Interval{from: ~o"2024-06-15", to: ~o"2024-06-16"}

      assert Interval.duration(iv) == Interval.duration(iv, leap_seconds: true)
    end

    test "multi-year span adds one second per leap second" do
      # 2015-06-30 and 2016-12-31 both fall inside this span.
      iv = %Interval{from: ~o"2015-01-01", to: ~o"2017-12-31"}

      base = Interval.duration(iv)
      with_leap = Interval.duration(iv, leap_seconds: true)

      assert base == ~o"P1095D"
      assert with_leap == ~o"P1095DT2S"
    end

    test "unbounded interval still returns :infinity" do
      iv = %Interval{from: ~o"2015-01-01", to: :undefined}
      assert Interval.duration(iv, leap_seconds: true) == :infinity
    end
  end
end
