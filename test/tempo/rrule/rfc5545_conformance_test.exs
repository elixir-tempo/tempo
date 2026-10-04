defmodule Tempo.RRule.Rfc5545ConformanceTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  doctest Tempo.RRule

  # RFC 5545 §3.8.5.3 worked examples.
  #
  # Each `test` mirrors one (or a close pair) of the RFC's
  # sample rules, exercising the full pipeline:
  #
  #   %Tempo.RRule.Rule{}  →  Expander.expand/3
  #                       →  Tempo.to_interval/2
  #                       →  Tempo.RRule.Selection.apply/3
  #                       →  [%Tempo.Interval{}]
  #
  # The expected dates are copied verbatim from the RFC. A passing
  # test means Tempo agrees with the RFC's canonical output; a
  # failure surfaces a semantic gap for Phase G to document or fix.
  #
  # DTSTART values in the RFC are often shown with a timezone
  # (e.g. `TZID=America/New_York`). Since RRULE expansion works in
  # "wall-clock" space, we use naive Tempo values here and compare
  # local date components — timezone handling is orthogonal.

  # ------------------------------------------------------------
  # Helper — return `{year, month, day}` tuples for easy asserts.
  defp ymd(occurrences) do
    Enum.map(occurrences, fn iv ->
      {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
    end)
  end

  # `{month, day}` for yearly tests where the year is obvious.
  defp md(occurrences) do
    Enum.map(occurrences, fn iv ->
      {iv.from.time[:month], iv.from.time[:day]}
    end)
  end

  ## =============================================================
  ## Daily
  ## =============================================================

  describe "Daily" do
    test "Daily for 10 occurrences" do
      # DTSTART;TZID=America/New_York:19970902T090000
      # RRULE:FREQ=DAILY;COUNT=10
      # ==> (1997 9:00 AM EDT) September 2-11
      rule = %Rule{freq: :day, interval: 1, count: 10}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")

      assert md(occ) == [
               {9, 2},
               {9, 3},
               {9, 4},
               {9, 5},
               {9, 6},
               {9, 7},
               {9, 8},
               {9, 9},
               {9, 10},
               {9, 11}
             ]
    end

    test "Daily until December 24, 1997" do
      # RRULE:FREQ=DAILY;UNTIL=19971224T000000Z
      # ==> (1997 9:00 AM EDT) September 2-30;October 1-25
      #     (1997 9:00 AM EST) October 26-31;November 1-30;December 1-23
      # The RFC's 113 count uses datetime-resolution DTSTART
      # (09:00) vs midnight UNTIL — a 9 AM candidate at Dec 24
      # falls AFTER midnight UNTIL and is excluded. At
      # day-resolution (below) the Dec 24 candidate compares
      # :same to UNTIL and inclusively passes, so we see 114.
      rule = %Rule{freq: :day, interval: 1, until: ~o"1997-12-24"}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")
      assert Enum.count(occ) == 114
      assert hd(occ).from.time == [year: 1997, month: 9, day: 2]
      assert List.last(occ).from.time == [year: 1997, month: 12, day: 24]
    end

    test "Every other day, bounded" do
      # RRULE:FREQ=DAILY;INTERVAL=2;COUNT=5
      rule = %Rule{freq: :day, interval: 2, count: 5}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")
      assert md(occ) == [{9, 2}, {9, 4}, {9, 6}, {9, 8}, {9, 10}]
    end

    test "Every 10 days, 5 occurrences" do
      # RRULE:FREQ=DAILY;INTERVAL=10;COUNT=5
      # ==> (1997 9:00 AM EDT) September 2,12,22; October 2,12
      rule = %Rule{freq: :day, interval: 10, count: 5}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")
      assert md(occ) == [{9, 2}, {9, 12}, {9, 22}, {10, 2}, {10, 12}]
    end
  end

  ## =============================================================
  ## Weekly
  ## =============================================================

  describe "Weekly" do
    test "Weekly for 10 occurrences" do
      # RRULE:FREQ=WEEKLY;COUNT=10
      rule = %Rule{freq: :week, interval: 1, count: 10}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")

      assert md(occ) == [
               {9, 2},
               {9, 9},
               {9, 16},
               {9, 23},
               {9, 30},
               {10, 7},
               {10, 14},
               {10, 21},
               {10, 28},
               {11, 4}
             ]
    end

    test "Weekly until December 24, 1997" do
      rule = %Rule{freq: :week, interval: 1, until: ~o"1997-12-24"}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")
      # Every Tuesday from Sep 2 through Dec 23 — 17 occurrences.
      assert Enum.count(occ) == 17
      assert hd(occ).from.time[:day] == 2
      assert List.last(occ).from.time == [year: 1997, month: 12, day: 23]
    end

    test "Every other week, forever (bounded for test — 6 occurrences)" do
      # RRULE:FREQ=WEEKLY;INTERVAL=2;WKST=SU
      rule = %Rule{freq: :week, interval: 2, wkst: 7, count: 6}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")
      assert md(occ) == [{9, 2}, {9, 16}, {9, 30}, {10, 14}, {10, 28}, {11, 11}]
    end

    test "Weekly on Tuesday and Thursday for 5 weeks" do
      # RRULE:FREQ=WEEKLY;COUNT=10;WKST=SU;BYDAY=TU,TH
      rule = %Rule{
        freq: :week,
        interval: 1,
        byday: [{nil, 2}, {nil, 4}],
        count: 10,
        wkst: 7
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")

      assert md(occ) == [
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

    test "Every other week, MO, WE, FR, 6 occurrences" do
      # RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=6;BYDAY=MO,WE,FR;WKST=SU
      # DTSTART = Mon 1997-09-01.
      rule = %Rule{
        freq: :week,
        interval: 2,
        byday: [{nil, 1}, {nil, 3}, {nil, 5}],
        count: 6,
        wkst: 7
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-09-01")
      # Wk1: Sep 1 (Mon), 3 (Wed), 5 (Fri) — 3 occ
      # Skip Wk2
      # Wk3: Sep 15, 17, 19 — 3 more
      assert md(occ) == [{9, 1}, {9, 3}, {9, 5}, {9, 15}, {9, 17}, {9, 19}]
    end

    test "Every other week, TU, TH, 4 occurrences" do
      # RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,TH;WKST=SU
      rule = %Rule{
        freq: :week,
        interval: 2,
        byday: [{nil, 2}, {nil, 4}],
        count: 4,
        wkst: 7
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")
      # Wk1: Sep 2 (Tue), 4 (Thu); Wk3: Sep 16, 18.
      assert md(occ) == [{9, 2}, {9, 4}, {9, 16}, {9, 18}]
    end
  end

  ## =============================================================
  ## Monthly
  ## =============================================================

  describe "Monthly" do
    test "Monthly on the first Friday for 10 occurrences" do
      # RRULE:FREQ=MONTHLY;COUNT=10;BYDAY=1FR
      # DTSTART = 1997-09-05 (Friday)
      rule = %Rule{freq: :month, interval: 1, byday: [{1, 5}], count: 10}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-05")

      assert ymd(occ) == [
               {1997, 9, 5},
               {1997, 10, 3},
               {1997, 11, 7},
               {1997, 12, 5},
               {1998, 1, 2},
               {1998, 2, 6},
               {1998, 3, 6},
               {1998, 4, 3},
               {1998, 5, 1},
               {1998, 6, 5}
             ]
    end

    test "Every other month on the 1st and last Sunday for 10 occurrences" do
      # RRULE:FREQ=MONTHLY;INTERVAL=2;COUNT=10;BYDAY=1SU,-1SU
      # DTSTART = 1997-09-07 (first Sunday of Sep).
      rule = %Rule{
        freq: :month,
        interval: 2,
        byday: [{1, 7}, {-1, 7}],
        count: 10
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-09-07")

      assert ymd(occ) == [
               {1997, 9, 7},
               {1997, 9, 28},
               {1997, 11, 2},
               {1997, 11, 30},
               {1998, 1, 4},
               {1998, 1, 25},
               {1998, 3, 1},
               {1998, 3, 29},
               {1998, 5, 3},
               {1998, 5, 31}
             ]
    end

    test "Monthly on the second-to-last Monday for 6 months" do
      # RRULE:FREQ=MONTHLY;COUNT=6;BYDAY=-2MO
      # DTSTART = 1997-09-22 (the last Monday of Sep is 29; 2nd-to-last is 22).
      rule = %Rule{freq: :month, interval: 1, byday: [{-2, 1}], count: 6}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-22")

      assert ymd(occ) == [
               {1997, 9, 22},
               {1997, 10, 20},
               {1997, 11, 17},
               {1997, 12, 22},
               {1998, 1, 19},
               {1998, 2, 16}
             ]
    end

    test "Monthly on the 2nd and 15th for 10 occurrences" do
      # RRULE:FREQ=MONTHLY;COUNT=10;BYMONTHDAY=2,15
      # DTSTART = 1997-09-02
      rule = %Rule{freq: :month, interval: 1, bymonthday: [2, 15], count: 10}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")

      assert ymd(occ) == [
               {1997, 9, 2},
               {1997, 9, 15},
               {1997, 10, 2},
               {1997, 10, 15},
               {1997, 11, 2},
               {1997, 11, 15},
               {1997, 12, 2},
               {1997, 12, 15},
               {1998, 1, 2},
               {1998, 1, 15}
             ]
    end

    test "Monthly on the first and last day of the month for 10 occurrences" do
      # RRULE:FREQ=MONTHLY;COUNT=10;BYMONTHDAY=1,-1
      # DTSTART = 1997-09-30 (last day of Sep).
      rule = %Rule{freq: :month, interval: 1, bymonthday: [1, -1], count: 10}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-30")

      assert ymd(occ) == [
               {1997, 9, 30},
               {1997, 10, 1},
               {1997, 10, 31},
               {1997, 11, 1},
               {1997, 11, 30},
               {1997, 12, 1},
               {1997, 12, 31},
               {1998, 1, 1},
               {1998, 1, 31},
               {1998, 2, 1}
             ]
    end

    test "Every 18 months on days 10–15 for 10 occurrences" do
      # RRULE:FREQ=MONTHLY;INTERVAL=18;COUNT=10;BYMONTHDAY=10,11,12,13,14,15
      # DTSTART = 1997-09-10
      rule = %Rule{
        freq: :month,
        interval: 18,
        bymonthday: [10, 11, 12, 13, 14, 15],
        count: 10
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-09-10")

      assert ymd(occ) == [
               {1997, 9, 10},
               {1997, 9, 11},
               {1997, 9, 12},
               {1997, 9, 13},
               {1997, 9, 14},
               {1997, 9, 15},
               {1999, 3, 10},
               {1999, 3, 11},
               {1999, 3, 12},
               {1999, 3, 13}
             ]
    end

    test "Every Tuesday every other month" do
      # RRULE:FREQ=MONTHLY;INTERVAL=2;BYDAY=TU;COUNT=18
      # DTSTART = 1997-09-02
      rule = %Rule{freq: :month, interval: 2, byday: [{nil, 2}], count: 18}
      {:ok, occ} = Expander.expand(rule, ~o"1997-09-02")

      # 4 Tuesdays in Sep, 5 in Nov, 4 in Jan, 5 in Mar — first 18:
      assert ymd(occ) == [
               {1997, 9, 2},
               {1997, 9, 9},
               {1997, 9, 16},
               {1997, 9, 23},
               {1997, 9, 30},
               {1997, 11, 4},
               {1997, 11, 11},
               {1997, 11, 18},
               {1997, 11, 25},
               {1998, 1, 6},
               {1998, 1, 13},
               {1998, 1, 20},
               {1998, 1, 27},
               {1998, 3, 3},
               {1998, 3, 10},
               {1998, 3, 17},
               {1998, 3, 24},
               {1998, 3, 31}
             ]
    end
  end

  ## =============================================================
  ## Yearly
  ## =============================================================

  describe "Yearly" do
    test "Yearly in June and July for 10 occurrences" do
      # RRULE:FREQ=YEARLY;COUNT=10;BYMONTH=6,7
      # DTSTART = 1997-06-10
      rule = %Rule{freq: :year, interval: 1, bymonth: [6, 7], count: 10}
      {:ok, occ} = Expander.expand(rule, ~o"1997-06-10")

      assert ymd(occ) == [
               {1997, 6, 10},
               {1997, 7, 10},
               {1998, 6, 10},
               {1998, 7, 10},
               {1999, 6, 10},
               {1999, 7, 10},
               {2000, 6, 10},
               {2000, 7, 10},
               {2001, 6, 10},
               {2001, 7, 10}
             ]
    end

    test "Every other year in Jan/Feb/Mar for 10 occurrences" do
      # RRULE:FREQ=YEARLY;INTERVAL=2;COUNT=10;BYMONTH=1,2,3
      # DTSTART = 1997-03-10
      rule = %Rule{freq: :year, interval: 2, bymonth: [1, 2, 3], count: 10}
      {:ok, occ} = Expander.expand(rule, ~o"1997-03-10")

      assert ymd(occ) == [
               {1997, 3, 10},
               {1999, 1, 10},
               {1999, 2, 10},
               {1999, 3, 10},
               {2001, 1, 10},
               {2001, 2, 10},
               {2001, 3, 10},
               {2003, 1, 10},
               {2003, 2, 10},
               {2003, 3, 10}
             ]
    end

    test "Every Thursday in March, 3 years" do
      # RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=TH;COUNT=11
      # DTSTART = 1997-03-13 (Thursday)
      rule = %Rule{
        freq: :year,
        interval: 1,
        bymonth: [3],
        byday: [{nil, 4}],
        count: 11
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-03-13")

      assert ymd(occ) == [
               {1997, 3, 13},
               {1997, 3, 20},
               {1997, 3, 27},
               {1998, 3, 5},
               {1998, 3, 12},
               {1998, 3, 19},
               {1998, 3, 26},
               {1999, 3, 4},
               {1999, 3, 11},
               {1999, 3, 18},
               {1999, 3, 25}
             ]
    end

    test "Every Thursday in June/July/August, 1 year" do
      # RRULE:FREQ=YEARLY;BYDAY=TH;BYMONTH=6,7,8;COUNT=14
      # DTSTART = 1997-06-05 (Thursday)
      rule = %Rule{
        freq: :year,
        interval: 1,
        bymonth: [6, 7, 8],
        byday: [{nil, 4}],
        count: 14
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-06-05")

      # June 5, 12, 19, 26; July 3, 10, 17, 24, 31; Aug 7, 14, 21, 28 = 13
      # … need 14, so the 14th falls on June 4, 1998.
      assert Enum.count(occ) == 14
      assert hd(occ).from.time == [year: 1997, month: 6, day: 5]
    end

    test "Every Friday the 13th, bounded" do
      # RRULE:FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13;COUNT=5
      # DTSTART = 1998-02-13 (first Friday the 13th of 1998)
      rule = %Rule{
        freq: :month,
        interval: 1,
        byday: [{nil, 5}],
        bymonthday: [13],
        count: 5
      }

      {:ok, occ} = Expander.expand(rule, ~o"1998-02-13")

      # RFC lists 1998-02-13, 1998-03-13, 1998-11-13, 1999-08-13, 2000-10-13.
      assert ymd(occ) == [
               {1998, 2, 13},
               {1998, 3, 13},
               {1998, 11, 13},
               {1999, 8, 13},
               {2000, 10, 13}
             ]
    end

    test "First Saturday following a first Sunday of the month" do
      # RRULE:FREQ=MONTHLY;BYDAY=SA;BYMONTHDAY=7,8,9,10,11,12,13;COUNT=10
      # A Saturday on day 7–13 is the first Saturday after the first
      # Sunday of the month. DTSTART = 1997-09-13.
      rule = %Rule{
        freq: :month,
        interval: 1,
        byday: [{nil, 6}],
        bymonthday: [7, 8, 9, 10, 11, 12, 13],
        count: 10
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-09-13")

      assert ymd(occ) == [
               {1997, 9, 13},
               {1997, 10, 11},
               {1997, 11, 8},
               {1997, 12, 13},
               {1998, 1, 10},
               {1998, 2, 7},
               {1998, 3, 7},
               {1998, 4, 11},
               {1998, 5, 9},
               {1998, 6, 13}
             ]
    end

    test "US Presidential Election Day — every 4 years, first Tue after a Mon in Nov" do
      # RRULE:FREQ=YEARLY;INTERVAL=4;BYMONTH=11;BYDAY=TU;BYMONTHDAY=2,3,4,5,6,7,8
      # DTSTART = 1996-11-05
      rule = %Rule{
        freq: :year,
        interval: 4,
        bymonth: [11],
        byday: [{nil, 2}],
        bymonthday: [2, 3, 4, 5, 6, 7, 8],
        count: 3
      }

      {:ok, occ} = Expander.expand(rule, ~o"1996-11-05")

      assert ymd(occ) == [{1996, 11, 5}, {2000, 11, 7}, {2004, 11, 2}]
    end

    test "Monday of week number 20, 3 years" do
      # RRULE:FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO
      # DTSTART = 1997-05-12
      # ==> (1997 9:00 AM EDT) May 12
      #     (1998 9:00 AM EDT) May 11
      #     (1999 9:00 AM EDT) May 17
      rule = %Rule{freq: :year, interval: 1, byweekno: [20], byday: [{nil, 1}], count: 3}

      {:ok, occ} = Expander.expand(rule, ~o"1997-05-12")

      assert ymd(occ) == [{1997, 5, 12}, {1998, 5, 11}, {1999, 5, 17}]
    end
  end

  ## =============================================================
  ## BYSETPOS
  ## =============================================================

  describe "BYSETPOS" do
    test "The 3rd instance into the month of Tue/Wed/Thu, 3 months" do
      # RRULE:FREQ=MONTHLY;COUNT=3;BYDAY=TU,WE,TH;BYSETPOS=3
      # DTSTART = 1997-09-04 (Thursday)
      rule = %Rule{
        freq: :month,
        interval: 1,
        byday: [{nil, 2}, {nil, 3}, {nil, 4}],
        bysetpos: [3],
        count: 3
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-09-04")

      assert ymd(occ) == [{1997, 9, 4}, {1997, 10, 7}, {1997, 11, 6}]
    end

    test "Second-to-last weekday of the month, 7 months" do
      # RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-2;COUNT=7
      # DTSTART = 1997-09-29 (Monday)
      rule = %Rule{
        freq: :month,
        interval: 1,
        byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}],
        bysetpos: [-2],
        count: 7
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-09-29")

      assert ymd(occ) == [
               {1997, 9, 29},
               {1997, 10, 30},
               {1997, 11, 27},
               {1997, 12, 30},
               {1998, 1, 29},
               {1998, 2, 26},
               {1998, 3, 30}
             ]
    end
  end

  ## =============================================================
  ## WKST — showing how week-start shifts weekly expansion
  ## =============================================================

  describe "WKST" do
    test "WKST=MO — every 2 weeks on Tue/Sun (default)" do
      # RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=MO
      # DTSTART = Tue 1997-08-05.
      # With WKST=MO, the week of Aug 5 is Mon Aug 4..Sun Aug 10.
      # BYDAY=TU,SU → Aug 5 (Tue), Aug 10 (Sun).
      # Next iteration (2 weeks later) anchors Tue Aug 19.
      # Week Mon Aug 18..Sun Aug 24 → Aug 19, Aug 24.
      rule = %Rule{
        freq: :week,
        interval: 2,
        byday: [{nil, 2}, {nil, 7}],
        wkst: 1,
        count: 4
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-08-05")

      assert ymd(occ) == [{1997, 8, 5}, {1997, 8, 10}, {1997, 8, 19}, {1997, 8, 24}]
    end

    test "WKST=SU — shifts the week boundary to Sunday-first" do
      # RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=SU
      # Week of Aug 5 (Tue) with WKST=SU is Sun Aug 3..Sat Aug 9.
      # BYDAY=TU,SU → Aug 3 (Sun), Aug 5 (Tue).
      # Next iteration anchors 2 weeks later. Different from MO case.
      rule = %Rule{
        freq: :week,
        interval: 2,
        byday: [{nil, 2}, {nil, 7}],
        wkst: 7,
        count: 4
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-08-05")

      assert [_, _, _, _] = occ

      # First occurrence is Aug 5 (the anchor), next is the Sun of its week (Aug 10 with SU-start).
      # Actually — the WKST=SU week of Aug 5 is Sun Aug 3..Sat Aug 9. Sunday in that week is Aug 3.
      # That precedes DTSTART, so it's dropped — leaving just Aug 5.
      # Second iteration (+2 weeks to Aug 19), WKST=SU week Sun Aug 17..Sat Aug 23:
      #   Sun Aug 17, Tue Aug 19 — 2 occurrences.
      # Third iteration (+2 weeks to Sep 2), WKST=SU week Sun Aug 31..Sat Sep 6:
      #   Sun Aug 31, Tue Sep 2.
      # Total: [Aug 5, Aug 17, Aug 19, Aug 31]. 4 occurrences.
      assert ymd(occ) == [{1997, 8, 5}, {1997, 8, 17}, {1997, 8, 19}, {1997, 8, 31}]
    end
  end

  ## =============================================================
  ## Edge cases — invalid dates, leap years
  ## =============================================================

  describe "Edge cases" do
    test "BYMONTHDAY=15,30 with FREQ=MONTHLY skips Feb 30 (invalid)" do
      # RRULE:FREQ=MONTHLY;BYMONTHDAY=15,30;COUNT=5
      # DTSTART = 1997-01-15 (a valid date matching the rule).
      rule = %Rule{
        freq: :month,
        interval: 1,
        bymonthday: [15, 30],
        count: 5
      }

      {:ok, occ} = Expander.expand(rule, ~o"1997-01-15")

      # Jan 15, Jan 30, Feb 15, (Feb 30 invalid — skip), Mar 15, Mar 30.
      assert ymd(occ) == [
               {1997, 1, 15},
               {1997, 1, 30},
               {1997, 2, 15},
               {1997, 3, 15},
               {1997, 3, 30}
             ]
    end

    test "Yearly at Feb 29, sparse across non-leap years" do
      rule = %Rule{
        freq: :year,
        interval: 1,
        bymonth: [2],
        bymonthday: [29],
        count: 3
      }

      {:ok, occ} = Expander.expand(rule, ~o"2020-02-29")
      assert ymd(occ) == [{2020, 2, 29}, {2024, 2, 29}, {2028, 2, 29}]
    end
  end
end
