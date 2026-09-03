if Code.ensure_loaded?(ICal) do
  defmodule Tempo.ICal do
    @moduledoc """
    Import iCalendar (RFC 5545) data into `%Tempo.IntervalSet{}`.

    This module wraps the [`ical`](https://github.com/expothecary/ical)
    parser and translates each `VEVENT` into a `%Tempo.Interval{}`
    with full event metadata (summary, description, location,
    attendees, status, …) attached to the interval's `:metadata`
    map. The `VCALENDAR` envelope's metadata (product id, version,
    calendar scale, method) attaches to the `IntervalSet`'s
    `:metadata` map.

    Every pipeline step that accepts a Tempo value — set
    operations, `Enum.take/2`, resolution alignment — preserves
    the metadata through to the result. That lets free/busy and
    scheduling queries stay connected to their source events.

    The `ical` dependency is declared `optional: true` in `mix.exs`.
    `Tempo.ICal` is only compiled when `ical` is available in the
    dependency tree; projects that don't import calendar data don't
    pay the compile cost.

    ## Availability

    `VEVENT`s say what is **taken**. `available_from_ical/2` reads the
    complementary [RFC 7953](https://www.rfc-editor.org/rfc/rfc7953.html)
    `VAVAILABILITY` components, which say what is **offered** — a
    resource's open hours, with `AVAILABLE` subcomponents repeating
    under their own `RRULE` and `PRIORITY` resolving overlaps. A
    scheduler usually wants both, and they compose directly:

        {:ok, free} = Tempo.ICal.available_from_ical(ics, within: week)
        {:ok, busy} = Tempo.ICal.from_ical(ics, bound: week)
        {:ok, bookable} = Tempo.difference(free, busy)

    ## Required reading

    * [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545) — the iCalendar spec.
    * [RFC 7953](https://www.rfc-editor.org/rfc/rfc7953) — calendar availability.
    * `guides/set-operations.md` for how the imported data is used downstream.

    ## RFC 5545 coverage

    | Property  | Status                                            |
    | --------- | ------------------------------------------------- |
    | `RRULE`   | Fully supported — every `BY*` part, `WKST`, and   |
    |           | `BYSETPOS` flow through the interpreter.          |
    | `RDATE`   | Supported — extra occurrences with the event's    |
    |           | own span.                                         |
    | `EXDATE`  | Supported — start-moment match removes the        |
    |           | corresponding occurrence.                         |
    | `EXRULE`  | Not surfaced by the underlying `ical` library, so |
    |           | not implementable at this layer. EXRULE is also   |
    |           | RFC-deprecated (RFC 2445 → 5545).                 |
    | Multiple  | RFC 5545 says SHOULD NOT; some exports do it      |
    | `RRULE`   | anyway. The `ical` library exposes only the       |
    | per       | first `RRULE` on `event.rrule`, so we materialise |
    | `VEVENT`  | that one and silently ignore the rest.            |
    | `DURATION`| Supported as the alternative to `DTEND`, on       |
    |           | `VEVENT`, `VAVAILABILITY` and `AVAILABLE` alike.  |

    ## Zoned, UTC, and floating times

    A `DATE-TIME` value takes one of three RFC 5545 §3.3.5 forms, and
    each maps to a faithful `%Tempo{}`:

    * **UTC** (`20220615T100000Z`) → a zoned value with
      `extended.zone_id: "Etc/UTC"`.
    * **Zoned** (`TZID=Europe/Paris:20220615T100000`) → a zoned value
      carrying that IANA zone.
    * **Floating** (`20220615T100000`, no `Z` and no `TZID`) → a
      genuinely zone-less value (`extended: nil`) — the same wall
      clock in whatever zone the reader is in.

    Tempo supports `ical ~> 2.0 or ~> 3.0`. The zone-less mapping of
    floating times holds on `ical` 3.0+, which surfaces them as
    `NaiveDateTime`; on 2.x the parser coerced floating times to a
    zoned `DateTime`, so they arrive already anchored to a zone.
    Tempo maps whatever the installed parser produces — it does not
    itself invent a zone.

    """

    alias Tempo.Compare
    alias Tempo.ConversionError
    alias Tempo.Interval
    alias Tempo.IntervalSet
    alias Tempo.Math
    alias Tempo.RRule.Expander
    alias Tempo.UnboundedRecurrenceError

    # A hard ceiling on how many occurrences any single RRULE can
    # materialise. Prevents a malformed rule or a very wide bound
    # from consuming unbounded memory; 10 000 is more than a human
    # calendar would ever contain in a recurring series.
    @safety_cap 10_000

    @doc """
    Parse an iCalendar string and return a `%Tempo.IntervalSet{}`.

    Every `VEVENT` becomes one `%Tempo.Interval{}` in the result.
    All-day events (`DTSTART` as a `Date`) use day-resolution
    endpoints; datetime events use the matching datetime
    resolution. The event's `SUMMARY`, `DESCRIPTION`, `LOCATION`,
    `UID`, `STATUS`, `TRANSPARENCY`, `CATEGORIES`, attendees, and
    organizer all flow into the interval's `:metadata` map.

    The calendar-level metadata (`PRODID`, `VERSION`, `CALSCALE`,
    `METHOD`, and the user-visible name from `X-WR-CALNAME` when
    present) attaches to the IntervalSet's `:metadata` map.

    ### Arguments

    * `ics` is an iCalendar string (the contents of an `.ics`
      file).

    ### Options

    * `:bound` — a `t:Tempo.t/0`, `t:Tempo.Interval.t/0`, or
      `t:Tempo.IntervalSet.t/0` within which recurring events
      (those with an `RRULE`) are expanded. Required when any
      event in the input has a recurrence rule; ignored when
      there are none. An unbounded recurrence is infinite and
      refused at set-op time.

    ### Returns

    * `{:ok, interval_set}` — sorted, coalesced IntervalSet of
      the events.
    * `{:error, reason}` when parsing fails or a recurring event
      requires a `:bound` that wasn't supplied.

    ### Examples

        iex> ics = \"\"\"
        ...> BEGIN:VCALENDAR
        ...> VERSION:2.0
        ...> PRODID:-//Test//Test//EN
        ...> BEGIN:VEVENT
        ...> UID:test-1
        ...> DTSTAMP:20220101T000000Z
        ...> DTSTART:20220615T100000Z
        ...> DTEND:20220615T110000Z
        ...> SUMMARY:Test meeting
        ...> LOCATION:Paris
        ...> END:VEVENT
        ...> END:VCALENDAR
        ...> \"\"\"
        iex> {:ok, set} = Tempo.ICal.from_ical(ics)
        iex> Tempo.IntervalSet.count(set)
        1
        iex> [iv] = Tempo.IntervalSet.to_list(set)
        iex> Tempo.Interval.metadata(iv).summary
        "Test meeting"
        iex> Tempo.Interval.metadata(iv).location
        "Paris"

    """
    @spec from_ical(binary(), keyword()) :: {:ok, IntervalSet.t()} | {:error, term()}
    def from_ical(ics, options \\ []) when is_binary(ics) do
      calendar = ICal.from_ics(ics)
      build_interval_set(calendar, options)
    rescue
      e in [ArgumentError, MatchError, FunctionClauseError] ->
        {:error, Exception.message(e)}
    end

    @doc """
    Parse an iCalendar file and return a `%Tempo.IntervalSet{}`.

    Wraps `from_ical/2` with `File.read/1`.

    ### Arguments

    * `path` is a path to an `.ics` file.

    ### Options

    See `from_ical/2`.

    ### Returns

    * `{:ok, interval_set}` or `{:error, reason}`.

    """
    @spec from_ical_file(binary(), keyword()) ::
            {:ok, IntervalSet.t()} | {:error, term()}
    def from_ical_file(path, options \\ []) do
      with {:ok, ics} <- File.read(path) do
        from_ical(ics, options)
      end
    end

    @doc """
    Materialise the *available* time an iCalendar's `VAVAILABILITY`
    components declare, as a `%Tempo.IntervalSet{}`.

    Where `from_ical/2` reads `VEVENT`s — time that is **taken** —
    this reads [RFC 7953](https://www.rfc-editor.org/rfc/rfc7953.html)
    availability: time that is **offered**. The two are complements,
    not variants, and a scheduler usually wants both: open hours from
    here, existing claims from there.

    ### How a VAVAILABILITY is read

    A `VAVAILABILITY` covers a period — `DTSTART` to `DTEND`, either
    end optional and unbounded when absent. Inside that period the
    default is busy, and each `AVAILABLE` subcomponent carves out free
    time, repeating under its own `RRULE`, `RDATE` and `EXDATE`. An
    `AVAILABLE` is shaped exactly like a `VEVENT`, so it materialises
    through the same expander — the occurrence span, the RDATE extras
    and the EXDATE removals all behave identically.

    Outside every component's period nothing is asserted, so nothing
    is returned: absence of a statement is not a statement of absence.

    ### Priority

    Where two components overlap, `PRIORITY` decides which applies —
    1 is the highest and 9 the lowest, while 0 or absent ranks below
    all of them. The winner decides its whole period, including the
    parts where it offers nothing: a high-priority component with no
    `AVAILABLE` covering Tuesday makes Tuesday unavailable, whatever a
    lower-priority component says.

    ### Arguments

    * `ics` is iCalendar data as a string.

    * `options` is a keyword list of options.

    ### Options

    * `:within` is the query window, a `t:Tempo.Interval.t/0` or any
      value `Tempo.to_interval/2` accepts. Required: an `AVAILABLE`
      carrying an unbounded `RRULE` has no materialisation without
      one.

    ### Returns

    * `{:ok, interval_set}` of the available time; or

    * `{:error, reason}`.

    ### Examples

        iex> ics = \"\"\"
        ...> BEGIN:VCALENDAR
        ...> VERSION:2.0
        ...> BEGIN:VAVAILABILITY
        ...> UID:office-hours
        ...> DTSTAMP:20260601T000000Z
        ...> DTSTART:20260601T000000Z
        ...> DTEND:20260608T000000Z
        ...> BEGIN:AVAILABLE
        ...> UID:weekday-mornings
        ...> DTSTAMP:20260601T000000Z
        ...> DTSTART:20260601T090000Z
        ...> DTEND:20260601T120000Z
        ...> RRULE:FREQ=DAILY;COUNT=5
        ...> END:AVAILABLE
        ...> END:VAVAILABILITY
        ...> END:VCALENDAR
        ...> \"\"\"
        iex> {:ok, free} = Tempo.ICal.available_from_ical(ics, within: ~o"2026Y6M1D/8D")
        iex> Tempo.IntervalSet.count(free)
        5

    """
    @spec available_from_ical(binary(), keyword()) ::
            {:ok, IntervalSet.t()} | {:error, term()}
    def available_from_ical(ics, options \\ []) when is_binary(ics) do
      available(ICal.from_ics(ics), options)
    rescue
      e in [ArgumentError, MatchError, FunctionClauseError] ->
        {:error, Exception.message(e)}
    end

    @doc """
    The available time an already-parsed calendar declares.

    The `%ICal{}` counterpart of `available_from_ical/2`, for when the
    calendar has been parsed once and is being asked several
    questions.

    ### Arguments

    * `calendar` is an `%ICal{}` struct.

    * `options` is a keyword list of options.

    ### Options

    See `available_from_ical/2`.

    ### Returns

    * `{:ok, interval_set}` or `{:error, reason}`.

    ### Examples

        iex> calendar = Elixir.ICal.from_ics(\"\"\"
        ...> BEGIN:VCALENDAR
        ...> VERSION:2.0
        ...> BEGIN:VAVAILABILITY
        ...> UID:clinic
        ...> DTSTAMP:20260601T000000Z
        ...> BEGIN:AVAILABLE
        ...> UID:tuesday-clinic
        ...> DTSTAMP:20260601T000000Z
        ...> DTSTART:20260602T090000Z
        ...> DTEND:20260602T170000Z
        ...> END:AVAILABLE
        ...> END:VAVAILABILITY
        ...> END:VCALENDAR
        ...> \"\"\")
        iex> {:ok, free} = Tempo.ICal.available(calendar, within: ~o"2026Y6M1D/8D")
        iex> [tuesday] = Tempo.IntervalSet.to_list(free)
        iex> from = Tempo.Interval.from(tuesday)
        iex> to = Tempo.Interval.to(tuesday)
        iex> {Tempo.day(from), Tempo.hour(from), Tempo.hour(to)}
        {2, 9, 17}

    """
    @spec available(ICal.t(), keyword()) :: {:ok, IntervalSet.t()} | {:error, term()}
    def available(%ICal{} = calendar, options \\ []) do
      with {:ok, window} <- query_window(options) do
        calendar
        |> Map.get(:availabilities, [])
        |> by_descending_priority()
        |> resolve_priority(window, empty_set(), options)
      end
    end

    defp query_window(options) do
      case Keyword.fetch(options, :within) do
        {:ok, within} -> Tempo.to_interval(within)
        :error -> {:error, ":within is required — an unbounded RRULE has no materialisation"}
      end
    end

    # RFC 7953 §3.2: 1 is the highest priority and 9 the lowest, while
    # 0 — or an absent PRIORITY — is lower than all of them. Sorting
    # on the number alone would put 0 first, which is exactly backwards.
    defp by_descending_priority(availabilities) do
      Enum.sort_by(availabilities, fn availability ->
        case availability.priority do
          nil -> 10
          0 -> 10
          priority -> priority
        end
      end)
    end

    # Walk the components highest priority first, each deciding the
    # part of the window still unclaimed by a stronger one. What it
    # offers becomes available; the rest of its period is busy by
    # definition, so removing its whole scope from `undecided` is what
    # makes a higher priority actually override a lower one rather
    # than merely add to it.
    defp resolve_priority([], _undecided, free, _options), do: {:ok, free}

    defp resolve_priority([availability | rest], undecided, free, options) do
      with {:ok, scope} <- component_scope(availability, undecided),
           {:ok, offered} <- offered_within(availability, scope, options),
           {:ok, free} <- Tempo.union(free, offered),
           {:ok, undecided} <- Tempo.difference(undecided, scope) do
        resolve_priority(rest, undecided, free, options)
      end
    end

    # The period a component governs, clipped to what is still
    # undecided. An absent DTSTART or DTEND is unbounded on that side,
    # which within a query window means the window's own edge.
    defp component_scope(%ICal.Availability{} = availability, undecided) do
      case bounds(availability) do
        :unbounded -> {:ok, undecided}
        {:ok, period} -> Tempo.intersection(undecided, period)
        {:error, _} = error -> error
      end
    end

    defp bounds(%ICal.Availability{dtstart: nil, dtend: nil, duration: nil}), do: :unbounded

    defp bounds(%ICal.Availability{} = availability) do
      %ICal.Event{
        dtstart: availability.dtstart,
        dtend: availability.dtend,
        duration: availability.duration
      }
      |> single_event_to_interval()
    end

    # Every AVAILABLE subcomponent, expanded and clipped to the scope
    # this component governs.
    defp offered_within(%ICal.Availability{available: []}, _scope, _options),
      do: {:ok, empty_set()}

    defp offered_within(%ICal.Availability{available: available}, scope, options) do
      options = Keyword.put_new(options, :bound, scope)

      Enum.reduce_while(available, {:ok, empty_set()}, fn subcomponent, {:ok, acc} ->
        case expand_available(subcomponent, scope, options) do
          {:ok, offered} -> {:cont, Tempo.union(acc, offered)}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end

    # An AVAILABLE is a VEVENT in all but name — DTSTART with DTEND or
    # DURATION, optionally repeating under RRULE, RDATE and EXDATE.
    # Converting rather than reimplementing means the occurrence span,
    # the RDATE extras and the EXDATE removals cannot drift from the
    # VEVENT path, because they *are* the VEVENT path.
    defp expand_available(%ICal.Availability.Available{} = subcomponent, scope, options) do
      with {:ok, intervals} <- event_to_intervals(as_event(subcomponent), options),
           {:ok, offered} <- IntervalSet.new(intervals, coalesce: true) do
        Tempo.intersection(offered, scope)
      end
    end

    defp as_event(%ICal.Availability.Available{} = subcomponent) do
      %ICal.Event{
        uid: subcomponent.uid,
        dtstamp: subcomponent.dtstamp,
        dtstart: subcomponent.dtstart,
        dtend: subcomponent.dtend,
        duration: subcomponent.duration,
        recurrence_id: subcomponent.recurrence_id,
        rrule: subcomponent.rrule,
        rdates: subcomponent.rdates,
        exdates: subcomponent.exdates,
        summary: subcomponent.summary,
        description: subcomponent.description,
        location: subcomponent.location,
        categories: subcomponent.categories,
        comments: subcomponent.comments,
        contacts: subcomponent.contacts,
        custom_properties: subcomponent.custom_properties
      }
    end

    defp empty_set, do: IntervalSet.new!([])

    ## ------------------------------------------------------------
    ## Calendar → IntervalSet
    ## ------------------------------------------------------------

    defp build_interval_set(%ICal{events: events} = calendar, opts) do
      case convert_events(events, opts) do
        {:ok, intervals} ->
          metadata = calendar_metadata(calendar)
          # Events are preserved as distinct intervals — overlapping
          # events (e.g. an all-day travel event on top of a lunch
          # meeting) are common and each carries its own metadata.
          # Coalescing would collapse these and silently lose
          # event identity. Callers who want coalesced free/busy
          # spans can union the set with itself or call a future
          # explicit coalesce helper.
          IntervalSet.new(intervals, metadata: metadata, coalesce: false)

        {:error, _} = err ->
          err
      end
    end

    defp convert_events(events, opts) do
      Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
        case event_to_intervals(event, opts) do
          {:ok, ivs} -> {:cont, {:ok, ivs ++ acc}}
          {:error, _} = err -> {:halt, err}
        end
      end)
    end

    defp calendar_metadata(%ICal{} = cal) do
      custom = Map.get(cal, :custom_properties) || %{}
      name = custom |> Map.get("X-WR-CALNAME") |> unwrap_custom_value()

      %{
        prodid: cal.product_id,
        version: cal.version,
        scale: cal.scale,
        method: cal.method,
        name: name
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end

    # The `ical` library wraps custom property values in a struct
    # like `%{value: "X", params: %{}}`. Unwrap the inner string.
    defp unwrap_custom_value(%{value: value}) when is_binary(value), do: value
    defp unwrap_custom_value(value) when is_binary(value), do: value
    defp unwrap_custom_value(_), do: nil

    ## ------------------------------------------------------------
    ## Event → Interval(s)
    ## ------------------------------------------------------------

    defp event_to_intervals(%ICal.Event{dtstart: nil}, _opts) do
      # iCal technically requires DTSTART, but some exports
      # contain events without one. Skip silently — they can't be
      # placed on a time line.
      {:ok, []}
    end

    defp event_to_intervals(%ICal.Event{rrule: nil} = event, _opts) do
      case single_event_to_interval(event) do
        {:ok, iv} -> {:ok, [iv]}
        {:error, _} = err -> err
      end
    end

    defp event_to_intervals(%ICal.Event{rrule: rrule} = event, opts) do
      case expand_recurrence(event, rrule, opts) do
        {:ok, intervals} -> {:ok, intervals}
        {:error, _} = err -> err
      end
    end

    ## Recurrence expansion.
    ##
    ## Delegates to `Tempo.RRule.Expander.expand/3`, which is the
    ## single source of truth for RRULE materialisation. This
    ## module is only responsible for:
    ##
    ## * shaping the base event (`DTSTART`/`DTEND` → `%Interval{}`),
    ## * mapping `%ICal.Recurrence{}` fields to the Expander's
    ##   options,
    ## * carrying event metadata onto every occurrence,
    ## * deciding the "BY* rules → first-occurrence fallback"
    ##   policy while Phase B of the expander is in flight.
    ##
    ## When BY* rule support lands in the interpreter, the
    ## fallback goes away and this function becomes unconditional
    ## delegation.

    # With Phases A–D landed, every RFC 5545 recurrence primitive
    # flows through the supported path:
    #
    #   RRULE → `Tempo.RRule.Expander.expand/3` →
    #           `Tempo.to_interval/2` → `Tempo.RRule.Selection`
    #
    #   RDATE  — unioned into the RRULE occurrence set as extra
    #            `%Tempo.Interval{}` values, each carrying the
    #            event's span (`DTEND − DTSTART`) and metadata.
    #
    #   EXDATE — subtracted from the combined set by matching on
    #            the occurrence's `from` start moment.
    #
    # Phases B + C cover: BYMONTH, BYMONTHDAY, BYYEARDAY,
    # BYWEEKNO, BYDAY (with and without ordinals), BYHOUR,
    # BYMINUTE, BYSECOND, BYSETPOS.
    #
    # EXRULE is RFC-deprecated and the `ical` library does not
    # surface it, so we don't need to handle it.
    defp expand_recurrence(event, %ICal.Recurrence{} = rule, opts) do
      if rule.count == nil and rule.until == nil and not Keyword.has_key?(opts, :bound) do
        {:error,
         UnboundedRecurrenceError.exception(
           reason:
             "Event #{inspect(event.uid)} has an unbounded recurrence rule " <>
               "(no COUNT, no UNTIL). Provide a `:bound` option — a Tempo " <>
               "value within which the recurrence will be materialised."
         )}
      else
        with {:ok, base} <- single_event_to_interval(event),
             {:ok, occurrences} <- Expander.expand(rule, base.from, expander_opts(opts, base)) do
          {:ok, combine_occurrences(occurrences, event, base)}
        end
      end
    end

    defp expander_opts(opts, base) do
      []
      |> maybe_put(:bound, Keyword.get(opts, :bound))
      |> Keyword.put(:metadata, base.metadata)
      |> Keyword.put(:base_to, base.to)
    end

    defp combine_occurrences(occurrences, event, base) do
      occurrences
      |> Enum.take(@safety_cap)
      |> apply_rdates(event, base)
      |> apply_exdates(event)
      |> sort_by_from()
    end

    defp maybe_put(keyword, _key, nil), do: keyword
    defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

    ## ----------------------------------------------------------
    ## RDATE / EXDATE
    ##
    ## `final = (RRULE_expansion ∪ RDATES) − EXDATES`
    ##
    ## The `ical` library delivers RDATE / EXDATE entries as
    ## plain `Date`, `DateTime`, or `NaiveDateTime` values. We
    ## normalise to `%Tempo{}` via `Tempo.from_elixir/1` so
    ## matching and set-operations share one vocabulary.
    ##
    ## Union: each RDATE becomes an `%Tempo.Interval{}` with the
    ## event's span (same `base_to - base_from` delta used by
    ## RRULE occurrences). Event metadata rides along so
    ## downstream operations keep the tie back to the source
    ## event.
    ##
    ## Subtract: EXDATE matches an occurrence when the
    ## occurrence's `from` moment equals the EXDATE. We compare
    ## via `Tempo.Compare.compare_endpoints/2` so time-zone
    ## equality and cross-resolution comparison fall out
    ## naturally.
    ## ----------------------------------------------------------

    defp apply_rdates(occurrences, %ICal.Event{rdates: nil}, _base), do: occurrences
    defp apply_rdates(occurrences, %ICal.Event{rdates: []}, _base), do: occurrences

    defp apply_rdates(occurrences, %ICal.Event{rdates: rdates}, %Interval{} = base) do
      extras =
        rdates
        |> Enum.map(&rdate_to_interval(&1, base))
        |> Enum.reject(&is_nil/1)

      occurrences ++ extras
    end

    # Turn one RDATE value into a full `%Tempo.Interval{}`. The
    # event's span (`base.to - base.from`) is preserved — an
    # RDATE adds a matching-duration occurrence at a new start.
    defp rdate_to_interval(%DateTime{} = dt, %Interval{} = base) do
      rdate_tempo(Tempo.from_elixir(dt), base)
    end

    defp rdate_to_interval(%NaiveDateTime{} = ndt, %Interval{} = base) do
      rdate_tempo(Tempo.from_elixir(ndt), base)
    end

    defp rdate_to_interval(%Date{} = d, %Interval{} = base) do
      rdate_tempo(Tempo.from_elixir(d, resolution: :day), base)
    end

    defp rdate_to_interval(_other, _base), do: nil

    # The RDATE's start is its full timestamp (date + time-of-day
    # if present). The end is `start + event_duration`, where the
    # event's duration is derived from the base occurrence in
    # UTC seconds via `Tempo.Compare.to_utc_seconds/1`. That
    # gives us a calendar-neutral delta that `Tempo.Math.add/2`
    # can apply to the RDATE start.
    defp rdate_tempo(%Tempo{} = from_tempo, %Interval{
           from: base_from,
           to: base_to,
           metadata: metadata
         }) do
      duration = event_duration(base_from, base_to)
      to_tempo = Math.add(from_tempo, duration)
      %Interval{from: from_tempo, to: to_tempo, metadata: metadata}
    end

    defp event_duration(%Tempo{} = from, %Tempo{} = to) do
      seconds = Compare.to_utc_seconds(to) - Compare.to_utc_seconds(from)
      %Tempo.Duration{time: [second: seconds]}
    end

    defp apply_exdates(occurrences, %ICal.Event{exdates: nil}), do: occurrences
    defp apply_exdates(occurrences, %ICal.Event{exdates: []}), do: occurrences

    defp apply_exdates(occurrences, %ICal.Event{exdates: exdates}) do
      excluded =
        exdates
        |> Enum.map(&exdate_to_tempo/1)
        |> Enum.reject(&is_nil/1)

      Enum.reject(occurrences, fn %Interval{from: from} ->
        Enum.any?(excluded, fn ex -> same_moment?(from, ex) end)
      end)
    end

    defp exdate_to_tempo(%DateTime{} = dt), do: Tempo.from_elixir(dt)
    defp exdate_to_tempo(%NaiveDateTime{} = ndt), do: Tempo.from_elixir(ndt)
    defp exdate_to_tempo(%Date{} = d), do: Tempo.from_elixir(d, resolution: :day)
    defp exdate_to_tempo(_other), do: nil

    defp same_moment?(%Tempo{} = a, %Tempo{} = b) do
      Compare.compare_endpoints(a, b) == :same
    end

    ## Sort the combined set so consumers see chronological order
    ## regardless of whether an RDATE landed after the RRULE run.
    defp sort_by_from(intervals) do
      Enum.sort_by(intervals, fn %Interval{from: %Tempo{time: time}} -> time_sort_key(time) end)
    end

    # Stable key for chronological sort — year, month, day, hour,
    # minute, second, with missing units defaulting to their unit
    # minimum so partial-resolution values sort alongside fully
    # specified ones.
    defp time_sort_key(time) do
      {
        Keyword.get(time, :year, 0),
        Keyword.get(time, :month, 1),
        Keyword.get(time, :day, 1),
        Keyword.get(time, :hour, 0),
        Keyword.get(time, :minute, 0),
        Keyword.get(time, :second, 0)
      }
    end

    # NOTE: `first_occurrence_only/2` was retired when Phase C
    # landed. Every RFC 5545 BY-rule now materialises through the
    # supported path, so no event emits only its first occurrence
    # with `metadata.recurrence_reason == :by_rules_not_supported`.
    # Restore it (git log) if a future RFC addition needs a
    # "visible but not fully materialised" fallback.

    defp single_event_to_interval(%ICal.Event{} = event) do
      with {:ok, from} <- dtstart_to_tempo(event.dtstart),
           {:ok, to} <- dtend_to_tempo(event, from) do
        {from, to, metadata} = ensure_non_degenerate(from, to, event_metadata(event))
        {:ok, %Interval{from: from, to: to, metadata: metadata}}
      end
    end

    # RFC 5545 §3.6.1 lets a timed event carry zero duration (a point) —
    # an instant-model artefact. Tempo's interval domain excludes
    # zero-extent intervals (Grüninger & Li's `T_bounded_meeting`: an
    # interval is never returned with zero extent), and building one via
    # the `%Interval{}` struct would smuggle a value past
    # `Tempo.Interval.new/1`'s guard and into set operations. A punctual
    # event is therefore materialised as the one-unit implicit span of
    # its start — the smallest span containing the instant — and tagged
    # `punctual: true` so the instantaneous origin is not lost. This
    # covers both the no-DTEND case and an explicit `DTEND == DTSTART`.
    defp ensure_non_degenerate(from, to, metadata) do
      case Compare.compare_endpoints(from, to) do
        :same ->
          {unit, _span} = Tempo.resolution(from)
          # `from` is a parsed DTSTART — a concrete date or date-time.
          {:ok, widened} = Math.add_unit(from, unit, from.calendar)
          {from, widened, Map.put(metadata, :punctual, true)}

        _earlier_or_later ->
          {from, to, metadata}
      end
    end

    # All-day event: DTSTART is a Date. Convert to a
    # day-resolution Tempo; DTEND is typically the day after
    # (iCal all-day semantics are half-open).
    defp dtstart_to_tempo(%Date{} = date) do
      {:ok, Tempo.from_elixir(date, resolution: :day)}
    end

    defp dtstart_to_tempo(%DateTime{} = dt) do
      {:ok, Tempo.from_elixir(dt)}
    end

    defp dtstart_to_tempo(%NaiveDateTime{} = ndt) do
      {:ok, Tempo.from_elixir(ndt)}
    end

    defp dtstart_to_tempo(other) do
      {:error,
       ConversionError.exception(
         value: other,
         target: Tempo,
         reason: "Unsupported DTSTART type: #{inspect(other)}"
       )}
    end

    defp dtend_to_tempo(%ICal.Event{dtstart: %Date{}, dtend: nil, duration: nil}, from) do
      # All-day event (DATE-valued DTSTART) with neither DTEND nor
      # DURATION. RFC 5545 §3.6.1: the event's duration is taken to
      # be one day. Advance the `from` by one unit at its own
      # resolution, which keeps the endpoint at day resolution so the
      # half-open span is exactly `[from, from + 1 day)`.
      {unit, _span} = Tempo.resolution(from)
      # `from` is a parsed DTSTART — a concrete date or date-time.
      Math.add_unit(from, unit, from.calendar)
    end

    defp dtend_to_tempo(%ICal.Event{dtend: nil, duration: nil}, from) do
      # Timed event (DATE-TIME DTSTART) with neither DTEND nor
      # DURATION. RFC 5545 §3.6.1: the event ends on the same date and
      # time of day as DTSTART — a zero-duration point (`to == from`).
      # `ensure_non_degenerate/3` then widens this punctual value to the
      # one-unit span the interval domain requires.
      {:ok, from}
    end

    defp dtend_to_tempo(%ICal.Event{dtend: nil, duration: %ICal.Duration{} = duration}, from) do
      # A component stating DURATION instead of DTEND ends that far
      # after its start. RFC 7953 lists DURATION as the alternative on
      # both VAVAILABILITY and AVAILABLE, so availability needs this
      # as much as events do.
      case duration_units(duration) do
        [] -> {:ok, from}
        units -> {:ok, Tempo.shift(from, units)}
      end
    end

    defp dtend_to_tempo(%ICal.Event{dtend: %Date{} = date}, _from) do
      {:ok, Tempo.from_elixir(date, resolution: :day)}
    end

    defp dtend_to_tempo(%ICal.Event{dtend: %DateTime{} = dt}, _from) do
      {:ok, Tempo.from_elixir(dt)}
    end

    defp dtend_to_tempo(%ICal.Event{dtend: %NaiveDateTime{} = ndt}, _from) do
      {:ok, Tempo.from_elixir(ndt)}
    end

    defp dtend_to_tempo(%ICal.Event{dtend: other}, _from) do
      {:error,
       ConversionError.exception(
         value: other,
         target: Tempo,
         reason: "Unsupported DTEND type: #{inspect(other)}"
       )}
    end

    # RFC 5545 §3.3.6 spells a duration as weeks, days and an
    # hour/minute/second triple, carrying its own sign. Tempo shifts by
    # units, so the struct maps straight across; zero components are
    # dropped so a shift is only asked for what actually moves.
    defp duration_units(
           %ICal.Duration{positive: positive, time: {hours, minutes, seconds}} = duration
         ) do
      sign = if positive, do: 1, else: -1

      [
        week: duration.weeks,
        day: duration.days,
        hour: hours,
        minute: minutes,
        second: seconds
      ]
      |> Enum.reject(fn {_unit, amount} -> amount == 0 end)
      |> Enum.map(fn {unit, amount} -> {unit, sign * amount} end)
    end

    # Lift the iCalendar properties users most often care about.
    # Everything absent from the event is dropped (kept the
    # metadata map compact). X-* custom properties go into
    # `:custom` for later access.
    defp event_metadata(%ICal.Event{} = event) do
      base = %{
        uid: event.uid,
        summary: event.summary,
        description: event.description,
        location: event.location,
        status: event.status,
        transparency: event.transparency,
        categories: event.categories,
        url: event.url,
        classification: event.class,
        priority: event.priority,
        organizer: stringify_organizer(event.organizer),
        attendees: stringify_attendees(event.attendees),
        custom: event.custom_properties
      }

      base
      |> Enum.reject(fn
        {_k, nil} -> true
        {_k, []} -> true
        {_k, %{} = map} when map_size(map) == 0 -> true
        _ -> false
      end)
      |> Map.new()
    end

    defp stringify_organizer(nil), do: nil

    defp stringify_organizer(%{__struct__: _, cname: cname}) when is_binary(cname),
      do: cname

    defp stringify_organizer(other), do: inspect(other)

    defp stringify_attendees([]), do: []

    defp stringify_attendees(attendees) when is_list(attendees) do
      Enum.map(attendees, fn
        %{cname: cname} when is_binary(cname) -> cname
        other -> inspect(other)
      end)
    end
  end
end
