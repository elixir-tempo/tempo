defmodule Tempo.IntervalSet.Backend.Lazy do
  @moduledoc """
  A lazy, potentially unbounded `Tempo.IntervalSet.Backend`: the state
  is an ordered generator (any `Enumerable`, typically a `Stream`)
  yielding member intervals in time order, sorted by `from`, disjoint,
  each anchored and bounded.

  A lazy set answers the walking questions — `Tempo.IntervalSet.walk/1`,
  `first/1`, `empty?/1`, `covered?/2`, `Enum.take/2`, and use as a
  `Tempo.shift/3` `skipping:` busy set — without ever building more
  members than the caller consumes. `bounded?/1` is `false`, so every
  aggregate operation (`to_list/1`, `count/1`, `coalesce/1`, set
  algebra) raises `Tempo.UnboundedSetError` instead of walking forever.

  Build one from your own generator with
  `Tempo.IntervalSet.from_stream/2`, or use a built-in source such as
  `Tempo.weekends/1`, or a recurrence's occurrences from an open-ended
  `:within` window (`Tempo.to_interval_set/2`). The **generator contract** is the caller's
  responsibility — members in time order, non-overlapping, anchored,
  bounded — because an infinite stream cannot be validated up front;
  each member is checked as it is consumed.

  """

  use Tempo.IntervalSet.Backend

  alias Tempo.Compare
  alias Tempo.UnboundedSetError

  @impl true
  def from_list(intervals, _options), do: intervals

  @impl true
  @spec to_list(term()) :: no_return()
  def to_list(_state) do
    raise UnboundedSetError.exception(operation: "Tempo.IntervalSet.to_list/1")
  end

  @impl true
  def walk(state), do: state

  @impl true
  def bounded?(_state), do: false

  @impl true
  @spec count(term()) :: no_return()
  def count(_state) do
    raise UnboundedSetError.exception(operation: "Tempo.IntervalSet.count/1")
  end

  @impl true
  def empty?(state), do: Enum.take(state, 1) == []

  @impl true
  def first(state), do: state |> Enum.take(1) |> List.first()

  # Walk only as far as the queried range reaches: members are in time
  # order, so once one starts at or beyond `hi` nothing later can
  # intersect `[lo, hi)`.
  @impl true
  def overlapping(state, {lo, hi}) do
    state
    |> Stream.take_while(fn interval -> Compare.to_utc_seconds(interval.from) < hi end)
    |> Enum.filter(fn interval -> Compare.to_utc_seconds(interval.to) > lo end)
  end
end
