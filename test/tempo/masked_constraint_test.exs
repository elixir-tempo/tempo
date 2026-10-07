defmodule Tempo.MaskedConstraintTest do
  @moduledoc """
  A mask in a constraint given to `Tempo.select/2`.

  A constraint is the selection of the same parts, and one implementation
  resolves both. A constraint with a mask was the exception: it was placed
  on its period and read there as the value it made, so `~o"1XD"` from June
  was the one span from the 10th to the 20th, where the selection
  `~o"L1XDN"` is its ten days. A mask in a constraint is each value its
  digits match too (decided 2026-10-08).

  The measure is the digits themselves: a value is one the mask matches
  where its number, written to the mask's width, has the mask's digits, and
  the values a unit has are Elixir's `Date` and the clock's.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Julian.March25
  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet

  ## The measure

  # Whether a number, written to a mask's width, has the mask's digits.
  defp matches?(number, mask) do
    written = number |> Integer.to_string() |> String.pad_leading(String.length(mask), "0")

    String.length(written) == String.length(mask) and
      Enum.all?(Enum.zip(String.graphemes(written), String.graphemes(mask)), fn
        {_digit, "X"} -> true
        {digit, digit} -> true
        {_digit, _another} -> false
      end)
  end

  defp seconds(%Date{} = date), do: seconds(NaiveDateTime.new!(date, ~T[00:00:00]))

  defp seconds(%NaiveDateTime{} = moment),
    do: moment |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp day(%Date{} = date), do: {seconds(date), seconds(Date.add(date, 1))}

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  defp spans({:ok, %IntervalSet{} = set}), do: Enum.map(IntervalSet.members(set), &bounds/1)

  defp read(text), do: Tempo.from_iso8601!(text)

  @day_masks ["1X", "X5", "3X", "XX", "0X", "2X", "X0"]

  describe "a day of a month, masked" do
    test "is each day of the month its digits match" do
      for {year, month} <- [{2026, 6}, {2026, 2}, {2024, 2}, {2026, 12}], mask <- @day_masks do
        first = Date.new!(year, month, 1)
        month_text = Calendar.strftime(first, "%Y-%m")

        expected =
          for number <- 1..Date.days_in_month(first), matches?(number, mask) do
            day(Date.new!(year, month, number))
          end

        assert {month_text, mask, spans(Tempo.select(read(month_text), read("#{mask}D")))} ==
                 {month_text, mask, expected}
      end
    end

    test "is ten days where it is the tens of June, each the day's own value" do
      {:ok, tens} = Tempo.select(~o"2026-06", ~o"1XD")

      assert IntervalSet.count(tens) == 10
      assert Enum.count(tens) == 10 * 24

      {:ok, tenth} = Tempo.to_interval(~o"2026-06-10")
      assert List.first(IntervalSet.members(tens)) == tenth
    end

    test "is what the selection of the same mask selects" do
      for mask <- @day_masks do
        assert {mask, Tempo.select(~o"2026-06", read("#{mask}D"))} ==
                 {mask, Tempo.select(~o"2026-06", read("L#{mask}DN"))}
      end

      assert Tempo.select(~o"2026", ~o"6M1XD") == Tempo.select(~o"2026", ~o"L6M1XDN")
      assert Tempo.select(~o"2026-06", ~o"-XD") == Tempo.select(~o"2026-06", ~o"L-XDN")
    end

    test "counted from the end is the last days of the month" do
      last_nine = for number <- 22..30, do: day(Date.new!(2026, 6, number))

      assert spans(Tempo.select(~o"2026-06", ~o"-XD")) == last_nine
    end
  end

  describe "a month, an hour and a minute, masked" do
    test "are each value their digits match" do
      for mask <- ["1X", "X2", "0X", "XX"] do
        expected =
          for number <- 1..12, matches?(number, mask) do
            first = Date.new!(2026, number, 1)
            {seconds(first), seconds(Date.shift(first, month: 1))}
          end

        assert {mask, spans(Tempo.select(~o"2026", read("#{mask}M")))} == {mask, expected}
      end

      for mask <- ["1X", "X0", "2X", "0X"] do
        expected =
          for number <- 0..23, matches?(number, mask) do
            from = NaiveDateTime.new!(2026, 6, 15, number, 0, 0)
            {seconds(from), seconds(NaiveDateTime.add(from, 3_600))}
          end

        assert {mask, spans(Tempo.select(~o"2026-06-15", read("T#{mask}H")))} == {mask, expected}
      end

      minutes =
        for number <- 0..59, matches?(number, "X5") do
          from = NaiveDateTime.new!(2026, 6, 15, 10, number, 0)
          {seconds(from), seconds(NaiveDateTime.add(from, 60))}
        end

      assert spans(Tempo.select(~o"2026-06-15", ~o"T10HX5M")) == minutes
    end

    test "are the days of the year and the weeks of it their digits match" do
      # The days of the year from the hundredth to the hundred and ninety-ninth.
      hundreds = for number <- 100..199, do: day(Date.add(~D[2026-01-01], number - 1))
      assert spans(Tempo.select(~o"2026", ~o"1XXO")) == hundreds

      {:ok, weeks} = Tempo.select(~o"2026", ~o"2XW")
      assert IntervalSet.count(weeks) == Enum.count(20..29)
    end
  end

  describe "a mask as coarse as what it is selected from" do
    test "keeps what its digits match, and drops what they do not" do
      assert spans(Tempo.select(~o"2026-06-15", ~o"1XD")) == [day(~D[2026-06-15])]
      assert spans(Tempo.select(~o"2026-06-25", ~o"1XD")) == []

      # Each day of a span of days that is in the tens of its month.
      assert spans(Tempo.select(~o"2026-06-05/2026-06-25", ~o"1XD")) ==
               for(number <- 10..19, do: day(Date.new!(2026, 6, number)))

      # The hour from ten is in the tens, and not in the twenties.
      {:ok, ten} = Tempo.to_interval(~o"2026-06-15T10")
      assert Tempo.select(~o"2026-06-15T10", ~o"T1XH") == IntervalSet.new([ten], coalesce: false)
      assert spans(Tempo.select(~o"2026-06-15T10", ~o"T2XH")) == []

      # The years of the 2020s among those from 2020 to 2029.
      {:ok, twenties} = Tempo.select(~o"2020/2030", ~o"202XY")
      assert IntervalSet.count(twenties) == 10
    end
  end

  describe "what a mask is not" do
    test "is an unspecified unit, which is the one span of every value still" do
      assert spans(Tempo.select(~o"2026-06", ~o"X*D")) ==
               [{seconds(~D[2026-06-01]), seconds(~D[2026-07-01])}]
    end

    test "is refused by name in a calendar whose year begins within a month, as a day of a month is" do
      for constraint <- ["15D", "1XD"] do
        assert {constraint,
                {:error,
                 %ConversionError{reason: :not_built, target: :selection, calendar: March25}}} =
                 {constraint,
                  Tempo.select(
                    Tempo.from_iso8601!("1750Y6M", March25),
                    Tempo.from_iso8601!(constraint, March25)
                  )}
      end
    end
  end
end
