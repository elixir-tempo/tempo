defmodule Tempo.Network.ChronoLandTest do
  use ExUnit.Case, async: true

  # The "ChronoLand" worked example from Levy, Geeraerts, Pluquet,
  # Piasetzky & Fantalkin, "Chronological networks in archaeology: A
  # formalised scheme", Journal of Archaeological Science (2020),
  # https://doi.org/10.1016/j.jas.2020.105225 — Fig. 6 (consistent) and
  # Fig. 7 (inconsistent variant). The tightened bounds asserted here
  # are the paper's published values (Fig. 6b).
  #
  # Kingdom of ChronoLand: kings K1 then K2 reign in succession, both
  # between 1200 and 1300 CE; K1's reign is at most 10 years and K2's at
  # least 35. Two strata S1 (built under K1, who founded ChronoCity) and
  # S2 (destroyed by fire under K2) follow one another, each lasting
  # 20–100 years.

  alias Tempo.Network
  alias Tempo.Network.{Solver, TimePeriod}

  defp chronoland do
    Network.new()
    |> Network.add_period(:k1, from: {:not_before, 1200}, duration: {:at_most, 10})
    |> Network.add_period(:k2, to: {:not_after, 1300}, duration: {:at_least, 35})
    |> Network.add_period(:s1, duration: {20, 100})
    |> Network.add_period(:s2, duration: {20, 100})
    |> Network.add_sequence([:k1, :k2])
    |> Network.add_sequence([:s1, :s2])
    |> Network.add_relation(:starts_during, :s1, :k1)
    |> Network.add_relation(:ends_during, :s2, :k2)
  end

  defp bounds(period) do
    %{
      start: {TimePeriod.year(period.earliest_start), TimePeriod.year(period.latest_start)},
      end: {TimePeriod.year(period.earliest_end), TimePeriod.year(period.latest_end)},
      duration: {duration_years(period.min_duration), duration_years(period.max_duration)}
    }
  end

  defp duration_years(nil), do: nil
  defp duration_years(%Tempo.Duration{time: time}), do: Keyword.get(time, :year)

  test "the network is consistent" do
    assert Solver.consistent?(chronoland())
  end

  describe "tightening reproduces the paper's Fig. 6b bounds" do
    setup do
      {:ok, tightened} = Solver.propagate(chronoland())
      %{network: tightened}
    end

    test "K1 — start [1200,1260], end [1200,1265], duration ≤ 10", %{network: network} do
      assert bounds(network.periods[:k1]) == %{
               start: {1200, 1260},
               end: {1200, 1265},
               duration: {nil, 10}
             }
    end

    test "K2 — start [1200,1265], end [1240,1300], duration [35,100]", %{network: network} do
      assert bounds(network.periods[:k2]) == %{
               start: {1200, 1265},
               end: {1240, 1300},
               duration: {35, 100}
             }
    end

    test "S1 — start [1200,1260], end [1220,1280], duration [20,80]", %{network: network} do
      assert bounds(network.periods[:s1]) == %{
               start: {1200, 1260},
               end: {1220, 1280},
               duration: {20, 80}
             }
    end

    test "S2 — start [1220,1280], end [1240,1300], duration [20,80]", %{network: network} do
      assert bounds(network.periods[:s2]) == %{
               start: {1220, 1280},
               end: {1240, 1300},
               duration: {20, 80}
             }
    end
  end

  test "the trace for the earliest end of K2 follows the paper's Fig. 6c" do
    {:ok, trace} = Solver.trace(chronoland(), {:end, :k2}, bound: :earliest)

    assert TimePeriod.year(trace.value) == 1240

    # The six-step propagation: K1 ≥ 1200 → S1 starts during K1 → S1 ≥ 20y
    # → S1 meets S2 → S2 ≥ 20y → S2 ends during K2.
    derived =
      Enum.map(trace.steps, fn step -> {step.boundary, TimePeriod.year(step.value)} end)

    assert derived == [
             {{:start, :k1}, 1200},
             {{:start, :s1}, 1200},
             {{:end, :s1}, 1220},
             {{:start, :s2}, 1220},
             {{:end, :s2}, 1240},
             {{:end, :k2}, 1240}
           ]

    assert trace.prose =~ "lasts at least 20 years"
    assert trace.prose =~ "ends during"
  end

  test "the Fig. 7 variant (K2 at most 25 years) is inconsistent" do
    # The two strata together last at least 40 years, but capping K2 at
    # 25 makes the whole dynasty at most 35 (10 + 25) — too short to
    # contain them.
    network =
      Network.new()
      |> Network.add_period(:k1, from: {:not_before, 1200}, duration: {:at_most, 10})
      |> Network.add_period(:k2, to: {:not_after, 1300}, duration: {:at_most, 25})
      |> Network.add_period(:s1, duration: {20, 100})
      |> Network.add_period(:s2, duration: {20, 100})
      |> Network.add_sequence([:k1, :k2])
      |> Network.add_sequence([:s1, :s2])
      |> Network.add_relation(:starts_during, :s1, :k1)
      |> Network.add_relation(:ends_during, :s2, :k2)

    refute Solver.consistent?(network)
    assert {:error, :inconsistent} = Solver.propagate(network)
  end

  # ── Dagstuhl TIME 2017 variant ──────────────────────────────────
  # The original, coarser Chronoland from Geeraerts, Levy & Pluquet,
  # "Models and Algorithms for Chronology", TIME 2017,
  # https://doi.org/10.4230/LIPIcs.TIME.2017.13 — Fig. 1 (data) and
  # Fig. 2 (optimal bounds). Same structure as the JAS version but with
  # looser king bounds: K1's reign is at most 15 years and K2's is
  # 30–100 years. The strata bounds come out identical to the JAS
  # version (they are independent of the king durations); only the
  # kings differ, since K2 must start by 1300 − 30 = 1270.

  defp chronoland_time2017 do
    Network.new()
    |> Network.add_period(:k1, from: {:not_before, 1200}, duration: {:at_most, 15})
    |> Network.add_period(:k2, to: {:not_after, 1300}, duration: {30, 100})
    |> Network.add_period(:s1, duration: {20, 100})
    |> Network.add_period(:s2, duration: {20, 100})
    |> Network.add_sequence([:k1, :k2])
    |> Network.add_sequence([:s1, :s2])
    |> Network.add_relation(:starts_during, :s1, :k1)
    |> Network.add_relation(:ends_during, :s2, :k2)
  end

  test "the TIME 2017 variant is consistent" do
    assert Solver.consistent?(chronoland_time2017())
  end

  describe "tightening reproduces the TIME 2017 Fig. 2 optimal bounds" do
    setup do
      {:ok, tightened} = Solver.propagate(chronoland_time2017())
      %{network: tightened}
    end

    test "K1 — start [1200,1260], end [1200,1270], duration ≤ 15", %{network: network} do
      assert bounds(network.periods[:k1]) == %{
               start: {1200, 1260},
               end: {1200, 1270},
               duration: {nil, 15}
             }
    end

    test "K2 — start [1200,1270], end [1240,1300], duration [30,100]", %{network: network} do
      assert bounds(network.periods[:k2]) == %{
               start: {1200, 1270},
               end: {1240, 1300},
               duration: {30, 100}
             }
    end

    test "S1 — start [1200,1260], end [1220,1280], duration [20,80]", %{network: network} do
      assert bounds(network.periods[:s1]) == %{
               start: {1200, 1260},
               end: {1220, 1280},
               duration: {20, 80}
             }
    end

    test "S2 — start [1220,1280], end [1240,1300], duration [20,80]", %{network: network} do
      assert bounds(network.periods[:s2]) == %{
               start: {1220, 1280},
               end: {1240, 1300},
               duration: {20, 80}
             }
    end
  end

  describe "contemporaneity — the paper's Props 7 & 10" do
    test "K1 cannot have built S2 — no contemporaneity at all" do
      # The paper's motivating question ("has K1 built S2?"): K1's
      # ≤15-year reign can't span the ≥20 years between the two strata's
      # starts, so no valid chronology has them overlapping.
      net = chronoland_time2017()

      assert Solver.contemporaneity(net, :k1, :s2) == :impossible
      refute Solver.possibly_contemporary?(net, :k1, :s2)
    end

    test "sequential and synchronised periods are certainly contemporary" do
      net = chronoland_time2017()

      assert Solver.contemporaneity(net, :k1, :k2) == :certain
      assert Solver.contemporaneity(net, :s1, :k1) == :certain
      assert Solver.contemporaneity(net, :s2, :k2) == :certain
      assert Solver.certainly_contemporary?(net, :k1, :k2)
    end

    test "K2 and S1 are certain — the ≤15y reign is shorter than S1's ≥20y span" do
      assert Solver.contemporaneity(chronoland_time2017(), :k2, :s1) == :certain
    end

    test "an inconsistent network reports the error rather than a verdict" do
      network =
        Network.new()
        |> Network.add_period(:a, duration: {:at_least, 10})
        |> Network.add_period(:b, duration: {:at_least, 10})
        |> Network.add_relation(:before, :a, :b)
        |> Network.add_relation(:before, :b, :a)

      assert {:error, :inconsistent} = Solver.contemporaneity(network, :a, :b)
    end
  end
end
