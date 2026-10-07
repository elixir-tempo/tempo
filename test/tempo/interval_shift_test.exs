defmodule Tempo.IntervalShiftTest do
  @moduledoc """
  An interval shifted, truncated and rounded (decided 2026-10-07).

  `Tempo.shift/3` moves both ends of an interval and keeps its length,
  `Tempo.trunc/2` gives the whole units it touches, its start taken down and
  its end up, and `Tempo.round/2` takes each end to the unit nearer it. Each
  was an `ArgumentError`, an interval being no one value.

  The measure is Elixir's own `Date` and `NaiveDateTime`, each end worked
  out apart from the library.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval

  ## The measure

  defp seconds(%Date{} = date), do: seconds(NaiveDateTime.new!(date, ~T[00:00:00]))

  defp seconds(%NaiveDateTime{} = moment),
    do: moment |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  defp interval(%NaiveDateTime{} = from, %NaiveDateTime{} = to),
    do:
      Interval.new!(
        from: Tempo.from_elixir(from, resolution: :minute),
        to: Tempo.from_elixir(to, resolution: :minute)
      )

  defp interval(%Date{} = from, %Date{} = to),
    do: Interval.new!(from: Tempo.from_date(from), to: Tempo.from_date(to))

  # Pairs of moments a few minutes to a few days apart, some through
  # midnight and through the end of a month.
  @moments [
    {~N[2026-06-15 10:30:00], ~N[2026-06-15 12:45:00]},
    {~N[2026-06-15 23:10:00], ~N[2026-06-16 01:20:00]},
    {~N[2026-01-31 22:00:00], ~N[2026-02-01 06:00:00]},
    {~N[2026-12-31 18:00:00], ~N[2027-01-02 09:15:00]},
    {~N[2024-02-28 12:00:00], ~N[2024-03-01 12:00:00]}
  ]

  @dates [
    {~D[2026-06-15], ~D[2026-06-18]},
    {~D[2026-01-29], ~D[2026-01-31]},
    {~D[2026-01-01], ~D[2026-02-01]},
    {~D[2024-02-29], ~D[2024-03-01]},
    {~D[2026-03-30], ~D[2026-05-31]},
    {~D[2026-08-31], ~D[2026-09-30]}
  ]

  describe "an interval shifted" do
    test "has both its ends moved, by days and by the units of the clock" do
      for {from, to} <- @moments,
          shift <- [[day: 1], [day: -40], [week: 2], [hour: 5], [minute: -90], [day: 1, hour: 13]] do
        expected =
          {seconds(NaiveDateTime.shift(from, shift)), seconds(NaiveDateTime.shift(to, shift))}

        assert {from, to, shift, bounds(Tempo.shift(interval(from, to), shift))} ==
                 {from, to, shift, expected}
      end
    end

    test "is as many days long as it was, a month or a year on" do
      for {from, to} <- @dates,
          shift <- [[month: 1], [month: -1], [month: 11], [year: 1], [year: -4]] do
        start = Date.shift(from, shift)
        expected = {seconds(start), seconds(Date.add(start, Date.diff(to, from)))}

        assert {from, to, shift, bounds(Tempo.shift(interval(from, to), shift))} ==
                 {from, to, shift, expected}
      end

      # 29 and 31 January are both 28 February a month on, and the two days
      # between them are kept.
      assert Date.shift(~D[2026-01-29], month: 1) == Date.shift(~D[2026-01-31], month: 1)
      assert Tempo.shift(~o"2026-01-29/2026-01-31", month: 1) == ~o"2026-02-28/2026-03-02"
    end

    test "counts its months and years first, and what else it is shifted by after" do
      for {from, to} <- @dates do
        start = from |> Date.shift(month: 1) |> Date.add(10)
        expected = {seconds(start), seconds(Date.add(start, Date.diff(to, from)))}

        assert {from, to, bounds(Tempo.shift(interval(from, to), month: 1, day: 10))} ==
                 {from, to, expected}
      end
    end

    test "is shifted by a duration and by its text, as by its units" do
      by_units = Tempo.shift(~o"2026-06-15T10:30/2026-06-15T12:45", day: 1)

      assert by_units == ~o"2026-06-16T10:30/2026-06-16T12:45"
      assert Tempo.shift(~o"2026-06-15T10:30/2026-06-15T12:45", ~o"P1D") == by_units
      assert Tempo.shift(~o"2026-06-15T10:30/2026-06-15T12:45", "P1D") == by_units
    end

    test "keeps the units its ends are written to" do
      assert Tempo.shift(~o"2026-01/2026-03", month: 1) == ~o"2026-02/2026-04"
      assert Tempo.shift(~o"2026/2028", year: -1) == ~o"2025/2027"
      assert Tempo.shift(~o"2026-06-15T10/2026-06-16", day: 2) == ~o"2026-06-17T10/2026-06-18"
    end

    test "keeps its duration where it is written with one, and an open end open" do
      assert Tempo.shift(~o"2026-06-01/P1M", month: 1) == ~o"2026-07-01/P1M"
      assert Tempo.shift(~o"P1M/2026-07-01", day: 1) == ~o"P1M/2026-07-02"
      assert Tempo.shift(~o"2026-06-01/..", day: 1) == ~o"2026-06-02/.."
      assert Tempo.shift(~o"../2026-06-01", day: 1) == ~o"../2026-06-02"
      assert Tempo.shift(~o"../..", day: 1) == ~o"../.."
      assert Tempo.shift(~o"R3/2026-06-01/P1D", day: 1) == ~o"R3/2026-06-02/P1D"
    end

    test "is at the same times on its zone's clock a day on, across a change of it" do
      # Paris's clocks go forward on the night of 28 March 2026.
      zone = "Europe/Paris"

      shifted =
        Tempo.shift(~o"2026-03-28T12:00[Europe/Paris]/2026-03-30T12:00[Europe/Paris]", day: 1)

      epoch = :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

      noon = fn day ->
        DateTime.to_unix(DateTime.new!(Date.new!(2026, 3, day), ~T[12:00:00], zone))
      end

      {from, to} = bounds(shifted)

      assert {from - epoch, to - epoch} == {noon.(29), noon.(31)}
    end

    test "is refused with :skipping, and by what is no duration" do
      interval = ~o"2026-06-15T10:30/2026-06-15T12:45"

      assert {:error, %ArgumentError{} = error} =
               Tempo.shift(interval, [day: 1], skipping: ~o"2026-06-16")

      assert Exception.message(error) =~ "has two ends"

      assert {:error, %ArgumentError{}} = Tempo.shift(interval, fortnight: 1)
      assert {:error, %Tempo.ParseError{}} = Tempo.shift(interval, "nonsense")
    end
  end

  describe "an interval truncated" do
    # A moment taken down to the start of its unit, and up to the start of
    # the next where it is not on one.
    defp down(moment, :hour), do: %{moment | minute: 0, second: 0}
    defp down(moment, :day), do: %{moment | hour: 0, minute: 0, second: 0}

    defp up(moment, unit) do
      floor = down(moment, unit)
      if floor == moment, do: floor, else: NaiveDateTime.shift(floor, [{unit, 1}])
    end

    test "is the whole units it touches, its start taken down and its end up" do
      for {from, to} <- [{~N[2026-06-15 10:00:00], ~N[2026-06-15 13:00:00]} | @moments],
          unit <- [:hour, :day] do
        expected = {seconds(down(from, unit)), seconds(up(to, unit))}

        assert {from, to, unit, bounds(Tempo.trunc(interval(from, to), unit))} ==
                 {from, to, unit, expected}
      end
    end

    test "is written to the unit it is truncated to" do
      assert Tempo.trunc(~o"2026-06-15T10:30/2026-06-15T12:45", :hour) ==
               ~o"2026-06-15T10/2026-06-15T13"

      assert Tempo.trunc(~o"2026-06-15T10:30/2026-06-17T08:00", :day) == ~o"2026-06-15/2026-06-18"
      assert Tempo.trunc(~o"2026-06-15T10:30/2026-06-17T08:00", :month) == ~o"2026-06/2026-07"

      # A week from its first day, in a calendar of months: 15 June 2026 is
      # a Monday.
      assert Date.day_of_week(~D[2026-06-15]) == 1

      assert Tempo.trunc(~o"2026-06-15T10:30/2026-06-17T08:00", :week) ==
               ~o"2026-06-15/2026-06-22"
    end

    test "leaves an end written to a coarser unit, an end on a unit's start, and an open end" do
      assert Tempo.trunc(~o"2026-06-15T10:30/2026-06-16", :hour) == ~o"2026-06-15T10/2026-06-16"

      assert Tempo.trunc(~o"2026-06-15T10:30/2026-06-15T13:00", :hour) ==
               ~o"2026-06-15T10/2026-06-15T13"

      assert Tempo.trunc(~o"2026-06-15T10:30/..", :hour) == ~o"2026-06-15T10/.."
    end

    test "is counted to its ends where it is written with a duration" do
      assert Tempo.trunc(~o"2026-06-15T10:30/PT2H15M", :hour) == ~o"2026-06-15T10/2026-06-15T13"
    end

    test "is refused of a recurrence, and to what is no unit" do
      assert {:error, %ArgumentError{}} = Tempo.trunc(~o"R3/2026-06-01/P1D", :month)

      assert {:error, %Tempo.InvalidUnitError{}} =
               Tempo.trunc(~o"2026-06-15T10:30/2026-06-15T12:45", :fortnight)
    end
  end

  describe "an interval rounded" do
    defp nearest(moment, :hour) do
      floor = %{moment | minute: 0, second: 0}
      if moment.minute >= 30, do: NaiveDateTime.shift(floor, hour: 1), else: floor
    end

    defp nearest(moment, :day) do
      floor = %{moment | hour: 0, minute: 0, second: 0}
      if moment.hour >= 12, do: NaiveDateTime.shift(floor, day: 1), else: floor
    end

    test "has each end taken to the unit nearer it" do
      for {from, to} <- @moments, unit <- [:hour, :day] do
        expected = {seconds(nearest(from, unit)), seconds(nearest(to, unit))}

        assert {from, to, unit, bounds(Tempo.round(interval(from, to), unit))} ==
                 {from, to, unit, expected}
      end
    end

    test "is written to the unit it is rounded to" do
      assert Tempo.round(~o"2026-06-15T10:30/2026-06-15T12:45", :hour) ==
               ~o"2026-06-15T11/2026-06-15T13"

      assert Tempo.round(~o"2026-06-10/2026-06-20", :month) == ~o"2026-06/2026-07"
    end

    test "leaves an end written to a coarser unit, and an open end" do
      assert Tempo.round(~o"2026-06-15T10:30/2026-06-16", :hour) == ~o"2026-06-15T11/2026-06-16"
      assert Tempo.round(~o"../2026-06-15T12:45", :hour) == ~o"../2026-06-15T13"
    end

    test "is refused of a recurrence" do
      assert {:error, %ArgumentError{}} = Tempo.round(~o"R3/2026-06-01/P1D", :month)
    end
  end
end
