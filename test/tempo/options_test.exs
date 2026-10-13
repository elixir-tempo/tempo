defmodule Tempo.OptionsTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{Cron, Duration, Interval, IntervalSet, RRule}

  # An option a function does not read is refused (law 7): passed over, a
  # window misspelt would answer for no window at all.

  describe "an option a function does not take" do
    test "is an error that names it and what the function takes" do
      assert {:error, %ArgumentError{message: message}} =
               Tempo.to_interval(~o"6M15D", withn: ~o"2026")

      assert message == ":withn is not an option of Tempo.to_interval/2: it takes :within"
    end

    test "names the option a Tempo 1 name became" do
      assert {:error, %ArgumentError{message: message}} =
               Tempo.to_interval(~o"R/2020-01-01/P1Y", bound: ~o"2026")

      assert message == ":bound is not an option of Tempo.to_interval/2: it is :within"
    end

    test "is refused by the functions that answer a tuple" do
      for result <- [
            Tempo.from_iso8601("2026", strict: true),
            Tempo.parse("2026", strict: true),
            Tempo.members(~o"2026Y{1,3}M", bound: ~o"2026"),
            Tempo.walk(~o"2026-06", :day, bound: ~o"2026"),
            Tempo.union(~o"2026-01", ~o"2026-03", bound: ~o"2026"),
            Tempo.intersection(~o"2026-01", ~o"2026-03", bound: ~o"2026"),
            Tempo.difference(~o"2026-01", ~o"2026-03", bound: ~o"2026"),
            Tempo.symmetric_difference(~o"2026-01", ~o"2026-03", bound: ~o"2026"),
            Tempo.complement(~o"2026-01", within: ~o"2026", bound: ~o"2026"),
            Tempo.members_overlapping(~o"2026-01", ~o"2026-03", bound: ~o"2026"),
            Tempo.members_outside(~o"2026-01", ~o"2026-03", bound: ~o"2026"),
            Tempo.members_in_exactly_one(~o"2026-01", ~o"2026-03", bound: ~o"2026"),
            Tempo.shift(~o"2026-06-15", ~o"P1D", skip: ~o"2026-06-16"),
            Tempo.select(~o"2026", ~o"12M25D", bound: ~o"2026"),
            Tempo.workdays(:US, excluding: []),
            Tempo.roll_to_workday(~o"2026-06-13", :US, direction: :preceding),
            Tempo.from_elixir(~D[2026-06-15], unit: :day),
            Interval.new(from: ~o"2026-06-15", until: ~o"2026-06-20"),
            IntervalSet.new([~o"2026-06-15"], sorted: true),
            IntervalSet.slots(~o"2026-06-15T09/2026-06-15T17", ~o"PT1H", step: ~o"PT30M"),
            IntervalSet.covered(~o"{2026-06-15,2026-06-16}", by: 2),
            RRule.parse("FREQ=DAILY;COUNT=3", dtstart: ~o"2026-06-01"),
            Cron.parse("0 9 * * 1-5", start: ~o"2026-06-01"),
            Duration.to_unit(~o"P1M", :day, from: ~o"2026-01-01")
          ] do
        assert {:error, %ArgumentError{}} = result
      end
    end

    test "raises from the functions that answer a bare value" do
      assert_raise ArgumentError,
                   ~r/:bound is not an option of Tempo.before\?\/3: it is :within/,
                   fn ->
                     Tempo.before?(~o"2026-01", ~o"2026-03", bound: ~o"2026")
                   end

      assert_raise ArgumentError, fn -> Tempo.compare(~o"2026-01", ~o"2026-03", bound: 1) end
      assert_raise ArgumentError, fn -> Duration.compare(~o"P1D", ~o"PT1H", from: 1) end
      assert_raise ArgumentError, fn -> IntervalSet.from_stream([], sorted: true) end
    end

    test "options that are no keyword list are refused" do
      assert {:error, %ArgumentError{message: message}} = Tempo.to_interval(~o"2026", [:within])
      assert message == "Tempo.to_interval/2 takes its options as a keyword list"
    end
  end

  describe "the options a function does take" do
    test "are read as before" do
      assert {:ok, _} = Tempo.to_interval(~o"6M15D", within: ~o"2026")
      assert {:ok, _} = Tempo.union(~o"2026-01", ~o"2026-03", metadata: :first)
      assert Tempo.before?(~o"2026-01", ~o"2026-03", within: ~o"2026")
    end
  end
end
