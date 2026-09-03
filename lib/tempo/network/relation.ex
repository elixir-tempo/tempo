defmodule Tempo.Network.Relation do
  @moduledoc """
  A chronological relation — a constraint between the boundaries of two
  time-periods.

  Relations are stored as data and translated to atomic Simple Temporal
  Problem constraints (`b₁ − b₂ ≤ k`) during normalisation. The
  vocabulary follows ChronoLog (Levy et al. 2020, Tables 1–5) and maps
  onto Allen's interval algebra where an Allen relation exists; the
  *metric* (delay) relations carry an integer offset Allen does not
  express.

  ### Relation types

  Qualitative (no parameters):

  * `:contemporary` — `A` and `B` overlap (non-empty intersection).

  * `:includes` / `:included_in` — `A` contains / is contained by `B`.

  * `:overlaps` / `:overlapped_by` — `A` overlaps and precedes /
    follows `B` (a shared extent, neither containing the other).

  * `:starts_during` / `:includes_start` — `A`'s start falls within
    `B` / `B`'s start falls within `A`.

  * `:ends_during` / `:includes_end` — `A`'s end falls within `B` /
    `B`'s end falls within `A`.

  * `:before` / `:after` — `A` is strictly before / after `B`
    (no overlap).

  * `:immediately_precedes` / `:immediately_follows` — `end(A)=start(B)`
    and the dual.

  * `:synchronous_start` / `:synchronous_end` — shared start / end
    boundary (in either direction; the loose form of Allen's
    `starts`/`started_by` and `finishes`/`finished_by`).

  * `:starts` / `:started_by` — `A` and `B` share a start boundary and
    `A` ends no later than / no earlier than `B` (Allen's `starts` /
    `started_by`).

  * `:finishes` / `:finished_by` — `A` and `B` share an end boundary
    and `A` starts no earlier than / no later than `B` (Allen's
    `finishes` / `finished_by`).

  * `:strictly_contemporary` — `A` and `B` share a non-empty *interior*
    (overlap of positive extent, not merely a touching boundary).

  * `:equals` — identical start and end.

  Metric (parameterised by a duration and a comparison):

  * `{:delay, edge_a, edge_b, comparison, duration}` — the `edge_a`
    boundary of `A` is `comparison` (`:exactly` | `:at_least` |
    `:at_most`) `duration` before the `edge_b` boundary of `B`, where
    each edge is `:start` or `:end`.

  Boundary (a single comparison between one boundary of each period):

  * `{:boundary, edge_a, comparison, edge_b}` — the `edge_a` boundary of
    `A` is `comparison` the `edge_b` boundary of `B`, where `comparison`
    is `:before` (strictly), `:at_or_before`, `:coincident` (equal),
    `:at_or_after`, or `:after` (strictly). This is the complete
    boundary-inequality lattice: any of ChronoLog's "starts/ends
    before/after/at the start/end of" synchronisms is one such relation
    (e.g. `{:boundary, :end, :at_or_before, :start}` is "ends before or
    at the start of").

  """

  @type edge :: :start | :end
  @type comparison :: :exactly | :at_least | :at_most

  @typedoc """
  A comparison between two boundaries: strictly `:before`,
  `:at_or_before` (≤), `:coincident` (=), `:at_or_after` (≥), or
  strictly `:after`.
  """
  @type boundary_comparison ::
          :before | :at_or_before | :coincident | :at_or_after | :after

  @type relation_type ::
          :contemporary
          | :includes
          | :included_in
          | :overlaps
          | :overlapped_by
          | :starts_during
          | :includes_start
          | :ends_during
          | :includes_end
          | :before
          | :after
          | :immediately_precedes
          | :immediately_follows
          | :synchronous_start
          | :synchronous_end
          | :starts
          | :started_by
          | :finishes
          | :finished_by
          | :strictly_contemporary
          | :equals
          | {:delay, edge(), edge(), comparison(), Tempo.Duration.t()}
          | {:boundary, edge(), boundary_comparison(), edge()}

  @type t :: %__MODULE__{
          type: relation_type(),
          from: term(),
          to: term(),
          metadata: map()
        }

  defstruct [:type, :from, :to, metadata: %{}]

  @doc """
  Build a relation between two periods.

  ### Arguments

  * `type` is a relation type (see the module documentation).

  * `from` and `to` are the ids of the two periods the relation
    constrains, read as "`from` *type* `to`".

  ### Options

  * `:metadata` is an arbitrary map carried with the relation.

  ### Returns

  * a `t:Tempo.Network.Relation.t/0`.

  ### Examples

      iex> relation = Tempo.Network.Relation.new(:included_in, :s1, :k1)
      iex> {relation.type, relation.from, relation.to}
      {:included_in, :s1, :k1}

  """
  @spec new(relation_type(), term(), term(), keyword()) :: t()
  def new(type, from, to, options \\ []) do
    %__MODULE__{
      type: type,
      from: from,
      to: to,
      metadata: Keyword.get(options, :metadata, %{})
    }
  end

  @typedoc """
  A boundary variable in the constraint graph: the start or end of a
  period, or the network origin `z₀`.
  """
  @type boundary :: {:start, term()} | {:end, term()} | :origin

  @typedoc """
  An edge weight. An integer is a fixed offset in the network's unit
  (`0` for `≤`, `-1` for a strict `<`); a duration weight is resolved
  to an integer by normalisation once the unit is known.
  """
  @type weight ::
          integer() | {:duration, Tempo.Duration.t()} | {:neg_duration, Tempo.Duration.t()}

  @typedoc """
  An atomic Simple Temporal Problem constraint `from − to ≤ weight`,
  one directed weighted edge `from → to` in the constraint graph.
  """
  @type atomic :: {boundary(), boundary(), weight()}

  @doc """
  Translate a relation into its atomic STP constraints.

  Each constraint has the single shape `from − to ≤ weight` (ISO of the
  paper's §3). An equality becomes two constraints; a strict `<` on the
  integer time-scale becomes `≤ -1`; a metric (delay) relation carries a
  duration weight that normalisation later resolves to an integer.

  ### Arguments

  * `relation` is a `t:Tempo.Network.Relation.t/0`.

  ### Returns

  * a list of `t:Tempo.Network.Relation.atomic/0` constraints.

  ### Examples

      iex> Tempo.Network.Relation.new(:before, :a, :b) |> Tempo.Network.Relation.to_atomic()
      [{{:end, :a}, {:start, :b}, -1}]

      iex> Tempo.Network.Relation.new(:immediately_precedes, :a, :b) |> Tempo.Network.Relation.to_atomic()
      [{{:end, :a}, {:start, :b}, 0}, {{:start, :b}, {:end, :a}, 0}]

      iex> Tempo.Network.Relation.new({:boundary, :end, :at_or_before, :start}, :a, :b) |> Tempo.Network.Relation.to_atomic()
      [{{:end, :a}, {:start, :b}, 0}]

  """
  @spec to_atomic(t()) :: [atomic()]
  # A flat dispatch over the relation vocabulary — its cyclomatic
  # complexity is the number of relation types, not branching logic.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def to_atomic(%__MODULE__{type: type, from: a, to: b}), do: atomic_for(type, a, b)

  # end(A) ≥ start(B) ∧ end(B) ≥ start(A) — non-empty overlap.
  defp atomic_for(:contemporary, a, b),
    do: [le(start(b), finish(a), 0), le(start(a), finish(b), 0)]

  # start(A) ≤ start(B) ∧ end(B) ≤ end(A).
  defp atomic_for(:includes, a, b),
    do: [le(start(a), start(b), 0), le(finish(b), finish(a), 0)]

  # start(B) ≤ start(A) ∧ end(A) ≤ end(B).
  defp atomic_for(:included_in, a, b),
    do: [le(start(b), start(a), 0), le(finish(a), finish(b), 0)]

  # Overlaps succeeding (Table 2): start(A) ≤ start(B) ≤ end(A) ≤ end(B).
  defp atomic_for(:overlaps, a, b),
    do: [le(start(a), start(b), 0), le(start(b), finish(a), 0), le(finish(a), finish(b), 0)]

  # Overlaps preceding: start(B) ≤ start(A) ≤ end(B) ≤ end(A).
  defp atomic_for(:overlapped_by, a, b),
    do: [le(start(b), start(a), 0), le(start(a), finish(b), 0), le(finish(b), finish(a), 0)]

  # A starts during B: start(B) ≤ start(A) ≤ end(B).
  defp atomic_for(:starts_during, a, b),
    do: [le(start(b), start(a), 0), le(start(a), finish(b), 0)]

  # A includes the start of B: start(A) ≤ start(B) ≤ end(A).
  defp atomic_for(:includes_start, a, b),
    do: [le(start(a), start(b), 0), le(start(b), finish(a), 0)]

  # A ends during B: start(B) ≤ end(A) ≤ end(B).
  defp atomic_for(:ends_during, a, b),
    do: [le(start(b), finish(a), 0), le(finish(a), finish(b), 0)]

  # A includes the end of B: start(A) ≤ end(B) ≤ end(A).
  defp atomic_for(:includes_end, a, b),
    do: [le(start(a), finish(b), 0), le(finish(b), finish(a), 0)]

  defp atomic_for(:before, a, b), do: [lt(finish(a), start(b))]

  defp atomic_for(:after, a, b), do: [lt(finish(b), start(a))]

  defp atomic_for(:immediately_precedes, a, b), do: eq(finish(a), start(b))

  defp atomic_for(:immediately_follows, a, b), do: eq(start(a), finish(b))

  defp atomic_for(:synchronous_start, a, b), do: eq(start(a), start(b))

  defp atomic_for(:synchronous_end, a, b), do: eq(finish(a), finish(b))

  defp atomic_for(:equals, a, b), do: eq(start(a), start(b)) ++ eq(finish(a), finish(b))

  # Shared start, A ends no later / no earlier than B (Allen starts / started_by).
  defp atomic_for(:starts, a, b), do: eq(start(a), start(b)) ++ [le(finish(a), finish(b), 0)]

  defp atomic_for(:started_by, a, b), do: eq(start(a), start(b)) ++ [le(finish(b), finish(a), 0)]

  # Shared end, A starts no earlier / no later than B (Allen finishes / finished_by).
  defp atomic_for(:finishes, a, b), do: eq(finish(a), finish(b)) ++ [le(start(b), start(a), 0)]

  defp atomic_for(:finished_by, a, b), do: eq(finish(a), finish(b)) ++ [le(start(a), start(b), 0)]

  # Non-empty interior overlap: start(B) < end(A) ∧ start(A) < end(B).
  defp atomic_for(:strictly_contemporary, a, b),
    do: [lt(start(b), finish(a)), lt(start(a), finish(b))]

  defp atomic_for({:delay, edge_a, edge_b, comparison, duration}, a, b),
    do: delay_atomic(boundary(edge_a, a), boundary(edge_b, b), comparison, duration)

  defp atomic_for({:boundary, edge_a, comparison, edge_b}, a, b),
    do: boundary_atomic(boundary(edge_a, a), comparison, boundary(edge_b, b))

  defp start(id), do: {:start, id}
  defp finish(id), do: {:end, id}

  # from − to ≤ k.
  defp le(from, to, k), do: {from, to, k}

  # from < to  ⇒  from − to ≤ -1 (strict on the integer time-scale).
  defp lt(from, to), do: {from, to, -1}

  # from = to  ⇒  from − to ≤ 0 ∧ to − from ≤ 0.
  defp eq(from, to), do: [{from, to, 0}, {to, from, 0}]

  defp boundary(:start, id), do: {:start, id}
  defp boundary(:end, id), do: {:end, id}

  # "edge_a is `comparison` `duration` before edge_b": with the offset
  # `bb − ba`, exactly = d, at least ≥ d, at most ≤ d.
  defp delay_atomic(ba, bb, :exactly, duration) do
    [{bb, ba, {:duration, duration}}, {ba, bb, {:neg_duration, duration}}]
  end

  defp delay_atomic(ba, bb, :at_least, duration) do
    [{ba, bb, {:neg_duration, duration}}]
  end

  defp delay_atomic(ba, bb, :at_most, duration) do
    [{bb, ba, {:duration, duration}}]
  end

  # "ba is `comparison` bb": one boundary of A against one of B.
  defp boundary_atomic(ba, :before, bb), do: [lt(ba, bb)]
  defp boundary_atomic(ba, :at_or_before, bb), do: [le(ba, bb, 0)]
  defp boundary_atomic(ba, :coincident, bb), do: eq(ba, bb)
  defp boundary_atomic(ba, :at_or_after, bb), do: [le(bb, ba, 0)]
  defp boundary_atomic(ba, :after, bb), do: [lt(bb, ba)]

  @doc """
  The Allen interval relation(s) a chronological relation corresponds
  to, for querying a solved network with `Tempo.Interval` predicates.

  Returns a single Allen atom for a one-to-one correspondence, a list
  when the relation is the disjunction of several Allen relations (e.g.
  `:contemporary`), or `nil` for a metric relation Allen cannot express.

  ### Examples

      iex> Tempo.Network.Relation.to_allen(:before)
      :precedes

      iex> Tempo.Network.Relation.to_allen(:synchronous_start)
      [:starts, :started_by, :equals]

  """
  @spec to_allen(relation_type()) :: atom() | [atom()] | nil
  def to_allen(:before), do: :precedes
  def to_allen(:after), do: :preceded_by
  def to_allen(:immediately_precedes), do: :meets
  def to_allen(:immediately_follows), do: :met_by
  def to_allen(:overlaps), do: :overlaps
  def to_allen(:overlapped_by), do: :overlapped_by
  def to_allen(:includes), do: :contains
  def to_allen(:included_in), do: :during
  def to_allen(:equals), do: :equals
  def to_allen(:starts), do: :starts
  def to_allen(:started_by), do: :started_by
  def to_allen(:finishes), do: :finishes
  def to_allen(:finished_by), do: :finished_by
  def to_allen(:synchronous_start), do: [:starts, :started_by, :equals]
  def to_allen(:synchronous_end), do: [:finishes, :finished_by, :equals]

  # Period synchronisms are looser than any single Allen relation.
  def to_allen(:starts_during), do: nil
  def to_allen(:includes_start), do: nil
  def to_allen(:ends_during), do: nil
  def to_allen(:includes_end), do: nil

  def to_allen(:strictly_contemporary),
    do: [
      :overlaps,
      :overlapped_by,
      :starts,
      :started_by,
      :during,
      :contains,
      :finishes,
      :finished_by
    ]

  def to_allen(:contemporary),
    do: [
      :overlaps,
      :overlapped_by,
      :starts,
      :started_by,
      :during,
      :contains,
      :finishes,
      :finished_by,
      :equals
    ]

  def to_allen({:delay, _, _, _, _}), do: nil

  # A single boundary inequality is looser than any one Allen relation.
  def to_allen({:boundary, _, _, _}), do: nil

  @doc """
  The chronological relation type naming a given Allen relation.

  The inverse of `to_allen/1`, direction-preserving for every relation
  that has a chronological type: `from_allen(to_allen(type)) == type` for
  all thirteen one-to-one cases.

  ### Examples

      iex> Tempo.Network.Relation.from_allen(:meets)
      :immediately_precedes

      iex> Tempo.Network.Relation.from_allen(:during)
      :included_in

  """
  @spec from_allen(atom()) :: relation_type()
  def from_allen(:precedes), do: :before
  def from_allen(:preceded_by), do: :after
  def from_allen(:meets), do: :immediately_precedes
  def from_allen(:met_by), do: :immediately_follows
  def from_allen(:overlaps), do: :overlaps
  def from_allen(:overlapped_by), do: :overlapped_by
  def from_allen(:contains), do: :includes
  def from_allen(:during), do: :included_in
  def from_allen(:equals), do: :equals
  def from_allen(:starts), do: :starts
  def from_allen(:started_by), do: :started_by
  def from_allen(:finishes), do: :finishes
  def from_allen(:finished_by), do: :finished_by
end
