defmodule Tempo.DayOfYearWithinTest do
  @moduledoc """
  A day of the year selected from a month or a week.

  A day of the year selected from a period that is a whole month or week is
  each day the period holds that is the day of its year the part names: the
  166th day of 2026 is 15 June, from June and from its week. A week holds
  the days of two years at most, and a day counted from the end of the year
  is counted in the year the day is in.

  The measure is Elixir's own `Date`: each day of the period is asked its
  day of the year, counted from the year's start and from its end.
  """
  use ExUnit.Case, async: true

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet

  # A part as it is written, and the days of a year it names.
  @parts [
    {"166O", [166]},
    {"1O", [1]},
    {"-1O", [-1]},
    {"{1..3}O", [1, 2, 3]},
    {"{360..366}O", Enum.to_list(360..366)},
    {"{-3..-1}O", [-3, -2, -1]},
    {"{59,60,61}O", [59, 60, 61]}
  ]

  # Months of a leap year and of a common one, and weeks that hold the days
  # of two years.
  @months for year <- [2024, 2026], month <- 1..12, do: {year, month}
  @weeks [{2026, 25}, {2026, 1}, {2026, 53}, {2025, 1}, {2024, 52}, {2024, 9}]

  ## The measure

  defp named?(date, numbers) do
    from_start = Date.day_of_year(date)
    from_end = from_start - days_in_year(date) - 1

    from_start in numbers or from_end in numbers
  end

  defp days_in_year(date), do: if(Date.leap_year?(date), do: 366, else: 365)

  defp seconds(%Date{} = date),
    do:
      date |> NaiveDateTime.new!(~T[00:00:00]) |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp expected(days, numbers) do
    for date <- days, named?(date, numbers), do: {seconds(date), seconds(Date.add(date, 1))}
  end

  defp spans({:ok, %IntervalSet{} = set}) do
    for span <- IntervalSet.members(set) do
      {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}
    end
  end

  defp pad(number), do: String.pad_leading(Integer.to_string(number), 2, "0")

  # ISO 8601's first week is the one that holds 4 January.
  defp monday_of_iso_week(year, week) do
    year
    |> Date.new!(1, 4)
    |> Date.beginning_of_week(:monday)
    |> Date.add(7 * (week - 1))
  end

  describe "a day of the year selected from a month" do
    test "is each day of the month that is the day of its year named" do
      for {year, month} <- @months, {part, numbers} <- @parts do
        first = Date.new!(year, month, 1)
        month_value = Tempo.from_iso8601!("#{year}-#{pad(month)}")

        assert {year, month, part, spans(Tempo.select(month_value, Tempo.from_iso8601!(part)))} ==
                 {year, month, part,
                  expected(Date.range(first, Date.end_of_month(first)), numbers)}
      end
    end
  end

  describe "a day of the year selected from a week" do
    test "is each day of the week that is the day of its own year named" do
      for {year, week} <- @weeks, {part, numbers} <- @parts do
        monday = monday_of_iso_week(year, week)
        week_value = Tempo.from_iso8601!("#{year}-W#{pad(week)}")

        assert {year, week, part, spans(Tempo.select(week_value, Tempo.from_iso8601!(part)))} ==
                 {year, week, part, expected(Date.range(monday, Date.add(monday, 6)), numbers)}
      end
    end
  end
end
