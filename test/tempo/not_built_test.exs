defmodule Tempo.NotBuiltTest do
  use ExUnit.Case, async: true

  # What Tempo does not yet work out, and is known to answer wrongly, is
  # refused by name: a `Tempo.ConversionError` whose reason is `:not_built`.
  # Each refusal is held here, and beside it what is still answered, against
  # an answer taken from the calendar's own functions.

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.ISOWeek
  alias Calendrical.Julian
  alias Calendrical.Julian.Dec25
  alias Calendrical.Julian.March1
  alias Calendrical.Julian.March25
  alias Calendrical.Julian.Sept1
  alias Calendrical.NRF
  alias Calendrical.Reform.England
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  # The calendars of one rule whose year does not begin with its first month.
  @turning [March25, March1, Sept1, Dec25]

  defp read(text, calendar), do: Tempo.from_iso8601!(text, calendar)

  defp not_built(target, calendar),
    do: %ConversionError{reason: :not_built, target: target, calendar: calendar}

  defp refused?({:error, %ConversionError{} = error}, target, calendar),
    do: %{error | value: nil} == not_built(target, calendar)

  defp refused?(_answer, _target, _calendar), do: false

  # The first day of each span of a set, as dates of the set's calendar.
  defp first_days({:ok, %IntervalSet{} = set}, calendar),
    do: for(interval <- IntervalSet.members(set), do: first_day(interval, calendar))

  defp first_day(interval, calendar),
    do: interval |> Interval.from() |> day(calendar)

  defp day(%Tempo{} = value, calendar) do
    {:ok, date} = value |> Tempo.extend_resolution(:day) |> Tempo.trunc(:day) |> Tempo.to_date()
    Date.convert!(date, calendar)
  end

  defp days(%Date.Range{} = range), do: Enum.to_list(range)

  defp mondays(dates), do: Enum.filter(dates, &(Date.day_of_week(&1) == 1))

  describe "a selection that counts days within a month or a year" do
    for calendar <- @turning do
      test "is refused in a value of #{inspect(calendar)}" do
        calendar = unquote(calendar)

        for text <- ~w(1750Y12ML-1DN 1750Y1ML1DN 1750Y3ML5DN 1750Y1ML1KN 1750Y12ML1K-1IN
                       1750YL1K1IN 1750YL1K-1IN 1750YL1KN 1750YL3M1KN) do
          value = read(text, calendar)

          assert refused?(Tempo.to_interval(value), :selection, calendar), text
          assert refused?(Tempo.to_interval_set(value), :selection, calendar), text
          assert refused?(Tempo.to_string(value), :selection, calendar), text
          assert_raise ConversionError, fn -> Enum.to_list(value) end
        end
      end

      test "is refused in the rule of a recurrence that steps by months or years of #{inspect(calendar)}" do
        calendar = unquote(calendar)

        for text <- ~w(R4/1750Y11M/P1M/FL1DN R4/1750Y11M/P1M/FL-1DN R3/1750Y1M/P1M/FL1KN
                       R2/1750Y5M10D/P1Y/FL1K1IN R2/1750Y5M10D/P1Y/FL15DN) do
          recurrence = read(text, calendar)

          assert refused?(Tempo.to_interval(recurrence), :selection, calendar), text
          assert_raise ConversionError, fn -> Enum.take(recurrence, 1) end
        end
      end

      test "is refused for a day of a month selected from a month of #{inspect(calendar)}" do
        calendar = unquote(calendar)

        for {span, selector} <- [{"1750Y1M", "-1D"}, {"1750Y12M", "1D"}, {"1750Y12M", "{1,15}D"}] do
          selected = Tempo.select(read(span, calendar), read(selector, calendar))

          assert refused?(selected, :selection, calendar), "#{selector} from #{span}"
        end

        assert refused?(Tempo.select(read("1750Y1M", calendar), [1, 15]), :selection, calendar)

        assert refused?(
                 Tempo.select(read("1750Y", calendar), read("L1K1IN", calendar)),
                 :selection,
                 calendar
               )
      end
    end

    test "names the value, what was asked for and the calendar" do
      {:error, error} = Tempo.to_interval(read("1750Y12ML-1DN", March25))

      assert Exception.message(error) =~
               "a selection that counts days within a month or a year is not built for " <>
                 "Calendrical.Julian.March25, whose year does not begin with its first month"

      assert Exception.message(error) =~ "1750Y12ML-1DN"
    end

    test "a month with a day is the date they name" do
      assert first_days(Tempo.to_interval(read("1750YL3M25DN", March25)), March25) ==
               [Date.new!(1750, 3, 25, March25)]

      assert first_days(Tempo.to_interval(read("1750YL3M24DN", March25)), March25) ==
               [Date.new!(1750, 3, 24, March25)]

      assert first_days(Tempo.select(read("1750Y", March25), read("3M25D", March25)), March25) ==
               [Date.new!(1750, 3, 25, March25)]
    end

    test "a month alone is the month the calendar counts" do
      for calendar <- @turning, month <- [1, 3, 12] do
        %Date.Range{first: first} = calendar.month(1750, month)
        year = read("1750Y", calendar)

        assert first_days(Tempo.to_interval(read("1750YL#{month}MN", calendar)), calendar) == [
                 first
               ]

        assert first_days(Tempo.select(year, read("#{month}M", calendar)), calendar) == [first]
        assert first_days(Tempo.select(year, [month]), calendar) == [first]
      end
    end

    test "a day of a month is selected from a span of dates" do
      # The 15ths from 25 March to 1 June: 15 March is at the year's end.
      selected = Tempo.select(read("1750Y3M25D/1750Y6M1D", March25), read("15D", March25))

      assert first_days(selected, March25) ==
               [Date.new!(1750, 4, 15, March25), Date.new!(1750, 5, 15, March25)]
    end

    test "a day of the year is counted from the day the year begins" do
      for calendar <- @turning, day <- [1, 100, 365] do
        date = calendar.year(1750) |> days() |> Enum.at(day - 1)

        assert first_days(Tempo.to_interval(read("1750YL#{day}ON", calendar)), calendar) == [date]

        assert first_days(
                 Tempo.select(read("1750Y", calendar), read("#{day}O", calendar)),
                 calendar
               ) ==
                 [date]
      end
    end

    test "a day with no month, selected in a year, is a day of the year" do
      # It was refused while it was read as a day of the year's first month.
      for calendar <- @turning, {day, index} <- [{1, 0}, {15, 14}, {100, 99}, {-1, -1}] do
        date = calendar.year(1750) |> days() |> Enum.at(index)
        next = calendar.year(1751) |> days() |> Enum.at(index)
        year = read("1750Y", calendar)

        assert first_days(Tempo.to_interval(read("1750YL#{day}DN", calendar)), calendar) == [date]
        assert first_days(Tempo.select(year, read("#{day}D", calendar)), calendar) == [date]
        assert first_days(Tempo.select(year, read("L#{day}DN", calendar)), calendar) == [date]

        assert first_days(Tempo.to_interval(read("R2/1750Y/P1Y/FL#{day}DN", calendar)), calendar) ==
                 [date, next]
      end
    end

    test "a weekday given to select/2 is selected among the days of the month or the year" do
      for calendar <- @turning, month <- [1, 2, 12] do
        expected = calendar.month(1750, month) |> days() |> mondays()
        selected = Tempo.select(read("1750Y#{month}M", calendar), read("1K", calendar))

        assert first_days(selected, calendar) == expected
      end

      for calendar <- @turning do
        expected = calendar.year(1750) |> days() |> mondays()
        selected = Tempo.select(read("1750Y", calendar), read("1K", calendar))

        assert first_days(selected, calendar) == expected
      end
    end

    test "a selection in a recurrence that steps by weeks or by less is answered" do
      start = Date.new!(1750, 3, 25, March25)
      weekly = Tempo.to_interval(read("R3/1750Y3M25D/P1W/FL1KN", March25))
      daily = Tempo.to_interval(read("R2/1750Y3M25D/P1D/FL1KN", March25))

      # 25 March 1750 is a Sunday: the Monday of each week from it, and the
      # first two Mondays among the days from it.
      assert Date.day_of_week(start) == 7
      assert first_days(weekly, March25) == for(days <- [1, 8, 15], do: Date.add(start, days))
      assert first_days(daily, March25) == for(days <- [1, 8], do: Date.add(start, days))
    end

    test "is answered where the year begins with its first month" do
      assert first_days(Tempo.to_interval(read("1750Y12ML-1DN", Julian)), Julian) ==
               [Date.new!(1750, 12, 31, Julian)]

      assert first_days(Tempo.to_interval(read("1750YL1K1IN", Julian)), Julian) ==
               [Julian.year(1750) |> days() |> mondays() |> hd()]
    end
  end

  describe "a season" do
    for calendar <- @turning do
      test "is refused in #{inspect(calendar)}" do
        calendar = unquote(calendar)

        for code <- 21..32 do
          assert refused?(Tempo.from_iso8601("1750Y#{code}M", calendar), :season, calendar),
                 "#{code}"
        end
      end
    end

    test "is refused in a year of England that began on 25 March, and answered in one that did not" do
      assert refused?(Tempo.from_iso8601("1750Y21M", England), :season, England)
      assert {:ok, %Interval{}} = Tempo.from_iso8601("1760Y21M", England)
    end

    test "names the season and the calendar" do
      {:error, error} = Tempo.from_iso8601("1750Y21M", March25)

      assert Exception.message(error) =~ "season 21 of the year 1750"
      assert Exception.message(error) =~ "a season is not built for Calendrical.Julian.March25"
    end

    test "a quarter is the months the calendar counts" do
      for calendar <- @turning, quarter <- 1..4 do
        %Date.Range{first: first, last: last} = calendar.quarter(1750, quarter)
        {:ok, interval} = Tempo.to_interval(read("1750Y#{32 + quarter}M", calendar))

        assert first_day(interval, calendar) == first
        assert interval |> Interval.to() |> day(calendar) == Date.add(last, 1)
      end
    end

    test "is answered where the year begins with its first month" do
      assert {:ok, %Interval{}} = Tempo.from_iso8601("1750Y21M", Julian)
    end
  end

  # A set names its values, and each is stepped by its calendar. A step by
  # days from one was refused, as it was counted through the values the
  # units hold, where the days of such a year are not in the order of their
  # numbers.
  describe "a step from a value that holds several months or years" do
    defp held([value]), do: "#{value}"
    defp held(values), do: "{#{Enum.join(values, ",")}}"

    defp in_order(dates), do: dates |> Enum.uniq() |> Enum.sort_by(&Date.to_gregorian_days/1)

    # The first day of each span an answer names.
    defp landed(%Tempo{} = value, calendar),
      do: first_days(Tempo.to_interval_set(value), calendar)

    defp landed(%IntervalSet{} = set, calendar), do: first_days({:ok, set}, calendar)

    for calendar <- @turning do
      test "is each of its dates stepped by the calendar, in #{inspect(calendar)}" do
        calendar = unquote(calendar)

        for {years, months, days} <- [
              {[1750], [3, 4], [15]},
              {[1750], [2, 3], [24]},
              {[1750], [3, 4], [25]},
              {[1750, 1751], [3], [24]},
              {[1750], [3], [24, 25]},
              {[1750], [11, 12], [24, 25]},
              {[1749, 1750], [1, 12], [1, 31]}
            ],
            {unit, part, by} <- [
              {:day, :days, 1},
              {:day, :days, -1},
              {:week, :weeks, 1},
              {:month, :months, 1}
            ] do
          text = "#{held(years)}Y#{held(months)}M#{held(days)}D"

          expected =
            for year <- years, month <- months, day <- days do
              {year, month, day} = calendar.plus(year, month, day, part, by, coerce: true)
              Date.new!(year, month, day, calendar)
            end

          shifted = Tempo.shift(read(text, calendar), [{unit, by}])

          assert {text, unit, by, landed(shifted, calendar)} ==
                   {text, unit, by, in_order(expected)}
        end
      end

      test "is each of its months and years from its first day, in #{inspect(calendar)}" do
        calendar = unquote(calendar)

        months = for month <- [3, 4], do: 1750 |> calendar.month(month) |> Enum.at(1)
        years = for year <- [1750, 1751], do: year |> calendar.year() |> Enum.at(1)

        assert landed(Tempo.shift(read("1750Y{3,4}M", calendar), day: 1), calendar) == months
        assert landed(Tempo.shift(read("{1750,1751}Y", calendar), day: 1), calendar) == years
      end

      test "is refused beside a mask, in #{inspect(calendar)}" do
        calendar = unquote(calendar)

        for text <- ["1750Y{3,4}MXXD", "1750Y{3,4}M15DTXXH", "{1750,1751}Y3MXXD"] do
          assert refused?(Tempo.shift(read(text, calendar), day: 1), :shift, calendar), text
        end
      end
    end

    test "reaches the day through a time of day" do
      assert Tempo.shift(read("1750Y{3,4}M15DT23H", March25), hour: 2) ==
               read("1750Y{3,4}M16DT1H", March25)
    end

    test "is refused where the calendar does not count the months a set names" do
      # A year of England before 1751: its months are not listed.
      for by <- [[day: 1], [month: 1], [year: 1]] do
        assert refused?(Tempo.shift(read("1750Y{3,4}M15D", England), by), :shift, England)
      end

      # Its years and its days are, and so are the months of a later year.
      assert Tempo.shift(read("{1749,1750}Y3M24D", England), day: 1) ==
               read("{1750,1751}Y3M25D", England)

      assert Tempo.shift(read("1752Y{8,9}M2D", England), month: 1) ==
               read("1752Y{9,10}M2D", England)
    end

    test "is refused from an unspecified day of the month the year begins within" do
      assert refused?(Tempo.shift(read("1750Y3MX*D", March25), day: 1), :shift, March25)
      assert refused?(Tempo.shift(read("1750Y12MX*D", Dec25), day: 1), :shift, Dec25)
      assert refused?(Tempo.shift(read("1750Y3MXXD", March25), day: 1), :shift, March25)
    end

    test "one date is stepped by its calendar" do
      for calendar <- @turning, {month, day} <- [{3, 24}, {12, 31}, {2, 28}, {8, 31}, {12, 24}] do
        {year, to_month, to_day} = calendar.plus(1750, month, day, :days, 1)

        assert Tempo.shift(read("1750Y#{month}M#{day}D", calendar), day: 1) ==
                 read("#{year}Y#{to_month}M#{to_day}D", calendar)
      end
    end

    test "each date a mask of years stands for is stepped by its calendar" do
      for calendar <- @turning do
        expected =
          for year <- 1750..1759 do
            {year, month, day} = calendar.plus(year, 3, 24, :days, 1)
            Date.new!(year, month, day, calendar)
          end

        shifted = Tempo.shift(read("175XY3M24D", calendar), day: 1)

        assert first_days({:ok, shifted}, calendar) ==
                 Enum.sort_by(expected, &Date.to_gregorian_days/1)
      end
    end

    test "several days of the year are stepped date by date, by the calendar" do
      for calendar <- @turning do
        shifted = Tempo.shift(read("{1750,1751}Y100O", calendar), day: 1)
        expected = for year <- [1750, 1751], do: year |> calendar.year() |> days() |> Enum.at(100)

        assert Enum.map(shifted, &day(&1, calendar)) == expected
      end
    end

    test "a step by years is answered" do
      assert Tempo.shift(read("1750Y{3,4}M15D", March25), year: 1) ==
               read("1751Y{3,4}M15D", March25)
    end

    test "a step from an unspecified day of another month than the year begins within is answered" do
      # The days of May, each a day on: some day from 2 May to 1 June.
      assert %Tempo.Set{type: :one, set: [%Tempo.Range{first: first, last: last}]} =
               Tempo.shift(read("1750Y5MX*D", March25), day: 1)

      assert day(first, March25) == Date.new!(1750, 5, 2, March25)
      assert day(last, March25) == Date.new!(1750, 6, 1, March25)
    end
  end

  describe "a month of a year of England before 1751" do
    test "is not read" do
      for text <- ~w(1750Y3M 1750Y5M 1700Y1M 1750Y{3,4}M 1750Y3MT10H {1750,1752}Y3M 1750Y3ML5DN
                     175XY3M 1750YX*M 1750Y2G3MU) do
        assert refused?(Tempo.from_iso8601(text, England), :month, England), text
      end

      assert refused?(Tempo.from_iso8601("1750Y3M/1750Y6M", England), :month, England)
      assert refused?(Tempo.new(year: 1750, month: 3, calendar: England), :month, England)
      assert refused?(Tempo.on(read("5M", England), read("1750Y", England)), :month, England)
    end

    test "is not what a year is walked by, extended to or selected from" do
      year = read("1750Y", England)
      {:ok, span} = Tempo.to_interval(year)

      assert_raise ConversionError, fn -> Enum.to_list(year) end
      assert_raise ConversionError, fn -> Enum.take(span, 1) end
      assert refused?(Tempo.extend(year), :month, England)
      assert refused?(Tempo.extend_resolution(year, :month), :month, England)
      assert refused?(Tempo.shift(year, month: 1), :month, England)
      assert refused?(Tempo.select(year, read("3M", England)), :month, England)
      assert refused?(Tempo.select(year, [3]), :month, England)
      assert refused?(Tempo.to_interval(read("1750YL3MN", England)), :month, England)
    end

    test "is not what a date is truncated or rounded to, or a later month stepped back to" do
      assert refused?(Tempo.trunc(read("1750Y5M10D", England), :month), :month, England)
      assert refused?(Tempo.round(read("1750Y5M20D", England), :month), :month, England)
      assert refused?(Tempo.shift(read("1751Y3M", England), month: -1), :month, England)
      assert refused?(Tempo.shift(read("1751Y6M", England), year: -1), :month, England)
    end

    test "names the value and the calendar" do
      {:error, error} = Tempo.from_iso8601("1750Y3M", England)

      assert Exception.message(error) =~
               "a month of a year that begins within one is not built for Calendrical.Reform.England"
    end

    test "the year, its dates and their steps are answered" do
      %Date.Range{first: first, last: last} = England.year(1750)
      {:ok, span} = Tempo.to_interval(read("1750Y", England))

      assert first_day(span, England) == first
      assert Tempo.trunc(read("1750Y5M10D", England), :year) == read("1750Y", England)

      {year, month, day} = England.plus(last.year, last.month, last.day, :days, 1)

      assert Tempo.shift(read("1750Y3M24D", England), day: 1) ==
               read("#{year}Y#{month}M#{day}D", England)

      assert Tempo.shift(read("1750Y5M10D", England), month: 1) == read("1750Y6M10D", England)
    end

    test "the months of 1751 and of the years after it are answered" do
      for {year, month} <- [{1751, 3}, {1751, 12}, {1752, 9}, {1760, 1}] do
        %Date.Range{first: first} = England.month(year, month)
        {:ok, span} = Tempo.to_interval(read("#{year}Y#{month}M", England))

        assert first_day(span, England) == first
      end

      assert Enum.to_list(read("1751Y", England)) ==
               for(month <- 3..12, do: read("1751Y#{month}M", England))
    end

    test "a month of a year whose months its calendar counts from its start is answered" do
      for calendar <- @turning do
        assert {:ok, %Interval{}} = Tempo.to_interval(read("1750Y1M", calendar))

        assert Enum.to_list(read("1750Y", calendar)) ==
                 for(month <- 1..12, do: read("1750Y#{month}M", calendar))
      end
    end
  end

  # An RRULE is a rule of the Gregorian calendar (RFC 5545), and one written
  # from a recurrence of another carried that calendar's months, weeks and
  # days as if they were Gregorian ones.
  describe "an RRULE of a recurrence of another calendar than the Gregorian" do
    test "is refused where it steps or selects by a month, a year, a week of the year or a day of one" do
      for {text, calendar} <- [
            {"R2/5786Y6M/P1M/FL3KN", Hebrew},
            {"R2/5786Y/P1Y/FL7M15DN", Hebrew},
            {"R2/5786Y6M1D/P1Y", Hebrew},
            {"R2/5786Y6M1D/P1M", Hebrew},
            {"R2/5786Y6M1D/P1D/FL15DN", Hebrew},
            {"R2/5786Y6M1DT0H/PT1H/FL100ON", Hebrew},
            {"R2/2026Y/P1Y/FL10W3KN", NRF},
            {"R2/2026Y/P1Y/FL25W2KN", ISOWeek}
          ] do
        assert refused?(RRule.to_string(read(text, calendar)), :rrule, calendar), text
      end
    end

    test "names the recurrence, what was asked and the calendar" do
      {:error, error} = RRule.to_string(read("R2/5786Y6M/P1M/FL3KN", Hebrew))

      assert Exception.message(error) =~ "R2/5786Y6M/P1M/FL3KN"
      assert Exception.message(error) =~ "an RRULE that steps or selects by a month"
      assert Exception.message(error) =~ "is not built for Calendrical.Hebrew"
    end

    test "is written where it steps by weeks, days or less and selects by weekday and time" do
      assert RRule.to_string(read("R2/5786Y6M1D/P1W/FL3KN", Hebrew)) ==
               {:ok, "COUNT=2;FREQ=WEEKLY;BYDAY=WE"}

      assert RRule.to_string(read("R2/5786Y6M1D/P1D/FLT{9,17}HN", Hebrew)) ==
               {:ok, "COUNT=2;FREQ=DAILY;BYHOUR=9,17"}

      # The third day of an NRF week, which starts on a Sunday, is a Tuesday.
      assert RRule.to_string(read("R2/2026Y25W/P1W/FL3KN", NRF)) ==
               {:ok, "COUNT=2;FREQ=WEEKLY;BYDAY=TU;WKST=SU"}
    end

    test "writes its end as the Gregorian date it is" do
      until = Date.new!(5786, 6, 10, Hebrew) |> Date.convert!(Calendar.ISO)

      daily = %Interval{
        recurrence: :infinity,
        from: read("5786Y6M1D", Hebrew),
        duration: ~o"P1D",
        to: read("5786Y6M10D", Hebrew)
      }

      assert RRule.to_string(daily) == {:ok, "UNTIL=#{Date.to_iso8601(until, :basic)};FREQ=DAILY"}
    end

    test "is written as it was in the Gregorian calendar" do
      assert RRule.to_string(~o"R/2026-01-01/P1Y/FL7M15DN") ==
               {:ok, "FREQ=YEARLY;BYMONTH=7;BYMONTHDAY=15"}

      assert RRule.to_string(~o"R2/2026-06-01/P1M/FL3KN") ==
               {:ok, "COUNT=2;FREQ=MONTHLY;BYDAY=WE"}
    end
  end

  # A week after a month is a week of that month, which no value is read as.
  # `Tempo.select/2` merged one onto a month into a value of a year, a month
  # and a week: its walk yielded `2026Y6M1W1K`, a set operation on it was a
  # `ResolutionError` and its text said "Jun 29, 2025 – Jun 4, 2026".
  describe "a week selected from within a month" do
    test "is refused from a month, in any calendar of months" do
      for {base, calendar} <- [
            {"2026Y6M", Calendrical.Gregorian},
            {"5787Y6M", Hebrew},
            {"1750Y6M", March25}
          ],
          week <- ["1W", "-1W", "25W", "25W3K"] do
        answer = Tempo.select(read(base, calendar), read(week, calendar))
        assert refused?(answer, :week_of_month, calendar), "#{week} from #{base}"
      end
    end

    test "from a day or a time of day is a filter by the week of the year" do
      # 15 June 2026 is in ISO week 25.
      for base <- ["2026Y6M15D", "2026Y6M15DT10H"] do
        {:ok, kept} = Tempo.select(read(base, Calendrical.Gregorian), ~o"25W")
        {:ok, dropped} = Tempo.select(read(base, Calendrical.Gregorian), ~o"26W")

        assert {base, IntervalSet.count(kept), IntervalSet.count(dropped)} == {base, 1, 0}
      end
    end

    test "names what was asked for and the calendar" do
      {:error, error} = Tempo.select(~o"2026-06", ~o"-1W")

      assert Exception.message(error) =~ "the selection of [week: -1] from ~o\"2026Y6M\""

      assert Exception.message(error) =~
               "a week of a month is not built for Calendrical.Gregorian"
    end

    test "a week is selected from a year and from a week, and a weekday from a month" do
      {:ok, weeks} = Tempo.select(~o"2026", ~o"-1W")
      assert Enum.map(IntervalSet.members(weeks), &Interval.from/1) == [~o"2026Y53W"]

      {:ok, same} = Tempo.select(~o"2026-W25", ~o"25W")
      assert Enum.map(IntervalSet.members(same), &Interval.from/1) == [~o"2026Y25W"]

      {:ok, mondays} = Tempo.select(~o"2026-06", ~o"1K")
      assert IntervalSet.count(mondays) == 5
    end
  end
end
