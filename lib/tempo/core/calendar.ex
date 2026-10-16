defmodule Tempo.Calendar do
  @moduledoc false

  # Every calendar question the library asks, and the one place that knows
  # which module answers for `Calendar.ISO`.
  #
  # Tempo holds a calendar as the module a caller gave it and asks it
  # questions through this module alone. `Calendar.ISO` keeps Elixir's
  # `Calendar` behaviour and none of Calendrical's, so its questions go to
  # the module that answers both for it (`Localize.Calendar.ISO`, or what
  # the application configures), and the answer comes back as a day number,
  # a `{year, month, day}` tuple, a span of days or a label: never as a date
  # of the answering module. A value's calendar is therefore what the caller
  # gave, from construction to output, and nothing is rewritten on the way
  # in or out.
  #
  # The questions are those of the calendar contract in
  # `plans/architecture-redesign.md`, section 8.3: the day scale, validity,
  # periods as spans, the labels of a date, a shift, the bounds a month and
  # a year have with no year, and names. Nothing here asks what kind of
  # calendar it is talking to, and nothing holds a number a calendar would
  # answer.

  alias Calendrical.{Ecclesiastical, Lunisolar}
  alias Tempo.Calendar.WeeksFrom
  alias Tempo.InvalidCalendarError

  @implementations Application.compile_env(
                     :ex_tempo,
                     :calendar_implementations,
                     %{Calendar.ISO => Localize.Calendar.ISO}
                   )

  # BCP 47's names for the day a week begins on (the `fw` key), Monday first.
  @week_day_names ~w(mon tue wed thu fri sat sun)

  # The Gregorian calendar with its weeks begun on each day but Monday.
  @weeks_from %{
    2 => WeeksFrom.Tuesday,
    3 => WeeksFrom.Wednesday,
    4 => WeeksFrom.Thursday,
    5 => WeeksFrom.Friday,
    6 => WeeksFrom.Saturday,
    7 => WeeksFrom.Sunday
  }
  @week_starts Map.new(@weeks_from, fn {day, calendar} -> {calendar, day} end)

  # ISO 8601 numbers the seven days of the week, Monday 1 to Sunday 7; a
  # calendar numbers them from the day its weeks begin on.
  @iso_weekdays 7

  # The days of the week by name, in ISO 8601's order.
  @weekday_names [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  # A day on which to ask a calendar both numberings of its day of the week
  # (2000-01-01, a day number, not a calendar's answer).
  @any_day 730_485

  @typedoc "A half-open span of days: the first day and the day after the last, as ISO day numbers."
  @type span :: {first :: integer(), after_last :: integer()}

  @type date :: {Calendar.year(), Calendar.month(), Calendar.day()}

  @type period :: :year | :month | :week | :quarter

  @doc "Whether a module is a calendar Tempo can ask: one of the implementations, or one that declares Calendrical's behaviour."
  @spec calendar?(term()) :: boolean()
  def calendar?(module) when is_atom(module) and not is_nil(module) do
    is_map_key(@implementations, module) or
      (Code.ensure_loaded?(module) and Calendrical in behaviours(module))
  end

  def calendar?(_other), do: false

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp impl(calendar), do: Map.get(@implementations, calendar, calendar)

  @doc "The calendar of a value that names none."
  @spec default() :: Calendar.ISO
  def default, do: Calendar.ISO

  @doc """
  Whether a calendar is the Gregorian: the default, the one CLDR's
  `gregorian` names, or either with its weeks begun on another day.
  """
  @spec gregorian?(module()) :: boolean()
  def gregorian?(calendar) do
    calendar == default() or from_type(:gregorian) == {:ok, calendar} or
      is_map_key(@week_starts, calendar)
  end

  # ── The day a week begins on ──────────────────────────────────────────

  @doc """
  The calendar of an expression whose weeks begin on a day, 1 (Monday) to 7
  (Sunday): for Monday the Gregorian calendar as it is, and for another day
  the one of the same dates whose weeks begin there. A calendar that is not
  the Gregorian has its own weeks and no other, and is an error.
  """
  @spec with_week_start(module(), 1..7) :: {:ok, module()} | {:error, Exception.t()}
  def with_week_start(calendar, day) when day in 1..7 do
    cond do
      not gregorian?(calendar) -> {:error, no_other_weeks(calendar)}
      day == 1 and is_map_key(@week_starts, calendar) -> {:ok, default()}
      day == 1 -> {:ok, calendar}
      true -> {:ok, Map.fetch!(@weeks_from, day)}
    end
  end

  def with_week_start(_calendar, day),
    do:
      {:error,
       ArgumentError.exception(
         "a week begins on a day 1 (Monday) to 7 (Sunday), not #{inspect(day)}"
       )}

  defp no_other_weeks(calendar) do
    ArgumentError.exception(
      "#{inspect(calendar)} has its own weeks: the day a week begins on is named for the Gregorian calendar only"
    )
  end

  @doc "The day an expression's weeks are written to begin on, 2 to 7, or nil for a calendar's own weeks."
  @spec week_start(module()) :: 2..7 | nil
  def week_start(calendar), do: Map.get(@week_starts, calendar)

  @doc "The day BCP 47's `fw` names: `sun` is 7."
  @spec week_start_named(String.t()) :: {:ok, 1..7} | :error
  def week_start_named(name) do
    case Enum.find_index(@week_day_names, &(&1 == name)) do
      nil -> :error
      index -> {:ok, index + 1}
    end
  end

  @doc "BCP 47's name for a day a week begins on: 7 is `sun`."
  @spec week_start_name(1..7) :: String.t()
  def week_start_name(day) when day in 1..7, do: Enum.at(@week_day_names, day - 1)

  @doc "The fields a locale's words for a date name, read through Calendrical in the default calendar unless one is given."
  @spec words(String.t(), keyword()) ::
          {:ok, map() | {map(), map()}} | {:error, Exception.t()}
  def words(text, options),
    do: Calendrical.parse(text, Keyword.put_new(options, :calendar, default()))

  # ── Days a calendar or the sky fixes ──────────────────────────────────

  @doc "The names of the solar terms, each with the number it is counted by, from `lichun`."
  @spec solar_term_names() :: %{String.t() => pos_integer()}
  def solar_term_names do
    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&{Lunisolar.solar_term_name(&1), &1})
    |> Enum.take_while(&match?({{:ok, _name}, _number}, &1))
    |> Map.new(fn {{:ok, name}, number} -> {name, number} end)
  end

  @doc """
  The day of a solar term of a Gregorian year, as the calendar reckons it:
  a lunisolar calendar at its own meridian. `{:error, :undefined}` for a
  calendar that reckons none.
  """
  @spec solar_term(module(), pos_integer(), Calendar.year()) ::
          {:ok, Date.t()} | {:error, term()}
  # `Localize.Calendar.ISO` answers no solar term, as Localize has no
  # astronomy, so the default calendar is asked as the Gregorian, which
  # reckons the terms at the traditional reference (decided 2026-10-14).
  def solar_term(Calendar.ISO, number, year), do: solar_term(Calendrical.Gregorian, number, year)
  def solar_term(calendar, number, year), do: impl(calendar).solar_term(number, year)

  @doc "Easter Sunday of a Gregorian year, as the Western churches reckon it."
  @spec easter(Calendar.year()) :: Date.t()
  def easter(year), do: Ecclesiastical.easter_sunday(year)

  @doc "Easter Sunday of a Gregorian year, as the Orthodox churches reckon it."
  @spec orthodox_easter(Calendar.year()) :: Date.t()
  def orthodox_easter(year), do: Ecclesiastical.orthodox_easter_sunday(year)

  # ── The day scale ─────────────────────────────────────────────────────

  @doc """
  The years after which a calendar's dates and weekdays come round again:
  four hundred in the Gregorian calendar. Nil for a calendar with no such
  cycle.
  """
  @spec years_in_cycle(module()) :: pos_integer() | nil
  def years_in_cycle(calendar), do: cycle_or_none(impl(calendar).years_in_cycle())

  defp cycle_or_none(years) when is_integer(years), do: years
  defp cycle_or_none(_none), do: nil

  @doc "The day number of a date."
  @spec iso_days(module(), Calendar.year(), Calendar.month(), Calendar.day()) :: integer()
  # The default calendar's day numbers are its own, as Elixir reckons them:
  # what its module in Localize answers, more directly.
  def iso_days(Calendar.ISO, year, month, day),
    do: Calendar.ISO.date_to_iso_days(year, month, day)

  def iso_days(calendar, year, month, day), do: impl(calendar).date_to_iso_days(year, month, day)

  @doc "The date of a day number."
  @spec date(module(), integer()) :: date()
  def date(Calendar.ISO, days), do: Calendar.ISO.date_from_iso_days(days)

  def date(calendar, days) do
    case impl(calendar).date_from_iso_days(days) do
      {year, month, day} -> {year, month, day}
      %{year: year, month: month, day: day} -> {year, month, day}
    end
  end

  @doc "Whether a date exists."
  @spec valid_date?(module(), Calendar.year(), Calendar.month(), Calendar.day()) :: boolean()
  def valid_date?(Calendar.ISO, year, month, day), do: Calendar.ISO.valid_date?(year, month, day)
  def valid_date?(calendar, year, month, day), do: impl(calendar).valid_date?(year, month, day)

  # ── Periods as spans of days ──────────────────────────────────────────

  @doc """
  The span of a period: a year, a month, a week of the calendar's own
  week-year, or a quarter. `{:error, reason}` for a period the calendar does
  not have.
  """
  @spec period(module(), period(), integer(), integer() | nil) :: {:ok, span()} | {:error, term()}
  def period(calendar, :year, year, nil), do: span(calendar, impl(calendar).year(year))
  def period(calendar, :month, year, month), do: span(calendar, impl(calendar).month(year, month))
  def period(calendar, :week, year, week), do: span(calendar, impl(calendar).week(year, week))

  def period(calendar, :quarter, year, quarter),
    do: span(calendar, impl(calendar).quarter(year, quarter))

  @doc "The spans of the weeks a month has, in order; a week may begin before the month or end after it."
  @spec weeks_of_month(module(), Calendar.year(), Calendar.month()) ::
          {:ok, [span()]} | {:error, term()}
  def weeks_of_month(calendar, year, month) do
    case impl(calendar).weeks_of_month(year, month) do
      {:error, _} = error ->
        error

      ranges ->
        {:ok,
         Enum.map(ranges, fn range ->
           {:ok, span} = span(calendar, range)
           span
         end)}
    end
  end

  defp span(calendar, %Date.Range{first: first, last: last}) do
    {:ok,
     {iso_days(calendar, first.year, first.month, first.day),
      iso_days(calendar, last.year, last.month, last.day) + 1}}
  end

  defp span(_calendar, {:error, _} = error), do: error

  # ── Labels of a date ──────────────────────────────────────────────────

  @doc """
  The day of the week as the calendar numbers it: 1 is the day its weeks
  begin on (decision 80), Monday for the Gregorian calendar, Sunday for the
  Hebrew, the day named for a week start written `[u-fw=…]`.
  """
  @spec day_of_week(module(), Calendar.year(), Calendar.month(), Calendar.day()) :: 1..7
  def day_of_week(calendar, year, month, day) do
    {day_of_week, _first, _last} = impl(calendar).day_of_week(year, month, day, :default)
    day_of_week
  end

  @doc "The day of the week as ISO 8601 numbers it, 1 (Monday) to 7 (Sunday), whatever the calendar's weeks."
  @spec iso_weekday(module(), Calendar.year(), Calendar.month(), Calendar.day()) :: 1..7
  def iso_weekday(calendar, year, month, day) do
    {weekday, _first, _last} = impl(calendar).day_of_week(year, month, day, :monday)
    weekday
  end

  @doc "The ISO 8601 day of the week, 1 (Monday) to 7, a calendar's weeks begin on."
  @spec first_weekday(module()) :: 1..7
  def first_weekday(calendar) do
    key = {__MODULE__, :first_weekday, calendar}
    known = :persistent_term.get(key, nil)

    if is_nil(known) do
      first = first_weekday_asked(calendar)
      :persistent_term.put(key, first)
      first
    else
      known
    end
  end

  # The two numberings of one day differ by the same count on every day, a
  # week being a cycle of the days, so any day will do.
  defp first_weekday_asked(calendar) do
    {year, month, day} = date(calendar, @any_day)
    own = day_of_week(calendar, year, month, day)
    iso = iso_weekday(calendar, year, month, day)
    Integer.mod(iso - own, @iso_weekdays) + 1
  end

  @doc "The calendar's number for an ISO 8601 day of the week: Friday is 6 where weeks begin on Sunday."
  @spec day_of_week_from_iso(module(), 1..7) :: 1..7
  def day_of_week_from_iso(calendar, iso_weekday) do
    Integer.mod(iso_weekday - first_weekday(calendar), @iso_weekdays) + 1
  end

  @doc """
  The calendar's number for a day of the week by its name, `:monday` to
  `:sunday`: `:friday` is 5 where weeks begin on Monday and 6 where they
  begin on Sunday.
  """
  @spec day_of_week_named(module(), atom()) :: {:ok, 1..7} | :error
  def day_of_week_named(calendar, name) do
    case Enum.find_index(@weekday_names, &(&1 == name)) do
      nil -> :error
      index -> {:ok, day_of_week_from_iso(calendar, index + 1)}
    end
  end

  @doc "The ISO 8601 day of the week of the calendar's numbered day: day 6 is Friday where weeks begin on Sunday."
  @spec iso_weekday_from_day_of_week(module(), 1..7) :: 1..7
  def iso_weekday_from_day_of_week(calendar, day_of_week) do
    Integer.mod(day_of_week + first_weekday(calendar) - 2, @iso_weekdays) + 1
  end

  @doc "The week-year and week of a date in the calendar's own weeks."
  @spec week_of_year(module(), Calendar.year(), Calendar.month(), Calendar.day()) ::
          {:ok, {integer(), pos_integer()}} | {:error, term()}
  def week_of_year(calendar, year, month, day) do
    case impl(calendar).week_of_year(year, month, day) do
      {:error, _} = error -> error
      {week_year, week} -> {:ok, {week_year, week}}
    end
  end

  @doc "The day of the year of a date, counted from the year's first day on the day scale."
  @spec day_of_year(module(), Calendar.year(), Calendar.month(), Calendar.day()) ::
          {:ok, pos_integer()} | {:error, term()}
  def day_of_year(calendar, year, month, day) do
    with {:ok, {first, _}} <- period(calendar, :year, year, nil) do
      {:ok, iso_days(calendar, year, month, day) - first + 1}
    end
  end

  @doc "A month as the calendar names it: its traditional number, or `{month, :leap}`."
  @spec traditional_month(module(), Calendar.year(), Calendar.month()) ::
          Calendar.month() | {Calendar.month(), :leap} | {:error, term()}
  def traditional_month(calendar, year, month), do: impl(calendar).traditional_month(year, month)

  @doc "The ordinal month a traditional month names."
  @spec month_from_traditional(
          module(),
          Calendar.year(),
          Calendar.month() | {Calendar.month(), :leap}
        ) :: Calendar.month() | {:error, term()}
  def month_from_traditional(calendar, year, named),
    do: impl(calendar).month_from_traditional(year, named)

  # ── Arithmetic the calendar owns ──────────────────────────────────────

  @doc "A date moved by a duration of years, months, weeks and days: years, then months, then the day clamped, then days."
  @spec shift_date(module(), Calendar.year(), Calendar.month(), Calendar.day(), Duration.t()) ::
          date()
  def shift_date(calendar, year, month, day, %Duration{} = duration) do
    impl(calendar).shift_date(year, month, day, duration)
  end

  # ── Bounds with no year ───────────────────────────────────────────────

  @doc "The fewest and the most months a year has."
  @spec months_in_year_bounds(module()) :: {pos_integer(), pos_integer()} | {:error, term()}
  def months_in_year_bounds(calendar), do: impl(calendar).months_in_year_bounds()

  @doc "The fewest and the most days a month has in any year."
  @spec days_in_month_bounds(module(), Calendar.month()) ::
          {pos_integer(), pos_integer()} | {:error, term()}
  def days_in_month_bounds(calendar, month), do: impl(calendar).days_in_month_bounds(month)

  # ── Names ─────────────────────────────────────────────────────────────

  @doc "The calendar's CLDR type, for IXDTF and for Localize."
  @spec type(module()) :: atom()
  def type(calendar), do: impl(calendar).cldr_calendar_type()

  @doc """
  The IXDTF `u-ca` identifier that names a calendar: Calendrical's own name
  for one of its additional calendars (`iso-week`, `julian`), else the
  calendar's CLDR type (`hebrew`). `Calendar.ISO` needs none. A calendar no
  name reads back to, such as a fiscal calendar, has none and is an error.

  ### Examples

      iex> Tempo.Calendar.identifier(Calendrical.Hebrew)
      {:ok, "hebrew"}

      iex> Tempo.Calendar.identifier(Calendrical.ISOWeek)
      {:ok, "iso-week"}

      iex> Tempo.Calendar.identifier(Calendar.ISO)
      {:ok, nil}

  """
  @spec identifier(module()) :: {:ok, String.t() | nil} | {:error, Exception.t()}
  def identifier(Calendar.ISO), do: {:ok, nil}

  # The Gregorian calendar with its weeks begun on another day is named by
  # that day (`[u-fw=sun]`), and needs no name as a calendar.
  def identifier(calendar) when is_map_key(@week_starts, calendar), do: {:ok, nil}

  def identifier(calendar) do
    additional =
      Enum.find_value(Calendrical.additional_calendars(), fn {name, module} ->
        if module == calendar, do: name |> Atom.to_string() |> String.replace("_", "-")
      end)

    case {additional, type(calendar)} do
      {name, _type} when is_binary(name) -> {:ok, name}
      {nil, :generic} -> {:error, InvalidCalendarError.exception(calendar: calendar)}
      {nil, type} -> named(calendar, type)
    end
  end

  # A CLDR type names a calendar only when it reads back to it: a fiscal
  # calendar's type is `gregorian`, which names another calendar, so it has
  # no identifier and a value in it no text.
  defp named(calendar, type) do
    if from_type(type) == {:ok, calendar},
      do: {:ok, type |> Atom.to_string() |> String.replace("_", "-")},
      else: {:error, InvalidCalendarError.exception(calendar: calendar)}
  end

  @doc "The calendar an IXDTF `u-ca` name or a CLDR type names; `iso8601` is `Calendar.ISO`."
  @spec from_type(atom() | String.t()) :: {:ok, module()} | {:error, Exception.t()}
  def from_type(type) when type in [:iso8601, "iso8601"], do: {:ok, Calendar.ISO}
  def from_type(type), do: Calendrical.calendar_from_cldr_calendar_type(type)

  # ── Accessors the public API forwards ─────────────────────────────────

  @doc "Whether a year is a leap year, as the calendar counts them."
  @spec leap_year?(module(), Calendar.year()) :: boolean()
  def leap_year?(calendar, year), do: impl(calendar).leap_year?(year)

  @doc "The quarter of a date."
  @spec quarter_of_year(module(), Calendar.year(), Calendar.month(), Calendar.day()) :: 1..4
  def quarter_of_year(calendar, year, month, day),
    do: impl(calendar).quarter_of_year(year, month, day)

  @doc "The days a month has."
  @spec days_in_month(module(), Calendar.year(), Calendar.month()) :: Calendar.day()
  def days_in_month(calendar, year, month), do: impl(calendar).days_in_month(year, month)

  @doc "The months a year has."
  @spec months_in_year(module(), Calendar.year()) :: Calendar.month()
  def months_in_year(calendar, year), do: impl(calendar).months_in_year(year)

  @doc "The weeks in a year of the calendar's own week system."
  @spec weeks_in_year(module(), Calendar.year()) :: pos_integer() | {:error, term()}
  def weeks_in_year(calendar, year) do
    case impl(calendar).weeks_in_year(year) do
      {:error, _} = error -> error
      {weeks, _days_in_last_week} -> weeks
      weeks when is_integer(weeks) -> weeks
    end
  end

  @doc "The days in a year."
  @spec days_in_year(module(), Calendar.year()) :: pos_integer() | {:error, term()}
  def days_in_year(calendar, year), do: impl(calendar).days_in_year(year)

  @doc "The days in a week of the calendar."
  @spec days_in_week(module()) :: pos_integer()
  def days_in_week(calendar), do: impl(calendar).days_in_week()

  # ── Derived here, never asked ─────────────────────────────────────────

  @doc """
  The first day of what a value's date units name: a year, a month, a
  date, a week, a week date or a day of the year. The units are concrete
  and coarsest first.
  """
  @spec first_day(module(), Tempo.Unit.units()) :: {:ok, integer()} | {:error, term()}
  def first_day(calendar, year: year, month: month, day: day) do
    if valid_date?(calendar, year, month, day),
      do: {:ok, iso_days(calendar, year, month, day)},
      else: {:error, :invalid_date}
  end

  def first_day(calendar, year: year, month: month),
    do: first_of(period(calendar, :month, year, month))

  def first_day(calendar, year: year), do: first_of(period(calendar, :year, year, nil))

  def first_day(calendar, year: year, week: week),
    do: first_of(period(calendar, :week, year, week))

  # The nth day of the week's own days, whatever day the calendar's week begins on.
  def first_day(calendar, year: year, week: week, day_of_week: day_of_week) do
    with {:ok, {first, after_last}} <- period(calendar, :week, year, week) do
      if day_of_week in 1..(after_last - first)//1,
        do: {:ok, first + day_of_week - 1},
        else: {:error, :invalid_date}
    end
  end

  def first_day(calendar, year: year, month: month, week: week),
    do: first_of(month_week(calendar, year, month, week))

  def first_day(calendar, year: year, month: month, week: week, day_of_week: day_of_week) do
    with {:ok, {first, after_last}} <- month_week(calendar, year, month, week) do
      if day_of_week in 1..(after_last - first)//1,
        do: {:ok, first + day_of_week - 1},
        else: {:error, :invalid_date}
    end
  end

  def first_day(calendar, year: year, day_of_year: day_of_year) do
    case period(calendar, :year, year, nil) do
      {:ok, {first, after_last}} when day_of_year >= 1 and first + day_of_year - 1 < after_last ->
        {:ok, first + day_of_year - 1}

      {:ok, _span} ->
        {:error, :invalid_date}

      {:error, _} = error ->
        error
    end
  end

  def first_day(_calendar, _units), do: {:error, :no_date}

  @doc """
  The month a day number falls in: the span of its days, its year and month,
  the label of its first day, and whether its labels count its days (the
  last day's label is the first's plus the days between). A month that
  leaves labels out as a calendar changes (England, September 1752) does
  not count them, and each day's label is then asked of the calendar.
  """
  @spec month_of_day(module(), integer()) :: %{
          first: integer(),
          after_last: integer(),
          year: Calendar.year(),
          month: Calendar.month(),
          label: Calendar.day(),
          counts?: boolean()
        }
  def month_of_day(calendar, day) do
    {year, month, label} = date(calendar, day)
    {:ok, {first, after_last}} = period(calendar, :month, year, month)

    {_year, _month, first_label} =
      if day == first, do: {year, month, label}, else: date(calendar, first)

    {_year, _month, last_label} = date(calendar, after_last - 1)

    %{
      first: first,
      after_last: after_last,
      year: year,
      month: month,
      label: first_label,
      counts?: last_label == first_label + (after_last - first) - 1
    }
  end

  @doc "The span of the year a day number falls in."
  @spec year_of_day(module(), integer()) :: span()
  def year_of_day(calendar, day) do
    {year, _month, _day} = date(calendar, day)
    {:ok, span} = period(calendar, :year, year, nil)
    span
  end

  @doc "The span of days a value's date units name, by the same reading as `first_day/2`; a date is one day."
  @spec span_of(module(), Tempo.Unit.units()) :: {:ok, span()} | {:error, term()}
  def span_of(calendar, year: year), do: period(calendar, :year, year, nil)
  def span_of(calendar, year: year, month: month), do: period(calendar, :month, year, month)
  def span_of(calendar, year: year, week: week), do: period(calendar, :week, year, week)

  def span_of(calendar, year: year, month: month, week: week),
    do: month_week(calendar, year, month, week)

  def span_of(calendar, units) do
    with {:ok, first} <- first_day(calendar, units), do: {:ok, {first, first + 1}}
  end

  # The nth week of a month, of the weeks the month has (`weeks_of_month/3`).
  defp month_week(calendar, year, month, week) do
    with {:ok, weeks} <- weeks_of_month(calendar, year, month) do
      case Enum.at(weeks, week - 1) do
        nil -> {:error, :invalid_date}
        span when week >= 1 -> {:ok, span}
        _span -> {:error, :invalid_date}
      end
    end
  end

  defp first_of({:ok, {first, _after_last}}), do: {:ok, first}
  defp first_of({:error, _} = error), do: error
end
