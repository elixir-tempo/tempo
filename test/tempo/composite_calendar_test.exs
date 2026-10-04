defmodule Tempo.CompositeCalendarTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.Reform.England
  alias Calendrical.Reform.Sweden
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.UnitValues

  # A month with days missing, and a year with months missing.
  #
  # A composite calendar changes from one calendar to another on a day, and
  # the month and the year that day is in hold the days and the months that
  # are left. England adopted the Gregorian calendar on 14 September 1752,
  # the day after 2 September, and began 1751 on 25 March and 1752 on 1
  # January, so its 1751 has no January or February and a March of seven
  # days. Sweden's February had thirty days in 1712 and seventeen in 1753.
  #
  # Every answer here is the calendar's own, asked of Calendrical apart from
  # Tempo: `valid_date?/3` for the days a month has, `month/2` and `year/1`
  # for their dates in order, and `plus/6` for a step.

  @months [
    {England, 1752, 9},
    {England, 1752, 8},
    {England, 1751, 3},
    {England, 1751, 12},
    {England, 1753, 9},
    {Sweden, 1712, 2},
    {Sweden, 1753, 2},
    {Sweden, 1700, 2}
  ]

  defp value(text, calendar), do: Tempo.from_iso8601!(text, calendar)

  defp month(year, month, calendar), do: value("#{year}Y#{month}M", calendar)

  defp day(%Date{} = date), do: Tempo.from_elixir(date)

  defp day_numbers(calendar, year, month),
    do: for(day <- 1..31, calendar.valid_date?(year, month, day), do: day)

  describe "what the calendars say" do
    test "is that a month has days missing, begins late or ends early" do
      assert day_numbers(England, 1752, 9) == [1, 2] ++ Enum.to_list(14..30)
      assert day_numbers(England, 1751, 3) == Enum.to_list(25..31)
      assert day_numbers(England, 1751, 1) == []
      assert day_numbers(Sweden, 1712, 2) == Enum.to_list(1..30)
      assert day_numbers(Sweden, 1753, 2) == Enum.to_list(1..17)
    end
  end

  describe "the values a unit takes" do
    test "are the days that are dates, and the months that have days" do
      assert UnitValues.in_period(:day, [year: 1752, month: 9], England) == {:ok, [1..2, 14..30]}
      assert UnitValues.in_period(:day, [year: 1751, month: 3], England) == {:ok, 25..31}
      assert UnitValues.in_period(:day, [year: 1751, month: 1], England) == {:error, :no_period}
      assert UnitValues.in_period(:month, [year: 1751], England) == {:ok, 3..12}
      assert UnitValues.in_period(:month, [year: 1752], England) == {:ok, 1..12}
      assert UnitValues.in_period(:day, [year: 1712, month: 2], Sweden) == {:ok, 1..30}
      assert UnitValues.in_period(:day, [year: 1753, month: 2], Sweden) == {:ok, 1..17}
    end

    test "have a first, a last and a value after and before each" do
      september = [year: 1752, month: 9]

      assert UnitValues.first(:day, [year: 1751, month: 3], England) == {:ok, 25}
      assert UnitValues.first(:month, [year: 1751], England) == {:ok, 3}
      assert UnitValues.last(:day, september, England) == {:ok, 30}
      assert UnitValues.following(:day, 2, september, England) == {:ok, 14}
      assert UnitValues.following(:day, 30, september, England) == :last
      assert UnitValues.preceding(:day, 14, september, England) == {:ok, 2}
      assert UnitValues.preceding(:day, 1, september, England) == :first
      assert UnitValues.preceding(:day, 25, [year: 1751, month: 3], England) == :first
      assert UnitValues.at_or_before(:day, 5, september, England) == {:ok, 2}
      assert UnitValues.at_or_before(:day, 31, september, England) == {:ok, 30}
    end

    test "are counted from the end, named and read among themselves" do
      days = [1..2, 14..30]

      assert UnitValues.from_end(-1, days) == 30
      assert UnitValues.from_end(-17, days) == 14
      assert UnitValues.from_end(-18, days) == 2
      assert UnitValues.named([1..-1//1], days) == [1, 2] ++ Enum.to_list(14..30)
      assert UnitValues.named([2, 3, 14], days) == [2, 14]
      assert UnitValues.resolve(14, days) == {:ok, 14}
      assert UnitValues.resolve(3, days) == {:error, {:not_taken, 3}}
      assert UnitValues.resolve(-18, days) == {:ok, 2}
      assert UnitValues.resolve(1..-1//1, days) == {:ok, [1..2, 14..30]}
      assert UnitValues.resolve(14..20//1, days) == {:ok, 14..20}
      assert UnitValues.resolve([1, 14..-1//1], days) == {:ok, [1, 14..30]}
    end
  end

  describe "a day of a month" do
    test "is read where it is a date of the calendar, and refused where it is not" do
      for {calendar, year, month} <- @months, day <- 1..31 do
        read = Tempo.from_iso8601("#{year}Y#{month}M#{day}D", calendar)

        if calendar.valid_date?(year, month, day) do
          assert {:ok, %Tempo{}} = read
        else
          assert {:error, %Tempo.InvalidDateError{}} = read
        end
      end
    end

    test "that is missing names the days the month has" do
      assert {:error, %Tempo.InvalidDateError{} = error} =
               Tempo.from_iso8601("1752Y9M3D", England)

      assert Exception.message(error) == "3 is not valid. The valid values are 1..2 and 14..30"
    end

    test "counted from the end is counted among the days the month has" do
      assert value("1752Y9M-1D", England) == value("1752Y9M30D", England)
      assert value("1752Y9M-17D", England) == value("1752Y9M14D", England)
      assert value("1752Y9M-18D", England) == value("1752Y9M2D", England)
      assert value("1751Y3M-1D", England) == value("1751Y3M31D", England)
      assert value("1753Y2M-1D", Sweden) == value("1753Y2M17D", Sweden)
    end
  end

  describe "a month" do
    test "is walked by the dates the calendar lists" do
      for {calendar, year, month} <- @months do
        dates = Enum.map(calendar.month(year, month), &day/1)
        value = month(year, month, calendar)

        assert Enum.to_list(value) == dates, "#{year}Y#{month}M in #{inspect(calendar)}"
        assert Enum.count(value) == length(dates)
        assert Tempo.days_in_month(value) == length(dates)
      end
    end

    test "written with every day, a mask or an unspecified day is walked by them too" do
      dates = Enum.map(England.month(1752, 9), &day/1)

      assert Enum.to_list(value("1752Y9M{1..-1}D", England)) == dates
      assert Enum.to_list(value("1752Y9MX*D", England)) == dates

      assert Enum.to_list(value("1752Y9M1XD", England)) ==
               for(day <- 14..19, do: value("1752Y9M#{day}D", England))
    end

    test "written by its days is the days it has, and reads back" do
      assert {:ok, written} = Tempo.extend(month(1752, 9, England))
      assert written == value("1752Y9M{1..2,14..30}D", England)
      assert Enum.to_list(written) == Enum.to_list(month(1752, 9, England))

      assert Tempo.extend(month(1751, 3, England)) == {:ok, value("1751Y3M{25..31}D", England)}
    end

    test "that its year does not have is refused" do
      for month <- [1, 2] do
        assert {:error, %Tempo.InvalidDateError{} = error} =
                 Tempo.from_iso8601("1751Y#{month}M", England)

        assert Exception.message(error) =~ "The valid values are 3..12"
      end
    end

    test "written with a set of days holds none that is missing" do
      assert {:error, %Tempo.InvalidDateError{}} =
               Tempo.from_iso8601("1752Y9M{1,2,3,14}D", England)

      assert Enum.to_list(value("1752Y9M{1,2,14}D", England)) ==
               for(day <- [1, 2, 14], do: value("1752Y9M#{day}D", England))
    end
  end

  describe "a year" do
    test "is walked by the months it has" do
      assert Enum.to_list(value("1751Y", England)) ==
               for(month <- 3..12, do: month(1751, month, England))

      assert Enum.count(value("1752Y", England)) == 12
    end

    test "spans the days the calendar gives it, and is a year long" do
      for {calendar, year} <- [{England, 1751}, {England, 1752}, {Sweden, 1712}, {Sweden, 1753}] do
        %Date.Range{first: first, last: last} = dates = calendar.year(year)
        {:ok, interval} = Tempo.to_interval(value("#{year}Y", calendar))
        {from, to} = Interval.endpoints(interval)

        assert Tempo.extend_resolution(from, :day) == day(first)
        assert Tempo.extend_resolution(to, :day) == day(Date.add(last, 1))
        assert Tempo.duration(interval) == ~o"P1Y"

        {:ok, days} = Interval.new(from: day(first), to: day(Date.add(last, 1)))
        assert Enum.count(days) == Enum.count(dates)
      end
    end
  end

  describe "a step" do
    test "of a day is to the next day the calendar has, and back" do
      for {calendar, year, month} <- @months do
        dates = Enum.to_list(calendar.month(year, month))

        for [date, next] <-
              Enum.chunk_every(dates ++ [Date.add(List.last(dates), 1)], 2, 1, :discard) do
          assert Tempo.shift(day(date), day: 1) == day(next)
          assert Tempo.shift(day(next), day: -1) == day(date)
        end
      end
    end

    test "of months and years is where the calendar steps to" do
      dates = [
        {England, ~D[1752-08-25 Calendrical.Reform.England]},
        {England, ~D[1752-08-05 Calendrical.Reform.England]},
        {England, ~D[1752-08-31 Calendrical.Reform.England]},
        {England, ~D[1752-10-05 Calendrical.Reform.England]},
        {England, ~D[1752-03-15 Calendrical.Reform.England]},
        {England, ~D[1752-01-15 Calendrical.Reform.England]},
        {England, ~D[1751-04-15 Calendrical.Reform.England]},
        {England, ~D[1750-03-10 Calendrical.Reform.England]},
        {Sweden, ~D[1712-01-30 Calendrical.Reform.Sweden]},
        {Sweden, ~D[1753-01-20 Calendrical.Reform.Sweden]}
      ]

      for {calendar, date} <- dates,
          {unit, part} <- [month: :months, year: :years],
          count <- [1, -1, 11, -13] do
        {year, month, day} =
          calendar.plus(date.year, date.month, date.day, part, count, coerce: true)

        assert Tempo.shift(day(date), [{unit, count}]) ==
                 day(Date.new!(year, month, day, calendar)),
               "#{inspect(date)} and #{count} #{part}"
      end
    end

    test "of a month of months is to the next month" do
      assert Tempo.shift(month(1752, 8, England), month: 1) == month(1752, 9, England)
      assert Tempo.shift(month(1752, 1, England), month: -1) == month(1751, 12, England)
      assert Tempo.shift(month(1751, 12, England), month: 1) == month(1752, 1, England)
    end
  end

  describe "a span" do
    test "of a day ends on the next day the calendar has" do
      {:ok, interval} = Tempo.to_interval(value("1752Y9M2D", England))

      assert Interval.endpoints(interval) ==
               {value("1752Y9M2D", England), value("1752Y9M14D", England)}
    end

    test "through the missing days is walked and measured without them" do
      interval = value("1752Y9M1D/1752Y9M16D", England)

      assert Enum.to_list(interval) ==
               for(day <- [1, 2, 14, 15], do: value("1752Y9M#{day}D", England))

      assert Tempo.duration(interval) == ~o"P4D"
    end

    test "of the month holds each of its days, and is the month each is truncated to" do
      september = month(1752, 9, England)

      for date <- England.month(1752, 9) do
        assert Tempo.contains?(september, day(date))
        assert Tempo.trunc(day(date), :month) == september
      end
    end
  end

  describe "a selection in the month" do
    test "counts its days as the month has them" do
      {:ok, last} = Tempo.to_interval(value("1752Y9ML-1DN", England))

      assert last |> IntervalSet.members() |> Enum.map(&Interval.from/1) == [
               value("1752Y9M30D", England)
             ]

      {:ok, third} = Tempo.to_interval(value("1752Y9ML3DN", England))
      assert IntervalSet.members(third) == []

      {:ok, mondays} = Tempo.select(month(1752, 9, England), ~o"1K")

      assert mondays |> IntervalSet.members() |> Enum.map(&Interval.from/1) ==
               for(
                 date <- England.month(1752, 9),
                 Date.day_of_week(date, :monday) == 1,
                 do: day(date)
               )
    end
  end

  describe "a calendar that is not a composite" do
    test "counts its days from one" do
      assert UnitValues.in_period(:day, [year: 2026, month: 2], Calendrical.Gregorian) ==
               {:ok, 1..28}

      assert UnitValues.in_period(:day, [year: 5786, month: 6], Hebrew) ==
               {:ok, 1..Hebrew.days_in_month(5786, 6)}

      assert UnitValues.first(:day, [year: 2026, month: 2], Calendrical.Gregorian) == {:ok, 1}
    end
  end
end
