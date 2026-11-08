defmodule Tempo.MatcherTest do
  use ExUnit.Case, async: true

  # Which rules the matcher compiles (decision 76), and where it leaves a
  # period to the engine. What it picks is held to the engine by the
  # measures: `rrule_measure_test.exs`, `rfc5545_examples_test.exs` and
  # `cron_test.exs`.

  import Tempo.Sigils

  alias Tempo.{Matcher, Placed, Select, Spans}

  defp extent(value) do
    {:ok, extent} = Spans.extent(value)
    extent
  end

  defp walked(value, unit) do
    {:ok, walk} = Tempo.walk(value, unit)
    Enum.to_list(walk)
  end

  # What the matcher picks in a period, held to what the engine picks: the
  # place of each occurrence and the span written, a shift and all.
  defp compared(:engine, _placed, _parts), do: :engine

  defp compared({:ok, picked}, placed, parts) do
    {:ok, engine} = Select.in_period(placed, parts, [])

    expected =
      Enum.map(engine, fn value ->
        {start, stop} = extent(value)
        {{start, stop}, Spans.span_of(value, stop)}
      end)

    assert {parts, placed.span, Enum.map(picked, &{Placed.extent(&1), &1.span})} ==
             {parts, placed.span, expected}

    :matcher
  end

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

    test "compiles readings of the clock in an hour or a minute, the coarser units as tests" do
      assert %Matcher{cycle: :hour, tests: [], clock: [minute: [59]]} =
               Matcher.compile([minute: 59], :hour, Calendar.ISO)

      assert %Matcher{cycle: :minute, tests: [hour: [9], minute: [0, 20]], clock: [second: [0]]} =
               Matcher.compile([hour: 9, minute: [0, 20], second: 0], :minute, Calendar.ISO)
    end

    test "counts a day of the week from the end of the week as the calendar's week is long" do
      assert %Matcher{weekdays: [7, 2]} =
               Matcher.compile([day_of_week: [-1, 2]], :week, Calendar.ISO)
    end

    test "compiles nested selections of days after months, with readings of the clock after them" do
      assert %Matcher{months: [11], scope: :month, pickers: [%{weekdays: [4], instances: [4]}]} =
               Matcher.compile(
                 [month: 11, selection: [day_of_week: 4, instance: 4]],
                 :year,
                 Calendar.ISO
               )

      assert %Matcher{scope: :period, clock: [hour: [9, 17]], pickers: [_, _]} =
               Matcher.compile(
                 [
                   all: [[day_of_week: 1, instance: 2], [day_of_week: 6, instance: -1]],
                   hour: [9, 17]
                 ],
                 :year,
                 Calendar.ISO
               )
    end

    test "leaves every other rule to the engine" do
      assert is_nil(
               Matcher.compile(
                 [month: 11, selection: [day_of_week: 4, instance: 4]],
                 :week,
                 Calendar.ISO
               )
             )

      assert is_nil(
               Matcher.compile(
                 [month: 11, selection: [day_of_week: 4], window: ~o"P7D"],
                 :year,
                 Calendar.ISO
               )
             )

      assert is_nil(
               Matcher.compile(
                 [day: 1, selection: [day_of_week: 4, instance: 1]],
                 :year,
                 Calendar.ISO
               )
             )

      assert is_nil(
               Matcher.compile(
                 [month: 11, selection: [day_of_week: 4, instance: 1], instance: 1],
                 :year,
                 Calendar.ISO
               )
             )

      assert is_nil(Matcher.compile([day_of_year: [1, 100, -1]], :year, Calendar.ISO))
      assert is_nil(Matcher.compile([], :hour, Calendar.ISO))
      assert is_nil(Matcher.compile([second: 30], :hour, Calendar.ISO))
      assert is_nil(Matcher.compile([minute: 59, instance: 1], :hour, Calendar.ISO))
      assert is_nil(Matcher.compile([day_of_week: 1, minute: 0], :hour, Calendar.ISO))
      assert is_nil(Matcher.compile([second: 0], :second, Calendar.ISO))
      assert is_nil(Matcher.compile([day: {:mask, [1, :x]}], :month, Calendar.ISO))
      assert is_nil(Matcher.compile([day: [1..-1//2]], :month, Calendar.ISO))
      assert is_nil(Matcher.compile([month: [-1]], :year, Calendar.ISO))
      assert is_nil(Matcher.compile([day_of_week: 1, roll: :nearest], :month, Calendar.ISO))
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

    @nested [
      [month: 11, selection: [day_of_week: 4, instance: 4], hour: 9],
      [month: [4, 10], all: [[day_of_week: 7, instance: 1], [day_of_week: 7, instance: -1]]],
      [
        month: 3,
        all: [[day_of_week: 1, instance: 2], [day_of_week: 6, instance: -1]],
        hour: [9, 17]
      ],
      [month: [1, 7], selection: [day: [1, 15, -1], day_of_week: [1, 2, 3, 4, 5], instance: -1]],
      [month: 3, selection: [day_of_week: 7, instance: 2], hour: 2, minute: 30],
      [month: 11, selection: [day_of_week: 7, instance: 1], hour: 1, minute: 30],
      [selection: [day_of_week: 1, instance: [1, 20, -1]]],
      [all: [[day_of_week: 1, instance: 1], [day_of_week: 5, instance: -1]], hour: 12]
    ]

    test "picks in a year or a month what the engine picks for nested selections" do
      compared =
        for parts <- @nested,
            year <- 2025..2028,
            {unit, units} <- [year: [year: year], month: [year: year, month: 3]] do
          assert {:ok, period} = Tempo.in_zone(Tempo.new!(units), "America/Chicago")
          assert {:ok, [placed]} = Spans.placed(period)
          matcher = Matcher.compile(parts, unit, Calendar.ISO)

          assert {:ok, picked} = Matcher.in_period(matcher, placed)
          assert {:ok, engine} = Select.in_period(placed, parts, [])

          assert {parts, period, Enum.map(picked, &Placed.extent/1)} ==
                   {parts, period, Enum.map(engine, &extent/1)}

          length(picked)
        end

      assert Enum.count(compared) == 64
      assert Enum.sum(compared) >= 100
    end

    @hour_parts [
      [minute: 59],
      [minute: [0, 30], second: [0, 30]],
      [hour: [1, 2, 3], minute: 30],
      [minute: [15, 45]]
    ]

    @minute_parts [
      [second: [0, 30]],
      [hour: 1, minute: [0, 15, 30, 45], second: 0],
      [second: 59]
    ]

    @days [
      ~o"2026-01-22[America/Chicago]",
      ~o"2026-03-08[America/Chicago]",
      ~o"2026-11-01[America/Chicago]",
      ~o"2026-04-05[Australia/Lord_Howe]",
      ~o"2026-10-04[Australia/Lord_Howe]",
      ~o"2026-06-15[Asia/Kathmandu]",
      ~o"2026-06-15",
      ~o"2026-06-15T00+05:30"
    ]

    @hours [
      ~o"2026-11-01T01[America/Chicago]",
      ~o"2026-11-01T01-06:00[America/Chicago]",
      ~o"2026-04-05T01[Australia/Lord_Howe]",
      ~o"2026-03-08T01[America/Chicago]"
    ]

    test "picks in an hour or a minute what the engine picks for readings of the clock" do
      hours = Enum.flat_map(@days, &walked(&1, :hour))
      minutes = Enum.flat_map(@hours, &walked(&1, :minute))

      answered =
        for {periods, unit, all_parts} <- [
              {hours, :hour, @hour_parts},
              {minutes, :minute, @minute_parts}
            ],
            parts <- all_parts,
            period <- periods do
          assert {:ok, [placed]} = Spans.placed(period)
          matcher = Matcher.compile(parts, unit, Calendar.ISO)
          compared(Matcher.in_period(matcher, placed), placed, parts)
        end

      # Every period of an ordinary day is the matcher's; those about a change of the clock are the engine's.
      assert Enum.count(answered, &(&1 == :matcher)) > 400
      assert Enum.count(answered, &(&1 == :engine)) > 50
    end

    test "leaves a period that cuts a month to the engine" do
      matcher =
        Matcher.compile(
          [month: 11, selection: [day_of_week: 4, instance: 4]],
          :year,
          Calendar.ISO
        )

      {:ok, [cut]} = Spans.placed(~o"2026-02-15/2027-02-14")
      assert Matcher.in_period(matcher, cut) == :engine
    end

    test "leaves an unplaced period to the engine" do
      matcher = Matcher.compile([day: [1]], :month, Calendar.ISO)
      assert Matcher.in_period(matcher, ~o"2026-06") == :engine
    end
  end
end
