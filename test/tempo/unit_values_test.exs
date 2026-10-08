defmodule Tempo.UnitValuesTest do
  @moduledoc """
  `Tempo.UnitValues` is the one place a unit's values and a count from the
  end are worked out, so this is the one place they are verified.

  The values a unit takes are held to the calendar asked another way: the
  days and the months it calls valid one by one, the days between two new
  years, Erlang's ISO 8601 week. The values a written value names are held
  to the rule restated as a condition on each value, where the module lists
  them.

  A month whose days are not consecutive (a reform's) is not here: the
  module still takes a month's days as the first to the last of as many as
  the calendar counts, which `plans/enumeration-and-selection.md` lists.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tempo.UnitValues

  doctest Tempo.UnitValues

  # Calendars of whole months whose year begins with its first month, each
  # with the year 15 June 2026 falls in.
  @calendars [
    Calendrical.Gregorian,
    Calendrical.Julian,
    Calendrical.Buddhist,
    Calendrical.Roc,
    Calendrical.Japanese,
    Calendrical.Indian,
    Calendrical.Persian,
    Calendrical.Coptic,
    Calendrical.Ethiopic,
    Calendrical.Ethiopic.AmeteAlem,
    Calendrical.Islamic.Civil,
    Calendrical.Islamic.Tbla,
    Calendrical.Islamic.UmmAlQura,
    Calendrical.Hebrew
  ]

  defp years(calendar) do
    %Date{year: year} = Date.convert!(~D[2026-06-15], calendar)
    (year - 6)..(year + 6)
  end

  # Long enough a run of years for a month to take every length it has: a
  # Hebrew year's lengths repeat within nineteen years, an Islamic one's
  # within thirty.
  defp many_years(calendar) do
    %Date{year: year} = Date.convert!(~D[2026-06-15], calendar)
    (year - 60)..(year + 60)
  end

  describe "in_period/3" do
    test "the months of a year are the months the calendar calls valid" do
      for calendar <- @calendars, year <- years(calendar) do
        valid = Enum.filter(1..14, &calendar.valid_date?(year, &1, 1))

        assert {:ok, months} = UnitValues.in_period(:month, [year: year], calendar)
        assert Enum.to_list(months) == valid, "#{inspect(calendar)} #{year}"
      end
    end

    test "the days of a month are the days the calendar calls valid" do
      for calendar <- @calendars, year <- years(calendar) do
        {:ok, months} = UnitValues.in_period(:month, [year: year], calendar)

        for month <- months do
          valid = Enum.filter(1..40, &calendar.valid_date?(year, month, &1))

          assert {:ok, days} = UnitValues.in_period(:day, [year: year, month: month], calendar)
          assert Enum.to_list(days) == valid, "#{inspect(calendar)} #{year}-#{month}"
        end
      end
    end

    test "the days of a year are the days from one new year to the next" do
      for calendar <- @calendars, year <- years(calendar) do
        new_year = Date.new!(year, 1, 1, calendar)
        next_new_year = Date.new!(year + 1, 1, 1, calendar)

        assert UnitValues.in_period(:day_of_year, [year: year], calendar) ==
                 {:ok, 1..Date.diff(next_new_year, new_year)//1}
      end
    end

    test "the weeks of a Gregorian year, and of a year of weeks, are ISO 8601's" do
      for year <- 1990..2060 do
        {^year, weeks} = :calendar.iso_week_number({year, 12, 28})

        assert UnitValues.in_period(:week, [year: year], Calendrical.Gregorian) ==
                 {:ok, 1..weeks//1}

        assert UnitValues.in_period(:week, [year: year], Calendrical.ISOWeek) ==
                 {:ok, 1..weeks//1}
      end
    end

    test "a unit of the clock and a weekday are the same in every period" do
      assert UnitValues.in_period(:hour, [], Calendrical.Hebrew) == {:ok, 0..23//1}
      assert UnitValues.in_period(:minute, [year: 2026], Calendrical.Gregorian) == {:ok, 0..59//1}
      assert UnitValues.in_period(:second, [], Calendrical.Gregorian) == {:ok, 0..59//1}
      assert UnitValues.in_period(:day_of_week, [], Calendrical.ISOWeek) == {:ok, 1..7//1}
    end

    test "a unit counted in a year or a month the context does not hold is unanchored" do
      assert UnitValues.in_period(:month, [], Calendrical.Gregorian) == {:error, :unanchored}

      assert UnitValues.in_period(:day, [year: 2026], Calendrical.Gregorian) ==
               {:error, :unanchored}

      assert UnitValues.in_period(:day, [month: 6], Calendrical.Gregorian) ==
               {:error, :unanchored}

      assert UnitValues.in_period(:week, [year: [2026, 2027]], Calendrical.Gregorian) ==
               {:error, :unanchored}

      assert UnitValues.in_period(:day_of_year, [], Calendrical.Hebrew) == {:error, :unanchored}
    end

    test "a unit that takes no run of values is uncounted" do
      assert UnitValues.in_period(:year, [], Calendrical.Gregorian) == {:error, :uncounted}
    end

    # Asked for the days of a month its year does not have, one calendar
    # answers as if the months went round, one with no days, and one raises.
    test "the days of a month its year does not have are no period" do
      for calendar <- @calendars, year <- years(calendar) do
        months = calendar.months_in_year(year)

        for month <- [0, months + 1, months + 2, -1] do
          assert UnitValues.in_period(:day, [year: year, month: month], calendar) ==
                   {:error, :no_period},
                 "#{inspect(calendar)} #{year}-#{month}"
        end
      end
    end

    test "a date of a calendar of weeks holds its week where a month is held" do
      {2026, weeks} = :calendar.iso_week_number({2026, 12, 28})

      for calendar <- [Calendrical.ISOWeek, Calendrical.NRF] do
        assert UnitValues.in_period(:day, [year: 2026, month: 25], calendar) == {:ok, 1..7//1}

        assert UnitValues.in_period(:day, [year: 2026, month: 0], calendar) ==
                 {:error, :no_period}
      end

      assert UnitValues.in_period(:day, [year: 2026, month: weeks], Calendrical.ISOWeek) ==
               {:ok, 1..7//1}

      assert UnitValues.in_period(:day, [year: 2026, month: weeks + 1], Calendrical.ISOWeek) ==
               {:error, :no_period}
    end
  end

  describe "in_any_year/3" do
    test "the months of any year are the fewest and the most its years have" do
      for calendar <- @calendars do
        counts = Enum.map(many_years(calendar), &calendar.months_in_year/1)

        assert UnitValues.in_any_year(:month, [], calendar) ==
                 {:ok, 1..Enum.min(counts)//1, 1..Enum.max(counts)//1},
               inspect(calendar)
      end
    end

    test "the days of a month of any year are the fewest and the most its years give it" do
      for calendar <- @calendars do
        years = many_years(calendar)
        most_months = years |> Enum.map(&calendar.months_in_year/1) |> Enum.max()

        for month <- 1..most_months do
          lengths =
            for year <- years, month <= calendar.months_in_year(year) do
              calendar.days_in_month(year, month)
            end

          assert UnitValues.in_any_year(:day, [month: month], calendar) ==
                   {:ok, 1..Enum.min(lengths)//1, 1..Enum.max(lengths)//1},
                 "#{inspect(calendar)} month #{month}"
        end
      end
    end

    test "a unit of the clock and a weekday take the same values in every year" do
      assert UnitValues.in_any_year(:hour, [], Calendrical.Hebrew) == {:ok, 0..23//1, 0..23//1}

      assert UnitValues.in_any_year(:minute, [month: 2], Calendrical.Gregorian) ==
               {:ok, 0..59//1, 0..59//1}

      assert UnitValues.in_any_year(:day_of_week, [], Calendrical.ISOWeek) ==
               {:ok, 1..7//1, 1..7//1}
    end

    test "a year in the context is not read" do
      assert UnitValues.in_any_year(:day, [year: 2027, month: 2], Calendrical.Gregorian) ==
               {:ok, 1..28//1, 1..29//1}
    end

    test "a day with no month, or in a month that is no one month of a year, is unanchored" do
      assert UnitValues.in_any_year(:day, [], Calendrical.Gregorian) == {:error, :unanchored}

      for month <- [0, -1, 13, [1, 2], 1..2, :any] do
        assert UnitValues.in_any_year(:day, [month: month], Calendrical.Gregorian) ==
                 {:error, :unanchored},
               inspect(month)
      end
    end

    test "a week and a day of the year are unanchored: no calendar counts them without a year" do
      for unit <- [:week, :calendar_week, :day_of_year] do
        assert UnitValues.in_any_year(unit, [], Calendrical.Gregorian) == {:error, :unanchored}
        assert UnitValues.in_any_year(unit, [], Calendrical.ISOWeek) == {:error, :unanchored}
      end
    end

    test "a calendar that cannot say without a year is unanchored" do
      # A reform calendar's months change length at the reform.
      assert UnitValues.in_any_year(:day, [month: 6], Calendrical.Reform.England) ==
               {:error, :unanchored}

      assert UnitValues.in_any_year(:month, [], Calendrical.Reform.England) ==
               {:error, :unanchored}

      # Elixir's own calendar answers neither question without a year.
      assert UnitValues.in_any_year(:day, [month: 6], Calendar.ISO) == {:error, :unanchored}
      assert UnitValues.in_any_year(:month, [], Calendar.ISO) == {:error, :unanchored}
    end

    test "a unit that takes no run of values is uncounted" do
      assert UnitValues.in_any_year(:year, [], Calendrical.Gregorian) == {:error, :uncounted}
    end
  end

  # A step asks what follows a value and what comes before it, and for the
  # first and the last value of the period it carries into or borrows from.
  # Each is held to the calendar's own word on which dates are valid.
  describe "following/4, preceding/4, first/3 and last/3, in a year" do
    test "a day is followed by the next the calendar calls valid, and the last by none" do
      for calendar <- @calendars, year <- years(calendar) do
        for month <- 1..calendar.months_in_year(year) do
          context = [year: year, month: month]
          valid = Enum.filter(1..40, &calendar.valid_date?(year, month, &1))

          assert UnitValues.first(:day, context, calendar) == {:ok, hd(valid)}
          assert UnitValues.last(:day, context, calendar) == {:ok, List.last(valid)}

          for day <- valid do
            expected = if (day + 1) in valid, do: {:ok, day + 1}, else: :last
            assert UnitValues.following(:day, day, context, calendar) == expected

            expected = if (day - 1) in valid, do: {:ok, day - 1}, else: :first
            assert UnitValues.preceding(:day, day, context, calendar) == expected
          end
        end
      end
    end

    test "a month is followed by the next the calendar calls valid, and the last by none" do
      for calendar <- @calendars, year <- years(calendar) do
        context = [year: year]
        valid = Enum.filter(1..14, &calendar.valid_date?(year, &1, 1))

        assert UnitValues.first(:month, context, calendar) == {:ok, hd(valid)}
        assert UnitValues.last(:month, context, calendar) == {:ok, List.last(valid)}

        for month <- valid do
          expected = if (month + 1) in valid, do: {:ok, month + 1}, else: :last
          assert UnitValues.following(:month, month, context, calendar) == expected

          expected = if (month - 1) in valid, do: {:ok, month - 1}, else: :first
          assert UnitValues.preceding(:month, month, context, calendar) == expected
        end
      end
    end

    test "a day of the year and a week are followed by the next their year has" do
      for year <- 2020..2032 do
        days = Date.diff(Date.new!(year + 1, 1, 1), Date.new!(year, 1, 1))
        {^year, weeks} = :calendar.iso_week_number({year, 12, 28})
        context = [year: year]

        assert UnitValues.last(:day_of_year, context, Calendrical.Gregorian) == {:ok, days}
        assert UnitValues.following(:day_of_year, days, context, Calendrical.Gregorian) == :last

        assert UnitValues.following(:day_of_year, days - 1, context, Calendrical.Gregorian) ==
                 {:ok, days}

        assert UnitValues.last(:week, context, Calendrical.Gregorian) == {:ok, weeks}
        assert UnitValues.following(:week, weeks, context, Calendrical.Gregorian) == :last

        assert UnitValues.following(:week, weeks - 1, context, Calendrical.Gregorian) ==
                 {:ok, weeks}

        assert UnitValues.preceding(:week, 1, context, Calendrical.Gregorian) == :first
      end
    end

    test "the first and the last are the ends of the values the unit takes" do
      for {unit, context} <- [
            month: [year: 2026],
            week: [year: 2026],
            calendar_week: [year: 2026],
            day_of_year: [year: 2026],
            day: [year: 2026, month: 2],
            day_of_week: [],
            hour: [],
            minute: [],
            second: []
          ] do
        assert {:ok, %Range{first: first, last: last}} =
                 UnitValues.in_period(unit, context, Calendrical.Gregorian)

        assert UnitValues.first(unit, context, Calendrical.Gregorian) == {:ok, first},
               inspect(unit)

        assert UnitValues.last(unit, context, Calendrical.Gregorian) == {:ok, last}, inspect(unit)
        assert UnitValues.following(unit, last, context, Calendrical.Gregorian) == :last
        assert UnitValues.preceding(unit, first, context, Calendrical.Gregorian) == :first
      end
    end

    test "a day past the last of its month is the last, and any other is itself" do
      for calendar <- @calendars, year <- years(calendar) do
        for month <- 1..calendar.months_in_year(year) do
          context = [year: year, month: month]
          valid = Enum.filter(1..40, &calendar.valid_date?(year, month, &1))

          for day <- 1..40 do
            expected = valid |> Enum.filter(&(&1 <= day)) |> List.last()
            assert UnitValues.at_or_before(:day, day, context, calendar) == {:ok, expected}
          end
        end
      end
    end

    test "an unspecified value counts as the last" do
      assert UnitValues.following(:day, :any, [year: 2026, month: 6], Calendrical.Gregorian) ==
               :last

      assert UnitValues.following(:month, :any, [year: 5787], Calendrical.Hebrew) == :last
      assert UnitValues.following(:week, :any, [year: 2026], Calendrical.Gregorian) == :last
      assert UnitValues.following(:day, :any, [month: 2], Calendrical.Gregorian) == :last
    end

    test "a unit that takes no run of values is uncounted" do
      assert UnitValues.first(:year, [], Calendrical.Gregorian) == {:error, :uncounted}
      assert UnitValues.last(:year, [], Calendrical.Gregorian) == {:error, :uncounted}
      assert UnitValues.following(:year, 2026, [], Calendrical.Gregorian) == {:error, :uncounted}
      assert UnitValues.preceding(:year, 2026, [], Calendrical.Gregorian) == {:error, :uncounted}
    end
  end

  describe "following/4 and last/3, with no year" do
    test "a day is followed by the next where every year has it, and is the last where no year has another" do
      for calendar <- @calendars do
        years = many_years(calendar)
        most_months = years |> Enum.map(&calendar.months_in_year/1) |> Enum.max()

        for month <- 1..most_months do
          lengths =
            for year <- years, month <= calendar.months_in_year(year) do
              calendar.days_in_month(year, month)
            end

          {fewest, most} = Enum.min_max(lengths)

          for day <- 1..most do
            expected =
              cond do
                day < fewest -> {:ok, day + 1}
                day == most -> :last
                true -> {:error, :unanchored}
              end

            assert UnitValues.following(:day, day, [month: month], calendar) == expected,
                   "#{inspect(calendar)} #{month}-#{day}"
          end

          expected = if fewest == most, do: {:ok, most}, else: {:error, :unanchored}
          assert UnitValues.last(:day, [month: month], calendar) == expected
        end
      end
    end

    test "a month is followed by the next where every year has it, and is the last where no year has another" do
      for calendar <- @calendars do
        {fewest, most} =
          calendar |> many_years() |> Enum.map(&calendar.months_in_year/1) |> Enum.min_max()

        for month <- 1..most do
          expected =
            cond do
              month < fewest -> {:ok, month + 1}
              month == most -> :last
              true -> {:error, :unanchored}
            end

          assert UnitValues.following(:month, month, [], calendar) == expected,
                 "#{inspect(calendar)} #{month}"
        end
      end
    end

    test "a day every year's month has is itself, and one past a month of one length its last" do
      for calendar <- @calendars do
        years = many_years(calendar)
        most_months = years |> Enum.map(&calendar.months_in_year/1) |> Enum.max()

        for month <- 1..most_months do
          lengths =
            for year <- years, month <= calendar.months_in_year(year) do
              calendar.days_in_month(year, month)
            end

          {fewest, most} = Enum.min_max(lengths)

          for day <- 1..40 do
            expected =
              cond do
                day <= fewest -> {:ok, day}
                fewest == most -> {:ok, most}
                true -> {:error, :unanchored}
              end

            assert UnitValues.at_or_before(:day, day, [month: month], calendar) == expected,
                   "#{inspect(calendar)} #{month}-#{day}"
          end
        end
      end
    end

    test "a week and a day of the year are followed by nothing that can be said" do
      assert UnitValues.following(:week, 25, [], Calendrical.Gregorian) == {:error, :unanchored}

      assert UnitValues.following(:day_of_year, 200, [], Calendrical.Gregorian) ==
               {:error, :unanchored}

      assert UnitValues.last(:week, [], Calendrical.Gregorian) == {:error, :unanchored}
    end

    test "a calendar that cannot say without a year leaves the step to the year" do
      assert UnitValues.following(:day, 15, [month: 6], Calendrical.Reform.England) ==
               {:error, :unanchored}

      assert UnitValues.following(:day, 15, [year: 2026, month: 6], Calendrical.Reform.England) ==
               {:ok, 16}
    end
  end

  # A number, or a range with a step, written from either end.
  defp written do
    index = integer(-70..70)

    range =
      gen all(first <- index, last <- index, step <- member_of([1, 2, 7])) do
        first..last//step
      end

    list_of(one_of([index, range]), max_length: 4)
  end

  defp values do
    gen all(first <- member_of([0, 1]), last <- integer(0..62)) do
      first..last//1
    end
  end

  # The rule as a condition on one value: it is the number written, counted
  # from the end when that is negative, or it lies between a range's ends on
  # one of the range's steps.
  defp names?(index, value, values) when is_integer(index), do: value == counted(index, values)

  defp names?(%Range{first: first, last: last, step: step}, value, values) do
    from = counted(first, values)
    value >= from and value <= counted(last, values) and rem(value - from, step) == 0
  end

  defp counted(index, %Range{last: last}) when index < 0, do: last + 1 + index
  defp counted(index, _values), do: index

  describe "named/2" do
    property "names each value of the unit that a written number or range names, once and in order" do
      check all(written <- written(), values <- values()) do
        expected = for value <- values, Enum.any?(written, &names?(&1, value, values)), do: value

        assert UnitValues.named(written, values) == expected
      end
    end

    property "takes one written value as it takes a list of one" do
      check all([one] <- list_of(integer(-70..70), length: 1), values <- values()) do
        assert UnitValues.named(one, values) == UnitValues.named([one], values)
      end
    end

    test "a range far longer than the unit's values costs no more than they do" do
      assert UnitValues.named([1..999_999_999//1], 1..30//1) == Enum.to_list(1..30)
    end

    test "what is not a number, a range, a mask or an unspecified unit names nothing" do
      assert UnitValues.named([{3, [approximate: true]}, :nothing, 3], 1..30//1) == [3]
    end

    test "an unspecified unit names every value" do
      # It was passed over, so a part written `X*` selected nothing.
      assert UnitValues.named(:any, 1..30//1) == Enum.to_list(1..30)
      assert UnitValues.named(:any, [1..2//1, 14..30//1]) == [1, 2] ++ Enum.to_list(14..30)
    end

    test "a mask names the values whose digits it matches, written to its width" do
      # A part written with unspecified digits was passed over, and named
      # nothing: `1X` of a month's days is its 10th to its 19th.
      assert UnitValues.named({:mask, [1, :X]}, 1..30//1) == Enum.to_list(10..19)
      assert UnitValues.named({:mask, [3, :X]}, 1..28//1) == []
      assert UnitValues.named({:mask, [:X]}, 1..30//1) == Enum.to_list(1..9)
      assert UnitValues.named({:mask, [:X, 5]}, 1..31//1) == [5, 15, 25]
      assert UnitValues.named([{:mask, [1, :X]}, 3], 1..30//1) == [3 | Enum.to_list(10..19)]

      # One counted from the end is the values that many from the last.
      assert UnitValues.named({:mask, [:negative, :X]}, 1..30//1) == Enum.to_list(22..30)
      assert UnitValues.named({:mask, [:negative, :X]}, 1..5//1) == Enum.to_list(1..5)
    end
  end

  describe "resolve/2" do
    property "keeps what it is given where every value is one the unit has, and names the first that is not" do
      check all(written <- written(), values <- values()) do
        case UnitValues.resolve(written, values) do
          {:ok, resolved} ->
            assert length(resolved) == length(written)
            assert UnitValues.named(resolved, values) == UnitValues.named(written, values)

          {:error, {:not_taken, value}} ->
            assert value in ends(written)
            refute value in values

          {:error, {:not_taken, value, counted}} ->
            assert value in ends(written)
            assert counted == UnitValues.from_end(value, values)
            refute counted in values

          {:error, {:backwards, %Range{first: first, last: last} = range, counted}} ->
            assert range in written
            assert counted.first == UnitValues.from_end(first, values)
            assert counted.last == UnitValues.from_end(last, values)
            assert counted.first > counted.last
        end
      end
    end

    test "a count from the end is the value it names, in a number, a range and a list" do
      assert UnitValues.resolve(-1, 1..30//1) == {:ok, 30}
      assert UnitValues.resolve(28..-1//1, 1..30//1) == {:ok, 28..30//1}
      assert UnitValues.resolve([1, -1, 10..-2//3], 0..23//1) == {:ok, [1, 23, 10..22//3]}
    end

    test "a range within the unit's values is kept as it is written" do
      assert UnitValues.resolve(20..23//1, 0..23//1) == {:ok, 20..23//1}
      assert UnitValues.resolve(0..23//6, 0..23//1) == {:ok, 0..23//6}
    end

    test "a range that counts down, or is counted to a first value after its last, is refused" do
      assert UnitValues.resolve(23..20//-1, 0..23//1) == {:error, {:backwards, 23..20//-1}}
      assert UnitValues.resolve(1..-1//-1, 1..30//1) == {:error, {:backwards, 1..-1//-1}}
      assert UnitValues.resolve(-1..1//1, 1..30//1) == {:error, {:backwards, -1..1//1, 30..1//1}}

      assert UnitValues.resolve(20..-15//1, 1..30//1) ==
               {:error, {:backwards, 20..-15//1, 20..16//1}}

      assert UnitValues.named(23..20//-1, 0..23//1) == []
      assert UnitValues.named(-1..1//1, 1..30//1) == []
    end

    test "a fraction within the unit's values is kept" do
      assert UnitValues.resolve(10.5, 0..23//1) == {:ok, 10.5}
      assert UnitValues.resolve(24.5, 0..23//1) == {:error, {:not_taken, 24.5}}
    end
  end

  # Each written number, and each end of each written range.
  defp ends(written) do
    Enum.flat_map(written, fn
      %Range{first: first, last: last} -> [first, last]
      value -> [value]
    end)
  end

  describe "from_end/2" do
    property "counts back from the last value, and leaves a count from the start as it is" do
      check all(index <- integer(-70..70), values <- values()) do
        counted = UnitValues.from_end(index, values)

        if index < 0,
          do: assert(counted - values.last == index + 1),
          else: assert(counted == index)
      end
    end
  end

  describe "iso_weekday_from_day_of_week/2 and day_of_week_from_iso_weekday/2" do
    # The weekday of each day of a week of the calendar, from its own date
    # converted to Elixir's calendar: every week of a calendar of weeks
    # starts on the same day.
    defp weekday_of_week_day(calendar, {year, week}, day) do
      Date.new!(year, week, day, calendar) |> Date.convert!(Calendar.ISO) |> Date.day_of_week()
    end

    test "a day of a calendar of weeks is the weekday its dates fall on" do
      for calendar <- [Calendrical.NRF, Calendrical.ISOWeek],
          week <- [{2026, 25}, {2024, 1}, {2031, 52}],
          day <- 1..7 do
        weekday = weekday_of_week_day(calendar, week, day)

        assert UnitValues.iso_weekday_from_day_of_week(day, calendar) == weekday
        assert UnitValues.day_of_week_from_iso_weekday(weekday, calendar) == day
      end
    end

    test "a day of a calendar of months is ISO 8601's weekday" do
      for calendar <- [Calendrical.Gregorian, Calendrical.Hebrew, Calendrical.Persian],
          day <- 1..7 do
        assert UnitValues.iso_weekday_from_day_of_week(day, calendar) == day
        assert UnitValues.day_of_week_from_iso_weekday(day, calendar) == day
      end
    end

    test "a number that is no day of a week is left as it is" do
      for calendar <- [Calendrical.Gregorian, Calendrical.NRF], number <- [0, 8, -1] do
        assert UnitValues.iso_weekday_from_day_of_week(number, calendar) == number
        assert UnitValues.day_of_week_from_iso_weekday(number, calendar) == number
      end
    end

    test "a week's days are counted from the calendar's own first day or from Monday" do
      assert UnitValues.week_counted_from(Calendrical.NRF) == :default
      assert UnitValues.week_counted_from(Calendrical.ISOWeek) == :default
      assert UnitValues.week_counted_from(Calendrical.Gregorian) == :monday
      assert UnitValues.week_counted_from(Calendrical.Hebrew) == :monday
    end
  end
end
