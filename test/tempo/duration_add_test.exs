defmodule Tempo.DurationAddTest do
  @moduledoc """
  `Tempo.Duration.add/2` and `sum/1` — component-wise duration
  addition with fractional-second carry.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Duration

  describe "add/2" do
    test "like units sum without conversion" do
      assert Duration.add(~o"PT7H30M", ~o"PT6H") == ~o"PT13H30M"
      assert Duration.add(~o"P1Y", ~o"P2M3D") == ~o"P1Y2M3D"
    end

    test "week components stay weeks" do
      assert Duration.add(~o"P1W", ~o"P2W") == ~o"P3W"
    end

    test "calendar units never convert into each other" do
      # Twelve months do not become a year — no reference date, no conversion.
      assert Duration.add(~o"P6M", ~o"P6M") == ~o"P12M"
    end

    test "a duration and its negation cancel to the zero duration" do
      assert Duration.add(~o"PT1H30M", Duration.negate(~o"PT1H30M")).time == []
    end

    test "mixed-sign components subtract" do
      assert Duration.add(~o"PT3H", Duration.negate(~o"PT1H")) == ~o"PT2H"
    end

    test "fractional seconds carry into whole seconds" do
      assert Duration.add(~o"PT1.5S", ~o"PT0.7S") == ~o"PT2.2S"
    end

    test "a negative fractional sum carries negatively" do
      result = Duration.add(~o"PT0.3S", Duration.negate(~o"PT1.5S"))
      assert result.time == [second: -1, microsecond: {-200_000, 1}]
    end
  end

  describe "sum/1" do
    test "a timesheet's entries sum to the total" do
      assert Duration.sum([~o"PT7H30M", ~o"PT6H", ~o"PT8H"]) == ~o"PT21H30M"

      assert Duration.to_unit(Duration.sum([~o"PT7H30M", ~o"PT6H", ~o"PT8H"]), :hour) ==
               {:ok, 21.5}
    end

    test "an empty list sums to the zero duration" do
      assert Duration.sum([]).time == []
    end

    test "a single member sums to itself" do
      assert Duration.sum([~o"PT45M"]) == ~o"PT45M"
    end

    test "a non-duration member raises" do
      assert_raise FunctionClauseError, fn -> Duration.sum([~o"PT1H", ~o"2026-06-15"]) end
    end
  end

  describe "negative fractional seconds round-trip" do
    test "negate renders with a single leading sign" do
      assert inspect(Duration.negate(~o"PT1.5S")) == ~s(~o"PT-1.5S")
      assert Tempo.to_iso8601(Duration.negate(~o"PT1.5S")) == "PT-1.5S"
    end

    test "PT-1.5S means minus one and a half seconds" do
      assert Duration.to_unit(~o"PT-1.5S", :second) == {:ok, -1.5}
      assert ~o"PT-1.5S" == Duration.negate(~o"PT1.5S")
    end

    test "a sub-second negative keeps its sign through the round-trip" do
      assert ~o"PT-0.2S".time == [second: 0, microsecond: {-200_000, 1}]
      assert Tempo.to_iso8601(~o"PT-0.2S") == "PT-0.2S"
    end

    test "a leading direction sign negates every component including the fraction" do
      assert Duration.to_unit(~o"-PT1.5S", :second) == {:ok, -1.5}
      assert ~o"-P1DT2H".time == [day: -1, hour: -2]
    end

    test "fraction precision survives the round-trip" do
      assert Tempo.to_iso8601(~o"PT1.250S") == "PT1.250S"
    end

    test "the zero duration renders as PT0S and re-parses" do
      assert Tempo.to_iso8601(Duration.sum([])) == "PT0S"
      assert inspect(Duration.sum([])) == ~s(~o"PT0S")
      assert {:ok, _zero} = Tempo.from_iso8601("PT0S")
    end
  end
end
