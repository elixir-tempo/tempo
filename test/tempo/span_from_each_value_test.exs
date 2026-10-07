defmodule Tempo.SpanFromEachValueTest do
  @moduledoc """
  A span written with a duration from a start that holds a set.

  A set in a unit names each of its values, and a recurrence from a start
  that holds one is the occurrences from each. An interval written with a
  duration is the one occurrence of such a recurrence, and was refused as
  an interval with no one start; it is the span from each value (decided
  2026-10-07), as are a span to an end that holds a set, a selector written
  so, and a shift that skips busy time.

  An interval written with two ends, one of which holds a set, was refused
  still. It is the span from each value to the other end, or to each from
  it (decided 2026-10-08): `2026Y6M{1,15}D/2026Y6M20D` runs from the 1st to
  the 20th and from the 15th to the 20th.

  The measure is Elixir's own `Date` and `NaiveDateTime`: each value of the
  set, and the duration counted from it or the other end as it is written.
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

    test "is still refused from a start that is no set" do
      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Tempo.to_interval(Tempo.from_iso8601!("2026-06-X5/P1D"))
    end
  end

  describe "an interval written with two ends, one of which holds a set" do
    test "is the span from each value of its start to its end" do
      for days <- @days, last <- [~D[2026-07-01], ~D[2026-07-15]] do
        text = "2026Y6M#{set(days)}D/#{last}"

        expected = for day <- days, do: {seconds(Date.new!(2026, 6, day)), seconds(last)}

        assert {text, spans(Tempo.from_iso8601!(text))} == {text, expected}
      end
    end

    test "is the span from its start to each value of its end" do
      for days <- @days do
        text = "2026-05-20/2026Y6M#{set(days)}D"

        expected =
          for day <- days, do: {seconds(~D[2026-05-20]), seconds(Date.new!(2026, 6, day))}

        assert {text, spans(Tempo.from_iso8601!(text))} == {text, expected}
      end
    end

    test "is so of months, of years and of times of day, with a year and with none" do
      assert spans(~o"2026Y{6,7}M/2026Y9M") ==
               for(
                 month <- [6, 7],
                 do: {seconds(Date.new!(2026, month, 1)), seconds(~D[2026-09-01])}
               )

      assert spans(~o"{2026,2027}Y/2030Y") ==
               for(
                 year <- [2026, 2027],
                 do: {seconds(Date.new!(year, 1, 1)), seconds(~D[2030-01-01])}
               )

      assert spans(~o"2026Y6M15DT{9,14}H/2026Y6M15DT16H") ==
               for(
                 hour <- [9, 14],
                 do:
                   {seconds(NaiveDateTime.new!(2026, 6, 15, hour, 0, 0)),
                    seconds(~N[2026-06-15 16:00:00])}
               )

      {:ok, on_the_clock} = Tempo.to_interval(~o"T{9,14}H/T16H")

      assert IntervalSet.members(on_the_clock) ==
               [Tempo.from_iso8601!("T9H/T16H"), Tempo.from_iso8601!("T14H/T16H")]
    end

    test "is in the zone its ends are written in" do
      {:ok, zoned} =
        Tempo.to_interval(Tempo.from_iso8601!("2026Y6M{1,15}D/2026Y6M20D[Europe/Paris]"))

      assert IntervalSet.members(zoned) == [
               Tempo.from_iso8601!("2026-06-01/2026-06-20[Europe/Paris]"),
               Tempo.from_iso8601!("2026-06-15/2026-06-20[Europe/Paris]")
             ]
    end

    test "keeps its spans apart, which overlap, and is one where they are asked to be merged" do
      value = ~o"2026Y6M{1,15}D/2026Y6M20D"

      {:ok, apart} = Tempo.to_interval(value)
      assert IntervalSet.count(apart) == 2

      {:ok, merged} = Tempo.to_interval(value, coalesce: true)

      assert Enum.map(IntervalSet.members(merged), &bounds/1) == [
               {seconds(~D[2026-06-01]), seconds(~D[2026-06-20])}
             ]
    end

    test "is refused where a value is at or after the end it runs to, as that interval is alone" do
      assert {:error, %Tempo.IntervalEndpointsError{} = later} =
               Tempo.to_interval(~o"2026Y6M{1,25}D/2026Y6M20D")

      assert inspect(later.interval) == ~s|~o"2026Y6M25D/20D"|

      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Tempo.to_interval(~o"2026Y6M{1,20}D/2026Y6M20D")
    end

    test "is refused with a set at each end, and with an end left open" do
      for text <- ["2026Y6M{1,15}D/2026Y6M{20,25}D", "2026Y6M{1,15}D/..", "../2026Y6M{1,15}D"] do
        assert {^text, {:error, %Tempo.IntervalEndpointsError{} = error}} =
                 {text, Tempo.to_interval(Tempo.from_iso8601!(text))}

        assert Exception.message(error) =~ "names several spans"
      end
    end

    test "is walked, shown and worded as its spans are" do
      value = ~o"2026Y6M{28,29}D/2026Y7M1D"

      assert Enum.to_list(value) ==
               [~o"2026-06-28", ~o"2026-06-29", ~o"2026-06-30", ~o"2026-06-29", ~o"2026-06-30"]

      assert Tempo.to_string(~o"2026Y6M{1,15}D/2026Y6M20D") ==
               {:ok, "Jun 1\u2009\u2013\u200919, 2026 and Jun 15\u2009\u2013\u200919, 2026"}

      words = to_string(Tempo.explain(~o"2026Y6M1D/2026Y6M{20,25}D"))
      assert words =~ "A span from its start to each value of its end."
      assert words =~ ~s|To:   ~o"2026Y6M{20,25}D"|
      refute words =~ "To:   2026-06-01"
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

    test "selects the span from each value with two ends, one of which holds a set" do
      four = seconds(~N[2026-06-15 16:00:00])

      {:ok, %IntervalSet{} = from_each} = Tempo.select(~o"2026-06-15", ~o"T{9,14}H/T16H")

      assert Enum.map(IntervalSet.members(from_each), &bounds/1) ==
               for(
                 hour <- [9, 14],
                 do: {seconds(NaiveDateTime.new!(2026, 6, 15, hour, 0, 0)), four}
               )

      {:ok, %IntervalSet{} = to_each} = Tempo.select(~o"2026-06-15", ~o"T9H/T{12,16}H")

      assert Enum.map(IntervalSet.members(to_each), &bounds/1) ==
               for(
                 hour <- [12, 16],
                 do:
                   {seconds(~N[2026-06-15 09:00:00]),
                    seconds(NaiveDateTime.new!(2026, 6, 15, hour, 0, 0))}
               )

      {:ok, %IntervalSet{} = days} = Tempo.select(~o"2026-06", ~o"{1,15}D/20D")

      assert Enum.map(IntervalSet.members(days), &bounds/1) ==
               for(
                 day <- [1, 15],
                 do: {seconds(Date.new!(2026, 6, day)), seconds(~D[2026-06-20])}
               )
    end

    test "is refused with a set at each end" do
      assert {:error, %Tempo.IntervalEndpointsError{operation: :select} = error} =
               Tempo.select(~o"2026-06-15", ~o"T{9,14}H/T{16,17}H")

      assert Exception.message(error) =~ "names several values"
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
