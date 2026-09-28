defmodule Tempo.Allen do
  @moduledoc """
  Allen's interval algebra, in Allen's own words.

  `Tempo`'s predicates answer the everyday questions about two spans:
  `Tempo.before?/2` is true when they share no instant and the first is
  earlier, and `Tempo.overlaps?/3` when they share any instant at all.
  James Allen's thirteen relations answer the exact question — which of
  thirteen mutually exclusive arrangements holds — and several of their
  names are narrower than the same English words: `:precedes` needs a gap
  between the two spans, and `:overlaps` means the first starts earlier
  and ends inside the second.

  This module keeps Allen's names for Allen's relations, so its name is
  the quotation marks: `Tempo.Allen.overlaps?/2` is the strict relation
  and `Tempo.overlaps?/3` the everyday one. `Tempo.relation/2` returns
  the relation that holds; each predicate here tests for one of them.

  | Relation | `a` … `b` |
  |---|---|
  | `:precedes` | ends before `b` starts, with a gap |
  | `:meets` | ends where `b` starts |
  | `:overlaps` | starts first and ends inside `b` |
  | `:finished_by` | starts first and ends with `b` |
  | `:contains` | starts before `b` and ends after it |
  | `:starts` | starts with `b` and ends inside it |
  | `:equals` | starts and ends with `b` |
  | `:started_by` | starts with `b` and ends after it |
  | `:during` | starts and ends inside `b` |
  | `:finishes` | starts inside `b` and ends with it |
  | `:overlapped_by` | starts inside `b` and ends after it |
  | `:met_by` | starts where `b` ends |
  | `:preceded_by` | starts after `b` ends, with a gap |

  `inverse/1` and `compose/2` reason about relations with no interval in
  hand, on a single relation or on a set of them.

  """

  alias Tempo.Interval
  alias Tempo.Interval.Composition
  alias Tempo.Interval.Relations

  @inverses %{
    precedes: :preceded_by,
    preceded_by: :precedes,
    meets: :met_by,
    met_by: :meets,
    overlaps: :overlapped_by,
    overlapped_by: :overlaps,
    starts: :started_by,
    started_by: :starts,
    finishes: :finished_by,
    finished_by: :finishes,
    during: :contains,
    contains: :during,
    equals: :equals
  }

  # {relation, what `a` does relative to `b`, example a, example b, the everyday counterpart}
  @relations [
    {:precedes, "ends before `b` starts, with a gap between them", ~s|~o"2026-01"|,
     ~s|~o"2026-03"|, "The everyday `Tempo.before?/2` also holds when `a` meets `b`."},
    {:meets, "ends exactly where `b` starts", ~s|~o"2026-01"|, ~s|~o"2026-02"|,
     "`Tempo.adjacent?/2` holds when either meets the other."},
    {:overlaps, "starts first and ends inside `b`", ~s|~o"2026-01/2026-03"|,
     ~s|~o"2026-02/2026-04"|, "The everyday `Tempo.overlaps?/3` holds for any shared instant."},
    {:finished_by, "starts first and ends with `b`", ~s|~o"2026-01/2026-04"|,
     ~s|~o"2026-03/2026-04"|, nil},
    {:contains, "starts before `b` and ends after it", ~s|~o"2026"|, ~s|~o"2026-06"|,
     "The everyday `Tempo.contains?/3` also holds when the two share an end."},
    {:starts, "starts with `b` and ends inside it", ~s|~o"2026-01"|, ~s|~o"2026-01/2026-04"|,
     nil},
    {:equals, "starts and ends with `b`", ~s|~o"2026-06"|, ~s|~o"2026-06"|,
     "`Tempo.equal?/3` asks the same of sets, instant by instant."},
    {:started_by, "starts with `b` and ends after it", ~s|~o"2026-01/2026-04"|, ~s|~o"2026-01"|,
     nil},
    {:during, "starts and ends inside `b`", ~s|~o"2026-06"|, ~s|~o"2026"|,
     "The everyday `Tempo.within?/3` also holds when the two share an end."},
    {:finishes, "starts inside `b` and ends with it", ~s|~o"2026-12"|, ~s|~o"2026"|, nil},
    {:overlapped_by, "starts inside `b` and ends after it", ~s|~o"2026-02/2026-04"|,
     ~s|~o"2026-01/2026-03"|, nil},
    {:met_by, "starts exactly where `b` ends", ~s|~o"2026-02"|, ~s|~o"2026-01"|, nil},
    {:preceded_by, "starts after `b` ends, with a gap between them", ~s|~o"2026-03"|,
     ~s|~o"2026-01"|, "The everyday `Tempo.after?/2` also holds when `a` is met by `b`."}
  ]

  for {relation, description, example_a, example_b, everyday} <- @relations do
    name = :"#{relation}?"
    note = if everyday, do: "\n" <> everyday <> "\n", else: ""

    @doc """
    `true` when `a` #{description} — Allen's `#{inspect(relation)}`.
    #{note}
    ### Arguments

    * `a` and `b` are each a bounded `t:Tempo.t/0`, `t:Tempo.Interval.t/0`
      or single-member `t:Tempo.IntervalSet.t/0`.

    ### Returns

    * `true` when the relation holds, `false` otherwise. Raises when an
      operand cannot be reduced to a single bounded interval, as
      `Tempo.relation/2` returns an error there.

    ### Examples

        iex> Tempo.Allen.#{name}(#{example_a}, #{example_b})
        true

    """
    @spec unquote(name)(Interval.interval_like(), Interval.interval_like()) :: boolean()
    def unquote(name)(a, b), do: holds?(a, b, unquote(relation))
  end

  @doc """
  The inverse of a relation — what holds from `b` to `a` when `relation`
  holds from `a` to `b`.

  If `Tempo.relation(a, b)` is `r`, then `Tempo.relation(b, a)` is
  `inverse(r)`. A set of relations inverts element by element.

  ### Arguments

  * `relation` is one of the thirteen relation atoms, or a list of them.

  ### Returns

  * The inverse relation, or for a list the inverse set in Allen's
    canonical order.

  * `{:error, {:invalid_relation, term}}` when a relation is not one of
    the thirteen.

  ### Examples

      iex> Tempo.Allen.inverse(:precedes)
      :preceded_by

      iex> Tempo.Allen.inverse([:precedes, :during])
      [:contains, :preceded_by]

  """
  @spec inverse(Interval.relation() | Relations.t()) ::
          Interval.relation() | Relations.t() | {:error, {:invalid_relation, term()}}
  def inverse(relations) when is_list(relations) do
    with relations when is_list(relations) <- Relations.canonical(relations) do
      relations |> Enum.map(&Map.fetch!(@inverses, &1)) |> Relations.canonical()
    end
  end

  def inverse(relation) do
    case Map.fetch(@inverses, relation) do
      {:ok, inverse} -> inverse
      :error -> {:error, {:invalid_relation, relation}}
    end
  end

  @doc """
  Compose two relations — the relations possible from `A` to `C` given
  that the first holds from `A` to `B` and the second from `B` to `C`.

  This is Allen's composition (Allen 1983), a constant-time read of the
  13×13 table. Where `Tempo.relation/2` compares two intervals you hold,
  `compose/2` takes one qualitative step with no interval in hand —
  *"if A precedes B and B is during C, how can A relate to C?"* — and
  returns every relation some arrangement of the three allows. Given sets
  of relations it composes every pair and returns the union, the widening
  step of a qualitative network (`Tempo.Interval.RelationNetwork`).

  ### Arguments

  * `first` is the relation, or set of relations, from `A` to `B`.

  * `second` is the relation, or set of relations, from `B` to `C`.

  ### Returns

  * The relations possible from `A` to `C`, in Allen's canonical order —
    one element when the step is determined, up to all thirteen when it
    is fully ambiguous, and none when a set is empty.

  * `{:error, {:invalid_relation, term}}` when a relation is not one of
    the thirteen.

  ### Examples

      iex> Tempo.Allen.compose(:precedes, :during)
      [:precedes, :meets, :overlaps, :starts, :during]

      iex> Tempo.Allen.compose([:overlaps, :during], [:equals])
      [:overlaps, :during]

      iex> Tempo.Allen.compose(:precedes, :nonsense)
      {:error, {:invalid_relation, :nonsense}}

  """
  @spec compose(Interval.relation() | Relations.t(), Interval.relation() | Relations.t()) ::
          Relations.t() | {:error, {:invalid_relation, term()}}
  def compose(first, second) when is_atom(first) and is_atom(second) do
    case Composition.compose(first, second) do
      nil -> {:error, {:invalid_relation, first_invalid(first, second)}}
      relations -> relations
    end
  end

  # A set, or a relation beside a set, composes element by element; a single
  # relation is the set of one.
  def compose(first, second) when is_list(first) or is_list(second) do
    with first when is_list(first) <- Relations.canonical(List.wrap(first)),
         second when is_list(second) <- Relations.canonical(List.wrap(second)) do
      for(r1 <- first, r2 <- second, do: Composition.compose(r1, r2))
      |> Enum.concat()
      |> Relations.canonical()
    end
  end

  def compose(first, second), do: {:error, {:invalid_relation, first_invalid(first, second)}}

  defp first_invalid(first, second) do
    if first in Composition.relations(), do: second, else: first
  end

  # A relation error must surface, not read as `false` — a silent false
  # asserts "the relation does not hold", a claim the error could not make.
  defp holds?(a, b, relation) do
    case Interval.relation(a, b) do
      held when is_atom(held) -> held == relation
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, to_string(reason)
    end
  end
end
