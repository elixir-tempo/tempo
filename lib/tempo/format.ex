defmodule Tempo.Format do
  @moduledoc """
  Locale-aware formatting for `Tempo` values, dispatching to the Localize library.

  `Tempo.to_string/1,2`, `Tempo.to_string!/1,2` and the `String.Chars` implementation for `Tempo`, `Tempo.Interval`, `Tempo.IntervalSet`, `Tempo.Set`, `Tempo.RecurrenceSet` and `Tempo.Duration` route through this module. Callers don't need to use it directly.

  ### Rendering rule — Tempo values are intervals

  A `%Tempo{}` at year or month resolution is a bounded span, and its user-visible rendering reflects that span. Rule:

  * `~o"2026"` (year resolution) → `"Jan\u2009\u2013\u2009Dec 2026"`. Iteration over a year yields months; the first and last months are shown.

  * `~o"2026-06"` (month resolution) → `"Jun 1\u2009\u2013\u200930, 2026"`. Iteration over a month yields days; first and last day.

  * `~o"2026-W25"` (week resolution) → its first and last day, `"Jun 15\u2009\u2013\u200921, 2026"`. A week date (`~o"2026-W25-2"`) is the day it names, `"Jun 16, 2026"`.

  * `~o"2026-06-15"` (day resolution) → `"Jun 15, 2026"`. A day is atomic at human display granularity; collapse to a single value.

  * `~o"2026-06-15T14:30"` (minute or finer) → `"Jun 15, 2026, 2:30\u202FPM"`. Same collapse rationale.

  The cutoff between "expand as closed interval" and "collapse as single value" lives at **day granularity** by design — matching how people talk: "2026" is January-through-December; "June 2026" is June 1 to 30; "June 15" is just June 15.

  ### Closed vs half-open at the display boundary

  The underlying interval is always half-open `[from, to)`. For display we compute the **closed** last member of a span of days, months or years — `to - 1 iteration_unit` — so users see `"Jan\u2009\u2013\u2009Dec 2026"`, not `"Jan\u2009\u2013\u2009Jan 2026/2027"`. The closure happens purely at the display layer; the internal representation is unchanged.

  A span of clock times is shown to its end as it is written, as a time is said: `~o"2026-06-15T09/2026-06-15T17"` is `"Jun 15, 2026, 9\u202FAM\u2009\u2013\u20095\u202FPM"`, nine to five, and `~o"2026-06-15T09:30/2026-06-15T10:45"` is `"9:30\u2009\u2013\u200910:45\u202FAM"`. An hour, a minute or a second, and the interval it converts to, is the one value it is (`"10\u202FAM"`).

  ### Values that name several spans

  A value that names something other than its own one span — a mask, a group, a set, a selection, a recurrence, a recurrence set — renders as the span or spans `Tempo.to_interval/2` gives it, in a `:within` window when it has no end of its own. Several spans are joined as a CLDR list in the locale ("Jun 15, 2026 and Jul 15, 2026"), and a one-of set's members as alternatives ("2026 or 2027").

  ### Values that cannot be rendered

  `Tempo.to_string/2` returns `{:error, exception}` for a value it cannot render — an interval without both ends, a recurrence with no end and no `:within` window, an interval set without an end, a week or a day of the week without a year, or a locale or format Localize does not accept — and `Tempo.to_string!/2` raises it. `String.Chars` has no way to return an error, and interpolation sits on render paths, so interpolating such a value writes its ISO 8601 form (`"2026Y6M15D/.."` for an open interval), or its `inspect/1` form when it has none.

  ### Calendar awareness

  The map passed to Localize carries the Tempo's `:calendar` field, so Localize selects the appropriate CLDR data when available for that calendar. Coverage of non-Gregorian calendars depends on Localize's CLDR data and may fall back to Gregorian-equivalent formatting where calendar-specific data is absent.

  """

  alias Localize.DateTime.Relative
  alias Tempo.Compare
  alias Tempo.FloatingTempoError
  alias Tempo.Interval
  alias Tempo.Interval.Steps
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.Math
  alias Tempo.TimeZoneDatabase
  alias Tempo.UnanchoredError
  alias Tempo.UnboundedSetError
  alias Tempo.UnitValues
  alias Tempo.UnknownZoneError
  @time_units [:hour, :minute, :second, :microsecond]

  # Localize's relative-time units, coarsest first.
  @relative_units [:year, :quarter, :month, :week, :day, :hour, :minute, :second]

  @doc """
  Format a Tempo value, interval, set or duration as a locale-aware string.

  Delegated from `Tempo.to_string/1,2`, which describes what it returns.

  """
  @spec to_string(
          Tempo.t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.RecurrenceSet.t()
          | Tempo.Duration.t(),
          keyword()
        ) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(value, options \\ [])

  def to_string(value, options) do
    if Keyword.keyword?(options) do
      {window, options} = Keyword.split(options, [:within])

      with {:ok, value} <- with_its_seasons_dated(value, options),
           do: render(value, options, window)
    else
      {:error, options_error("to_string/2", options)}
    end
  end

  @doc false
  # `String.Chars` has no way to return an error, and interpolation sits on
  # render paths, so a value Localize cannot render shows as its ISO 8601
  # form, and one with no ISO 8601 form as its inspect form.
  @spec string_chars(
          Tempo.t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.RecurrenceSet.t()
          | Tempo.Duration.t()
        ) :: String.t()
  def string_chars(value) do
    case to_string(value, []) do
      {:ok, string} -> string
      {:error, _reason} -> iso8601_or_inspect(value)
    end
  end

  # A season of 21 to 24 is rendered as the dates it has in the territory of
  # the locale it is rendered in, and with no `:locale` in the application's
  # default territory and then the current locale's.
  defp with_its_seasons_dated(value, options),
    do: Tempo.with_seasons_dated(value, Keyword.take(options, [:locale]))

  defp iso8601_or_inspect(value) do
    case Tempo.to_iso8601(value) do
      {:ok, iso8601} -> iso8601
      {:error, _reason} -> inspect(value)
    end
  end

  # A plain value names its own one span and renders by its resolution. Any
  # other value — a mask, a group, a set, a selection, a recurrence, a recurrence
  # set — renders as the span or spans `Tempo.to_interval/2` gives it, in the
  # caller's `:within` window.
  defp render(%Tempo{} = tempo, options, window) do
    cond do
      not one_span?(tempo) -> tempo |> Tempo.to_interval(window) |> render_materialised(options)
      unplaced_without_year?(tempo) -> {:error, unplaced_without_year_error(tempo)}
      true -> render_value(tempo, options)
    end
  end

  defp render(%Tempo.Interval{} = interval, options, window) do
    interval |> Tempo.to_interval(window) |> render_materialised(options)
  end

  defp render(%Tempo.IntervalSet{} = set, options, _window),
    do: render_set(set, options, :standard)

  # A one-of set is one of its members, so it renders as their alternatives
  # ("2026 or 2027"); as an interval set it would assert every one.
  defp render(%Tempo.Set{type: :one, set: members, except: []}, options, window) do
    members
    |> render_each(&render(&1, options, window))
    |> join_rendered(options, :or)
  end

  defp render(%Tempo.Set{type: :one} = set, options, window) do
    with {:ok, %IntervalSet{} = candidates} <- Tempo.to_interval(%{set | type: :all}, window) do
      render_set(candidates, options, :or)
    end
  end

  defp render(%Tempo.Set{} = set, options, window) do
    set |> Tempo.to_interval(window) |> render_materialised(options)
  end

  defp render(%Tempo.RecurrenceSet{} = set, options, window) do
    set |> Tempo.to_interval(window) |> render_materialised(options)
  end

  # A range among a one-of set's members (`[2020..2025,2030]`) is one of the
  # values it spans, so it renders as that one span: the values an all-of set
  # of the range holds, merged.
  defp render(%Tempo.Range{} = range, options, window) do
    with {:ok, %IntervalSet{} = values} <-
           Tempo.to_interval(%Tempo.Set{type: :all, set: [range]}, window) do
      values |> IntervalSet.coalesce() |> render_set(options, :standard)
    end
  end

  # A duration's fraction of a second is its microseconds, which Localize
  # leaves out unless asked (`:except` defaults to `[:microsecond]`). A Tempo
  # duration holds only what was written, so they are kept.
  defp render(%Tempo.Duration{} = duration, options, _window) do
    Localize.Duration.to_string(
      to_localize_duration(duration),
      Keyword.put_new(options, :except, [])
    )
  end

  defp render(value, _options, _window) do
    {:error,
     ArgumentError.exception(
       "Tempo.to_string/2 formats a Tempo, Tempo.Interval, Tempo.IntervalSet, Tempo.Set, " <>
         "Tempo.RecurrenceSet or Tempo.Duration, got #{inspect(value)}."
     )}
  end

  defp render_materialised({:ok, %Tempo.Interval{} = interval}, options),
    do: render_interval(interval, options)

  defp render_materialised({:ok, %IntervalSet{} = set}, options),
    do: render_set(set, options, :standard)

  defp render_materialised({:error, _reason} = error, _options), do: error

  defp render_value(%Tempo{} = tempo, options) do
    {unit, _} = Tempo.resolution(tempo)

    cond do
      week_of_a_calendar_of_weeks?(tempo, options) ->
        render_weeks(tempo, tempo, options)

      expand_as_closed_interval?(unit, tempo, options) ->
        render_tempo_as_closed_interval(tempo, unit, options)

      true ->
        render_single_value(tempo, options)
    end
  end

  defp render_interval(%Tempo.Interval{from: from, to: to} = interval, options) do
    if weeks_of_a_calendar_of_weeks?(from, to, options),
      do: render_weeks(from, last_week(to), options),
      else: render_dates(interval, options)
  end

  defp render_dates(%Tempo.Interval{} = interval, options) do
    case the_one_value(interval) do
      %Tempo{} = value -> render_value(value, options)
      nil -> render_span(interval, options)
    end
  end

  defp render_span(%Tempo.Interval{} = interval, options) do
    with {:ok, from, to} <- interval_endpoints_for_format(interval) do
      {from, to} = collapse_midnight_endpoints(from, to)
      render_closed(from, last_shown(from, to), options)
    end
  end

  # An hour, a minute or a second is shown as the one value it is ("10 AM"),
  # and the interval it converts to is that value's span, with the unit it
  # is walked by. Shown in that unit it was its first and last minutes
  # ("10:00 – 10:59 AM"), and each member of a set of hours was too. So a
  # span that runs from a time of day to the next of its own unit is shown
  # as that value, whether it was converted from one or written with its
  # two ends (`T10/T11` is the hour of ten, as `T10` is; `T10:00/T11:00` is
  # sixty minutes, and is shown to its end). A day's span is one already,
  # its ends being midnights.
  @one_value_units [:hour, :minute, :second]

  defp the_one_value(%Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to}) do
    with {resolution, _span} when resolution in @one_value_units <- Tempo.resolution(from),
         %Tempo{} = next <- Math.add(from, Tempo.Duration.build([{resolution, 1}])),
         :same <- Compare.compare_endpoints(next, to) do
      from
    else
      _a_span_of_several_values -> nil
    end
  end

  defp the_one_value(_interval), do: nil

  # A week of a calendar of weeks is a unit of that calendar as a month is
  # of the Gregorian, and is shown as the locale words one: "week 25 of
  # 2026", "Woche 25 des Jahres 2026" (CLDR's `yw`), and a span of weeks
  # from its first to its last. It was shown by its first and last days,
  # "2026-W25-1 – 2026-W25-7", which is the notation and not the words.
  # A week of a calendar of months is the dates it holds, as it was.
  defp week_of_a_calendar_of_weeks?(
         %Tempo{time: [{:year, year}, {:week, week}], calendar: calendar},
         options
       )
       when is_integer(year) and is_integer(week) do
    Tempo.week_based_calendar?(calendar) and expandable_format?(Keyword.get(options, :format))
  end

  defp week_of_a_calendar_of_weeks?(_value, _options), do: false

  defp weeks_of_a_calendar_of_weeks?(%Tempo{} = from, %Tempo{} = to, options) do
    week_of_a_calendar_of_weeks?(from, options) and week_of_a_calendar_of_weeks?(to, options)
  end

  defp weeks_of_a_calendar_of_weeks?(_from, _to, _options), do: false

  # The last week a span of weeks holds is the one before its end.
  defp last_week(%Tempo{} = to), do: Math.subtract(to, Tempo.Duration.build(week: 1))

  defp render_weeks(%Tempo{time: time} = first, %Tempo{time: time}, options),
    do: Localize.Date.to_string(to_locale_map(first), in_weeks(options))

  defp render_weeks(%Tempo{} = first, %Tempo{} = last, options),
    do: Localize.Interval.to_string(to_locale_map(first), to_locale_map(last), in_weeks(options))

  defp render_weeks(_first, {:error, _reason} = error, _options), do: error

  defp in_weeks(options), do: options |> Keyword.drop([:fields]) |> Keyword.put(:format, :yw)

  # A span whose first and last values are one value is that value, so it
  # renders as a value does and a skeleton format applies to it.
  defp render_closed(%Tempo{time: time} = from, %Tempo{time: time}, options),
    do: render_value(from, options)

  defp render_closed(%Tempo{} = from, %Tempo{} = closed_last, options) do
    options = with_default_interval_options(options, from, closed_last)
    format_interval(from, closed_last, options)
  end

  defp render_closed(_from, {:error, _reason} = error, _options), do: error

  # The members joined as a CLDR list in the locale: `:standard` for a set's
  # members ("A, B, and C"), `:or` for alternatives. A set without an end has
  # no list to join.
  defp render_set(%IntervalSet{} = set, options, style) do
    if IntervalSet.bounded?(set) do
      set
      |> IntervalSet.members()
      |> render_each(&render_interval(&1, options))
      |> join_rendered(options, style)
    else
      {:error, UnboundedSetError.exception(operation: "Tempo.to_string/2", set: set)}
    end
  end

  defp render_each(items, render) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, rendered} ->
      case render.(item) do
        {:ok, string} -> {:cont, {:ok, [string | rendered]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp join_rendered({:ok, rendered}, options, style) do
    Localize.List.to_string(
      Enum.reverse(rendered),
      [list_style: style] ++ Keyword.take(options, [:locale])
    )
  end

  defp join_rendered({:error, _reason} = error, _options, _style), do: error

  # A value whose every component is one concrete value names its own one span.
  defp one_span?(%Tempo{time: time}), do: Enum.all?(time, &one_value?/1)

  defp one_value?({:selection, _selection}), do: false
  defp one_value?({_unit, value}) when is_integer(value), do: true

  defp one_value?({:microsecond, {value, precision}})
       when is_integer(value) and is_integer(precision),
       do: true

  # A margin of error rides on the value it is written beside. Significant
  # digits name the block of values the digits leave open (`1950S2` is the
  # twentieth century), which is a span of its own, as a mask's is.
  defp one_value?({_unit, {value, meta}}) when is_integer(value) and is_list(meta),
    do: not Keyword.has_key?(meta, :significant_digits)

  defp one_value?(_component), do: false

  # A week, a day of the week or a day of the year with no year has no date for
  # Localize to show.
  defp unplaced_without_year?(%Tempo{time: time}) do
    not Keyword.has_key?(time, :year) and
      Enum.any?([:week, :day_of_week, :day_of_year], &Keyword.has_key?(time, &1))
  end

  defp unplaced_without_year_error(tempo) do
    UnanchoredError.exception(
      operation: "render a week, a day of the week or a day of the year",
      value: tempo
    )
  end

  # Convert a Tempo.Duration (keyword-list time) into a
  # Localize.Duration struct. Weeks are normalised to days (as
  # `Calendrical.weeks_to_days/1` counts them, added onto any existing
  # :day count) because Localize.Duration has no :week field. Missing
  # units default to 0, and microseconds to `{0, 6}`.
  defp to_localize_duration(%Tempo.Duration{time: time}) do
    {weeks, rest} = Keyword.pop(time, :week, 0)
    days = Calendrical.weeks_to_days(weeks)
    rest = if weeks == 0, do: rest, else: Keyword.update(rest, :day, days, &(&1 + days))

    %Localize.Duration{
      year: Keyword.get(rest, :year, 0),
      month: Keyword.get(rest, :month, 0),
      day: Keyword.get(rest, :day, 0),
      hour: Keyword.get(rest, :hour, 0),
      minute: Keyword.get(rest, :minute, 0),
      second: Keyword.get(rest, :second, 0),
      microsecond: Keyword.get(rest, :microsecond, {0, 6})
    }
  end

  ## ---------------------------------------------------------
  ## Relative-time formatting — "3 hours ago", "in 2 days"
  ## ---------------------------------------------------------

  @doc """
  Format a Tempo or Tempo.Interval as a locale-aware relative
  time string, like `"3 hours ago"` or `"in 2 days"`.

  Delegated from `Tempo.to_relative_string/1,2`, which describes what it
  returns.

  """
  @spec to_relative_string(Tempo.t() | Tempo.Interval.t(), keyword()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_relative_string(value, options \\ [])

  def to_relative_string(value, options) do
    if Keyword.keyword?(options),
      do: relative_string(value, options),
      else: {:error, options_error("to_relative_string/2", options)}
  end

  # A season of 21 to 24 is the span it has in the locale's territory, and
  # is told from where that starts.
  defp relative_string(value, options)
       when is_struct(value, Tempo) or is_struct(value, Tempo.Interval) do
    with {:ok, dated} <- with_its_seasons_dated(value, options),
         do: relative_dated(dated, options)
  end

  defp relative_string(value, _options) do
    {:error,
     ArgumentError.exception(
       "Tempo.to_relative_string/2 formats a Tempo or Tempo.Interval, got #{inspect(value)}."
     )}
  end

  defp relative_dated(%Tempo{} = tempo, options), do: render_relative(tempo, options)

  defp relative_dated(%Tempo.Interval{} = interval, options) do
    with {:ok, start} <- interval_start(interval), do: render_relative(start, options)
  end

  defp options_error(function, options) do
    ArgumentError.exception(
      "Tempo.#{function} takes a keyword list of options, got #{inspect(options)}."
    )
  end

  # Where an interval starts: the start it is written with, the start its
  # duration is counted back to from its end, and for a recurrence written
  # to its end, the start of its first occurrence.
  defp interval_start(%Tempo.Interval{} = interval) do
    case Interval.from(interval) do
      %Tempo{} = start -> {:ok, start}
      _no_start -> first_occurrence_start(interval)
    end
  end

  defp first_occurrence_start(%Tempo.Interval{recurrence: recurrence} = interval)
       when is_integer(recurrence) and recurrence > 1 do
    with {:ok, %IntervalSet{} = occurrences} <- Tempo.to_interval(interval),
         [first | _rest] <- IntervalSet.members(occurrences),
         %Tempo{} = start <- Interval.from(first) do
      {:ok, start}
    else
      _no_occurrence -> {:error, no_start_error(interval)}
    end
  end

  defp first_occurrence_start(interval), do: {:error, no_start_error(interval)}

  defp no_start_error(interval) do
    IntervalEndpointsError.exception(
      operation: "to_relative_string/2",
      interval: interval,
      reason:
        "Tempo.to_relative_string/2 counts to where an interval starts, and " <>
          "#{inspect(interval)} has no start."
    )
  end

  defp render_relative(%Tempo{} = tempo, options) do
    {from, options} = Keyword.pop_lazy(options, :from, &Tempo.utc_now/0)
    {unit, options} = Keyword.pop(options, :unit)

    # Localize counts the unit's calendar periods from the baseline to the
    # value, in the value's calendar and on the value's wall clock.
    with {:ok, value, baseline, own_unit} <- relative_moments(tempo, from, unit),
         options = Keyword.put(options, :relative_to, baseline),
         {:ok, unit} <- counting_unit(unit, value, options, own_unit) do
      Relative.to_string(value, Keyword.put(options, :unit, unit))
    end
  end

  # The unit asked for or, without one, the unit Localize chooses — the
  # largest of which a whole one lies between — but never one finer than the
  # value's own: 2027 is "next year" from July 2026, not "in 6 months".
  # Localize names its unit on the number's parts, which a named form such
  # as "yesterday" has none of, so it is asked for the numeric form.
  defp counting_unit(nil, value, options, own_unit) do
    with {:ok, parts} <- Relative.to_parts(value, Keyword.put(options, :numeric, :always)) do
      chosen = Enum.find_value(parts, & &1[:unit])
      {:ok, Enum.find(@relative_units, &(&1 in [chosen, own_unit]))}
    end
  end

  defp counting_unit(unit, _value, _options, _own_unit), do: {:ok, unit}

  # The value and the baseline as Localize counts between them, each from
  # where its span starts. The value is on its own wall clock and in its own
  # calendar: a date for a day or longer, and a date and time for a finer
  # value or a finer unit, in its time zone when it names one, so the hours
  # across a change of offset are the hours that pass. The baseline is where
  # the value's clock reads it when both are zoned, and its own wall clock
  # otherwise.
  defp relative_moments(tempo, from, unit) do
    with {:ok, tempo} <- anchored(tempo),
         {:ok, from} <- anchored(from),
         {:ok, value} <- span_start(tempo),
         {:ok, from} <- span_start(from),
         kind = span_kind(value, unit),
         {:ok, moment} <- moment(value, kind, place(value)),
         {:ok, baseline} <- baseline(from, kind, place(value), place(from)) do
      {:ok, moment, baseline, own_unit(value)}
    end
  end

  defp anchored(%Tempo{} = value) do
    if Tempo.anchored?(value),
      do: {:ok, value},
      else: {:error, UnanchoredError.exception(operation: :to_relative_string, value: value)}
  end

  defp anchored(other) do
    {:error, ArgumentError.exception("`:from` must be a Tempo value, got #{inspect(other)}.")}
  end

  # Where a value's span starts. A value naming several spans has no one
  # start, nor does one whose span is open at its start.
  defp span_start(value) do
    case Interval.from(value) do
      %Tempo{} = start ->
        {:ok, start}

      {:error, _reason} = error ->
        error

      _open ->
        {:error,
         IntervalEndpointsError.exception(
           operation: "to_relative_string/2",
           reason: "#{inspect(value)} has no start to count from."
         )}
    end
  end

  defp moment(value, :date, _place), do: wall_date(value)
  defp moment(value, :time, {:zone, zone}), do: zoned_datetime(value, zone)
  defp moment(value, :time, _place), do: wall_datetime(value)

  # A zoned value finer than a day is measured from a baseline on the time
  # line, which a floating one is not.
  defp baseline(from, :time, place, :floating) when place != :floating,
    do: {:error, FloatingTempoError.exception(operation: :to_relative_string, value: from)}

  defp baseline(from, _kind, {:zone, zone}, from_place) when from_place != :floating,
    do: zoned_datetime(from, zone)

  defp baseline(from, _kind, {:offset, offset}, from_place) when from_place != :floating,
    do: {:ok, NaiveDateTime.from_gregorian_seconds(utc_seconds(from) + offset)}

  defp baseline(from, _kind, _place, _from_place), do: wall_datetime(from)

  # A value finer than a day, or counted in a unit finer than a day, is a
  # moment of its day; otherwise it is a date, so 16 June is "in 1 hour"
  # from 23:00 the day before and "tomorrow" in days.
  defp span_kind(_value, unit) when unit in @time_units, do: :time

  defp span_kind(value, _unit) do
    {resolution, _span} = Tempo.resolution(value)
    if resolution in @time_units, do: :time, else: :date
  end

  # The unit a value is written to: a day for a day of the week or of the
  # year, and a second for a fraction of one.
  defp own_unit(value) do
    {resolution, _span} = Tempo.resolution(value)
    relative_unit(resolution)
  end

  defp relative_unit(unit) when unit in [:year, :month, :week, :day, :hour, :minute, :second],
    do: unit

  defp relative_unit(:microsecond), do: :second
  defp relative_unit(_day), do: :day

  # Where a value's wall clock is: a named zone, a fixed offset in seconds,
  # or nowhere, for a floating value.
  defp place(%Tempo{extended: %{zone_id: zone}}) when is_binary(zone), do: {:zone, zone}

  defp place(%Tempo{shift: shift}) when is_list(shift),
    do: {:offset, Compare.offset_seconds(shift)}

  defp place(%Tempo{}), do: :floating

  # A value's first moment on its own wall clock, in its own calendar.
  defp wall_datetime(%Tempo{calendar: calendar} = value) do
    value
    |> Compare.to_wall_seconds()
    |> floor()
    |> NaiveDateTime.from_gregorian_seconds()
    |> NaiveDateTime.convert(Compare.effective_calendar(calendar))
  end

  defp wall_date(value) do
    with {:ok, datetime} <- wall_datetime(value), do: {:ok, NaiveDateTime.to_date(datetime)}
  end

  # A zoned value's first moment in `zone`, in its own calendar.
  defp zoned_datetime(%Tempo{calendar: calendar} = value, zone) do
    utc = DateTime.from_gregorian_seconds(utc_seconds(value))

    case DateTime.shift_zone(utc, zone, TimeZoneDatabase.database()) do
      {:ok, zoned} -> DateTime.convert(zoned, Compare.effective_calendar(calendar))
      {:error, _reason} -> {:error, UnknownZoneError.exception(zone_id: zone)}
    end
  end

  defp utc_seconds(value), do: value |> Compare.to_utc_seconds() |> floor()

  ## ---------------------------------------------------------
  ## Closed-interval expansion for year/month Tempo values
  ## ---------------------------------------------------------

  # Rule B: year and month expand; day, hour, minute, second, and
  # unanchored values collapse. An unanchored Tempo has no
  # enumeration start in interval terms — we fall through to the
  # single-value path which routes to Localize.Time.
  defp expand_as_closed_interval?(unit, tempo, options)

  # A year whose months are not the months named (`named_unit/2`) is shown
  # as the year it is: its first and last days carry one year's number in
  # the calendar's own dates, the last a day before the first.
  defp expand_as_closed_interval?(:year, %Tempo{} = tempo, options) do
    named_unit(:month, tempo) == :month and expandable_format?(Keyword.get(options, :format))
  end

  defp expand_as_closed_interval?(unit, %Tempo{time: time}, options)
       when unit in [:month, :week] do
    Keyword.has_key?(time, :year) and expandable_format?(Keyword.get(options, :format))
  end

  defp expand_as_closed_interval?(_unit, _tempo, _options), do: false

  # Expanding a year into "Jan – Dec 2026" is Rule B's answer to the
  # question "how should a year be shown?" — it is what to do when the
  # caller has not said. A caller who names a skeleton has said: `:y`
  # asks for a year, and rendering its twelve months instead answers a
  # question they did not ask. A span written with two ends takes a
  # skeleton across them, as Localize's interval formats do.
  #
  # A named width names both ends of a range as readily as a single
  # value, so those still expand.
  defp expandable_format?(nil), do: true
  defp expandable_format?(format) when format in [:short, :medium, :long, :full], do: true
  defp expandable_format?(_skeleton), do: false

  # Materialise the Tempo, compute first and closed-last at the
  # iteration unit (one level finer than the Tempo's resolution),
  # then hand off to Localize.Interval.
  defp render_tempo_as_closed_interval(%Tempo{} = tempo, unit, options) do
    iter_unit = unit |> next_finer_unit() |> named_unit(tempo)

    case Tempo.to_interval(tempo) do
      {:ok, %Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to, unit: unit}} ->
        # The rendered range spans the implicit sub-units ("Jan – Dec
        # 2026" for a year), so fill the own-resolution bounds down to
        # the interval's iteration unit before truncating.
        calendar = Compare.effective_calendar(from.calendar)
        unit = named_unit(unit, tempo)
        from = Steps.fill_to_unit(from, unit, calendar)
        to = Steps.fill_to_unit(to, unit, calendar)
        shown_unit = duration_unit(iter_unit)
        one_less = Tempo.Duration.build([{shown_unit, 1}])

        # The day before a week's end is a date in a calendar of months and
        # a day of the week in a calendar of weeks, and `:day` is the day of
        # either.
        with %Tempo{} = last <- Math.subtract(to, one_less),
             %Tempo{} = first <- Tempo.trunc(from, shown_unit),
             %Tempo{} = closed_last <- Tempo.trunc(last, shown_unit) do
          options = with_default_interval_options(options, first, closed_last)
          format_interval(first, closed_last, options)
        else
          _other -> render_single_value(tempo, options)
        end

      _other ->
        # Fall back to single-value render if materialisation
        # returned something unexpected (e.g. IntervalSet from a
        # masked value).
        render_single_value(tempo, options)
    end
  end

  # A span is shown from its first value to its last in the unit it is walked
  # by, and a month is shown by its name. A year that begins within a month
  # starts and ends in the month of one name (a `Calendrical.Julian.March25`
  # year runs from 25 March to the next 24 March), so it and a span of its
  # months are shown by their days: by its months it was "Mar 1750".
  defp named_unit(:month, %Tempo{time: [{:year, year} | _rest], calendar: calendar})
       when is_integer(year) do
    if UnitValues.year_named_by_its_months?(year, Compare.effective_calendar(calendar)),
      do: :month,
      else: :day
  end

  defp named_unit(unit, %Tempo{}), do: unit

  defp next_finer_unit(:year), do: :month
  defp next_finer_unit(:month), do: :day
  defp next_finer_unit(:week), do: :day_of_week
  defp next_finer_unit(:day), do: :hour
  defp next_finer_unit(:hour), do: :minute
  defp next_finer_unit(:minute), do: :second
  defp next_finer_unit(:second), do: :second

  # A week's days are days of the week; a duration counts them as days.
  defp duration_unit(:day_of_week), do: :day
  defp duration_unit(unit), do: unit

  ## ---------------------------------------------------------
  ## Single-value rendering (day, hour, minute, second, time-only)
  ## ---------------------------------------------------------

  defp render_single_value(%Tempo{} = tempo, options), do: dispatch(tempo, options)

  # Route a plain Tempo to the right Localize function.
  #
  # Two things decide where a value goes: the fields it actually
  # carries, and the fields the requested format names. They are not
  # the same question, and conflating them is what produced renderings
  # like `": , 10:45 am"` — a date-and-time value sent to
  # `Localize.DateTime` with a skeleton naming no date fields, leaving
  # that half of the pattern with nothing to fill it.
  #
  # So the format is reconciled against the value first (see
  # `reconcile/2`), and the *reconciled* format decides the axis:
  #
  #   * a format naming only time fields renders the time alone, even
  #     when the value also carries a date — asking for `:hm` is asking
  #     for an hour and a minute;
  #   * a format naming only date fields renders the date alone;
  #   * a named width (`:short`, `:medium`, …) names both halves, so
  #     the value's own shape decides.
  defp dispatch(%Tempo{} = tempo, options) do
    {format, options} = Keyword.pop(options, :format)
    format = reconcile(format, tempo)
    options = Keyword.put(options, :format, format)

    case axis(format) do
      :time -> Localize.Time.to_string(to_locale_map(tempo), options)
      :date -> Localize.Date.to_string(to_locale_map(tempo), options)
      :both -> dispatch_by_value(tempo, options)
    end
  end

  defp dispatch_by_value(%Tempo{} = tempo, options) do
    cond do
      date_only?(tempo) -> Localize.Date.to_string(to_locale_map(tempo), options)
      time_only?(tempo) -> Localize.Time.to_string(to_locale_map(tempo), options)
      true -> Localize.DateTime.to_string(to_locale_map(tempo), options)
    end
  end

  # A skeleton asking for finer precision than the value carries would
  # render empty fields — `:hms` on a value with no second gives
  # `"10:45:"`. Trim the request to what is actually there. A skeleton
  # asking for an axis the value does not have at all (`:yMMMd` on a
  # time) cannot be honoured, so the value's own shape takes over.
  defp reconcile(nil, %Tempo{} = tempo) do
    {unit, _span} = Tempo.resolution(tempo)
    default_format_for_unit(unit, tempo)
  end

  defp reconcile(format, %Tempo{} = tempo) when is_atom(format) do
    case axis(format) do
      :time -> trim_time(format, tempo)
      :date -> trim_date(format, tempo)
      :both -> format
    end
  end

  # A pattern string is the caller spelling out exactly what they want.
  defp reconcile(format, _tempo), do: format

  defp trim_time(format, %Tempo{} = tempo) do
    if date_only?(tempo) do
      # No time to render at all; fall back to the value's own shape.
      reconcile(nil, tempo)
    else
      finest = Enum.find([:second, :minute, :hour], &has_field?(tempo, &1))

      case {format, finest} do
        {_any, nil} -> reconcile(nil, tempo)
        {:hms, :minute} -> :hm
        {:hms, :hour} -> :h
        {:hm, :hour} -> :h
        {given, _finest} -> given
      end
    end
  end

  defp trim_date(format, %Tempo{} = tempo) do
    if time_only?(tempo) do
      reconcile(nil, tempo)
    else
      finest = Enum.find([:day, :month, :year], &has_field?(tempo, &1))

      case {format, finest} do
        {_any, nil} -> reconcile(nil, tempo)
        {:yMMMd, :month} -> :yMMM
        {:yMMMd, :year} -> :y
        {:yMMM, :year} -> :y
        {given, _finest} -> given
      end
    end
  end

  # Which half of the clock a format names. Named widths name both.
  defp axis(format) when format in [:short, :medium, :long, :full], do: :both
  defp axis(format) when format in [:h, :hm, :hms], do: :time
  defp axis(format) when format in [:y, :yMMM, :yMMMd, :MMM], do: :date
  defp axis(_format), do: :both

  # The fields Localize is given, so a week date has the day it names.
  defp has_field?(%Tempo{} = tempo, field), do: Map.has_key?(to_locale_map(tempo), field)

  # A Tempo is date-only when its time kv list contains none of
  # :hour, :minute, :second. It is time-only when it contains
  # none of :year, :month, :day (i.e. unanchored). Otherwise
  # it's a datetime.
  defp date_only?(%Tempo{time: time}) do
    Keyword.has_key?(time, :year) and
      not (Keyword.has_key?(time, :hour) or Keyword.has_key?(time, :minute) or
             Keyword.has_key?(time, :second))
  end

  defp time_only?(%Tempo{time: time}) do
    not Keyword.has_key?(time, :year) and
      not Keyword.has_key?(time, :month) and
      not Keyword.has_key?(time, :day)
  end

  # Convert a Tempo to the map shape Localize accepts: flatten the
  # time keyword list into map keys and append the :calendar field.
  defp to_locale_map(%Tempo{time: time, calendar: calendar}) do
    calendar = calendar || Calendrical.Gregorian

    time
    |> week_date_as_day(calendar)
    |> Enum.reduce(%{}, fn
      {k, v}, acc when is_integer(v) -> Map.put(acc, k, v)
      _other, acc -> acc
    end)
    |> Map.put(:calendar, calendar)
  end

  # A week date names a day — its day of the week, or the first day of a
  # whole week — which Localize takes as a date's year, month and day in
  # the value's calendar.
  defp week_date_as_day(time, calendar) do
    with week when is_integer(week) <- Keyword.get(time, :week),
         year when is_integer(year) <- Keyword.get(time, :year),
         day when is_integer(day) <- Keyword.get(time, :day_of_week, 1),
         {:ok, date} <- UnitValues.date_from_iso_week(year, week, day, calendar) do
      [year: date.year, month: date.month, day: date.day] ++
        Keyword.drop(time, [:year, :week, :day_of_week])
    else
      _not_a_week_date -> time
    end
  end

  # A value of a year before 1 is shown with its era, which the formats
  # for a date of today leave out: `-0044-03-15` is "Mar 15, 45 BC", where
  # it was "Mar 15, 45", the words for a day ninety years later.
  defp default_format_for_unit(unit, tempo) do
    if before_the_era?(tempo),
      do: format_with_era(unit, tempo),
      else: format_for_unit(unit, tempo)
  end

  defp format_for_unit(:year, _tempo), do: :y
  # A month of no particular year is its name alone.
  defp format_for_unit(:month, %Tempo{time: time}) do
    if Keyword.has_key?(time, :year), do: :yMMM, else: :MMM
  end

  defp format_for_unit(:day, _tempo), do: :medium

  # `:h` and `:hm` are time-only skeletons. They are right for a value
  # with no date and wrong for one that has both halves, where
  # `:medium` names each and follows the components present — showing
  # seconds for a second-resolution value and omitting them otherwise.
  defp format_for_unit(unit, tempo) when unit in [:hour, :minute] do
    if time_only?(tempo) do
      (unit == :hour && :h) || :hm
    else
      :medium
    end
  end

  defp format_for_unit(:second, _tempo), do: :medium
  defp format_for_unit(_other, _tempo), do: :medium

  # CLDR's skeletons that name the era (`G`) beside the fields a value of
  # each resolution holds.
  defp format_with_era(:year, _tempo), do: :Gy
  defp format_with_era(:month, _tempo), do: :GyMMM
  defp format_with_era(:hour, _tempo), do: :GyMMMdj
  defp format_with_era(:minute, _tempo), do: :GyMMMdjm
  defp format_with_era(:second, _tempo), do: :GyMMMdjms
  defp format_with_era(_day_or_another, _tempo), do: :GyMMMd

  # Whether a value's year is before year 1 of the Gregorian calendar's
  # era, or of a calendar CLDR words as it does the Gregorian (the Julian):
  # the era CLDR's formats for a date take as read is the one today is in.
  defp before_the_era?(%Tempo{time: [{:year, year} | _units], calendar: calendar})
       when is_integer(year) do
    calendar = Compare.effective_calendar(calendar)

    worded_as_gregorian?(calendar) and match?({_year, 0}, calendar.year_of_era(year))
  end

  defp before_the_era?(_value), do: false

  defp worded_as_gregorian?(calendar) do
    Code.ensure_loaded?(calendar) and function_exported?(calendar, :cldr_calendar_type, 0) and
      function_exported?(calendar, :year_of_era, 1) and
      calendar.cldr_calendar_type() == :gregorian
  end

  ## ---------------------------------------------------------
  ## Interval formatting helpers (shared by %Tempo{} expansion
  ## and %Tempo.Interval{})
  ## ---------------------------------------------------------

  # What a span is shown to. A span of days, months or years is shown to
  # the last it holds ("Jun 15 – 17, 2026" for one that ends as the 18th
  # begins), the end of a half-open span being no day of it. A span of clock
  # times is shown to its end as it is written (decided 2026-10-08), as a
  # time is said: nine to five is "9 AM – 5 PM". It was shown to the last
  # hour it holds, "9 AM – 4 PM", and to its last minute where it was
  # written to the minute, "9:30 – 10:44 AM".
  defp last_shown(%Tempo{} = from, %Tempo{} = to) do
    case Tempo.resolution(from) do
      {unit, _span} when unit in @time_units -> to
      _a_unit_of_the_date -> closed_last_for_interval(from, to)
    end
  end

  # For a raw Interval, the closed last is `to - 1 iteration_unit`
  # where the iteration unit is the resolution of `from` (explicit
  # spans iterate at their own resolution per the architecture
  # note in CLAUDE.md).
  defp closed_last_for_interval(%Tempo{} = from, %Tempo{} = to) do
    {iter_unit, _} = Tempo.resolution(from)
    Math.subtract(to, Tempo.Duration.build([{duration_unit(iter_unit), 1}]))
  end

  # When an interval's endpoints carry time-of-day components that
  # are all zero — i.e. the interval is midnight-to-midnight — the
  # time parts are materialisation artifacts rather than
  # user-chosen resolution. Trunc both endpoints to the coarsest
  # unit common to both so the rendering matches what the user
  # would see for the equivalent `%Tempo{}`. Explicit intervals
  # with non-zero time components are preserved.
  defp collapse_midnight_endpoints(%Tempo{} = from, %Tempo{} = to) do
    if midnight_endpoints?(from) and midnight_endpoints?(to) do
      target_unit = display_unit_for_midnight_pair(from, to)
      {Tempo.trunc(from, target_unit), Tempo.trunc(to, target_unit)}
    else
      {from, to}
    end
  end

  defp midnight_endpoints?(%Tempo{time: time}) do
    Keyword.get(time, :hour, 0) == 0 and
      Keyword.get(time, :minute, 0) == 0 and
      Keyword.get(time, :second, 0) == 0
  end

  # The natural display unit for a midnight-to-midnight pair is
  # the coarsest date unit both endpoints carry. If both have day,
  # use :day. If both have at least month, use :month. Otherwise
  # :year.
  defp display_unit_for_midnight_pair(%Tempo{time: from_time}, %Tempo{time: to_time}) do
    Enum.find([:day, :day_of_week, :month, :week], :year, fn unit ->
      Keyword.has_key?(from_time, unit) and Keyword.has_key?(to_time, unit)
    end)
  end

  # Intervals take {:format, :fields} options; `:fields` tells
  # Localize which date fields to render (Localize 1.0 renamed it
  # from `:style`). We pick the fields from the coarsest resolution
  # among the two endpoints so a year-month interval doesn't try to
  # render an absent day.
  #
  # A span with an end before year 1 names the era at both ends, by the
  # skeleton of the fields it shows ("Mar 15, 45 BC – Aug 19, 14 AD"),
  # where the caller names no format.
  defp with_default_interval_options(options, %Tempo{} = from, %Tempo{} = to) do
    fields = interval_fields_for(from, to)

    if not Keyword.has_key?(options, :format) and (before_the_era?(from) or before_the_era?(to)) do
      Keyword.put(options, :format, interval_format_with_era(fields, from))
    else
      options
      |> Keyword.put_new(:format, :medium)
      |> with_fields(fields)
    end
  end

  defp with_fields(options, :as_they_hold), do: options
  defp with_fields(options, fields), do: Keyword.put_new(options, :fields, fields)

  # Months alone, or the days and the times of day the ends are written to.
  defp interval_format_with_era(:year_and_month, _from), do: :GyMMM

  defp interval_format_with_era(_date_or_as_they_hold, %Tempo{} = from) do
    {unit, _span} = Tempo.resolution(from)
    format_with_era(unit, from)
  end

  # Two months of no year (`6M/9M`, June to August of any year) are shown
  # by the fields they hold, which Localize writes as "Jun – Aug". They
  # were asked for with their year, which they have none of.
  defp interval_fields_for(%Tempo{time: [month: _from_month]}, %Tempo{time: [month: _to_month]}),
    do: :as_they_hold

  defp interval_fields_for(%Tempo{} = from, %Tempo{} = to) do
    {from_unit, _} = Tempo.resolution(from)
    {to_unit, _} = Tempo.resolution(to)
    coarsest = coarsest_unit(day_as_day(from_unit), day_as_day(to_unit))

    case coarsest do
      :year -> :year_and_month
      :month -> :year_and_month
      :day -> :date
      _time_component -> :date
    end
  end

  # A week date's day is a day.
  defp day_as_day(:day_of_week), do: :day
  defp day_as_day(unit), do: unit

  @unit_order_ctf [:year, :month, :day, :hour, :minute, :second]

  defp coarsest_unit(a, b) do
    i_a = Enum.find_index(@unit_order_ctf, &(&1 == a)) || 0
    i_b = Enum.find_index(@unit_order_ctf, &(&1 == b)) || 0
    Enum.at(@unit_order_ctf, min(i_a, i_b))
  end

  # Year-resolution intervals don't render well through
  # Localize.Interval (the patterns assume at least month). Format
  # each endpoint with the `:y` skeleton and join with the
  # thin-space en-dash CLDR uses for interval ranges.
  #
  # For all other resolutions, delegate to Localize.Interval which
  # handles date-, hour-, minute-, and second-level endpoints and
  # collapses the degenerate (from == to) case natively.
  defp format_interval(%Tempo{} = from, %Tempo{} = to, options) do
    {from_unit, _} = Tempo.resolution(from)
    {to_unit, _} = Tempo.resolution(to)

    if from_unit == :year and to_unit == :year do
      format_year_only_interval(from, to, options)
    else
      Localize.Interval.to_string(to_locale_map(from), to_locale_map(to), options)
    end
  end

  defp format_year_only_interval(%Tempo{} = from, %Tempo{} = to, options) do
    year_format = if before_the_era?(from) or before_the_era?(to), do: :Gy, else: :y

    year_opts =
      options
      |> Keyword.put(:format, year_format)
      |> Keyword.drop([:fields])

    with {:ok, from_str} <- Localize.Date.to_string(to_locale_map(from), year_opts),
         {:ok, to_str} <- Localize.Date.to_string(to_locale_map(to), year_opts) do
      if from_str == to_str do
        {:ok, from_str}
      else
        {:ok, from_str <> "\u2009\u2013\u2009" <> to_str}
      end
    end
  end

  # Extract {from, to} from an interval for formatting. A plain
  # pair of endpoints is enough for Localize.Interval; a recurrence
  # is materialised to its occurrences before it gets here.
  #
  # Both ends are filled down to the unit the interval is shown in, so
  # the last value it holds is one such unit before its end: a year to
  # a month (`2026/2026-03`) is January to February, as its walk yields.
  defp interval_endpoints_for_format(%Tempo.Interval{} = interval) do
    case Tempo.Interval.endpoints(interval) do
      {%Tempo{} = from, %Tempo{} = to} ->
        calendar = Compare.effective_calendar(from.calendar)
        {from, to} = on_one_axis(from, to, calendar)
        unit = %Tempo.Interval{interval | from: from, to: to} |> shown_unit() |> named_unit(from)
        {:ok, Steps.fill_to_unit(from, unit, calendar), Steps.fill_to_unit(to, unit, calendar)}

      {from, _to} ->
        {:error,
         IntervalEndpointsError.exception(
           operation: "Tempo.to_string/2",
           interval: interval,
           reason:
             "Tempo.to_string/2 shows an interval from its start to its end, and " <>
               "#{inspect(interval)} has no #{open_end(from)}."
         )}
    end
  end

  defp open_end(%Tempo{}), do: "end"
  defp open_end(_open), do: "start"

  # A week beside a month or a day of one has no unit in common with it, so
  # it is shown as the date its first day is: `2026-W25/2026-07-01` runs
  # from 15 June.
  defp on_one_axis(%Tempo{} = from, %Tempo{} = to, calendar) do
    if week?(from) == week?(to),
      do: {from, to},
      else: {week_as_date(from, calendar), week_as_date(to, calendar)}
  end

  defp week?(%Tempo{time: time}), do: Keyword.has_key?(time, :week)

  defp week_as_date(%Tempo{time: time} = tempo, calendar),
    do: %Tempo{tempo | time: week_date_as_day(time, calendar)}

  # The unit an interval is shown in. A materialised implicit span carries
  # its iteration granularity on `:unit` ("Jan – Dec 2026" for a year). One
  # written with two ends is shown in the unit it is walked by, the finer
  # of its ends', and a range of whole weeks by its days, as a week is.
  defp shown_unit(%Tempo.Interval{unit: unit}) when not is_nil(unit), do: unit

  defp shown_unit(%Tempo.Interval{} = interval) do
    case Tempo.Interval.granularity(interval) do
      :week -> :day_of_week
      unit -> unit
    end
  end
end
