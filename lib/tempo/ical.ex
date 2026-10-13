if Code.ensure_loaded?(ICal) do
  defmodule Tempo.ICal do
    @moduledoc """
    Reads iCalendar (RFC 5545) data into Tempo: each `VEVENT` an interval
    carrying the event's summary, location and the rest as metadata, each
    recurring event its occurrences, and RFC 7953 `VAVAILABILITY` components
    the time they offer.

    The text is parsed by the optional [`ical`](https://hex.pm/packages/ical)
    dependency, and this module is compiled only when it is present. An
    event's `RRULE` is lowered to a Tempo recurrence by `Tempo.RRule`, so its
    occurrences are those any Tempo recurrence gives; `RDATE` adds
    occurrences of the event's own length and `EXDATE` removes the one that
    starts at it. An all-day event (`DTSTART` a `DATE`) is a span of days,
    written to its last day; `BYHOUR`, `BYMINUTE` and `BYSECOND` are ignored
    on one, as RFC 5545 §3.3.10 has it.

    Events say what is taken and availability what is offered, and the two
    compose:

        {:ok, free} = Tempo.ICal.available(ics, within: week)
        {:ok, busy} = Tempo.ICal.parse(ics, within: week)
        {:ok, bookable} = Tempo.difference(free, busy)

    """

    alias Tempo.{
      Algebra,
      ConversionError,
      Duration,
      Interval,
      IntervalSet,
      Occurrences,
      Options,
      Spans
    }

    @frequencies %{
      secondly: :second,
      minutely: :minute,
      hourly: :hour,
      daily: :day,
      weekly: :week,
      monthly: :month,
      yearly: :year
    }
    @weekdays %{
      monday: 1,
      tuesday: 2,
      wednesday: 3,
      thursday: 4,
      friday: 5,
      saturday: 6,
      sunday: 7
    }

    @doc """
    Reads iCalendar text into a set of intervals, one for each event or
    occurrence of an event, in order of start.

    ### Arguments

    * `ics` is iCalendar text.

    * `options` is a keyword list of options.

    ### Options

    * `:within` is a `t:Tempo.t/0`, the window whose events are wanted:
      every occurrence that overlaps it is kept. It is required when an
      event repeats with neither `COUNT` nor `UNTIL`.

    ### Returns

    * `{:ok, set}`, a `t:Tempo.t/0` of the `:all` form, its metadata the
      calendar's (`:prodid`, `:version`, `:scale`, `:method`, `:name`) and
      each member's its event's (`:uid`, `:summary`, `:description`,
      `:location`, `:status`, and so on).

    * `{:error, exception}` when a recurring event has no end and no window
      is given, or a value cannot be read.

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
        iex> {:ok, events} = Tempo.ICal.parse(ics)
        iex> [meeting] = Tempo.IntervalSet.members(events)
        iex> {Tempo.metadata(meeting).summary, Tempo.duration(meeting)}
        {"Test meeting", ~o"PT3600S"}

    """
    @spec parse(binary(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
    def parse(ics, options \\ []) when is_binary(ics), do: from_ical(ICal.from_ics(ics), options)

    @doc """
    Reads an iCalendar file as `parse/2` reads text.

    ### Arguments

    * `path` is the path of an `.ics` file.

    * `options` is a keyword list of options.

    ### Options

    * `:within` is as for `parse/2`.

    ### Returns

    * `{:ok, set}`, or `{:error, exception}`, a `File.Error` when the file
      cannot be read.

    """
    @spec parse_file(Path.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
    def parse_file(path, options \\ []) do
      case File.read(path) do
        {:ok, ics} ->
          parse(ics, options)

        {:error, reason} ->
          {:error, File.Error.exception(reason: reason, action: "read file", path: path)}
      end
    end

    @doc """
    The events of a calendar the `ical` library has already parsed, as
    `parse/2` gives them.

    ### Arguments

    * `calendar` is an `%ICal{}`.

    * `options` is a keyword list of options.

    ### Options

    * `:within` is as for `parse/2`.

    ### Returns

    * `{:ok, set}` or `{:error, exception}`, as for `parse/2`.

    """
    @spec from_ical(ICal.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
    def from_ical(%ICal{events: events} = calendar, options \\ []) do
      with :ok <- Options.check(options, [:within], "Tempo.ICal.parse/2"),
           {:ok, spans} <- each_event(events, options),
           {:ok, kept} <- Occurrences.within(spans, options[:within]) do
        Algebra.gathered(kept,
          metadata: calendar_metadata(calendar),
          floating: :place,
          sorted: true
        )
      end
    end

    @doc """
    The time an iCalendar's `VAVAILABILITY` components offer (RFC 7953).

    Each component covers a period, `DTSTART` to `DTEND`, and within it each
    `AVAILABLE` subcomponent offers time, repeating under its own `RRULE`.
    Where components overlap the one of higher `PRIORITY` (1 the highest,
    0 or none the lowest) decides its whole period.

    ### Arguments

    * `ics` is iCalendar text or an `%ICal{}`.

    * `options` is a keyword list of options.

    ### Options

    * `:within` is a `t:Tempo.t/0`, the window the time offered is taken in.
      It is required.

    ### Returns

    * `{:ok, set}` of the time offered within the window, merged.

    * `{:error, exception}` with no window, or as for `parse/2`.

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
        iex> {:ok, free} = Tempo.ICal.available(ics, within: ~o"2026-06-01T00Z/2026-06-08T00Z")
        iex> Tempo.IntervalSet.count(free)
        5

    """
    @spec available(binary() | ICal.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
    def available(ics, options \\ [])
    def available(ics, options) when is_binary(ics), do: available(ICal.from_ics(ics), options)

    def available(%ICal{availabilities: availabilities}, options) do
      with :ok <- Options.check(options, [:within], "Tempo.ICal.available/2"),
           do: available_in(availabilities, options[:within], options)
    end

    defp available_in(availabilities, %Tempo{} = window, options),
      do: offered(Enum.sort_by(availabilities, &rank/1), window, options)

    defp available_in(_availabilities, _no_window, _options),
      do: {:error, ConversionError.exception(value: :availability, reason: :unbounded)}

    # 1 is the highest priority and 9 the lowest; 0 or none ranks below all.
    defp rank(%{priority: priority}) when priority in 1..9, do: priority
    defp rank(_availability), do: 10

    # Each component in order of rank offers within what no higher one covers.
    defp offered(availabilities, window, options) do
      empty = %Tempo{form: {:all, []}, calendar: window.calendar}

      availabilities
      |> Enum.reduce_while({:ok, empty, window}, fn availability, {:ok, free, undecided} ->
        case offered_by(availability, window, free, undecided, options) do
          {:ok, free, undecided} -> {:cont, {:ok, free, undecided}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, free, _undecided} -> IntervalSet.coalesce(free)
        error -> error
      end
    end

    defp offered_by(availability, window, free, undecided, options) do
      with {:ok, period} <- period(availability, window),
           {:ok, scope} <- Tempo.intersection(period, undecided),
           {:ok, slots} <- available_spans(availability, options),
           {:ok, offered} <- Tempo.intersection(set(slots, %{}), scope),
           {:ok, free} <- Tempo.union(free, offered),
           {:ok, undecided} <- Tempo.difference(undecided, period) do
        {:ok, free, undecided}
      end
    end

    defp period(%{dtstart: nil, dtend: nil}, window), do: {:ok, window}

    defp period(%{dtstart: dtstart, dtend: dtend}, window) do
      with {:ok, from} <- bound(dtstart),
           {:ok, to} <- bound(dtend) do
        Interval.new(from: from || :open, to: to || :open)
        |> clipped(window)
      end
    end

    defp bound(nil), do: {:ok, nil}
    defp bound(value), do: Tempo.from_elixir(value)

    defp clipped({:ok, period}, window),
      do: Tempo.intersection(window, bounded_in(period, window))

    defp clipped(error, _window), do: error

    # An open end of a period is the window's.
    defp bounded_in(%Tempo{form: {:span, from, to}} = period, %Tempo{} = window) do
      {:ok, [%Tempo{form: {:span, window_from, window_to}}]} = Spans.spans(window)

      %{
        period
        | form:
            {:span, if(from == :open, do: window_from, else: from),
             if(to == :open, do: window_to, else: to)}
      }
    end

    defp available_spans(%{available: available}, options) do
      available |> Enum.map(&as_event/1) |> each_event(options)
    end

    defp as_event(subcomponent) do
      struct(
        ICal.Event,
        Map.take(Map.from_struct(subcomponent), Map.keys(Map.from_struct(%ICal.Event{})))
      )
    end

    # ── Events ──────────────────────────────────────────────────────────

    defp each_event(events, options) do
      Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
        case occurrences(event, options) do
          {:ok, spans} -> {:cont, {:ok, acc ++ spans}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end

    defp occurrences(%ICal.Event{dtstart: nil}, _options), do: {:ok, []}

    defp occurrences(%ICal.Event{} = event, options) do
      with {:ok, from} <- Tempo.from_elixir(event.dtstart),
           {:ok, extra} <- each(event.rdates || [], &Tempo.from_elixir/1),
           {:ok, excluded} <- each(event.exdates || [], &Tempo.from_elixir/1) do
        Occurrences.of(
          %{
            from: from,
            duration: duration(event),
            rules: rules(event),
            extra: extra,
            excluded: excluded,
            metadata: metadata(event)
          },
          options
        )
      end
    end

    defp each(items, fun) do
      Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
        case fun.(item) do
          {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end

    # An event's length: DTEND less DTSTART, DURATION, a day for an all-day
    # event with neither, and its own second for a time with neither.
    defp duration(%ICal.Event{dtstart: %Date{} = from, dtend: %Date{} = to}),
      do: %Duration{units: [day: max(Date.diff(to, from), 1)]}

    defp duration(%ICal.Event{dtstart: from, dtend: to})
         when not is_nil(to) and not is_struct(from, Date) do
      case seconds_between(from, to) do
        seconds when seconds > 0 -> %Duration{units: [second: seconds]}
        _ -> nil
      end
    end

    defp duration(%ICal.Event{duration: %ICal.Duration{positive: true, time: {h, m, s}} = d}) do
      units =
        Enum.reject([week: d.weeks, day: d.days, hour: h, minute: m, second: s], fn {_, n} ->
          n == 0
        end)

      if units == [], do: nil, else: %Duration{units: units}
    end

    defp duration(_event), do: nil

    defp seconds_between(%DateTime{} = from, %DateTime{} = to), do: DateTime.diff(to, from)

    defp seconds_between(%NaiveDateTime{} = from, %NaiveDateTime{} = to),
      do: NaiveDateTime.diff(to, from)

    defp seconds_between(_from, _to), do: 0

    defp rules(%ICal.Event{rrule: nil}), do: []

    defp rules(%ICal.Event{rrule: %ICal.Recurrence{} = rule, dtstart: dtstart}),
      do: [rule(rule, dtstart)]

    defp rule(%ICal.Recurrence{} = rule, dtstart) do
      all_day? = is_struct(dtstart, Date)

      %{
        freq: Map.fetch!(@frequencies, rule.frequency),
        interval: rule.interval || 1,
        count: rule.count,
        until: until(rule.until),
        bymonth: rule.by_month,
        bymonthday: rule.by_month_day,
        byyearday: rule.by_year_day,
        byweekno: rule.by_week_number,
        byday: byday(rule.by_day),
        byhour: if(all_day?, do: nil, else: rule.by_hour),
        byminute: if(all_day?, do: nil, else: rule.by_minute),
        bysecond: if(all_day?, do: nil, else: rule.by_second),
        bysetpos: rule.by_set_position
      }
      |> Enum.reject(fn {_, value} -> value in [nil, []] end)
      |> Map.new()
    end

    defp until(nil), do: nil
    defp until(value), do: Tempo.from_elixir!(value)

    defp byday(nil), do: nil

    defp byday(days) do
      Enum.map(days, fn {offset, day} ->
        {if(offset in [nil, 0], do: nil, else: offset), Map.fetch!(@weekdays, day)}
      end)
    end

    defp metadata(%ICal.Event{} = event) do
      %{
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
        organizer: named(event.organizer),
        attendees: Enum.map(event.attendees || [], &named/1),
        custom: event.custom_properties
      }
      |> present()
    end

    defp calendar_metadata(%ICal{} = calendar) do
      %{
        prodid: calendar.product_id,
        version: calendar.version,
        scale: calendar.scale,
        method: calendar.method,
        name: calendar.name
      }
      |> present()
    end

    defp present(map) do
      map
      |> Enum.reject(fn {_, value} -> value in [nil, [], %{}] end)
      |> Map.new()
    end

    defp named(nil), do: nil
    defp named(%{cname: name}) when is_binary(name), do: name
    defp named(text) when is_binary(text), do: text
    defp named(other), do: inspect(other)

    defp set([], metadata),
      do: %Tempo{form: {:all, []}, calendar: Calendar.ISO, metadata: metadata}

    defp set([first | _] = spans, metadata),
      do: %Tempo{
        form: {:all, spans},
        calendar: first.calendar,
        zone: first.zone,
        metadata: metadata
      }
  end
end
