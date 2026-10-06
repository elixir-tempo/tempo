defmodule Tempo.ScheduleTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  doctest Tempo.Schedule

  alias Tempo.Interval
  alias Tempo.Schedule
  alias Tempo.Schedule.ScheduledTask

  # design(2d) → build(3d), design → docs(1d), build+docs → ship(2d),
  # anchored at 2026-06-01, ship due 2026-06-08.
  defp plan do
    {:ok, plan} =
      Schedule.new()
      |> Schedule.task(:design, duration: ~o"P2D", start: ~o"2026-06-01")
      |> Schedule.task(:build, duration: ~o"P3D", after: :design)
      |> Schedule.task(:docs, duration: ~o"P1D", after: :design)
      |> Schedule.task(:ship, duration: ~o"P2D", after: [:build, :docs], deadline: ~o"2026-06-08")
      |> Schedule.solve()

    plan
  end

  describe "solve/1 — the schedule" do
    test "each task is placed at its earliest feasible position" do
      plan = plan()
      assert %ScheduledTask{id: :design} = plan[:design]
      assert Interval.endpoints(plan[:design].early) == {~o"2026-06-01", ~o"2026-06-03"}
      assert Interval.endpoints(plan[:build].early) == {~o"2026-06-03", ~o"2026-06-06"}
      assert Interval.from(plan[:docs].early) == ~o"2026-06-03"
      assert Interval.endpoints(plan[:ship].early) == {~o"2026-06-06", ~o"2026-06-08"}
    end

    test "a finish-to-start dependency may leave a gap, not just abut" do
      # docs (1 day) finishes 06-04 but ship can't start until build
      # finishes 06-06 — a two-day gap after docs.
      plan = plan()
      assert Interval.to(plan[:docs].early) == ~o"2026-06-04"
      assert Interval.from(plan[:ship].early) == ~o"2026-06-06"
    end
  end

  describe "critical path and slack" do
    test "the critical path is the zero-slack chain in start order" do
      assert Schedule.critical_path(plan()) == [:design, :build, :ship]
    end

    test "a task off the critical path has slack (early < late start)" do
      docs = plan()[:docs]
      refute docs.critical?
      # docs can start as late as 06-05 (so it still finishes by the
      # time ship needs it) yet schedules early at 06-03.
      assert Interval.from(docs.early) == ~o"2026-06-03"
      assert Interval.endpoints(docs.late) == {~o"2026-06-05", ~o"2026-06-06"}
    end

    test "critical tasks have coincident early and late schedules" do
      build = plan()[:build]
      assert build.critical?
      assert build.early == build.late
    end
  end

  describe "span/1" do
    test "covers the whole project from earliest start to latest finish" do
      span = Schedule.span(plan())
      assert Interval.endpoints(span) == {~o"2026-06-01", ~o"2026-06-08"}
    end

    test "a plan with no tasks, or none placed on the calendar, has no span" do
      assert {:error, %Tempo.IntervalEndpointsError{}} = Schedule.span(%{})

      {:ok, relative} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P2D")
        |> Schedule.task(:b, duration: ~o"P2D", after: :a)
        |> Schedule.solve()

      assert relative[:a].early == nil
      assert {:error, %Tempo.IntervalEndpointsError{} = error} = Schedule.span(relative)
      assert Exception.message(error) =~ "no fixed start or :not_before date"
    end
  end

  describe "bounds and feasibility" do
    test "an over-tight deadline is infeasible" do
      result =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P5D", start: ~o"2026-06-01", deadline: ~o"2026-06-03")
        |> Schedule.solve()

      assert result == {:error, :infeasible}
    end

    test ":not_before holds a task back" do
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P1D", not_before: ~o"2026-06-10")
        |> Schedule.solve()

      assert Interval.from(plan[:a].early) == ~o"2026-06-10"
    end

    test ":within bounds both ends" do
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P2D", within: ~o"2026-06-01/2026-06-10")
        |> Schedule.solve()

      assert Interval.from(plan[:a].early) == ~o"2026-06-01"
      assert Interval.to(plan[:a].late) == ~o"2026-06-10"
    end

    test ":within takes a value as its window, as every :within does" do
      # A task done in June starts no earlier than the month does and
      # finishes no later than it ends.
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P2D", within: ~o"2026-06")
        |> Schedule.solve()

      assert Interval.from(plan[:a].early) == ~o"2026-06-01"
      assert Interval.to(plan[:a].late) == ~o"2026-07-01"
    end

    test "an anchored task is critical (pinned); a downstream task with no deadline is undetermined" do
      # An anchored task has zero slack — it cannot move. A task whose
      # latest start nothing bounds (no deadline downstream) reports nil.
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P2D", start: ~o"2026-06-01")
        |> Schedule.task(:b, duration: ~o"P3D", after: :a)
        |> Schedule.solve()

      assert plan[:a].critical? == true
      assert plan[:b].critical? == nil
      assert plan[:b].late == nil
      assert Schedule.critical_path(plan) == [:a]
    end

    test "a relative schedule of day-length tasks measures in days (not the year axis)" do
      # With no dates at all the network's durations fix the axis, so a
      # 3-task day chain spans the right number of days.
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P2D", start: ~o"2026-06-01")
        |> Schedule.task(:b, duration: ~o"P2D", after: :a)
        |> Schedule.task(:c, duration: ~o"P2D", after: :b)
        |> Schedule.solve()

      assert Interval.to(plan[:c].early) == ~o"2026-06-07"
    end

    test "a cyclic dependency is infeasible" do
      result =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P1D", start: ~o"2026-06-01", after: :b)
        |> Schedule.task(:b, duration: ~o"P1D", after: :a)
        |> Schedule.solve()

      assert result == {:error, :infeasible}
    end
  end

  describe "an option task/3 cannot read is an error from solve/1, not a raise" do
    defp solve_with(options) do
      Schedule.new()
      |> Schedule.task(:a, [{:duration, ~o"P1D"} | options])
      |> Schedule.solve()
    end

    test "a 1.x :earliest names :not_before" do
      assert {:error, %ArgumentError{} = error} = solve_with(earliest: ~o"2026-06-10")
      assert Exception.message(error) =~ "takes :not_before where 1.x took :earliest"
    end

    test "an option it does not take, or options that are not a keyword list" do
      assert {:error, %ArgumentError{} = error} = solve_with(finish: ~o"2026-06-10")
      assert Exception.message(error) =~ "does not take :finish"

      assert {:error, %ArgumentError{}} =
               Schedule.new() |> Schedule.task(:a, :duration) |> Schedule.solve()
    end

    test "a :within that is no window" do
      assert {:error, %ArgumentError{} = error} = solve_with(within: ~o"2026-06/..")
      assert Exception.message(error) =~ "takes :within as a window with a start and an end"

      assert {:error, %ArgumentError{}} = solve_with(within: "June")
    end

    test "a :within written as the pair 1.x took names the window" do
      assert {:error, %ArgumentError{} = error} =
               solve_with(within: {~o"2026-06-01", ~o"2026-06-10"})

      assert Exception.message(error) =~ "where 1.x took a {from, to} pair"
    end

    test "a date or a duration it cannot read" do
      assert {:error, %ArgumentError{}} = solve_with(start: "not a date")
      assert {:error, %ArgumentError{}} = solve_with(deadline: :tomorrow)

      assert {:error, %ArgumentError{}} =
               Schedule.new() |> Schedule.task(:a, duration: "two days") |> Schedule.solve()
    end
  end
end
