defmodule Tempo.IntervalSet.Backend do
  @moduledoc """
  The behaviour a `Tempo.IntervalSet` storage backend implements.

  An interval set's representation is pluggable: the set struct carries a
  `:backend` module and an opaque backend `state` (in its `:intervals`
  field), and every `Tempo.IntervalSet` function reaches the members
  through this contract rather than assuming a concrete data structure.
  `Tempo.IntervalSet.Backend.List` — a sorted plain list — is the default
  and the reference implementation.

  ## The contract

  The universal primitive is the **ordered walk**: `walk/1` returns an
  enumerable that yields the member intervals in time order, sorted by
  `from` endpoint, disjoint, each half-open `[from, to)`. A backend is
  correct as soon as it can walk; the remaining callbacks exist so a
  backend can answer common questions without a full walk, and default
  to walk-derived implementations via `use Tempo.IntervalSet.Backend`.

  `bounded?/1` is the honesty bit: a backend over a finite member list
  returns `true`; a lazy backend over a potentially unbounded generator
  returns `false`, and aggregate operations (`to_list/1`, `count/1`,
  set-wide duration) refuse rather than walk forever. Callers must
  consult `bounded?/1` before calling `to_list/1` or `count/1`.

  ## Implementing a backend

      defmodule MyBackend do
        use Tempo.IntervalSet.Backend

        @impl true
        def from_list(intervals, _options), do: build_my_state(intervals)

        @impl true
        def to_list(state), do: my_state_to_list(state)

        @impl true
        def walk(state), do: my_lazy_stream(state)

        @impl true
        def bounded?(_state), do: true
      end

  `use` provides overridable `count/1`, `empty?/1`, and `first/1`
  derived from `to_list/1` and `walk/1`; override them when the
  representation can answer faster (a tree knows its size; any backend
  can peek its first member without building the set).

  Construct a set on a specific backend with
  `Tempo.IntervalSet.new(intervals, backend: MyBackend)`. Set operations
  preserve the backend of member-preserving results; newly constructed
  extents default to the list backend.

  """

  alias Tempo.Interval

  @typedoc """
  The backend's opaque representation of the member intervals. For the
  list backend this is the member list itself; other backends choose
  their own shape.
  """
  @type state :: term()

  @doc """
  Build backend state from a sorted, disjoint member list.

  `Tempo.IntervalSet.new/2` validates, sorts, and (by default)
  coalesces the members before calling this — the backend may assume
  time order and disjointness.
  """
  @callback from_list([Interval.t()], keyword()) :: state()

  @doc """
  The members as a plain list in time order. Only valid when
  `bounded?/1` is `true`; an unbounded backend raises.
  """
  @callback to_list(state()) :: [Interval.t()]

  @doc """
  An enumerable yielding the members in time order. The universal
  primitive: safe on every backend, lazy where the backend is lazy.
  """
  @callback walk(state()) :: Enumerable.t()

  @doc """
  Whether the member list is finite. Aggregate operations consult this
  before building the set; `false` makes them refuse rather than hang.
  """
  @callback bounded?(state()) :: boolean()

  @doc """
  The number of members. Only valid when `bounded?/1` is `true`.
  """
  @callback count(state()) :: non_neg_integer()

  @doc """
  Whether the set has no members. Safe on every backend — peeking one
  element never requires a full walk.
  """
  @callback empty?(state()) :: boolean()

  @doc """
  The earliest member, or `nil` when empty. Safe on every backend.
  """
  @callback first(state()) :: Interval.t() | nil

  @doc """
  Candidate members whose extent may intersect the half-open UTC-second
  range `[lo, hi)`.

  A **pruning** callback, not a semantic one: the contract is to return
  *at least* every member whose `[from, to)` intersects the range — a
  backend may return extra members, or all of them (the default). The
  caller applies the exact resolution-aware check to the candidates, so
  a backend that prunes well (an interval tree) accelerates stabbing
  and overlap queries without owning their semantics.
  """
  @callback overlapping(state(), {number(), number()}) :: [Interval.t()]

  @doc """
  Whether the backend can hold these members.

  `Tempo.IntervalSet.new/2` asks before it builds the state, so a
  backend that cannot hold a member refuses it with an error and does
  not raise: an interval tree indexes positions on the time line, and a
  member with no year has none. The default holds any members.
  """
  @callback accepts([Interval.t()]) :: :ok | {:error, Exception.t()}

  @optional_callbacks accepts: 1

  defmacro __using__(_opts) do
    quote do
      @behaviour Tempo.IntervalSet.Backend

      @impl true
      def accepts(_intervals), do: :ok

      @impl true
      def count(state), do: state |> to_list() |> length()

      @impl true
      def empty?(state), do: state |> walk() |> Enum.take(1) == []

      @impl true
      def first(state), do: state |> walk() |> Enum.take(1) |> List.first()

      @impl true
      def overlapping(state, _seconds_range), do: to_list(state)

      defoverridable accepts: 1, count: 1, empty?: 1, first: 1, overlapping: 2
    end
  end
end
