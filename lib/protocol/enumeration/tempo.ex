defimpl Enumerable, for: Tempo do
  @moduledoc false

  alias Tempo.Enumeration
  alias Tempo.Enumeration.Zone

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

  @impl Enumerable
  def count(%Tempo{} = tempo) do
    with {:ok, interval} <- single_interval(tempo),
         {:ok, _count} = counted <- Enumerable.count(interval) do
      counted
    else
      _no_fast_path -> {:error, __MODULE__}
    end
  end

  @impl Enumerable
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
  def reduce(%Tempo{time: time} = tempo, acc, fun) do
    # A value that holds a selection (`2026Y6ML2KN`, the Tuesdays of June
    # 2026) names the dates the selection picks, and is walked as they are.
    if List.keymember?(time, :selection, 0) do
      reduce_spans(Tempo.to_interval(tempo), acc, fun)
    else
      tempo |> Enumeration.implicit_walk() |> reduce_walk(acc, fun)
    end
  end

  defp reduce_spans({:ok, spans}, acc, fun), do: Enumerable.reduce(spans, acc, fun)
  defp reduce_spans({:error, exception}, _acc, _fun), do: raise(exception)

  # The walk of the value (see `Tempo.Enumeration`), a few values at a time.
  defp reduce_walk(_walk, {:halt, acc}, _fun), do: {:halted, acc}

  defp reduce_walk(walk, {:suspend, acc}, fun),
    do: {:suspended, acc, &reduce_walk(walk, &1, fun)}

  defp reduce_walk(walk, {:cont, acc}, fun) do
    case Enumeration.next(walk) do
      {:ok, values, walk} -> reduce_values(values, walk, {:cont, acc}, fun)
      :done -> {:done, acc}
      {:error, exception} -> raise exception
    end
  end

  # The values read from the walk, each read through its zone.
  defp reduce_values(_values, _walk, {:halt, acc}, _fun), do: {:halted, acc}

  defp reduce_values(values, walk, {:suspend, acc}, fun),
    do: {:suspended, acc, &reduce_values(values, walk, &1, fun)}

  defp reduce_values([], walk, {:cont, acc}, fun), do: reduce_walk(walk, {:cont, acc}, fun)

  defp reduce_values([value | values], walk, {:cont, acc}, fun) do
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
      {:ambiguous, first_shift, second_shift} ->
        folded = [%{value | shift: first_shift}, %{value | shift: second_shift}]
        reduce_folded(folded, values, walk, {:cont, acc}, fun)
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
