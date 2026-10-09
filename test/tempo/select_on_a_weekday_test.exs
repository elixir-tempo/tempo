defmodule Tempo.SelectOnAWeekdayTest do
  @moduledoc """
  A selector that names a day of the week and a time of day after it.

  As a value it is that time on each such day of the base: `1KT10H` is the
  hour from 10:00 of each Monday. As a span whose start names the weekday it
  is the span on each such day: `1KT9H/T17H` is Monday's nine to five.

  The span was merged onto every day of the base as it stood, so a week gave
  seven spans, each in a value that held its date and the weekday both
  (`2026Y6M16D1KT9H`, a Tuesday and Monday). A span that does not start and
  end on the one weekday is no span within a day, and is refused.

  The measure is `Date` and `NaiveDateTime` alone: the days of the base whose
  day of the week `Date.day_of_week/1` gives as the one named, and the times
  of day on each.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.Matrix.Extent

  @epoch ~N[0000-01-01 00:00:00]
  @june Date.range(~D[2026-06-01], ~D[2026-06-30])
  @week Date.range(~D[2026-06-15], ~D[2026-06-21])

  defp microseconds(%NaiveDateTime{} = moment),
    do: NaiveDateTime.diff(moment, @epoch, :microsecond)

  defp selected(base, selector) do
    {:ok, set} = Tempo.select(base, selector)
    {:ok, members} = Extent.members(set)
    Enum.map(members, fn %{spans: [span]} -> span end)
  end

  # The span from one time of day to so long after it, on each day of
  # `dates` that is one of `weekdays`.
  defp on_weekdays(dates, weekdays, %Time{} = from, length) do
    for date <- dates, Date.day_of_week(date) in weekdays do
      start = NaiveDateTime.new!(date, from)
      {microseconds(start), microseconds(NaiveDateTime.shift(start, length))}
    end
  end

  describe "a value that names a weekday and a time of day" do
    test "is that time on each such day of the base" do
      for {selector, weekdays, from, length} <- [
            {~o"1KT10H", [1], ~T[10:00:00], [hour: 1]},
            {~o"5KT10H", [5], ~T[10:00:00], [hour: 1]},
            {~o"1KT10H30M", [1], ~T[10:30:00], [minute: 1]},
            {~o"{1,3}KT10H", [1, 3], ~T[10:00:00], [hour: 1]},
            {~o"{1..5}KT8H", [1, 2, 3, 4, 5], ~T[08:00:00], [hour: 1]}
          ] do
        assert {selector, selected(~o"2026-06", selector)} ==
                 {selector, on_weekdays(@june, weekdays, from, length)}
      end

      # June 2026 has five Mondays.
      assert [_, _, _, _, _] = on_weekdays(@june, [1], ~T[10:00:00], hour: 1)
    end

    test "is each time it names, on each such day" do
      ten = on_weekdays(@week, [1], ~T[10:00:00], hour: 1)
      two = on_weekdays(@week, [1], ~T[14:00:00], hour: 1)

      assert selected(~o"2026-06-15/2026-06-22", ~o"1KT{10,14}H") == ten ++ two
    end
  end

  describe "a span whose start names a weekday" do
    test "is the span on each such day of the base" do
      for {selector, weekdays, from, length} <- [
            {~o"1KT9H/T17H", [1], ~T[09:00:00], [hour: 8]},
            {~o"1KT9H/1KT17H", [1], ~T[09:00:00], [hour: 8]},
            {~o"1KT9H/PT8H", [1], ~T[09:00:00], [hour: 8]},
            {~o"1KT9H30M/T17H15M", [1], ~T[09:30:00], [hour: 7, minute: 45]},
            {~o"{1,3}KT9H/T17H", [1, 3], ~T[09:00:00], [hour: 8]},
            {~o"{1..5}KT9H/T17H", [1, 2, 3, 4, 5], ~T[09:00:00], [hour: 8]},
            # A night that ends on the day after.
            {~o"5KT21H/T5H", [5], ~T[21:00:00], [hour: 8]},
            # From the day's start, where the start names no time.
            {~o"1K/T17H", [1], ~T[00:00:00], [hour: 17]}
          ] do
        assert {selector, selected(~o"2026-06", selector)} ==
                 {selector, on_weekdays(@june, weekdays, from, length)}

        assert {selector, selected(~o"2026-06-15/2026-06-22", selector)} ==
                 {selector, on_weekdays(@week, weekdays, from, length)}
      end
    end

    test "is the times selected from the days selected" do
      {:ok, mondays} = Tempo.select(~o"2026-06", ~o"1K")

      assert Tempo.select(~o"2026-06", ~o"1KT9H/T17H") == Tempo.select(mondays, ~o"T9H/T17H")
    end

    test "is one span of a day that is the weekday, and none of a day that is not" do
      assert Date.day_of_week(~D[2026-06-15]) == 1

      assert selected(~o"2026-06-15", ~o"1KT9H/T17H") ==
               on_weekdays([~D[2026-06-15]], [1], ~T[09:00:00], hour: 8)

      assert selected(~o"2026-06-16", ~o"1KT9H/T17H") == []
    end

    test "goes on without end from a base that has none" do
      {:ok, set} = Tempo.select(~o"2026-06-15/..", ~o"1KT9H/T17H")

      assert set |> IntervalSet.walk() |> Enum.take(3) |> Enum.map(&Tempo.to_iso8601!/1) ==
               ["2026Y6M15DT9H/T17H", "2026Y6M22DT9H/T17H", "2026Y6M29DT9H/T17H"]
    end

    test "leaves a span that names no weekday on every day" do
      assert selected(~o"2026-06-15/2026-06-22", ~o"T9H/T17H") ==
               on_weekdays(@week, [1, 2, 3, 4, 5, 6, 7], ~T[09:00:00], hour: 8)
    end
  end

  describe "a span that does not run within one day of the week" do
    test "is refused, where each day of the base was given it" do
      for selector <- [~o"1KT9H/5KT17H", ~o"1K/5K", ~o"1K/1K", ~o"T9H/1KT17H"] do
        assert {^selector, {:error, %IntervalEndpointsError{} = error}} =
                 {selector, Tempo.select(~o"2026-06-15/2026-06-22", selector)}

        assert Exception.message(error) =~ "does not run within one day of the week"
      end
    end
  end
end
