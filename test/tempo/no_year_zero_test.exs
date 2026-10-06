defmodule Tempo.NoYearZeroTest do
  use ExUnit.Case, async: true

  # The Julian calendar has no year 0: its year before 1 is -1, as
  # Calendrical has it (the day after 31 December of -1 is 1 January of 1,
  # and `Calendrical.Julian.valid_date?(0, 1, 1)` is false). Tempo counted a
  # year on as a number, so in that calendar it read a year 0, stepped onto
  # it, walked through it and ended a span on it.
  #
  # The measure is Elixir's `Date` in `Calendrical.Julian`: `Date.add/2`,
  # `Date.shift/2` and `Date.range/2` are the calendar's own arithmetic. The
  # Gregorian calendar has a year 0, and is held beside it.

  import Tempo.Sigils

  alias Tempo.ChangeOfTheClock
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError
  alias Tempo.RRule

  @julian Calendrical.Julian

  # Dates either side of the year the calendar lacks: the last days of -1,
  # the first of 1, a leap day and the ends of months of 31 days.
  @dates [
    Date.new!(-2, 12, 30, Calendrical.Julian),
    Date.new!(-1, 1, 31, Calendrical.Julian),
    Date.new!(-1, 2, 29, Calendrical.Julian),
    Date.new!(-1, 12, 31, Calendrical.Julian),
    Date.new!(1, 1, 1, Calendrical.Julian),
    Date.new!(1, 3, 31, Calendrical.Julian),
    Date.new!(2, 6, 15, Calendrical.Julian)
  ]

  defp julian(text), do: Tempo.from_iso8601!(text, @julian)

  defp shifted(%Date{} = date, unit, count) do
    {:ok, shifted} =
      date
      |> Tempo.from_date()
      |> Tempo.shift(%Tempo.Duration{time: [{unit, count}]})
      |> Tempo.to_date()

    shifted
  end

  defp years(values), do: Enum.map(values, &Tempo.year/1)

  describe "a year the calendar does not have" do
    test "is not read" do
      for text <- ["0000Y", "0000-06-15", "0000-06", "0000-W10-1", "{0000,0001}Y"] do
        assert {text, Tempo.from_iso8601(text, @julian)} ==
                 {text,
                  {:error,
                   %InvalidDateError{
                     unit: :year,
                     value: 0,
                     calendar: @julian,
                     reason:
                       "0 is not a year in Calendrical.Julian: the year before its year 1 is -1."
                   }}}
      end
    end

    test "is a year of the Gregorian calendar" do
      assert {:ok, year_zero} = Tempo.from_iso8601("0000Y")
      assert Tempo.shift(~o"0001-01-15", ~o"P-1Y") == ~o"0000-01-15"

      {:ok, span} = Tempo.to_interval(year_zero)
      assert {Interval.from(span), Interval.to(span)} == {~o"0000Y", ~o"0001Y"}

      assert years(Interval.new!(from: ~o"-0001Y", to: ~o"0002Y")) == [-1, 0, 1]
    end
  end

  describe "a step in a calendar with no year 0" do
    test "of days, months and years is the calendar's" do
      for date <- @dates do
        for count <- -800..800//37 do
          assert {date, :day, count, shifted(date, :day, count)} ==
                   {date, :day, count, Date.add(date, count)}
        end

        for count <- -30..30 do
          assert {date, :month, count, shifted(date, :month, count)} ==
                   {date, :month, count, Date.shift(date, month: count)}
        end

        for count <- -5..5 do
          assert {date, :year, count, shifted(date, :year, count)} ==
                   {date, :year, count, Date.shift(date, year: count)}
        end
      end
    end

    test "of a year or a month alone passes over the year" do
      assert Tempo.shift(julian("-0001Y"), ~o"P1Y") == julian("0001Y")
      assert Tempo.shift(julian("0001Y"), ~o"P-1Y") == julian("-0001Y")
      assert Tempo.shift(julian("-0005Y"), ~o"P10Y") == julian("0006Y")

      assert Tempo.shift(julian("-0001Y12M"), ~o"P1M") == julian("0001Y1M")
      assert Tempo.shift(julian("0001Y1M"), ~o"P-1M") == julian("-0001Y12M")
      assert Tempo.shift(julian("-0001Y6M"), ~o"P24M") == julian("0002Y6M")

      assert Tempo.round(julian("-0001Y8M"), :year) == julian("0001Y")
    end
  end

  describe "a span in a calendar with no year 0" do
    test "ends where the next value starts" do
      for {text, next} <- [
            {"-0001Y", "0001Y"},
            {"-0001Y12M", "0001Y1M"},
            {"-0001-12-31", "0001-01-01"},
            {"-0001-12-31T23", "0001-01-01T00"}
          ] do
        {:ok, span} = Tempo.to_interval(julian(text))

        assert {text, Interval.to(span)} == {text, julian(next)}
        assert {text, Tempo.relation(julian(text), julian(next))} == {text, :meets}
      end
    end
  end

  describe "a walk in a calendar with no year 0" do
    test "of years, months and days passes over the year" do
      years = Interval.new!(from: julian("-0003Y"), to: julian("0003Y"))
      assert years(years) == [-3, -2, -1, 1, 2]

      months = Interval.new!(from: julian("-0001Y11M"), to: julian("0001Y3M"))

      assert Enum.to_list(months) ==
               Enum.map(["-0001Y11M", "-0001Y12M", "0001Y1M", "0001Y2M"], &julian/1)

      first = Date.new!(-1, 12, 25, @julian)
      last = Date.new!(1, 1, 6, @julian)
      days = Interval.new!(from: Tempo.from_date(first), to: Tempo.from_date(Date.add(last, 1)))

      assert Enum.map(days, fn day ->
               {:ok, date} = Tempo.to_date(day)
               date
             end) == Enum.to_list(Date.range(first, last))

      # What `Enum` answers without a walk is the walk's.
      for span <- [years, months, days] do
        assert ChangeOfTheClock.walk_against_enum(span) == []
      end
    end

    test "of a yearly recurrence passes over the year" do
      {:ok, rule} = RRule.parse("FREQ=YEARLY;COUNT=4", from: julian("-0002-03-15"))
      {:ok, set} = Tempo.to_interval(rule)

      assert Enum.map(IntervalSet.members(set), &Interval.from/1) ==
               Enum.map(["-0002-03-15", "-0001-03-15", "0001-03-15", "0002-03-15"], &julian/1)
    end
  end

  describe "the years a set, a range, a mask, a decade and a century name" do
    test "are those the calendar has" do
      {:ok, either_side} = Tempo.to_interval(julian("{-0001..0001}Y"))

      assert Enum.map(IntervalSet.members(either_side), &Interval.from/1) ==
               [julian("-0001Y"), julian("0001Y")]

      for {text, first, last, ends} <- [
            {"000X", 1, 9, "0010Y"},
            {"-000X", -9, -1, "0001Y"},
            {"000J", 1, 9, "0010Y"},
            {"00C", 1, 99, "0100Y"},
            {"-00C", -99, -1, "0001Y"}
          ] do
        value = julian(text)
        walked = years(value)
        {:ok, span} = Tempo.to_interval(value)

        assert {text, List.first(walked), List.last(walked)} == {text, first, last}
        assert {text, Enum.count(value)} == {text, last - first + 1}
        assert {text, Interval.from(span)} == {text, julian("#{first}Y")}
        assert {text, Interval.to(span)} == {text, julian(ends)}
      end
    end

    test "hold a year 0 in the Gregorian calendar" do
      assert years(~o"000X") == Enum.to_list(0..9)
      assert years(~o"-000X") == Enum.to_list(-9..0)
      assert Tempo.to_interval(~o"00C") == Tempo.to_interval(~o"0000Y/0100Y")
    end
  end
end
