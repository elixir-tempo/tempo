defmodule Tempo.Iso8601.WrittenFormsOfAValueTest do
  @moduledoc """
  A value is one its unit takes, however it is written.

  A value written as a whole number is asked of its unit: `T25H` is no hour
  and `2026Y13M` no month. One written with a margin of error (`±`), with
  significant digits (`S`) or with a fraction was not, so `T99S2H`,
  `2026Y40±1M` and `T25.5H` were read, and a fraction of a week, of a day of
  the week, or of a month or a day of the year with no year was left in the
  value as a number with a fraction, which nothing reads.

  The measure is the values each unit takes, written here apart from the
  library: the hours of a day, the days of June, the weeks of 2026 as
  Erlang's `:calendar` numbers them.
  """
  use ExUnit.Case, async: true

  alias Tempo.InvalidDateError
  alias Tempo.ParseError

  ## The measure

  {_year, weeks_in_2026} = :calendar.iso_week_number({2026, 12, 31})

  # What is written before a value and after it, and the values its unit
  # takes there.
  @units [
    {"month of a year", "2026Y", "M", 1..12},
    {"month alone", "", "M", 1..12},
    {"week of a year", "2026Y", "W", 1..weeks_in_2026},
    {"day of June", "2026Y6M", "D", 1..Date.days_in_month(~D[2026-06-01])},
    {"day of a June", "6M", "D", 1..30},
    {"day of the year", "2026Y", "O", 1..365},
    {"day of the week", "", "K", 1..7},
    {"day of a week", "2026Y25W", "K", 1..7},
    {"hour", "T", "H", 0..23},
    {"hour of a day", "2026Y6M15DT", "H", 0..23},
    {"minute", "T10H", "M", 0..59},
    {"minute alone", "T", "M", 0..59},
    {"second", "T10H30M", "S", 0..59}
  ]

  defp read?(text), do: match?({:ok, _value}, Tempo.from_iso8601(text))

  # The values about the ends of a range, on both sides of each.
  defp about(first..last//_), do: [first, first + 1, last - 1, last, last + 1, last + 5, 99]

  describe "a value written with a margin of error or with significant digits" do
    test "is read where the value alone is one its unit takes, and refused where it is not" do
      for {named, before, letter, taken} <- @units,
          value <- about(taken),
          written <- ["±1", "S1"] do
        text = "#{before}#{value}#{written}#{letter}"
        assert {named, text, read?(text)} == {named, text, value in taken}
      end
    end

    test "is refused as the value alone is, with what that says" do
      assert {:error, %InvalidDateError{} = alone} = Tempo.from_iso8601("T25H")
      assert {:error, %InvalidDateError{} = with_margin} = Tempo.from_iso8601("T25±1H")
      assert {:error, %InvalidDateError{} = with_digits} = Tempo.from_iso8601("T25S1H")

      assert Exception.message(with_margin) == Exception.message(alone)
      assert Exception.message(with_digits) == Exception.message(alone)
    end

    test "keeps what it is written with where it is read" do
      assert {:ok, %Tempo{time: [hour: {12, [margin_of_error: 1]}]}} =
               Tempo.from_iso8601("T12±1H")

      assert {:ok, %Tempo{time: [year: 2026, month: 6, day: {15, [margin_of_error: 2]}]}} =
               Tempo.from_iso8601("2026Y6M15±2D")

      assert {:ok, %Tempo{time: [year: {1950, [significant_digits: 2]}]}} =
               Tempo.from_iso8601("1950S2")

      # A year has no last value, with or without them.
      assert read?("123456789S3Y")
      assert read?("-13.787E9S4±20E6Y")
    end
  end

  describe "an hour and a minute written with a fraction" do
    test "are read where the whole hour or minute is one, and refused where it is not" do
      for {before, letter, taken} <- [{"T", "H", 0..23}, {"T10H", "M", 0..59}, {"T", "M", 0..59}],
          value <- about(taken) do
        text = "#{before}#{value}.5#{letter}"
        assert {text, read?(text)} == {text, value in taken}
      end
    end

    test "are the minutes of the hour and the seconds of the minute they are a part of" do
      assert {:ok, %Tempo{time: [hour: 10, minute: 30]}} = Tempo.from_iso8601("T10.5H")
      assert {:ok, %Tempo{time: [hour: 23, minute: 45]}} = Tempo.from_iso8601("T23.75H")

      assert {:ok, %Tempo{time: [hour: 10, minute: 30, second: 30]}} =
               Tempo.from_iso8601("T10H30.5M")

      assert {:ok, %Tempo{time: [minute: 59, second: 30]}} = Tempo.from_iso8601("T59.5M")
    end
  end

  describe "a fraction of a unit it is not read of" do
    test "is refused, where it was left in the value" do
      for text <- [
            "30.5W",
            "2026Y30.5W",
            "3.5K",
            "2026Y25W3.5K",
            "166.5O",
            "6.5M",
            "13.5M"
          ] do
        assert {^text, {:error, %ParseError{}}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "is read of a year, of a month of a year and of a day, as it was" do
      # Half of June's thirty days is fifteen days elapsed, the 16th.
      assert {:ok, %Tempo{time: [year: 2026, month: 6, day: 16]}} =
               Tempo.from_iso8601("2026Y6.5M")

      assert {:ok, %Tempo{time: [year: 2026, month: 6, day: 15, hour: 12]}} =
               Tempo.from_iso8601("2026Y6M15.5D")

      assert {:ok, %Tempo{time: [year: 2026, month: 6, day: 15, hour: 12]}} =
               Tempo.from_iso8601("2026Y166.5O")

      assert {:ok, %Tempo{time: [day: 15, hour: 12]}} = Tempo.from_iso8601("15.5D")
    end

    test "holds no number with a fraction in any value that is read" do
      for {_named, before, letter, taken} <- @units,
          value <- about(taken),
          text = "#{before}#{value}.5#{letter}",
          {:ok, %Tempo{time: time}} <- [Tempo.from_iso8601(text)] do
        assert {text, Enum.filter(time, fn {_unit, held} -> is_float(held) end)} == {text, []}
      end
    end
  end
end
