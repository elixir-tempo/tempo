defmodule Tempo.Interval.RelationNetworkTest do
  @moduledoc """
  Path-consistency propagation over Allen relations.

  The property that matters is **soundness**: propagation may only remove
  relations that are genuinely impossible. Grounded intervals give an
  independent oracle — seed a network with supersets of the relations that
  actually hold, propagate, and every true relation must survive.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.Interval.RelationNetwork, as: Net
  alias Tempo.Interval.Relations

  doctest Tempo.Interval.RelationNetwork, import: true

  @intervals [
    ~o"2026-06-01/2026-06-10",
    ~o"2026-06-05/2026-06-15",
    ~o"2026-06-10/2026-06-20",
    ~o"2026-06-01/2026-06-20",
    ~o"2026-06-12/2026-06-14",
    ~o"2026-06-20/2026-06-25"
  ]

  describe "new/1" do
    test "asserts nothing between distinct labels" do
      net = Net.new([:a, :b, :c])

      assert Net.between(net, :a, :b) == Relations.full()
      assert Net.between(net, :b, :c) == Relations.full()
    end

    test "a period equals itself" do
      assert Net.new([:a]) |> Net.between(:a, :a) == [:equals]
    end

    test "duplicate labels are collapsed" do
      assert Net.new([:a, :a, :b]) |> Net.between(:a, :b) == Relations.full()
    end
  end

  describe "constrain/4" do
    test "records the converse on the reverse pair" do
      net = Net.new([:a, :b]) |> Net.constrain(:a, [:precedes, :meets], :b)

      assert Net.between(net, :a, :b) == [:precedes, :meets]
      assert Net.between(net, :b, :a) == [:met_by, :preceded_by]
    end

    test "accumulates — a second assertion narrows rather than replaces" do
      net =
        Net.new([:a, :b])
        |> Net.constrain(:a, [:precedes, :meets], :b)
        |> Net.constrain(:a, [:meets, :overlaps], :b)

      assert Net.between(net, :a, :b) == [:meets]
    end

    test "reports an unknown label rather than silently adding one" do
      net = Net.new([:a, :b])

      assert Net.constrain(net, :a, [:precedes], :zzz) == {:error, {:unknown_label, :zzz}}
      assert Net.between(net, :a, :zzz) == {:error, {:unknown_label, :zzz}}
    end

    test "reports a relation that is not one of the thirteen" do
      net = Net.new([:a, :b])

      assert Net.constrain(net, :a, [:nonsense], :b) == {:error, {:invalid_relation, :nonsense}}
    end
  end

  describe "propagate/1" do
    test "derives a transitive consequence" do
      net =
        Net.new([:a, :b, :c])
        |> Net.constrain(:a, [:precedes], :b)
        |> Net.constrain(:b, [:precedes], :c)

      assert {:ok, solved} = Net.propagate(net)
      assert Net.between(solved, :a, :c) == [:precedes]
    end

    test "leaves genuine ambiguity ambiguous" do
      # Precedes-then-during does not determine the relation, and
      # propagation must not pretend otherwise.
      net =
        Net.new([:a, :b, :c])
        |> Net.constrain(:a, [:precedes], :b)
        |> Net.constrain(:b, [:during], :c)

      assert {:ok, solved} = Net.propagate(net)
      assert Net.between(solved, :a, :c) == [:precedes, :meets, :overlaps, :starts, :during]
    end

    test "reports a contradiction definitively" do
      net =
        Net.new([:a, :b, :c])
        |> Net.constrain(:a, [:precedes], :b)
        |> Net.constrain(:b, [:precedes], :c)
        |> Net.constrain(:c, [:precedes], :a)

      assert {:error, {:inconsistent, {_a, _b}}} = Net.propagate(net)
    end

    test "a directly contradictory pair is caught" do
      net =
        Net.new([:a, :b])
        |> Net.constrain(:a, [:precedes], :b)
        |> Net.constrain(:a, [:preceded_by], :b)

      refute Net.consistent?(net)
    end

    test "is idempotent — propagating a solved network changes nothing" do
      net =
        Net.new([:a, :b, :c])
        |> Net.constrain(:a, [:precedes, :meets], :b)
        |> Net.constrain(:b, [:overlaps, :during], :c)

      assert {:ok, once} = Net.propagate(net)
      assert {:ok, twice} = Net.propagate(once)
      assert once == twice
    end

    test "preserves the converse invariant on every pair" do
      net =
        Net.new([:a, :b, :c])
        |> Net.constrain(:a, [:precedes, :meets], :b)
        |> Net.constrain(:b, [:overlaps], :c)

      assert {:ok, solved} = Net.propagate(net)

      for x <- [:a, :b, :c], y <- [:a, :b, :c], x != y do
        assert Net.between(solved, y, x) == Relations.converse(Net.between(solved, x, y))
      end
    end

    test "a disjunction survives — the case Tempo.Network cannot represent" do
      net =
        Net.new([:fire, :rebuild]) |> Net.constrain(:fire, [:precedes, :preceded_by], :rebuild)

      assert {:ok, solved} = Net.propagate(net)
      assert Net.between(solved, :fire, :rebuild) == [:precedes, :preceded_by]
    end
  end

  describe "soundness against real intervals" do
    # Seed a network with the relations that actually hold, widened by a
    # decoy each, then propagate. The true relation must always survive:
    # propagation may only remove what is genuinely impossible.
    property "propagation never removes a relation that actually holds" do
      check all(
              triple <- uniq_list_of(member_of(@intervals), length: 3),
              decoy <- member_of(Relations.full()),
              max_runs: 200
            ) do
        [x, y, z] = triple
        labels = [:x, :y, :z]
        pairs = [{:x, :y, x, y}, {:y, :z, y, z}, {:x, :z, x, z}]

        net =
          Enum.reduce(pairs, Net.new(labels), fn {la, lb, a, b}, net ->
            truth = Interval.relation(a, b)
            Net.constrain(net, la, Relations.canonical([truth, decoy]), lb)
          end)

        assert {:ok, solved} = Net.propagate(net)

        for {la, lb, a, b} <- pairs do
          truth = Interval.relation(a, b)

          assert truth in Net.between(solved, la, lb),
                 "propagation removed the true relation #{inspect(truth)} " <>
                   "between #{inspect(la)} and #{inspect(lb)}"
        end
      end
    end

    test "a network of fully determined true relations stays consistent" do
      for x <- @intervals, y <- @intervals, z <- @intervals, x != y, y != z, x != z do
        net =
          Net.new([:x, :y, :z])
          |> Net.constrain(:x, [Interval.relation(x, y)], :y)
          |> Net.constrain(:y, [Interval.relation(y, z)], :z)
          |> Net.constrain(:x, [Interval.relation(x, z)], :z)

        assert Net.consistent?(net),
               "a network built from relations that genuinely hold was reported inconsistent"
      end
    end
  end
end
