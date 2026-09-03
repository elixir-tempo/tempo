defmodule Tempo.Network.QualitativeTest do
  @moduledoc """
  The bridge between the metric (STP) and qualitative (Allen) networks.

  Each direction has one property that must hold: reading a metric
  network qualitatively must not invent relations its bounds exclude, and
  feeding derived relations back must never make a consistent network
  inconsistent.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval.RelationNetwork, as: QNet
  alias Tempo.Network
  alias Tempo.Network.Qualitative
  alias Tempo.Network.Solver

  defp dated_network do
    Network.new()
    |> Network.add_period(:a, start: ~o"2000", end: ~o"2005")
    |> Network.add_period(:b, start: ~o"2010", end: ~o"2015")
    |> Network.add_period(:c, [])
    |> Network.add_relation(:before, :b, :c)
  end

  describe "from_network/1" do
    test "seeds each pair with what the metric bounds already prove" do
      qualitative = Qualitative.from_network(dated_network())

      # The dates settle a→b outright, so the qualitative network starts
      # from one relation rather than thirteen.
      assert QNet.between(qualitative, :a, :b) == [:precedes]
    end

    test "agrees with the metric solver on every pair" do
      network = dated_network()
      qualitative = Qualitative.from_network(network)

      for a <- [:a, :b, :c], b <- [:a, :b, :c], a != b do
        assert QNet.between(qualitative, a, b) == List.wrap(Solver.relation(network, a, b))
      end
    end

    test "an undated period is left open rather than guessed" do
      network =
        Network.new()
        |> Network.add_period(:x, [])
        |> Network.add_period(:y, [])

      qualitative = Qualitative.from_network(network)

      assert length(QNet.between(qualitative, :x, :y)) == 13
    end
  end

  describe "apply_to_network/2" do
    test "adds a determined relation as a metric constraint" do
      network = dated_network()
      {:ok, propagated} = network |> Qualitative.from_network() |> QNet.propagate()

      refined = Qualitative.apply_to_network(propagated, network)

      assert Enum.any?(refined.relations, &(&1.type == :before and &1.from == :a and &1.to == :c))
    end

    test "skips a disjunction the metric network cannot represent" do
      # Two undated periods: nothing is determined, so nothing is added.
      network =
        Network.new()
        |> Network.add_period(:x, [])
        |> Network.add_period(:y, [])

      qualitative =
        QNet.new([:x, :y]) |> QNet.constrain(:x, [:precedes, :preceded_by], :y)

      refined = Qualitative.apply_to_network(qualitative, network)

      assert refined.relations == network.relations
    end
  end

  describe "refine/1" do
    test "derives relations the metric constraints alone left implicit" do
      network = dated_network()

      assert {:ok, refined} = Qualitative.refine(network)
      assert length(refined.relations) > length(network.relations)
    end

    test "never makes a consistent network inconsistent" do
      network = dated_network()

      assert Solver.consistent?(network)
      assert {:ok, refined} = Qualitative.refine(network)
      assert Solver.consistent?(refined)
    end

    test "is idempotent — a second pass adds nothing" do
      assert {:ok, once} = Qualitative.refine(dated_network())
      assert {:ok, twice} = Qualitative.refine(once)

      assert length(once.relations) == length(twice.relations)
    end

    test "reports a metric network that has no solution" do
      network =
        Network.new()
        |> Network.add_period(:a, start: ~o"2010", end: ~o"2015")
        |> Network.add_period(:b, start: ~o"2000", end: ~o"2005")
        |> Network.add_relation(:before, :a, :b)

      assert Qualitative.refine(network) == {:error, :inconsistent}
    end

    test "preserves the tightened bounds the metric solver reports" do
      network = dated_network()
      {:ok, before} = Solver.tighten(network)
      {:ok, refined} = Qualitative.refine(network)
      {:ok, after_refine} = Solver.tighten(refined)

      # Refinement may only narrow — never widen — what the solver knows.
      assert map_size(after_refine) == map_size(before)
    end
  end
end
