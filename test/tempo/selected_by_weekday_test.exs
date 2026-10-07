defmodule Tempo.SelectedByWeekdayTest do
  @moduledoc """
  A day selected by its weekday.

  A day `Tempo.select/2` selects is the day's own value, as
  `Tempo.to_interval/1` gives it, and is walked by its hours. A day selected
  by its weekday alone (`~o"1K"`, `~o"L1KN"`, `Tempo.workdays/1`) was left
  the span of the day with no unit, and was walked as the one day; it is the
  day's own value too (decided 2026-10-08). So `Enum.count/1` of the five
  Mondays of June is 120, its hours, and `Tempo.IntervalSet.count/1` the 5
  it was.

  A weekday selected from an hour keeps the hour where its day is that
  weekday, as the selection `~o"L1KN"` did: the constraint and the workdays
  selected nothing there, an hour holding no whole day.

  The measure is Elixir's own `Date`: the days of a span that are a given
  day of the week, and each as `Tempo.to_interval/1` gives that day.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  ## The measure

  # The days of a range that are on one of `weekdays`, each as the value
  # the day is.
  defp own_values(%Date.Range{} = days, weekdays, zone \\ nil) do
    for day <- days, Date.day_of_week(day) in weekdays do
      {:ok, own} = Tempo.to_interval(as_value(day, zone))
      own
    end
  end

  defp as_value(%Date{} = day, nil), do: Tempo.from_date(day)
  defp as_value(%Date{} = day, zone), do: Tempo.from_iso8601!("#{day}[#{zone}]")

  defp selected(base, selector) do
    {:ok, %IntervalSet{} = set} = Tempo.select(base, selector)
    IntervalSet.members(set)
  end

  @june Date.range(~D[2026-06-01], ~D[2026-06-30])

  describe "a day selected by its weekday" do
    test "is the day's own value, by a constraint, a selection and the workdays" do
      mondays = own_values(@june, [1])
      assert Enum.count(mondays) == 5

      assert selected(~o"2026-06", ~o"1K") == mondays
      assert selected(~o"2026-06", ~o"L1KN") == mondays
      assert selected(~o"2026-06", ~o"{1,3}K") == own_values(@june, [1, 3])
      assert selected(~o"2026-06", Tempo.workdays(:US)) == own_values(@june, 1..5)
    end

    test "is walked by its hours, and counted as the one member it is" do
      {:ok, mondays} = Tempo.select(~o"2026-06", ~o"1K")

      assert IntervalSet.count(mondays) == 5
      assert Enum.count(mondays) == 5 * 24
      assert Enum.take(mondays, 2) == [~o"2026-06-01T00", ~o"2026-06-01T01"]

      {:ok, workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
      assert {IntervalSet.count(workdays), Enum.count(workdays)} == {22, 22 * 24}
    end

    test "is the same value as the day selected by its number" do
      # 15 June 2026 is a Monday.
      assert Date.day_of_week(~D[2026-06-15]) == 1

      [by_number] = selected(~o"2026-06", ~o"15D")

      assert by_number in selected(~o"2026-06", ~o"1K")
      assert selected(~o"2026-06-15", ~o"1K") == [by_number]
      assert selected(~o"2026-W25", ~o"1K") == [by_number]
    end

    test "is so from a year, from a span of days and from a span with no end" do
      year = Date.range(~D[2026-01-01], ~D[2026-12-31])
      assert selected(~o"2026", ~o"1K") == own_values(year, [1])

      assert selected(~o"2026-06-15/2026-06-22", Tempo.workdays(:US)) ==
               own_values(Date.range(~D[2026-06-15], ~D[2026-06-21]), 1..5)

      {:ok, from_here_on} = Tempo.select(~o"2026-06-15/..", ~o"1K")
      next_two = from_here_on |> IntervalSet.walk() |> Enum.take(2)

      assert next_two == own_values(Date.range(~D[2026-06-15], ~D[2026-06-22]), [1])
    end

    test "is in the zone of what it is selected from" do
      assert selected(Tempo.from_iso8601!("2026-06[Europe/Paris]"), ~o"1K") ==
               own_values(@june, [1], "Europe/Paris")
    end

    test "less a holiday is the days no holiday falls on, each its own value" do
      # The King's Birthday, Monday 8 June 2026.
      business_days = Tempo.workdays(:AU, except: ~o"2026-06-08")

      assert selected(~o"2026-06", business_days) ==
               @june |> own_values(1..5) |> Enum.reject(&(Interval.from(&1) == ~o"2026-06-08"))
    end
  end

  describe "a weekday selected from a time of day" do
    test "keeps an hour and a minute of that weekday, as the selection does" do
      for base <- [~o"2026-06-15T10", ~o"2026-06-15T10:30"] do
        {:ok, own} = Tempo.to_interval(base)

        assert {base, selected(base, ~o"1K")} == {base, [own]}
        assert {base, selected(base, ~o"L1KN")} == {base, [own]}
        assert {base, selected(base, Tempo.workdays(:US))} == {base, [own]}

        # A Monday is no Tuesday.
        assert {base, selected(base, ~o"2K")} == {base, []}
      end
    end

    test "keeps the hours of a span that are on that weekday" do
      # From ten on Monday to noon on Tuesday: fourteen hours of Monday.
      span = ~o"2026-06-15T10/2026-06-16T12"

      hours =
        for hour <- 10..23 do
          {:ok, own} = Tempo.to_interval(Tempo.from_iso8601!("2026-06-15T#{hour}"))
          own
        end

      assert selected(span, ~o"1K") == hours
      assert selected(span, ~o"L1KN") == hours
      assert Enum.count(selected(span, ~o"2K")) == 12
    end
  end

  describe "the workdays of a span, counted" do
    test "are its whole days, as they were, whatever it is written to" do
      assert Tempo.count_workdays(~o"2026-06", :US) ==
               Enum.count(@june, &(Date.day_of_week(&1) in 1..5))

      # From ten on Monday to ten on Wednesday: Monday and Tuesday.
      assert Tempo.count_workdays(~o"2026-06-15T10/2026-06-17T10", :US) == 2
      assert Tempo.count_workdays(~o"2026-06-15T10/PT48H", :US) == 2

      # An hour of a workday holds no whole day.
      assert Tempo.count_workdays(~o"2026-06-15T10", :US) == 0
      assert Tempo.count_workdays(~o"2026-06-15T10/2026-06-15T12", :US) == 0
    end
  end
end
