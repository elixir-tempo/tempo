defmodule Tempo.SpansAtOnceTest do
  @moduledoc """
  The most spans a value is converted to at once.

  `Tempo.to_interval/2` gives the spans of a value that names several: each
  value of its sets, each candidate of its masks, each date of a range. It
  gave them however many there were, so the half a million minutes of
  `2026Y{1..12}M{1..28}DT{0..23}H{0..59}M` took ten seconds, and the three
  million days of `{1..9999}Y{1..12}M{1..28}D` did not come to an end. A
  value that names more than 10,000 is refused (decided 2026-10-08), as a
  recurrence that has more than 10,000 occurrences is: at once, with a
  `Tempo.ConversionError` whose reason is `:too_many_values`.

  The measure is the number of values a value names, counted apart from the
  library: the product of the sizes of its sets, and the days `Date.range/2`
  has between two dates.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.IntervalSet

  @most 10_000

  ## The measure

  # What is to be said of a value that names `count` values.
  defp to_say(count) when count > @most, do: :refused
  defp to_say(count), do: {:spans, count}

  defp said({:ok, %IntervalSet{} = set}), do: {:spans, IntervalSet.count(set)}
  defp said({:error, %ConversionError{reason: :too_many_values}}), do: :refused

  defp converted(text), do: text |> Tempo.from_iso8601!() |> Tempo.to_interval()

  defp held_to(cases) do
    for {text, count} <- cases do
      assert {text, said(converted(text))} == {text, to_say(count)}
    end
  end

  describe "a value that holds sets" do
    # A value as it is written, and the number of values it names.
    @sets [
      {"2026Y{1..12}M{1..28}DT{0..23}H", 12 * 28 * 24},
      {"2026Y{1..12}M{1..28}DT{0..23}H{0,30}M", 12 * 28 * 24 * 2},
      {"2026Y{1..12}M{1..28}DT{0..23}H{0..59}M", 12 * 28 * 24 * 60},
      {"{1..9999}Y{1..12}M{1..28}D", 9_999 * 12 * 28},
      {"{2000..2999}Y{1..12}M", 1_000 * 12},
      {"{1..9999}Y{1,7}M", 9_999 * 2},
      {"{2001..2010}Y{1..10}M{1..10}DT{0..9}H", 10 * 10 * 10 * 10},
      {"{2001..2010}Y{1..10}M{1..10}DT{0..9}H{0,30}M", 10 * 10 * 10 * 10 * 2},
      {"{1..10000}Y", 10_000},
      {"{1..10001}Y", 10_001},
      {"{1..99999999}Y", 99_999_999}
    ]

    test "is its spans where it names 10,000 values or fewer, and refused past them" do
      held_to(@sets)
    end

    test "counts the values its units hold, a range counted from an end among them" do
      # The days of thirty-one years, a month's being counted to its last.
      days = Enum.count(Date.range(~D[2000-01-01], ~D[2030-12-31]))
      assert days == 11_323

      held_to([
        {"{2000..2030}Y{1..12}M{1..-1}D", days},
        {"2026Y{1..12}M{1..-1}D", Enum.count(Date.range(~D[2026-01-01], ~D[2026-12-31]))}
      ])
    end
  end

  describe "a value that holds masks" do
    # A mask of four digits of a year stands for the years written to four,
    # 1000 to 9999.
    @masks [
      {"19XX-XX-15", 100 * 12},
      {"1XXX-XX-15", 1_000 * 12},
      {"XXXX-XX-15", 9_000 * 12},
      {"XXXXY6M", 9_000},
      {"XXXX-02-XX", 9_000},
      {"XXXXXY6M", 90_000},
      {"XXXXXXXXXY6M", 900_000_000},
      {"{2000..2099}-XX-1X", 100 * 12},
      {"{2000..2999}-XX-1X", 1_000 * 12}
    ]

    test "is the spans its candidates name where there are 10,000 or fewer, and refused past them" do
      held_to(@masks)
    end

    test "is one span, however many years it stands for, where nothing after it names them apart" do
      assert converted("XXXXXXXXXY") == {:ok, ~o"0Y/1000000000Y"}
      assert converted("XXXX-XX-XX") == {:ok, ~o"0Y/10000Y"}
    end

    test "is not walked through a mask of more than 10,000 years, as through as many significant digits" do
      assert Enum.take(Tempo.from_iso8601!("XXXXY6M"), 2) == [~o"1000Y6M", ~o"1001Y6M"]

      assert_raise ConversionError, ~r/names more than 10000 values/, fn ->
        Enum.take(Tempo.from_iso8601!("XXXXXY6M"), 2)
      end
    end
  end

  describe "a set of values and a range of them" do
    test "are their spans where they name 10,000 or fewer, and refused past them" do
      ten_thousandth = Date.add(~D[2000-01-01], @most - 1)
      next = Date.add(ten_thousandth, 1)

      held_to([
        {"{2000-01-01..#{ten_thousandth}}", @most},
        {"{2000-01-01..#{next}}", @most + 1},
        {"{2000-01-01..2040-12-31}", Enum.count(Date.range(~D[2000-01-01], ~D[2040-12-31]))},
        {"{0001-01-01..9999-12-31}", Enum.count(Date.range(~D[0001-01-01], ~D[9999-12-31]))}
      ])
    end

    test "count the values of each member" do
      of_one = 12 * 28 * 12
      one = "Y{1..12}M{1..28}DT{0..11}H"

      held_to([
        {"{2026#{one},2027#{one}}", 2 * of_one},
        {"{2026#{one},2027#{one},2028#{one}}", 3 * of_one},
        {"{2026Y{1..12}M{1..28}DT{0..23}H{0..59}M}", 12 * 28 * 24 * 60}
      ])
    end
  end

  describe "a value that holds a selection" do
    test "is the spans it selects where there are 10,000 or fewer, and refused past them" do
      weekdays =
        Enum.count(Date.range(~D[2026-01-01], ~D[2026-12-31]), &(Date.day_of_week(&1) in 1..5))

      assert weekdays == 261

      held_to([
        {"2026YL{1..5}KNT{9,14}H", weekdays * 2},
        {"2026YL{1..5}KNT{0..23}H{0..59}M", weekdays * 24 * 60},
        # A period for each month of each year.
        {"{1..9999}Y{1..12}ML1K1IN", 9_999 * 12},
        {"{1..99999999}YL1K1IN", 99_999_999},
        {"XXXXXY6ML1K1IN", 90_000}
      ])
    end
  end

  describe "an interval and a recurrence from each value of a start" do
    test "are the spans from each where there are 10,000 or fewer, and refused past them" do
      held_to([
        {"2026Y{1..12}M{1..-1}D/P1D", 365},
        {"{2000..2030}Y{1..12}M{1..-1}D/P1D", 11_323},
        {"2026Y{1..12}M{1..28}DT{0..23}H{0..59}M/PT1M", 12 * 28 * 24 * 60},
        # Three occurrences, and six, from each of two thousand starts.
        {"R3/{2000..2999}Y{1,7}M1D/P1D", 1_000 * 2 * 3},
        {"R6/{2000..2999}Y{1,7}M1D/P1D", 1_000 * 2 * 6},
        {"R3/{1..9999}Y{1,7}M1D/P1D", 9_999 * 2 * 3}
      ])
    end
  end

  describe "the refusal" do
    test "names the value, the most there are and how its values are taken" do
      many = Tempo.from_iso8601!("{1..10001}Y")

      assert {:error, %ConversionError{value: ^many} = error} = Tempo.to_interval(many)

      assert Exception.message(error) ==
               ~s|~o"{1..10001}Y" names more than 10000 values, and 10000 are the most listed | <>
                 "or converted at once. Convert a narrower value, or take its values one at a " <>
                 "time with `Enum` or `Stream`."

      assert_raise ConversionError, fn -> Tempo.to_interval!(many) end
    end

    test "is what the functions built on the conversion say" do
      many = Tempo.from_iso8601!("2026Y{1..12}M{1..28}DT{0..23}H{0,30}M")
      refused = {:error, ConversionError.exception(value: many, reason: :too_many_values)}

      assert Tempo.duration(many) == refused
      assert Tempo.to_string(many) == refused
      assert Tempo.union(many, ~o"2027") == refused
      assert Tempo.relation(many, ~o"2027") == refused
      assert Tempo.shift(many, ~o"P1D") == refused

      assert_raise ConversionError, fn -> Tempo.overlaps?(many, ~o"2027") end
      assert_raise ConversionError, fn -> Tempo.compare(many, ~o"2027-01-01T00:00") end
    end

    test "leaves a value's values to be taken one at a time" do
      many = Tempo.from_iso8601!("2026Y{1..12}M{1..28}DT{0..23}H{0..59}M")

      assert Enum.take(many, 2) == [~o"2026Y1M1DT0H0M", ~o"2026Y1M1DT0H1M"]
      assert Enum.count(many) == 12 * 28 * 24 * 60
    end
  end

  describe "a step and a selection" do
    test "of a value that names 10,000 values or fewer are as they were" do
      {:ok, %IntervalSet{} = stepped} =
        {:ok, Tempo.shift(Tempo.from_iso8601!("{2000..2099}Y{1..12}M"), ~o"P1M")}

      assert IntervalSet.count(stepped) == 100 * 12
    end

    test "of a value that names more are refused as its conversion is" do
      for text <- ["{2000..2999}Y{1..12}M", "XXXX-XX-15", "XXXXXXY6M"] do
        value = Tempo.from_iso8601!(text)

        assert {text, Tempo.shift(value, ~o"P1M")} ==
                 {text,
                  {:error, ConversionError.exception(value: value, reason: :too_many_values)}}
      end

      assert {:error, %ConversionError{reason: :too_many_values}} =
               Tempo.select(
                 ~o"2026",
                 Tempo.from_iso8601!("{1..12}M{1..28}DT{0..23}H{0..59}M/PT1M")
               )
    end

    test "keep a mask that a step passes by, however many values it stands for" do
      assert Tempo.shift(Tempo.from_iso8601!("XXXX-XX-15"), ~o"PT1H") == ~o"XXXXYXXM15DT1H"
    end
  end

  describe "a group under a set of years" do
    test "is written by its values however many years there are, none of them being listed" do
      assert Tempo.extend(Tempo.from_iso8601!("{1..10999}Y2G3MU")) ==
               {:ok, Tempo.from_iso8601!("{1..10999}Y{4..6}M")}
    end
  end
end
