defmodule Tempo.WorkdayInACalendarOfWeeksTest do
  @moduledoc """
  A workday counted from a day and a time of day in a calendar of weeks.

  A calendar of weeks keeps a value's week and day of the week beside a
  time of day, where a week date of the Gregorian calendar is read as a
  month and a day. The workday functions read a day's date only where it
  was written alone, so `2024-W10-7T01[u-ca=iso-week]` was a
  `Tempo.ResolutionError` that said it denoted no day, and `workday?/2` and
  `weekend?/2` raised.

  The measure is Elixir's own `Date` and Erlang's `:calendar`: a Gregorian
  date's week and day of the week, the weekend written here, and the
  workday stepped to a day at a time.
  """
  use ExUnit.Case, async: true

  alias Tempo.IntervalSet

  @weekend [6, 7]

  # A stretch across the end of a year of 52 weeks, and one of 53.
  @days Enum.to_list(Date.range(~D[2024-12-23], ~D[2025-01-12])) ++
          Enum.to_list(Date.range(~D[2026-12-21], ~D[2027-01-10]))

  @clocks [{"", []}, {"T01", [hour: 1]}, {"T10:30", [hour: 10, minute: 30]}]

  ## The measure

  defp off?(date, holidays), do: Date.day_of_week(date) in @weekend or date in holidays

  defp first_workday(date, step, holidays) do
    next = Date.add(date, step)
    if off?(next, holidays), do: first_workday(next, step, holidays), else: next
  end

  defp workdays_on(date, 0, _holidays), do: date

  defp workdays_on(date, count, holidays) when count > 0,
    do: date |> first_workday(1, holidays) |> workdays_on(count - 1, holidays)

  defp workdays_on(date, count, holidays),
    do: date |> first_workday(-1, holidays) |> workdays_on(count + 1, holidays)

  # The nearer workday, the one before where they are as near.
  defp nearest(date, holidays) do
    if off?(date, holidays), do: nearest(date, 1, holidays), else: date
  end

  defp nearest(date, distance, holidays) do
    cond do
      not off?(Date.add(date, -distance), holidays) -> Date.add(date, -distance)
      not off?(Date.add(date, distance), holidays) -> Date.add(date, distance)
      true -> nearest(date, distance + 1, holidays)
    end
  end

  # A Gregorian date as the units a calendar of weeks writes it in.
  defp week_units(%Date{} = date) do
    {year, week} = :calendar.iso_week_number(Date.to_erl(date))
    [year: year, week: week, day_of_week: Date.day_of_week(date)]
  end

  defp in_weeks(%Date{} = date, clock, suffix \\ "") do
    [year: year, week: week, day_of_week: day] = week_units(date)
    week = week |> Integer.to_string() |> String.pad_leading(2, "0")

    Tempo.from_iso8601!("#{year}-W#{week}-#{day}#{clock}#{suffix}[u-ca=iso-week]")
  end

  describe "a workday counted from a day and a time of a calendar of weeks" do
    test "is the day Elixir's Date counts to, at the same time of day" do
      for date <- @days,
          {clock, units} <- @clocks,
          {name, operation, expected} <- [
            {"add 1", &Tempo.add_workdays(&1, 1, :US), workdays_on(date, 1, [])},
            {"add 5", &Tempo.add_workdays(&1, 5, :US), workdays_on(date, 5, [])},
            {"add -1", &Tempo.add_workdays(&1, -1, :US), workdays_on(date, -1, [])},
            {"add -7", &Tempo.add_workdays(&1, -7, :US), workdays_on(date, -7, [])},
            {"add 0", &Tempo.add_workdays(&1, 0, :US), date},
            {"next", &Tempo.next_workday(&1, :US), first_workday(date, 1, [])},
            {"previous", &Tempo.previous_workday(&1, :US), first_workday(date, -1, [])},
            {"nearest", &Tempo.nearest_workday(&1, :US), nearest(date, [])},
            {"following", &Tempo.roll_to_workday(&1, :US),
             if(off?(date, []), do: first_workday(date, 1, []), else: date)},
            {"preceding", &Tempo.roll_to_workday(&1, :US, roll: :preceding),
             if(off?(date, []), do: first_workday(date, -1, []), else: date)}
          ] do
        assert %Tempo{calendar: Calendrical.ISOWeek, time: time} =
                 operation.(in_weeks(date, clock))

        assert {date, clock, name, time} == {date, clock, name, week_units(expected) ++ units}
      end
    end

    test "is asked whether it is a workday or on the weekend" do
      for date <- @days, {clock, _units} <- @clocks do
        value = in_weeks(date, clock)

        assert {date, clock, Tempo.workday?(value, :US)} == {date, clock, not off?(date, [])}
        assert {date, clock, Tempo.weekend?(value, :US)} == {date, clock, off?(date, [])}
      end
    end

    test "steps over a holiday, given in either calendar" do
      # Christmas Day and New Year's Day of the first stretch.
      holidays = [~D[2024-12-25], ~D[2025-01-01]]

      for except <- [
            IntervalSet.new!(
              Enum.map(holidays, &(&1 |> Tempo.from_date() |> Tempo.to_interval!()))
            ),
            IntervalSet.new!(Enum.map(holidays, &(&1 |> in_weeks("") |> Tempo.to_interval!())))
          ],
          business_days = Tempo.workdays(:US, except: except),
          date <- Date.range(~D[2024-12-23], ~D[2025-01-05]),
          {clock, units} <- @clocks do
        value = in_weeks(date, clock)

        assert %Tempo{time: next} = Tempo.next_workday(value, business_days)
        assert %Tempo{time: previous} = Tempo.previous_workday(value, business_days)

        assert {date, clock, next} ==
                 {date, clock, week_units(first_workday(date, 1, holidays)) ++ units}

        assert {date, clock, previous} ==
                 {date, clock, week_units(first_workday(date, -1, holidays)) ++ units}

        assert {date, clock, Tempo.workday?(value, business_days)} ==
                 {date, clock, not off?(date, holidays)}
      end
    end

    test "keeps its zone" do
      # Sunday 10 March 2024, the day New York's clocks go forward.
      value = in_weeks(~D[2024-03-10], "T01", "[America/New_York]")

      assert %Tempo{time: time, extended: %{zone_id: "America/New_York"}} =
               Tempo.add_workdays(value, 1, :US)

      assert time == week_units(~D[2024-03-11]) ++ [hour: 1]
    end

    test "is still refused where it denotes no one day, and by a modified roll" do
      for text <- ["2024-W10", "2024-W10-{6,7}T01", "2024-W10-XT01"] do
        value = Tempo.from_iso8601!(text <> "[u-ca=iso-week]")

        assert {^text, {:error, %Tempo.ResolutionError{operation: :next_workday, target: :day}}} =
                 {text, Tempo.next_workday(value, :US)}
      end

      assert {:error, %Tempo.ResolutionError{operation: :roll_to_workday, target: :month}} =
               Tempo.roll_to_workday(in_weeks(~D[2024-03-10], "T01"), :US,
                 roll: :modified_following
               )
    end
  end
end
