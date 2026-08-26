if Code.ensure_loaded?(JSCalendar) do
  defmodule Tempo.JSCalendar do
    @moduledoc """
    Import JSCalendar ([RFC 8984](https://www.rfc-editor.org/rfc/rfc8984.html))
    data into `%Tempo.IntervalSet{}`.

    This module wraps the [`jscalendar`](https://github.com/elixir-tempo/jscalendar)
    parser and places its events on a timeline. Where that library
    turns documents into structs, this one turns structs into time:
    resolving a wall-clock `start` against its zone, deriving the end
    from the duration, and expanding recurrence rules.

    JSCalendar is the IETF's intended successor to iCalendar, so this
    is the counterpart of `Tempo.ICal` — same destination, newer
    format. Event metadata (`uid`, `title`, `description`, `status`,
    …) rides on each interval's `:metadata` map, so downstream set
    operations stay connected to their source.

    The `jscalendar` dependency is declared `optional: true` in
    `mix.exs`. This module is only compiled when it is available.

    ## Start, duration, and the zone

    An RFC 8984 event stores a *wall-clock* `start` and a separate
    `timeZone`, not an instant. That is the whole point: an hour-long
    meeting stays an hour long across a daylight-saving boundary,
    where a stored end time would silently become two hours or none.
    So the end here is always `start + duration` resolved in the
    event's own zone.

    An event with no `timeZone` is *floating* — the same wall clock
    wherever it is read — and materialises as a zone-less `%Tempo{}`
    rather than being anchored to the reader's zone.

    ## Where a local time is ambiguous

    RFC 8984 does not say which instant to pick when a wall-clock time
    falls in a daylight-saving fold or gap, so this module chooses and
    says so:

    * **Ambiguous** — the clock repeats an hour — takes the *earlier*
      instant, the first time that reading occurs.

    * **A gap** — the clock skips an hour, so the time never happens —
      takes the instant the gap ends, which is the first moment at or
      after the nominal time.

    Both are the readings a person means by "half past two that
    morning". Neither is an error, because a calendar full of such
    events is ordinary and refusing to read them would be worse.

    ## Overrides

    RFC 8984 §4.3 builds a recurrence set in three steps: the rules
    generate, the excluded rules remove, and `recurrenceOverrides`
    adds, removes and varies. All three happen here, so a document
    that cancels one week and moves another materialises what it
    says rather than its unmodified series.

    An override is keyed by *recurrence id* — the wall-clock moment
    the rules produced — which is not necessarily where the
    occurrence ends up, since a patch may move its `start`. Each key
    is therefore resolved in the event's own zone and matched by
    instant, the same way `excludedRecurrenceRules` is. A key that
    matches nothing is an additional occurrence, iCalendar's `RDATE`
    by another name, and an event may consist of nothing else: with
    overrides and no rules it still recurs.

    A patched occurrence carries its own metadata, so a renamed week
    arrives with the new title on its interval.

    ## What is not expanded

    `localizations` are parsed but not applied. A localisation is a
    choice about which language to render, and nothing in an interval
    set expresses that — the patches are on the object for a caller
    who knows which locale they want.

    """

    alias JSCalendar.Event
    alias JSCalendar.Group
    alias JSCalendar.NDay
    alias JSCalendar.Occurrence
    alias JSCalendar.RecurrenceRule
    alias JSCalendar.Task
    alias Tempo.Compare
    alias Tempo.Interval
    alias Tempo.IntervalSet
    alias Tempo.Math
    alias Tempo.RRule.Expander
    alias Tempo.RRule.Rule

    @doc """
    Parse a JSCalendar document and return a `%Tempo.IntervalSet{}`.

    Every `Event` becomes one or more intervals — one per occurrence
    when it recurs. A `Group` contributes its member events. A `Task`
    contributes nothing: a task is work to be done, not time occupied,
    and placing one on a timeline would say something the document
    does not.

    ### Arguments

    * `json` is a JSCalendar document as a string.

    ### Options

    * `:bound` is a Tempo value within which recurring events are
      expanded. Required when any event has a recurrence rule with
      neither `count` nor `until`; ignored when there are none.

    ### Returns

    * `{:ok, interval_set}`; or

    * `{:error, reason}` when the document cannot be parsed, a zone is
      unknown, or a recurrence needs a `:bound` that was not supplied.

    ### Examples

        iex> json = ~s({
        ...>   "@type": "Event",
        ...>   "uid": "review",
        ...>   "updated": "2026-06-01T09:00:00Z",
        ...>   "title": "Quarterly review",
        ...>   "start": "2026-06-02T09:00:00",
        ...>   "duration": "PT1H"
        ...> })
        iex> {:ok, set} = Tempo.JSCalendar.from_jscalendar(json)
        iex> [interval] = Tempo.IntervalSet.to_list(set)
        iex> Tempo.to_iso8601(interval)
        "2026Y6M2DT9H0M0S/2026Y6M2DT10H0M0S"
        iex> Tempo.Interval.metadata(interval).title
        "Quarterly review"

    """
    @spec from_jscalendar(binary(), keyword()) :: {:ok, IntervalSet.t()} | {:error, term()}
    def from_jscalendar(json, options \\ []) when is_binary(json) do
      with {:ok, object} <- JSCalendar.decode(json) do
        to_interval_set(object, options)
      end
    end

    @doc """
    Place an already-parsed JSCalendar object on a timeline.

    The struct counterpart of `from_jscalendar/2`, for when the
    document has been decoded once already — as part of a JMAP
    response, say.

    ### Arguments

    * `object` is a `t:JSCalendar.Event.t/0`,
      `t:JSCalendar.Task.t/0` or `t:JSCalendar.Group.t/0`.

    ### Options

    See `from_jscalendar/2`.

    ### Returns

    * `{:ok, interval_set}` or `{:error, reason}`.

    ### Examples

        iex> event = %JSCalendar.Event{
        ...>   uid: "e",
        ...>   start: ~N[2026-06-02 09:00:00],
        ...>   duration: %Duration{hour: 1}
        ...> }
        iex> {:ok, set} = Tempo.JSCalendar.to_interval_set(event)
        iex> Tempo.IntervalSet.count(set)
        1

    """
    @spec to_interval_set(struct(), keyword()) :: {:ok, IntervalSet.t()} | {:error, term()}
    def to_interval_set(object, options \\ [])

    def to_interval_set(%Event{} = event, options) do
      with {:ok, intervals} <- occurrences(event, options) do
        IntervalSet.new(intervals, coalesce: false)
      end
    end

    # A task is work, not time occupied. Placing one on a timeline
    # would assert something the document does not say.
    def to_interval_set(%Task{}, _options), do: IntervalSet.new([])

    def to_interval_set(%Group{entries: entries}, options) do
      entries
      |> List.wrap()
      |> Enum.filter(&is_struct(&1, Event))
      |> Enum.reduce_while({:ok, []}, fn event, {:ok, acc} ->
        case occurrences(event, options) do
          {:ok, intervals} -> {:cont, {:ok, acc ++ intervals}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, intervals} -> IntervalSet.new(intervals, coalesce: false)
        {:error, _reason} = error -> error
      end
    end

    def to_interval_set(other, _options), do: {:error, {:not_a_calendar_object, other}}

    ## ------------------------------------------------------------
    ## Event → Interval(s)
    ## ------------------------------------------------------------

    # An event with no start cannot be placed. RFC 8984 makes `start`
    # mandatory, but a document that omits it is skipped rather than
    # failing the whole calendar — one malformed event should not cost
    # the reader the other four hundred.
    defp occurrences(%Event{start: nil}, _options), do: {:ok, []}

    defp occurrences(%Event{} = event, options) do
      with {:ok, from} <- at_zone(event.start, event.time_zone),
           {:ok, base} <- span(event, from) do
        expand(event, base, options)
      end
    end

    # The end is `start + duration` in the event's own zone, which is
    # why the duration is applied to the wall clock rather than to an
    # instant. `Tempo.shift/2` does that arithmetic calendar-aware.
    defp span(%Event{} = event, from) do
      to = event |> Event.duration() |> units() |> shift(from)
      {from, to, metadata} = ensure_non_degenerate(from, to, metadata(event))

      Interval.new(from: from, to: to, metadata: metadata)
    end

    defp shift([] = _no_units, from), do: from
    defp shift(units, from), do: Tempo.shift(from, units)

    # RFC 8984 §5.1.2 gives `duration` a default of `PT0S`, so an event
    # with none is an instant. Tempo's interval domain excludes
    # zero-extent intervals, so a punctual event materialises as the
    # one-unit implicit span of its start — the smallest span
    # containing the instant — tagged so the instantaneous origin is
    # not lost. `Tempo.ICal` treats a zero-duration VEVENT the same
    # way; the two formats should not disagree about what a moment is.
    defp ensure_non_degenerate(from, to, metadata) do
      case Compare.compare_endpoints(from, to) do
        :same ->
          {unit, _span} = Tempo.resolution(from)

          {from, Math.add_unit(from, unit, from.calendar), Map.put(metadata, :punctual, true)}

        _earlier_or_later ->
          {from, to, metadata}
      end
    end

    # RFC 8984 §4.3 builds the recurrence set in three steps, in this
    # order: the rules generate, the excluded rules remove, and the
    # overrides add, remove and vary. An event with no rules but with
    # overrides is still recurring — every occurrence is an additional
    # one — so the rule-free clauses stop at the overrides rather than
    # at the base.
    defp expand(%Event{recurrence_rules: rules} = event, base, options)
         when rules in [nil, []] do
      override(event, [base], options)
    end

    defp expand(%Event{} = event, base, options) do
      with {:ok, included} <- materialise(event.recurrence_rules, base, event, options),
           {:ok, excluded} <-
             materialise(event.excluded_recurrence_rules || [], base, event, options) do
        override(event, without(included, excluded), options)
      end
    end

    defp materialise(rules, %Interval{} = base, event, options) do
      expander_options =
        options
        |> Keyword.take([:bound])
        |> Keyword.put(:metadata, metadata(event))
        |> Keyword.put(:duration, occurrence_duration(base))

      rules
      |> Enum.reduce_while({:ok, []}, fn rule, {:ok, acc} ->
        with {:ok, converted} <- to_rule(rule),
             {:ok, occurrences} <- Expander.expand(converted, base.from, expander_options) do
          {:cont, {:ok, acc ++ occurrences}}
        else
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end

    # Each occurrence spans as long as the first one does.
    defp occurrence_duration(%Interval{from: from, to: to}) do
      seconds = Compare.to_utc_seconds(to) - Compare.to_utc_seconds(from)

      %Tempo.Duration{time: [second: seconds]}
    end

    ## recurrenceOverrides
    ## ------------------------------------------------------------

    # An override is keyed by *recurrence id* — the wall-clock moment
    # the rules produced — not by the moment the occurrence ends up at,
    # which a patched `start` is free to move. So each key is resolved
    # in the event's own zone and matched against the generated set by
    # endpoint comparison, the same way `excludedRecurrenceRules` is:
    # comparing `%Tempo{}` structs for equality would make a match
    # depend on how a value happens to be written.
    #
    # A key that matches nothing is an additional occurrence — RDATE by
    # another name — and the patch for one of those is often empty.
    defp override(%Event{} = event, occurrences, options) do
      case Occurrence.overridden(event) do
        [] ->
          {:ok, occurrences}

        ids ->
          with({:ok, keyed} <- resolve(ids, event), do: merge(keyed, event, occurrences, options))
      end
    end

    defp merge(keyed, %Event{} = event, occurrences, options) do
      varied = Enum.map(occurrences, &vary(&1, keyed, event, options))
      matched = Enum.flat_map(varied, fn {_interval, id} -> List.wrap(id) end)

      added =
        keyed
        |> Enum.reject(fn {id, _from} -> id in matched end)
        |> Enum.map(fn {id, _from} -> {occurrence(event, id, options), id} end)

      collect(varied ++ added)
    end

    defp resolve(ids, %Event{} = event) do
      ids
      |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
        case at_zone(id, event.time_zone) do
          {:ok, from} -> {:cont, {:ok, [{id, from} | acc]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, keyed} -> {:ok, Enum.reverse(keyed)}
        {:error, _reason} = error -> error
      end
    end

    # `:keep` rather than the interval itself, so a generated occurrence
    # that no override touches is not rebuilt — the expander already
    # produced it, and rebuilding would discard whatever it knows.
    defp vary(%Interval{from: from} = interval, keyed, event, options) do
      case Enum.find(keyed, fn {_id, moment} ->
             Compare.compare_endpoints(moment, from) == :same
           end) do
        nil -> {{:ok, interval}, nil}
        {id, _moment} -> {occurrence(event, id, options), id}
      end
    end

    # `Occurrence.at/2` strips the recurrence machinery, so the patched
    # object is a single event and this cannot recurse.
    defp occurrence(%Event{} = event, id, options) do
      case Occurrence.at(event, id) do
        {:ok, occurrence} ->
          case occurrences(occurrence, options) do
            {:ok, [interval]} -> {:ok, interval}
            {:ok, []} -> :excluded
            {:error, _reason} = error -> error
          end

        :excluded ->
          :excluded

        {:error, _reason} = error ->
          error
      end
    end

    defp collect(results) do
      results
      |> Enum.reduce_while({:ok, []}, fn
        {:excluded, _id}, {:ok, acc} -> {:cont, {:ok, acc}}
        {{:ok, interval}, _id}, {:ok, acc} -> {:cont, {:ok, [interval | acc]}}
        {{:error, _reason} = error, _id}, {:ok, _acc} -> {:halt, error}
      end)
      |> case do
        {:ok, intervals} ->
          {:ok, Enum.sort_by(intervals, &Compare.to_utc_seconds(&1.from))}

        {:error, _reason} = error ->
          error
      end
    end

    # `excludedRecurrenceRules` removes occurrences by start moment,
    # exactly as EXDATE does for iCalendar.
    defp without(included, []), do: included

    defp without(included, excluded) do
      starts = MapSet.new(excluded, & &1.from)

      Enum.reject(included, fn %Interval{from: from} ->
        Enum.any?(starts, &(Compare.compare_endpoints(&1, from) == :same))
      end)
    end

    ## ------------------------------------------------------------
    ## Wall clock → instant
    ## ------------------------------------------------------------

    defp at_zone(%NaiveDateTime{} = naive, nil), do: {:ok, Tempo.from_elixir(naive)}

    defp at_zone(%NaiveDateTime{} = naive, zone) when is_binary(zone) do
      case DateTime.from_naive(naive, zone) do
        {:ok, datetime} -> {:ok, Tempo.from_elixir(datetime)}
        {:ambiguous, earlier, _later} -> {:ok, Tempo.from_elixir(earlier)}
        {:gap, _before, after_gap} -> {:ok, Tempo.from_elixir(after_gap)}
        {:error, reason} -> {:error, {:invalid_time_zone, zone, reason}}
      end
    end

    ## ------------------------------------------------------------
    ## RecurrenceRule → Rule
    ## ------------------------------------------------------------

    defp to_rule(%RecurrenceRule{} = rule) do
      with {:ok, freq} <- frequency(rule.frequency),
           {:ok, months} <- months(rule.by_month) do
        {:ok,
         %Rule{
           freq: freq,
           interval: rule.interval || 1,
           count: rule.count,
           until: rule.until && Tempo.from_elixir(rule.until),
           wkst: weekday(rule.first_day_of_week) || 1,
           bymonth: months,
           bymonthday: rule.by_month_day,
           byyearday: rule.by_year_day,
           byweekno: rule.by_week_no,
           byday: byday(rule.by_day),
           byhour: rule.by_hour,
           byminute: rule.by_minute,
           bysecond: rule.by_second,
           bysetpos: rule.by_set_position
         }}
      end
    end

    defp frequency("yearly"), do: {:ok, :year}
    defp frequency("monthly"), do: {:ok, :month}
    defp frequency("weekly"), do: {:ok, :week}
    defp frequency("daily"), do: {:ok, :day}
    defp frequency("hourly"), do: {:ok, :hour}
    defp frequency("minutely"), do: {:ok, :minute}
    defp frequency("secondly"), do: {:ok, :second}
    defp frequency(other), do: {:error, {:unsupported_frequency, other}}

    defp weekday("mo"), do: 1
    defp weekday("tu"), do: 2
    defp weekday("we"), do: 3
    defp weekday("th"), do: 4
    defp weekday("fr"), do: 5
    defp weekday("sa"), do: 6
    defp weekday("su"), do: 7
    defp weekday(_other), do: nil

    defp byday(nil), do: nil
    defp byday([]), do: nil

    defp byday(days) when is_list(days) do
      Enum.map(days, fn %NDay{} = day ->
        {day.nth_of_period, weekday(day.day) || 1}
      end)
    end

    # RFC 8984 writes months as strings so that a lunisolar leap month
    # can be `"3L"`. Tempo's rule takes ordinals, and there is no
    # honest ordinal for a leap month, so that is reported rather than
    # rounded to the month it is not.
    defp months(nil), do: {:ok, nil}

    defp months(values) when is_list(values) do
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
        case Integer.parse(value) do
          {number, ""} -> {:cont, {:ok, acc ++ [number]}}
          _leap_or_junk -> {:halt, {:error, {:unsupported_month, value}}}
        end
      end)
    end

    ## ------------------------------------------------------------
    ## Support
    ## ------------------------------------------------------------

    # Elixir's `Duration` carries microseconds as a `{value, precision}`
    # pair, which has no unit in a Tempo shift, so sub-second precision
    # is dropped here. Calendar durations are not measured that finely.
    defp units(%Duration{} = duration) do
      [
        year: duration.year,
        month: duration.month,
        week: duration.week,
        day: duration.day,
        hour: duration.hour,
        minute: duration.minute,
        second: duration.second
      ]
      |> Enum.reject(fn {_unit, amount} -> amount == 0 end)
    end

    defp metadata(%Event{} = event) do
      %{
        uid: event.uid,
        title: event.title,
        description: event.description,
        status: event.status,
        free_busy_status: event.free_busy_status,
        privacy: event.privacy,
        time_zone: event.time_zone,
        sequence: event.sequence
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Map.new()
    end
  end
end
