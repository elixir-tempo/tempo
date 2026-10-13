defmodule Tempo.Shift do
  @moduledoc false
  # One arithmetic: an expression moved by a duration, and the rounding,
  # truncation and extension of a value to a unit.
  #
  # A value is shifted at its own resolution, extended to the duration's
  # finest unit where that is finer: a year a day on is its second day. The
  # move is one of the position of the value's start (`Tempo.Spans.shifted/4`:
  # the calendar part through the calendar's `shift_date`, the clock part in
  # ticks through the zone), and the value is written back at the moved
  # position on its own axis: a week date stays a week date, a time of day a
  # time of day. A value with no year is shifted in each of a run of years
  # and is the one answer they agree on, or an error when they disagree.
  # A value that names several (a set in a unit, a mask) is each value it
  # names shifted, gathered back into one value where one can hold them.

  alias Tempo.{
    Algebra,
    Calendar,
    ConversionError,
    Duration,
    Expand,
    Limit,
    Scale,
    Spans,
    Unit,
    Walk,
    Zone
  }

  @day 86_400_000_000
  @sample_years 33

  @type expression :: Tempo.t()

  # ── Shifting ──────────────────────────────────────────────────────────

  @doc "An expression moved by a duration: a value, a span end by end, a set member by member."
  @spec shift(expression(), Duration.t()) :: {:ok, expression()} | {:error, Exception.t()}
  def shift(%Tempo{form: {:value, units}} = value, %Duration{} = by) do
    cond do
      Keyword.has_key?(units, :selection) ->
        {:error, conversion(value, :selection)}

      Keyword.has_key?(units, :group) ->
        {:error, conversion(value, :group)}

      Unit.anchored?(units) and Unit.concrete?(units) and Expand.one_span?(units) ->
        shift_one(value, by)

      Unit.anchored?(units) ->
        shift_each(value, by)

      true ->
        shift_unanchored(value, by)
    end
  end

  def shift(%Tempo{form: {:span, from, to}} = span, %Duration{} = by) do
    case shift_span(span, from, to, by) do
      {:ok, %Tempo{form: {:span, %Tempo{form: {kind, _}}, _}}} when kind != :value ->
        shift_spans(span, by)

      {:ok, %Tempo{form: {:span, _, %Tempo{form: {kind, _}}}}} when kind != :value ->
        shift_spans(span, by)

      result ->
        result
    end
  end

  def shift(%Tempo{form: {:every, first, bound, rule}} = recurrence, %Duration{} = by) do
    with {:ok, first} <- shift(first, by),
         {:ok, bound} <- shift_bound(bound, by) do
      {:ok, %{recurrence | form: {:every, first, bound, rule}}}
    end
  end

  def shift(%Tempo{form: {kind, members}} = set, %Duration{} = by) when kind in [:all, :one] do
    with {:ok, shifted} <- each(members, &shift(&1, by)),
         do: {:ok, %{set | form: {kind, shifted}}}
  end

  def shift(%Tempo{} = expression, %Duration{}),
    do: {:error, conversion(expression, :conditions)}

  def shift(%Duration{} = duration, _by), do: {:error, conversion(duration, :bare_duration)}

  defp shift_bound(%Tempo{} = until, by), do: shift(until, by)
  defp shift_bound(count_or_infinity, _by), do: {:ok, count_or_infinity}

  # A span whose ends shift to no one value is each span it names shifted.
  defp shift_spans(span, by) do
    with {:ok, spans} <- Spans.spans(span), do: shift_members(span, Enum.to_list(spans), by)
  end

  # ── One value with a year ─────────────────────────────────────────────

  # The value extended to the duration's finest unit, its start moved, and
  # the result written back on the value's own axis at that resolution.
  defp shift_one(%Tempo{form: {:value, units}} = value, %Duration{units: by_units} = by) do
    case {Keyword.has_key?(units, :week), Keyword.pop(by_units, :year)} do
      {true, {years, rest}} when is_integer(years) ->
        with {:ok, value} <- week_years_on(value, years),
             do: shift_rest(value, %Duration{units: rest})

      _ ->
        shift_at(value, by)
    end
  end

  defp shift_rest(value, %Duration{units: []}), do: {:ok, value}
  defp shift_rest(value, by), do: shift_one(value, by)

  # A week date a year on keeps its week and weekday, the week clamped to the year's last.
  defp week_years_on(%Tempo{form: {:value, units}, calendar: calendar} = value, years) do
    [year: year, week: week] = Keyword.take(plain(units), [:year, :week])
    moved_year = year + years

    case Calendar.weeks_in_year(calendar, moved_year) do
      weeks when is_integer(weeks) ->
        moved = [year: moved_year, week: min(week, weeks)] ++ Keyword.drop(units, [:year, :week])
        {:ok, %{value | form: {:value, annotated(moved, units)}}}

      {:error, reason} ->
        {:error, conversion(value, reason)}
    end
  end

  defp shift_at(%Tempo{form: {:value, units}} = value, by) do
    frame = Spans.frame_of(value)
    extended = extended(units, by, value.calendar)

    with {:ok, {start, _stop}} <- extent(plain(extended), frame, value),
         {:ok, moved} <- Spans.shifted(start, by, frame, value) do
      {:ok, rezoned(%{value | form: {:value, rewritten(moved, extended, frame)}}, value, moved)}
    end
  end

  # Annotated units as their stated values: `2018±2Y` is shifted as 2018.
  defp plain(units) do
    Enum.map(units, fn
      {unit, {n, _annotation}} when is_integer(n) -> {unit, n}
      other -> other
    end)
  end

  defp extent(units, frame, value) do
    case Expand.extent(units, frame) do
      {:ok, extent} -> {:ok, extent}
      {:error, reason} -> {:error, conversion(value, reason)}
    end
  end

  # A duration's finest unit, as the unit of a value: a week on a date is a day's step.
  defp extended(units, %Duration{units: by}, calendar) do
    case by |> List.last() |> elem(0) do
      :week ->
        if Keyword.has_key?(units, :week), do: units, else: extended_to(units, :day, calendar)

      finest ->
        extended_to(units, finest, calendar)
    end
  end

  # Units extended to a finer unit with first values: a year to its first day.
  # A week date reaches a day as its first weekday, which is the day's unit; a
  # century or a decade is first written as its first year.
  @doc false
  @spec extended_to(Unit.units(), Unit.t(), module()) :: Unit.units()
  def extended_to(units, unit, calendar) do
    if Unit.compare(unit, Unit.grain(Unit.resolution(units))) == :gt do
      units |> as_years(calendar) |> filled_down_to(unit)
    else
      units
    end
  end

  # A century or a decade written as its first year is already at the year.
  defp filled_down_to(units, unit) do
    if written_to?(units, unit), do: units, else: with_first(Expand.filled_to(units, unit), unit)
  end

  defp with_first(filled, unit) do
    if written_to?(filled, unit), do: filled, else: filled ++ [{unit, Unit.minimum(unit)}]
  end

  defp written_to?(units, unit), do: units |> List.last() |> elem(0) |> Unit.grain() == unit

  defp as_years([{unit, _} | _] = units, calendar) when unit in [:century, :decade] do
    case Expand.day_span(calendar, plain(units)) do
      {:ok, {first, _}} -> Walk.at_day(first, :year, calendar)
      {:error, _} -> units
    end
  end

  defp as_years(units, _calendar), do: units

  # The units at a position, on the axis and at the resolution of a model's
  # units, with the model's annotations carried onto the same units.
  @doc false
  @spec rewritten(Scale.position(), Unit.units(), Spans.frame()) :: Unit.units()
  def rewritten(position, model, frame) do
    wall = Walk.wall(position, frame)
    day = Integer.floor_div(wall, @day)
    clock = Integer.mod(wall, @day)
    date = date_units(day, Unit.date_units(model), frame.calendar)
    clock = clock_units(clock, Unit.clock_units(model))
    annotated(date ++ clock, model)
  end

  defp date_units(_day, [], _calendar), do: []

  defp date_units(day, model, calendar) do
    {y, m, d} = Calendar.date(calendar, day)

    cond do
      Keyword.has_key?(model, :week) ->
        {:ok, {week_year, week}} = Calendar.week_of_year(calendar, y, m, d)

        weekday =
          if Keyword.has_key?(model, :day_of_week),
            do: [day_of_week: Calendar.day_of_week(calendar, y, m, d)],
            else: []

        [year: week_year, week: week] ++ weekday

      Keyword.has_key?(model, :day_of_year) ->
        {:ok, day_of_year} = Calendar.day_of_year(calendar, y, m, d)
        [year: y, day_of_year: day_of_year]

      true ->
        Walk.at_day(day, day_unit(Unit.resolution(model)), calendar)
    end
  end

  defp day_unit(unit) when unit in [:day, :day_of_week, :day_of_year], do: :day
  defp day_unit(unit) when unit in [:month, :traditional_month, :season], do: :month
  defp day_unit(unit) when unit in [:year, :decade, :century, :week, :quarter], do: unit
  defp day_unit(_unit), do: :day

  defp clock_units(_ticks, []), do: []

  defp clock_units(ticks, model) do
    case List.last(model) do
      {:microsecond, {_, precision}} -> Scale.clock_at(ticks, {:microsecond, precision})
      {unit, _} -> Scale.clock_at(ticks, unit)
    end
  end

  defp annotated(units, model) do
    Enum.map(units, fn {unit, value} ->
      case Keyword.get(model, unit) do
        {n, annotation} when is_integer(n) and (is_list(annotation) or annotation == :leap) ->
          {unit, {value, annotation}}

        _plain ->
          {unit, value}
      end
    end)
  end

  # ── A value with no year ──────────────────────────────────────────────

  # Placed in each of a run of years and shifted there; the answer the years
  # agree on, with the placed units stripped, or an error where they differ.
  defp shift_unanchored(%Tempo{form: {:value, units}} = value, by) do
    cyclic = Unit.cyclic(units)
    coarsest = if cyclic == [], do: :year, else: Unit.coarsest(cyclic)

    answers =
      value.calendar
      |> sample_years()
      |> Enum.map(fn year ->
        prefix =
          if cyclic == [],
            do: [year: year],
            else: Expand.filled_to(placing(year, coarsest), coarsest)

        placed_units = prefix ++ cyclic
        placed = %{value | form: {:value, placed_units}}
        added = Keyword.keys(placed_units) -- Keyword.keys(cyclic)

        with {:ok, shifted} <- shift(placed, by), do: {:ok, stripped(shifted, added)}
      end)
      |> Enum.uniq()

    any_year = Enum.filter(units, &match?({:year, :any}, &1))

    case answers do
      [{:ok, agreed}] -> {:ok, prefixed(agreed, any_year)}
      [{:error, _} = error] -> error
      _several -> {:error, conversion(value, :needs_a_year)}
    end
  end

  # The units a placement added, taken off every value of a result.
  defp stripped(%Tempo{form: {:value, units}} = value, added),
    do: %{value | form: {:value, Enum.reject(units, fn {unit, _} -> unit in added end)}}

  defp stripped(%Tempo{form: {kind, members}} = set, added) when kind in [:all, :one],
    do: %{set | form: {kind, Enum.map(members, &stripped(&1, added))}}

  defp prefixed(%Tempo{form: {:value, units}} = value, prefix),
    do: %{value | form: {:value, prefix ++ units}}

  defp prefixed(%Tempo{form: {kind, members}} = set, prefix) when kind in [:all, :one],
    do: %{set | form: {kind, Enum.map(members, &prefixed(&1, prefix))}}

  # A year and, for a day of the week alone, a week to hang it on.
  defp placing(year, :day_of_week), do: [year: year, week: 1]
  defp placing(year, _coarsest), do: [year: year]

  defp sample_years(calendar) do
    {year, _, _} = Calendar.date(calendar, Calendar.iso_days(Elixir.Calendar.ISO, 2000, 1, 1))
    half = div(@sample_years, 2)
    Enum.to_list((year - half)..(year + half))
  end

  # ── Several values ────────────────────────────────────────────────────

  # Each value a plural value names shifted, gathered into one value where its
  # units can hold them all: the held units kept where the shift passes them
  # by, one unit of a list where only one differs, else a set of the values.
  defp shift_each(%Tempo{form: {:value, units}} = value, by) do
    with {:ok, members} <- Spans.members(%{value | form: {:value, plain(units)}}),
         members = Enum.map(members, &plain_member/1),
         {:ok, shifted} <- each(members, &shift(&1, by)) do
      {:ok, gathered(value, units, members, Enum.map(shifted, &reannotated(&1, units)))}
    end
  end

  defp plain_member(%Tempo{form: {:value, units}} = member),
    do: %{member | form: {:value, plain(units)}}

  defp reannotated(%Tempo{form: {:value, shifted}} = member, model),
    do: %{member | form: {:value, annotated(shifted, model)}}

  defp gathered(value, units, members, shifted) do
    plural = for {unit, held} <- units, not Unit.singular?(held), do: unit

    cond do
      Enum.sort(shifted) == Enum.sort(members) ->
        value

      passed_by?(plural, members, shifted) ->
        [%Tempo{form: {:value, first}} | _] = shifted
        %{value | form: {:value, Enum.map(first, &kept(&1, units, plural))}}

      as_written?(value, units, shifted) ->
        %{value | form: {:value, as_written(units, shifted)}}

      mask?(units) ->
        one_of(value, one_unit_differs(value, Enum.uniq(shifted)))

      true ->
        one_unit_differs(value, Enum.uniq(shifted))
    end
  end

  # The units a value was written with, holding what the first shifted value
  # holds: a time on each day of June moved a month is that time on each day
  # of July, where July's days are the shifted values and no others.
  defp as_written(units, [%Tempo{form: {:value, first}} | _]),
    do: Enum.map(units, fn {unit, held} -> {unit, Keyword.get(first, unit, held)} end)

  defp as_written?(value, units, shifted) do
    candidate = %{value | form: {:value, as_written(plain(units), shifted)}}

    case Spans.members(candidate) do
      {:ok, members} -> Enum.map(members, &plain_member/1) == Enum.map(shifted, &plain_member/1)
      {:error, _} -> false
    end
  end

  # A mask names one of its values, so its values shifted are one of them too.
  defp one_of(value, %Tempo{form: {:all, members}}), do: %{value | form: {:one, members}}
  defp one_of(value, %Tempo{form: {:value, _}} = one), do: %{value | form: {:one, [one]}}

  # The shift left every plural unit as it was, and the rest the same in all.
  defp passed_by?(plural, members, shifted) do
    Enum.zip(members, shifted)
    |> Enum.all?(fn {%Tempo{form: {:value, m}}, %Tempo{form: {:value, s}}} ->
      Enum.all?(plural, &(Keyword.get(m, &1) == Keyword.get(s, &1)))
    end) and
      shifted
      |> Enum.map(fn %Tempo{form: {:value, s}} -> Keyword.drop(s, plural) end)
      |> Enum.uniq()
      |> length() == 1
  end

  defp kept({unit, value}, units, plural),
    do: if(unit in plural, do: {unit, Keyword.fetch!(units, unit)}, else: {unit, value})

  defp mask?(units), do: Enum.any?(units, &(match?({_, {:mask, _}}, &1) or match?({_, :any}, &1)))

  defp one_unit_differs(_value, [one]), do: one

  # The values as one value where they are every combination of the values
  # each unit takes, each varying unit written as its list; else a set.
  defp one_unit_differs(%Tempo{form: {:value, original}} = value, shifted) do
    keys = shifted |> Enum.map(fn %Tempo{form: {:value, s}} -> Keyword.keys(s) end) |> Enum.uniq()

    case keys do
      [keys] ->
        taken =
          Enum.map(keys, fn k ->
            {k, shifted |> Enum.map(&held(&1, k)) |> Enum.uniq() |> Enum.sort()}
          end)

        as_one_or_set(value, original, shifted, taken)

      _several_shapes ->
        %{value | form: {:all, shifted}}
    end
  end

  defp as_one_or_set(value, original, shifted, taken) do
    product = Enum.reduce(taken, 1, fn {_, v}, n -> n * length(v) end)

    if product == length(shifted) and every_combination?(taken, shifted) do
      %Tempo{form: {:value, first}} = hd(shifted)
      %{value | form: {:value, Enum.map(first, &varied(&1, taken, original))}}
    else
      %{value | form: {:all, shifted}}
    end
  end

  defp varied({unit, value}, taken, original) do
    case Keyword.fetch!(taken, unit) do
      [_one] -> {unit, value}
      values -> {unit, shaped(values, Keyword.get(original, unit))}
    end
  end

  defp every_combination?(taken, shifted) do
    combinations =
      Enum.reduce(taken, [[]], fn {unit, values}, acc ->
        for units <- acc, v <- values, do: units ++ [{unit, v}]
      end)

    Enum.sort(combinations) ==
      shifted |> Enum.map(fn %Tempo{form: {:value, s}} -> s end) |> Enum.sort()
  end

  defp held(%Tempo{form: {:value, units}}, unit), do: Keyword.get(units, unit)

  # A list of values keeps the shape the unit was written in: a list stays a list of values, else runs are ranges.
  defp shaped(values, original) when is_list(original) do
    if Enum.any?(original, &is_struct(&1, Range)), do: listed(values), else: values
  end

  defp shaped(values, _original), do: listed(values)

  # Consecutive whole numbers as a range, as the writer writes them.
  defp listed(values) do
    values
    |> Enum.chunk_while([], &run/2, &{:cont, Enum.reverse(&1), []})
    |> Enum.map(fn
      [one] -> one
      [first | _] = run when is_integer(first) -> first..List.last(run)
      run -> run
    end)
    |> List.flatten()
  end

  defp run(value, []), do: {:cont, [value]}

  defp run(value, [last | _] = acc)
       when is_integer(value) and is_integer(last) and value == last + 1,
       do: {:cont, [value | acc]}

  defp run(value, acc), do: {:cont, Enum.reverse(acc), [value]}

  defp shift_members(expression, members, by) do
    with {:ok, shifted} <- each(members, &shift(&1, by)),
         do: {:ok, %{expression | form: {:all, shifted}}}
  end

  defp each(members, fun) do
    Enum.reduce_while(members, {:ok, []}, fn member, {:ok, acc} ->
      case fun.(member) do
        {:ok, shifted} -> {:cont, {:ok, acc ++ [shifted]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # ── Spans ─────────────────────────────────────────────────────────────

  # Each written end moved; a duration end and an open end stay. With a month
  # or a year in the duration the span keeps its length, its end moved by it.
  defp shift_span(span, from, to, by) do
    with {:ok, from_moved} <- shift_end(from, by),
         {:ok, to_moved} <- shift_end(to, by),
         {:ok, to_moved} <- kept_length(span, from, to, from_moved, to_moved, by) do
      {:ok, %{span | form: {:span, from_moved, to_moved}}}
    end
  end

  defp shift_end(%Tempo{} = value, by), do: shift(value, by)
  defp shift_end(other, _by), do: {:ok, other}

  defp kept_length(span, %Tempo{} = from, %Tempo{} = to, from_moved, to_moved, by) do
    if Duration.exact?(by) or Unit.compare(finer_resolution(from, to), :day) == :lt do
      {:ok, to_moved}
    else
      frame = Spans.frame_of(span)

      with {:ok, {start, stop}} <- Spans.extent(span),
           {:ok, {moved_start, _}} <- Spans.extent(%{span | form: {:span, from_moved, to}}) do
        length = Walk.wall(stop, frame) - Walk.wall(start, frame)
        stop = utc_of_wall(Walk.wall(moved_start, frame) + length, frame)
        {:ok, rezoned(Spans.at_position(stop, to, :end, span.calendar, span.zone), to, stop)}
      end
    end
  end

  defp kept_length(_span, _from, _to, _from_moved, to_moved, _by), do: {:ok, to_moved}

  # ── Shifting through free time ────────────────────────────────────────

  @doc """
  A value moved by an exact duration of free time: the busy set's spans cost
  nothing to cross, and an origin inside one first moves to its edge. A date
  moved by days or weeks steps from free day to free day; a time moves tick
  by tick through the free gaps.
  """
  @spec skipping(expression(), Duration.t(), expression()) ::
          {:ok, expression()} | {:error, Exception.t()}
  # A busy set with no end is read only as far as the shift can reach.
  def skipping(
        %Tempo{form: {:value, units}} = value,
        %Duration{} = by,
        %Tempo{form: {:all, members}} = busy
      )
      when not is_list(members) do
    extended = extended(units, by, value.calendar)
    frame = Spans.frame_of(value)

    with {:ok, total} <- exact_ticks(by, value),
         :ok <- forward(total, busy),
         {:ok, {start, _}} <- extent(plain(units), frame, value),
         {:ok, spans} <- Spans.spans(busy) do
      busy_extents = reached(spans, start, total)
      landed = landed(start, total, busy_extents, extended, by, frame)
      {:ok, %{value | form: {:value, rewritten(landed, extended, frame)}}}
    end
  end

  def skipping(%Tempo{form: {:value, units}} = value, %Duration{} = by, %Tempo{} = busy) do
    extended = extended(units, by, value.calendar)

    with {:ok, total} <- exact_ticks(by, value),
         {:ok, frame, origin, positioned} <- Algebra.aligned(value, busy, []),
         {:ok, {start, _}} <- Algebra.single(origin, value, busy) do
      free_from = covered(positioned, frame)
      landed = landed(start, total, free_from, extended, by, Spans.frame_of(value))
      {:ok, %{value | form: {:value, rewritten(landed, extended, Spans.frame_of(value))}}}
    end
  end

  def skipping(%Tempo{} = expression, _by, _busy), do: {:error, conversion(expression, :several)}

  def skipping(%Duration{} = duration, _by, _busy),
    do: {:error, conversion(duration, :bare_duration)}

  defp forward(total, _busy) when total >= 0, do: :ok
  defp forward(_total, busy), do: {:error, conversion(busy, :unbounded)}

  # The busy spans a walk of free time can reach: each one met puts the landing further on.
  defp reached(spans, start, total) do
    spans
    |> Stream.map(&Spans.extent/1)
    |> Enum.reduce_while({[], 0}, fn
      {:ok, {s, e}}, {acc, busy} when is_integer(s) and is_integer(e) ->
        if s > start + total + busy,
          do: {:halt, {acc, busy}},
          else: {:cont, {[{s, e} | acc], busy + max(e - max(s, start), 0)}}

      _open_or_error, acc ->
        {:halt, acc}
    end)
    |> elem(0)
    |> Enum.sort()
  end

  defp exact_ticks(%Duration{} = by, value) do
    case Duration.to_microseconds(by) do
      {:ok, ticks} -> {:ok, ticks}
      {:error, _} -> {:error, conversion(value, {:inexact, inexact_unit(by)})}
    end
  end

  defp inexact_unit(%Duration{units: units}),
    do: units |> Enum.find(fn {unit, _} -> unit in [:year, :month] end) |> elem(0)

  defp covered(positioned, frame) do
    positioned |> Algebra.covered(1, frame) |> Enum.map(&{&1.start, &1.stop}) |> Enum.sort()
  end

  # Days or weeks on a date step a day at a time; anything else is a walk in ticks.
  defp landed(start, total, busy, extended, %Duration{units: by}, frame) do
    by_days? = Enum.all?(by, fn {unit, _} -> unit in [:week, :day] end)

    if by_days? and Unit.clock_units(extended) == [],
      do: stepped_days(start, div(total, @day), busy, frame),
      else: walked(start, total, busy)
  end

  defp walked(start, total, busy) when total >= 0 do
    cursor = Enum.find_value(busy, start, fn {s, e} -> if s <= start and start < e, do: e end)

    busy
    |> Enum.filter(fn {s, _} -> s >= cursor end)
    |> Enum.reduce_while({cursor, total}, fn {s, e}, {c, remaining} ->
      if s - c >= remaining,
        do: {:halt, {c + remaining, 0}},
        else: {:cont, {e, remaining - (s - c)}}
    end)
    |> then(fn {c, remaining} -> c + remaining end)
  end

  defp walked(start, total, busy) do
    cursor = Enum.find_value(busy, start, fn {s, e} -> if s < start and start < e, do: s end)

    busy
    |> Enum.filter(fn {_, e} -> e <= cursor end)
    |> Enum.reverse()
    |> Enum.reduce_while({cursor, -total}, fn {s, e}, {c, remaining} ->
      if c - e >= remaining,
        do: {:halt, {c - remaining, 0}},
        else: {:cont, {s, remaining - (c - e)}}
    end)
    |> then(fn {c, remaining} -> c - remaining end)
  end

  # From a day to the nth free day on, a calendar day at a time, on the frame's wall clock.
  defp stepped_days(start, days, busy, frame) do
    wall_busy = Enum.map(busy, fn {s, e} -> {Walk.wall(s, frame), Walk.wall(e, frame)} end)
    direction = if days < 0, do: -1, else: 1
    day = Integer.floor_div(Walk.wall(start, frame), @day)

    landed_day =
      Enum.reduce(1..abs(days)//1, day, fn _, d ->
        next_free_day(d + direction, direction, wall_busy)
      end)

    utc_of_wall(landed_day * @day + Integer.mod(Walk.wall(start, frame), @day), frame)
  end

  defp next_free_day(day, direction, busy) do
    if Enum.any?(busy, fn {s, e} -> s < (day + 1) * @day and day * @day < e end),
      do: next_free_day(day + direction, direction, busy),
      else: day
  end

  defp utc_of_wall(wall, %{zone: nil, shift: nil}), do: wall

  defp utc_of_wall(wall, %{zone: zone, shift: shift}),
    do: Zone.utc_of_wall(zone, shift, wall)

  # ── Truncating, rounding, extending ───────────────────────────────────

  @doc "An expression written to a coarser unit: its units through that one, or the period of it the value starts in."
  @spec trunc(expression(), Unit.t()) :: {:ok, expression()} | {:error, Exception.t()}
  def trunc(%Tempo{form: {:value, units}} = value, unit) do
    cond do
      Keyword.has_key?(units, unit) ->
        {:ok, %{value | form: {:value, through(units, unit)}} |> requalified()}

      Unit.compare(unit, Unit.grain(Unit.resolution(units))) != :lt ->
        {:ok, value}

      not Unit.concrete?(units) ->
        {:error, conversion(value, :several)}

      not Unit.anchored?(units) ->
        {:error, conversion(value, :needs_a_year)}

      true ->
        frame = Spans.frame_of(value)

        with {:ok, {start, _}} <- extent(plain(units), frame, value) do
          {:ok, %{value | form: {:value, period_units(start, unit, frame)}} |> requalified()}
        end
    end
  end

  def trunc(%Tempo{} = expression, unit), do: each_part(expression, &trunc(&1, unit))
  def trunc(%Duration{} = duration, _unit), do: {:error, conversion(duration, :bare_duration)}

  defp through(units, unit) do
    {before, [at | _]} = Enum.split_while(units, fn {u, _} -> u != unit end)
    before ++ [at]
  end

  # The qualifications of the units a value still has.
  defp requalified(%Tempo{qualifications: nil} = value), do: value

  defp requalified(%Tempo{form: {:value, units}, qualifications: q} = value) do
    kept = Map.take(q, Keyword.keys(units))
    %{value | qualifications: if(kept == %{}, do: nil, else: kept)}
  end

  # The period of a unit a position is in, written on that unit's axis.
  @doc false
  @spec period_units(Scale.position(), Unit.t(), Spans.frame()) :: Unit.units()
  def period_units(position, unit, frame) do
    wall = Walk.wall(position, frame)
    day = Integer.floor_div(wall, @day)

    cond do
      unit in [:week, :day_of_week] -> date_units(day, [week: 1] ++ weekday(unit), frame.calendar)
      unit == :day_of_year -> date_units(day, [day_of_year: 1], frame.calendar)
      Unit.clock?(unit) -> Walk.at_tick(wall, unit, frame.calendar)
      true -> Walk.at_day(day, day_unit(unit), frame.calendar)
    end
  end

  defp weekday(:day_of_week), do: [day_of_week: 1]
  defp weekday(_week), do: []

  @doc "A value rounded to the nearest period of a unit: truncated, and moved on one unit when its start is past the midpoint."
  @spec round(expression(), Unit.t()) :: {:ok, expression()} | {:error, Exception.t()}
  def round(%Tempo{form: {:value, units}} = value, unit) do
    cond do
      not Unit.concrete?(units) ->
        {:error, conversion(value, :several)}

      Unit.compare(unit, Unit.grain(Unit.resolution(units))) == :gt ->
        {:error, conversion(value, {:finer_than_written, unit})}

      true ->
        rounded(value, units, unit)
    end
  end

  def round(%Tempo{} = expression, unit), do: each_part(expression, &round(&1, unit))
  def round(%Duration{} = duration, _unit), do: {:error, conversion(duration, :bare_duration)}

  defp rounded(value, units, unit) do
    frame = Spans.frame_of(value)

    with {:ok, %Tempo{form: {:value, floor_units}} = floor} <- trunc(value, unit),
         {:ok, {start, _}} <- extent(plain(units), frame, value),
         {:ok, {first, last}} <- extent(plain(floor_units), frame, floor) do
      if 2 * start >= first + last, do: shift(floor, one(unit)), else: {:ok, floor}
    end
  end

  # One unit, as a duration.
  @doc false
  @spec one(Unit.t()) :: Duration.t()
  def one(:quarter), do: %Duration{units: [month: 3]}
  def one(:decade), do: %Duration{units: [year: 10]}
  def one(:century), do: %Duration{units: [year: 100]}
  def one(:microsecond), do: %Duration{units: [microsecond: {1, 6}]}
  def one(unit), do: %Duration{units: [{Unit.grain(unit), 1}]}

  @doc "A value with the next finer unit written as the values it takes, down to a unit when one is given."
  @spec extend(expression(), Unit.t() | nil) :: {:ok, expression()} | {:error, Exception.t()}
  def extend(%Tempo{form: {:value, units}} = value, unit) do
    if unit != nil and Unit.compare(unit, Unit.grain(Unit.resolution(units))) != :gt do
      {:ok, value}
    else
      with {:ok, extended} <- extend_once(value, units), do: extend_on(extended, unit)
    end
  end

  def extend(%Tempo{} = expression, unit), do: each_part(expression, &extend(&1, unit))
  def extend(%Duration{} = duration, _unit), do: {:error, conversion(duration, :bare_duration)}

  defp extend_on(extended, nil), do: {:ok, extended}
  defp extend_on(extended, unit), do: extend(extended, unit)

  defp extend_once(value, units) do
    case List.last(units) do
      {:group, {nth, [{unit, size}]}} ->
        group_values(value, Enum.drop(units, -1), nth, unit, size)

      {:second, _} ->
        {:error, conversion(value, :no_finer_unit)}

      {:microsecond, _} ->
        {:error, conversion(value, :no_finer_unit)}

      {last, _} when last in [:century, :decade] ->
        child_values(value, [], :year)

      {last, _} ->
        child_values(value, units, child_of(last))
    end
  end

  defp child_of(:week), do: :day_of_week
  defp child_of(unit), do: Unit.child(Unit.grain(unit))

  defp child_values(value, _units, nil), do: {:error, conversion(value, :no_finer_unit)}

  defp child_values(%Tempo{form: {:value, original}} = value, [], :year) do
    with {:ok, children} <- children(plain(original), :year, Spans.frame_of(value), value),
         do: {:ok, %{value | form: {:value, [year: listed(Enum.map(children, &elem(&1, 0)))]}}}
  end

  defp child_values(%Tempo{} = value, units, child) do
    if Unit.concrete?(units) and Unit.anchored?(units) do
      frame = Spans.frame_of(value)

      case Expand.children(plain(units), child, frame) do
        {:ok, children} ->
          {:ok,
           %{value | form: {:value, units ++ [{child, listed(Enum.map(children, &elem(&1, 0)))}]}}}

        {:error, reason} ->
          {:error, conversion(value, reason)}
      end
    else
      {:ok, %{value | form: {:value, units ++ [{child, every(child)}]}}}
    end
  end

  # Every value of a unit under values that may differ in how many they hold.
  defp every(:hour), do: [0..23]
  defp every(unit) when unit in [:minute, :second], do: [0..59]
  defp every(:day_of_week), do: [1..7]
  defp every(_calendar), do: [1..-1//1]

  # Several groups are several values: each is extended, and they are a set.
  defp group_values(%Tempo{} = value, _prefix, nth, _unit, _size) when not is_integer(nth) do
    with {:ok, members} <- Spans.members(value),
         {:ok, extended} <- each(Enum.take(members, Limit.values()), &extend(&1, nil)),
         do: {:ok, %{value | form: {:all, extended}}}
  end

  defp group_values(%Tempo{} = value, prefix, nth, unit, size) do
    if Unit.concrete?(prefix) and Unit.anchored?(prefix) do
      with {:ok, children} <- children(plain(prefix), unit, Spans.frame_of(value), value) do
        groups = children |> Enum.map(&elem(&1, 0)) |> Enum.chunk_every(size)
        grouped(value, prefix, unit, Enum.at(groups, group_index(nth, length(groups))))
      end
    else
      {:error, conversion(value, :several)}
    end
  end

  defp group_index(nth, _count) when nth > 0, do: nth - 1
  defp group_index(nth, count), do: count + nth

  defp grouped(value, _prefix, _unit, nil), do: {:error, conversion(value, :no_such_value)}

  defp grouped(value, prefix, unit, values),
    do: {:ok, %{value | form: {:value, prefix ++ [{unit, listed(values)}]}}}

  defp children(prefix, unit, frame, value) do
    case Expand.children(prefix, unit, frame) do
      {:ok, children} -> {:ok, children}
      {:error, reason} -> {:error, conversion(value, reason)}
    end
  end

  @doc "A value written at a unit: truncated to a coarser one, extended with first values to a finer one."
  @spec at_resolution(expression(), Unit.t()) :: {:ok, expression()} | {:error, Exception.t()}
  def at_resolution(%Tempo{form: {:value, units}} = value, unit) do
    if Unit.compare(unit, Unit.grain(Unit.resolution(units))) == :gt,
      do: {:ok, %{value | form: {:value, extended_to(units, unit, value.calendar)}}},
      else: trunc(value, unit)
  end

  def at_resolution(%Tempo{} = expression, unit),
    do: each_part(expression, &at_resolution(&1, unit))

  def at_resolution(%Duration{} = duration, _unit),
    do: {:error, conversion(duration, :bare_duration)}

  @doc "A value split into its date and its time of day, either nil when the value has none."
  @spec split(expression()) :: {Tempo.t() | nil, Tempo.t() | nil} | {:error, Exception.t()}
  def split(%Tempo{form: {:value, units}} = value) do
    {part(value, Unit.date_units(units)), part(value, Unit.clock_units(units))}
  end

  def split(%Tempo{} = expression), do: {:error, conversion(expression, :several)}
  def split(%Duration{} = duration), do: {:error, conversion(duration, :bare_duration)}

  defp part(_value, []), do: nil
  defp part(value, units), do: requalified(%{value | form: {:value, units}})

  # An operation on each written end of a span, each member of a set, and a
  # recurrence's first span and end.
  defp each_part(%Tempo{form: {:span, from, to}} = span, fun) do
    with {:ok, from} <- end_part(from, fun),
         {:ok, to} <- end_part(to, fun) do
      {:ok, %{span | form: {:span, from, to}}}
    end
  end

  defp each_part(%Tempo{form: {:every, first, bound, rule}} = recurrence, fun) do
    with {:ok, first} <- each_part(first, fun),
         {:ok, bound} <- end_part(bound, fun) do
      {:ok, %{recurrence | form: {:every, first, bound, rule}}}
    end
  end

  defp each_part(%Tempo{form: {kind, members}} = set, fun) when kind in [:all, :one] do
    with {:ok, members} <- each(members, fun), do: {:ok, %{set | form: {kind, members}}}
  end

  defp each_part(%Tempo{} = expression, _fun), do: {:error, conversion(expression, :conditions)}

  defp end_part(%Tempo{} = value, fun), do: fun.(value)
  defp end_part(other, _fun), do: {:ok, other}

  defp finer_resolution(%Tempo{form: {:value, a}}, %Tempo{form: {:value, b}}) do
    [a, b]
    |> Enum.map(&Unit.grain(Unit.resolution(&1)))
    |> Enum.max_by(fn unit -> Enum.find_index(Unit.order(), &(&1 == unit)) end)
  end

  # A value in a named zone written with a time shift takes the zone's shift where it lands.
  defp rezoned(%Tempo{zone: %Zone{} = zone} = moved, %Tempo{shift: shift}, position)
       when shift != nil do
    offset = Zone.offset_at_utc(zone, position)
    hours = div(offset, 3_600_000_000)
    minutes = div(rem(offset, 3_600_000_000), 60_000_000)
    %{moved | shift: [hour: hours, minute: minutes]}
  end

  defp rezoned(moved, _original, _position), do: moved

  defp conversion(expression, reason),
    do: ConversionError.exception(value: expression, reason: reason)
end
