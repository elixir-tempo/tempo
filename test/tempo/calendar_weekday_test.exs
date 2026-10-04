defmodule Tempo.CalendarWeekdayTest do
  @moduledoc """
  Weekday semantics across calendars on Calendrical ≥ 1.3, which
  numbers days of the week per each calendar's own tradition (Hebrew
  and Islamic weeks run Sunday–Saturday, Persian Saturday–Friday).
  Tempo's weekend/workday classification converts to `Calendar.ISO`
  first, so it is immune to the native numbering; `trunc(value, :week)`
  deliberately follows the value's own calendar.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  # 2026-08-26 is a Wednesday; 2026-08-29 a Saturday; 2026-08-28 a Friday.

  describe "weekend classification is immune to native weekday numbering" do
    test "a Hebrew Wednesday is a workday and a Hebrew Saturday a weekend day" do
      {:ok, wednesday} = Tempo.to_calendar(~o"2026-08-26", Calendrical.Hebrew)
      {:ok, saturday} = Tempo.to_calendar(~o"2026-08-29", Calendrical.Hebrew)

      refute Tempo.weekend?(wednesday)
      assert Tempo.weekend?(saturday)
    end

    test "an Islamic Friday is the Saudi weekend" do
      {:ok, friday} = Tempo.to_calendar(~o"2026-08-28", Calendrical.Islamic.Civil)

      assert Tempo.weekend?(friday, :SA)
      refute Tempo.weekend?(friday, :US)
    end

    test "classification agrees across the calendar conversion" do
      {:ok, hebrew} = Tempo.to_calendar(~o"2026-08-29", Calendrical.Hebrew)
      assert Tempo.weekend?(hebrew) == Tempo.weekend?(~o"2026-08-29")
    end
  end

  describe "the week a value truncates to follows its own calendar" do
    test "a Hebrew week begins on Sunday, a Gregorian week on Monday" do
      {:ok, hebrew_wednesday} = Tempo.to_calendar(~o"2026-08-26", Calendrical.Hebrew)

      # Gregorian: back to Monday 2026-08-24.
      assert Tempo.day(Tempo.trunc(~o"2026-08-26", :week)) == 24

      # Hebrew: 13 Elul 5786 rolls back to Sunday 10 Elul.
      hebrew_sunday = Tempo.trunc(hebrew_wednesday, :week)
      assert Tempo.day(hebrew_sunday) == 10
      assert hebrew_sunday.calendar == Calendrical.Hebrew
    end
  end

  describe "Hebrew calendar weeks parse and materialise" do
    # Enabled by Calendrical 1.3's week_of_year/weeks_in_year for the
    # Hebrew and Islamic calendars.
    test "a Hebrew week is a week-resolution span in its own calendar" do
      {:ok, week} = Tempo.from_iso8601("5786-W03", Calendrical.Hebrew)
      {:ok, interval} = Tempo.to_interval(week)

      assert Tempo.week(week) == 3
      assert interval.from.calendar == Calendrical.Hebrew
      assert Tempo.week(interval.to) == 4
    end

    test "a Hebrew week compares with Gregorian values across calendars" do
      {:ok, week} = Tempo.from_iso8601("5786-W03", Calendrical.Hebrew)

      assert Tempo.relation(~o"2026-08-26", week) in [
               :precedes,
               :preceded_by,
               :during,
               :meets,
               :met_by
             ]
    end
  end

  describe "week-axis arithmetic and accessors" do
    test "Tempo.week/1 reads week-axis values and single-week intervals" do
      assert Tempo.week(~o"2026Y32W") == 32
      assert Tempo.week(~o"2026-06-15") == nil

      {:ok, interval} = Tempo.to_interval(~o"2026Y32W")
      assert Tempo.week(interval) == 32
      assert Tempo.year(interval) == 2026
    end

    test "a multi-week interval is ambiguous" do
      {:ok, fortnight} = Tempo.to_interval(~o"2026Y32W/34W")
      assert_raise ArgumentError, ~r/ambiguous/, fn -> Tempo.week(fortnight) end
    end

    test "shifting a week-axis value steps weeks natively" do
      # Regression: normalising the week duration to days demanded
      # month/day keys the week axis lacks, raising KeyError.
      assert Tempo.shift(~o"2026Y32W", week: 1) == ~o"2026Y33W"
      assert Tempo.shift(~o"2026Y32W", week: -1) == ~o"2026Y31W"
      # 2026 has 53 ISO 8601 weeks.
      assert Tempo.shift(~o"2026Y52W", week: 2) == ~o"2027Y1W"
    end

    test "a month-axis value still takes weeks as seven days" do
      assert Tempo.shift(~o"2026-06-15", week: 1) == ~o"2026-06-22"
    end
  end

  describe "a step of days or hours from a week" do
    # 2026-W32 runs from Monday 3 August.
    test "a Gregorian week's day is the calendar date, carrying across weeks" do
      assert Tempo.shift(~o"2026Y32W", day: 2) == ~o"2026-08-05"
      assert Tempo.shift(~o"2026Y32W", day: 7) == ~o"2026-08-10"
      assert Tempo.shift(~o"2026Y32W", day: -1) == ~o"2026-08-02"
      assert Tempo.shift(~o"2026Y32W", week: 1, day: 2) == ~o"2026-08-12"
    end

    test "the week of the next year is stepped to before its days are" do
      # 2027-W32 runs from Monday 9 August.
      assert Tempo.shift(~o"2026Y32W", year: 1, day: 1) == ~o"2027-08-10"
    end

    test "a week whose days are in another year gives their dates" do
      assert Tempo.shift(~o"2026Y1W", day: 1) == ~o"2025-12-30"
      assert Tempo.shift(~o"2026Y53W", day: 6) == ~o"2027-01-03"
    end

    test "a sub-day duration steps the week's hours, carrying across days and weeks" do
      assert Tempo.shift(~o"2026Y32W", hour: 1) == ~o"2026-08-03T01"
      assert Tempo.shift(~o"2026Y32W", hour: 25) == ~o"2026-08-04T01"
      assert Tempo.shift(~o"2026Y32W", hour: -1) == ~o"2026-08-02T23"
    end

    test "a duration given as a value or as text steps to the date too" do
      assert Tempo.shift(~o"2026Y32W", ~o"P2D") == ~o"2026-08-05"
      assert Tempo.shift(~o"2026Y32W", "P2D") == ~o"2026-08-05"
      assert Tempo.shift(~o"2026Y32W", ~o"P1.5D") == ~o"2026-08-04T12"
    end

    test "a week steps by weeks and years to a week" do
      assert Tempo.shift(~o"2026Y32W", week: 1) == ~o"2026Y33W"
      assert Tempo.shift(~o"2026Y32W", year: 1) == ~o"2027Y32W"
    end

    test "a qualified week's day is a qualified date" do
      shifted = Tempo.shift(~o"2026-W32?", day: 2)

      assert shifted.time == [year: 2026, month: 8, day: 5]
      assert Tempo.qualification(shifted) == :uncertain
    end

    test "a calendar of weeks keeps its week and its day" do
      week = Tempo.from_iso8601!("2026Y32W", Calendrical.ISOWeek)

      assert Tempo.shift(week, day: 2).time == [year: 2026, week: 32, day_of_week: 3]
      assert Tempo.shift(week, day: 7).time == [year: 2026, week: 33, day_of_week: 1]
      assert Tempo.shift(week, hour: 25).time == [year: 2026, week: 32, day_of_week: 2, hour: 1]
    end

    test "a week with no year keeps its day of the week" do
      assert Tempo.shift(~o"7K", day: 1) == ~o"1K"
      assert match?({:error, %Tempo.UnanchoredError{}}, Tempo.shift(~o"25W3K", day: 5))
    end
  end

  describe "a week read by its days" do
    test "a day that enumerating a week gives is a one-day span of hours" do
      [monday] = Enum.take(~o"2026-W40", 1)
      {:ok, day} = Tempo.to_interval(monday)

      assert Tempo.duration(day) == ~o"P1D"
      assert Enum.count(monday) == 24
    end

    # 2026-W40 runs from Monday 28 September to Sunday 4 October.
    test "a Gregorian week's days are the dates they name" do
      assert Enum.to_list(~o"2026-W40") == [
               ~o"2026-09-28",
               ~o"2026-09-29",
               ~o"2026-09-30",
               ~o"2026-10-01",
               ~o"2026-10-02",
               ~o"2026-10-03",
               ~o"2026-10-04"
             ]
    end

    test "Enum counts, indexes, slices and searches a week's days" do
      week = ~o"2026-W40"
      [monday] = Enum.take(week, 1)

      assert Enum.count(week) == 7
      assert Enum.at(week, 3) == ~o"2026-10-01"
      assert Enum.slice(week, 5, 2) == [~o"2026-10-03", ~o"2026-10-04"]
      assert Enum.member?(week, monday)
      assert Enum.member?(week, ~o"2026-09-30")
      refute Enum.member?(week, ~o"2026-10-05")
    end

    test "the interval a week converts to is walked by the same dates" do
      {:ok, interval} = Tempo.to_interval(~o"2026-W40")

      assert Enum.to_list(interval) == Enum.to_list(~o"2026-W40")
      assert Enum.count(interval) == 7
      assert Enum.at(interval, 3) == ~o"2026-10-01"
      assert Enum.member?(interval, ~o"2026-09-30")
      refute Enum.member?(interval, ~o"2026-10-05")
    end

    test "a week's days in another year, and a week counted from the year's end" do
      assert Enum.take(~o"2026Y1W", 2) == [~o"2025-12-29", ~o"2025-12-30"]
      assert List.last(Enum.to_list(~o"2026Y53W")) == ~o"2027-01-03"
      assert Enum.take(~o"2026Y-1W", 1) == [~o"2026-12-28"]
    end

    test "a set, a mask and an unspecified day of a week are walked as dates" do
      assert Enum.to_list(~o"2026Y40W{1,3}K") == [~o"2026-09-28", ~o"2026-09-30"]
      assert Enum.take(~o"2026Y40WX*K", 2) == [~o"2026-09-28", ~o"2026-09-29"]
      assert Enum.to_list(~o"{2026,2027}Y40W1K") == [~o"2026-09-28", ~o"2027-10-04"]

      assert Enum.to_list(~o"2026Y40W{1,3}KT{10,11}H") == [
               ~o"2026-09-28T10",
               ~o"2026-09-28T11",
               ~o"2026-09-30T10",
               ~o"2026-09-30T11"
             ]
    end

    test "a week of weeks is walked by its weeks" do
      assert Enum.to_list(~o"2026Y{40,41}W") == [~o"2026Y40W", ~o"2026Y41W"]
      assert Enum.to_list(~o"2026-W40/2026-W42") == [~o"2026Y40W", ~o"2026Y41W"]
    end

    test "an interval from a week is walked by dates" do
      assert Enum.to_list(~o"2026-W40/P3D") == [~o"2026-09-28", ~o"2026-09-29", ~o"2026-09-30"]
      assert Enum.take(~o"2026-W40/2026-10-15", 2) == [~o"2026-09-28", ~o"2026-09-29"]
      assert Enum.to_list(~o"P2D/2026-W40") == [~o"2026-09-26", ~o"2026-09-27"]
    end

    test "a qualified week's days are qualified dates" do
      [monday | _rest] = Enum.to_list(~o"2026-W40?")

      assert monday.time == [year: 2026, month: 9, day: 28]
      assert Tempo.qualification(monday) == :uncertain
    end

    test "a calendar of weeks walks its week by its own days" do
      week = Tempo.from_iso8601!("2026Y40W", Calendrical.ISOWeek)

      assert week |> Enum.take(2) |> Enum.map(& &1.time) == [
               [year: 2026, week: 40, day_of_week: 1],
               [year: 2026, week: 40, day_of_week: 2]
             ]

      {:ok, interval} = Tempo.to_interval(week)
      assert interval |> Enum.at(3) |> Map.fetch!(:time) == [year: 2026, week: 40, day_of_week: 4]
    end

    test "a week with no year is walked by its days of the week" do
      assert Enum.take(~o"25W", 2) == [~o"25W1K", ~o"25W2K"]
    end

    test "a zoned week's day steps its hours on the time line" do
      # New York springs forward in the early hours of Sunday 8 March 2026.
      saturday = Tempo.from_iso8601!("2026-W10[America/New_York]") |> Enum.at(5)

      assert saturday.time == [year: 2026, month: 3, day: 7]
      assert Tempo.shift(saturday, hour: 28).time == [year: 2026, month: 3, day: 8, hour: 5]
    end
  end

  describe "an end counted from a week" do
    test "an interval's end a duration counts to is a date" do
      assert Tempo.to_interval(~o"2026-W40/P3D") == Tempo.to_interval(~o"2026-W40/2026-W40-4")
      assert {:ok, counted} = Tempo.to_interval(~o"2026-W40/P3D")
      assert Interval.to(counted) == ~o"2026-10-01"

      assert {:ok, counted_back} = Tempo.to_interval(~o"P3D/2026-W40")
      assert Interval.from(counted_back) == ~o"2026-09-25"
    end

    test "a week of whole weeks keeps its weeks" do
      assert {:ok, counted} = Tempo.to_interval(~o"2026-W40/P1W")
      assert Interval.to(counted) == ~o"2026Y41W"
    end

    test "each occurrence a day apart from a week is a day" do
      {:ok, occurrences} = Tempo.to_interval(~o"R3/2026-W40/P1D")

      assert occurrences |> IntervalSet.members() |> Enum.map(&Interval.to/1) ==
               [~o"2026-09-29", ~o"2026-09-30", ~o"2026-10-01"]
    end
  end

  describe "a week extended to its days" do
    test "extend_resolution/2 and at_resolution/2 give the date of its first day" do
      assert Tempo.extend_resolution(~o"2026-W40", :day) == ~o"2026-09-28"
      assert Tempo.at_resolution(~o"2026-W40", :day) == ~o"2026-09-28"
      assert Tempo.extend_resolution(~o"2026-W40", :hour) == ~o"2026-09-28T00"
    end

    test "a calendar of weeks is extended to its first day of the week" do
      week = Tempo.from_iso8601!("2026Y40W", Calendrical.ISOWeek)

      assert Tempo.extend_resolution(week, :day).time == [year: 2026, week: 40, day_of_week: 1]
    end
  end

  describe "set operations on a week" do
    test "a week cut below its days is written in dates" do
      {:ok, rest} = Tempo.difference(~o"2026-W40", ~o"2026-W40/P3D")

      assert rest |> IntervalSet.members() |> Enum.map(&Interval.endpoints/1) ==
               [{~o"2026-10-01", ~o"2026-10-05"}]

      {:ok, shared} = Tempo.intersection(~o"2026-W40/P3D", ~o"2026-W40")

      assert shared |> IntervalSet.members() |> Enum.map(&Interval.endpoints/1) ==
               [{~o"2026-09-28", ~o"2026-10-01"}]
    end

    test "a week kept whole beside a date is walked by its seven days" do
      {:ok, both} = Tempo.union(~o"2026-W40", ~o"2026-10-10")
      [week, _day] = IntervalSet.members(both)

      assert Enum.to_list(week) == Enum.to_list(~o"2026-W40")
    end

    test "whole weeks stay weeks" do
      {:ok, shared} = Tempo.intersection(~o"2026-W40", ~o"2026-W39/2026-W42")

      assert shared |> IntervalSet.members() |> Enum.map(&Interval.endpoints/1) ==
               [{~o"2026Y40W", ~o"2026Y41W"}]
    end
  end
end
