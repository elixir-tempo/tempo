defmodule Tempo.RRuleTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{Cron, IntervalSet, RRule}

  # RFC 5545 rules lowered to Tempo recurrences
  # (`plans/architecture-redesign.md`, section 18): the examples of RFC 5545
  # §3.8.5.3 with the occurrences the RFC lists, and cron expressions.

  defp dates(text, from, options \\ []) do
    {:ok, rule} = RRule.parse(text, from: from)
    {:ok, set} = Tempo.to_interval(rule, options)

    IntervalSet.map(set, fn occurrence ->
      {Tempo.year(occurrence), Tempo.month(occurrence), Tempo.day(occurrence)}
    end)
  end

  describe "RFC 5545 §3.8.5.3" do
    test "daily for ten occurrences" do
      assert dates("FREQ=DAILY;COUNT=10", ~o"1997-09-02T09:00:00") ==
               for(d <- 2..11, do: {1997, 9, d})
    end

    test "weekly for ten occurrences takes the weekday of the start" do
      assert dates("FREQ=WEEKLY;COUNT=10", ~o"1997-09-02T09:00:00") ==
               [
                 {1997, 9, 2},
                 {1997, 9, 9},
                 {1997, 9, 16},
                 {1997, 9, 23},
                 {1997, 9, 30},
                 {1997, 10, 7},
                 {1997, 10, 14},
                 {1997, 10, 21},
                 {1997, 10, 28},
                 {1997, 11, 4}
               ]
    end

    test "every other week on Tuesday and Thursday" do
      assert dates("FREQ=WEEKLY;INTERVAL=2;COUNT=8;BYDAY=TU,TH", ~o"1997-09-02T09:00:00") ==
               [
                 {1997, 9, 2},
                 {1997, 9, 4},
                 {1997, 9, 16},
                 {1997, 9, 18},
                 {1997, 9, 30},
                 {1997, 10, 2},
                 {1997, 10, 14},
                 {1997, 10, 16}
               ]
    end

    test "monthly on the first Friday" do
      assert dates("FREQ=MONTHLY;COUNT=10;BYDAY=1FR", ~o"1997-09-05T09:00:00") ==
               [
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

    test "monthly on the second-to-last Monday" do
      assert dates("FREQ=MONTHLY;COUNT=6;BYDAY=-2MO", ~o"1997-09-22T09:00:00") ==
               [
                 {1997, 9, 22},
                 {1997, 10, 20},
                 {1997, 11, 17},
                 {1997, 12, 22},
                 {1998, 1, 19},
                 {1998, 2, 16}
               ]
    end

    test "monthly on the third-to-last day" do
      assert dates("FREQ=MONTHLY;BYMONTHDAY=-3;COUNT=4", ~o"1997-09-28T09:00:00") ==
               [{1997, 9, 28}, {1997, 10, 29}, {1997, 11, 28}, {1997, 12, 29}]
    end

    test "monthly on the second and fifteenth" do
      assert dates("FREQ=MONTHLY;COUNT=6;BYMONTHDAY=2,15", ~o"1997-09-02T09:00:00") ==
               [
                 {1997, 9, 2},
                 {1997, 9, 15},
                 {1997, 10, 2},
                 {1997, 10, 15},
                 {1997, 11, 2},
                 {1997, 11, 15}
               ]
    end

    test "yearly in June and July" do
      assert dates("FREQ=YEARLY;COUNT=6;BYMONTH=6,7", ~o"1997-06-10T09:00:00") ==
               [
                 {1997, 6, 10},
                 {1997, 7, 10},
                 {1998, 6, 10},
                 {1998, 7, 10},
                 {1999, 6, 10},
                 {1999, 7, 10}
               ]
    end

    test "every third year on the first, hundredth and two hundredth day" do
      assert dates("FREQ=YEARLY;INTERVAL=3;COUNT=6;BYYEARDAY=1,100,200", ~o"1997-01-01T09:00:00") ==
               [
                 {1997, 1, 1},
                 {1997, 4, 10},
                 {1997, 7, 19},
                 {2000, 1, 1},
                 {2000, 4, 9},
                 {2000, 7, 18}
               ]
    end

    test "Monday of week twenty" do
      assert dates("FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO;COUNT=3", ~o"1997-05-12T09:00:00") ==
               [{1997, 5, 12}, {1998, 5, 11}, {1999, 5, 17}]
    end

    test "the last weekday of the month" do
      assert dates(
               "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3",
               ~o"1997-09-29T09:00:00"
             ) ==
               [{1997, 9, 30}, {1997, 10, 31}, {1997, 11, 28}]
    end

    test "a monthly rule from the thirty-first passes over the shorter months" do
      assert dates("FREQ=MONTHLY;COUNT=4", ~o"2026-01-31") == [
               {2026, 1, 31},
               {2026, 3, 31},
               {2026, 5, 31},
               {2026, 7, 31}
             ]
    end

    test "until bounds the occurrences, and a window an endless rule" do
      assert dates("FREQ=DAILY;UNTIL=19970905", ~o"1997-09-02") == [
               {1997, 9, 2},
               {1997, 9, 3},
               {1997, 9, 4},
               {1997, 9, 5}
             ]

      assert dates("FREQ=YEARLY", ~o"2026-03-10", within: ~o"2026/2028") == [
               {2026, 3, 10},
               {2027, 3, 10},
               {2028, 3, 10}
             ]
    end

    test "an occurrence keeps the start's time of day and the event's length" do
      {:ok, rule} =
        RRule.parse("FREQ=MONTHLY;BYDAY=1WE;COUNT=2",
          from: ~o"2026-06-01T18:00",
          duration: ~o"PT2H"
        )

      {:ok, set} = Tempo.to_interval(rule)

      assert IntervalSet.map(set, &Tempo.to_iso8601!/1) == [
               "2026Y6M3DT18H0M/T20H0M",
               "2026Y7M1DT18H0M/T20H0M"
             ]
    end
  end

  describe "text" do
    test "a rule reads to the recurrence its ISO 8601-2 text reads to, and writes back" do
      {:ok, rule} = RRule.parse("FREQ=MONTHLY;BYDAY=2MO", from: ~o"2025-01-01")
      assert Tempo.from_iso8601("R/2025Y1M1D/P1M/FL1K2IN") == {:ok, rule}
      assert RRule.to_string(rule) == {:ok, "FREQ=MONTHLY;BYDAY=2MO"}

      assert RRule.to_string(~o"R/2026-06-01/P1M/FL{1,3,5}KT17H0MN") ==
               {:ok, "FREQ=MONTHLY;BYHOUR=17;BYMINUTE=0;BYDAY=MO,WE,FR"}

      assert RRule.to_string(RRule.parse!("FREQ=MONTHLY;BYDAY=1MO,3MO", from: ~o"2026-01-01")) ==
               {:ok, "FREQ=MONTHLY;BYDAY=1MO,3MO"}
    end

    test "what is no rule, or not supported, is an error" do
      for text <- [
            "BYMONTH=6",
            "FREQ=NONSENSE",
            "FREQ=DAILY;BOGUS=1",
            "FREQ=WEEKLY;BYDAY=ZZ",
            "FREQ=DAILY;COUNT=2;UNTIL=20260101",
            "FREQ=DAILY;WKST=SU",
            "FREQ=YEARLY;RSCALE=HEBREW"
          ] do
        assert {:error, %ArgumentError{}} = RRule.parse(text), text
      end

      assert {:error, %Tempo.ConversionError{reason: {:no_rrule, _}}} =
               RRule.to_string(~o"2026-06-15")

      assert {:error, %Tempo.ConversionError{reason: {:no_rrule, _}}} =
               RRule.to_string(~o"R/2026-01-01/P1Y/FL(easter)eN")
    end
  end

  describe "cron" do
    defp firings(expression, from, window) do
      {:ok, rule} = Cron.parse(expression, from: from)
      {:ok, set} = Tempo.to_interval(rule, within: window)
      IntervalSet.map(set, &Tempo.to_iso8601!/1)
    end

    test "fires at the minutes its fields name" do
      assert firings("*/15 * * * *", ~o"2026-01-05T09:05", ~o"2026-01-05T09") == [
               "2026Y1M5DT9H15M/T16M",
               "2026Y1M5DT9H30M/T31M",
               "2026Y1M5DT9H45M/T46M"
             ]

      assert firings("30 9 * * *", ~o"2026-01-05", ~o"2026-01-05/2026-01-06") == [
               "2026Y1M5DT9H30M/T31M",
               "2026Y1M6DT9H30M/T31M"
             ]

      assert Enum.count(firings("0 */2 * * *", ~o"2026-01-05", ~o"2026-01-05")) == 12
      assert Enum.count(firings("0 * * * 1", ~o"2026-01-05", ~o"2026-01-05/2026-01-11")) == 24
      assert Enum.count(firings("0 * 5 * *", ~o"2026-01-01", ~o"2026-01")) == 24
      assert Enum.count(firings("* * * * *", ~o"2026-01-05T09:00", ~o"2026-01-05T09")) == 60
    end

    test "names months and weekdays, and reads the aliases" do
      assert firings("0 0 * JAN MON", ~o"2026-01-01", ~o"2026-01") |> Enum.count() == 4

      assert firings("@daily", ~o"2026-01-05", ~o"2026-01-05/2026-01-06") == [
               "2026Y1M5DT0H0M/T1M",
               "2026Y1M6DT0H0M/T1M"
             ]

      assert firings("*/30 * * * * *", ~o"2026-01-05T09:00:00", ~o"2026-01-05T09:00") == [
               "2026Y1M5DT9H0M0S/T1S",
               "2026Y1M5DT9H0M30S/T31S"
             ]
    end

    test "a day of the month and a day of the week both restricted fire on either" do
      days =
        firings("0 9 13 * 5", ~o"2026-02-01", ~o"2026-02")
        |> Enum.map(&String.slice(&1, 0, 9))
        |> Enum.sort()

      assert "2026Y2M13" in days
      assert Enum.count(days) == 5
    end

    test "what is no cron expression is an error" do
      for text <- ["@reboot", "* * *", "61 * * * *", "* * * FOO *", "5L * * * *"] do
        assert {:error, %ArgumentError{}} = Cron.parse(text), text
      end
    end
  end
end
