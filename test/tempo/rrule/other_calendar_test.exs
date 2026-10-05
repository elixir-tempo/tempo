defmodule Tempo.RRule.OtherCalendarTest do
  use ExUnit.Case, async: true

  # An RRULE is read in the Gregorian calendar (RFC 5545). A recurrence of
  # another calendar is written where a reader of the rule finds the
  # occurrences the recurrence has, and that is the measure here: each rule
  # written is read again in the Gregorian calendar, from the Gregorian date
  # of the recurrence's start, and its occurrences are compared with the
  # recurrence's own, each as the Gregorian date `Date.convert!/2` gives its
  # day and its time of day. The Gregorian reading is held to RFC 5545's own
  # examples by `Tempo.RRule.Rfc5545ConformanceTest`.
  #
  # What is not written, a rule that steps or selects by a month, a year, a
  # week of the year or a day of one, is refused by name and is held by
  # `Tempo.NotBuiltTest`.

  alias Calendrical.Hebrew
  alias Calendrical.ISOWeek
  alias Calendrical.Julian.March25
  alias Calendrical.NRF
  alias Calendrical.Persian
  alias Calendrical.Reform.England
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  # A calendar of months, one whose year turns within a month, one with days
  # missing (England's September 1752, which the weeks from 30 August cross),
  # and two calendars of weeks: NRF's begin on Sunday and ISO 8601's on Monday.
  @starts [
    {Hebrew, "5786Y6M1D"},
    {Persian, "1405Y1M1D"},
    {March25, "1750Y3M20D"},
    {England, "1752Y8M30D"},
    {NRF, "2026Y25W"},
    {NRF, "2026Y25W4K"},
    {ISOWeek, "2026Y25W"},
    {ISOWeek, "2026Y25W3K"}
  ]

  # A step by weeks, days and hours, alone and with each selection an RRULE
  # of another calendar is written with: days of the week, the last of them,
  # a position among them and times of day.
  @rules ~w(P1W P1W/FL3KN P1W/FL{1,7}KN P1W/FL-1KN P1W/FL{1,2}K1IN P1W/FL{1,7}K-1IN
            P1W/FLT{9,17}HN P2W P2W/FL3KN P2W/FL{1,7}KN P2W/FL-1KN P2W/FL{1,2}K1IN
            P2W/FL{1,7}K-1IN P2W/FL{2,4}KT{9,17}HN P3D P3D/FL{1..5}KN P1D/FL{1,7}KN
            P1D/FLT{9,17}HN PT6H PT6H/FL{1..5}KN)

  # A rule read with each week start, and with none.
  @read ["", ";WKST=MO", ";WKST=WE", ";WKST=SU"]

  defp read(text, calendar), do: Tempo.from_iso8601!(text, calendar)

  # When each occurrence of a recurrence starts.
  defp starts(recurrence) do
    {:ok, set} = Tempo.to_interval(recurrence)
    for occurrence <- IntervalSet.members(set), do: start(Interval.from(occurrence))
  end

  defp start(%Tempo{time: time} = value) do
    {gregorian_date(value), for({unit, count} <- time, unit in [:hour, :minute], do: count)}
  end

  defp gregorian_date(%Tempo{} = value) do
    {:ok, date} = value |> day() |> Tempo.to_date()
    Date.convert!(date, Calendar.ISO)
  end

  # The day a value starts in: the first day of a week, and the day a time
  # of day is in.
  defp day(%Tempo{} = value) do
    case Tempo.extend_resolution(value, :day) do
      %Tempo{} = day -> Tempo.trunc(day, :day)
      {:error, _finer_than_a_day} -> Tempo.trunc(value, :day)
    end
  end

  # The start an RFC 5545 reader is given with a rule: the Gregorian date of
  # the recurrence's first day.
  defp gregorian_start(%Interval{from: from}), do: Tempo.from_date(gregorian_date(from))

  # The occurrences a written rule has for a reader of RFC 5545.
  defp read_in_gregorian(written, recurrence) do
    {:ok, rule} = RRule.parse(written, from: gregorian_start(recurrence))
    starts(rule)
  end

  describe "a rule written from a recurrence of another calendar" do
    for {calendar, start} <- @starts do
      test "reads in the Gregorian calendar as the recurrence from #{start} of #{inspect(calendar)}" do
        for rule <- @rules do
          recurrence = read("R6/#{unquote(start)}/#{rule}", unquote(calendar))
          {:ok, written} = RRule.to_string(recurrence)

          assert {rule, written, read_in_gregorian(written, recurrence)} ==
                   {rule, written, starts(recurrence)}
        end
      end

      test "reads so when the rule was read with a week start from #{start} of #{inspect(calendar)}" do
        for week_start <- @read do
          text = "COUNT=6;FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO" <> week_start
          {:ok, recurrence} = RRule.parse(text, from: read(unquote(start), unquote(calendar)))
          {:ok, written} = RRule.to_string(recurrence)

          assert {text, written, read_in_gregorian(written, recurrence)} ==
                   {text, written, starts(recurrence)}
        end
      end
    end
  end

  describe "the week start of a rule written from a calendar of weeks" do
    test "is the day the calendar's weeks begin, where that is not Monday" do
      assert RRule.to_string(read("R/2026Y25W/P1W/FL3KN", NRF)) ==
               {:ok, "FREQ=WEEKLY;BYDAY=TU;WKST=SU"}

      assert RRule.to_string(read("R/2026Y25W/P2W/FL{1,2}KN", NRF)) ==
               {:ok, "FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=SU"}

      assert RRule.to_string(read("R/2026Y25W/P1W/FL3KN", ISOWeek)) ==
               {:ok, "FREQ=WEEKLY;BYDAY=WE"}
    end

    test "is written last, after a time of day" do
      assert RRule.to_string(read("R/2026Y25W/P1W/FL{2,4}KT{9,17}HN", NRF)) ==
               {:ok, "FREQ=WEEKLY;BYDAY=MO,WE;BYHOUR=9,17;WKST=SU"}
    end

    test "is not written for a rule that has no selection or does not step by weeks" do
      assert RRule.to_string(read("R/2026Y25W/P2W", NRF)) == {:ok, "FREQ=WEEKLY;INTERVAL=2"}

      assert RRule.to_string(read("R/2026Y25W1K/P1D/FL{1..5}KN", NRF)) ==
               {:ok, "FREQ=DAILY;BYDAY=SU,MO,TU,WE,TH"}
    end

    test "replaces the one a rule was read with, which a calendar of weeks does not count by" do
      for week_start <- @read do
        {:ok, recurrence} =
          RRule.parse("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO" <> week_start,
            from: read("2026Y25W", NRF)
          )

        assert {week_start, RRule.to_string(recurrence)} ==
                 {week_start, {:ok, "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,SU;WKST=SU"}}
      end

      {:ok, recurrence} =
        RRule.parse("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=SU", from: read("2026Y25W", ISOWeek))

      assert RRule.to_string(recurrence) == {:ok, "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,SU"}
    end
  end

  describe "the week start of a rule written from a calendar of months" do
    test "is the one the rule holds, by which its weeks are counted" do
      {:ok, recurrence} =
        RRule.parse("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=SU", from: read("5786Y6M1D", Hebrew))

      assert RRule.to_string(recurrence) == {:ok, "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,SU;WKST=SU"}

      assert RRule.to_string(read("R/5786Y6M1D/P2W/FL{1,7}KN", Hebrew)) ==
               {:ok, "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,SU"}
    end
  end
end
