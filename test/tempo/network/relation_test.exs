defmodule Tempo.Network.RelationTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval.Relations
  alias Tempo.Network.Relation

  describe "to_atomic/1 — qualitative relations" do
    test "before / after are strict on the integer scale" do
      assert Relation.new(:before, :a, :b) |> Relation.to_atomic() ==
               [{{:end, :a}, {:start, :b}, -1}]

      assert Relation.new(:after, :a, :b) |> Relation.to_atomic() ==
               [{{:end, :b}, {:start, :a}, -1}]
    end

    test "contemporary requires a non-empty overlap" do
      assert Relation.new(:contemporary, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :b}, {:end, :a}, 0}, {{:start, :a}, {:end, :b}, 0}]
    end

    test "includes and included_in are duals" do
      assert Relation.new(:includes, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :a}, {:start, :b}, 0}, {{:end, :b}, {:end, :a}, 0}]

      assert Relation.new(:included_in, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :b}, {:start, :a}, 0}, {{:end, :a}, {:end, :b}, 0}]
    end

    test "equals constrains both boundaries (four edges)" do
      atomics = Relation.new(:equals, :a, :b) |> Relation.to_atomic()

      assert atomics == [
               {{:start, :a}, {:start, :b}, 0},
               {{:start, :b}, {:start, :a}, 0},
               {{:end, :a}, {:end, :b}, 0},
               {{:end, :b}, {:end, :a}, 0}
             ]
    end

    test "synchronous_start / synchronous_end pin one shared boundary" do
      assert Relation.new(:synchronous_start, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :a}, {:start, :b}, 0}, {{:start, :b}, {:start, :a}, 0}]

      assert Relation.new(:synchronous_end, :a, :b) |> Relation.to_atomic() ==
               [{{:end, :a}, {:end, :b}, 0}, {{:end, :b}, {:end, :a}, 0}]
    end

    test "overlaps is non-strict per the paper (start ≤ start ≤ end ≤ end)" do
      assert Relation.new(:overlaps, :a, :b) |> Relation.to_atomic() ==
               [
                 {{:start, :a}, {:start, :b}, 0},
                 {{:start, :b}, {:end, :a}, 0},
                 {{:end, :a}, {:end, :b}, 0}
               ]
    end

    test "starts_during places A's start inside B" do
      # start(B) ≤ start(A) ≤ end(B)
      assert Relation.new(:starts_during, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :b}, {:start, :a}, 0}, {{:start, :a}, {:end, :b}, 0}]
    end

    test "ends_during places A's end inside B" do
      # start(B) ≤ end(A) ≤ end(B)
      assert Relation.new(:ends_during, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :b}, {:end, :a}, 0}, {{:end, :a}, {:end, :b}, 0}]
    end

    test "starts / started_by share a start and order the ends (Allen starts)" do
      # start(A) = start(B) ∧ end(A) ≤ end(B)
      assert Relation.new(:starts, :a, :b) |> Relation.to_atomic() ==
               [
                 {{:start, :a}, {:start, :b}, 0},
                 {{:start, :b}, {:start, :a}, 0},
                 {{:end, :a}, {:end, :b}, 0}
               ]

      # start(A) = start(B) ∧ end(B) ≤ end(A)
      assert Relation.new(:started_by, :a, :b) |> Relation.to_atomic() ==
               [
                 {{:start, :a}, {:start, :b}, 0},
                 {{:start, :b}, {:start, :a}, 0},
                 {{:end, :b}, {:end, :a}, 0}
               ]
    end

    test "finishes / finished_by share an end and order the starts (Allen finishes)" do
      # end(A) = end(B) ∧ start(B) ≤ start(A)
      assert Relation.new(:finishes, :a, :b) |> Relation.to_atomic() ==
               [
                 {{:end, :a}, {:end, :b}, 0},
                 {{:end, :b}, {:end, :a}, 0},
                 {{:start, :b}, {:start, :a}, 0}
               ]

      # end(A) = end(B) ∧ start(A) ≤ start(B)
      assert Relation.new(:finished_by, :a, :b) |> Relation.to_atomic() ==
               [
                 {{:end, :a}, {:end, :b}, 0},
                 {{:end, :b}, {:end, :a}, 0},
                 {{:start, :a}, {:start, :b}, 0}
               ]
    end

    test "strictly_contemporary requires a non-empty interior overlap" do
      # start(B) < end(A) ∧ start(A) < end(B)
      assert Relation.new(:strictly_contemporary, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :b}, {:end, :a}, -1}, {{:start, :a}, {:end, :b}, -1}]
    end
  end

  # Each relation is said in words in the module's documentation, and is
  # what the constraints it becomes say of two periods' boundaries. The
  # words are written here as comparisons of whole numbers, and held against
  # the constraints for every pair of periods that starts and ends within
  # five steps: a relation and its dual that were swapped, or a boundary
  # that was the wrong one, would hold of other pairs.
  describe "to_atomic/1 — every relation, of every pair of small periods" do
    @in_words %{
      contemporary: &__MODULE__.contemporary?/4,
      strictly_contemporary: &__MODULE__.strictly_contemporary?/4,
      includes: &__MODULE__.includes?/4,
      included_in: &__MODULE__.included_in?/4,
      overlaps: &__MODULE__.overlaps?/4,
      overlapped_by: &__MODULE__.overlapped_by?/4,
      starts_during: &__MODULE__.starts_during?/4,
      includes_start: &__MODULE__.includes_start?/4,
      ends_during: &__MODULE__.ends_during?/4,
      includes_end: &__MODULE__.includes_end?/4,
      before: &__MODULE__.before?/4,
      after: &__MODULE__.after?/4,
      immediately_precedes: &__MODULE__.immediately_precedes?/4,
      immediately_follows: &__MODULE__.immediately_follows?/4,
      synchronous_start: &__MODULE__.synchronous_start?/4,
      synchronous_end: &__MODULE__.synchronous_end?/4,
      equals: &__MODULE__.equals?/4,
      starts: &__MODULE__.starts?/4,
      started_by: &__MODULE__.started_by?/4,
      finishes: &__MODULE__.finishes?/4,
      finished_by: &__MODULE__.finished_by?/4
    }

    test "holds where its words do" do
      periods = for from <- 0..4, to <- 0..4, from < to, do: {from, to}

      for {type, in_words?} <- @in_words, {a1, a2} <- periods, {b1, b2} <- periods do
        boundaries = %{{:start, :a} => a1, {:end, :a} => a2, {:start, :b} => b1, {:end, :b} => b2}

        # A constraint `{x, y, k}` says x is no more than k after y.
        holds? =
          type
          |> Relation.new(:a, :b)
          |> Relation.to_atomic()
          |> Enum.all?(fn {x, y, k} -> boundaries[x] - boundaries[y] <= k end)

        assert {type, {a1, a2}, {b1, b2}, holds?} ==
                 {type, {a1, a2}, {b1, b2}, in_words?.(a1, a2, b1, b2)}
      end
    end
  end

  # A and B overlap; and by more than a boundary they share.
  def contemporary?(a1, a2, b1, b2), do: b1 <= a2 and a1 <= b2
  def strictly_contemporary?(a1, a2, b1, b2), do: b1 < a2 and a1 < b2

  # A contains B, and is contained by it.
  def includes?(a1, a2, b1, b2), do: a1 <= b1 and b2 <= a2
  def included_in?(a1, a2, b1, b2), do: b1 <= a1 and a2 <= b2

  # A overlaps B and comes first, and comes after.
  def overlaps?(a1, a2, b1, b2), do: a1 <= b1 and b1 <= a2 and a2 <= b2
  def overlapped_by?(a1, a2, b1, b2), do: b1 <= a1 and a1 <= b2 and b2 <= a2

  # A's start is within B, and B's within A; then their ends.
  def starts_during?(a1, _a2, b1, b2), do: b1 <= a1 and a1 <= b2
  def includes_start?(a1, a2, b1, _b2), do: a1 <= b1 and b1 <= a2
  def ends_during?(_a1, a2, b1, b2), do: b1 <= a2 and a2 <= b2
  def includes_end?(a1, a2, _b1, b2), do: a1 <= b2 and b2 <= a2

  # A is over before B starts, and the dual.
  def before?(_a1, a2, b1, _b2), do: a2 < b1
  def after?(a1, _a2, _b1, b2), do: b2 < a1

  # A ends where B starts, and starts where B ends.
  def immediately_precedes?(_a1, a2, b1, _b2), do: a2 == b1
  def immediately_follows?(a1, _a2, _b1, b2), do: a1 == b2

  # A boundary shared.
  def synchronous_start?(a1, _a2, b1, _b2), do: a1 == b1
  def synchronous_end?(_a1, a2, _b1, b2), do: a2 == b2
  def equals?(a1, a2, b1, b2), do: a1 == b1 and a2 == b2

  # A start shared, A ending no later, and no earlier; then an end shared.
  def starts?(a1, a2, b1, b2), do: a1 == b1 and a2 <= b2
  def started_by?(a1, a2, b1, b2), do: a1 == b1 and b2 <= a2
  def finishes?(a1, a2, b1, b2), do: a2 == b2 and b1 <= a1
  def finished_by?(a1, a2, b1, b2), do: a2 == b2 and a1 <= b1

  describe "to_atomic/1 — boundary comparisons" do
    test "the five comparisons cover the boundary lattice" do
      # end(A) < start(B) — strict before.
      assert Relation.new({:boundary, :end, :before, :start}, :a, :b) |> Relation.to_atomic() ==
               [{{:end, :a}, {:start, :b}, -1}]

      # end(A) ≤ start(B).
      assert Relation.new({:boundary, :end, :at_or_before, :start}, :a, :b)
             |> Relation.to_atomic() == [{{:end, :a}, {:start, :b}, 0}]

      # start(A) = start(B).
      assert Relation.new({:boundary, :start, :coincident, :start}, :a, :b)
             |> Relation.to_atomic() ==
               [{{:start, :a}, {:start, :b}, 0}, {{:start, :b}, {:start, :a}, 0}]

      # start(A) ≥ start(B).
      assert Relation.new({:boundary, :start, :at_or_after, :start}, :a, :b)
             |> Relation.to_atomic() == [{{:start, :b}, {:start, :a}, 0}]

      # start(A) > end(B) — strict after.
      assert Relation.new({:boundary, :start, :after, :end}, :a, :b) |> Relation.to_atomic() ==
               [{{:end, :b}, {:start, :a}, -1}]
    end
  end

  describe "to_atomic/1 — metric (delay) relations" do
    test "exactly emits both directions" do
      relation = Relation.new({:delay, :end, :start, :exactly, ~o"P10Y"}, :a, :b)

      assert Relation.to_atomic(relation) == [
               {{:start, :b}, {:end, :a}, {:duration, ~o"P10Y"}},
               {{:end, :a}, {:start, :b}, {:neg_duration, ~o"P10Y"}}
             ]
    end

    test "at_least is a single lower-bound edge" do
      relation = Relation.new({:delay, :start, :start, :at_least, ~o"P20Y"}, :a, :b)

      assert Relation.to_atomic(relation) ==
               [{{:start, :a}, {:start, :b}, {:neg_duration, ~o"P20Y"}}]
    end

    test "at_most is a single upper-bound edge" do
      relation = Relation.new({:delay, :start, :start, :at_most, ~o"P20Y"}, :a, :b)

      assert Relation.to_atomic(relation) ==
               [{{:start, :b}, {:start, :a}, {:duration, ~o"P20Y"}}]
    end
  end

  describe "Allen bridge" do
    test "to_allen / from_allen round-trip the one-to-one relations" do
      for type <- [
            :before,
            :after,
            :immediately_precedes,
            :immediately_follows,
            :overlaps,
            :overlapped_by,
            :includes,
            :included_in,
            :equals,
            :starts,
            :started_by,
            :finishes,
            :finished_by
          ] do
        assert Relation.from_allen(Relation.to_allen(type)) == type
      end
    end

    test "from_allen preserves direction for every Allen relation" do
      # `:overlapped_by` used to map to `:overlaps`, silently reversing
      # the operands — a trap for anything feeding derived relations back
      # into a network.
      for allen <- Relations.full() do
        type = Relation.from_allen(allen)

        assert Relation.to_allen(type) == allen,
               "from_allen(#{inspect(allen)}) gave #{inspect(type)}, " <>
                 "which reads back as #{inspect(Relation.to_allen(type))}"
      end
    end

    test "loose relations map to a disjunction of Allen relations" do
      assert :equals in Relation.to_allen(:synchronous_start)
      assert :starts in Relation.to_allen(:synchronous_start)
      assert Relation.to_allen({:delay, :start, :start, :exactly, ~o"P1Y"}) == nil
    end

    test "metric and boundary relations have no single Allen image" do
      assert Relation.to_allen({:delay, :start, :start, :exactly, ~o"P1Y"}) == nil
      assert Relation.to_allen({:boundary, :end, :at_or_before, :start}) == nil
    end
  end
end
