defmodule Tempo.RRule.SelectionTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.ICal
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule
  alias Tempo.RRule.Selection

  # These tests exercise the Phase B pipeline:
  #
  #   parser / adapter
  #       │
  #       ▼
  #   %Tempo.Interval{repeat_rule: %Tempo{time: [selection: [...]]}}
  #       │
  #       ▼
  #   Tempo.to_interval/2 → iterate_recurrence/7 → Tempo.RRule.Selection.apply/3
  #       │
  #       ▼
  #   list of expanded / limited %Tempo.Interval{} occurrences
  #
  # Each BY-rule has its own describe block. As Phase B sub-phases
  # land, this file grows. BYSETPOS lives in its own describe
  # block (Phase C).

  describe "apply/3 — passthrough" do
    test "nil repeat_rule returns [candidate] unchanged" do
      candidate = %Tempo.Interval{from: ~o"2022-06-15"}
      assert Selection.apply(candidate, nil, :day) == [candidate]
    end

    test "empty selection returns [candidate] unchanged" do
      candidate = %Tempo.Interval{from: ~o"2022-06-15"}
      rule = %Tempo{time: [selection: []], calendar: Calendrical.Gregorian}
      assert Selection.apply(candidate, rule, :day) == [candidate]
    end

    test "unrecognised selection token passes through" do
      # Future-proofing: tokens that Phase B hasn't implemented
      # yet must not reject their candidates — they pass through
      # unchanged so the first-cut behaviour is "no-op until
      # implemented."
      candidate = %Tempo.Interval{from: ~o"2022-06-15"}
      rule = %Tempo{time: [selection: [bogus: 42]], calendar: Calendrical.Gregorian}
      assert Selection.apply(candidate, rule, :day) == [candidate]
    end
  end

  describe "BYMONTH — always a LIMIT" do
    test "single month: keeps matching candidate" do
      candidate = %Tempo.Interval{from: ~o"2022-06-15"}
      rule = %Tempo{time: [selection: [month: 6]], calendar: Calendrical.Gregorian}
      assert Selection.apply(candidate, rule, :month) == [candidate]
    end

    test "single month: drops non-matching candidate" do
      candidate = %Tempo.Interval{from: ~o"2022-07-15"}
      rule = %Tempo{time: [selection: [month: 6]], calendar: Calendrical.Gregorian}
      assert Selection.apply(candidate, rule, :month) == []
    end

    test "list of months: keeps candidate whose month is in the list" do
      candidate = %Tempo.Interval{from: ~o"2022-08-15"}
      rule = %Tempo{time: [selection: [month: [6, 7, 8]]], calendar: Calendrical.Gregorian}
      assert Selection.apply(candidate, rule, :month) == [candidate]
    end

    test "list of months: drops candidate whose month is outside the list" do
      candidate = %Tempo.Interval{from: ~o"2022-12-15"}
      rule = %Tempo{time: [selection: [month: [6, 7, 8]]], calendar: Calendrical.Gregorian}
      assert Selection.apply(candidate, rule, :month) == []
    end
  end

  describe "end-to-end — BYMONTH through Expander.expand/3" do
    test "FREQ=MONTHLY;BYMONTH=6,7,8 produces only summer months" do
      rule = %Rule{freq: :month, interval: 1, bymonth: [6, 7, 8]}

      {:ok, occurrences} =
        Expander.expand(rule, ~o"2022-06-15", bound: ~o"2023-12-31")

      months = Enum.map(occurrences, & &1.from.time[:month])
      assert months == [6, 7, 8, 6, 7, 8]
    end

    test "FREQ=YEARLY;BYMONTH=6 with COUNT yields N June occurrences" do
      rule = %Rule{freq: :year, interval: 1, bymonth: [6], count: 3}
      {:ok, occurrences} = Expander.expand(rule, ~o"2022-06-15")

      years = Enum.map(occurrences, & &1.from.time[:year])
      assert years == [2022, 2023, 2024]

      assert Enum.all?(occurrences, fn iv -> iv.from.time[:month] == 6 end)
    end

    test "COUNT counts occurrences AFTER filtering, per RFC 5545" do
      # FREQ=MONTHLY advances one month per iteration; BYMONTH=6
      # rejects every non-June candidate. COUNT=2 means "the
      # first 2 survivors," not "the first 2 iterations."
      rule = %Rule{freq: :month, interval: 1, bymonth: [6], count: 2}
      {:ok, occurrences} = Expander.expand(rule, ~o"2022-06-15")

      assert Enum.map(occurrences, fn iv -> {iv.from.time[:year], iv.from.time[:month]} end) ==
               [{2022, 6}, {2023, 6}]
    end
  end

  describe "BYMONTHDAY — always a LIMIT" do
    test "single day: keeps matching candidate" do
      candidate = %Tempo.Interval{from: ~o"2022-06-15"}
      rule = %Tempo{time: [selection: [day: 15]], calendar: Calendrical.Gregorian}
      assert Selection.apply(candidate, rule, :month) == [candidate]
    end

    test "negative day: -1 matches the last day of the month" do
      # June has 30 days. BYMONTHDAY=-1 matches June 30.
      candidate = %Tempo.Interval{from: ~o"2022-06-30"}
      rule = %Tempo{time: [selection: [day: -1]], calendar: Calendrical.Gregorian}
      assert Selection.apply(candidate, rule, :month) == [candidate]
    end

    test "EXPAND for MONTHLY — swaps candidate day to the requested" do
      # BYMONTHDAY with FREQ=MONTHLY is EXPAND per RFC 5545
      # §3.3.10. The resolver rewrites the candidate's day to
      # each listed value (signed indexing resolved against the
      # enclosing month's length).
      candidate = %Tempo.Interval{from: ~o"2022-06-29"}
      rule = %Tempo{time: [selection: [day: -1]], calendar: Calendrical.Gregorian}

      [result] = Selection.apply(candidate, rule, :month)
      assert result.from.time[:day] == 30
    end

    test "YEARLY + BYMONTH + BYMONTHDAY end-to-end" do
      # Jan 1 of each year for 3 years.
      rule = %Rule{freq: :year, interval: 1, bymonth: [1], bymonthday: [1], count: 3}
      {:ok, occ} = Expander.expand(rule, ~o"2022-01-01")

      assert Enum.map(occ, fn iv ->
               {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
             end) == [{2022, 1, 1}, {2023, 1, 1}, {2024, 1, 1}]
    end
  end

  describe "BYYEARDAY — LIMIT with signed indexing" do
    test "BYYEARDAY=1 matches Jan 1" do
      candidate = %Tempo.Interval{from: ~o"2022-01-01"}
      rule = %Tempo{time: [selection: [day_of_year: 1]], calendar: Calendrical.Gregorian}
      assert Selection.apply(candidate, rule, :year) == [candidate]
    end

    test "BYYEARDAY=-1 matches Dec 31 (both leap and non-leap)" do
      # 2024 is a leap year: day 366 = Dec 31. 2022 is not:
      # day 365 = Dec 31. In both cases BYYEARDAY=-1 picks the
      # last day.
      for year <- [2022, 2024] do
        candidate = %Tempo.Interval{from: Tempo.new!(year: year, month: 12, day: 31)}
        rule = %Tempo{time: [selection: [day_of_year: -1]], calendar: Calendrical.Gregorian}
        assert Selection.apply(candidate, rule, :year) == [candidate]
      end
    end

    test "end-to-end: FREQ=YEARLY;BYYEARDAY=-1 picks every Dec 31" do
      rule = %Rule{freq: :year, interval: 1, byyearday: [-1], count: 3}
      {:ok, occ} = Expander.expand(rule, ~o"2022-12-31")

      assert Enum.map(occ, fn iv ->
               {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
             end) == [{2022, 12, 31}, {2023, 12, 31}, {2024, 12, 31}]
    end
  end

  describe "BYWEEKNO — EXPAND for YEARLY" do
    test "EXPAND emits all 7 days of the matching ISO week" do
      # BYWEEKNO with FREQ=YEARLY is EXPAND per RFC 5545
      # §3.3.10. Each listed week expands to its 7 constituent
      # days (Mon..Sun, ISO).
      candidate = %Tempo.Interval{from: ~o"2022-01-03"}
      rule = %Tempo{time: [selection: [week: 1]], calendar: Calendrical.Gregorian}

      results = Selection.apply(candidate, rule, :year)
      assert length(results) == 7

      days = Enum.map(results, & &1.from.time[:day])
      assert days == [3, 4, 5, 6, 7, 8, 9]
    end

    test "end-to-end: FREQ=YEARLY;BYWEEKNO=1 — 2 years of week-1 days (filtered by DTSTART floor)" do
      rule = %Rule{freq: :year, interval: 1, byweekno: [1], count: 5}
      {:ok, occ} = Expander.expand(rule, ~o"2022-01-03")

      # Year 1: Jan 3-9 (7 days), all ≥ DTSTART.
      # Year 2 starts Jan 2 2023 (Mon) — expansion yields Jan
      # 2-8 (7 more), all ≥ DTSTART.
      # COUNT=5 takes the first 5.
      pairs =
        Enum.map(occ, fn iv ->
          {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
        end)

      assert pairs == [
               {2022, 1, 3},
               {2022, 1, 4},
               {2022, 1, 5},
               {2022, 1, 6},
               {2022, 1, 7}
             ]
    end
  end

  describe "BYDAY without ordinal" do
    test "DAILY: LIMIT — weekdays only" do
      # MO=1, TU=2, WE=3, TH=4, FR=5 drop SA/SU.
      rule = %Rule{
        freq: :day,
        interval: 1,
        byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}],
        count: 5
      }

      {:ok, occ} = Expander.expand(rule, ~o"2022-06-15")

      # 2022-06-15 = Wed. Expect Wed, Thu, Fri, skip Sat, Sun,
      # then Mon, Tue. That's 5 weekday occurrences.
      days = Enum.map(occ, & &1.from.time[:day])
      assert days == [15, 16, 17, 20, 21]
    end

    test "MONTHLY: EXPAND — every Monday in each month" do
      rule = %Rule{freq: :month, interval: 1, byday: [{nil, 1}]}

      {:ok, occ} =
        Expander.expand(rule, ~o"2022-06-06", bound: ~o"2022-08-01")

      pairs =
        Enum.map(occ, fn iv -> {iv.from.time[:month], iv.from.time[:day]} end)

      # June Mondays: 6, 13, 20, 27. July Mondays: 4, 11, 18, 25.
      # Occurrences are ordered by iteration (monthly cadence
      # steps through candidate anchors), so June's Mondays
      # interleave with July's within the expanded per-iteration
      # group.
      assert Enum.sort(pairs) ==
               [{6, 6}, {6, 13}, {6, 20}, {6, 27}, {7, 4}, {7, 11}, {7, 18}, {7, 25}]
    end

    test "YEARLY: EXPAND — ~52 Mondays in 2022" do
      rule = %Rule{freq: :year, interval: 1, byday: [{nil, 1}], count: 60}
      {:ok, occ} = Expander.expand(rule, ~o"2022-01-03")

      mondays_2022 = Enum.count(occ, fn iv -> iv.from.time[:year] == 2022 end)
      assert mondays_2022 == 52
    end

    test "WEEKLY: EXPAND — RFC 5545 §3.8.5.3 canonical example" do
      # "Weekly on Tuesday and Thursday for five weeks":
      #   DTSTART=Tue 1997-09-02  BYDAY=TU,TH  COUNT=10
      # Expected: Sep 2, 4, 9, 11, 16, 18, 23, 25, 30, Oct 2.
      rule = %Rule{freq: :week, interval: 1, byday: [{nil, 2}, {nil, 4}], count: 10}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")

      pairs = Enum.map(occ, fn iv -> {iv.from.time[:month], iv.from.time[:day]} end)

      assert pairs == [
               {9, 2},
               {9, 4},
               {9, 9},
               {9, 11},
               {9, 16},
               {9, 18},
               {9, 23},
               {9, 25},
               {9, 30},
               {10, 2}
             ]
    end
  end

  describe "BYHOUR / BYMINUTE / BYSECOND — expand when FREQ is coarser" do
    test "DAILY + BYHOUR=9,17 EXPAND produces 2 occurrences per day" do
      rule = %Rule{freq: :day, interval: 1, byhour: [9, 17], count: 4}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01T09")

      pairs = Enum.map(occ, &{&1.from.time[:day], &1.from.time[:hour]})
      assert Enum.sort(pairs) == [{1, 9}, {1, 17}, {2, 9}, {2, 17}]
    end

    test "DAILY + BYMINUTE=0,30 EXPAND" do
      rule = %Rule{freq: :day, interval: 1, byminute: [0, 30], count: 4}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01T09:00")

      triples =
        Enum.map(occ, &{&1.from.time[:day], &1.from.time[:hour], &1.from.time[:minute]})

      assert Enum.sort(triples) == [{1, 9, 0}, {1, 9, 30}, {2, 9, 0}, {2, 9, 30}]
    end

    test "HOURLY + BYHOUR=9,17 LIMIT — filter candidates to listed hours" do
      rule = %Rule{freq: :hour, interval: 1, byhour: [9, 17], count: 4}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01T09")

      pairs = Enum.map(occ, &{&1.from.time[:day], &1.from.time[:hour]})
      assert pairs == [{1, 9}, {1, 17}, {2, 9}, {2, 17}]
    end
  end

  describe "end-to-end — BYMONTH through Tempo.ICal.from_ical/2" do
    test "FREQ=MONTHLY;BYMONTH=6,7,8;COUNT=6 no longer falls back to first-only" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:bymonth-test
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Summer-only monthly
      RRULE:FREQ=MONTHLY;BYMONTH=6,7,8;COUNT=6
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.from_ical(ics)
      assert length(set.intervals) == 6

      # No event has the fallback marker — all are real
      # materialised occurrences.
      assert Enum.all?(set.intervals, fn iv ->
               iv.metadata[:recurrence_note] == nil
             end)

      pairs =
        Enum.map(set.intervals, fn iv ->
          {iv.from.time[:year], iv.from.time[:month]}
        end)

      assert pairs == [{2022, 6}, {2022, 7}, {2022, 8}, {2023, 6}, {2023, 7}, {2023, 8}]
    end

    test "FREQ=WEEKLY;BYDAY=TU,TH;COUNT=10 (RFC example) no longer falls back" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:weekly-tu-th
      DTSTAMP:19970101T000000Z
      DTSTART:19970902T090000Z
      DTEND:19970902T100000Z
      SUMMARY:Tue and Thu
      RRULE:FREQ=WEEKLY;BYDAY=TU,TH;COUNT=10
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.from_ical(ics)
      assert length(set.intervals) == 10

      assert Enum.all?(set.intervals, fn iv ->
               iv.metadata[:recurrence_note] == nil
             end)
    end

    test "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH (Thanksgiving) materialises — Phase C support" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:thanksgiving
      DTSTAMP:20220101T000000Z
      DTSTART:20221124T000000Z
      DTEND:20221125T000000Z
      SUMMARY:Thanksgiving
      RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=3
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.from_ical(ics)
      assert length(set.intervals) == 3

      assert Enum.all?(set.intervals, fn iv ->
               iv.metadata[:recurrence_note] == nil
             end)

      pairs =
        Enum.map(set.intervals, fn iv ->
          {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
        end)

      # 4th Thursday of November: 2022-11-24, 2023-11-23, 2024-11-28.
      assert pairs == [{2022, 11, 24}, {2023, 11, 23}, {2024, 11, 28}]
    end
  end

  describe "BYDAY with ordinal — nth_kday within period" do
    test "FREQ=MONTHLY;BYDAY=1MO picks the first Monday of each month" do
      rule = %Rule{freq: :month, interval: 1, byday: [{1, 1}], count: 3}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01")

      pairs =
        Enum.map(occ, fn iv ->
          {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
        end)

      # 1st Mondays: 2022-06-06, 2022-07-04, 2022-08-01.
      assert pairs == [{2022, 6, 6}, {2022, 7, 4}, {2022, 8, 1}]
    end

    test "FREQ=MONTHLY;BYDAY=-1FR picks the last Friday of each month" do
      rule = %Rule{freq: :month, interval: 1, byday: [{-1, 5}], count: 3}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01")

      pairs =
        Enum.map(occ, fn iv ->
          {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
        end)

      # Last Fridays of June/July/August 2022: 24, 29, 26.
      assert pairs == [{2022, 6, 24}, {2022, 7, 29}, {2022, 8, 26}]
    end

    test "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH (Thanksgiving) — 4th Thursday of November" do
      rule = %Rule{freq: :year, interval: 1, bymonth: [11], byday: [{4, 4}], count: 3}
      {:ok, occ} = Expander.expand(rule, ~o"2022-11-24")

      pairs =
        Enum.map(occ, fn iv ->
          {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
        end)

      assert pairs == [{2022, 11, 24}, {2023, 11, 23}, {2024, 11, 28}]
    end

    test "mixed ordinals — FREQ=MONTHLY;BYDAY=1MO,-1FR produces 2 per month" do
      rule = %Rule{freq: :month, interval: 1, byday: [{1, 1}, {-1, 5}], count: 4}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01")

      pairs =
        Enum.map(occ, fn iv ->
          {iv.from.time[:month], iv.from.time[:day]}
        end)

      # June: 1st Mon = 6, last Fri = 24. July: 1st Mon = 4, last Fri = 29.
      assert Enum.sort(pairs) == Enum.sort([{6, 6}, {6, 24}, {7, 4}, {7, 29}])
    end

    test "mixed BYDAY entries — `BYDAY=MO,2TU` combines expand + nth_kday" do
      # MO without ordinal: every Monday of the month.
      # 2TU: 2nd Tuesday of the month.
      rule = %Rule{freq: :month, interval: 1, byday: [{nil, 1}, {2, 2}]}

      # `~o"2022-06"` has upper endpoint = July 1 (exclusive),
      # so the iterator terminates before the July anchor.
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01", bound: ~o"2022-06")

      pairs = Enum.map(occ, fn iv -> {iv.from.time[:month], iv.from.time[:day]} end)

      # June 2022: Mondays = 6, 13, 20, 27; 2nd Tuesday = 14.
      assert Enum.sort(pairs) == Enum.sort([{6, 6}, {6, 13}, {6, 20}, {6, 27}, {6, 14}])
    end

    test "out-of-range ordinal drops silently — `BYDAY=5MO` in a 4-Monday month" do
      # June 2022 has 4 Mondays (6, 13, 20, 27) — no 5th Monday.
      rule = %Rule{freq: :month, interval: 1, byday: [{5, 1}]}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01", bound: ~o"2022-06-30")

      assert occ == []
    end
  end

  describe "BYSETPOS — picks Nth from per-period set" do
    test "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1 = last weekday of each month" do
      rule = %Rule{
        freq: :month,
        interval: 1,
        byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}],
        bysetpos: [-1],
        count: 3
      }

      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01")

      pairs =
        Enum.map(occ, fn iv ->
          {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
        end)

      # Last weekday of June 2022 = 30 (Thu). July = 29 (Fri). Aug = 31 (Wed).
      assert pairs == [{2022, 6, 30}, {2022, 7, 29}, {2022, 8, 31}]
    end

    test "BYSETPOS=3 picks the 3rd occurrence in the per-period set" do
      # "The third instance into the month of one of Tuesday,
      # Wednesday, or Thursday, for the next 3 months" — RFC
      # example.
      rule = %Rule{
        freq: :month,
        interval: 1,
        byday: [{nil, 2}, {nil, 3}, {nil, 4}],
        bysetpos: [3],
        count: 3
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")

      pairs =
        Enum.map(occ, fn iv ->
          {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
        end)

      # Sep 1997 Tue/Wed/Thu in order: 2, 3, 4, 9, 10, 11, 16, ...
      # The 3rd is Sep 4 (Thu). Oct 3rd: TU=7, WE=1, TH=2 → 1st Oct is Wed;
      # list = [Oct 1 (Wed), Oct 2 (Thu), Oct 7 (Tue)] → 3rd = Oct 7.
      # Actually: Oct 1997 Tue/Wed/Thu = [1, 2, 7, 8, 9, ...], 3rd = Oct 7.
      # Nov 1997 Tue/Wed/Thu = [4, 5, 6, 11, ...], 3rd = Nov 6.
      assert pairs == [{1997, 9, 4}, {1997, 10, 7}, {1997, 11, 6}]
    end

    test "BYSETPOS with out-of-range positions silently drops" do
      # 3 weekdays per week; asking for 99th is nonsense — drop.
      # Bound-terminated (not COUNT) so the iterator stops at
      # end-of-June instead of walking to the safety cap.
      rule = %Rule{
        freq: :week,
        interval: 1,
        byday: [{nil, 1}, {nil, 3}, {nil, 5}],
        bysetpos: [99]
      }

      {:ok, occ} = Expander.expand(rule, ~o"2022-06-06", bound: ~o"2022-06")
      assert occ == []
    end
  end

  describe "end-to-end — BYSETPOS through Tempo.ICal.from_ical/2" do
    test "last-weekday-of-month event materialises fully" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:last-weekday
      DTSTAMP:20220101T000000Z
      DTSTART:20220630T170000Z
      DTEND:20220630T180000Z
      SUMMARY:Month-end review
      RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.from_ical(ics)
      assert length(set.intervals) == 3

      assert Enum.all?(set.intervals, fn iv ->
               iv.metadata[:recurrence_note] == nil
             end)

      pairs =
        Enum.map(set.intervals, fn iv ->
          {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
        end)

      assert pairs == [{2022, 6, 30}, {2022, 7, 29}, {2022, 8, 31}]
    end
  end

  describe "US holiday patterns — ISO 8601 selection materialisation" do
    # The real US federal-holiday rules, written as converged ISO 8601-2 §12.9
    # selections (weekday-then-position, `1K2I`) and materialised into 2026 —
    # the same forms the holidays guide documents. This exercises the ISO
    # selection surface end-to-end, distinct from the RRULE/`%Rule{}` blocks
    # above, and locks in the nth-weekday, last-weekday and day-range shapes.

    test "nth weekday of month — MLK, Presidents, Columbus, Thanksgiving" do
      assert holiday_dates("R/../P1Y/FL1M1K3IN") == ["2026-01-19"]
      assert holiday_dates("R/../P1Y/FL2M1K3IN") == ["2026-02-16"]
      assert holiday_dates("R/../P1Y/FL10M1K2IN") == ["2026-10-12"]
      assert holiday_dates("R/../P1Y/FL11M4K4IN") == ["2026-11-26"]
    end

    test "last weekday of month — Memorial Day (last Monday in May)" do
      assert holiday_dates("R/../P1Y/FL5M1K-1IN") == ["2026-05-25"]
    end

    test "day-range + weekday + position — Election Day (1st Tuesday after the 1st Monday)" do
      # A Tuesday in days 2..8 of November is the first Tuesday after the
      # first Monday — the rule resolves the day range, filters to Tuesday,
      # then takes position 1.
      assert holiday_dates("R/../P1Y/FL11M{2..8}D2K1IN") == ["2026-11-03"]
    end

    test "day-range + weekday + position — first Friday on or after the 11th" do
      assert holiday_dates("R/../P1Y/FL11M{11..17}D5K1IN") == ["2026-11-13"]
    end

    test "fixed-date holidays — Independence, Veterans, Christmas" do
      assert holiday_dates("R/../P1Y/FL7M4DN") == ["2026-07-04"]
      assert holiday_dates("R/../P1Y/FL11M11DN") == ["2026-11-11"]
      assert holiday_dates("R/../P1Y/FL12M25DN") == ["2026-12-25"]
    end
  end

  describe "ISO 8601-2 §12.10 selection with a time interval" do
    # Each date the inner selection resolves to becomes the start of a window
    # of the given duration; the outer selectors pick within it. These are the
    # spec's own worked examples (§12.11) plus the holidays they describe.

    test "Example 3 — 2nd Thursday following the 2nd Tuesday" do
      # 2nd Tuesday of 2026 is Jan 13; the 2nd Thursday in the 10 days from it
      # is Jan 22.
      assert holiday_dates("R/../P1Y/FLLL2K2IN/P10DN4K2IN") == ["2026-01-22"]
    end

    test "Example 7 — 2nd Sunday before April 4 (Qingming)" do
      assert holiday_dates("R/../P1Y/FLL4M4D/-P20DN7K-2IN") == ["2026-03-22"]
    end

    test "Example 8 — US Election Day (1st Tuesday after the 1st Monday of November)" do
      assert holiday_dates("R/../P1Y/FL11MLL1K1IN/P9DN2K1IN") == ["2026-11-03"]
    end

    test "Good Friday — the last Friday in the seven days before Easter" do
      assert holiday_dates("R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN") == ["2026-04-03"]
    end

    test "a terminal window is one interval spanning its duration" do
      {:ok, rule} = Tempo.from_iso8601("R/../P1Y/FLL3K4IN/P5DN")
      {:ok, set} = Tempo.to_interval(rule, bound: ~o"2026Y")

      # "the 4th Wednesday for 5 days": one occurrence, [Jan 28, Feb 2).
      assert [%Interval{} = occurrence] = IntervalSet.to_list(set)
      assert Interval.from(occurrence) == ~o"2026Y1M28D"
      assert Interval.to(occurrence) == ~o"2026Y2M2D"
    end

    test "a windowed selection round-trips through to_iso8601/1" do
      for iso <- [
            "R/../P1Y/FLLL2K2IN/P10DN4K2IN",
            "R/../P1Y/FL11MLL1K1IN/P9DN2K1IN",
            "R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN"
          ] do
        {:ok, value} = Tempo.from_iso8601(iso)
        assert Tempo.from_iso8601(Tempo.to_iso8601(value)) == {:ok, value}
      end
    end

    test "explain/1 names the window and what is picked within it" do
      assert Tempo.explain(~o"R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN") =~
               "on the last Friday within the 7 days before Easter"

      assert Tempo.explain(~o"R/../P1Y/FL11MLL1K1IN/P9DN2K1IN") =~
               "on the 1st Tuesday within the 9 days from the 1st Monday of November"

      # A terminal window is described on its own.
      assert Tempo.explain(~o"R/../P1Y/FLL3K4IN/P5DN") =~ "the 5 days from the 4th Wednesday"
    end
  end

  # Parse a selection recurrence and list the ISO dates it yields inside 2026.
  defp holiday_dates(iso) do
    {:ok, rule} = Tempo.from_iso8601(iso)
    {:ok, set} = Tempo.to_interval(rule, bound: ~o"2026Y")

    set
    |> IntervalSet.to_list()
    |> Enum.map(fn interval ->
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      Date.to_iso8601(date)
    end)
  end
end
