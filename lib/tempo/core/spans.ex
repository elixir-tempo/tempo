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
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Expand
  alias Tempo.Scale
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

  def frame(%Tempo{form: {kind, [first | _]}}) when kind in [:all, :one],
    do: frame(member_value(first))

  def frame(%Tempo{form: {:when, member, _conditions}}), do: frame(member)
  def frame(%Tempo{}), do: :floating

  defp first_value(ends), do: Enum.find(ends, &match?(%Tempo{}, &1)) || %Tempo{form: {:value, []}}
  defp member_value({:except, member}), do: member
  defp member_value(member), do: member

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
  the clock part in ticks, each read on the wall clock of the frame.
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

    wall = Walk.wall(tick, frame)
    day = Integer.floor_div(wall, @day)
    clock = Integer.mod(wall, @day)
    moved = day_shifted(day, date_units, frame.calendar) * @day + clock + clock_ticks(clock_units)
    {:ok, placed(moved, frame)}
  end

  def shifted(nil, _duration, _frame, expression), do: {:error, conversion(expression, :open)}

  defp day_shifted(day, [], _calendar), do: day

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
  def negated(%Duration{units: units}) do
    %Duration{
      units:
        Enum.map(units, fn
          {:microsecond, {us, precision}} -> {:microsecond, {-us, precision}}
          {unit, n} -> {unit, -n}
        end)
    }
  end

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
        {:error, conversion(value, :selection)}

      not Unit.anchored?(units) and options[:within] != nil ->
        spans(placed_in(value, options[:within]), Keyword.delete(options, :within))

      Expand.one_span?(units) ->
        with {:ok, span} <- as_span(value), do: {:ok, [span]}

      true ->
        expanded_spans(value)
    end
  end

  def spans(%Tempo{form: {:span, from, to}} = span, options) do
    case {plural_end(from), plural_end(to)} do
      {false, false} -> with {:ok, resolved} <- resolved(span, options), do: {:ok, [resolved]}
      {true, true} -> {:error, conversion(span, :several)}
      {true, false} -> each_end(span, :from, from, options)
      {false, true} -> each_end(span, :to, to, options)
    end
  end

  def spans(%Tempo{form: {:every, first, bound, rule}} = recurrence, options) do
    if rule == nil,
      do: occurrences(first, bound, recurrence, options),
      else: {:error, conversion(recurrence, :repeat_rule)}
  end

  def spans(%Tempo{form: {:all, members}} = set, options) do
    if Enum.any?(members, &match?({:except, _}, &1)) do
      {:error, conversion(set, :exclusion)}
    else
      with {:ok, streams} <- each_spans(members, options), do: {:ok, Stream.concat(streams)}
    end
  end

  def spans(%Tempo{form: {:one, _}} = set, _options), do: {:error, conversion(set, :one_of)}

  def spans(%Tempo{form: {:when, _, _}} = member, _options),
    do: {:error, conversion(member, :conditions)}

  defp each_spans(members, options) do
    Enum.reduce_while(members, {:ok, []}, fn member, {:ok, acc} ->
      case spans(member, options) do
        {:ok, stream} -> {:cont, {:ok, acc ++ [stream]}}
        error -> {:halt, error}
      end
    end)
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

  # A value with no year placed on each period of a window: the window's units above its own.
  defp placed_in(
         %Tempo{form: {:value, units}} = value,
         %Tempo{form: {:value, window_units}} = window
       ) do
    %{
      value
      | form: {:value, Expand.filled(window_units ++ Unit.cyclic(units))},
        calendar: window.calendar,
        zone: value.zone || window.zone
    }
  end

  defp placed_in(value, _window), do: value

  # ── A value as its one span ───────────────────────────────────────────

  @doc """
  The one span of a singular value (law 3): from the value, through the
  value when it is written to a calendar unit, to the next reading when it
  is written to a clock unit.
  """
  @spec as_span(Tempo.t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def as_span(%Tempo{form: {:value, _units}} = value) do
    with {:ok, {_start, stop}} <- extent(value) do
      to = if clock_resolution?(value), do: clock_end(value, stop), else: value

      {:ok,
       %Tempo{
         form: {:span, value, to},
         calendar: value.calendar,
         zone: value.zone,
         metadata: value.metadata
       }}
    end
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
        wall = Walk.wall(stop, frame_of(value))
        units = Walk.at_tick(wall, written_unit(units), value.calendar)
        %{value | form: {:value, units}, qualifications: nil}
    end
  end

  defp written_unit(units) do
    case Unit.resolution(units) do
      :microsecond -> {:microsecond, units |> Keyword.fetch!(:microsecond) |> elem(1)}
      unit -> unit
    end
  end

  # ── Written spans ─────────────────────────────────────────────────────

  # A written span with its duration end made a value and an open end placed by the window, if one is given.
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
      case side do
        :from -> {:ok, value_at(wstart, model_of(to, window), :start, span)}
        :to -> {:ok, value_at(wstop, model_of(from, window), :end, span)}
      end
    end
  end

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
        clock_unit?(resolution) ->
          Walk.at_tick(Walk.wall(position, frame), resolution, span.calendar)

        kind == :end ->
          Walk.at_day(
            Integer.floor_div(Walk.wall(position, frame) - 1, @day),
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

    %{model | form: {:value, units}, qualifications: nil, shift: model.shift}
  end

  defp clock_unit?({:microsecond, _}), do: true
  defp clock_unit?(unit), do: Unit.clock?(unit)

  defp day_unit(unit) when unit in [:day, :day_of_week, :day_of_year], do: :day
  defp day_unit(unit) when unit in [:month, :traditional_month, :season], do: :month
  defp day_unit(unit) when unit in [:year, :decade, :century, :week, :quarter], do: unit
  defp day_unit(_unit), do: :day

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
        |> Stream.map(fn n -> occurrence(base, {from, to}, scaled(cadence, n), recurrence) end)
        |> bounded(bound, until, options)

      {:ok, stream}
    end
  end

  # Where an until value ends, read as a written end (law 9); a count or none has no position.
  defp until_position(%Tempo{} = until), do: end_position(until)
  defp until_position(_count_or_infinity), do: {:ok, nil}

  # Forward from the start, or, when the start is a duration, back from the end in order.
  defp indexes(%Duration{}, bound, recurrence) do
    with {:ok, backwards} <- backward_indexes(bound, recurrence),
         do: {:ok, Enum.map(backwards, &(-&1))}
  end

  defp indexes(_from, _bound, _recurrence), do: {:ok, Stream.iterate(0, &(&1 + 1))}

  # The nth occurrence: the first span's start moved n cadences, and its end as
  # the first was written, a duration from that start or a value moved the same.
  defp occurrence(base, _ends, %Duration{units: []}, _recurrence), do: base

  defp occurrence(
         %Tempo{form: {:span, from, to}} = base,
         {_, %Duration{} = duration},
         step,
         recurrence
       ) do
    from = moved_value(from, step, :start, base, recurrence)
    {:ok, {start, _}} = extent(from)
    {:ok, stop} = shifted(start, duration, frame_of(base), recurrence)
    %{base | form: {:span, from, value_at(stop, to, :end, base)}}
  end

  defp occurrence(
         %Tempo{form: {:span, from, to}} = base,
         {%Duration{} = duration, _},
         step,
         recurrence
       ) do
    to = moved_value(to, step, :end, base, recurrence)
    {:ok, stop} = end_position(to)
    {:ok, start} = shifted(stop, negated(duration), frame_of(base), recurrence)
    %{base | form: {:span, value_at(start, from, :start, base), to}}
  end

  defp occurrence(%Tempo{form: {:span, from, to}} = base, _ends, step, recurrence) do
    %{
      base
      | form:
          {:span, moved_value(from, step, :start, base, recurrence),
           moved_value(to, step, :end, base, recurrence)}
    }
  end

  defp backward_indexes(count, _recurrence) when is_integer(count),
    do: {:ok, Enum.to_list((count - 1)..0//-1)}

  defp backward_indexes(_bound, recurrence), do: {:error, conversion(recurrence, :unbounded)}

  defp bounded(stream, count, _until, _options) when is_integer(count),
    do: Stream.take(stream, count)

  defp bounded(stream, %Tempo{}, until, _options),
    do: Stream.take_while(stream, fn occurrence -> starts_before?(occurrence, until) end)

  defp bounded(stream, :infinity, _until, options) do
    case options[:within] do
      %Tempo{} = window ->
        case extent(window) do
          {:ok, {_, stop}} when stop != nil ->
            Stream.take_while(stream, &starts_before?(&1, stop))

          _ ->
            stream
        end

      _ ->
        stream
    end
  end

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

  defp moved_value(%Tempo{} = value, duration, kind, span, recurrence) do
    {:ok, {start, stop}} = extent(value)
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
    |> Enum.max_by(fn {unit, _} -> Enum.find_index(Unit.order(), &(&1 == unit)) || 0 end, fn ->
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
  defp own(unit, _units) when unit in [:traditional_month, :season], do: :month
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
        {:error, conversion(value, :selection)}

      not Unit.anchored?(units) and options[:within] != nil ->
        members(placed_in(value, options[:within]), Keyword.delete(options, :within))

      Expand.one_span?(units) ->
        {:ok, [value]}

      true ->
        expanded_values(value)
    end
  end

  def members(%Tempo{form: {:all, members}}, _options),
    do: {:ok, Enum.map(members, &member_value/1)}

  def members(%Tempo{form: {:one, members}}, _options), do: {:ok, members}

  def members(%Tempo{form: {:every, _, _, _}} = recurrence, options),
    do: spans(recurrence, options)

  def members(%Tempo{form: {:span, _, _}} = span, options), do: spans(span, options)

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

  # ── Errors ────────────────────────────────────────────────────────────

  defp conversion(expression, {:no_such_value, _}),
    do: ConversionError.exception(value: expression, reason: :no_such_value)

  defp conversion(expression, reason),
    do: ConversionError.exception(value: expression, reason: reason)
end
