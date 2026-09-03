defimpl Enumerable, for: Tempo.Interval do
  @moduledoc false

  alias Tempo.Enumeration.Zone
  alias Tempo.Interval.Steps
  alias Tempo.Math

  # An interval represents a span on the time line. Enumerating it
  # walks forward one unit at a time from the `:from` endpoint. This
  # is a different iteration semantics from `Enumerable.Tempo`:
  #
  #   * `Enum.take(%Tempo{time: [year: 1985]}, 3)` yields
  #     `[1985-Jan, 1985-Feb, 1985-Mar]` — drilling INTO the year at
  #     the implicit next-finer unit (month).
  #
  #   * `Enum.take(%Tempo.Interval{from: ~o"1985Y", to: :undefined}, 3)`
  #     yields `[1985, 1986, 1987]` — stepping FORWARD at the
  #     endpoint's own resolution.
  #
  # The step unit is the interval's explicit `:unit` when set (a
  # materialised implicit span carries its iteration granularity as
  # data — `to_interval(~o"2025-07-04")` has day-resolution bounds and
  # `unit: :hour`), otherwise it derives from `resolution(from)`. When
  # `:unit` is finer than the endpoint resolution the walk fills the
  # endpoint down to the unit once at the start (`Steps.fill_to_unit/3`)
  # instead of the bounds carrying drilled components.
  #
  # Open-lower and fully-open intervals have no anchor to iterate
  # from, so `reduce/3` raises a clear `ArgumentError`.
  #
  # A *recurring* interval (`recurrence` > 1 or `:infinity`) enumerates
  # exactly as its materialised occurrences do: `reduce/3` delegates to
  # the `Tempo.IntervalSet` walk over `Tempo.to_interval/1`'s expansion,
  # so a bounded recurrence yields the sub-points of every occurrence.
  # An unbounded recurrence cannot be materialised and raises
  # `Tempo.UnboundedRecurrenceError` directing the caller to
  # `Tempo.to_interval/2` with a `:bound`.

  @impl Enumerable
  def count(%Tempo.Interval{recurrence: recurrence}) when recurrence != 1 do
    {:error, __MODULE__}
  end

  def count(
        %Tempo.Interval{from: %Tempo{calendar: calendar} = from, to: %Tempo{} = to} = interval
      ) do
    unit = iteration_unit(interval, from)
    # Fill both bounds: the closed-form step counters read unit
    # components from each side, and start-of-unit filling names the
    # same boundary instant under the half-open convention.
    from = Steps.fill_to_unit(from, unit, calendar)
    to = Steps.fill_to_unit(to, unit, calendar)

    case Steps.count_steps(from, to, unit, calendar) do
      n when is_integer(n) -> {:ok, max(n, 0)}
      :not_supported -> {:error, __MODULE__}
    end
  end

  def count(_interval), do: {:error, __MODULE__}

  @impl Enumerable
  def member?(%Tempo.Interval{recurrence: recurrence}, _element) when recurrence != 1 do
    {:error, __MODULE__}
  end

  def member?(
        %Tempo.Interval{from: %Tempo{calendar: calendar} = from, to: %Tempo{} = to} = interval,
        %Tempo{} = element
      ) do
    unit = iteration_unit(interval, from)
    from = Steps.fill_to_unit(from, unit, calendar)

    cond do
      Tempo.Compare.compare_endpoints(element, from) == :earlier ->
        {:ok, false}

      Tempo.Compare.compare_endpoints(element, to) in [:later, :same] ->
        {:ok, false}

      true ->
        case Steps.on_step?(element, from, unit, calendar) do
          bool when is_boolean(bool) -> {:ok, bool}
          :not_supported -> {:error, __MODULE__}
        end
    end
  end

  def member?(_interval, _element), do: {:error, __MODULE__}

  @impl Enumerable
  def slice(%Tempo.Interval{recurrence: recurrence}) when recurrence != 1 do
    {:error, __MODULE__}
  end

  def slice(
        %Tempo.Interval{from: %Tempo{calendar: calendar} = from, to: %Tempo{} = to} = interval
      ) do
    unit = iteration_unit(interval, from)
    from = Steps.fill_to_unit(from, unit, calendar)
    to = Steps.fill_to_unit(to, unit, calendar)

    case Steps.count_steps(from, to, unit, calendar) do
      n when is_integer(n) and n >= 0 ->
        {:ok, n, slicer(from, unit, calendar)}

      _ ->
        {:error, __MODULE__}
    end
  end

  def slice(_interval), do: {:error, __MODULE__}

  # The explicit iteration unit when the interval carries one,
  # otherwise the endpoint's own resolution.
  defp iteration_unit(%Tempo.Interval{unit: unit}, from) do
    unit || from |> Tempo.resolution() |> elem(0)
  end

  defp slicer(from, unit, calendar) do
    fn start, length, step ->
      for i <- start..(start + length - 1)//step,
          do: Steps.nth_step(from, i, unit, calendar)
    end
  end

  @impl Enumerable
  def reduce(%Tempo.Interval{recurrence: recurrence} = interval, acc, fun)
      when recurrence != 1 do
    # A recurring interval enumerates as its materialised occurrences.
    # `to_interval/1` expands a bounded recurrence to an IntervalSet;
    # an unbounded one returns `UnboundedRecurrenceError` (raised with
    # its own `:bound` direction); a shape it cannot expand (an
    # `Rn/from/to` repetition) comes back unchanged and is refused
    # like the crisp API refuses it — never re-entered.
    case Tempo.to_interval(interval) do
      {:ok, %Tempo.IntervalSet{} = occurrences} ->
        Enumerable.reduce(occurrences, acc, fun)

      {:ok, %Tempo.Interval{}} ->
        raise Tempo.MaterialisationError.exception(
                value: interval,
                reason: :recurring_interval
              )

      {:error, exception} when is_exception(exception) ->
        raise exception
    end
  end

  def reduce(%Tempo.Interval{from: :undefined, to: :undefined}, _acc, _fun) do
    raise ArgumentError,
          "Cannot enumerate a fully open interval `../..` — " <>
            "no anchor from which to start iteration."
  end

  def reduce(%Tempo.Interval{from: :undefined, to: %Tempo{}, duration: nil}, _acc, _fun) do
    raise ArgumentError,
          "Cannot enumerate an interval with an open lower bound `../to` — " <>
            "Enumerable iterates forward from the lower bound, which is not defined."
  end

  def reduce(
        %Tempo.Interval{
          from: :undefined,
          to: %Tempo{} = to,
          duration: %Tempo.Duration{} = duration
        } = interval,
        acc,
        fun
      ) do
    # `P1M/1985-06` — duration + to. Compute the lower bound via
    # `Tempo.Math.subtract/2` and iterate as a closed interval.
    from = Tempo.Math.subtract(to, duration)
    do_reduce(fill_from(from, interval), to, acc, fun)
  end

  def reduce(
        %Tempo.Interval{
          from: %Tempo{} = from,
          to: to,
          duration: %Tempo.Duration{} = duration
        } = interval,
        acc,
        fun
      )
      when to in [nil, :undefined] do
    # `from + duration` — compute the upper bound and iterate as
    # a closed interval. This respects the duration bound; the
    # sequence terminates naturally.
    computed_to = Tempo.Math.add(from, duration)
    do_reduce(fill_from(from, interval), computed_to, acc, fun)
  end

  def reduce(%Tempo.Interval{from: %Tempo{} = from, to: to} = interval, acc, fun)
      when is_struct(to, Tempo) or to in [:undefined, nil] do
    # Closed `[from, to)` or open-upper `from/..`. Iteration is
    # driven by `do_reduce/4` below.
    do_reduce(fill_from(from, interval), to, acc, fun)
  end

  def reduce(%Tempo.Interval{}, _acc, _fun) do
    raise ArgumentError,
          "Cannot enumerate this interval shape — only closed `from/to`, " <>
            "open-upper `from/..`, and `from/duration` intervals are iterable."
  end

  # Fill the walk anchor down to the interval's explicit iteration
  # unit (no-op when `:unit` is nil or already at the endpoint's
  # resolution). Subsequent steps derive from the filled value, so
  # the fill happens exactly once per walk.
  defp fill_from(%Tempo{calendar: calendar} = from, %Tempo.Interval{unit: unit}) do
    Steps.fill_to_unit(from, unit, calendar)
  end

  defp do_reduce(_current, _to, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp do_reduce(current, to, {:suspend, acc}, fun) do
    {:suspended, acc, &do_reduce(current, to, &1, fun)}
  end

  defp do_reduce(current, to, {:cont, acc}, fun) do
    case past_end?(current, to) do
      true ->
        {:done, acc}

      false ->
        # Classify each emitted moment against its zone so the walk
        # matches the DST-aware `Tempo.Interval.Steps` count/slice and
        # the implicit `Enumerable.Tempo` walk: skip a spring-forward
        # gap hour, emit a fall-back hour twice with its two offsets.
        case Zone.zone_status(current) do
          :gap ->
            do_reduce(increment(current), to, {:cont, acc}, fun)

          {:ambiguous, first_shift, second_shift} ->
            emit_fold(
              [%{current | shift: first_shift}, %{current | shift: second_shift}],
              current,
              to,
              acc,
              fun
            )

          :ok ->
            do_reduce(increment(current), to, fun.(current, acc), fun)
        end
    end
  end

  # Emit each occurrence of a DST fall-back moment, threading the
  # accumulator and honouring halt/suspend, then advance past the
  # folded hour exactly once.
  defp emit_fold([], current, to, acc, fun),
    do: do_reduce(increment(current), to, {:cont, acc}, fun)

  defp emit_fold([value | rest], current, to, acc, fun) do
    case fun.(value, acc) do
      {:cont, acc2} ->
        emit_fold(rest, current, to, acc2, fun)

      {:halt, acc2} ->
        {:halted, acc2}

      {:suspend, acc2} ->
        {:suspended, acc2, &emit_fold_after_suspend(rest, current, to, fun, &1)}
    end
  end

  defp emit_fold_after_suspend(rest, current, to, fun, {:cont, acc}),
    do: emit_fold(rest, current, to, acc, fun)

  defp emit_fold_after_suspend(_rest, _current, _to, _fun, {:halt, acc}),
    do: {:halted, acc}

  defp emit_fold_after_suspend(rest, current, to, fun, {:suspend, acc}),
    do: {:suspended, acc, &emit_fold_after_suspend(rest, current, to, fun, &1)}

  # Open-upper: `to` is `:undefined` (explicit `../` in source) or
  # `nil` (from+duration shape with no computed upper bound yet).
  # Both mean "no bound to check — never terminate on the upper".

  defp past_end?(_current, :undefined), do: false
  defp past_end?(_current, nil), do: false

  # Half-open `[from, to)` convention: the upper bound is EXCLUSIVE.
  # `current >= to` terminates. See `CLAUDE.md`:
  #   "Every span is inclusive of the first boundary and exclusive of
  #    the last boundary — `[first, last)`."

  defp past_end?(%Tempo{time: current_time}, %Tempo{time: to_time}) do
    case compare_time(current_time, to_time) do
      :lt -> false
      _ -> true
    end
  end

  # Compare two keyword-list time representations as start-moments:
  # missing trailing units are implicitly filled with their unit
  # minimum (month/day minimum is 1, hour/minute/second/week minimum
  # is 0). This lets `1985` (start = 1985-01-01) compare correctly
  # against `1986-06` (start = 1986-06-01) and against `1986` itself.
  #
  # Both lists are assumed sorted descending-by-unit (the invariant
  # the tokenizer and `Unit.sort/2` maintain).

  defp compare_time([], []), do: :eq

  # Microseconds compare by value only — precision sets interval width,
  # not instant ordering (`.12` and `.120` are the same moment).
  defp compare_time([{:microsecond, {v1, _p1}} | t1], [{:microsecond, {v2, _p2}} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  defp compare_time([{:microsecond, {v, _p}} | rest], []) do
    if v > 0, do: :gt, else: compare_time(rest, [])
  end

  defp compare_time([], [{:microsecond, {v, _p}} | rest]) do
    if v > 0, do: :lt, else: compare_time([], rest)
  end

  defp compare_time([{unit, v} | rest], []) do
    min = unit_minimum(unit)

    cond do
      v < min -> :lt
      v > min -> :gt
      true -> compare_time(rest, [])
    end
  end

  defp compare_time([], [{unit, v} | rest]) do
    min = unit_minimum(unit)

    cond do
      min < v -> :lt
      min > v -> :gt
      true -> compare_time([], rest)
    end
  end

  defp compare_time([{unit, v1} | t1], [{unit, v2} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  # Mismatched units at the same position (e.g. week vs month) —
  # conservative bailout. A well-formed interval has endpoints
  # using the same unit vocabulary.
  defp compare_time(_, _), do: :eq

  # Delegates to `Tempo.Math.unit_minimum/1` — see that module's
  # docstring for the start-of-unit semantics.
  defp unit_minimum(unit), do: Math.unit_minimum(unit)

  # Advance a Tempo by 1 unit at its declared resolution, carrying
  # over into coarser units as needed. Delegates to `Tempo.Math`.
  defp increment(%Tempo{calendar: calendar} = tempo) do
    {unit, _span} = Tempo.resolution(tempo)

    case Math.add_unit(tempo, unit, calendar) do
      {:ok, stepped} ->
        stepped

      # `Enumerable.reduce/3` has no error channel, so a value whose next
      # step depends on a year it does not carry has to signal by raising.
      {:error, :requires_anchor} ->
        raise Tempo.RequiresAnchorError, value: tempo
    end
  end
end
