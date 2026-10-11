defmodule Tempo.Interval.Relations do
  @moduledoc """
  Algebra over *sets* of Allen relations.

  `Tempo.relation/2` answers which single relation holds between two
  intervals you hold. When an interval is not yet grounded the answer is
  not one relation but a **set** of them — "the fire is either before or
  after the rebuild, never during" is `[:precedes, :preceded_by]`, and
  knowing nothing at all is all thirteen.

  This module is the algebra over those sets — the full set, the empty
  one, canonical order, and the narrowing of one set by another — beside
  `Tempo.Allen.inverse/1` and `Tempo.Allen.compose/2`, which take sets
  too. Together they are the operations a qualitative constraint network
  is built from — Allen's propagation step is
  `narrow(known, Tempo.Allen.compose(first_leg, second_leg))` — but they
  are useful on their own for reasoning about partial knowledge.

  No interval is involved anywhere in this module. Its values are lists of
  relation atoms, always returned in Allen's canonical order so that two
  equivalent sets compare equal.

  """

  alias Tempo.Interval
  alias Tempo.Interval.Composition

  @type t :: [Interval.relation()]

  @doc """
  Every Allen relation — the set that asserts nothing.

  ### Returns

  * The thirteen relations in Allen's canonical order.

  ### Examples

      iex> Tempo.Interval.Relations.full() |> length()
      13

      iex> Tempo.Interval.Relations.full() |> hd()
      :precedes

  """
  @spec full() :: t()
  def full, do: Composition.relations()

  @doc """
  Whether a relation set is empty — the contradiction.

  An empty set means no relation can hold between the two intervals,
  which is to say the constraints that produced it cannot all be true.

  ### Arguments

  * `relations` is a list of Allen relations.

  ### Returns

  * `true` when the set is empty, `false` otherwise.

  ### Examples

      iex> Tempo.Interval.Relations.empty?([])
      true

      iex> Tempo.Interval.Relations.empty?([:precedes])
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(relations) when is_list(relations), do: relations == []

  @doc """
  Put a relation set in canonical form — deduplicated and in Allen's order.

  Two sets that assert the same thing compare equal after this, so a
  propagation loop can test for a fixpoint with `==`.

  ### Arguments

  * `relations` is a list of Allen relations, in any order, possibly with
    duplicates.

  ### Returns

  * The set in Allen's canonical order.

  * `{:error, {:invalid_relation, term}}` when an element is not one of
    the thirteen.

  ### Examples

      iex> Tempo.Interval.Relations.canonical([:during, :precedes, :during])
      [:precedes, :during]

      iex> Tempo.Interval.Relations.canonical([:precedes, :nonsense])
      {:error, {:invalid_relation, :nonsense}}

  """
  @spec canonical(t()) :: t() | {:error, {:invalid_relation, term()}}
  def canonical(relations) when is_list(relations) do
    case Enum.find(relations, &(&1 not in full())) do
      nil -> Enum.filter(full(), &(&1 in relations))
      invalid -> {:error, {:invalid_relation, invalid}}
    end
  end

  @doc """
  Narrow one relation set by another — what survives when two sources of
  knowledge about the same pair are combined.

  This is set intersection, named for what it is used for. It is *not*
  `Tempo.intersection/2`, which is set algebra over time values and
  returns the overlapping extent of two intervals; this combines
  constraints and returns the relations still possible.

  ### Arguments

  * `relations1` is a list of Allen relations.

  * `relations2` is a list of Allen relations.

  ### Returns

  * The relations present in both, in Allen's canonical order — the empty
    list when the two sources contradict each other.

  * `{:error, {:invalid_relation, term}}` when an element is not one of
    the thirteen.

  ### Examples

      iex> Tempo.Interval.Relations.narrow([:precedes, :meets, :overlaps], [:meets, :overlaps, :during])
      [:meets, :overlaps]

  Narrowing by the full set changes nothing, since it asserts nothing:

      iex> Tempo.Interval.Relations.narrow([:precedes], Tempo.Interval.Relations.full())
      [:precedes]

  Contradictory knowledge narrows to the empty set:

      iex> Tempo.Interval.Relations.narrow([:precedes], [:preceded_by])
      []

  """
  @spec narrow(t(), t()) :: t() | {:error, {:invalid_relation, term()}}
  def narrow(relations1, relations2) when is_list(relations1) and is_list(relations2) do
    with relations1 when is_list(relations1) <- canonical(relations1),
         relations2 when is_list(relations2) <- canonical(relations2) do
      Enum.filter(relations1, &(&1 in relations2))
    end
  end
end
