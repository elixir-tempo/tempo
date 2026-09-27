defmodule Tempo.WeekDateRolloverTest do
  @moduledoc """
  Edge cases for ISO 8601 week-date (`YYYY-Www-D`) to calendar-date
  conversion. A `W` week is an ISO 8601 week in every calendar, and
  `Calendrical.ISOWeek` (the sigil's `W` modifier) holds its dates as
  weeks. A `w` week, Tempo's extension, is the calendar's own:
  `Calendrical.Gregorian` numbers its weeks from the one holding
  January 1.

  ISO 8601 §5.2.3: week 01 is the week containing the first Thursday
  of the calendar year (equivalently, the week containing January 4).
  Consequences:

  * Week 01 of year Y can start in December of year Y-1. The Monday
    of `2020-W01` is **2019-12-30** — three days before the calendar
    year begins.

  * Week 53 exists only when January 1 is a Thursday, or when the
    year is a leap year and January 1 is a Wednesday. 2020 and 2015
    are both 53-week years; 2021 is not.

  * Week 01 of the year *after* a 53-week year can start four days
    after January 1. The Monday of `2021-W01` is **2021-01-04** —
    because January 1-3 2021 fall in `2020-W53`.

  These two boundaries are where naive "week × 7 + day" arithmetic
  breaks, and where calendar-date libraries historically disagree.
  These tests pin down Tempo's behaviour against hand-computed
  answers.

  """

  use ExUnit.Case, async: true
  import Tempo.Sigils

  describe "2020 week-date rollover (2020 is a 53-week year)" do
    test "W01-1 rolls back to the previous calendar year" do
      assert Tempo.to_calendar(~o"2020-W01-1"W, Calendrical.Gregorian) == {:ok, ~o"2019-12-30"}
    end

    test "W01-2 rolls back to the previous calendar year" do
      assert Tempo.to_calendar(~o"2020-W01-2"W, Calendrical.Gregorian) == {:ok, ~o"2019-12-31"}
    end

    test "W01-3 is the first day of the calendar year" do
      assert Tempo.to_calendar(~o"2020-W01-3"W, Calendrical.Gregorian) == {:ok, ~o"2020-01-01"}
    end

    test "W01-7 is the last day of week 1" do
      assert Tempo.to_calendar(~o"2020-W01-7"W, Calendrical.Gregorian) == {:ok, ~o"2020-01-05"}
    end

    test "W52-7 is the last day of week 52" do
      assert Tempo.to_calendar(~o"2020-W52-7"W, Calendrical.Gregorian) == {:ok, ~o"2020-12-27"}
    end
  end

  describe "2021 week-date rollover (follows a 53-week year)" do
    # Jan 1-3 2021 belong to 2020-W53 (Fri, Sat, Sun). 2021-W01
    # therefore starts on Monday Jan 4 — four days into the
    # calendar year.
    test "W01-1 starts Jan 4 when previous year has 53 weeks" do
      assert Tempo.to_calendar(~o"2021-W01-1"W, Calendrical.Gregorian) == {:ok, ~o"2021-01-04"}
    end

    test "W52-5 is Dec 31 in a 52-week year" do
      assert Tempo.to_calendar(~o"2021-W52-5"W, Calendrical.Gregorian) == {:ok, ~o"2021-12-31"}
    end
  end

  describe "2015 week-date rollover (2015 is a 53-week year)" do
    test "W01-4 is the first Thursday (= Jan 1 rule)" do
      assert Tempo.to_calendar(~o"2015-W01-4"W, Calendrical.Gregorian) == {:ok, ~o"2015-01-01"}
    end

    test "W53-7 is the last day of W53 in a 53-week year" do
      assert Tempo.to_calendar(~o"2015-W53-7"W, Calendrical.Gregorian) == {:ok, ~o"2016-01-03"}
    end

    test "W53-1 is the Monday of the 53rd week" do
      assert Tempo.to_calendar(~o"2015-W53-1"W, Calendrical.Gregorian) == {:ok, ~o"2015-12-28"}
    end
  end

  describe "canonical mid-year week-dates (no rollover)" do
    test "W24-3 is unambiguous" do
      assert Tempo.to_calendar(~o"2020-W24-3"W, Calendrical.Gregorian) == {:ok, ~o"2020-06-10"}
    end

    test "the Thursday of any week shares its ISO week-year with the calendar year" do
      # 2020-W01-4 is Jan 2, 2020 — Thursday; 2020-06-15 is in W25,
      # etc. Pins down one sample per quarter so a regression in
      # week-to-date arithmetic surfaces fast.
      assert Tempo.to_calendar(~o"2020-W01-4"W, Calendrical.Gregorian) == {:ok, ~o"2020-01-02"}
      assert Tempo.to_calendar(~o"2020-W14-4"W, Calendrical.Gregorian) == {:ok, ~o"2020-04-02"}
      assert Tempo.to_calendar(~o"2020-W27-4"W, Calendrical.Gregorian) == {:ok, ~o"2020-07-02"}
      assert Tempo.to_calendar(~o"2020-W40-4"W, Calendrical.Gregorian) == {:ok, ~o"2020-10-01"}
    end
  end

  describe "the default calendar's W weeks are ISO 8601's" do
    test "week 1 is the week holding January 4" do
      assert Tempo.to_date(~o"2023-W01-1") == {:ok, ~D[2023-01-02]}
    end

    test "2026 has a week 53 and 2023 does not" do
      assert {:ok, _week} = Tempo.from_iso8601("2026-W53")
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2023-W53")
    end
  end

  describe "a calendar week (w) is Calendrical.Gregorian's own" do
    # Week 1 holds January 1 and weeks run Monday to Sunday, so 2023 has
    # 53 weeks where ISO 8601 gives it 52, and 2026 52 where ISO gives
    # it 53.
    test "week 1 is the week holding January 1" do
      assert ~o"2023Y1w1K" == ~o"2022-12-26"
    end

    test "2023 has a week 53 and 2026 does not" do
      assert {:ok, _week} = Tempo.from_iso8601("2023Y53w")
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026Y53w")
    end

    test "a week alone is the span of its seven days" do
      assert ~o"2027Y1w" == ~o"2026-12-28/2027-01-04"
    end
  end

  describe "a calendar week (w) in a calendar that numbers weeks within its year" do
    # Hebrew weeks run from Sunday to Shabbat. 1 Tishri 5787 is a Saturday,
    # so 5787's week 1 is that one day and week 2 runs from Sunday 2 Tishri
    # to Shabbat 8 Tishri; the year ends on a Friday, six days into its
    # week 56.
    test "a week cut short at the start or end of its year spans only its own days" do
      assert Tempo.from_iso8601!("5787Y1w[u-ca=hebrew]") ==
               Tempo.from_iso8601!("5787Y1M1D/2D[u-ca=hebrew]")

      assert Tempo.from_iso8601!("5787Y2w[u-ca=hebrew]") ==
               Tempo.from_iso8601!("5787Y1M2D/9D[u-ca=hebrew]")

      assert Tempo.from_iso8601!("5787Y56w[u-ca=hebrew]") ==
               Tempo.from_iso8601!("5787Y13M24D/5788Y1M1D[u-ca=hebrew]")

      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("5787Y57w[u-ca=hebrew]")
    end

    test "a day of the week is ISO 8601's, and a short week has only its own" do
      # Saturday (6K) is 1 Tishri; there is no Monday (1K) in week 1
      assert Tempo.from_iso8601!("5787Y1w6K[u-ca=hebrew]") ==
               Tempo.from_iso8601!("5787Y1M1D[u-ca=hebrew]")

      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("5787Y1w1K[u-ca=hebrew]")

      # Sunday (7K) opens the Hebrew week 2
      assert Tempo.from_iso8601!("5787Y2w7K[u-ca=hebrew]") ==
               Tempo.from_iso8601!("5787Y1M2D[u-ca=hebrew]")
    end

    test "Julian weeks run from Monday within the Julian year" do
      # 1 January 2026 (Julian) is a Wednesday
      assert Tempo.from_iso8601!("2026Y1w[u-ca=julian]") ==
               Tempo.from_iso8601!("2026Y1M1D/6D[u-ca=julian]")

      assert Tempo.from_iso8601!("2026Y1w3K[u-ca=julian]") ==
               Tempo.from_iso8601!("2026Y1M1D[u-ca=julian]")
    end
  end
end
