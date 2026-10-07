defmodule Tempo.SelectTimeOfDayTest do
  @moduledoc """
  Projecting time-of-day windows onto day sets: interval selectors
  project as spans, the duration form, midnight roll-forward, and the
  integer-index unit inference fixed at month/year boundaries.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Duration
  alias Tempo.Interval
  alias Tempo.IntervalSet

  describe "integer indices take the unit from the base's own resolution" do
    test "a day span ending in the next month selects hours, not days" do
      {:ok, set} = Tempo.select(~o"2026-07-31/2026-08-01", 9..16)
      [first | _rest] = IntervalSet.members(set)

      assert IntervalSet.count(set) == 8
      assert first.from.time == [year: 2026, month: 7, day: 31, hour: 9]
    end

    test "a day span ending in the next year selects hours, not months" do
      {:ok, set} = Tempo.select(~o"2026-12-31/2027-01-01", 9..16)
      [first | _rest] = IntervalSet.members(set)

      assert IntervalSet.count(set) == 8
      assert first.from.time == [year: 2026, month: 12, day: 31, hour: 9]
    end

    test "whole-month traversal stays clean at the boundary" do
      {:ok, days} = Tempo.select(~o"2026-07", Tempo.workdays(:AU))
      {:ok, hours} = Tempo.select(days, 9..16)

      assert IntervalSet.count(days) == 23
      assert IntervalSet.count(hours) == 23 * 8

      resolutions =
        hours |> IntervalSet.members() |> Enum.map(&Interval.resolution/1) |> Enum.uniq()

      assert resolutions == [:hour]
    end
  end

  describe "an interval selector projects as a span" do
    test "nine to five is one eight-hour span per day" do
      {:ok, days} = Tempo.select(~o"2026-07", Tempo.workdays(:AU))
      {:ok, open} = Tempo.select(days, ~o"T09/T17")

      assert IntervalSet.count(open) == 23

      [first | _rest] = IntervalSet.members(open)
      assert first.from.time == [year: 2026, month: 7, day: 1, hour: 9]
      assert first.to.time == [year: 2026, month: 7, day: 1, hour: 17]
      assert Tempo.exactly?(first, ~o"PT8H")
    end

    test "a list of windows gives several spans per day" do
      {:ok, days} = Tempo.select(~o"2026-07", Tempo.workdays(:AU))
      {:ok, split} = Tempo.select(days, [~o"T09/T12", ~o"T13/T17"])

      assert IntervalSet.count(split) == 46

      [morning, afternoon | _rest] = IntervalSet.members(split)
      assert Tempo.exactly?(morning, ~o"PT3H")
      assert Tempo.exactly?(afternoon, ~o"PT4H")
    end

    test "half-open: nine to five is written nine to five" do
      {:ok, open} = Tempo.select(~o"2026-07-15/2026-07-16", ~o"T09/T17")
      [window] = IntervalSet.members(open)

      assert Tempo.exactly?(window, ~o"PT8H")
    end
  end

  describe "the duration form" do
    test "start plus duration projects a non-hour-aligned window" do
      {:ok, statutory} = Tempo.select(~o"2026-07-15/2026-07-16", ~o"T09/PT7H36M")
      [window] = IntervalSet.members(statutory)

      assert window.from.time == [year: 2026, month: 7, day: 15, hour: 9]
      assert window.to.time == [year: 2026, month: 7, day: 15, hour: 16, minute: 36]
      assert Tempo.exactly?(window, ~o"PT7H36M")
    end
  end

  describe "windows that cross midnight roll forward" do
    test "a night shift's end lands on the following day" do
      {:ok, shifts} = Tempo.select(~o"2026-07-15/2026-07-16", ~o"T21/T05")
      [shift] = IntervalSet.members(shifts)

      assert shift.from.time == [year: 2026, month: 7, day: 15, hour: 21]
      assert shift.to.time == [year: 2026, month: 7, day: 16, hour: 5]
      assert Tempo.exactly?(shift, ~o"PT8H")
    end

    test "an equal from and to reads as a full day" do
      {:ok, full} = Tempo.select(~o"2026-07-15/2026-07-16", ~o"T09/T09")
      [window] = IntervalSet.members(full)

      assert Tempo.exactly?(window, ~o"PT24H")
    end
  end

  describe "composition — the sentence the plan starts from" do
    test "the workdays of the month, nine to five with an hour for lunch" do
      {:ok, workdays} = Tempo.select(~o"2026-07", Tempo.workdays(:AU))
      {:ok, open} = Tempo.select(workdays, [~o"T09/T12", ~o"T13/T17"])

      assert IntervalSet.count(open) == 46
      assert Duration.to_unit(IntervalSet.duration(open), :hour) == {:ok, 23 * 7.0}
    end
  end

  describe "a time of day selected from a day of a week, in a calendar of weeks" do
    # A time of day is on no axis of dates, and takes no unit from the day it
    # is merged onto. It was held to be on the month's axis, so the day of
    # the week was taken from a week's last day, whose span ends in the next
    # week: 09:00 of a Sunday was 09:00 of that week's Monday, which is no
    # time of the Sunday, and nothing was selected.

    @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

    # The date Erlang gives a day of a week of ISO 8601.
    defp date_of_week_day(year, week, day) do
      Enum.find(Date.range(Date.new!(year, 1, 1), Date.new!(year, 12, 31)), fn date ->
        :calendar.iso_week_number(Date.to_erl(date)) == {year, week} and
          Date.day_of_week(date) == day
      end)
    end

    defp starts(%IntervalSet{} = set) do
      for member <- IntervalSet.members(set),
          do: Compare.to_utc_seconds(Interval.from(member)) - @unix_epoch
    end

    test "is that time on each day of the week, its last too" do
      for day <- 1..7 do
        base = Tempo.from_iso8601!("2024-W10-#{day}[u-ca=iso-week]")
        date = date_of_week_day(2024, 10, day)
        nine = date |> DateTime.new!(~T[09:00:00]) |> DateTime.to_unix()

        {:ok, hour} = Tempo.select(base, ~o"T09")
        {:ok, window} = Tempo.select(base, ~o"T09/T17")
        {:ok, placed} = Tempo.select(base, [9])

        assert {day, starts(hour), starts(window), starts(placed)} ==
                 {day, [nine], [nine], [nine]}
      end
    end

    test "is that time on the last day of a week in a zone" do
      # Sunday 10 March 2024, when New York's clocks go from 02:00 to 03:00.
      base = Tempo.from_iso8601!("2024-W10-7[America/New_York][u-ca=iso-week]")

      nine =
        ~D[2024-03-10] |> DateTime.new!(~T[09:00:00], "America/New_York") |> DateTime.to_unix()

      {:ok, hour} = Tempo.select(base, ~o"T09")
      {:ok, skipped} = Tempo.select(base, ~o"T02")

      assert starts(hour) == [nine]
      assert starts(skipped) == []
    end
  end
end
