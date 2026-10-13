defmodule Tempo.Network.ColdstreamTest do
  use ExUnit.Case, async: true

  # Coldstream's Corinthian Geometric sequence, modelled with date-ranges
  # and an overlap synchronism — Levy et al. (2020), Fig. 5c (after
  # Coldstream 2008). It demonstrates regional ceramic phases joined by
  # an `:overlaps` relation rather than a strict sequence, where each
  # style's date range is approximate. Years are BCE (negative).
  #
  # The paper presents Fig. 5 as input-modelling options and does not
  # publish a tightened table, so the bounds asserted here are
  # hand-derived from the constraints and confirmed against the solver.

  import Tempo.Sigils

  alias Tempo.Network
  alias Tempo.Network.{Solver, TimePeriod}

  defp corinthian do
    Network.new()
    |> Network.add_period(:lpg,
      name: "LPG",
      from: {~o"-910Y", ~o"-890Y"},
      to: {~o"-885Y", ~o"-865Y"}
    )
    |> Network.add_period(:eg,
      name: "EG",
      from: {~o"-885Y", ~o"-865Y"},
      to: {:not_before, ~o"-825Y"}
    )
    |> Network.add_period(:mg1,
      name: "MG I",
      from: {:not_before, ~o"-840Y"},
      to: {~o"-810Y", ~o"-790Y"}
    )
    |> Network.add_sequence([:lpg, :eg])
    |> Network.add_relation(:overlaps, :eg, :mg1)
  end

  defp span(period) do
    {
      {TimePeriod.year(period.earliest_start), TimePeriod.year(period.latest_start)},
      {TimePeriod.year(period.earliest_end), TimePeriod.year(period.latest_end)}
    }
  end

  test "the regional sequence with an overlap is consistent" do
    assert Solver.consistent?(corinthian())
  end

  describe "tightening propagates the overlap across the styles" do
    setup do
      {:ok, solved} = Solver.propagate(corinthian())
      %{network: solved}
    end

    test "LPG keeps its input ranges", %{network: network} do
      assert span(network.periods[:lpg]) == {{-910, -890}, {-885, -865}}
    end

    test "the overlap caps EG's end at MG I's latest end (-790)", %{network: network} do
      # EG overlaps MG I ⇒ end(EG) ≤ end(MG I) ≤ -790, so EG's open-above
      # end (≥ -825) gains an upper bound of -790.
      assert span(network.periods[:eg]) == {{-885, -865}, {-825, -790}}
    end

    test "MG I's start is bounded above by its own end", %{network: network} do
      assert span(network.periods[:mg1]) == {{-840, -790}, {-810, -790}}
    end
  end
end
