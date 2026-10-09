defmodule Tempo.Iso8601.FractionOfAUnitTest do
  @moduledoc """
  A fraction of a unit (ISO 8601-2 §7.12) is so much of the unit elapsed:
  `30.5D` is noon on the 30th, and `1985.5Y` half way through 1985.

  A fraction of a month's last day was refused, the number with its fraction
  being held to the month's days (`1985Y6M30.5D`, "30.5 is not valid"), and
  so was a fraction of a month that lands on its last day. A fraction below
  zero was read as a set of the minus sign's character and the number
  (`-0.5Y` was `{45, 0.5}Y`), or as a time counted from the end with its
  fraction (`T10H-30.5M` was 10:30:30).

  The measure is `NaiveDateTime`: the start of the unit and so many seconds
  on.
  """
  use ExUnit.Case, async: true

  alias Calendrical.Hebrew
  alias Tempo.InvalidDateError
  alias Tempo.ParseError

  defp read(text), do: Tempo.from_iso8601(text)

  # The value a moment is, written to the hour or to the minute.
  defp at(%NaiveDateTime{} = moment, resolution),
    do: {:ok, Tempo.from_elixir(moment, resolution: resolution)}

  defp seconds_of(days), do: round(days * 86_400)

  describe "a fraction of a day of a month" do
    test "is so much of that day, the month's last among them" do
      for {year, month} <- [{1985, 1}, {1985, 2}, {1984, 2}, {1985, 6}, {1985, 12}],
          day <- [1, 15, Date.days_in_month(Date.new!(year, month, 1))],
          {fraction, hour} <- [{"5", 12}, {"25", 6}, {"75", 18}] do
        text = "#{year}Y#{month}M#{day}.#{fraction}D"

        assert {text, read(text)} ==
                 {text, at(NaiveDateTime.new!(year, month, day, hour, 0, 0), :hour)}
      end
    end

    test "is refused past the month's last day, and of a day there is none of" do
      assert {:error, %InvalidDateError{}} = read("1985Y6M31.5D")
      assert {:error, %InvalidDateError{}} = read("1985Y2M29.5D")
      assert {:error, %InvalidDateError{}} = read("1985Y6M0.5D")
      assert {:error, %InvalidDateError{}} = read("0.0D")
    end

    test "is read in another calendar by the days its month has" do
      assert Hebrew.days_in_month(5787, 1) == 30

      assert read("5787Y1M30.5D[u-ca=hebrew]") == read("5787Y1M30DT12H[u-ca=hebrew]")
      assert {:error, %InvalidDateError{}} = read("5787Y1M31.5D[u-ca=hebrew]")
    end
  end

  describe "a fraction of a month" do
    test "is so much of the month, to its last day" do
      for {year, month, fraction} <- [
            {1985, 12, 0.5},
            {1985, 12, 0.99},
            {1985, 1, 0.99},
            {1985, 2, 0.5},
            {1984, 2, 0.75}
          ] do
        days = Date.days_in_month(Date.new!(year, month, 1))

        moment =
          NaiveDateTime.add(
            NaiveDateTime.new!(year, month, 1, 0, 0, 0),
            seconds_of(days * fraction)
          )

        text = "#{year}Y#{month + fraction}M"

        # A fraction that lands on a whole day is that day, on a whole hour
        # the hour, and otherwise the minute it falls in.
        resolution =
          cond do
            moment.hour == 0 and moment.minute == 0 -> :day
            moment.minute == 0 -> :hour
            true -> :minute
          end

        assert {text, read(text)} == {text, at(moment, resolution)}
      end
    end
  end

  describe "a fraction of a year before 0" do
    test "is so much of that year, as of a later one" do
      for year <- [-1985, -1984, -44, -1] do
        days = if Date.leap_year?(Date.new!(year, 1, 1)), do: 366, else: 365
        moment = NaiveDateTime.add(NaiveDateTime.new!(year, 1, 1, 0, 0, 0), seconds_of(days / 2))
        resolution = if moment.hour == 0, do: :day, else: :hour

        assert {year, read("#{year}.5Y")} == {year, at(moment, resolution)}
      end
    end

    test "of no fraction is the year, and of the year 0 with a sign the year 0" do
      assert read("-1985.0Y") == read("-1985Y")
      assert read("-0.5Y") == read("0.5Y")
    end
  end

  describe "a fraction of a unit counted from the end" do
    test "is refused by name, where its sign was read as a number" do
      for {text, unit} <- [
            {"-5.5D", "a day"},
            {"1985Y-6.5M", "a month"},
            {"1985Y6M-5.5D", "a day"},
            {"T-10.5H", "an hour"},
            {"T10H-30.5M", "a minute"},
            {"1985Y6M15DT-10.5H", "an hour"},
            {"1985Y-1.5W", "a week"}
          ] do
        assert {^text, {:error, %ParseError{} = error}} = {text, read(text)}

        assert Exception.message(error) =~
                 "A fraction of #{unit} counted from the end is not read"
      end
    end
  end

  describe "a fraction of nothing" do
    test "is the unit, an hour and a minute at 0 among them" do
      assert read("T0.0H") == read("T0H")
      assert read("T10H0.0M") == read("T10H0M")
      assert read("T0.5H") == read("T0H30M")
      assert read("T10H0.5M") == read("T10H0M30S")
      assert read("1985Y6M30.0D") == read("1985Y6M30D")
    end
  end
end
