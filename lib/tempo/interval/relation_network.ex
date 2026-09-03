defmodule Tempo.Interval.RelationNetwork do
  @moduledoc """
  A qualitative constraint network over Allen relations, with the
  path-consistency propagation of Allen (1983) §3.

  Where every interval is grounded, `Tempo.relation/2` answers directly.
  This module is for the case where they are not: you know how some
  periods relate to each other, not when any of them happened, and want
  to know what follows. Each pair of periods carries a *set* of the
  relations still possible; asserting a constraint narrows a set, and
  propagation narrows every other set that the assertion implies.

  ## Not `Tempo.Network`

  `Tempo.Network` solves the **Simple Temporal Problem** — metric
  constraints (`at_least: 20, unit: :year`) over dated periods, by
  shortest paths. It is complete and polynomial, and its relation
  vocabulary is convex: it cannot represent "before **or** after".

  This module is the qualitative counterpart. It has no dates and no
  metric constraints, and it *can* represent disjunction — which is
  exactly why it is incomplete (below). Use `Tempo.Network` when you have
  bounds and want dates; use this when you have relations and want
  relations.

  ## Sound but incomplete

  `propagate/1` computes **path consistency**, not satisfiability.

  * Every relation it *removes* is genuinely impossible. Pruning is sound,
    so a surviving set is an over-approximation you can trust as an upper
    bound on what might hold.

  * A network that propagates cleanly may still be **unsatisfiable**.
    Deciding satisfiability for the full algebra is NP-complete
    (Vilain & Kautz 1986; Nebel & Bürckert 1995), and path consistency is
    the standard polynomial approximation.

  So `{:ok, network}` means "no contradiction was found", not "a
  consistent assignment exists". `{:error, {:inconsistent, pair}}` is
  definitive in the other direction: an empty set is a real contradiction.

  ## Example

      iex> alias Tempo.Interval.RelationNetwork, as: Net
      iex> net =
      ...>   Net.new([:fire, :rebuild, :occupation])
      ...>   |> Net.constrain(:fire, [:precedes], :rebuild)
      ...>   |> Net.constrain(:rebuild, [:during], :occupation)
      iex> {:ok, net} = Net.propagate(net)
      iex> Net.between(net, :fire, :occupation)
      [:precedes, :meets, :overlaps, :starts, :during]

  The fire precedes the rebuild, and the rebuild happened during the
  occupation — so the fire is somewhere before the occupation ended, but
  which of those five relations holds is not determined by what was
  asserted.

  """

  alias Tempo.Interval.Relations

  defstruct labels: [], edges: %{}

  @type label :: term()
  @type t :: %__MODULE__{labels: [label()], edges: %{{label(), label()} => Relations.t()}}

  @doc """
  A network over `labels`, with nothing asserted between any pair.

  Every pair starts as the full set of thirteen relations — the state of
  knowing nothing — and every period equals itself.

  ### Arguments

  * `labels` is a list of period identifiers. Any term may be a label.

  ### Returns

  * A `t:t/0`.

  ### Examples

      iex> net = Tempo.Interval.RelationNetwork.new([:a, :b])
      iex> Tempo.Interval.RelationNetwork.between(net, :a, :b) |> length()
      13

      iex> net = Tempo.Interval.RelationNetwork.new([:a, :b])
      iex> Tempo.Interval.RelationNetwork.between(net, :a, :a)
      [:equals]

  """
  @spec new([label()]) :: t()
  def new(labels) when is_list(labels) do
    unique = Enum.uniq(labels)

    edges =
      for a <- unique, b <- unique, a != b, into: %{} do
        {{a, b}, Relations.full()}
      end

    %__MODULE__{labels: unique, edges: edges}
  end

  @doc """
  The relations still possible from `a` to `b`.

  ### Arguments

  * `network` is a `t:t/0`.

  * `a` and `b` are labels in the network.

  ### Returns

  * The relation set, in Allen's canonical order.

  * `[:equals]` when `a` and `b` are the same label.

  * `{:error, {:unknown_label, label}}` when a label is not in the network.

  ### Examples

      iex> net = Tempo.Interval.RelationNetwork.new([:a, :b])
      iex> net = Tempo.Interval.RelationNetwork.constrain(net, :a, [:meets], :b)
      iex> Tempo.Interval.RelationNetwork.between(net, :a, :b)
      [:meets]

      iex> net = Tempo.Interval.RelationNetwork.new([:a, :b])
      iex> Tempo.Interval.RelationNetwork.between(net, :a, :zzz)
      {:error, {:unknown_label, :zzz}}

  """
  @spec between(t(), label(), label()) ::
          Relations.t() | {:error, {:unknown_label, label()}}
  def between(%__MODULE__{} = network, a, b) do
    with :ok <- known(network, a), :ok <- known(network, b) do
      if a == b, do: [:equals], else: Map.fetch!(network.edges, {a, b})
    end
  end

  @doc """
  Narrow what is possible from `a` to `b` by `relations`.

  Constraints accumulate: asserting twice narrows twice, and asserting
  something already known changes nothing. The converse is recorded on the
  reverse pair automatically, so `constrain(net, a, [:precedes], b)` also
  establishes that `b` is preceded by `a`.

  This records the assertion only. Call `propagate/1` to draw out what it
  implies for other pairs.

  ### Arguments

  * `network` is a `t:t/0`.

  * `a` and `b` are labels in the network.

  * `relations` is the set of relations to narrow by.

  ### Returns

  * The updated `t:t/0`.

  * `{:error, {:unknown_label, label}}` when a label is not in the network.

  * `{:error, {:invalid_relation, term}}` when `relations` holds something
    that is not one of the thirteen.

  ### Examples

      iex> alias Tempo.Interval.RelationNetwork, as: Net
      iex> net = Net.new([:a, :b]) |> Net.constrain(:a, [:precedes, :meets], :b)
      iex> Net.between(net, :b, :a)
      [:met_by, :preceded_by]

  Asserting a second constraint narrows rather than replaces:

      iex> alias Tempo.Interval.RelationNetwork, as: Net
      iex> net =
      ...>   Net.new([:a, :b])
      ...>   |> Net.constrain(:a, [:precedes, :meets], :b)
      ...>   |> Net.constrain(:a, [:meets, :overlaps], :b)
      iex> Net.between(net, :a, :b)
      [:meets]

  """
  @spec constrain(t(), label(), Relations.t(), label()) ::
          t() | {:error, {:unknown_label, label()} | {:invalid_relation, term()}}
  def constrain(%__MODULE__{} = network, a, relations, b) when is_list(relations) do
    with :ok <- known(network, a),
         :ok <- known(network, b),
         canonical when is_list(canonical) <- Relations.canonical(relations) do
      put_edge(network, a, b, Relations.narrow(between(network, a, b), canonical))
    end
  end

  @doc """
  Propagate every constraint to a fixpoint.

  Allen's §3 path consistency: for every triple, the relations possible
  from `i` to `k` are narrowed by what a step through `j` allows —
  `R(i,k) ← R(i,k) ∩ (R(i,j) ∘ R(j,k))` — repeated until nothing changes.

  Read the module docs before trusting the result: pruning is sound, but a
  clean pass is **not** proof of consistency.

  ### Arguments

  * `network` is a `t:t/0`.

  ### Returns

  * `{:ok, network}` with every set narrowed as far as path consistency
    reaches. No contradiction was found.

  * `{:error, {:inconsistent, {a, b}}}` when some pair narrowed to the
    empty set. That is definitive: the constraints cannot all hold.

  ### Examples

      iex> alias Tempo.Interval.RelationNetwork, as: Net
      iex> net =
      ...>   Net.new([:a, :b, :c])
      ...>   |> Net.constrain(:a, [:precedes], :b)
      ...>   |> Net.constrain(:b, [:precedes], :c)
      iex> {:ok, net} = Net.propagate(net)
      iex> Net.between(net, :a, :c)
      [:precedes]

  A cycle that cannot be satisfied is reported:

      iex> alias Tempo.Interval.RelationNetwork, as: Net
      iex> net =
      ...>   Net.new([:a, :b, :c])
      ...>   |> Net.constrain(:a, [:precedes], :b)
      ...>   |> Net.constrain(:b, [:precedes], :c)
      ...>   |> Net.constrain(:c, [:precedes], :a)
      iex> {:error, {:inconsistent, _pair}} = Net.propagate(net)

  """
  @spec propagate(t()) :: {:ok, t()} | {:error, {:inconsistent, {label(), label()}}}
  def propagate(%__MODULE__{} = network) do
    # An edge `constrain/4` already narrowed to nothing is a contradiction
    # the fixpoint would never notice: it only reports a set that empties
    # *while* narrowing, and an empty set narrows to itself unchanged.
    case Enum.find(network.edges, fn {_pair, relations} -> relations == [] end) do
      {pair, _empty} -> {:error, {:inconsistent, pair}}
      nil -> run(network, Map.keys(network.edges))
    end
  end

  @doc """
  Whether propagation finds no contradiction.

  ### Arguments

  * `network` is a `t:t/0`.

  ### Returns

  * `true` when `propagate/1` succeeds, `false` when it reports an
    inconsistency. A `true` result is not proof of satisfiability — see
    the module docs.

  ### Examples

      iex> alias Tempo.Interval.RelationNetwork, as: Net
      iex> Net.new([:a, :b]) |> Net.constrain(:a, [:precedes], :b) |> Net.consistent?()
      true

      iex> alias Tempo.Interval.RelationNetwork, as: Net
      iex> Net.new([:a, :b])
      ...> |> Net.constrain(:a, [:precedes], :b)
      ...> |> Net.constrain(:a, [:preceded_by], :b)
      ...> |> Net.consistent?()
      false

  """
  @spec consistent?(t()) :: boolean()
  def consistent?(%__MODULE__{} = network) do
    match?({:ok, _network}, propagate(network))
  end

  ## ------------------------------------------------------------
  ## Propagation
  ## ------------------------------------------------------------

  # Queue-driven fixpoint. A pair is queued when its set narrows; each
  # queued pair is re-examined against every third label, in both the
  # `(i,j),(j,k)` and `(k,i),(i,j)` directions, because either can tighten.
  defp run(network, []), do: {:ok, network}

  defp run(network, [{i, j} | queue]) do
    case revise_through(network, i, j, queue) do
      {:ok, network, queue} -> run(network, queue)
      {:error, _pair} = error -> error
    end
  end

  defp revise_through(network, i, j, queue) do
    network.labels
    |> Enum.reject(&(&1 == i or &1 == j))
    |> Enum.reduce_while({:ok, network, queue}, fn k, {:ok, network, queue} ->
      case revise_pair_both_ways(network, i, j, k, queue) do
        {:ok, _network, _queue} = ok -> {:cont, ok}
        {:error, _pair} = error -> {:halt, error}
      end
    end)
  end

  defp revise_pair_both_ways(network, i, j, k, queue) do
    with {:ok, network, queue} <- revise(network, i, k, compose_leg(network, i, j, k), queue) do
      revise(network, k, j, compose_leg(network, k, i, j), queue)
    end
  end

  defp compose_leg(network, from, via, to) do
    Relations.compose(between(network, from, via), between(network, via, to))
  end

  # Narrow `(a,b)` by `implied`; queue the pair when it actually changed.
  defp revise(network, a, b, implied, queue) do
    current = between(network, a, b)
    narrowed = Relations.narrow(current, implied)

    cond do
      narrowed == current -> {:ok, network, queue}
      narrowed == [] -> {:error, {:inconsistent, {a, b}}}
      true -> {:ok, put_edge(network, a, b, narrowed), [{a, b} | queue]}
    end
  end

  ## ------------------------------------------------------------
  ## Edges
  ## ------------------------------------------------------------

  # Every edge is stored with its converse, so `between/3` is a lookup in
  # either direction and the two can never disagree.
  defp put_edge(network, a, b, relations) do
    edges =
      network.edges
      |> Map.put({a, b}, relations)
      |> Map.put({b, a}, Relations.converse(relations))

    %{network | edges: edges}
  end

  defp known(%__MODULE__{labels: labels}, label) do
    if label in labels, do: :ok, else: {:error, {:unknown_label, label}}
  end
end
