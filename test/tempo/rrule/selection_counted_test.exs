defmodule Tempo.RRule.SelectionCountedTest do
  @moduledoc """
  The most occurrences a selection is asked for in one period.

  A time of day in a selection multiplies what the parts before it made:
  `2026YL{1..12}M{1..28}DT{0..23}H{0..59}M{0..59}SN` names 29 million
  seconds. The resolver made every one before anything counted them, so the
  half a million minutes of the same value without its seconds took five
  seconds to be refused, and the seconds did not come to an end. It is told
  the most its caller takes (`:at_most` of `Tempo.RRule.Selection.apply/4`)
  and counts an occurrence as it makes it.

  The measure is the number of occurrences a selection names, counted apart
  from the library: the product of the sizes of its sets, and for a zone the
  readings Elixir's `DateTime` has on the day.
  """
  use ExUnit.Case, async: true

  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule.Selection

  @most 10_000

  ## The measure

  defp to_say(count) when count > @most, do: :refused
  defp to_say(count), do: {:spans, count}

  defp said({:ok, %IntervalSet{} = set}), do: {:spans, IntervalSet.count(set)}
  defp said({:ok, %Interval{}}), do: {:spans, 1}
  defp said({:error, %ConversionError{reason: :too_many_values}}), do: :refused

  defp converted(text), do: text |> Tempo.from_iso8601!() |> Tempo.to_interval()

  # The seconds of a day's first hours that the clock of a zone shows.
  defp seconds_shown(date, hours, zone) do
    Enum.count(0..(hours * 3_600 - 1), fn second ->
      match?({:ok, _shown}, DateTime.new(date, Time.from_seconds_after_midnight(second), zone))
    end)
  end

  # A selection as it is written after a year, the rule it is, and the year
  # as the candidate it is resolved in.
  defp in_2026(selection) do
    %Tempo{time: [{:year, 2026} | rule]} = value = Tempo.from_iso8601!("2026Y" <> selection)

    year = %Interval{
      from: Tempo.from_iso8601!("2026-01-01"),
      to: Tempo.from_iso8601!("2027-01-01")
    }

    {year, %{value | time: rule}}
  end

  describe "a value that holds a selection with times of day" do
    # A value as it is written, and the number of occurrences it names.
    @selections [
      {"2026Y1ML{1..25}DT{0..19}H{0..19}MN", 25 * 20 * 20},
      {"2026Y1ML{1..25}DT{0..19}H{0..20}MN", 25 * 20 * 21},
      {"2026Y1ML{1..7}DT{0..23}H{0..59}MN", 7 * 24 * 60},
      {"2026YL{1..12}M{1..28}DT{0..23}HN", 12 * 28 * 24},
      {"2026YL{1..12}M{1..28}DT{0..23}H{0..59}MN", 12 * 28 * 24 * 60},
      {"2026YL{1..12}M{1..28}DT{0..23}H{0..59}M{0..59}SN", 12 * 28 * 24 * 60 * 60},
      {"{2026..2028}YL{1..12}M{1..28}DT{0..23}H{0..59}M{0..59}SN", 3 * 12 * 28 * 24 * 60 * 60},
      {"2026YL{1..5}KT{0..23}H{0..59}M{0..59}SN", 261 * 24 * 60 * 60}
    ]

    test "is the spans it selects where there are 10,000 or fewer, and refused past them" do
      for {text, count} <- @selections do
        assert {text, said(converted(text))} == {text, to_say(count)}
      end
    end

    test "is counted by what its last part gives, and not by what a part before it made" do
      # The 10,080 minutes of a week are more than the most, and none of
      # them has a seventieth second.
      assert said(converted("2026Y1ML{1..7}DT{0..23}H{0..59}M70SN")) == {:spans, 0}

      # Twenty-five days of four hundred minutes, each with one second of
      # the two named.
      assert said(converted("2026Y1ML{1..25}DT{0..19}H{0..19}M{0,70}SN")) == {:spans, 10_000}
    end

    test "is counted by the readings its zone's clock shows" do
      # The clocks of Paris go from 02:00 to 03:00 on 29 March 2026, so the
      # 10,800 seconds of the day's first three hours are 7,200 readings.
      shown = seconds_shown(~D[2026-03-29], 3, "Europe/Paris")
      assert shown == 7_200

      assert said(converted("2026Y3ML29DT{0..2}H{0..59}M{0..59}SN[Europe/Paris]")) ==
               {:spans, shown}

      # A fourth hour takes them past the most.
      assert seconds_shown(~D[2026-03-29], 4, "Europe/Paris") == 10_800

      assert said(converted("2026Y3ML29DT{0..3}H{0..59}M{0..59}SN[Europe/Paris]")) == :refused
    end

    test "is the one a position picks of them, every one being made for it to pick among" do
      assert said(converted("2026Y1ML{1..7}DT{0..23}H{0..59}M1IN")) == {:spans, 1}
    end
  end

  describe "Tempo.RRule.Selection.apply/4 asked for no more than so many" do
    # A selection, and the number of occurrences it names in 2026.
    @counted [
      {"L{1..3}M{1,15}DT{9,14}H{0,30}MN", 3 * 2 * 2 * 2},
      {"L1M{1..7}DT{0..23}HN", 7 * 24},
      {"L{1..5}KT{9,14}HN", 261 * 2},
      {"L6M{1..31}DT12HN", 30},
      {"L6M{1,15}DN", 2},
      {"L1M1DT{0..23}H{0..59}M70SN", 0}
    ]

    test "gives what it gives asked for all, where that is no more" do
      for {selection, count} <- @counted, most <- [count, count + 1, @most] do
        {year, rule} = in_2026(selection)
        all = Selection.apply(year, rule, :year)

        assert {selection, length(all)} == {selection, count}

        assert {selection, most, Selection.apply(year, rule, :year, at_most: most)} ==
                 {selection, most, all}
      end
    end

    test "says there are more, where there are" do
      for {selection, count} <- @counted, count > 0, most <- [0, count - 1] do
        {year, rule} = in_2026(selection)

        assert {selection, Selection.apply(year, rule, :year, at_most: most)} ==
                 {selection, {:error, {:more_than, most}}}
      end
    end

    test "counts what a position picks, and not what it picks among" do
      {year, rule} = in_2026("L1M{1..7}DT{0..23}H{1,-1}IN")
      picked = Selection.apply(year, rule, :year)

      assert Enum.map(picked, & &1.from) ==
               [Tempo.from_iso8601!("2026Y1M1DT0H"), Tempo.from_iso8601!("2026Y1M7DT23H")]

      assert Selection.apply(year, rule, :year, at_most: 2) == picked
      assert Selection.apply(year, rule, :year, at_most: 1) == {:error, {:more_than, 1}}
    end

    test "counts the minutes of an hour it keeps, in a rule that steps by hours" do
      {_year, rule} = in_2026("LT{9,10}H{0,15,30,45}MN")

      nine = %Interval{
        from: Tempo.from_iso8601!("2026-06-15T09"),
        to: Tempo.from_iso8601!("2026-06-15T10")
      }

      eleven = %Interval{
        from: Tempo.from_iso8601!("2026-06-15T11"),
        to: Tempo.from_iso8601!("2026-06-15T12")
      }

      quarters = Selection.apply(nine, rule, :hour)
      assert [_first, _second, _third, _fourth] = quarters

      assert Selection.apply(nine, rule, :hour, at_most: 4) == quarters
      assert Selection.apply(nine, rule, :hour, at_most: 3) == {:error, {:more_than, 3}}
      assert Selection.apply(eleven, rule, :hour, at_most: 0) == []
    end
  end
end
