defmodule Tempo.WeekCalendarTest do
  use ExUnit.Case, async: true

  # A week-based calendar (the ISO week calendar, the NRF retail calendar, a
  # retail calendar built with `Calendrical.new/3`) numbers its weeks within
  # its year. Its dates take ISO 8601's week date shape, `[year, week,
  # day_of_week]`, however they are made, and are written as ISO 8601-2
  # §7.2.4's explicit week date, `2026Y25W2K`.

  import Tempo.Sigils

  alias Calendrical.ISOWeek
  alias Calendrical.NRF
  alias Tempo.IntervalSet

  defp read_back(value), do: value |> Tempo.to_iso8601!() |> Tempo.from_iso8601!()

  describe "one shape, however the value is made" do
    test "parsed, built from an Elixir date, converted and shifted into a zone" do
      tuesday = ~o"2026-W25-2"W

      {:ok, zoned} =
        Tempo.shift_zone(
          Tempo.from_iso8601!("2026-W25-2T10:30[Europe/Paris][u-ca=iso-week]"),
          "Etc/UTC"
        )

      assert tuesday.time == [year: 2026, week: 25, day_of_week: 2]
      assert Tempo.from_elixir(Date.new!(2026, 25, 2, ISOWeek)) == tuesday
      assert Tempo.to_calendar!(~o"2026-06-16", ISOWeek) == tuesday

      assert Keyword.take(zoned.time, [:week, :day_of_week, :hour]) == [
               week: 25,
               day_of_week: 2,
               hour: 8
             ]

      naive = Tempo.from_elixir(NaiveDateTime.new!(2026, 25, 2, 10, 30, 0, {0, 0}, ISOWeek))
      assert naive.time == [year: 2026, week: 25, day_of_week: 2, hour: 10, minute: 30, second: 0]
    end

    test "the NRF retail calendar's weeks" do
      parsed = Tempo.from_iso8601!("2026-W20-3[u-ca=nrf]")

      assert parsed.time == [year: 2026, week: 20, day_of_week: 3]
      built = Tempo.from_elixir(Date.new!(2026, 20, 3, NRF))
      assert {built.calendar, built.time} == {NRF, parsed.time}
    end
  end

  describe "the ISO 8601 form reads back as the value" do
    test "a week date is written with ISO 8601-2's day of the week" do
      assert Tempo.to_iso8601!(~o"2026-W25-2"W) == "2026Y25W2K[u-ca=iso-week]"
      assert inspect(~o"2026-W25-2"W) == ~s|~o"2026Y25W2K"W|
      back = read_back(~o"2026-W25-2"W)
      assert {back.calendar, back.time} == {ISOWeek, [year: 2026, week: 25, day_of_week: 2]}
    end

    test "a week, a date and time, a zoned value and an NRF quarter" do
      week = Tempo.from_iso8601!("2026-W25[u-ca=iso-week]")
      datetime = Tempo.from_iso8601!("2026-W25-2T10:30:00[u-ca=iso-week]")
      zoned = Tempo.from_iso8601!("2026-W25-2T10:30:00[Europe/Paris][u-ca=iso-week]")
      {:ok, quarter} = Tempo.from_elixir(NRF.quarter(2026, 1))

      for value <- [week, datetime, zoned] do
        back = read_back(value)
        assert {back.calendar, back.time} == {ISOWeek, value.time}
      end

      assert Tempo.to_iso8601!(quarter) == "2026Y1W1K/14W1K[u-ca=nrf]"
      assert Tempo.equal?(read_back(quarter), quarter)
    end

    test "a week-based calendar ISO 8601 cannot name is an error, and inspect names it" do
      {:ok, retail} =
        Calendrical.new(Tempo.WeekCalendarTest.Retail, :week, weeks_in_month: [4, 4, 5])

      week = Tempo.from_iso8601!("2026Y20W3K", retail)

      assert {:error, %Tempo.Iso8601EncodeError{construct: :calendar}} = Tempo.to_iso8601(week)

      {evaluated, _binding} = Code.eval_string(inspect(week))
      assert evaluated == week
    end
  end

  describe "operations on a week date" do
    test "it names the same day as the Gregorian date and meets it in set operations" do
      assert Tempo.equal?(~o"2026-W25-2"W, ~o"2026-06-16")
      assert Tempo.relation(~o"2026-W25-2"W, ~o"2026-06-16") == :equals

      assert Tempo.equal?(
               Tempo.from_iso8601!("2026-W20-3[u-ca=nrf]"),
               Tempo.from_elixir(Date.new!(2026, 20, 3, NRF))
             )

      assert {:ok, overlap} = Tempo.intersection(~o"2026-W25"W, ~o"2026-06-16/2026-06-18")
      assert IntervalSet.count(overlap) == 1
    end

    test "days and weeks step on the week axis, and a month is an error" do
      assert Tempo.shift(~o"2026-W25-7"W, ~o"P1D") == ~o"2026-W26-1"W
      assert Tempo.shift(~o"2026-W25-2"W, ~o"P1W") == ~o"2026-W26-2"W

      assert {:error, %Tempo.ResolutionError{target: :month}} =
               Tempo.shift(~o"2026-W25-2"W, ~o"P1M")
    end

    test "its day of the week and year, its rounding, and its date and time" do
      tuesday = ~o"2026-W25-2"W
      datetime = Tempo.from_iso8601!("2026-W25-2T10:30:00[u-ca=iso-week]")

      assert {Tempo.day_of_week(tuesday), Tempo.day_of_year(tuesday)} == {2, 170}
      assert Tempo.round(tuesday, :week) == ~o"2026-W25"W
      assert Tempo.round(~o"2026-W25-5"W, :week) == ~o"2026-W26"W
      assert Tempo.split(datetime) == {tuesday, ~o"T10:30:00"W}

      assert Tempo.to_naive_datetime(datetime) ==
               NaiveDateTime.new(2026, 25, 2, 10, 30, 0, 0, ISOWeek)
    end
  end

  describe "to_string/2" do
    test "a week date is the day it names" do
      assert Tempo.to_string(Tempo.new!(year: 2026, week: 25, day_of_week: 2)) ==
               {:ok, "Jun 16, 2026"}

      assert Tempo.to_string(
               Tempo.new!(year: 2026, week: 25, day_of_week: 2, hour: 10, minute: 30)
             ) ==
               {:ok, "Jun 16, 2026, 10:30 AM"}
    end

    test "a week is its first and last day, across a month or a year" do
      assert Tempo.to_string(~o"2026-W25") == {:ok, "Jun 15 – 21, 2026"}
      assert Tempo.to_string(~o"2026-W27") == {:ok, "Jun 29 – Jul 5, 2026"}
      assert Tempo.to_string(~o"2026-W53") == {:ok, "Dec 28, 2026 – Jan 3, 2027"}
    end

    test "a range of weeks runs to the last day of its last week" do
      assert Tempo.to_string(Tempo.from_iso8601!("2026-W25/2026-W27")) ==
               {:ok, "Jun 15 – 28, 2026"}
    end

    test "a week-based calendar's date is handed to Localize in its own calendar" do
      {:ok, localized} = Localize.Date.to_string(Date.new!(2026, 25, 2, ISOWeek))

      assert Tempo.to_string(~o"2026-W25-2"W) == {:ok, localized}
    end

    test "a week-based calendar's day is written as its calendar writes it" do
      assert Tempo.to_string(~o"2026-W25-2"W) == {:ok, "2026-W25-2"}
      assert Tempo.to_string(~o"2026-W25-2"W, format: :full, locale: :de) == {:ok, "2026-W25-2"}
    end

    test "a week-based calendar's year is written, alone and across a range" do
      {:ok, localized} = Localize.Date.to_string(%{year: 2026, calendar: ISOWeek}, format: :y)

      assert localized =~ "2026"
      assert Tempo.to_string(~o"2026"W) == {:ok, localized}

      assert {:ok, years} = Tempo.to_string(Tempo.from_iso8601!("2026/2028", ISOWeek))
      assert years =~ "2026"
      assert years =~ "2027"
    end
  end

  describe "a Gregorian ISO week date" do
    test "has its day of the week, splits and rounds" do
      tuesday = Tempo.new!(year: 2026, week: 25, day_of_week: 2)

      assert Tempo.day_of_week(tuesday) == 2
      assert Tempo.round(tuesday, :week) == Tempo.new!(year: 2026, week: 25)

      assert Tempo.split(Tempo.new!(year: 2026, week: 25, day_of_week: 2, hour: 10)) ==
               {tuesday, ~o"T10"}
    end
  end
end
