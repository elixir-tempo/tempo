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
  # a clock unit (law 9). A recurrence is its first span moved by n cadences
  # for each n, scaled rather than accumulated. A set is its members' spans.

  alias Tempo.Calendar
  alias Tempo.Conditions
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Expand
  alias Tempo.Limit
  alias Tempo.Scale
  alias Tempo.Season
  alias Tempo.Select
  alias Tempo.Shift
  alias Tempo.Unit
  alias Tempo.Walk
  alias Tempo.Zone

  @rule_units [
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

  @day Scale.ticks_per_day()

  # Where the start of a rule's next period is kept (`start_at/3`).
  @next_start {__MODULE__, :next_start}

  # The periods of a day or finer a rule tries one by one, selecting
  # nothing, before it looks ahead for where its parts next name a value.
  @quiet_periods 2

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

  defp first_value(ends), do: Enum.find(ends, &match?(%Tempo{}, &1)) || %Tempo{form: {:value, []}}
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

  # Where a written end ends: after its last unit for a date, at its reading for a time of day.
  defp end_position(%Tempo{} = to) do
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
    placed(moved * @day + Integer.mod(wall, @day), frame)
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

  defp placed(wall, %{zone: nil, shift: nil}), do: wall
  defp placed(wall, %{zone: zone, shift: shift}), do: Zone.utc_of_wall(zone, shift, wall)

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
  """
  @spec spans(Tempo.t() | Duration.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def spans(expression, options \\ [])

  def spans(%Duration{} = duration, _options), do: {:error, conversion(duration, :bare_duration)}

  def spans(%Tempo{form: {:value, units}} = value, options) do
    cond do
      Keyword.has_key?(units, :selection) ->
        with {:ok, values} <- selected_values(value, options), do: each_spans_of(values, [])

      not Unit.anchored?(units) and options[:within] != nil ->
        placed_spans(value, options[:within], Keyword.delete(options, :within))

      Expand.one_span?(units) ->
        with {:ok, span} <- as_span(value), do: {:ok, [span]}

      true ->
        expanded_spans(value)
    end
  end

  def spans(%Tempo{form: {:span, from, to}} = span, options) do
    case {plural_end(from), plural_end(to)} do
      {false, false} -> with {:ok, resolved} <- resolved(span, options), do: {:ok, [resolved]}
      {true, true} -> paired_ends(span, options)
      {true, false} -> each_end(span, :from, from, options)
      {false, true} -> each_end(span, :to, to, options)
    end
  end

  def spans(%Tempo{form: {:every, first, bound, rule}} = recurrence, options) do
    options = windowed_for(options, recurrence)

    if rule == nil,
      do: occurrences(first, bound, recurrence, options),
      else: rule_occurrences(first, bound, rule, recurrence, options)
  end

  # A set read from a stream gives its members' spans as they are asked for.
  # Its members are in order of start, so a window stops the reading.
  def spans(%Tempo{form: {:all, members}}, options) when not is_list(members) do
    {:ok, members |> Stream.flat_map(&member_stream(&1, options)) |> windowed(options)}
  end

  def spans(%Tempo{form: {:all, members}} = set, options) do
    case Enum.split_with(members, &match?({:except, _}, &1)) do
      {[], members} ->
        members |> member_spans(options) |> overlapping(set, options)

      {excluded, members} ->
        set
        |> excluded_spans(members, Enum.map(excluded, &elem(&1, 1)), options)
        |> overlapping(set, options)
    end
  end

  def spans(%Tempo{form: {:one, _}} = set, _options), do: {:error, conversion(set, :one_of)}

  # A domain filter: the members' spans in the years the filter names.
  def spans(%Tempo{form: {:when, member, years: filter}} = expression, options) do
    with {:ok, spans} <- spans(%{member | calendar: expression.calendar}, options),
         do: {:ok, Stream.filter(spans, &in_years?(&1, filter, expression.calendar))}
  end

  # A rule converted to another calendar (`Tempo.to_calendar/2` of a rule
  # with no end): selected in its own calendar, each span read in this one.
  def spans(%Tempo{form: {:when, member, read_in: calendar}} = converted, options) do
    with {:ok, spans} <- spans(member, options) do
      {:ok, Stream.map(spans, &read_in(&1, calendar, converted.metadata))}
    end
  end

  def spans(%Tempo{form: {:when, _, _}} = member, options) do
    if Conditions.conditional?(member),
      do: Conditions.resolve([member], [], options),
      else: {:error, conversion(member, :conditions)}
  end

  defp read_in(%Tempo{form: {:span, from, to}} = span, calendar, metadata) do
    {:ok, {start, stop}} = extent(span)

    %Tempo{
      form:
        {:span, at_position(start, from, :start, calendar, span.zone),
         at_position(stop, to, :end, calendar, span.zone)},
      calendar: calendar,
      zone: span.zone,
      metadata: Map.merge(metadata, span.metadata)
    }
  end

  defp member_stream(member, options) do
    case spans(member, options) do
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
        {:ok, Stream.filter(spans, &overlaps_window?(extent(&1), start, stop))}

      _none ->
        {:ok, spans}
    end
  end

  defp overlapping(error, _set, _options), do: error

  defp overlaps_window?({:ok, {s, e}}, start, stop) when is_integer(s) and is_integer(e),
    do: (stop == nil or s < stop) and (start == nil or e > start)

  defp overlaps_window?(_extent, _start, _stop), do: true

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
          {:ok, Enum.sort_by(others ++ conditional, &start_position/1)}
        end
    end
  end

  defp widened(options) do
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

  defp start_position(span) do
    case extent(span) do
      {:ok, {start, _}} when is_integer(start) -> start
      _ -> 0
    end
  end

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
        with {:ok, spans} <- spans(window, []),
             do: {:ok, Enum.map(spans, &%{&1 | metadata: value.metadata})}

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

  # A value with no year placed by a window: in it, where the window is one
  # value it fits under, and else on each of the window's periods, as
  # `Tempo.select/3` selects it there (`4M` in `2026/2027`, each April).
  defp placed_spans(value, window, options) do
    placed = placed_in(value, window)

    if on_the_line?(window) and not Unit.anchored?(elem(placed.form, 1)),
      do:
        with(
          {:ok, values} <- in_each_period(value, window, options),
          do: each_spans_of(values, [])
        ),
      else: spans(placed, options)
  end

  defp on_the_line?(%Tempo{} = window), do: not match?({:cycle, _}, frame(window))
  defp on_the_line?(_none), do: false

  defp in_each_period(%Tempo{form: {:value, units}} = value, window, options) do
    with {:ok, periods} <- spans(window, []),
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

  # ── Repeat rules ──────────────────────────────────────────────────────

  # Each repeating interval is a period the rule selects within; the units of
  # the start finer than the rule's finest unit are inherited (§13.6.3); a
  # count counts the occurrences selected, an until bounds them.
  defp rule_occurrences(
         %Tempo{form: {:span, from, _to}} = first,
         bound,
         rule,
         recurrence,
         options
       ) do
    with {:ok, periods} <- rule_periods(aligned(first), from, recurrence, options),
         {:ok, until} <- until_position(bound),
         {:ok, excluded} <- exclusions(from, options) do
      parts = with_inherited(rule, inherited_units(from, rule, first))
      stepped = stepped_first(first, range_start(from))
      walk = %{first: stepped, parts: parts, begins: start_of_rule(from), options: options}

      stream =
        periods
        |> selected_in(walk, first_period(periods, bound, parts, from, options))
        |> left_out(excluded)
        |> to_range_end(from)
        |> in_range_years(from, first.calendar)
        |> Stream.dedup_by(&landing/1)
        |> Stream.map(fn {occurrence, extent} ->
          {%{occurrence | metadata: Map.merge(recurrence.metadata, occurrence.metadata)}, extent}
        end)
        |> bounded(bound, until, options)
        |> Stream.map(&elem(&1, 0))

      {:ok, stream}
    end
  end

  # A domain's members are each selected in.
  defp selected_in({:each, periods}, walk, _first_step) do
    periods
    |> Stream.map(&eligible(&1, walk.first))
    |> Stream.flat_map(&picked_in(&1, period_extent(&1), walk))
  end

  # A cadence's periods are stepped through by number, so that a run of
  # periods the rule selects nothing in is passed over to the next value its
  # parts name, and a rule that selects nothing in a whole cycle of its
  # calendar's years comes to an end.
  defp selected_in({:steps, period_at}, walk, first_step) do
    walk = Map.merge(walk, %{period_at: period_at, horizon: horizon(walk)})

    {first_step, nil}
    |> Stream.unfold(fn {k, quiet_since} ->
      {period, extent} = eligible_at(period_at.({:with_extent, k}), walk.first)
      step(picked_in(period, extent, walk), {period, extent}, k, quiet_since, walk)
    end)
    |> Stream.flat_map(& &1)
  end

  # What a period selects, from where the rule begins: a period that begins
  # there or later selects only from there, and the first is filtered. Each
  # occurrence goes on with its extent, reckoned once as its span is made.
  defp picked_in(period, {start, _stop} = extent, %{parts: parts, begins: begins} = walk)
       when start >= begins,
       do: in_rule_period(period, parts, [extent: extent] ++ walk.options)

  defp picked_in(period, extent, %{parts: parts, begins: begins, options: options}) do
    options = if extent, do: [extent: extent] ++ options, else: options

    period
    |> in_rule_period(parts, options)
    |> Enum.filter(fn {_occurrence, {start, _stop}} -> start >= begins end)
  end

  defp period_extent(period) do
    case extent(period) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> {start, stop}
      _ -> nil
    end
  end

  defp step([_ | _] = picked, _period, k, _quiet_since, _walk), do: {picked, {k + 1, nil}}

  # A day or a finer period that selects nothing is followed by the next,
  # for a few: a weekend in a daily rule of weekdays is passed over a day at
  # a time, each day's weekday asked of it. A longer quiet, and a quiet of
  # coarser periods, is passed over to where the parts next name a value.
  defp step([], {period, extent}, k, quiet_since, walk) do
    {start, stop} = extent || {0, 0}
    {since, quiet_from} = quiet_since || {start, k}

    cond do
      start - since > walk.horizon -> nil
      k - quiet_from < quiet_periods(walk.first) -> {[], {k + 1, {since, quiet_from}}}
      true -> stepped_on(next_named(stop, period, walk), k, {since, quiet_from}, walk)
    end
  end

  defp stepped_on(nil, _k, _quiet_since, _walk), do: nil

  defp stepped_on(tick, k, quiet_since, walk),
    do: {[], {index_at(tick, walk.period_at, k, k + 1), quiet_since}}

  defp quiet_periods(first),
    do: if(cadence_unit(first) in [:day, :hour, :minute, :second], do: @quiet_periods, else: 0)

  defp ends_of(period) do
    case extent(period) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> {start, stop}
      _ -> {0, 0}
    end
  end

  # A count counts from the rule's start; any other bound's occurrences are
  # looked for from the period the window begins in.
  defp first_step({:steps, period_at}, bound, options) when not is_integer(bound) do
    case window_extent(options[:within]) do
      {:ok, {start, _}} when is_integer(start) -> index_at(start, period_at, 0, 0)
      _none -> 0
    end
  end

  defp first_step(_periods, _bound, _options), do: 0

  # The period a rule's occurrences are looked for from: the window's, or
  # the one before it where an occurrence may run on into the window, and
  # never one before a domain's first.
  defp first_period(periods, bound, parts, from, options) do
    first = first_step(periods, bound, options) - carried_back(bound, parts)
    if range_start(from), do: max(first, 0), else: first
  end

  # A selection that opens a window (a day observed on the Monday after, a
  # holiday of several days from 19 December) may carry an occurrence into
  # the next period: a window's occurrences are looked for from the period
  # before it, and those before it dropped. A count counts from the rule's
  # start, which no period before reaches.
  defp carried_back(count, _parts) when is_integer(count), do: 0

  defp carried_back(_bound, parts) do
    if Keyword.has_key?(with_nested(parts), :window), do: 1, else: 0
  end

  # The number of the last period that begins by a position, no less than a
  # least number: reckoned from the length of a period and then stepped to.
  defp index_at(tick, period_at, k, least) do
    start = start_position(period_at.(k))
    length = max(start_position(period_at.(k + 1)) - start, 1)

    (k + div(tick - start, length))
    |> max(least)
    |> back_to(tick, period_at, least)
    |> on_to(tick, period_at)
  end

  defp back_to(n, tick, period_at, least) when n > least do
    if start_position(period_at.(n)) > tick,
      do: back_to(n - 1, tick, period_at, least),
      else: n
  end

  defp back_to(n, _tick, _period_at, _least), do: n

  defp on_to(n, tick, period_at) do
    if start_position(period_at.(n + 1)) <= tick, do: on_to(n + 1, tick, period_at), else: n
  end

  # Where the rule's parts next name a value from a position on, whatever
  # the cadence: looked for a year, a month or a day at a time, as far as the
  # horizon. A nested selection, or a set of them, is made in the period as a whole (the fifth
  # Sunday of a month, at nine), so its parts are looked for in the next period.
  defp next_named(tick, period, walk) do
    parts = picking(walk.parts)

    # A skip gives a period that names nothing a day of its own, so no
    # period is passed over to the next that names one.
    every_period? = Enum.any?([:selection, :all, :skip], &Keyword.has_key?(parts, &1))

    case {every_period?, Select.probe(parts)} do
      {true, _probe} -> tick
      {false, nil} -> nil
      {false, probe} -> named_from(tick, tick, probe, period, walk)
    end
  end

  defp named_from(tick, from, {unit, search} = probe, period, walk) do
    span = %{period | form: {:value, Shift.period_units(tick, unit, frame_of(period))}}
    {_start, stop} = ends_of(span)

    cond do
      found = first_named(span, search, from, walk.options) -> found
      stop <= tick or stop - from > walk.horizon -> nil
      true -> named_from(stop, from, probe, period, walk)
    end
  end

  # A window may carry what it selects back out of its period, so where the
  # parts open one, a period in which anything is selected is the place.
  defp first_named(span, search, from, options) do
    case {Select.in_period(span, search, options), Keyword.has_key?(search, :selection)} do
      {{:ok, [_ | _]}, true} ->
        max(from, start_position(span))

      {{:ok, picked}, _windowed?} ->
        picked
        |> Enum.map(&start_position/1)
        |> Enum.filter(&(&1 >= from))
        |> Enum.min(fn -> nil end)

      {{:error, _}, _windowed?} ->
        nil
    end
  end

  # How long a rule may select nothing before it has no more to select. One
  # that names times of day alone has named them all in two years, a zone's
  # clock changing by the year. Any other has in a cycle of its calendar's
  # years, in which every date and weekday it could name comes round, or in
  # a thousand years in a calendar with no cycle.
  defp horizon(%{parts: parts, first: %Tempo{calendar: calendar}}) do
    if Enum.all?(Keyword.keys(picking(parts)), &(&1 in [:hour, :minute, :second, :instance])),
      do: 2 * 366 * @day,
      else: (Calendar.years_in_cycle(calendar) || 1000) * 366 * @day
  end

  # A rule's repeating intervals are whole periods of its cadence's unit, the
  # first the one its start is in (RFC 5545's weeks and months, ISO 8601-2's
  # eligible intervals); occurrences before the start are not counted.
  defp aligned(
         %Tempo{
           form:
             {:span, %Tempo{form: {:value, _}} = from, %Duration{units: [{unit, _}]} = cadence}
         } = first
       ) do
    case Shift.trunc(from, unit) do
      {:ok, truncated} -> %{first | form: {:span, truncated, cadence}}
      {:error, _} -> first
    end
  end

  defp aligned(first), do: first

  # Of a repeating interval of several units (every second week), the first
  # unit is the one the rule selects in, as RFC 5545's INTERVAL has it.
  defp eligible(
         %Tempo{form: {:span, %Tempo{} = from, _}} = period,
         %Tempo{form: {:span, %Tempo{form: {:value, _}}, %Duration{units: [{unit, n}]}}}
       )
       when n > 1,
       do: %{period | form: {:span, from, %Duration{units: [{unit, 1}]}}}

  defp eligible(period, _first), do: period

  # A period whose extent its building gave keeps it, unless the rule
  # selects in the first unit of a longer repeat.
  defp eligible_at({period, extent}, first) do
    case eligible(period, first) do
      ^period when extent != nil -> {period, extent}
      narrowed -> {narrowed, period_extent(narrowed)}
    end
  end

  defp start_of_rule(%Tempo{form: {:value, _}} = from) do
    case extent(from) do
      {:ok, {start, _}} when is_integer(start) -> start
      _ -> 0
    end
  end

  defp start_of_rule(_from), do: 0

  # The start's finer units join the parts that pick the occurrences: the
  # rule's own, or those of a selection whose windows are the occurrences.
  defp with_inherited(rule, []), do: rule

  defp with_inherited([selection: parts, window: window], inherited),
    do: [selection: with_inherited(parts, inherited), window: window]

  defp with_inherited(rule, inherited), do: rule ++ inherited

  defp picking(selection: parts, window: _window), do: picking(parts)
  defp picking(rule), do: rule

  # A domain (a set in the start's place) gives its members as the periods;
  # a start gives the cadence's repeating intervals.
  defp rule_periods(first, %Tempo{form: form} = domain, recurrence, options)
       when elem(form, 0) in [:all, :when] do
    cond do
      only_exclusions?(domain) or every_year?(domain) ->
        rule_periods(%{first | form: put_elem(first.form, 1, :open)}, :open, recurrence, options)

      match?(%Tempo{}, range_start(domain)) ->
        steps(aligned(stepped_first(first, range_start(domain))), recurrence)

      true ->
        each_member(domain, first, recurrence, options)
    end
  end

  # A rule with no start (`R/../P1Y/F…`) has the cadence's periods the window runs through.
  defp rule_periods(
         %Tempo{form: {:span, :open, %Duration{units: [{unit, n}]}}} = first,
         :open,
         recurrence,
         options
       ) do
    case window_extent(options[:within]) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
        # The window says where; the periods are of the rule's own calendar.
        frame = %{frame_of(options[:within]) | calendar: first.calendar}
        anchor = %{first | form: {:value, Shift.period_units(start, unit, frame)}}
        step = %Duration{units: [{unit, n}]}
        steps(%{first | form: {:span, anchor, step}}, recurrence)

      _none ->
        {:error, conversion(recurrence, :unbounded)}
    end
  end

  defp rule_periods(first, _from, recurrence, _options), do: steps(first, recurrence)

  # A domain that is one range (`{1848Y..}`) is stepped through from its
  # start by the cadence, to its end.
  defp stepped_first(first, nil), do: first
  defp stepped_first(first, %Tempo{} = start), do: %{first | form: put_elem(first.form, 1, start)}

  defp range_start(%Tempo{form: {:all, [%Tempo{form: {:span, %Tempo{} = from, _to}}]}}), do: from
  # A filter of years on a range (`{2000Y..}e`) is of the range's periods.
  defp range_start(%Tempo{form: {:when, %Tempo{} = inner, [years: _filter]}}),
    do: range_start(inner)

  defp range_start(_domain), do: nil

  defp in_range_years(stream, %Tempo{form: {:when, %Tempo{} = inner, [years: filter]}}, calendar) do
    if range_start(inner) != nil or every_year?(inner),
      do: Stream.filter(stream, &in_years?(elem(&1, 0), filter, calendar)),
      else: stream
  end

  defp in_range_years(stream, _from, _calendar), do: stream

  defp to_range_end(
         stream,
         %Tempo{form: {:all, [%Tempo{form: {:span, %Tempo{}, %Tempo{} = to}}]}}
       ) do
    case end_position(to) do
      {:ok, stop} when is_integer(stop) ->
        Stream.take_while(stream, fn {_occurrence, {start, _}} -> start < stop end)

      _ ->
        stream
    end
  end

  defp to_range_end(stream, %Tempo{form: {:when, %Tempo{} = inner, [years: _filter]}}),
    do: to_range_end(stream, inner)

  defp to_range_end(stream, _from), do: stream

  # A count counts from the domain's first member, so a counted recurrence
  # takes all of a domain that has an end, and the window the occurrences.
  defp each_member(domain, first, recurrence, options) do
    options = domain_window(options, recurrence)

    with {:ok, members} <- spans(domain, options) do
      periods = Stream.flat_map(members, &cadence_periods(&1, first, options))
      {:ok, {:each, on_steps(periods, domain_start(domain), first, recurrence)}}
    end
  end

  # A range in a domain (`{..2019Y,2021Y..}`) is each period of the cadence
  # it holds, from the first the window reaches, as a domain of one range is;
  # a year or a set of years is its periods already.
  defp cadence_periods(
         %Tempo{form: {:span, _from, _to}} = range,
         %Tempo{form: {:span, _domain, %Duration{units: [{unit, _n}]}}},
         options
       ) do
    case walk(range, unit, []) do
      {:ok, periods} -> from_window(periods, options[:within])
      {:error, _} -> [range]
    end
  end

  defp cadence_periods(member, _first, _options), do: [member]

  defp from_window(periods, nil), do: periods

  defp from_window(periods, window) do
    case window_extent(window) do
      {:ok, {start, _stop}} when is_integer(start) ->
        Stream.drop_while(periods, &ends_by?(&1, start))

      _none ->
        periods
    end
  end

  # A cadence of several units steps through a domain from its first period:
  # `R/{1848Y..}/P4Y/F…` is every fourth year from 1848.
  defp on_steps(
         members,
         %Tempo{} = start,
         %Tempo{form: {:span, _domain, %Duration{units: [{_unit, n}]} = cadence}} = first,
         recurrence
       )
       when n > 1 do
    case steps(%{first | form: {:span, start, cadence}}, recurrence) do
      {:ok, {:steps, period_at}} -> Stream.filter(members, &on_step?(&1, period_at))
      _no_steps -> members
    end
  end

  defp on_steps(members, _start, _first, _recurrence), do: members

  # The domain's members a window reaches: every one where the rule is
  # counted, as the count counts from the first; and the year before the
  # window too where an occurrence may run on into it from the period before
  # (a holiday from 19 December into January).
  defp domain_window(options, %Tempo{form: {:every, _first, count, _rule}})
       when is_integer(count),
       do: Keyword.delete(options, :within)

  defp domain_window(options, %Tempo{form: {:every, _first, bound, rule}}) do
    if carried_back(bound, rule) == 1, do: widened(options), else: options
  end

  defp on_step?(member, period_at) do
    start = start_position(member)
    start_position(period_at.(index_at(start, period_at, 0, 0))) == start
  end

  # Where a domain's first period begins, if it has a first.
  defp domain_start(%Tempo{form: {:all, [first | _]}}), do: first_start(first)
  defp domain_start(_domain), do: nil

  defp first_start(%Tempo{form: {:span, %Tempo{} = from, _to}}), do: from

  defp first_start(%Tempo{form: {:value, _}} = value) do
    case spans(value, []) do
      {:ok, spans} -> spans |> Enum.take(1) |> Enum.map(&elem(&1.form, 1)) |> List.first()
      {:error, _} -> nil
    end
  end

  defp first_start(_member), do: nil

  # A domain of exclusions alone (`R/^2022Y/P1Y/F…`) names no period of its
  # own: the window gives the periods, and what the exclusions name is left out.
  defp only_exclusions?(%Tempo{form: {:all, [_ | _] = members}}) when is_list(members),
    do: Enum.all?(members, &match?({:except, _}, &1))

  defp only_exclusions?(_domain), do: false

  # Every year (`R/..e/…`), the years a filter keeps of those a window gives.
  defp every_year?(%Tempo{form: {:when, inner, [years: _filter]}}), do: every_year?(inner)
  defp every_year?(%Tempo{form: {:span, :open, :open}}), do: true
  defp every_year?(_domain), do: false

  defp left_out(stream, []), do: stream

  defp left_out(stream, excluded),
    do: Stream.reject(stream, fn {_occurrence, extent} -> excluded?({:ok, extent}, excluded) end)

  # The extents a domain of exclusions alone leaves out. One that cannot be
  # given its spans is the error, and no occurrence is answered as if
  # nothing were left out.
  defp exclusions(%Tempo{form: {:all, members}} = domain, options) do
    if only_exclusions?(domain) do
      excluded = %{domain | form: {:all, Enum.map(members, &elem(&1, 1))}}

      with {:ok, spans} <- spans(excluded, options),
           {:ok, spans} <- Limit.take(spans, excluded),
           do: {:ok, Enum.map(spans, &extent/1)}
    else
      {:ok, []}
    end
  end

  defp exclusions(_domain, _options), do: {:ok, []}

  # The cadence's periods by number: the first, and each a cadence on.
  defp steps(%Tempo{form: {:span, from, to}} = first, recurrence) do
    with {:ok, [base]} <- spans(first, []),
         {:ok, cadence} <- cadence(from, to, base, recurrence) do
      # `{:with_extent, k}` gives the period with the extent it was built
      # from, where that is known, so that a walk need not reckon it again;
      # the start of the period after it, which that needs, is kept for it.
      walk = make_ref()

      # Every period is the first moved by whole cadences, so where the
      # first starts is placed once for the walk and not at every step.
      first_start = start_extent(base)

      {:ok,
       {:steps,
        fn
          {:with_extent, k} ->
            occurrence_at(
              base,
              {from, to},
              cadences(cadence, k),
              {recurrence, walk, k, first_start}
            )

          k ->
            occurrence(base, {from, to}, cadences(cadence, k), recurrence)
        end}}
    end
  end

  defp inherited_units(%Tempo{form: {:value, units}} = from, rule, first) do
    rule = picking(rule)

    finest =
      case rule |> with_nested() |> Keyword.take(@rule_units) do
        [] -> :day
        parts -> parts |> Unit.resolution() |> Unit.grain() |> finer_of(cadence_unit(first))
      end

    units
    |> Enum.filter(fn {unit, _} ->
      Unit.compare(Unit.grain(unit), finest) == :gt and not Keyword.has_key?(rule, unit)
    end)
    |> weekday_of_week(rule, from)
  end

  defp inherited_units(_from, _rule, _first), do: []

  # What a rule names includes what a selection within it names: the last
  # Sunday of October names a day, and takes no day from the start.
  defp with_nested(rule) do
    Enum.flat_map(rule, fn
      {:selection, nested} -> with_nested(nested)
      {:all, each} -> Enum.flat_map(each, &with_nested/1)
      part -> [part]
    end)
  end

  # A rule whose parts are coarser than its cadence keeps the periods they
  # name (`FREQ=DAILY;BYMONTH=1` is each day of January), so its start gives
  # it only what is finer than a period.
  defp finer_of(unit, nil), do: unit

  defp finer_of(unit, cadence),
    do: if(Unit.compare(cadence, unit) == :gt, do: cadence, else: unit)

  defp cadence_unit(%Tempo{form: {:span, _from, %Duration{units: [{unit, _}]}}})
       when unit in [:year, :month, :day, :hour, :minute, :second],
       do: unit

  defp cadence_unit(_first), do: nil

  # A rule that names a week and no day of it takes the day of the week its
  # start falls on, where a rule of months takes the start's day of the month.
  defp weekday_of_week(inherited, rule, from) do
    weekday = Tempo.day_of_week(from)

    if Keyword.has_key?(rule, :week) and not Keyword.has_key?(rule, :day_of_week) and
         is_integer(weekday),
       do: [{:day_of_week, weekday} | Keyword.delete(inherited, :day)],
       else: inherited
  end

  defp in_rule_period(period, parts, options) do
    case Select.in_period(period, parts, options) do
      {:ok, picked} -> Enum.flat_map(picked, &with_extent(&1, period, options[:extent]))
      {:error, _} -> []
    end
  end

  # A span of two values picked whole is where the walk placed it.
  defp with_extent(%Tempo{form: {:span, %Tempo{}, %Tempo{}}} = period, period, {_, _} = extent),
    do: [{period, extent}]

  defp with_extent(picked, _period, _extent), do: with_extent(picked)

  # An occurrence and its extent: a value picked is the span it covers.
  defp with_extent(%Tempo{form: {:value, _}} = value) do
    case extent(value) do
      {:ok, {start, stop} = extent} when is_integer(start) and is_integer(stop) ->
        [{span_of(value, stop), extent}]

      {:error, exception} ->
        raise exception
    end
  end

  defp with_extent(picked) do
    occurrence = as_span_or_self(picked)

    case extent(occurrence) do
      {:ok, {start, stop} = extent} when is_integer(start) and is_integer(stop) ->
        [{occurrence, extent}]

      _open ->
        []
    end
  end

  # A window from a selected value, with its end written as a value.
  defp as_span_or_self(%Tempo{form: {:span, %Tempo{}, %Duration{}}} = span) do
    case resolved(span, []) do
      {:ok, resolved} -> resolved
      {:error, _} -> span
    end
  end

  defp as_span_or_self(other), do: other

  # ── Exclusions and domain filters ─────────────────────────────────────

  # The members' spans with what an excluded member covers taken out: a
  # member within one is left out, and one an excluded member falls inside
  # is cut around it, each piece written to the member's own resolution
  # (`{2017Y..,^2020Y}` is 2017 to 2019, and 2021 on).
  defp excluded_spans(set, members, excluded, options) do
    with {:ok, kept} <- spans(%{set | form: {:all, members}}, options),
         {:ok, out} <- spans(%{set | form: {:all, excluded}}, options),
         {:ok, out} <- Limit.take(out, set) do
      out = out |> Enum.flat_map(&bounded_extent/1) |> Enum.sort()
      {:ok, Stream.flat_map(kept, &cut_around(&1, out))}
    end
  end

  defp bounded_extent(span) do
    case extent(span) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> [{start, stop}]
      _open -> []
    end
  end

  defp cut_around(span, out) do
    case extent(span) do
      {:ok, {start, stop}} when is_integer(start) -> pieces(span, {start, stop}, out)
      _ -> [span]
    end
  end

  defp pieces(span, whole, out) do
    case left_after(whole, out) do
      [^whole] -> [span]
      left -> Enum.map(left, &piece(span, &1))
    end
  end

  # What of a stretch no excluded stretch covers; a stop of nil has no end.
  defp left_after({start, stop}, out) do
    {left, from} =
      Enum.reduce(out, {[], start}, fn {s, e}, {left, from} ->
        cond do
          e <= from or (stop != nil and s >= stop) -> {left, from}
          s > from -> {[{from, s} | left], e}
          true -> {left, max(from, e)}
        end
      end)

    if stop == nil or from < stop,
      do: Enum.reverse([{from, stop} | left]),
      else: Enum.reverse(left)
  end

  defp piece(%Tempo{form: {:span, from, to}} = span, {start, stop}) do
    model = if match?(%Tempo{form: {:value, _}}, from), do: from, else: to
    first = at_position(start, model, :start, span.calendar, span.zone)
    last = if stop == nil, do: to, else: at_position(stop, model, :end, span.calendar, span.zone)
    %{span | form: {:span, first, last}}
  end

  defp excluded?({:ok, {start, stop}}, out) when is_integer(start) and is_integer(stop) do
    Enum.any?(out, fn
      {:ok, {s, e}} when is_integer(s) and is_integer(e) -> s <= start and stop <= e
      _ -> false
    end)
  end

  defp excluded?(_extent, _out), do: false

  defp in_years?(%Tempo{form: {:span, %Tempo{form: {:value, units}}, _}}, filter, calendar) do
    case Keyword.get(units, :year) do
      year when is_integer(year) -> year_in?(year, filter, calendar)
      _ -> false
    end
  end

  defp in_years?(_span, _filter, _calendar), do: false

  defp year_in?(year, :even, _calendar), do: rem(year, 2) == 0
  defp year_in?(year, :odd, _calendar), do: rem(year, 2) != 0
  defp year_in?(year, :leap, calendar), do: Calendar.leap_year?(calendar, year)
  defp year_in?(year, :common, calendar), do: not Calendar.leap_year?(calendar, year)

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
      case spans(member, options) do
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
       when map_size(metadata) > 0,
       do: Stream.map(stream, &%{&1 | metadata: Map.merge(metadata, &1.metadata)})

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
  defp in_time_order([stream]), do: stream

  defp in_time_order(streams) do
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

  defp put_next(continuation, place, heads) do
    case continuation.({:cont, nil}) do
      {:suspended, span, next} -> :gb_sets.add({start_position(span), place, span, next}, heads)
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
    {:ok, [resolved]} = spans(%{span | form: {:span, from, to}}, options)
    resolved
  end

  defp expanded_spans(%Tempo{form: {:value, units}} = value) do
    case Expand.expand(units, frame_of(value)) do
      {:ok, stream} ->
        {:ok, Stream.map(stream, fn units -> as_span!(%{value | form: {:value, units}}) end)}

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
    with {:ok, {_start, stop}} <- extent(value), do: {:ok, span_of(value, stop)}
  end

  # The span a value names carries its metadata; its ends are points, and
  # carry none.
  defp span_of(value, stop) do
    from = %{value | metadata: %{}}
    to = if clock_resolution?(from), do: clock_end(from, stop), else: from

    %Tempo{
      form: {:span, from, to},
      calendar: value.calendar,
      zone: value.zone,
      metadata: value.metadata
    }
  end

  defp as_span!(value) do
    case as_span(value) do
      {:ok, span} -> span
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

  defp begins_at?(%Tempo{} = value, position), do: match?({:ok, {^position, _}}, extent(value))

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

  # A written span with its duration end made a value and an open end placed by the window, if one is given.
  # A span of two values has neither, and is placed only when it is asked where it lies.
  defp resolved(%Tempo{form: {:span, %Tempo{}, %Tempo{}}} = span, _options), do: {:ok, span}

  defp resolved(%Tempo{form: {:span, from, to}} = span, options) do
    with {:ok, {start, stop}} <- extent(span),
         {:ok, from} <- resolved_end(from, start, stop, :from, span, options),
         {:ok, to} <- resolved_end(to, start, stop, :to, span, options) do
      {:ok, %{span | form: {:span, from, to}}}
    end
  end

  defp resolved_end(%Tempo{} = value, _start, _stop, _side, _span, _options), do: {:ok, value}

  # A duration end is the period, at the other end's resolution, where the span begins or ends.
  defp resolved_end(%Duration{} = duration, _start, stop, :to, span, _options) do
    %Tempo{form: {:span, from, _}} = span
    {:ok, value_at(stop, finer_model(from, duration), :end, span)}
  end

  defp resolved_end(%Duration{} = duration, start, _stop, :from, span, _options) do
    %Tempo{form: {:span, _, to}} = span
    {:ok, value_at(start, finer_model(to, duration), :start, span)}
  end

  defp resolved_end(:open, _start, _stop, side, span, options),
    do: open_end(Keyword.get(options, :within), side, span)

  # An open end stays open, or is placed where the window begins or ends.
  defp open_end(nil, _side, _span), do: {:ok, :open}

  defp open_end(%Tempo{} = window, side, %Tempo{form: {:span, from, to}} = span) do
    with :ok <- placeable(span),
         {:ok, {wstart, wstop}} <- extent(window) do
      placed_end(side, {wstart, wstop}, {from, to}, window, span)
    end
  end

  # A window open at the side it is asked for places nothing there.
  defp placed_end(:from, {nil, _wstop}, _ends, _window, _span), do: {:ok, :open}
  defp placed_end(:to, {_wstart, nil}, _ends, _window, _span), do: {:ok, :open}

  defp placed_end(:from, {wstart, _wstop}, {_from, to}, window, span),
    do: {:ok, value_at(wstart, model_of(to, window), :start, span)}

  defp placed_end(:to, {_wstart, wstop}, {from, _to}, window, span),
    do: {:ok, value_at(wstop, model_of(from, window), :end, span)}

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
      else: model
  end

  defp clock_minima(finest) do
    [:hour, :minute, :second, :microsecond]
    |> Enum.take_while(&(&1 != finest))
    |> Enum.map(&{&1, 0})
    |> Kernel.++(if finest == :microsecond, do: [microsecond: {0, 6}], else: [{finest, 0}])
  end

  # The value at a position, written to the resolution of a model value: a date end is the period that ends there.
  defp value_at(position, %Tempo{form: {:value, _}} = model, kind, %Tempo{} = span)
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
  defp at_its_showing(%Tempo{shift: nil} = value, position, %{zone: %Zone{name: name} = zone})
       when is_binary(name) do
    {wall, offset} = Zone.wall_of_utc(zone, nil, position)
    second_showing(Zone.offsets_at_wall(zone, wall), offset, value)
  end

  defp at_its_showing(value, _position, _frame), do: value

  defp second_showing([first, offset], offset, value) when first != offset,
    do: %{value | shift: Zone.shift_of(offset)}

  defp second_showing(_offsets, _offset, value), do: value

  # A time of day on a week date or an ordinal date is written on that date's own axis.
  defp own_axis?(units),
    do: Keyword.has_key?(units, :week) or Keyword.has_key?(units, :day_of_year)

  defp clock_unit?({:microsecond, _}), do: true
  defp clock_unit?(unit), do: Unit.clock?(unit)

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

  # ── Recurrences ───────────────────────────────────────────────────────

  # The first span moved by n cadences for each n, scaled from the first so a
  # month's cadence from the 31st lands right on every occurrence; a count, an
  # until value or a window bounds it, and with none it runs on.
  defp occurrences(%Tempo{form: {:span, from, to}} = first, bound, recurrence, options) do
    with {:ok, [base]} <-
           spans(%{first | form: {:span, from, to}}, Keyword.delete(options, :within)),
         {:ok, cadence} <- cadence(from, to, base, recurrence),
         {:ok, indexes} <- indexes(from, bound, recurrence),
         {:ok, until} <- until_position(bound) do
      stream =
        indexes
        |> Stream.map(fn n -> occurrence(base, {from, to}, cadences(cadence, n), recurrence) end)
        |> Stream.dedup_by(&landing/1)
        |> Stream.map(&%{&1 | metadata: Map.merge(recurrence.metadata, &1.metadata)})
        |> bounded(bound, until, options)

      {:ok, stream}
    end
  end

  # Where an occurrence starts on a line. Two steps that land on one start
  # (the second having stepped over a day the clock left out) are one
  # occurrence; on a cycle each is its own.
  defp landing({%Tempo{}, {start, _stop}}), do: start

  defp landing(occurrence) do
    case extent(occurrence) do
      {:ok, {start, _}} when is_integer(start) -> start
      _ -> make_ref()
    end
  end

  # The position occurrences start before to be kept. An until value bounds a
  # recurrence in an inclusive manner (RFC 5545 section 3.3.10): written to a
  # date it is read through, and written to a time of day an occurrence that
  # starts on it is the last, so the position is the tick after it. A count
  # or none has no position.
  defp until_position(%Tempo{} = until) do
    with {:ok, position} <- end_position(until) do
      if clock_resolution?(until), do: {:ok, position + 1}, else: {:ok, position}
    end
  end

  defp until_position(_count_or_infinity), do: {:ok, nil}

  # Forward from the start, or, when the start is a duration, back from the end in order.
  defp indexes(%Duration{}, bound, recurrence) do
    with {:ok, backwards} <- backward_indexes(bound, recurrence),
         do: {:ok, Enum.map(backwards, &(-&1))}
  end

  defp indexes(_from, _bound, _recurrence), do: {:ok, Stream.iterate(0, &(&1 + 1))}

  # The cadence scaled to the nth occurrence, to the one after it and to the one before.
  defp cadences(cadence, n),
    do: {scaled(cadence, n), scaled(cadence, n + 1), scaled(cadence, n - 1)}

  # The nth occurrence. A first span written with a length is one of a series
  # of consecutive spans (ISO 8601-1 3.1.1.11), each ending where the next
  # starts: both of its ends are the first's moved by whole cadences, so a
  # month from 31 January ends on 28 February and the next on 31 March. A
  # first span of two values is moved whole.
  defp occurrence(base, _ends, {%Duration{units: []}, _next, _previous}, _recurrence), do: base

  defp occurrence(
         %Tempo{form: {:span, from, to}} = base,
         {_, %Duration{} = duration},
         {step, next, _previous},
         recurrence
       ) do
    moved = moved_value(from, step, :start, base, recurrence)
    {:ok, {start, _}} = extent(moved)
    {:ok, {stop, _}} = extent(moved_value(from, next, :start, base, recurrence))
    stop = later(stop, start, duration, base, recurrence)
    %{base | form: {:span, moved, value_at(stop, to, :end, base)}}
  end

  defp occurrence(
         %Tempo{form: {:span, from, to}} = base,
         {%Duration{}, _},
         {step, _next, previous},
         recurrence
       ) do
    {:ok, start} = end_position(moved_value(to, previous, :end, base, recurrence))

    %{
      base
      | form:
          {:span, value_at(start, from, :start, base),
           moved_value(to, step, :end, base, recurrence)}
    }
  end

  defp occurrence(
         %Tempo{form: {:span, from, to}} = base,
         _ends,
         {step, _next, _previous},
         recurrence
       ) do
    %{
      base
      | form:
          {:span, moved_value(from, step, :start, base, recurrence),
           moved_value(to, step, :end, base, recurrence)}
    }
  end

  # A span written with a length knows its extent as it is built: where it
  # starts, and where the next starts.
  defp occurrence_at(
         %Tempo{form: {:span, from, to}} = base,
         {_, %Duration{} = duration},
         {%Duration{units: [_ | _]} = step, next, _previous},
         {recurrence, walk, k, first_start}
       ) do
    {moved, start} =
      start_at(walk, k, fn -> moved_from(first_start, from, step, :start, base, recurrence) end)

    stop =
      next_start_at(walk, k + 1, fn ->
        moved_from(first_start, from, next, :start, base, recurrence)
      end)

    stop = later(stop, start, duration, base, recurrence)
    {%{base | form: {:span, moved, value_at(stop, to, :end, base)}}, {start, stop}}
  end

  defp occurrence_at(base, ends, cadences, {recurrence, _walk, _k, _first_start}),
    do: {occurrence(base, ends, cadences, recurrence), nil}

  defp start_extent(%Tempo{form: {:span, %Tempo{} = from, _to}}), do: extent(from)
  defp start_extent(_base), do: nil

  # The start of the kth period and where it starts: the one the period
  # before it reckoned, where it is the next of the same walk, or reckoned
  # now. One is kept in the process, whichever walk last reckoned one.
  defp start_at(walk, k, moved) do
    case Process.get(@next_start) do
      {^walk, ^k, value, start} -> {value, start}
      _other -> reckoned(moved)
    end
  end

  defp next_start_at(walk, k, moved) do
    {value, start} = reckoned(moved)
    Process.put(@next_start, {walk, k, value, start})
    start
  end

  defp reckoned(moved) do
    value = moved.()
    {:ok, {start, _}} = extent(value)
    {value, start}
  end

  # Where the next occurrence starts, when that is later; where it is not (the
  # next step lands on the same start past a day a clock left out, or a cycle
  # comes round), the occurrence's own length from its start.
  defp later(stop, start, _duration, _base, _recurrence) when stop > start, do: stop

  defp later(_stop, start, duration, base, recurrence) do
    {:ok, stop} = shifted(start, duration, frame_of(base), recurrence)
    stop
  end

  defp backward_indexes(count, _recurrence) when is_integer(count),
    do: {:ok, Enum.to_list((count - 1)..0//-1)}

  defp backward_indexes(_bound, recurrence), do: {:error, conversion(recurrence, :unbounded)}

  # A count counts from the sequence's start and an until ends it; of the
  # occurrences either leaves, a window keeps those that overlap it.
  defp bounded(stream, count, _until, options) when is_integer(count),
    do: stream |> Stream.take(count) |> windowed(options)

  defp bounded(stream, %Tempo{}, until, options) do
    stream
    |> Stream.take_while(fn occurrence -> starts_before?(occurrence, until) end)
    |> windowed(options)
  end

  # With no end of its own a sequence is its occurrences that overlap the window.
  defp bounded(stream, :infinity, _until, options), do: windowed(stream, options)

  defp windowed(stream, options) do
    case window_extent(options[:within]) do
      {:ok, {start, stop}} -> stream |> dropped_before(start) |> taken_before(stop)
      _none -> stream
    end
  end

  defp window_extent(%Tempo{} = window), do: extent(window)
  defp window_extent(_none), do: :none

  defp dropped_before(stream, nil), do: stream
  defp dropped_before(stream, start), do: Stream.drop_while(stream, &ends_by?(&1, start))

  defp taken_before(stream, nil), do: stream
  defp taken_before(stream, stop), do: Stream.take_while(stream, &starts_before?(&1, stop))

  defp ends_by?({%Tempo{}, {_, stop}}, start), do: stop <= start

  defp ends_by?(occurrence, start) do
    case extent(occurrence) do
      {:ok, {_, stop}} when is_integer(stop) -> stop <= start
      _ -> false
    end
  end

  defp starts_before?({%Tempo{}, {start, _}}, stop), do: Scale.compare(start, stop) == :lt

  defp starts_before?(occurrence, stop) do
    case extent(occurrence) do
      {:ok, {start, _}} -> Scale.compare(start, stop) == :lt
      _ -> false
    end
  end

  # The cadence of a recurrence: its written duration, else the length of its first span in days or ticks.
  defp cadence(%Duration{} = duration, _to, _base, _recurrence), do: {:ok, duration}
  defp cadence(_from, %Duration{} = duration, _base, _recurrence), do: {:ok, duration}

  defp cadence(from, to, base, recurrence) do
    with {:ok, {start, stop}} <- extent(base) do
      cond do
        start == nil or stop == nil ->
          {:error, conversion(recurrence, :open)}

        match?({:cycle, _}, frame(base)) ->
          {:ok, %Duration{units: [second: div(stop - start, Unit.ticks(:second))]}}

        clock_resolution?(from) or clock_resolution?(to) ->
          {:ok, %Duration{units: [second: div(stop - start, Unit.ticks(:second))]}}

        true ->
          {:ok, %Duration{units: [day: div(stop - start, @day)]}}
      end
    end
  end

  defp moved_value(%Tempo{} = value, duration, kind, span, recurrence),
    do: moved_from(extent(value), value, duration, kind, span, recurrence)

  # A value moved by a duration from where it is, its extent given.
  defp moved_from({:ok, {start, stop}}, value, duration, kind, span, recurrence) do
    position = if kind == :end and not clock_resolution?(value), do: stop, else: start
    {:ok, moved} = shifted(position, duration, frame_of(span), recurrence)
    value_at(moved, value, kind, span)
  end

  # ── Children (law 6) ──────────────────────────────────────────────────

  @doc """
  What `Enum` yields for an expression (law 6): a singular expression's
  children, the values one unit below its resolution (the finer of its ends'
  for a written span), each a value in the expression's frame; a plural
  expression's members.
  """
  @spec children(Tempo.t() | Duration.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def children(expression, options \\ [])

  def children(%Tempo{} = expression, options) do
    if singular?(expression),
      do: walk(expression, child_unit(expression), options),
      else: members(expression, options)
  end

  def children(%Duration{} = duration, _options),
    do: {:error, conversion(duration, :bare_duration)}

  @doc "The unit one below an expression's resolution: what its walk yields when none is named."
  @spec child_unit(Tempo.t()) :: Unit.t() | {:microsecond, 1..6} | nil
  def child_unit(%Tempo{form: {:value, units}}) do
    case List.last(units) do
      {:group, {_nth, [{unit, _size}]}} -> unit
      _ -> below(Unit.resolution(units), units)
    end
  end

  def child_unit(%Tempo{form: {:span, from, to}}) do
    [from, to]
    |> Enum.flat_map(&end_resolution/1)
    |> Enum.max_by(fn {unit, _} -> Unit.rank(unit) || 0 end, fn ->
      nil
    end)
    |> then(fn
      nil -> nil
      {unit, units} -> own(unit, units)
    end)
  end

  def child_unit(_plural), do: nil

  defp end_resolution(%Tempo{form: {:value, units}}), do: [{Unit.resolution(units), units}]
  defp end_resolution(%Duration{units: units}), do: [{units |> List.last() |> elem(0), units}]
  defp end_resolution(_open), do: []

  # A value's children are one unit down; a label's are the hours of its day, a group's the units it groups.
  defp below(:microsecond, units) do
    case Keyword.fetch!(units, :microsecond) do
      {_, 6} -> nil
      {_, precision} -> {:microsecond, precision + 1}
    end
  end

  defp below(:second, _units), do: {:microsecond, 1}
  defp below(unit, _units) when unit in [:day_of_week, :day_of_year], do: :hour
  defp below(unit, _units) when unit in [:quarter, :season, :traditional_month], do: :day
  defp below(:group, units), do: units |> Keyword.fetch!(:group) |> elem(1) |> hd() |> elem(0)
  defp below(unit, _units), do: Unit.child(unit)

  # A span is walked at its own resolution: `2026/2028` by years, `T09/T17` by hours.
  defp own(:microsecond, units),
    do: {:microsecond, units |> Keyword.fetch!(:microsecond) |> elem(1)}

  defp own(unit, _units) when unit in [:day_of_week, :day_of_year], do: :day
  defp own(:traditional_month, _units), do: :month

  # A meteorological season is whole months; an astronomical one is not.
  defp own(:season, units) do
    if Season.abstract?(Keyword.fetch!(units, :season)), do: :month, else: :day
  end

  defp own(:group, units), do: units |> Keyword.fetch!(:group) |> elem(1) |> hd() |> elem(0)
  defp own(unit, _units), do: unit

  @doc """
  An expression walked at a unit: a singular expression's extent stepped at
  the unit (`Tempo.Walk`), each step a value in the expression's frame; a
  plural expression's members each walked in turn.
  """
  @spec walk(Tempo.t(), Unit.t() | {:microsecond, 1..6} | nil, keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def walk(expression, unit, options \\ [])

  def walk(%Tempo{} = expression, nil, _options),
    do: {:error, conversion(expression, :nothing_finer)}

  def walk(%Tempo{} = expression, unit, options) do
    if singular?(expression) do
      with {:ok, {start, stop}} <- extent(expression),
           :ok <- walkable(start, expression),
           {:ok, steps} <- steps(expression, {start, stop}, unit) do
        {:ok, Stream.map(steps, &stepped(expression, &1))}
      end
    else
      with {:ok, members} <- members(expression, options) do
        {:ok, Stream.flat_map(members, fn member -> walk!(member, unit, options) end)}
      end
    end
  end

  # On a line the extent is stepped; on a cycle a value's children come from
  # the calendar's counts, and a span's from the cycle's values run through
  # its end (`12M/2M` is December, January and February).
  defp steps(expression, extent, unit) do
    case frame(expression) do
      {:cycle, coarsest} -> cycle_steps(expression, extent, unit, coarsest)
      _line -> Walk.steps(extent, unit, frame_of(expression)) |> walk_error(expression)
    end
  end

  # A cycle value's children come from the calendar's counts; a cycle span is
  # stepped by the clock through midnight, or through the cycle's own values
  # from its start through its end (`12M/2M` is December, January and February).
  defp cycle_steps(%Tempo{form: {:value, units}} = value, {start, stop}, unit, coarsest) do
    if clock_unit?(unit) and Unit.clock?(coarsest) do
      {:ok, Walk.cycle_clock_steps(start, stop, unit)}
    else
      case Expand.children(units, unit, frame_of(value)) do
        {:ok, children} ->
          {:ok, Enum.map(children, &cycle_child(&1, units, unit, coarsest, value.calendar))}

        {:error, reason} ->
          {:error, conversion(value, reason)}
      end
    end
  end

  defp cycle_steps(%Tempo{form: {:span, from, to}} = span, {start, stop}, unit, coarsest) do
    cond do
      clock_unit?(unit) and Unit.clock?(coarsest) ->
        {:ok, Walk.cycle_clock_steps(start, stop, unit)}

      unit == coarsest and match?(%Tempo{}, from) and match?(%Tempo{}, to) ->
        with {:ok, children} <- Expand.children([], unit, frame_of(span)) |> walk_error(span) do
          values = Enum.map(children, &elem(&1, 0))
          {:ok, Enum.map(rotated(values, held(from, unit), held(to, unit)), &[{unit, &1}])}
        end

      true ->
        {:error, conversion(span, :needs_a_year)}
    end
  end

  defp held(%Tempo{form: {:value, units}}, unit), do: Keyword.get(units, unit)

  # A child of a group on a cycle is read back from its place on the cycle (`6M2G10DU` walks `6M11D`).
  defp cycle_child({held, span}, units, unit, coarsest, calendar) do
    case {Keyword.has_key?(units, :group), span} do
      {true, {start, _}} when is_integer(start) ->
        Scale.cycle_units(start, coarsest, unit, calendar)

      _ ->
        Unit.cyclic(units) ++ [{unit, held}]
    end
  end

  # The cycle's values from one through another, running on through the cycle's end.
  defp rotated(values, from, through) do
    rotated =
      values |> Stream.cycle() |> Stream.drop_while(&(&1 != from)) |> Enum.take(length(values))

    case Enum.find_index(rotated, &(&1 == through)) do
      nil -> rotated
      index -> Enum.take(rotated, index + 1)
    end
  end

  defp walkable(nil, expression), do: {:error, conversion(expression, :open)}
  defp walkable(_start, _expression), do: :ok

  defp walk_error({:ok, steps}, _expression), do: {:ok, steps}
  defp walk_error({:error, reason}, expression), do: {:error, conversion(expression, reason)}

  defp walk!(member, unit, options) do
    case walk(member, unit, options) do
      {:ok, stream} -> stream
      {:error, exception} -> raise exception
    end
  end

  # A step as a value of the expression's frame, keeping the marks on the units it shares with its source.
  defp stepped(source, {:shifted, units, shift}), do: %{stepped(source, units) | shift: shift}

  defp stepped(%Tempo{form: {:span, from, to}} = span, units),
    do: stepped(%{first_value([from, to]) | metadata: span.metadata}, units)

  defp stepped(%Tempo{form: {:value, own}} = source, units) do
    %Tempo{
      form: {:value, units},
      calendar: source.calendar,
      zone: source.zone,
      shift: source.shift,
      qualifications: shared_marks(source.qualifications, own, units),
      metadata: source.metadata
    }
  end

  defp stepped(%Tempo{} = source, units),
    do: %Tempo{
      form: {:value, units},
      calendar: source.calendar,
      zone: source.zone,
      metadata: source.metadata
    }

  defp shared_marks(nil, _own, _units), do: nil

  defp shared_marks(marks, own, units) do
    kept =
      for {unit, mark} <- marks,
          Keyword.get(own, unit) == Keyword.get(units, unit),
          into: %{},
          do: {unit, mark}

    if kept == %{}, do: nil, else: kept
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

      not Unit.anchored?(units) and options[:within] != nil ->
        members(placed_in(value, options[:within]), Keyword.delete(options, :within))

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

  defp expanded_values(%Tempo{form: {:value, units}} = value) do
    case Expand.expand(units, frame_of(value)) do
      {:ok, stream} -> {:ok, Stream.map(stream, fn units -> %{value | form: {:value, units}} end)}
      {:error, reason} -> {:error, conversion(value, reason)}
    end
  end

  # ── Readings ──────────────────────────────────────────────────────────

  @doc """
  The readings of an uncertain expression, each as an extent: the members of
  a one-of set, each placing of a year with a margin, each value a mask
  allows; an interval with uncertain ends, each pairing of their readings in
  order. An expression with one reading is its own extent.
  """
  @spec readings(Tempo.t() | Duration.t()) ::
          {:ok, [{Scale.position(), Scale.position()}]} | {:error, Exception.t()}
  def readings(%Tempo{form: {:one, members}}), do: each_readings(members, &readings/1)
  def readings(%Duration{} = duration), do: {:error, conversion(duration, :bare_duration)}

  def readings(%Tempo{form: {:value, units}} = value) do
    with {:ok, placings} <- placings(value, units), do: closed_extents(placings, value)
  end

  def readings(%Tempo{form: {:span, from, to}} = span) do
    if margin?(from) or margin?(to),
      do: paired_readings(span),
      else: spans_readings(span)
  end

  # A recurrence with no end has no finite readings to judge.
  def readings(%Tempo{form: {:every, _, :infinity, _}} = recurrence),
    do: {:error, conversion(recurrence, :unbounded)}

  # A set, a recurrence or a member with conditions has the readings of the spans it names.
  def readings(%Tempo{} = expression), do: spans_readings(expression)

  # The extents of each of several, or the first error.
  defp each_readings(expressions, read) do
    Enum.reduce_while(expressions, {:ok, []}, fn expression, {:ok, acc} ->
      case read.(expression) do
        {:ok, extents} -> {:cont, {:ok, acc ++ extents}}
        error -> {:halt, error}
      end
    end)
  end

  # The extent of each expression, every one closed at both ends.
  defp closed_extents(expressions, source) do
    each_readings(expressions, fn expression ->
      case extent(expression) do
        {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> {:ok, [{start, stop}]}
        {:ok, _open} -> {:error, conversion(source, :open)}
        error -> error
      end
    end)
  end

  defp margin?(%Tempo{form: {:value, units}}),
    do: Enum.any?(units, &match?({_, {n, [margin: _]}} when is_integer(n), &1))

  defp margin?(_other), do: false

  # A span with a margin at an end is each pairing of its ends' readings in order, on through a cycle's end.
  defp paired_readings(%Tempo{form: {:span, from, to}} = span) do
    with {:ok, starts} <- readings(from),
         {:ok, ends} <- readings(to) do
      pairs =
        for {start, _} <- starts,
            stop <- Enum.map(ends, &end_of_reading(&1, to)),
            stop = wrapped_stop(start, stop, span),
            start < stop,
            do: {start, stop}

      if pairs == [], do: {:error, conversion(span, :open)}, else: {:ok, pairs}
    end
  end

  defp end_of_reading({stop_start, stop_end}, to),
    do: if(clock_resolution?(to), do: stop_start, else: stop_end)

  defp wrapped_stop(start, stop, span) when stop <= start do
    case frame(span) do
      {:cycle, coarsest} ->
        case Scale.cycle_length(coarsest, span.calendar) do
          {:ok, length} -> stop + length
          {:error, _} -> stop
        end

      _line ->
        stop
    end
  end

  defp wrapped_stop(_start, stop, _span), do: stop

  # Any other span is the spans it names, each an extent: a plural end gives one for each value.
  defp spans_readings(span) do
    with {:ok, spans} <- spans(span),
         {:ok, spans} <- Limit.take(spans, span),
         do: closed_extents(spans, span)
  end

  # A year with a margin is each year it may be; a value with a mask or a set each value it allows.
  defp placings(value, units) do
    case Enum.find(units, fn {_, held} -> match?({n, [margin: _]} when is_integer(n), held) end) do
      {unit, {n, [margin: m]}} ->
        {:ok,
         for(
           placed <- (n - m)..(n + m),
           do: %{value | form: {:value, Keyword.put(units, unit, placed)}}
         )}

      nil ->
        single_or_members(value, units)
    end
  end

  defp single_or_members(value, units) do
    if Expand.one_span?(units),
      do: {:ok, [value]},
      else: with({:ok, members} <- members(value), do: Limit.take(members, value))
  end

  # ── Errors ────────────────────────────────────────────────────────────

  defp conversion(expression, {:no_such_value, _}),
    do: ConversionError.exception(value: expression, reason: :no_such_value)

  defp conversion(expression, reason),
    do: ConversionError.exception(value: expression, reason: reason)
end
