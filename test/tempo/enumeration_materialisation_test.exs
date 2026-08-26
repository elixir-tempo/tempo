defmodule Tempo.EnumerationMaterialisationTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  # Golden-master characterisation net for the enumeration/materialisation
  # unification (see plans/enumerable-unification-plan.md). It pins the
  # current *correct* behaviour so the refactor that merges the two
  # candidate generators cannot regress it. Enumeration ORDER is
  # deliberately not asserted (only count, coverage, and the materialised
  # span) — order is an implementation detail the rewrite may change.

  describe "crisp value" do
    test "drills coarse->fine when enumerated; materialises to one span" do
      assert Enum.count(~o"2020Y") == 12
      assert Enum.member?(~o"2020Y", ~o"2020Y1M")
      assert Enum.member?(~o"2020Y", ~o"2020Y12M")
      assert {:ok, interval} = Tempo.to_interval(~o"2020Y")
      # Bounds keep year resolution; the drill unit travels as data.
      assert inspect(interval) == ~S|#Tempo.Interval<~o"2020Y/2021Y" unit: month>|
    end

    test "day drills to hours" do
      assert Enum.count(~o"2020-06-15") == 24
      assert {:ok, interval} = Tempo.to_interval(~o"2020-06-15")
      assert inspect(interval) == ~S|#Tempo.Interval<~o"2020Y6M15D/16D" unit: hour>|
    end
  end

  describe "masks" do
    test "trailing day mask enumerates only valid days; materialises to the month span" do
      assert Enum.count(~o"2020-06-XX") == 30
      assert Enum.member?(~o"2020-06-XX", ~o"2020Y6M1D")
      assert Enum.member?(~o"2020-06-XX", ~o"2020Y6M30D")
      assert {:ok, interval} = Tempo.to_interval(~o"2020-06-XX")
      assert inspect(interval) == ~S|~o"2020Y6M/7M"|
    end

    test "leap-February day mask stops at 29" do
      assert Enum.count(~o"2020-02-XX") == 29
      assert Enum.count(~o"2019-02-XX") == 28
    end

    test "decade mask enumerates 10 years; materialises to the decade span" do
      assert Enum.count(~o"195X") == 10
      assert {:ok, interval} = Tempo.to_interval(~o"195X")
      assert inspect(interval) == ~S|~o"1950Y/1960Y"|
    end

    test "trailing year+month mask enumerates every month of the century" do
      assert Enum.count(~o"19XX-XX") == 1200
      assert {:ok, interval} = Tempo.to_interval(~o"19XX-XX")
      assert inspect(interval) == ~S|~o"1900Y/2000Y"|
    end

    test "non-contiguous mask materialises to one disjoint interval per valid value" do
      assert {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(~o"1985-XX-15")
      assert length(intervals) == 12
      assert Enum.count(~o"1985-XX-15") == 12
    end
  end
end
