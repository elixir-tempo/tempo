defmodule Tempo.AllenTest do
  use ExUnit.Case, async: true

  # Allen's relations held to their axioms over every pair of spans on a short
  # line: every pair has one relation, a span equals itself, the inverse of a
  # relation is the relation the other way, the composition table has every
  # cell and composes with equals as identity, and the everyday predicates of
  # `Tempo` agree with their relation sets for two single spans.

  import Tempo.Sigils

  alias Tempo.Allen
  alias Tempo.Interval

  @spans for from <- 0..6, to <- (from + 1)..7, do: {from, to}

  test "every pair of spans stands in exactly one of the thirteen relations" do
    for a <- @spans, b <- @spans do
      assert Allen.relation(a, b) in Allen.relations()
    end

    assert @spans
           |> Enum.flat_map(fn a -> Enum.map(@spans, &Allen.relation(a, &1)) end)
           |> Enum.uniq()
           |> length() == 13
  end

  test "a span equals itself and the inverse law holds" do
    for a <- @spans, b <- @spans do
      assert Allen.relation(a, a) == :equals
      assert Allen.inverse(Allen.relation(a, b)) == Allen.relation(b, a)
    end
  end

  test "the composition table has 169 cells and equals composes as identity" do
    for r1 <- Allen.relations(), r2 <- Allen.relations() do
      assert is_list(Allen.compose(r1, r2))
      assert Allen.compose(:equals, r2) == [r2]
      assert Allen.compose(r1, :equals) == [r1]
    end

    assert Allen.compose(:precedes, :precedes) == [:precedes]
    assert Allen.compose(:meets, :met_by) == [:finished_by, :equals, :finishes]
  end

  test "the everyday predicates of two single spans are their relation sets" do
    day = fn n -> Tempo.new!(year: 2026, month: 1, day: n) end

    span = fn {from, to} ->
      Interval.new!(from: day.(from + 1), to: day.(to))
    end

    for a <- @spans, b <- @spans do
      relation = Allen.relation(a, b)
      sa = span.(a)
      sb = span.(b)
      assert Tempo.relation(sa, sb) == relation

      for {predicate, fun} <- [
            before: &Tempo.before?/2,
            after: &Tempo.after?/2,
            adjacent: &Tempo.adjacent?/2,
            within: &Tempo.within?/2,
            contains: &Tempo.contains?/2,
            overlaps: &Tempo.overlaps?/2,
            disjoint: &Tempo.disjoint?/2,
            equal: &Tempo.equal?/2
          ] do
        assert fun.(sa, sb) == relation in Allen.predicate(predicate),
               "#{predicate} of #{inspect(a)} and #{inspect(b)} (#{relation})"
      end
    end
  end

  describe "the relations as predicates" do
    test "each holds when it is the relation" do
      june = ~o"2026-06"

      assert Allen.meets?(june, ~o"2026-07")
      assert Allen.met_by?(~o"2026-07", june)
      assert Allen.precedes?(june, ~o"2026-08")
      assert Allen.preceded_by?(~o"2026-08", june)
      assert Allen.during?(~o"2026-06-15", june)
      assert Allen.contains?(june, ~o"2026-06-15")
      assert Allen.starts?(~o"2026-06-01", june)
      assert Allen.started_by?(june, ~o"2026-06-01")
      assert Allen.finishes?(~o"2026-06-30", june)
      assert Allen.finished_by?(june, ~o"2026-06-30")
      assert Allen.equals?(june, ~o"2026-06-01/2026-06-30")
      assert Allen.overlaps?(~o"2026-05-15/2026-06-15", june)
      assert Allen.overlapped_by?(june, ~o"2026-05-15/2026-06-15")
      refute Allen.meets?(june, ~o"2026-08")
    end

    test "the everyday predicates are named, and each is a set of relations" do
      assert Enum.sort(Allen.predicates()) ==
               [:adjacent, :after, :before, :contains, :disjoint, :equal, :overlaps, :within]

      assert Allen.predicate(:adjacent) == [:meets, :met_by]
      assert Allen.predicate(:meets) == [:meets]
    end

    test "two expressions that share no frame raise the error a relation returns" do
      assert_raise Tempo.FrameError, fn -> Allen.meets?(~o"2026-06-15T10", ~o"2026-06-15T10Z") end
    end
  end

  describe "membership" do
    test "an expression holds what lies within it" do
      assert ~o"2026-06-15" in ~o"2026-06"
      refute ~o"2026-07-15" in ~o"2026-06"
      refute :nonsense in ~o"2026-06"
      refute ~o"2026-06-15T10Z" in ~o"2026-06"
    end
  end
end
