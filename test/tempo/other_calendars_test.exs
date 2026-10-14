defmodule Tempo.OtherCalendarsTest do
  use ExUnit.Case, async: true

  # Calendars that are not the default one, each asked the same questions a
  # Gregorian value is: a calendar of weeks (ISO 8601's, and the NRF retail
  # calendar, whose year begins on a Sunday in February), a calendar that
  # changed from one reckoning to another and left days out (England's, which
  # went from 2 to 14 September 1752), and a calendar whose year begins in
  # the middle of a month (the Julian year from Lady Day, 25 March).
  #
  # The measure is Calendrical's own answer for each calendar and Elixir's
  # `Date` over it: Tempo asks its calendar through the one behaviour and
  # knows nothing of what kind it is.

  import Tempo.Sigils

  alias Calendrical.{ISOWeek, NRF}
  alias Calendrical.Julian.March25
  alias Calendrical.Reform.England
  alias Tempo.{Interval, IntervalSet}

  defp value(%Date{year: year, month: month, day: day, calendar: calendar}),
    do: Tempo.new!(year: year, month: month, day: day, calendar: calendar)

  defp date(%Tempo{} = value) do
    {:ok, date} = Tempo.to_date(value)
    date
  end

  defp days_of(%Tempo{} = value) do
    {:ok, days} = Tempo.walk(value, :day)
    days
  end

  defp gregorian(%Tempo{} = value), do: value |> date() |> Date.convert!(Calendar.ISO)
  defp gregorian(%Date{} = date), do: Date.convert!(date, Calendar.ISO)

  describe "a week date in a calendar of weeks" do
    test "is the day its calendar says" do
      for {calendar, name, week, day} <- [
            {ISOWeek, "iso-week", 25, 2},
            {NRF, "nrf", 20, 3},
            {ISOWeek, "iso-week", 1, 1},
            {NRF, "nrf", 53, 7}
          ],
          year <- [2023, 2026] do
        measured = calendar.date_from_week_date(year, week, day)

        read =
          Tempo.from_iso8601(
            "#{year}-W#{String.pad_leading("#{week}", 2, "0")}-#{day}[u-ca=#{name}]"
          )

        case measured do
          %Date{} ->
            assert {name, year, week, gregorian(elem(read, 1))} ==
                     {name, year, week, gregorian(measured)}

          {:error, _} ->
            assert {^name, ^year, ^week, {:error, _}} = {name, year, week, read}
        end
      end
    end

    test "is written and read as itself, alone and with a time in a zone" do
      for text <- [
            "2026Y20W3K[u-ca=nrf]",
            "2026Y5M17D[u-ca=nrf]",
            "2026Y25W[u-ca=iso-week]",
            "2026Y25W2KT10H30M[Europe/Paris][u-ca=iso-week]"
          ] do
        assert Tempo.to_iso8601(Tempo.from_iso8601!(text)) == {:ok, text}
      end
    end
  end

  describe "a date in the NRF calendar" do
    # Tuesday 16 June 2026 is the seventeenth day of its fifth month, in its
    # week 20.
    setup do
      {:ok, tuesday: Tempo.to_calendar!(~o"2026-06-16", NRF)}
    end

    test "is the date of that calendar, from a Gregorian one and back", %{tuesday: tuesday} do
      assert date(tuesday) == Date.convert!(~D[2026-06-16], NRF)
      assert Tempo.from_elixir(Date.convert!(~D[2026-06-16], NRF)) == {:ok, tuesday}
      assert Tempo.to_calendar(tuesday, Calendar.ISO) == {:ok, ~o"2026-06-16"}
      assert Tempo.relation(tuesday, ~o"2026-06-16") == :equals
    end

    test "has the week and the day of the week its calendar gives it", %{tuesday: tuesday} do
      %Date{year: year, month: month, day: day} = date(tuesday)

      assert {Tempo.year(tuesday), Tempo.week(tuesday)} == NRF.week_of_year(year, month, day)
      assert Tempo.day_of_week(tuesday) == Date.day_of_week(~D[2026-06-16])
    end

    test "is stepped as its calendar steps it", %{tuesday: tuesday} do
      for step <- [[day: 1], [day: -20], [week: 1], [month: 1], [month: -3], [year: 1]] do
        {:ok, stepped} = Tempo.shift(tuesday, step)
        assert {step, date(stepped)} == {step, Date.shift(date(tuesday), step)}
      end
    end

    test "is in a month and a week of the days its calendar gives them" do
      for month <- 1..12 do
        assert {month, Enum.count(Tempo.new!(year: 2026, month: month, calendar: NRF))} ==
                 {month, NRF.days_in_month(2026, month)}
      end

      week = NRF.week(2026, 20)
      days = Tempo.new!(year: 2026, week: 20, calendar: NRF)

      assert Enum.map(days, &gregorian/1) == Enum.map(week, &gregorian/1)
    end

    test "recurs by its calendar's months", %{tuesday: tuesday} do
      monthly = Tempo.every!(~o"P1M", from: tuesday, count: 4)

      assert Enum.map(monthly, &date(Interval.from(&1))) ==
               for(step <- 0..3, do: Date.shift(date(tuesday), month: step))
    end

    test "meets a Gregorian span in a set operation", %{tuesday: tuesday} do
      week = Tempo.new!(year: 2026, week: 20, calendar: NRF)
      {:ok, shared} = Tempo.intersection(week, ~o"2026-06-16/2026-06-18")

      assert Tempo.equal?(shared, ~o"2026-06-16/2026-06-18")
      assert Tempo.within?(tuesday, week)
    end
  end

  describe "a quarter" do
    test "is the three months its calendar gives it, and is three months long" do
      for calendar <- [Calendar.ISO, NRF], quarter <- 1..4 do
        value = Tempo.new!(year: 2026, quarter: quarter, calendar: calendar)
        {:ok, span} = Tempo.to_interval(value)

        assert {calendar, quarter, Tempo.duration(value)} == {calendar, quarter, ~o"P3M"}
        assert {calendar, quarter, Tempo.duration(span)} == {calendar, quarter, ~o"P3M"}
      end

      first = Tempo.new!(year: 2026, quarter: 1, calendar: NRF)
      measured = NRF.quarter(2026, 1)

      assert gregorian(Enum.at(days_of(first), 0)) == gregorian(measured.first)
      assert Tempo.duration(~o"2026-33/2026-34") == ~o"P6M"
    end
  end

  describe "a calendar that left days out as it changed" do
    # England's September 1752 has the 1st, the 2nd, and the 14th to the 30th.
    test "has the days of a month that its calendar has" do
      september = Tempo.new!(year: 1752, month: 9, calendar: England)
      measured = for day <- 1..30, England.valid_date?(1752, 9, day), do: day

      assert Enum.map(september, &Tempo.day/1) == measured
      assert Enum.count(september) == 19

      assert {:error, %Tempo.InvalidDateError{}} =
               Tempo.new(year: 1752, month: 9, day: 3, calendar: England)
    end

    test "steps from the 2nd to the 14th, and the two meet" do
      second = value(Date.new!(1752, 9, 2, England))
      fourteenth = value(Date.new!(1752, 9, 14, England))

      assert Tempo.shift(second, day: 1) == {:ok, fourteenth}
      assert Tempo.shift(fourteenth, day: -1) == {:ok, second}
      assert Tempo.relation(second, fourteenth) == :meets
      assert Date.diff(gregorian(fourteenth), gregorian(second)) == 1
    end

    # The year 1751 began on 25 March and ended on 31 December: it has the
    # months from March to December.
    test "has the months of a year that its calendar has" do
      year = Tempo.new!(year: 1751, calendar: England)
      measured = Enum.flat_map(England.month_numbers(1751), &Enum.to_list/1)

      assert Enum.map(year, &Tempo.month/1) == measured
    end

    test "recurs by its months, past the days it left out" do
      monthly = Tempo.every!(~o"P1M", from: value(Date.new!(1752, 8, 5, England)), count: 3)

      assert Enum.map(monthly, &date(Interval.from(&1))) ==
               for(step <- 0..2, do: Date.shift(Date.new!(1752, 8, 5, England), month: step))
    end

    test "selects the days it has" do
      {:ok, days} = Tempo.select(Tempo.new!(year: 1752, month: 9, calendar: England), [2, 3, 14])
      assert IntervalSet.map(days, &Tempo.day/1) == [2, 14]
    end

    test "is written and read as itself" do
      text = "1752Y9M14D[u-ca=reform-england]"
      assert Tempo.to_iso8601(Tempo.from_iso8601!(text)) == {:ok, text}
    end
  end

  describe "a calendar whose year begins in the middle of a month" do
    # The Julian year from Lady Day: 1750 begins on 25 March, so its first
    # month is the seven days to the end of March, and it has a thirteenth,
    # the 1st to the 24th of the next March.
    test "has the months and the days its calendar numbers" do
      year = Tempo.new!(year: 1750, calendar: March25)

      assert Enum.map(year, &Tempo.month/1) ==
               Enum.flat_map(March25.month_numbers(1750), &Enum.to_list/1)

      for month <- [1, 2, 13] do
        assert {month,
                Enum.map(Tempo.new!(year: 1750, month: month, calendar: March25), &Tempo.day/1)} ==
                 {month, Enum.flat_map(March25.day_numbers(1750, month), &Enum.to_list/1)}
      end
    end

    test "begins and ends on the days its calendar says" do
      year = March25.year(1750)
      days = days_of(Tempo.new!(year: 1750, calendar: March25))

      assert gregorian(Enum.at(days, 0)) == gregorian(year.first)
      assert gregorian(Enum.at(days, -1)) == gregorian(year.last)
      assert Enum.count(days) == March25.days_in_year(1750)
    end

    test "steps from its last day to the first of the next year" do
      last = value(March25.year(1750).last)
      first_of_next = value(March25.year(1751).first)

      assert Tempo.shift(last, day: 1) == {:ok, first_of_next}
      assert Tempo.relation(last, first_of_next) == :meets
    end

    test "recurs by its years" do
      first = value(March25.year(1750).first)
      yearly = Tempo.every!(~o"P1Y", from: first, count: 3)

      assert Enum.map(yearly, &gregorian(Interval.from(&1))) ==
               for(year <- 1750..1752, do: gregorian(March25.year(year).first))
    end
  end
end
