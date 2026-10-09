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

  # A year that begins on another day than 1 January.
  #
  # Calendrical's Julian calendars whose year turns on another day count the
  # months of a year from the day it begins, and a date's fields are those
  # months and the days of them, in the order of time. A year that begins on
  # the first of a month has twelve; one that begins within a month has
  # thirteen: the first month of a `March25` year is 25 to 31 March, and its
  # thirteenth 1 to 24 March.
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
    test "count their months from the day their year begins, which is not 1 January" do
      for {calendar, year} <- cases() do
        first = calendar.year(year).first
        julian = Date.convert!(first, Calendrical.Julian)

        assert first == Date.new!(year, 1, 1, calendar)
        assert {julian.month, julian.day} != {1, 1}
        assert calendar.months_in_year(year) in [12, 13]
      end
    end

    test "name a date's month and day otherwise than by its fields" do
      assert UnitValues.named_date(1750, 1, 1, March25) == {1750, 3, 25}
      assert UnitValues.named_date(1750, 13, 24, March25) == {1750, 3, 24}
      assert UnitValues.named_date(1750, 1, 1, Sept1) == {1750, 9, 1}

      refute UnitValues.month_named_once?(1750, 1, March25)
      refute UnitValues.month_named_once?(1750, 13, March25)
      assert UnitValues.month_named_once?(1750, 2, March25)
      assert UnitValues.month_named_once?(1750, 1, March1)

      refute UnitValues.year_named_by_its_months?(1750, March25)
      refute UnitValues.year_named_by_its_months?(1750, Dec25)
      assert UnitValues.year_named_by_its_months?(1750, March1)
      assert UnitValues.year_named_by_its_months?(1750, Sept1)
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

        assert months ==
                 for(month <- 1..calendar.months_in_year(year), do: month(year, month, calendar))

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

    test "is a month long, and a year as many of them as the calendar counts" do
      for {calendar, year} <- cases() do
        months_in_year = calendar.months_in_year(year)

        for month <- 1..months_in_year do
          {:ok, interval} = Tempo.to_interval(month(year, month, calendar))
          assert Tempo.duration(interval) == ~o"P1M"
        end

        {:ok, months} =
          Interval.new(from: month(year, 1, calendar), to: month(year + 1, 1, calendar))

        assert Tempo.duration(months) == Tempo.from_iso8601!("P#{months_in_year}M")
      end
    end

    test "is stepped by months through the year's end" do
      for {calendar, year} <- cases() do
        last = calendar.months_in_year(year)
        last_of_the_year_before = calendar.months_in_year(year - 1)

        assert Tempo.shift(month(year, 1, calendar), month: 1) == month(year, 2, calendar)
        assert Tempo.shift(month(year, last, calendar), month: 1) == month(year + 1, 1, calendar)

        assert Tempo.shift(month(year, 1, calendar), month: -1) ==
                 month(year - 1, last_of_the_year_before, calendar)
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

    test "through the turn of a month, and of the year, is walked day by day" do
      for {calendar, year} <- cases(),
          turn <- [calendar.month(year, 2).first, calendar.year(year + 1).first] do
        before = Date.add(turn, -2)
        {:ok, interval} = Interval.new(from: day(before), to: day(Date.add(before, 4)))

        assert Enum.to_list(interval) == days(Date.range(before, Date.add(before, 3)))
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

        # The months the calendar's quarter holds: three, and four in the last
        # quarter of a year of thirteen.
        quarter_days = calendar.quarter(year, quarter)

        assert Enum.to_list(value) ==
                 for(
                   month <- 1..calendar.months_in_year(year),
                   Enum.member?(quarter_days, calendar.month(year, month).first),
                   do: month(year, month, calendar)
                 )
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
        months = for month <- 1..calendar.months_in_year(year), do: month(year, month, calendar)
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

        for date <- [first, last, Date.add(first, 10), Date.add(last, -40)],
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
      # The nth group of three months is the months the calendar counts
      # (n - 1) * 3 + 1 to n * 3, whichever quarter it puts them in.
      for {calendar, year} <- cases(), group <- 1..4 do
        first_month = (group - 1) * 3 + 1
        %Date.Range{first: first} = calendar.month(year, first_month)
        %Date.Range{last: last} = calendar.month(year, first_month + 2)
        dates = Date.range(first, last)

        for count <- [1, 40, Enum.count(dates)] do
          assert value("#{year}Y#{group}G3MU#{count}D", calendar) ==
                   day(Date.add(first, count - 1)),
                 "day #{count} of group #{group} of #{year} in #{inspect(calendar)}"
        end

        assert {:error, %Tempo.InvalidDateError{}} =
                 Tempo.from_iso8601("#{year}Y#{group}G3MU#{Enum.count(dates) + 1}D", calendar)
      end
    end
  end

  describe "the days of a month a date names" do
    # A month with a day after it is the month the calendar counts, so its
    # unspecified and masked days are the days it has, one after another.
    defp covered(result) do
      {:ok, set} = Tempo.to_interval_set(result)
      set |> IntervalSet.coalesce() |> IntervalSet.members() |> Enum.map(&span/1)
    end

    defp runs_of(dates) do
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
      for {calendar, year} <- cases(), month <- 1..calendar.months_in_year(year) do
        dates =
          for day <- 1..calendar.days_in_month(year, month),
              do: Date.new!(year, month, day, calendar)

        assert covered(value("#{year}Y#{month}MX*D", calendar)) == runs_of(dates),
               "#{year}Y#{month}MX*D in #{inspect(calendar)}"
      end
    end

    test "masked, are the days its digits allow, and none where the month is too short" do
      for {calendar, year} <- cases(), month <- 1..calendar.months_in_year(year) do
        dates =
          for day <- 20..calendar.days_in_month(year, month)//1,
              day <= 29,
              do: Date.new!(year, month, day, calendar)

        text = "#{year}Y#{month}M2XD"

        # The seven days from 25 March have no day in the twenties.
        case dates do
          [] ->
            assert {^text, {:error, %Tempo.InvalidDateError{}}} =
                     {text, Tempo.to_interval_set(value(text, calendar))}

          [_ | _] ->
            assert covered(value(text, calendar)) == runs_of(dates),
                   "#{text} in #{inspect(calendar)}"
        end
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

      assert Tempo.to_string(month(1750, 12, March25)) == {:ok, "Feb 1\u2009–\u200928, 1750"}
      assert Tempo.to_string(month(1750, 13, March25)) == {:ok, "Mar 1\u2009–\u200924, 1750"}
      assert Tempo.to_string(value("1750Y1M1D", March25)) == {:ok, "Mar 25, 1750"}

      assert Tempo.to_string(month(1750, 1, Sept1)) == {:ok, "Sep 1\u2009–\u200930, 1750"}
      assert Tempo.to_string(month(1750, 1, March25), format: :yMMM) == {:ok, "Mar 1750"}

      assert Tempo.to_string(value("1750Y1M/1750Y3M", March25)) ==
               {:ok, "Mar 25\u2009–\u2009Apr 30, 1750"}
    end

    # An end is written as far as the value is (decided 2026-10-08), and the
    # day it starts on is told beside it where the writing does not say: a
    # year and a month of this calendar were written as their first dates.
    test "is explained by the month's number, its span as written and the day it starts on" do
      assert Tempo.explain(month(1750, 1, March25)) =~
               "Month 1 of 1750.\nSpan: [1750-01, 1750-02).\nStarts on 1750-03-25."

      assert Tempo.explain(year(1750, March25)) =~
               "The year 1750.\nSpan: [1750, 1751).\nStarts on 1750-03-25."

      assert Tempo.explain(value("1750Y/1752Y", March25)) =~
               "From: 1750 (starts on 1750-03-25).\nTo:   1752 (starts on 1752-03-25; exclusive"

      # A month whose name is its own in the year is told by it, and a date
      # by the day it names.
      assert Tempo.explain(month(1750, 2, March25)) =~ "April 1750."
      assert Tempo.explain(month(1750, 13, March25)) =~ "Month 13 of 1750."
      assert Tempo.explain(value("1750Y1M1D", March25)) =~ "March 25, 1750."
    end
  end

  describe "a date written in words" do
    test "is read as the date it names, and written as it was" do
      # 25 March 1750 is the first day of its year, and 10 April the tenth of
      # the second month the calendar counts.
      for {text, fields} <- [{"March 25, 1750", "1750Y1M1D"}, {"April 10, 1750", "1750Y2M10D"}] do
        assert {text, Tempo.parse(text, locale: :en, calendar: March25)} ==
                 {text, {:ok, value(fields, March25)}}

        assert Tempo.to_string(value(fields, March25), format: :long) == {:ok, text}
      end
    end
  end

  describe "a date rounded" do
    test "to the month is the nearer of the month it is in and the next" do
      # The first month of a March25 year is the seven days from 25 March,
      # its twelfth February and its thirteenth 1 to 24 March.
      assert Tempo.round(value("1750Y1M3D", March25), :month) == month(1750, 1, March25)
      assert Tempo.round(value("1750Y1M6D", March25), :month) == month(1750, 2, March25)
      assert Tempo.round(value("1750Y12M10D", March25), :month) == month(1750, 12, March25)
      assert Tempo.round(value("1750Y13M5D", March25), :month) == month(1750, 13, March25)
      assert Tempo.round(value("1750Y13M20D", March25), :month) == month(1751, 1, March25)
    end

    test "to the year is the nearer of the year it is in and the next" do
      assert Tempo.round(value("1750Y6M10D", March25), :year) == year(1750, March25)
      assert Tempo.round(value("1750Y13M10D", March25), :year) == year(1751, March25)
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

      # The years to 1750 began on 25 March and have thirteen months; 1751
      # ran from 25 March to 31 December, and 1752 began on 1 January.
      assert england.months_in_year(1750) == 13
      assert england.months_in_year(1752) == 12
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
