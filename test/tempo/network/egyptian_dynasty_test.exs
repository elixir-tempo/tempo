defmodule Tempo.Network.EgyptianDynastyTest do
  use ExUnit.Case, async: true

  # The Egyptian 26th-dynasty Sequence from Levy et al. (2020), Fig. 2a
  # (after Kitchen 2000, p. 50): six kings reigning in succession with
  # known durations, anchored by Psammetichus I's accession in 664 BCE.
  # Given only the anchor, the durations, and the sequence, tightening
  # derives every reign's absolute dates — exercising BCE (negative)
  # years and a six-period sequence.

  alias Tempo.Network
  alias Tempo.Network.{Solver, TimePeriod}

  @reigns [
    {:psammetichus_i, 54},
    {:necho_ii, 15},
    {:psammetichus_ii, 6},
    {:apries, 19},
    {:amasis_ii, 44},
    {:psammetichus_iii, 1}
  ]

  defp dynasty do
    network =
      Enum.reduce(@reigns, Network.new(), fn {id, years}, network ->
        Network.add_period(network, id, duration: years)
      end)

    network
    # Anchor the dynasty at Psammetichus I's accession, 664 BCE.
    |> Network.add_period(:psammetichus_i, from: -664, duration: 54)
    |> Network.add_sequence(Enum.map(@reigns, &elem(&1, 0)))
  end

  test "the dynasty is consistent" do
    assert Solver.consistent?(dynasty())
  end

  test "tightening derives every reign's absolute dates (Fig. 2a)" do
    {:ok, network} = Solver.propagate(dynasty())

    spans =
      Map.new(network.periods, fn {id, period} ->
        {id, {TimePeriod.year(period.earliest_start), TimePeriod.year(period.earliest_end)}}
      end)

    assert spans == %{
             psammetichus_i: {-664, -610},
             necho_ii: {-610, -595},
             psammetichus_ii: {-595, -589},
             apries: {-589, -570},
             amasis_ii: {-570, -526},
             psammetichus_iii: {-526, -525}
           }
  end

  test "the derived dates are exact (earliest equals latest)" do
    {:ok, network} = Solver.propagate(dynasty())
    amasis = network.periods[:amasis_ii]

    assert TimePeriod.year(amasis.earliest_start) == TimePeriod.year(amasis.latest_start)
    assert TimePeriod.year(amasis.earliest_end) == TimePeriod.year(amasis.latest_end)
  end
end
