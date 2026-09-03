defmodule Tempo.Interval.RelationsTest do
  @moduledoc """
  `Tempo.Interval.Relations` is an algebra, so most of what is worth
  asserting are its laws. The composition table it builds on is already
  validated cell-for-cell in `Tempo.Interval.CompositionTest`; these tests
  cover the lifting of that table to sets, and the soundness of the
  lifting against real intervals.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.Interval.Relations

  # A generator over non-empty subsets of the thirteen.
  defp relation_set do
    Relations.full()
    |> Enum.map(&constant/1)
    |> one_of()
    |> list_of(min_length: 1, max_length: 5)
    |> map(&Relations.canonical/1)
  end

  describe "canonical/1" do
    test "deduplicates and orders" do
      assert Relations.canonical([:during, :precedes, :during]) == [:precedes, :during]
    end

    test "rejects a relation that is not one of the thirteen" do
      assert Relations.canonical([:precedes, :nonsense]) ==
               {:error, {:invalid_relation, :nonsense}}
    end

    test "two sets asserting the same thing compare equal" do
      assert Relations.canonical([:meets, :precedes]) == Relations.canonical([:precedes, :meets])
    end
  end

  describe "converse/1" do
    test "swaps each relation for its inverse" do
      assert Relations.converse([:precedes, :during]) == [:contains, :preceded_by]
    end

    test "equals is its own converse" do
      assert Relations.converse([:equals]) == [:equals]
    end

    property "is an involution" do
      check all(set <- relation_set()) do
        assert set |> Relations.converse() |> Relations.converse() == set
      end
    end

    property "preserves size" do
      check all(set <- relation_set()) do
        assert length(Relations.converse(set)) == length(set)
      end
    end
  end

  describe "narrow/2" do
    test "keeps what both sources allow" do
      assert Relations.narrow([:precedes, :meets, :overlaps], [:meets, :overlaps, :during]) ==
               [:meets, :overlaps]
    end

    test "contradictory sources narrow to nothing" do
      assert Relations.narrow([:precedes], [:preceded_by]) == []
      assert Relations.empty?(Relations.narrow([:precedes], [:preceded_by]))
    end

    property "the full set is the identity — it asserts nothing" do
      check all(set <- relation_set()) do
        assert Relations.narrow(set, Relations.full()) == set
      end
    end

    property "is idempotent and commutative" do
      check all(a <- relation_set(), b <- relation_set()) do
        assert Relations.narrow(a, a) == a
        assert Relations.narrow(a, b) == Relations.narrow(b, a)
      end
    end

    property "never widens" do
      check all(a <- relation_set(), b <- relation_set()) do
        assert length(Relations.narrow(a, b)) <= length(a)
      end
    end
  end

  describe "compose/2" do
    test "a determined step stays determined" do
      assert Relations.compose([:precedes], [:precedes]) == [:precedes]
    end

    test "an ambiguous step widens" do
      assert Relations.compose([:precedes], [:during]) ==
               [:precedes, :meets, :overlaps, :starts, :during]
    end

    test "a step through an interval that cannot be placed yields nothing" do
      assert Relations.compose([:precedes], []) == []
      assert Relations.compose([], [:precedes]) == []
    end

    property "equals is the identity element" do
      check all(set <- relation_set()) do
        assert Relations.compose(set, [:equals]) == set
        assert Relations.compose([:equals], set) == set
      end
    end

    property "is associative" do
      check all(a <- relation_set(), b <- relation_set(), c <- relation_set()) do
        assert Relations.compose(Relations.compose(a, b), c) ==
                 Relations.compose(a, Relations.compose(b, c))
      end
    end

    property "converse distributes over composition, reversing the order" do
      check all(a <- relation_set(), b <- relation_set()) do
        assert Relations.converse(Relations.compose(a, b)) ==
                 Relations.compose(Relations.converse(b), Relations.converse(a))
      end
    end

    property "is monotone — a wider input never gives a narrower result" do
      check all(a <- relation_set(), b <- relation_set(), c <- relation_set()) do
        wider = Relations.canonical(a ++ c)
        narrower = Relations.compose(a, b)

        assert Enum.all?(narrower, &(&1 in Relations.compose(wider, b)))
      end
    end
  end

  describe "soundness against real intervals" do
    # The composition of two known relations must admit the relation that
    # actually holds. Three grounded intervals give an independent oracle:
    # whatever `relation/2` says about A→C has to be in the composition of
    # A→B and B→C.
    @intervals [
      ~o"2026-06-01/2026-06-10",
      ~o"2026-06-05/2026-06-15",
      ~o"2026-06-10/2026-06-20",
      ~o"2026-06-01/2026-06-20",
      ~o"2026-06-12/2026-06-14",
      ~o"2026-06-20/2026-06-25"
    ]

    test "composition admits the relation that actually holds" do
      for a <- @intervals, b <- @intervals, c <- @intervals do
        ab = Interval.relation(a, b)
        bc = Interval.relation(b, c)
        ac = Interval.relation(a, c)

        possible = Relations.compose([ab], [bc])

        assert ac in possible,
               """
               composition was unsound:
                 A→B #{inspect(ab)}, B→C #{inspect(bc)} gave #{inspect(possible)}
                 but A→C is actually #{inspect(ac)}
               """
      end
    end

    test "narrowing by the truth never empties a sound composition" do
      for a <- @intervals, b <- @intervals, c <- @intervals do
        possible = Relations.compose([Interval.relation(a, b)], [Interval.relation(b, c)])

        refute Relations.empty?(Relations.narrow(possible, [Interval.relation(a, c)]))
      end
    end
  end

  describe "errors" do
    test "every operation reports an invalid relation rather than guessing" do
      assert Relations.converse([:nonsense]) == {:error, {:invalid_relation, :nonsense}}

      assert Relations.narrow([:nonsense], [:precedes]) ==
               {:error, {:invalid_relation, :nonsense}}

      assert Relations.compose([:precedes], [:nonsense]) ==
               {:error, {:invalid_relation, :nonsense}}
    end
  end
end
