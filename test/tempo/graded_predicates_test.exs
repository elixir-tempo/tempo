defmodule Tempo.GradedPredicatesTest do
  @moduledoc """
  The graded predicates of values written with a margin of error (`±`):
  `certainly_overlaps?/2`, `possibly_before?/2` and the six beside them.

  A value with a margin is any of the values the margin allows, and an
  interval with a margin at an end has that end at any of them. A predicate
  holds certainly where it holds however the two are placed, and possibly
  where it holds for some placement.

  The measure is each placement listed and asked: a year by its number, and
  a span of years by the two numbers it runs between.
  """
  use ExUnit.Case, async: true

  alias Tempo.Interval

  # What is asked of two placed spans of years, each `{first, after_last}`.
  @holds %{
    overlaps: {&Interval.certainly_overlaps?/2, &Interval.possibly_overlaps?/2},
    within: {&Interval.certainly_within?/2, &Interval.possibly_within?/2},
    before: {&Interval.certainly_before?/2, &Interval.possibly_before?/2},
    after: {&Interval.certainly_after?/2, &Interval.possibly_after?/2}
  }

  ## The measure

  defp holds?(:overlaps, {a_from, a_to}, {b_from, b_to}), do: a_from < b_to and b_from < a_to
  defp holds?(:within, {a_from, a_to}, {b_from, b_to}), do: b_from <= a_from and a_to <= b_to
  defp holds?(:before, {_a_from, a_to}, {b_from, _b_to}), do: a_to <= b_from
  defp holds?(:after, {a_from, _a_to}, {_b_from, b_to}), do: a_from >= b_to

  # A year with a margin, placed: the year it is, a year long.
  defp placed({year, margin}),
    do: for(placed <- (year - margin)..(year + margin), do: {placed, placed + 1})

  # A span of years with a margin at each end, placed: each start with each
  # end that is after it.
  defp placed({from, from_margin, to, to_margin}) do
    for start <- (from - from_margin)..(from + from_margin),
        stop <- (to - to_margin)..(to + to_margin),
        start < stop,
        do: {start, stop}
  end

  defp year(year, 0), do: "#{year}"
  defp year(year, margin), do: "#{year}±#{margin}Y"

  defp written({year, margin}), do: year(year, margin)

  defp written({from, from_margin, to, to_margin}),
    do: "#{year(from, from_margin)}/#{year(to, to_margin)}"

  # Whether a predicate holds for every placement, and for some.
  defp measured(concept, a, b) do
    held =
      for placed_a <- placed(a), placed_b <- placed(b), do: holds?(concept, placed_a, placed_b)

    {Enum.all?(held), Enum.any?(held)}
  end

  defp asked(concept, a, b) do
    {certainly, possibly} = Map.fetch!(@holds, concept)
    a = Tempo.from_iso8601!(written(a))
    b = Tempo.from_iso8601!(written(b))

    {certainly.(a, b), possibly.(a, b)}
  end

  describe "two years, each with a margin" do
    test "are related certainly where every placement is, and possibly where some is" do
      for a_year <- 2000..2004,
          a_margin <- 0..2,
          b_margin <- 0..2,
          concept <- Map.keys(@holds) do
        a = {a_year, a_margin}
        b = {2002, b_margin}

        assert {concept, written(a), written(b), asked(concept, a, b)} ==
                 {concept, written(a), written(b), measured(concept, a, b)}
      end
    end

    test "are as the examples of their functions say" do
      assert asked(:before, {2000, 1}, {2010, 1}) == {true, true}
      assert asked(:before, {2000, 1}, {2001, 1}) == {false, true}
      assert asked(:after, {2010, 1}, {2000, 1}) == {true, true}
      assert asked(:overlaps, {2000, 1}, {2000, 0}) == {false, true}
      assert asked(:overlaps, {2000, 0}, {2000, 0}) == {true, true}
      assert asked(:overlaps, {2000, 1}, {2005, 1}) == {false, false}
    end
  end

  describe "two spans of years, with a margin at an end" do
    test "are related certainly where every placement is, and possibly where some is" do
      spans =
        for from <- [2000, 2003], from_margin <- 0..1, length <- [2, 5], to_margin <- 0..1 do
          {from, from_margin, from + length, to_margin}
        end

      others = [{2003, 0, 2006, 0}, {2003, 1, 2006, 1}, {2002, 0, 2010, 1}, {2005, 1, 2007, 0}]

      for a <- spans, b <- others, concept <- Map.keys(@holds) do
        assert {concept, written(a), written(b), asked(concept, a, b)} ==
                 {concept, written(a), written(b), measured(concept, a, b)}
      end
    end
  end
end
