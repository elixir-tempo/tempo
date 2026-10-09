defmodule Tempo.SelectByARecurrenceTest do
  @moduledoc """
  A selector that recurs, or that has no end or no start (decided
  2026-10-09, user).

  A recurrence selects its occurrences within each period of the base,
  counted from its start as the period places it: `R3/T9H/PT2H` is the two
  hours from 09:00, from 11:00 and from 13:00 of each day. One with no
  start is its rule's occurrences there: `R/../P1D/FLT9HN`, which an RRULE
  read with no start is. A span with no end runs from its start to the
  period's end (`T9H/..`, nine to midnight), and one with no start from the
  period's start to its end (`../T17H`).

  Each was read as its start alone, the hour from 09:00 and no more, or was
  no selector.

  The measure is `Date` and `NaiveDateTime` alone.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.Matrix.Extent
  alias Tempo.RRule
  alias Tempo.UnboundedRecurrenceError

  @epoch ~N[0000-01-01 00:00:00]
  @week Date.range(~D[2026-06-15], ~D[2026-06-21])
  @june Date.range(~D[2026-06-01], ~D[2026-06-30])

  defp microseconds(%NaiveDateTime{} = moment),
    do: NaiveDateTime.diff(moment, @epoch, :microsecond)

  defp at(%Date{} = date, %Time{} = time), do: NaiveDateTime.new!(date, time)

  defp span(%NaiveDateTime{} = from, %NaiveDateTime{} = to),
    do: {microseconds(from), microseconds(to)}

  defp selected(base, selector) do
    {:ok, set} = Tempo.select(base, selector)
    {:ok, members} = Extent.members(set)
    Enum.map(members, fn %{spans: [span]} -> span end)
  end

  # `count` spans of `length`, one after another from `start`.
  defp occurrences(%NaiveDateTime{} = start, count, length) do
    for index <- 0..(count - 1) do
      from = NaiveDateTime.shift(start, Enum.map(length, fn {unit, n} -> {unit, n * index} end))
      span(from, NaiveDateTime.shift(from, length))
    end
  end

  describe "a span with no end" do
    test "runs from its start to the end of each period" do
      to_midnight =
        for date <- @week, do: span(at(date, ~T[09:00:00]), at(Date.add(date, 1), ~T[00:00:00]))

      assert selected(~o"2026-06-15/2026-06-22", ~o"T9H/..") == to_midnight
      assert selected(~o"2026-06-15", ~o"T9H/..") == Enum.take(to_midnight, 1)

      assert selected(~o"2026-06-15", ~o"T9H30M/..") ==
               [span(at(~D[2026-06-15], ~T[09:30:00]), at(~D[2026-06-16], ~T[00:00:00]))]
    end

    test "runs to the end of a month from a day of it" do
      to_july = [span(at(~D[2026-06-10], ~T[00:00:00]), at(~D[2026-07-01], ~T[00:00:00]))]

      assert selected(~o"2026-06", ~o"10D/..") == to_july
      assert selected(~o"2026-06", ~o"2026-06-10/..") == to_july
    end

    test "runs from a weekday's time to the end of that day" do
      assert Date.day_of_week(~D[2026-06-15]) == 1

      assert selected(~o"2026-06-15/2026-06-22", ~o"1KT9H/..") ==
               [span(at(~D[2026-06-15], ~T[09:00:00]), at(~D[2026-06-16], ~T[00:00:00]))]
    end

    test "goes on without end from a base that has none" do
      {:ok, set} = Tempo.select(~o"2026-06-15/..", ~o"T9H/..")

      assert set |> IntervalSet.walk() |> Enum.take(2) |> Enum.map(&Tempo.to_iso8601!/1) ==
               ["2026Y6M15DT9H/16DT0H", "2026Y6M16DT9H/17DT0H"]
    end
  end

  describe "a span with no start" do
    test "runs from the start of each period to its end" do
      from_midnight = for date <- @week, do: span(at(date, ~T[00:00:00]), at(date, ~T[17:00:00]))

      assert selected(~o"2026-06-15/2026-06-22", ~o"../T17H") == from_midnight

      assert selected(~o"2026-06", ~o"../10D") ==
               [span(at(~D[2026-06-01], ~T[00:00:00]), at(~D[2026-06-10], ~T[00:00:00]))]
    end

    test "is refused where its end names a weekday, which no start is on" do
      assert {:error, %IntervalEndpointsError{}} =
               Tempo.select(~o"2026-06-15/2026-06-22", ~o"../1KT17H")
    end
  end

  describe "a recurrence" do
    test "is its occurrences within each period, from its start placed on the period" do
      each_day =
        Enum.flat_map(@week, &occurrences(at(&1, ~T[09:00:00]), 3, hour: 2))

      assert selected(~o"2026-06-15/2026-06-22", ~o"R3/T9H/PT2H") == each_day
      assert selected(~o"2026-06-15", ~o"R3/T9H/PT2H") == Enum.take(each_day, 3)

      # Written with its first occurrence's end, it is the same recurrence.
      assert selected(~o"2026-06-15", ~o"R3/T9H/T11H") == Enum.take(each_day, 3)
    end

    test "with no count is those that start within the period" do
      # From 09:00 by five hours: 09:00, 14:00 and 19:00 start within the day.
      assert selected(~o"2026-06-15", ~o"R/T9H/PT5H") ==
               occurrences(at(~D[2026-06-15], ~T[09:00:00]), 3, hour: 5)

      # Weeks from 1 June: five start within June, the last of them ending in July.
      assert selected(~o"2026-06", ~o"R/2026-06-01/P1W") ==
               occurrences(at(~D[2026-06-01], ~T[00:00:00]), 5, week: 1)

      assert selected(~o"2026-06", ~o"R2/15D/P1W") ==
               occurrences(at(~D[2026-06-15], ~T[00:00:00]), 2, week: 1)
    end

    test "is selected from each member of a set" do
      {:ok, workdays} = Tempo.select(~o"2026-06-15/2026-06-22", Tempo.workdays(:US))

      assert selected(workdays, ~o"R2/T9H/PT2H") ==
               @week
               |> Enum.filter(&(Date.day_of_week(&1) in 1..5))
               |> Enum.flat_map(&occurrences(at(&1, ~T[09:00:00]), 2, hour: 2))
    end

    test "that has more occurrences in a period than are given at once is that error" do
      assert {:error, %UnboundedRecurrenceError{}} = Tempo.select(~o"2026-06", ~o"R/T0H0M0S/PT1S")
    end
  end

  describe "a recurrence of another calendar than the span's" do
    defp hebrew(text), do: Tempo.from_iso8601!(text, Calendrical.Hebrew)

    test "is refused, as a selection of another calendar is" do
      # A rule is counted in its calendar, and its occurrences are that
      # calendar's values: the 15th of a Hebrew month is no day of June.
      for rule <- ["R/../P1M/FL15DN", "R/../P1D/FLT9HN", "R/../P1W/FL1KN", "R2/15D/P1W"] do
        assert {^rule, {:error, %ConversionError{} = error}} =
                 {rule, Tempo.select(~o"2026-06", hebrew(rule))}

        assert Exception.message(error) =~ "written in Calendrical.Hebrew"
      end

      assert {:error, %ConversionError{}} = Tempo.select(~o"2026-06", hebrew("L15DN"))
    end

    test "selects from a span of its own calendar" do
      {:ok, set} = Tempo.select(hebrew("5786Y9M"), hebrew("R/../P1M/FL15DN"))

      assert Enum.map(IntervalSet.members(set), &Tempo.to_iso8601!/1) ==
               ["5786Y9M15D/16D[u-ca=hebrew]"]
    end

    test "selects where it names no unit a calendar numbers, and has a start" do
      # Hours are the same in every calendar, and the start is placed on the span.
      assert selected(~o"2026-06-15", hebrew("R3/T9H/PT2H")) ==
               occurrences(at(~D[2026-06-15], ~T[09:00:00]), 3, hour: 2)
    end
  end

  describe "a recurrence with no start" do
    test "is what its rule selects in each period, as an RRULE read with no start is" do
      {:ok, daily_at_nine} = RRule.parse("FREQ=DAILY;BYHOUR=9")
      {:ok, mondays} = RRule.parse("FREQ=WEEKLY;BYDAY=MO")

      nine = fn dates ->
        for date <- dates, do: span(at(date, ~T[09:00:00]), at(date, ~T[10:00:00]))
      end

      assert selected(~o"2026-06-15/2026-06-22", daily_at_nine) == nine.(@week)
      # A month is one period, and the rule steps by days within it.
      assert selected(~o"2026-06", daily_at_nine) == nine.(@june)

      assert selected(~o"2026-06", mondays) ==
               for(
                 date <- @june,
                 Date.day_of_week(date) == 1,
                 do: span(at(date, ~T[00:00:00]), at(Date.add(date, 1), ~T[00:00:00]))
               )
    end

    test "is the selection it holds" do
      assert selected(~o"2026", ~o"R/../P1Y/FL7M4DN") == selected(~o"2026", ~o"L7M4DN")

      assert selected(~o"2026", ~o"R/../P1Y/FL7M4DN") ==
               [span(at(~D[2026-07-04], ~T[00:00:00]), at(~D[2026-07-05], ~T[00:00:00]))]
    end
  end
end
