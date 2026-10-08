defmodule Tempo.Explain.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Explain
  alias Tempo.ICal
  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet
  alias Tempo.RRule

  doctest Tempo.Explain

  # Tests for `Tempo.Explain.explain/1` — structured prose
  # descriptions of Tempo values. Three formatters (`to_string`,
  # `to_ansi`, `to_iodata`) are exercised for the same structured
  # output.

  setup_all do
    Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
    :ok
  end

  # The first line of a value's explanation, parsed from ISO 8601 text.
  defp headline(iso), do: iso |> Tempo.from_iso8601!() |> first_line()
  defp headline(iso, calendar), do: iso |> Tempo.from_iso8601!(calendar) |> first_line()

  defp first_line(value), do: value |> Tempo.explain() |> String.split("\n") |> hd()

  describe "scalar Tempo" do
    test "a year is classified :anchored with headline, span, enumeration, hint" do
      exp = Explain.explain(~o"2022Y")
      assert exp.kind == :anchored
      tags = exp.parts |> Enum.map(&elem(&1, 0))
      assert :headline in tags
      assert :span in tags
      assert :enumeration in tags
      assert :hint in tags
    end

    test "the year 2022's headline mentions the year" do
      assert Tempo.explain(~o"2022Y") =~ "2022"
    end

    test "a year-month-day's headline reads like prose" do
      assert Tempo.explain(~o"2026-06-15") =~ "June 15, 2026"
    end

    test "a datetime's headline includes the time" do
      assert Tempo.explain(~o"2026-06-15T10:30") =~ "10:30"
    end

    test "a qualified year mentions the qualifier" do
      exp = Explain.explain(~o"2022Y?")
      tags = exp.parts |> Enum.map(&elem(&1, 0))
      assert :qualification in tags

      assert Tempo.explain(~o"2022Y?") =~ "uncertain"
    end
  end

  describe "week values" do
    test "a week is headlined as its week, with its span and the day it starts on" do
      prose = Tempo.explain(~o"2026-W25")

      assert prose =~ "Week 25 of 2026."
      assert prose =~ "Span: [2026-W25, 2026-W26).\nStarts on 2026-06-15."
      refute prose =~ "The year"
    end

    test "a week at either end of its year starts on the day it does, in whichever year" do
      assert Tempo.explain(~o"2026-W01") =~ "Span: [2026-W01, 2026-W02).\nStarts on 2025-12-29."
      assert Tempo.explain(~o"2026-W53") =~ "Span: [2026-W53, 2027-W01).\nStarts on 2026-12-28."

      # The measure: the Mondays of those weeks.
      assert Date.from_iso8601!("2025-12-29") |> Date.day_of_week() == 1
      assert :calendar.iso_week_number({2025, 12, 29}) == {2026, 1}
      assert :calendar.iso_week_number({2026, 12, 28}) == {2026, 53}
    end

    # In the Gregorian calendar a week and a day of it are the calendar date
    # they name, so it is explained as one. A week calendar's keep their terms.
    test "a Gregorian week date is explained as the calendar date it is" do
      day = Tempo.explain(Tempo.new!(year: 2026, week: 25, day_of_week: 2))

      assert day =~ "June 16, 2026."
      assert day =~ "Span: [2026-06-16, 2026-06-17)."
      assert day == Tempo.explain(~o"2026-W25-2")
    end

    test "a week calendar's values are written in its own notation" do
      assert Tempo.explain(~o"2026"W) =~ "Span: [2026, 2027)."

      week = Tempo.explain(~o"2026-W25"W)
      assert week =~ "Week 25 of 2026."
      assert week =~ "Span: [2026-W25, 2026-W26)."
      refute week =~ "Starts on"

      day = Tempo.explain(~o"2026-W25-2"W)
      assert day =~ "Tuesday of week 25 of 2026."
      assert day =~ "Span: [2026-W25-2, 2026-W25-3)."

      minute = Tempo.explain(~o"2026-W25-2T10:30"W)
      assert minute =~ "Tuesday of week 25 of 2026 at 10:30."
      assert minute =~ "Span: [2026-W25-2T10:30, 2026-W25-2T10:31)."
    end

    test "a week calendar's weekday is the one its calendar gives" do
      # The retail calendar starts its weeks on a Sunday, so its day 2 is a Monday.
      day = Tempo.new!(year: 2026, week: 25, day_of_week: 2, calendar: Calendrical.NRF)

      assert Tempo.explain(day) =~ "Monday of week 25 of 2026."
    end

    test "a week in another month-based calendar spans that calendar's days" do
      prose = Tempo.explain(Tempo.from_iso8601!("5786-W25[u-ca=hebrew]"))

      assert prose =~ "Week 25 of 5786."
      assert prose =~ "Span: [5786-W25, 5786-W26).\nStarts on 5786-06-20."
    end

    test "a week with no year recurs, as a yearless date does" do
      assert Tempo.explain(~o"25W") =~ "Week 25 of any year"
      assert Tempo.explain(~o"25W2K") =~ "Tuesday of week 25, in any year"
      assert Tempo.explain(~o"2K") =~ "Tuesday of any week"
      assert Tempo.explain(~o"25W2K"W) =~ "Day 2 of week 25, in any year"
    end

    # An end is written as far as the value is, and no further (decided
    # 2026-10-08): a week was written as the date of its first day, and a
    # year as its first of January. The day a week starts on is told beside
    # it, its writing not saying which.
    test "a week is written as the week wherever it bounds something, with the day it starts on" do
      assert Tempo.explain(~o"2026-W25/2026-W27") =~ "From: 2026-W25 (starts on 2026-06-15)."

      assert Tempo.explain(~o"2026-W25/2026-W27") =~
               "To:   2026-W27 (starts on 2026-06-29; exclusive — half-open `[from, to)`)."

      assert Tempo.explain(Tempo.from_iso8601!("2026-W25/..")) =~
               "Lower bound: 2026-W25 (starts on 2026-06-15)."

      assert Tempo.explain(Tempo.from_iso8601!("R5/2026-W25/P1W")) =~
               "Starting: 2026-W25 (starts on 2026-06-15)."

      assert Tempo.explain(Tempo.from_iso8601!("2026-W2X")) =~
               "Span: [2026-W20, 2026-W30).\nStarts on 2026-05-11."

      {:ok, weeks} = Tempo.union(~o"2026-W25", ~o"2026-W30")

      assert Tempo.explain(weeks) =~
               "1. 2026-W25 (starts on 2026-06-15) → 2026-W26 (starts on 2026-06-22)"

      assert Tempo.explain(weeks) =~
               "2. 2026-W30 (starts on 2026-07-20) → 2026-W31 (starts on 2026-07-27)"

      # A calendar of weeks writes a week in its own notation, which says
      # where it starts.
      week_calendar = Tempo.from_iso8601!("2026-W25/2026-W27", Calendrical.ISOWeek)
      assert Tempo.explain(week_calendar) =~ "From: 2026-W25."
      assert Tempo.explain(week_calendar) =~ "To:   2026-W27 (exclusive"
    end

    test "a time of day is worded with the units it is written to, and no others" do
      # An hour was worded with minutes it does not have ("at 10:00"), and a
      # minute with no hour as half past midnight ("00:30").
      for {text, headline} <- [
            {"1984-06-15T10", "June 15, 1984 at hour 10."},
            {"1984-06-15T10:30", "June 15, 1984 at 10:30."},
            {"1984-06-15T10:30:15", "June 15, 1984 at 10:30:15."},
            {"T10", "Hour 10 of the day (unanchored — recurs every day)."},
            {"T10:30", "The time-of-day 10:30 (unanchored — recurs every day)."},
            {"T30M", "Minute 30 of the hour (unanchored — recurs every hour)."},
            {"T15S", "Second 15 of the minute (unanchored — recurs every minute)."},
            {"T{9,14}H", "Hours 9 and 14 of the day (unanchored — they recur every day)."}
          ] do
        assert {text, headline(text)} == {text, headline}
      end

      week_date = Tempo.from_iso8601!("2026-W25-2T10", Calendrical.ISOWeek)
      assert Tempo.explain(week_date) =~ "Tuesday of week 25 of 2026 at hour 10."

      # Its ends are written the same way: a minute with no hour by its unit.
      assert Tempo.explain(~o"T30M") =~ "Span: [T30M, T31M)."
      assert Tempo.explain(~o"T15S") =~ "Span: [T15S, T16S)."
      assert Tempo.explain(~o"T10") =~ "Span: [T10, T11)."
    end

    test "a year, a month, a day and a time at an end are written as far as they are" do
      for {text, from, to} <- [
            {"1984/1986", "1984", "1986"},
            {"1984-06/1986-02", "1984-06", "1986-02"},
            {"1984/1986-06", "1984", "1986-06"},
            {"1984-06-15/1984-06-20", "1984-06-15", "1984-06-20"},
            {"1984-06-15T10/1984-06-15T12", "1984-06-15T10", "1984-06-15T12"},
            {"1984-06-15T10:30/1984-06-15T12", "1984-06-15T10:30", "1984-06-15T12"},
            {"T10/T12", "T10", "T12"}
          ] do
        explained = Tempo.explain(Tempo.from_iso8601!(text))

        assert {text, explained} ==
                 {text,
                  "A closed interval.\nFrom: #{from}.\n" <>
                    "To:   #{to} (exclusive — half-open `[from, to)`)."}
      end

      # The interval a value converts to is explained as it is written too.
      assert ~o"1984/1986" |> Tempo.to_interval!() |> Tempo.explain() ==
               "A closed interval.\nFrom: 1984.\nTo:   1986 (exclusive — half-open `[from, to)`)."

      assert Tempo.explain(~o"1984") =~ "The year 1984.\nSpan: [1984, 1985).\nIterates"
      assert Tempo.explain(~o"1984-06") =~ "Span: [1984-06, 1984-07).\nIterates"
    end
  end

  describe "months in other calendars" do
    test "a month is named as its calendar names it" do
      assert headline("5786-06-15[u-ca=hebrew]") == "Adar 15, 5786."
      assert headline("5786-06-15T10:30[u-ca=hebrew]") == "Adar 15, 5786 at 10:30."
      assert headline("5786-06[u-ca=hebrew]") == "Adar 5786."
      assert headline("1405-01-01[u-ca=persian]") == "Farvardin 1, 1405."
      assert headline("1447-09-01[u-ca=islamic-civil]") == "Ramadan 1, 1447."
    end

    test "a lunisolar month is named in its own year, and a thirteenth month has a name" do
      # 5787 is a Hebrew leap year, with two Adars and thirteen months.
      assert headline("5787-06-15[u-ca=hebrew]") == "Adar I 15, 5787."
      assert headline("5787-07-15[u-ca=hebrew]") == "Adar II 15, 5787."
      assert headline("5787-13-01[u-ca=hebrew]") == "Elul 1, 5787."
      assert headline("1742-13-03[u-ca=coptic]") == "Nasie 3, 1742."
    end

    test "a calendar with the Gregorian calendar's months keeps their names" do
      assert headline("2026-06-15[u-ca=japanese]") == "June 15, 2026."
      assert headline("2569-06-15[u-ca=buddhist]") == "June 15, 2569."
    end

    test "a month with no year is named only where every year names it alike" do
      assert headline("6M15D", Calendrical.Persian) =~ "Shahrivar 15, in any year"
      assert headline("6M", Calendrical.Persian) =~ "Shahrivar, in any year"

      # The Hebrew calendar's sixth month is Adar in one year and Adar I in the next.
      assert headline("6M15D", Calendrical.Hebrew) =~ "Day 15 of month 6, in any year"
      assert headline("6M", Calendrical.Hebrew) =~ "Month 6, in any year"
    end

    test "a selection's months are named in its calendar" do
      yearly = Tempo.explain(Tempo.from_iso8601!("R/../P1Y/FL1M1DN[u-ca=persian]"))
      assert yearly =~ "Selects: in Farvardin, on the 1st."

      in_a_year = Tempo.explain(Tempo.from_iso8601!("1405YL1M1DN[u-ca=persian]"))
      assert in_a_year =~ "In 1405, selects in Farvardin, on the 1st."

      window = Tempo.explain(Tempo.from_iso8601!("R/../P1Y/FLL1M1DN/P5DN[u-ca=persian]"))
      assert window =~ "Selects: the 5 days from Farvardin 1."

      # A rule selects in every year, and a Hebrew month has no one name across them.
      lunisolar = Tempo.explain(Tempo.from_iso8601!("R/../P1Y/FL7M15DN[u-ca=hebrew]"))
      assert lunisolar =~ "Selects: in month 7, on the 15th."

      assert Tempo.explain(~o"R/../P1Y/FL11M4K4IN") =~
               "Selects: in November, on the 4th Thursday."
    end
  end

  # What a selection selects, in words. A weekday, an hour, a minute and a
  # second take the same values wherever they are, so a count from the end
  # is the value it names; a day, a week and a position are counted in a
  # period the selection alone does not fix, so theirs is worded as written.
  describe "a selection's values" do
    defp selects(iso), do: iso |> Tempo.from_iso8601!() |> selects_line()
    defp selects(iso, calendar), do: iso |> Tempo.from_iso8601!(calendar) |> selects_line()

    defp selects_line(value) do
      value
      |> Tempo.explain()
      |> String.split("\n")
      |> Enum.find(&(&1 =~ ~r/[Ss]elects/))
    end

    test "a range that reaches the end of its period is worded by its ends" do
      assert selects("R/../P1M/FL{28..-1}DN") == "Selects: on the 28th to the last."
      assert selects("R/../P1M/FL{2..-2}DN") == "Selects: on the 2nd to the 2nd-to-last."

      assert selects("R/../P1M/FL{1..-1//7}DN") ==
               "Selects: on every 7th from the 1st to the last."

      assert selects("R/../P1M/FL{1,28..-1}DN") ==
               "Selects: on the 1st and the 28th to the last."

      assert selects("R/../P1Y/FL{52..-1}WN") == "Selects: in the 52nd to the last ISO week."

      assert selects("R/../P1Y/FL{364..-1}ON") ==
               "Selects: on the 364th to the last day of the year."

      assert selects("R/../P1M/FL1K{2..-1}IN") == "Selects: on the 2nd to the last Monday."

      assert selects("R/../P1M/FL{1..5}K{2..-1}IN") ==
               "Selects: on a Monday, Tuesday, Wednesday, Thursday or Friday, " <>
                 "keeping the 2nd to the last occurrence."
    end

    test "a count from the end follows those counted from the start" do
      assert selects("R/../P1M/FL-1DN") == "Selects: on the last."
      assert selects("R/../P1M/FL{1,15,-1}DN") == "Selects: on the 1st, 15th, and last."
      assert selects("R/../P1M/FL{-3..-1}DN") == "Selects: on the 3rd-to-last–last."
      assert selects("R/../P1M/FL5K-1IN") == "Selects: on the last Friday."
    end

    test "weekdays are named, a set of them and one counted from the end" do
      assert selects("R/../P1W/FL{1,3}KN") == "Selects: on a Monday or Wednesday."
      assert selects("R/../P1W/FL{6..7}KN") == "Selects: on a Saturday or Sunday."
      assert selects("R/../P1W/FL{6..-1}KN") == "Selects: on a Saturday or Sunday."
      assert selects("R/../P1W/FL-1KN") == "Selects: on a Sunday."

      assert selects("R/../P1M/FL{1,5}K-1IN") ==
               "Selects: on a Monday or Friday, keeping the last occurrence."
    end

    test "a month counted from the end is named where a year's months can be counted" do
      assert selects("R/../P1Y/FL-1MN") == "Selects: in December."
      assert selects("R/../P1Y/FL{11..-1}MN") == "Selects: in November or December."
      assert selects("R/../P1Y/FL{1..-1//3}MN") == "Selects: in January, April, July or October."

      # A Hebrew year has twelve months or thirteen, and its last is Elul.
      assert selects("5787YL-1MN", Calendrical.Hebrew) == "In 5787, selects in Elul."
      assert selects("5786YL-1MN", Calendrical.Hebrew) == "In 5786, selects in Elul."

      # A rule selects in every year, and which month is the last depends on the year.
      assert selects("R/../P1Y/FL-1MN[u-ca=hebrew]") == "Selects: in the last month."

      assert selects("R/../P1Y/FL{11..-1}MN[u-ca=hebrew]") ==
               "Selects: in month 11 to the last month."
    end

    test "a time of day is each hour with each minute and second, as far as it is written" do
      # An hour is worded as the hour, and not with minutes it does not have
      # (decided 2026-10-08): it was "at 09:00".
      assert selects("R/../P1D/FLT9HN") == "Selects: at hour 9."
      assert selects("R/../P1D/FLT{9,17}HN") == "Selects: at hour 9 or 17."
      assert selects("R/../P1D/FLT10H30MN") == "Selects: at 10:30."
      assert selects("R/../P1D/FLT10H30M15SN") == "Selects: at 10:30:15."
      assert selects("R/../P1D/FLT{9,17}H30MN") == "Selects: at 09:30 or 17:30."
      assert selects("R/../P1D/FLT-1HN") == "Selects: at hour 23."
      assert selects("R/../P1D/FLT{22..-1}HN") == "Selects: at hour 22 or 23."
      assert selects("R/../P1D/FLT10H-1MN") == "Selects: at 10:59."

      assert selects("R/../P1D/FLT{9..17}H{0,30}MN") ==
               "Selects: at 18 times of day from 09:00 to 17:30."
    end

    test "a minute or a second with no hour is that of each hour or minute" do
      assert selects("R/../P1D/FLT30MN") == "Selects: at minute 30 of each hour."
      assert selects("R/../P1D/FLT{0,30}MN") == "Selects: at minute 0 or 30 of each hour."
      assert selects("R/../P1D/FLT30M15SN") == "Selects: at 30:15 past each hour."
      assert selects("R/../P1D/FLT15SN") == "Selects: at second 15 of each minute."
    end

    test "a value the unit does not take is worded as it is written" do
      assert selects("R/../P1D/FLT25HN") == "Selects: at hour 25."
      assert selects("R/../P1W/FL8KN") == "Selects: on a weekday 8."
      assert selects("R/../P1Y/FL13MN") == "Selects: in month 13."
    end

    test "a day with no month is a day of the year where it is selected in one" do
      assert selects("2026YL15DN") == "In 2026, selects on the 15th day of the year."
      assert selects("2026YL-1DN") == "In 2026, selects on the last day of the year."
      assert selects("R/2026/P1Y/FL45DN") == "Selects: on the 45th day of the year."
      assert selects("R/../P1Y/FL45DN") == "Selects: on the 45th day of the year."

      # A start that names a month gives the day its month, and a selection
      # alone has no period yet.
      assert selects("R/2026-03-10/P1Y/FL15DN") == "Selects: on the 15th."
      assert selects("R/2026/P1M/FL15DN") == "Selects: on the 15th."
      assert selects("L15DN") == "Selects on the 15th."
    end

    test "the period a value's selection is in is named" do
      assert selects("2026YL3M15DN") == "In 2026, selects in March, on the 15th."
      assert selects("2026Y6ML15DN") == "In June 2026, selects on the 15th."
      assert selects("2026Y6M15DLT9HN") == "On June 15, 2026, selects at hour 9."
      assert selects("2026Y25WL1KN") == "In week 25 of 2026, selects on a Monday."
      assert selects("2026Y{6,7}ML15DN") == "In June and July 2026, selects on the 15th."
      assert selects("6ML15DN") == "In June, in any year, selects on the 15th."

      assert selects("2026Y6M15DT10HLT30MN") ==
               "On June 15, 2026 at hour 10, selects at minute 30 of each hour."

      assert selects("5787Y6ML{28..-1}DN", Calendrical.Hebrew) ==
               "In Adar I 5787, selects on the 28th to the last."
    end
  end

  describe "a count from the end in a value with no year" do
    test "is worded by its place from the end" do
      assert headline("-1D") == "The last day of any month (no year or month — it recurs)."
      assert headline("-2D") == "The 2nd-to-last day of any month (no year or month — it recurs)."
      assert headline("2M-1D") == "The last day of February, in any year (no year — it recurs)."
      assert headline("-1M") == "The last month, in any year (no year — it recurs)."

      assert headline("-1M-1D") ==
               "The last day of the last month, in any year (no year — it recurs)."

      assert headline("-1M15D") == "Day 15 of the last month, in any year (no year — it recurs)."
      assert headline("-1W") == "The last week of any year (no year — it recurs)."
      assert headline("-1O") == "The last day of any year (no year — it recurs)."
    end

    test "is the value it names where that is the same in every year" do
      assert headline("6M-1D") == "June 30, in any year (no year — it recurs)."
      assert headline("-1K") == "Sunday of any week (no year or week — it recurs)."
    end
  end

  describe "values holding a set or a group" do
    test "a set is each of its members" do
      assert headline("2026-{06,07}") == "June and July 2026."
      assert headline("2026-{06..08}") == "June–August 2026."
      assert headline("2026-{01,06..08}") == "January, June, July, and August 2026."
      assert headline("2026-06-{01,15}") == "The 1st and 15th of June 2026."
      assert headline("2026-06-{01..07}") == "The 1st–7th of June 2026."
      assert headline("2026-{06,07}-15") == "The 15th of June and July 2026."
      assert headline("2026-{06,07}-{01,15}") == "The 1st and 15th of June and July 2026."
    end

    test "a set of years is not a value without a year" do
      assert headline("{2021,2022}Y") == "The years 2021 and 2022."
      assert headline("{2021..2023}Y") == "The years 2021–2023."
      assert headline("{2021,2022}Y6M") == "June of 2021 and 2022."
      assert headline("{2021,2022}Y6M15D") == "The 15th of June of 2021 and 2022."
    end

    test "a group is one span, from its first value to its last" do
      assert headline("2026-33") == "January to March 2026."
      assert headline("2026-40") == "January to June 2026."
      assert headline("2022Y1M2G3DU") == "The 4th to 6th of January 2022."
      assert headline("2022Y5G1WU") == "Week 5 of 2022."
      assert headline("20C") == "The years 2000 to 2099."
    end

    test "weeks, days of the week and days of the year are named too" do
      assert headline("2026Y{25,27}W") == "Weeks 25 and 27 of 2026."
      assert headline("2026Y{25..27}W") == "Weeks 25–27 of 2026."
      assert headline("2026Y25W{1,3}K") == "Monday and Wednesday of week 25 of 2026."
      assert headline("2026Y{25,27}W2K") == "Tuesday of weeks 25 and 27 of 2026."
      assert headline("2020Y{100,200}O") == "Days 100 and 200 of 2020."
    end

    test "several times of a day are each written" do
      assert headline("2026-06-15T{10,14}") == "June 15, 2026 at hours 10 and 14."
      assert headline("2026-06-15T10:{00,30}") == "June 15, 2026 at 10:00 and 10:30."
      assert headline("2026-06-15T{10,14}:30") == "June 15, 2026 at 10:30 and 14:30."

      assert headline("T{10,14}H") ==
               "Hours 10 and 14 of the day (unanchored — they recur every day)."

      assert headline("T10H{0,30}M") =~ "The times of day 10:00 and 10:30"
    end

    test "a set with no year recurs" do
      assert headline("{6,7}M") == "June and July, in any year (no year — it recurs)."

      assert headline("6M{1,15}D") ==
               "The 1st and 15th of June, in any year (no year — it recurs)."

      assert headline("{6,7}M15D") ==
               "The 15th of June and July, in any year (no year — it recurs)."

      assert headline("{10,20}W") == "Weeks 10 and 20 of any year (no year — it recurs)."

      assert headline("{1,3}K") ==
               "Monday and Wednesday of any week (no year or week — it recurs)."
    end

    test "a set's months are named in its calendar" do
      assert headline("5786-{06,07}[u-ca=hebrew]") == "Adar and Nisan 5786."
    end

    test "a group of groups, or of days with no month, is described by its resolution" do
      assert headline("2018-{1,3,5}G2MU") == "A Tempo value at :month resolution."
      assert headline("{1,4,7..9}G2YU3M1D") == "A Tempo value at :day resolution."
      assert headline("5G10DU") == "A Tempo value at :day resolution."
    end

    test "no headline writes a placeholder" do
      for iso <- ["T{-4..-1}H", "T10H{0,30}M", "2026-06-15T10:{00,30}", "2026-{06,07}"] do
        refute headline(iso) =~ "?", "#{iso} wrote a placeholder"
      end
    end
  end

  describe "masked Tempo" do
    test "156X is classified :masked" do
      assert Explain.explain(~o"156X").kind == :masked
    end

    test "156X names the decade" do
      assert Tempo.explain(~o"156X") =~ "1560s"
    end

    test "1XXX names the millennium" do
      assert Tempo.explain(~o"1XXX") =~ ~r/millennium|century|1000s/
    end
  end

  describe "time-of-day" do
    test "T10:30 is classified :time_of_day" do
      assert Explain.explain(~o"T10:30").kind == :time_of_day
    end

    test "mentions the unanchored nature" do
      assert Tempo.explain(~o"T10:30") =~ "unanchored"
    end
  end

  describe "a date with no year and a time of day" do
    # Its headline named the date and left the time out: "June 15, in any
    # year" for ten o'clock on it.
    test "is headlined with its time, as far as the time is written" do
      for {text, headline} <- [
            {"6M15DT10H", "June 15 at hour 10, in any year (no year — it recurs)."},
            {"6M15DT10H30M", "June 15 at 10:30, in any year (no year — it recurs)."},
            {"6M15DT10H30M15S", "June 15 at 10:30:15, in any year (no year — it recurs)."},
            {"6M15D", "June 15, in any year (no year — it recurs)."},
            {"15DT10H", "Day 15 of any month at hour 10 (no year or month — it recurs)."},
            {"166OT10H", "Day 166 of any year at hour 10 (no year — it recurs)."},
            {"25W2KT10H", "Tuesday of week 25 at hour 10, in any year (no year — it recurs)."},
            {"2KT10H", "Tuesday of any week at hour 10 (no year or week — it recurs)."},
            {"6M15DT{9,14}H",
             "The 15th of June at hours 9 and 14, in any year (no year — it recurs)."}
          ] do
        assert {text, headline(text)} == {text, headline}
      end

      assert headline("25W2KT10H30M", Calendrical.ISOWeek) ==
               "Day 2 of week 25 at 10:30, in any year (no year — it recurs)."
    end

    test "is written at its ends as the value is, where its date has no ISO spelling" do
      # The words for the date were run into the time: "day 166 of the yearT10".
      assert Tempo.explain(~o"166OT10H") =~ ~s|Span: [~o"166OT10H", ~o"166OT11H").|
      assert Tempo.explain(~o"2KT10H") =~ ~s|Span: [~o"2KT10H", ~o"2KT11H").|
      assert Tempo.explain(~o"6M15DT10H") =~ "Span: [--06-15T10, --06-15T11)."
    end
  end

  describe "a recurrence of one occurrence that has a rule" do
    # Its occurrence is the first its rule selects. It was explained as the
    # interval its start and its duration make, with no word of the rule,
    # and with no start as "an unusual shape".
    test "is explained as a recurrence, with what its rule selects" do
      for {text, lines} <- [
            {"R1/2019-01-01/P1D/FL7KN",
             ["A recurrence of 1 occurrence.", "Starting: 2019-01-01.", "Selects: on a Sunday."]},
            {"R1/P1D/2019-01-08/FL7KN",
             [
               "A recurrence of 1 occurrence.",
               "Ending: 2019-01-08 (exclusive — half-open `[from, to)`).",
               "Selects: on a Sunday."
             ]},
            {"R1/../P1D/FL7KN",
             [
               "A recurrence of 1 occurrence.",
               "Starting: open — the rule names no start.",
               "Selects: on a Sunday."
             ]},
            {"R1/2019-01-01/2019-01-02/FL7KN",
             ["A recurrence of 1 occurrence.", "Selects: on a Sunday."]}
          ] do
        explained = Tempo.explain(Tempo.from_iso8601!(text))

        for line <- lines do
          assert {text, line, explained =~ line} == {text, line, true}
        end

        # One with no start is told how to give it a window or a start.
        assert {text, explained =~ ~r/Find the occurrence|names no start of its own/} ==
                 {text, true}

        refute explained =~ "unusual shape"
        refute explained =~ "An interval given as"
      end
    end

    test "with no rule is the interval it is, as it was" do
      assert Tempo.explain(~o"R1/2019-01-01/P1D") =~
               "An interval given as a start and a duration."

      assert Tempo.explain(~o"2019-01-01/P1D") =~ "An interval given as a start and a duration."
    end
  end

  describe "a rule with an UNTIL and no start" do
    test "is headlined by its end, where it was called unbounded" do
      {:ok, rule} = RRule.parse("FREQ=DAILY;BYDAY=SU;UNTIL=20190108")
      explained = Tempo.explain(rule)

      assert explained =~
               "A recurrence until 2019-01-08.\nStarting: open — the rule names no start."

      refute explained =~ "unbounded"

      {:ok, no_end} = RRule.parse("FREQ=DAILY;BYDAY=SU")
      assert Tempo.explain(no_end) =~ "An unbounded recurrence."
    end
  end

  describe "a window from a time of day" do
    test "is worded in its hours and minutes" do
      # It was "the PT4H window from at 22:00".
      assert selects("R/2027-01-01/P1D/FLLT22HN/PT4HN") == "Selects: the 4 hours from hour 22."

      assert selects("R/2027-01-01/P1D/FLLT22H30MN/PT90MN") ==
               "Selects: the 90 minutes from 22:30."

      assert selects("R/2027-01-01/P1D/FLLT9HN/PT1H30MN") ==
               "Selects: the 1 hour, 30 minutes from hour 9."

      assert selects("R/2027-01-01/P1D/FLLT22HN/PT-4HN") == "Selects: the 4 hours before hour 22."
    end

    test "names the time without its \"at\" in a window of days too" do
      assert selects("R/2027-01-01/P1D/FLLT22HN/P2DN") == "Selects: the 2 days from hour 22."
      assert selects("R/2027-01-01/P1W/FLL1KN/P3DN") == "Selects: the 3 days from a Monday."
    end
  end

  describe "IXDTF metadata" do
    test "zoned Tempo mentions the zone" do
      paris = Tempo.from_elixir(DateTime.new!(~D[2026-06-15], ~T[10:00:00], "Europe/Paris"))
      assert Tempo.explain(paris) =~ "Europe/Paris"
    end
  end

  describe "Tempo.Duration" do
    test "classified :duration with a hint that it has no place on the time line" do
      exp = Explain.explain(~o"P1Y2M")
      assert exp.kind == :duration
      assert Tempo.explain(~o"P1Y2M") =~ "no place on the time line"
    end

    test "reads in human units" do
      assert Tempo.explain(~o"P3M") =~ "3 months"
    end
  end

  describe "Tempo.Interval" do
    test "closed interval is classified :closed_interval" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06-15")
      assert Explain.explain(iv).kind == :closed_interval
    end

    test "open-upper interval is classified :open_upper_interval" do
      {:ok, iv} = Tempo.from_iso8601("1985/..")
      assert Explain.explain(iv).kind == :open_upper_interval
    end

    test "fully open is classified :fully_open_interval" do
      {:ok, iv} = Tempo.from_iso8601("../..")
      assert Explain.explain(iv).kind == :fully_open_interval
    end

    test "interval with metadata mentions the event summary" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06-15")
      iv = %{iv | metadata: %{summary: "Design review", location: "Room 101"}}
      assert Tempo.explain(iv) =~ "Design review"
      assert Tempo.explain(iv) =~ "Room 101"
    end

    test "an unbounded recurrence with a BY-rule selection is explained in prose" do
      # US Election Day — the Tuesday falling on the 2nd–8th of November.
      election = ~o"R/2024Y11M1D/P1Y/FL11M{2..8}D2KN"

      assert Explain.explain(election).kind == :recurring_interval

      prose = Tempo.explain(election)
      assert prose =~ "unbounded recurrence"
      assert prose =~ "in November, on the 2nd–8th, on a Tuesday"
    end

    test "a recurrence with an open start explains its selection and names what is missing" do
      # `R/../…` has no start at all. Two sentinels spell "no endpoint" —
      # `:undefined` from the ISO 8601 parser and `nil` from the RRULE
      # parser — and only the first was recognised, so a fully described
      # rule reported "an unusual shape" and said nothing useful.
      thanksgiving = ~o"R/../P1Y/FL11M4K4IN"

      prose = Tempo.explain(thanksgiving)

      assert prose =~ "unbounded recurrence"
      assert prose =~ "in November, on the 4th Thursday"
      assert prose =~ "1 year"
      assert prose =~ "Starting: open"
      refute prose =~ "unusual shape"
    end

    test "a recurrence with an open start materialises into a window and the hint says so" do
      # A window is where to materialise: "every Monday" within 2026
      # lists that year's 52 Mondays, and the explain hint points
      # at exactly that path.
      assert {:ok, %IntervalSet{} = set} =
               Tempo.to_interval(~o"R/../P1W/FL1KN", within: ~o"2026Y")

      assert IntervalSet.count(set) == 52
      assert Tempo.explain(~o"R/../P1W/FL1KN") =~ "List its occurrences within a window"
    end

    test "an unspecified year materialises instead of crashing in the calendar" do
      # `X*Y12M28D` is "28 December of an unspecified year". The year key
      # is present but holds `:any`, and the anchored branches guarded on
      # key *presence*, so `:any` reached `days_in_month/3`, which guards
      # `is_integer/1`, as a FunctionClauseError.
      assert {:ok, interval} = Tempo.to_interval(~o"X*Y12M28D")
      assert Tempo.explain(interval) =~ "interval"

      # December is 31 days in every year, so the step is answerable
      # without one; the roll-over into January likewise.
      assert {:ok, %Tempo.Interval{}} = Tempo.to_interval(~o"X*Y12M31D")
    end

    test "an unspecified year reports the year it needs when the answer depends on one" do
      # February's length does depend on the year, so this is the case
      # `UnanchoredError` exists for — an error, not a guess.
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"X*Y2M28D")
    end

    test "a yearless masked month resolves against the calendar's own month count" do
      # `XX-15` is "the 15th of any month" with no year at all.
      # `Keyword.fetch!(previous, :year)` raised a bare KeyError; the
      # unanchored calendar callback answers it exactly for Gregorian.
      assert {:ok, set} = Tempo.to_interval(~o"XX-15")
      assert IntervalSet.count(set) == 12

      assert Enum.take(~o"XX-15", 3) == [~o"1M15D", ~o"2M15D", ~o"3M15D"]
      assert Tempo.explain(~o"XX-15") =~ "12 disjoint intervals"
    end

    test "a yearless masked month needs a year where the month count varies" do
      # A Hebrew leap year has 13 months, so "any month" is genuinely
      # unanswerable without knowing the year.
      hebrew = Tempo.from_iso8601!("XX-15", Calendrical.Hebrew)

      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(hebrew)
    end

    test "a start-and-duration interval is described, not called an unusual shape" do
      # `<start>/<duration>` is ordinary ISO 8601 — "an 8-hour shift from
      # 09:00". It carries no `to`, so it matched no clause and reported
      # an unusual shape.
      prose = Tempo.explain(~o"2026-06-15T09:00/PT8H")

      assert prose =~ "start and a duration"
      assert prose =~ "2026-06-15T09:00"
      assert prose =~ "8 hours"
      refute prose =~ "unusual shape"
    end

    test "a duration-and-end interval is not called open-lower" do
      # The lower bound is implied by the duration, not absent. Calling
      # this open-lower was wrong rather than merely vague: the value
      # materialises to a bounded one-day span.
      assert {:ok, ~o"2026Y6M14D/15D"} = Tempo.to_interval(~o"P1D/2026-06-15")

      prose = Tempo.explain(~o"P1D/2026-06-15")

      assert prose =~ "duration and an end"
      refute prose =~ "open-lower"
      refute prose =~ "requires a lower bound"
    end

    test "genuinely open intervals still explain as open" do
      assert Tempo.explain(~o"../2026-06-15") =~ "open-lower"
      assert Tempo.explain(~o"2026-06-15/..") =~ "open-upper"
      assert Tempo.explain(~o"../..") =~ "fully open"
    end

    test "a real recurrence still wins over the start-and-duration clause" do
      assert Tempo.explain(~o"R3/2026-01-01/P1M") =~ "recurrence of 3 occurrences"
      assert Tempo.explain(~o"R1/2026-01-01/P1Y") =~ "start and a duration"
    end

    test "a recurrence written with an end is a recurrence" do
      start_and_end = ~o"R5/2026-06-15/2026-06-20"
      assert Explain.explain(start_and_end).kind == :recurring_interval
      assert Tempo.explain(start_and_end) =~ "recurrence of 5 occurrences"
      assert Tempo.explain(start_and_end) =~ "First occurrence: 2026-06-15 to 2026-06-20"

      duration_and_end = ~o"R5/P1D/2026-06-20"
      assert Explain.explain(duration_and_end).kind == :recurring_interval
      assert Tempo.explain(duration_and_end) =~ "recurrence of 5 occurrences"
      assert Tempo.explain(duration_and_end) =~ "Ending: 2026-06-20"

      assert Tempo.explain(~o"R/2026-06-15/2026-06-20") =~ "unbounded recurrence"
    end

    test "a duration and an end are a closed interval, not an open one" do
      assert Explain.explain(~o"P1D/2026-06-20").kind == :closed_interval
    end

    test "an RRULE with an UNTIL is bounded by it" do
      {:ok, rule} = RRule.parse("FREQ=DAILY;UNTIL=20260620", from: ~o"2026-06-15")

      assert Tempo.explain(rule) =~ "A recurrence until 2026-06-20."
      refute Tempo.explain(rule) =~ "unbounded"
    end

    test "a counted recurrence with an open start is explained the same way" do
      prose = Tempo.explain(~o"R5/../P1Y/FL5M1K-1IN")

      assert prose =~ "recurrence of 5 occurrences"
      assert prose =~ "in May, on the last Monday"
      assert prose =~ "Starting: open"
    end
  end

  describe "every representation explains" do
    # An audit over every ISO literal in the repo (1777 of them) found 140
    # values `explain/1` either crashed on, described generically, or
    # described *wrongly* — a yearless date reported itself as "anchored"
    # with a `[?, ?)` span. One representative per failing class is kept
    # here; the property is that none of them raises and none reports a
    # placeholder.
    @shapes [
      # yearless and partial dates — the birthday case
      "4M3D",
      "12M31D",
      "14D",
      "1M",
      # clock-only values, including resolved negatives
      "T-1H",
      "T-1M",
      "T-1S",
      "T{-4..-1}H",
      # week and ordinal axes without a year
      "1W",
      "{10,20}W",
      # bare offsets, which carry no components at all
      "Z",
      "Z8H",
      # groups, whose components are 3-tuples rather than a keyword list
      "{1,4,7..9}G1YU",
      "2018-{1,3,5}G2MU",
      "{1,4,7..9}G2YU3M1D",
      # bare selections — a rule, not a span
      "2018YL1K1IN",
      "L1K2IN",
      # sub-second durations, stored as `{value, precision}`
      "PT1.5S",
      "-PT1.5S",
      "P1Y2MT1.5S",
      # masked and margin-of-error interval endpoints
      "198X/1999",
      "2018±2Y/2020±2Y"
    ]

    test "no representation raises, goes generic, or renders a placeholder" do
      for iso <- @shapes do
        {:ok, value} = Tempo.from_iso8601(iso)
        prose = Tempo.explain(value)

        refute prose =~ "unusual shape", "#{iso} explained generically"
        refute prose =~ "doesn't know how to describe", "#{iso} was not described"

        refute Regex.match?(~r/(Span|From|To|bound):[^\n]*\?/, prose),
               "#{iso} rendered an endpoint as `?`:\n#{prose}"
      end
    end

    test "a yearless date is not described as anchored" do
      prose = Tempo.explain(~o"4M3D")

      refute Tempo.anchored?(~o"4M3D")
      refute prose =~ "An anchored"
      assert prose =~ "in any year"
      assert prose =~ "--04-03"
    end

    test "a bare selection is explained as the rule it is" do
      prose = Tempo.explain(~o"2018YL1K1IN")

      assert prose =~ "selection"
      assert prose =~ "In 2018, selects"
      assert prose =~ "Monday"
    end

    test "a sub-second duration renders its fraction" do
      # One and a half seconds, which was worded "1 second, 0.5 seconds".
      assert Tempo.explain(~o"PT1.5S") =~ "A duration of 1.5 seconds."
      assert Tempo.explain(~o"PT0.5S") =~ "A duration of 0.5 seconds."
      assert Tempo.explain(~o"PT1M30.25S") =~ "A duration of 1 minute, 30.25 seconds."
    end

    test "a duration of one unit back is one, as one forward is" do
      assert Tempo.explain(~o"-P1D") =~ "A duration of -1 day."
      assert Tempo.explain(~o"P1D") =~ "A duration of 1 day."
      assert Tempo.explain(~o"-P2D") =~ "A duration of -2 days."
    end
  end

  describe "Tempo.IntervalSet" do
    test "empty set is classified :empty_interval_set" do
      {:ok, set} = IntervalSet.new([])
      assert Explain.explain(set).kind == :empty_interval_set
    end

    test "non-empty set previews first 3 intervals" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      X-WR-CALNAME:Work
      BEGIN:VEVENT
      UID:evt-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Standup
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      text = Tempo.explain(set)
      assert text =~ "IntervalSet with 1 interval"
      assert text =~ "Standup"
      assert text =~ "Work"
    end
  end

  describe "Tempo.Set" do
    test "one-of set mentions epistemic disjunction" do
      {:ok, s} = Tempo.from_iso8601("[2020Y,2021Y,2022Y]")
      assert Explain.explain(s).kind == :one_of_set
      assert Tempo.explain(s) =~ "one of"
    end
  end

  describe "Tempo.RecurrenceSet" do
    test "a recurrence set is its members' rules, led by their names" do
      christmas = Tempo.put_metadata(~o"R/../P1Y/FL12M25DN", %{name: "Christmas Day"})
      {:ok, holidays} = RecurrenceSet.new([christmas, ~o"R/../P1Y/FL1M1DN"])

      assert Explain.explain(holidays).kind == :recurrence_set

      assert Tempo.explain(holidays) ==
               """
               A recurrence set of 2 members.
               1. Christmas Day: in December, on the 25th, every year.
               2. In January, on the 1st, every year.
               List its occurrences in a window: `Tempo.to_interval(set, within: ~o"2026")`.\
               """
    end

    test "each kind of member is described, three of them in full" do
      {:ok, set} =
        RecurrenceSet.new([
          ~o"R5/2026-06-15/P1D",
          ~o"R2/2026-06-15/2026-06-20",
          ~o"2026-06-15",
          ~o"R5/P1D/2026-06-20"
        ])

      prose = Tempo.explain(set)

      assert prose =~ "1. Every day, from 2026-06-15, 5 times."
      assert prose =~ "2. 2026-06-15 to 2026-06-20, then back to back, 2 times."
      assert prose =~ "3. 2026-06-15."
      assert prose =~ "… and 1 more."
      refute prose =~ "doesn't know how to describe"
    end

    test "an empty recurrence set says so" do
      {:ok, empty} = RecurrenceSet.new([])
      assert Tempo.explain(empty) == "An empty recurrence set."
    end

    test "a conditional member is described on its own" do
      christmas = Tempo.put_metadata(~o"R/../P1Y/FL12M25DN", %{name: "Christmas Day"})
      moved = RecurrenceSet.move_when(christmas, falls_on: %{type: :public}, to_next: ~o"1K")

      assert Explain.explain(moved).kind == :conditional_member

      assert Tempo.explain(moved) =~
               "Christmas Day: in December, on the 25th, every year, moved when it falls on another member's occurrence."
    end
  end

  describe "formatters" do
    test "to_string produces a multi-line string" do
      exp = Explain.explain(~o"2022Y")
      text = Explain.to_string(exp)
      assert is_binary(text)
      assert String.contains?(text, "\n")
    end

    test "to_ansi produces a string with ANSI escape codes" do
      exp = Explain.explain(~o"2022Y")
      text = Explain.to_ansi(exp)
      # ANSI codes start with the escape sequence \e[ (or \x1B[).
      assert String.contains?(text, "\e[")
    end

    test "to_iodata produces tagged {atom, string} pairs" do
      exp = Explain.explain(~o"2022Y")
      parts = Explain.to_iodata(exp)
      assert Enum.all?(parts, fn {tag, text} -> is_atom(tag) and is_binary(text) end)
    end
  end

  describe "± margins" do
    test "a single year margin surfaces the margin and the grounding span" do
      explanation = Tempo.explain(~o"2000±1Y")

      assert explanation =~ "Margin: ±1 year"
      assert explanation =~ "groundings span [1999, 2002)"
    end

    test "a plural margin pluralises the unit" do
      assert Tempo.explain(~o"2000±2Y") =~
               "Margin: ±2 years — groundings span [1998, 2003)."
    end

    test "the margin is a tagged part" do
      parts = Explain.explain(~o"2000±1Y").parts
      assert Enum.any?(parts, fn {tag, _text} -> tag == :margin end)
    end

    test "an unanchored margin states the margin without an uncomputable span" do
      unanchored = %Tempo{
        time: [month: {6, [margin_of_error: 1]}],
        calendar: Calendrical.Gregorian
      }

      explanation = Tempo.explain(unanchored)

      assert explanation =~ "Margin: ±1 month."
      refute explanation =~ "groundings span"
    end

    test "a value without margins has no margin part" do
      refute Enum.any?(Explain.explain(~o"2022Y").parts, fn {tag, _} -> tag == :margin end)
    end
  end

  describe "Tempo.explain/1 (top-level delegation)" do
    test "returns the string form" do
      assert Tempo.explain(~o"2022Y") == Explain.to_string(Explain.explain(~o"2022Y"))
    end
  end

  describe "Tempo extensions" do
    test "a traditional-month selection names the traditional month" do
      prose = Tempo.explain(~o"R/../P1Y/FL8m15DN[u-ca=chinese]")
      assert prose =~ "in traditional month 8, on the 15th"
    end

    test "a traditional leap-month selection is described as the leap month" do
      prose = Tempo.explain(~o"R/../P1Y/FL6+m1DN[u-ca=chinese]")
      assert prose =~ "in the leap month after traditional month 6"
    end

    test "a week-start (`q`) is mentioned in the selection prose" do
      prose = Tempo.explain(~o"R4/../P2W/FL{2,7}K7qN")
      assert prose =~ "with weeks starting on Sunday"
    end

    test "a set exclusion is named" do
      prose = Tempo.explain(~o"{2024Y,2026Y,^2026Y}")
      assert prose =~ "excluding"
      assert prose =~ ~s(~o"2026Y")
    end

    test "a recurrence domain with an exclusion is explained, not an unusual shape" do
      prose = Tempo.explain(~o"R/{2020Y..2024Y,^2022Y}/P1Y/FL12M25DN")
      refute prose =~ "unusual shape"
      assert prose =~ "Domain:"
      assert prose =~ ~s(~o"2020Y"..~o"2024Y")
      assert prose =~ "excluding"
      assert prose =~ "in December, on the 25th"
    end

    test "an even-year domain filter is named" do
      prose = Tempo.explain(~o"R/{2020Y..2026Y}e/P1Y/FL1M1DN")
      assert prose =~ "even years only"
    end
  end
end
