defmodule Tempo.DayOfDivisionTest do
  @moduledoc """
  A day written after a division of a year.

  ISO 8601-2 numbers a year's divisions as months: a season is month 21 to
  32, a quarter 33 to 36, a quadrimester 37 to 39 and a semester 40 or 41.
  A day after one is a day of the division, Tempo's own form, as a day
  after a group is (`2026Y2G3MU45D`). The reader held a day after any
  month to thirty-one, so the forty-fifth day of the second quarter
  (`2026Y34M45D`) was refused as no day.

  A season of 21 to 24 is no such division: it is "independent of
  location", and has no dates to count a day in until it is given a
  hemisphere. A day after one is refused.

  The measure is Elixir's own `Date`: the day so many on from the
  division's first.
  """
  use ExUnit.Case, async: true

  alias Tempo.InvalidDateError

  # Each division of 2026 by its number, with its first day and the first
  # day after it.
  @divisions %{
    33 => {~D[2026-01-01], ~D[2026-04-01]},
    34 => {~D[2026-04-01], ~D[2026-07-01]},
    35 => {~D[2026-07-01], ~D[2026-10-01]},
    36 => {~D[2026-10-01], ~D[2027-01-01]},
    37 => {~D[2026-01-01], ~D[2026-05-01]},
    38 => {~D[2026-05-01], ~D[2026-09-01]},
    39 => {~D[2026-09-01], ~D[2027-01-01]},
    40 => {~D[2026-01-01], ~D[2026-07-01]},
    41 => {~D[2026-07-01], ~D[2027-01-01]}
  }

  describe "a day after a division of a year" do
    test "is that day of the division, to its last" do
      for {code, {first, next}} <- @divisions, day <- 1..Date.diff(next, first) do
        date = Date.add(first, day - 1)

        assert {code, day, Tempo.from_iso8601("2026Y#{code}M#{day}D")} ==
                 {code, day, {:ok, Tempo.from_date(date)}}
      end

      # The forty-fifth day of the second quarter is 15 May.
      assert Tempo.from_iso8601("2026Y34M45D") == {:ok, Tempo.from_date(~D[2026-05-15])}
      assert Tempo.from_iso8601("2026-34-45") == {:ok, Tempo.from_date(~D[2026-05-15])}
    end

    test "is no day past the division's last" do
      for {code, {first, next}} <- @divisions do
        past = Date.diff(next, first) + 1

        assert {^code, {:error, %InvalidDateError{}}} =
                 {code, Tempo.from_iso8601("2026Y#{code}M#{past}D")}
      end
    end

    test "is refused after a season of 21 to 24, which has no dates until it has a hemisphere" do
      for code <- 21..24, day <- [1, 15, 92] do
        assert {^code, ^day, {:error, %Tempo.ParseError{}}} =
                 {code, day, Tempo.from_iso8601("2026Y#{code}M#{day}D")}
      end
    end

    test "is the day after the group the division is" do
      for quarter <- 1..4, day <- [1, 31, 32, 45, 90] do
        assert {quarter, day, Tempo.from_iso8601("2026Y#{32 + quarter}M#{day}D")} ==
                 {quarter, day, Tempo.from_iso8601("2026Y#{quarter}G3MU#{day}D")}
      end
    end

    test "takes a time of day, and is counted in the value's calendar" do
      assert Tempo.from_iso8601("2026Y34M45DT10H") ==
               {:ok, Tempo.from_iso8601!("2026-05-15T10")}

      # The second quarter of a Hebrew year starts with its fourth month.
      assert {:ok, %Tempo{time: [year: 5786, month: month, day: _day]}} =
               Tempo.from_iso8601("5786Y34M45D[u-ca=hebrew]")

      assert month in 4..6
    end
  end

  describe "a day after a month" do
    test "is still held to thirty-one where it is read" do
      for text <- ["2026Y6M45D", "2026Y13M45D", "2026Y6M32D", "6M32D"] do
        assert {^text, {:error, %Tempo.ParseError{}}} = {text, Tempo.from_iso8601(text)}
      end
    end
  end
end
