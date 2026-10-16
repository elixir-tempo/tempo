defmodule Tempo.Select do
  @moduledoc false
  # Selection: the values a selection picks in a period (plan, section 7.4).
  #
  # A selection's parts are units beneath a period: `[day_of_week: 1,
  # instance: 1]` in June 2026 is its first Monday. The engine walks the
  # period at the parts' container unit (the months of a year for days of
  # the week, the days of a span for a time of day), expands the container's
  # units with the parts (`Tempo.Expand.expand/2`: a count from the end, a
  # list, a label under a month or a week, a clock reading through the zone),
  # keeps the values that lie within the period, filters them by the years a
  # rule names, and applies the positions (`instance`) to the whole period's
  # candidates. A nested selection with a window opens a span of the window's
  # length from each value it picks, and the parts after it select within
  # each. An event (`(easter)e`) is asked of `Tempo.Event` for each year the
  # period runs through. A roll (`(modified-nearest)r`) moves each value
  # picked to a weekday before the positions are applied.

  alias Tempo.{
    ConversionError,
    Duration,
    Event,
    Expand,
    Limit,
    Placed,
    Shift,
    Skip,
    Spans,
    Unit,
    Workdays,
    Zone
  }

  @part_units [
    :month,
    :traditional_month,
    :week,
    :day,
    :day_of_week,
    :day_of_year,
    :hour,
    :minute,
    :second
  ]

  # The parts a skip moves: a month and a day of it.
  @skipped_units [:month, :traditional_month, :day]

  @type parts :: Unit.selection()

  @doc """
  The values a selection picks in a period, in order: `{:ok, values}` with
  each a `%Tempo{}` of the `:value` form (or the `:span` form for a window),
  or an error when the period has no extent.
  """
  @spec in_period(Tempo.t() | Placed.t(), parts(), keyword()) ::
          {:ok, [Tempo.t()]} | {:error, Exception.t()}
  # A placed period is selected in at the place it was given, not placed again.
  def in_period(%Placed{start: start, stop: stop, span: period}, parts, options)
      when is_integer(start) and is_integer(stop),
      do: in_period(period, parts, Keyword.put(options, :extent, {start, stop}))

  def in_period(%Placed{span: period}, parts, options), do: in_period(period, parts, options)

  def in_period(%Tempo{} = period, parts, options) do
    {before, nested, window, later} = around_nested(parts)
    {position, later} = counted_among_all(nested, later)
    {given, options} = Keyword.pop(options, :extent)

    with :ok <- anchored(period),
         {:ok, {start, stop} = outer} <- known_extent(given, period),
         {:ok, periods} <-
           windows(scopes(period, before, outer, options), nested, window, options) do
      # Where the period is selected in whole, its extent is the one known.
      known = if before == [] and nested == nil, do: {:ok, outer}, else: nil

      periods
      |> Enum.flat_map(&selected(&1, later, outer_of(&1, nested, {start, stop}), options, known))
      |> positioned(position)
      |> then(&{:ok, &1})
    end
  end

  # A caller that has the period's extent gives it (`:extent`), and it is not reckoned again.
  defp known_extent({start, stop} = extent, _period) when is_integer(start) and is_integer(stop),
    do: {:ok, extent}

  defp known_extent(_none, period), do: bounded_extent(period)

  # A position after a set of selections counts among all they select in
  # the period, as a position counts last among what the rules before it
  # select (ISO 8601-2 §12.9): the first of the second Mondays and second
  # Wednesdays of a month is whichever comes first.
  defp counted_among_all({:all, _each}, later) do
    case Enum.split_with(later, &match?({:instance, _}, &1)) do
      {[instance: position], later} -> {position, later}
      {_none, _later} -> {nil, later}
    end
  end

  defp counted_among_all(_nested, later), do: {nil, later}

  # A window a nested selection opens may run out of the period that made
  # it: the Friday before a New Year's Day is in the year before. What is
  # selected in a window is selected in the whole of it.
  defp outer_of(_period, nil, outer), do: outer

  defp outer_of(window, _nested, outer) do
    case bounded_extent(window) do
      {:ok, extent} -> extent
      {:error, _} -> outer
    end
  end

  @doc """
  What to look for, and a year, a month or a day at a time, to find where
  parts next name a value: the unit their coarsest counts in and the parts
  less a position and a roll. Nil for parts that name no value of their own.
  """
  @spec probe(Unit.selection()) :: {Unit.t(), Unit.selection()} | nil
  def probe(parts) do
    # A roll is left out with the position: the period a value is named in
    # is looked for, and a value rolled out of it would name the next.
    search = Keyword.drop(parts, [:instance, :roll, :skip])
    units = Enum.filter(search, fn {unit, _} -> unit in @part_units end)

    cond do
      units != [] -> {container_of(coarsest(units)), search}
      Keyword.has_key?(search, :event) -> {:year, search}
      true -> nil
    end
  end

  # A period with no year has no days to select in.
  defp anchored(period) do
    case Spans.frame(period) do
      {:cycle, _} -> {:error, ConversionError.exception(value: period, reason: :needs_a_year)}
      _line -> :ok
    end
  end

  # A nested selection, written `L…N/P…` inside, with its window, the parts
  # written before it and those after. Rules apply higher order first
  # (ISO 8601-2 §12.1): the parts before say where the nested selection is
  # made (`11M` before it, in November), and the parts after select within
  # each window it opens. With no nested selection every part selects in the
  # period.
  defp around_nested(parts) do
    case Enum.split_while(parts, fn {key, _held} -> key not in [:selection, :all] end) do
      {parts, []} ->
        {[], nil, nil, parts}

      {before, [{:all, each} | later]} ->
        {before, {:all, each}, nil, later}

      {before, [{:selection, nested} | rest]} ->
        {window, later} = Keyword.pop(rest, :window)
        {before, nested, window, later}
    end
  end

  # Where a nested selection is made: the period, or each value the parts
  # before it select there.
  defp scopes(period, [], _outer, _options), do: [period]
  defp scopes(period, before, outer, options), do: selected(period, before, outer, options)

  # The periods the later parts select in: each scope itself, or a window
  # from each value a nested selection picks in it.
  defp windows(scopes, nil, _window, _options), do: {:ok, scopes}

  # A set of selections picks what each of its selections picks, in time
  # order, a value two of them pick once.
  defp windows(scopes, {:all, each}, nil, options) do
    Enum.reduce_while(scopes, {:ok, []}, fn scope, {:ok, windows} ->
      case all_picked(scope, each, options) do
        {:ok, picked} -> {:cont, {:ok, windows ++ picked}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp windows(scopes, nested, window, options) do
    Enum.reduce_while(scopes, {:ok, []}, fn scope, {:ok, windows} ->
      case in_period(scope, nested, options) do
        {:ok, picked} -> {:cont, {:ok, windows ++ Enum.map(picked, &windowed(&1, window, scope))}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp all_picked(scope, each, options) do
    each
    |> Enum.reduce_while({:ok, []}, fn parts, {:ok, picked} ->
      case in_period(scope, parts, options) do
        {:ok, more} -> {:cont, {:ok, picked ++ more}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> in_time_order()
  end

  defp in_time_order({:ok, picked}),
    do: {:ok, picked |> Enum.uniq() |> Enum.sort_by(&Spans.start_position/1) |> first_showings()}

  defp in_time_order(error), do: error

  defp windowed(value, nil, _period), do: value

  # A window of a negative length runs back from the value: the seven days
  # before Easter, and not Easter.
  defp windowed(%Tempo{form: {:value, _}} = value, %Duration{} = window, period) do
    if backward?(window),
      do: back_window(Shift.shift(value, window), window, value, period),
      else: %{period | form: {:span, value, window}}
  end

  defp windowed(%Tempo{form: {:span, from, _}} = span, %Duration{} = window, _period),
    do: %{span | form: {:span, from, window}}

  defp windowed(other, _window, _period), do: other

  defp backward?(%Duration{units: units}),
    do: units != [] and Enum.all?(units, fn {_unit, held} -> is_integer(held) and held <= 0 end)

  defp back_window({:ok, from}, window, _value, period),
    do: %{period | form: {:span, from, Spans.negated(window)}}

  defp back_window({:error, _}, window, value, period),
    do: %{period | form: {:span, value, window}}

  # ── One period ────────────────────────────────────────────────────────

  # The candidates of a period: with no parts left the period itself (a
  # window), else the expansion of each container with the parts, within the
  # period, filtered by the rule's years, then positioned.
  defp selected(period, parts, outer, options, known \\ nil)

  defp selected(period, [], _outer, _options, _known), do: [period]

  defp selected(period, parts, outer, options, known) do
    {instance, parts} = Keyword.pop(parts, :instance)
    {years, parts} = Keyword.pop(parts, :year)
    {event, parts} = Keyword.pop(parts, :event)
    {roll, parts} = Keyword.pop(parts, :roll)
    {skip, parts} = Keyword.pop(parts, :skip)
    moves = %{event: event, roll: roll, skip: skip, years: years, instance: instance}

    case known || bounded_extent(period) do
      {:ok, extent} ->
        extent = clipped(extent, outer)
        moved? = event != nil or roll != nil or skip != nil
        picked(on_its_day(moved?, period, parts, extent), period, extent, moves, options)

      {:error, _} ->
        []
    end
  end

  # What a period picks: nothing, where its one day is not one its parts
  # name; the day itself, or the times named on it; else what its parts
  # select, moved, filtered and positioned as they say.
  defp picked(:none, _period, _extent, _moves, _options), do: []

  defp picked({:day, []}, period, {start, _stop}, moves, _options),
    do: positioned([the_day(period, start)], moves.instance)

  defp picked({:times, values}, period, extent, moves, _options),
    do: values |> Enum.flat_map(&met(&1, period, extent)) |> positioned(moves.instance)

  defp picked({_kept_or_day, parts}, period, extent, moves, options) do
    period
    |> candidates(parts, moves.event, extent, options)
    |> Kernel.++(skipped(period, parts, moves.skip, extent))
    |> Enum.uniq()
    |> Enum.filter(&in_years?(&1, moves.years))
    |> rolled(moves.roll, options)
    |> Enum.sort_by(&Spans.start_position/1)
    |> first_showings()
    |> positioned(moves.instance)
  end

  # The day a period within one day is, as a value: a span of one day is
  # the day it holds.
  defp the_day(%Tempo{form: {:value, _units}} = period, _start), do: period

  defp the_day(period, start),
    do: as_value(period, Shift.period_units(start, :day, frame(period)))

  # A period within one day is a day the parts naming a month, a day of the
  # month or a weekday are true of or not: the period selects nothing where
  # one is not, and the parts finer than a day select within it where all
  # are. A daily rule of weekdays asks of each day whether it is one, and
  # does not look for the weekdays of its month.
  defp on_its_day(false = _moved?, period, parts, {start, stop}) do
    {dated, finer} =
      Enum.split_with(parts, fn {unit, _} -> unit in [:month, :day, :day_of_week] end)

    if Enum.all?(finer, fn {unit, _} -> Unit.clock?(unit) end) and
         Enum.all?(dated, &plain_held?/1) do
      day = one_day(period, start, stop)
      day |> day_tested(dated, finer, period.calendar) |> at_times(period, day)
    else
      {:ok, parts}
    end
  end

  defp on_its_day(true, _period, parts, _extent), do: {:ok, parts}

  defp one_day(period, start, stop) do
    frame = frame(period)
    first = Shift.period_units(start, :day, frame)
    if Shift.period_units(stop - 1, :day, frame) == first, do: first, else: nil
  end

  defp day_tested(nil, dated, finer, _calendar), do: {:ok, dated ++ finer}

  defp day_tested(_day, [], finer, _calendar), do: {:ok, finer}

  defp day_tested([year: year, month: month, day: day], dated, finer, calendar) do
    weekday = Tempo.Calendar.day_of_week(calendar, year, month, day)
    actual = [month: month, day: day, day_of_week: weekday]

    if Enum.all?(dated, fn {unit, held} -> holds?(held, actual[unit]) end),
      do: {:day, finer},
      else: :none
  end

  defp day_tested(_units, dated, finer, _calendar), do: {:ok, dated ++ finer}

  # Times of day named by number on a day are its values, each shown at
  # the reading's first showing and none where the clock skips the reading:
  # nothing need be looked for. Anything else is looked for as it is.
  defp at_times({:day, finer} = tested, period, day) do
    if whole_times?(finer) and Enum.all?(finer, &named_time?/1),
      do: {:times, times_on(period, day, finer)},
      else: tested
  end

  defp at_times({:ok, [_ | _] = finer}, period, day) when is_list(day),
    do: at_times({:day, finer}, period, day)

  defp at_times(tested, _period, _day), do: tested

  # An hour, an hour and a minute, or all three: a reading of the day.
  defp whole_times?(finer),
    do: Enum.sort(Keyword.keys(finer)) in [[:hour], [:hour, :minute], [:hour, :minute, :second]]

  defp named_time?({unit, held}) when unit in [:hour, :minute, :second],
    do: natural?(held) or (is_list(held) and Enum.all?(held, &natural?/1))

  defp named_time?(_part), do: false

  defp times_on(period, day, finer) do
    finer
    |> Enum.sort_by(fn {unit, _} -> unit_index(unit) end)
    |> Enum.reduce([day], fn {unit, held}, prefixes ->
      for prefix <- prefixes, n <- Enum.sort(List.wrap(held)), n >= 0, do: prefix ++ [{unit, n}]
    end)
    |> Enum.map(&as_value(period, &1))
    |> Enum.reject(&skipped_reading?/1)
  end

  defp skipped_reading?(%Tempo{zone: %Zone{name: name} = zone, shift: nil} = value)
       when is_binary(name) do
    case Spans.extent(%{value | zone: nil}) do
      {:ok, {wall, _}} when is_integer(wall) ->
        match?({:gap, _, _}, Zone.offsets_at_wall(zone, wall))

      _no_reading ->
        true
    end
  end

  defp skipped_reading?(_value), do: false

  # A whole number of a unit, or a list of them and of ranges, all counted
  # from the start.
  defp plain_held?({_unit, n}) when is_integer(n), do: n > 0

  defp plain_held?({_unit, held}) when is_list(held),
    do:
      Enum.all?(
        held,
        &(positive?(&1) or match?(%Range{first: f, last: l, step: 1} when f > 0 and l >= f, &1))
      )

  defp plain_held?(_part), do: false

  defp positive?(n), do: is_integer(n) and n > 0
  defp natural?(n), do: is_integer(n) and n >= 0

  defp holds?(n, value) when is_integer(n), do: n == value

  defp holds?(held, value) when is_list(held),
    do: Enum.any?(held, &(&1 == value or (is_struct(&1, Range) and value in &1)))

  # What a selection with a skip is given for the days and months it names
  # that a year lacks (`Tempo.Skip`): the day after or the day before, with
  # the times of day the selection names. Such a day may lie outside the
  # period it was looked for in, the first of March for a 29th of February.
  defp skipped(_period, _parts, nil, _extent), do: []

  defp skipped(period, parts, direction, extent) do
    unit_parts = Enum.filter(parts, fn {unit, _} -> unit in @part_units end)
    {times, dates} = Enum.split_with(unit_parts, fn {unit, _} -> Unit.clock?(unit) end)

    if dates == [] or not Enum.all?(Keyword.keys(dates), &(&1 in @skipped_units)) do
      []
    else
      period
      |> containers(container_of(coarsest(dates)), extent)
      |> Enum.flat_map(fn %Tempo{form: {:value, container}} ->
        Skip.replacements(period.calendar, container, dates, direction)
      end)
      |> Enum.flat_map(&each_value(period, &1 ++ times))
    end
  end

  defp each_value(period, units) do
    case Expand.expand(units, frame(period)) do
      {:ok, values} -> values |> Enum.take(Limit.values()) |> Enum.map(&as_value(period, &1))
      {:error, _} -> []
    end
  end

  # Each value picked is rolled to a weekday by a convention, where the
  # selection names one, and two that roll to one day are that day once.
  # The weekdays are those of the locale asked in (`:locale`), or of the
  # territory in force. A rolled value may lie outside the period it was
  # picked in: a first of the month kept on the Friday before it.
  defp rolled(values, nil, _options), do: values

  defp rolled(values, convention, options) do
    workdays = workdays!(options[:locale])

    values
    |> Enum.flat_map(fn value ->
      case Workdays.roll(value, workdays, convention) do
        {:ok, rolled} -> [rolled]
        {:error, _not_a_day} -> []
      end
    end)
    |> Enum.uniq()
  end

  defp workdays!(locale) do
    case Workdays.new(locale) do
      {:ok, workdays} -> workdays
      {:error, exception} -> raise exception
    end
  end

  defp clipped({start, stop}, {outer_start, outer_stop}),
    do: {max(start, outer_start), min(stop, outer_stop)}

  defp candidates(period, parts, nil, extent, _options) do
    unit_parts =
      parts
      |> Enum.filter(fn {unit, _} -> unit in @part_units end)
      |> Enum.map(&weekday_from_end(&1, period.calendar))

    if unit_parts == [] do
      []
    else
      unit = coarsest(unit_parts)

      period
      |> containers(counted_in(unit, period, extent), extent)
      |> Enum.flat_map(&in_container(&1, period, unit_parts, unit, extent))
    end
  end

  defp candidates(period, parts, {name, zone}, extent, _options) do
    period
    |> years_through(extent)
    |> Enum.flat_map(&event_date(name, zone, &1, period))
    |> Enum.flat_map(&with_parts(&1, parts, period))
    |> Enum.flat_map(&met(&1, period, extent))
  end

  # A week is of the year or the month that numbers it, though it may begin
  # before it or end after: the first week of 2026 begins in 2025. So a
  # numbered week is picked when the period holds the whole of what numbers
  # it, as any candidate is that lies within the period.
  defp in_container(container, period, parts, :week, extent) do
    if within?(container, extent),
      do: expanded(period, container, parts),
      else: in_container(container, period, parts, :other, extent)
  end

  defp in_container(container, period, parts, _unit, extent) do
    period
    |> placed_values(container, parts)
    |> Enum.flat_map(fn {value, placed} -> met(value, placed, period, extent) end)
  end

  # A day of the week counted from the end of the week: `-1K` is the week's last day.
  defp weekday_from_end({:day_of_week, held}, calendar) do
    days = Tempo.Calendar.days_in_week(calendar)

    from_end = fn
      n when is_integer(n) and n < 0 -> days + n + 1
      other -> other
    end

    case held do
      list when is_list(list) -> {:day_of_week, Enum.map(list, from_end)}
      held -> {:day_of_week, from_end.(held)}
    end
  end

  defp weekday_from_end(part, _calendar), do: part

  # A candidate within the period is picked whole; one the period lies within
  # picks the period itself (an hour of the 15th, asked for the 15th); one
  # that overlaps otherwise is not picked.
  defp met(%Tempo{} = candidate, period, extent), do: met(candidate, nil, period, extent)

  # A candidate whose extent its expansion gave is not placed again.
  defp met(%Tempo{} = candidate, nil, period, extent) do
    case Spans.extent(candidate) do
      {:ok, {s, e}} when is_integer(s) and is_integer(e) ->
        met_at({s, e}, extent, candidate, period)

      _ ->
        []
    end
  end

  defp met(candidate, placed, period, extent), do: met_at(placed, extent, candidate, period)

  defp met_at({s, e}, {start, stop}, candidate, _period) when s >= start and e <= stop,
    do: [candidate]

  defp met_at({s, e}, {start, stop}, _candidate, period) when s <= start and stop <= e,
    do: [period]

  defp met_at(_candidate_extent, _extent, _candidate, _period), do: []

  defp coarsest(parts), do: parts |> Enum.map(&elem(&1, 0)) |> Enum.min_by(&unit_index/1)
  defp unit_index(unit), do: Unit.rank(Unit.grain(unit)) || 99

  # The unit a part counts its candidates in: days of the month in their
  # month, days of the week in their month, months and weeks in their year,
  # the clock in its day. The weeks of a month, asked of that month, are the
  # weeks the calendar numbers in it.
  defp container_of(unit) when unit in [:month, :traditional_month, :week, :day_of_year],
    do: :year

  defp container_of(unit) when unit in [:day, :day_of_week], do: :month
  defp container_of(:minute), do: :hour
  defp container_of(:second), do: :minute
  defp container_of(_clock), do: :day

  # The weeks asked of one whole month are that month's.
  defp counted_in(:week, period, extent) do
    case containers(period, :month, extent) do
      [month] -> if Spans.extent(month) == {:ok, extent}, do: :month, else: :year
      _several -> :year
    end
  end

  defp counted_in(unit, _period, _extent), do: container_of(unit)

  # The containers a period runs through: the one its start is in, and each
  # next until the period's end. Containers tile the line, so the one that
  # ends at or after the period's end is the last, and no next is looked
  # for; a next whose extent was found in finding it is not placed again.
  defp containers(%Tempo{} = period, unit, {start, stop}) do
    frame = frame(period)

    {container_at(period, start, unit, frame), nil}
    |> Stream.unfold(fn
      nil ->
        nil

      {container, placed} ->
        case placed || Spans.extent(container) do
          {:ok, {container_start, container_stop} = extent} when container_start < stop ->
            {container,
             if(container_stop < stop, do: next(container, extent, unit, period, frame))}

          _ ->
            nil
        end
    end)
    |> Enum.to_list()
  end

  defp container_at(period, position, unit, frame) do
    container = %{period | form: {:value, Shift.period_units(position, unit, frame)}}
    at_showing(container, position, unit, frame)
  end

  # A unit of the clock is followed by the one the clock shows as it ends,
  # which across a change of the clock is not an hour on by the clock; any
  # other by the next of its unit. Each is given with its extent where
  # finding it placed it, else nil.
  defp next(_container, {container_start, container_stop}, unit, period, frame)
       when unit in [:hour, :minute] do
    following = container_at(period, container_stop, unit, frame)

    case Spans.extent(following) do
      {:ok, {next_start, _}} = placed when next_start > container_start -> {following, placed}
      _ -> nil
    end
  end

  defp next(container, _extent, unit, _period, _frame) do
    case next_of_unit(container, unit) do
      nil -> nil
      following -> {following, nil}
    end
  end

  defp next_of_unit(container, unit) do
    case Shift.shift(container, Shift.one(unit)) do
      {:ok, moved} -> moved
      {:error, _} -> nil
    end
  end

  # A container of the clock that begins at the second showing of its
  # reading carries the shift the clock has then, and is expanded there.
  defp at_showing(container, start, unit, %{zone: zone, shift: nil})
       when unit in [:hour, :minute],
       do: Zone.at_showing(container, zone, start)

  defp at_showing(container, _start, _unit, _frame), do: container

  # A container's units with the parts beneath: every concrete value they allow.
  defp expanded(period, scope, parts),
    do: period |> placed_values(scope, parts) |> Enum.map(&elem(&1, 0))

  # Each with the extent its expansion gave it, where it gave one and the
  # value is still on the frame it was found on: a value given another
  # shift (a second showing, a reading on a zone of fixed offset) is
  # placed again where it is asked.
  defp placed_values(period, %Tempo{form: {:value, container}} = scope, parts) do
    frame = scope_frame(period, scope)

    case Expand.placed(container ++ parts, frame) do
      {:ok, placed} ->
        placed
        |> Enum.take(Limit.values())
        |> Enum.map(fn {units, extent} ->
          on_frame(in_scope(as_value(period, units), scope), extent, frame)
        end)
        |> showings()

      {:error, _} ->
        []
    end
  end

  defp on_frame(%Tempo{shift: shift} = value, extent, %{shift: shift}), do: {value, extent}
  defp on_frame(value, _extent, _frame), do: {value, nil}

  # A reading a zone's clock shows twice is selected in a period once, at its
  # first showing there, as a value written to that reading is read (decision
  # 36, and RFC 5545 section 3.3.5): the second showing is kept where the
  # period holds it and not the first, an hour of an hourly rule.
  defp first_showings(values), do: Enum.uniq_by(values, & &1.form)

  # A reading a zone's clock shows twice is expanded twice, in the order the
  # clock shows it; the second is the second showing, and carries the shift
  # the clock has then, where the two would otherwise be one value.
  defp showings(placed) do
    {shown, _seen} =
      Enum.map_reduce(placed, MapSet.new(), fn {value, extent}, seen ->
        if MapSet.member?(seen, value),
          do: {{second_showing(value), nil}, seen},
          else: {{value, extent}, MapSet.put(seen, value)}
      end)

    shown
  end

  defp second_showing(%Tempo{zone: %Zone{} = zone, shift: nil} = value) do
    case Spans.extent(%{value | zone: nil}) do
      {:ok, {wall, _}} when is_integer(wall) ->
        shifted_to(value, Zone.second_showing_of(zone, wall))

      _no_reading ->
        value
    end
  end

  defp second_showing(value), do: value

  defp shifted_to(value, nil), do: value
  defp shifted_to(value, shift), do: %{value | shift: shift}

  # A value found in a container at the second showing of its reading is in
  # that showing.
  defp in_scope(value, %Tempo{shift: shift}) when is_list(shift), do: %{value | shift: shift}
  defp in_scope(value, _scope), do: value

  defp scope_frame(period, %Tempo{shift: shift}) when is_list(shift),
    do: %{frame(period) | shift: shift}

  defp scope_frame(period, _scope), do: frame(period)

  # A value in the period's frame: a span's ends carry the shift, a value
  # itself; in a named zone the shift is the zone's at the value.
  defp as_value(%Tempo{} = period, units) do
    %{shift: shift, zone: zone} = frame(period)
    value = %{period | form: {:value, units}, qualifications: nil, shift: shift}
    if zone != nil and shift != nil, do: rezoned(value, zone), else: value
  end

  # The frame a period is selected in. In a named zone that is the zone's
  # clock: a shift written on the period's start says only which showing it
  # begins at, and each value is read on the clock, a second showing given
  # its own shift (`showings/1`).
  defp frame(period) do
    case Spans.frame_of(period) do
      %{zone: %Zone{name: name}} = frame when is_binary(name) -> %{frame | shift: nil}
      frame -> frame
    end
  end

  defp rezoned(value, zone) do
    case Spans.extent(%{value | shift: nil}) do
      {:ok, {start, _}} when is_integer(start) ->
        %{value | shift: Zone.shift_of(Zone.offset_at_utc(zone, start))}

      _ ->
        value
    end
  end

  defp within?(%Placed{start: s, stop: e}, {start, stop}),
    do: is_integer(s) and is_integer(e) and s >= start and e <= stop

  defp within?(%Tempo{} = value, {start, stop}) do
    case Spans.extent(value) do
      {:ok, {s, e}} when is_integer(s) and is_integer(e) -> s >= start and e <= stop
      _ -> false
    end
  end

  # A span placed in a period is selected when it begins there: `T22/T02` runs out of its day.
  defp starts_within?(%Tempo{} = span, {start, stop}) do
    case Spans.extent(span) do
      {:ok, {s, _}} when is_integer(s) -> s >= start and s < stop
      _ -> false
    end
  end

  defp in_years?(_value, nil), do: true

  defp in_years?(%Tempo{form: {form, units}}, years) when form in [:value, :span] do
    year = if form == :value, do: Keyword.get(units, :year), else: nil

    is_integer(year) and
      year in List.flatten(Enum.map(List.wrap(years), &Enum.to_list(List.wrap(&1))))
  end

  # ── Positions ─────────────────────────────────────────────────────────

  @doc "The candidates at the positions named, counting from the end when negative; all with none."
  @spec positions([term()], integer() | [integer() | Range.t()] | nil) :: [term()]
  def positions(candidates, instances), do: positioned(candidates, instances)

  # The nth of the candidates, counting from the end when negative.
  defp positioned(candidates, nil), do: candidates

  defp positioned(candidates, instances) do
    count = length(candidates)

    instances
    |> List.wrap()
    |> Enum.flat_map(&indices(&1, count))
    |> Enum.filter(&(&1 >= 0 and &1 < count))
    |> Enum.sort()
    |> Enum.uniq()
    |> Enum.map(&Enum.at(candidates, &1))
  end

  # The indices a position names among `count` candidates. Each end of a
  # range is counted first, from the end where it is negative, so that
  # `{2..-1}` is the second to the last, as a range of a unit's values is.
  defp indices(%Range{first: first, last: last, step: step}, count) do
    Enum.to_list(index(first, count)..index(last, count)//abs(step))
  end

  defp indices(n, count) do
    [index(n, count)]
  end

  defp index(n, _count) when n > 0 do
    n - 1
  end

  defp index(n, count) do
    count + n
  end

  # ── Events ────────────────────────────────────────────────────────────

  defp years_through(%Tempo{calendar: calendar} = period, {start, stop}) do
    frame = frame(period)
    first = Keyword.fetch!(Shift.period_units(start, :year, frame), :year)
    last = Keyword.fetch!(Shift.period_units(stop - 1, :year, frame), :year)
    _ = calendar
    Enum.to_list(first..last)
  end

  defp event_date(name, zone, year, %Tempo{calendar: calendar} = period) do
    case Event.date(event_name(name, zone), year, calendar) do
      {:ok, %Date{} = date} ->
        [
          %{
            period
            | form: {:value, [year: date.year, month: date.month, day: date.day]},
              qualifications: nil
          }
        ]

      {:error, _} ->
        []
    end
  end

  defp event_name(name, nil), do: name
  defp event_name(name, zone), do: "#{name}@#{zone}"

  # Parts written beside an event (a time of day) apply to its date.
  defp with_parts(%Tempo{form: {:value, units}} = value, [], _period),
    do: [%{value | form: {:value, units}}]

  defp with_parts(%Tempo{form: {:value, units}} = value, parts, period) do
    case Expand.expand(units ++ parts, frame(period)) do
      {:ok, values} -> Enum.map(values, &%{value | form: {:value, &1}})
      {:error, _} -> []
    end
  end

  # ── Selectors ─────────────────────────────────────────────────────────

  @doc """
  The values a selector picks in each span of a base expression, in order:
  a value with no year names its parts, a span with no year is placed in
  each period it fits, a recurrence gives its occurrences within, a
  `Tempo.Workdays` its weekdays less its days off, a list of integers the
  days of the month, a list of selectors each of them, and a function is
  given each period and answers with a selector for it.
  """
  @spec select(Tempo.t(), term(), keyword()) :: {:ok, [Tempo.t()]} | {:error, Exception.t()}
  def select(base, selector, options \\ [])

  # A base with no end is selected as it is walked: each period the selector
  # counts in is taken in turn, and the answer is a stream.
  def select(%Tempo{form: {:span, %Tempo{} = from, :open}} = base, selector, options) do
    with {:ok, frame} <- line_of(base),
         {:ok, {start, _}} <- Spans.extent(from) do
      unit = selector_unit(selector)

      first = %{
        from
        | form: {:value, Shift.period_units(start, unit, frame)},
          qualifications: nil
      }

      ends = ends_at(selector)

      picked =
        first
        |> Stream.iterate(&next_of_unit(&1, unit))
        |> Stream.take_while(&(&1 != nil and before_end?(&1, ends)))
        |> Stream.flat_map(&picked_in(selector, %{&1 | metadata: base.metadata}, options))
        |> Stream.filter(&(Spans.start_position(&1) >= start))

      {:ok, picked}
    end
  end

  def select(%Tempo{} = base, selector, options) do
    with {:ok, periods} <- Spans.placed(base, Keyword.take(options, [:within])),
         {:ok, periods} <- bounded_periods(periods, base) do
      each_picked(periods, &apply_selector(selector, &1, options))
    end
  end

  # A base with no end is on a line: one with no year has no periods to take
  # in turn, as a base with an end and no year has none.
  defp line_of(base) do
    case Spans.frame(base) do
      {:cycle, _} -> {:error, ConversionError.exception(value: base, reason: :needs_a_year)}
      _line -> {:ok, Spans.frame_of(base)}
    end
  end

  # A period of a base with no end is selected in as it is come to: what
  # the selector cannot answer there is raised, as the stream has no other
  # way to say so, and is never passed over to look in the next for ever.
  defp picked_in(selector, period, options) do
    case apply_selector(selector, period, options) do
      {:ok, picked} -> picked
      {:error, exception} -> raise exception
    end
  end

  # Where a selector picks nothing more, for ever: workdays from days off
  # with no end. Nil for one that may pick in any period.
  defp ends_at(%Workdays{} = workdays), do: Workdays.off_from(workdays)
  defp ends_at(_selector), do: nil

  defp before_end?(_period, nil), do: true
  defp before_end?(period, ends), do: Spans.start_position(period) < ends

  # The period an endless base is taken in, one at a time: the unit the selector counts in.
  defp selector_unit(%Tempo{form: {:value, units}}) do
    case Enum.filter(selector_parts(units), fn {unit, _} -> unit in @part_units end) do
      [] -> :month
      parts -> container_of(coarsest(parts))
    end
  end

  defp selector_unit({:ok, selector}), do: selector_unit(selector)
  defp selector_unit(_selector), do: :month

  defp each_picked(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, picked} -> {:cont, {:ok, acc ++ picked}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp bounded_periods(periods, base), do: Limit.take(periods, base)

  defp apply_selector(%Tempo{form: {:value, units}} = selector, period, options) do
    if Unit.anchored?(units) do
      {:error, not_a_selector(selector)}
    else
      parts = weekdays_in(Unit.cyclic(units), selector.calendar, calendar_of(period))
      in_period(period, parts, options)
    end
  end

  # Any other selector takes the period as written.
  defp apply_selector(selector, %Placed{span: period}, options),
    do: apply_selector(selector, period, options)

  defp apply_selector(
         %Tempo{form: {:span, %Tempo{form: {:value, units}}, _}} = selector,
         period,
         _options
       ) do
    if Unit.anchored?(units) do
      {:error, not_a_selector(selector)}
    else
      with {:ok, extent} <- bounded_extent(period) do
        unit = units |> Unit.cyclic() |> coarsest() |> container_of()

        selector = span_in(selector, period.calendar)

        placed =
          period
          |> containers(unit, extent)
          |> Enum.map(&Spans.placed_in(selector, &1))
          |> Enum.filter(&starts_within?(&1, extent))

        {:ok, Enum.map(placed, &%{&1 | metadata: period.metadata})}
      end
    end
  end

  defp apply_selector(%Tempo{form: {:span, _, _}} = selector, _period, _options),
    do: {:error, not_a_selector(selector)}

  defp apply_selector(%Tempo{form: {kind, _, _, _}} = recurrence, period, options)
       when kind == :every,
       do: occurrences_in(recurrence, period, options)

  # A rule read in another calendar, or a member with conditions, gives its
  # occurrences in each period as a recurrence does.
  defp apply_selector(%Tempo{form: {:when, _, _}} = member, period, options),
    do: occurrences_in(member, period, options)

  defp apply_selector(%Tempo{form: {kind, members}}, period, options) when kind in [:all, :one],
    do: apply_selector(members, period, options)

  # CLDR numbers a territory's weekdays from Monday; the period's calendar
  # numbers its days of the week from the day its weeks begin on.
  defp apply_selector(%Tempo.Workdays{weekdays: weekdays, except: except}, period, options) do
    numbered = Enum.map(weekdays, &Tempo.Calendar.day_of_week_from_iso(period.calendar, &1))

    with {:ok, days} <- in_period(period, [day_of_week: numbered], options),
         {:ok, off} <- days_off(except, period, options) do
      {:ok, Enum.reject(days, &overlaps_any?(&1, off))}
    end
  end

  # A list answers as a set does, in the order of time and each span once,
  # whatever order its members are written in and however often one is named.
  defp apply_selector(selector, period, options) when is_list(selector) do
    picked =
      if selector != [] and Enum.all?(selector, &(is_integer(&1) or is_struct(&1, Range))),
        do: in_period(period, [day: selector], options),
        else: each_picked(selector, &apply_selector(&1, period, options))

    with {:ok, picked} <- picked do
      {:ok, picked |> Enum.uniq_by(&Spans.extent/1) |> Enum.sort_by(&Spans.start_position/1)}
    end
  end

  defp apply_selector(%Range{} = range, period, options),
    do: in_period(period, [day: [range]], options)

  defp apply_selector(fun, period, options) when is_function(fun, 1) do
    case fun.(period) do
      {:error, _} = error -> error
      selector -> apply_selector(selector, period, options)
    end
  end

  defp apply_selector(selector, _period, _options), do: {:error, not_a_selector(selector)}

  defp occurrences_in(recurrence, period, options) do
    with {:ok, spans} <- Spans.placed(recurrence, Keyword.put(options, :within, period)),
         {:ok, spans} <- Limit.take(spans, recurrence),
         {:ok, extent} <- bounded_extent(period) do
      {:ok, spans |> Enum.filter(&within?(&1, extent)) |> Placed.written()}
    end
  end

  # A value's units as a selection's parts, a selection written in them
  # flattened into the units around it: what the selector counts in. It is
  # selected with the selection kept, so the units before it name each value
  # it selects in (`4ML1K1IN`, the first Monday of each April).
  defp selector_parts(units) do
    units
    |> Unit.cyclic()
    |> Enum.flat_map(fn
      {:selection, parts} -> parts
      part -> [part]
    end)
  end

  # ── A selector of another calendar ────────────────────────────────────

  @doc """
  Parts with each day of the week they name, in a selection nested in them
  too, numbered as another calendar numbers it (decision 80): the same day
  of the week, counted from the day the other calendar's weeks begin on.
  `Tempo.weekends(:US)`, Saturday and Sunday counted from Monday, selects
  the same two days where weeks begin on Sunday. A day counted from the end
  is a last day of the first calendar's week.
  """
  @spec weekdays_in(parts(), module(), module()) :: parts()
  def weekdays_in(parts, calendar, calendar) do
    parts
  end

  def weekdays_in(parts, from, to) do
    Enum.map(parts, &weekday_part_in(&1, from, to))
  end

  defp weekday_part_in({:day_of_week, held}, from, to) do
    {:day_of_week, weekdays_held_in(held, from, to)}
  end

  defp weekday_part_in({:selection, parts}, from, to) do
    {:selection, weekdays_in(parts, from, to)}
  end

  defp weekday_part_in({:all, selections}, from, to) when is_list(selections) do
    {:all, Enum.map(selections, &weekdays_in(&1, from, to))}
  end

  defp weekday_part_in(part, _from, _to) do
    part
  end

  defp weekdays_held_in(day, from, to) when is_integer(day) do
    weekday_in(day, from, to)
  end

  defp weekdays_held_in(held, from, to) when is_list(held) do
    Enum.flat_map(held, &weekdays_member_in(&1, from, to))
  end

  defp weekdays_held_in(held, _from, _to) do
    held
  end

  # A range stays a range where its days are still in order in the other
  # calendar's numbering (`1..5`, Monday to Friday, is `2..6` where weeks
  # begin on Sunday), and is its days where they come round (`5..7`, Friday
  # to Sunday, is `6, 7, 1`).
  defp weekdays_member_in(%Range{first: first, last: last, step: step}, from, to) do
    days = Tempo.Calendar.days_in_week(from)
    from_first = own_weekday(first, days)
    from_last = own_weekday(last, days)
    numbered = Enum.map(from_first..from_last//abs(step), &weekday_in(&1, from, to))
    to_first = weekday_in(from_first, from, to)
    to_last = weekday_in(from_last, from, to)

    if numbered == Enum.to_list(to_first..to_last//abs(step)) do
      [to_first..to_last//abs(step)]
    else
      numbered
    end
  end

  defp weekdays_member_in(day, from, to) do
    [weekday_in(day, from, to)]
  end

  defp weekday_in(day, from, to) do
    own = own_weekday(day, Tempo.Calendar.days_in_week(from))
    iso_weekday = Tempo.Calendar.iso_weekday_from_day_of_week(from, own)
    Tempo.Calendar.day_of_week_from_iso(to, iso_weekday)
  end

  defp own_weekday(day, days) when day < 0 do
    days + day + 1
  end

  defp own_weekday(day, _days) do
    day
  end

  # A span selector's two ends, their days of the week numbered in the
  # period's calendar.
  defp span_in(%Tempo{calendar: calendar} = selector, calendar) do
    selector
  end

  defp span_in(%Tempo{form: {:span, from, to}, calendar: own} = selector, calendar) do
    %{
      selector
      | form: {:span, end_in(from, own, calendar), end_in(to, own, calendar)},
        calendar: calendar
    }
  end

  defp end_in(%Tempo{form: {:value, units}} = value, own, calendar) do
    %{value | form: {:value, weekdays_in(units, own, calendar)}, calendar: calendar}
  end

  defp end_in(other, _own, _calendar) do
    other
  end

  defp calendar_of(%Placed{span: %Tempo{calendar: calendar}}) do
    calendar
  end

  defp calendar_of(%Tempo{calendar: calendar}) do
    calendar
  end

  defp days_off(nil, _period, _options), do: {:ok, []}

  defp days_off(except, period, options) do
    with {:ok, spans} <- Spans.placed(except, Keyword.put(options, :within, period)),
         {:ok, spans} <- Limit.take(spans, except),
         do: {:ok, Enum.map(spans, &{:ok, Placed.extent(&1)})}
  end

  defp overlaps_any?(value, off) do
    case Spans.extent(value) do
      {:ok, {start, stop}} ->
        Enum.any?(off, fn
          {:ok, {s, e}} when is_integer(s) and is_integer(e) -> s < stop and start < e
          _ -> false
        end)

      _ ->
        false
    end
  end

  defp not_a_selector(selector) do
    ArgumentError.exception(
      "Tempo.select/3 does not recognise selector #{inspect(selector)}: a selector is a value " <>
        "with no year, a span or recurrence, a Tempo.Workdays, a list of days or of selectors, " <>
        "or a function of the period"
    )
  end

  # ── Extents ───────────────────────────────────────────────────────────

  defp bounded_extent(%Tempo{} = period) do
    case Spans.extent(period) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> {:ok, {start, stop}}
      {:ok, _open} -> {:error, ConversionError.exception(value: period, reason: :open)}
      {:error, _} = error -> error
    end
  end
end
