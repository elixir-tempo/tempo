defmodule Tempo.RRuleByMonthExpansionTest do
  @moduledoc """
  RFC 5545 BYMONTH expansion must not let DTSTART's day-of-month
  filter or select occurrences: when BYMONTHDAY/BYDAY determine the
  day, results are identical from any DTSTART; when nothing later
  sets the day, DTSTART's day clamps to each occurrence's month —
  per occurrence, leap-aware, in every calendar.
  """
  use ExUnit.Case, async: true

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  defp expand(rule, %Date{} = from), do: expand(rule, Tempo.from_elixir(from))

  defp expand(rule, from) do
    parsed = RRule.parse!(rule, from: from)
    {:ok, set} = Tempo.to_interval(parsed)

    set
    |> IntervalSet.to_list()
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

  describe "no later part sets the day — DTSTART's day clamps per occurrence" do
    test "a 31st clamps to February's end, restoring the 29th in leap years" do
      assert expand("FREQ=YEARLY;BYMONTH=2;COUNT=4", ~D[2025-01-31]) ==
               [~D[2025-02-28], ~D[2026-02-28], ~D[2027-02-28], ~D[2028-02-29]]
    end

    test "a 31st clamps to a 30-day month's end" do
      assert expand("FREQ=YEARLY;BYMONTH=4;COUNT=2", ~D[2026-01-31]) ==
               [~D[2026-04-30], ~D[2027-04-30]]
    end

    test "clamping gives identical results from the 29th through 31st" do
      expected = expand("FREQ=YEARLY;BYMONTH=2;COUNT=3", ~D[2026-01-29])

      for day <- [30, 31] do
        assert expand("FREQ=YEARLY;BYMONTH=2;COUNT=3", Date.new!(2026, 1, day)) == expected
      end
    end

    test "a valid day passes through unclamped" do
      assert expand("FREQ=YEARLY;BYMONTH=2;COUNT=3", ~D[2026-01-15]) ==
               [~D[2026-02-15], ~D[2027-02-15], ~D[2028-02-15]]
    end
  end

  describe "leap-day DTSTART with plain frequencies" do
    test "yearly from February 29 clamps per occurrence and restores the leap day" do
      assert expand("FREQ=YEARLY;COUNT=5", ~D[2024-02-29]) ==
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

    defp hebrew_expand(rule, iso) do
      parsed = RRule.parse!(rule, from: Tempo.from_iso8601!(iso, Calendrical.Hebrew))
      {:ok, set} = Tempo.to_interval(parsed)

      set
      |> IntervalSet.to_list()
      |> Enum.map(&Tempo.to_iso8601(Interval.from(&1)))
    end

    test "a day-30 DTSTART clamps to each year's own month length" do
      assert hebrew_expand("FREQ=YEARLY;BYMONTH=2;COUNT=4", "5786-05-30") ==
               ["5787Y2M30D", "5788Y2M30D", "5789Y2M29D", "5790Y2M29D"]
    end

    test "BYMONTHDAY overrides a day-30 DTSTART in every year" do
      assert hebrew_expand("FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=10;COUNT=3", "5786-05-30") ==
               ["5787Y4M10D", "5788Y4M10D", "5789Y4M10D"]
    end

    test "a leap month only occurs in leap years — dropped, not clamped" do
      assert hebrew_expand("FREQ=YEARLY;BYMONTH=13;BYMONTHDAY=5;COUNT=3", "5786-05-30") ==
               ["5787Y13M5D", "5790Y13M5D", "5793Y13M5D"]
    end
  end
end
