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

    test "what is not a number or a range names nothing" do
      assert UnitValues.named([:any, {:mask, [1, :X]}, 3], 1..30//1) == [3]
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
        end
      end
    end

    test "a count from the end is the value it names, in a number, a range and a list" do
      assert UnitValues.resolve(-1, 1..30//1) == {:ok, 30}
      assert UnitValues.resolve(28..-1//1, 1..30//1) == {:ok, 28..30//1}
      assert UnitValues.resolve([1, -1, 10..-2//3], 0..23//1) == {:ok, [1, 23, 10..22//3]}
    end

    test "a range within the unit's values is kept as it is written" do
      assert UnitValues.resolve(23..20//-1, 0..23//1) == {:ok, 23..20//-1}
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
end
