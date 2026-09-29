defmodule Tempo.Network.SolverTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Tempo.Sigils

  alias Tempo.Network
  alias Tempo.Network.{Solver, TimePeriod}

  doctest Tempo.Network.Solver
  doctest Tempo.Network.Normalize

  # Read the integer year of a tightened bound.
  defp years(period) do
    %{
      start: {TimePeriod.year(period.earliest_start), TimePeriod.year(period.latest_start)},
      end: {TimePeriod.year(period.earliest_end), TimePeriod.year(period.latest_end)},
      duration: {duration_years(period.min_duration), duration_years(period.max_duration)}
    }
  end

  defp duration_years(nil), do: nil
  defp duration_years(%Tempo.Duration{time: time}), do: Keyword.get(time, :year)

  # Two grounded periods a = [a1, a2) and b = [b1, b2) as integer years.
  defp ground(a1, a2, b1, b2) do
    Network.new()
    |> Network.add_period(:a, from: a1, to: a2)
    |> Network.add_period(:b, from: b1, to: b2)
  end

  # The same two intervals compared by the core point algebra, for agreement.
  defp core_relation(a1, a2, b1, b2) do
    Tempo.relation(
      Tempo.from_iso8601!("#{a1}Y/#{a2}Y"),
      Tempo.from_iso8601!("#{b1}Y/#{b2}Y")
    )
  end

  describe "consistency" do
    test "a single well-formed period is consistent" do
      assert Network.new()
             |> Network.add_period(:k, from: 1200, duration: {:at_least, 10})
             |> Solver.consistent?()
    end

    test "an end before a start is inconsistent" do
      refute Network.new()
             |> Network.add_period(:k, from: 1200, to: 1180)
             |> Solver.consistent?()
    end

    test "a sequence whose links cannot be satisfied is inconsistent" do
      # k1 must end by 1210, k2 must start by 1205, but k1 meets k2 and
      # k1 lasts at least 30 years from a start no earlier than 1200.
      refute Network.new()
             |> Network.add_period(:k1,
               from: {:not_before, 1200},
               duration: {:at_least, 30},
               to: {:not_after, 1210}
             )
             |> Network.add_period(:k2, [])
             |> Network.add_sequence([:k1, :k2])
             |> Solver.consistent?()
    end

    test "contradictory relations are inconsistent" do
      # a is both strictly before b and strictly after b.
      refute Network.new()
             |> Network.add_period(:a, [])
             |> Network.add_period(:b, [])
             |> Network.add_relation(:before, :a, :b)
             |> Network.add_relation(:after, :a, :b)
             |> Solver.consistent?()
    end
  end

  describe "tightening — sequence with two-sided bounds" do
    setup do
      {:ok, tightened} =
        Network.new()
        |> Network.add_period(:k1, from: {1200, 1210}, duration: {20, 30})
        |> Network.add_period(:k2, duration: {35, 50})
        |> Network.add_sequence([:k1, :k2])
        |> Solver.propagate()

      %{network: tightened}
    end

    test "k1 propagates start + duration into its end", %{network: network} do
      assert years(network.periods[:k1]) == %{
               start: {1200, 1210},
               # end = start + duration ∈ [1200+20, 1210+30]
               end: {1220, 1240},
               duration: {20, 30}
             }
    end

    test "k2 inherits its start from k1's end and pushes its own end", %{network: network} do
      assert years(network.periods[:k2]) == %{
               # start(k2) = end(k1) ∈ [1220, 1240]
               start: {1220, 1240},
               # end(k2) = start(k2) + duration ∈ [1220+35, 1240+50]
               end: {1255, 1290},
               duration: {35, 50}
             }
    end
  end

  describe "tightening — relations" do
    test "inclusion nests one period inside another" do
      {:ok, network} =
        Network.new()
        |> Network.add_period(:k, from: {1200, 1200}, to: {1260, 1260})
        |> Network.add_period(:s, duration: {:at_least, 10})
        |> Network.add_relation(:included_in, :s, :k)
        |> Solver.propagate()

      # s sits within k = [1200, 1260]: its start ≥ 1200, end ≤ 1260,
      # and (start ≤ end − 10) so start ≤ 1250 and end ≥ 1210.
      assert years(network.periods[:s]) == %{
               start: {1200, 1250},
               end: {1210, 1260},
               duration: {10, 60}
             }
    end

    test "a delay relation enforces a minimum gap" do
      # start(b) is at least 40 years after start(a): a delay where
      # start(a) is at least 40 before start(b).
      {:ok, network} =
        Network.new()
        |> Network.add_period(:a, from: {1000, 1000})
        |> Network.add_period(:b, [])
        |> Network.add_relation({:delay, :start, :start, :at_least, ~o"P40Y"}, :a, :b)
        |> Solver.propagate()

      assert TimePeriod.year(network.periods[:b].earliest_start) == 1040
    end

    test "contemporaneity forces overlapping windows to meet" do
      # a ends by 1100; b is contemporary with a, so b starts by 1100.
      {:ok, network} =
        Network.new()
        |> Network.add_period(:a, to: {:not_after, 1100})
        |> Network.add_period(:b, from: {:not_before, 1050})
        |> Network.add_relation(:contemporary, :a, :b)
        |> Solver.propagate()

      assert TimePeriod.year(network.periods[:b].latest_start) == 1100
    end
  end

  describe "tighten/1 on an inconsistent network" do
    test "returns an error tuple" do
      assert {:error, :inconsistent} =
               Network.new()
               |> Network.add_period(:k, from: 1200, to: 1180)
               |> Solver.propagate()
    end
  end

  describe "trace/3" do
    test "explains an earliest bound as a chain of named constraints" do
      {:ok, trace} =
        Network.new()
        |> Network.add_period(:k1, from: {:not_before, 1200}, duration: {:at_least, 20})
        |> Network.add_period(:k2, duration: {:at_least, 35})
        |> Network.add_sequence([:k1, :k2])
        |> Solver.trace({:end, :k2})

      assert TimePeriod.year(trace.value) == 1255
      assert List.last(trace.steps).boundary == {:end, :k2}
      assert trace.prose =~ "immediately precedes"
    end

    test "an unbounded boundary returns {:error, :unbounded}" do
      assert {:error, :unbounded} =
               Network.new()
               |> Network.add_period(:k, duration: {:at_least, 10})
               |> Solver.trace({:end, :k}, bound: :latest)
    end

    test "an inconsistent network returns {:error, :inconsistent}" do
      assert {:error, :inconsistent} =
               Network.new()
               |> Network.add_period(:k, from: 1200, to: 1180)
               |> Solver.trace({:start, :k})
    end
  end

  describe "relation/3 — the tightest Allen relation" do
    test "grounded periods pin exactly one relation, one per Allen class" do
      # One representative of each of the thirteen base relations, each read
      # back as a single entailed atom.
      assert Solver.relation(ground(1200, 1250, 1300, 1350), :a, :b) == :precedes
      assert Solver.relation(ground(1200, 1250, 1250, 1300), :a, :b) == :meets
      assert Solver.relation(ground(1200, 1250, 1230, 1280), :a, :b) == :overlaps
      assert Solver.relation(ground(1200, 1280, 1230, 1280), :a, :b) == :finished_by
      assert Solver.relation(ground(1200, 1280, 1230, 1250), :a, :b) == :contains
      assert Solver.relation(ground(1200, 1250, 1200, 1280), :a, :b) == :starts
      assert Solver.relation(ground(1200, 1250, 1200, 1250), :a, :b) == :equals
      assert Solver.relation(ground(1200, 1280, 1200, 1250), :a, :b) == :started_by
      assert Solver.relation(ground(1230, 1250, 1200, 1280), :a, :b) == :during
      assert Solver.relation(ground(1230, 1280, 1200, 1280), :a, :b) == :finishes
      assert Solver.relation(ground(1230, 1280, 1200, 1250), :a, :b) == :overlapped_by
      assert Solver.relation(ground(1250, 1300, 1200, 1250), :a, :b) == :met_by
      assert Solver.relation(ground(1300, 1350, 1200, 1250), :a, :b) == :preceded_by
    end

    test "an unconstrained pair leaves all thirteen relations possible" do
      # Two periods with only proper-interval constraints — every relation
      # remains feasible, so the answer is the full disjunction.
      relations =
        Network.new()
        |> Network.add_period(:a, duration: {:at_least, 1})
        |> Network.add_period(:b, duration: {:at_least, 1})
        |> Solver.relation(:a, :b)

      assert length(relations) == 13
    end

    test "a sequence link entails :meets" do
      assert Network.new()
             |> Network.add_period(:a, duration: {:at_least, 10})
             |> Network.add_period(:b, duration: {:at_least, 10})
             |> Network.add_sequence([:a, :b])
             |> Solver.relation(:a, :b) == :meets
    end

    test "partial constraints narrow to a disjunction without pinning one" do
      # b starts within a's span but its end is free, so b may finish inside a
      # (:during), coincide with a's end (:finishes), or run past it
      # (:overlapped_by) — but never precede or meet a.
      relations =
        Network.new()
        |> Network.add_period(:a, from: {1200, 1200}, to: {1260, 1260})
        |> Network.add_period(:b, from: {1210, 1210}, duration: {:at_least, 5})
        |> Solver.relation(:b, :a)

      assert is_list(relations)
      assert :during in relations
      assert :finishes in relations
      assert :overlapped_by in relations
      refute :precedes in relations
      refute :meets in relations
    end

    test "an inconsistent network returns {:error, :inconsistent}" do
      assert {:error, :inconsistent} =
               Network.new()
               |> Network.add_period(:a, from: 1200, to: 1180)
               |> Network.add_period(:b, from: 1000, to: 1100)
               |> Solver.relation(:a, :b)
    end

    test "an unknown period returns {:error, :unknown_period}" do
      assert {:error, :unknown_period} =
               ground(1200, 1250, 1230, 1280) |> Solver.relation(:a, :missing)
    end

    property "on grounded periods it entails one relation, matching Tempo.relation/2" do
      check all(
              a1 <- integer(1000..2000),
              da <- integer(1..400),
              b1 <- integer(1000..2000),
              db <- integer(1..400)
            ) do
        a2 = a1 + da
        b2 = b1 + db
        network_relation = Solver.relation(ground(a1, a2, b1, b2), :a, :b)

        # Exactly one relation is feasible (jointly exhaustive, pairwise
        # disjoint), and it is the one the core point algebra reports.
        assert is_atom(network_relation)
        assert network_relation == core_relation(a1, a2, b1, b2)
      end
    end
  end

  describe "relation_certainty/4" do
    test ":certain when the relation is the only one entailed" do
      net = ground(1200, 1250, 1230, 1280)
      assert Solver.relation_certainty(net, :a, :b, :overlaps) == :certain
    end

    test ":impossible when the relation is ruled out" do
      net = ground(1200, 1250, 1230, 1280)
      assert Solver.relation_certainty(net, :a, :b, :during) == :impossible
    end

    test ":possible when the relation is one of several still open" do
      net =
        Network.new()
        |> Network.add_period(:a, duration: {:at_least, 1})
        |> Network.add_period(:b, duration: {:at_least, 1})

      assert Solver.relation_certainty(net, :a, :b, :overlaps) == :possible
      assert Solver.relation_certainty(net, :a, :b, :precedes) == :possible
    end

    test "propagates the errors relation/3 returns" do
      net = ground(1200, 1250, 1230, 1280)
      assert {:error, :unknown_period} = Solver.relation_certainty(net, :a, :missing, :precedes)
    end
  end
end
