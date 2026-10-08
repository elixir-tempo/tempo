defmodule Tempo.RRule.WeekdayAtAPositionTest do
  @moduledoc """
  A weekday at a position in a month or a year: `L1K1IN`, the first Monday.

  A weekday with a position after it is the shape a holiday is written in
  (the first Monday of September, the last Thursday of November). Each day
  of the period was asked its day of the week, every match was made an
  occurrence and the position picked one of them, 365 questions for the
  first Monday of a year. The day is asked of Calendrical where the weekday
  is one and its period one.

  The measure is Elixir's own `Date`: the days of the period on the day of
  the week, in order, and the one at the position.
  """
  use ExUnit.Case, async: true

  alias Calendrical.Hebrew
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  ## The measure

  # The days of a range on a day of the week (ISO 8601's, Monday the first)
  # at each of some positions, a negative one counted from the end, in order.
  defp at_positions(%Date.Range{} = days, weekday, positions) do
    on_the_day = Enum.filter(days, &(Date.day_of_week(&1, :monday) == weekday))
    count = Enum.count(on_the_day)

    positions
    |> Enum.map(&if(&1 < 0, do: count + &1, else: &1 - 1))
    |> Enum.filter(&(&1 in 0..(count - 1)//1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&Enum.at(on_the_day, &1))
  end

  defp month_of(year, month, calendar \\ Calendar.ISO) do
    first = Date.new!(year, month, 1, calendar)
    Date.range(first, Date.end_of_month(first))
  end

  defp year_of(year),
    do: Date.range(Date.new!(year, 1, 1), Date.new!(year, 12, 31))

  defp days_of({:ok, %Interval{} = one}), do: [day_of(one)]
  defp days_of({:ok, %IntervalSet{} = set}), do: Enum.map(IntervalSet.members(set), &day_of/1)

  defp day_of(%Interval{} = occurrence) do
    {:ok, date} = Tempo.to_date(Interval.from(occurrence))
    date
  end

  defp written(positions) when is_list(positions), do: "{#{Enum.join(positions, ",")}}"

  defp selected(text), do: text |> Tempo.from_iso8601!() |> Tempo.to_interval() |> days_of()

  @positions [[1], [2], [4], [5], [6], [-1], [-2], [-5], [-6], [1, -1], [-1, 1], [2, 4], [5, -5]]

  describe "a weekday at a position in a month" do
    test "is the day at that position among the month's days on the weekday" do
      for year <- [2024, 2026],
          month <- 1..12,
          weekday <- 1..7,
          positions <- @positions do
        text = "#{year}Y#{month}ML#{weekday}K#{written(positions)}IN"

        assert {text, selected(text)} ==
                 {text, year |> month_of(month) |> at_positions(weekday, positions)}
      end
    end

    test "is that day in each month of a rule that steps by months" do
      # The second Tuesday of each month, as an RRULE has it.
      {:ok, rule} =
        RRule.parse("FREQ=MONTHLY;BYDAY=2TU;COUNT=24", from: Tempo.from_iso8601!("2026-01-13"))

      expected =
        for year <- [2026, 2027],
            month <- 1..12,
            do: hd(at_positions(month_of(year, month), 2, [2]))

      assert days_of(Tempo.to_interval(rule)) == expected
    end

    test "is counted in a month of another calendar by its own days" do
      # Tishri and Adar of 5786, and the Adar Rishon of 5787, a leap year.
      for {year, month} <- [{5786, 1}, {5786, 7}, {5786, 12}, {5787, 6}],
          weekday <- [1, 6, 7],
          positions <- [[1], [-1], [5], [2, -2]] do
        text = "#{year}Y#{month}ML#{weekday}K#{written(positions)}IN[u-ca=hebrew]"

        assert {text, selected(text)} ==
                 {text, at_positions(month_of(year, month, Hebrew), weekday, positions)}
      end
    end
  end

  describe "a weekday at a position in a year" do
    test "is the day at that position among the year's days on the weekday" do
      for year <- 2020..2030,
          weekday <- 1..7,
          positions <- [[1], [20], [52], [53], [54], [-1], [-53], [-54], [1, -1], [26, 27]] do
        text = "#{year}YL#{weekday}K#{written(positions)}IN"

        assert {text, selected(text)} ==
                 {text, year |> year_of() |> at_positions(weekday, positions)}
      end
    end

    test "is picked among the days of every month a year's months name" do
      # The position counts through June and July together.
      for positions <- [[1], [5], [6], [-1], [9], [10]] do
        text = "2026YL{6,7}M1K#{written(positions)}IN"
        mondays = Date.range(~D[2026-06-01], ~D[2026-07-31])

        assert {text, selected(text)} ==
                 {text, mondays |> at_positions(1, positions)}
      end
    end
  end

  describe "a weekday with a position that is no one day" do
    test "is resolved as its parts apart: several weekdays, and a range of positions" do
      june = month_of(2026, 6)
      weekdays = Enum.filter(june, &(Date.day_of_week(&1, :monday) in 1..5))

      assert selected("2026Y6ML{1..5}K-1IN") == [List.last(weekdays)]
      assert selected("2026Y6ML{1..5}K1IN") == [hd(weekdays)]

      assert selected("2026Y6ML1K{2..-1}IN") ==
               june |> at_positions(1, [2, 3, 4, 5])
    end
  end

  describe "weekdays with no position" do
    # One, two or three weekdays are each found a week at a time from the
    # first of them in the month, and more are asked of each of its days:
    # either way they are the month's days on those weekdays.
    @weekday_sets [
      [1],
      [7],
      [1, 3],
      [2, 4, 6],
      [6, 7],
      [1, 2, 3, 4],
      [1, 2, 3, 4, 5],
      [1, 2, 3, 4, 5, 6, 7]
    ]

    defp on_weekdays(%Date.Range{} = days, weekdays),
      do: Enum.filter(days, &(Date.day_of_week(&1, :monday) in weekdays))

    test "are the days of a month on them, in the order of time" do
      for year <- [2024, 2026], month <- 1..12, weekdays <- @weekday_sets do
        text = "#{year}Y#{month}ML#{written(weekdays)}KN"

        assert {text, selected(text)} ==
                 {text, on_weekdays(month_of(year, month), weekdays)}
      end
    end

    test "are the days of a year on them" do
      for year <- [2024, 2026, 2027], weekdays <- [[2], [6, 7], [1, 2, 3, 4, 5]] do
        text = "#{year}YL#{written(weekdays)}KN"
        assert {text, selected(text)} == {text, on_weekdays(year_of(year), weekdays)}
      end
    end

    test "are those of a month of another calendar, by its own days" do
      for {year, month} <- [{5786, 1}, {5786, 12}, {5787, 6}],
          weekdays <- [[7], [1, 6], [1, 2, 3, 4, 5]] do
        text = "#{year}Y#{month}ML#{written(weekdays)}KN[u-ca=hebrew]"

        assert {text, selected(text)} ==
                 {text, on_weekdays(month_of(year, month, Hebrew), weekdays)}
      end
    end

    test "are each Tuesday of a rule that steps by months, and by years" do
      {:ok, monthly} =
        RRule.parse("FREQ=MONTHLY;BYDAY=TU;COUNT=30", from: Tempo.from_iso8601!("2026-01-06"))

      {:ok, yearly} =
        RRule.parse("FREQ=YEARLY;BYDAY=TU,TH;COUNT=150", from: Tempo.from_iso8601!("2026-01-01"))

      days = Date.range(~D[2026-01-01], ~D[2028-12-31])

      assert days_of(Tempo.to_interval(monthly)) ==
               days
               |> on_weekdays([2])
               |> Enum.reject(&(Date.compare(&1, ~D[2026-01-06]) == :lt))
               |> Enum.take(30)

      assert days_of(Tempo.to_interval(yearly)) == days |> on_weekdays([2, 4]) |> Enum.take(150)
    end
  end
end
