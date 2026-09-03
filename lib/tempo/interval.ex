defmodule Tempo.Interval do
  @moduledoc """
  An explicit bounded span on the time line.

  Every Tempo value *is* an interval at some resolution; a bare
  `%Tempo{}` materialises to an `%Tempo.Interval{}` via
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
  alias Tempo.Duration
  alias Tempo.FloatingTempoError
  alias Tempo.Interval.Composition
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidUnitError
  alias Tempo.Iso8601.AST
  alias Tempo.Iso8601.Unit
  alias Tempo.LeapSeconds
  alias Tempo.Mask
  alias Tempo.MaterialisationError
  alias Tempo.Math
  alias Tempo.RequiresAnchorError

  @type t :: %__MODULE__{
          recurrence: pos_integer() | :infinity,
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

  @public_new_options [:from, :to, :duration, :recurrence, :repeat_rule, :unit, :metadata]

  # Units a caller may request as iteration granularity via `new/1` —
  # the month-based calendar/clock chain the walk-time fill can reach.
  # Selector-only units (`:instance`, `:day_of_week`, …) are not
  # iteration units; `:week`/`:day_of_week` are reachable only from
  # week-calendar values, where materialisation sets them itself.
  @iteration_units [:year, :month, :day, :hour, :minute, :second]

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

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(options) when is_list(options) do
    with :ok <- ensure_keyword_options(options),
         :ok <- ensure_has_anchor(options),
         from <- Keyword.get(options, :from),
         to <- Keyword.get(options, :to),
         :ok <- validate_endpoint_types(from, to),
         {from, to} = propagate_endpoint_frame(from, to),
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

  defp ensure_has_anchor(options) do
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
  # floating and universal time lines — so a grounded `to` frame (zone
  # or offset) propagates backward onto a floating `from`. Propagation
  # is one-directional (`to` → `from` only) and never overwrites a
  # frame `from` already carries; a zone on `from` alone never flows
  # forward. The same rule serves the IXDTF parser (where a trailing
  # `[zone]` binds to the upper endpoint) and `new/1`, so a constructed
  # interval and its re-parsed ISO 8601 string cannot disagree.
  def propagate_endpoint_frame(%Tempo{} = from, %Tempo{} = to) do
    if Tempo.floating?(from) and not Tempo.floating?(to) do
      {copy_frame(to, from), to}
    else
      {from, to}
    end
  end

  def propagate_endpoint_frame(from, to), do: {from, to}

  # Overlay `source`'s grounding frame — its numeric `shift` and the zone
  # fields of its `extended` — onto `target`, leaving target's own units,
  # calendar, and tags untouched.
  defp copy_frame(%Tempo{} = source, %Tempo{} = target) do
    %{target | shift: source.shift, extended: put_zone_fields(target.extended, source.extended)}
  end

  defp put_zone_fields(target_extended, nil), do: target_extended

  defp put_zone_fields(nil, %{zone_id: zone_id, zone_offset: zone_offset} = source) do
    %{
      zone_id: zone_id,
      zone_offset: zone_offset,
      zone_critical: Map.get(source, :zone_critical, false),
      calendar: nil,
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

  defp validate_from_to_order(%Tempo{} = from, %Tempo{} = to) do
    case Compare.compare_endpoints(from, to) do
      :earlier ->
        :ok

      :same ->
        {:error,
         IntervalEndpointsError.exception(
           interval: %__MODULE__{from: from, to: to},
           operation: :new,
           reason:
             ":from and :to endpoints are equal — a zero-extent interval " <>
               "is not a valid interval under the half-open [from, to) convention. " <>
               "If the operation that produced these endpoints is set-theoretic, " <>
               "return an empty IntervalSet instead."
         )}

      :later ->
        {:error,
         IntervalEndpointsError.exception(
           interval: %__MODULE__{from: from, to: to},
           operation: :new,
           reason: ":from endpoint is later than :to endpoint"
         )}
    end
  end

  defp validate_from_to_order(_from, _to), do: :ok

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

  # An unanchored recurrence with no selection — `R/../P1W`, the inspect form
  # of a cron/`RRule` value that has no `:from`. The duration is the cadence,
  # kept as-is; the start stays `nil` (not `:undefined`) so it matches what
  # inspect renders and round-trips to the same value.
  def build([:undefined, {:duration, duration}]) do
    %__MODULE__{from: nil, duration: Duration.build(duration)}
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

  # An unanchored recurrence carrying a selection — `R/../P1W/FLT17H0M5KN`, the
  # inspect form of a cron schedule with no `:from`. Start stays `nil`; the
  # duration is the cadence and the selection is the repeat rule.
  def build([:undefined, {:duration, duration}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: nil,
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
  defp inherit_from_start(%Tempo{time: to_units} = to, %Tempo{time: from_units})
       when is_list(to_units) and is_list(from_units) do
    with [{coarsest, _value} | _rest] <- to_units,
         rank when is_integer(rank) <- unit_rank(coarsest) do
      %{to | time: higher_order_than(from_units, rank) ++ to_units}
    else
      _not_inheritable -> to
    end
  end

  defp inherit_from_start(to, _from), do: to

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
  # upper bound is `add_unit(unit=last)` so it carries correctly.
  #
  # `add_unit` at a date unit needs the coarser units present to
  # carry (days-in-month needs year+month; months-in-year needs
  # year), and the carry can cascade up to year. A group materialises
  # only when its value carries that contiguous anchored prefix; a
  # non-anchored fragment (`5G10DU` — days 41..50, no year) or an
  # ordinal-day group does not, and has no concrete span. Checking
  # the prefix up front keeps the path total without a `rescue`.
  defp group_boundary(tempo, time, unit, first, last, calendar) do
    prefix = List.delete_at(time, -1)

    cond do
      group_required_units(unit) == :not_a_group_unit ->
        group_error(tempo)

      # Fully anchored: the carry chain up to year is satisfied.
      anchored_prefix?(prefix, unit) ->
        materialise_group(tempo, prefix, unit, first, last, calendar)

      # A *pure* time-of-day group (no date components) materialises to
      # a **non-anchored** interval — the relative span it denotes on
      # the time-of-day axis (`16:01..16:16`) — provided the upper
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

  defp anchored_prefix?(prefix, unit) do
    Enum.all?(group_required_units(unit), &Keyword.has_key?(prefix, &1))
  end

  defp group_error(tempo) do
    {:error, MaterialisationError.exception(value: tempo, reason: :unanchored_group)}
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
        with {:ok, upper_time} <- Math.add_unit(time, :microsecond, calendar) do
          {:ok, build_bounds(tempo, time, upper_time), nil}
        end

      # A second-resolution value is no longer the finest unit once
      # sub-second (microsecond) resolution exists below it, so it
      # materialises to a one-second span rather than erroring. Like
      # the microsecond case the lower bound is the value as-is and
      # the upper is one second later, keeping both endpoints at
      # second resolution instead of drilling into microseconds.
      {:second, _value} ->
        with {:ok, upper_time} <- Math.add_unit(time, :second, calendar) do
          {:ok, build_bounds(tempo, time, upper_time), nil}
        end

      _ ->
        {unit, _span} = Tempo.resolution(tempo)

        case Unit.implicit_enumerator(unit, calendar) do
          nil ->
            {:error, MaterialisationError.exception(value: tempo, reason: :finest_resolution)}

          {next_unit, _range} ->
            implicit_span(tempo, time, unit, next_unit, calendar)
        end
    end
  end

  # The implicit span is one unit wide at the value's own resolution — a
  # day spans `[day, day+1)`, not `[day T0H, day+1 T0H)`. The next-finer
  # unit is returned separately as the iteration granularity; the walk
  # fills the anchor to it at iteration time (`Steps.fill_to_unit/3`).
  defp implicit_span(tempo, time, unit, next_unit, calendar) do
    with {:ok, upper_time} <- Math.add_unit(time, unit, calendar) do
      {:ok, build_bounds(tempo, time, upper_time), next_unit}
    end
  end

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
  defp significant_digits_as_mask(time) do
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
    # No un-masked prefix — nothing to anchor against. Shouldn't
    # happen in practice (the parser always resolves a year before
    # finer units can appear), but raise a clear error if it does.
    {:error,
     MaterialisationError.exception(
       reason:
         "Cannot materialise a masked Tempo with no un-masked coarser unit — " <>
           "nothing to anchor the span against."
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
       MaterialisationError.exception(
         reason:
           "Cannot materialise a masked Tempo whose un-masked prefix contains ranges, " <>
             "selections, or other non-scalar values."
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
  one of these relations.

  ### Arguments

  * `a` and `b` are each one of:

    * a `t:Tempo.t/0` point (materialised via its implicit span).

    * a `t:Tempo.Interval.t/0`.

    * a `t:Tempo.IntervalSet.t/0` with exactly one member.

  ### Returns

  * One of the 13 relation atoms.

  * `{:error, reason}` when either operand is a multi-member
    IntervalSet, an open-ended interval, or otherwise can't be
    reduced to a single bounded interval. For multi-member
    sets use `Tempo.IntervalSet.relation_matrix/2`.

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
    reject_mixed_frame!(a, b)

    with {:ok, iv_a} <- to_single_interval(a, :a),
         {:ok, iv_b} <- to_single_interval(b, :b) do
      classify(iv_a, iv_b)
    end
  end

  @doc """
  The inverse Allen relation.

  If `relation(a, b)` returns `r`, then `relation(b, a)` returns
  `inverse_relation(r)`.

  ### Examples

      iex> Tempo.Interval.inverse_relation(:contains)
      :during

      iex> Tempo.Interval.inverse_relation(:precedes)
      :preceded_by

      iex> Tempo.Interval.inverse_relation(:equals)
      :equals

  """
  @spec inverse_relation(relation()) :: relation()
  def inverse_relation(:precedes), do: :preceded_by
  def inverse_relation(:preceded_by), do: :precedes
  def inverse_relation(:meets), do: :met_by
  def inverse_relation(:met_by), do: :meets
  def inverse_relation(:overlaps), do: :overlapped_by
  def inverse_relation(:overlapped_by), do: :overlaps
  def inverse_relation(:starts), do: :started_by
  def inverse_relation(:started_by), do: :starts
  def inverse_relation(:finishes), do: :finished_by
  def inverse_relation(:finished_by), do: :finishes
  def inverse_relation(:during), do: :contains
  def inverse_relation(:contains), do: :during
  def inverse_relation(:equals), do: :equals

  @doc """
  Compose two Allen relations — the relations possible from `A` to `C` given
  `A r1 B` and `B r2 C`.

  This is Allen's interval-algebra composition (Allen 1983): a constant-time
  read of the 13×13 table. Where `relation/2` compares two intervals you hold,
  `compose/2` takes one qualitative step with no interval in hand —
  *"if A precedes B and B is during C, how can A relate to C?"* — and returns
  every relation some arrangement of the three intervals allows. It is the same
  reasoning `Tempo.Network.Solver.relation/3` applies across a whole network,
  reduced to a single step.

  ### Arguments

  * `relation1` is the Allen relation from `A` to `B` — one of the 13 atoms
    `relation/2` returns.

  * `relation2` is the Allen relation from `B` to `C`.

  ### Returns

  * A list of the relations possible from `A` to `C`, in Allen's canonical
    order — one element when the composition is determined, up to all 13 when
    the step is fully ambiguous.

  * `{:error, {:invalid_relation, term}}` when either argument is not one of
    the 13 relation atoms.

  ### Examples

      iex> Tempo.Interval.compose(:precedes, :during)
      [:precedes, :meets, :overlaps, :starts, :during]

      iex> Tempo.Interval.compose(:equals, :overlaps)
      [:overlaps]

      iex> Tempo.Interval.compose(:precedes, :nonsense)
      {:error, {:invalid_relation, :nonsense}}

  """
  @spec compose(relation(), relation()) ::
          [relation()] | {:error, {:invalid_relation, term()}}
  def compose(relation1, relation2) do
    case Composition.compose(relation1, relation2) do
      nil -> {:error, {:invalid_relation, first_invalid(relation1, relation2)}}
      relations -> relations
    end
  end

  defp first_invalid(relation1, relation2) do
    if relation1 in Composition.relations(), do: relation2, else: relation1
  end

  # Three endpoint comparisons drive the 13-way branch:
  # `a.from vs b.from`, `a.to vs b.to`, and the "seam" checks
  # `a.to vs b.from` / `a.from vs b.to` which disambiguate
  # disjoint (meets/precedes and their inverses) from
  # overlapping cases. Dispatched as a multi-head table on the four
  # comparisons — the head count is the size of Allen's 13-relation
  # algebra.
  defp classify(%__MODULE__{from: a_from, to: a_to}, %__MODULE__{from: b_from, to: b_to}) do
    classify_relation(
      Compare.compare_endpoints(a_to, b_from),
      Compare.compare_endpoints(a_from, b_to),
      Compare.compare_endpoints(a_from, b_from),
      Compare.compare_endpoints(a_to, b_to)
    )
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
    {:error, MaterialisationError.exception(value: interval, reason: :recurring_interval)}
  end

  defp to_single_interval(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = iv, _label), do: {:ok, iv}

  defp to_single_interval(%IntervalSet{} = set, label) do
    case IntervalSet.to_list(set) do
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

  defp to_single_interval(%__MODULE__{}, label) do
    {:error,
     ArgumentError.exception(
       "Tempo.Interval.relation/2 needs bounded intervals on both sides. " <>
         "Operand #{inspect(label)} has an open-ended endpoint (`:undefined`)."
     )}
  end

  # A one-of set is an epistemic disjunction — it has no single crisp
  # relation, only a set of possible ones. The crisp API refuses with the
  # same error `to_interval/1` gives; the certainty API (`relation_certainty/3`,
  # `possibly_before?/2`, …) answers the question the set can actually support.
  defp to_single_interval(%Tempo.Set{type: :one} = set, _label) do
    {:error, MaterialisationError.exception(value: set, reason: :one_of_set)}
  end

  defp to_single_interval(other, label) do
    {:error,
     ArgumentError.exception(
       "Tempo.Interval.relation/2 cannot classify operand #{inspect(label)}: " <>
         "#{inspect(other)}"
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
  neither `:undefined` nor `nil`. Useful as a guard before set
  operations or duration checks.

  ### Examples

      iex> Tempo.Interval.bounded?(%Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"})
      true

      iex> Tempo.Interval.bounded?(%Tempo.Interval{from: ~o"2026-06-01", to: :undefined})
      false

  """
  @spec bounded?(t()) :: boolean()
  def bounded?(%__MODULE__{from: %Tempo{}, to: %Tempo{}}), do: true
  def bounded?(%__MODULE__{}), do: false

  @doc """
  `true` when the interval has zero or negative length —
  `from == to` (degenerate instant) or `from > to` (inverted
  span).

  Under the half-open `[from, to)` convention, an interval with
  `from >= to` contains no real instants. Empty intervals pass
  `bounded?/1` but have no span; inverted intervals are treated
  as empty rather than as a span with "negative" duration.

  ### Examples

      iex> Tempo.Interval.empty?(%Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-15"})
      true

      iex> Tempo.Interval.empty?(%Tempo.Interval{from: ~o"2026-06-20", to: ~o"2026-06-15"})
      true

      iex> Tempo.Interval.empty?(%Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"})
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}) do
    Compare.compare_endpoints(from, to) in [:same, :later]
  end

  def empty?(%__MODULE__{}), do: false

  @doc """
  `true` when two intervals describe the same temporal extent,
  regardless of calendar, zone display, or attached metadata.

  Standard `==` compares all struct fields, including `:metadata`,
  `:calendar`, and the zone-display details on the endpoints, so the
  same span shown in two different zones compares unequal.
  `equivalent?/2` projects endpoints to UTC and compares only the
  temporal positions — matching the equivalence notion of the
  T_bounded_meeting ontology of Grüninger and Li (TIME 2017), under
  which intervals are individuated by their position in the structure
  of `meets`, not by labels.

  Recurrence-related fields (`:recurrence`, `:direction`,
  `:repeat_rule`, `:duration`) must match structurally: two recurring
  intervals with different rules describe different extents.

  ### Arguments

  * `a` and `b` are `t:t/0` values.

  ### Returns

  * `true` if both intervals occupy the same temporal extent under UTC projection.

  * `false` otherwise.

  ### Examples

      iex> a = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"}
      iex> b = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"}
      iex> Tempo.Interval.equivalent?(a, b)
      true

      iex> a = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"}
      iex> b = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-17"}
      iex> Tempo.Interval.equivalent?(a, b)
      false

  """
  @spec equivalent?(t(), t()) :: boolean()
  def equivalent?(%__MODULE__{} = a, %__MODULE__{} = b) do
    endpoints_equivalent?(a.from, b.from) and
      endpoints_equivalent?(a.to, b.to) and
      a.recurrence == b.recurrence and
      a.direction == b.direction and
      a.repeat_rule == b.repeat_rule and
      a.duration == b.duration
  end

  defp endpoints_equivalent?(%Tempo{} = a, %Tempo{} = b) do
    Compare.compare_endpoints(a, b) == :same
  end

  defp endpoints_equivalent?(:undefined, :undefined), do: true
  defp endpoints_equivalent?(nil, nil), do: true
  defp endpoints_equivalent?(nil, :undefined), do: true
  defp endpoints_equivalent?(:undefined, nil), do: true
  defp endpoints_equivalent?(_, _), do: false

  ## ----------------------------------------------------------
  ## Duration query + duration predicates
  ## ----------------------------------------------------------

  @doc """
  Return the interval's `from` endpoint.

  A named helper so callers never have to reach into the struct
  fields in user-facing code. Compose with `Tempo.day/1`, `Tempo.year/1`,
  etc. to extract components of the starting point.

  ### Arguments

  * `interval` is a `t:t/0`.

  ### Returns

  * The `from` endpoint as a `t:Tempo.t/0` or `:undefined` for
    open-ended intervals.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      iex> Tempo.Interval.from(iv) |> Tempo.day()
      15

  """
  @spec from(t()) :: Tempo.t() | :undefined
  def from(%__MODULE__{from: from}), do: from

  @doc """
  Return the interval's `to` endpoint.

  Under half-open `[from, to)` semantics, this is the exclusive
  upper bound — the first instant **outside** the span.

  ### Arguments

  * `interval` is a `t:t/0`.

  ### Returns

  * The `to` endpoint as a `t:Tempo.t/0` or `:undefined` for
    open-ended intervals.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      iex> Tempo.Interval.to(iv) |> Tempo.day()
      20

  """
  @spec to(t()) :: Tempo.t() | :undefined
  def to(%__MODULE__{to: to}), do: to

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
  def endpoints(%__MODULE__{from: from, to: to}), do: {from, to}

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
  Return the interval's length as a `%Tempo.Duration{}` in
  seconds. Returns `:infinity` for unbounded intervals (one or
  both endpoints `:undefined`).

  The result is calendar- and zone-aware — it goes through
  `Tempo.Compare.to_utc_seconds/1` so cross-zone intervals
  compute a correct wall-clock delta.

  ### Options

  * `:leap_seconds` — when `true`, adds one second to the
    returned duration for each IERS leap-second insertion that
    falls inside `[from, to)`. Defaults to `false` so behaviour
    matches `DateTime`, `Time`, and `:calendar` from Elixir/OTP
    (none of which count leap seconds). See
    `Tempo.Interval.spans_leap_second?/1` and
    `leap_seconds_spanned/1` for detection without arithmetic.

  ### Examples

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"})
      ~o"PT3600S"

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-06-15", to: :undefined})
      :infinity

      iex> iv = %Tempo.Interval{from: ~o"2016-12-31T23:59:00Z", to: ~o"2017-01-01T00:01:00Z"}
      iex> Tempo.Interval.duration(iv)
      ~o"PT120S"
      iex> Tempo.Interval.duration(iv, leap_seconds: true)
      ~o"PT121S"

  """
  @spec duration(t(), keyword()) :: Duration.t() | :infinity
  def duration(interval, opts \\ [])

  # A finite recurring interval's duration is the total across its
  # occurrences, which only the materialised set can report — reading
  # the base span (or the open `to` as infinity) would be wrong on
  # both counts. Unbounded recurrences fall through to `:infinity`,
  # which is their true total extent.
  def duration(%__MODULE__{recurrence: recurrence} = interval, _opts)
      when is_integer(recurrence) and recurrence > 1 do
    raise MaterialisationError.exception(value: interval, reason: :recurring_duration)
  end

  def duration(%__MODULE__{from: :undefined}, _opts), do: :infinity
  def duration(%__MODULE__{to: :undefined}, _opts), do: :infinity
  def duration(%__MODULE__{from: nil}, _opts), do: :infinity
  def duration(%__MODULE__{to: nil}, _opts), do: :infinity

  def duration(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to} = iv, opts) do
    :ok = require_same_calendar(from, to, "Tempo.Interval.duration/1")

    if empty?(iv) do
      # Degenerate (from == to) and inverted (from > to) intervals
      # contain no real instants under `[from, to)`. Duration is
      # zero rather than a negative count of wall-clock seconds.
      %Duration{time: [second: 0]}
    else
      base = Compare.to_utc_seconds(to) - Compare.to_utc_seconds(from)

      seconds =
        if Keyword.get(opts, :leap_seconds, false) do
          # Positive insertions add a second; negative removals
          # (reserved, none yet used) would subtract one.
          base + length(leap_second_insertions_spanned(iv)) -
            length(leap_second_removals_spanned(iv))
        else
          base
        end

      %Duration{time: [second: seconds]}
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
  def spans_leap_second?(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = iv) do
    leap_second_insertions_spanned(iv) != [] or
      leap_second_removals_spanned(iv) != []
  end

  def spans_leap_second?(%__MODULE__{}), do: false

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

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2015-01-01", to: ~o"2017-12-31"}
      iex> Tempo.Interval.leap_seconds_spanned(iv)
      [{2015, 6, 30}, {2016, 12, 31}]

  """
  @spec leap_seconds_spanned(t()) :: [{integer(), 1..12, 1..31}]
  def leap_seconds_spanned(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = iv) do
    # Union of positive insertions and (reserved) negative
    # removals, in chronological order.
    (leap_second_insertions_spanned(iv) ++ leap_second_removals_spanned(iv))
    |> Enum.sort()
  end

  def leap_seconds_spanned(%__MODULE__{}), do: []

  defp leap_second_insertions_spanned(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}) do
    :ok = require_same_calendar(from, to, "Tempo.Interval.leap_seconds_spanned/1")
    from_s = Compare.to_utc_seconds(from)
    to_s = Compare.to_utc_seconds(to)

    for {y, m, d} <- LeapSeconds.dates(),
        leap_second_in_interval?(y, m, d, from_s, to_s),
        do: {y, m, d}
  end

  defp leap_second_removals_spanned(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}) do
    :ok = require_same_calendar(from, to, "Tempo.Interval.leap_seconds_spanned/1")
    from_s = Compare.to_utc_seconds(from)
    to_s = Compare.to_utc_seconds(to)

    for {y, m, d} <- LeapSeconds.removals(),
        leap_second_in_interval?(y, m, d, from_s, to_s),
        do: {y, m, d}
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

  # Cross-calendar endpoints produce nonsense arithmetic — the
  # Gregorian seconds of Hebrew 5786 and Gregorian 2026 measure
  # from different epochs and subtracting them yields a garbage
  # duration. Refuse explicitly and tell the caller how to fix it.
  defp require_same_calendar(
         %Tempo{calendar: cal, time: from_time},
         %Tempo{calendar: cal, time: to_time},
         _context
       ) do
    # Non-anchored endpoints (no year) share the time-of-day axis
    # across any calendar — no conversion needed.
    _ = from_time
    _ = to_time
    :ok
  end

  defp require_same_calendar(%Tempo{} = from, %Tempo{} = to, context) do
    if not Tempo.anchored?(from) or not Tempo.anchored?(to) do
      :ok
    else
      raise ArgumentError,
            "#{context} requires both endpoints in the same calendar. " <>
              "Got #{inspect(from.calendar)} and #{inspect(to.calendar)}. " <>
              "Convert one endpoint first — set operations such as " <>
              "`Tempo.intersection/2` and `Tempo.difference/2` handle " <>
              "cross-calendar inputs automatically via `Date.convert!/2`."
    end
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
  def at_least?(%__MODULE__{from: :undefined}, _), do: true
  def at_least?(%__MODULE__{to: :undefined}, _), do: true

  def at_least?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) in [:earlier, :same]
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
  def at_most?(%__MODULE__{from: :undefined}, _), do: false
  def at_most?(%__MODULE__{to: :undefined}, _), do: false

  def at_most?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) in [:later, :same]
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
  def exactly?(%__MODULE__{from: :undefined}, _), do: false
  def exactly?(%__MODULE__{to: :undefined}, _), do: false

  def exactly?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) == :same
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
  def longer_than?(%__MODULE__{from: :undefined}, _), do: true
  def longer_than?(%__MODULE__{to: :undefined}, _), do: true

  def longer_than?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) == :earlier
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
  def shorter_than?(%__MODULE__{from: :undefined}, _), do: false
  def shorter_than?(%__MODULE__{to: :undefined}, _), do: false

  def shorter_than?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) == :later
  end

  ## ----------------------------------------------------------
  ## Relation predicates — thin shortcuts over relation/2
  ## ----------------------------------------------------------

  @doc """
  `true` when `a` ends strictly before `b` starts, with a gap
  (Allen's `:precedes`). Use `adjacent?/2` to include the
  no-gap case.

  Returns `false` on any error or non-matching relation.
  """
  @spec before?(interval_like(), interval_like()) :: boolean()
  def before?(a, b), do: match_relation(a, b, [:precedes])

  @doc """
  `true` when `a` starts strictly after `b` ends, with a gap
  (Allen's `:preceded_by`).
  """
  @spec after?(interval_like(), interval_like()) :: boolean()
  def after?(a, b), do: match_relation(a, b, [:preceded_by])

  @doc """
  `true` when `a`'s end coincides exactly with `b`'s start
  (Allen's `:meets`). Under the half-open convention this means
  the intervals share no point but have no gap.
  """
  @spec meets?(interval_like(), interval_like()) :: boolean()
  def meets?(a, b), do: match_relation(a, b, [:meets])

  @doc """
  `true` when the two intervals touch at a single boundary —
  either `a` meets `b` or `b` meets `a` (Allen's
  `:meets | :met_by`).

  ### Examples

      iex> Tempo.Interval.adjacent?(~o"2026-06-15", ~o"2026-06-16")
      true

      iex> Tempo.Interval.adjacent?(~o"2026-06-15", ~o"2026-06-17")
      false

  """
  @spec adjacent?(interval_like(), interval_like()) :: boolean()
  def adjacent?(a, b), do: match_relation(a, b, [:meets, :met_by])

  @doc """
  `true` when `a` is strictly inside `b` — both endpoints of
  `a` lie strictly within `b` (Allen's `:during`). Shared-
  endpoint cases (`:starts`, `:finishes`) return `false`; use
  `within?/2` for the inclusive version.
  """
  @spec during?(interval_like(), interval_like()) :: boolean()
  def during?(a, b), do: match_relation(a, b, [:during])

  @doc """
  `true` when `a` lies inside `b` inclusive of shared
  endpoints (Allen's `:equals | :starts | :during | :finishes`).
  The canonical "does this fit inside that window?" predicate.

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
  #   * Un-anchored values (no year) — comparable only on a shared leading
  #     unit (the same-axis rule); off-axis they return a
  #     `RequiresAnchorError` rather than guess the missing year.
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

  The three-valued counterpart of `overlaps?/2`. Each margin-bearing
  endpoint is widened into a range, and the result reports whether
  intersection holds for every consistent placement (`:certain`), some
  (`:possible`), or none (`:impossible`). Crisp operands degrade exactly
  to `overlaps?/2` (only `:certain`/`:impossible` occur).

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
    `t:Tempo.RequiresAnchorError.t/0` when an un-anchored operand is
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
  its mask admits, and two un-anchored operands compare on a shared leading
  unit.

  ### Arguments

  * `a` and `b` are bounded interval-like values.

  * `target` is a single Allen relation atom (e.g. `:during`) or a list
    of relation atoms.

  ### Returns

  * `:certain`, `:possible`, or `:impossible`.

  * `{:error, reason}` for open-ended or multi-member operands, or a
    `t:Tempo.RequiresAnchorError.t/0` when an un-anchored operand is
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
  `overlaps?/2`.

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
  `true` when `a` ends before `b` starts, with a gap (Allen `:precedes`),
  for *every* placement of their `±` margins. Crisp counterpart:
  `before?/2`.

  ### Examples

      iex> Tempo.Interval.certainly_before?(~o"2000±1Y", ~o"2010±1Y")
      true

      iex> Tempo.Interval.certainly_before?(~o"2000±1Y", ~o"2001±1Y")
      false

  """
  @spec certainly_before?(interval_like(), interval_like()) :: boolean()
  def certainly_before?(a, b), do: certainty_in?(relation_certainty(a, b, :precedes), [:certain])

  @doc """
  `true` when `a` *could* end before `b` starts for some placement of
  their `±` margins.

  ### Examples

      iex> Tempo.Interval.possibly_before?(~o"2000±1Y", ~o"2001±1Y")
      true

  """
  @spec possibly_before?(interval_like(), interval_like()) :: boolean()
  def possibly_before?(a, b),
    do: certainty_in?(relation_certainty(a, b, :precedes), [:certain, :possible])

  @doc """
  `true` when `a` starts after `b` ends, with a gap (Allen
  `:preceded_by`), for *every* placement of their `±` margins. Crisp
  counterpart: `after?/2`.

  ### Examples

      iex> Tempo.Interval.certainly_after?(~o"2010±1Y", ~o"2000±1Y")
      true

  """
  @spec certainly_after?(interval_like(), interval_like()) :: boolean()
  def certainly_after?(a, b),
    do: certainty_in?(relation_certainty(a, b, :preceded_by), [:certain])

  @doc """
  `true` when `a` *could* start after `b` ends for some placement of
  their `±` margins.

  ### Examples

      iex> Tempo.Interval.possibly_after?(~o"2001±1Y", ~o"2000±1Y")
      true

  """
  @spec possibly_after?(interval_like(), interval_like()) :: boolean()
  def possibly_after?(a, b),
    do: certainty_in?(relation_certainty(a, b, :preceded_by), [:certain, :possible])

  # A certainty error must surface, not read as `false` — a silent false
  # asserts "impossible", a claim the error explicitly could not make.
  defp certainty_in?({:error, exception}, _accepted) when is_exception(exception),
    do: raise(exception)

  defp certainty_in?({:error, reason}, _accepted), do: raise(ArgumentError, to_string(reason))
  defp certainty_in?(certainty, accepted), do: certainty in accepted

  ## Graded-relation internals

  defp concept_certainty(a, b, concept) do
    reject_mixed_frame!(a, b)

    case possible_relations(a, b) do
      {:error, _} = error -> error
      possible -> certainty(possible, concept)
    end
  end

  @doc false
  # A floating value has no position on the universal time line, so it
  # cannot be compared with a grounded one — every crisp relation and
  # certainty query rejects the mixed frame rather than silently
  # grounding the floating side to UTC. Ground it first with
  # `Tempo.in_zone/2` (or an offset). Two floating or two grounded
  # operands compare normally. Shared with `Tempo.Operations` so the
  # set-theoretic predicates (`overlaps?/2`, `disjoint?/2`, …) reject
  # the same mismatch.
  def reject_mixed_frame!(a, b) do
    case floating_conflict(a, b) do
      %Tempo{} = floating ->
        raise FloatingTempoError.exception(operation: :compare, value: floating)

      nil ->
        :ok
    end
  end

  # Returns the floating endpoint Tempo when `a` and `b` are a
  # floating-vs-grounded mismatch, else `nil` (same frame, or a frame
  # can't be determined — e.g. a fully open interval).
  defp floating_conflict(a, b) do
    with %Tempo{} = ta <- frame_tempo(a),
         %Tempo{} = tb <- frame_tempo(b),
         true <- Tempo.floating?(ta) != Tempo.floating?(tb) do
      if Tempo.floating?(ta), do: ta, else: tb
    else
      _ -> nil
    end
  end

  defp frame_tempo(%Tempo{} = tempo), do: tempo
  defp frame_tempo(%__MODULE__{from: %Tempo{} = from}), do: from
  defp frame_tempo(%__MODULE__{to: %Tempo{} = to}), do: to
  defp frame_tempo(%IntervalSet{} = set), do: frame_tempo(IntervalSet.first(set))
  defp frame_tempo(_other), do: nil

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
      union_over_choices(choices_a, choices_b)
    end
  end

  defp mask_candidates(operand) do
    if non_contiguous_mask?(operand) do
      case Tempo.to_interval(operand) do
        {:ok, %IntervalSet{} = set} -> {:ok, IntervalSet.to_list(set)}
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

  # Two un-anchored values (no year) compare only on a shared leading unit —
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
      {:error,
       RequiresAnchorError.exception(value: unanchored_operand(a, b), reason: :comparison)}
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
    case IntervalSet.to_list(set) do
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
      for ia <- a_places, ib <- b_places, into: MapSet.new(), do: classify(ia, ib)
    else
      envelope_relations(a, b)
    end
  end

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
    ordered =
      for from_place <- offset_positions(from, margin_spec(from)),
          to_place <- offset_positions(to, margin_spec(to)),
          Compare.compare_endpoints(from_place, to_place) == :earlier do
        %__MODULE__{from: from_place, to: to_place}
      end

    {:ok, ordered}
  end

  defp placements(%IntervalSet{} = set) do
    case IntervalSet.to_list(set) do
      [interval] -> placements(interval)
      _members -> to_single_interval(set, :graded)
    end
  end

  defp placements(operand), do: to_single_interval(operand, :graded)

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
      {:ok, _non_contiguous} -> {:error, :no_resolution}
      {:error, _} = error -> error
    end
  end

  # `Tempo.resolution/1` is `{unit, count}` for a metric value (`{:year, 1}`)
  # but `{unit, finer_unit}` for a selection; only the former has a numeric
  # width to build a Duration from.
  defp resolution_duration(operand) do
    case Tempo.resolution(operand) do
      {unit, count} when is_integer(count) -> {:ok, Duration.new!([{unit, count}])}
      {_unit, _finer_unit} -> {:error, :no_resolution}
    end
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
    case IntervalSet.to_list(set) do
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
