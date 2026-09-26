defmodule Tempo.Iso8601.Group do
  @moduledoc false

  alias Calendrical.Gregorian
  alias Tempo.InvalidDateError
  alias Tempo.Iso8601.Group
  alias Tempo.Iso8601.Parser
  alias Tempo.Math
  alias Tempo.ParseError

  @hours_per_day 24

  # This module expands groups into base time units. For example, it
  # expands:
  #  * quarters, quadrimesters and semesters, into the months (or, in a
  #    week-based calendar, the weeks) the calendar's periods span
  #  * groups of a unit (`2G3MU`), into the range of values they cover
  #  * seasons, astronomical and meteorological

  def expand_groups(tempo, calendar \\ Calendrical.Gregorian)

  # A value is grouped in its own calendar, so a Hebrew quarter holds the
  # Hebrew months Calendrical puts in it.
  def expand_groups(%Tempo{time: time} = tempo, calendar) do
    case expand_groups(time, tempo.calendar || calendar) do
      {:error, reason} -> {:error, reason}
      %Tempo.Interval{} = interval -> {:ok, interval}
      time -> {:ok, %{tempo | time: time}}
    end
  end

  def expand_groups(%Tempo.Duration{time: time} = tempo, calendar) do
    case expand_groups(time, calendar) do
      {:error, reason} -> {:error, reason}
      time -> {:ok, %{tempo | time: time}}
    end
  end

  def expand_groups(%Tempo.Interval{} = tempo, calendar) do
    with {:ok, from} <- expand_groups(tempo.from, calendar),
         {:ok, to} <- expand_groups(tempo.to, calendar),
         {:ok, duration} <- expand_groups(tempo.duration, calendar) do
      {:ok, %{tempo | from: from, to: to, duration: duration}}
    end
  end

  def expand_groups(%Tempo.Set{set: set} = tempo, calendar) do
    expanded =
      Enum.reduce_while(set, [], fn elem, acc ->
        case expand_groups(elem, calendar) do
          {:error, reason} -> {:halt, {:error, reason}}
          {:ok, tempo} -> {:cont, [tempo | acc]}
        end
      end)

    case expanded do
      {:error, reason} -> {:error, reason}
      expanded -> {:ok, %{tempo | set: Enum.reverse(expanded)}}
    end
  end

  def expand_groups(nil, _calendar) do
    {:ok, nil}
  end

  def expand_groups(:undefined, _calendar) do
    {:ok, :undefined}
  end

  def expand_groups(%Tempo.Range{first: first, last: last}, calendar) do
    with {:ok, first} <- expand_groups(first, calendar),
         {:ok, last} <- expand_groups(last, calendar) do
      {:ok, %Tempo.Range{first: first, last: last}}
    end
  end

  # Seasons (ISO 8601-2 Part 2, Table 2)
  #
  # Codes 25-32 are **astronomical** seasons: the boundaries are the
  # March and September equinoxes and the June and December solstices
  # as computed by the `Astro` library (accurate to ~2 minutes for
  # years 1000..3000 CE).
  #
  # * 25 = Spring (Northern) / 31 = Autumn (Southern) — March equinox → June solstice
  # * 26 = Summer (Northern) / 32 = Winter (Southern) — June solstice → September equinox
  # * 27 = Autumn (Northern) / 29 = Spring (Southern) — September equinox → December solstice
  # * 28 = Winter (Northern) / 30 = Summer (Southern) — December solstice (year Y) → March equinox (year Y+1)
  #
  # Codes 21-24 are generic (hemisphere-unspecified) seasons and are
  # handled separately as meteorological approximations; see the
  # clauses below.

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in [25, 31] do
    astronomical_season(year, rest, calendar, :march, :june)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in [26, 32] do
    astronomical_season(year, rest, calendar, :june, :september)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in [27, 29] do
    astronomical_season(year, rest, calendar, :september, :december)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in [28, 30] do
    astronomical_season(year, rest, calendar, :december, :march_next)
  end

  # Meteorological seasons 21-24 (hemisphere-unspecified — we default to
  # Northern hemisphere meteorological boundaries as a conventional
  # interpretation).

  def expand_groups([{:year, year}, {:month, 21} | rest], calendar) do
    meteorological_season(year, rest, calendar, 3, 5)
  end

  def expand_groups([{:year, year}, {:month, 22} | rest], calendar) do
    meteorological_season(year, rest, calendar, 6, 8)
  end

  def expand_groups([{:year, year}, {:month, 23} | rest], calendar) do
    meteorological_season(year, rest, calendar, 9, 11)
  end

  def expand_groups([{:year, year}, {:month, 24}, {:day, day} | rest], _calendar) do
    # Winter runs from December 1 of the previous year to March 1.
    with {:ok, start_date} <- season_date(year - 1, 12),
         {:ok, end_date} <- season_date(year, 3) do
      season_day(start_date, end_date, day, rest)
    end
  end

  def expand_groups([{:year, year}, {:month, 24} | rest], calendar) do
    # Winter: December of previous year through February of this year.
    season_interval(
      [{:year, year - 1}, {:month, 12} | rest],
      [{:year, year}, {:month, 2} | rest],
      calendar
    )
  end

  # The ISO 8601-2 sub-year divisions (codes 33–41): quarters,
  # quadrimesters and semesters are the calendar's own periods, as
  # Calendrical spans them. A leap month is in the period of the month it
  # repeats and a thirteenth month in the last period; a week-based
  # calendar's periods are runs of weeks.
  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 33..36 do
    expand_year_division([{:year, year} | rest], :quarter, month - 32, calendar)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 37..39 do
    expand_year_division([{:year, year} | rest], :quadrimester, month - 36, calendar)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 40..41 do
    expand_year_division([{:year, year} | rest], :semester, month - 39, calendar)
  end

  # The `nth` group of `size` units covers the values from the unit's
  # first, so the second group of three months is months 4..6 and the
  # third group of eight hours is hours 16..23.
  def expand_groups([{:group, [{:nth, nth}, {unit, size}]} | rest], calendar)
      when is_integer(nth) and is_integer(size) do
    first = (nth - 1) * size + Math.unit_minimum(unit)
    last = first + size - 1

    expand_groups([{unit, {:group, first..last//1}} | rest], calendar)
  end

  def expand_groups([{:group, [{:all_of, set}, {unit, value}]} | rest], calendar) do
    prepend({unit, {:group, {:all, set}}, value}, expand_groups(rest, calendar))
  end

  def expand_groups([{:group, [{:one_of, set}, {unit, value}]} | rest], calendar) do
    prepend({unit, {:group, {:one, set}}, value}, expand_groups(rest, calendar))
  end

  # TODO implement complex groups
  def expand_groups([{:group, group} | _rest], _calendar) do
    {:error,
     ParseError.exception(reason: "Complex groupings not yet supported. Found #{inspect(group)}")}
  end

  def expand_groups([first | rest], calendar) do
    prepend(first, expand_groups(rest, calendar))
  end

  def expand_groups(other, _calendar) do
    other
  end

  # An error expanding the rest of the list is the list's error.
  defp prepend(_first, {:error, _reason} = error), do: error
  defp prepend(first, time), do: [first | time]

  ## Sub-year divisions

  defp expand_year_division([{:year, year} | rest], division, number, calendar) do
    case year_division_group(calendar, year, division, number) do
      {:ok, group} ->
        expand_groups([{:year, year}, group | rest], calendar)

      {:error, reason} ->
        {:error, year_division_error(reason, year, division, number, calendar)}
    end
  end

  @doc false
  # The `number`th `division` (`:quarter`, `:quadrimester` or `:semester`)
  # of `year` as the group of months the calendar's period spans, or of
  # weeks in a week-based calendar.
  @spec year_division_group(module(), integer(), :quarter | :quadrimester | :semester, integer()) ::
          {:ok, {:month | :week, {:group, Range.t()}}} | {:error, :not_defined | :invalid_date}
  def year_division_group(calendar, year, division, number) do
    with {:ok, %Date.Range{first: first, last: last}} <-
           year_division_date_range(calendar, year, division, number) do
      {:ok, {year_division_unit(calendar), {:group, first.month..last.month//1}}}
    end
  end

  @doc false
  # The exception for a division `year_division_group/4` could not place.
  @spec year_division_error(atom(), integer(), atom(), integer(), module()) :: Exception.t()
  def year_division_error(:not_defined, _year, division, _number, calendar) do
    InvalidDateError.exception(
      reason: "#{inspect(calendar)} does not divide its year into #{division}s"
    )
  end

  def year_division_error(_reason, year, division, number, calendar) do
    InvalidDateError.exception(
      reason: "#{number} is not a #{division} of #{year} in #{inspect(calendar)}"
    )
  end

  defp year_division_date_range(calendar, year, division, number) do
    if Code.ensure_loaded?(calendar) and function_exported?(calendar, division, 2) do
      calendar
      |> apply(division, [year, number])
      |> year_division_date_range_result()
    else
      {:error, :not_defined}
    end
  end

  defp year_division_date_range_result(%Date.Range{} = range), do: {:ok, range}
  defp year_division_date_range_result({:error, reason}), do: {:error, reason}

  # A week-based calendar numbers its weeks in the date's `month` field.
  defp year_division_unit(calendar) do
    if function_exported?(calendar, :calendar_base, 0) and calendar.calendar_base() == :week,
      do: :week,
      else: :month
  end

  ## The container of a group

  @doc false
  # A group keeps the values its `nGsizeU` declares, so it renders as it
  # was written, and is bounded by its container where it is used: the
  # last group of eleven days in February (`2018Y2M3G11DU`, days 23..33)
  # runs to the 28th. A group that starts beyond its container, such as
  # months 13..15 of a twelve-month year, is an error.
  @spec bound_groups(list(), module()) :: {:ok, list()} | {:error, Exception.t()}
  def bound_groups(time, calendar) when is_list(time) do
    time
    |> Enum.reduce_while({:ok, []}, fn component, {:ok, prefix} ->
      case bound_group(component, Enum.reverse(prefix), calendar) do
        {:ok, bounded} -> {:cont, {:ok, [bounded | prefix]}}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
    |> bound_groups_result()
  end

  def bound_groups(other, _calendar), do: {:ok, other}

  defp bound_groups_result({:ok, reversed}), do: {:ok, Enum.reverse(reversed)}
  defp bound_groups_result({:error, _exception} = error), do: error

  defp bound_group(
         {unit, {:group, %Range{first: first, last: last}}} = component,
         prefix,
         calendar
       ) do
    case container_maximum(prefix, unit, calendar) do
      nil ->
        {:ok, component}

      maximum when first <= maximum ->
        {:ok, {unit, {:group, first..min(last, maximum)//1}}}

      maximum ->
        {:error,
         InvalidDateError.exception(
           unit: unit,
           value: first,
           valid_range: Math.unit_minimum(unit)..maximum//1,
           calendar: calendar
         )}
    end
  end

  defp bound_group(component, _prefix, _calendar), do: {:ok, component}

  @doc false
  # The largest value `unit` takes within `prefix`, the components before
  # it, or `nil` when they do not bound it (a group of years, or a
  # container that is itself a set or a mask).
  @spec container_maximum(list(), atom(), module()) :: integer() | nil
  def container_maximum(prefix, unit, calendar) do
    if Enum.all?(prefix, &integer_component?/1) do
      prefix
      |> Keyword.keys()
      |> container_unit(unit)
      |> maximum_within(unit, Map.new(prefix), calendar)
    end
  end

  defp integer_component?({_unit, value}), do: is_integer(value)
  defp integer_component?(_component), do: false

  # The unit a group's unit counts within, when the components before it
  # name one: days count within a month, a week, or (alone with a year)
  # the year, and hours within a day or (alone with a year) the year.
  defp container_unit(units, unit) when unit in [:month, :week] do
    if :year in units, do: :year
  end

  defp container_unit(units, :day) do
    cond do
      :month in units -> :month
      :week in units -> :week
      units == [:year] -> :year
      true -> nil
    end
  end

  defp container_unit(units, :day_of_week), do: if(:week in units, do: :week)

  defp container_unit(units, :hour) do
    cond do
      :day in units -> :day
      units == [:year] -> :year
      true -> nil
    end
  end

  defp container_unit(units, :minute), do: if(:hour in units, do: :hour)
  defp container_unit(units, :second), do: if(:minute in units, do: :minute)
  defp container_unit(_units, _unit), do: nil

  defp maximum_within(:year, :month, %{year: year}, calendar), do: calendar.months_in_year(year)

  defp maximum_within(:year, :week, %{year: year}, calendar),
    do: year |> calendar.weeks_in_year() |> elem(0)

  defp maximum_within(:year, :day, %{year: year}, calendar), do: calendar.days_in_year(year)

  defp maximum_within(:year, :hour, %{year: year}, calendar),
    do: calendar.days_in_year(year) * @hours_per_day - 1

  defp maximum_within(:month, :day, %{year: year, month: month}, calendar),
    do: calendar.days_in_month(year, month)

  defp maximum_within(:week, _unit, _prefix, calendar), do: calendar.days_in_week()
  defp maximum_within(:day, :hour, _prefix, _calendar), do: @hours_per_day - 1
  defp maximum_within(:hour, :minute, _prefix, _calendar), do: 59
  defp maximum_within(:minute, :second, _prefix, _calendar), do: 59
  defp maximum_within(_container_unit, _unit, _prefix, _calendar), do: nil

  ## Season helpers

  # Expand an astronomical season into an interval whose boundaries
  # are the relevant equinox or solstice dates. The boundaries are
  # inclusive on the lower end and exclusive on the upper end
  # (matching the half-open `[first, last)` convention).
  defp astronomical_season(year, rest, calendar, start_event, :march_next) do
    with {:ok, start_date} <- season_boundary_date(year, start_event),
         {:ok, end_date} <- season_boundary_date(year + 1, :march) do
      astronomical_span(start_date, end_date, rest, calendar)
    end
  end

  defp astronomical_season(year, rest, calendar, start_event, end_event) do
    with {:ok, start_date} <- season_boundary_date(year, start_event),
         {:ok, end_date} <- season_boundary_date(year, end_event) do
      astronomical_span(start_date, end_date, rest, calendar)
    end
  end

  # ISO 8601-2 writes a season only as a year and month; a day after one
  # is its nth day, as a day after a quarter or a semester is.
  defp astronomical_span(start_date, end_date, [{:day, day} | rest], _calendar) do
    season_day(start_date, end_date, day, rest)
  end

  defp astronomical_span(start_date, end_date, rest, calendar) do
    build_season_interval(start_date, end_date, rest, calendar)
  end

  # The day Calendrical's arithmetic reaches `day - 1` days after the
  # season's first day, provided it falls before the season ends. Season
  # boundaries are Gregorian dates.
  defp season_day(%Date{} = start_date, %Date{} = end_date, day, rest)
       when is_integer(day) and day >= 1 do
    {year, month, day_of_month} =
      Gregorian.plus(start_date.year, start_date.month, start_date.day, :days, day - 1)

    season_date_before(Date.new(year, month, day_of_month), end_date, day, rest)
  end

  defp season_day(_start_date, end_date, day, _rest), do: season_day_error(day, end_date)

  defp season_date_before({:ok, date}, end_date, day, rest) do
    case Date.compare(date, end_date) do
      :lt -> [{:year, date.year}, {:month, date.month}, {:day, date.day} | rest]
      _on_or_after -> season_day_error(day, end_date)
    end
  end

  defp season_date_before({:error, _reason}, end_date, day, _rest),
    do: season_day_error(day, end_date)

  defp season_day_error(day, end_date) do
    {:error,
     InvalidDateError.exception(
       reason: "Day #{inspect(day)} of the season is not before its end, #{end_date}"
     )}
  end

  # The first day of a month of a meteorological season, or of the month
  # after one.
  defp season_date(year, month) do
    case Date.new(year, month, 1) do
      {:ok, date} ->
        {:ok, date}

      {:error, _reason} ->
        {:error, InvalidDateError.exception(reason: "#{year}-#{month} has no season date")}
    end
  end

  defp month_after(year, month) do
    {next_year, next_month, _day} = Gregorian.plus(year, month, 1, :months, 1)
    season_date(next_year, next_month)
  end

  defp season_boundary_date(year, event) when event in [:march, :september] do
    year |> Astro.equinox(event) |> season_boundary(year, event)
  end

  defp season_boundary_date(year, event) when event in [:june, :december] do
    year |> Astro.solstice(event) |> season_boundary(year, event)
  end

  defp season_boundary({:ok, %DateTime{} = datetime}, _year, _event) do
    {:ok, DateTime.to_date(datetime)}
  end

  # Astro computes equinoxes and solstices for a bounded span of years
  # and returns `{:error, :year_out_of_range}` beyond it.
  defp season_boundary({:error, reason}, year, event) do
    {:error,
     ParseError.exception(
       reason:
         "The #{boundary_name(event)} of #{year}, which bounds this season, " <>
           "cannot be computed (#{inspect(reason)})"
     )}
  end

  defp boundary_name(:march), do: "March equinox"
  defp boundary_name(:june), do: "June solstice"
  defp boundary_name(:september), do: "September equinox"
  defp boundary_name(:december), do: "December solstice"

  defp build_season_interval(%Date{} = start_date, %Date{} = end_date, rest, calendar) do
    season_interval(
      [{:year, start_date.year}, {:month, start_date.month}, {:day, start_date.day} | rest],
      [{:year, end_date.year}, {:month, end_date.month}, {:day, end_date.day} | rest],
      calendar
    )
  end

  # A day of the season is its nth day, reached as after an astronomical
  # season.
  defp meteorological_season(year, [{:day, day} | rest], _calendar, start_month, end_month) do
    with {:ok, start_date} <- season_date(year, start_month),
         {:ok, end_date} <- month_after(year, end_month) do
      season_day(start_date, end_date, day, rest)
    end
  end

  defp meteorological_season(year, rest, calendar, start_month, end_month) do
    season_interval(
      [{:year, year}, {:month, start_month} | rest],
      [{:year, year}, {:month, end_month} | rest],
      calendar
    )
  end

  # The interval between a season's boundaries, or the error building
  # it returns.
  defp season_interval(from, to, calendar) do
    [interval: [datetime: from, datetime: to]]
    |> Parser.parse()
    |> Group.expand_groups(calendar)
    |> season_interval_result()
  end

  defp season_interval_result({:ok, interval}), do: interval
  defp season_interval_result({:error, _reason} = error), do: error
end
