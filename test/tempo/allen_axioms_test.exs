defmodule Tempo.AllenAxiomsTest do
  @moduledoc """
  Property-based verification that `Tempo.Interval.relation/2` satisfies
  Allen's interval-algebra axioms and the bounded-meeting ontology
  axioms of Grüninger and Li (TIME 2017).

  Following the precedent set by Haskell's `interval-algebra` package
  (which ships axiom tests against Allen and Hayes 1987), these
  properties mechanically verify that Tempo's implementation realises
  the ontology rather than merely asserting it in documentation.

  Tested properties:

    * Joint exhaustiveness — every pair of non-empty bounded intervals
      yields one of the 13 named relations.

    * Self-equality — `relation(a, a) == :equals`.

    * Inverse consistency — `Allen.inverse(relation(a, b)) == relation(b, a)`
      for every pair.

    * Meets asymmetry — when `relation(a, b) == :meets`, the inverse pair
      yields `:met_by` (not `:meets`); a direct check of the
      $T_{bounded\\_meeting}$ asymmetry axiom (Grüninger & Li axiom 14).

    * Sum Axiom — chain-meeting intervals coalesce into a single interval,
      realising axiom 15 of $T_{bounded\\_meeting}$.

    * Predicate-relation consistency — the everyday predicates
      (`within?`, `before?`, `after?`, `adjacent?`) correspond to
      specific subsets of the 13 Allen relations as documented, and
      each `Tempo.Allen` predicate holds exactly when its relation does.

  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tempo.Allen
  alias Tempo.Interval
  alias Tempo.IntervalSet

  @relations [
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
  ]

  describe "Allen-Hayes / T_bounded_meeting axioms" do
    property "relation/2 always returns one of the 13 named relations" do
      check all(
              a <- interval_gen(),
              b <- interval_gen()
            ) do
        assert Interval.relation(a, b) in @relations
      end
    end

    property "self-relation is :equals" do
      check all(a <- interval_gen()) do
        assert Interval.relation(a, a) == :equals
      end
    end

    property "inverse(relation(a, b)) == relation(b, a)" do
      check all(
              a <- interval_gen(),
              b <- interval_gen()
            ) do
        forward = Interval.relation(a, b)
        backward = Interval.relation(b, a)
        assert Allen.inverse(forward) == backward
      end
    end

    property "meets is asymmetric (Grüninger & Li axiom 14)" do
      check all(
              a <- interval_gen(),
              b <- interval_gen()
            ) do
        if Interval.relation(a, b) == :meets do
          # Asymmetry: if A meets B then B does not meet A.
          # Under the inverse correspondence, B's relation to A is :met_by.
          assert Interval.relation(b, a) == :met_by
          refute Interval.relation(b, a) == :meets
        end
      end
    end

    property "Sum Axiom: chain-meeting intervals coalesce to one (axiom 15)" do
      check all(offsets <- ordered_offsets(5)) do
        [t0, t1, t2, t3, t4] = Enum.map(offsets, &point/1)

        # Three chain-meeting intervals: meets(a, b), meets(b, c), meets(c, d).
        a = Interval.new!(from: t0, to: t1)
        b = Interval.new!(from: t1, to: t2)
        c = Interval.new!(from: t2, to: t3)
        d = Interval.new!(from: t3, to: t4)

        assert Interval.relation(a, b) == :meets
        assert Interval.relation(b, c) == :meets
        assert Interval.relation(c, d) == :meets

        # Sum Axiom: there exists a single interval n such that
        # meets(a, n) ∧ meets(n, d). In Tempo, the canonical
        # (coalesced) form realises this: four chain-meeting
        # intervals collapse to [t0, t4).
        {:ok, set} = IntervalSet.new([a, b, c, d], coalesce: true)
        assert IntervalSet.count(set) == 1

        [coalesced] = set.intervals
        assert coalesced.from == t0
        assert coalesced.to == t4
      end
    end
  end

  describe "named predicates ↔ Allen relations" do
    property "before?(a, b) iff relation(a, b) in [:precedes, :meets]" do
      check all(
              a <- interval_gen(),
              b <- interval_gen()
            ) do
        assert Interval.before?(a, b) == Interval.relation(a, b) in [:precedes, :meets]
      end
    end

    property "after?(a, b) iff relation(a, b) in [:preceded_by, :met_by]" do
      check all(
              a <- interval_gen(),
              b <- interval_gen()
            ) do
        assert Interval.after?(a, b) == Interval.relation(a, b) in [:preceded_by, :met_by]
      end
    end

    property "each Allen predicate iff its relation holds" do
      check all(
              a <- interval_gen(),
              b <- interval_gen()
            ) do
        held = Interval.relation(a, b)

        for relation <- @relations do
          assert apply(Allen, :"#{relation}?", [a, b]) == (held == relation)
        end
      end
    end

    property "adjacent?(a, b) iff relation(a, b) in [:meets, :met_by]" do
      check all(
              a <- interval_gen(),
              b <- interval_gen()
            ) do
        assert Interval.adjacent?(a, b) ==
                 Interval.relation(a, b) in [:meets, :met_by]
      end
    end

    property "within?(a, b) iff relation(a, b) in [:equals, :starts, :during, :finishes]" do
      check all(
              a <- interval_gen(),
              b <- interval_gen()
            ) do
        assert Interval.within?(a, b) ==
                 Interval.relation(a, b) in [:equals, :starts, :during, :finishes]
      end
    end

    property "within?(a, a) is always true (reflexive: :equals ∈ within set)" do
      check all(a <- interval_gen()) do
        assert Interval.within?(a, a)
      end
    end
  end

  describe "axioms hold at microsecond resolution" do
    property "relation/2 returns one of the 13 relations" do
      check all(
              a <- microsecond_interval_gen(),
              b <- microsecond_interval_gen()
            ) do
        assert Interval.relation(a, b) in @relations
      end
    end

    property "inverse(relation(a, b)) == relation(b, a)" do
      check all(
              a <- microsecond_interval_gen(),
              b <- microsecond_interval_gen()
            ) do
        assert Allen.inverse(Interval.relation(a, b)) == Interval.relation(b, a)
      end
    end

    property "self-relation is :equals" do
      check all(a <- microsecond_interval_gen()) do
        assert Interval.relation(a, a) == :equals
      end
    end
  end

  ## Generators

  # Generate a non-empty bounded interval over a 10-year span at
  # day resolution. Day resolution avoids leap-second and DST edge
  # cases that would obscure the algebra under test; the algebra
  # holds regardless of resolution, so day-level intervals are a
  # sufficient witness.
  defp interval_gen do
    gen all(
          start_offset <- StreamData.integer(0..3650),
          length <- StreamData.integer(1..3650)
        ) do
      Interval.new!(from: point(start_offset), to: point(start_offset + length))
    end
  end

  # Generate `n` distinct ordered offsets — used to produce a chain
  # of meeting intervals where each subsequent interval's :from
  # equals the previous interval's :to.
  defp ordered_offsets(n) do
    gen all(
          offsets <-
            StreamData.list_of(StreamData.integer(0..10_000), length: n)
            |> StreamData.map(&Enum.uniq/1)
            |> StreamData.filter(&(length(&1) == n))
            |> StreamData.map(&Enum.sort/1)
        ) do
      offsets
    end
  end

  # Convert a day offset into a Tempo value at day resolution.
  defp point(day_offset) do
    ~D[2020-01-01]
    |> Date.add(day_offset)
    |> Tempo.from_elixir()
  end

  # Generate a non-empty bounded interval at microsecond resolution,
  # spanning a window within a single minute. Verifies the algebra
  # holds at the finest resolution, not only at day resolution.
  defp microsecond_interval_gen do
    gen all(
          a <- StreamData.integer(0..59_999_999),
          b <- StreamData.integer(0..59_999_999),
          a != b
        ) do
      [lo, hi] = Enum.sort([a, b])
      Interval.new!(from: microsecond_point(lo), to: microsecond_point(hi))
    end
  end

  # Convert a microseconds-within-a-minute offset into a Tempo value
  # at microsecond resolution.
  defp microsecond_point(total_microseconds) do
    second = div(total_microseconds, 1_000_000)
    microsecond = rem(total_microseconds, 1_000_000)
    {:ok, naive} = NaiveDateTime.new(2026, 6, 15, 10, 30, second, {microsecond, 6})
    Tempo.from_elixir(naive)
  end
end
