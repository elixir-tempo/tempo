defmodule Tempo.Operations do
  @moduledoc """
  Set operations on Tempo values — union, intersection,
  complement, difference, symmetric difference — plus the
  companion predicates (`disjoint?/2`, `overlaps?/2`,
  `within?/2`, `contains?/2`, `equal?/2`).

  Every operation accepts any Tempo value (implicit `%Tempo{}`,
  `%Tempo.Interval{}`, `%Tempo.IntervalSet{}`, or all-of
  `%Tempo.Set{}`) and routes through `align/2,3` — a single
  preflight that normalises operands to a common anchor class,
  resolution, calendar, and (where relevant) UTC reference frame.
  Set-op results are always `%Tempo.IntervalSet{}`; predicate
  results are booleans.

  See `plans/set-operations.md` for the design rationale
  including:

  * why IntervalSet (not rule-algebra) is the operational form,
  * how timezones and DST are handled,
  * why the `:within` option is required for some operand
    combinations,
  * and the axis-compatibility rule (anchored vs unanchored).

  The top-level user API lives on `Tempo` via delegation — callers
  should prefer `Tempo.union/2`, `Tempo.intersection/2`, etc. over
  calling `Tempo.Operations` directly.

  """

  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.Interval.Cycle
  alias Tempo.IntervalSet
  alias Tempo.Iso8601.Unit
  alias Tempo.Math
  alias Tempo.ResolutionError
  alias Tempo.UnanchoredError
  alias Tempo.UnboundedRecurrenceError
  alias Tempo.Validation

  ## ---------------------------------------------------------------
  ## Preflight — `align/2,3`
  ## ---------------------------------------------------------------

  @doc """
  Normalise two operands to the same anchor class, resolution,
  and calendar, and return them both as `%Tempo.IntervalSet{}`.

  ### Arguments

  * `a` and `b` are any Tempo values that can be converted to
    an interval set — `%Tempo{}`, `%Tempo.Interval{}`,
    `%Tempo.IntervalSet{}`, or `%Tempo.Set{type: :all}`.

  ### Options

  * `:within` — a Tempo value (any of the above types), the window
    the operation works within: a time-of-day operand is placed on
    every day of it, inside the window, and a
    `t:Tempo.RecurrenceSet.t/0` operand gives the occurrences that
    overlap it (the other operand, by default). Required when `a` and
    `b` belong to different anchor classes.

  ### Returns

  * `{:ok, {aligned_a, aligned_b}}` where both are `%Tempo.IntervalSet{}`.

  * `{:error, reason}` when a preflight check fails (duration
    operand, one-of set operand, incompatible anchor classes
    without `:within`, calendar mismatch, a leftover `:bound`,
    etc.).

  * `{:error, %Tempo.FloatingTempoError{}}` when one operand has a
    zone or an offset and the other none: a value with no zone has no
    place on the universal time line, as `Tempo.relation/2` holds.

  ### Examples

      iex> {:ok, {a, b}} = Tempo.Operations.align(~o"2026-01", ~o"2026-03")
      iex> {Tempo.IntervalSet.count(a), Tempo.IntervalSet.count(b)}
      {1, 1}

      iex> Tempo.Operations.align(~o"P1D", ~o"2026-01")
      {:error, %Tempo.ConversionError{value: ~o"P1D", reason: :bare_duration}}

  """
  @spec align(operand, operand, keyword()) ::
          {:ok, {IntervalSet.t(), IntervalSet.t()}} | {:error, term()}
        when operand:
               Tempo.t()
               | Interval.t()
               | IntervalSet.t()
               | Tempo.Set.t()
  def align(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align_members(a, b, opts),
         {:ok, a_set} <- split_crossers(a_set),
         {:ok, b_set} <- split_crossers(b_set) do
      {:ok, {a_set, b_set}}
    end
  end

  # The operands as the operations take them: aligned, and each member whole.
  # A span with no year that runs through its cycle's end is one member here,
  # and is cut where its cycle ends only to be swept (`turns/1`).
  defp align_members(a, b, opts) do
    # A `%Tempo.RecurrenceSet{}` operand is materialised against the other
    # operand (its window), so `intersection(diary, holidays)` needs no explicit
    # `:within` — the diary supplies it. An explicit `:within` still wins.
    with :ok <- Tempo.check_within_option(opts, "a set operation") do
      a = resolve_recurrence_set(a, b, opts)
      b = resolve_recurrence_set(b, a, opts)
      align_resolved(a, b, opts)
    end
  end

  defp align_resolved(a, b, opts) do
    with :ok <- validate_operand(a),
         :ok <- validate_operand(b),
         :ok <- Interval.same_frame(a, b),
         {:ok, class_a, class_b} <- compatible_classes(a, b, opts),
         {:ok, a_set} <- to_aligned_set(a, class_a, opts),
         {:ok, b_set} <- to_aligned_set(b, class_b, opts),
         {:ok, a_set, b_set} <- maybe_anchor_to_window(a_set, b_set, class_a, class_b, opts),
         {:ok, b_set} <- convert_calendar(b_set, a_set),
         {:ok, a_set, b_set} <- canonicalize_axes(a_set, b_set),
         {:ok, a_set, b_set} <- align_resolution(a_set, b_set) do
      {:ok, {walked_by_dates(a_set), walked_by_dates(b_set)}}
    end
  end

  ## Spans with no year, on their cycle.
  ##
  ## An unanchored interval like `T23:30/T01:00` represents a
  ## 1.5-hour span that wraps around midnight on the time-of-day
  ## axis. A sweep orders ends, so such a span is swept as the two
  ## spans it is in one turn of its cycle:
  ##
  ##     [T23:30, T24:00) ∪ [T00:00, T01:00)
  ##
  ## Anchored intervals that cross midnight (after materialisation
  ## to a specific day) are already concrete — they live on the
  ## universal time line and their endpoints don't wrap.
  ##
  ## The same holds on every cycle a value with no year lies on: the
  ## year for a month and a day (`12M31D`, whose span ends at the turn
  ## of the year), the week for a day of the week.
  ## `Tempo.Interval.Cycle.parts/1` cuts each such span at its cycle's
  ## end.
  ##
  ## The span is still one member. So each member of a set with no year
  ## is swept by its own parts (`turns/1`), and what an operation leaves
  ## of it on both sides of the cycle's end is written back as the one
  ## span it is (`Tempo.Interval.Cycle.joined/1`): a member comes back
  ## whole where an operation keeps it, and cut only where the other
  ## operand cuts it.

  defp on_cycle?(%IntervalSet{} = set) do
    case IntervalSet.first(set) do
      nil -> false
      first -> Cycle.cyclic?(first)
    end
  end

  # Each member of a set with the parts it is swept by, in the members'
  # order, each member's parts in the order of their starts.
  defp turns(%IntervalSet{} = set) do
    set
    |> IntervalSet.members()
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, turns} ->
      case Cycle.parts(member) do
        {:ok, parts} -> {:cont, {:ok, [{member, in_order(parts)} | turns]}}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, turns} -> {:ok, Enum.reverse(turns)}
      {:error, _exception} = error -> error
    end
  end

  # Every part of a set's members, in the order of their starts, as a sweep
  # takes its second operand.
  defp parts(%IntervalSet{} = set) do
    with {:ok, turns} <- turns(set) do
      {:ok, turns |> Enum.flat_map(fn {_member, parts} -> parts end) |> in_order()}
    end
  end

  defp in_order(parts),
    do: Enum.sort(parts, &(Compare.compare_endpoints(&1.from, &2.from) != :later))

  # A set with each member that runs through its cycle's end cut there, as
  # `align/3` returns it.
  defp split_crossers(%IntervalSet{} = set) do
    if on_cycle?(set) do
      with {:ok, parts} <- parts(set),
           do: IntervalSet.new(parts, metadata: IntervalSet.metadata(set))
    else
      {:ok, set}
    end
  end

  # Each member of the first set cut by the second: one sweep of the two for
  # sets with a year, and a sweep of each member's own parts for a set with
  # none.
  defp cut_members(%IntervalSet{} = a_set, %IntervalSet{} = b_set, sweep) do
    if on_cycle?(a_set) or on_cycle?(b_set) do
      with {:ok, a_turns} <- turns(a_set),
           {:ok, b_parts} <- parts(b_set) do
        {:ok, Enum.flat_map(a_turns, &cut_member(&1, b_parts, sweep))}
      end
    else
      {:ok, sweep.(IntervalSet.members(a_set), IntervalSet.members(b_set))}
    end
  end

  # A member the other operand does not cut is the member, as it is written.
  defp cut_member({member, parts}, b_parts, sweep) do
    left = sweep.(parts, b_parts)
    if same_spans?(left, parts), do: [member], else: as_spans(left)
  end

  # The members of the first set that overlap the second, or that do not,
  # each kept whole: one of a set with no year overlaps where a part of it
  # does.
  defp kept_members(%IntervalSet{} = a_set, %IntervalSet{} = b_set, mode) do
    if on_cycle?(a_set) or on_cycle?(b_set),
      do: kept_on_cycle(a_set, b_set, mode),
      else: {:ok, sweep_members(IntervalSet.members(a_set), IntervalSet.members(b_set), mode)}
  end

  defp kept_on_cycle(a_set, b_set, mode) do
    with {:ok, a_turns} <- turns(a_set),
         {:ok, b_parts} <- parts(b_set) do
      kept =
        for {member, parts} <- a_turns,
            overlaps_a_part?(parts, b_parts) == (mode == :overlapping),
            do: member

      {:ok, kept}
    end
  end

  # Each member of the first set cut to each member of the second it
  # overlaps, in a set with no year, where a pair's parts on both sides of
  # the cycle's end are one span. A member that lies within the other is cut
  # nowhere, and is written as it is.
  defp shared_on_cycle(%IntervalSet{} = a_set, %IntervalSet{} = b_set, resolve) do
    with {:ok, a_turns} <- turns(a_set),
         {:ok, b_turns} <- turns(b_set) do
      shared =
        for {member, a_parts} <- a_turns,
            {_b_member, b_parts} <- b_turns,
            part <- shared_by_pair(member, a_parts, b_parts, resolve),
            do: part

      {:ok, shared}
    end
  end

  defp shared_by_pair(member, a_parts, b_parts, resolve) do
    case sweep_intersection(a_parts, b_parts, resolve) do
      [%Interval{metadata: metadata} | _rest] = shared ->
        if same_spans?(shared, a_parts),
          do: [%Interval{from: member.from, to: member.to, metadata: metadata}],
          else: as_spans(shared)

      [] ->
        []
    end
  end

  # Whether a sweep has left a member's parts as they were, wherever the
  # other operand's own parts end within them.
  defp same_spans?(left, parts) do
    left = joined_where_they_meet(left)
    parts = joined_where_they_meet(parts)

    length(left) == length(parts) and
      left |> Enum.zip(parts) |> Enum.all?(&same_extent?/1)
  end

  # What a sweep leaves of one member, or of one pair of members, as the
  # spans it is: its parts in one turn of the cycle joined where they meet,
  # within the turn (a whole turn that starts within it is two parts that
  # meet there) and through the cycle's end.
  defp as_spans(fragments), do: fragments |> joined_where_they_meet() |> Cycle.joined()

  defp joined_where_they_meet([first | rest]) do
    rest
    |> Enum.reduce([first], fn fragment, [last | spans] ->
      if Compare.compare_endpoints(last.to, fragment.from) == :same,
        do: [%{last | to: fragment.to} | spans],
        else: [fragment, last | spans]
    end)
    |> Enum.reverse()
  end

  defp joined_where_they_meet([]), do: []

  defp overlaps_a_part?(parts, b_parts),
    do: sweep_members(parts, b_parts, :overlapping) != []

  ## Placing on a window — a `:within` window places each operand with no
  ## year on every day of it, so the operation is of dated spans.
  ##
  ## An operand with no year is placed whatever the other is: a dated one,
  ## another with no year, or an empty set, whose own kind cannot be told
  ## (the working hours of a week with no meetings in it are still that
  ## week's). A window that has no year itself places nothing: it is an
  ## operand on the same cycle, as `complement/2`'s is, and is an error only
  ## where a dated operand needs a dated window.

  defp maybe_anchor_to_window(a, b, class_a, class_b, opts) do
    classes = {anchor_class(a), anchor_class(b)}

    case Keyword.get(opts, :within) do
      nil -> {:ok, a, b}
      within -> place_on_window(a, b, classes, {class_a, class_b}, within)
    end
  end

  # Neither operand has a time of day to place.
  defp place_on_window(a, b, {class_a, class_b}, _compatible, _within)
       when class_a != :unanchored and class_b != :unanchored,
       do: {:ok, a, b}

  defp place_on_window(a, b, classes, compatible, within) do
    with {:ok, window_set} <- Tempo.to_interval_set(within) do
      placed_on_window(a, b, classes, {anchor_class(window_set), compatible}, window_set, within)
    end
  end

  defp placed_on_window(a, b, {class_a, class_b}, {:anchored, _compatible}, window_set, _within) do
    with {:ok, a} <- anchor_if_unanchored(class_a, a, window_set),
         {:ok, b} <- anchor_if_unanchored(class_b, b, window_set) do
      {:ok, a, b}
    end
  end

  # A window with no year, on the operands' own cycle.
  defp placed_on_window(a, b, _classes, {_no_year, {same, same}}, _window_set, _within),
    do: {:ok, a, b}

  # A window with no year, where an operand is dated.
  defp placed_on_window(_a, _b, _classes, _dated_operand, window_set, within),
    do: ensure_anchored_window(window_set, within)

  defp ensure_anchored_window(window_set, within) do
    if anchor_class(window_set) == :anchored do
      :ok
    else
      {:error,
       UnanchoredError.exception(operation: "use a value as the :within window", value: within)}
    end
  end

  # Anchoring to a `:within` window walks its days and grafts each unanchored
  # interval onto every day, which is only meaningful for time-of-day values.
  # A month- or day-axis partial (`~o"15D"`, `~o"06-15"`) grafted onto a day
  # would silently match every day of the window, so reject it and point at
  # the vocabulary that expresses the recurring reading properly.
  defp anchor_if_unanchored(:unanchored, value, window_set) do
    if leading_unit(value) in [:hour, :minute, :second] do
      anchor_to_days(value, window_set)
    else
      {:error,
       UnanchoredError.exception(
         operation:
           "place a value led by #{inspect(leading_unit(value))} on each day of a " <>
             ":within window, which takes a time of day only (write a recurring " <>
             "date as a selection or an RRULE)"
       )}
    end
  end

  defp anchor_if_unanchored(_class, value, _window_set), do: {:ok, value}

  # For each interval in the window, walk each day, and anchor
  # every unanchored interval to that day. Returns {:ok,
  # IntervalSet} or {:error, _}.

  defp anchor_to_days(%IntervalSet{} = unanchored_set, %IntervalSet{} = window_set) do
    times_of_day = IntervalSet.members(unanchored_set)

    window_set
    |> IntervalSet.members()
    |> Enum.reduce_while({:ok, []}, fn window, {:ok, placed} ->
      case placed_on(times_of_day, window) do
        {:ok, on_window} -> {:cont, {:ok, [on_window | placed]}}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, placed} -> placed |> Enum.reverse() |> Enum.concat() |> IntervalSet.new()
      {:error, _exception} = error -> error
    end
  end

  # A time of day is placed on each day the window touches, and what is
  # placed is the part of it the window holds: on a window from noon to noon,
  # nine to five is noon to five on its first day and nine to noon on its
  # last. Nothing placed lies outside the window.
  defp placed_on(times_of_day, %Interval{} = window) do
    with {:ok, days} <- days_in(window) do
      placed =
        for day <- days,
            time <- times_of_day,
            held <- held_by(anchor_interval_to_day(time, day), window),
            do: held

      {:ok, placed}
    end
  end

  defp held_by(%Interval{} = placed, %Interval{from: from, to: to}) do
    held = %{
      placed
      | from: later_endpoint(placed.from, from),
        to: earlier_endpoint(placed.to, to)
    }

    if Compare.compare_endpoints(held.from, held.to) == :earlier, do: [held], else: []
  end

  # The days a window touches, its last included when the window ends part
  # of the way through it. Each is a value of whole units down to its day:
  # a calendar date, or in a calendar of weeks a week and a day of it. The
  # window's ends may be written in any units (a year, a month, a week, a
  # day of the year): a day is read from where the end is, not from a month
  # and a day it may not hold.
  defp days_in(%Interval{from: from, to: to}) do
    with {:ok, first} <- day_of(from) do
      {:ok, first |> Stream.unfold(&day_before(&1, to)) |> Enum.to_list()}
    end
  end

  defp day_before(%Tempo{time: time, calendar: calendar} = day, to) do
    if Compare.compare_endpoints(day, to) == :earlier do
      # A day of a window is a concrete date, so the step cannot need a year.
      {:ok, next} = Math.add_unit(time, day_step(time), calendar)
      {day, %{day | time: next}}
    end
  end

  # The day an end of a window is in.
  defp day_of(%Tempo{calendar: calendar} = endpoint) do
    if Tempo.week_based_calendar?(calendar) do
      {:ok, %{endpoint | time: week_date(endpoint.time)}}
    else
      with {:ok, %Tempo{time: time} = dated} <- month_axis_endpoint(endpoint) do
        {:ok, %{dated | time: calendar_date(time)}}
      end
    end
  end

  defp calendar_date(time) do
    [
      year: Keyword.fetch!(time, :year),
      month: Keyword.get(time, :month, 1),
      day: Keyword.get(time, :day, 1)
    ]
  end

  defp week_date(time) do
    [
      year: Keyword.fetch!(time, :year),
      week: Keyword.get(time, :week, 1),
      day_of_week: Keyword.get(time, :day_of_week, 1)
    ]
  end

  # The unit a day is stepped by: the day of the week where the day is one.
  defp day_step(time), do: if(Keyword.has_key?(time, :day_of_week), do: :day_of_week, else: :day)

  defp anchor_interval_to_day(
         %Interval{from: na_from, to: na_to, metadata: metadata},
         %Tempo{time: day_time, calendar: calendar} = day
       ) do
    if crosses_midnight?(na_from, na_to) do
      # Unanchored interval like `T23:30/T01:00` anchored to
      # day D → `[D T23:30, (D+1) T01:00)`. Advance `to`'s day.
      # The anchoring day is a concrete date, so this step is total.
      {:ok, next_day_time} = Math.add_unit(day_time, day_step(day_time), calendar)
      new_from = on_day(na_from, day_time, day)
      new_to = on_day(na_to, next_day_time, day)
      %Interval{from: new_from, to: new_to, metadata: metadata}
    else
      %Interval{
        from: on_day(na_from, day_time, day),
        to: on_day(na_to, day_time, day),
        metadata: metadata
      }
    end
  end

  # A time of day placed on a day is in the day's zone when it has none of
  # its own, as `Tempo.at/2` places it: 10:00 on a day in Paris is 10:00 in
  # Paris. It is a date and time of the day's calendar, whose units the day
  # is written in: no calendar numbers a time of day.
  defp on_day(%Tempo{time: time} = time_of_day, day_time, %Tempo{calendar: calendar} = day) do
    placed = %{time_of_day | time: day_time ++ time, calendar: calendar}
    {_day, placed} = Interval.propagate_endpoint_frame(day, placed)

    placed
  end

  # An unanchored interval "crosses midnight" when its `from`
  # time-of-day is at or after its `to` time-of-day — e.g.
  # `T23:30/T01:00`, and `T10:00/T10:00`, which ends where it starts
  # and is once round the clock.
  defp crosses_midnight?(%Tempo{time: from_time}, %Tempo{time: to_time}) do
    Compare.compare_time(from_time, to_time) != :lt
  end

  ## Operand validation — reject durations and one-of sets up-front.

  defp validate_operand(%Tempo.Duration{} = value) do
    {:error,
     ConversionError.exception(
       value: value,
       reason: :bare_duration
     )}
  end

  defp validate_operand(%Tempo.Set{type: :one} = value) do
    {:error,
     ConversionError.exception(
       value: value,
       reason: :one_of_set
     )}
  end

  defp validate_operand(_), do: :ok

  ## Anchor-class detection and compatibility check.

  defp compatible_classes(a, b, opts) do
    class_a = anchor_class(a)
    class_b = anchor_class(b)
    within = Keyword.get(opts, :within)

    cond do
      class_a == :empty ->
        {:ok, class_b, class_b}

      class_b == :empty ->
        {:ok, class_a, class_a}

      # Two unanchored operands only share a timeline when they sit on the
      # same resolution axis. `~o"1M31D"` (a month/day) and `~o"15D"` (a bare
      # day) recur on different cycles — annual vs monthly — so aligning them
      # would silently compare incomparable spans. Require a matching leading
      # unit; otherwise it needs a year, like the mixed-class case.
      class_a == :unanchored and class_b == :unanchored and not same_axis?(a, b) ->
        {:error,
         UnanchoredError.exception(
           operation:
             "combine values on different axes (led by #{inspect(leading_unit(a))} " <>
               "and #{inspect(leading_unit(b))}) in a set operation; give both the " <>
               "same leading unit"
         )}

      class_a == class_b ->
        {:ok, class_a, class_b}

      within != nil ->
        {:ok, class_a, class_b}

      true ->
        {:error,
         UnanchoredError.exception(
           operation:
             "combine a value with a year and one without in a set operation " <>
               "that has no `:within` window to place it on"
         )}
    end
  end

  # Classify a value's anchor class. `:anchored` = has a year;
  # `:unanchored` = has none (a time of day, a month and day, a bare
  # day); `:empty` = empty IntervalSet (identity element, compatible
  # with any class).

  defp anchor_class(%IntervalSet{} = set) do
    case IntervalSet.first(set) do
      nil -> :empty
      first -> anchor_class(first)
    end
  end

  defp anchor_class(%Interval{from: %Tempo{} = from}), do: anchor_class(from)
  defp anchor_class(%Interval{to: %Tempo{} = to}), do: anchor_class(to)
  defp anchor_class(%Interval{}), do: :empty

  defp anchor_class(%Tempo.Set{set: [first | _]}), do: anchor_class(first)
  defp anchor_class(%Tempo.Set{set: []}), do: :empty

  # A set's range member is anchored as its ends are.
  defp anchor_class(%Tempo.Range{first: %Tempo{} = first}), do: anchor_class(first)
  defp anchor_class(%Tempo.Range{last: %Tempo{} = last}), do: anchor_class(last)
  defp anchor_class(%Tempo.Range{}), do: :empty

  defp anchor_class(%Tempo{} = tempo) do
    if Tempo.anchored?(tempo), do: :anchored, else: :unanchored
  end

  # Two unanchored operands are comparable only when they lead with the same
  # (coarsest) unit — the axis they recur on. A bare-day value has no month, so
  # it cannot be placed against a month/day value.
  defp same_axis?(a, b), do: leading_unit(a) == leading_unit(b)

  defp leading_unit(%IntervalSet{} = set), do: leading_unit(IntervalSet.first(set))
  defp leading_unit(%Interval{from: %Tempo{} = from}), do: leading_unit(from)
  defp leading_unit(%Interval{to: %Tempo{} = to}), do: leading_unit(to)
  defp leading_unit(%Interval{}), do: nil
  defp leading_unit(%Tempo.Set{set: [first | _]}), do: leading_unit(first)
  defp leading_unit(%Tempo.Range{first: %Tempo{} = first}), do: leading_unit(first)
  defp leading_unit(%Tempo.Range{last: %Tempo{} = last}), do: leading_unit(last)
  defp leading_unit(%Tempo{time: [{unit, _value} | _]}), do: unit
  defp leading_unit(_other), do: nil

  ## Conversion to IntervalSet.

  # A `%Tempo.RecurrenceSet{}` operand materialises against `counterparty` (or an
  # explicit `:within`) as its window, keeping every occurrence that overlaps it —
  # a day's holiday meets a meeting at 10:00 that day. If it cannot (no usable
  # window), it is left as-is for `validate_operand/1` to reject with a clear
  # error.
  defp resolve_recurrence_set(%Tempo.RecurrenceSet{} = recurrence_set, counterparty, opts) do
    within = Keyword.get(opts, :within, counterparty)

    case Tempo.to_interval_set(recurrence_set, within: within) do
      {:ok, %IntervalSet{} = set} -> set
      _other -> recurrence_set
    end
  end

  defp resolve_recurrence_set(other, _counterparty, _opts), do: other

  defp to_aligned_set(%IntervalSet{} = set, _class, _opts), do: {:ok, set}

  defp to_aligned_set(other, _class, _opts) do
    case Tempo.to_interval_set(other) do
      {:ok, %IntervalSet{} = set} -> {:ok, set}
      {:error, _} = err -> err
    end
  end

  ## Calendar alignment — second operand converts to first's
  ## calendar. Unanchored intervals (pure time-of-day) skip this
  ## step because their time components are calendar-independent.
  ##
  ## For anchored intervals, we extend every endpoint to day+
  ## resolution, convert year/month/day via `Date.convert!/2`, and
  ## preserve hour/minute/second (those don't change under
  ## calendar conversion). The converted struct's `:calendar` is
  ## updated to match the target, which is the one record of its
  ## calendar: `to_iso8601/1` writes the `u-ca` suffix from it, so
  ## the output re-parses in the same calendar.

  defp convert_calendar(%IntervalSet{} = b_set, %IntervalSet{} = a_set) do
    convert_calendar_first(b_set, IntervalSet.first(b_set), IntervalSet.first(a_set))
  end

  defp convert_calendar_first(b_set, nil, _a_first), do: {:ok, b_set}
  defp convert_calendar_first(b_set, _b_first, nil), do: {:ok, b_set}

  defp convert_calendar_first(b_set, b_first, a_first) do
    a_cal = endpoint_calendar(a_first)
    b_cal = endpoint_calendar(b_first)

    cond do
      a_cal == b_cal ->
        {:ok, b_set}

      # An interval with unbounded endpoints — an unanchored
      # recurrence such as `~o"R/../P1W/FL1KN"`, which RRULE parsing
      # produces when no DTSTART is supplied — names no calendar.
      # `nil` is not a calendar to convert *into*: passing it on asks
      # `Date.convert!/2` to call a function on `nil`.
      is_nil(a_cal) ->
        {:ok, b_set}

      # Unanchored intervals don't have calendar-bound components;
      # their time-of-day units work the same in any calendar.
      not anchored_endpoint?(b_first.from) ->
        {:ok, b_set}

      true ->
        convert_calendar_intervals(b_set, a_cal)
    end
  end

  # `Tempo.anchored?/1` takes a `%Tempo{}`, and an unbounded endpoint
  # is `nil` — which is not anchored, rather than an error.
  defp anchored_endpoint?(%Tempo{} = tempo), do: Tempo.anchored?(tempo)
  defp anchored_endpoint?(_unbounded), do: false

  defp endpoint_calendar(%Interval{from: %Tempo{calendar: cal}}), do: cal
  defp endpoint_calendar(%Interval{to: %Tempo{calendar: cal}}), do: cal
  defp endpoint_calendar(_), do: nil

  defp convert_calendar_intervals(%IntervalSet{} = set, target_calendar) do
    set
    |> IntervalSet.members()
    |> Enum.reduce_while({:ok, []}, fn %Interval{from: from, to: to} = interval, {:ok, acc} ->
      with {:ok, from} <- convert_tempo_calendar(from, target_calendar),
           {:ok, to} <- convert_tempo_calendar(to, target_calendar) do
        {:cont, {:ok, [%{interval | from: from, to: to} | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, converted} -> {:ok, IntervalSet.with_intervals(set, Enum.reverse(converted))}
      error -> error
    end
  end

  # Convert a single %Tempo{}'s day into the target calendar, keeping its
  # time of day. Unanchored Tempos (no :year) pass through unchanged —
  # their components are calendar-independent. An unbounded endpoint
  # carries no calendar-bound components.
  defp convert_tempo_calendar(nil, _target_calendar), do: {:ok, nil}

  defp convert_tempo_calendar(%Tempo{} = tempo, target_calendar) do
    if Tempo.anchored?(tempo),
      do: convert_anchored_calendar(tempo, target_calendar),
      else: {:ok, tempo}
  end

  # Extend to day precision so there is a day to convert — a calendar date,
  # or a week date's day of the week — and write the converted day in the
  # target calendar's shape.
  defp convert_anchored_calendar(tempo, target_calendar) do
    extended =
      case Tempo.extend_resolution(tempo, day_unit(tempo)) do
        %Tempo{} = ext -> ext
        _ -> tempo
      end

    {day, time_of_day} =
      Enum.split_while(
        extended.time,
        &(elem(&1, 0) not in [:hour, :minute, :second, :microsecond])
      )

    with {:ok, source_date} <- Tempo.to_date(%{extended | time: day, shift: nil}),
         {:ok, date} <- Date.convert(source_date, target_calendar) do
      time = Tempo.date_units(date.year, date.month, date.day, target_calendar) ++ time_of_day

      {:ok, %{extended | time: time, calendar: target_calendar}}
    else
      {:error, %{__exception__: true}} = error ->
        error

      {:error, _reason} ->
        {:error, ConversionError.exception(value: tempo, target: target_calendar)}
    end
  end

  # The day unit a value extends to: the day of the week on a week axis.
  defp day_unit(%Tempo{time: time}),
    do: if(Keyword.has_key?(time, :week), do: :day_of_week, else: :day)

  ## Axis canonicalisation — week-axis endpoints
  ## (`[year, week, day_of_week]`) have no common unit vocabulary
  ## with month-axis endpoints (`[year, month, day]`), so the
  ## sweep cannot compare them. When exactly one operand is
  ## week-axis, rewrite its endpoints as month-axis calendar dates
  ## via `Tempo.Validation.resolve/2` (ISO week semantics,
  ## converted into the endpoint's own calendar). Same-axis pairs
  ## pass through untouched — week-on-week set operations stay on
  ## the week axis.

  defp canonicalize_axes(a_set, b_set) do
    case {week_axis?(a_set), week_axis?(b_set)} do
      {true, false} -> one_axis(a_set, b_set, :first, years_of_weeks?(b_set))
      {false, true} -> one_axis(a_set, b_set, :second, years_of_weeks?(a_set))
      _same_axis -> {:ok, a_set, b_set}
    end
  end

  # In a calendar of weeks a year is made of its weeks, and starts where its
  # first week does, so a year and a week of it are on one axis as they
  # stand: the year is extended to the week, or to the day of the week, as
  # any coarser operand is (`align_resolution/2`). They were taken for two
  # axes, and the week could not be written as a date of a month, which
  # such a calendar need not have.
  defp one_axis(a_set, b_set, _week_operand, true), do: {:ok, a_set, b_set}

  defp one_axis(a_set, b_set, week_operand, false),
    do: month_axis_operands(a_set, b_set, week_operand)

  defp years_of_weeks?(%IntervalSet{} = set) do
    endpoints =
      for %Interval{from: from, to: to} <- IntervalSet.members(set),
          %Tempo{} = endpoint <- [from, to],
          do: endpoint

    endpoints != [] and Enum.all?(endpoints, &year_of_weeks?/1)
  end

  defp year_of_weeks?(%Tempo{time: [{:year, year}], calendar: calendar}) when is_integer(year),
    do: Tempo.week_based_calendar?(calendar)

  defp year_of_weeks?(%Tempo{}), do: false

  defp month_axis_operands(a_set, b_set, :first) do
    with {:ok, converted} <- map_endpoints(a_set, &month_axis_endpoint/1) do
      {:ok, converted, b_set}
    end
  end

  defp month_axis_operands(a_set, b_set, :second) do
    with {:ok, converted} <- map_endpoints(b_set, &month_axis_endpoint/1) do
      {:ok, a_set, converted}
    end
  end

  defp week_axis?(%IntervalSet{} = set) do
    Enum.any?(IntervalSet.members(set), fn %Interval{from: from, to: to} ->
      week_axis_endpoint?(from) or week_axis_endpoint?(to)
    end)
  end

  defp week_axis_endpoint?(%Tempo{time: time}), do: Keyword.has_key?(time, :week)
  defp week_axis_endpoint?(_other), do: false

  # Rewrite one week-axis endpoint as a month-axis calendar date.
  # A week-resolution endpoint denotes the start of its week under
  # the half-open convention, so a missing `:day_of_week` pads to 1
  # before resolution.
  defp month_axis_endpoint(%Tempo{time: time, calendar: calendar} = tempo) do
    if Keyword.has_key?(time, :week) do
      resolved = time |> pad_day_of_week() |> Validation.resolve(calendar)
      month_axis_time(resolved, tempo)
    else
      {:ok, tempo}
    end
  end

  defp month_axis_endpoint(other), do: {:ok, other}

  defp month_axis_time({:error, _} = error, _tempo), do: error

  defp month_axis_time(resolved, tempo) when is_list(resolved) do
    if Keyword.has_key?(resolved, :week) do
      {:error,
       ResolutionError.exception(
         current: :week,
         target: :month,
         operation: :align,
         calendar: tempo.calendar,
         reason:
           "Cannot express #{inspect(tempo)} as a month-axis calendar date " <>
             "under #{inspect(tempo.calendar)}"
       )}
    else
      {:ok, %{tempo | time: resolved}}
    end
  end

  defp pad_day_of_week(time) do
    if Keyword.has_key?(time, :day_of_week) do
      time
    else
      Enum.flat_map(time, fn
        {:week, _} = week -> [week, {:day_of_week, 1}]
        other -> [other]
      end)
    end
  end

  # An end on the week axis becomes a date where the other operand is written
  # in dates (`canonicalize_axes/2`) and where it is extended below its week
  # in a calendar of months (`Tempo.extend_resolution/2`). A member walked by
  # the days of its week, as a week converted to an interval is, is then
  # walked by days: the days of the week are a unit of the week axis alone.
  # Whole weeks stay weeks, and a calendar of weeks keeps its own.
  defp walked_by_dates(%IntervalSet{} = set) do
    members = IntervalSet.members(set)

    if Enum.any?(members, &walked_by_weekdays_of_dates?/1),
      do: IntervalSet.with_intervals(set, Enum.map(members, &walked_by_days/1)),
      else: set
  end

  defp walked_by_weekdays_of_dates?(%Interval{unit: :day_of_week, from: from, to: to}),
    do: not (week_axis_endpoint?(from) or week_axis_endpoint?(to))

  defp walked_by_weekdays_of_dates?(%Interval{}), do: false

  defp walked_by_days(%Interval{} = member) do
    if walked_by_weekdays_of_dates?(member), do: %{member | unit: :day}, else: member
  end

  ## Resolution alignment — extend the coarser operand's endpoints
  ## to the finer resolution.

  defp align_resolution(a_set, b_set) do
    if IntervalSet.empty?(a_set) or IntervalSet.empty?(b_set) do
      {:ok, a_set, b_set}
    else
      align_nonempty_resolution(a_set, b_set)
    end
  end

  defp align_nonempty_resolution(a_set, b_set) do
    a_res = finest_resolution(a_set)
    b_res = finest_resolution(b_set)

    target =
      case Unit.compare(a_res, b_res) do
        :lt -> a_res
        _ -> b_res
      end

    with {:ok, a_aligned} <- apply_resolution(a_set, target),
         {:ok, b_aligned} <- apply_resolution(b_set, target) do
      {:ok, a_aligned, b_aligned}
    end
  end

  # An unbounded endpoint has no resolution to contribute, so it is
  # skipped rather than asked for one. A set of nothing but unbounded
  # endpoints falls back to the default, as an empty set already does.
  defp finest_resolution(%IntervalSet{} = set) do
    set
    |> IntervalSet.members()
    |> Enum.flat_map(fn %Interval{from: from, to: to} -> [from, to] end)
    |> Enum.filter(&is_struct(&1, Tempo))
    |> Enum.map(fn endpoint -> endpoint |> Tempo.resolution() |> elem(0) end)
    |> Enum.min_by(&Unit.sort_key/1, fn -> :day end)
  end

  defp apply_resolution(%IntervalSet{} = set, target) do
    map_endpoints(set, &extend_or_pass(&1, target))
  end

  defp extend_or_pass(%Tempo{} = tempo, target) do
    {current, _} = Tempo.resolution(tempo)

    case Unit.compare(target, current) do
      :lt -> extend_endpoint(tempo, target)
      _eq_or_gt -> {:ok, tempo}
    end
  end

  # There is no resolution to extend an unbounded endpoint to.
  defp extend_or_pass(unbounded, _target), do: {:ok, unbounded}

  defp extend_endpoint(tempo, target) do
    case Tempo.extend_resolution(tempo, target) do
      %Tempo{} = extended -> {:ok, extended}
      {:error, _} = error -> error
    end
  end

  # Apply `mapper` to every interval endpoint in `set`, preserving
  # member order and propagating the first `{:error, _}` returned.
  # Both callers apply monotone per-endpoint transforms, so the
  # from-sorted precondition the sweeps rely on is preserved.
  defp map_endpoints(%IntervalSet{} = set, mapper) do
    with {:ok, mapped} <- map_interval_endpoints(IntervalSet.members(set), mapper, []) do
      {:ok, IntervalSet.with_intervals(set, mapped)}
    end
  end

  defp map_interval_endpoints([], _mapper, acc), do: {:ok, Enum.reverse(acc)}

  defp map_interval_endpoints([%Interval{from: from, to: to} = interval | rest], mapper, acc) do
    with {:ok, mapped_from} <- mapper.(from),
         {:ok, mapped_to} <- mapper.(to) do
      map_interval_endpoints(rest, mapper, [
        %{interval | from: mapped_from, to: mapped_to} | acc
      ])
    end
  end

  ## ---------------------------------------------------------------
  ## Core set operations
  ## ---------------------------------------------------------------

  @doc """
  Union of two operands — every member of either operand, kept
  as a distinct interval with its original metadata.

  Under Tempo's member-preserving semantics, two inputs that
  happen to cover the same time range produce **two** members in
  the result, not one. If you want the canonical instant-set form
  (touching members merged), call `Tempo.IntervalSet.coalesce/1`
  on the result.

  ### Examples

      iex> {:ok, both} = Tempo.union(~o"2026-01", ~o"2026-03")
      iex> Tempo.IntervalSet.count(both)
      2

  Members stay distinct even when they touch; `coalesce/1` merges them:

      iex> {:ok, both} = Tempo.union(~o"2026-01", ~o"2026-02")
      iex> {Tempo.IntervalSet.count(both),
      ...>  both |> Tempo.IntervalSet.coalesce() |> Tempo.IntervalSet.count()}
      {2, 1}

  """
  @spec union(operand, operand | [operand], keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def union(a, b, opts \\ [])

  def union(a, operands, opts) when is_list(operands) do
    fold_operands(a, operands, opts, &union/3)
  end

  def union(a, b, opts) do
    with {:ok, {a_set, b_set}} <- align_members(a, b, opts) do
      IntervalSet.new(IntervalSet.members(a_set) ++ IntervalSet.members(b_set),
        metadata: a_set.metadata
      )
    end
  end

  @doc """
  Intersection of two operands — every instant present in both
  operands, returned as one or more trimmed intervals.

  There is one result interval for each pair of members that
  overlap: the `a` member trimmed to its overlap with the `b`
  member. So a member of `a` gives several intervals when several
  members of `b` overlap it, and where the members of an operand
  overlap each other so do the results (two bookings of one room,
  each within the opening hours, are two results); call
  `Tempo.IntervalSet.coalesce/1` for the time they cover.

  This is the canonical set-theoretic intersection: `A ∩ B`.
  Use it when the question is about *covered time* — "the parts
  of my meetings that fall inside business hours", "the overlap
  between two date ranges".

  For the member-preserving filter (return whole `a` members
  that overlap any `b` member, untrimmed), use
  `members_overlapping/3`.

  ### Options

  * `:metadata` decides what an emitted fragment carries when both
    operands have metadata:

    * `:left` (the default) keeps the source `a` member's metadata
      and drops `b`'s.

    * `:merge` merges the two maps, `b` winning on a conflicting key.

    * `{:merge, fun}` calls `fun.(a_metadata, b_metadata)` and uses
      the result.

  Reach for `{:merge, fun}` whenever the question is *which operands
  produced this window*. A plain `:merge` cannot answer it: merging
  `%{resource: "Alice"}` with `%{resource: "Bob"}` keeps only Bob,
  silently. Supplying a resolver that accumulates keeps both.

  ### N-ary form

  The second argument may be a **list of operands**, intersected
  left-to-right, so *"when are all of these free at once?"* reads as
  one expression. An empty list is the identity — `a` alone.

      iex> alice = ~o"2026-06-15T09:00:00/2026-06-15T12:00:00"
      iex> bob = ~o"2026-06-15T10:00:00/2026-06-15T17:00:00"
      iex> room = ~o"2026-06-15T11:00:00/2026-06-15T15:00:00"
      iex> {:ok, mutual} = Tempo.intersection(alice, [bob, room])
      iex> Tempo.IntervalSet.members(mutual)
      [~o"2026Y6M15DT11H0M0S/T12H0M0S"]

  ### Examples

      iex> alice = Tempo.Interval.new!(
      ...>   from: ~o"2026-06-15T09:00:00", to: ~o"2026-06-15T12:00:00",
      ...>   metadata: %{free: ["Alice"]})
      iex> bob = Tempo.Interval.new!(
      ...>   from: ~o"2026-06-15T10:00:00", to: ~o"2026-06-15T17:00:00",
      ...>   metadata: %{free: ["Bob"]})
      iex> accumulate = fn a, b -> Map.merge(a, b, fn _key, x, y -> x ++ y end) end
      iex> {:ok, both} = Tempo.intersection(alice, bob, metadata: {:merge, accumulate})
      iex> both |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.Interval.metadata/1)
      [%{free: ["Alice", "Bob"]}]

  """
  @spec intersection(operand, operand | [operand], keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def intersection(a, b, opts \\ [])

  def intersection(a, operands, opts) when is_list(operands) do
    fold_operands(a, operands, opts, &intersection/3)
  end

  def intersection(a, b, opts) do
    with {:ok, resolve} <- metadata_resolver(Keyword.get(opts, :metadata, :left)),
         {:ok, {a_set, b_set}} <- align_members(a, b, opts),
         {:ok, shared} <- shared(a_set, b_set, resolve) do
      IntervalSet.new(shared, metadata: a_set.metadata)
    end
  end

  defp shared(a_set, b_set, resolve) do
    if on_cycle?(a_set) or on_cycle?(b_set),
      do: shared_on_cycle(a_set, b_set, resolve),
      else:
        {:ok, sweep_intersection(IntervalSet.members(a_set), IntervalSet.members(b_set), resolve)}
  end

  @doc """
  Member-preserving overlap filter — the **members of `a`** that
  overlap any member of `b`, kept as distinct intervals with
  their original metadata.

  This is the "which of these bookings hit the query window?"
  query. Each surviving member is an entire member of `a` — not
  a trimmed portion.

  For the canonical instant-level intersection (each survivor
  trimmed to its overlap with `b`), use `intersection/3`.

  ### Examples

      iex> bookings = Tempo.IntervalSet.new!([~o"2026-01-05/2026-01-06", ~o"2026-01-20/2026-01-21"])
      iex> {:ok, hits} = Tempo.members_overlapping(bookings, ~o"2026-01-01/2026-01-10")
      iex> Tempo.IntervalSet.members(hits)
      [~o"2026Y1M5D/6D"]

  """
  @spec members_overlapping(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def members_overlapping(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align_members(a, b, opts),
         {:ok, kept} <- kept_members(a_set, b_set, :overlapping) do
      IntervalSet.new(kept, metadata: a_set.metadata)
    end
  end

  # Member-preserving overlap scan over two from-sorted member lists
  # (the `IntervalSet` constructor sorts unconditionally, and `align/3`
  # only applies per-member monotone transforms, so both lists arrive
  # sorted). O(len(a) + len(b)): each step either classifies and
  # advances the leading A member, or permanently discards the leading
  # B member — a B that ends at-or-before the current A starts can
  # never overlap any later A member either, because A is from-sorted.
  #
  # Two half-open intervals share an instant iff `a.from < b.to` and
  # `b.from < a.to` — boundary touches (`:meets`/`:met_by`) are not
  # overlap. `mode` selects which A members survive: `:overlapping`
  # keeps the sharers, `:outside` keeps the rest.

  defp sweep_members([], _b_list, _mode), do: []
  defp sweep_members(a_list, [], :outside), do: a_list
  defp sweep_members(_a_list, [], :overlapping), do: []

  defp sweep_members([a | a_rest] = a_list, [b | b_rest] = b_list, mode) do
    cond do
      # B ends at-or-before A starts — discard B for good.
      Compare.compare_endpoints(b.to, a.from) != :later ->
        sweep_members(a_list, b_rest, mode)

      # B ends after A starts (from above) and starts before A ends:
      # they share an instant.
      Compare.compare_endpoints(b.from, a.to) == :earlier ->
        emit_member(a, mode == :overlapping, a_rest, b_list, mode)

      # B — and, B being from-sorted, every later B — starts at-or-
      # after A ends: this A overlaps nothing.
      true ->
        emit_member(a, mode == :outside, a_rest, b_list, mode)
    end
  end

  defp emit_member(a, true, a_rest, b_list, mode) do
    [a | sweep_members(a_rest, b_list, mode)]
  end

  defp emit_member(_a, false, a_rest, b_list, mode) do
    sweep_members(a_rest, b_list, mode)
  end

  # The intersection of two lists of members, each in the order of its
  # starts: for each pair of members that overlap, the first's cut to the
  # second's, with the metadata `resolve` gives the pair (see
  # `metadata_resolver/1`).
  #
  # The members of either list may overlap each other (two bookings of one
  # room), so a member of B is not done with once one member of A has passed
  # it: each A is met with every B that is still open when it starts. A B is
  # opened once some A reaches its start, and closed for good once an A
  # starts at or after its end, since every later A starts no earlier. Two
  # lists with no overlap of their own are swept in one pass, and a list
  # whose members overlap costs a comparison for each B open at each A.

  defp keep_left_metadata(a_metadata, _b_metadata), do: a_metadata

  defp sweep_intersection(a_list, b_list, resolve),
    do: sweep_pairs(a_list, [], b_list, resolve)

  defp sweep_pairs([], _open, _unopened, _resolve), do: []
  defp sweep_pairs(_a_list, [], [], _resolve), do: []

  defp sweep_pairs([%Interval{} = a | a_rest], open, unopened, resolve) do
    {opened, unopened} = Enum.split_while(unopened, &starts_before_end?(&1, a))
    open = Enum.reject(open ++ opened, &ends_by_start?(&1, a))

    shared_with(a, open, resolve) ++ sweep_pairs(a_rest, open, unopened, resolve)
  end

  # A B that starts before this A ends is one this A may reach; the Bs are in
  # the order of their starts, so the first that does not ends the run.
  defp starts_before_end?(%Interval{from: b_from}, %Interval{to: a_to}),
    do: Compare.compare_endpoints(b_from, a_to) == :earlier

  # A B that ends at or before this A starts shares no time with it, nor
  # with any A after it.
  defp ends_by_start?(%Interval{to: b_to}, %Interval{from: a_from}),
    do: Compare.compare_endpoints(b_to, a_from) != :later

  # A B is open from an earlier A that may have ended later than this one,
  # so each is asked whether it starts before this A ends.
  defp shared_with(%Interval{} = a, open, resolve) do
    for %Interval{} = b <- open, starts_before_end?(b, a) do
      %Interval{
        from: later_endpoint(a.from, b.from),
        to: earlier_endpoint(a.to, b.to),
        metadata: resolve.(a.metadata, b.metadata)
      }
    end
  end

  # `:metadata` decides what an emitted fragment carries when both
  # operands have something to say. `:left` is the historical default.
  # A plain `:merge` is deliberately *not* enough for provenance —
  # merging `%{resource: "Alice"}` with `%{resource: "Bob"}` silently
  # keeps only Bob — so `{:merge, fun}` lets the caller decide how
  # conflicting keys combine.
  defp metadata_resolver(:left), do: {:ok, &keep_left_metadata/2}
  defp metadata_resolver(:merge), do: {:ok, &Map.merge/2}

  defp metadata_resolver({:merge, fun}) when is_function(fun, 2), do: {:ok, fun}

  defp metadata_resolver(other) do
    {:error,
     "Invalid :metadata option #{inspect(other)}. " <>
       "Valid options are :left, :merge, or {:merge, fun/2}"}
  end

  defp later_endpoint(x, y) do
    case Compare.compare_endpoints(x, y) do
      :later -> x
      _ -> y
    end
  end

  defp earlier_endpoint(x, y) do
    case Compare.compare_endpoints(x, y) do
      :earlier -> x
      _ -> y
    end
  end

  @doc """
  Complement of `set` within a window — the instants of the
  `:within` window that no member of `set` covers.

  Unlike `difference/3` (which is member-preserving),
  `complement/2` returns the **instant-set** form: one member
  per gap in the covered region. This is the right semantics
  for "find all free time in the workday" style queries.

  ### Arguments

  * `set` is any Tempo value.

  * `opts` is a keyword list of options.

  ### Options

  * `:within` is the window to complement within — any Tempo
    value. Required: a complement with no window is infinite,
    and Tempo does not pick one implicitly.

  ### Returns

  * `{:ok, interval_set}` — the gaps, one member each.

  * `{:error, reason}` when no `:within` window is given, a
    leftover `:bound` is, or the operands cannot be aligned.

  ### Examples

      iex> lunch = ~o"2026-06-15T12:00:00/2026-06-15T13:00:00"
      iex> day = ~o"2026-06-15T09:00:00/2026-06-15T17:00:00"
      iex> {:ok, free} = Tempo.complement(lunch, within: day)
      iex> Tempo.IntervalSet.members(free)
      [~o"2026Y6M15DT9H0M0S/T12H0M0S", ~o"2026Y6M15DT13H0M0S/T17H0M0S"]

  """
  @spec complement(operand, keyword()) :: {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def complement(set, opts) do
    with :ok <- Tempo.check_within_option(opts, "Tempo.complement/2") do
      complement_within(set, Keyword.get(opts, :within), opts)
    end
  end

  defp complement_within(_set, nil, _opts) do
    {:error,
     UnboundedRecurrenceError.exception(
       reason:
         "`complement/2` requires a `:within` window. A complement with no " <>
           "window is infinite; supply the window to complement within."
     )}
  end

  defp complement_within(set, within, opts) do
    # The input is coalesced so gaps are computed against the
    # union-of-covered-instants, not against overlapping members
    # individually.
    with {:ok, {window_set, input_set}} <- align_members(within, set, opts),
         covered = IntervalSet.coalesce(input_set),
         {:ok, gaps} <- cut_members(window_set, covered, &sweep_difference/2) do
      IntervalSet.new(gaps, metadata: window_set.metadata)
    end
  end

  @doc """
  Difference `a \\ b` — every instant in `a` that is NOT in `b`,
  returned as one or more trimmed intervals.

  Each member of `a` is trimmed to its portions that don't
  overlap any member of `b`. A single `a` member can split into
  multiple fragments if `b` covers only its middle. Each emitted
  fragment carries the source `a` member's metadata.

  This is the canonical set-theoretic difference: `A ∖ B`. Use
  it when the question is about *covered time* — "the parts of
  the workday that aren't lunch", "free time around a busy
  schedule".

  For the member-preserving filter (keep whole `a` members that
  don't overlap any `b` member, drop the rest), use
  `members_outside/3`.

  ### N-ary form

  The second argument may be a **list of operands**, subtracted
  left-to-right, so *"the workday minus everything already booked"*
  reads as one expression rather than a hand-rolled `Enum.reduce`. An
  empty list is the identity — nothing is booked, so all of `a`
  remains — which means the caller never has to special-case it.

      iex> work = ~o"2026-06-15T09:00:00/2026-06-15T17:00:00"
      iex> standup = ~o"2026-06-15T09:00:00/2026-06-15T09:30:00"
      iex> lunch = ~o"2026-06-15T12:00:00/2026-06-15T13:00:00"
      iex> {:ok, free} = Tempo.difference(work, [standup, lunch])
      iex> Tempo.IntervalSet.count(free)
      2

      iex> work = ~o"2026-06-15T09:00:00/2026-06-15T17:00:00"
      iex> {:ok, free} = Tempo.difference(work, [])
      iex> Tempo.IntervalSet.count(free)
      1

  """
  @spec difference(operand, operand | [operand], keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def difference(a, b, opts \\ [])

  def difference(a, operands, opts) when is_list(operands) do
    fold_operands(a, operands, opts, &difference/3)
  end

  def difference(a, b, opts) do
    with {:ok, {a_set, b_set}} <- align_members(a, b, opts),
         {:ok, left} <- cut_members(a_set, b_set, &sweep_difference/2) do
      IntervalSet.new(left, metadata: a_set.metadata)
    end
  end

  # N-ary set operations: the second argument may be a *list* of
  # operands, folded left-to-right. A list is never itself a valid
  # operand, so there is no ambiguity. An empty list is the identity —
  # `a` alone, coerced to a set — which makes "subtract whatever is
  # busy" work without the caller special-casing "nothing is busy".
  defp fold_operands(a, [], opts, _operation), do: as_set(a, opts)

  defp fold_operands(a, operands, opts, operation) do
    Enum.reduce_while(operands, {:ok, a}, fn operand, {:ok, acc} ->
      case operation.(acc, operand, opts) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Coerce a lone operand to its `IntervalSet` form using the same
  # preflight every operation runs.
  defp as_set(a, opts) do
    with {:ok, {a_set, _b_set}} <- align_members(a, a, opts) do
      {:ok, a_set}
    end
  end

  @doc """
  Member-preserving anti-overlap filter — the **members of `a`**
  that do NOT overlap any member of `b`, kept whole with their
  original metadata.

  This is the "which workdays aren't holidays?" query. A member
  of `a` is dropped entirely if any member of `b` overlaps it,
  even partially.

  For the canonical instant-level difference (trim each member
  of `a` to its non-overlapping portion of `b`, splitting if
  necessary), use `difference/3`.

  ### Examples

      iex> bookings = Tempo.IntervalSet.new!([~o"2026-01-05/2026-01-06", ~o"2026-01-20/2026-01-21"])
      iex> {:ok, missed} = Tempo.members_outside(bookings, ~o"2026-01-01/2026-01-10")
      iex> Tempo.IntervalSet.members(missed)
      [~o"2026Y1M20D/21D"]

  """
  @spec members_outside(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def members_outside(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align_members(a, b, opts),
         {:ok, kept} <- kept_members(a_set, b_set, :outside) do
      IntervalSet.new(kept, metadata: a_set.metadata)
    end
  end

  # Sweep-line difference: for each A interval, walk through
  # B intervals that overlap it, emitting the uncovered portions.

  defp sweep_difference([], _b), do: []
  defp sweep_difference(a_list, []), do: a_list

  # The members of A are in order of their starts and may overlap each other
  # (two bookings of one room), so a B that ends inside one A may reach the
  # next: each A is cut by every B that can reach it. Only a B that ends at
  # or before an A starts is dropped for the As after it, which start no
  # earlier.
  defp sweep_difference([%Interval{from: a_from} = a | a_rest], b_list) do
    b_list = Enum.drop_while(b_list, &(Compare.compare_endpoints(&1.to, a_from) != :later))
    {emitted, _remaining_b} = subtract_from(a, b_list)
    emitted ++ sweep_difference(a_rest, b_list)
  end

  # Subtract all overlapping B intervals from a single A interval.
  # Returns `{list_of_uncovered_parts_of_a, remaining_b_list}`.
  # Every emitted fragment carries A's metadata — the surviving
  # portions of A "are" A, with its event identity intact.

  defp subtract_from(%Interval{from: a_from, to: a_to, metadata: a_meta}, []) do
    {maybe_emit(a_from, a_to, a_meta), []}
  end

  defp subtract_from(
         %Interval{from: a_from, to: a_to, metadata: a_meta} = a,
         [%Interval{} = b | b_rest]
       ) do
    cond do
      # B is entirely before A — skip it.
      not after_or_eq?(b.to, a_from) ->
        subtract_from(a, b_rest)

      # B is entirely after A — no more overlaps; emit current A
      # (only if it has positive width — a tail residue from a
      # previous full-cover step can be zero-width).
      not after_or_eq?(a_to, b.from) ->
        {maybe_emit(a_from, a_to, a_meta), [b | b_rest]}

      # B starts inside A (or at its edge).
      true ->
        left = maybe_emit(a_from, b.from, a_meta)
        rest_from = later_endpoint(b.to, a_from)

        if after_or_eq?(a_to, b.to) do
          # B ends inside A — continue subtracting from the rest.
          rest_a = %Interval{from: rest_from, to: a_to, metadata: a_meta}
          {right, remaining_b} = subtract_from(rest_a, b_rest)
          {left ++ right, remaining_b}
        else
          # B fully covers A's tail — stop emitting, B may extend further.
          {left, [b | b_rest]}
        end
    end
  end

  # Emit a one-interval list if `from < to`, empty otherwise.
  # `metadata` is carried on the emitted interval.
  defp maybe_emit(from, to, metadata) do
    case Compare.compare_endpoints(from, to) do
      :earlier -> [%Interval{from: from, to: to, metadata: metadata}]
      _ -> []
    end
  end

  defp after_or_eq?(a, b) do
    Compare.compare_endpoints(a, b) != :earlier
  end

  @doc """
  Symmetric difference `a △ b` — every instant in exactly one
  of the operands, returned as trimmed intervals. Derived as
  `(a \\ b) ∪ (b \\ a)` using the instant-level `difference/3`.

  Use this when the question is about *covered time* — "the
  hours that one of us has free but the other doesn't". For
  the member-preserving filter (whole members of either
  operand that don't overlap any member of the other), use
  `members_in_exactly_one/3`.

  ### Examples

      iex> {:ok, either} = Tempo.symmetric_difference(~o"2026-01/2026-04", ~o"2026-03/2026-06")
      iex> Tempo.IntervalSet.members(either)
      [~o"2026Y1M/3M", ~o"2026Y4M/6M"]

  """
  @spec symmetric_difference(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def symmetric_difference(a, b, opts \\ []) do
    with {:ok, a_minus_b} <- difference(a, b, opts),
         {:ok, b_minus_a} <- difference(b, a, opts) do
      IntervalSet.new(IntervalSet.members(a_minus_b) ++ IntervalSet.members(b_minus_a),
        metadata: a_minus_b.metadata
      )
    end
  end

  @doc """
  Member-preserving symmetric-difference filter — the members
  of either operand that do NOT overlap any member of the
  other, kept whole with their original metadata. Derived as
  `members_outside(a, b) ∪ members_outside(b, a)`.

  This is the "which events appear on exactly one calendar?"
  query. For the canonical instant-level form, use
  `symmetric_difference/3`.

  ### Examples

      iex> mine = Tempo.IntervalSet.new!([~o"2026-01-05/2026-01-06", ~o"2026-01-20/2026-01-21"])
      iex> yours = Tempo.IntervalSet.new!([~o"2026-01-20/2026-01-21", ~o"2026-01-25/2026-01-26"])
      iex> {:ok, unshared} = Tempo.members_in_exactly_one(mine, yours)
      iex> Tempo.IntervalSet.members(unshared)
      [~o"2026Y1M5D/6D", ~o"2026Y1M25D/26D"]

  """
  @spec members_in_exactly_one(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def members_in_exactly_one(a, b, opts \\ []) do
    with {:ok, a_minus_b} <- members_outside(a, b, opts),
         {:ok, b_minus_a} <- members_outside(b, a, opts) do
      IntervalSet.new(IntervalSet.members(a_minus_b) ++ IntervalSet.members(b_minus_a),
        metadata: a_minus_b.metadata
      )
    end
  end

  ## ---------------------------------------------------------------
  ## Predicates
  ## ---------------------------------------------------------------

  @doc """
  `true` when `a` and `b` share no instants — no member of `a`
  overlaps any member of `b`.

  ### Examples

      iex> {Tempo.disjoint?(~o"2026-01", ~o"2026-03"),
      ...>  Tempo.disjoint?(~o"2026-01", ~o"2026-01")}
      {true, false}

  """
  @spec disjoint?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def disjoint?(a, b, opts \\ []) do
    Interval.reject_mixed_frame!(a, b)

    case intersection(a, b, opts) do
      {:ok, %IntervalSet{} = result} -> IntervalSet.empty?(result)
      {:error, exception} -> raise exception
    end
  end

  @doc """
  `true` when `a` and `b` share at least one instant.

  ### Examples

      iex> {Tempo.overlaps?(~o"2026-01/2026-04", ~o"2026-03/2026-06"),
      ...>  Tempo.overlaps?(~o"2026-01", ~o"2026-03")}
      {true, false}

  """
  @spec overlaps?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def overlaps?(a, b, opts \\ []), do: not disjoint?(a, b, opts)

  @doc """
  `true` when every instant covered by `a` is also covered by
  `b` — `a` fits inside `b`, shared ends included. Operates at the
  instant-set level (both operands coalesced internally), not
  member by member, so it answers for single values and sets alike.

  ### Examples

      iex> {Tempo.within?(~o"2026-01-15", ~o"2026-01"),
      ...>  Tempo.within?(~o"2026-01", ~o"2026-01-15")}
      {true, false}

  """
  @spec within?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def within?(a, b, opts \\ []) do
    Interval.reject_mixed_frame!(a, b)

    case difference(a, b, opts) do
      {:ok, %IntervalSet{} = result} -> IntervalSet.empty?(result)
      {:error, exception} -> raise exception
    end
  end

  @doc """
  `true` when every instant covered by `b` is also covered by
  `a` — the mirror of `within?/3`.

  ### Examples

      iex> {Tempo.contains?(~o"2026-01", ~o"2026-01-15"),
      ...>  Tempo.contains?(~o"2026-01-15", ~o"2026-01")}
      {true, false}

  """
  @spec contains?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def contains?(a, b, opts \\ []), do: within?(b, a, opts)

  @doc """
  `true` when `a` and `b` cover the same instants — i.e. they
  are mutual subsets at the instant-set level. Member identity
  and metadata are ignored; only the covered instants matter.

  ### Examples

      iex> Tempo.equal?(~o"2026-01", ~o"2026-01-01/2026-02-01")
      true

      iex> Tempo.equal?(~o"2026-01", ~o"2026-02")
      false

  """
  @spec equal?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def equal?(a, b, opts \\ []) do
    case align(a, b, opts) do
      {:ok, {a_set, b_set}} ->
        a_members = IntervalSet.members(IntervalSet.merged(a_set))
        b_members = IntervalSet.members(IntervalSet.merged(b_set))

        length(a_members) == length(b_members) and
          a_members |> Enum.zip(b_members) |> Enum.all?(&same_extent?/1)

      {:error, exception} ->
        raise exception
    end
  end

  # Instant-set equality is about extents, so members compare by their
  # endpoint *instants* — `compare_endpoints/2` projects through zones
  # and offsets, making `09:00+05:30` equal `03:30Z`. Iteration `:unit`,
  # `:metadata`, and the wall-clock representation are not extents; a
  # struct comparison would resurrect all three.
  defp same_extent?({%Interval{from: a_from, to: a_to}, %Interval{from: b_from, to: b_to}}) do
    endpoint_same?(a_from, b_from) and endpoint_same?(a_to, b_to)
  end

  defp endpoint_same?(%Tempo{} = a, %Tempo{} = b), do: Compare.compare_endpoints(a, b) == :same
  defp endpoint_same?(a, b), do: a == b
end
