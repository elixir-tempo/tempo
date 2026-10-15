defmodule Tempo.MatcherTest do
  use ExUnit.Case, async: true

  # Which rules the matcher compiles (decision 76), and where it leaves a
  # period to the engine. What it picks is held to the engine by the
  # measures: `rrule_measure_test.exs`, `rfc5545_examples_test.exs` and
  # `cron_test.exs`.

  import Tempo.Sigils

  alias Tempo.{Matcher, Placed, Spans}

  describe "compile/3" do
    test "compiles the plain parts of a rule whose period is a day or coarser" do
      assert %Matcher{weekdays: [1, 3, 5], clock: [hour: [23], minute: [59], second: [0]]} =
               Matcher.compile(
                 [day_of_week: [1, 3, 5], hour: 23, minute: 59, second: 0],
                 :week,
                 Calendar.ISO
               )

      assert %Matcher{months: [1, 6], days: {[1, 15], [-1]}, instances: [-1]} =
               Matcher.compile(
                 [month: [1, 6], day: [1, 15, -1], instance: -1],
                 :month,
                 Calendar.ISO
               )

      assert %Matcher{days: {[1, 2, 3, 4, 5], []}} =
               Matcher.compile([day: [1..5]], :month, Calendar.ISO)
    end

    test "counts a day of the week from the end of the week as the calendar's week is long" do
      assert %Matcher{weekdays: [7, 2]} =
               Matcher.compile([day_of_week: [-1, 2]], :week, Calendar.ISO)
    end

    test "leaves every other rule to the engine" do
      assert Matcher.compile(
               [month: 11, selection: [day_of_week: 4, instance: 4]],
               :year,
               Calendar.ISO
             ) == nil

      assert Matcher.compile([all: [[day_of_week: 1, instance: 2]]], :month, Calendar.ISO) == nil
      assert Matcher.compile([day_of_year: [1, 100, -1]], :year, Calendar.ISO) == nil
      assert Matcher.compile([minute: 59], :hour, Calendar.ISO) == nil
      assert Matcher.compile([day: {:mask, [1, :x]}], :month, Calendar.ISO) == nil
      assert Matcher.compile([day: [1..-1//2]], :month, Calendar.ISO) == nil
      assert Matcher.compile([month: [-1]], :year, Calendar.ISO) == nil
      assert Matcher.compile([day_of_week: 1, roll: :nearest], :month, Calendar.ISO) == nil
    end
  end

  describe "in_period/2" do
    test "picks in a placed period what the engine picks" do
      matcher = Matcher.compile([day_of_week: [1, 3, 5], hour: 9], :week, Calendar.ISO)
      {:ok, [period]} = Spans.placed(~o"2026-W25")

      assert {:ok, picked} = Matcher.in_period(matcher, period)

      assert Enum.map(picked, & &1.span) == [
               ~o"2026Y6M15DT9H/T10H",
               ~o"2026Y6M17DT9H/T10H",
               ~o"2026Y6M19DT9H/T10H"
             ]

      for %Placed{} = placed <- picked do
        assert {:ok, Placed.extent(placed)} == Spans.extent(placed.span)
      end
    end

    test "leaves a period to the engine where a month does not count its days" do
      matcher = Matcher.compile([day: [1, 14]], :month, Calendrical.Reform.England)

      {:ok, [september]} =
        Spans.placed(Tempo.new!(year: 1752, month: 9, calendar: Calendrical.Reform.England))

      assert Matcher.in_period(matcher, september) == :engine
    end

    test "leaves an unplaced period to the engine" do
      matcher = Matcher.compile([day: [1]], :month, Calendar.ISO)
      assert Matcher.in_period(matcher, ~o"2026-06") == :engine
    end
  end
end
