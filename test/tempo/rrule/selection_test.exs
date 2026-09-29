defmodule Tempo.RRule.SelectionTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.ICal
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
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
        Expander.expand(rule, ~o"2022-06-15", within: ~o"2022/2024")

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

    test "end-to-end: FREQ=YEARLY;BYWEEKNO=1 takes DTSTART's weekday" do
      # ISO 8601-2 Annex C.3: with no BYDAY, BYMONTHDAY or BYYEARDAY the
      # weekday is DTSTART's, a Monday, so each year gives week 1's Monday.
      rule = %Rule{freq: :year, interval: 1, byweekno: [1], count: 5}

      assert rule_dates(rule, ~o"2022-01-03") ==
               ["2022-01-03", "2023-01-02", "2024-01-01", "2024-12-30", "2025-12-29"]
    end

    test "BYWEEKNO without BYDAY is the RFC's Monday of week 20 from a Monday DTSTART" do
      rule = %Rule{freq: :year, interval: 1, byweekno: [20], count: 3}

      assert rule_dates(rule, ~o"1997-05-12") == ["1997-05-12", "1998-05-11", "1999-05-17"]
    end

    test "an RRULE without a DTSTART keeps the whole week" do
      {:ok, rule} = RRule.parse("FREQ=YEARLY;BYWEEKNO=20")
      {:ok, weeks} = Tempo.to_interval(rule, within: ~o"2026")

      assert Tempo.relation(weeks, ~o"2026-05-11/2026-05-18") == :equals
    end

    test "WKST decides which week is week 1" do
      # 2026 starts on a Thursday. Monday-first, week 1 (Dec 29 – Jan 4)
      # holds four days of 2026; Sunday-first, Dec 28 – Jan 3 holds only
      # three, so week 1 is Jan 4 – 10.
      monday_first = %Rule{freq: :year, interval: 1, byweekno: [1], byday: [{nil, 6}], count: 2}
      sunday_first = %{monday_first | wkst: 7}

      assert rule_dates(monday_first, ~o"2026-01-01") == ["2026-01-03", "2027-01-09"]
      assert rule_dates(sunday_first, ~o"2026-01-01") == ["2026-01-10", "2027-01-09"]
    end

    test "a week keeps its days in the calendar year before" do
      rule = %Rule{freq: :year, interval: 1, byweekno: [1], byday: [{nil, 1}], count: 3}

      assert rule_dates(rule, ~o"2025-01-01") == ["2025-12-29", "2027-01-04", "2028-01-03"]
    end

    test "week -1 of a 53-week year runs into the next calendar year" do
      # Week 53 of 2026 is Dec 28 – Jan 3, and week 52 of 2027 Dec 27 – Jan 2.
      rule = %Rule{freq: :year, interval: 1, byweekno: [-1], byday: [{nil, 6}], count: 2}

      assert rule_dates(rule, ~o"2026-01-01") == ["2027-01-02", "2028-01-01"]
    end

    test "BYMONTH keeps the days of the week in the month" do
      # Week 5 of 2026 is Jan 26 – Feb 1. A DTSTART on the 31st does not
      # drop February, since BYWEEKNO decides the day.
      rule = %Rule{
        freq: :year,
        interval: 1,
        bymonth: [2],
        byweekno: [5],
        byday: [{nil, 7}],
        count: 3
      }

      assert rule_dates(rule, ~o"2026-01-31") == ["2026-02-01", "2027-02-07", "2028-02-06"]
    end

    test "BYMONTHDAY keeps the days of the week with that day of the month" do
      rule = %Rule{freq: :year, interval: 1, byweekno: [1], bymonthday: [1], count: 3}

      assert rule_dates(rule, ~o"2026-01-01") == ["2026-01-01", "2029-01-01", "2030-01-01"]
    end

    test "WKST numbers the weeks a finer FREQ limits to" do
      daily = %Rule{freq: :day, interval: 1, byweekno: [1], count: 4}

      assert rule_dates(daily, ~o"2026-01-01") ==
               ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04"]

      assert rule_dates(%{daily | wkst: 7}, ~o"2026-01-01") ==
               ["2026-01-04", "2026-01-05", "2026-01-06", "2026-01-07"]
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
        Expander.expand(rule, ~o"2022-06-06", within: ~o"2022-06/2022-08")

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

  describe "a time-of-day selection keeps each occurrence's span" do
    # An event's span (its DTEND) runs from the time BYHOUR, BYMINUTE or
    # BYSECOND picks, not from the time its DTSTART names.
    test "BYHOUR, BYMINUTE and BYSECOND move the whole occurrence" do
      assert event_spans("FREQ=DAILY;BYHOUR=9,17;COUNT=4", "20260105T090000", "20260105T100000") ==
               [
                 "2026Y1M5DT9H0M0S/T10H0M0S",
                 "2026Y1M5DT17H0M0S/T18H0M0S",
                 "2026Y1M6DT9H0M0S/T10H0M0S",
                 "2026Y1M6DT17H0M0S/T18H0M0S"
               ]

      assert event_spans(
               "FREQ=HOURLY;BYMINUTE=0,30;COUNT=4",
               "20260105T090000",
               "20260105T091500"
             ) ==
               [
                 "2026Y1M5DT9H0M0S/T15M0S",
                 "2026Y1M5DT9H30M0S/T45M0S",
                 "2026Y1M5DT10H0M0S/T15M0S",
                 "2026Y1M5DT10H30M0S/T45M0S"
               ]

      assert event_spans(
               "FREQ=MINUTELY;BYSECOND=0,30;COUNT=4",
               "20260105T090000",
               "20260105T090005"
             ) ==
               [
                 "2026Y1M5DT9H0M0S/T5S",
                 "2026Y1M5DT9H0M30S/T35S",
                 "2026Y1M5DT9H1M0S/T5S",
                 "2026Y1M5DT9H1M30S/T35S"
               ]
    end

    test "a span that runs past midnight ends the next day" do
      assert event_spans("FREQ=DAILY;BYHOUR=9,22;COUNT=4", "20260105T090000", "20260105T130000") ==
               [
                 "2026Y1M5DT9H0M0S/T13H0M0S",
                 "2026Y1M5DT22H0M0S/6DT2H0M0S",
                 "2026Y1M6DT9H0M0S/T13H0M0S",
                 "2026Y1M6DT22H0M0S/7DT2H0M0S"
               ]
    end
  end

  describe "end-to-end — BYMONTH through Tempo.ICal.parse/2" do
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

      {:ok, set} = ICal.parse(ics)
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

      {:ok, set} = ICal.parse(ics)
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

      {:ok, set} = ICal.parse(ics)
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
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01", within: ~o"2022-06")

      pairs = Enum.map(occ, fn iv -> {iv.from.time[:month], iv.from.time[:day]} end)

      # June 2022: Mondays = 6, 13, 20, 27; 2nd Tuesday = 14.
      assert Enum.sort(pairs) == Enum.sort([{6, 6}, {6, 13}, {6, 20}, {6, 27}, {6, 14}])
    end

    test "out-of-range ordinal drops silently — `BYDAY=5MO` in a 4-Monday month" do
      # June 2022 has 4 Mondays (6, 13, 20, 27) — no 5th Monday.
      rule = %Rule{freq: :month, interval: 1, byday: [{5, 1}]}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-01", within: ~o"2022-06-30")

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

      {:ok, occ} = Expander.expand(rule, ~o"2022-06-06", within: ~o"2022-06")
      assert occ == []
    end
  end

  describe "end-to-end — BYSETPOS through Tempo.ICal.parse/2" do
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

      {:ok, set} = ICal.parse(ics)
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

    test "a window reaches into the bound from the year either side" do
      # The first Friday in the five days from 30 December 2025 is 2 January
      # 2026, and the last Tuesday in the five days before 3 January 2027 is
      # 29 December 2026.
      assert holiday_dates("R/../P1Y/FLLL12M30DN/P5DN5K1IN") == ["2026-01-02"]
      assert holiday_dates("R/../P1Y/FLLL1M3DN/-P5DN2K-1IN") == ["2026-12-29"]
    end

    test "a window keeps what starts in its domain's years, across and between them" do
      window = "/P1Y/FLLL12M30DN/P5DN5K1IN"

      assert holiday_dates("R/{2025Y..2027Y}" <> window, ~o"2020Y/2030Y") ==
               ["2025-01-03", "2026-01-02", "2027-01-01", "2027-12-31"]

      # 2026 is outside the domain, so 2 January 2026 is not kept
      assert holiday_dates("R/{2025Y,2027Y}" <> window, ~o"2020Y/2030Y") ==
               ["2025-01-03", "2027-01-01", "2027-12-31"]
    end

    test "a terminal window is one interval spanning its duration" do
      {:ok, rule} = Tempo.from_iso8601("R/../P1Y/FLL3K4IN/P5DN")
      {:ok, set} = Tempo.to_interval(rule, within: ~o"2026Y")

      # "the 4th Wednesday for 5 days": one occurrence, [Jan 28, Feb 2).
      assert [%Interval{} = occurrence] = IntervalSet.members(set)
      assert Interval.from(occurrence) == ~o"2026Y1M28D"
      assert Interval.to(occurrence) == ~o"2026Y2M2D"
    end

    test "a terminal window of hours runs from the time of day it starts at" do
      # Every night, the four hours from 22:00 and the four hours before it.
      nights = ~o"2027-01-01/2027-01-03"

      assert occurrence_spans("R/2027-01-01/P1D/FLLT22HN/PT4HN", nights) ==
               ["2027Y1M1DT22H/2DT2H", "2027Y1M2DT22H/3DT2H"]

      assert occurrence_spans("R/2027-01-01/P1D/FLLT22HN/-PT4HN", nights) ==
               ["2027Y1M1DT18H/T22H", "2027Y1M2DT18H/T22H"]

      # The twelve hours from the 4th Wednesday start at its midnight.
      assert occurrence_spans("R/../P1Y/FLL3K4IN/PT12HN", ~o"2026Y") == ["2026Y1M28D/T12H"]
    end

    test "a window moving an occurrence into the previous year lands there" do
      # 1 January 2022 is a Saturday: "the previous Friday" is 31 December 2021,
      # which belongs to 2021's bound, not 2022's.
      rule = "R/../P1Y/FLLL1M1D6KN/-P7DN5K1IN"
      assert holiday_dates(rule, ~o"2021Y") == ["2021-12-31"]
      assert holiday_dates(rule, ~o"2022Y") == []
    end

    test "a window moving an occurrence into the next year lands there" do
      # 31 December 2022 is a Saturday: "the following Monday" is 2 January 2023.
      rule = "R/../P1Y/FLLL12M31D6KN/P8DN1K-1IN"
      assert holiday_dates(rule, ~o"2022Y") == []
      assert holiday_dates(rule, ~o"2023Y") == ["2023-01-02"]
      assert holiday_dates(rule, ~o"{2021..2023}Y") == ["2023-01-02"]
    end

    test "a calendar window crossing the Gregorian year lands in the following year" do
      # 10 Dhu al-Hijjah 1427 (Umm al-Qura) is Sunday 31 December 2006; the
      # following Monday is 1 January 2007.
      rule = "R/../P1Y/FLLL12M10D7KN/P8DN1K-1IN[u-ca=islamic-umalqura]"
      assert gregorian_dates(rule, ~o"2006Y") == []
      assert gregorian_dates(rule, ~o"2007Y") == ["2007-01-01"]
    end

    test "a windowed selection round-trips through to_iso8601/1" do
      for iso <- [
            "R/../P1Y/FLLL2K2IN/P10DN4K2IN",
            "R/../P1Y/FL11MLL1K1IN/P9DN2K1IN",
            "R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN"
          ] do
        {:ok, value} = Tempo.from_iso8601(iso)
        assert Tempo.from_iso8601(Tempo.to_iso8601!(value)) == {:ok, value}
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

  describe "an explicit anchor coarser than its selection" do
    test "a year anchor walks a day selection rather than raising" do
      {:ok, rule} = Tempo.from_iso8601("R/2020Y/P4Y/FL11M3DN")
      {:ok, set} = Tempo.to_interval(rule, within: ~o"{2019..2028}Y")

      assert Enum.map(IntervalSet.members(set), &Tempo.to_iso8601!(Interval.from(&1))) ==
               ["2020Y11M3D", "2024Y11M3D", "2028Y11M3D"]
    end

    test "a counted recurrence from a year anchor" do
      {:ok, rule} = Tempo.from_iso8601("R3/2020Y/P1Y/FL6M15DN")
      {:ok, set} = Tempo.to_interval(rule)

      assert Enum.map(IntervalSet.members(set), &Tempo.to_iso8601!(Interval.from(&1))) ==
               ["2020Y6M15D", "2021Y6M15D", "2022Y6M15D"]
    end
  end

  # Parse a selection recurrence and list the ISO dates it yields inside a bound
  # (2026 by default).
  defp holiday_dates(iso, bound \\ ~o"2026Y") do
    {:ok, rule} = Tempo.from_iso8601(iso)
    {:ok, set} = Tempo.to_interval(rule, within: bound)

    set
    |> IntervalSet.members()
    |> Enum.map(fn interval ->
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      Date.to_iso8601(date)
    end)
  end

  # As `holiday_dates/2`, converting a calendar recurrence's dates to Gregorian.
  defp gregorian_dates(iso, bound) do
    {:ok, rule} = Tempo.from_iso8601(iso)
    {:ok, set} = Tempo.to_interval(rule, within: bound)

    set
    |> IntervalSet.members()
    |> Enum.map(fn interval ->
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      date |> Date.convert!(Calendar.ISO) |> Date.to_iso8601()
    end)
  end

  describe "week selections (ISO 8601-2 §12.2.2)" do
    # 2027 starts on a Friday, so ISO 8601's week 1 starts on Monday 4
    # January and Calendrical.Gregorian's own week 1 on Monday 28 December.
    test "W selects an ISO 8601 week and w the calendar's own" do
      {:ok, iso} = Tempo.to_interval(~o"R/../P1Y/FL10WN", within: ~o"2027")
      {:ok, calendar} = Tempo.to_interval(~o"R/../P1Y/FL10wN", within: ~o"2027")

      assert Tempo.relation(iso, ~o"2027-03-08/2027-03-15") == :equals
      assert Tempo.relation(calendar, ~o"2027-03-01/2027-03-08") == :equals
    end

    test "a weekday within a week selection is in that week" do
      assert holiday_dates("R/../P1Y/FL10W3KN", ~o"2027Y") == ["2027-03-10"]
      assert holiday_dates("R/../P1Y/FL10w3KN", ~o"2027Y") == ["2027-03-03"]
    end

    test "a calendar week cut short at the start of its year holds only its own days" do
      # The Saturday of each Hebrew year's week 1, which runs from 1 Tishri
      # to the first Shabbat: 5 Tishri 5786, 1 Tishri 5787 and 5788 (both
      # Saturdays, so week 1 is that day alone) and 3 Tishri 5789.
      assert holiday_dates(
               "R/5786Y1M1D[u-ca=hebrew]/P1Y/FL1w6KN",
               Tempo.from_iso8601!("5786Y/5790Y[u-ca=hebrew]")
             ) == ["2025-09-27", "2026-09-12", "2027-10-02", "2028-09-23"]

      # 1 Tishri 5787 is week 1's only day, so it has no Monday
      assert holiday_dates(
               "R/5787Y1M1D[u-ca=hebrew]/P1Y/FL1w1KN",
               Tempo.from_iso8601!("5787Y[u-ca=hebrew]")
             ) == []
    end
  end

  describe "a year in a recurrence selection" do
    # ISO 8601-2 §12.2 has no year selection rule. A year in a recurrence's
    # selection limits it to the occurrences that start in a listed year, as
    # a recurrence domain does.
    test "a year limits a yearly recurrence to its occurrence in that year" do
      assert holiday_dates("R/2026-01-01/P1Y/FL2027Y1M1DN", ~o"2026Y/2030Y") == ["2027-01-01"]
      assert holiday_dates("R/2026-01-01/P1Y/FL2027YN", ~o"2026Y/2030Y") == ["2027-01-01"]
    end

    test "a set, a range or a mask of years limits to each year it holds" do
      bound = ~o"2026Y/2030Y"
      even_years = ["2026-01-01", "2028-01-01"]

      assert holiday_dates("R/2026-01-01/P1Y/FL{2026,2028}Y1M1DN", bound) == even_years

      assert holiday_dates("R/2026-01-01/P1Y/FL{2027..2028}Y1M1DN", bound) ==
               ["2027-01-01", "2028-01-01"]

      # Any four-digit even year, as ISO 8601-2 §12.11 writes US Election Day's
      assert holiday_dates("R/2026-01-01/P1Y/FLXXX{0,2,4,6,8}Y1M1DN", bound) == even_years

      assert holiday_dates("R/2026-01-01/P1Y/FLX*Y1M1DN", bound) ==
               ["2026-01-01", "2027-01-01", "2028-01-01", "2029-01-01"]
    end

    test "a year limits a finer recurrence to that year's occurrences" do
      dates = holiday_dates("R/2026-01-01/P1M/FL2027Y15DN", ~o"2026Y/2029Y")

      assert length(dates) == 12
      assert hd(dates) == "2027-01-15"
      assert List.last(dates) == "2027-12-15"
    end

    test "an occurrence counts in the year it starts in, as a domain's does" do
      # ISO 8601 week 1 of 2026 starts on Monday 29 December 2025
      bound = ~o"2025Y/2028Y"

      assert holiday_dates("R/2025-01-01/P1Y/FL2026Y1W1KN", bound) ==
               holiday_dates("R/{2026Y}/P1Y/FL1W1KN", bound)

      assert holiday_dates("R/2025-01-01/P1Y/FL2027Y1W1KN", bound) == ["2027-01-04"]
    end

    test "a year in a window's selection limits the window's start" do
      assert holiday_dates("R/2026-01-01/P1Y/FLL2027Y12M31DN/P3DN", ~o"2026Y/2030Y") ==
               ["2027-12-31"]
    end
  end

  describe "a selection within a value (ISO 8601-2 §12.11)" do
    # The units before a selection are its context; each period of the
    # context resolves the selection once.
    test "a selection in a stated year and month is that month's date" do
      # §12.11.1 Example 1: the first Monday of March 2018
      assert selection_dates("2018Y3ML1K1IN") == ["2018-03-05"]
      assert selection_dates("2018Y{3,9}ML1K1IN") == ["2018-03-05", "2018-09-03"]
    end

    test "a set of years resolves the selection in each" do
      # §12.11.1 Example 3: the February 29 of 2018 to 2022
      assert selection_dates("{2018,2019,2020,2021,2022}YL2M29D1IN") == ["2020-02-29"]
    end

    test "US Election Day in any four-digit even year resolves one year at a time" do
      # §12.11.1 Example 8: the Tuesday after the first Monday of November
      election_day = "XXX{0,2,4,6,8}Y11MLLL1K1IN/P9DN2K1IN"

      assert selection_dates(election_day, within: ~o"2024Y/2029Y") ==
               ["2024-11-05", "2026-11-03", "2028-11-07"]

      assert selection_dates("2024Y11MLLL1K1IN/P9DN2K1IN") == ["2024-11-05"]
    end

    test "a selection in an unspecified year needs a bound" do
      # §12.11.1 Example 4: Mother's Day, the second Sunday of May
      assert selection_dates("X*YL5M7K2IN", within: ~o"2024Y/2027Y") ==
               ["2024-05-12", "2025-05-11", "2026-05-10"]

      assert {:error, %Tempo.UnboundedRecurrenceError{}} =
               Tempo.to_interval(Tempo.from_iso8601!("X*YL5M7K2IN"))
    end

    test "a window before a date selects within it" do
      # §12.11.1 Example 7: the second Sunday before 4 April
      assert selection_dates("2026YLL4M4D/-P20DN7K-2IN") == ["2026-03-22"]
    end

    test "the units after a selection apply to every date it selects" do
      # §12.11.2 Example 2: every Monday, Tuesday and Friday of 2018 at 10:00
      {:ok, set} = Tempo.to_interval(Tempo.from_iso8601!("2018YL{1,2,5}KNT10H0M0S"))
      [first | _rest] = occurrences = IntervalSet.members(set)

      assert length(occurrences) == 157
      assert Tempo.relation(first, ~o"2018-01-01T10:00:00/2018-01-01T10:00:01") == :equals
    end

    test "an interval from or to a selection spans from or to each date it selects" do
      # §12.11.3 Example 1: five days from the first Monday of September 2018
      {:ok, from_monday} = Tempo.to_interval(Tempo.from_iso8601!("2018Y9ML1K1IN/P5D"))
      {:ok, to_monday} = Tempo.to_interval(Tempo.from_iso8601!("P5D/2018Y9ML1K1IN"))

      assert Tempo.relation(from_monday, ~o"2018-09-03/2018-09-08") == :equals
      assert Tempo.relation(to_monday, ~o"2018-08-29/2018-09-03") == :equals
    end
  end

  # Materialise a value holding a selection and list the ISO dates it yields.
  defp selection_dates(iso, options \\ []) do
    {:ok, set} = iso |> Tempo.from_iso8601!() |> Tempo.to_interval(options)

    set
    |> IntervalSet.members()
    |> Enum.map(fn interval ->
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      Date.to_iso8601(date)
    end)
  end

  # Materialise a recurrence within `within` and list its occurrences.
  defp occurrence_spans(iso, within) do
    {:ok, set} = iso |> Tempo.from_iso8601!() |> Tempo.to_interval(within: within)
    set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
  end

  # Parse one iCalendar event recurring by `rule` and list its occurrences.
  defp event_spans(rule, dtstart, dtend) do
    {:ok, set} =
      ICal.parse("""
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:event-spans
      DTSTAMP:20260101T000000Z
      DTSTART:#{dtstart}
      DTEND:#{dtend}
      RRULE:#{rule}
      END:VEVENT
      END:VCALENDAR
      """)

    set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
  end

  # Expand an RRULE from `dtstart` and list the ISO dates of its occurrences.
  defp rule_dates(rule, dtstart) do
    {:ok, occurrences} = Expander.expand(rule, dtstart)

    Enum.map(occurrences, fn interval ->
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      Date.to_iso8601(date)
    end)
  end
end
