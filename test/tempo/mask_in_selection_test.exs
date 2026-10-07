defmodule Tempo.MaskInSelectionTest do
  @moduledoc """
  A part of a selection written with unspecified digits.

  A mask stands for each value of its unit that its digits match, as a
  masked year in a selection's context stands for the years it matches. A
  part written with one (`L1XDN`, the days from the 10th to the 19th) was
  passed over where a part's values are named, so it selected nothing, and
  `Tempo.explain/1` and `Tempo.RRule.to_string/1` raised on it.

  The measure is the unit's values counted here with Elixir's `Date`, each
  written to the mask's width and held to its digits.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  ## The measure

  # Whether a number, written to the mask's width with zeros before it, has
  # the mask's digits where the mask gives one.
  defp matches?(number, mask) do
    written = number |> Integer.to_string() |> String.pad_leading(String.length(mask), "0")

    String.length(written) == String.length(mask) and
      written
      |> String.graphemes()
      |> Enum.zip(String.graphemes(mask))
      |> Enum.all?(fn {digit, wanted} -> wanted == "X" or wanted == digit end)
  end

  defp seconds(%Date{} = date),
    do:
      date |> NaiveDateTime.new!(~T[00:00:00]) |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  defp spans({:ok, %IntervalSet{} = set}), do: set |> IntervalSet.members() |> Enum.map(&bounds/1)

  defp days(dates), do: for(date <- dates, do: {seconds(date), seconds(Date.add(date, 1))})

  @day_masks ["1X", "2X", "3X", "X", "XX", "X5", "X0", "0X"]

  describe "a day written with unspecified digits, in a selection" do
    test "is each day of the month its digits match" do
      for month <- 1..12, mask <- @day_masks do
        first = Date.new!(2026, month, 1)

        expected =
          for date <- Date.range(first, Date.end_of_month(first)),
              matches?(date.day, mask),
              do: date

        selection = Tempo.from_iso8601!("2026Y#{month}ML#{mask}DN")

        assert {month, mask, spans(Tempo.to_interval(selection))} == {month, mask, days(expected)}
      end

      # February has no thirtieth, and the 28th is the last a `2X` names.
      assert spans(Tempo.to_interval(~o"2026Y2ML3XDN")) == []
      assert List.last(spans(Tempo.to_interval(~o"2026Y2ML2XDN"))) == hd(days([~D[2026-02-28]]))
    end

    test "is selected from a month, and is the occurrences of a rule" do
      teens = days(Date.range(~D[2026-06-10], ~D[2026-06-19]))

      assert spans(Tempo.select(~o"2026-06", ~o"L1XDN")) == teens

      assert spans(Tempo.to_interval_set(~o"R/2026Y6M/P1M/FL1XDN", within: ~o"2026-06")) == teens

      assert Enum.to_list(~o"2026Y6ML1XDN") ==
               Enum.map(Date.range(~D[2026-06-10], ~D[2026-06-19]), &Tempo.from_date/1)
    end

    test "counted from the end is the days that many from the month's last" do
      for month <- [2, 6, 12] do
        last = Date.end_of_month(Date.new!(2026, month, 1))

        assert {month, spans(Tempo.to_interval(Tempo.from_iso8601!("2026Y#{month}ML-XDN")))} ==
                 {month, days(Date.range(Date.add(last, -8), last))}
      end
    end
  end

  describe "another unit written with unspecified digits, in a selection" do
    test "is each month, week, day of the year, weekday and hour its digits match" do
      {:ok, months} = Tempo.to_interval(~o"2026YL1XMN")

      assert Enum.map(IntervalSet.members(months), &Interval.from/1) == [
               ~o"2026-10",
               ~o"2026-11",
               ~o"2026-12"
             ]

      # 2026 has fifty-three ISO weeks.
      assert :calendar.iso_week_number({2026, 12, 31}) == {2026, 53}
      {:ok, weeks} = Tempo.to_interval(~o"2026YL5XWN")

      assert Enum.map(IntervalSet.members(weeks), &Interval.from/1) ==
               for(week <- 50..53, do: Tempo.from_iso8601!("2026Y#{week}W"))

      assert spans(Tempo.to_interval(~o"2026YL36XON")) ==
               days(for(day <- 360..365, do: Date.add(~D[2026-01-01], day - 1)))

      assert Enum.count(spans(Tempo.to_interval(~o"2026Y6MLXKN"))) == 30

      {:ok, hours} = Tempo.to_interval(~o"2026Y6M15DLT1XHN")

      assert Enum.map(IntervalSet.members(hours), &Interval.from/1) ==
               for(hour <- 10..19, do: Tempo.from_iso8601!("2026-06-15T#{hour}"))
    end
  end

  describe "a selection written with unspecified digits" do
    test "is explained as it is written" do
      for {text, wording} <- [
            {"2026Y6ML1XDN", "on a day written 1X"},
            {"2026Y6M15DLT1XHN", "at an hour written 1X"},
            {"2026YL1XMN", "in a month written 1X"},
            {"2026YL5XW3KN", "in an ISO week written 5X, on a Wednesday"},
            {"2026Y6ML-XDN", "on a day written -X"},
            {"R/2026Y6M/P1M/FL1XDN", "on a day written 1X"}
          ] do
        assert {text, Tempo.explain(Tempo.from_iso8601!(text)) =~ wording} == {text, true}
      end
    end

    test "is no RRULE, which names its numbers" do
      for text <- ["R2/2026Y6M/P1M/FL1XDN", "R2/2026Y6M1D/P1M/FL15DT1XHN"] do
        assert {^text, {:error, %Tempo.ConversionError{target: :rrule} = error}} =
                 {text, RRule.to_string(Tempo.from_iso8601!(text))}

        assert Exception.message(error) =~ "unspecified digits"
      end
    end

    test "is written and read back" do
      for text <- ["2026Y6ML1XDN", "2026YL1XMN", "2026Y6ML-XDN"] do
        value = Tempo.from_iso8601!(text)

        assert {text, Tempo.to_iso8601(value), inspect(value)} ==
                 {text, {:ok, text}, ~s(~o"#{text}")}
      end
    end
  end
end
