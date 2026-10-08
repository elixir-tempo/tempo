defmodule Tempo.RRule.WeekNumberFromWkstTest do
  @moduledoc """
  The week of the year a day is in, counted from a rule's `WKST`.

  RFC 5545 §3.3.10 numbers a year's weeks from the day `WKST` names, week 1
  being the first with four of its days in the year, and a rule of days or
  less with a `BYWEEKNO` asks each of its periods which week it is in. The
  year's weeks were listed to find the day's among them, 53 dates for each
  day asked, and the week is now counted from the first day of week 1.

  The measure is Elixir's own `Date`: the week a day is in starts on the
  `WKST` weekday on or before it, belongs to the year its fourth day is in,
  and is as many weeks on from the week that holds 4 January of that year.
  For a week that starts on Monday it is checked against Erlang's
  `:calendar.iso_week_number/1`.
  """
  use ExUnit.Case, async: true

  alias Calendrical.Gregorian
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.Validation

  @weekdays %{
    1 => {:monday, "MO"},
    2 => {:tuesday, "TU"},
    3 => {:wednesday, "WE"},
    4 => {:thursday, "TH"},
    5 => {:friday, "FR"},
    6 => {:saturday, "SA"},
    7 => {:sunday, "SU"}
  }

  @days Date.range(~D[2018-12-20], ~D[2027-01-15])

  ## The measure

  defp week_start(date, wkst), do: Date.beginning_of_week(date, elem(@weekdays[wkst], 0))

  defp first_week_start(year, wkst), do: week_start(Date.new!(year, 1, 4), wkst)

  defp weeks_in(year, wkst),
    do: div(Date.diff(first_week_start(year + 1, wkst), first_week_start(year, wkst)), 7)

  # The year a day's week belongs to, the week's number in it, and how many
  # weeks that year has.
  defp week_of(date, wkst) do
    start = week_start(date, wkst)
    year = Date.add(start, 3).year
    {year, div(Date.diff(start, first_week_start(year, wkst)), 7) + 1, weeks_in(year, wkst)}
  end

  defp named?(date, wkst, weeks) do
    {_year, week, weeks_in_year} = week_of(date, wkst)
    Enum.any?(weeks, &(&1 == week or &1 == week - weeks_in_year - 1))
  end

  defp days_of({:ok, %IntervalSet{} = set}) do
    for occurrence <- IntervalSet.members(set) do
      {:ok, date} = Tempo.to_date(Interval.from(occurrence))
      Date.convert!(date, Calendar.ISO)
    end
  end

  describe "the measure" do
    test "is ISO 8601's week where the week starts on Monday" do
      for date <- @days do
        {year, week, _weeks} = week_of(date, 1)
        assert {date, {year, week}} == {date, :calendar.iso_week_number(Date.to_erl(date))}
      end
    end
  end

  describe "the week of the year a week is, counted from a day of the week" do
    test "is the measure's, with the weeks its year has, for each day a week can start on" do
      for wkst <- 1..7, date <- @days, Date.day_of_week(date) == wkst do
        {year, week, weeks} = week_of(date, wkst)
        start = Date.convert!(date, Gregorian)

        assert {wkst, date, Validation.week_number(Gregorian, year, wkst, start)} ==
                 {wkst, date, {:ok, week, weeks}}
      end
    end

    test "is none in a year the week does not belong to" do
      # Monday 29 December 2025 starts week 1 of 2026.
      start = Date.convert!(~D[2025-12-29], Gregorian)

      assert Validation.week_number(Gregorian, 2026, 1, start) == {:ok, 1, 53}
      assert Validation.week_number(Gregorian, 2025, 1, start) == :error
      assert Validation.week_number(Gregorian, 2027, 1, start) == :error
    end
  end

  describe "a rule of days with a week of the year" do
    test "keeps the days of the weeks it names, counted from its WKST" do
      weeks = [1, 20, 53, -1]

      for wkst <- [1, 3, 6, 7] do
        {_day, code} = @weekdays[wkst]

        {:ok, rule} =
          RRule.parse("FREQ=DAILY;BYWEEKNO=1,20,53,-1;WKST=#{code};UNTIL=20270115",
            from: Tempo.from_iso8601!("2018-12-20")
          )

        assert {code, days_of(Tempo.to_interval(rule))} ==
                 {code, Enum.filter(@days, &named?(&1, wkst, weeks))}
      end
    end
  end

  describe "a rule of days or less counted through the weeks it names" do
    # The walk goes on from one week named to the next, where each day
    # between was asked its week: a year of them for one week, which a count
    # of many years did not come to the end of.
    defp days_of_week_of_year(year, week, wkst),
      do: for(day <- 0..6, do: Date.add(first_week_start(year, wkst), (week - 1) * 7 + day))

    test "has the Monday of week 20 of ninety years" do
      {:ok, rule} =
        RRule.parse("FREQ=DAILY;BYWEEKNO=20;BYDAY=MO;COUNT=90",
          from: Tempo.from_iso8601!("2026-01-01")
        )

      mondays = for year <- 2026..2115, do: hd(days_of_week_of_year(year, 20, 1))

      assert Enum.map(mondays, &:calendar.iso_week_number(Date.to_erl(&1))) ==
               for(year <- 2026..2115, do: {year, 20})

      assert days_of(Tempo.to_interval(rule)) == mondays
    end

    test "has the days of a week 53 in the years that have one, counted from each WKST" do
      for wkst <- [1, 4, 7] do
        {_day, code} = @weekdays[wkst]

        {:ok, rule} =
          RRule.parse("FREQ=DAILY;BYWEEKNO=53;WKST=#{code};COUNT=21",
            from: Tempo.from_iso8601!("2026-01-01")
          )

        long_years = 2025..2080 |> Enum.filter(&(weeks_in(&1, wkst) == 53))

        expected =
          long_years
          |> Enum.flat_map(&days_of_week_of_year(&1, 53, wkst))
          |> Enum.reject(&(Date.compare(&1, ~D[2026-01-01]) == :lt))
          |> Enum.take(21)

        assert {code, days_of(Tempo.to_interval(rule))} == {code, expected}
      end
    end

    test "has the last week of each year, and the first, through a turn of the year" do
      {:ok, rule} =
        RRule.parse("FREQ=DAILY;BYWEEKNO=-1,1;COUNT=70",
          from: Tempo.from_iso8601!("2026-06-01")
        )

      expected =
        2026..2032
        |> Enum.flat_map(fn year ->
          days_of_week_of_year(year, 1, 1) ++ days_of_week_of_year(year, weeks_in(year, 1), 1)
        end)
        |> Enum.reject(&(Date.compare(&1, ~D[2026-06-01]) == :lt))
        |> Enum.take(70)

      assert days_of(Tempo.to_interval(rule)) == expected
    end

    test "has nine o'clock on each day of week 20 in a rule of hours" do
      {:ok, rule} =
        RRule.parse("FREQ=HOURLY;BYWEEKNO=20;BYHOUR=9;COUNT=50",
          from: Tempo.from_iso8601!("2026-01-01T00:00:00")
        )

      {:ok, set} = Tempo.to_interval(rule)

      expected =
        2026..2034
        |> Enum.flat_map(&days_of_week_of_year(&1, 20, 1))
        |> Enum.take(50)
        |> Enum.map(&[year: &1.year, month: &1.month, day: &1.day, hour: 9, minute: 0, second: 0])

      assert Enum.map(IntervalSet.members(set), &Interval.from(&1).time) == expected
    end
  end
end
