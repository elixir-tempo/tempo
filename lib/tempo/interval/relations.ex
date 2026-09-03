defmodule Tempo.Interval.Relations do
  @moduledoc """
  Algebra over *sets* of Allen relations.

  `Tempo.relation/2` answers which single relation holds between two
  intervals you hold. When an interval is not yet grounded the answer is
  not one relation but a **set** of them — "the fire is either before or
  after the rebuild, never during" is `[:precedes, :preceded_by]`, and
  knowing nothing at all is all thirteen.

  This module is the algebra over those sets: the converse of a set, the
  narrowing of one set by another, and Allen's composition lifted from
  single relations to sets. Together they are the operations a
  qualitative constraint network is built from — Allen's propagation step
  is `narrow(known, compose(first_leg, second_leg))` — but they are
  useful on their own for reasoning about partial knowledge.

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
  The converse of a relation set — what holds from `B` to `A` given the
  set that holds from `A` to `B`.

  ### Arguments

  * `relations` is a list of Allen relations.

  ### Returns

  * The converse set, in Allen's canonical order.

  * `{:error, {:invalid_relation, term}}` when an element is not one of
    the thirteen.

  ### Examples

      iex> Tempo.Interval.Relations.converse([:precedes, :during])
      [:contains, :preceded_by]

      iex> Tempo.Interval.Relations.converse([:equals])
      [:equals]

  The converse of the full set is the full set — knowing nothing about
  `A` to `B` is knowing nothing about `B` to `A`:

      iex> Tempo.Interval.Relations.converse(Tempo.Interval.Relations.full())
      Tempo.Interval.Relations.full()

  """
  @spec converse(t()) :: t() | {:error, {:invalid_relation, term()}}
  def converse(relations) when is_list(relations) do
    with relations when is_list(relations) <- canonical(relations) do
      relations |> Enum.map(&Interval.inverse_relation/1) |> canonical()
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

  @doc """
  Compose two relation sets — the relations possible from `A` to `C`
  given a set from `A` to `B` and a set from `B` to `C`.

  Allen's composition (`Tempo.compose/2`) lifted from single relations to
  sets: the union of composing every pair. Because each element pair
  contributes everything it admits, composition widens — this is the step
  that loses information, and `narrow/2` is what claws it back.

  ### Arguments

  * `relations1` is the set of relations from `A` to `B`.

  * `relations2` is the set of relations from `B` to `C`.

  ### Returns

  * The union of the pairwise compositions, in Allen's canonical order.

  * The empty list when either argument is empty, since there is no
    consistent step through `B`.

  * `{:error, {:invalid_relation, term}}` when an element is not one of
    the thirteen.

  ### Examples

      iex> Tempo.Interval.Relations.compose([:precedes], [:precedes])
      [:precedes]

      iex> Tempo.Interval.Relations.compose([:precedes], [:during])
      [:precedes, :meets, :overlaps, :starts, :during]

  Composing with `equals` is the identity, since `B` and `C` are the same
  interval:

      iex> Tempo.Interval.Relations.compose([:overlaps, :during], [:equals])
      [:overlaps, :during]

  A step through an interval that cannot be placed yields nothing:

      iex> Tempo.Interval.Relations.compose([:precedes], [])
      []

  """
  @spec compose(t(), t()) :: t() | {:error, {:invalid_relation, term()}}
  def compose(relations1, relations2) when is_list(relations1) and is_list(relations2) do
    with relations1 when is_list(relations1) <- canonical(relations1),
         relations2 when is_list(relations2) <- canonical(relations2) do
      for(r1 <- relations1, r2 <- relations2, do: Interval.compose(r1, r2))
      |> Enum.concat()
      |> canonical()
    end
  end
end
