defmodule Tempo.Rounding do
  @moduledoc false

  alias Tempo.RoundingError
  alias Tempo.Validation

  @hours_in_day 24
  @seconds_in_minute 60
  @minutes_in_hour 60
  @minutes_in_day @minutes_in_hour * @hours_in_day
  # @seconds_in_hour @seconds_in_minute * @minutes_in_hour
  # @seconds_in_day @seconds_in_hour * @hours_in_day

  def round(%Tempo{time: time, calendar: calendar} = tempo, time_unit) do
    {resolution, _} = Tempo.resolution(tempo)
    round(time, calendar, resolution, time_unit)
  end

  # Round to year

  defp round([{:year, _year}, {:month, _month}, {:day, _day}] = time, calendar, :day, :year) do
    time
    |> round(calendar, :day, :month)
    |> round(calendar, :month, :year)
  end

  defp round([{:year, _year}, {:week, _month}, {:day, _day}] = time, calendar, :day, :year) do
    time
    |> round(calendar, :day, :week)
    |> round(calendar, :week, :year)
  end

  defp round([{:year, year}, {:month, month}], calendar, :month, :year) do
    if month <= div(calendar.months_in_year(year), 2) do
      [{:year, year}]
    else
      {year, _month, _day} = calendar.plus(year, 1, 1, :years, 1)
      [{:year, year}]
    end
  end

  defp round([{:year, year}, {:week, week}], calendar, :week, :year) do
    if week <= div(Validation.iso_weeks_in_year(year, calendar), 2) do
      [{:year, year}]
    else
      [{:year, year + 1}]
    end
  end

  defp round([{:year, year}, {:day, day}], calendar, :day, :year) do
    if day <= div(calendar.days_in_year(year), 2) do
      [{:year, year}]
    else
      [{:year, year + 1}]
    end
  end

  defp round([{:year, _year}] = time, _calendar, :year, :year) do
    time
  end

  # Round to month

  defp round([{:year, year}, {:month, month}, {:day, day}], calendar, :day, :month) do
    if day <= div(calendar.days_in_month(year, month), 2) do
      [{:year, year}, {:month, month}]
    else
      {year, month, _day} = calendar.plus(year, month, 1, :months, 1)
      [{:year, year}, {:month, month}]
    end
  end

  defp round([{:year, _year}, {:month, _month}] = time, _calendar, :month, :month) do
    time
  end

  defp round([{:month, _month}] = time, _calendar, :month, :month) do
    time
  end

  # Round to week

  defp round([{:year, year}, {:week, week}, {:day, day}], calendar, :day, :week) do
    if day <= div(calendar.days_in_week(), 2) do
      [{:year, year}, {:week, week}]
    else
      {year, week, _day} = calendar.plus(year, week, 1, :weeks, 1)
      [{:year, year}, {:week, week}]
    end
  end

  defp round([{:year, _year}, {:week, _week}] = time, _calendar, :week, :week) do
    time
  end

  defp round([{:week, _week}] = time, _calendar, :week, :week) do
    time
  end

  # Round to day

  defp round([{:year, _year}, {:month, _month}, {:day, _day}] = time, _calendar, :day, :day) do
    time
  end

  defp round([{:year, _year}, {:week, _month}, {:day, _day}] = time, _calendar, :day, :day) do
    time
  end

  defp round([{:year, _year}, {:day, _day}] = time, _calendar, :day, :day) do
    time
  end

  defp round([{:day, _day}] = time, _calendar, :day, :day) do
    time
  end

  # Round to hour

  defp round(
         [{:hour, _hour}, {:minute, _minute}, {:second, _second}] = time,
         calendar,
         :second,
         :hour
       ) do
    time
    |> round(calendar, :second, :minute)
    |> round(calendar, :minute, :hour)
  end

  defp round([{:hour, hour}, {:minute, minute}], calendar, :minute, :hour) do
    if minute <= div(@minutes_in_hour, 2) do
      [hour: hour]
    else
      round([hour: hour + 1], calendar, :hour, :hour)
    end
  end

  defp round([{:hour, hour}], _calendar, :hour, :hour) when hour > @hours_in_day - 1 do
    [day: 1, hour: 0]
  end

  defp round([{:hour, _hour}] = time_of_day, _calendar, :hour, :hour) do
    time_of_day
  end

  # Round to minute

  defp round([{:hour, hour}, {:minute, minute}, {:second, second}], calendar, :second, :minute) do
    if second <= div(@seconds_in_minute, 2) do
      [hour: hour, minute: minute]
    else
      round([hour: hour, minute: minute + 1], calendar, :minute, :minute)
    end
  end

  defp round([{:hour, hour}, {:minute, minute}], calendar, :minute, :minute)
       when hour > @hours_in_day - 1 do
    round([day: 1, hour: 0, minute: minute], calendar, :minute, :minute)
  end

  defp round([{:hour, hour}, {:minute, minute}], calendar, :minute, :minute)
       when minute > @minutes_in_day - 1 do
    round([hour: hour + 1, minute: 0], calendar, :minute, :minute)
  end

  defp round([{:hour, _hour}, {:minute, _minute}] = time_of_day, _calendar, :minute, :minute) do
    time_of_day
  end

  defp round([{:minute, _minute}] = time_of_day, _calendar, :minute, :minute) do
    time_of_day
  end

  # Round to second

  defp round(
         [{:hour, _hour}, {:minute, _minute}, {:second, _second}] = time_of_day,
         _calendar,
         :second,
         :second
       ) do
    time_of_day
  end

  defp round([{:minute, _minute}, {:second, _second}] = time_of_day, _calendar, :second, :second) do
    time_of_day
  end

  defp round([{:second, _second}] = time_of_day, _calendar, :second, :second) do
    time_of_day
  end

  # Rounding from a time-of-day resolution (hour/minute/second)
  # *up* to a calendar-unit resolution (year/month/week/day) would
  # require crossing the day boundary via Tempo–Duration addition
  # (e.g. 23:30 rounded to day is "midnight of the next day"). That
  # crossing pathway isn't implemented yet — the fallthrough clause
  # below returns a clear `Tempo.RoundingError`. When the pathway
  # lands, re-introduce a branch here that uses `Tempo.Math.add/2`
  # to carry the rollover rather than a separate shift module.

  # All others are error

  defp round(time, _calendar, resolution, time_unit) do
    {:error, rounding_error(time, resolution, time_unit)}
  end

  defp rounding_error(time, resolution, time_unit) do
    RoundingError.exception(
      unit: time_unit,
      reason:
        "Time #{inspect(time)} resolution #{inspect(resolution)} cannot be rounded to #{inspect(time_unit)}"
    )
  end
end
