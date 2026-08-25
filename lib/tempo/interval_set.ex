defmodule Tempo.IntervalSet do
  @moduledoc """
  A sorted, non-overlapping collection of `t:Tempo.Interval.t/0`
  values — the multi-interval counterpart to `Tempo.Interval`.

  `IntervalSet` is the operational form for set operations. Every
  AST shape that expands to a disjoint list of bounded spans
  (non-contiguous masks, stepped ranges, iterated groups, bounded
  recurrences, all-of sets) materialises to an `IntervalSet` via
  `Tempo.to_interval/1`.

  ## Storage backends

  The representation is pluggable through `Tempo.IntervalSet.Backend`:
  the struct carries a `:backend` module and opaque backend state, and
  every function here reaches the members through that contract. The
  default is `Tempo.IntervalSet.Backend.List` — a sorted plain list.
  Select a backend at construction with `new(intervals, backend: ...)`;
  member-preserving operations keep their operand's backend.

  ## Invariants

  The constructor `new/1` guarantees:

  * Intervals are sorted ascending by `from`.

  * Adjacent or overlapping intervals are coalesced. Half-open
    semantics means `[a, b) ++ [b, c) == [a, c)` — the coalesce
    pass merges both overlap and touch cases.

  * No missing endpoints, spelled either `:undefined` (an ISO 8601
    open interval such as `2020Y/..`) or `nil` (an unanchored
    recurrence). Neither has an extent, so neither can participate
    in a set; the caller must bound them first.

  ## Counting

  A set answers three different "how much" questions, and they return
  very different numbers — reach for the one that matches intent:

  * **How many windows** (member spans)? — `count/1`, the set's
    cardinality.

  * **How many sub-points** (days, hours, … at the members'
    resolution)? — `Enum.count/1`. The `Enumerable` protocol walks
    *into* each member and yields its stepped points, so this totals
    across every window, not the number of windows.

  * **How long** (elapsed time)? — `Tempo.duration/1` on the whole
    set (the members' total) or on a member, or `Tempo.at_least?/2`
    to keep only windows of a given length. Never
    count sub-points for this: across a DST boundary the walk skips the
    spring-forward hour and emits the fall-back hour twice, so
    `Enum.count` deliberately diverges from elapsed time.

  A two-window set — January and March — is `2` windows but `62`
  sub-points (31 + 31 days):

      iex> {:ok, free} = Tempo.union(~o"2026Y1M", ~o"2026Y3M")
      iex> Tempo.IntervalSet.count(free)
      2
      iex> Enum.count(free)
      62

  ## Timezone handling

  An IntervalSet preserves the wall-clock + zone form of its member
  intervals on the struct. Any set operation that needs to compare
  endpoints across zones derives a UTC projection on demand; no
  UTC cache is stored on the struct. This keeps results stable when
  the zone database updates — re-running the operation simply uses whatever
  zone rules are current at the time of the call.

  See `guides/enumeration-semantics.md` for the full discussion of
  wall-clock-vs-UTC authority.

  """

  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet.Backend
  alias Tempo.UnboundedSetError

  @typedoc """
  The set struct. `:intervals` holds the backend's state — for the
  default `Tempo.IntervalSet.Backend.List` that is the member list
  itself; other backends store their own representation there. Reach
  members through the named accessors (`to_list/1`, `walk/1`,
  `count/1`, `empty?/1`, `first/1`), never the field.
  """
  @type t :: %__MODULE__{
          intervals: Backend.state(),
          metadata: map(),
          backend: module()
        }

  defstruct intervals: [], metadata: %{}, backend: Backend.List

  @doc """
  Construct a `t:t/0` from a list of intervals.

  The input list is sorted ascending by `from` endpoint and
  coalesced — adjacent or overlapping intervals are merged under
  the half-open `[from, to)` convention.

  ### Arguments

  * `intervals` is a list of `t:Tempo.Interval.t/0` values. Intervals
    missing an endpoint are rejected, whether it is `:undefined` (an
    ISO 8601 open interval) or `nil` (an unanchored recurrence).

  ### Options

  * `:coalesce` merges touching or overlapping members into larger
    spans. The default is `false` — member identity is preserved.

  * `:metadata` is a map of set-level metadata. The default is `%{}`.

  * `:backend` is the storage backend module (see
    `Tempo.IntervalSet.Backend`), or a shorthand — `:list` (the
    default, `Tempo.IntervalSet.Backend.List`) or `:tree`
    (`Tempo.IntervalSet.Backend.Tree`, an interval tree for large,
    query-heavy sets of anchored members).

  ### Returns

  * `{:ok, interval_set}` where `interval_set` is a `t:t/0`, or

  * `{:error, reason}` when an input interval is open-ended or
    otherwise cannot participate in a set.

  ### Examples

      iex> {:ok, a} = Tempo.to_interval(~o"2022Y1M")
      iex> {:ok, b} = Tempo.to_interval(~o"2022Y3M")
      iex> {:ok, set} = Tempo.IntervalSet.new([b, a])
      iex> Tempo.IntervalSet.count(set)
      2
      iex> Tempo.IntervalSet.first(set).from.time
      [year: 2022, month: 1]

  """
  @spec new([Interval.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def new(intervals, opts \\ []) when is_list(intervals) do
    with :ok <- validate_all_bounded(intervals) do
      # `coalesce: false` is the default: IntervalSet preserves
      # member identity by design. Callers who want canonical
      # instant-set form (touching or overlapping intervals merged
      # into larger spans) must either pass `coalesce: true` here
      # or apply `coalesce/1` explicitly after construction.
      coalesce? = Keyword.get(opts, :coalesce, false)
      backend = resolve_backend(Keyword.get(opts, :backend, Backend.List))

      sorted = Enum.sort(intervals, &compare_from/2)
      final = if coalesce?, do: coalesce_intervals(sorted), else: sorted
      metadata = Keyword.get(opts, :metadata, %{})

      {:ok,
       %__MODULE__{
         intervals: backend.from_list(final, opts),
         metadata: metadata,
         backend: backend
       }}
    end
  end

  defp resolve_backend(:list), do: Backend.List
  defp resolve_backend(:tree), do: Backend.Tree
  defp resolve_backend(:lazy), do: Backend.Lazy
  defp resolve_backend(module) when is_atom(module), do: module

  @doc """
  Construct a lazy, potentially unbounded set from an ordered
  generator.

  The generator is any `Enumerable` (typically a `Stream`) yielding
  member intervals in time order — sorted by `from`, disjoint, each
  anchored and bounded. An infinite generator cannot be validated up
  front, so this contract is the caller's responsibility; members are
  checked as they are consumed. See `Tempo.IntervalSet.Backend.Lazy`
  for what a lazy set can and cannot answer.

  ### Arguments

  * `enumerable` is the ordered member generator.

  * `options` is a keyword list of options.

  ### Options

  * `:metadata` is a map of set-level metadata. The default is `%{}`.

  ### Returns

  * A `t:t/0` on the lazy backend.

  ### Examples

      iex> mondays = Stream.iterate(~o"2026-01-05", &Tempo.shift(&1, week: 1))
      iex> set = mondays |> Stream.map(&Tempo.to_interval!/1) |> Tempo.IntervalSet.from_stream()
      iex> set |> Tempo.IntervalSet.walk() |> Enum.take(2) |> Enum.map(& &1.from.time[:day])
      [5, 12]

  """
  @spec from_stream(Enumerable.t(), keyword()) :: t()
  def from_stream(enumerable, options \\ []) do
    %__MODULE__{
      intervals: enumerable,
      metadata: Keyword.get(options, :metadata, %{}),
      backend: Backend.Lazy
    }
  end

  @doc """
  Raising version of `new/1`.
  """
  @spec new!([Interval.t()], keyword()) :: t()
  def new!(intervals, opts \\ []) do
    case new(intervals, opts) do
      {:ok, set} -> set
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  @doc """
  Return the member intervals as a plain list.

  The `Enumerable` protocol implementation for an IntervalSet
  walks every sub-point inside each interval (consistent with
  the Tempo and Tempo.Interval `Enumerable` implementations —
  every Tempo value is a span, iteration walks its sub-points at
  the next-finer resolution).

  When you want to operate on the **member intervals** instead
  — filter them, count them, map them — `to_list/1` gives you
  a plain list you can pipe into `Enum`. `members/1` is the same
  function under a name that says which list you are getting, and
  reads better at a call site where the distinction matters.

  ### Examples

      iex> {:ok, set} = Tempo.IntervalSet.new([
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"},
      ...>   %Tempo.Interval{from: ~o"2026-07-01", to: ~o"2026-07-10"}
      ...> ])
      iex> set |> Tempo.IntervalSet.to_list() |> length()
      2

  Pair with the interval predicates for expressive scheduling:

      set
      |> Tempo.IntervalSet.to_list()
      |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))

  """
  @spec to_list(t()) :: [Interval.t()]
  def to_list(%__MODULE__{backend: backend, intervals: state} = set) do
    ensure_bounded!(set, "Tempo.IntervalSet.to_list/1")
    backend.to_list(state)
  end

  @doc """
  The member intervals, as a plain list.

  The same value and the same cost as `to_list/1`, under a name that
  says *which* list you get. An IntervalSet has two plausible ones and
  they are wildly different sizes: `Enum` walks the sub-points inside
  the set, while this walks the intervals the set is made of.

      {:ok, set} = Tempo.IntervalSet.new([
        ~o"2026-06-15T09:00:00/2026-06-15T12:00:00",
        ~o"2026-06-15T13:00:00/2026-06-15T17:00:00"
      ])

      Enum.count(set)                       #=> 25200 — every second
      Tempo.IntervalSet.members(set) |> length()  #=> 2 — the two blocks

  Prefer `members/1` wherever the intent is "the intervals this set is
  made of". `to_list/1` remains, because converting a collection to a
  list is an idiom Elixir readers expect to find, and the two are
  interchangeable.

  The trap `members/1` is named to avoid: at day resolution the two
  counts *agree* — a five-member set of days enumerates as five days —
  so code that reaches for `Enum` is correct until the day someone
  passes it hours, and then it is silently wrong by a factor of the
  granularity. See `walk/1` for the lazy counterpart.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * The member intervals in time order, as a list.

  ### Examples

      iex> {:ok, set} = Tempo.IntervalSet.new([
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"},
      ...>   %Tempo.Interval{from: ~o"2026-07-01", to: ~o"2026-07-10"}
      ...> ])
      iex> Tempo.IntervalSet.members(set) |> length()
      2

      iex> {:ok, set} = Tempo.IntervalSet.new([~o"2026-06-15T09:00:00/2026-06-15T12:00:00"])
      iex> Tempo.IntervalSet.members(set) == Tempo.IntervalSet.to_list(set)
      true

  """
  @spec members(t()) :: [Interval.t()]
  def members(%__MODULE__{} = set), do: to_list(set)

  @doc """
  An enumerable yielding the member intervals in time order.

  The lazy-safe counterpart to `to_list/1`: on the default list
  backend it is the member list; on a lazy backend it is a stream
  that never materialises more members than the caller consumes.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * An `Enumerable` of `t:Tempo.Interval.t/0` members in time order.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}
      ...> ])
      iex> set |> Tempo.IntervalSet.walk() |> Enum.count()
      1

  """
  @spec walk(t()) :: Enumerable.t()
  def walk(%__MODULE__{backend: backend, intervals: state}), do: backend.walk(state)

  @doc """
  Return the number of member intervals in the set.

  A named helper so callers never have to write
  `length(set.intervals)` or `length(to_list(set))` in
  user-facing code.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * The count of member intervals as a non-negative integer.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"},
      ...>   %Tempo.Interval{from: ~o"2026-07-01", to: ~o"2026-07-10"}
      ...> ])
      iex> Tempo.IntervalSet.count(set)
      2

  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{backend: backend, intervals: state} = set) do
    ensure_bounded!(set, "Tempo.IntervalSet.count/1")
    backend.count(state)
  end

  @doc """
  Whether the set has no member intervals.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * `true` when the set is empty, otherwise `false`.

  ### Examples

      iex> Tempo.IntervalSet.empty?(Tempo.IntervalSet.new!([]))
      true

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}
      ...> ])
      iex> Tempo.IntervalSet.empty?(set)
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{backend: backend, intervals: state}), do: backend.empty?(state)

  @doc """
  The earliest member interval of the set, or `nil` when the set
  is empty.

  Members are held in time order, so this is the interval with the
  earliest `from` endpoint.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * The first `t:Tempo.Interval.t/0`, or `nil` for an empty set.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-07-01", to: ~o"2026-07-10"},
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}
      ...> ])
      iex> Tempo.IntervalSet.first(set).from
      ~o"2026Y6M1D"

      iex> Tempo.IntervalSet.first(Tempo.IntervalSet.new!([]))
      nil

  """
  @spec first(t()) :: Interval.t() | nil
  def first(%__MODULE__{backend: backend, intervals: state}), do: backend.first(state)

  @doc """
  Whether the set's backend holds a finite member list.

  `true` on the list and tree backends; `false` on a lazy generator
  backend, where aggregate operations (`to_list/1`, `count/1`,
  `coalesce/1`, set algebra) raise `Tempo.UnboundedSetError` instead
  of walking forever.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * `true` when every member can be materialised, otherwise `false`.

  ### Examples

      iex> Tempo.IntervalSet.bounded?(Tempo.IntervalSet.new!([]))
      true

  """
  @spec bounded?(t()) :: boolean()
  def bounded?(%__MODULE__{backend: backend, intervals: state}), do: backend.bounded?(state)

  # The refusal gate for aggregate operations: raising (not an error
  # tuple) because these functions have no error shape and a silent
  # infinite walk is the alternative.
  defp ensure_bounded!(%__MODULE__{} = set, operation) do
    if bounded?(set) do
      set
    else
      raise UnboundedSetError.exception(operation: operation, set: set)
    end
  end

  @doc false
  # Replace the member list, keeping the set's metadata (and, once
  # backends land, its backend). The internal counterpart to `new/2`
  # for representation-preserving rewrites; members must already be
  # sorted and disjoint.
  @spec with_intervals(t(), [Interval.t()]) :: t()
  def with_intervals(%__MODULE__{backend: backend} = set, intervals) when is_list(intervals) do
    %{set | intervals: backend.from_list(intervals, [])}
  end

  @doc """
  Total covered duration of the set — the sum of every member's
  length.

  Each member's length is measured on the UTC time line (the same
  measurement as `Tempo.Interval.duration/1`), so DST transitions
  inside a member are accounted for. Members are disjoint by
  construction when produced by the set operations; if the set was
  built with overlapping members deliberately preserved, the overlap
  is counted once per member.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * A `t:Tempo.Duration.t/0` holding the total in seconds. The empty
    set has a duration of zero seconds.

  ### Examples

      iex> {:ok, free} = Tempo.union(~o"2026-06-01T09/2026-06-01T12", ~o"2026-06-01T14/2026-06-01T17")
      iex> Tempo.IntervalSet.duration(free)
      ~o"PT21600S"

  """
  @spec duration(t()) :: Duration.t()
  def duration(%__MODULE__{} = set) do
    intervals = to_list(set)

    total =
      Enum.reduce(intervals, 0, fn interval, acc ->
        %Duration{time: [second: seconds]} = Interval.duration(interval)
        acc + seconds
      end)

    %Duration{time: [second: total]}
  end

  @doc """
  Cut each member into consecutive fixed-length bookable slots.

  Turns a region of free time into the discrete slots you could actually
  book within it. Within each member interval, slots of length
  `duration` are emitted starting at the member's start and spaced by
  `:every` (a slot every `duration` by default — back-to-back,
  non-overlapping); a slot is kept only if it fits entirely inside the
  member. The members stay distinct (the result is *not* coalesced).

  This is the slicing counterpart to the set operations: where
  `difference`/`intersection` give you the free *regions*,
  `slots/3` cuts those regions into the fixed-length windows a
  booking UI offers.

  ### Arguments

  * `set` is a `t:t/0` or a single `t:Tempo.Interval.t/0` (as returned
    by a set operation on a connected result).

  * `duration` is the slot length, a `t:Tempo.Duration.t/0`.

  ### Options

  * `:every` is the spacing between slot starts, a
    `t:Tempo.Duration.t/0`. Defaults to `duration` (adjacent slots).
    A smaller value yields overlapping slots; a larger value leaves
    gaps. Must be positive.

  ### Metadata

  Each slot carries the metadata of the member it was cut from, so a
  region tagged with the resource it belongs to yields slots that are
  still tagged with it. Cutting cannot create a conflict — every slot
  comes from exactly one member.

  ### Returns

  * a `t:t/0` of the fitting slots, in order.

  ### Examples

      iex> work = Tempo.Interval.new!(from: ~o"2026-06-15T09:00:00", to: ~o"2026-06-15T12:00:00")
      iex> work |> Tempo.IntervalSet.slots(~o"PT1H") |> Tempo.IntervalSet.count()
      3

      iex> work = Tempo.Interval.new!(from: ~o"2026-06-15T09:00:00", to: ~o"2026-06-15T12:00:00")
      iex> work |> Tempo.IntervalSet.slots(~o"PT1H", every: ~o"PT30M") |> Tempo.IntervalSet.count()
      5

  """
  @spec slots(t() | Interval.t(), Tempo.Duration.t(), keyword()) :: t()
  def slots(set, duration, options \\ [])

  def slots(%Interval{} = interval, duration, options) do
    slots(%__MODULE__{intervals: [interval]}, duration, options)
  end

  def slots(%__MODULE__{} = set, %Tempo.Duration{} = duration, options) do
    intervals = to_list(set)

    every = Keyword.get(options, :every, duration)

    intervals
    |> Enum.flat_map(&interval_slots(&1, duration, every))
    |> new!()
  end

  defp interval_slots(%Interval{from: from, to: to, metadata: metadata}, duration, every) do
    collect_slots(from, to, duration, every, metadata, [])
  end

  defp collect_slots(slot_start, to, duration, every, metadata, acc) do
    slot_end = Tempo.shift(slot_start, duration)

    if Compare.compare_endpoints(slot_end, to) in [:earlier, :same] do
      slot = Interval.new!(from: slot_start, to: slot_end, metadata: metadata)
      next_start = Tempo.shift(slot_start, every)

      # Strictly advancing guarantees termination even if `:every` is
      # non-positive — at worst a single slot is emitted.
      if Compare.compare_endpoints(next_start, slot_start) == :later do
        collect_slots(next_start, to, duration, every, metadata, [slot | acc])
      else
        Enum.reverse([slot | acc])
      end
    else
      Enum.reverse(acc)
    end
  end

  @doc """
  Apply `fun` to each member interval and return the results as
  a plain list.

  Unlike the `Enumerable` protocol for `IntervalSet` — which
  walks each sub-point inside every interval at the next-finer
  resolution — `map/2` operates on the **member intervals
  themselves**. It's the set-as-sequence-of-spans view.

  The result is a plain list, not an IntervalSet, because the
  mapper may return anything (integers, tuples, arbitrary values).

  ### Arguments

  * `set` is a `t:t/0`.

  * `fun` is a 1-arity function applied to each member
    `t:Tempo.Interval.t/0`.

  ### Returns

  * A list of whatever `fun` returns, in the set's sort order.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"},
      ...>   %Tempo.Interval{from: ~o"2026-06-20", to: ~o"2026-06-21"}
      ...> ])
      iex> Tempo.IntervalSet.map(set, &Tempo.day/1)
      [15, 20]

  """
  @spec map(t(), (Interval.t() -> any())) :: [any()]
  def map(%__MODULE__{} = set, fun) when is_function(fun, 1) do
    set |> to_list() |> Enum.map(fun)
  end

  @doc """
  Keep only the member intervals for which `fun` returns `true`,
  returning a new `t:t/0`.

  ### Arguments

  * `set` is a `t:t/0`.

  * `fun` is a 1-arity predicate applied to each member
    `t:Tempo.Interval.t/0`.

  ### Returns

  * A new `t:t/0` containing only the members where `fun`
    returned a truthy value. The input's invariants (sorted,
    coalesced) are preserved — filtering cannot create overlap.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"},
      ...>   %Tempo.Interval{from: ~o"2026-06-20", to: ~o"2026-06-25"}
      ...> ])
      iex> long = Tempo.IntervalSet.filter(set, &Tempo.at_least?(&1, ~o"P2D"))
      iex> Tempo.IntervalSet.count(long)
      1

  """
  @spec filter(t(), (Interval.t() -> as_boolean(any()))) :: t()
  def filter(%__MODULE__{} = set, fun) when is_function(fun, 1) do
    with_intervals(set, set |> to_list() |> Enum.filter(fun))
  end

  @doc """
  Build the Allen-relation matrix between every member of `a`
  and every member of `b`.

  Allen's algebra is defined on pairs of intervals, not sets —
  two multi-member sets can relate several different ways
  simultaneously. `relation_matrix/2` returns the complete
  per-pair classification so you can reason about mixed
  conflicts, merge logic, or scheduling visualisations.

  ### Arguments

  * `a` and `b` are `t:t/0` (single intervals and Tempo points
    are coerced to single-member sets for convenience).

  ### Returns

  * `[{a_index, b_index, relation}]` — one tuple per pair.
    Indexes are 0-based into each set's `.intervals` list. The
    relation is one of `t:Tempo.Interval.relation/0`.

  * `{:error, reason}` when either input can't be reduced to an
    IntervalSet of bounded intervals.

  ### Examples

      iex> a = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-03"},
      ...>   %Tempo.Interval{from: ~o"2026-06-05", to: ~o"2026-06-07"}
      ...> ], coalesce: false)
      iex> b = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-04", to: ~o"2026-06-06"}
      ...> ], coalesce: false)
      iex> Tempo.IntervalSet.relation_matrix(a, b)
      [{0, 0, :precedes}, {1, 0, :overlapped_by}]

  """
  # Dialyzer over-widens the return type when a `with` clause
  # has no explicit `else` — it includes the bound intermediate
  # `{:ok, IntervalSet{intervals: []}}` shape even though that
  # path always produces a list via the comprehension. The spec
  # below is humanly correct; suppress the warning rather than
  # widen the spec with a fictitious return.
  @dialyzer {:nowarn_function, relation_matrix: 2}

  @spec relation_matrix(t() | Interval.t() | Tempo.t(), t() | Interval.t() | Tempo.t()) ::
          [
            {non_neg_integer(), non_neg_integer(), Interval.relation() | {:error, term()}}
          ]
          | {:error, term()}
  def relation_matrix(a, b) do
    with {:ok, %__MODULE__{} = a_set} <- coerce(a),
         {:ok, %__MODULE__{} = b_set} <- coerce(b) do
      a_ivs = to_list(a_set)
      b_ivs = to_list(b_set)

      for {iv_a, ai} <- Enum.with_index(a_ivs),
          {iv_b, bi} <- Enum.with_index(b_ivs) do
        {ai, bi, Interval.relation(iv_a, iv_b)}
      end
    end
  end

  defp coerce(%__MODULE__{} = set), do: {:ok, set}
  defp coerce(%Interval{} = iv), do: new([iv], coalesce: false)
  defp coerce(%Tempo{} = point), do: Tempo.to_interval_set(point)

  defp coerce(other) do
    {:error, ConversionError.exception(value: other, target: Tempo.IntervalSet)}
  end

  ## Validation

  defp validate_all_bounded(intervals) do
    Enum.reduce_while(intervals, :ok, fn interval, :ok ->
      case validate_member(interval) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Every member must be an interval, bounded on both ends. A member
  # that is neither is reported rather than raised: `new/2` answers
  # with a tagged tuple, so a bad value arriving from user input —
  # a changeset, a decoded document — must not crash the caller.
  #
  # Two things spell "no endpoint here". `:undefined` is what ISO 8601
  # open intervals (`2020Y/..`) parse to; `nil` is what an unanchored
  # recurrence carries — `Tempo.RRule.parse("FREQ=WEEKLY;BYDAY=MO")`
  # with no DTSTART is "every Monday" beginning nowhere. Neither has an
  # extent to sweep, so both are unbounded for the purposes of a set.
  defp validate_member(%Interval{from: from, to: to} = interval)
       when from in [nil, :undefined] or to in [nil, :undefined] do
    {:error,
     IntervalEndpointsError.exception(
       interval: interval,
       operation: "include open-ended interval in a set"
     )}
  end

  defp validate_member(%Interval{}), do: :ok

  defp validate_member(other) do
    {:error,
     ConversionError.exception(
       value: other,
       target: Interval,
       reason: "IntervalSet members must be Tempo.Interval structs, got: #{inspect(other)}"
     )}
  end

  ## Ordering

  # Sort ascending by `from` endpoint. Ties break by `to` (shorter
  # first) so that a pointwise interval comes before a longer one
  # sharing the same start — matches intuition and makes the
  # coalesce pass deterministic.

  # Ordering is calendar-aware: `Compare.compare_endpoints/2` projects
  # cross-calendar endpoints to the shared absolute frame, so intervals from
  # different calendars sort by their true instants — which the coalesce pass
  # relies on to merge overlaps.
  defp compare_from(%Interval{from: a_from, to: a_to}, %Interval{from: b_from, to: b_to}) do
    case Compare.compare_endpoints(a_from, b_from) do
      :earlier -> true
      :later -> false
      :same -> Compare.compare_endpoints(a_to, b_to) != :later
    end
  end

  ## ---------------------------------------------------------
  ## Coalesce — canonical instant-set form
  ## ---------------------------------------------------------

  @doc """
  Merge touching or overlapping member intervals into larger
  spans, returning a new `t:t/0` in **canonical instant-set
  form**.

  `IntervalSet` preserves member identity by default — each
  interval stays a distinct member with its own metadata. That
  shape is right for event management, bookings, and any query
  that asks about individual members.

  Some questions are about the *instants covered* by the set,
  not the members: "is this point covered?", "what's the total
  duration?", "are these two schedules equivalent?". For those,
  the canonical instant-set form is the right shape — two
  touching intervals merge into one, and the set has exactly
  one member per contiguous covered region.

  Under the half-open `[from, to)` convention, intervals merge
  when the later one's `from` is at or before the earlier one's
  `to`. Touching (`[a, b) ++ [b, c) == [a, c)`) and overlapping
  cases both merge.

  ### Metadata

  When two members merge, the earlier member's metadata is kept
  on the merged span and the later member's is dropped. If
  metadata matters for your query, filter or project before
  coalescing.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * A `t:t/0` with touching and overlapping intervals merged.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"},
      ...>   %Tempo.Interval{from: ~o"2026-06-16", to: ~o"2026-06-17"}
      ...> ])
      iex> Tempo.IntervalSet.count(set)
      2
      iex> coalesced = Tempo.IntervalSet.coalesce(set)
      iex> Tempo.IntervalSet.count(coalesced)
      1

  """
  @spec coalesce(t()) :: t()
  def coalesce(%__MODULE__{} = set) do
    with_intervals(set, coalesce_intervals(to_list(set)))
  end

  @doc """
  `true` when any member interval of `set` covers `point`.

  Coalesces internally — a point is "covered" iff it falls inside
  at least one member span. For the common booking/scheduling
  question "is this slot occupied?", this is the right predicate.

  ### Arguments

  * `set` is a `t:t/0`.

  * `point` is any `t:Tempo.t/0`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      ...> ])
      iex> Tempo.IntervalSet.covered?(set, ~o"2026-06-17")
      true
      iex> Tempo.IntervalSet.covered?(set, ~o"2026-06-25")
      false

  """
  @spec covered?(t(), Tempo.t()) :: boolean()
  def covered?(%__MODULE__{backend: backend, intervals: state} = set, %Tempo{} = point) do
    # The backend prunes to candidate members (an interval tree answers
    # in O(log n + k)); the exact resolution-aware containment check
    # stays here. A non-anchored point has no timeline position to
    # prune by, so it scans.
    candidates =
      case point_span_seconds(point) do
        {:ok, seconds_range} -> backend.overlapping(state, seconds_range)
        :error -> to_list(set)
      end

    Enum.any?(candidates, fn interval -> Interval.within?(point, interval) end)
  end

  defp point_span_seconds(%Tempo{} = point) do
    with true <- Tempo.anchored?(point),
         {:ok, %Interval{from: %Tempo{} = from, to: %Tempo{} = to}} <- Tempo.to_interval(point) do
      {:ok, {Compare.to_utc_seconds(from), Compare.to_utc_seconds(to)}}
    else
      _other -> :error
    end
  end

  @doc """
  The regions covered by at least `:at_least` members of the set.

  Where `coalesce/1` flattens overlap away, this measures it. Sweeping
  the members' endpoints and tracking how many are open at each instant
  answers the questions overlap depth is really asked for — *"when are
  three or more of these happening at once?"*, *"where is this
  double-booked?"*, *"when did load peak?"*

  `at_least: 1` is the covered region, equivalent to
  `coalesce/1`. Higher thresholds narrow to the busier parts.

  The half-open convention decides the boundaries: a member ending at
  the instant another begins does not overlap it, so depth never
  spuriously rises where two members merely meet.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Options

  * `:at_least` is the minimum number of overlapping members a region
    must have. Required, and must be positive.

  ### Returns

  * a `t:t/0` of the qualifying regions, in order. Empty when nothing
    reaches the threshold.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15T09:00:00", to: ~o"2026-06-15T12:00:00"},
      ...>   %Tempo.Interval{from: ~o"2026-06-15T11:00:00", to: ~o"2026-06-15T14:00:00"}
      ...> ])
      iex> set
      ...> |> Tempo.IntervalSet.overlapping(at_least: 2)
      ...> |> Tempo.IntervalSet.to_list()
      ...> |> Enum.map(&Tempo.to_iso8601/1)
      ["2026Y6M15DT11H0M0S/2026Y6M15DT12H0M0S"]

  Members that merely meet do not overlap:

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15T09:00:00", to: ~o"2026-06-15T10:00:00"},
      ...>   %Tempo.Interval{from: ~o"2026-06-15T10:00:00", to: ~o"2026-06-15T11:00:00"}
      ...> ])
      iex> set |> Tempo.IntervalSet.overlapping(at_least: 2) |> Tempo.IntervalSet.empty?()
      true

  """
  @spec overlapping(t(), keyword()) :: t()
  def overlapping(%__MODULE__{} = set, options) do
    threshold = Keyword.fetch!(options, :at_least)

    set
    |> to_list()
    |> Enum.flat_map(fn %Interval{from: from, to: to} -> [{from, 1}, {to, -1}] end)
    |> sort_edges()
    |> sweep_depth(threshold, 0, nil, [])
    |> Enum.reverse()
    |> then(&with_intervals(set, &1))
  end

  # Closing edges sort before opening ones at the same instant, which
  # is what keeps `[a, b)` and `[b, c)` from reading as an overlap at
  # `b`.
  defp sort_edges(edges) do
    Enum.sort(edges, fn {a_at, a_delta}, {b_at, b_delta} ->
      case Compare.compare_endpoints(a_at, b_at) do
        :earlier -> true
        :later -> false
        :same -> a_delta <= b_delta
      end
    end)
  end

  defp sweep_depth([], _threshold, _depth, _opened_at, acc), do: acc

  defp sweep_depth([{at, delta} | rest], threshold, depth, opened_at, acc) do
    deeper = depth + delta

    cond do
      depth < threshold and deeper >= threshold ->
        sweep_depth(rest, threshold, deeper, at, acc)

      depth >= threshold and deeper < threshold ->
        sweep_depth(rest, threshold, deeper, nil, emit_region(opened_at, at, acc))

      true ->
        sweep_depth(rest, threshold, deeper, opened_at, acc)
    end
  end

  defp emit_region(from, to, acc) do
    case Compare.compare_endpoints(from, to) do
      :earlier -> [%Interval{from: from, to: to} | acc]
      _not_a_span -> acc
    end
  end

  @doc """
  Total duration covered by the set's members, as a
  `t:Tempo.Duration.t/0`.

  Coalesces internally so overlapping members are not
  double-counted — the returned duration is the length of the
  union of covered instants, not the sum of individual member
  durations. For the "sum of member durations" semantics, use
  `map(set, &Tempo.Interval.duration/1) |> Enum.sum()` with
  explicit arithmetic.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * A `t:Tempo.Duration.t/0`.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15T09:00:00", to: ~o"2026-06-15T10:00:00"},
      ...>   %Tempo.Interval{from: ~o"2026-06-15T11:00:00", to: ~o"2026-06-15T12:00:00"}
      ...> ])
      iex> Tempo.IntervalSet.total_duration(set)
      ~o"PT7200S"

  """
  @spec total_duration(t()) :: Tempo.Duration.t()
  def total_duration(%__MODULE__{} = set) do
    set
    |> coalesce()
    |> to_list()
    |> Enum.reduce(Duration.build([]), fn interval, acc ->
      add_durations(acc, Interval.duration(interval))
    end)
  end

  defp add_durations(%Tempo.Duration{time: a}, %Tempo.Duration{time: b}) do
    merged =
      Keyword.merge(a, b, fn _key, v1, v2 -> v1 + v2 end)

    Duration.build(merged)
  end

  # Single forward pass. At each step, decide whether the next
  # interval should merge with the current "accumulator" interval
  # (overlap OR touch) or start a new span. Half-open semantics:
  # `[a, b)` and `[b, c)` touch at `b` and merge to `[a, c)`.
  #
  # Private helper used by `new/2` (when `coalesce: true` is
  # passed) and by the public `coalesce/1` wrapper above.

  defp coalesce_intervals([]), do: []

  defp coalesce_intervals([interval | rest]) do
    coalesce_step(rest, [interval])
  end

  defp coalesce_step([], acc), do: Enum.reverse(acc)

  defp coalesce_step([next | rest], [current | tail] = acc) do
    case merge_if_touching(current, next) do
      {:merged, merged} ->
        coalesce_step(rest, [merged | tail])

      :separate ->
        coalesce_step(rest, [next | acc])
    end
  end

  # Two intervals merge if the later one starts at or before the
  # earlier one's end. Under `[from, to)`:
  # * `next.from < current.to` → overlap
  # * `next.from == current.to` → touch (half-open concatenation)
  # In both cases the merged interval spans from `current.from` to
  # `max(current.to, next.to)`.

  defp merge_if_touching(%Interval{} = current, %Interval{} = next) do
    case Compare.compare_endpoints(next.from, current.to) do
      order when order in [:earlier, :same] ->
        merged_to =
          case Compare.compare_endpoints(next.to, current.to) do
            :later -> next.to
            _ -> current.to
          end

        {:merged, %{current | to: merged_to}}

      :later ->
        :separate
    end
  end
end
