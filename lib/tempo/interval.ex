defmodule Tempo.Interval do
  @moduledoc """
  An explicit bounded span on the time line.

  Every Tempo value *is* an interval at some resolution; a bare
  `%Tempo{}` converts to an `%Tempo.Interval{}` with
  `Tempo.to_interval/1`. `%Tempo.Interval{}` carries explicit
  `from` and `to` endpoints plus optional recurrence metadata
  (`recurrence`, `duration`, `repeat_rule`) for RRULE-style
  values.

  Tempo uses the half-open `[from, to)` convention: `from` is
  inclusive, `to` is exclusive. Adjacent intervals concatenate
  cleanly — `[a, b) ++ [b, c) == [a, c)`.

  ## Comparing intervals

  `relation/2` classifies two intervals by Allen's interval
  algebra, returning one of 13 mutually-exclusive relations.
  See the function docs for the full table.

  ## Domain semantics: continuous time, discrete-style intervals

  Tempo's underlying time line is **continuous**: endpoints project
  to gregorian seconds (a real number, via Erlang's
  `:calendar.datetime_to_gregorian_seconds/1`) and cross-zone
  comparison uses real-number ordering. The set of representable
  endpoint positions is dense within Tempo's resolution range
  (currently down to one-second granularity).

  Interval **boundary semantics** are nonetheless treated in the
  discrete style — the `:to` endpoint is *exclusive*, so two
  intervals `[a, b)` and `[b, c)` *meet* at the shared boundary `b`
  with empty geometric intersection. This is the same convention
  Rust's `allen-intervals` crate uses for its discrete integer
  domain, and matches Hayes' open-connected-subsets model that
  Grüninger and Li cite (TIME 2017, §2.2). It contrasts with the
  closed-interval / continuous-domain convention (e.g., Allen's
  original 1983 paper, which treats intervals as closed and lets
  `meets` happen at a single shared point of inclusion); Tempo's
  half-open choice keeps adjacency unambiguous and lets coalescing
  be a pure operation on endpoints without a "do these touch?"
  predicate.

  In practical terms: if you need to model an event that includes
  both endpoint moments (a true closed interval), encode it as
  `[a, b + ε)` where `ε` is one unit at the value's resolution.
  Library code never imposes this — the half-open convention is the
  contract.

  """

  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.FloatingTempoError
  alias Tempo.Interval.Cycle
  alias Tempo.Interval.Steps
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidUnitError
  alias Tempo.Iso8601.AST
  alias Tempo.Iso8601.Group
  alias Tempo.Iso8601.Unit
  alias Tempo.LeapSeconds
  alias Tempo.Mask
  alias Tempo.Math
  alias Tempo.Qualification
  alias Tempo.TimeZoneDatabase
  alias Tempo.UnanchoredError
  alias Tempo.UnitValues

  @type t :: %__MODULE__{
          recurrence: non_neg_integer() | :infinity,
          direction: 1 | -1,
          from: Tempo.t() | Tempo.Duration.t() | :undefined | nil,
          to: Tempo.t() | :undefined | nil,
          duration: Tempo.Duration.t() | nil,
          repeat_rule: Tempo.t() | nil,
          unit: atom() | nil,
          metadata: map()
        }

  @typedoc """
  One of Allen's 13 interval relations — jointly exhaustive and
  pairwise disjoint under the half-open `[from, to)` convention.
  """
  @type relation ::
          :precedes
          | :meets
          | :overlaps
          | :finished_by
          | :contains
          | :starts
          | :equals
          | :started_by
          | :during
          | :finishes
          | :overlapped_by
          | :met_by
          | :preceded_by

  @typedoc """
  Anything `relation/2` can reduce to a single bounded interval.
  """
  @type interval_like :: Tempo.t() | t() | IntervalSet.t()

  defstruct recurrence: 1,
            direction: 1,
            from: nil,
            to: nil,
            duration: nil,
            repeat_rule: nil,
            unit: nil,
            metadata: %{}

  @public_new_options [
    :from,
    :to,
    :through,
    :duration,
    :recurrence,
    :repeat_rule,
    :unit,
    :metadata
  ]

  # Units a caller may request as iteration granularity via `new/1` —
  # the month-based calendar/clock chain the walk-time fill can reach.
  # Selector-only units (`:instance`, `:day_of_week`, …) are not
  # iteration units; `:week`/`:day_of_week` are reachable only from
  # week-calendar values, where materialisation sets them itself.
  @iteration_units [:year, :month, :day, :hour, :minute, :second]

  @hours_per_day 24

  @doc """
  Construct a `t:Tempo.Interval.t/0` from a keyword list of options.

  The companion to `~o` interval sigils and `Tempo.to_interval/1`.
  Use this when you have the endpoints as runtime values (e.g. two
  `%Tempo{}` structs) rather than an ISO 8601 string.

  At least one of `:from`, `:to`, or `:duration` must be supplied.

  ### Arguments

  * `options` is a keyword list of construction options
    (see below).

  ### Options

  * `:from` is a `t:Tempo.t/0` or the atom `:undefined`
    (open start).

  * `:to` is a `t:Tempo.t/0` or the atom `:undefined`
    (open end).

  * `:through` is a `t:Tempo.t/0` or a `t:t/0` whose span the interval
    runs to the end of, so the last day a published range names is
    inside it. It takes the place of `:to` and `:duration`.

  * `:duration` is a `t:Tempo.Duration.t/0`. When combined with
    `:from`, the `:to` endpoint is derived lazily by
    `Tempo.to_interval/1`.

  * `:recurrence` is a `pos_integer()` or `:infinity`.

  * `:repeat_rule` is a `t:Tempo.RRule.Rule.t/0` or `t:Tempo.t/0`.

  * `:metadata` is a free-form map carried through set operations.

  ### Returns

  * `{:ok, t()}` on success.

  * `{:error, reason}` when endpoints are invalid, `:from` is not
    strictly earlier than `:to` (a zero-extent interval is not a
    valid interval under the half-open convention; see
    `Tempo.Interval.empty?/1` for the predicate that detects
    malformed struct literals), or required fields are missing.

  ### Examples

      iex> {:ok, iv} = Tempo.Interval.new(
      ...>   from: Tempo.new!(year: 2026, month: 6, day: 15, hour: 9),
      ...>   to:   Tempo.new!(year: 2026, month: 6, day: 15, hour: 17)
      ...> )
      iex> iv.from.time
      [year: 2026, month: 6, day: 15, hour: 9]

      iex> {:ok, iv} = Tempo.Interval.new(
      ...>   from: Tempo.new!(year: 1985),
      ...>   to: :undefined
      ...> )
      iex> iv.to
      :undefined

  A term that runs from Thursday 28 January through Friday 9 April
  ends where Saturday 10 April begins:

      iex> Tempo.Interval.new(from: ~o"2027-01-28", through: ~o"2027-04-09")
      {:ok, ~o"2027Y1M28D/4M10D"}

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(options) when is_list(options) do
    with :ok <- ensure_keyword_options(options),
         {:ok, options} <- resolve_through(options),
         :ok <- ensure_describes_span(options),
         from <- Keyword.get(options, :from),
         to <- Keyword.get(options, :to),
         :ok <- validate_endpoint_types(from, to),
         {from, to} = propagate_zone({from, to}),
         :ok <- validate_from_to_order(from, to),
         {:ok, unit} <- validate_unit(Keyword.get(options, :unit), from) do
      recurrence = Keyword.get(options, :recurrence, 1)
      duration = Keyword.get(options, :duration)
      repeat_rule = Keyword.get(options, :repeat_rule)
      metadata = Keyword.get(options, :metadata, %{})

      {:ok,
       %__MODULE__{
         from: from || :undefined,
         to: closing_endpoint(to, duration),
         duration: duration,
         recurrence: recurrence,
         repeat_rule: repeat_rule,
         unit: unit,
         metadata: metadata
       }}
    end
  end

  # `through:` closes the interval at the end of a value's span, so the
  # last day named is inside it.
  defp resolve_through(options) do
    case Keyword.pop(options, :through) do
      {nil, options} -> {:ok, options}
      {last, options} -> close_through(last, options)
    end
  end

  defp close_through(last, options) do
    if Keyword.has_key?(options, :to) or Keyword.has_key?(options, :duration) do
      {:error,
       ArgumentError.exception(
         "Tempo.Interval.new/1 takes one of :to, :through and :duration to close an interval."
       )}
    else
      with {:ok, end_of_last} <- span_end(last), do: {:ok, Keyword.put(options, :to, end_of_last)}
    end
  end

  defp span_end(%struct{} = last) when struct in [Tempo, __MODULE__] do
    case to(last) do
      {:error, _reason} = error -> error
      end_of_last -> {:ok, end_of_last}
    end
  end

  defp span_end(last) do
    {:error,
     ArgumentError.exception(
       "Tempo.Interval.new/1's :through is a Tempo value or interval, not #{inspect(last)}."
     )}
  end

  # The closing endpoint of an interval. When a `:duration` is supplied
  # and `:to` is omitted, the endpoint is *derived* from the duration, so
  # it is left as `nil` — the canonical shape the parser and `to_iso8601/1`
  # render as `from/duration` (or `R<n>/from/duration` when recurring). An
  # omitted `:to` with no duration is an explicitly *open* endpoint
  # (`2020/..`), represented as `:undefined`.
  defp closing_endpoint(nil, %Duration{}), do: nil
  defp closing_endpoint(nil, _no_duration), do: :undefined
  defp closing_endpoint(to, _duration), do: to

  @doc """
  Bang variant of `new/1`. Raises on invalid input.
  """
  @spec new!(keyword()) :: t()
  def new!(options) when is_list(options) do
    case new(options) do
      {:ok, iv} -> iv
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, "Tempo.Interval.new!/1 failed: #{inspect(reason)}"
    end
  end

  @doc """
  Construct a bounded `t:t/0` from two concrete endpoints.

  The positional companion to `new/1` for the common case — a
  closed interval `[from, to)` from two `%Tempo{}` values. Equivalent
  to `new(from: from, to: to)`, but reads as the two nouns it is.
  For the `:duration`, `:recurrence`, `:repeat_rule`, or `:metadata`
  forms — or an open-ended endpoint (`:undefined`) — use the
  keyword `new/1`, where the labels earn their place.

  ### Arguments

  * `from` is the start `t:Tempo.t/0` (inclusive).

  * `to` is the end `t:Tempo.t/0` (exclusive), and must be strictly
    later than `from`.

  ### Returns

  * `{:ok, interval}` on success.

  * `{:error, reason}` when the endpoints are of incompatible
    calendars, or `from` is not strictly earlier than `to`.

  ### Examples

      iex> {:ok, iv} = Tempo.Interval.new(~o"2026-06-15T09", ~o"2026-06-15T17")
      iex> iv.from.time
      [year: 2026, month: 6, day: 15, hour: 9]

  """
  @spec new(Tempo.t(), Tempo.t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%Tempo{} = from, %Tempo{} = to) do
    new(from: from, to: to)
  end

  @doc """
  Bang variant of `new/2`. Raises on invalid input.

  ### Examples

      iex> iv = Tempo.Interval.new!(~o"2026-06-15T09", ~o"2026-06-15T17")
      iex> iv.to.time
      [year: 2026, month: 6, day: 15, hour: 17]

  """
  @spec new!(Tempo.t(), Tempo.t()) :: t()
  def new!(%Tempo{} = from, %Tempo{} = to) do
    new!(from: from, to: to)
  end

  defp ensure_keyword_options(options) do
    cond do
      not Keyword.keyword?(options) ->
        {:error,
         ArgumentError.exception(
           "Tempo.Interval.new/1 expects a keyword list; got #{inspect(options)}"
         )}

      unknown = Enum.find(Keyword.keys(options), &(&1 not in @public_new_options)) ->
        {:error,
         ArgumentError.exception(
           "Tempo.Interval.new/1 does not recognise option #{inspect(unknown)}. " <>
             "Valid options: #{inspect(@public_new_options)}"
         )}

      true ->
        :ok
    end
  end

  defp ensure_describes_span(options) do
    if Keyword.has_key?(options, :from) or Keyword.has_key?(options, :to) or
         Keyword.has_key?(options, :duration) do
      :ok
    else
      {:error,
       ArgumentError.exception(
         "Tempo.Interval.new/1 requires at least one of :from, :to, or :duration."
       )}
    end
  end

  defp validate_endpoint_types(from, to) do
    cond do
      not valid_endpoint?(from) ->
        {:error,
         ArgumentError.exception(":from must be a %Tempo{} or :undefined, got #{inspect(from)}")}

      not valid_endpoint?(to) ->
        {:error,
         ArgumentError.exception(":to must be a %Tempo{} or :undefined, got #{inspect(to)}")}

      true ->
        :ok
    end
  end

  @doc false
  # A single interval names one span, and a span cannot straddle the
  # floating and universal time lines — so a zone or offset on either
  # endpoint applies to a floating other. Forward, from the start to the
  # end, is ISO 8601-1 §5.5.1: "Representations for time zones and UTC
  # included with the component preceding the separator shall be assumed
  # to apply to the component following the separator" —
  # `2018-01-15T10:00+05:00/2018-02-20T10:00` ends at +05:00 too. Backward,
  # from the end to the start, is where IXDTF binds a trailing `[zone]`.
  # Propagation never overwrites a frame an endpoint carries, so two zoned
  # endpoints keep their own. The zone's rule serves the parser and `new/1`,
  # so a constructed interval and its re-parsed ISO 8601 string cannot
  # disagree.
  #
  # The calendar's rule is the parser's alone. In text a trailing `[u-ca=…]`
  # is how both ends are written; two values given to `new/1` are each in the
  # calendar they have, and naming the start's units as the end's calendar
  # would make 1 January 2025 a day of the Hebrew year 2025. The rule reads
  # the name a suffix gave an endpoint, which an endpoint holds only while
  # its text is being read: the parser drops it once the calendars are
  # settled, so for any other pair of values this rule does nothing.
  def propagate_endpoint_frame(%Tempo{} = from, %Tempo{} = to) do
    {from, to}
    |> propagate_zone()
    |> propagate_calendar()
  end

  def propagate_endpoint_frame(from, to), do: {from, to}

  defp propagate_zone({%Tempo{} = from, %Tempo{} = to}),
    do: propagate_zone(from, to, Tempo.floating?(from), Tempo.floating?(to))

  defp propagate_zone({from, to}), do: {from, to}

  defp propagate_zone(from, to, true = _floating_from, false = _floating_to),
    do: {copy_frame(to, from), to}

  defp propagate_zone(from, to, false = _floating_from, true = _floating_to),
    do: {from, copy_frame(from, to)}

  defp propagate_zone(from, to, _floating_from, _floating_to), do: {from, to}

  # A `[u-ca=…]` at the end names the calendar the interval is written in,
  # and an endpoint carrying none of its own inherits it — the same
  # backward flow as the zone. Without this,
  # `1448Y9M24D/25D[u-ca=islamic-civil]` parses as a *mixed*
  # Gregorian/Islamic pair, which cannot be what it means: the abbreviated
  # `25D` is only readable against `from`'s own year and month.
  #
  # Never overwrites, so a deliberately mixed pair
  # (`1447Y9M1D[u-ca=islamic-civil]/2026Y6M1D`) and a pair tagging both
  # ends keep exactly the calendars they name.
  defp propagate_calendar({%Tempo{} = from, %Tempo{} = to}) do
    if is_nil(tagged_calendar(from)) and not is_nil(tagged_calendar(to)) do
      {copy_calendar(to, from), to}
    else
      {from, to}
    end
  end

  defp tagged_calendar(%Tempo{extended: %{calendar: calendar}}) when not is_nil(calendar),
    do: calendar

  defp tagged_calendar(%Tempo{}), do: nil

  defp copy_calendar(%Tempo{} = source, %Tempo{} = target) do
    %{
      target
      | calendar: source.calendar,
        extended: put_calendar_field(target.extended, tagged_calendar(source))
    }
  end

  defp put_calendar_field(nil, calendar) do
    %{zone_id: nil, zone_offset: nil, zone_critical: false, calendar: calendar, tags: %{}}
  end

  defp put_calendar_field(target_extended, calendar) do
    Map.put(target_extended, :calendar, calendar)
  end

  # Overlay `source`'s zone frame — its numeric `shift` and the zone
  # fields of its `extended` — onto `target`, leaving target's own units,
  # calendar, and tags untouched.
  defp copy_frame(%Tempo{} = source, %Tempo{} = target) do
    %{target | shift: source.shift, extended: put_zone_fields(target.extended, source.extended)}
  end

  defp put_zone_fields(target_extended, nil), do: target_extended

  # A source whose frame is its numeric shift alone has no zone to give a
  # target that has no annotations.
  defp put_zone_fields(nil, %{zone_id: nil, zone_offset: nil}), do: nil

  defp put_zone_fields(nil, %{zone_id: zone_id, zone_offset: zone_offset} = source) do
    %{
      zone_id: zone_id,
      zone_offset: zone_offset,
      zone_critical: Map.get(source, :zone_critical, false),
      tags: %{}
    }
  end

  defp put_zone_fields(target_extended, %{zone_id: zone_id, zone_offset: zone_offset} = source) do
    %{
      target_extended
      | zone_id: zone_id,
        zone_offset: zone_offset,
        zone_critical: Map.get(source, :zone_critical, false)
    }
  end

  # The iteration `:unit` must be a walkable unit and — when `:from` is a
  # concrete endpoint — equal to or finer than its resolution: the walk
  # fills the endpoint down to `unit`, and there is nothing to fill toward
  # a coarser unit. A unit equal to the endpoint resolution adds nothing
  # over the derived default, so it normalises to `nil`.
  defp validate_unit(nil, _from), do: {:ok, nil}

  defp validate_unit(unit, from) when is_atom(unit) and unit in @iteration_units do
    case endpoint_resolution_unit(from) do
      nil ->
        {:ok, unit}

      resolution_unit ->
        case Unit.compare(unit, resolution_unit) do
          # Finer units carry a smaller sort key, so :lt means finer.
          :lt -> {:ok, unit}
          :eq -> {:ok, nil}
          :gt -> {:error, coarser_unit_error(unit, resolution_unit)}
        end
    end
  end

  defp validate_unit(unit, _from) do
    {:error, InvalidUnitError.exception(unit: unit, valid_units: @iteration_units)}
  end

  defp endpoint_resolution_unit(%Tempo{} = from), do: from |> Tempo.resolution() |> elem(0)
  defp endpoint_resolution_unit(_from), do: nil

  defp coarser_unit_error(unit, resolution_unit) do
    ArgumentError.exception(
      ":unit must be equal to or finer than the resolution of :from " <>
        "(#{inspect(resolution_unit)}), got #{inspect(unit)}"
    )
  end

  defp valid_endpoint?(nil), do: true
  defp valid_endpoint?(:undefined), do: true
  defp valid_endpoint?(%Tempo{}), do: true
  defp valid_endpoint?(_other), do: false

  # The ends are ordered as the points their spans start at, so an end written
  # as a mask or a group (`202X`, `20C`) is in order where its span is. Two
  # ends with no order (one with a year and one without) are that error.
  defp validate_from_to_order(%Tempo{} = from, %Tempo{} = to) do
    case Compare.order(from, to) do
      {:ok, :earlier} ->
        :ok

      {:ok, :same} ->
        same_ends(%__MODULE__{from: from, to: to})

      {:ok, :later} ->
        later_start(%__MODULE__{from: from, to: to})

      {:error, _exception} = error ->
        error
    end
  end

  defp validate_from_to_order(_from, _to), do: :ok

  # A span with no year that ends where it starts is once round its cycle
  # (`T0H/T0H`, the whole day). With a year it has no extent.
  defp same_ends(%__MODULE__{} = interval) do
    if Cycle.cyclic?(interval),
      do: :ok,
      else:
        {:error,
         IntervalEndpointsError.exception(
           interval: interval,
           operation: :new,
           reason:
             ":from and :to endpoints are equal — a zero-extent interval " <>
               "is not a valid interval under the half-open [from, to) convention. " <>
               "If the operation that produced these endpoints is set-theoretic, " <>
               "return an empty IntervalSet instead."
         )}
  end

  # A span with no year whose end is not after its start runs through the end
  # of its cycle (`T22H/T2H`, through midnight), as the parser reads it. With
  # a year it is an end before its start.
  defp later_start(%__MODULE__{} = interval) do
    if Cycle.cyclic?(interval),
      do: :ok,
      else:
        {:error,
         IntervalEndpointsError.exception(
           interval: interval,
           operation: :new,
           reason: ":from endpoint is later than :to endpoint"
         )}
  end

  @doc false
  # Internal constructor called by the parser / tokenizer pipeline.
  # Accepts tokenizer-emitted tagged-tuple shapes — not part of the
  # public API. Use `new/1` for developer-facing construction.

  ## Recurrence peeler

  def build([{:recurrence, recur} | rest]) do
    rest
    |> build()
    |> Map.put(:recurrence, recur)
  end

  ## Two-element forms: undefined endpoints

  def build([:undefined, :undefined]) do
    %__MODULE__{from: :undefined, to: :undefined}
  end

  def build([{_from_tag, time}, :undefined]) do
    %__MODULE__{from: AST.build(time), to: :undefined}
  end

  # A recurrence with an open start and no selection — `R/../P1W`, the inspect form
  # of a cron/`RRule` value that has no `:from`. The duration is the cadence,
  # kept as-is; the start stays `nil` (not `:undefined`) so it matches what
  # inspect renders and round-trips to the same value.
  def build([:undefined, {:duration, duration}]) do
    %__MODULE__{from: nil, duration: Duration.build(duration)}
  end

  # A recurrence over a domain set with no selection (`R/{2020Y..2030Y}/P1Y`).
  def build([{:domain, %Tempo.Set{} = domain}, {:duration, duration}]) do
    %__MODULE__{from: domain, duration: Duration.build(duration)}
  end

  def build([:undefined, {_to_tag, time}]) do
    %__MODULE__{from: :undefined, to: AST.build(time)}
  end

  ## Two-element forms with a duration (must precede the
  ## wildcard date/date clause below).

  def build([{:duration, duration}, {_to_tag, time}]) do
    %__MODULE__{
      from: :undefined,
      duration: Duration.build(duration),
      to: AST.build(time)
    }
  end

  def build([{_from_tag, time}, {:duration, duration}]) do
    %__MODULE__{from: AST.build(time), duration: Duration.build(duration)}
  end

  ## Two-element date/date form (wildcard; must be last among
  ## two-element clauses).

  def build([{_from_tag, from}, {_to_tag, to}]) do
    from = AST.build(from)

    %__MODULE__{from: from, to: to |> AST.build() |> inherit_from_start(from)}
  end

  ## Three-element forms with a repeat_rule.

  # A recurrence with an open start and a selection — `R/../P1W/FLT17H0M5KN`, the
  # inspect form of a cron schedule with no `:from`. Start stays `nil`; the
  # duration is the cadence and the selection is the repeat rule.
  def build([:undefined, {:duration, duration}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: nil,
      duration: Duration.build(duration),
      repeat_rule: AST.build(repeat_rule)
    }
  end

  # A recurrence over a domain set (`R/{2020Y..2030Y,^2026Y}/P1Y/FL…N`): the
  # `{…}` start (a `%Tempo.Set{}` with `^` exclusions, built by the parser) is
  # the recurrence's window, carried in `:from` and applied at materialisation.
  def build([
        {:domain, %Tempo.Set{} = domain},
        {:duration, duration},
        {:repeat_rule, repeat_rule}
      ]) do
    %__MODULE__{
      from: domain,
      duration: Duration.build(duration),
      repeat_rule: AST.build(repeat_rule)
    }
  end

  def build([{:duration, duration}, {_to_tag, to}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: :undefined,
      to: AST.build(to),
      duration: Duration.build(duration),
      repeat_rule: AST.build(repeat_rule)
    }
  end

  def build([{_from_tag, from}, {:duration, duration}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: AST.build(from),
      duration: Duration.build(duration),
      repeat_rule: AST.build(repeat_rule)
    }
  end

  def build([{_from_tag, from}, {_to_tag, to}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: AST.build(from),
      to: AST.build(to),
      repeat_rule: AST.build(repeat_rule)
    }
  end

  # ISO 8601-1:2019 §5.5.1: "For expression of a time interval by a
  # start and an end, higher order time scale components may be omitted
  # from the 'end of time interval' … In this case the omitted higher
  # order components from the 'start of time interval' expression
  # apply." So `2018-01-15/02-20` *is* `2018-01-15/2018-02-20`, and
  # `2025-08-28T09:00/T10:15` ends on the day it started.
  #
  # Applying them here rather than leaving the end short is what keeps
  # the value anchored. An end carrying only `[hour: 10, minute: 15]`
  # has no year, so it cannot be projected onto the time line at all —
  # `Tempo.Compare.to_utc_seconds/1` refuses it — while
  # `compare_endpoints/2` resolves it contextually and reports it equal
  # to the anchored form. One value, two answers, and the failure
  # surfaces far from the parse that caused it.
  defp inherit_from_start(%Tempo{time: to_units} = to, %Tempo{time: from_units} = from)
       when is_list(to_units) and is_list(from_units) do
    with [{coarsest, _value} | _rest] <- to_units,
         rank when is_integer(rank) <- unit_rank(coarsest) do
      borrowed = higher_order_than(from_units, rank)
      qualified_with_start(%{to | time: borrowed ++ to_units}, to, from, Keyword.keys(borrowed))
    else
      _not_inheritable -> to
    end
  end

  defp inherit_from_start(to, _from), do: to

  # The components an end takes from its start come as the start holds them,
  # qualified or not. An end qualified as a whole (`…/07-20?`, ISO 8601-2
  # §8.2.1) is qualified in every component, those it takes from the start
  # among them, as the same end written in full is.
  defp qualified_with_start(%Tempo{time: time} = completed, written, from, borrowed) do
    case Qualification.whole(written) do
      nil ->
        taken = Map.take(from.qualifications || %{}, borrowed)

        %{
          completed
          | qualifications: nil_if_empty(Map.merge(taken, written.qualifications || %{}))
        }

      qualification ->
        %{completed | qualifications: Qualification.complete(time, qualification)}
    end
  end

  defp nil_if_empty(qualifications) when map_size(qualifications) == 0, do: nil
  defp nil_if_empty(qualifications), do: qualifications

  # Only components strictly coarser than the end's own coarsest unit
  # are borrowed, and only while they remain plain values: a group, a
  # selection or a mask on the start says something about a *set* of
  # times, which cannot be read as the end's missing prefix.
  defp higher_order_than(from_units, rank) do
    Enum.take_while(from_units, fn {unit, value} ->
      is_integer(value) and
        case unit_rank(unit) do
          nil -> false
          from_rank -> from_rank > rank
        end
    end)
  end

  defp unit_rank(unit) when is_atom(unit) do
    case Unit.fetch_sort_key(unit) do
      {:ok, key} -> key
      :error -> nil
    end
  end

  defp unit_rank(_unit), do: nil

  ## Implicit → explicit materialisation
  ##
  ## `Tempo.to_interval/1` is the public entry point; the heavy
  ## lifting lives here so the logic is testable in isolation and
  ## stays close to the struct it produces.

  @doc """
  Given a fully-resolved `%Tempo{}`, compute the two endpoints of
  its implicit span under the half-open `[from, to)` convention.

  Returns `{:ok, {lower, upper}, unit}` where both bounds are
  `%Tempo{}` values at the input's own resolution and `unit` is the
  iteration granularity the implicit span walks at — the next-finer
  unit below the input's resolution (`nil` when the walk unit is
  simply the bounds' resolution, as for masked and grouped values).
  Returns `{:error, reason}` when the input has no finer unit that
  could produce a bounded span.

  The bounds are *not* drilled into the finer unit: `[year: 2022]`
  yields `[year: 2022] / [year: 2023]` with unit `:month`, not
  `2022-01 / 2023-01`. Extent keeps its stated resolution;
  granularity travels separately so `Tempo.to_interval/1` can carry
  it on the interval's `:unit` field. Masked values widen to the
  coarsest un-masked prefix and use the internal mask-bounds helper
  to determine the enclosing span.

  """
  def next_unit_boundary(%Tempo{time: time, calendar: calendar} = tempo) do
    calendar = Compare.effective_calendar(calendar)
    time = significant_digits_as_mask(time)

    case List.last(time) do
      # A group at the finest unit — `20C` (century =
      # `{:group, 2000..2099}` on year), `201J` (decade), `1G6M`
      # (first six-month group) — is a *contiguous* span of
      # `[first, last]` at that unit. Materialise it to the enclosing
      # half-open interval `[unit=first, unit=last+1)`. The upper
      # bound is `add_unit(unit=last)` so it carries (month 12 → next
      # January). Handling it here avoids the `ArithmeticError` that
      # `add_unit(:year)` raises on a `{:group, …}` year value, and
      # gives the right bounds for grouped months too (the generic
      # path widened them to a full year).
      {unit, {:group, %Range{first: first, last: last}}} ->
        group_boundary(tempo, time, unit, first, last, calendar)

      _ ->
        case masked_widening(time) do
          {:ok, {lower_time, upper_time}} ->
            {:ok, build_bounds(tempo, lower_time, upper_time), nil}

          {:widen, prefix, unit} ->
            widened_span(tempo, prefix, unit, calendar)

          {:error, _} = err ->
            err

          :no_mask ->
            concrete_boundary(tempo, calendar)
        end
    end
  end

  # Materialise a group (`{:group, first..last}` at the finest unit)
  # to the enclosing half-open span `[unit=first, unit=last+1)`. The
  # upper bound is `add_unit(unit=last)` so it carries correctly, and a
  # group that runs past its container ends with it: the last group of
  # eleven days in February 2018 (`2018Y2M3G11DU`) ends on 1 March.
  #
  # `add_unit` at a date unit needs the coarser units present to
  # carry (days-in-month needs year+month; months-in-year needs
  # year), and the carry can cascade up to year. A group materialises
  # only when its value carries that contiguous anchored prefix; a
  # unanchored fragment (`5G10DU` — days 41..50, no year) does not,
  # and has no concrete span. A year alone anchors a group of its weeks,
  # its days (`1933Y1G80DU`, the first eighty) or its hours
  # (`2018Y20GT12HU`, noon to midnight on 10 January), which
  # materialise as the dates and times they cover. Checking the prefix
  # up front keeps the path total without a `rescue`.
  defp group_boundary(tempo, time, unit, first, last, calendar) do
    prefix = List.delete_at(time, -1)

    case Group.container_maximum(prefix, unit, calendar) do
      maximum when is_integer(maximum) and first > maximum ->
        group_error(tempo)

      maximum ->
        last = if is_integer(maximum), do: min(last, maximum), else: last
        bounded_group_boundary(tempo, prefix, unit, first, last, calendar)
    end
  end

  defp bounded_group_boundary(tempo, [year: year], unit, first, last, calendar)
       when unit in [:day, :hour] do
    lower_time = year_counted_time(year, unit, first, calendar)

    with {:ok, upper_time} <-
           Math.add_unit(year_counted_time(year, unit, last, calendar), unit, calendar) do
      {:ok, build_bounds(tempo, lower_time, upper_time), nil}
    end
  end

  defp bounded_group_boundary(tempo, prefix, unit, first, last, calendar) do
    cond do
      group_required_units(unit) == :not_a_group_unit ->
        group_error(tempo)

      # Fully anchored: the carry chain up to year is satisfied.
      anchored_prefix?(prefix, unit) ->
        materialise_group(tempo, prefix, unit, first, last, calendar)

      # A *pure* time-of-day group (no date components) materialises to
      # an **unanchored** interval — the relative span it denotes on
      # the time-of-day axis (`T16H1GT15MU` is `16:00..16:15`) — provided the upper
      # bound's carry stays within the present time units and cannot
      # overflow into an absent day. The result lives on the
      # time-of-day axis until anchored (see `guides/interop.md`); it
      # cannot project to UTC, so `duration/1`, Allen comparison, and
      # set operations require anchoring it first. Date groups and
      # partially-dated values still require anchoring.
      time_of_day_unit?(unit) and pure_time_of_day?(prefix) and
          carry_safe?(prefix ++ [{unit, last}], unit) ->
        materialise_group(tempo, prefix, unit, first, last, calendar)

      true ->
        group_error(tempo)
    end
  end

  defp materialise_group(tempo, prefix, unit, first, last, calendar) do
    lower_time = prefix ++ [{unit, first}]

    with {:ok, upper_time} <- Math.add_unit(prefix ++ [{unit, last}], unit, calendar) do
      {:ok, build_bounds(tempo, lower_time, upper_time), nil}
    end
  end

  # The date of a day of the year, or the date and hour of an hour of the
  # year (counted from 0), as the calendar numbers them.
  defp year_counted_time(year, :day, day_of_year, calendar) do
    date = Calendrical.date_from_day_of_year(year, day_of_year, calendar)
    [year: date.year, month: date.month, day: date.day]
  end

  defp year_counted_time(year, :hour, hour_of_year, calendar) do
    year
    |> year_counted_time(:day, div(hour_of_year, @hours_per_day) + 1, calendar)
    |> Kernel.++(hour: rem(hour_of_year, @hours_per_day))
  end

  defp anchored_prefix?(prefix, unit) do
    Enum.all?(group_required_units(unit), &Keyword.has_key?(prefix, &1))
  end

  defp group_error(tempo) do
    {:error, ConversionError.exception(value: tempo, reason: :unanchored_group)}
  end

  defp time_of_day_unit?(unit), do: unit in [:hour, :minute, :second]

  defp pure_time_of_day?(prefix) do
    not Enum.any?([:year, :month, :day, :week], &Keyword.has_key?(prefix, &1))
  end

  # `Math.add_unit` carries when a unit is at its maximum; the carry
  # needs the next-coarser unit present, recursively. For a pure
  # time-of-day value the chain tops out at `:hour` → `:day`, so a carry
  # off the top of the day (no `:day` present) is unsafe.
  defp carry_safe?(time, unit) do
    if Keyword.get(time, unit) < unit_max(unit) do
      true
    else
      case coarser_time_unit(unit) do
        :day -> false
        coarser -> Keyword.has_key?(time, coarser) and carry_safe?(time, coarser)
      end
    end
  end

  defp unit_max(:hour), do: 23
  defp unit_max(:minute), do: 59
  defp unit_max(:second), do: 59

  defp coarser_time_unit(:second), do: :minute
  defp coarser_time_unit(:minute), do: :hour
  defp coarser_time_unit(:hour), do: :day

  # The coarser units `add_unit`'s carry can reach from each unit.
  # Their presence guarantees the carry chain is well-defined, so
  # materialisation cannot raise. Units outside the standard
  # year→second chain aren't materialisable as a span.
  defp group_required_units(:year), do: []
  defp group_required_units(:month), do: [:year]
  defp group_required_units(:week), do: [:year]
  defp group_required_units(:day), do: [:year, :month]
  defp group_required_units(:hour), do: [:year, :month, :day]
  defp group_required_units(:minute), do: [:year, :month, :day, :hour]
  defp group_required_units(:second), do: [:year, :month, :day, :hour, :minute]
  defp group_required_units(_other), do: :not_a_group_unit

  # Concrete (non-masked) path: drill to the implicit-enumerator unit
  # for the lower bound, then add one unit at the input's resolution
  # for the upper bound.

  defp concrete_boundary(%Tempo{time: time} = tempo, calendar) do
    time = Compare.drop_margin_of_error(time)

    case List.last(time) do
      # Sub-second resolution is the finest unit and cannot drill into a
      # finer one, so the lower bound is the value as-is and the upper
      # bound is one unit-in-the-last-place larger: `45.123` (precision
      # 3) spans `[45.123, 45.124)`, i.e. +1000 µs; `45.123456`
      # (precision 6) spans a single microsecond.
      {:microsecond, {_value, _precision}} ->
        with {:ok, bounds} <- span_bounds(tempo, time, :microsecond, calendar) do
          {:ok, bounds, nil}
        end

      # A second-resolution value is no longer the finest unit once
      # sub-second (microsecond) resolution exists below it, so it
      # materialises to a one-second span rather than erroring. Like
      # the microsecond case the lower bound is the value as-is and
      # the upper is one second later, keeping both endpoints at
      # second resolution instead of drilling into microseconds.
      {:second, _value} ->
        with {:ok, bounds} <- span_bounds(tempo, time, :second, calendar) do
          {:ok, bounds, nil}
        end

      _ ->
        {unit, _span} = Tempo.resolution(tempo)

        case Unit.implicit_enumerator(unit, calendar) do
          nil ->
            {:error, ConversionError.exception(value: tempo, reason: :finest_resolution)}

          {next_unit, _range} ->
            implicit_span(tempo, time, unit, next_unit, calendar)
        end
    end
  end

  # The implicit span is one unit wide at the value's own resolution — a
  # day spans `[day, day+1)`, not `[day T0H, day+1 T0H)`. The next-finer
  # unit is returned separately as the iteration granularity; the walk
  # fills the start to it at iteration time (`Steps.fill_to_unit/3`).
  defp implicit_span(tempo, time, unit, next_unit, calendar) do
    with {:ok, bounds} <- span_bounds(tempo, time, unit, calendar) do
      {:ok, bounds, Unit.walked_by(next_unit, calendar)}
    end
  end

  # The span runs to one unit past the value. A clock unit of a value in
  # a named zone is a unit of elapsed time, ending on the reading the wall
  # clock shows then (`Tempo.Math.add/2`): the hour a fall-back repeats
  # ends where its second occurrence begins, and the hour before a
  # spring-forward gap ends on the gap's far side. A day in a named zone
  # ends on the next day the zone has: 29 December 2011 in Samoa ends where
  # the 31st begins, the zone having left the 30th out.
  defp span_bounds(%Tempo{extended: %{zone_id: zone}} = tempo, time, unit, _calendar)
       when is_binary(zone) and unit in [:hour, :minute, :second, :microsecond],
       do: bounds_by_the_clock(tempo, time, unit)

  # Nearly every zone leaves no day out, and a day in one ends on the day
  # after it as a day in no zone does.
  defp span_bounds(%Tempo{extended: %{zone_id: zone}} = tempo, time, :day, calendar)
       when is_binary(zone) do
    if TimeZoneDatabase.days_left_out(zone) == [],
      do: bounds_by_the_calendar(tempo, time, :day, calendar),
      else: bounds_by_the_clock(tempo, time, :day)
  end

  defp span_bounds(tempo, time, unit, calendar),
    do: bounds_by_the_calendar(tempo, time, unit, calendar)

  defp bounds_by_the_clock(tempo, time, unit) do
    lower = %{tempo | time: time}

    case Math.add(lower, one_unit(unit, time)) do
      %Tempo{} = upper -> {:ok, {lower, upper}}
      {:error, _reason} = error -> error
    end
  end

  defp bounds_by_the_calendar(tempo, time, unit, calendar) do
    with {:ok, upper_time} <- Math.add_unit(time, unit, calendar) do
      {:ok, build_bounds(tempo, time, upper_time)}
    end
  end

  # One unit in the last place: a microsecond value's unit is its
  # precision's.
  defp one_unit(:microsecond, time) do
    {_value, precision} = Keyword.fetch!(time, :microsecond)
    %Duration{time: [microsecond: {Integer.pow(10, 6 - precision), precision}]}
  end

  defp one_unit(unit, _time), do: %Duration{time: [{unit, 1}]}

  defp widened_span(tempo, prefix, unit, calendar) do
    with {:ok, upper_time} <- Math.add_unit(prefix, unit, calendar) do
      {:ok, build_bounds(tempo, prefix, upper_time), nil}
    end
  end

  # A `Range` supplied by `Unit.implicit_enumerator/2` — we take
  # its first value as the unit's start-of-span.
  # ISO 8601-2 significant digits (`1950S3`) denote the block of values
  # sharing the leading `n` digits — `1950S3` is the decade `1950..1959`,
  # exactly the mask `195X`. For crisp materialisation the annotation is
  # rewritten to its equivalent mask so the existing mask-widening path
  # (terminal, non-terminal, and negative alike) produces the enclosing
  # span. The annotation is preserved on the original value — only this
  # materialisation copy is rewritten. `n` covering every digit is a
  # no-op (the value is already exact); other annotations are left as-is.
  @doc false
  @spec significant_digits_as_mask(list()) :: list()
  def significant_digits_as_mask(time) do
    Enum.map(time, fn
      {unit, {value, options}} when is_list(options) and is_integer(value) ->
        case Keyword.get(options, :significant_digits) do
          n when is_integer(n) and n > 0 -> {unit, significant_digits_mask(value, n)}
          _ -> {unit, {value, options}}
        end

      other ->
        other
    end)
  end

  defp significant_digits_mask(value, n) do
    digits = Integer.digits(abs(value))

    if n >= length(digits) do
      value
    else
      masked = Enum.take(digits, n) ++ List.duplicate(:X, length(digits) - n)
      if value < 0, do: {:mask, [:negative | masked]}, else: {:mask, masked}
    end
  end

  # Mask path: scan the time list for the first masked unit.
  # The rule:
  #
  # * If the first masked unit is `:year` (the only unit whose
  #   mask-bounds translate directly to an integer range — every
  #   digit position contributes a power of ten), use the mask
  #   bounds. Honour `[:negative | …]` by flipping sign.
  #
  # * If the first masked unit is ANY OTHER unit (`:month`,
  #   `:day`, `:week`, etc.), the mask doesn't map cleanly to the
  #   unit's valid range (a two-digit `XX` month mask nominally
  #   spans `00..99`, but only `01..12` are valid). In that case we
  #   widen to the PARENT — take the un-masked prefix as the lower
  #   bound and increment it at the coarsest stated unit. This
  #   matches the plan's "widest enclosing bound" rule:
  #   `1985-XX-XX` → `[1985, 1986)`.

  defp masked_widening(time) do
    case find_first_mask(time, []) do
      nil -> :no_mask
      {prefix, :year, mask} -> year_mask_bounds(prefix, mask)
      {prefix, _unit, _mask} -> parent_widen(prefix)
    end
  end

  defp find_first_mask([], _acc), do: nil

  defp find_first_mask([{unit, {:mask, mask}} | _rest], acc) do
    {Enum.reverse(acc), unit, mask}
  end

  # An unspecified unit other than the year (`X*D`, any day) is every value
  # the unit takes, as one with every digit masked is (`XXD`), so it widens
  # to the units before it.
  defp find_first_mask([{unit, :any} | _rest], acc) when unit != :year do
    {Enum.reverse(acc), unit, :any}
  end

  defp find_first_mask([entry | rest], acc) do
    find_first_mask(rest, [entry | acc])
  end

  # Year mask — both positive and negative.
  # Positive: `[1, 5, 6, :X]` → magnitude range `(1560, 1569)` → interval `[1560, 1570)`.
  # Negative: `[:negative, 1, :X, :X, :X]` → magnitude `(1000, 1999)` →
  #           signed values range from -1999 (most negative) to -1000
  #           (least negative), half-open upper = -999.
  defp year_mask_bounds([], [:negative | digits]) do
    {mag_min, mag_max} = Mask.mask_bounds(digits)
    {:ok, {[year: -mag_max], [year: -mag_min + 1]}}
  end

  defp year_mask_bounds([], digits) do
    {min, max} = Mask.mask_bounds(digits)
    {:ok, {[year: min], [year: max + 1]}}
  end

  # A year mask appearing after some prefix doesn't make sense in
  # ISO 8601 — year is the coarsest unit. We leave it as a noop
  # rather than crash; callers will see the original time unchanged.
  defp year_mask_bounds(_prefix, _mask), do: :no_mask

  # Widen to the parent: use the un-masked prefix as the lower
  # bound, increment the coarsest stated unit for the upper bound.
  # `1985-XX-XX` → prefix `[year: 1985]` → `[[year: 1985], [year: 1986]]`.
  defp parent_widen([]) do
    # No un-masked prefix — nothing to place the span on. Shouldn't
    # happen in practice (the parser always resolves a year before
    # finer units can appear), but return a clear error if it does.
    {:error,
     ConversionError.exception(
       reason:
         "Cannot convert a masked Tempo with no un-masked coarser unit to an interval — " <>
           "nothing to place the span on."
     )}
  end

  defp parent_widen(prefix) do
    # Use the LAST (finest) un-masked unit as the span's unit.
    {unit, _value} = List.last(prefix)
    # Resolve any inner ranges/masks we might not have caught — not
    # expected here, but if the prefix contains non-scalar values
    # we can't increment cleanly. Pull out just the scalar case.
    if Enum.all?(prefix, fn {_u, v} -> is_integer(v) end) do
      # We need a calendar to call add_unit. Embed the increment
      # inside the outer next_unit_boundary flow — signal via a
      # shape that the caller then materialises with the source
      # tempo's calendar.
      {:widen, prefix, unit}
    else
      {:error,
       ConversionError.exception(
         reason:
           "Cannot convert a masked Tempo whose un-masked prefix contains ranges, " <>
             "selections or other non-scalar values to an interval."
       )}
    end
  end

  defp build_bounds(%Tempo{} = source, lower_time, upper_time) do
    lower = %{source | time: lower_time}
    upper = %{source | time: upper_time}
    {lower, upper}
  end

  ## ----------------------------------------------------------
  ## Allen's interval algebra
  ## ----------------------------------------------------------

  @doc """
  Classify the Allen relation between two interval-like values.

  Returns one of 13 mutually exclusive relations from Allen's
  interval algebra — a richer answer than stdlib's ternary
  `compare/2` (`:lt` / `:eq` / `:gt`), which collapses intervals
  to their start points and loses the containment and overlap
  distinctions that interval algebra captures. Hence the name
  `relation` rather than `compare`.

  For intervals `X = [x₁, x₂)` and `Y = [y₁, y₂)` under Tempo's
  half-open convention:

  | Relation          | Shape (X relative to Y)          | Condition                      |
  | ----------------- | -------------------------------- | ------------------------------ |
  | `:precedes`       | X ends strictly before Y starts  | `x₂ < y₁`                      |
  | `:meets`          | X ends exactly at Y's start      | `x₂ = y₁`                      |
  | `:overlaps`       | X starts before Y, ends inside   | `x₁ < y₁ < x₂ < y₂`            |
  | `:finished_by`    | X contains Y, shared end         | `x₁ < y₁ ∧ x₂ = y₂`            |
  | `:contains`       | X strictly contains Y            | `x₁ < y₁ ∧ x₂ > y₂`            |
  | `:starts`         | Shared start, X ends earlier     | `x₁ = y₁ ∧ x₂ < y₂`            |
  | `:equals`         | Identical endpoints              | `x₁ = y₁ ∧ x₂ = y₂`            |
  | `:started_by`     | Shared start, X ends later       | `x₁ = y₁ ∧ x₂ > y₂`            |
  | `:during`         | X strictly inside Y              | `x₁ > y₁ ∧ x₂ < y₂`            |
  | `:finishes`       | X starts after Y, shared end     | `x₁ > y₁ ∧ x₂ = y₂`            |
  | `:overlapped_by`  | Y starts before X, ends inside X | `y₁ < x₁ < y₂ < x₂`            |
  | `:met_by`         | X starts exactly at Y's end      | `x₁ = y₂`                      |
  | `:preceded_by`    | X starts strictly after Y's end  | `x₁ > y₂`                      |

  Every pair of non-empty bounded intervals stands in exactly
  one of these relations. `Tempo.Allen` has a predicate for each,
  and the inverse (`Tempo.Allen.inverse/1`) and composition
  (`Tempo.Allen.compose/2`) of relations.

  ### Arguments

  * `a` and `b` are each one of:

    * a `t:Tempo.t/0` point (converted to its implicit span).

    * a `t:Tempo.Interval.t/0`.

    * a `t:Tempo.IntervalSet.t/0` with exactly one member.

  ### Returns

  * One of the 13 relation atoms.

  * `{:error, reason}` when either operand is a multi-member
    IntervalSet, an open-ended interval, or otherwise can't be
    reduced to a single bounded interval. For multi-member
    sets use `Tempo.IntervalSet.relation_matrix/2`.

  * `{:error, %Tempo.FloatingTempoError{}}` when one operand is zoned
    and the other floating: a value with no zone has no place on the
    universal time line to relate from.

  * `{:error, %Tempo.UnanchoredError{}}` when one operand has a year
    and the other none, or neither has and they lead with different
    units: they share no line to be related on.

  ### Examples

      iex> a = Tempo.Interval.new!(from: ~o"2026-06-01", to: ~o"2026-06-10")
      iex> b = Tempo.Interval.new!(from: ~o"2026-06-05", to: ~o"2026-06-15")
      iex> Tempo.Interval.relation(a, b)
      :overlaps

      iex> Tempo.Interval.relation(~o"2026Y", ~o"2026-06-15")
      :contains

  """
  @spec relation(interval_like(), interval_like()) :: relation() | {:error, term()}
  def relation(a, b) do
    with :ok <- same_frame(a, b),
         {:ok, iv_a} <- to_single_interval(a, :a),
         {:ok, iv_b} <- to_single_interval(b, :b) do
      classify(iv_a, iv_b)
    end
  end

  # Three endpoint comparisons drive the 13-way branch:
  # `a.from vs b.from`, `a.to vs b.to`, and the "seam" checks
  # `a.to vs b.from` / `a.from vs b.to` which disambiguate
  # disjoint (meets/precedes and their inverses) from
  # overlapping cases. Dispatched as a multi-head table on the four
  # comparisons — the head count is the size of Allen's 13-relation
  # algebra.
  #
  # Two spans with no line to share (one dated and one with no year) have
  # no relation, and the comparison's error says so.
  defp classify(%__MODULE__{from: a_from, to: a_to}, %__MODULE__{from: b_from, to: b_to}) do
    with {:ok, starts} <- Compare.order(a_from, b_from),
         {:ok, end_to_start} <- Compare.order(a_to, b_from),
         {:ok, start_to_end} <- Compare.order(a_from, b_to),
         {:ok, ends} <- Compare.order(a_to, b_to) do
      classify_relation(end_to_start, start_to_end, starts, ends)
    end
  end

  # Disjoint first: the end-to-start seams settle precedes/meets and
  # their inverses before the start/end positions are consulted.
  defp classify_relation(:earlier, _s_vs_be, _s, _e), do: :precedes
  defp classify_relation(:same, _s_vs_be, _s, _e), do: :meets
  defp classify_relation(_e_vs_bs, :later, _s, _e), do: :preceded_by
  defp classify_relation(_e_vs_bs, :same, _s, _e), do: :met_by

  # Overlapping: start (s = a.from vs b.from) and end (e = a.to vs b.to).
  defp classify_relation(_, _, :earlier, :earlier), do: :overlaps
  defp classify_relation(_, _, :earlier, :same), do: :finished_by
  defp classify_relation(_, _, :earlier, :later), do: :contains
  defp classify_relation(_, _, :same, :earlier), do: :starts
  defp classify_relation(_, _, :same, :same), do: :equals
  defp classify_relation(_, _, :same, :later), do: :started_by
  defp classify_relation(_, _, :later, :earlier), do: :during
  defp classify_relation(_, _, :later, :same), do: :finishes
  defp classify_relation(_, _, :later, :later), do: :overlapped_by

  # A recurring interval is a rule generating occurrences, not a single
  # span — classifying it as one would silently read only the base
  # extent. The error directs to materialisation and the set-level API.
  defp to_single_interval(%__MODULE__{recurrence: recurrence} = interval, _label)
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    {:error, ConversionError.exception(value: interval, reason: :recurring_interval)}
  end

  # A span with no year is read on its cycle: one that ends where the cycle
  # does (`T23H/T0H`) is the one span up to its end, and one that runs past
  # it is two spans, with no one relation.
  defp to_single_interval(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = iv, _label) do
    with {:ok, %__MODULE__{} = span} <- endpoints_as_points(iv) do
      if Cycle.cyclic?(span), do: Cycle.one_part(span), else: {:ok, span}
    end
  end

  defp to_single_interval(%IntervalSet{} = set, label) do
    case IntervalSet.members(set) do
      [iv] -> {:ok, iv}
      ivs -> multi_member_error(ivs, label)
    end
  end

  defp to_single_interval(%Tempo{} = point, label) do
    case Tempo.to_interval(point) do
      {:ok, %__MODULE__{} = iv} -> to_single_interval(iv, label)
      {:ok, %IntervalSet{} = set} -> to_single_interval(set, label)
      {:error, _} = err -> err
    end
  end

  # A start and a duration, or a duration and an end, is as bounded as two
  # stated endpoints.
  defp to_single_interval(%__MODULE__{duration: %Duration{}} = interval, label) do
    case resolve_duration_form(interval) do
      %__MODULE__{from: %Tempo{}, to: %Tempo{}} = resolved -> {:ok, resolved}
      _unresolved -> open_ended_error(label)
    end
  end

  defp to_single_interval(%__MODULE__{}, label), do: open_ended_error(label)

  # A one-of set is an epistemic disjunction — it has no single crisp
  # relation, only a set of possible ones. The crisp API refuses with the
  # same error `to_interval/1` gives; the certainty API (`relation_certainty/3`,
  # `possibly_before?/2`, …) answers the question the set can actually support.
  defp to_single_interval(%Tempo.Set{type: :one} = set, _label) do
    {:error, ConversionError.exception(value: set, reason: :one_of_set)}
  end

  defp to_single_interval(other, label) do
    {:error,
     ArgumentError.exception(
       "Tempo.Interval.relation/2 cannot classify operand #{inspect(label)}: " <>
         "#{inspect(other)}"
     )}
  end

  @doc false
  # An interval runs from the point its start's span starts at to the point
  # its end's span starts at. An end written as a group, a mask or significant
  # digits (`20C/21C`, `202X/2040`) is read as that point (`2000Y/2100Y`), so
  # it compares as the moment it is and not as the term it is written as. An
  # end that names several spans (a set, a selection, a mask whose values do
  # not run together) is no one point. One whose span starts at no point it
  # can name (`X*Y12M31D`, the 31 December of any year) is left as it is.
  @spec endpoints_as_points(t()) :: {:ok, t()} | {:error, Exception.t()}
  def endpoints_as_points(%__MODULE__{from: from, to: to} = interval) do
    with {:ok, from} <- endpoint_point(from, "start", interval),
         {:ok, to} <- endpoint_point(to, "end", interval),
         :ok <- one_line(from, to) do
      {:ok, %{interval | from: from, to: to}}
    end
  end

  # Ends with no line to share (a year beside a day of no year,
  # `2020Y/X*Y6M15D`) have no order, and so no span between them.
  defp one_line(%Tempo{} = from, %Tempo{} = to) do
    case Compare.orderable(from, to) do
      {:error, %UnanchoredError{}} = error -> error
      _ordered_or_no_one_point -> :ok
    end
  end

  defp one_line(_from, _to), do: :ok

  defp endpoint_point(%Tempo{time: time} = endpoint, end_name, interval) do
    if Compare.point?(time),
      do: {:ok, endpoint},
      else: endpoint |> Tempo.to_interval() |> span_start(endpoint, end_name, interval)
  end

  defp endpoint_point(endpoint, _end_name, _interval), do: {:ok, endpoint}

  defp span_start({:ok, %__MODULE__{from: %Tempo{time: time} = start}}, endpoint, _end, _iv),
    do: if(Compare.point?(time), do: {:ok, start}, else: {:ok, endpoint})

  defp span_start({:ok, %IntervalSet{} = set}, endpoint, end_name, interval) do
    case IntervalSet.bounded?(set) and IntervalSet.members(set) do
      [%__MODULE__{} = span] -> span_start({:ok, span}, endpoint, end_name, interval)
      _several -> {:error, several_spans_error(endpoint, end_name, interval)}
    end
  end

  defp span_start({:error, _exception} = error, _endpoint, _end_name, _interval), do: error
  defp span_start({:ok, _no_start}, endpoint, _end_name, _interval), do: {:ok, endpoint}

  defp several_spans_error(endpoint, end_name, interval) do
    IntervalEndpointsError.exception(
      interval: interval,
      reason:
        "#{inspect(interval)} has no one #{end_name}: #{inspect(endpoint)} names several " <>
          "spans (a set, a selection, or a mask whose values do not run together)."
    )
  end

  @doc false
  # Whether each end an interval has is one point, so that nothing in it
  # needs reading as the point its span starts at.
  @spec points?(t()) :: boolean()
  def points?(%__MODULE__{from: from, to: to}), do: end_point?(from) and end_point?(to)

  defp end_point?(%Tempo{time: time}), do: Compare.point?(time)
  defp end_point?(_absent), do: true

  defp open_ended_error(label) do
    {:error,
     ArgumentError.exception(
       "Tempo.Interval.relation/2 needs bounded intervals on both sides. " <>
         "Operand #{inspect(label)} has an open-ended endpoint (`:undefined`)."
     )}
  end

  defp multi_member_error(ivs, label) do
    {:error,
     ArgumentError.exception(
       "Tempo.Interval.relation/2 requires a single bounded interval on each side. " <>
         "Operand #{inspect(label)} is an IntervalSet with #{length(ivs)} members. " <>
         "For set-level questions use `Tempo.overlaps?/2`, `Tempo.disjoint?/2`, " <>
         "`Tempo.intersection/2`, or `Tempo.IntervalSet.relation_matrix/2`."
     )}
  end

  ## ----------------------------------------------------------
  ## Shape predicates
  ## ----------------------------------------------------------

  @doc """
  `true` when both endpoints are concrete `%Tempo{}` values —
  stated, or fixed by a start or an end and a duration
  (`2026-06-01/P9D`) — rather than `:undefined` or `nil`. Useful
  as a guard before set operations or duration checks.

  ### Examples

      iex> Tempo.Interval.bounded?(%Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"})
      true

      iex> Tempo.Interval.bounded?(~o"2026-06-01/P9D")
      true

      iex> Tempo.Interval.bounded?(%Tempo.Interval{from: ~o"2026-06-01", to: :undefined})
      false

      iex> Tempo.Interval.bounded?(~o"R3/2026-06-01/P1D")
      true

  """
  @spec bounded?(t()) :: boolean()
  # A recurrence of a count is as bounded as each of its occurrences: its
  # last ends where the count does.
  def bounded?(%__MODULE__{recurrence: count} = interval) when is_integer(count) and count > 1,
    do: bounded?(%{interval | recurrence: 1})

  def bounded?(%__MODULE__{} = interval) do
    case resolve_duration_form(interval) do
      %__MODULE__{from: %Tempo{}, to: %Tempo{}} ->
        true

      # A start, or an end, with a duration that is not counted from it here:
      # the start names several values (`2026Y6M{1,15}D/P1M`), and the span
      # from each of them is as long as the duration.
      %__MODULE__{recurrence: 1, from: %Tempo{}, to: to, duration: %Duration{}}
      when to in [nil, :undefined] ->
        true

      %__MODULE__{recurrence: 1, from: :undefined, to: %Tempo{}, duration: %Duration{}} ->
        true

      _open ->
        false
    end
  end

  @doc false
  # A bounded interval is written three ways: both endpoints, a start and a
  # duration (`2026-06-01/P9D`, `to: nil`), or a duration and an end
  # (`P9D/2026-06-10`, `from: :undefined` beside the duration). Everything
  # that reads one interval's endpoints works on the first form, so the other
  # two resolve to it here — as `Tempo.to_interval/1` resolves them for the set
  # operations — keeping the metadata, unit and direction. Anything else (a
  # recurrence, an open or unanchored interval, an endpoint holding a selection,
  # which stands for several spans) is returned unchanged.
  @spec resolve_duration_form(term()) :: term()
  def resolve_duration_form(
        %__MODULE__{recurrence: 1, from: %Tempo{}, to: to, duration: %Duration{}} = interval
      )
      when to in [nil, :undefined] do
    resolve_endpoints(interval)
  end

  def resolve_duration_form(
        %__MODULE__{recurrence: 1, from: :undefined, to: %Tempo{}, duration: %Duration{}} =
          interval
      ) do
    resolve_endpoints(interval)
  end

  def resolve_duration_form(value), do: value

  defp resolve_endpoints(interval) do
    case Tempo.to_interval(interval) do
      {:ok, %__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}} ->
        %{interval | from: from, to: to, duration: nil}

      _several_spans_or_error ->
        interval
    end
  end

  # The interval a measurement or a comparison reads: both endpoints, each
  # the point it names (`20C/2150` is `2000Y/2150Y`). An interval written
  # with a duration resolves to its endpoints first, and one whose end names
  # several spans is left as it is.
  defp measured_form(interval), do: interval |> resolve_duration_form() |> as_points()

  defp as_points(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = interval) do
    case endpoints_as_points(interval) do
      {:ok, points} -> points
      {:error, _several_spans} -> interval
    end
  end

  defp as_points(interval), do: interval

  @doc """
  `true` when the interval has zero or negative length —
  `from == to` (degenerate instant) or `from > to` (inverted
  span).

  Under the half-open `[from, to)` convention, an interval with
  `from >= to` contains no real instants. Empty intervals pass
  `bounded?/1` but have no span; inverted intervals are treated
  as empty rather than as a span with "negative" duration.

  A span with no year is on a cycle, and one whose end is before its
  start runs through the cycle's end: `~o"T22H/T2H"` is the four hours
  through midnight, and is not empty.

  ### Examples

      iex> Tempo.Interval.empty?(%Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-15"})
      true

      iex> Tempo.Interval.empty?(%Tempo.Interval{from: ~o"2026-06-20", to: ~o"2026-06-15"})
      true

      iex> Tempo.Interval.empty?(%Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"})
      false

      iex> Tempo.Interval.empty?(~o"T22H/T2H")
      false

      iex> Tempo.Interval.empty?(~o"T0H/T0H")
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to} = interval) do
    case Compare.compare_endpoints(from, to) do
      :earlier -> false
      # A span with no year that ends before it starts runs through the end
      # of its cycle (`T23H/T0H`, the last hour of the day), and one that
      # ends where it starts is once round it (`T0H/T0H`, the whole day).
      _same_or_later -> not Cycle.cyclic?(interval)
    end
  end

  def empty?(%__MODULE__{}), do: false

  ## ----------------------------------------------------------
  ## Duration query + duration predicates
  ## ----------------------------------------------------------

  @doc """
  Return the interval's `from` endpoint, or where the span a value
  names begins.

  A named helper so callers never have to reach into the struct
  fields in user-facing code. Compose with `Tempo.day/1`, `Tempo.year/1`,
  etc. to extract components of the starting point.

  ### Arguments

  * `interval` is a `t:t/0`, or a `t:Tempo.t/0`, which is the span it
    names: `~o"2026-06"` is June, and a selection that picks one day
    is that day.

  ### Returns

  * The `from` endpoint as a `t:Tempo.t/0` or `:undefined` for
    open-ended intervals.

  * `{:error, reason}` for a value naming no single span, such as a set
    of values, a selection picking several days or none, or 29 February
    without a year.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      iex> Tempo.Interval.from(iv) |> Tempo.day()
      15

      iex> Tempo.Interval.from(~o"2026-06")
      ~o"2026Y6M"

  The Friday that falls 7–13 April 2027 is the ninth:

      iex> Tempo.Interval.from(~o"2027YLLL4M7DN/P7DN5K1IN")
      ~o"2027Y4M9D"

  """
  @spec from(t() | Tempo.t()) :: Tempo.t() | :undefined | {:error, Exception.t()}
  def from(%__MODULE__{} = interval), do: resolve_duration_form(interval).from
  def from(%Tempo{} = value), do: with_span(value, &from/1)

  @doc """
  Return the interval's `to` endpoint, or where the span a value
  names ends.

  Under half-open `[from, to)` semantics, this is the exclusive
  upper bound — the first instant **outside** the span. A day ends
  where the next begins.

  ### Arguments

  * `interval` is a `t:t/0`, or a `t:Tempo.t/0`, which is the span it
    names: `~o"2026-06-15"` is that day.

  ### Returns

  * The `to` endpoint as a `t:Tempo.t/0` or `:undefined` for
    open-ended intervals.

  * `{:error, reason}` for a value naming no single span, such as a set
    of values, a selection picking several days or none, or 29 February
    without a year.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      iex> Tempo.Interval.to(iv) |> Tempo.day()
      20

      iex> Tempo.Interval.to(~o"2027-04-09")
      ~o"2027Y4M10D"

  """
  @spec to(t() | Tempo.t()) :: Tempo.t() | :undefined | {:error, Exception.t()}
  def to(%__MODULE__{} = interval), do: resolve_duration_form(interval).to
  def to(%Tempo{} = value), do: with_span(value, &to/1)

  # A value is the span it names, read through `Tempo.to_interval/1`: a
  # selection that picks one day is that day. One that names several spans,
  # or none, has no single start or end.
  defp with_span(%Tempo{} = value, endpoint) do
    case Tempo.to_interval(value) do
      {:ok, %__MODULE__{} = span} -> endpoint.(span)
      {:ok, %IntervalSet{} = spans} -> only_span(spans, value, endpoint)
      {:error, _reason} = error -> error
    end
  end

  defp only_span(spans, value, endpoint) do
    case IntervalSet.bounded?(spans) and IntervalSet.members(spans) do
      [span] -> endpoint.(span)
      [] -> {:error, no_span_error(value)}
      _several -> {:error, several_spans_error(value)}
    end
  end

  defp no_span_error(value) do
    ArgumentError.exception("#{inspect(value)} names no span: its selection picks nothing.")
  end

  defp several_spans_error(value) do
    ArgumentError.exception(
      "#{inspect(value)} names several spans, so it has no single start or end: " <>
        "take them from its interval set with Tempo.to_interval_set/1."
    )
  end

  @doc """
  Return the interval's endpoints as a `{from, to}` tuple.

  A named helper so callers never have to reach into the struct
  fields in user-facing code.

  ### Arguments

  * `interval` is a `t:t/0`.

  ### Returns

  * `{from, to}` where each endpoint is a `t:Tempo.t/0` or
    `:undefined` for open-ended intervals.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      iex> {from, to} = Tempo.Interval.endpoints(iv)
      iex> {Tempo.day(from), Tempo.day(to)}
      {15, 20}

  """
  @spec endpoints(t()) :: {Tempo.t() | :undefined, Tempo.t() | :undefined}
  def endpoints(%__MODULE__{} = interval) do
    %__MODULE__{from: from, to: to} = resolve_duration_form(interval)
    {from, to}
  end

  @doc false
  # The unit an interval is walked by: its explicit `:unit` when it carries
  # one, and otherwise the finer of the resolutions of its two ends, so its
  # values are the interval and none runs past its end (`2026/2026-03` is
  # January and February). An interval with no end to read steps by its
  # start's. The walk and the text an interval is shown as both read it here.
  @spec granularity(t()) :: Tempo.time_unit() | nil
  def granularity(%__MODULE__{unit: unit}) when not is_nil(unit), do: unit

  def granularity(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}),
    do: finer_unit(resolution_unit(from), resolution_unit(to))

  def granularity(%__MODULE__{from: %Tempo{} = from}), do: resolution_unit(from)
  def granularity(%__MODULE__{}), do: nil

  defp resolution_unit(%Tempo{} = endpoint), do: endpoint |> Tempo.resolution() |> elem(0)

  # A finer unit has the smaller sort key.
  defp finer_unit(unit, other) do
    if Unit.compare(other, unit) == :lt, do: other, else: unit
  end

  @doc """
  Return the metadata map attached to the interval.

  A named helper so callers never have to reach into the struct
  fields in user-facing code. Metadata is free-form and is
  preserved across set operations — intervals that survive a
  union, intersection, or difference inherit the surviving
  operand's metadata, so this accessor is the intended way to
  read iCal `SUMMARY`, `LOCATION`, event UIDs, and any other
  application-attached per-interval data.

  ### Arguments

  * `interval` is a `t:t/0`.

  ### Returns

  * The metadata map. An interval constructed without metadata
    returns `%{}`.

  ### Examples

      iex> iv = Tempo.Interval.new!(
      ...>   from: ~o"2026-06-15T09",
      ...>   to:   ~o"2026-06-15T10",
      ...>   metadata: %{summary: "Stand-up"}
      ...> )
      iex> Tempo.Interval.metadata(iv)
      %{summary: "Stand-up"}

      iex> iv = Tempo.Interval.new!(from: ~o"2026-06-15", to: ~o"2026-06-20")
      iex> Tempo.Interval.metadata(iv)
      %{}

  """
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{metadata: metadata}), do: metadata

  @doc """
  Return the interval's span resolution — the coarsest unit at
  which `from` and `to` differ.

  Under the half-open `[from, to)` convention, this is the unit
  that "ticks forward" across the span. `[2026-06-15, 2026-06-16)`
  ticks at the day; `[2026-06-01, 2026-07-01)` ticks at the month;
  `[2026, 2027)` ticks at the year.

  Unlike `Tempo.resolution/1` on a filled endpoint (which would
  report the finest unit present on the time keyword list after
  `Tempo.to_interval/1` has padded missing units with their
  minimums), this function reports the **span's** resolution —
  the authoritative scale of the interval itself.

  ### Arguments

  * `interval` is a `t:t/0`. Must be bounded (both endpoints
    present) — `:undefined` endpoints return `:undefined`.

  ### Returns

  * A unit atom (`:year`, `:month`, `:day`, `:hour`, `:minute`,
    `:second`, …), or `:undefined` for open-ended intervals.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"}
      iex> Tempo.Interval.resolution(iv)
      :day

      iex> iv = %Tempo.Interval{from: ~o"2026-06", to: ~o"2026-07"}
      iex> Tempo.Interval.resolution(iv)
      :month

  """
  @spec resolution(t()) :: Tempo.time_unit() | :undefined
  def resolution(%__MODULE__{from: :undefined}), do: :undefined
  def resolution(%__MODULE__{to: :undefined}), do: :undefined

  def resolution(%__MODULE__{from: %Tempo{time: from_time}, to: %Tempo{time: to_time}}) do
    span_resolution(from_time, to_time)
  end

  # The coarsest unit at which from and to differ is the span's
  # declared resolution. Walk left-to-right through from.time — the
  # first unit where from and to disagree is the answer. If they
  # agree at every unit present on `from`, fall through to the
  # finest present unit as the resolution.
  defp span_resolution(from_time, to_time) do
    Enum.reduce_while(from_time, finest_unit(from_time), fn {unit, fv}, acc ->
      case Keyword.get(to_time, unit) do
        nil -> {:halt, acc}
        ^fv -> {:cont, acc}
        _other -> {:halt, unit}
      end
    end)
  end

  defp finest_unit(time) do
    case List.last(time) do
      nil -> :day
      {unit, _} -> unit
    end
  end

  @doc """
  Return the interval's length as a `%Tempo.Duration{}`, counted in
  the unit its endpoints are written in.

  The unit is the finer of the endpoints' resolutions: two days are a
  number of days apart, two months a number of months, and a day and
  an hour a number of hours. A week against a month or a year is
  counted in days, since weeks do not divide them.

  Years, months, weeks and days are counted on the calendar with
  `Calendrical.diff/3`, so a month is one month however many days it
  has, and the day a daylight-saving change shortens is still one day.
  Hours, minutes and seconds are elapsed time on the UTC time line
  (`Tempo.Compare.to_utc_seconds/1`), so the same day measured in hours
  is 23 of them. Whatever is less than a whole unit — an hour-resolution
  span between zones half an hour apart, or a day-resolution span whose
  endpoints are in different zones — is kept in the finer units after
  it (`PT5H30M`, `P2DT1H`) rather than lost.

  A duration in months or years has no fixed number of seconds, so
  ordering it against another with `Tempo.Duration.compare/3` needs a
  `:relative_to` date.

  ### Arguments

  * `interval` is a `t:t/0`. One written as a start and a duration, or
    a duration and an end, is measured between the endpoints it
    resolves to. An endpoint that names a span — a century, a masked
    month, a selection that picks one day — is read from where its
    span starts, so `20C/2100` is a hundred years.

  ### Options

  * `:leap_seconds` — when `true`, adds one second to the
    returned duration for each IERS leap-second insertion that
    falls inside `[from, to)`. Defaults to `false` so behaviour
    matches `DateTime`, `Time`, and `:calendar` from Elixir/OTP
    (none of which count leap seconds). See
    `Tempo.Interval.spans_leap_second?/1` and
    `leap_seconds_spanned/1` for detection without arithmetic.

  ### Returns

  * A `t:Tempo.Duration.t/0` in the endpoints' unit. An empty or
    inverted interval has a duration of zero in that unit.

  * `:infinity` when one or both endpoints are `:undefined`, or for a
    recurrence without end.

  * `{:error, reason}` — a `Tempo.ConversionError` for a finite
    recurrence, bounded by a count or an RRULE `UNTIL`, whose length
    is its occurrences' (the
    `Tempo.IntervalSet.duration/1` of its interval set); a
    `Tempo.UnanchoredError` for an endpoint without a year; an
    `ArgumentError` for endpoints in different calendars, an endpoint
    naming several spans, a value that is not an interval, or an
    option this does not take.

  ### Examples

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-07-21"})
      ~o"P36D"

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-06", to: ~o"2026-09"})
      ~o"P3M"

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16T12"})
      ~o"PT36H"

  The day New York moves its clocks forward is one day, but 23 hours:

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-03-08[America/New_York]", to: ~o"2026-03-09[America/New_York]"})
      ~o"P1D"

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-03-08T00[America/New_York]", to: ~o"2026-03-09T00[America/New_York]"})
      ~o"PT23H"

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-06-15", to: :undefined})
      :infinity

      iex> Tempo.Interval.duration(~o"20C/2100")
      ~o"P100Y"

      iex> match?({:error, %Tempo.UnanchoredError{}}, Tempo.Interval.duration(~o"T09/T17"))
      true

      iex> iv = %Tempo.Interval{from: ~o"2016-12-31T23:59:00Z", to: ~o"2017-01-01T00:01:00Z"}
      iex> Tempo.Interval.duration(iv)
      ~o"PT120S"
      iex> Tempo.Interval.duration(iv, leap_seconds: true)
      ~o"PT121S"

  """
  @spec duration(t(), keyword()) :: Duration.t() | :infinity | {:error, Exception.t()}
  def duration(interval, options \\ [])

  def duration(%__MODULE__{} = interval, options) do
    with {:ok, leap_seconds?} <- leap_seconds_option(options) do
      interval
      |> measured_form()
      |> resolved_duration(leap_seconds?)
    end
  end

  def duration(value, _options) do
    {:error,
     ArgumentError.exception(
       "Tempo.Interval.duration/2 measures an interval, not #{inspect(value)}: " <>
         "Tempo.duration/1 measures the span a value names."
     )}
  end

  defp leap_seconds_option(options) do
    with true <- Keyword.keyword?(options),
         {:ok, [leap_seconds: leap_seconds?]} when is_boolean(leap_seconds?) <-
           Keyword.validate(options, leap_seconds: false) do
      {:ok, leap_seconds?}
    else
      _invalid ->
        {:error,
         ArgumentError.exception(
           "Tempo.Interval.duration/2 takes one option, :leap_seconds, true or false, " <>
             "not #{inspect(options)}."
         )}
    end
  end

  # A finite recurring interval's duration is the total across its
  # occurrences, which only the materialised set can report — reading
  # the base span (or the open `to` as infinity) would be wrong on
  # both counts. An RRULE `UNTIL` bounds a recurrence as a count does.
  # Any other unbounded recurrence is `:infinity`, its true total
  # extent, however its first occurrence is written.
  defp resolved_duration(%__MODULE__{recurrence: recurrence} = interval, _leap_seconds?)
       when is_integer(recurrence) and recurrence != 1,
       do: {:error, ConversionError.exception(value: interval, reason: :recurring_duration)}

  defp resolved_duration(
         %__MODULE__{recurrence: :infinity, from: %Tempo{}, to: %Tempo{}, duration: %Duration{}} =
           interval,
         _leap_seconds?
       ),
       do: {:error, ConversionError.exception(value: interval, reason: :recurring_duration)}

  defp resolved_duration(%__MODULE__{recurrence: :infinity}, _leap_seconds?), do: :infinity

  defp resolved_duration(%__MODULE__{from: from, to: to}, _leap_seconds?)
       when from in [nil, :undefined] or to in [nil, :undefined],
       do: :infinity

  defp resolved_duration(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = interval, leap_seconds?) do
    with {:ok, %__MODULE__{from: from, to: to} = measured} <-
           measured_interval(interval, :duration) do
      unit = common_unit(endpoint_unit(from), endpoint_unit(to))

      # Degenerate (from == to) and inverted (from > to) intervals
      # contain no real instants under `[from, to)`. Duration is
      # zero rather than a negative count.
      if empty?(measured),
        do: %Duration{time: zero_parts(unit)},
        else: measured_duration(measured, unit, leap_seconds?)
    end
  end

  defp resolved_duration(%__MODULE__{from: from, to: to}, _leap_seconds?) do
    endpoint = if is_struct(from, Tempo), do: to, else: from

    {:error,
     ArgumentError.exception(
       "An interval's endpoints are Tempo values, and #{inspect(endpoint)} is not one, " <>
         "so the interval has no length."
     )}
  end

  defp measured_duration(%__MODULE__{from: from, to: to} = measured, unit, leap_seconds?) do
    with {:ok, leap} <- spanned_leap_seconds(measured, leap_seconds?),
         do: %Duration{time: measure(from, to, unit, leap)}
  end

  # An interval's endpoints as points on the time line. An endpoint that
  # names one point is that point, and one that names a span — a century, a
  # masked month, a selection that picks one day — is where its span starts,
  # as a half-open interval runs from its start's start to its end's start.
  # Both must have a year and share a calendar.
  defp measured_interval(%__MODULE__{from: from, to: to} = interval, operation) do
    with %Tempo{} = from <- span_start(from),
         %Tempo{} = to <- span_start(to),
         :ok <- measurable(interval, from, to, operation) do
      {:ok, %{interval | from: from, to: to}}
    else
      {:error, _reason} = error ->
        error

      _open ->
        {:error,
         ArgumentError.exception("#{inspect(interval)} has an endpoint whose span has no start.")}
    end
  end

  defp span_start(%Tempo{time: time} = endpoint) do
    if Enum.all?(time, &single_value?/1), do: endpoint, else: from(endpoint)
  end

  # A unit's value names one point: a number, or a number with its
  # precision or margin. A group, a mask, a list or a selection names a
  # span, or several.
  defp single_value?({_unit, value}) when is_integer(value), do: true

  defp single_value?({_unit, {value, precision_or_margin}})
       when is_integer(value) and
              (is_integer(precision_or_margin) or is_list(precision_or_margin)),
       do: true

  defp single_value?(_component), do: false

  defp measurable(interval, %Tempo{} = from, %Tempo{} = to, operation) do
    cond do
      not (Tempo.anchored?(from) and Tempo.anchored?(to)) ->
        {:error, UnanchoredError.exception(operation: operation, value: interval)}

      from.calendar != to.calendar ->
        {:error, different_calendars_error(from, to, operation)}

      true ->
        :ok
    end
  end

  # Cross-calendar endpoints produce nonsense arithmetic — the Gregorian
  # seconds of Hebrew 5786 and Gregorian 2026 measure from different epochs —
  # so they are refused, with how to fix it.
  defp different_calendars_error(from, to, operation) do
    ArgumentError.exception(
      "`Tempo.Interval.#{operation}` requires both endpoints in the same calendar. " <>
        "Got #{inspect(from.calendar)} and #{inspect(to.calendar)}. " <>
        "Convert one endpoint first — set operations such as " <>
        "`Tempo.intersection/2` and `Tempo.difference/2` handle " <>
        "cross-calendar inputs automatically."
    )
  end

  @calendar_units [:year, :month, :week, :day]
  @clock_units [:hour, :minute, :second]

  # The unit a duration counts an endpoint in: its resolution, reading a
  # day of the week or of the year (a week's members) as a day.
  defp endpoint_unit(%Tempo{} = tempo) do
    tempo |> Tempo.resolution() |> elem(0) |> counting_unit()
  end

  defp counting_unit(unit) when unit in [:day_of_year, :day_of_week], do: :day
  defp counting_unit(unit) when unit in @calendar_units or unit in @clock_units, do: unit
  defp counting_unit(:microsecond), do: :microsecond
  defp counting_unit(_other), do: :second

  # Weeks do not divide a month or a year, so a week measured against
  # one counts days; otherwise the finer of the two units is the one.
  defp common_unit(:week, unit) when unit in [:year, :month], do: :day
  defp common_unit(unit, :week) when unit in [:year, :month], do: :day

  defp common_unit(unit, other) do
    if Unit.compare(unit, other) == :gt, do: other, else: unit
  end

  defp zero_parts(:microsecond), do: [second: 0]
  defp zero_parts(unit), do: [{unit, 0}]

  # Positive insertions add a second; negative removals (reserved, none
  # yet used) would subtract one.
  defp spanned_leap_seconds(_measured, false), do: {:ok, 0}

  defp spanned_leap_seconds(measured, true) do
    {:ok,
     length(leap_seconds_in(measured, LeapSeconds.dates())) -
       length(leap_seconds_in(measured, LeapSeconds.removals()))}
  end

  # A fraction of a second is elapsed time too, kept to the precision
  # of the finer endpoint.
  defp measure(from, to, :microsecond, leap) do
    elapsed =
      (seconds_between(from, to) + leap) * 1_000_000 + microseconds(to) - microseconds(from)

    [second: div(elapsed, 1_000_000)] ++
      microsecond_parts(rem(elapsed, 1_000_000), max(precision(from), precision(to)))
  end

  defp measure(from, to, unit, leap) when unit in @clock_units do
    clock_parts(seconds_between(from, to) + leap, unit)
  end

  # Calendar units are counted on the calendar, and whatever the count
  # leaves is kept in clock time. A calendar that cannot count them — a
  # caller's own without `diff/3` — is measured in elapsed seconds.
  defp measure(from, to, unit, leap) do
    case calendar_parts(from, to, unit) do
      {:ok, parts, reached} -> parts ++ remainder_parts(seconds_between(reached, to) + leap)
      _cannot_count -> clock_parts(seconds_between(from, to) + leap, :second)
    end
  end

  # The most whole units that can be added to `from` without passing
  # `to`. Endpoints that share a frame — both floating, or both in one
  # zone — are exactly the count between their dates apart. Endpoints in
  # different zones can be a day out on their dates, so the count is
  # fitted on the time line and what is left is counted in days.
  defp calendar_parts(from, to, unit) do
    case units_as_counted(from, to, unit) do
      count when is_integer(count) -> {:ok, [{unit, count}], to}
      :by_dates -> calendar_parts_by_dates(from, to, unit)
    end
  end

  defp calendar_parts_by_dates(from, to, unit) do
    with {:ok, from_date} <- first_date(from),
         {:ok, to_date} <- first_date(to),
         count when is_integer(count) <- Calendrical.diff(from_date, to_date, date_part(unit)) do
      counted_parts(from, to, unit, count, frame(from) == frame(to))
    end
  end

  # Two ends written to the month or the year are a number of months or of
  # years apart, counted in the units themselves where the calendar steps a
  # date itself (`Tempo.UnitValues.stepped_by_calendar?/2`). In a year that
  # does not begin with its first month the calendar counts the months from
  # the day the year begins, so the first days of two that follow one
  # another are not a month of days apart (25 March and 1 April, in a year
  # that begins on 25 March); and a composite calendar's year can be short
  # of a year of days (1751 in `Calendrical.Reform.England`, from 25 March).
  defp units_as_counted(
         %Tempo{time: [{:year, from_year} | _], calendar: calendar} = from,
         %Tempo{time: [{:year, to_year} | _]} = to,
         unit
       )
       when is_integer(from_year) and is_integer(to_year) and unit in [:year, :month] do
    calendar = Compare.effective_calendar(calendar)

    if UnitValues.stepped_by_calendar?(from_year, calendar) or
         UnitValues.stepped_by_calendar?(to_year, calendar),
       do: units_between(from, to, unit, calendar),
       else: :by_dates
  end

  defp units_as_counted(_from, _to, _unit), do: :by_dates

  defp units_between(
         %Tempo{time: [year: from_year]},
         %Tempo{time: [year: to_year]},
         :year,
         _calendar
       ),
       do: to_year - from_year

  defp units_between(from, to, :month, calendar) do
    from = Steps.fill_to_unit(from, :month, calendar)
    to = Steps.fill_to_unit(to, :month, calendar)

    case Steps.months_apart(from, to, calendar) do
      months when is_integer(months) -> months
      :not_supported -> :by_dates
    end
  end

  defp units_between(_from, _to, _unit, _calendar), do: :by_dates

  defp counted_parts(_from, to, unit, count, true = _same_frame), do: {:ok, [{unit, count}], to}

  defp counted_parts(from, to, unit, guess, false = _same_frame) do
    with {:ok, count, reached} <- fit(from, to, unit, guess),
         {:ok, days, reached} <- remaining_days(reached, to, unit) do
      {:ok, [{unit, count} | day_parts(days)], reached}
    end
  end

  defp remaining_days(reached, _to, :day), do: {:ok, 0, reached}

  defp remaining_days(reached, to, _unit),
    do: fit(reached, to, :day, div(seconds_between(reached, to), 86_400))

  # Moves a guess — never more than a unit or two out — to the largest
  # count whose step from `from` does not pass `to` on the time line.
  defp fit(from, to, unit, count) do
    with %Tempo{} = reached <- Tempo.shift(from, [{unit, count}]),
         %Tempo{} = next <- Tempo.shift(from, [{unit, count + 1}]) do
      cond do
        count > 0 and seconds_between(to, reached) > 0 -> fit(from, to, unit, count - 1)
        seconds_between(next, to) >= 0 -> fit(from, to, unit, count + 1)
        true -> {:ok, count, reached}
      end
    end
  end

  # The first day of an endpoint, as a date in its own calendar: a year
  # or a month from its first day, a week from its Monday.
  defp first_date(%Tempo{time: time} = tempo) do
    day_unit = if Keyword.has_key?(time, :week), do: :day_of_week, else: :day

    case Tempo.at_resolution(tempo, day_unit) do
      %Tempo{} = day -> Tempo.to_date(day)
      error -> error
    end
  end

  defp date_part(:year), do: :years
  defp date_part(:month), do: :months
  defp date_part(:week), do: :weeks
  defp date_part(:day), do: :days

  # An endpoint's frame is the zone it names, or else its offset;
  # floating endpoints share the empty one.
  defp frame(%Tempo{extended: %{zone_id: zone_id}}) when is_binary(zone_id), do: zone_id

  defp frame(%Tempo{shift: shift, extended: %{zone_offset: zone_offset}}),
    do: {shift, zone_offset}

  defp frame(%Tempo{shift: shift}), do: {shift, nil}

  defp seconds_between(%Tempo{} = from, %Tempo{} = to),
    do: Compare.to_utc_seconds(to) - Compare.to_utc_seconds(from)

  # Elapsed seconds in a clock unit, with any part of a unit left over
  # in the finer clock units after it.
  defp clock_parts(seconds, :hour),
    do: [hour: div(seconds, 3600)] ++ minute_parts(rem(seconds, 3600))

  defp clock_parts(seconds, :minute),
    do: [minute: div(seconds, 60)] ++ second_parts(rem(seconds, 60))

  defp clock_parts(seconds, :second), do: [second: seconds]

  defp remainder_parts(seconds) when seconds >= 3600, do: clock_parts(seconds, :hour)
  defp remainder_parts(seconds), do: minute_parts(seconds)

  defp minute_parts(seconds) when seconds >= 60, do: clock_parts(seconds, :minute)
  defp minute_parts(seconds), do: second_parts(seconds)

  defp day_parts(0), do: []
  defp day_parts(days), do: [day: days]

  defp second_parts(0), do: []
  defp second_parts(seconds), do: [second: seconds]

  defp microsecond_parts(0, _precision), do: []
  defp microsecond_parts(value, precision), do: [microsecond: {value, precision}]

  defp microseconds(%Tempo{time: time}) do
    case Keyword.get(time, :microsecond) do
      {value, _precision} -> value
      nil -> 0
    end
  end

  defp precision(%Tempo{time: time}) do
    case Keyword.get(time, :microsecond) do
      {_value, precision} -> precision
      nil -> 0
    end
  end

  @doc """
  Return `true` when the interval `[from, to)` contains at least
  one IERS-announced positive leap second.

  A historical predicate: it doesn't affect any other Tempo
  operation. Use it when you want to know if an elapsed-time
  calculation needs leap-second correction, or to flag intervals
  for a scientific/astronomy pipeline.

  ### Arguments

  * `interval` is a `t:t/0` with both endpoints present. Unbounded
    intervals always return `false` (open-ended to `:undefined`)
    and pre-Unix-era intervals pre-1972 return `false` (IERS leap
    seconds started in 1972).

  ### Returns

  * `true` when at least one entry from `Tempo.LeapSeconds.dates/0`
    falls inside `[from, to)`.

  * `false` otherwise.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2016-12-31T23:00:00Z", to: ~o"2017-01-01T01:00:00Z"}
      iex> Tempo.Interval.spans_leap_second?(iv)
      true

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"}
      iex> Tempo.Interval.spans_leap_second?(iv)
      false

  """
  @spec spans_leap_second?(t()) :: boolean()
  def spans_leap_second?(%__MODULE__{} = interval) do
    # A predicate has only true and false to give, so an interval it
    # cannot measure raises.
    case leap_seconds_spanned(interval) do
      [] -> false
      [_ | _] -> true
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Return the list of IERS leap-second dates that fall inside
  `[from, to)`.

  ### Arguments

  * `interval` is a `t:t/0` with both endpoints present.

  ### Returns

  * A list of `{year, month, day}` tuples, each entry drawn from
    `Tempo.LeapSeconds.dates/0`. Empty list when no leap second
    falls inside the span, or when either endpoint is
    `:undefined`.

  * `{:error, reason}` for an interval whose endpoints have no year or
    are in different calendars, or for a value that is not an interval.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2015-01-01", to: ~o"2017-12-31"}
      iex> Tempo.Interval.leap_seconds_spanned(iv)
      [{2015, 6, 30}, {2016, 12, 31}]

  """
  @spec leap_seconds_spanned(t()) :: [{integer(), 1..12, 1..31}] | {:error, Exception.t()}
  def leap_seconds_spanned(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = interval) do
    # Union of positive insertions and (reserved) negative
    # removals, in chronological order.
    with {:ok, measured} <- measured_interval(interval, :leap_seconds_spanned) do
      Enum.sort(
        leap_seconds_in(measured, LeapSeconds.dates()) ++
          leap_seconds_in(measured, LeapSeconds.removals())
      )
    end
  end

  def leap_seconds_spanned(%__MODULE__{}), do: []

  def leap_seconds_spanned(value) do
    {:error,
     ArgumentError.exception(
       "Tempo.Interval.leap_seconds_spanned/1 reads an interval, not #{inspect(value)}."
     )}
  end

  # The leap-second dates among `dates` that fall within an interval whose
  # endpoints `measured_interval/2` has checked.
  defp leap_seconds_in(%__MODULE__{from: from, to: to}, dates) do
    from_s = Compare.to_utc_seconds(from)
    to_s = Compare.to_utc_seconds(to)

    for {y, m, d} <- dates, leap_second_in_interval?(y, m, d, from_s, to_s), do: {y, m, d}
  end

  # A leap second is inserted at 23:59:60 UTC on day (y,m,d) —
  # conceptually *between* 23:59:59 and 00:00:00 of the following
  # day. In leap-second-naive gregorian seconds those two endpoints
  # collide at N+1 (where N = gregorian(y,m,d,23,59,59)).
  #
  # For a half-open interval `[from_s, to_s)`, the leap second is
  # included iff `from_s ≤ N AND to_s > N`. That is: the interval
  # starts at or before the final second of day (y,m,d) and extends
  # past that final-second boundary. This places the leap second
  # infinitesimally after N in naive time — any interval that
  # contains N and extends beyond it contains the leap second.
  defp leap_second_in_interval?(year, month, day, from_s, to_s) do
    n = :calendar.datetime_to_gregorian_seconds({{year, month, day}, {23, 59, 59}})
    from_s <= n and to_s > n
  end

  @doc """
  `true` when the interval is at least as long as the given
  duration.

  Unbounded intervals (`:undefined` endpoint) satisfy any finite
  minimum — an infinite span is trivially "at least" any
  duration.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T11"}
      iex> Tempo.Interval.at_least?(iv, ~o"PT1H")
      true
      iex> Tempo.Interval.at_least?(iv, ~o"PT3H")
      false

  """
  @spec at_least?(t(), Duration.t()) :: boolean()
  def at_least?(interval, duration),
    do: resolved_at_least?(measurable!(interval), duration)

  defp resolved_at_least?(%__MODULE__{from: :undefined}, _), do: true
  defp resolved_at_least?(%__MODULE__{to: :undefined}, _), do: true

  defp resolved_at_least?(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = interval, %Duration{} = d) do
    length_order(interval, d) in [:earlier, :same]
  end

  @doc """
  `true` when the interval is at most as long as the given
  duration.

  Unbounded intervals return `false` — an infinite span exceeds
  any finite maximum.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      iex> Tempo.Interval.at_most?(iv, ~o"PT1H")
      true
      iex> Tempo.Interval.at_most?(iv, ~o"PT30M")
      false

  """
  @spec at_most?(t(), Duration.t()) :: boolean()
  def at_most?(interval, duration),
    do: resolved_at_most?(measurable!(interval), duration)

  defp resolved_at_most?(%__MODULE__{from: :undefined}, _), do: false
  defp resolved_at_most?(%__MODULE__{to: :undefined}, _), do: false

  defp resolved_at_most?(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = interval, %Duration{} = d) do
    length_order(interval, d) in [:later, :same]
  end

  @doc """
  `true` when the interval's length equals the given duration
  exactly.

  Unbounded intervals always return `false`.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      iex> Tempo.Interval.exactly?(iv, ~o"PT1H")
      true
      iex> Tempo.Interval.exactly?(iv, ~o"PT2H")
      false

  """
  @spec exactly?(t(), Duration.t()) :: boolean()
  def exactly?(interval, duration),
    do: resolved_exactly?(measurable!(interval), duration)

  defp resolved_exactly?(%__MODULE__{from: :undefined}, _), do: false
  defp resolved_exactly?(%__MODULE__{to: :undefined}, _), do: false

  defp resolved_exactly?(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = interval, %Duration{} = d) do
    length_order(interval, d) == :same
  end

  @doc """
  `true` when the interval's length is strictly greater than
  the given duration.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T11"}
      iex> Tempo.Interval.longer_than?(iv, ~o"PT1H")
      true
      iex> Tempo.Interval.longer_than?(iv, ~o"PT2H")
      false

  """
  @spec longer_than?(t(), Duration.t()) :: boolean()
  def longer_than?(interval, duration),
    do: resolved_longer_than?(measurable!(interval), duration)

  defp resolved_longer_than?(%__MODULE__{from: :undefined}, _), do: true
  defp resolved_longer_than?(%__MODULE__{to: :undefined}, _), do: true

  defp resolved_longer_than?(
         %__MODULE__{from: %Tempo{}, to: %Tempo{}} = interval,
         %Duration{} = d
       ) do
    length_order(interval, d) == :earlier
  end

  @doc """
  `true` when the interval's length is strictly less than the
  given duration.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      iex> Tempo.Interval.shorter_than?(iv, ~o"PT2H")
      true
      iex> Tempo.Interval.shorter_than?(iv, ~o"PT1H")
      false

  """
  @spec shorter_than?(t(), Duration.t()) :: boolean()
  def shorter_than?(interval, duration),
    do: resolved_shorter_than?(measurable!(interval), duration)

  defp resolved_shorter_than?(%__MODULE__{from: :undefined}, _), do: false
  defp resolved_shorter_than?(%__MODULE__{to: :undefined}, _), do: false

  defp resolved_shorter_than?(
         %__MODULE__{from: %Tempo{}, to: %Tempo{}} = interval,
         %Duration{} = d
       ) do
    length_order(interval, d) == :later
  end

  # The interval a length predicate measures: both ends points, or one open.
  # A predicate has only true and false to give, so what has no one length (a
  # recurrence, an interval whose end names several spans, or what is no
  # interval) raises.
  defp measurable!(%__MODULE__{recurrence: recurrence} = interval) when recurrence != 1,
    do: raise(ConversionError.exception(value: interval, reason: :recurring_interval))

  defp measurable!(%__MODULE__{} = interval) do
    case measured_form(interval) do
      %__MODULE__{from: :undefined} = measured ->
        measured

      %__MODULE__{to: :undefined} = measured ->
        measured

      %__MODULE__{from: %Tempo{}, to: %Tempo{}} = measured ->
        measured

      _no_length ->
        raise IntervalEndpointsError.exception(interval: interval, operation: :measure)
    end
  end

  defp measurable!(other) do
    raise ArgumentError, "A length is measured of an interval, and #{inspect(other)} is not one."
  end

  # How a duration from an interval's start compares with its end: `:earlier`
  # when the interval is the longer, `:later` when the duration is. With a
  # year the duration is counted on the calendar from the start. With none the
  # span is on a cycle, where stepping comes round again, so the two are
  # measured: a time of day or a day of the week by its clock, against which
  # a duration of months or years is longer than any span the cycle holds.
  defp length_order(%__MODULE__{from: from, to: to} = interval, %Duration{} = duration) do
    if Cycle.cyclic?(interval),
      do: cyclic_length_order(interval, duration),
      else: Compare.compare_endpoints(reached!(from, duration), to)
  end

  defp cyclic_length_order(interval, %Duration{time: time}) do
    case {Cycle.microseconds(interval), fixed_microseconds(time)} do
      {{:ok, _span}, :longer_than_a_cycle} -> :later
      {{:ok, span}, lasting} when lasting < span -> :earlier
      {{:ok, span}, lasting} when lasting > span -> :later
      {{:ok, _span}, _lasting} -> :same
      {{:error, exception}, _lasting} -> raise exception
    end
  end

  # A duration's microseconds where each of its units has one length on a
  # clock with no date: a week, a day, and the units of a time of day.
  defp fixed_microseconds(time) do
    Enum.reduce_while(time, 0, fn
      {:week, weeks}, total -> {:cont, total + weeks * 604_800_000_000}
      {:day, days}, total -> {:cont, total + days * 86_400_000_000}
      {:hour, hours}, total -> {:cont, total + hours * 3_600_000_000}
      {:minute, minutes}, total -> {:cont, total + minutes * 60_000_000}
      {:second, seconds}, total -> {:cont, total + round(seconds * 1_000_000)}
      {:microsecond, {value, _precision}}, total -> {:cont, total + value}
      {:microsecond, value}, total when is_integer(value) -> {:cont, total + value}
      _months_or_years, _total -> {:halt, :longer_than_a_cycle}
    end)
  end

  # The point a duration reaches from a start. One it cannot be counted to
  # leaves no length to compare.
  defp reached!(%Tempo{} = from, duration) do
    case Math.add(from, duration) do
      %Tempo{} = reached -> reached
      {:error, exception} when is_exception(exception) -> raise exception
      _several -> raise ConversionError.exception(value: from, reason: :grouped_component)
    end
  end

  ## ----------------------------------------------------------
  ## Relation predicates — thin shortcuts over relation/2
  ## ----------------------------------------------------------

  # The everyday `before?/2` and `after?/2`: the two share no instant, one
  # earlier — Allen's gap relation or its meeting.
  @before_relations [:precedes, :meets]
  @after_relations [:preceded_by, :met_by]

  @doc """
  `true` when `a` ends at or before `b` starts — the two share no
  instant and `a` is earlier.

  This is the everyday sense: an 11:00–12:00 meeting is before a
  12:00 lunch, since under the half-open convention the meeting ends
  as lunch begins. Allen's `:precedes` also needs a gap between the
  two; `Tempo.Allen.precedes?/2` tests for it.

  Raises when an operand is not a single bounded interval (a
  multi-member set, an open or recurring interval, a one-of set), as
  `relation/2` returns an error there.

  ### Examples

      iex> meeting = ~o"2026-06-15T11/2026-06-15T12"
      iex> Tempo.Interval.before?(meeting, ~o"2026-06-15T12/2026-06-15T13")
      true
      iex> Tempo.Interval.before?(meeting, ~o"2026-06-15T11:30/2026-06-15T13")
      false

  """
  @spec before?(interval_like(), interval_like()) :: boolean()
  def before?(a, b), do: match_relation(a, b, @before_relations)

  @doc """
  `true` when `a` starts at or after `b` ends — the two share no
  instant and `a` is later.

  The mirror of `before?/2`. Allen's `:preceded_by` also needs a gap
  between the two; `Tempo.Allen.preceded_by?/2` tests for it.

  ### Examples

      iex> Tempo.Interval.after?(~o"2026-02", ~o"2026-01")
      true

  """
  @spec after?(interval_like(), interval_like()) :: boolean()
  def after?(a, b), do: match_relation(a, b, @after_relations)

  @doc """
  `true` when the two intervals touch at a single boundary —
  either ends exactly where the other starts (Allen's
  `:meets | :met_by`; `Tempo.Allen.meets?/2` tests one direction).

  ### Examples

      iex> Tempo.Interval.adjacent?(~o"2026-06-15", ~o"2026-06-16")
      true

      iex> Tempo.Interval.adjacent?(~o"2026-06-15", ~o"2026-06-17")
      false

  """
  @spec adjacent?(interval_like(), interval_like()) :: boolean()
  def adjacent?(a, b), do: match_relation(a, b, [:meets, :met_by])

  @doc """
  `true` when `a` lies inside `b` inclusive of shared
  endpoints (Allen's `:equals | :starts | :during | :finishes`).
  The canonical "does this fit inside that window?" predicate;
  Allen's strict `:during` is `Tempo.Allen.during?/2`.

  `within?/2` asks about the whole of `a`. The `:within` option of
  `Tempo.to_interval_set/2` and the set operations is looser: it
  keeps every occurrence that overlaps its window, one already in
  progress when the window opens included.

  ### Examples

      iex> a = %Tempo.Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}
      iex> window = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T17"}
      iex> Tempo.Interval.within?(a, window)
      true
      iex> # Candidate shares the window's start — still inside
      iex> a2 = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      iex> Tempo.Interval.within?(a2, window)
      true

  """
  @spec within?(interval_like(), interval_like()) :: boolean()
  def within?(a, b), do: match_relation(a, b, [:equals, :starts, :during, :finishes])

  # A relation error must surface, not read as `false` — a silent false
  # asserts "the relation does not hold", a claim the error explicitly
  # could not make. One-of sets, for example, have no crisp relation at
  # all; the raised error points the caller at the certainty API.
  defp match_relation(a, b, allowed_relations) do
    case relation(a, b) do
      r when is_atom(r) -> r in allowed_relations
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, to_string(reason)
    end
  end

  # ------------------------------------------------------------------
  # Graded relations over uncertain and underspecified intervals
  #
  # A margin widens each endpoint into a range; comparing two ranges
  # yields the *set* of orderings (:earlier/:same/:later) they could
  # stand in, and running the crisp `classify_relation/4` table over the
  # cartesian product yields every Allen relation the two values could
  # satisfy. A concept (overlaps, within, …) is a set of relations, and
  # its certainty is set containment: possible ⊆ concept → :certain;
  # possible ∩ concept = ∅ → :impossible; otherwise → :possible.
  #
  # The same lens covers three sources of uncertainty, each turned into
  # an endpoint range the machinery already consumes:
  #
  #   * ISO 8601-2 `±` margin-of-error — a rigid shift of both endpoints.
  #   * Unspecified digits (`~o"20XXY"` — some year in `[2000, 2100)`) —
  #     read as their *grounding envelope*: the resolution-wide value
  #     slides anywhere inside the span the mask admits, so certainty is
  #     over every year the mask could be, not the enclosing block.
  #   * Unanchored values (no year) — comparable only on a shared leading
  #     unit (the same-axis rule); off-axis they return a
  #     `UnanchoredError` rather than guess the missing year.
  #
  # Endpoints are treated independently, which for a rigidly-shifting ±
  # or a masked value is a *sound over-approximation*: `:certain` and
  # `:impossible` are never wrong; the verdict only ever errs toward
  # `:possible`. Crisp operands widen to points, so every concept degrades
  # exactly to its boolean predicate (`certainly_within?/2 == within?/2`).

  @intersecting_relations MapSet.new([
                            :overlaps,
                            :overlapped_by,
                            :starts,
                            :started_by,
                            :during,
                            :contains,
                            :finishes,
                            :finished_by,
                            :equals
                          ])

  @within_relations MapSet.new([:equals, :starts, :during, :finishes])

  @typedoc "A three-valued relation certainty."
  @type certainty :: :certain | :possible | :impossible

  @doc """
  The certainty that `a` and `b` intersect, given their `±` margins.

  The three-valued counterpart of `Tempo.overlaps?/3`. Each margin-bearing
  endpoint is widened into a range, and the result reports whether
  intersection holds for every consistent placement (`:certain`), some
  (`:possible`), or none (`:impossible`). Crisp operands degrade exactly
  to `Tempo.overlaps?/3` (only `:certain`/`:impossible` occur).

  ### Arguments

  * `a` and `b` are each a bounded `t:Tempo.t/0`, `t:Tempo.Interval.t/0`,
    or single-member `t:Tempo.IntervalSet.t/0`.

  ### Returns

  * `:certain`, `:possible`, or `:impossible`.

  * `{:error, reason}` when either operand is open-ended or a
    multi-member set.

  ### Examples

      iex> Tempo.Interval.overlap_certainty(~o"2000±1Y", ~o"2010±1Y")
      :impossible

      iex> Tempo.Interval.overlap_certainty(~o"2000±1Y", ~o"2001±1Y")
      :possible

      iex> Tempo.Interval.overlap_certainty(~o"2000Y", ~o"2000Y")
      :certain

  """
  @spec overlap_certainty(interval_like(), interval_like()) :: certainty() | {:error, term()}
  def overlap_certainty(a, b), do: concept_certainty(a, b, @intersecting_relations)

  @doc """
  The certainty that `a` falls within `b`, given any uncertainty in either.

  The three-valued counterpart of `within?/2` (Allen `:equals | :starts
  | :during | :finishes`). Uncertainty may be a `±` margin *or*
  underspecification — an unspecified-digit value (`~o"20XXY"`) is read
  over the set of years its mask admits, so `:possible` reports that some
  but not all groundings fall within `b`. Crisp operands degrade exactly to
  `within?/2`.

  ### Arguments

  * `a` and `b` are each a bounded `t:Tempo.t/0`, `t:Tempo.Interval.t/0`,
    or single-member `t:Tempo.IntervalSet.t/0`.

  ### Returns

  * `:certain`, `:possible`, or `:impossible`.

  * `{:error, reason}` for open-ended or multi-member operands, or a
    `t:Tempo.UnanchoredError.t/0` when an unanchored operand is
    compared across resolution axes.

  ### Examples

      iex> Tempo.Interval.within_certainty(~o"2000Y6M", ~o"2000Y")
      :certain

      iex> Tempo.Interval.within_certainty(~o"2000±1Y", ~o"2000Y")
      :possible

      iex> # ~o"20XXY" is some year in [2000, 2100); 2000 escapes [2001, 2101)
      iex> Tempo.Interval.within_certainty(~o"20XXY", ~o"2001Y/2101Y")
      :possible

  """
  @spec within_certainty(interval_like(), interval_like()) :: certainty() | {:error, term()}
  def within_certainty(a, b), do: concept_certainty(a, b, @within_relations)

  @doc """
  The certainty that `relation(a, b)` is (one of) `target`.

  Certainty is containment of the possible relations in `target`. The
  possible relations account for any `±` margin and for underspecification:
  an unspecified-digit operand (`~o"20XXY"`) is read over every grounding
  its mask admits, and two unanchored operands compare on a shared leading
  unit.

  ### Arguments

  * `a` and `b` are bounded interval-like values.

  * `target` is a single Allen relation atom (e.g. `:during`) or a list
    of relation atoms.

  ### Returns

  * `:certain`, `:possible`, or `:impossible`.

  * `{:error, reason}` for open-ended or multi-member operands, or a
    `t:Tempo.UnanchoredError.t/0` when an unanchored operand is
    compared across resolution axes.

  ### Examples

      iex> Tempo.Interval.relation_certainty(~o"2000±1Y", ~o"2010±1Y", :precedes)
      :certain

      iex> Tempo.Interval.relation_certainty(~o"2000Y", ~o"2000Y", :equals)
      :certain

      iex> # some year in 2000–2099 may precede 2050, may follow it
      iex> Tempo.Interval.relation_certainty(~o"20XXY", ~o"2050Y", :precedes)
      :possible

  """
  @spec relation_certainty(interval_like(), interval_like(), relation() | [relation()]) ::
          certainty() | {:error, term()}
  def relation_certainty(a, b, target) when is_atom(target),
    do: concept_certainty(a, b, MapSet.new([target]))

  def relation_certainty(a, b, target) when is_list(target),
    do: concept_certainty(a, b, MapSet.new(target))

  @doc """
  `true` when `a` and `b` intersect for *every* placement of their `±`
  margins — `overlap_certainty(a, b) == :certain`. Crisp counterpart:
  `Tempo.overlaps?/3`.

  ### Examples

      iex> Tempo.Interval.certainly_overlaps?(~o"2000Y", ~o"2000Y")
      true

      iex> Tempo.Interval.certainly_overlaps?(~o"2000±1Y", ~o"2001±1Y")
      false

  """
  @spec certainly_overlaps?(interval_like(), interval_like()) :: boolean()
  def certainly_overlaps?(a, b), do: certainty_in?(overlap_certainty(a, b), [:certain])

  @doc """
  `true` when `a` and `b` *could* intersect for some placement of their
  `±` margins — `overlap_certainty/2` is `:certain` or `:possible`.

  ### Examples

      iex> Tempo.Interval.possibly_overlaps?(~o"2000±1Y", ~o"2001±1Y")
      true

      iex> Tempo.Interval.possibly_overlaps?(~o"2000±1Y", ~o"2010±1Y")
      false

  """
  @spec possibly_overlaps?(interval_like(), interval_like()) :: boolean()
  def possibly_overlaps?(a, b), do: certainty_in?(overlap_certainty(a, b), [:certain, :possible])

  @doc """
  `true` when `a` falls within `b` for *every* placement of their `±`
  margins. Crisp counterpart: `within?/2`.

  ### Examples

      iex> Tempo.Interval.certainly_within?(~o"2000Y6M", ~o"2000Y")
      true

  """
  @spec certainly_within?(interval_like(), interval_like()) :: boolean()
  def certainly_within?(a, b), do: certainty_in?(within_certainty(a, b), [:certain])

  @doc """
  `true` when `a` *could* fall within `b` for some placement of their
  `±` margins.

  ### Examples

      iex> Tempo.Interval.possibly_within?(~o"2000±1Y", ~o"2000Y")
      true

  """
  @spec possibly_within?(interval_like(), interval_like()) :: boolean()
  def possibly_within?(a, b), do: certainty_in?(within_certainty(a, b), [:certain, :possible])

  @doc """
  `true` when `a` ends at or before `b` starts — they share no instant
  and `a` is earlier — for *every* placement of their `±` margins.
  Crisp counterpart: `before?/2`.

  ### Examples

      iex> Tempo.Interval.certainly_before?(~o"2000±1Y", ~o"2010±1Y")
      true

      iex> Tempo.Interval.certainly_before?(~o"2000±1Y", ~o"2001±1Y")
      false

  """
  @spec certainly_before?(interval_like(), interval_like()) :: boolean()
  def certainly_before?(a, b),
    do: certainty_in?(relation_certainty(a, b, @before_relations), [:certain])

  @doc """
  `true` when `a` *could* end at or before `b` starts for some placement
  of their `±` margins.

  ### Examples

      iex> Tempo.Interval.possibly_before?(~o"2000±1Y", ~o"2001±1Y")
      true

  """
  @spec possibly_before?(interval_like(), interval_like()) :: boolean()
  def possibly_before?(a, b),
    do: certainty_in?(relation_certainty(a, b, @before_relations), [:certain, :possible])

  @doc """
  `true` when `a` starts at or after `b` ends — they share no instant
  and `a` is later — for *every* placement of their `±` margins. Crisp
  counterpart: `after?/2`.

  ### Examples

      iex> Tempo.Interval.certainly_after?(~o"2010±1Y", ~o"2000±1Y")
      true

  """
  @spec certainly_after?(interval_like(), interval_like()) :: boolean()
  def certainly_after?(a, b),
    do: certainty_in?(relation_certainty(a, b, @after_relations), [:certain])

  @doc """
  `true` when `a` *could* start at or after `b` ends for some placement
  of their `±` margins.

  ### Examples

      iex> Tempo.Interval.possibly_after?(~o"2001±1Y", ~o"2000±1Y")
      true

  """
  @spec possibly_after?(interval_like(), interval_like()) :: boolean()
  def possibly_after?(a, b),
    do: certainty_in?(relation_certainty(a, b, @after_relations), [:certain, :possible])

  # A certainty error must surface, not read as `false` — a silent false
  # asserts "impossible", a claim the error explicitly could not make.
  defp certainty_in?({:error, exception}, _accepted) when is_exception(exception),
    do: raise(exception)

  defp certainty_in?({:error, reason}, _accepted), do: raise(ArgumentError, to_string(reason))
  defp certainty_in?(certainty, accepted), do: certainty in accepted

  ## Graded-relation internals

  defp concept_certainty(a, b, concept) do
    with :ok <- same_frame(a, b) do
      case possible_relations(a, b) do
        {:error, _} = error -> error
        possible -> certainty(possible, concept)
      end
    end
  end

  @doc false
  # A floating value has no position on the universal time line, so it
  # cannot be compared with a zoned one — every crisp relation and
  # certainty query rejects the mixed frame rather than silently
  # reading the floating side as UTC. Place it in a zone first with
  # `Tempo.in_zone/2` (or write an offset). Two floating or two zoned
  # operands compare normally. A function with an error to return
  # returns this one; a predicate, with only true and false to give,
  # raises it (`reject_mixed_frame!/2`).
  @spec same_frame(term(), term()) :: :ok | {:error, FloatingTempoError.t()}
  def same_frame(a, b) do
    case mixed_frame(operand_frame(a), operand_frame(b)) do
      %Tempo{} = floating ->
        {:error, FloatingTempoError.exception(operation: :compare, value: floating)}

      nil ->
        :ok
    end
  end

  @doc false
  # A window with no zone that bounds a value in a zone is read in that zone:
  # it takes the frame of what it bounds, as a time of day takes the frame of
  # what it is placed on. `2026-06-01/2026-06-03` within which a recurrence
  # in New York is asked for is those days in New York, not in UTC. Any other
  # pair is left as it is.
  @spec window_in_frame_of(term(), term()) :: term()
  def window_in_frame_of(window, value) do
    case {operand_frame(window), operand_frame(value)} do
      {{:floating, _floating}, {:zoned, %Tempo{} = zoned}} -> in_frame(window, zoned)
      _one_frame_or_none -> window
    end
  end

  defp in_frame(%Tempo{time: [{:year, year} | _rest]} = point, zoned) when year != :any,
    do: copy_frame(zoned, point)

  defp in_frame(%__MODULE__{from: from, to: to} = interval, zoned),
    do: %{interval | from: in_frame(from, zoned), to: in_frame(to, zoned)}

  defp in_frame(%IntervalSet{} = set, zoned) do
    if IntervalSet.bounded?(set),
      do: IntervalSet.map(set, &in_frame(&1, zoned)),
      else: set
  end

  defp in_frame(other, _zoned), do: other

  @doc false
  # `same_frame/2` for a predicate. Shared with `Tempo.Operations` so the
  # set-theoretic predicates (`overlaps?/2`, `disjoint?/2`, …) reject the
  # same mismatch.
  def reject_mixed_frame!(a, b) do
    with {:error, exception} <- same_frame(a, b), do: raise(exception)
  end

  # The floating value of a pair of frames that are not one frame: a floating
  # frame and a zoned one, or a set that holds both.
  defp mixed_frame({:mixed, floating}, _frame), do: floating
  defp mixed_frame(_frame, {:mixed, floating}), do: floating
  defp mixed_frame({:floating, floating}, {:zoned, _zoned}), do: floating
  defp mixed_frame({:zoned, _zoned}, {:floating, floating}), do: floating
  defp mixed_frame(_frame, _another), do: nil

  # The frame an operand is in: `{:floating, value}` or `{:zoned, value}` by
  # one of its dated values, `{:mixed, floating}` when it holds both, and
  # `:none` when it holds no dated value. A value with no year (a time of
  # day) is in no frame of its own: it takes the frame of what it is placed
  # on, as `Tempo.at/2` gives it.
  defp operand_frame(%Tempo{time: [{:year, year} | _rest]} = tempo) when year != :any do
    if Tempo.floating?(tempo), do: {:floating, tempo}, else: {:zoned, tempo}
  end

  defp operand_frame(%__MODULE__{from: from, to: to}),
    do: both_frames(operand_frame(from), operand_frame(to))

  # Each member of a set is read, since a calendar holds days with no zone
  # beside meetings in one. A set without end is read by its first.
  defp operand_frame(%IntervalSet{} = set) do
    if IntervalSet.bounded?(set),
      do: set |> IntervalSet.members() |> frames(),
      else: operand_frame(IntervalSet.first(set))
  end

  defp operand_frame(%Tempo.Set{set: members}) when is_list(members), do: frames(members)

  defp operand_frame(%Tempo.Range{first: first, last: last}),
    do: both_frames(operand_frame(first), operand_frame(last))

  defp operand_frame(_other), do: :none

  defp frames(members) do
    Enum.reduce_while(members, :none, fn member, held ->
      case both_frames(held, operand_frame(member)) do
        {:mixed, _floating} = mixed -> {:halt, mixed}
        held -> {:cont, held}
      end
    end)
  end

  defp both_frames(:none, frame), do: frame
  defp both_frames(frame, :none), do: frame
  defp both_frames({:mixed, _floating} = mixed, _frame), do: mixed
  defp both_frames(_frame, {:mixed, _floating} = mixed), do: mixed
  defp both_frames({kind, _value} = frame, {kind, _another}), do: frame
  defp both_frames({:floating, floating}, {:zoned, _zoned}), do: {:mixed, floating}
  defp both_frames({:zoned, _zoned}, {:floating, floating}), do: {:mixed, floating}

  defp certainty(possible, concept) do
    cond do
      MapSet.subset?(possible, concept) -> :certain
      MapSet.disjoint?(possible, concept) -> :impossible
      true -> :possible
    end
  end

  # Beyond this many candidate pairings, fall back to the sound
  # endpoint-range over-approximation rather than enumerate. Covers
  # margins up to ~±128 units on each operand exactly.
  @max_placement_pairs 65_536

  # The set of Allen relations the two values could satisfy once their
  # margins are taken into account. A `±m` value can sit at any integer
  # offset `-m..+m` — rigidly, both endpoints moving together — so
  # enumerating each operand's candidate placements and classifying every
  # pairing yields the *exact* conceptual neighbourhood. For
  # pathologically wide margins the pairing count is capped and we fall
  # back to the sound (looser) endpoint-range method.
  # Each operand is classified once, and the pair dispatches on whichever
  # class dominates (earliest in the priority order below).
  defp possible_relations(a, b) do
    a = measured_form(a)
    b = measured_form(b)
    relations_for(dominant_class(operand_class(a), operand_class(b)), a, b)
  end

  defp operand_class(operand) do
    cond do
      one_of_operand?(operand) -> :one_of
      non_contiguous_mask?(operand) -> :candidates
      not anchored_operand?(operand) -> :unanchored
      masked_operand?(operand) -> :masked
      true -> :concrete
    end
  end

  defp dominant_class(class, class), do: class

  defp dominant_class(class_a, class_b) do
    Enum.find(
      [:one_of, :candidates, :unanchored, :masked, :concrete],
      &(&1 in [class_a, class_b])
    )
  end

  # An epistemic one-of set (`[1984,1986]`) is a finite envelope: the value
  # is exactly one member, we don't know which. The relations the pair can
  # stand in are the union over every member choice; `certainty/2` then
  # reads the concept as usual — possible when some choice admits it,
  # certain only when every choice does.
  defp relations_for(:one_of, a, b), do: one_of_relations(a, b)

  # A mask above concrete finer units (`~o"1985-XX-15"`) admits a finite
  # set of concrete groundings, not a contiguous span, so the envelope
  # machinery cannot represent it. Expand the candidates and union,
  # exactly as for a one-of set.
  defp relations_for(:candidates, a, b), do: candidate_relations(a, b)

  defp relations_for(:unanchored, a, b), do: unanchored_possible_relations(a, b)

  # An unspecified-digit value (`~o"20XXY"`) denotes an unknown grounding
  # within a bounded span. Its grounding envelope feeds the same
  # endpoint-range machinery the wide-± fallback uses, so the concept
  # certainty is read over every year the mask admits, not the block.
  defp relations_for(:masked, a, b), do: envelope_relations(a, b)

  defp relations_for(:concrete, a, b) do
    with {:ok, a_places} <- placements(a),
         {:ok, b_places} <- placements(b) do
      classify_placements(a, b, a_places, b_places)
    end
  end

  defp one_of_operand?(%Tempo.Set{type: :one}), do: true
  defp one_of_operand?(_operand), do: false

  # Union of the possible relations over the cartesian product of member
  # choices. Members recurse through `possible_relations/2`, so a member
  # that is itself masked or margined composes its own envelope.
  defp one_of_relations(a, b) do
    union_over_choices(one_of_choices(a), one_of_choices(b))
  end

  defp union_over_choices(choices_a, choices_b) do
    pairs = for choice_a <- choices_a, choice_b <- choices_b, do: {choice_a, choice_b}

    pairs
    |> Enum.reduce_while({:ok, MapSet.new()}, fn {choice_a, choice_b}, {:ok, acc} ->
      case possible_relations(choice_a, choice_b) do
        {:error, _} = error -> {:halt, error}
        possible -> {:cont, {:ok, MapSet.union(acc, possible)}}
      end
    end)
    |> case do
      {:ok, possible} -> possible
      error -> error
    end
  end

  defp one_of_choices(%Tempo.Set{type: :one, set: members}), do: members
  defp one_of_choices(operand), do: [operand]

  # A non-contiguous mask expands to a finite candidate set — one concrete
  # interval per grounding the mask admits — so the pair's possible relations
  # are the union over candidates, exactly as for a one-of set. The candidates
  # come out of `Tempo.to_interval/1` with concrete bounds, so the recursive
  # `possible_relations/2` calls take the placement path.
  defp candidate_relations(a, b) do
    with {:ok, choices_a} <- mask_candidates(a),
         {:ok, choices_b} <- mask_candidates(b) do
      union_over_candidates(choices_a, choices_b)
    end
  end

  # Each candidate against each is as many pairings as the product of the
  # two counts: a million for two masked values of a thousand candidates.
  # Candidates that are spans in order, none overlapping the next, need not
  # be paired so. Against such a run a span is preceded by every candidate
  # that ends before it starts and precedes every one that starts after it
  # ends, so only the candidates between are classified one by one.
  defp union_over_candidates([_, _ | _] = choices_a, [_, _ | _] = choices_b) do
    with {:ok, run_a} <- as_run(choices_a),
         {:ok, run_b} <- as_run(choices_b) do
      relations_along(run_a, List.to_tuple(run_b), [])
    else
      :not_a_run -> union_over_choices(choices_a, choices_b)
    end
  end

  defp union_over_candidates(choices_a, choices_b), do: union_over_choices(choices_a, choices_b)

  # Candidates as the spans `relation/2` reads them as, when they are spans
  # in order: each ends after it starts and no later than the next starts.
  defp as_run(choices) do
    with {:ok, spans} <- single_spans(choices, []),
         true <- in_order?(spans) do
      {:ok, spans}
    else
      _not_spans_in_order -> :not_a_run
    end
  end

  defp single_spans([%__MODULE__{} = choice | rest], spans) do
    case to_single_interval(choice, :graded) do
      {:ok, %__MODULE__{from: %Tempo{}, to: %Tempo{}} = span} ->
        single_spans(rest, [span | spans])

      _no_one_span ->
        :not_a_run
    end
  end

  defp single_spans([], spans), do: {:ok, Enum.reverse(spans)}
  defp single_spans(_not_a_span, _spans), do: :not_a_run

  defp in_order?([%__MODULE__{from: from, to: to}]),
    do: Compare.order(from, to) == {:ok, :earlier}

  defp in_order?([%__MODULE__{from: from, to: to}, %__MODULE__{from: next} = following | rest]) do
    Compare.order(from, to) == {:ok, :earlier} and
      Compare.order(to, next) in [{:ok, :earlier}, {:ok, :same}] and
      in_order?([following | rest])
  end

  # The relations found are gathered in a list, each once, and are a set
  # when the last span has been related.
  defp relations_along([a | rest], run, relations) do
    case relations_to_run(a, run, relations) do
      {:error, _exception} = error -> error
      found -> relations_along(rest, run, found)
    end
  end

  defp relations_along([], _run, relations), do: MapSet.new(relations)

  defp relations_to_run(%__MODULE__{from: from} = a, run, relations) do
    with {:ok, first} <- first_not_ended(run, from, 0, tuple_size(run)) do
      relations = if first > 0, do: with_relation(relations, :preceded_by), else: relations
      relations_from(a, run, first, relations)
    end
  end

  # The relations of a span to a run's candidates from `index` on. The first
  # it precedes is followed only by candidates it precedes too.
  defp relations_from(_a, run, index, relations) when index == tuple_size(run), do: relations

  defp relations_from(a, run, index, relations) do
    case classify(a, elem(run, index)) do
      {:error, _exception} = error -> error
      :precedes -> with_relation(relations, :precedes)
      relation -> relations_from(a, run, index + 1, with_relation(relations, relation))
    end
  end

  # There are thirteen relations, so a list of those found is searched as
  # fast as a set of them.
  defp with_relation(relations, relation) do
    if relation in relations, do: relations, else: [relation | relations]
  end

  # The index of a run's first candidate that does not end before `point`,
  # by bisection: in a run the candidates' ends are in order.
  defp first_not_ended(run, point, low, high) when low < high do
    middle = div(low + high, 2)

    case Compare.order(elem(run, middle).to, point) do
      {:ok, :earlier} -> first_not_ended(run, point, middle + 1, high)
      {:ok, _same_or_later} -> first_not_ended(run, point, low, middle)
      {:error, _exception} = error -> error
    end
  end

  defp first_not_ended(_run, _point, low, _high), do: {:ok, low}

  defp mask_candidates(operand) do
    if non_contiguous_mask?(operand) do
      case Tempo.to_interval(operand) do
        {:ok, %IntervalSet{} = set} -> {:ok, IntervalSet.members(set)}
        {:ok, %__MODULE__{} = interval} -> {:ok, [interval]}
        {:error, _} = error -> error
      end
    else
      {:ok, [operand]}
    end
  end

  # A mask above concrete finer units (`~o"1985-XX-15"`) does not denote a
  # contiguous grounding span: each admitted month contributes one concrete
  # day, with gaps between them. A trailing mask (`~o"20XX"`) is contiguous
  # and keeps the envelope treatment.
  defp non_contiguous_mask?(%Tempo{time: time}) do
    time
    |> Enum.drop_while(&(not masked_field?(&1)))
    |> Enum.any?(&(not masked_field?(&1)))
  end

  defp non_contiguous_mask?(_operand), do: false

  # Two unanchored values (no year) compare only on a shared leading unit —
  # the same-axis rule the set operations use. Same axis: the positional
  # `relation/2` is definite, so the possible set is the single relation it
  # returns. Different axes (or one operand anchored, the other not): the answer
  # depends on the missing year, so we signal that rather than guess.
  defp unanchored_possible_relations(a, b) do
    if same_axis_operands?(a, b) do
      case relation(a, b) do
        relation when is_atom(relation) -> MapSet.new([relation])
        {:error, _reason} = error -> error
      end
    else
      {:error, UnanchoredError.exception(value: unanchored_operand(a, b), reason: :comparison)}
    end
  end

  defp same_axis_operands?(a, b), do: leading_time_unit(a) == leading_time_unit(b)

  defp leading_time_unit(%Tempo{time: [{unit, _value} | _rest]}), do: unit
  defp leading_time_unit(%__MODULE__{from: %Tempo{} = from}), do: leading_time_unit(from)

  defp leading_time_unit(%IntervalSet{} = set), do: leading_time_unit(IntervalSet.first(set))

  defp leading_time_unit(_operand), do: nil

  defp unanchored_operand(a, b), do: if(anchored_operand?(a), do: b, else: a)

  defp anchored_operand?(%Tempo{} = value), do: Tempo.anchored?(value)
  defp anchored_operand?(%__MODULE__{from: %Tempo{} = from}), do: Tempo.anchored?(from)

  defp anchored_operand?(%IntervalSet{} = set) do
    case IntervalSet.members(set) do
      [interval] -> anchored_operand?(interval)
      _members -> true
    end
  end

  defp anchored_operand?(_operand), do: true

  defp masked_operand?(%Tempo{time: time}), do: Enum.any?(time, &masked_field?/1)
  defp masked_operand?(_operand), do: false

  defp masked_field?({_unit, {:mask, _digits}}), do: true
  defp masked_field?(_field), do: false

  defp classify_placements(a, b, a_places, b_places) do
    if length(a_places) * length(b_places) <= @max_placement_pairs do
      classify_each(for(ia <- a_places, ib <- b_places, do: {ia, ib}), [])
    else
      envelope_relations(a, b)
    end
  end

  # The relations of each pairing of placements, or the error of the first
  # pairing that has none.
  defp classify_each([{ia, ib} | rest], relations) do
    case classify(ia, ib) do
      {:error, _exception} = error -> error
      relation -> classify_each(rest, with_relation(relations, relation))
    end
  end

  defp classify_each([], relations), do: MapSet.new(relations)

  # Every crisp interval an operand could be, across its margin offsets.
  # A bare `%Tempo{}` value shifts rigidly (one margin, both endpoints
  # together); an explicit interval moves its endpoints independently
  # (each by its own margin), keeping only the still-ordered pairings.
  defp placements(%Tempo{} = value) do
    case to_single_interval(value, :graded) do
      {:ok, %__MODULE__{from: from, to: to}} ->
        {:ok, rigid_placements(from, to, margin_spec(value))}

      {:error, _} = error ->
        error
    end
  end

  defp placements(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}) do
    ordered_placements(
      for from_place <- offset_positions(from, margin_spec(from)),
          to_place <- offset_positions(to, margin_spec(to)),
          do: {from_place, to_place}
    )
  end

  defp placements(%IntervalSet{} = set) do
    case IntervalSet.members(set) do
      [interval] -> placements(interval)
      _members -> to_single_interval(set, :graded)
    end
  end

  defp placements(operand), do: to_single_interval(operand, :graded)

  # The pairings of two ends' positions that are still in order. Ends with no
  # line to share (`2020Y/X*Y6M15D`, a year and a day of no year) have no
  # order, which is the error returned.
  defp ordered_placements(pairs) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn {from, to}, {:ok, placed} ->
      case Compare.order(from, to) do
        {:ok, :earlier} -> {:cont, {:ok, [%__MODULE__{from: from, to: to} | placed]}}
        {:ok, _same_or_later} -> {:cont, {:ok, placed}}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
    |> ordered_in_turn()
  end

  defp ordered_in_turn({:ok, placed}), do: {:ok, Enum.reverse(placed)}
  defp ordered_in_turn({:error, _exception} = error), do: error

  defp rigid_placements(from, to, nil), do: [%__MODULE__{from: from, to: to}]

  defp rigid_placements(from, to, {unit, margin}) do
    for delta <- -margin..margin do
      %__MODULE__{from: shift_by(from, unit, delta), to: shift_by(to, unit, delta)}
    end
  end

  defp offset_positions(endpoint, nil), do: [endpoint]

  defp offset_positions(endpoint, {unit, margin}) do
    for delta <- -margin..margin, do: shift_by(endpoint, unit, delta)
  end

  defp shift_by(endpoint, _unit, 0), do: endpoint

  defp shift_by(endpoint, unit, delta) when delta > 0,
    do: Math.add(endpoint, Duration.new!([{unit, delta}]))

  defp shift_by(endpoint, unit, delta) when delta < 0,
    do: Math.subtract(endpoint, Duration.new!([{unit, -delta}]))

  # The ± margin of a value as `{unit, amount}`, or nil when crisp.
  defp margin_spec(%Tempo{time: time}) do
    Enum.find_value(time, fn
      {unit, {value, options}} when is_integer(value) and is_list(options) ->
        case Keyword.get(options, :margin_of_error) do
          nil -> nil
          margin -> {unit, margin}
        end

      _ ->
        nil
    end)
  end

  # The sound over-approximation: treat each endpoint's uncertainty range
  # independently. Looser than the placement enumeration (it ignores the
  # rigid-shift linkage), but O(1) — used only as the wide-margin
  # fallback. `:certain`/`:impossible` verdicts stay correct; it only
  # ever errs toward `:possible`.
  defp envelope_relations(a, b) do
    with {:ok, {a_from, a_to}} <- endpoint_envelopes(a),
         {:ok, {b_from, b_to}} <- endpoint_envelopes(b) do
      end_to_start = compare_ranges(a_to, b_from)
      start_to_end = compare_ranges(a_from, b_to)
      starts = compare_ranges(a_from, b_from)
      ends = compare_ranges(a_to, b_to)

      for e_bs <- end_to_start,
          s_be <- start_to_end,
          s <- starts,
          e <- ends,
          into: MapSet.new(),
          do: classify_relation(e_bs, s_be, s, e)
    end
  end

  # value -> {from_range, to_range}, each a {lo, hi} of endpoint Tempos.
  defp endpoint_envelopes(operand) do
    if masked_operand?(operand) do
      grounding_envelope(operand)
    else
      case to_single_interval(operand, :graded) do
        {:ok, %__MODULE__{from: from_endpoint, to: to_endpoint}} ->
          {from_margin, to_margin} = endpoint_margins(operand)
          {:ok, {widen(from_endpoint, from_margin), widen(to_endpoint, to_margin)}}

        {:error, _} = error ->
          error
      end
    end
  end

  # A masked value's grounding envelope: its unknown grounding is a
  # resolution-wide interval sliding anywhere inside the bounded span the mask
  # admits (`~o"20XXY"` → some year in `[2000, 2100)`). The from-endpoint
  # ranges over `[span_start, span_end − width]`, the to-endpoint over
  # `[span_start + width, span_end]`.
  defp grounding_envelope(operand) do
    with {:ok, %__MODULE__{from: span_start, to: span_end}} <- Tempo.to_interval(operand),
         {:ok, width} <- resolution_duration(operand) do
      from_range = {span_start, Math.subtract(span_end, width)}
      to_range = {Math.add(span_start, width), span_end}
      {:ok, {from_range, to_range}}
    else
      # A materialisation that isn't a single contiguous interval (an
      # IntervalSet of candidates) has no grounding envelope; those
      # values are routed through `candidate_relations/2` before this
      # path is reached.
      {:ok, _non_contiguous} -> {:error, no_width_error(operand)}
      {:error, _} = error -> error
    end
  end

  # `Tempo.resolution/1` is `{unit, count}` for a metric value (`{:year, 1}`)
  # but `{unit, finer_unit}` for a selection; only the former has a numeric
  # width to build a Duration from.
  defp resolution_duration(operand) do
    case Tempo.resolution(operand) do
      {unit, count} when is_integer(count) -> {:ok, Duration.new!([{unit, count}])}
      {_unit, _finer_unit} -> {:error, no_width_error(operand)}
    end
  end

  # A value whose candidates are several spans, or whose resolution is a
  # selection's, has no one width to slide across the span it may lie in.
  defp no_width_error(operand) do
    ConversionError.exception(
      value: operand,
      reason:
        "#{inspect(operand)} names several spans, so it has no one span whose place is " <>
          "uncertain: ask of each span in `Tempo.to_interval_set/1`."
    )
  end

  # A single ±-value's margin applies to both endpoints; an explicit
  # interval carries a margin per endpoint.
  defp endpoint_margins(%Tempo{} = value) do
    margin = margin_duration(value)
    {margin, margin}
  end

  defp endpoint_margins(%__MODULE__{from: from_endpoint, to: to_endpoint}) do
    {margin_duration(from_endpoint), margin_duration(to_endpoint)}
  end

  defp endpoint_margins(%IntervalSet{} = set) do
    case IntervalSet.members(set) do
      [interval] -> endpoint_margins(interval)
      _members -> {nil, nil}
    end
  end

  defp endpoint_margins(_operand), do: {nil, nil}

  # The ± margin of a value as a Duration, or nil when crisp.
  defp margin_duration(%Tempo{time: time}) do
    Enum.find_value(time, fn
      {unit, {value, options}} when is_integer(value) and is_list(options) ->
        case Keyword.get(options, :margin_of_error) do
          nil -> nil
          margin -> Duration.new!([{unit, margin}])
        end

      _ ->
        nil
    end)
  end

  defp margin_duration(_endpoint), do: nil

  defp widen(endpoint, nil), do: {endpoint, endpoint}

  defp widen(endpoint, %Duration{} = margin) do
    {Math.subtract(endpoint, margin), Math.add(endpoint, margin)}
  end

  # Which of :earlier/:same/:later two endpoint ranges could stand in:
  # earlier possible when a_lo < b_hi, later when a_hi > b_lo, same when
  # the ranges intersect.
  defp compare_ranges({a_lo, a_hi}, {b_lo, b_hi}) do
    lo_vs_hi = Compare.compare_endpoints(a_lo, b_hi)

    earlier? = lo_vs_hi == :earlier
    later? = Compare.compare_endpoints(a_hi, b_lo) == :later
    same? = lo_vs_hi != :later and Compare.compare_endpoints(b_lo, a_hi) != :later

    for {possible?, ordering} <- [{earlier?, :earlier}, {same?, :same}, {later?, :later}],
        possible?,
        into: MapSet.new(),
        do: ordering
  end
end
