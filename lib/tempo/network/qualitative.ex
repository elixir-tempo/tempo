defmodule Tempo.Network.Qualitative do
  @moduledoc """
  The bridge between Tempo's two constraint networks.

  `Tempo.Network` reasons **metrically**: dated periods, bounds like
  "at least twenty years after", solved completely and in polynomial time
  by shortest paths. Its relation vocabulary is convex, so it cannot
  represent "before **or** after".

  `Tempo.Interval.RelationNetwork` reasons **qualitatively**: relation
  sets over undated periods, propagated by Allen's path consistency. It
  represents disjunction, and is correspondingly incomplete.

  Neither subsumes the other, and each can tighten the other:

  * **Metric → qualitative.** A solved metric network already excludes
    relations its bounds make impossible. `from_network/1` reads those
    out as relation sets, giving the qualitative network a much tighter
    starting point than "all thirteen".

  * **Qualitative → metric.** A relation set that has narrowed to a
    single relation is a convex constraint the metric network accepts.
    `apply_to_network/2` feeds those back, where they may tighten dates
    that the metric constraints alone left loose.

  `refine/1` runs the round trip.

  ## Example

  Two periods whose order the dates leave open, plus the qualitative fact
  that they cannot overlap:

      iex> alias Tempo.Network
      iex> alias Tempo.Network.Qualitative
      iex> network =
      ...>   Network.new()
      ...>   |> Network.add_period("dig", earliest_start: ~o"2020", latest_end: ~o"2030")
      ...>   |> Network.add_period("survey", earliest_start: ~o"2020", latest_end: ~o"2030")
      iex> qualitative = Qualitative.from_network(network)
      iex> is_struct(qualitative, Tempo.Interval.RelationNetwork)
      true

  """

  alias Tempo.Interval.RelationNetwork
  alias Tempo.Network
  alias Tempo.Network.Relation
  alias Tempo.Network.Solver

  @doc """
  Read a metric network out as a qualitative one.

  Every pair of periods is seeded with the relations the solved metric
  network still permits, so propagation starts from what the dates
  already prove rather than from the full thirteen.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  ### Returns

  * A `t:Tempo.Interval.RelationNetwork.t/0` over the same period ids.

  * `{:error, :inconsistent}` when the metric network has no solution, so
    there are no relations to read.

  """
  @spec from_network(Network.t()) ::
          RelationNetwork.t() | {:error, :inconsistent}
  def from_network(%Network{} = network) do
    ids = Network.period_ids(network)

    Enum.reduce_while(pairs(ids), RelationNetwork.new(ids), fn {a, b}, qualitative ->
      case Solver.relation(network, a, b) do
        {:error, :inconsistent} = error -> {:halt, error}
        {:error, _other} -> {:cont, qualitative}
        allen -> {:cont, RelationNetwork.constrain(qualitative, a, List.wrap(allen), b)}
      end
    end)
  end

  @doc """
  Add every determined qualitative relation to a metric network.

  A relation set narrowed to exactly one relation is knowledge the metric
  network can use; a set with two or more still-possible relations is a
  disjunction it cannot represent, and is skipped.

  ### Arguments

  * `qualitative` is a `t:Tempo.Interval.RelationNetwork.t/0`.

  * `network` is the `t:Tempo.Network.t/0` to add constraints to.

  ### Returns

  * The updated `t:Tempo.Network.t/0`.

  """
  @spec apply_to_network(RelationNetwork.t(), Network.t()) :: Network.t()
  def apply_to_network(%RelationNetwork{} = qualitative, %Network{} = network) do
    ids = Network.period_ids(network)

    Enum.reduce(pairs(ids), network, fn {a, b}, network ->
      qualitative
      |> RelationNetwork.between(a, b)
      |> determined_relation()
      |> add_determined(network, a, b)
    end)
  end

  @doc """
  Run the round trip: read the metric network qualitatively, propagate,
  and feed back what propagation determined.

  This is where the two formalisms pay for each other. The metric bounds
  prune relations Allen's algebra alone would leave open; propagation
  then determines relations the bounds alone did not, and those become
  metric constraints that can tighten dates.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  ### Returns

  * `{:ok, network}` — the metric network with every qualitatively
    determined relation added.

  * `{:error, :inconsistent}` when the metric network has no solution.

  * `{:error, {:inconsistent, pair}}` when qualitative propagation finds
    a contradiction the metric solver did not.

  """
  @spec refine(Network.t()) ::
          {:ok, Network.t()} | {:error, :inconsistent | {:inconsistent, {term(), term()}}}
  def refine(%Network{} = network) do
    with %RelationNetwork{} = qualitative <- from_network(network),
         {:ok, propagated} <- RelationNetwork.propagate(qualitative) do
      {:ok, apply_to_network(propagated, network)}
    end
  end

  ## ------------------------------------------------------------

  defp pairs(ids) do
    for a <- ids, b <- ids, a < b, do: {a, b}
  end

  # Only a set narrowed to one relation is convex enough for the metric
  # network. Two or more is a disjunction it cannot express.
  defp determined_relation([single]) when is_atom(single), do: single
  defp determined_relation(_ambiguous_or_error), do: nil

  defp add_determined(nil, network, _a, _b), do: network

  defp add_determined(allen, network, a, b) do
    type = Relation.from_allen(allen)

    # Re-asserting a constraint the network already holds is a no-op for
    # the solver but grows the relation list, so `refine/1` would not be
    # idempotent. Skip what is already there.
    if already_holds?(network, type, a, b) do
      network
    else
      Network.add_relation(network, type, a, b)
    end
  end

  defp already_holds?(%Network{relations: relations}, type, a, b) do
    Enum.any?(relations, &(&1.type == type and &1.from == a and &1.to == b))
  end
end
