defmodule Tempo.AllenTest do
  use ExUnit.Case, async: true

  # Allen's relations held to their axioms over every pair of spans on a short
  # line: every pair has one relation, a span equals itself, the inverse of a
  # relation is the relation the other way, the composition table has every
  # cell and composes with equals as identity, and the everyday predicates of
  # `Tempo` agree with their relation sets for two single spans.

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
    day = fn n ->
      Tempo.from_iso8601!("2026-01-#{String.pad_leading(Integer.to_string(n), 2, "0")}")
    end

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
end
