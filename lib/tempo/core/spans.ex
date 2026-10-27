defmodule Tempo.Spans do
  @moduledoc false

  # The meaning of any expression (section 7.1 of the plan): the ordered
  # sequence of half-open spans it denotes, each a `%Tempo{}` of the `:span`
  # form with concrete value ends, lazily where the sequence is long. Every
  # other core module reads an expression through this one.
  #
  # A value is one span, `[v, next(v))` (law 3), or, with a set, a mask or a
  # group in a unit, each value its units allow (`Tempo.Expand`). A written
  # span runs from the start of its first end to the end of its last when
  # that end is written to a calendar unit and to its start when written to
  # a clock unit (law 9). A set is its members' spans, merged in order of
  # start. A recurrence's occurrences are `Tempo.Recurrence`'s, what a set or
  # a rule leaves out `Tempo.Exclusions`', and what `Enum` yields for an
  # expression, with its readings, `Tempo.Children`'.

  alias Tempo.Calendar
  alias Tempo.Conditions
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Exclusions
  alias Tempo.Expand
  alias Tempo.Limit
  alias Tempo.Placed
  alias Tempo.Recurrence
  alias Tempo.Scale
  alias Tempo.Select
  alias Tempo.Shift
  alias Tempo.Unit
  alias Tempo.Walk
  alias Tempo.Zone

  @day Scale.ticks_per_day()

  @type frame :: %{
          calendar: module(),
          zone: Zone.t() | nil,
          shift: Zone.shift() | nil,
          frame: Scale.frame()
        }
  @type extent :: {Scale.position() | nil, Scale.position() | nil}

  # ── Frames ────────────────────────────────────────────────────────────

  @doc "The frame an expression lies on: the UTC line, the floating line or a cycle."
  @spec frame(Tempo.t()) :: Scale.frame()
  def frame(%Tempo{form: {:value, units}, zone: zone, shift: shift}),
    do: Scale.frame(units, zone, shift)

  def frame(%Tempo{form: {:span, from, to}}), do: frame(first_value([from, to]))
  def frame(%Tempo{form: {:every, first, _bound, _rule}}), do: frame(first)

  # A set's frame is that of its first member with a place of its own: a
  # rule with no start (`R/../P1Y/F…`) takes the frame of what it is beside.
  def frame(%Tempo{form: {kind, [first | _] = members}}) when kind in [:all, :one] do
    members
    |> Enum.map(&member_value/1)
    |> Enum.find(member_value(first), &placed?/1)
    |> frame()
  end

  def frame(%Tempo{form: {:when, member, _conditions}}), do: frame(member)

  # A set read from a stream takes its frame from its first member.
  def frame(%Tempo{form: {:all, members}}) when not is_list(members) do
    case Enum.take(members, 1) do
      [first] -> frame(first)
      [] -> :floating
    end
  end

  def frame(%Tempo{}), do: :floating

  # A duration has no place: a set of durations is on no line.
  def frame(%Duration{}), do: :floating

  defp placed?(%Tempo{form: {:every, %Tempo{form: {:span, :open, _}}, _, _}}), do: false
  defp placed?(%Tempo{form: {:span, :open, _}}), do: false
  defp placed?(_member), do: true

  @doc """
  The first end of a span that is a value, or a value of no units for a
  span open at both ends.
  """
  @spec first_value([Tempo.t() | Duration.t() | :open]) :: Tempo.t()
  def first_value(ends), do: Enum.find(ends, &match?(%Tempo{}, &1)) || %Tempo{form: {:value, []}}
  defp member_value({:except, member}), do: member
  defp member_value(member), do: member

  @doc """
  A window as an expression's occurrences are looked for in it. A floating
  window beside a zoned expression is read on that expression's clock: June
  is the June of its zone.
  """
  @spec window_in(Tempo.t() | nil, Tempo.t()) :: Tempo.t() | nil
  def window_in(%Tempo{} = window, %Tempo{} = expression) do
    if frame(window) == :floating and frame(expression) == :utc,
      do: on_clock(window, clock_of(expression)),
      else: window
  end

  def window_in(window, _expression), do: window

  defp windowed_for(options, expression) do
    case options[:within] do
      %Tempo{} = window -> Keyword.put(options, :within, window_in(window, expression))
      _none -> options
    end
  end

  # The zone, or with none the shift, an expression's readings are placed by.
  defp clock_of(%Tempo{form: {:every, first, _bound, _rule}, zone: zone}),
    do: {zone || first.zone, frame_of(first).shift}

  defp clock_of(%Tempo{form: {:all, [%Tempo{} = first | _]}, zone: nil}), do: clock_of(first)
  defp clock_of(%Tempo{zone: zone} = expression), do: {zone, frame_of(expression).shift}

  defp on_clock(window, {nil, nil}), do: window

  defp on_clock(%Tempo{form: {:value, _}} = value, {nil, shift}), do: %{value | shift: shift}
  defp on_clock(%Tempo{form: {:value, _}} = value, {zone, _shift}), do: %{value | zone: zone}

  defp on_clock(%Tempo{form: {:span, from, to}} = span, {zone, _shift} = clock),
    do: %{span | zone: zone, form: {:span, end_on_clock(from, clock), end_on_clock(to, clock)}}

  defp on_clock(window, _clock), do: window

  defp end_on_clock(%Tempo{} = value, clock), do: on_clock(value, clock)
  defp end_on_clock(other, _clock), do: other

  @doc "The calendar, zone and shift of an expression, as the engine takes them."
  @spec frame_of(Tempo.t()) :: frame()
  def frame_of(%Tempo{form: {:span, from, to}} = span),
    do: %{
      calendar: span.calendar,
      zone: span.zone,
      shift: end_shift([from, to]),
      frame: frame(span)
    }

  def frame_of(%Tempo{calendar: calendar, zone: zone, shift: shift} = expression),
    do: %{calendar: calendar, zone: zone, shift: shift, frame: frame(expression)}

  defp end_shift(ends) do
    case Enum.find(ends, &match?(%Tempo{}, &1)) do
      %Tempo{shift: shift} -> shift
      nil -> nil
    end
  end

  # ── One span or many ──────────────────────────────────────────────────

  @doc """
  Whether an expression is a set whose members are read as they are asked
  for (`Tempo.IntervalSet.from_stream/2`, a selection over a span with no
  end): it may have no last member, so nothing that needs every member is
  answered of it without a window.
  """
  @spec lazy?(Tempo.t() | Duration.t()) :: boolean()
  def lazy?(%Tempo{form: {kind, members}}) when kind in [:all, :one], do: not is_list(members)
  def lazy?(_expression), do: false

  @doc "`:ok` for an expression every member of which can be asked for, and the error for a lazy set."
  @spec whole(Tempo.t() | Duration.t()) :: :ok | {:error, Exception.t()}
  def whole(expression) do
    if lazy?(expression), do: {:error, conversion(expression, :unbounded)}, else: :ok
  end

  @doc "Whether an expression denotes one span: a value with one value in each unit, or a written span with such ends."
  @spec singular?(Tempo.t() | Duration.t()) :: boolean()
  def singular?(%Tempo{form: {:value, units}}), do: Expand.one_span?(units)
  def singular?(%Tempo{form: {:span, from, to}}), do: end_singular?(from) and end_singular?(to)
  def singular?(_expression), do: false

  defp end_singular?(%Tempo{} = value), do: singular?(value)
  defp end_singular?(_duration_or_open), do: true

  # ── Extents ───────────────────────────────────────────────────────────

  @doc """
  The half-open extent of a singular expression on its frame: of a value,
  one unit of its resolution; of a written span, from the start of its
  first end to the end of a calendar-unit last end or the start of a
  clock-unit one (law 9). An open end is `nil`.
  """
  @spec extent(Tempo.t()) :: {:ok, extent()} | {:error, Exception.t()}
  def extent(%Tempo{form: {:value, units}} = value) do
    case Expand.extent(units, frame_of(value)) do
      {:ok, extent} -> {:ok, extent}
      {:error, reason} -> {:error, conversion(value, reason)}
    end
  end

  def extent(%Tempo{form: {:span, from, to}} = span) do
    with {:ok, extent} <- span_extent(from, to, span), do: wrapped(extent, span)
  end

  def extent(%Tempo{} = expression), do: {:error, conversion(expression, :several)}

  # On a cycle an end not after the start runs on through the cycle's end: `T22H/T2H`, `12M/2M`.
  defp wrapped({start, stop}, span)
       when is_integer(start) and is_integer(stop) and stop <= start do
    case frame(span) do
      {:cycle, coarsest} ->
        with {:ok, length} <- Scale.cycle_length(coarsest, span.calendar) |> cycle_error(span) do
          {:ok, {start, stop + length}}
        end

      _line ->
        {:ok, {start, stop}}
    end
  end

  defp wrapped(extent, _span), do: {:ok, extent}

  defp cycle_error({:ok, length}, _span), do: {:ok, length}
  defp cycle_error({:error, reason}, span), do: {:error, conversion(span, reason)}

  defp span_extent(%Tempo{} = from, %Tempo{} = to, _span) do
    with {:ok, {start, _}} <- extent(from),
         {:ok, stop} <- end_position(to) do
      {:ok, {start, stop}}
    end
  end

  defp span_extent(%Tempo{} = from, %Duration{} = duration, span) do
    with {:ok, {start, _}} <- extent(from),
         {:ok, stop} <- shifted(start, duration, frame_of(span), span) do
      {:ok, {start, stop}}
    end
  end

  defp span_extent(%Duration{} = duration, %Tempo{} = to, span) do
    with {:ok, stop} <- end_position(to),
         {:ok, start} <- shifted(stop, negated(duration), frame_of(span), span) do
      {:ok, {start, stop}}
    end
  end

  defp span_extent(%Tempo{} = from, :open, _span) do
    with {:ok, {start, _}} <- extent(from), do: {:ok, {start, nil}}
  end

  defp span_extent(:open, %Tempo{} = to, _span) do
    with {:ok, stop} <- end_position(to), do: {:ok, {nil, stop}}
  end

  defp span_extent(:open, :open, _span), do: {:ok, {nil, nil}}
  defp span_extent(_from, _to, span), do: {:error, conversion(span, :open)}

  @doc """
  Where a written end ends: after its last unit for a date, at its reading
  for a time of day.
  """
  @spec end_position(Tempo.t()) :: {:ok, Scale.position()} | {:error, Exception.t()}
  def end_position(%Tempo{} = to) do
    with {:ok, {start, stop}} <- extent(to) do
      if clock_resolution?(to), do: {:ok, start}, else: {:ok, stop}
    end
  end

  @doc "Whether a value is written to a clock unit, so that as an end it is a boundary and not a period."
  @spec clock_resolution?(Tempo.t()) :: boolean()
  def clock_resolution?(%Tempo{form: {:value, units}}), do: Unit.clock?(Unit.resolution(units))
  def clock_resolution?(_other), do: false

  # ── Shifting a position by a duration ─────────────────────────────────

  @doc """
  A position moved by a duration: the date part on the day scale through the
  calendar (years, then months with the day clamped, then weeks and days),
  read on the wall clock of the frame; then the clock part in ticks, which is
  elapsed time.
  """
  @spec shifted(Scale.position(), Duration.t(), frame(), Tempo.t()) ::
          {:ok, Scale.position()} | {:error, Exception.t()}
  def shifted(tick, %Duration{units: units}, %{frame: {:cycle, _}}, expression)
      when is_integer(tick) do
    if Enum.all?(units, fn {unit, _} -> Unit.clock?(unit) end),
      do: {:ok, tick + clock_ticks(units)},
      else: {:error, conversion(expression, :needs_a_year)}
  end

  def shifted(tick, %Duration{units: units}, frame, _expression) when is_integer(tick) do
    {date_units, clock_units} =
      Enum.split_with(units, fn {unit, _} -> unit in [:year, :month, :week, :day] end)

    {:ok, date_shifted(tick, date_units, frame) + clock_ticks(clock_units)}
  end

  def shifted(nil, _duration, _frame, expression), do: {:error, conversion(expression, :open)}

  # The date part moves the day and keeps the reading of the wall clock; the
  # clock part is added to the position, so an hour is an hour of elapsed time
  # across a change of the clock.
  defp date_shifted(tick, [], _frame), do: tick

  defp date_shifted(tick, date_units, frame) do
    wall = Walk.wall(tick, frame)
    day = Integer.floor_div(wall, @day)
    moved = day |> day_shifted(date_units, frame.calendar) |> shown_day(day, frame)
    on_frame(moved * @day + Integer.mod(wall, @day), frame)
  end

  # A day the zone's clock leaves out is not landed on: the step goes on to
  # the day after it, or the day before where it runs back.
  defp shown_day(moved, from, %{zone: zone, shift: shift}) do
    cond do
      not Zone.day_skipped?(zone, shift, moved) -> moved
      moved < from -> moved - 1
      true -> moved + 1
    end
  end

  defp day_shifted(day, date_units, calendar) do
    {weeks, rest} = Keyword.pop(date_units, :week, 0)
    rest = Keyword.update(rest, :day, weeks * 7, &(&1 + weeks * 7))
    {y, m, d} = Calendar.date(calendar, day)
    {y2, m2, d2} = Calendar.shift_date(calendar, y, m, d, Elixir.Duration.new!(rest))
    Calendar.iso_days(calendar, y2, m2, d2)
  end

  defp clock_ticks(units) do
    Enum.reduce(units, 0, fn
      {:microsecond, {microseconds, _precision}}, sum -> sum + microseconds
      {unit, n}, sum -> sum + n * Unit.ticks(unit)
    end)
  end

  defp on_frame(wall, %{zone: nil, shift: nil}), do: wall
  defp on_frame(wall, %{zone: zone, shift: shift}), do: Zone.utc_of_wall(zone, shift, wall)

  @doc "A duration in the reverse direction."
  @spec negated(Duration.t()) :: Duration.t()
  def negated(%Duration{} = duration), do: scaled(duration, -1)

  @doc "A duration taken n times."
  @spec scaled(Duration.t(), integer()) :: Duration.t()
  def scaled(%Duration{units: units}, n) do
    %Duration{
      units:
        Enum.map(units, fn
          {:microsecond, {us, precision}} -> {:microsecond, {us * n, precision}}
          {unit, value} -> {unit, value * n}
        end)
    }
  end

  # ── Spans ─────────────────────────────────────────────────────────────

  @doc """
  The spans an expression denotes, lazily and in order, each a `%Tempo{}` of
  the `:span` form with value ends and the expression's calendar, zone and
  metadata. A sequence with no end of its own is bounded by `:within`.
  This is `placed/2` with the places left off: the public layer's reading.
  """
  @spec spans(Tempo.t() | Duration.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def spans(expression, options \\ []) do
    with {:ok, placed} <- placed(expression, options), do: {:ok, Placed.written(placed)}
  end

  @doc """
  The spans an expression denotes, each with its place (`Tempo.Placed`):
  the engine's reading, made as each span is made so that no span is placed
  again by the step that takes it. A sequence with no end of its own is
  bounded by `:within`.
  """
  @spec placed(Tempo.t() | Duration.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def placed(expression, options \\ [])

  def placed(%Duration{} = duration, _options), do: {:error, conversion(duration, :bare_duration)}

  def placed(%Tempo{form: {:value, units}} = value, options) do
    cond do
      Keyword.has_key?(units, :selection) ->
        with {:ok, values} <- selected_values(value, options), do: each_spans_of(values, [])

      not Unit.anchored?(units) and not is_nil(options[:within]) ->
        placed_value_spans(value, options[:within], Keyword.delete(options, :within))

      Expand.one_span?(units) ->
        with {:ok, span} <- as_placed(value), do: {:ok, [span]}

      true ->
        expanded_spans(value)
    end
  end

  def placed(%Tempo{form: {:span, from, to}} = span, options) do
    if not is_nil(options[:within]) and match?({:cycle, _}, frame(span)) do
      placed_span_spans(span, options[:within], Keyword.delete(options, :within))
    else
      written_spans(span, from, to, options)
    end
  end

  def placed(%Tempo{form: {:every, first, bound, rule}} = recurrence, options) do
    options = windowed_for(options, recurrence)

    if is_nil(rule) do
      Recurrence.occurrences(first, bound, recurrence, options)
    else
      Recurrence.rule_occurrences(first, bound, rule, recurrence, options)
    end
  end

  # A set read from a stream gives its members' spans as they are asked for.
  # Its members are in order of start, so a window stops the reading.
  def placed(%Tempo{form: {:all, members}}, options) when not is_list(members) do
    {:ok, members |> Stream.flat_map(&member_stream(&1, options)) |> windowed(options)}
  end

  def placed(%Tempo{form: {:all, members}} = set, options) do
    case Enum.split_with(members, &match?({:except, _}, &1)) do
      {[], members} ->
        members |> member_spans(options) |> overlapping(set, options)

      {excluded, members} ->
        set
        |> Exclusions.excluded_spans(members, Enum.map(excluded, &elem(&1, 1)), options)
        |> overlapping(set, options)
    end
  end

  def placed(%Tempo{form: {:one, _}} = set, _options), do: {:error, conversion(set, :one_of)}

  # A domain filter: the members' spans in the years the filter names.
  def placed(%Tempo{form: {:when, member, years: filter}} = expression, options) do
    with {:ok, spans} <- placed(%{member | calendar: expression.calendar}, options) do
      {:ok, Stream.filter(spans, &Exclusions.in_years?(&1.span, filter, expression.calendar))}
    end
  end

  # A rule converted to another calendar (`Tempo.to_calendar/2` of a rule
  # with no end): selected in its own calendar, each span read in this one.
  def placed(%Tempo{form: {:when, member, read_in: calendar}} = converted, options) do
    with {:ok, spans} <- placed(member, options) do
      {:ok, Stream.map(spans, &read_in(&1, calendar, converted.metadata))}
    end
  end

  def placed(%Tempo{form: {:when, _, _}} = member, options) do
    if Conditions.conditional?(member),
      do: Conditions.resolve([member], [], options),
      else: {:error, conversion(member, :conditions)}
  end

  # A span on the line, or written there: the spans its ends name.
  defp written_spans(span, from, to, options) do
    case {plural_end(from), plural_end(to)} do
      {false, false} ->
        with {:ok, resolved} <- resolved_placed(span, options), do: {:ok, [resolved]}

      {true, true} ->
        paired_ends(span, options)

      {true, false} ->
        each_end(span, :from, from, options)

      {false, true} ->
        each_end(span, :to, to, options)
    end
  end

  # A span with no year placed by a window on the line, as a value is
  # (decision 72): from each start the window holds, to the next reading of
  # its end. A window with no year places nothing.
  defp placed_span_spans(%Tempo{form: {:span, from, to}} = span, window, options) do
    if on_the_line?(window),
      do: each_placed_span(span, window, options),
      else: written_spans(span, from, to, options)
  end

  defp each_placed_span(%Tempo{form: {:span, %Tempo{} = from, to}} = span, window, options) do
    with {:ok, starts} <- held_in(from, window, options) do
      starts
      |> Enum.map(&%{span | form: {:span, &1, end_after(to, &1, from)}})
      |> each_spans_of(open_end_options(to, window))
    end
  end

  # A span with an open start is placed by its end: from where the window
  # begins to each end the window holds.
  defp each_placed_span(%Tempo{form: {:span, :open, %Tempo{} = to}} = span, window, options) do
    with {:ok, ends} <- held_in(to, window, options) do
      ends
      |> Enum.map(&%{span | form: {:span, :open, &1}})
      |> each_spans_of(within: window)
    end
  end

  defp each_placed_span(%Tempo{form: {:span, from, to}} = span, _window, options),
    do: written_spans(span, from, to, options)

  # An open end of a placed span is placed where the window ends, as the open
  # end of a span with a year is.
  defp open_end_options(:open, window) do
    [within: window]
  end

  defp open_end_options(_end, _window) do
    []
  end

  # The values of an end with no year whose first instant the window holds,
  # each whole (decision 72): a window finer than the value selects a part
  # of it, and the value is that part written to the value's own unit, held
  # where one of the window's periods holds its first instant.
  defp held_in(value, window, options) do
    with {:ok, placed} <- in_each_period(value, window, options),
         {:ok, periods} <- placed(window, []),
         {:ok, periods} <- Limit.take(periods, window) do
      bounds = Enum.map(periods, &{&1.start, &1.stop})

      placed
      |> Enum.flat_map(&held(&1, value, bounds))
      |> Enum.uniq()
      |> then(&{:ok, &1})
    end
  end

  defp held(placed, value, bounds) do
    case whole_of(first_of(placed), value) do
      {:ok, whole, start} -> held_whole(whole, start, bounds)
      {:error, _exception} -> []
    end
  end

  defp held_whole(whole, start, bounds) do
    if Enum.any?(bounds, &holds?(&1, start)) do
      [whole]
    else
      []
    end
  end

  defp first_of(%Tempo{form: {:span, %Tempo{} = first, _last}}) do
    first
  end

  defp first_of(value) do
    value
  end

  defp whole_of(first, %Tempo{form: {:value, units}}) do
    with {:ok, whole} <- Shift.trunc(first, Unit.grain(Unit.resolution(units))),
         {:ok, {start, _stop}} <- extent(whole) do
      {:ok, whole, start}
    end
  end

  defp holds?({start, stop}, position) when is_integer(start) and is_integer(stop) do
    start <= position and position < stop
  end

  defp holds?(_open, _position) do
    false
  end

  # The end of a placed span is the first reading of its end at or after its
  # start, within one turn of the cycle they differ on: the Tuesday after a
  # Friday, the 02:00 after 22:00.
  defp end_after(%Tempo{form: {:value, _}} = to, start, from) do
    turn = %{start | form: {:span, start, cycle_of(differing(from, to))}}

    case in_each_period(to, turn, []) do
      {:ok, [first | _]} -> first
      _none -> to
    end
  end

  defp end_after(duration_or_open, _start, _from), do: duration_or_open

  defp read_in(%Placed{start: start, stop: stop, span: span}, calendar, metadata) do
    %Tempo{form: {:span, from, to}} = span

    read = %Tempo{
      form:
        {:span, at_position(start, from, :start, calendar, span.zone),
         at_position(stop, to, :end, calendar, span.zone)},
      calendar: calendar,
      zone: span.zone,
      metadata: Map.merge(metadata, span.metadata)
    }

    Placed.new(read, {start, stop})
  end

  defp member_stream(member, options) do
    case placed(member, options) do
      {:ok, spans} -> spans
      {:error, exception} -> raise exception
    end
  end

  # A set's members' spans; members conditional on the others are judged
  # against the others' spans, and the whole put in order of start.
  # A window keeps the members of a set that overlap it, a dated member as
  # an occurrence of a recurrence.
  defp overlapping({:ok, spans}, set, options) do
    case window_extent(window_in(options[:within], set)) do
      {:ok, {start, stop}} ->
        {:ok, Stream.filter(spans, &overlaps_window?(&1, {start, stop}))}

      _none ->
        {:ok, spans}
    end
  end

  defp overlapping(error, _set, _options), do: error

  defp overlaps_window?(%Placed{start: s, stop: e}, window) when is_integer(s) and is_integer(e),
    do: Scale.overlap?({s, e}, window)

  defp overlaps_window?(_open, _window), do: true

  defp member_spans(members, options) do
    case Enum.split_with(members, &Conditions.conditional?/1) do
      {[], members} ->
        with {:ok, streams} <- each_spans(members, options), do: {:ok, in_time_order(streams)}

      # The conditions are read over the window and a year either side, so
      # that a day kept between two holidays at the window's edge, or moved
      # into it from before, is judged as it is anywhere; the set keeps
      # what lies in the window.
      {conditionals, members} ->
        wide = widened(options)

        with {:ok, streams} <- each_spans(members, wide),
             {:ok, others} <- Limit.take(in_time_order(streams), hd(conditionals)),
             {:ok, conditional} <- Conditions.resolve(conditionals, others, wide) do
          {:ok, Enum.sort_by(others ++ conditional, &start_of/1)}
        end
    end
  end

  @doc """
  The options with their `:within` window widened by a year either side,
  where it has one: the conditions of a set are read over it.
  """
  @spec widened(keyword()) :: keyword()
  def widened(options) when is_list(options) do
    case window_extent(options[:within]) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
        Keyword.put(options, :within, widened_window(options[:within], start, stop))

      _none ->
        options
    end
  end

  defp widened_window(%Tempo{calendar: calendar, zone: zone} = window, start, stop) do
    day = %Tempo{form: {:value, [year: 2000, month: 1, day: 1]}, calendar: calendar, zone: zone}
    from = at_position(start - 366 * @day, day, :start, calendar, zone)
    to = at_position(stop + 366 * @day, day, :end, calendar, zone)
    %{window | form: {:span, from, to}, metadata: %{}}
  end

  @doc "Where a span starts, or 0 where it has no start on a line; a placed span knows."
  @spec start_position(Tempo.t() | Placed.t()) :: Scale.position()
  def start_position(%Placed{start: start}) when is_integer(start), do: start
  def start_position(%Placed{}), do: 0

  def start_position(span) do
    case extent(span) do
      {:ok, {start, _}} when is_integer(start) -> start
      _ -> 0
    end
  end

  defp start_of(placed_or_span), do: start_position(placed_or_span)

  # ── Selections ────────────────────────────────────────────────────────

  # The values a selection picks: the units before it are the period, placed
  # by the window when they have no year, and the window itself when there
  # are none; the units after it apply to each value picked.
  defp selected_values(%Tempo{form: {:value, units}} = value, options) do
    {prefix, [{:selection, parts} | trailing]} =
      Enum.split_while(units, fn {unit, _} -> unit != :selection end)

    with {:ok, periods} <- selection_periods(value, prefix, options),
         {:ok, picked} <- each_selected(periods, parts, options) do
      {:ok, Enum.flat_map(picked, &with_trailing(&1, trailing, value))}
    end
  end

  defp selection_periods(value, [], options) do
    case options[:within] do
      %Tempo{} = window ->
        with {:ok, spans} <- placed(window, []),
             do: {:ok, Enum.map(spans, &with_metadata(&1, value.metadata))}

      _ ->
        {:error, conversion(value, :needs_a_year)}
    end
  end

  defp selection_periods(value, prefix, options) do
    window = options[:within]
    period = placed_in(%{value | form: {:value, prefix}}, window)

    cond do
      Unit.anchored?(elem(period.form, 1)) -> {:ok, [period]}
      on_the_line?(window) -> in_each_period(%{value | form: {:value, prefix}}, window, [])
      true -> {:error, conversion(value, :needs_a_year)}
    end
  end

  defp with_metadata(%Placed{} = placed, metadata),
    do: Placed.update_span(placed, &%{&1 | metadata: metadata})

  # A value with no year placed by a window: in it, where the window is one
  # value it fits under, and else on each of the window's periods, as
  # `Tempo.select/3` selects it there (`4M` in `2026/2027`, each April).
  defp placed_value_spans(value, window, options) do
    placed = placed_in(value, window)

    if on_the_line?(window) and not Unit.anchored?(elem(placed.form, 1)),
      do:
        with(
          {:ok, values} <- in_each_period(value, window, options),
          do: each_spans_of(values, [])
        ),
      else: placed(placed, options)
  end

  defp on_the_line?(%Tempo{} = window), do: not match?({:cycle, _}, frame(window))
  defp on_the_line?(_none), do: false

  defp in_each_period(%Tempo{form: {:value, units}} = value, window, options) do
    with {:ok, periods} <- placed(window, []),
         {:ok, periods} <- Limit.take(periods, window),
         {:ok, picked} <- each_selected(periods, Unit.cyclic(units), options) do
      {:ok, Enum.map(picked, &%{&1 | metadata: value.metadata})}
    end
  end

  defp each_selected(periods, parts, options) do
    Enum.reduce_while(periods, {:ok, []}, fn period, {:ok, acc} ->
      case Select.in_period(period, parts, options) do
        {:ok, picked} -> {:cont, {:ok, acc ++ picked}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp with_trailing(picked, [], _value), do: [picked]

  defp with_trailing(%Tempo{form: {:value, units}} = picked, trailing, _value) do
    case Expand.expand(units ++ trailing, frame_of(picked)) do
      {:ok, values} ->
        values |> Enum.take(Limit.values()) |> Enum.map(&%{picked | form: {:value, &1}})

      {:error, _} ->
        []
    end
  end

  defp with_trailing(picked, _trailing, _value), do: [picked]

  # ── Several spans: plural ends, sets and several values ───────────────

  # Two ends plural in the same date units (`T22H/T2H` placed on every day of
  # a month) are paired value by value; each pair wraps as a span does.
  defp paired_ends(%Tempo{form: {:span, %Tempo{} = from, %Tempo{} = to}} = span, options) do
    %Tempo{form: {:value, a}} = from
    %Tempo{form: {:value, b}} = to

    if Unit.date_units(a) == Unit.date_units(b) and not Unit.plain?(Unit.date_units(a)),
      do: paired(span, from, to, options),
      else: {:error, conversion(span, :several)}
  end

  defp paired_ends(span, _options), do: {:error, conversion(span, :several)}

  defp paired(span, from, to, options) do
    with {:ok, froms} <- members(from, options),
         {:ok, tos} <- members(to, options) do
      pairs = Enum.zip_with(froms, tos, fn f, t -> wrapped(%{span | form: {:span, f, t}}) end)
      each_spans_of(pairs, Keyword.delete(options, :within))
    end
  end

  defp each_spans_of(pairs, options) do
    with {:ok, streams} <- each_spans(pairs, options), do: {:ok, Stream.concat(streams)}
  end

  defp each_spans(members, options) do
    members
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case placed(member, options) do
        {:ok, stream} -> {:cont, {:ok, [beneath(stream, member) | acc]}}
        error -> {:halt, error}
      end
    end)
    |> in_member_order()
  end

  defp in_member_order({:ok, reversed}), do: {:ok, Enum.reverse(reversed)}
  defp in_member_order(error), do: error

  # A set held as a member carries its metadata to each of its occurrences,
  # beneath the occurrence's own: a holiday's name, on the day it falls and
  # on the day it is observed.
  defp beneath(stream, %Tempo{form: {:all, _members}, metadata: metadata})
       when map_size(metadata) > 0 do
    Stream.map(
      stream,
      &Placed.update_span(&1, fn span ->
        %{span | metadata: Map.merge(metadata, span.metadata)}
      end)
    )
  end

  defp beneath(stream, _member), do: stream

  # A set's members' spans, each in the order of time, are its spans in that
  # order: merged as they are asked for, since a member may have no end.
  #
  # The merge holds each member's next span, its head, in an ordered set
  # keyed by where the span starts and then by the member's place in the
  # set, so that spans starting together keep the members' order. Taking
  # the earliest head and putting back that member's next is a logarithmic
  # step, where a list scanned for the earliest made merging a set of n
  # members n² steps.
  defp in_time_order(streams), do: merged(streams)

  @doc """
  Several sequences of placed spans, each in the order of time, as one
  sequence in that order, merged as they are asked for.
  """
  @spec merged([Enumerable.t()]) :: Enumerable.t()
  def merged([stream]), do: stream

  def merged(streams) do
    Stream.resource(
      fn -> streams |> Enum.with_index() |> Enum.reduce(:gb_sets.new(), &put_head/2) end,
      &earliest/1,
      fn _heads -> :ok end
    )
  end

  defp put_head({enumerable, place}, heads),
    do:
      put_next(
        &Enumerable.reduce(enumerable, &1, fn span, _ -> {:suspend, span} end),
        place,
        heads
      )

  # A sequence's next span, or its last, which a sequence that ends with it
  # (one taken to a count) gives as it halts, with no continuation.
  defp put_next(:done, _place, heads), do: heads

  defp put_next(continuation, place, heads) do
    case continuation.({:cont, nil}) do
      {:suspended, placed, next} -> :gb_sets.add({start_of(placed), place, placed, next}, heads)
      {:halted, %Placed{} = last} -> :gb_sets.add({start_of(last), place, last, :done}, heads)
      {_done_or_halted, _} -> heads
    end
  end

  defp earliest(heads) do
    if :gb_sets.is_empty(heads) do
      {:halt, heads}
    else
      {{_start, place, span, next}, rest} = :gb_sets.take_smallest(heads)
      {[span], put_next(next, place, rest)}
    end
  end

  defp plural_end(%Tempo{} = value), do: not singular?(value)
  defp plural_end(_duration_or_open), do: false

  # An end that holds a set is each of its values, with the other end as written (`2026Y6M{1,15}D/P1D`).
  defp each_end(span, side, plural, options) do
    with {:ok, values} <- members(plural, options) do
      {:ok, Stream.map(values, &end_span(span, side, &1, options))}
    end
  end

  defp end_span(%Tempo{form: {:span, from, to}} = span, side, value, options) do
    {from, to} = if side == :from, do: {value, to}, else: {from, value}
    {:ok, [resolved]} = placed(%{span | form: {:span, from, to}}, options)
    resolved
  end

  defp expanded_spans(%Tempo{form: {:value, units}} = value) do
    case Expand.expand(units, frame_of(value)) do
      {:ok, stream} ->
        {:ok, Stream.map(stream, fn units -> as_placed!(%{value | form: {:value, units}}) end)}

      {:error, reason} ->
        {:error, conversion(value, reason)}
    end
  end

  @doc """
  A value with no year placed on each period of a window: the window's units
  coarser than the value's own, before them. A window no coarser than the
  value places nothing, and the value is returned as it is. A span's ends
  are placed each, and a set's members.
  """
  @spec placed_in(Tempo.t(), Tempo.t() | nil) :: Tempo.t()
  # ── Placing in a window ───────────────────────────────────────────────

  def placed_in(value, window)

  def placed_in(
        %Tempo{form: {:value, units}} = value,
        %Tempo{form: {:value, window_units}} = window
      ) do
    case Unit.cyclic(units) do
      # Any year (`X*Y`) placed in a window is the window.
      [] -> %{value | form: {:value, window_units}}
      cyclic -> placed_under(value, cyclic, window_units, window)
    end
  end

  def placed_in(%Tempo{form: {:span, from, to}} = span, %Tempo{form: {:value, _}} = window) do
    placed = %{span | form: {:span, placed_end(from, window), placed_end(to, window)}}
    if placed == span, do: span, else: placed |> in_window(window) |> wrapped()
  end

  def placed_in(%Tempo{form: {:every, first, bound, rule}} = recurrence, window) do
    placed = %{
      recurrence
      | form: {:every, placed_in(first, window), placed_end(bound, window), rule}
    }

    if placed == recurrence, do: recurrence, else: in_window(placed, window)
  end

  # A set read from a stream is placed already: its members are come to one
  # at a time, and are not gone through to be placed.
  def placed_in(%Tempo{form: {kind, members}} = set, _window)
      when kind in [:all, :one] and not is_list(members),
      do: set

  def placed_in(%Tempo{form: {kind, members}} = set, %Tempo{form: {:value, _}} = window)
      when kind in [:all, :one] do
    placed = %{set | form: {kind, Enum.map(members, &placed_in(&1, window))}}
    if placed == set, do: set, else: in_window(placed, window)
  end

  def placed_in(value, _window), do: value

  defp placed_end(%Tempo{} = value, window), do: placed_in(value, window)
  defp placed_end(other, _window), do: other

  # A span that ran through its cycle's end (`T22H/T2H`, `12M/2M`) runs into
  # the next period once placed: its end is moved on by one cycle of the
  # coarsest unit the two ends differ in.
  defp wrapped(%Tempo{form: {:span, %Tempo{} = from, %Tempo{} = to}} = span) do
    case {extent(from), end_position(to)} do
      {{:ok, {start, _}}, {:ok, stop}}
      when is_integer(start) and is_integer(stop) and stop <= start ->
        moved = shifted(stop, cycle_of(differing(from, to)), frame_of(span), span)
        wrapped_to(span, from, to, moved)

      _ ->
        span
    end
  end

  defp wrapped(span), do: span

  defp wrapped_to(span, from, to, {:ok, moved}),
    do: %{span | form: {:span, from, value_at(moved, to, :end, span)}}

  defp wrapped_to(span, _from, _to, {:error, _}), do: span

  defp differing(%Tempo{form: {:value, a}}, %Tempo{form: {:value, b}}) do
    Enum.find_value(a, Unit.resolution(a), fn {unit, held} ->
      if Keyword.get(b, unit) != held, do: unit
    end)
  end

  defp cycle_of(unit) when unit in [:week, :day_of_week], do: %Duration{units: [week: 1]}
  defp cycle_of(unit) when unit in [:month, :day, :day_of_year], do: %Duration{units: [year: 1]}
  defp cycle_of(_clock), do: %Duration{units: [day: 1]}

  defp placed_under(value, cyclic, window_units, window) do
    coarsest = Unit.coarsest(cyclic)

    case Enum.take_while(window_units, fn {unit, _} -> Unit.compare(unit, coarsest) == :lt end) do
      [] -> value
      above -> in_window(%{value | form: {:value, Expand.filled(above ++ cyclic)}}, window)
    end
  end

  defp in_window(expression, window) do
    %{
      expression
      | calendar: window.calendar,
        zone: expression.zone || window.zone,
        shift: expression.shift || window.shift
    }
  end

  # ── A value as its one span ───────────────────────────────────────────

  @doc """
  The one span of a singular value (law 3): from the value, through the
  value when it is written to a calendar unit, to the next reading when it
  is written to a clock unit.
  """
  @spec as_span(Tempo.t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def as_span(%Tempo{form: {:value, _units}} = value) do
    with {:ok, placed} <- as_placed(value), do: {:ok, placed.span}
  end

  @doc "The one span of a singular value with its place: what `as_span/1` gives, placed as it is made."
  @spec as_placed(Tempo.t()) :: {:ok, Placed.t()} | {:error, Exception.t()}
  def as_placed(%Tempo{form: {:value, _units}} = value) do
    with {:ok, {start, stop}} <- extent(value),
         do: {:ok, Placed.new(span_of(value, stop), {start, stop})}
  end

  # The span a value names carries its metadata; its ends are points, and
  # carry none.
  def span_of(value, stop) do
    from = %{value | metadata: %{}}
    to = if clock_resolution?(from), do: clock_end(from, stop), else: from

    %Tempo{
      form: {:span, from, to},
      calendar: value.calendar,
      zone: value.zone,
      metadata: value.metadata
    }
  end

  defp as_placed!(value) do
    case as_placed(value) do
      {:ok, placed} -> placed
      {:error, exception} -> raise exception
    end
  end

  # The reading a clock-resolution value ends at, as a value of the same resolution and shift.
  defp clock_end(%Tempo{form: {:value, units}} = value, stop) do
    case frame(value) do
      {:cycle, coarsest} ->
        units = Scale.cycle_units(stop, coarsest, written_unit(units), value.calendar)
        %{value | form: {:value, units}, qualifications: nil}

      _line ->
        ended = %{
          value
          | form: {:value, clock_end_units(units, stop, value)},
            qualifications: nil
        }

        if begins_at?(ended, stop), do: ended, else: as_the_zone_shows(value, units, stop)
    end
  end

  # A reading built at a position begins there where its clock keeps one
  # offset about it: always on the floating line, and in a zone whose clock
  # does not change within a day of it. Elsewhere it is placed to see, since
  # the clock may skip or repeat where it would begin.
  defp begins_at?(%Tempo{zone: nil, shift: nil}, _position), do: true

  defp begins_at?(%Tempo{zone: %Zone{name: name} = zone, shift: nil} = value, position)
       when is_binary(name) do
    case Zone.steady_offset(zone, nil, position - @day, position + @day) do
      {:ok, _offset} -> true
      :changes -> placed_at?(value, position)
    end
  end

  defp begins_at?(value, position), do: placed_at?(value, position)

  defp placed_at?(value, position), do: match?({:ok, {^position, _}}, extent(value))

  # A reading that ends where its zone's clock changes may end on no reading
  # of its own unit at its own shift: the half hour from midnight that ends
  # as the clock goes back to midnight. Its end is then the reading the zone
  # shows there, with the offset it has there.
  defp as_the_zone_shows(%Tempo{zone: %Zone{name: name} = zone} = value, units, stop)
       when is_binary(name) do
    {wall, offset} = Zone.wall_of_utc(zone, nil, stop)
    shown = Walk.at_tick(wall, written_unit(units), value.calendar)
    %{value | form: {:value, shown}, qualifications: nil, shift: Zone.shift_of(offset)}
  end

  defp as_the_zone_shows(value, units, stop),
    do: %{value | form: {:value, clock_end_units(units, stop, value)}, qualifications: nil}

  defp clock_end_units(units, stop, value) do
    if own_axis?(units),
      do: Shift.rewritten(stop, units, frame_of(value)),
      else: Walk.at_tick(Walk.wall(stop, frame_of(value)), written_unit(units), value.calendar)
  end

  defp written_unit(units) do
    case Unit.resolution(units) do
      :microsecond -> {:microsecond, units |> Keyword.fetch!(:microsecond) |> elem(1)}
      unit -> unit
    end
  end

  # ── Written spans ─────────────────────────────────────────────────────

  @doc """
  A written span with its duration end made a value and an open end placed
  by the window, if one is given. A span of two values has neither, and is
  placed only when it is asked where it lies.
  """
  @spec resolved(Tempo.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def resolved(%Tempo{} = span, options) do
    with {:ok, placed} <- resolved_placed(span, options), do: {:ok, placed.span}
  end

  # A written span resolved and placed: a span of two values is placed once
  # here, and one with a duration or an open end at the positions resolving
  # it reckoned, an open end placed by no window staying open.
  defp resolved_placed(%Tempo{form: {:span, %Tempo{}, %Tempo{}}} = span, _options) do
    with {:ok, extent} <- extent(span), do: {:ok, Placed.new(span, extent)}
  end

  defp resolved_placed(%Tempo{form: {:span, from, to}} = span, options) do
    with {:ok, {start, stop}} <- extent(span),
         {:ok, from, from_at} <- resolved_end(from, start, stop, :from, span, options),
         {:ok, to, to_at} <- resolved_end(to, start, stop, :to, span, options) do
      {:ok, Placed.new(%{span | form: {:span, from, to}}, {from_at, to_at})}
    end
  end

  # Each end resolved, with the position it stands at: a value where it was,
  # a duration end at the position the span's extent gave it, an open end at
  # the window's edge where a window places it and at none otherwise.
  defp resolved_end(%Tempo{} = value, start, _stop, :from, _span, _options),
    do: {:ok, value, start}

  defp resolved_end(%Tempo{} = value, _start, stop, :to, _span, _options), do: {:ok, value, stop}

  # A duration end is the period, at the other end's resolution, where the span begins or ends.
  defp resolved_end(%Duration{} = duration, _start, stop, :to, span, _options) do
    %Tempo{form: {:span, from, _}} = span
    {:ok, value_at(stop, finer_model(from, duration), :end, span), stop}
  end

  defp resolved_end(%Duration{} = duration, start, _stop, :from, span, _options) do
    %Tempo{form: {:span, _, to}} = span
    {:ok, value_at(start, finer_model(to, duration), :start, span), start}
  end

  defp resolved_end(:open, _start, _stop, side, span, options),
    do: open_end(Keyword.get(options, :within), side, span)

  # An open end stays open, or is placed where the window begins or ends.
  defp open_end(nil, _side, _span), do: {:ok, :open, nil}

  defp open_end(%Tempo{} = window, side, %Tempo{form: {:span, from, to}} = span) do
    with :ok <- placeable(span),
         {:ok, {wstart, wstop}} <- extent(window) do
      placed_end(side, {wstart, wstop}, {from, to}, window, span)
    end
  end

  # A window open at the side it is asked for places nothing there.
  defp placed_end(:from, {nil, _wstop}, _ends, _window, _span), do: {:ok, :open, nil}
  defp placed_end(:to, {_wstart, nil}, _ends, _window, _span), do: {:ok, :open, nil}

  defp placed_end(:from, {wstart, _wstop}, {_from, to}, window, span),
    do: {:ok, value_at(wstart, model_of(to, window), :start, span), wstart}

  defp placed_end(:to, {_wstart, wstop}, {from, _to}, window, span),
    do: {:ok, value_at(wstop, model_of(from, window), :end, span), wstop}

  defp placeable(span) do
    case frame(span) do
      {:cycle, _} -> {:error, conversion(span, :needs_a_year)}
      _line -> :ok
    end
  end

  defp model_of(%Tempo{} = value, _window), do: value
  defp model_of(_other, %Tempo{form: {:value, _}} = window), do: window
  defp model_of(_other, %Tempo{form: {:span, from, to}}), do: first_value([from, to])

  # A duration of hours from a date ends at a time of day: the model takes the duration's finest unit when finer.
  defp finer_model(%Tempo{form: {:value, units}} = model, %Duration{units: duration_units}) do
    {finest, _} = List.last(duration_units)

    if Unit.compare(Unit.resolution(units), finest) == :lt and Unit.clock?(finest),
      do: %{model | form: {:value, Unit.date_units(units) ++ clock_minima(finest)}},
      else: %{model | form: {:value, Shift.finer_fraction(units, duration_units)}}
  end

  defp clock_minima(finest) do
    [:hour, :minute, :second, :microsecond]
    |> Enum.take_while(&(&1 != finest))
    |> Enum.map(&{&1, 0})
    |> Kernel.++(if finest == :microsecond, do: [microsecond: {0, 6}], else: [{finest, 0}])
  end

  @doc """
  An end of a span written 24:00 on a date, with nothing but zeros below the
  hour, read as ISO 8601-1 §5.3.2 (Amendment 1, 2022) has it: the next day's
  first instant, written as the next day's first unit at the resolution
  written. It is placed where the day's extent ends, so a day whose next
  midnight a zone skips ends where the next day begins. Anything else, and a
  24:00 with no date (on the day's cycle, where it stays), is returned as it is.
  """
  @spec next_day_from_end_of_day(term()) :: term()
  def next_day_from_end_of_day(%Tempo{form: {:value, units}} = value) do
    dated = Unit.date_units(units)

    if Unit.end_of_day?(units) and match?([_ | _], dated) do
      next_day_begun(value, dated, units)
    else
      value
    end
  end

  def next_day_from_end_of_day(other) do
    other
  end

  defp next_day_begun(value, dated, units) do
    day = %{value | form: {:value, dated}}

    case extent(day) do
      {:ok, {_start, stop}} when is_integer(stop) ->
        model = %{value | form: {:value, List.keyreplace(units, :hour, 0, {:hour, 0})}}
        value_at(stop, model, :start, value)

      _no_place ->
        value
    end
  end

  @doc """
  The value at a position, written to the resolution of a model value: a
  date end is the period that ends there.
  """
  @spec value_at(Scale.position(), Tempo.t(), :start | :end, Tempo.t()) :: Tempo.t()
  def value_at(position, %Tempo{form: {:value, _}} = model, kind, %Tempo{} = span)
      when is_integer(position) do
    case frame(span) do
      {:cycle, coarsest} -> cycle_value_at(position, model, kind, coarsest, span)
      _line -> line_value_at(position, model, kind, span)
    end
  end

  # On a cycle a position is read back through the cycle's units; a clock end at the cycle's end stays 24:00.
  defp cycle_value_at(position, %Tempo{form: {:value, units}} = model, kind, coarsest, span) do
    {:ok, length} = Scale.cycle_length(coarsest, span.calendar)

    ticks =
      if kind == :end and position == length, do: position, else: Integer.mod(position, length)

    ticks = if kind == :end and not clock_unit?(written_unit(units)), do: ticks - 1, else: ticks
    units = Scale.cycle_units(ticks, coarsest, written_unit(units), span.calendar)
    %{model | form: {:value, units}, qualifications: nil}
  end

  defp line_value_at(position, %Tempo{form: {:value, units}} = model, kind, span) do
    frame = frame_of(span)
    resolution = written_unit(units)

    units =
      cond do
        clock_unit?(resolution) and own_axis?(units) ->
          Shift.rewritten(position, units, frame)

        clock_unit?(resolution) ->
          Walk.at_tick(Walk.wall(position, frame), resolution, span.calendar)

        kind == :end ->
          # The day of the last tick before the end, read on the wall clock: so
          # an end at the midnight after a day the clock left out is the day before it.
          Walk.at_day(
            Integer.floor_div(Walk.wall(position - 1, frame), @day),
            day_unit(resolution),
            span.calendar
          )

        true ->
          Walk.at_day(
            Integer.floor_div(Walk.wall(position, frame), @day),
            day_unit(resolution),
            span.calendar
          )
      end

    value = %{model | form: {:value, units}, qualifications: nil, shift: model.shift}
    if clock_unit?(resolution), do: at_its_showing(value, position, frame), else: value
  end

  # A reading of the clock that a zone shows twice is written, at its second
  # showing, with the shift the clock has then: the end of the hour from 00:00
  # on a day the clock goes back from 02:00 is 01:00 at the second showing,
  # and with no shift it would be read as the first, an hour earlier.
  defp at_its_showing(%Tempo{shift: nil} = value, position, %{zone: zone}),
    do: Zone.at_showing(value, zone, position)

  defp at_its_showing(value, _position, _frame), do: value

  # A time of day on a week date or an ordinal date is written on that date's own axis.
  defp own_axis?(units),
    do: Keyword.has_key?(units, :week) or Keyword.has_key?(units, :day_of_year)

  @doc "Whether a unit, or a part of a second with its precision, is of the clock."
  @spec clock_unit?(Unit.t() | {:microsecond, 1..6}) :: boolean()
  def clock_unit?({:microsecond, _}), do: true
  def clock_unit?(unit), do: Unit.clock?(unit)

  defp day_unit(unit) when unit in [:day, :day_of_week, :day_of_year], do: :day
  defp day_unit(unit) when unit in [:month, :traditional_month, :season], do: :month
  defp day_unit(unit) when unit in [:year, :decade, :century, :week, :quarter], do: unit
  defp day_unit(_unit), do: :day

  @doc """
  The value at a position, written to a model value's resolution in a
  calendar and a zone: how a set operation writes a result's end from the
  operand end that stands there. A model of another calendar is written at
  day resolution, a month of one calendar being no month of another, as is
  a season, which begins and ends on a day; a clock resolution is kept.
  """
  @spec at_position(Scale.position(), Tempo.t(), :start | :end, module(), Zone.t() | nil) ::
          Tempo.t()
  def at_position(position, %Tempo{} = model, kind, calendar, zone) do
    model =
      if model.calendar == calendar and not season?(model), do: model, else: day_model(model)

    # In a named zone the ends are its wall readings, with no shift of their
    # own. With none, an end that an operand wrote in a zone has that zone no
    # longer and is written at UTC, so that it is the moment still.
    model = placed_model(model, zone)
    context = %Tempo{form: {:span, model, model}, calendar: calendar, zone: zone}
    %{value_at(position, model, kind, context) | calendar: calendar, zone: zone}
  end

  # A season is no unit a position is written at: its ends are days.
  defp season?(%Tempo{form: {:value, units}}), do: Keyword.has_key?(units, :season)
  defp season?(_model), do: false

  defp placed_model(%Tempo{} = model, %Zone{}), do: %{model | shift: nil}

  defp placed_model(%Tempo{zone: %Zone{}, shift: nil} = model, nil),
    do: %{model | zone: nil, shift: [hour: 0]}

  defp placed_model(%Tempo{} = model, nil), do: model

  defp day_model(%Tempo{form: {:value, units}} = model) do
    if Unit.clock?(Unit.resolution(units)),
      do: model,
      else: %{model | form: {:value, [year: 1, month: 1, day: 1]}}
  end

  # ── Windows ───────────────────────────────────────────────────────────

  @doc """
  A stream of spans, placed or not, with what ends before the `:within`
  window and what starts after it left out.
  """
  @spec windowed(Enumerable.t(), keyword()) :: Enumerable.t()
  def windowed(stream, options) do
    case window_extent(options[:within]) do
      {:ok, {start, stop}} -> stream |> dropped_before(start) |> taken_before(stop)
      _none -> stream
    end
  end

  @doc "The extent of a window, or `:none` for no window."
  @spec window_extent(Tempo.t() | nil) :: {:ok, extent()} | {:error, Exception.t()} | :none
  def window_extent(%Tempo{} = window), do: extent(window)
  def window_extent(_none), do: :none

  defp dropped_before(stream, nil), do: stream
  defp dropped_before(stream, start), do: Stream.drop_while(stream, &ends_by?(&1, start))

  defp taken_before(stream, nil), do: stream
  defp taken_before(stream, stop), do: Stream.take_while(stream, &starts_before?(&1, stop))

  @doc "Whether a span, placed or not, ends at or before a position; an open end does not."
  @spec ends_by?(Tempo.t() | Placed.t(), Scale.position()) :: boolean()
  def ends_by?(%Placed{stop: stop}, start) when is_integer(stop), do: stop <= start
  def ends_by?(%Placed{}, _start), do: false

  def ends_by?(occurrence, start) do
    case extent(occurrence) do
      {:ok, {_, stop}} when is_integer(stop) -> stop <= start
      _ -> false
    end
  end

  @doc "Whether a span, placed or not, starts before a position; an open start does."
  @spec starts_before?(Tempo.t() | Placed.t(), Scale.position()) :: boolean()
  def starts_before?(%Placed{start: start}, stop) when is_integer(start),
    do: Scale.compare(start, stop) == :lt

  def starts_before?(%Placed{start: nil}, _stop), do: true

  def starts_before?(occurrence, stop) do
    case extent(occurrence) do
      {:ok, {start, _}} -> Scale.compare(start, stop) == :lt
      _ -> false
    end
  end

  # ── Members ───────────────────────────────────────────────────────────

  @doc """
  What a plural expression is made of (law 6): the values a value with a set
  in a unit allows, the members of a set, the occurrences of a recurrence; a
  singular expression is its own one member.
  """
  @spec members(Tempo.t() | Duration.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def members(expression, options \\ [])

  def members(%Tempo{form: {:value, units}} = value, options) do
    cond do
      Keyword.has_key?(units, :selection) ->
        selected_values(value, options)

      not Unit.anchored?(units) and not is_nil(options[:within]) ->
        placed_members(value, options[:within], Keyword.delete(options, :within))

      Expand.one_span?(units) ->
        {:ok, [value]}

      true ->
        expanded_values(value)
    end
  end

  def members(%Tempo{form: {:all, members}}, _options) when is_list(members),
    do: {:ok, Enum.map(members, &member_value/1)}

  # A set read from a stream: its members as they come, those a window holds when one is given.
  def members(%Tempo{form: {:all, members}}, options), do: {:ok, windowed(members, options)}

  def members(%Tempo{form: {:one, members}}, _options), do: {:ok, members}

  def members(%Tempo{form: {:every, _, _, _}} = recurrence, options),
    do: spans(recurrence, options)

  def members(%Tempo{form: {:span, _, _}} = span, options), do: spans(span, options)

  def members(%Tempo{form: {:when, _, read_in: _}} = converted, options),
    do: spans(converted, options)

  def members(%Tempo{form: {:when, _, _}} = member, _options),
    do: {:error, conversion(member, :conditions)}

  def members(%Duration{} = duration, _options),
    do: {:error, conversion(duration, :bare_duration)}

  # A value with no year placed by a window, as `placed_spans/3` places it:
  # in the window's one value, or on each of the window's periods.
  defp placed_members(value, window, options) do
    placed = placed_in(value, window)

    if on_the_line?(window) and not Unit.anchored?(elem(placed.form, 1)),
      do: in_each_period(value, window, options),
      else: members(placed, options)
  end

  defp expanded_values(%Tempo{form: {:value, units}} = value) do
    case Expand.expand(units, frame_of(value)) do
      {:ok, stream} -> {:ok, Stream.map(stream, fn units -> %{value | form: {:value, units}} end)}
      {:error, reason} -> {:error, conversion(value, reason)}
    end
  end

  # ── Errors ────────────────────────────────────────────────────────────

  defp conversion(expression, {:no_such_value, _}),
    do: ConversionError.exception(value: expression, reason: :no_such_value)

  defp conversion(expression, reason),
    do: ConversionError.exception(value: expression, reason: reason)
end
