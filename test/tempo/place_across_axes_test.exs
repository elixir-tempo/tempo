defmodule Tempo.PlaceAcrossAxesTest do
  @moduledoc """
  A value placed on one written by other units of a date.

  A date is written by its month and day, by its week and a day of it, or
  by its day of the year. `Tempo.at/2` and `Tempo.on/2` put the units of
  the one value under the other's, and where the two were of two of those
  they gave a value that names nothing and that no reader takes:
  `2026Y25W15D` for the 15th on a week, `2026Y6M3K` for a Wednesday on a
  month, `2026Y6M2W` for a week on a month. What is placed is what
  `Tempo.select/2` selects by the one from the other, where that is one
  value: the 15th on week 25 of 2026 is 15 June.

  The measure is Elixir's own `Date` and Erlang's `:calendar`: the dates of
  an ISO 8601 week, a date's day of the month, of the year and of the week.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError

  ## The measure

  # The dates of an ISO 8601 week of 2026, found among the days around the
  # year by the week Erlang numbers each in.
  @around Date.range(~D[2025-12-22], ~D[2027-01-10])

  defp dates_of_week(week),
    do: Enum.filter(@around, &(:calendar.iso_week_number(Date.to_erl(&1)) == {2026, week}))

  defp week(number),
    do: Tempo.from_iso8601!("2026-W" <> String.pad_leading(Integer.to_string(number), 2, "0"))

  defp read_back?(%Tempo{} = value),
    do: Tempo.from_iso8601(Tempo.to_iso8601!(value)) == {:ok, value}

  describe "a day of a month placed on a week" do
    test "is the day of the week that has that number, and no date where none has" do
      for number <- 1..53, day <- [1, 3, 15, 28, 29, 31] do
        placed = Tempo.on(Tempo.from_iso8601!("#{day}D"), week(number))

        case Enum.filter(dates_of_week(number), &(&1.day == day)) do
          [date] ->
            assert {number, day, placed} == {number, day, {:ok, Tempo.from_date(date)}}

          [] ->
            assert {^number, ^day, {:error, %InvalidDateError{}}} = {number, day, placed}
        end
      end

      # Week 25 of 2026 is 15 to 21 June.
      assert dates_of_week(25) == Enum.to_list(Date.range(~D[2026-06-15], ~D[2026-06-21]))
      assert Tempo.on(~o"15D", ~o"2026-W25") == {:ok, ~o"2026-06-15"}
      assert Tempo.at(~o"2026-W25", ~o"15D") == {:ok, ~o"2026-06-15"}
    end

    test "keeps the week's zone, and takes a time of day after it" do
      assert Tempo.on(~o"15D", ~o"2026-W25[Europe/Paris]") == {:ok, ~o"2026-06-15[Europe/Paris]"}
      assert Tempo.on(~o"15DT10H", ~o"2026-W25") == {:ok, ~o"2026-06-15T10"}
    end
  end

  describe "a day of the year placed on a week" do
    test "is the day of the week that is that day of its year" do
      for number <- [1, 25, 53], day <- [1, 166, 167, 365] do
        placed = Tempo.on(Tempo.from_iso8601!("#{day}O"), week(number))

        case Enum.filter(dates_of_week(number), &(Date.day_of_year(&1) == day)) do
          [date | _one_of_each_year] ->
            assert {number, day, placed} == {number, day, {:ok, Tempo.from_date(date)}}

          [] ->
            assert {^number, ^day, {:error, %InvalidDateError{}}} = {number, day, placed}
        end
      end
    end
  end

  describe "a day of the week placed with no week" do
    test "is the day it is placed on where that is the weekday, and no date where it is not" do
      for date <- Date.range(~D[2026-06-15], ~D[2026-06-21]), weekday <- 1..7 do
        placed = Tempo.on(Tempo.from_iso8601!("#{weekday}K"), Tempo.from_date(date))

        if Date.day_of_week(date) == weekday do
          assert {date, weekday, placed} == {date, weekday, {:ok, Tempo.from_date(date)}}
        else
          assert {^date, ^weekday, {:error, %InvalidDateError{}}} = {date, weekday, placed}
        end
      end
    end

    test "names more than one date on a month or a year, which are select/2's to give" do
      for base <- [~o"2026-06", ~o"2026"] do
        assert {:error, %ArgumentError{} = error} = Tempo.on(~o"3K", base)
        assert Exception.message(error) =~ "Tempo.select/2"
      end

      # Under a week it is the one day, as it was.
      assert Date.day_of_week(~D[2026-06-17]) == 3
      assert Tempo.on(~o"3K", ~o"2026-W25") == {:ok, ~o"2026-06-17"}
    end
  end

  describe "a week placed on a month" do
    test "is the week of the month, as the value written with a week after its month is read" do
      for week <- 1..4 do
        %Interval{} = read = Tempo.from_iso8601!("2026Y6M#{week}W")
        {:ok, %Interval{} = placed} = Tempo.on(Tempo.from_iso8601!("#{week}W"), ~o"2026-06")

        assert {week, Interval.from(placed), Interval.to(placed)} ==
                 {week, Interval.from(read), Interval.to(read)}
      end

      assert {:ok, %Interval{} = first} = Tempo.on(~o"1W", ~o"2026-07")
      assert {Interval.from(first), Interval.to(first)} == {~o"2026-06-29", ~o"2026-07-06"}

      # June 2026 has four weeks.
      assert {:error, %InvalidDateError{}} = Tempo.on(~o"5W", ~o"2026-06")
      assert {:error, %InvalidDateError{}} = Tempo.on(~o"25W", ~o"2026-06")
    end

    test "with a day of it is that day's date, and a span of weeks runs from one's start to another's" do
      assert Date.day_of_week(~D[2026-06-10]) == 3

      assert Tempo.on(~o"2W3K", ~o"2026-06") == {:ok, ~o"2026-06-10"}
      assert Tempo.on(~o"2W3KT10H", ~o"2026-06") == {:ok, ~o"2026-06-10T10"}
      assert Tempo.at(~o"2026-06", ~o"1W/3W") == {:ok, ~o"2026-06-01/2026-06-15"}
    end
  end

  describe "two values of two axes with no year" do
    test "name one date only in a year, and are refused" do
      for {value, other} <- [{~o"25W", ~o"15D"}, {~o"6M", ~o"3K"}, {~o"6M", ~o"2W"}] do
        assert {:error, %ArgumentError{} = error} = Tempo.at(value, other)
        assert Exception.message(error) =~ "with a year"
      end
    end
  end

  describe "a value placed with a selection that has no period" do
    # A selection with nothing before it (`L5KN`, the Fridays) was held the
    # finest of all, so a time of day was written before it
    # (`T17H30ML5KN`), which no reader takes.
    test "is after it where it is finer than what the selection names, and before it where coarser" do
      for {selection, value, text} <- [
            {~o"L5KN", ~o"T17H30M", "L5KNT17H30M"},
            {~o"L1K1IN", ~o"T9H", "L1K1INT9H"},
            {~o"L(easter)eN", ~o"T9H", "L(easter)eNT9H"},
            {~o"L6MN", ~o"15D", "L6MN15D"},
            {~o"L5KN", ~o"6M", "6ML5KN"},
            {~o"L15DN", ~o"6M", "6ML15DN"},
            {~o"LT10HN", ~o"15D", "15DLT10HN"}
          ] do
        read = Tempo.from_iso8601!(text)

        assert {text, Tempo.at(selection, value)} == {text, {:ok, read}}
        assert {text, Tempo.at(value, selection)} == {text, {:ok, read}}
        assert {text, read_back?(read)} == {text, true}
      end
    end

    test "is the time on each date the selection names, once it has a period" do
      {:ok, fridays_at_half_past_five} = Tempo.at(~o"L5KN", ~o"T17H30M")
      {:ok, in_june} = Tempo.on(fridays_at_half_past_five, ~o"2026-06")
      {:ok, occurrences} = Tempo.to_interval(in_june)

      fridays =
        Enum.filter(Date.range(~D[2026-06-01], ~D[2026-06-30]), &(Date.day_of_week(&1) == 5))

      assert Enum.map(IntervalSet.members(occurrences), &Interval.from/1) ==
               for(date <- fridays, do: Tempo.from_iso8601!("#{Date.to_iso8601(date)}T17:30"))
    end

    test "is in order as it was with a year or a month before the selection" do
      assert Tempo.at(~o"2018YL1K1IN", ~o"T9H") == {:ok, Tempo.from_iso8601!("2018YL1K1INT9H")}
    end
  end

  describe "what is placed" do
    test "is read back as itself" do
      for {value, other} <- [
            {~o"15D", ~o"2026-W25"},
            {~o"166O", ~o"2026-W25"},
            {~o"3K", ~o"2026-06-17"},
            {~o"2W3K", ~o"2026-06"},
            {~o"3K", ~o"2026-W25"},
            {~o"25W3K", ~o"2026"},
            {~o"6M15D", ~o"2026"},
            {~o"T17", ~o"2026-06-15"}
          ] do
        assert {:ok, %Tempo{} = placed} = Tempo.on(value, other)
        assert {value, other, read_back?(placed)} == {value, other, true}
      end
    end

    test "is as it was where the two are of one axis" do
      assert Tempo.at(~o"2026-06-15", ~o"T17") == {:ok, ~o"2026-06-15T17"}
      assert Tempo.at(~o"3M", ~o"2D") == {:ok, ~o"3M2D"}
      assert Tempo.on(~o"15D", ~o"2026-06") == {:ok, ~o"2026-06-15"}
      assert Tempo.on(~o"25W", ~o"2026") == {:ok, ~o"2026-W25"}
      assert Tempo.on(~o"166O", ~o"2026") == {:ok, ~o"2026-06-15"}
      assert Tempo.at(~o"2026-06-15", ~o"T09/T17") == {:ok, ~o"2026-06-15T09/2026-06-15T17"}
    end
  end
end
