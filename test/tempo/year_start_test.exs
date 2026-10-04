defmodule Tempo.YearStartTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Julian.Dec25
  alias Calendrical.Julian.March1
  alias Calendrical.Julian.March25
  alias Calendrical.Julian.Sept1
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.UnitValues

  # A year that does not begin with its first month.
  #
  # Calendrical's Julian calendars whose year turns on another day than 1
  # January keep each month's Julian number, so a year's dates do not run in
  # the order of their numbers (1 January follows 31 December of the same
  # year), and the calendar counts the months of a year from the day it
  # begins (`month/2`): the first month of a `March25` year is 25 to 31
  # March, and its twelfth 1 February to 24 March.
  #
  # Every answer here is the calendar's own, asked of Calendrical apart from
  # Tempo: `year/1` for a year's days, `month/2` for a month's, `quarter/2`
  # for a quarter's, and Elixir's `Date` for the day after a day.

  @calendars [March25, March1, Sept1, Dec25]

  # 1751 and 1752 hold a Julian leap day between them in each calendar, and
  # year 4 is the first leap year of the era.
  @years [1750, 1751, 1752, 4]

  defp value(text, calendar), do: Tempo.from_iso8601!(text, calendar)

  defp year(year, calendar), do: value("#{year}Y", calendar)

  defp month(year, month, calendar), do: value("#{year}Y#{month}M", calendar)

  defp day(%Date{} = date), do: Tempo.from_elixir(date)

  defp days(%Date.Range{} = range), do: Enum.map(range, &day/1)

  defp span({:ok, %Interval{} = interval}), do: span(interval)

  defp span(%Interval{} = interval) do
    {from, to} = Interval.endpoints(interval)
    {Tempo.extend_resolution(from, :day), Tempo.extend_resolution(to, :day)}
  end

  defp expected_span(%Date.Range{first: first, last: last}),
    do: {day(first), day(Date.add(last, 1))}

  defp cases, do: for(calendar <- @calendars, year <- @years, do: {calendar, year})

  describe "the calendars" do
    test "do not begin their year with their first month" do
      for {calendar, year} <- cases() do
        refute UnitValues.year_begins_with_first_month?(year, calendar)
        assert calendar.year(year).first != Date.new!(year, 1, 1, calendar)
      end

      assert UnitValues.year_begins_with_first_month?(1750, Calendrical.Julian)
      assert UnitValues.year_begins_with_first_month?(1750, Calendrical.Julian.Jan1)
    end
  end

  describe "a year" do
    test "spans the days the calendar gives it" do
      for {calendar, year} <- cases() do
        assert span(Tempo.to_interval(year(year, calendar))) ==
                 expected_span(calendar.year(year)),
               "#{year} in #{inspect(calendar)}"
      end
    end

    test "starts on its first day, ends on its last and holds every day between" do
      for {calendar, year} <- cases() do
        %Date.Range{first: first, last: last} = calendar.year(year)
        year = year(year, calendar)

        assert Tempo.relation(year, day(first)) == :started_by
        assert Tempo.relation(year, day(last)) == :finished_by
        assert Tempo.contains?(year, day(Date.add(first, 100)))
        assert Tempo.relation(year, day(Date.add(first, -1))) == :met_by
        assert Tempo.relation(year, day(Date.add(last, 1))) == :meets
      end
    end

    test "is walked by its months, the first to the last, in the order of their days" do
      for {calendar, year} <- cases() do
        months = Enum.to_list(year(year, calendar))

        assert months == for(month <- 1..12, do: month(year, month, calendar))

        for [earlier, later] <- Enum.chunk_every(months, 2, 1, :discard) do
          assert Tempo.compare(earlier, later) == :lt
          assert Tempo.relation(earlier, later) == :meets
        end
      end
    end

    test "is followed by the next" do
      for {calendar, year} <- cases() do
        assert Tempo.relation(year(year, calendar), year(year + 1, calendar)) == :meets
        assert Tempo.compare(year(year, calendar), year(year + 1, calendar)) == :lt
        assert Tempo.shift(year(year, calendar), year: 1) == year(year + 1, calendar)
      end
    end

    test "written to the day is its first day" do
      for {calendar, year} <- cases() do
        first = calendar.year(year).first

        assert Tempo.extend_resolution(year(year, calendar), :day) == day(first)
        assert Tempo.at_resolution(year(year, calendar), :day) == day(first)
      end
    end
  end

  describe "a month" do
    test "spans the days the calendar gives the month counted from the year's start" do
      for {calendar, year} <- cases(), month <- 1..12 do
        assert span(Tempo.to_interval(month(year, month, calendar))) ==
                 expected_span(calendar.month(year, month)),
               "month #{month} of #{year} in #{inspect(calendar)}"
      end
    end

    test "is walked by those days, counted and found among them" do
      for {calendar, year} <- cases(), month <- 1..12 do
        dates = calendar.month(year, month)
        month = month(year, month, calendar)

        assert Enum.to_list(month) == days(dates)
        assert Enum.count(month) == Enum.count(dates)
        assert Enum.at(month, 0) == day(dates.first)
        assert Enum.member?(month, day(dates.last))
        refute Enum.member?(month, day(Date.add(dates.last, 1)))
      end
    end

    test "is what the interval it converts to is walked by" do
      for {calendar, year} <- cases(), month <- [1, 2, 11, 12] do
        dates = calendar.month(year, month)
        {:ok, interval} = Tempo.to_interval(month(year, month, calendar))

        assert Enum.to_list(interval) == days(dates)
      end
    end

    test "holds each of its days, and is the month each is truncated to" do
      for {calendar, year} <- cases(), month <- 1..12 do
        value = month(year, month, calendar)

        for date <- calendar.month(year, month) do
          assert Tempo.contains?(value, day(date))
          assert Tempo.trunc(day(date), :month) == value
          assert Tempo.at_resolution(day(date), :month) == value
        end
      end
    end

    test "written to the day or the hour is its first day" do
      for {calendar, year} <- cases(), month <- 1..12 do
        first = calendar.month(year, month).first
        value = month(year, month, calendar)

        assert Tempo.extend_resolution(value, :day) == day(first)

        assert Tempo.extend_resolution(value, :hour) ==
                 Tempo.extend_resolution(day(first), :hour)
      end
    end

    test "is a month long, and a year twelve of them" do
      for {calendar, year} <- cases() do
        for month <- 1..12 do
          {:ok, interval} = Tempo.to_interval(month(year, month, calendar))
          assert Tempo.duration(interval) == ~o"P1M"
        end

        {:ok, months} =
          Interval.new(from: month(year, 1, calendar), to: month(year + 1, 1, calendar))

        assert Tempo.duration(months) == ~o"P12M"
      end
    end

    test "is stepped by months through the year's end" do
      for {calendar, year} <- cases() do
        assert Tempo.shift(month(year, 1, calendar), month: 1) == month(year, 2, calendar)
        assert Tempo.shift(month(year, 12, calendar), month: 1) == month(year + 1, 1, calendar)
        assert Tempo.shift(month(year, 1, calendar), month: -1) == month(year - 1, 12, calendar)
      end
    end

    test "is stepped by days from its first day" do
      for {calendar, year} <- cases(), month <- [1, 6, 12] do
        first = calendar.month(year, month).first

        assert Tempo.shift(month(year, month, calendar), day: 1) == day(Date.add(first, 1))
        assert Tempo.shift(month(year, month, calendar), day: -1) == day(Date.add(first, -1))
      end
    end
  end

  describe "a date" do
    test "keeps its month's own number, and is followed by the day after it" do
      for {calendar, year} <- cases() do
        dates = Enum.to_list(calendar.year(year))

        for [date, next] <-
              Enum.chunk_every(dates ++ [Date.add(List.last(dates), 1)], 2, 1, :discard) do
          assert day(date).time == [year: date.year, month: date.month, day: date.day]
          assert Tempo.shift(day(date), day: 1) == day(next)
          assert Tempo.shift(day(next), day: -1) == day(date)
          assert Tempo.compare(day(date), day(next)) == :lt
          assert Tempo.relation(day(date), day(next)) == :meets
        end
      end
    end

    test "is in the year it is truncated to" do
      for {calendar, year} <- cases() do
        %Date.Range{first: first, last: last} = calendar.year(year)

        assert Tempo.trunc(day(first), :year) == year(year, calendar)
        assert Tempo.trunc(day(last), :year) == year(year, calendar)
      end
    end

    test "is read whichever side of the year's turn it is on" do
      for {calendar, year} <- cases() do
        %Date.Range{first: first, last: last} = calendar.year(year)

        for date <- [first, last, Date.add(first, 1), Date.add(last, -1)] do
          text = "#{date.year}Y#{date.month}M#{date.day}D"

          assert Tempo.to_date(value(text, calendar)) == {:ok, date}
        end
      end
    end
  end

  describe "an interval of days" do
    test "from a year's first day to its last is read, and walked through the year" do
      for {calendar, year} <- cases() do
        %Date.Range{first: first, last: last} = dates = calendar.year(year)
        {:ok, interval} = Interval.new(from: day(first), to: day(Date.add(last, 1)))

        assert Enum.count(interval) == Enum.count(dates)
        assert Enum.to_list(interval) == days(dates)

        text =
          "#{first.year}Y#{first.month}M#{first.day}D/#{last.year}Y#{last.month}M#{last.day}D"

        assert {:ok, %Interval{}} = Tempo.from_iso8601(text, calendar)
      end
    end

    test "through the turn of the calendar's months is walked day by day" do
      for {calendar, year} <- cases() do
        december = Date.new!(year, 12, 30, calendar)
        {:ok, interval} = Interval.new(from: day(december), to: day(Date.add(december, 4)))

        assert Enum.to_list(interval) == days(Date.range(december, Date.add(december, 3)))
      end
    end
  end

  describe "a time of day under a year or a month" do
    test "is on the year's first day, and the month's" do
      for {calendar, year} <- cases() do
        first = calendar.year(year).first

        assert value("#{year}YT17H", calendar) ==
                 value("#{first.year}Y#{first.month}M#{first.day}DT17H", calendar)

        for month <- [1, 2, 12] do
          first = calendar.month(year, month).first

          assert value("#{year}Y#{month}MT10H", calendar) ==
                   value("#{first.year}Y#{first.month}M#{first.day}DT10H", calendar)
        end
      end
    end
  end

  describe "a quarter" do
    test "spans the days the calendar gives it, and is walked by its months" do
      for {calendar, year} <- cases(), quarter <- 1..4 do
        value = value("#{year}Y#{quarter}Q", calendar)

        assert span(Tempo.to_interval(value)) == expected_span(calendar.quarter(year, quarter)),
               "quarter #{quarter} of #{year} in #{inspect(calendar)}"

        first = (quarter - 1) * 3 + 1

        assert Enum.to_list(value) ==
                 for(month <- first..(first + 2), do: month(year, month, calendar))
      end
    end
  end

  describe "a day of the year and a week" do
    test "are counted from the year's first day" do
      for {calendar, year} <- cases() do
        first = calendar.year(year).first

        assert value("#{year}Y1O", calendar) == day(first)
        assert value("#{year}Y60O", calendar) == day(Date.add(first, 59))
      end
    end
  end

  describe "set operations" do
    test "a year less its first month is the rest of it" do
      for {calendar, year} <- cases() do
        {:ok, rest} = Tempo.difference(year(year, calendar), month(year, 1, calendar))

        assert [rest] = IntervalSet.members(rest)

        assert span(rest) ==
                 {day(calendar.month(year, 2).first), day(Date.add(calendar.year(year).last, 1))}
      end
    end

    test "the months of a year joined are the year" do
      for {calendar, year} <- cases() do
        months = for month <- 1..12, do: month(year, month, calendar)
        {:ok, joined} = Tempo.union(hd(months), tl(months))

        assert [whole] = joined |> IntervalSet.coalesce() |> IntervalSet.members()
        assert span(whole) == expected_span(calendar.year(year))
        assert Tempo.equal?(joined, year(year, calendar))
      end
    end

    test "a month and a day of it share the day" do
      for {calendar, year} <- cases(), month <- [1, 12] do
        last = calendar.month(year, month).last
        {:ok, shared} = Tempo.intersection(month(year, month, calendar), day(last))

        assert [day] = IntervalSet.members(shared)
        assert span(day) == {day(last), day(Date.add(last, 1))}
      end
    end
  end

  describe "a month written by its days" do
    test "is its dates where they are in one month, and an error where they are in two" do
      for {calendar, year} <- cases(), month <- 1..12 do
        %Date.Range{first: first, last: last} = calendar.month(year, month)
        value = month(year, month, calendar)

        if first.month == last.month do
          assert {:ok, written} = Tempo.extend(value)

          assert written.time == [
                   year: first.year,
                   month: first.month,
                   day: [first.day..last.day]
                 ]

          assert Enum.to_list(written) == Enum.to_list(value)
        else
          assert {:error, %Tempo.ConversionError{}} = Tempo.extend(value)
        end
      end
    end
  end

  describe "a date stepped by months and years" do
    test "is where the calendar steps it to" do
      for {calendar, year} <- cases() do
        %Date.Range{first: first, last: last} = calendar.year(year)

        for date <- [first, last, Date.add(first, 10), Date.new!(year, 12, 31, calendar)],
            months <- [1, 2, 11, 12, -1] do
          # A day the month stepped to does not have is its last.
          {stepped_year, stepped_month, stepped_day} =
            calendar.plus(date.year, date.month, date.day, :months, months, coerce: true)

          assert Tempo.shift(day(date), month: months) ==
                   day(Date.new!(stepped_year, stepped_month, stepped_day, calendar)),
                 "#{inspect(date)} and #{months} months"
        end

        {next_year, month, day} = calendar.plus(first.year, first.month, first.day, :years, 1)
        assert Tempo.shift(day(first), year: 1) == day(Date.new!(next_year, month, day, calendar))
      end
    end
  end

  describe "a day counted in a group of months" do
    test "is counted from the group's first day" do
      for {calendar, year} <- cases(), quarter <- 1..4 do
        %Date.Range{first: first} = dates = calendar.quarter(year, quarter)

        for count <- [1, 40, Enum.count(dates)] do
          assert value("#{year}Y#{quarter}G3MU#{count}D", calendar) ==
                   day(Date.add(first, count - 1)),
                 "day #{count} of quarter #{quarter} of #{year} in #{inspect(calendar)}"
        end

        assert {:error, %Tempo.InvalidDateError{}} =
                 Tempo.from_iso8601("#{year}Y#{quarter}G3MU#{Enum.count(dates) + 1}D", calendar)
      end
    end
  end

  describe "the days of a month a date names" do
    # A month with a day after it is the month the date names, whichever
    # month of the year the calendar counts it as, so its unspecified and
    # masked days are the days so numbered: one span, or where the year
    # turns within the month the days on each side of the turn.
    defp covered(result) do
      {:ok, set} = Tempo.to_interval_set(result)
      set |> IntervalSet.coalesce() |> IntervalSet.members() |> Enum.map(&span/1)
    end

    defp runs_of(dates) do
      # `Date.compare/2` orders one calendar's dates by their fields, which
      # is not the order of these calendars' days.
      dates
      |> Enum.sort_by(&Date.to_gregorian_days/1)
      |> Enum.chunk_while(
        [],
        fn
          date, [] ->
            {:cont, [date]}

          date, [last | _] = run ->
            if Date.diff(date, last) == 1, do: {:cont, [date | run]}, else: {:cont, run, [date]}
        end,
        fn run -> {:cont, run, []} end
      )
      |> Enum.map(fn run -> {day(List.last(run)), day(Date.add(hd(run), 1))} end)
    end

    test "unspecified, are the days the month has" do
      for {calendar, year} <- cases(), month <- 1..12 do
        dates =
          for day <- 1..calendar.days_in_month(year, month),
              do: Date.new!(year, month, day, calendar)

        assert covered(value("#{year}Y#{month}MX*D", calendar)) == runs_of(dates),
               "#{year}Y#{month}MX*D in #{inspect(calendar)}"
      end
    end

    test "masked, are the days its digits allow" do
      for {calendar, year} <- cases(), month <- 1..12 do
        dates =
          for day <- 20..calendar.days_in_month(year, month)//1,
              day <= 29,
              do: Date.new!(year, month, day, calendar)

        assert covered(value("#{year}Y#{month}M2XD", calendar)) == runs_of(dates),
               "#{year}Y#{month}M2XD in #{inspect(calendar)}"
      end
    end
  end

  describe "what is read of a month and a year" do
    test "a month has the days the calendar lists, and starts on its first day's weekday" do
      for {calendar, year} <- cases(), month <- 1..12 do
        %Date.Range{first: first} = dates = calendar.month(year, month)
        value = month(year, month, calendar)

        assert Tempo.days_in_month(value) == Enum.count(dates)
        assert Tempo.day_of_week(value) == Tempo.day_of_week(day(first))
        assert Tempo.quarter_of_year(value) == div(month - 1, 3) + 1
        assert Tempo.day_of_year(value) == Date.diff(first, calendar.year(year).first) + 1
      end
    end

    test "a year starts on its first day's weekday, in its first quarter" do
      for {calendar, year} <- cases() do
        assert Tempo.day_of_week(year(year, calendar)) ==
                 Tempo.day_of_week(day(calendar.year(year).first))

        assert Tempo.quarter_of_year(year(year, calendar)) == 1
        assert Tempo.day_of_year(year(year, calendar)) == 1
      end
    end
  end

  describe "the weekdays selected in a month" do
    test "are those among its days" do
      for {calendar, year} <- cases(), month <- [1, 6, 12] do
        mondays =
          for date <- calendar.month(year, month), Date.day_of_week(date, :monday) == 1, do: date

        {:ok, selected} = Tempo.select(month(year, month, calendar), ~o"1K")

        assert selected |> IntervalSet.members() |> Enum.map(&Interval.from/1) ==
                 Enum.map(mondays, &day/1)
      end
    end
  end

  describe "the text of a year and a month" do
    test "is the year's number, and the month's days" do
      assert Tempo.to_string(year(1750, March25)) == {:ok, "1750"}
      assert Tempo.to_string(month(1750, 1, March25)) == {:ok, "Mar 25\u2009–\u200931, 1750"}

      assert Tempo.to_string(month(1750, 12, March25)) ==
               {:ok, "Feb 1\u2009–\u2009Mar 24, 1750"}

      assert Tempo.to_string(month(1750, 1, Sept1)) == {:ok, "Sep 1\u2009–\u200930, 1750"}
      assert Tempo.to_string(month(1750, 1, March25), format: :yMMM) == {:ok, "Mar 1750"}

      assert Tempo.to_string(value("1750Y1M/1750Y3M", March25)) ==
               {:ok, "Mar 25\u2009–\u2009Apr 30, 1750"}
    end

    test "is explained by the month's number and the span's own dates" do
      assert Tempo.explain(month(1750, 1, March25)) =~
               "Month 1 of 1750.\nSpan: [1750-03-25, 1750-04-01)."

      assert Tempo.explain(year(1750, March25)) =~
               "The year 1750.\nSpan: [1750-03-25, 1751-03-25)."
    end
  end

  describe "a date rounded" do
    test "to the month is the nearer of the month it is in and the next" do
      # The first month of a March25 year is 25 to 31 March, and its twelfth
      # 1 February to 24 March.
      assert Tempo.round(value("1750Y3M27D", March25), :month) == month(1750, 1, March25)
      assert Tempo.round(value("1750Y3M30D", March25), :month) == month(1750, 2, March25)
      assert Tempo.round(value("1750Y2M10D", March25), :month) == month(1750, 12, March25)
      assert Tempo.round(value("1750Y3M10D", March25), :month) == month(1751, 1, March25)
    end

    test "to the year is the nearer of the year it is in and the next" do
      assert Tempo.round(value("1750Y6M10D", March25), :year) == year(1750, March25)
      assert Tempo.round(value("1750Y3M10D", March25), :year) == year(1751, March25)
    end
  end

  describe "a composite calendar" do
    # England's year began on 25 March until 1752, which began on 1 January.
    test "starts each year on the day the calendar in effect does" do
      england = Calendrical.Reform.England

      for year <- [1750, 1751, 1752, 1753] do
        first = Calendrical.first_day_of_year(year, england)

        assert Tempo.extend_resolution(year(year, england), :day) == day(first)
        assert Tempo.relation(year(year, england), day(first)) == :started_by
        assert Tempo.contains?(year(year, england), day(Date.add(first, 200)))
      end

      refute UnitValues.year_begins_with_first_month?(1750, england)
      assert UnitValues.year_begins_with_first_month?(1752, england)
    end
  end

  describe "a calendar whose year begins with its first month" do
    test "is read as it was" do
      for calendar <- [Calendrical.Gregorian, Calendrical.Julian, Calendrical.Hebrew] do
        year = if calendar == Calendrical.Hebrew, do: 5786, else: 2026
        month = month(year, 3, calendar)

        assert Tempo.extend_resolution(month, :day).time == [year: year, month: 3, day: 1]
        assert hd(Enum.to_list(month)).time == [year: year, month: 3, day: 1]
        assert Tempo.trunc(value("#{year}Y3M10D", calendar), :month) == month
      end
    end
  end
end
