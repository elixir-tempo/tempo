defmodule Tempo.Network.HoursTest do
  use ExUnit.Case, async: true

  # A network in hours, minutes or seconds counts on the time line: the
  # wall clock for floating values, UTC for zoned ones. An hour is an hour
  # of elapsed time, and a day or a month is measured by calendar
  # arithmetic in its period's zone, so a day across a daylight-saving
  # change is its 23 or 25 hours.

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.Network
  alias Tempo.Network.Solver
  alias Tempo.Schedule

  defp solved(network, id) do
    {:ok, propagated} = Solver.propagate(network)
    propagated.periods[id]
  end

  defp new_york(iso), do: Tempo.from_iso8601!(iso <> "[America/New_York]")

  describe "a schedule in hours" do
    test "runs each task for its hours and finds the critical path" do
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:design, duration: ~o"PT2H", start: ~o"2026-06-01T09")
        |> Schedule.task(:build, duration: ~o"PT3H", after: :design)
        |> Schedule.task(:docs, duration: ~o"PT1H", after: :design)
        |> Schedule.task(:ship,
          duration: ~o"PT1H",
          after: [:build, :docs],
          deadline: ~o"2026-06-01T15"
        )
        |> Schedule.solve()

      assert Interval.endpoints(plan[:build].early) == {~o"2026-06-01T11", ~o"2026-06-01T14"}
      assert Interval.endpoints(plan[:docs].late) == {~o"2026-06-01T13", ~o"2026-06-01T14"}
      assert Schedule.critical_path(plan) == [:design, :build, :ship]
    end

    test "counts minutes where a task lasts them" do
      period =
        solved(
          Network.add_period(Network.new(), :a, from: ~o"2026-06-01T09:00", duration: ~o"PT90M"),
          :a
        )

      assert period.earliest_end == ~o"2026-06-01T10:30"
    end
  end

  describe "a day or a month in hours is measured" do
    test "a floating day is 24 hours" do
      period =
        solved(
          Network.add_period(Network.new(), :a, from: ~o"2026-03-07T09", duration: ~o"P1D"),
          :a
        )

      assert {period.earliest_end, period.min_duration} == {~o"2026-03-08T09", ~o"PT24H"}
    end

    test "a zoned day across a daylight-saving change is its 23 or 25 hours" do
      spring =
        solved(
          Network.add_period(Network.new(), :a,
            from: new_york("2026-03-07T09"),
            duration: ~o"P1D"
          ),
          :a
        )

      assert Tempo.equal?(spring.earliest_end, new_york("2026-03-08T09"))
      assert spring.min_duration == ~o"PT23H"

      autumn =
        solved(
          Network.add_period(Network.new(), :a,
            from: new_york("2026-10-31T09"),
            duration: ~o"P1D"
          ),
          :a
        )

      assert autumn.min_duration == ~o"PT25H"
    end

    test "a month from 31 January is 28 days of hours" do
      period =
        solved(
          Network.add_period(Network.new(), :a,
            from: new_york("2026-01-31T09"),
            duration: ~o"P1M"
          ),
          :a
        )

      assert Tempo.equal?(period.earliest_end, new_york("2026-02-28T09"))
      assert period.min_duration == ~o"PT672H"
    end

    test "a start free over a week takes each day's hours" do
      period =
        Network.new()
        |> Network.add_period(:a,
          from: {new_york("2026-03-05T00"), new_york("2026-03-11T00")},
          duration: ~o"P1D"
        )
        |> solved(:a)

      assert {period.min_duration, period.max_duration} == {~o"PT23H", ~o"PT24H"}
      assert Tempo.equal?(period.earliest_end, new_york("2026-03-06T00"))
      assert Tempo.equal?(period.latest_end, new_york("2026-03-12T00"))
    end
  end

  describe "hours are elapsed time on the time line" do
    test "two hours from 01:00 on the night the clocks spring forward end at 04:00" do
      period =
        solved(
          Network.add_period(Network.new(), :a,
            from: new_york("2026-03-08T01"),
            duration: ~o"PT2H"
          ),
          :a
        )

      assert Tempo.equal?(period.earliest_end, new_york("2026-03-08T04"))
    end

    test "a half-hour zone and a fixed offset count their own hours" do
      kolkata =
        Network.new()
        |> Network.add_period(:a,
          from: Tempo.from_iso8601!("2026-06-01T10[Asia/Kolkata]"),
          duration: ~o"PT4H"
        )
        |> solved(:a)

      assert Tempo.equal?(
               kolkata.earliest_end,
               Tempo.from_iso8601!("2026-06-01T14[Asia/Kolkata]")
             )

      offset =
        Network.new()
        |> Network.add_period(:a,
          from: Tempo.from_iso8601!("2026-06-01T09+05:30"),
          duration: ~o"PT4H"
        )
        |> solved(:a)

      assert Tempo.equal?(offset.earliest_end, Tempo.from_iso8601!("2026-06-01T13+05:30"))
    end

    test "a zoned bound in another calendar keeps its calendar" do
      jerusalem = Tempo.from_iso8601!("5787-01-01T10:00[Asia/Jerusalem][u-ca=hebrew]")

      period =
        Network.new()
        |> Network.add_period(:a, from: jerusalem, duration: ~o"PT2H")
        |> solved(:a)

      assert period.earliest_end.calendar == Calendrical.Hebrew

      assert Tempo.equal?(
               period.earliest_end,
               Tempo.from_iso8601!("5787-01-01T12:00[Asia/Jerusalem][u-ca=hebrew]")
             )
    end

    test "bounds in two zones share UTC" do
      network =
        Network.new()
        |> Network.add_period(:a,
          from: Tempo.from_iso8601!("2026-06-01T09[Europe/Paris]"),
          duration: ~o"PT2H"
        )
        |> Network.add_period(:b, from: new_york("2026-06-01T09"))

      assert Tempo.equal?(solved(network, :a).earliest_end, Tempo.from_iso8601!("2026-06-01T09Z"))
    end

    test "a day bound in a network of hours is its hours" do
      network =
        Network.new()
        |> Network.add_period(:a, from: {:not_after, ~o"2026-06-01"})
        |> Network.add_period(:b, from: ~o"2026-06-01T09")

      assert solved(network, :a).latest_start == ~o"2026-06-01T23"
    end
  end

  describe "what a network in hours cannot place is an error" do
    test "floating and zoned bounds on one time line" do
      network =
        Network.new()
        |> Network.add_period(:a, from: ~o"2026-06-01T09")
        |> Network.add_period(:b, from: Tempo.from_iso8601!("2026-06-01T09[Europe/Paris]"))

      assert {:error, %ArgumentError{} = error} = Solver.propagate(network)
      assert Exception.message(error) =~ "mix floating values with zoned ones"
    end

    test "a unit finer than a second" do
      network = Network.add_period(Network.new(), :a, from: ~o"2026-06-01T09:00:00.5")

      assert {:error, %ArgumentError{} = error} = Solver.propagate(network)
      assert Exception.message(error) =~ "to the second"
    end

    test "a zoned day nothing bounds, whose hours depend on where it starts" do
      network =
        Network.new()
        |> Network.add_period(:a, from: Tempo.from_iso8601!("2026-06-01T09[Europe/Paris]"))
        |> Network.add_period(:b, duration: ~o"P1D")

      assert {:error, %ArgumentError{} = error} = Solver.propagate(network)
      assert Exception.message(error) =~ "Europe/Paris"
    end
  end
end
