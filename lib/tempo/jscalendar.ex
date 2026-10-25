if Code.ensure_loaded?(JSCalendar) do
  defmodule Tempo.JSCalendar do
    @moduledoc """
    Reads JSCalendar (RFC 8984) documents into Tempo: each `Event` an
    interval or, when it recurs, its occurrences, with the event's title,
    status and the rest as metadata; a `Group` its member events; a `Task`
    nothing, a task being work to do and not time taken.

    The JSON is decoded by the optional
    [`jscalendar`](https://hex.pm/packages/jscalendar) dependency, and this
    module is compiled only when it is present. An event's `start` is a
    local time in its `timeZone`, floating when it has none. Its recurrence
    rules are lowered to Tempo recurrences by `Tempo.RRule`, its excluded
    rules take occurrences away, and its recurrence overrides replace or
    remove the occurrence they name, or add one.

    Not read: a rule's `rscale` other than Gregorian, a `skip` other than
    `omit`, and a first day of the week other than Monday.

    """

    alias JSCalendar.{Event, Group, NDay, Occurrence, RecurrenceRule}
    alias Tempo.{Algebra, ConversionError, Occurrences, Options, Spans}

    @frequencies %{
      "yearly" => :year,
      "monthly" => :month,
      "weekly" => :week,
      "daily" => :day,
      "hourly" => :hour,
      "minutely" => :minute,
      "secondly" => :second
    }
    @weekdays %{"mo" => 1, "tu" => 2, "we" => 3, "th" => 4, "fr" => 5, "sa" => 6, "su" => 7}

    @doc """
    Reads a JSCalendar document into a set of intervals, one for each event
    or occurrence of an event, in order of start.

    ### Arguments

    * `json` is a JSCalendar document as text.

    * `options` is a keyword list of options.

    ### Options

    * `:within` is a `t:Tempo.t/0`, the window whose events are wanted:
      every occurrence that overlaps it is kept. It is required when an
      event recurs with neither `count` nor `until`.

    ### Returns

    * `{:ok, set}`, a `t:Tempo.t/0` of the `:all` form, each member's
      metadata its event's (`:uid`, `:title`, `:description`, `:status`,
      `:free_busy_status`, `:privacy`, `:time_zone`, `:sequence`).

    * `{:error, %ArgumentError{}}` when the document cannot be decoded,
      naming the reason the `jscalendar` library gives, and
      `{:error, exception}` when a zone is unknown, a rule is not supported
      or a recurrence has no end and no window is given.

    ### Examples

        iex> json = ~s({
        ...>   "@type": "Event",
        ...>   "uid": "review",
        ...>   "updated": "2026-06-01T09:00:00Z",
        ...>   "title": "Quarterly review",
        ...>   "start": "2026-06-02T09:00:00",
        ...>   "duration": "PT1H"
        ...> })
        iex> {:ok, events} = Tempo.JSCalendar.parse(json)
        iex> [review] = Tempo.IntervalSet.members(events)
        iex> {Tempo.to_iso8601!(review), Tempo.metadata(review).title}
        {"2026Y6M2DT9H0M0S/T10H0M0S", "Quarterly review"}

    """
    @spec parse(binary(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
    def parse(json, options \\ [])

    def parse(json, options) when is_binary(json) do
      with {:ok, object} <- decoded(JSCalendar.decode(json)), do: from_jscalendar(object, options)
    end

    def parse(other, _options),
      do:
        {:error,
         ArgumentError.exception("a JSCalendar document is JSON text, not #{inspect(other)}")}

    @doc """
    `parse/2`, returning its answer or raising the error.

    ### Arguments

    * The arguments are those of `parse/2`.

    ### Options

    * The options of `parse/2`.

    ### Returns

    * What `parse/2` returns as `{:ok, answer}`, the answer alone.
      The error it returns as `{:error, exception}` is raised.

    ### Examples

        iex> json = ~s({"@type":"Event","uid":"e","updated":"2026-06-01T09:00:00Z","start":"2026-06-02T09:00:00","duration":"PT1H"})
        iex> json |> Tempo.JSCalendar.parse!() |> Tempo.IntervalSet.count()
        1

    """
    @spec parse!(binary(), keyword()) :: Tempo.t()
    def parse!(json, options \\ []) do
      case parse(json, options) do
        {:ok, answer} -> answer
        {:error, exception} -> raise exception
      end
    end

    # The `jscalendar` library answers a document it cannot read with a
    # reason (`:invalid_json`, `{:unknown_type, type}`); Tempo answers with
    # an exception that names it.
    defp decoded({:ok, object}), do: {:ok, object}

    defp decoded({:error, reason}),
      do:
        {:error,
         ArgumentError.exception("the text is no JSCalendar document: #{inspect(reason)}")}

    @doc """
    The events of a JSCalendar object already decoded, as `parse/2` gives
    them.

    ### Arguments

    * `object` is a `JSCalendar.Event`, `JSCalendar.Task` or
      `JSCalendar.Group`.

    * `options` is a keyword list of options.

    ### Options

    * `:within` is as for `parse/2`.

    ### Returns

    * `{:ok, set}` or `{:error, exception}`, as for `parse/2`.

    ### Examples

        iex> {:ok, object} =
        ...>   JSCalendar.decode(
        ...>     ~s({"@type":"Event","uid":"e","updated":"2026-06-01T09:00:00Z","start":"2026-06-02T09:00:00","duration":"PT1H"})
        ...>   )
        iex> {:ok, events} = Tempo.JSCalendar.from_jscalendar(object)
        iex> Tempo.IntervalSet.map(events, &Tempo.to_iso8601!/1)
        ["2026Y6M2DT9H0M0S/T10H0M0S"]

    """
    @spec from_jscalendar(struct(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
    def from_jscalendar(object, options \\ []) do
      with :ok <- Options.check(options, [:within], "Tempo.JSCalendar.parse/2"),
           {:ok, spans} <- object_occurrences(object, options),
           {:ok, kept} <- Occurrences.within(spans, options[:within]) do
        Algebra.gathered(kept, floating: :place, sorted: true)
      end
    end

    @doc """
    `from_jscalendar/2`, returning its answer or raising the error.

    ### Arguments

    * The arguments are those of `from_jscalendar/2`.

    ### Options

    * The options of `from_jscalendar/2`.

    ### Returns

    * What `from_jscalendar/2` returns as `{:ok, answer}`, the answer alone.
      The error it returns as `{:error, exception}` is raised.

    ### Examples

        iex> json = ~s({"@type":"Event","uid":"e","updated":"2026-06-01T09:00:00Z","start":"2026-06-02T09:00:00","duration":"PT1H"})
        iex> {:ok, object} = JSCalendar.decode(json)
        iex> object |> Tempo.JSCalendar.from_jscalendar!() |> Tempo.IntervalSet.count()
        1

    """
    @spec from_jscalendar!(struct(), keyword()) :: Tempo.t()
    def from_jscalendar!(object, options \\ []) do
      case from_jscalendar(object, options) do
        {:ok, answer} -> answer
        {:error, exception} -> raise exception
      end
    end

    defp object_occurrences(%Event{} = event, options), do: occurrences(event, options)
    defp object_occurrences(%JSCalendar.Task{}, _options), do: {:ok, []}

    defp object_occurrences(%Group{entries: entries}, options) do
      entries
      |> List.wrap()
      |> Enum.filter(&is_struct(&1, Event))
      |> each(&occurrences(&1, options))
      |> flat()
    end

    defp object_occurrences(other, _options),
      do: {:error, ConversionError.exception(value: other, reason: :not_a_calendar_object)}

    defp occurrences(%Event{start: nil}, _options), do: {:ok, []}

    defp occurrences(%Event{} = event, options) do
      with {:ok, from} <- at_zone(event.start, event.time_zone),
           {:ok, rules} <- each(event.recurrence_rules || [], &rule/1),
           {:ok, excluded_rules} <- each(event.excluded_recurrence_rules || [], &rule/1),
           {:ok, spans} <-
             Occurrences.of(
               %{
                 from: from,
                 duration: duration(event),
                 rules: rules,
                 excluded_rules: excluded_rules,
                 metadata: metadata(event)
               },
               options
             ) do
        overridden(event, spans, options)
      end
    end

    # A recurrence override replaces the occurrence that starts at its id,
    # removes it when it is excluded, and adds one when no occurrence does.
    defp overridden(%Event{} = event, spans, options) do
      case Occurrence.overridden(event) do
        [] -> {:ok, spans}
        ids -> Enum.reduce_while(ids, {:ok, spans}, &override(&1, &2, event, options))
      end
    end

    defp override(id, {:ok, spans}, event, options) do
      case replaced(id, spans, event, options) do
        {:ok, spans} -> {:cont, {:ok, spans}}
        {:error, _} = error -> {:halt, error}
      end
    end

    defp replaced(id, spans, event, options) do
      with {:ok, at} <- at_zone(id, event.time_zone),
           {:ok, replacement} <- replacement(event, id, options) do
        start = Spans.start_position(at)
        {:ok, Enum.reject(spans, &(Spans.start_position(&1) == start)) ++ replacement}
      end
    end

    defp replacement(event, id, options) do
      case Occurrence.at(event, id) do
        {:ok, %Event{} = occurrence} ->
          occurrences(
            %{
              occurrence
              | recurrence_rules: nil,
                excluded_recurrence_rules: nil,
                recurrence_overrides: nil
            },
            options
          )

        :excluded ->
          {:ok, []}

        {:error, reason} ->
          {:error, ConversionError.exception(value: id, reason: reason)}
      end
    end

    # A local time in the event's zone, floating when it has none.
    defp at_zone(%NaiveDateTime{} = naive, nil), do: Tempo.from_elixir(naive)

    defp at_zone(%NaiveDateTime{} = naive, zone) when is_binary(zone) do
      with {:ok, value} <- Tempo.from_elixir(naive), do: Tempo.in_zone(value, zone)
    end

    defp duration(%Event{} = event) do
      units =
        event
        |> Event.duration()
        |> Map.take([:year, :month, :week, :day, :hour, :minute, :second])
        |> Enum.reject(fn {_, amount} -> amount == 0 end)

      case units do
        [] -> nil
        [_ | _] -> %Tempo.Duration{units: ordered(units)}
      end
    end

    defp ordered(units) do
      order = [:year, :month, :week, :day, :hour, :minute, :second]
      Enum.sort_by(units, fn {unit, _} -> Enum.find_index(order, &(&1 == unit)) end)
    end

    defp rule(%RecurrenceRule{} = rule) do
      with {:ok, freq} <- fetch(@frequencies, rule.frequency, :unsupported_frequency),
           {:ok, skip} <- skip(rule.skip),
           {:ok, months} <- months(rule.by_month),
           {:ok, days} <- byday(rule.by_day),
           {:ok, until} <- until(rule.until) do
        {:ok,
         %{
           freq: freq,
           interval: rule.interval || 1,
           count: rule.count,
           until: until,
           bymonth: months,
           bymonthday: rule.by_month_day,
           byyearday: rule.by_year_day,
           byweekno: rule.by_week_no,
           byday: days,
           byhour: rule.by_hour,
           byminute: rule.by_minute,
           bysecond: rule.by_second,
           bysetpos: rule.by_set_position,
           wkst: Map.get(@weekdays, rule.first_day_of_week),
           rscale: rule.rscale,
           skip: skip
         }
         |> Enum.reject(fn {_, value} -> value in [nil, []] end)
         |> Map.new()}
      end
    end

    # What is taken for a day or a month a year lacks (RFC 7529, as RFC 8984
    # takes it up); `omit`, the default, is no part of a rule.
    defp skip(skip) when skip in [nil, "omit"], do: {:ok, nil}
    defp skip("forward"), do: {:ok, :forward}
    defp skip("backward"), do: {:ok, :backward}
    defp skip(other), do: {:error, unsupported(:skip, other)}

    defp unsupported(what, value),
      do: ConversionError.exception(value: value, reason: {:unsupported, what})

    defp fetch(map, key, reason) do
      case Map.fetch(map, key) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, ConversionError.exception(value: key, reason: reason)}
      end
    end

    defp months(nil), do: {:ok, nil}

    defp months(values) do
      each(values, fn text ->
        case Integer.parse(text) do
          {month, ""} -> {:ok, month}
          {month, "L"} -> {:ok, {month, :leap}}
          _ -> {:error, unsupported(:month, text)}
        end
      end)
    end

    defp byday(nil), do: {:ok, nil}

    defp byday(days) do
      each(days, fn %NDay{day: day, nth_of_period: nth} ->
        with {:ok, weekday} <- fetch(@weekdays, day, :unsupported_day), do: {:ok, {nth, weekday}}
      end)
    end

    defp until(nil), do: {:ok, nil}
    defp until(%NaiveDateTime{} = until), do: Tempo.from_elixir(until)

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
      |> Enum.reject(fn {_, value} -> value in [nil, ""] end)
      |> Map.new()
    end

    defp each(items, fun) do
      Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
        case fun.(item) do
          {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end

    defp flat({:ok, lists}), do: {:ok, List.flatten(lists)}
    defp flat(error), do: error
  end
end
