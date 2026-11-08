defmodule Tempo.SetExclusionTest do
  use ExUnit.Case, async: true

  # A set less what its exclusions cover (`^`, or `:except` to
  # `Tempo.IntervalSet.new/2`): its members have what an exclusion covers
  # taken out (decision 105), a piece cut from a member is written to the
  # finer of its resolution and the exclusion's, and a shift moves the
  # exclusions with the members where a rewrite leaves them as written
  # (decision 106).

  import Tempo.Sigils

  alias Tempo.IntervalSet

  defp june_less_the_15th do
    IntervalSet.new!([Tempo.new!(year: 2026, month: 6), Tempo.new!(year: 2026, month: 7)],
      except: [Tempo.new!(year: 2026, month: 6, day: 15)]
    )
  end

  describe "the members of a set with exclusions" do
    test "are its members with what the exclusions cover taken out" do
      assert Tempo.members(june_less_the_15th()) ==
               {:ok, [~o"2026-06-01/2026-06-14", ~o"2026-06-16/2026-06-30", ~o"2026-07"]}

      assert Tempo.members(~o"{2017Y..2022Y,^2020Y}") ==
               {:ok, [~o"2017", ~o"2018", ~o"2019", ~o"2021", ~o"2022"]}

      assert Tempo.members(~o"{2026,2027,^2027}") == {:ok, [~o"2026"]}
    end

    test "are what a set's count, first member and walk give" do
      set = june_less_the_15th()

      assert IntervalSet.count(set) == 3
      assert IntervalSet.first(set) == ~o"2026-06-01/2026-06-14"
      assert Enum.count(set) == 3
      assert IntervalSet.count(~o"{2017Y..2022Y,^2020Y}") == 5
      assert IntervalSet.first(~o"{2017Y..2022Y,^2020Y}") == ~o"2017"
    end

    test "are what a set filtered or mapped is given" do
      longer_than_a_fortnight =
        IntervalSet.filter(june_less_the_15th(), &Tempo.at_least?(&1, ~o"P15D"))

      assert IntervalSet.members(longer_than_a_fortnight) == [
               ~o"2026-06-16/2026-06-30",
               ~o"2026-07"
             ]
    end

    test "are what to_string/1 names" do
      assert Tempo.to_string(~o"{2026-06,^2026-06-15}") ==
               {:ok, "Jun 1 – 14, 2026 and Jun 16 – 30, 2026"}
    end
  end

  describe "a member cut by a finer exclusion" do
    test "is written to the finer of the two resolutions" do
      assert Tempo.to_interval(~o"{2026-06,^2026-06-15}") ==
               {:ok, ~o"{2026-06-01/2026-06-14,2026-06-16/2026-06-30}"}

      assert Tempo.to_interval(~o"{2026Y,^2026-06}") ==
               {:ok, ~o"{2026-01/2026-05,2026-07/2026-12}"}

      assert Tempo.difference(~o"2026", ~o"{2026-06,^2026-06-15}") ==
               {:ok, ~o"{2026Y/5M31D,2026Y6M15D/2026Y6M15D,2026Y7M1D/2026Y}"}
    end

    test "an exclusion of the member's own resolution keeps it" do
      assert Tempo.to_interval(~o"{2017Y..,^2020Y}", within: ~o"2016/2022") ==
               {:ok, ~o"{2017Y/2019Y,2021Y/2022Y}"}
    end
  end

  describe "a set with exclusions measured" do
    test "is the time its members cover less what the exclusions take out" do
      assert Tempo.duration(~o"{2026-06-01/2026-06-30,^2026-06-15}") == ~o"P29D"
      assert Tempo.duration(~o"{2017Y..2022Y,^2020Y}") == ~o"P5Y"
      assert Tempo.duration(~o"{2026Y,^2026-06}") == ~o"P11M"
      assert Tempo.count(june_less_the_15th(), :day) == {:ok, 60}
      assert Tempo.bounded?(june_less_the_15th())
    end

    test "is explained with its exclusions" do
      assert Tempo.explain(~o"{2026Y,^2026-06}") =~
               "A set of one member, all of which it names, less what one exclusion covers."
    end
  end

  describe "a set with exclusions moved or rewritten" do
    test "moves its exclusions with its members" do
      assert Tempo.shift(~o"{2026-06-01/2026-06-30,^2026-06-15}", ~o"P1Y") ==
               {:ok, ~o"{2027-06-01/2027-06-30,^2027-06-15}"}

      assert {:ok, moved} = Tempo.shift(june_less_the_15th(), day: 1)
      assert Tempo.to_iso8601(moved) == {:ok, "{2026Y6M2D,2026Y7M2D,^2026Y6M16D}"}
    end

    test "keeps its exclusions as they are written when its members are rewritten" do
      assert Tempo.trunc(~o"{2026-06-01/2026-06-30,^2026-06-15}", :month) ==
               {:ok, ~o"{2026-06/2026-06,^2026-06-15}"}

      assert Tempo.at_resolution(~o"{2026Y,^2026-06}", :month) == {:ok, ~o"{2026-01,^2026-06}"}
    end
  end
end
