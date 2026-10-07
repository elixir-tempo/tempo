defmodule Tempo.WeekOfMonthTest do
  @moduledoc """
  A week of a month (decided 2026-10-07).

  A week after a month is a week of the month, which the calendar numbers:
  the week Calendrical's `week_of_month/3` gives each date. `2026Y6M2W` was
  not read, and a week selected from a month was refused as not built. It
  is read as the span of the dates the calendar numbers in it, as a
  calendar week of a year (`w`) is, selected from a month by
  `Tempo.select/2`, and the occurrence of a rule that steps by months.

  The measure for the Gregorian calendar is Elixir's own `Date`, by the
  rule the decision states: whole weeks from a Monday, the first of a month
  the one that holds its first day. For a calendar that cuts a month's
  weeks at its ends the measure is the calendar's own answer for each date
  of the span, and for the dates either side of it.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Gregorian
  alias Calendrical.Hebrew
  alias Calendrical.Julian.March25
  alias Calendrical.Persian
  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError
  alias Tempo.ParseError
  alias Tempo.RRule
  alias Tempo.UnitValues

  ## The measure

  @months for year <- 2024..2028, month <- 1..12, do: {year, month}

  defp monday_of(date), do: Date.beginning_of_week(date, :monday)

  # How many weeks a month has: those from the week that holds its first
  # day up to the week that holds the first day of the next.
  defp weeks_in(year, month) do
    first = Date.new!(year, month, 1)
    next = first |> Date.end_of_month() |> Date.add(1)

    div(Date.diff(monday_of(next), monday_of(first)), 7)
  end

  # A week of a month, from its Monday to the Monday after.
  defp week(year, month, week) do
    start = Date.new!(year, month, 1) |> monday_of() |> Date.add(7 * (week - 1))
    {start, Date.add(start, 7)}
  end

  defp seconds(%Date{} = date),
    do:
      date |> NaiveDateTime.new!(~T[00:00:00]) |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp seconds({%Date{} = from, %Date{} = to}), do: {seconds(from), seconds(to)}

  defp seconds({%Date{} = from, count}) when is_integer(count),
    do: seconds({from, Date.add(from, count)})

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  defp spans({:ok, %IntervalSet{} = set}), do: set |> IntervalSet.members() |> Enum.map(&bounds/1)

  defp text(year, month, rest), do: "#{year}Y#{month}M#{rest}"

  defp pad(number), do: String.pad_leading(Integer.to_string(number), 2, "0")

  # The spans of days, each from its date for so many days.
  defp days(answer), do: spans(answer)

  describe "a week of a month, read" do
    test "is the whole week from a Monday, the first the one that holds the month's first day" do
      for {year, month} <- @months, week <- 1..weeks_in(year, month) do
        read = Tempo.from_iso8601!(text(year, month, "#{week}W"))

        assert {year, month, week, bounds(read)} ==
                 {year, month, week, seconds(week(year, month, week))}
      end
    end

    test "is the decision's: the first week of July 2026 starts on 29 June" do
      assert Tempo.from_iso8601!("2026Y7M1W") == ~o"2026-06-29/2026-07-06"
      assert Tempo.from_iso8601!("2026Y10M1W") == ~o"2026-09-28/2026-10-05"

      # June 2026 has weeks 1 to 4, and its last two days are in July's first.
      assert weeks_in(2026, 6) == 4
      assert Tempo.from_iso8601!("2026Y6M4W") == ~o"2026-06-22/2026-06-29"

      assert {:error, %InvalidDateError{unit: :week, value: 5}} =
               Tempo.from_iso8601("2026Y6M5W")
    end

    test "is no week the month does not have" do
      for {year, month} <- @months, week <- [0, weeks_in(year, month) + 1, 7] do
        assert {^year, ^month, ^week, {:error, %InvalidDateError{unit: :week}}} =
                 {year, month, week, Tempo.from_iso8601(text(year, month, "#{week}W"))}
      end
    end

    test "is counted from the month's last week where it is negative" do
      for {year, month} <- @months, back <- 1..weeks_in(year, month) do
        week = weeks_in(year, month) - back + 1

        assert {year, month, back, bounds(Tempo.from_iso8601!(text(year, month, "-#{back}W")))} ==
                 {year, month, back, seconds(week(year, month, week))}
      end

      assert {:error, %InvalidDateError{unit: :week}} = Tempo.from_iso8601("2026Y6M-5W")
    end

    test "with a day of the week is that day's date, and a time of day is on it" do
      for {year, month} <- @months, week <- 1..weeks_in(year, month), day <- 1..7 do
        {monday, _next} = week(year, month, week)
        date = Date.add(monday, day - 1)

        assert {year, month, week, day, Tempo.from_iso8601!(text(year, month, "#{week}W#{day}K"))} ==
                 {year, month, week, day, Tempo.from_date(date)}
      end

      # Wednesday of the second week of June 2026 is the 10th.
      assert Date.day_of_week(~D[2026-06-10]) == 3
      assert Tempo.from_iso8601!("2026Y6M2W3K") == ~o"2026-06-10"
      assert Tempo.from_iso8601!("2026Y6M2W-1K") == ~o"2026-06-14"
      assert Tempo.from_iso8601!("2026Y6M2W3KT10H30M") == ~o"2026-06-10T10:30"

      # A time of day under the week alone is on its first day, as it is
      # under a week of a year.
      assert Tempo.from_iso8601!("2026Y24WT10H") == ~o"2026-06-08T10"
      assert Tempo.from_iso8601!("2026Y6M2WT10H") == ~o"2026-06-08T10"

      assert {:error, %InvalidDateError{unit: :day_of_week}} =
               Tempo.from_iso8601("2026Y6M2W8K")
    end

    test "is the dates its calendar numbers in it, where the calendar cuts a month's weeks short" do
      for {calendar, year, months} <- [
            {Hebrew, 5786, 1..12},
            {Persian, 1405, 1..12},
            {Calendrical.Julian, 2025, 1..12}
          ],
          month <- months,
          week <- 1..6,
          {:ok, %Interval{} = read} <- [
            Tempo.from_iso8601(text(year, month, "#{week}W"), calendar)
          ] do
        {:ok, first} = Tempo.to_date(Interval.from(read))
        {:ok, after_last} = Tempo.to_date(Interval.to(read))
        last = Date.add(after_last, -1)

        for date <- Date.range(first, last) do
          assert {calendar, date, calendar.week_of_month(date.year, date.month, date.day)} ==
                   {calendar, date, {month, week}}
        end

        for outside <- [Date.add(first, -1), after_last] do
          refute {month, week} ==
                   calendar.week_of_month(outside.year, outside.month, outside.day)
        end
      end

      # The first week of Tishri 5786 is the five days to its first Saturday.
      assert Tempo.from_iso8601!("5786Y1M1W", Hebrew) ==
               Tempo.from_iso8601!("5786Y1M1D/5786Y1M6D", Hebrew)
    end

    test "is the week that holds four or more of the month's days, where its calendar counts by that rule" do
      # `Calendrical.ISO` gives a week to the month that holds its Thursday,
      # as ISO 8601 gives one to its year: the first days of a month may be
      # in the last week of the month before.
      for year <- [2021, 2026], month <- 1..12 do
        first = Date.new!(year, month, 1)
        next = first |> Date.end_of_month() |> Date.add(1)

        thursday_week = fn date ->
          monday_of(Date.add(date, Integer.mod(4 - Date.day_of_week(date), 7)))
        end

        weeks = div(Date.diff(thursday_week.(next), thursday_week.(first)), 7)

        for week <- 1..weeks do
          start = Date.add(thursday_week.(first), 7 * (week - 1))
          read = Tempo.from_iso8601!(text(year, month, "#{week}W"), Calendrical.ISO)

          assert {year, month, week, bounds(read)} ==
                   {year, month, week, seconds({start, Date.add(start, 7)})}
        end

        assert {^year, ^month, {:error, %InvalidDateError{unit: :week}}} =
                 {year, month,
                  Tempo.from_iso8601(text(year, month, "#{weeks + 1}W"), Calendrical.ISO)}
      end

      # 1 October 2021 is a Friday, in the fifth week of September.
      assert Date.day_of_week(~D[2021-10-01]) == 5

      assert bounds(Tempo.from_iso8601!("2021Y10M1W", Calendrical.ISO)) ==
               seconds({~D[2021-10-04], ~D[2021-10-11]})

      assert bounds(Tempo.from_iso8601!("2021Y9M5W", Calendrical.ISO)) ==
               seconds({~D[2021-09-27], ~D[2021-10-04]})
    end

    test "is where it starts as the end of an interval, and a member of a set" do
      assert Tempo.from_iso8601!("2026Y6M2W/2026Y6M4W") == ~o"2026-06-08/2026-06-22"
      assert Tempo.from_iso8601!("2026Y6M2W/P3D") == ~o"2026-06-08/P3D"

      assert Tempo.from_iso8601!("{2026Y6M1W,2026Y6M3W}") ==
               Tempo.from_iso8601!("{2026-06-01/2026-06-08,2026-06-15/2026-06-22}")
    end

    test "keeps its zone, and is walked by its days" do
      assert Tempo.from_iso8601!("2026Y6M2W[Europe/Paris]") ==
               ~o"2026-06-08[Europe/Paris]/2026-06-15[Europe/Paris]"

      assert Enum.to_list(Tempo.from_iso8601!("2026Y7M1W")) ==
               Enum.map(Date.range(~D[2026-06-29], ~D[2026-07-05]), &Tempo.from_date/1)
    end

    test "is one week of one month of one year" do
      for text <- ["2026Y6M{1,3}W", "2026Y6MXW", "2026Y{6,7}M2W", "202XY6M2W", "2026Y6M2W{1,3}K"] do
        assert {^text, {:error, %ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
        assert Exception.message(error) =~ "Tempo.select/2"
      end

      # A season and a quarter are no month, and a week with no year is not read.
      for text <- ["2026Y21M2W", "2026Y33M2W", "2026Y13M2W"] do
        assert {^text, {:error, %InvalidDateError{unit: :week}}} =
                 {text, Tempo.from_iso8601(text)}
      end

      assert {:error, %ParseError{}} = Tempo.from_iso8601("6M2W")
    end

    test "is not built where the year does not begin with its first month, and has no calendar of weeks" do
      assert {:error,
              %ConversionError{reason: :not_built, target: :week_of_month, calendar: March25}} =
               Tempo.from_iso8601("1750Y6M2W", March25)

      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("2026Y6M2W[u-ca=iso-week]")
    end
  end

  describe "a week selected from a month" do
    test "is the week of that month, and nothing where the month has none" do
      for {year, month} <- Enum.filter(@months, fn {year, _month} -> year in 2026..2027 end),
          week <- 1..6 do
        expected =
          if week <= weeks_in(year, month), do: [seconds(week(year, month, week))], else: []

        month_value = Tempo.from_iso8601!(text(year, month, ""))

        assert {year, month, week,
                spans(Tempo.select(month_value, Tempo.from_iso8601!("#{week}W")))} ==
                 {year, month, week, expected}
      end
    end

    test "is not always within its month, and is the week of one month alone" do
      assert spans(Tempo.select(~o"2026-07", ~o"1W")) == [
               seconds({~D[2026-06-29], ~D[2026-07-06]})
             ]

      # The week that starts on 29 June is July's first and no week of June,
      # so a span of months selects it once.
      assert spans(Tempo.select(~o"2026-06/2026-09", ~o"1W")) ==
               Enum.map([6, 7, 8], &seconds(week(2026, &1, 1)))

      assert spans(Tempo.select(~o"2026-06", ~o"5W")) == []
    end

    test "is each week a set or a range names, and the last where it is negative" do
      assert spans(Tempo.select(~o"2026-06", ~o"{1,3}W")) ==
               Enum.map([1, 3], &seconds(week(2026, 6, &1)))

      assert spans(Tempo.select(~o"2026-06", ~o"{2..-1}W")) ==
               Enum.map(2..4, &seconds(week(2026, 6, &1)))

      assert spans(Tempo.select(~o"2026-06", ~o"-1W")) == [seconds(week(2026, 6, 4))]
      assert spans(Tempo.select(~o"2027-01", ~o"-1W")) == [seconds(week(2027, 1, 5))]
    end

    test "with a day of the week and a time of day is the day and the hour" do
      assert spans(Tempo.select(~o"2026-06", ~o"2W3K")) ==
               [seconds({~D[2026-06-10], ~D[2026-06-11]})]

      assert spans(Tempo.select(~o"2026-07", ~o"1W1K")) ==
               [seconds({~D[2026-06-29], ~D[2026-06-30]})]

      assert spans(Tempo.select(~o"2026-06", ~o"2W{1,3,5}K")) ==
               for(
                 day <- [8, 10, 12],
                 do: seconds({Date.new!(2026, 6, day), Date.new!(2026, 6, day + 1)})
               )

      {:ok, hour} = Tempo.select(~o"2026-06", ~o"2W3KT10H")
      assert [%Interval{} = ten] = IntervalSet.members(hour)
      assert Interval.from(ten) == ~o"2026-06-10T10"
    end

    test "as the ends of a span is from where the one starts to where the other does" do
      assert spans(Tempo.select(~o"2026-06", ~o"1W/3W")) ==
               [seconds({~D[2026-06-01], ~D[2026-06-15]})]

      assert spans(Tempo.select(~o"2026-06", ~o"2W1K/2W6K")) ==
               [seconds({~D[2026-06-08], ~D[2026-06-13]})]

      assert spans(Tempo.select(~o"2026-06", ~o"2W/P10D")) ==
               [seconds({~D[2026-06-08], ~D[2026-06-18]})]
    end

    test "is selected beside another selector, and keeps the month's zone" do
      assert spans(Tempo.select(~o"2026-06", [~o"15D", ~o"1W"])) ==
               [seconds(week(2026, 6, 1)), seconds({~D[2026-06-15], ~D[2026-06-16]})]

      {:ok, zoned} = Tempo.select(~o"2026-06[Europe/Paris]", ~o"2W")
      assert [%Interval{} = week] = IntervalSet.members(zoned)

      assert {Interval.from(week), Interval.to(week)} ==
               {~o"2026-06-08[Europe/Paris]", ~o"2026-06-15[Europe/Paris]"}
    end

    test "is the calendar's own in another calendar, selected by a week written in it" do
      {:ok, first} =
        Tempo.select(Tempo.from_iso8601!("5786Y1M", Hebrew), Tempo.from_iso8601!("1W", Hebrew))

      assert [%Interval{} = week] = IntervalSet.members(first)

      assert {Interval.from(week), Interval.to(week)} ==
               {Tempo.from_iso8601!("5786Y1M1D", Hebrew),
                Tempo.from_iso8601!("5786Y1M6D", Hebrew)}

      assert {:error, %ConversionError{}} =
               Tempo.select(Tempo.from_iso8601!("5786Y1M", Hebrew), ~o"1W")
    end

    test "from a year is still a week of the year, and from a day a filter by one" do
      {:ok, of_the_year} = Tempo.select(~o"2026", ~o"2W")
      assert Enum.map(IntervalSet.members(of_the_year), &Interval.from/1) == [~o"2026Y2W"]

      # 15 June 2026 is in ISO week 25.
      assert :calendar.iso_week_number({2026, 6, 15}) == {2026, 25}

      assert spans(Tempo.select(~o"2026-06-15", ~o"25W")) == [
               seconds({~D[2026-06-15], ~D[2026-06-16]})
             ]

      assert spans(Tempo.select(~o"2026-06-15", ~o"3W")) == []
    end

    test "is refused by name where it is no whole number, and in a year that begins within a month" do
      assert {:error, %ConversionError{reason: :not_built, target: :week_of_month}} =
               Tempo.select(~o"2026-06", ~o"XW")

      assert {:error,
              %ConversionError{reason: :not_built, target: :week_of_month, calendar: March25}} =
               Tempo.select(
                 Tempo.from_iso8601!("1750Y6M", March25),
                 Tempo.from_iso8601!("2W", March25)
               )
    end
  end

  describe "a week selected by a rule in a month" do
    test "is the week of the month, as the value written with a week after its month is" do
      for {year, month} <- Enum.filter(@months, fn {year, _month} -> year == 2026 end),
          week <- 1..weeks_in(year, month) do
        expected = [seconds(week(year, month, week))]
        month_value = Tempo.from_iso8601!(text(year, month, ""))

        assert {year, month, week,
                spans(Tempo.to_interval(Tempo.from_iso8601!(text(year, month, "L#{week}WN"))))} ==
                 {year, month, week, expected}

        assert {year, month, week,
                spans(Tempo.select(month_value, Tempo.from_iso8601!("L#{week}WN")))} ==
                 {year, month, week, expected}
      end

      assert spans(Tempo.to_interval(Tempo.from_iso8601!("2026Y6ML5WN"))) == []

      assert spans(Tempo.select(~o"2026-06/2026-09", ~o"L{1,-1}WN")) ==
               for(
                 month <- [6, 7, 8],
                 week <- [1, weeks_in(2026, month)],
                 do: seconds(week(2026, month, week))
               )
    end

    test "is the occurrence of a rule that steps by months" do
      second = for month <- 6..8, do: seconds(week(2026, month, 2))

      assert spans(Tempo.to_interval_set(Tempo.from_iso8601!("R3/2026Y6M/P1M/FL2WN"))) == second

      assert spans(
               Tempo.to_interval_set(Tempo.from_iso8601!("R/../P1M/FL2WN"),
                 within: ~o"2026-06/2026-09"
               )
             ) == second

      # From a year, the months of it from the first.
      assert spans(Tempo.to_interval_set(Tempo.from_iso8601!("R3/2026Y/P1M/FL2WN"))) ==
               for(month <- 1..3, do: seconds(week(2026, month, 2)))

      assert spans(Tempo.to_interval_set(Tempo.from_iso8601!("R3/2026Y6M/P1M/FL-1WN"))) ==
               for(month <- 6..8, do: seconds(week(2026, month, weeks_in(2026, month))))
    end

    test "has the first week of its start's month, where that starts before the month does" do
      # The first week of a month starts before it in every month that does
      # not begin on a Monday, and was dropped as coming before the start.
      for {year, month} <- @months do
        {next_year, next_month} = if month == 12, do: {year + 1, 1}, else: {year, month + 1}
        rule = Tempo.from_iso8601!("R2/#{year}Y#{month}M/P1M/FL1WN")

        assert {year, month, spans(Tempo.to_interval_set(rule))} ==
                 {year, month,
                  [seconds(week(year, month, 1)), seconds(week(next_year, next_month, 1))]}
      end

      assert spans(Tempo.to_interval_set(Tempo.from_iso8601!("R2/2026Y7M/P1M/FL1WN"))) ==
               [
                 seconds({~D[2026-06-29], ~D[2026-07-06]}),
                 seconds({~D[2026-07-27], ~D[2026-08-03]})
               ]
    end

    test "is a fifth week only in the months that have one" do
      expected =
        for month <- 1..12, weeks_in(2026, month) >= 5, do: seconds(week(2026, month, 5))

      assert expected != []

      assert spans(
               Tempo.to_interval_set(Tempo.from_iso8601!("R/2026Y1M/P1M/FL5WN"), within: ~o"2026")
             ) == expected
    end

    test "limits a rule that starts on a date by its week of the year, as it did" do
      # The 15th of each month, kept where it is in ISO week 25.
      {:ok, kept} = Tempo.to_interval_set(Tempo.from_iso8601!("R2/2026-01-15/P1M/FL25WN"))

      assert Enum.map(IntervalSet.members(kept), &Interval.from/1) ==
               [~o"2026-06-15", ~o"2032-06-15"]
    end

    test "is refused by name as the calendar's own week, which is a week of its year" do
      assert {:error, %ConversionError{reason: :not_built, target: :week_of_month}} =
               Tempo.to_interval(Tempo.from_iso8601!("2026Y6ML2wN"))

      assert {:error, %ConversionError{reason: :not_built, target: :week_of_month} = error} =
               Tempo.select(~o"2026-06", ~o"L2wN")

      assert Exception.message(error) =~ "from ~o\"2026Y6M\""
    end
  end

  # A week of a month in a selection, beside a part that picks within it,
  # was refused as not built: the week's start was a day of the month, which
  # the resolver kept or dropped by its week of the year. It hands its days
  # to the parts after it, as a week of a year does (`2026YL24W3KN`).
  describe "a week of a month beside a part that picks within it, in a selection" do
    test "with a day of the week is that day's date" do
      for {year, month} <- @months, week <- 1..weeks_in(year, month), day <- 1..7 do
        {monday, _next} = week(year, month, week)
        date = Date.add(monday, day - 1)
        value = Tempo.from_iso8601!(text(year, month, "L#{week}W#{day}KN"))

        assert {year, month, week, day, spans(Tempo.to_interval(value))} ==
                 {year, month, week, day, [seconds({date, Date.add(date, 1)})]}
      end

      # Wednesday of the second week of June 2026 is the 10th, as the value
      # written with no selection is.
      assert spans(Tempo.to_interval(~o"2026Y6ML2W3KN")) ==
               [bounds(Tempo.to_interval!(Tempo.from_iso8601!("2026Y6M2W3K")))]
    end

    test "keeps a day of the week that is outside the month, and a month beside it limits the month" do
      # The first week of July 2026 starts on Monday 29 June.
      assert week(2026, 7, 1) == {~D[2026-06-29], ~D[2026-07-06]}
      monday = [seconds({~D[2026-06-29], ~D[2026-06-30]})]

      assert spans(Tempo.to_interval(~o"2026Y7ML1W1KN")) == monday
      assert spans(Tempo.to_interval(~o"2026Y7ML7M1W1KN")) == monday
      assert spans(Tempo.to_interval(~o"2026Y7ML6M1W1KN")) == []
    end

    test "with a time of day is that time on each of its days" do
      {monday, _next} = week(2026, 6, 2)

      at_ten =
        for day <- 0..6 do
          start = NaiveDateTime.new!(Date.add(monday, day), ~T[10:00:00])

          {start |> NaiveDateTime.to_gregorian_seconds() |> elem(0),
           start |> NaiveDateTime.add(1, :hour) |> NaiveDateTime.to_gregorian_seconds() |> elem(0)}
        end

      assert spans(Tempo.to_interval(~o"2026Y6ML2WT10HN")) == at_ten
      assert spans(Tempo.to_interval(~o"2026Y6ML2W3KT10HN")) == [Enum.at(at_ten, 2)]
    end

    test "with a day of the month keeps the day it names, and with a position the day so placed" do
      # The second week of June 2026 is the 8th to the 14th.
      assert week(2026, 6, 2) == {~D[2026-06-08], ~D[2026-06-15]}
      day = &[seconds({&1, Date.add(&1, 1)})]

      assert spans(Tempo.to_interval(~o"2026Y6ML2W9DN")) == day.(~D[2026-06-09])
      assert spans(Tempo.to_interval(~o"2026Y6ML2W20DN")) == []
      assert spans(Tempo.to_interval(~o"2026Y6ML2W1IN")) == day.(~D[2026-06-08])
      assert spans(Tempo.to_interval(~o"2026Y6ML2W-1IN")) == day.(~D[2026-06-14])
      assert spans(Tempo.to_interval(~o"2026Y6ML2W{1,3}K1IN")) == day.(~D[2026-06-08])
      assert spans(Tempo.to_interval(~o"2026Y6ML-1W-1KN")) == day.(~D[2026-06-28])

      assert spans(Tempo.to_interval(~o"2026Y6ML{1,2}W{1,3}KN")) ==
               Enum.flat_map(
                 [~D[2026-06-01], ~D[2026-06-03], ~D[2026-06-08], ~D[2026-06-10]],
                 day
               )
    end

    test "is what Tempo.select/2 gives, each day the value it is" do
      {:ok, by_selection} = Tempo.select(~o"2026-06", ~o"L2W3KN")
      {:ok, by_constraint} = Tempo.select(~o"2026-06", ~o"2W3K")

      assert [%Interval{unit: :hour} = wednesday] = IntervalSet.members(by_selection)
      assert bounds(wednesday) == seconds({~D[2026-06-10], ~D[2026-06-11]})
      assert IntervalSet.members(by_constraint) == [wednesday]

      # A time under the week alone is on each of its days by a selection, as
      # it is under a week of a year, and on its first by a constraint, as
      # the value so written is read.
      for {period, selection, constraint} <- [
            {~o"2026-06", ~o"L2WT10HN", ~o"2WT10H"},
            {~o"2026", ~o"L24WT10HN", ~o"24WT10H"}
          ] do
        {:ok, each_day} = Tempo.select(period, selection)
        {:ok, first_day} = Tempo.select(period, constraint)

        assert Enum.map(IntervalSet.members(each_day), &Interval.from/1) ==
                 for(day <- 8..14, do: Tempo.from_iso8601!("2026-06-#{pad(day)}T10"))

        assert Enum.map(IntervalSet.members(first_day), &Interval.from/1) == [~o"2026-06-08T10"]
      end
    end

    test "is each month's in a rule that steps by months" do
      mondays = for month <- 7..9, do: seconds({elem(week(2026, month, 1), 0), 1})

      assert days(Tempo.to_interval(Tempo.from_iso8601!("R3/2026Y7M/P1M/FL1W1KN"))) == mondays

      # From a year, the months of it from the first.
      assert days(Tempo.to_interval(Tempo.from_iso8601!("R3/2026Y/P1M/FL1W1KN"))) ==
               for(month <- 1..3, do: seconds({elem(week(2026, month, 1), 0), 1}))

      # With no start, those of them in the window: the Monday of July's
      # first week is 29 June.
      assert days(
               Tempo.to_interval(Tempo.from_iso8601!("R/../P1M/FL1W1KN"),
                 within: ~o"2026-07/2026-09"
               )
             ) == Enum.drop(mondays, 1)

      # A month has no seventh week, and the rule no occurrence.
      assert days(Tempo.to_interval(Tempo.from_iso8601!("R3/2026Y6M/P1M/FL7W1KN"))) == []
    end

    test "is each month's from a set or a range of years, and from a set of months" do
      wednesday = fn year, month -> seconds({Date.add(elem(week(year, month, 2), 0), 2), 1}) end

      assert days(Tempo.to_interval(Tempo.from_iso8601!("R/{2026Y,2028Y}/P1M/FL2W3KN"))) ==
               for(year <- [2026, 2028], month <- 1..12, do: wednesday.(year, month))

      assert days(Tempo.to_interval(Tempo.from_iso8601!("R/{2026Y..2027Y}/P1M/FL2W3KN"))) ==
               for(year <- 2026..2027, month <- 1..12, do: wednesday.(year, month))

      assert spans(Tempo.to_interval(Tempo.from_iso8601!("R/{2026Y6M,2026Y9M}/P1M/FL2WN"))) ==
               for(month <- [6, 9], do: seconds(week(2026, month, 2)))
    end

    test "is its days in whatever order a rule built by hand holds its parts" do
      # A rule is read with its parts from the coarsest, and one built with
      # the week last starts from a month, with no day to move.
      rule = %Tempo{time: [selection: [day_of_week: 3, week: 2]], calendar: Gregorian}

      recurrence =
        Interval.new!(from: ~o"2026-06", duration: ~o"P1M", recurrence: 2, repeat_rule: rule)

      assert days(Tempo.to_interval(recurrence)) ==
               for(month <- 6..7, do: seconds({Date.add(elem(week(2026, month, 2), 0), 2), 1}))
    end

    test "as the calendar's own week is refused in a rule of months, and limits one from a date" do
      for {text, options} <- [
            {"R2/2026Y6M/P1M/FL2wN", []},
            {"R/../P1M/FL2wN", [within: ~o"2026"]}
          ] do
        assert {^text, {:error, %ConversionError{reason: :not_built, target: :week_of_month}}} =
                 {text, Tempo.to_interval(Tempo.from_iso8601!(text), options)}
      end

      # 8 June is in the calendar's week 24 of 2026 and of 2027, and the rule
      # keeps the months whose 8th is.
      for year <- [2026, 2027] do
        assert Gregorian.week_of_year(year, 6, 8) == {year, 24}
      end

      {:ok, kept} = Tempo.to_interval(Tempo.from_iso8601!("R2/2026-06-08/P1M/FL24wN"))

      assert Enum.map(IntervalSet.members(kept), &Interval.from/1) ==
               [~o"2026-06-08", ~o"2027-06-08"]
    end

    test "is refused in a rule of a calendar whose year begins within a month" do
      for text <- ["R2/1750Y6M/P1M/FL2WN", "R2/1750Y6M/P1M/FL2W3KN"] do
        assert {^text, {:error, %ConversionError{reason: :not_built, calendar: March25}}} =
                 {text, Tempo.to_interval(Tempo.from_iso8601!(text, March25))}
      end
    end

    test "is the day its calendar numbers in the week, where the calendar cuts a month's weeks short" do
      # The days of the second week of Adar 5787, as Calendrical numbers
      # them, and the one of them that is a Wednesday.
      in_week =
        for day <- 1..Hebrew.days_in_month(5787, 6),
            Hebrew.week_of_month(5787, 6, day) == {6, 2},
            do: Date.new!(5787, 6, day, Hebrew)

      assert [wednesday] =
               Enum.filter(in_week, &(Date.day_of_week(Date.convert!(&1, Calendar.ISO)) == 3))

      {:ok, selected} = Tempo.to_interval(Tempo.from_iso8601!("5787Y6ML2W3KN[u-ca=hebrew]"))

      assert Enum.map(IntervalSet.members(selected), &Tempo.to_date(Interval.from(&1))) ==
               [{:ok, wednesday}]
    end

    test "is worded as a week of the month, and has no RRULE to be written as" do
      assert Tempo.explain(~o"2026Y6ML2W3KN") =~ "in the 2nd week of the month, on a Wednesday"
      assert Tempo.explain(~o"2026YL24W3KN") =~ "in the 24th ISO week"

      assert {:error, %ConversionError{target: :rrule} = error} =
               RRule.to_string(Tempo.from_iso8601!("R/2026Y6M/P1M/FL2W3KN"))

      assert Exception.message(error) =~ "a week of a month"
    end
  end

  describe "the weeks of a month, as the one place they are worked out gives them" do
    test "are the weeks the measure has, each from its first date to its last" do
      for {year, month} <- @months do
        {:ok, weeks} = UnitValues.weeks_of_month(year, month, Gregorian)

        expected =
          for week <- 1..weeks_in(year, month) do
            {monday, next} = week(year, month, week)
            {monday, Date.add(next, -1)}
          end

        found =
          Enum.map(
            weeks,
            &{Date.convert!(&1.first, Calendar.ISO), Date.convert!(&1.last, Calendar.ISO)}
          )

        assert {year, month, found} == {year, month, expected}
      end
    end

    test "are none for a month the calendar does not have, and in a calendar of weeks" do
      assert UnitValues.weeks_of_month(2026, 13, Gregorian) == {:error, :no_period}
      assert UnitValues.weeks_of_month(2026, 6, Calendrical.ISOWeek) == {:error, :no_period}
      assert UnitValues.weeks_of_month(1750, 6, March25) == {:error, :no_period}
      assert UnitValues.week_of_month(2026, 6, 0, Gregorian) == {:error, :no_period}
      assert UnitValues.week_of_month(2026, 6, "2", Gregorian) == {:error, :no_period}
    end
  end
end
