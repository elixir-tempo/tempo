defmodule Tempo.UnanchoredRecurrenceTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.Operations
  alias Tempo.RRule
  alias Tempo.UnboundedRecurrenceError

  # `RRule.parse/2` without a `:from` anchor yields a recurrence
  # with no endpoints at all — `~o"R/../P1W/FL1KN"`, "every Monday"
  # beginning nowhere. It reached set algebra as a value that looked
  # ordinary and crashed several frames down, in code that could no
  # longer say why.
  #
  # Two sentinels spell "no endpoint": `:undefined` from the ISO 8601
  # parser and `nil` from the RRULE parser. Only the first was
  # recognised, so the second walked straight past the gate.

  setup do
    {:ok, unanchored} = RRule.parse("FREQ=WEEKLY;BYDAY=MO", [])
    {:ok, dtstart} = Tempo.from_iso8601("2026-06-01T09:00:00")
    {:ok, anchored} = RRule.parse("FREQ=WEEKLY;BYDAY=MO", from: dtstart)

    %{
      unanchored: unanchored,
      anchored: anchored,
      window: ~o"2026Y6M1D/7M1D"
    }
  end

  describe "to_interval/2" do
    test "a bound materialises an unanchored recurrence into its window", context do
      # "Every Monday" has no start of its own; the bound supplies one.
      # Materialising it into June 2026 yields that month's five Mondays,
      # and the half-open upper bound keeps the following Monday out.
      assert {:ok, %IntervalSet{} = set} =
               Tempo.to_interval(context.unanchored, bound: context.window)

      assert IntervalSet.count(set) == 5
      assert Interval.from(IntervalSet.first(set)) == ~o"2026Y6M1D"
    end

    test "a wider bound materialises more occurrences", context do
      # The same recurrence, a decade-wide window: the bound is the
      # extent to walk, so it materialises every Monday it spans.
      assert {:ok, %IntervalSet{} = set} =
               Tempo.to_interval(context.unanchored, bound: ~o"2020Y/2030Y")

      assert IntervalSet.count(set) > 500
    end

    test "with no bound there is still nothing to anchor against", context do
      # A bound is the window to materialise into. Without one, an
      # unanchored recurrence has neither a start nor a stop, so it stays
      # a clean refusal rather than an open-ended walk.
      assert {:error, %IntervalEndpointsError{} = error} =
               Tempo.to_interval(context.unanchored)

      assert error.reason == :unanchored
    end

    test "the bound may be given at any resolution — year, month or day" do
      # The ISO 8601 holiday form for the fourth Thursday of November.
      # Whatever the resolution of the bound that anchors it — the whole
      # year, that November, or Thanksgiving Day itself — it lands on the
      # same day. The bound says where to walk, not at what grain.
      {:ok, thanksgiving} = Tempo.from_iso8601("R/../P1Y/FL11M4K4IN")

      for bound <- [~o"2026", ~o"2026-11", ~o"2026-11-26"] do
        assert {:ok, %IntervalSet{} = set} = Tempo.to_interval(thanksgiving, bound: bound)
        assert Interval.from(IntervalSet.first(set)) == ~o"2026Y11M26D"
      end
    end

    test "an occurrence takes the resolution its selection names" do
      # A day selection spans a day, a month selection a whole month, a
      # week selection a whole week — the occurrence is at the grain the
      # selection names, not forced down to a day.
      {:ok, christmas} = Tempo.from_iso8601("R/../P1Y/FL12M25DN")
      {:ok, june} = Tempo.from_iso8601("R/../P1Y/FL6MN")
      {:ok, week10} = Tempo.from_iso8601("R/../P1Y/FL10WN")

      assert {:ok, day_set} = Tempo.to_interval(christmas, bound: ~o"2026")
      assert Interval.from(IntervalSet.first(day_set)) == ~o"2026Y12M25D"

      assert {:ok, month_set} = Tempo.to_interval(june, bound: ~o"2026")
      assert Interval.from(IntervalSet.first(month_set)) == ~o"2026Y6M"

      assert {:ok, week_set} = Tempo.to_interval(week10, bound: ~o"2026")
      assert Interval.from(IntervalSet.first(week_set)) == ~o"2026Y10W"
    end

    test "it returns the materialised set, never the rule itself", context do
      # A materialised recurrence is the set of its occurrences — never
      # the rule handed straight back as though it had been expanded.
      refute Tempo.to_interval(context.unanchored, bound: context.window) ==
               {:ok, context.unanchored}
    end

    test "an anchored recurrence still materialises", context do
      assert {:ok, %IntervalSet{} = set} =
               Tempo.to_interval(context.anchored, bound: context.window)

      assert IntervalSet.count(set) == 5
    end

    test "an ordinary interval is unaffected" do
      assert {:ok, ~o"2026Y6M1D/7M1D"} = Tempo.to_interval(~o"2026Y6M1D/7M1D")
    end
  end

  describe "set operations reject rather than crash" do
    test "intersection, in either argument order", context do
      assert {:error, %IntervalEndpointsError{}} =
               Tempo.intersection(context.unanchored, context.window)

      assert {:error, %IntervalEndpointsError{}} =
               Tempo.intersection(context.window, context.unanchored)
    end

    test "union and difference", context do
      assert {:error, %IntervalEndpointsError{}} =
               Tempo.union(context.unanchored, context.window)

      assert {:error, %IntervalEndpointsError{}} =
               Tempo.difference(context.window, context.unanchored)

      assert {:error, %IntervalEndpointsError{}} =
               Tempo.difference(context.unanchored, context.window)
    end

    test "it is the same kind of failure open-ended ISO intervals already gave", context do
      # `2020Y/..` and an unanchored recurrence are the same kind of
      # problem — an endpoint that is not there — so they raise the
      # same exception type rather than two unrelated ones. The
      # `operation` differs because they are caught at different
      # points: the recurrence cannot even be materialised, while the
      # open interval fails on entry to a set.
      assert {:error, %IntervalEndpointsError{}} =
               Tempo.intersection(~o"2020Y/..", ~o"2020Y/2025Y")

      assert {:error, %IntervalEndpointsError{}} =
               Tempo.intersection(context.unanchored, context.window)
    end

    test "an anchored but infinite recurrence gets its own diagnosis", context do
      # Anchored is not the same as bounded. An infinite recurrence
      # with a start still needs materialising against a bound before
      # set algebra, and Tempo already says so — the point here is
      # that the two cases stay distinguishable rather than collapsing
      # into one vague failure.
      assert {:error, %UnboundedRecurrenceError{}} =
               Tempo.intersection(context.anchored, context.window)
    end

    test "an anchored recurrence intersects once materialised", context do
      {:ok, materialised} = Tempo.to_interval(context.anchored, bound: context.window)

      assert {:ok, %IntervalSet{} = set} =
               Tempo.intersection(materialised, context.window)

      assert IntervalSet.count(set) > 0
    end
  end

  describe "IntervalSet construction" do
    test "an interval with a nil endpoint is not a member" do
      assert {:error, %IntervalEndpointsError{}} =
               IntervalSet.new([%Interval{from: nil, to: nil, recurrence: :infinity}])
    end

    test "an interval with an :undefined endpoint is still not a member" do
      assert {:error, %IntervalEndpointsError{}} = IntervalSet.new([~o"2020Y/.."])
    end

    test "a bounded interval still is" do
      assert {:ok, set} = IntervalSet.new([~o"2026Y6M1D/7M1D"])
      assert IntervalSet.count(set) == 1
    end
  end

  describe "endpoint transforms tolerate an unbounded endpoint" do
    # `Operations.align/3` is public, so a caller can hand it a
    # set built by hand that never passed IntervalSet.new/2's
    # validation. The endpoint transforms must not crash on one.
    test "align/3 does not raise on a hand-built unbounded set" do
      unbounded = %IntervalSet{
        intervals: [%Interval{from: nil, to: nil, recurrence: :infinity}]
      }

      bounded = %IntervalSet{intervals: [~o"2026Y6M1D/7M1D"]}

      assert {:ok, {_a, _b}} = Operations.align(unbounded, bounded)
      assert {:ok, {_a, _b}} = Operations.align(bounded, unbounded)
    end
  end
end
