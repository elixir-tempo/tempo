defmodule Tempo.Iso8601.WeekDateTest do
  use ExUnit.Case, async: true

  # A week date of the Gregorian calendar (`2026-W25-3`) is the date ISO 8601
  # gives it: weeks start on a Monday, and week 1 is the week that holds the
  # year's first Thursday. Tempo asks `Calendrical.ISOWeek`, the calendar
  # that is those weeks, for the date and for how many weeks a year has.
  #
  # The measure is Erlang's `:calendar`, asked of every day of two centuries:
  # the week-based year, the week and the weekday it gives a date are the
  # week date that names the date.

  @years 1900..2100

  defp days do
    Date.range(Date.new!(@years.first, 1, 1), Date.new!(@years.last, 12, 31))
  end

  # The weeks of a year by Erlang's count: 28 December is always in the last.
  defp weeks_in(year) do
    {^year, weeks} = :calendar.iso_week_number({year, 12, 28})
    weeks
  end

  defp monday_of(year, week) do
    Enum.find(Date.range(Date.new!(year - 1, 12, 25), Date.new!(year + 1, 1, 7)), fn date ->
      :calendar.iso_week_number(Date.to_erl(date)) == {year, week} and Date.day_of_week(date) == 1
    end)
  end

  describe "a year, a week and a day of it" do
    test "are the date Erlang gives them, on every day of two centuries" do
      for date <- days() do
        {week_year, week} = :calendar.iso_week_number(Date.to_erl(date))
        day = :calendar.day_of_the_week(Date.to_erl(date))

        assert {date, Tempo.new(year: week_year, week: week, day_of_week: day)} ==
                 {date, {:ok, Tempo.from_date(date)}}
      end
    end

    test "are read from text as that date, in the first and the last week of each year" do
      for year <- @years, week <- [1, weeks_in(year)], day <- 1..7 do
        monday = monday_of(year, week)
        date = Date.add(monday, day - 1)
        text = "#{year}-W#{String.pad_leading(Integer.to_string(week), 2, "0")}-#{day}"

        assert {text, Tempo.from_iso8601(text)} == {text, {:ok, Tempo.from_date(date)}}
      end
    end

    test "are no date in a week the year does not have, or on a day no week has" do
      for year <- @years do
        beyond = weeks_in(year) + 1

        assert {year, match?({:error, _}, Tempo.new(year: year, week: beyond, day_of_week: 1))} ==
                 {year, true}

        assert {year, match?({:error, _}, Tempo.new(year: year, week: 0, day_of_week: 1))} ==
                 {year, true}

        assert {year, match?({:error, _}, Tempo.new(year: year, week: 1, day_of_week: 8))} ==
                 {year, true}
      end
    end
  end

  describe "a year's weeks" do
    test "are as many as Erlang counts, the last of them the week counted from the end" do
      for year <- @years do
        weeks = weeks_in(year)

        # The last week is read; one more is not.
        assert {year, match?({:ok, _}, Tempo.new(year: year, week: weeks))} == {year, true}
        assert {year, match?({:error, _}, Tempo.new(year: year, week: weeks + 1))} == {year, true}

        assert {year, Tempo.new(year: year, week: -1, day_of_week: 1)} ==
                 {year, {:ok, Tempo.from_date(monday_of(year, weeks))}}
      end
    end
  end
end
