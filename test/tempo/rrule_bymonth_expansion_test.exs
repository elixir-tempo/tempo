defmodule Tempo.RRuleByMonthExpansionTest do
  @moduledoc """
  RFC 5545 BYMONTH expansion must not let DTSTART's day-of-month
  filter or select occurrences: when BYMONTHDAY/BYDAY determine the
  day, results are identical from any DTSTART. When nothing later
  sets the day it is DTSTART's: a rule read from an RRULE states it
  (ISO 8601-2 Annex C.3) and passes over a month that lacks it, as
  RFC 5545 does, and an ISO 8601 recurrence keeps the last day of
  such a month — per occurrence, leap-aware, in every calendar.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  defp expand(rule, from, options \\ [])

  defp expand(rule, %Date{} = from, options), do: expand(rule, Tempo.from_elixir(from), options)
  defp expand(rule, from, options), do: dates(RRule.parse!(rule, from: from), options)

  # The day each occurrence of a recurrence starts on.
  defp dates(recurrence, options \\ []) do
    {:ok, set} = Tempo.to_interval(recurrence, options)

    set
    |> IntervalSet.members()
    |> Enum.map(&(&1 |> Interval.from() |> Tempo.to_date() |> elem(1)))
  end

  @late_days [28, 29, 30, 31]

  describe "BYDAY sets the day — DTSTART's day is irrelevant" do
    test "the RFC Thanksgiving example" do
      assert expand("FREQ=YEARLY;BYDAY=4TH;BYMONTH=11;COUNT=3", ~D[1997-11-06]) ==
               [~D[1997-11-27], ~D[1998-11-26], ~D[1999-11-25]]
    end

    test "identical results from the 28th through 31st of months before the target" do
      expected = [~D[2026-11-26], ~D[2027-11-25], ~D[2028-11-23]]

      for month <- [1, 3, 8], day <- @late_days do
        from = Date.new!(2026, month, day)

        assert expand("FREQ=YEARLY;BYDAY=4TH;BYMONTH=11;COUNT=3", from) == expected,
               "diverged from DTSTART #{from}"
      end
    end

    test "a DTSTART after the target month starts the following year" do
      assert expand("FREQ=YEARLY;BYDAY=4TH;BYMONTH=11;COUNT=3", ~D[2026-12-31]) ==
               [~D[2027-11-25], ~D[2028-11-23], ~D[2029-11-22]]
    end
  end

  describe "BYMONTHDAY names the day outright — the silent-wrong-answer case" do
    test "identical Februaries from the 28th through 31st" do
      # From the 29th this used to return leap years only — real
      # February 14ths in quietly the wrong years.
      expected = [~D[2027-02-14], ~D[2028-02-14], ~D[2029-02-14]]

      for day <- @late_days do
        from = Date.new!(2026, 8, day)

        assert expand("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=14;COUNT=3", from) == expected,
               "diverged from DTSTART #{from}"
      end
    end

    test "February-targeting rule from a leap-day DTSTART" do
      assert expand("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=14;COUNT=3", ~D[2024-02-29]) ==
               [~D[2025-02-14], ~D[2026-02-14], ~D[2027-02-14]]
    end
  end

  describe "no later part sets the day — a rule read from an RRULE passes over a month without it" do
    test "a 31st is no day of February, and a 29th one of its leap years" do
      assert expand("FREQ=YEARLY;BYMONTH=2", ~D[2025-01-31], within: ~o"2025Y/2035Y") == []

      assert expand("FREQ=YEARLY;BYMONTH=2;COUNT=3", ~D[2025-01-29]) ==
               [~D[2028-02-29], ~D[2032-02-29], ~D[2036-02-29]]
    end

    test "a 31st is no day of a 30-day month" do
      assert expand("FREQ=YEARLY;BYMONTH=4", ~D[2026-01-31], within: ~o"2026Y/2036Y") == []

      assert expand("FREQ=YEARLY;BYMONTH=4,5;COUNT=2", ~D[2026-01-31]) ==
               [~D[2026-05-31], ~D[2027-05-31]]
    end

    test "a valid day is listed in every year" do
      assert expand("FREQ=YEARLY;BYMONTH=2;COUNT=3", ~D[2026-01-15]) ==
               [~D[2026-02-15], ~D[2027-02-15], ~D[2028-02-15]]
    end
  end

  describe "no later part sets the day — an ISO 8601 recurrence keeps the month's last day" do
    test "a 31st is February's end, the 29th in leap years" do
      assert dates(~o"R4/2025-01-31/P1Y/FL2MN") ==
               [~D[2025-02-28], ~D[2026-02-28], ~D[2027-02-28], ~D[2028-02-29]]
    end

    test "a 31st is a 30-day month's end" do
      assert dates(~o"R2/2026-01-31/P1Y/FL4MN") == [~D[2026-04-30], ~D[2027-04-30]]
    end

    test "the 29th through the 31st give identical results" do
      expected = dates(~o"R3/2026-01-29/P1Y/FL2MN")

      for day <- [30, 31] do
        assert dates(Tempo.from_iso8601!("R3/2026-01-#{day}/P1Y/FL2MN")) == expected
      end
    end

    test "a valid day passes through" do
      assert dates(~o"R3/2026-01-15/P1Y/FL2MN") ==
               [~D[2026-02-15], ~D[2027-02-15], ~D[2028-02-15]]
    end
  end

  describe "leap-day DTSTART with plain frequencies" do
    test "a yearly rule read from an RRULE lists the leap years" do
      assert expand("FREQ=YEARLY;COUNT=3", ~D[2024-02-29]) ==
               [~D[2024-02-29], ~D[2028-02-29], ~D[2032-02-29]]
    end

    test "a yearly ISO 8601 recurrence keeps February's last day and restores the leap day" do
      assert dates(~o"R5/2024-02-29/P1Y") ==
               [~D[2024-02-29], ~D[2025-02-28], ~D[2026-02-28], ~D[2027-02-28], ~D[2028-02-29]]
    end

    test "a BYMONTH move off February frees the leap day entirely" do
      assert expand("FREQ=YEARLY;BYMONTH=8;COUNT=2", ~D[2024-02-29]) ==
               [~D[2024-08-29], ~D[2025-08-29]]
    end
  end

  describe "unaffected shapes stay exact from a 31st" do
    test "weekly, monthly-ordinal, and monthly-monthday shapes" do
      assert expand("FREQ=WEEKLY;BYDAY=MO;COUNT=2", ~D[2026-08-31]) ==
               [~D[2026-08-31], ~D[2026-09-07]]

      assert expand("FREQ=MONTHLY;BYDAY=2FR;COUNT=2", ~D[2026-08-31]) ==
               [~D[2026-09-11], ~D[2026-10-09]]

      assert expand("FREQ=MONTHLY;BYMONTHDAY=13;COUNT=2", ~D[2026-08-31]) ==
               [~D[2026-09-13], ~D[2026-10-13]]
    end
  end

  describe "variable-length months and leap months (Hebrew calendar)" do
    # Cheshvan (month 2) has 29 or 30 days depending on the year;
    # month 13 exists only in leap years (5787, 5790, 5793 here).

    defp hebrew_expand(rule, iso),
      do: starts(RRule.parse!(rule, from: Tempo.from_iso8601!(iso, Hebrew)))

    defp starts(recurrence) do
      {:ok, set} = Tempo.to_interval(recurrence)

      set
      |> IntervalSet.members()
      |> Enum.map(&Tempo.to_iso8601!(Interval.from(&1)))
    end

    test "a day-30 DTSTART is listed in the years whose month has thirty days" do
      assert hebrew_expand("FREQ=YEARLY;BYMONTH=2;COUNT=4", "5786-05-30") ==
               [
                 "5787Y2M30D[u-ca=hebrew]",
                 "5788Y2M30D[u-ca=hebrew]",
                 "5791Y2M30D[u-ca=hebrew]",
                 "5794Y2M30D[u-ca=hebrew]"
               ]
    end

    test "an ISO 8601 recurrence keeps each year's own month length" do
      assert starts(Tempo.from_iso8601!("R4/5786-05-30/P1Y/FL2MN", Hebrew)) ==
               [
                 "5787Y2M30D[u-ca=hebrew]",
                 "5788Y2M30D[u-ca=hebrew]",
                 "5789Y2M29D[u-ca=hebrew]",
                 "5790Y2M29D[u-ca=hebrew]"
               ]
    end

    test "BYMONTHDAY overrides a day-30 DTSTART in every year" do
      assert hebrew_expand("FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=10;COUNT=3", "5786-05-30") ==
               ["5787Y4M10D[u-ca=hebrew]", "5788Y4M10D[u-ca=hebrew]", "5789Y4M10D[u-ca=hebrew]"]
    end

    test "a leap month only occurs in leap years — dropped, not clamped" do
      assert hebrew_expand("FREQ=YEARLY;BYMONTH=13;BYMONTHDAY=5;COUNT=3", "5786-05-30") ==
               ["5787Y13M5D[u-ca=hebrew]", "5790Y13M5D[u-ca=hebrew]", "5793Y13M5D[u-ca=hebrew]"]
    end
  end
end
