defimpl Enumerable, for: Tempo.IntervalSet do
  @moduledoc false

  # An IntervalSet is a sorted, non-overlapping list of intervals.
  # Enumeration walks each interval in sequence, yielding the
  # forward-stepped values produced by `Enumerable.Tempo.Interval`.
  # The result is a flat sequence of `%Tempo{}` values in time
  # order — the natural input for free/busy scans and calendar
  # renderings.
  #
  # There are two legitimate iteration modes, and this is the
  # deliberate resolution of that tension: the `Enumerable` protocol
  # yields *sub-points* (the free/busy-scan and calendar-rendering
  # input), and iterating the *member intervals* is an explicit, named
  # operation — `Tempo.IntervalSet.members/1` returns the members for
  # piping into `Enum`. The protocol is not overloaded to do both; the
  # accessor makes the member-level intent visible at the call site.

  # On an unbounded (lazy) set the fallback algorithms these `{:error,
  # __MODULE__}` returns trigger would reduce forever, so they refuse
  # loudly instead. Bounded walking (`Enum.take/2`, `take_while`,
  # `Stream` composition) works on every backend.

  @impl Enumerable
  def count(%Tempo.IntervalSet{} = set) do
    ensure_bounded!(set, "Enum.count/1")
    {:error, __MODULE__}
  end

  @impl Enumerable
  def member?(%Tempo.IntervalSet{} = set, _element) do
    ensure_bounded!(set, "Enum.member?/2")
    {:error, __MODULE__}
  end

  @impl Enumerable
  def slice(%Tempo.IntervalSet{} = set) do
    ensure_bounded!(set, "Enum.slice/2")
    {:error, __MODULE__}
  end

  @impl Enumerable
  def reduce(%Tempo.IntervalSet{} = set, acc, fun) do
    if Tempo.IntervalSet.bounded?(set) do
      do_reduce(Tempo.IntervalSet.members(set), acc, fun)
    else
      # Flatten the member walk into its sub-points lazily: each member
      # interval is itself Enumerable, and halting propagates, so
      # `Enum.take/2` and friends work without materialising the set.
      set
      |> Tempo.IntervalSet.walk()
      |> Stream.flat_map(& &1)
      |> Enumerable.reduce(acc, fun)
    end
  end

  defp ensure_bounded!(set, operation) do
    unless Tempo.IntervalSet.bounded?(set) do
      raise Tempo.UnboundedSetError.exception(operation: operation, set: set)
    end
  end

  defp do_reduce(_intervals, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp do_reduce(intervals, {:suspend, acc}, fun) do
    {:suspended, acc, &do_reduce(intervals, &1, fun)}
  end

  defp do_reduce([], {:cont, acc}, _fun) do
    {:done, acc}
  end

  # Reduce the current interval, capturing its result. On `:done`,
  # advance to the next interval. On `:halted` / `:suspended`,
  # propagate upward and preserve the continuation so the enumeration
  # resumes mid-set.

  defp do_reduce([interval | rest], {:cont, acc}, fun) do
    case Enumerable.reduce(interval, {:cont, acc}, fun) do
      {:done, acc} ->
        do_reduce(rest, {:cont, acc}, fun)

      {:halted, acc} ->
        {:halted, acc}

      {:suspended, acc, continuation} ->
        {:suspended, acc, &resume_current(continuation, rest, &1, fun)}
    end
  end

  # When the current interval's enumeration is suspended, resuming
  # first finishes that interval and only then moves to the next.
  defp resume_current(continuation, rest, acc, fun) do
    case continuation.(acc) do
      {:done, acc} ->
        do_reduce(rest, {:cont, acc}, fun)

      {:halted, acc} ->
        {:halted, acc}

      {:suspended, acc, next_continuation} ->
        {:suspended, acc, &resume_current(next_continuation, rest, &1, fun)}
    end
  end
end
