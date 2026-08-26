defmodule Tempo.CoreCoverageTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError
  alias Tempo.MaterialisationError

  describe "duration predicates (delegated to Tempo.Interval)" do
    @one_day ~o"2020Y1M1D/2D"

    test "at_most? / exactly?" do
      assert Tempo.at_most?(@one_day, ~o"P1D")
      assert Tempo.exactly?(@one_day, ~o"P1D")
    end

    test "longer_than? / shorter_than?" do
      assert Tempo.longer_than?(@one_day, ~o"PT1H")
      assert Tempo.shorter_than?(@one_day, ~o"P2D")
    end
  end

  describe "Allen relation predicates (delegated to Tempo.Interval)" do
    test "before? / after? hold across a gap" do
      assert Tempo.before?(~o"2020Y", ~o"2022Y")
      assert Tempo.after?(~o"2022Y", ~o"2020Y")
    end

    test "meets? holds for adjacent spans" do
      assert Tempo.meets?(~o"2020Y/2021Y", ~o"2021Y/2022Y")
    end

    test "during? holds for a contained span" do
      assert Tempo.during?(~o"2020Y6M", ~o"2020Y")
    end
  end

  describe "working-day helpers in their default-territory form" do
    test "workdays/0 returns Monday–Friday" do
      assert inspect(Tempo.workdays()) == ~s|~o"{1,2,3,4,5}K"|
    end

    test "weekend? / workday?" do
      assert Tempo.weekend?(~o"2026-06-13")
      assert Tempo.workday?(~o"2026-06-15")
    end

    test "arithmetic skips the weekend" do
      assert Tempo.add_working_days(~o"2026-06-12", 1) == ~o"2026-06-15"
      assert Tempo.next_working_day(~o"2026-06-12") == ~o"2026-06-15"
      assert Tempo.previous_working_day(~o"2026-06-15") == ~o"2026-06-12"
    end

    test "working_days_in counts business days in an interval" do
      assert Tempo.working_days_in(~o"2026-06-15/2026-06-20") == 5
    end
  end

  describe "map/2 and try_map/2 collect into an IntervalSet" do
    @july4 [~o"2025-07-04", ~o"2026-07-04", ~o"2027-07-04"]

    defp member_dates(set) do
      set
      |> IntervalSet.to_list()
      |> Enum.map(fn iv -> {iv.from.time[:month], iv.from.time[:day]} end)
    end

    test "map returns an IntervalSet, one member per element" do
      observed = Tempo.map(@july4, &Tempo.nearest_working_day(&1, :US))
      assert %IntervalSet{} = observed
      # July 4 stays (Fri), rolls to Fri 3 (from Sat), Mon 5 (from Sun).
      assert member_dates(observed) == [{7, 4}, {7, 3}, {7, 5}]
    end

    test "try_map returns {:ok, set} when every element resolves" do
      assert {:ok, set} = Tempo.try_map(@july4, &Tempo.nearest_working_day(&1, :US))
      assert member_dates(set) == [{7, 4}, {7, 3}, {7, 5}]
    end

    test "try_map halts at the first un-materialisable value" do
      assert {:error, %MaterialisationError{reason: :bare_duration}} =
               Tempo.try_map([~o"2025-07-04", ~o"P1D"], & &1)
    end

    test "map raises on an un-materialisable value" do
      assert_raise MaterialisationError, fn -> Tempo.map([~o"P1D"], & &1) end
    end
  end

  describe "bang functions raise on invalid input" do
    test "new!/1 raises on an out-of-range component" do
      assert_raise InvalidDateError, fn -> Tempo.new!(year: 2020, month: 13) end
    end

    test "parse!/2 raises on an unparseable string" do
      assert_raise Calendrical.ParseError, fn -> Tempo.parse!("@@@") end
    end
  end
end
