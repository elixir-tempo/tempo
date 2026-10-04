defimpl Enumerable, for: Tempo.Interval do
  @moduledoc false

  alias Tempo.Enumeration.Zone
  alias Tempo.Interval.Steps
  alias Tempo.Math
  alias Tempo.Validation

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
  # `unit: :hour`). Otherwise it is the highest resolution the interval's
  # boundaries are written to: the finer of its two ends', so that the
  # values a walk yields are the interval and none runs past its end
  # (`2026/2026-03` is January and February, and `1985/1986-06` the
  # seventeen months from January 1985 to May 1986). When the unit is finer
  # than the start's resolution the walk fills the start down to it once
  # (`Steps.fill_to_unit/3`) instead of the bounds carrying drilled
  # components.
  #
  # Open-lower and fully-open intervals have no start to iterate
  # from, so `reduce/3` raises a clear `ArgumentError`.
  #
  # A *recurring* interval (`recurrence` > 1 or `:infinity`) enumerates
  # exactly as its materialised occurrences do: `reduce/3` delegates to
  # the `Tempo.IntervalSet` walk over `Tempo.to_interval/1`'s expansion,
  # so a bounded recurrence yields the sub-points of every occurrence.
  # An unbounded recurrence cannot be materialised and raises
  # `Tempo.UnboundedRecurrenceError` directing the caller to
  # `Tempo.to_interval/2` with a `:within` window.

  @impl Enumerable
  def count(%Tempo.Interval{recurrence: recurrence}) when recurrence != 1 do
    {:error, __MODULE__}
  end

  def count(%Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to} = interval) do
    case stepped_count(interval, from, to) do
      {n, _from, _unit} when is_integer(n) -> {:ok, max(n, 0)}
      :not_supported -> {:error, __MODULE__}
    end
  end

  # An interval with no end has no count, and the walk `Enum.count/1` falls
  # back to would never end.
  def count(%Tempo.Interval{from: %Tempo{}, to: to, duration: nil} = interval)
      when to in [nil, :undefined] do
    raise endless_error(interval, "Enum.count/1")
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

    # An end or an element with no year, or one that holds a set or a mask,
    # has no place on the time line to compare by, so the walk answers. So it
    # does for ends that are not in the order of their units.
    if dated?(from) and dated?(to) and dated?(element) and Tempo.Compare.structural?(from, to),
      do: stepped_member?(element, from, to, unit, calendar),
      else: {:error, __MODULE__}
  end

  # The walk `Enum.member?/2` falls back to ends only when it finds the
  # element, and an interval with no end is walked for ever.
  def member?(%Tempo.Interval{from: %Tempo{} = from, to: to, duration: nil} = interval, element)
      when to in [nil, :undefined] do
    endless_member?(interval, from, element)
  end

  def member?(_interval, _element), do: {:error, __MODULE__}

  # A walk yields dated values from a dated start, one after another in
  # time. So what is no such value is no member, and one that is has its
  # answer in the step it would be, or in a walk that stops once it has
  # passed it. A start with no year comes round its axis for ever, with no
  # order to stop a search by, so the question is refused.
  defp endless_member?(_interval, _from, element) when not is_struct(element, Tempo),
    do: {:ok, false}

  defp endless_member?(interval, %Tempo{calendar: calendar} = from, element) do
    unit = iteration_unit(interval, from)
    from = Steps.fill_to_unit(from, unit, calendar)

    cond do
      not dated?(from) -> raise endless_error(interval, "Enum.member?/2")
      not dated?(element) -> {:ok, false}
      Tempo.Compare.compare_endpoints(element, from) == :earlier -> {:ok, false}
      true -> {:ok, on_endless_walk?(interval, element, from, unit, calendar)}
    end
  end

  defp on_endless_walk?(interval, element, from, unit, calendar) do
    case Steps.on_step?(element, from, unit, calendar) do
      on_step? when is_boolean(on_step?) -> on_step?
      :not_supported -> found_before_passed?(interval, element)
    end
  end

  defp found_before_passed?(interval, element) do
    Enum.reduce_while(interval, false, fn value, _found? ->
      cond do
        value === element -> {:halt, true}
        Tempo.Compare.compare_endpoints(value, element) == :later -> {:halt, false}
        true -> {:cont, false}
      end
    end)
  end

  defp endless_error(interval, operation) do
    Tempo.IntervalEndpointsError.exception(
      interval: interval,
      operation: operation,
      reason:
        "`#{operation}` needs every value of #{inspect(interval)}, which has no end and " <>
          "would be walked for ever. Take the values you need with `Enum.take/2` or " <>
          "`Enum.take_while/2`, or give the interval an end."
    )
  end

  defp endless_slice_error(interval) do
    Tempo.IntervalEndpointsError.exception(
      interval: interval,
      operation: "Enum.slice/2",
      reason:
        "`Enum.at/2`, `Enum.empty?/1`, `Enum.random/1` and `Enum.slice/2` are not answered " <>
          "for #{inspect(interval)}, which has no end: what needs its last value would walk " <>
          "it for ever. Take the values you need with `Enum.take/2` or `Enum.take_while/2`, " <>
          "or give the interval an end."
    )
  end

  defp stepped_member?(element, from, to, unit, calendar) do
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

  defp dated?(%Tempo{time: time}),
    do: Steps.whole_units?(time) and Keyword.has_key?(time, :year)

  @impl Enumerable
  def slice(%Tempo.Interval{recurrence: recurrence}) when recurrence != 1 do
    {:error, __MODULE__}
  end

  def slice(
        %Tempo.Interval{from: %Tempo{calendar: calendar} = from, to: %Tempo{} = to} = interval
      ) do
    case stepped_count(interval, from, to) do
      {n, from, unit} when is_integer(n) and n >= 0 -> {:ok, n, slicer(from, unit, calendar)}
      _not_counted -> {:error, __MODULE__}
    end
  end

  # A slice is what `Enum.at/2`, `Enum.fetch/2`, `Enum.empty?/1`,
  # `Enum.random/1` and `Enum.slice/2` ask for, and it cannot tell one that
  # needs the start from one that needs the last value, which an interval
  # with no end never reaches. So it is refused, as a lazy interval set
  # refuses it, where the walk they fall back to would never end.
  def slice(%Tempo.Interval{from: %Tempo{}, to: to, duration: nil} = interval)
      when to in [nil, :undefined] do
    raise endless_slice_error(interval)
  end

  def slice(_interval), do: {:error, __MODULE__}

  # The steps in `[from, to)` in closed form, with the start filled to the
  # unit they are counted in. Ends that are not in the order of their units
  # (a week and a date, two zones, two calendars) are counted by the walk.
  defp stepped_count(interval, %Tempo{calendar: calendar} = from, %Tempo{} = to) do
    unit = iteration_unit(interval, from)

    if Tempo.Compare.structural?(from, to) do
      # Fill both bounds: the closed-form step counters read unit
      # components from each side, and start-of-unit filling names the
      # same boundary instant under the half-open convention.
      from = Steps.fill_to_unit(from, unit, calendar)
      to = Steps.fill_to_unit(to, unit, calendar)

      case Steps.count_steps(from, to, unit, calendar) do
        n when is_integer(n) -> {n, from, unit}
        :not_supported -> :not_supported
      end
    else
      :not_supported
    end
  end

  # The unit the interval is walked by from `from`, which is its start or
  # the start a duration was counted to (`Tempo.Interval.granularity/1`).
  defp iteration_unit(%Tempo.Interval{} = interval, %Tempo{} = from),
    do: Tempo.Interval.granularity(%{interval | from: from})

  defp slicer(from, unit, calendar) do
    fn start, length, step ->
      for i <- start..(start + length - 1)//step,
          do: Steps.nth_step(from, i, unit, calendar)
    end
  end

  @impl Enumerable
  def reduce(%Tempo.Interval{} = interval, acc, fun) do
    if occurrences?(interval),
      do: reduce_occurrences(interval, acc, fun),
      else: reduce_span(interval, acc, fun)
  end

  # A recurring interval, or one with an end that holds a selection
  # (`2026Y6ML2KN/P1D`, a day from each Tuesday of June), names several spans
  # and enumerates as they do.
  defp occurrences?(%Tempo.Interval{recurrence: recurrence}) when recurrence != 1, do: true
  defp occurrences?(%Tempo.Interval{from: from, to: to}), do: selects?(from) or selects?(to)

  defp selects?(%Tempo{time: time}), do: List.keymember?(time, :selection, 0)
  defp selects?(_no_endpoint), do: false

  # `to_interval/1` expands a bounded recurrence to an IntervalSet,
  # however it is written (a start and a duration, a start and an end,
  # or a duration and an end); an unbounded one returns
  # `UnboundedRecurrenceError` (raised with its own `:within`
  # direction); one that comes back as a single interval is refused
  # like the crisp API refuses it — never re-entered.
  defp reduce_occurrences(interval, acc, fun) do
    case Tempo.to_interval(interval) do
      {:ok, %Tempo.IntervalSet{} = occurrences} ->
        Enumerable.reduce(occurrences, acc, fun)

      {:ok, %Tempo.Interval{}} ->
        raise no_occurrences_error(interval)

      {:error, exception} when is_exception(exception) ->
        raise exception
    end
  end

  defp no_occurrences_error(%Tempo.Interval{recurrence: recurrence} = interval)
       when recurrence != 1,
       do: Tempo.ConversionError.exception(value: interval, reason: :recurring_interval)

  defp no_occurrences_error(interval) do
    Tempo.IntervalEndpointsError.exception(
      interval: interval,
      reason:
        "Cannot walk #{inspect(interval)}: an end that holds a selection names several " <>
          "dates, and the interval converts to no span for each."
    )
  end

  defp reduce_span(%Tempo.Interval{from: :undefined, to: :undefined}, _acc, _fun) do
    raise ArgumentError,
          "Cannot enumerate a fully open interval `../..` — " <>
            "no start to iterate from."
  end

  defp reduce_span(%Tempo.Interval{from: :undefined, to: %Tempo{}, duration: nil}, _acc, _fun) do
    raise ArgumentError,
          "Cannot enumerate an interval with an open lower bound `../to` — " <>
            "Enumerable iterates forward from the lower bound, which is not defined."
  end

  defp reduce_span(
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
    start = to |> Math.subtract(duration) |> derived!(to)
    walk(interval, fill_from(start, to, interval), to, acc, fun)
  end

  defp reduce_span(
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
    computed_to = from |> Math.add(duration) |> derived!(from)
    walk(interval, fill_from(from, computed_to, interval), computed_to, acc, fun)
  end

  defp reduce_span(%Tempo.Interval{from: %Tempo{} = from, to: to} = interval, acc, fun)
       when is_struct(to, Tempo) or to in [:undefined, nil] do
    # Closed `[from, to)` or open-upper `from/..`. Iteration is
    # driven by `do_reduce/4` below.
    walk(interval, fill_from(from, to, interval), to, acc, fun)
  end

  defp reduce_span(%Tempo.Interval{}, _acc, _fun) do
    raise ArgumentError,
          "Cannot enumerate this interval shape — only closed `from/to`, " <>
            "open-upper `from/..`, and `from/duration` intervals are iterable."
  end

  # A walk steps from one point and stops at another. A start that holds
  # several values (`{2026,2027}Y/2030Y`) is no one point to step from, and
  # an end that does, or that counts from the end of a unit it does not bound
  # (`1M/-1M`), no one point to stop at: the walk would yield nothing, or
  # never end.
  defp walk(interval, %Tempo{time: start_time} = start, to, acc, fun) do
    cond do
      not stepped_from?(start_time) ->
        raise Tempo.ConversionError.exception(value: start, reason: :grouped_component)

      is_struct(to, Tempo) and not stops_at?(to.time, start_time) ->
        raise Tempo.IntervalEndpointsError.exception(
                interval: interval,
                reason:
                  "Cannot walk #{inspect(interval)}: its end is no one point to stop at. It " <>
                    "holds several values (a set, a range, a group or unspecified digits) " <>
                    "or counts from the end of a unit it does not bound."
              )

      true ->
        do_reduce({:at, start}, walk_end(start, to), acc, fun)
    end
  end

  # Whether an end is one point for a walk from `start` to stop at: each unit
  # one whole number, or unspecified where the start is unspecified too
  # (`X*Y12M31D/X*Y1M2D`, two days of whatever year).
  defp stops_at?([{unit, :any} | rest], start),
    do: List.keyfind(start, unit, 0) == {unit, :any} and stops_at?(rest, start)

  defp stops_at?([{:year, year} | rest], start) when is_integer(year), do: stops_at?(rest, start)

  defp stops_at?([{:microsecond, {value, precision}} | rest], start)
       when is_integer(value) and is_integer(precision),
       do: stops_at?(rest, start)

  defp stops_at?([{_unit, value} | rest], start) when is_integer(value) and value >= 0,
    do: stops_at?(rest, start)

  defp stops_at?([], _start), do: true
  defp stops_at?(_several, _start), do: false

  # Whether a walk can step from a time list: one point, or one with an
  # unspecified year (`X*Y12M31D`), which a step carries over. Any other
  # unspecified unit (`2026YX*O`, every day of the year) names a span, as a
  # mask does, and is no one point to step from.
  defp stepped_from?([{:year, :any} | rest]), do: stepped_from?(rest)
  defp stepped_from?([{:year, year} | rest]) when is_integer(year), do: stepped_from?(rest)

  defp stepped_from?([{:microsecond, {value, precision}} | rest])
       when is_integer(value) and is_integer(precision),
       do: stepped_from?(rest)

  defp stepped_from?([{_unit, value} | rest]) when is_integer(value) and value >= 0,
    do: stepped_from?(rest)

  defp stepped_from?([]), do: true
  defp stepped_from?(_several), do: false

  # Fill the walk's start down to the unit the walk steps by (no-op when
  # it is already at that resolution): the interval's explicit unit, or the
  # finer of its two ends'. Subsequent steps derive from the filled value,
  # so the fill happens exactly once per walk. A start that is not one point
  # is left for the walk to refuse.
  defp fill_from(%Tempo{calendar: calendar, time: time} = from, to, interval) do
    if stepped_from?(time),
      do: Steps.fill_to_unit(from, iteration_unit(%{interval | to: to}, from), calendar),
      else: from
  end

  # The end a duration is counted to from the other. One it cannot be
  # counted to (the day after `2M28D`, which depends on the year) leaves no
  # walk to make, and `Enumerable.reduce/3` has no error to return, so the
  # stepper's error is raised.
  defp derived!(%Tempo{} = endpoint, _other), do: endpoint
  defp derived!({:error, exception}, _other) when is_exception(exception), do: raise(exception)

  # A value that holds unspecified digits steps to a set of candidates.
  defp derived!(_several, other),
    do: raise(Tempo.ConversionError.exception(value: other, reason: :grouped_component))

  # Where a walk stops: at its end, or never when it has none. A span with
  # no year lies on an axis that comes round again — the hours of a day, the
  # days of a week, the months of a year — so one that ends before it starts
  # (`7K/1K`, Sunday to Monday; `T22H/T2H`, ten at night to two) runs off the
  # end of the axis and on to its end.
  #
  # Two ends written on one axis, in one zone and one calendar, are in the
  # order of their units, and the walk reads its position against the end so.
  # Any others (a week and a date, two zones, two calendars) are ordered as
  # the moments they are.
  #
  # Ends with no line to share (a day of no year and a year, `X*Y6M15D/2030Y`)
  # have no order to stop by, and their error is raised before a value is
  # given.
  defp walk_end(%Tempo{} = start, %Tempo{} = to) do
    case Tempo.Compare.orderable(start, to) do
      {:error, %Tempo.UnanchoredError{} = exception} -> raise exception
      _ordered_or_read_by_the_walk -> end_on_one_line(start, to)
    end
  end

  defp walk_end(_start, to), do: to

  defp end_on_one_line(%Tempo{time: start_time} = start, %Tempo{time: to_time} = to) do
    cond do
      cyclic?(start_time) -> end_on_a_cycle(start, compare_time(start_time, to_time), to)
      Tempo.Compare.structural?(start, to) -> to
      true -> {:as_moments, to}
    end
  end

  # A span with no year that ends where it starts is once round its axis
  # (`T0H/T0H`, the whole day), and one that ends before it starts runs off
  # the end of the axis and on to its end.
  defp end_on_a_cycle(start, :eq, _to), do: {:turn, start}
  defp end_on_a_cycle(start, :gt, to), do: {:round, start, to}
  defp end_on_a_cycle(_start, :lt, to), do: to

  defp cyclic?(time) do
    case List.keyfind(time, :year, 0) do
      nil -> true
      {:year, :any} -> true
      _year -> false
    end
  end

  # The walk's position is the value it is at, `{:at, value}`, or the one
  # after the value it last gave, `{:after, value}`. The step is taken only
  # when the walk goes on, so a walk that stops short of a step it cannot
  # take (`Enum.take(~o"2M27D/..", 2)`, which stops at 28 February) gives the
  # values it has.
  defp do_reduce(_position, _to, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp do_reduce(position, to, {:suspend, acc}, fun) do
    {:suspended, acc, &do_reduce(position, to, &1, fun)}
  end

  defp do_reduce(position, to, {:cont, acc}, fun) do
    current = reached(position)

    case past_end?(current, to) and not first_of_turn?(position, to) do
      true ->
        {:done, acc}

      false ->
        # Classify each emitted moment against its zone so the walk
        # matches the DST-aware `Tempo.Interval.Steps` count/slice and
        # the implicit `Enumerable.Tempo` walk: skip a spring-forward
        # gap hour, emit a fall-back hour twice with its two offsets.
        case Zone.zone_status(current) do
          :gap ->
            do_reduce({:after, current}, to, {:cont, acc}, fun)

          {:ambiguous, first_shift, second_shift} ->
            yielded = yielded(current)

            emit_fold(
              [%{yielded | shift: first_shift}, %{yielded | shift: second_shift}],
              current,
              to,
              acc,
              fun
            )

          :ok ->
            do_reduce({:after, current}, to, fun.(yielded(current), acc), fun)
        end
    end
  end

  defp reached({:at, value}), do: value
  defp reached({:after, value}), do: increment(value)

  # The value a step gives. A week of a calendar of months is stepped by its
  # own days, a week and a day of it, and each is given as the date it names,
  # as the walk of the week gives it and a value read is held.
  defp yielded(%Tempo{} = value), do: Validation.calendar_date_from_week_date(value)

  # A whole turn ends where it starts, so its first value is given before
  # the walk can be past its end.
  defp first_of_turn?({:at, _start}, {:turn, _same_start}), do: true
  defp first_of_turn?(_position, _to), do: false

  # Emit each occurrence of a DST fall-back moment, threading the
  # accumulator and honouring halt/suspend, then advance past the
  # folded hour exactly once.
  defp emit_fold([], current, to, acc, fun),
    do: do_reduce({:after, current}, to, {:cont, acc}, fun)

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

  defp past_end?(%Tempo{} = current, {:as_moments, %Tempo{} = to}),
    do: Tempo.Compare.compare_endpoints(current, to) != :earlier

  # A whole turn is past its end when it is back at its start.
  defp past_end?(%Tempo{time: current}, {:turn, %Tempo{time: start}}),
    do: compare_time(current, start) == :eq

  # A walk that comes round is past its end once it is at or after it and
  # before its start again.
  defp past_end?(%Tempo{time: current}, {:round, %Tempo{time: start}, %Tempo{time: to}}) do
    compare_time(current, to) != :lt and compare_time(current, start) == :lt
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
      # A step that leaves the value where it is (a year on from `X*Y`, an
      # unspecified year) would walk it for ever.
      {:ok, ^tempo} ->
        raise Tempo.ConversionError, value: tempo, reason: :grouped_component

      {:ok, stepped} ->
        stepped

      # `Enumerable.reduce/3` has no error channel, so a value whose next
      # step depends on a year it does not carry has to signal by raising.
      {:error, :unanchored} ->
        raise Tempo.UnanchoredError, value: tempo

      # Nor has one whose next step would count from a unit holding several
      # values.
      {:error, :grouped_component} ->
        raise Tempo.ConversionError, value: tempo, reason: :grouped_component
    end
  end
end
