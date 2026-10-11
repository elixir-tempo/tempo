defmodule Tempo.IntervalSet.Backend.Lazy do
  @moduledoc """
  A lazy, potentially unbounded `Tempo.IntervalSet.Backend`: the state
  holds an ordered generator (any `Enumerable`, typically a `Stream`)
  yielding member intervals in time order, sorted by `from`, disjoint,
  each anchored and bounded.

  A lazy set answers the walking questions — `Tempo.IntervalSet.walk/1`,
  `first/1`, `empty?/1`, `covered?/2`, `Enum.take/2`, and use as a
  `Tempo.shift/3` `skipping:` busy set — without ever building more
  members than the caller consumes. `bounded?/1` is `false`, so every
  aggregate operation (`members/1`, `count/1`, `coalesce/1`, set
  algebra) raises `Tempo.UnboundedSetError` instead of walking forever.

  Build one from your own generator with
  `Tempo.IntervalSet.from_stream/2`, or use a built-in source: a
  selection across an open-ended span (`Tempo.select/2`), or a
  recurrence's occurrences from an open-ended `:within` window
  (`Tempo.to_interval_set/2`). The **generator contract** is the caller's
  responsibility — members in time order, non-overlapping, anchored,
  bounded — because an infinite stream cannot be validated up front;
  each member is checked as it is consumed.

  """

  use Tempo.IntervalSet.Backend

  alias Tempo.Calendars
  alias Tempo.Compare
  alias Tempo.UnboundedSetError

  # The state: the generator, and the calendar a member that names no
  # calendar is in. The members of a lazy set are not there to be looked at
  # until they are read, so the set says beside them how they are held: a
  # caller holds such a member in `Calendar.ISO`, and inside a call it holds
  # the module Tempo works with (`Tempo.Border`, which reads the one field
  # as it reads a value's).
  @enforce_keys [:members, :calendar]
  defstruct [:members, :calendar]

  @typedoc false
  @type t :: %__MODULE__{members: Enumerable.t(), calendar: module()}

  @doc false
  # The state of a lazy set of the members a generator gives.
  @spec state(Enumerable.t()) :: t()
  def state(members), do: %__MODULE__{members: members, calendar: Calendars.default()}

  @impl true
  def from_list(intervals, _options), do: state(intervals)

  @impl true
  @spec to_list(term()) :: no_return()
  def to_list(_state) do
    raise UnboundedSetError.exception(operation: "Tempo.IntervalSet.members/1")
  end

  @impl true
  def walk(%__MODULE__{members: members}), do: members

  @impl true
  def bounded?(_state), do: false

  @impl true
  @spec count(term()) :: no_return()
  def count(_state) do
    raise UnboundedSetError.exception(operation: "Tempo.IntervalSet.count/1")
  end

  @impl true
  def empty?(%__MODULE__{members: members}), do: Enum.take(members, 1) == []

  @impl true
  def first(%__MODULE__{members: members}), do: members |> Enum.take(1) |> List.first()

  # Walk only as far as the queried range reaches: members are in time
  # order, so once one starts at or beyond `hi` nothing later can
  # intersect `[lo, hi)`.
  @impl true
  def overlapping(%__MODULE__{members: members}, {lo, hi}) do
    members
    |> Stream.take_while(fn interval -> Compare.to_utc_seconds(interval.from) < hi end)
    |> Enum.filter(fn interval -> Compare.to_utc_seconds(interval.to) > lo end)
  end
end
