defimpl Enumerable, for: Tempo do
  @moduledoc false

  alias Tempo.Enumeration
  alias Tempo.Enumeration.Zone
  alias Tempo.Interval.Steps

  # Implicit enumeration of a resolved `%Tempo{}` walks the same
  # sequence as forward-stepping its materialised interval (see
  # `to_interval/1`), so `count/1`, `member?/2`, and `slice/1` reuse
  # the interval's O(1) `Tempo.Interval.Steps`-backed implementations.
  # Those are DST-aware in the same way as `reduce/3` here — a
  # spring-forward gap hour is not counted/sliced, a fall-back hour is
  # counted twice — so the fast paths agree with the walk.
  #
  # Values that don't materialise to a single interval — groups,
  # selections, ranges, sets, masks — return `{:error, __MODULE__}`,
  # so `Enum` falls back to the reduce-based traversal that handles
  # them. So does a value whose interval has no fast path (a week,
  # walked by its days): the fallback reduces the value itself, so the
  # module it names must be this one, never the interval's.

  # A struct given `nil` for its calendar is walked in the default one.
  @impl Enumerable
  def count(%Tempo{calendar: nil} = tempo), do: count(Tempo.with_a_calendar(tempo))

  def count(%Tempo{} = tempo) do
    with {:ok, interval} <- single_interval(tempo),
         {:ok, _count} = counted <- Enumerable.count(interval) do
      counted
    else
      _no_fast_path -> {:error, __MODULE__}
    end
  end

  @impl Enumerable
  def member?(%Tempo{calendar: nil} = tempo, element),
    do: member?(Tempo.with_a_calendar(tempo), element)

  def member?(%Tempo{} = tempo, %Tempo{} = element) do
    with {:ok, interval} <- single_interval(tempo),
         {:ok, _member?} = answered <- Enumerable.member?(interval, element) do
      answered
    else
      _no_fast_path -> {:error, __MODULE__}
    end
  end

  def member?(_tempo, _element) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def slice(%Tempo{calendar: nil} = tempo), do: slice(Tempo.with_a_calendar(tempo))

  def slice(%Tempo{} = tempo) do
    with {:ok, interval} <- single_interval(tempo),
         {:ok, _size, _slicer} = sliced <- Enumerable.slice(interval) do
      sliced
    else
      _no_fast_path -> {:error, __MODULE__}
    end
  end

  defp single_interval(%Tempo{} = tempo) do
    # Any value that enumerates *candidates* (masks, `:any`, ranges,
    # groups) materialises to a single block interval whose
    # `count`/`slice` would disagree with the candidate walk — e.g.
    # `2020-06-XX` is 30 day-candidates, not one month-long span. Route
    # exactly those through the reduce fallback, using the canonical
    # `explicitly_enumerable?/1` predicate rather than an ad-hoc mask check
    # (which missed `:any`, ranges, and groups).
    #
    # The interval of a value that names one span carries the unit the value
    # is walked by (a day's is `:hour`), and counts as the walk does. One that
    # carries none is walked by its own ends, which is not the walk of the
    # value: a second is walked by its tenths and its interval is one second,
    # and a year with significant digits (`1950S2`) is walked by the months of
    # each year of its block and its interval by the years.
    if Enumeration.explicitly_enumerable?(tempo) do
      :error
    else
      case Tempo.to_interval(tempo) do
        {:ok, %Tempo.Interval{unit: unit} = interval} when not is_nil(unit) -> {:ok, interval}
        _ -> :error
      end
    end
  end

  # `Enumerable.reduce/3` has no error to return, so a value that cannot be
  # walked raises the exception `Tempo.to_interval/2` would return for it.
  @impl Enumerable
  def reduce(%Tempo{calendar: nil} = tempo, acc, fun),
    do: reduce(Tempo.with_a_calendar(tempo), acc, fun)

  def reduce(%Tempo{time: time} = tempo, acc, fun) do
    # A value that holds a selection (`2026Y6ML2KN`, the Tuesdays of June
    # 2026) names the dates the selection picks, and is walked as they are.
    if List.keymember?(time, :selection, 0),
      do: reduce_spans(Tempo.to_interval(tempo), acc, fun),
      else: reduce_steps(clock_walk(tempo), tempo, acc, fun)
  end

  # A value in a named zone that names one span walked by hours, minutes or
  # seconds is walked as its span is, by the time elapsed
  # (`Tempo.Interval.Steps.clock_walk/4`): its values are in the order of
  # time and within it whatever its zone's clock does. Any other value, and
  # one whose zone changes its clock off the steps, is walked by its units.
  defp reduce_steps({:ok, steps}, _tempo, acc, fun), do: Steps.reduce_clock_walk(steps, acc, fun)

  defp reduce_steps(:not_supported, tempo, acc, fun),
    do: reduce_walk({Enumeration.implicit_walk(tempo), own_occurrence(tempo)}, acc, fun)

  defp clock_walk(%Tempo{extended: %{zone_id: zone}, calendar: calendar} = tempo)
       when is_binary(zone) do
    case single_interval(tempo) do
      {:ok, %Tempo.Interval{from: from, to: to, unit: unit}} ->
        Steps.clock_walk(from, to, unit, calendar)

      :error ->
        :not_supported
    end
  end

  defp clock_walk(%Tempo{}), do: :not_supported

  # A wall time a clock shows twice (the hour a clock goes back) names the
  # first time it shows it, or the one the offset written with it names: the
  # reading `Tempo.to_interval/2`, `Enum.count/1` and comparison give it. Its
  # walk yields that occurrence. A value that holds such an hour without
  # being in it (the day the clock goes back) is walked through both.
  defp own_occurrence(%Tempo{shift: shift} = tempo) do
    case Zone.zone_status(tempo) do
      {:ambiguous, first, second} -> if same_offset?(shift, second), do: second, else: first
      _one_reading -> :both
    end
  end

  defp same_offset?(nil, _shift), do: false

  defp same_offset?(written, shift),
    do: Tempo.Compare.offset_seconds(written) == Tempo.Compare.offset_seconds(shift)

  defp reduce_spans({:ok, spans}, acc, fun), do: Enumerable.reduce(spans, acc, fun)
  defp reduce_spans({:error, exception}, _acc, _fun), do: raise(exception)

  # The walk of the value (see `Tempo.Enumeration`), a few values at a time,
  # with the occurrence of an hour shown twice that the value names.
  defp reduce_walk(_walk, {:halt, acc}, _fun), do: {:halted, acc}

  defp reduce_walk(walk, {:suspend, acc}, fun),
    do: {:suspended, acc, &reduce_walk(walk, &1, fun)}

  defp reduce_walk({walk, fold}, {:cont, acc}, fun) do
    case Enumeration.next(walk) do
      {:ok, values, next} -> reduce_values(values, {next, fold}, {:cont, acc}, fun)
      :done -> {:done, acc}
      {:error, exception} -> raise exception
    end
  end

  # The values read from the walk, each read through its zone.
  defp reduce_values(_values, _walk, {:halt, acc}, _fun), do: {:halted, acc}

  defp reduce_values(values, walk, {:suspend, acc}, fun),
    do: {:suspended, acc, &reduce_values(values, walk, &1, fun)}

  defp reduce_values([], walk, {:cont, acc}, fun), do: reduce_walk(walk, {:cont, acc}, fun)

  defp reduce_values([value | values], {_walk, fold} = walk, {:cont, acc}, fun) do
    case Zone.zone_status(value) do
      :ok ->
        reduce_values(values, walk, fun.(value, acc), fun)

      # Wall clock never shows this moment (DST spring-forward): skip and
      # advance.
      :gap ->
        reduce_values(values, walk, {:cont, acc}, fun)

      # Wall clock shows this moment twice (DST fall-back): emit both
      # occurrences, distinguished by their `:shift` — first with the
      # pre-transition offset (e.g. AEDT +11), second with the
      # post-transition offset (AEST +10). RFC 9557 IXDTF treats the explicit
      # numeric offset as the fold disambiguator, so the two emitted Tempos
      # round-trip as distinct values and compare as distinct UTC instants.
      {:ambiguous, first_shift, second_shift} when fold == :both ->
        folded = [%{value | shift: first_shift}, %{value | shift: second_shift}]
        reduce_folded(folded, values, walk, {:cont, acc}, fun)

      # The value walked is itself in the hour shown twice, and its values
      # are in the occurrence it names.
      {:ambiguous, _first_shift, _second_shift} ->
        reduce_values(values, walk, fun.(%{value | shift: fold}, acc), fun)
    end
  end

  # The two occurrences of a fall-back hour, then the values after it.
  defp reduce_folded(_folded, _values, _walk, {:halt, acc}, _fun), do: {:halted, acc}

  defp reduce_folded(folded, values, walk, {:suspend, acc}, fun),
    do: {:suspended, acc, &reduce_folded(folded, values, walk, &1, fun)}

  defp reduce_folded([], values, walk, {:cont, acc}, fun),
    do: reduce_values(values, walk, {:cont, acc}, fun)

  defp reduce_folded([occurrence | folded], values, walk, {:cont, acc}, fun),
    do: reduce_folded(folded, values, walk, fun.(occurrence, acc), fun)
end
