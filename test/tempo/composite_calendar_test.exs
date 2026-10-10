defmodule Tempo.CompositeCalendarTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.Reform.England
  alias Calendrical.Reform.Japan
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

      assert Exception.message(error) ==
               "3 is not valid for a day of 1752-09 in Calendrical.Reform.England. " <>
                 "The valid values are 1..2 and 14..30"
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

  describe "a year that begins on another day than the first of its first month" do
    # England's 1751 began on 25 March and ended on 31 December: its months
    # are March to December as they are numbered, and its March is the seven
    # days from the 25th. It is the one such year of the calendars
    # Calendrical has, and every answer here is the calendar's own: `year/1`,
    # `month/2` and `quarter/2` for their dates in order.

    test "is 1751, and neither of the years about it" do
      assert England.year(1751).first == ~D[1751-03-25 Calendrical.Reform.England]

      refute UnitValues.year_begins_with_first_month?(1751, England)
      assert UnitValues.year_begins_with_first_month?(1750, England)
      assert UnitValues.year_begins_with_first_month?(1752, England)
    end

    test "starts with its first day, which the year before meets" do
      %Date.Range{first: first, last: last} = England.year(1751)
      before = Date.add(first, -1)

      assert Tempo.relation(value("1751Y", England), day(first)) == :started_by
      assert Tempo.relation(value("1751Y", England), day(last)) == :finished_by
      assert Tempo.relation(value("1751Y", England), day(before)) == :met_by

      assert Tempo.relation(value("1750Y", England), day(before)) == :finished_by
      assert Tempo.relation(value("1750Y", England), day(first)) == :meets
      assert Tempo.relation(value("1750Y", England), value("1751Y", England)) == :meets
    end

    test "has a first month that starts with the year's first day" do
      %Date.Range{first: first, last: last} = dates = England.month(1751, 3)

      assert first == England.year(1751).first

      assert Tempo.relation(month(1751, 3, England), day(first)) == :started_by
      assert Tempo.relation(month(1751, 3, England), day(last)) == :finished_by
      assert Tempo.relation(month(1751, 3, England), day(Date.add(first, -1))) == :met_by
      assert Tempo.relation(month(1750, 13, England), day(first)) == :meets

      assert Tempo.days_in_month(month(1751, 3, England)) == Enum.count(dates)
    end

    test "is written to its month, and walked from it, by the first month it has" do
      first_month = England.year(1751).first.month

      assert Tempo.extend_resolution(value("1751Y", England), :month) ==
               month(1751, first_month, England)

      {:ok, interval} = Tempo.to_interval(value("1751Y", England))

      assert Enum.to_list(interval) == Enum.to_list(value("1751Y", England))
      assert hd(Enum.to_list(interval)) == month(1751, first_month, England)

      # The month after a year's first is a month on from the year.
      assert Tempo.shift(value("1751Y", England), month: 1) ==
               month(1751, first_month + 1, England)
    end

    test "is at a time of day on its first day" do
      %Date{month: month, day: day} = England.year(1751).first

      assert value("1751YT10H", England) == value("1751Y#{month}M#{day}DT10H", England)
      assert value("1751Y3MT10H", England) == value("1751Y3M#{day}DT10H", England)
    end

    test "counts a day of a quarter and of a half from the day each begins" do
      first_quarter = Enum.to_list(England.quarter(1751, 1))
      second_quarter = Enum.to_list(England.quarter(1751, 2))
      first_half = first_quarter ++ second_quarter

      for {text, date} <- [
            {"1751Y1Q1D", hd(first_quarter)},
            {"1751Y1Q#{length(first_quarter)}D", List.last(first_quarter)},
            {"1751Y2Q1D", hd(second_quarter)},
            {"1751Y2Q#{length(second_quarter)}D", List.last(second_quarter)},
            {"1751Y1H1D", hd(first_half)},
            {"1751Y1H8D", Enum.at(first_half, 7)},
            {"1751Y1H#{length(first_half)}D", List.last(first_half)}
          ] do
        assert {text, value(text, England)} == {text, day(date)}
      end

      for text <- [
            "1751Y1Q#{length(first_quarter) + 1}D",
            "1751Y2Q#{length(second_quarter) + 1}D",
            "1751Y1H#{length(first_half) + 1}D"
          ] do
        assert {^text, {:error, %Tempo.InvalidDateError{}}} =
                 {text, Tempo.from_iso8601(text, England)}
      end
    end

    test "counts a month of a group of years from the first month it has" do
      months = England.year(1751) |> Enum.map(& &1.month) |> Enum.uniq()

      # `1752G1YU` is the group of one year that is 1751.
      assert {:ok, interval} = Tempo.to_interval(value("1752G1YU", England))
      assert Interval.endpoints(interval) == {value("1751Y", England), value("1752Y", England)}

      for {month, nth} <- Enum.with_index(months, 1) do
        assert {nth, value("1752G1YU#{nth}M", England)} == {nth, month(1751, month, England)}
      end

      assert {:error, %Tempo.InvalidDateError{}} =
               Tempo.from_iso8601("1752G1YU#{length(months) + 1}M", England)

      # `104G17YU` is the seventeen years from 1751, and the month after the
      # last of 1751 is the first of 1752.
      assert value("104G17YU#{length(months) + 1}M", England) == month(1752, 1, England)
    end

    test "has months whose every day is the month, as in any calendar" do
      for month <- England.year(1751) |> Enum.map(& &1.month) |> Enum.uniq() do
        {:ok, of_every_day} = Tempo.to_interval(value("1751Y#{month}MX*D", England))
        {:ok, of_the_month} = Tempo.to_interval(month(1751, month, England))

        assert {month, Interval.endpoints(of_every_day)} ==
                 {month, Interval.endpoints(of_the_month)}
      end

      {:ok, of_every_day} = Tempo.to_interval(~o"2026Y3MX*D")
      assert Interval.endpoints(of_every_day) == {~o"2026Y3M", ~o"2026Y4M"}
    end
  end

  describe "a year the calendar does not have" do
    # Japan counted its years otherwise before 1873, and its composite has no
    # day of the years to 1872 as the Gregorian calendar numbers them.
    test "has no month and no day to count, and says so" do
      assert Japan.months_in_year(1872) == 0
      assert Japan.days_in_year(1872) == 0

      # `1873G1YU` is the group of one year that is 1872.
      for text <- ["1873G1YU1M", "1872Y1O", "1872Y1G3MU1D"] do
        assert {^text, {:error, %Tempo.InvalidDateError{} = error}} =
                 {text, Tempo.from_iso8601(text, Japan)}

        refute Exception.message(error) =~ ".."
        assert Exception.message(error) =~ "There are no valid values"
      end
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
