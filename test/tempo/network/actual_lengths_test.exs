defmodule Tempo.Network.ActualLengthsTest do
  use ExUnit.Case, async: true

  # A network places every value by its actual length, never a mean one: a
  # year of days, or of months, is measured by calendar arithmetic from
  # where its period can start, in the period's own calendar.

  import Tempo.Sigils

  alias Tempo.Network
  alias Tempo.Network.{Normalize, Solver}
  alias Tempo.Schedule

  defp solved(network, id) do
    {:ok, propagated} = Solver.propagate(network)
    propagated.periods[id]
  end

  defp hebrew(year, month, day) do
    {:ok, date} = Date.new(year, month, day, Calendrical.Hebrew)
    Tempo.from_elixir(date)
  end

  describe "a duration coarser than the axis is measured" do
    test "a year from the first day of a leap year is 366 days" do
      period =
        solved(Network.add_period(Network.new(), :a, from: ~o"2024-01-01", duration: ~o"P1Y"), :a)

      assert period.earliest_end == ~o"2025-01-01"
      assert {period.min_duration, period.max_duration} == {~o"P366D", ~o"P366D"}
    end

    test "a month from 31 January ends on 28 February" do
      period =
        solved(Network.add_period(Network.new(), :a, from: ~o"2026-01-31", duration: ~o"P1M"), :a)

      assert period.earliest_end == ~o"2026-02-28"
      assert period.min_duration == ~o"P28D"
    end

    test "a Hebrew year is the Hebrew year's days, in the Hebrew calendar" do
      # 5784 is a leap year of 383 days, and 5785 a year of 355.
      network =
        Network.new()
        |> Network.add_period(:a, from: hebrew(5784, 1, 1), duration: ~o"P1Y")
        |> Network.add_period(:b, duration: ~o"P1Y")
        |> Network.add_sequence([:a, :b])

      assert solved(network, :a).earliest_end == hebrew(5785, 1, 1)
      assert solved(network, :a).min_duration == ~o"P383D"
      assert solved(network, :b).earliest_end == hebrew(5786, 1, 1)
      assert solved(network, :b).min_duration == ~o"P355D"
    end

    test "each year in a sequence takes its own length" do
      network =
        Network.new()
        |> Network.add_period(:a, from: ~o"2024-01-01", duration: ~o"P1Y")
        |> Network.add_period(:b, duration: ~o"P1Y")
        |> Network.add_sequence([:a, :b])

      assert solved(network, :b).earliest_end == ~o"2026-01-01"
      assert solved(network, :b).min_duration == ~o"P365D"
    end

    test "a start free over a year bounds the end by where each start's year ends" do
      # From 1 January 2024 the year ends on 1 January 2025, 366 days on;
      # from 31 December 2024, on 31 December 2025.
      period =
        Network.new()
        |> Network.add_period(:a, from: {~o"2024-01-01", ~o"2024-12-31"}, duration: ~o"P1Y")
        |> solved(:a)

      assert {period.earliest_end, period.latest_end} == {~o"2025-01-01", ~o"2025-12-31"}
      assert {period.min_duration, period.max_duration} == {~o"P365D", ~o"P366D"}
    end

    test "an undated year runs 365 or 366 days, the Gregorian calendar's extremes" do
      period =
        Network.new()
        |> Network.add_period(:a, duration: ~o"P1Y")
        |> Network.add_period(:b, duration: ~o"P10D")
        |> solved(:a)

      assert {period.min_duration, period.max_duration} == {~o"P365D", ~o"P366D"}
    end

    test "a year on a month axis is twelve months" do
      period =
        solved(Network.add_period(Network.new(), :a, from: ~o"2026-01", duration: ~o"P1Y"), :a)

      assert period.earliest_end == ~o"2027-01"
    end
  end

  describe "the axis" do
    test "a relation's delay sets it, so a six-month gap is not rounded to a year" do
      network =
        Network.new()
        |> Network.add_period(:a, from: ~o"1200Y", to: ~o"1210Y")
        |> Network.add_period(:b, from: {~o"1200Y", ~o"1300Y"})
        |> Network.add_relation({:delay, :end, :start, :at_least, ~o"P6M"}, :a, :b)

      assert Normalize.finest_unit(network) == :month
      assert solved(network, :b).earliest_start == ~o"1210-07"
    end

    test "a network in one calendar counts that calendar's years" do
      period =
        Network.new()
        |> Network.add_period(:a, from: ~o"5784Y[u-ca=hebrew]", duration: ~o"P1Y")
        |> solved(:a)

      assert period.earliest_end == Tempo.new!(year: 5785, calendar: Calendrical.Hebrew)
    end

    test "weeks count in days" do
      period = solved(Network.add_period(Network.new(), :a, duration: ~o"P2W"), :a)
      assert period.min_duration == ~o"P14D"
    end

    test "a bound is the span it names, so the latest start in 1300 is its last day" do
      network =
        Network.new()
        |> Network.add_period(:a, from: {:not_after, ~o"1300Y"})
        |> Network.add_period(:b, from: ~o"1200-06-15")

      assert solved(network, :a).latest_start == ~o"1300-12-31"
    end
  end

  describe "what a network cannot place is an error, not a raise" do
    test "a unit finer than a second" do
      network = Network.add_period(Network.new(), :a, from: ~o"2026-01-05T10:00:00.5")

      assert {:error, %ArgumentError{}} = Solver.propagate(network)
      assert {:error, %ArgumentError{}} = Normalize.normalize(network)
      assert_raise ArgumentError, fn -> Solver.consistent?(network) end

      assert {:error, %ArgumentError{}} =
               Schedule.new()
               |> Schedule.task(:a, duration: ~o"PT0.5S", start: ~o"2026-06-01")
               |> Schedule.solve()
    end

    test "a fraction of the axis unit" do
      network = Network.add_period(Network.new(), :a, from: ~o"1200Y", duration: ~o"P1.5Y")
      assert {:error, %ArgumentError{}} = Solver.propagate(network)
    end

    test "a start nothing bounds, counting another calendar's years" do
      network =
        Network.new()
        |> Network.add_period(:a, from: hebrew(5784, 1, 1))
        |> Network.add_period(:b, duration: ~o"P1Y")

      assert {:error, %ArgumentError{} = error} = Solver.propagate(network)
      assert Exception.message(error) =~ "nothing bounds that start"
    end
  end
end
