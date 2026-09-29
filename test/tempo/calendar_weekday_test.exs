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

  describe "week-axis day durations" do
    test "a day duration steps day_of_week, carrying across weeks" do
      # The sigil parses week-dates to the month axis, so pin the
      # week-axis components directly.
      assert Tempo.shift(~o"2026Y32W", day: 2).time == [year: 2026, week: 32, day_of_week: 3]
      assert Tempo.shift(~o"2026Y32W", day: 7).time == [year: 2026, week: 33, day_of_week: 1]
    end

    test "a sub-day duration steps the week's hours, carrying across days and weeks" do
      assert Tempo.shift(~o"2026Y32W", hour: 1).time ==
               [year: 2026, week: 32, day_of_week: 1, hour: 1]

      assert Tempo.shift(~o"2026Y32W", hour: 25).time ==
               [year: 2026, week: 32, day_of_week: 2, hour: 1]

      assert Tempo.shift(~o"2026Y32W", hour: -1).time ==
               [year: 2026, week: 31, day_of_week: 7, hour: 23]
    end
  end

  describe "a week read by its days" do
    test "a day that enumerating a week gives is a one-day span of hours" do
      [monday] = Enum.take(~o"2026-W40", 1)
      {:ok, day} = Tempo.to_interval(monday)

      assert Tempo.duration(day) == ~o"P1D"
      assert Enum.count(monday) == 24
    end

    test "Enum counts, indexes, slices and searches a week's days" do
      week = ~o"2026-W40"
      [monday] = Enum.take(week, 1)

      assert Enum.count(week) == 7
      assert Enum.at(week, 3).time == [year: 2026, week: 40, day_of_week: 4]
      assert week |> Enum.slice(5, 2) |> Enum.map(& &1.time[:day_of_week]) == [6, 7]
      assert Enum.member?(week, monday)
    end

    test "a zoned week's day steps its hours on the time line" do
      # New York springs forward in the early hours of Sunday 8 March 2026.
      saturday = Tempo.from_iso8601!("2026-W10[America/New_York]") |> Enum.at(5)

      assert Tempo.shift(saturday, hour: 28).time ==
               [year: 2026, week: 10, day_of_week: 7, hour: 5]
    end
  end
end
