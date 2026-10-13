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
  alias Tempo.Select
  alias Tempo.Shift
  alias Tempo.Unit
  alias Tempo.Walk
  alias Tempo.Zone

  @rule_units [:month, :week, :day, :day_of_week, :day_of_year, :hour, :minute, :second]

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

  defp placed?(%Tempo{form: {:every, %Tempo{form: {:span, :open, _}}, _, _}}), do: false
  defp placed?(%Tempo{form: {:span, :open, _}}), do: false
  defp placed?(_member), do: true

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
      {true, true} -> paired_ends(span, options)
      {true, false} -> each_end(span, :from, from, options)
      {false, true} -> each_end(span, :to, to, options)
    end
  end

  def spans(%Tempo{form: {:every, first, bound, rule}} = recurrence, options) do
    if rule == nil,
      do: occurrences(first, bound, recurrence, options),
      else: rule_occurrences(first, bound, rule, recurrence, options)
  end

  # A set read from a stream gives its members' spans as they are asked for.
  def spans(%Tempo{form: {:all, members}}, options) when not is_list(members) do
    {:ok, Stream.flat_map(members, &member_stream(&1, options))}
  end

  def spans(%Tempo{form: {:all, members}} = set, options) do
    case Enum.split_with(members, &match?({:except, _}, &1)) do
      {[], members} ->
        member_spans(members, options)

      {excluded, members} ->
        excluded_spans(set, members, Enum.map(excluded, &elem(&1, 1)), options)
    end
  end

  def spans(%Tempo{form: {:one, _}} = set, _options), do: {:error, conversion(set, :one_of)}

  # A domain filter: the members' spans in the years the filter names.
  def spans(%Tempo{form: {:when, member, years: filter}} = expression, options) do
    with {:ok, spans} <- spans(%{member | calendar: expression.calendar}, options),
         do: {:ok, Stream.filter(spans, &in_years?(&1, filter, expression.calendar))}
  end

  def spans(%Tempo{form: {:when, _, _}} = member, options) do
    if Conditions.conditional?(member),
      do: Conditions.resolve([member], [], options),
      else: {:error, conversion(member, :conditions)}
  end

  defp member_stream(member, options) do
    case spans(member, options) do
      {:ok, spans} -> spans
      {:error, exception} -> raise exception
    end
  end

  # A set's members' spans; members conditional on the others are judged
  # against the others' spans, and the whole put in order of start.
  defp member_spans(members, options) do
    case Enum.split_with(members, &Conditions.conditional?/1) do
      {[], members} ->
        with {:ok, streams} <- each_spans(members, options), do: {:ok, Stream.concat(streams)}

      {conditionals, members} ->
        with {:ok, streams} <- each_spans(members, options),
             others = streams |> Stream.concat() |> Enum.take(Limit.values()),
             {:ok, conditional} <- Conditions.resolve(conditionals, others, options) do
          {:ok, Enum.sort_by(others ++ conditional, &start_position/1)}
        end
    end
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
    period = placed_in(%{value | form: {:value, prefix}}, options[:within])

    if Unit.anchored?(elem(period.form, 1)),
      do: {:ok, [period]},
      else: {:error, conversion(value, :needs_a_year)}
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
         {:ok, until} <- until_position(bound) do
      parts = with_inherited(rule, inherited_units(from, rule))
      begins = start_of_rule(from)

      stream =
        periods
        |> Stream.map(&eligible(&1, first))
        |> Stream.flat_map(&in_rule_period(&1, parts, options))
        |> Stream.filter(&(start_position(&1) >= begins))
        |> Stream.map(&%{&1 | metadata: Map.merge(recurrence.metadata, &1.metadata)})
        |> bounded(bound, until, options)

      {:ok, stream}
    end
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

  defp start_of_rule(%Tempo{form: {:value, _}} = from) do
    case extent(from) do
      {:ok, {start, _}} when is_integer(start) -> start
      _ -> 0
    end
  end

  defp start_of_rule(_from), do: 0

  # The start's finer units join the rule's parts, before its window.
  defp with_inherited(rule, []), do: rule

  defp with_inherited(rule, inherited) do
    {window, parts} = Keyword.pop(rule, :window)
    parts ++ inherited ++ if(window, do: [window: window], else: [])
  end

  # A domain (a set in the start's place) gives its members as the periods;
  # a start gives the cadence's repeating intervals.
  defp rule_periods(_first, %Tempo{form: form} = domain, _recurrence, options)
       when elem(form, 0) in [:all, :when],
       do: spans(domain, options)

  # A rule with no start (`R/../P1Y/F…`) has the cadence's periods the window runs through.
  defp rule_periods(
         %Tempo{form: {:span, :open, %Duration{units: [{unit, n}]}}} = first,
         :open,
         recurrence,
         options
       ) do
    case window_extent(options[:within]) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
        frame = frame_of(options[:within])
        anchor = %{first | form: {:value, Shift.period_units(start, unit, frame)}}
        step = %Duration{units: [{unit, n}]}
        occurrences(%{first | form: {:span, anchor, step}}, :infinity, recurrence, options)

      _none ->
        {:error, conversion(recurrence, :unbounded)}
    end
  end

  defp rule_periods(first, _from, recurrence, options),
    do: occurrences(first, :infinity, recurrence, options)

  defp inherited_units(%Tempo{form: {:value, units}}, rule) do
    finest =
      case Keyword.take(rule, @rule_units) do
        [] -> :day
        parts -> parts |> Unit.resolution() |> Unit.grain()
      end

    Enum.filter(units, fn {unit, _} ->
      Unit.compare(Unit.grain(unit), finest) == :gt and not Keyword.has_key?(rule, unit)
    end)
  end

  defp inherited_units(_from, _rule), do: []

  defp in_rule_period(period, parts, options) do
    case Select.in_period(period, parts, options) do
      {:ok, picked} -> Enum.map(picked, &as_span_or_self/1)
      {:error, _} -> []
    end
  end

  defp as_span_or_self(%Tempo{form: {:value, _}} = value), do: as_span!(value)

  # A window from a selected value, with its end written as a value.
  defp as_span_or_self(%Tempo{form: {:span, %Tempo{}, %Duration{}}} = span) do
    case resolved(span, []) do
      {:ok, resolved} -> resolved
      {:error, _} -> span
    end
  end

  defp as_span_or_self(other), do: other

  # ── Exclusions and domain filters ─────────────────────────────────────

  # The members' spans but those that lie within an excluded member's.
  defp excluded_spans(set, members, excluded, options) do
    with {:ok, kept} <- spans(%{set | form: {:all, members}}, options),
         {:ok, out} <- spans(%{set | form: {:all, excluded}}, options) do
      out = out |> Enum.take(Limit.values()) |> Enum.map(&extent/1)
      {:ok, Stream.reject(kept, &excluded?(extent(&1), out))}
    end
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

  @doc """
  A value with no year placed on each period of a window: the window's units
  coarser than the value's own, before them. A window no coarser than the
  value places nothing, and the value is returned as it is. A span's ends
  are placed each, and a set's members.
  """
  @spec placed_in(Tempo.t(), Tempo.t() | nil) :: Tempo.t()
  def placed_in(
        %Tempo{form: {:value, units}} = value,
        %Tempo{form: {:value, window_units}} = window
      ) do
    cyclic = Unit.cyclic(units)
    coarsest = Unit.coarsest(cyclic)

    case Enum.take_while(window_units, fn {unit, _} -> Unit.compare(unit, coarsest) == :lt end) do
      [] -> value
      above -> in_window(%{value | form: {:value, Expand.filled(above ++ cyclic)}}, window)
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

  @doc """
  The value at a position, written to a model value's resolution in a
  calendar and a zone: how a set operation writes a result's end from the
  operand end that stands there. A model of another calendar is written at
  day resolution, a month of one calendar being no month of another; a
  clock resolution is kept.
  """
  @spec at_position(Scale.position(), Tempo.t(), :start | :end, module(), Zone.t() | nil) ::
          Tempo.t()
  def at_position(position, %Tempo{} = model, kind, calendar, zone) do
    model = if model.calendar == calendar, do: model, else: day_model(model)
    # In a named zone the ends are its wall readings, with no shift of their own.
    model = if zone == nil, do: model, else: %{model | shift: nil}
    context = %Tempo{form: {:span, model, model}, calendar: calendar, zone: zone}
    %{value_at(position, model, kind, context) | calendar: calendar, zone: zone}
  end

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

  # With no end of its own a sequence is its occurrences that overlap the window.
  defp bounded(stream, :infinity, _until, options) do
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

  defp ends_by?(occurrence, start) do
    case extent(occurrence) do
      {:ok, {_, stop}} when is_integer(stop) -> stop <= start
      _ -> false
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

  def members(%Tempo{form: {:all, members}}, _options), do: {:ok, members}

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

  # ── Readings ──────────────────────────────────────────────────────────

  @doc """
  The readings of an uncertain expression, each as an extent: the members of
  a one-of set, each placing of a year with a margin, each value a mask
  allows; an interval with uncertain ends, each pairing of their readings in
  order. An expression with one reading is its own extent.
  """
  @spec readings(Tempo.t()) ::
          {:ok, [{Scale.position(), Scale.position()}]} | {:error, Exception.t()}
  def readings(%Tempo{form: {:one, members}}), do: each_readings(members, &readings/1)

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
    with {:ok, spans} <- spans(span), do: closed_extents(Enum.take(spans, Limit.values()), span)
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
      else: with({:ok, members} <- members(value), do: {:ok, Enum.take(members, Limit.values())})
  end

  # ── Errors ────────────────────────────────────────────────────────────

  defp conversion(expression, {:no_such_value, _}),
    do: ConversionError.exception(value: expression, reason: :no_such_value)

  defp conversion(expression, reason),
    do: ConversionError.exception(value: expression, reason: reason)
end
