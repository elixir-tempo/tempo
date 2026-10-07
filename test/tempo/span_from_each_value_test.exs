defmodule Tempo.SpanFromEachValueTest do
  @moduledoc """
  A span written with a duration from a start that holds a set.

  A set in a unit names each of its values, and a recurrence from a start
  that holds one is the occurrences from each. An interval written with a
  duration is the one occurrence of such a recurrence, and was refused as
  an interval with no one start; it is the span from each value (decided
  2026-10-07), as are a span to an end that holds a set, a selector written
  so, and a shift that skips busy time.

  The measure is Elixir's own `Date` and `NaiveDateTime`: each value of the
  set, and the duration counted from it.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet

  ## The measure

  defp seconds(%Date{} = date), do: seconds(NaiveDateTime.new!(date, ~T[00:00:00]))

  defp seconds(%NaiveDateTime{} = moment),
    do: moment |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  defp spans(value) do
    {:ok, %IntervalSet{} = set} = Tempo.to_interval(value)
    set |> IntervalSet.members() |> Enum.map(&bounds/1)
  end

  # A start of June 2026 that holds a set of days, as text, with the dates
  # it names; a duration as text, with the same as Elixir's `Date.shift/2`
  # takes it.
  @days [[1, 15], [1, 2, 3], [10, 30], [28, 29, 30]]
  @durations [{"P1D", [day: 1]}, {"P3D", [day: 3]}, {"P1W", [week: 1]}, {"P1M", [month: 1]}]

  defp set(days), do: "{" <> Enum.join(days, ",") <> "}"

  describe "an interval written with a duration from a start that holds a set" do
    test "is the span from each value of the set" do
      for days <- @days, {duration, shift} <- @durations do
        text = "2026Y6M#{set(days)}D/#{duration}"

        expected =
          for day <- days, date = Date.new!(2026, 6, day) do
            {seconds(date), seconds(Date.shift(date, shift))}
          end

        assert {text, spans(Tempo.from_iso8601!(text))} == {text, expected}
      end
    end

    test "is the span to each value, written with a duration and an end" do
      for days <- @days, {duration, shift} <- @durations do
        text = "#{duration}/2026Y6M#{set(days)}D"
        back = for {unit, amount} <- shift, do: {unit, -amount}

        expected =
          for day <- days, date = Date.new!(2026, 6, day) do
            {seconds(Date.shift(date, back)), seconds(date)}
          end

        assert {text, spans(Tempo.from_iso8601!(text))} == {text, expected}
      end
    end

    test "is counted from a time of day on each day, and from each month and each year" do
      assert spans(~o"2026Y6M{1,15}DT10H/PT2H") == [
               {seconds(~N[2026-06-01 10:00:00]), seconds(~N[2026-06-01 12:00:00])},
               {seconds(~N[2026-06-15 10:00:00]), seconds(~N[2026-06-15 12:00:00])}
             ]

      assert spans(~o"2026Y{1..3}M/P2M") ==
               for(
                 month <- 1..3,
                 do: {seconds(Date.new!(2026, month, 1)), seconds(Date.new!(2026, month + 2, 1))}
               )

      # A set in each of two units, and a day one of the years lacks.
      assert spans(~o"{2027,2028}Y2M{28,29}D/P1D") == [
               {seconds(~D[2027-02-28]), seconds(~D[2027-03-01])},
               {seconds(~D[2028-02-28]), seconds(~D[2028-02-29])},
               {seconds(~D[2028-02-29]), seconds(~D[2028-03-01])}
             ]
    end

    test "is the one occurrence of the recurrence from the same start, and the selection's spans" do
      one = spans(~o"2026Y6M{1,15}D/P1D")

      assert one == spans(~o"R1/2026Y6M{1,15}D/P1D")
      assert one == spans(~o"2026Y6ML{1,15}DN/P1D")

      # Two occurrences from each value begin with the one.
      assert Enum.take_every(spans(~o"R2/2026Y6M{1,15}D/P1D"), 2) == one
    end

    test "is walked as its spans are" do
      hours =
        for day <- [1, 15],
            hour <- 0..2,
            do: seconds(NaiveDateTime.new!(2026, 6, day, hour, 0, 0))

      assert Enum.map(~o"2026Y6M{1,15}D/PT3H", &Compare.to_utc_seconds/1) == hours
      assert Enum.count(~o"2026Y6M{1,15}D/PT3H") == 6
    end

    test "is still refused with two ends, and from a start that is no set" do
      for text <- ["2026Y6M{1,15}D/2026Y6M20D", "2026-06-X5/P1D"] do
        assert {^text, {:error, %Tempo.IntervalEndpointsError{}}} =
                 {text, Tempo.to_interval(Tempo.from_iso8601!(text))}
      end
    end
  end

  describe "a selector written with a duration from a start that holds a set" do
    test "selects the span from each value" do
      {:ok, %IntervalSet{} = hours} = Tempo.select(~o"2026-06-15", ~o"T{9,14}H/PT1H")

      assert Enum.map(IntervalSet.members(hours), &bounds/1) == [
               {seconds(~N[2026-06-15 09:00:00]), seconds(~N[2026-06-15 10:00:00])},
               {seconds(~N[2026-06-15 14:00:00]), seconds(~N[2026-06-15 15:00:00])}
             ]

      {:ok, %IntervalSet{} = days} = Tempo.select(~o"2026-06", ~o"{1,15}D/P2D")

      assert Enum.map(IntervalSet.members(days), &bounds/1) == [
               {seconds(~D[2026-06-01]), seconds(~D[2026-06-03])},
               {seconds(~D[2026-06-15]), seconds(~D[2026-06-17])}
             ]
    end

    test "selects what each value alone selects, on each day of a span" do
      base = ~o"2026-06-15/2026-06-18"

      {:ok, both} = Tempo.select(base, ~o"T{9,14}H/PT1H30M")
      {:ok, from_nine} = Tempo.select(base, ~o"T9H/PT1H30M")
      {:ok, from_two} = Tempo.select(base, ~o"T14H/PT1H30M")

      alone = IntervalSet.members(from_nine) ++ IntervalSet.members(from_two)

      assert IntervalSet.count(both) == 6

      assert Enum.sort(Enum.map(IntervalSet.members(both), &bounds/1)) ==
               Enum.sort(Enum.map(alone, &bounds/1))
    end

    test "is still refused with two ends" do
      assert {:error, %Tempo.IntervalEndpointsError{operation: :select}} =
               Tempo.select(~o"2026-06-15", ~o"T{9,14}H/T16H")
    end
  end

  describe "a shift that skips busy time, of a value that holds a set" do
    test "is each value shifted, written as one value where they are one" do
      # A day of free time from the 1st is the 3rd where the 2nd is busy.
      assert Tempo.shift(~o"2026Y6M{1,15}D", [day: 1], skipping: ~o"2026-06-02") ==
               ~o"2026Y6M{3,16}D"

      # An hour of free time from 09:30 is 11:30 where 10:00 to 11:00 is busy.
      assert Tempo.shift(~o"2026-06-15T{9,14}:30", ~o"PT1H",
               skipping: ~o"2026-06-15T10/2026-06-15T11"
             ) ==
               ~o"2026Y6M15DT{11,15}H30M0S"
    end

    test "is what each value gives alone" do
      busy = ~o"2026-06-16"

      for {set, values} <- [
            {~o"2026Y6M{1,15}D", [~o"2026-06-01", ~o"2026-06-15"]},
            {~o"2026Y6M{15,30}D", [~o"2026-06-15", ~o"2026-06-30"]}
          ] do
        alone =
          for value <- values,
              do: bounds(Tempo.to_interval!(Tempo.shift(value, [day: 1], skipping: busy)))

        {:ok, together} = Tempo.to_interval_set(Tempo.shift(set, [day: 1], skipping: busy))

        assert Enum.map(IntervalSet.members(together), &bounds/1) == alone
      end
    end
  end
end
