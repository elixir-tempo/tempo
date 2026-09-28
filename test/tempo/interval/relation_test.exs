defmodule Tempo.Interval.CompareTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Allen
  alias Tempo.Interval
  alias Tempo.IntervalSet

  # Fixtures. Each interval is a day-resolution span. Anchor Y
  # around an arbitrary reference interval so every Allen
  # relation has a concrete example.
  #
  #                     J 3 — J 5 — J 7 — J 9 — J 11 — J 13
  # Y (reference):            [——————————————————)
  # X candidates built relative to Y.

  @y %Interval{from: ~o"2026-06-05", to: ~o"2026-06-11"}

  describe "relation/2 — 13 Allen relations" do
    test ":precedes — X ends strictly before Y starts" do
      x = %Interval{from: ~o"2026-06-01", to: ~o"2026-06-03"}
      assert Interval.relation(x, @y) == :precedes
    end

    test ":meets — X ends exactly at Y's start (half-open adjacency)" do
      x = %Interval{from: ~o"2026-06-01", to: ~o"2026-06-05"}
      assert Interval.relation(x, @y) == :meets
    end

    test ":overlaps — X starts before Y, ends inside Y" do
      x = %Interval{from: ~o"2026-06-03", to: ~o"2026-06-07"}
      assert Interval.relation(x, @y) == :overlaps
    end

    test ":finished_by — X contains Y, shared end" do
      x = %Interval{from: ~o"2026-06-03", to: ~o"2026-06-11"}
      assert Interval.relation(x, @y) == :finished_by
    end

    test ":contains — X strictly contains Y" do
      x = %Interval{from: ~o"2026-06-03", to: ~o"2026-06-13"}
      assert Interval.relation(x, @y) == :contains
    end

    test ":starts — shared start, X ends earlier" do
      x = %Interval{from: ~o"2026-06-05", to: ~o"2026-06-09"}
      assert Interval.relation(x, @y) == :starts
    end

    test ":equals — identical endpoints" do
      x = %Interval{from: ~o"2026-06-05", to: ~o"2026-06-11"}
      assert Interval.relation(x, @y) == :equals
    end

    test ":started_by — shared start, X ends later" do
      x = %Interval{from: ~o"2026-06-05", to: ~o"2026-06-13"}
      assert Interval.relation(x, @y) == :started_by
    end

    test ":during — X strictly inside Y" do
      x = %Interval{from: ~o"2026-06-07", to: ~o"2026-06-09"}
      assert Interval.relation(x, @y) == :during
    end

    test ":finishes — X starts after Y, shared end" do
      x = %Interval{from: ~o"2026-06-07", to: ~o"2026-06-11"}
      assert Interval.relation(x, @y) == :finishes
    end

    test ":overlapped_by — Y starts before X, ends inside X" do
      x = %Interval{from: ~o"2026-06-09", to: ~o"2026-06-15"}
      assert Interval.relation(x, @y) == :overlapped_by
    end

    test ":met_by — X starts exactly at Y's end" do
      x = %Interval{from: ~o"2026-06-11", to: ~o"2026-06-15"}
      assert Interval.relation(x, @y) == :met_by
    end

    test ":preceded_by — X starts strictly after Y's end" do
      x = %Interval{from: ~o"2026-06-13", to: ~o"2026-06-15"}
      assert Interval.relation(x, @y) == :preceded_by
    end
  end

  describe "Allen.inverse/1 — every relation and its inverse" do
    test "every pair round-trips via inverse" do
      # For every pair of intervals (X, Y), compare(Y, X) must
      # equal inverse(compare(X, Y)). Walk every case once.
      pairs = [
        {%Interval{from: ~o"2026-06-01", to: ~o"2026-06-03"}, :precedes},
        {%Interval{from: ~o"2026-06-01", to: ~o"2026-06-05"}, :meets},
        {%Interval{from: ~o"2026-06-03", to: ~o"2026-06-07"}, :overlaps},
        {%Interval{from: ~o"2026-06-03", to: ~o"2026-06-11"}, :finished_by},
        {%Interval{from: ~o"2026-06-03", to: ~o"2026-06-13"}, :contains},
        {%Interval{from: ~o"2026-06-05", to: ~o"2026-06-09"}, :starts},
        {%Interval{from: ~o"2026-06-05", to: ~o"2026-06-11"}, :equals},
        {%Interval{from: ~o"2026-06-05", to: ~o"2026-06-13"}, :started_by},
        {%Interval{from: ~o"2026-06-07", to: ~o"2026-06-09"}, :during},
        {%Interval{from: ~o"2026-06-07", to: ~o"2026-06-11"}, :finishes},
        {%Interval{from: ~o"2026-06-09", to: ~o"2026-06-15"}, :overlapped_by},
        {%Interval{from: ~o"2026-06-11", to: ~o"2026-06-15"}, :met_by},
        {%Interval{from: ~o"2026-06-13", to: ~o"2026-06-15"}, :preceded_by}
      ]

      for {x, expected} <- pairs do
        # Sanity: the forward relation matches the expectation.
        assert Interval.relation(x, @y) == expected,
               "expected compare(x, y) == #{inspect(expected)} for X=#{inspect(x.from)}..#{inspect(x.to)}"

        # Inverse round-trip: compare(y, x) == inverse(expected).
        assert Interval.relation(@y, x) == Allen.inverse(expected),
               "expected compare(y, x) == inverse(#{inspect(expected)}) for X=#{inspect(x.from)}..#{inspect(x.to)}"
      end
    end

    test "inverse is self-symmetric — inverse(inverse(r)) == r" do
      for r <- [
            :precedes,
            :meets,
            :overlaps,
            :finished_by,
            :contains,
            :starts,
            :equals,
            :started_by,
            :during,
            :finishes,
            :overlapped_by,
            :met_by,
            :preceded_by
          ] do
        assert Allen.inverse(Allen.inverse(r)) == r
      end
    end

    test ":equals is its own inverse" do
      assert Allen.inverse(:equals) == :equals
    end

    test "an unknown relation is an error" do
      assert Allen.inverse(:nonsense) == {:error, {:invalid_relation, :nonsense}}
    end
  end

  describe "relation/2 — input coercion" do
    test "accepts Tempo points (materialised via implicit span)" do
      # ~o"2026Y" contains ~o"2026-06-15".
      assert Interval.relation(~o"2026Y", ~o"2026-06-15") == :contains
    end

    test "day + next day meets under half-open convention" do
      assert Interval.relation(~o"2026-06-15", ~o"2026-06-16") == :meets
    end

    test "single-member IntervalSet is accepted" do
      a =
        IntervalSet.new!([%Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}],
          coalesce: false
        )

      b = %Interval{from: ~o"2026-06-05", to: ~o"2026-06-15"}

      assert Interval.relation(a, b) == :overlaps
    end

    test "multi-member IntervalSet returns an explanatory error" do
      set =
        IntervalSet.new!(
          [
            %Interval{from: ~o"2026-06-01", to: ~o"2026-06-03"},
            %Interval{from: ~o"2026-06-05", to: ~o"2026-06-07"}
          ],
          coalesce: false
        )

      b = %Interval{from: ~o"2026-06-04", to: ~o"2026-06-06"}

      assert {:error, %ArgumentError{} = error} = Interval.relation(set, b)
      assert Exception.message(error) =~ "IntervalSet with 2 members"
      assert Exception.message(error) =~ "relation_matrix"
    end
  end

  describe "Tempo.relation/2 — top-level delegate" do
    test "delegates to Tempo.Interval.relation/2" do
      a = %Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}
      b = %Interval{from: ~o"2026-06-05", to: ~o"2026-06-15"}

      assert Tempo.relation(a, b) == :overlaps
    end
  end

  describe "Tempo.IntervalSet.relation_matrix/2" do
    test "full per-pair relation listing" do
      a =
        IntervalSet.new!(
          [
            %Interval{from: ~o"2026-06-01", to: ~o"2026-06-03"},
            %Interval{from: ~o"2026-06-05", to: ~o"2026-06-07"}
          ],
          coalesce: false
        )

      b =
        IntervalSet.new!(
          [
            %Interval{from: ~o"2026-06-04", to: ~o"2026-06-06"}
          ],
          coalesce: false
        )

      assert IntervalSet.relation_matrix(a, b) == [
               {0, 0, :precedes},
               {1, 0, :overlapped_by}
             ]
    end

    test "empty sets yield an empty matrix" do
      empty = IntervalSet.new!([], coalesce: false)

      assert IntervalSet.relation_matrix(empty, empty) == []
    end

    test "coerces a bare Interval to a single-member set" do
      a = %Interval{from: ~o"2026-06-01", to: ~o"2026-06-05"}

      b =
        IntervalSet.new!(
          [
            %Interval{from: ~o"2026-06-03", to: ~o"2026-06-07"},
            %Interval{from: ~o"2026-06-10", to: ~o"2026-06-12"}
          ],
          coalesce: false
        )

      assert [{0, 0, :overlaps}, {0, 1, :precedes}] =
               IntervalSet.relation_matrix(a, b)
    end
  end
end
