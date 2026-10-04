defmodule Tempo.Iso8601.Group do
  @moduledoc false

  alias Calendrical.Gregorian
  alias Tempo.Compare
  alias Tempo.InvalidDateError
  alias Tempo.Iso8601.Group
  alias Tempo.Iso8601.Parser
  alias Tempo.Math
  alias Tempo.ParseError
  alias Tempo.UnitValues
  alias Tempo.Validation

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

  # A duration's units are counts, not a date's: twenty-one months are not
  # the season a date's month 21 is, and `P1Y21M` is a year and twenty-one
  # months. It holds no group to expand.
  def expand_groups(%Tempo.Duration{} = duration, _calendar), do: {:ok, duration}

  def expand_groups(%Tempo.Interval{} = tempo, calendar) do
    with {:ok, from} <- expand_groups(tempo.from, calendar),
         {:ok, to} <- expand_groups(tempo.to, calendar),
         {:ok, duration} <- expand_groups(tempo.duration, calendar) do
      {:ok, %{tempo | from: from, to: to, duration: duration}}
    end
  end

  def expand_groups(%Tempo.Set{set: set, except: except} = tempo, calendar) do
    with {:ok, set} <- expand_members(set, calendar),
         {:ok, except} <- expand_members(except, calendar) do
      {:ok, %{tempo | set: set, except: except}}
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
  #
  # The seasons are Gregorian. A year in another calendar takes the
  # season of that kind that starts within it (the first, should the year
  # hold two), with its endpoints in that calendar; a year that holds
  # none, as a 354-day Islamic year can, is an error.

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 21..32 and calendar != Gregorian do
    calendar_season(year, month, rest, calendar)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 25..32 do
    with {:ok, start_date, end_date} <- gregorian_season(month, year) do
      astronomical_span(start_date, end_date, rest, calendar)
    end
  end

  # Meteorological seasons 21-24 (hemisphere-unspecified — we default to
  # Northern hemisphere meteorological boundaries as a conventional
  # interpretation): whole months, spring from March to the start of
  # June, and winter from the December before.

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 21..24 do
    with {:ok, start_date, end_date} <- gregorian_season(month, year) do
      meteorological_span(start_date, end_date, rest, calendar)
    end
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar) when month in 21..32 do
    unspecified_year_season(year, month, rest, calendar)
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

  # A calendar week (`w`, Tempo's extension) is a week of the calendar's own
  # numbering, as `W` is an ISO 8601 week. With a day of the week it is that
  # day's date; alone it is the span of its seven days. A week-based
  # calendar's own weeks are its ISO 8601 weeks.
  def expand_groups([{:year, year}, {:calendar_week, week} | rest], calendar)
      when is_integer(year) and is_integer(week) do
    calendar_week(year, week, rest, calendar)
  end

  def expand_groups([{:year, year}, {:calendar_week, week} | _rest], _calendar)
      when is_integer(year) do
    {:error,
     InvalidDateError.exception(reason: "A calendar week is a single week, not #{inspect(week)}")}
  end

  def expand_groups([{:year, _year}, {:calendar_week, week} | _rest], _calendar) do
    {:error,
     InvalidDateError.exception(
       reason: "Calendar week #{inspect(week)} needs a year with no unspecified digits"
     )}
  end

  def expand_groups([{:calendar_week, week} | _rest], _calendar) do
    {:error,
     InvalidDateError.exception(
       reason:
         "Calendar week #{inspect(week)} needs a year: the calendar numbers each year's weeks"
     )}
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

  # A set's members, and the members it excludes, each expand as a value does.
  defp expand_members(members, calendar) do
    members
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, expanded} ->
      case expand_groups(member, calendar) do
        {:ok, member} -> {:cont, {:ok, [member | expanded]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> reversed()
  end

  defp reversed({:ok, members}), do: {:ok, Enum.reverse(members)}
  defp reversed({:error, _reason} = error), do: error

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
  # The groups a group of a set names (`{1,2}G3MU`, `{1..-1}G3MU`), each as
  # the range of the unit's values it covers: the first and the second
  # groups of three months are `[1..3, 4..6]`. A group counted from the end
  # (`-1`, the last, or a range that runs to it) is counted in its
  # container, the components before it, and has no number where they do
  # not fix how many groups there are.
  @spec groups_of_set(atom(), [integer() | Range.t()], pos_integer(), list(), module()) ::
          {:ok, [Range.t()]} | {:error, {:unresolved, atom()}}
  def groups_of_set(unit, members, size, prefix, calendar) do
    minimum = Math.unit_minimum(unit)

    case group_numbers(members, group_count(prefix, unit, size, calendar)) do
      {:ok, numbers} -> {:ok, Enum.map(numbers, &group_range(&1, size, minimum))}
      :unresolved -> {:error, {:unresolved, unit}}
    end
  end

  # The values the `number`th group of `size` covers, counted from the
  # unit's first.
  defp group_range(number, size, minimum) do
    first = (number - 1) * size + minimum
    first..(first + size - 1)//1
  end

  # How many groups of `size` the container holds, the last of them short
  # where they do not divide it, or `nil` when the container is not fixed.
  defp group_count(prefix, unit, size, calendar) do
    case container_maximum(prefix, unit, calendar) do
      nil -> nil
      maximum -> div(maximum - Math.unit_minimum(unit) + size, size)
    end
  end

  defp group_numbers(members, count) do
    members
    |> Enum.reduce_while([], fn member, numbers ->
      case member_numbers(member, count) do
        :unresolved -> {:halt, :unresolved}
        found -> {:cont, [found | numbers]}
      end
    end)
    |> case do
      :unresolved -> :unresolved
      numbers -> {:ok, numbers |> Enum.reverse() |> Enum.concat()}
    end
  end

  defp member_numbers(number, _count) when is_integer(number) and number > 0, do: [number]
  defp member_numbers(number, nil) when is_integer(number), do: :unresolved
  defp member_numbers(number, count) when is_integer(number), do: [count + 1 + number]

  defp member_numbers(%Range{first: first, last: last, step: step}, _count)
       when first > 0 and last > 0,
       do: Enum.to_list(first..last//step)

  defp member_numbers(%Range{last: last}, nil) when last < 0, do: :unresolved

  defp member_numbers(%Range{first: first, last: last, step: step}, count) when last < 0,
    do: Enum.to_list(first..(count + 1 + last)//step)

  defp member_numbers(_other, _count), do: :unresolved

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
    do: Validation.iso_weeks_in_year(year, calendar)

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

  # A Gregorian season's first day and the day after its last, as the
  # Gregorian `year` labels it: the equinox and solstice dates of an
  # astronomical season (the half-open `[first, last)` convention), the
  # first days of the months of a meteorological one. A winter runs into
  # the next year, the meteorological one (24) from the year before.
  defp gregorian_season(code, year) when code in 21..23 do
    {start_month, end_month} = meteorological_months(code)
    meteorological_bounds(year, start_month, year, end_month)
  end

  defp gregorian_season(24, year), do: meteorological_bounds(year - 1, 12, year, 3)

  defp gregorian_season(code, year) when code in [25, 31],
    do: astronomical_bounds(year, :march, year, :june)

  defp gregorian_season(code, year) when code in [26, 32],
    do: astronomical_bounds(year, :june, year, :september)

  defp gregorian_season(code, year) when code in [27, 29],
    do: astronomical_bounds(year, :september, year, :december)

  defp gregorian_season(code, year) when code in [28, 30],
    do: astronomical_bounds(year, :december, year + 1, :march)

  defp meteorological_bounds(start_year, start_month, end_year, end_month) do
    with {:ok, start_date} <- season_date(start_year, start_month),
         {:ok, end_date} <- season_date(end_year, end_month) do
      {:ok, start_date, end_date}
    end
  end

  defp astronomical_bounds(start_year, start_event, end_year, end_event) do
    with {:ok, start_date} <- season_boundary_date(start_year, start_event),
         {:ok, end_date} <- season_boundary_date(end_year, end_event) do
      {:ok, start_date, end_date}
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

  defp season_day(start_date, end_date, day, rest) do
    with {:ok, date} <- nth_day_of_season(start_date, end_date, day) do
      [{:year, date.year}, {:month, date.month}, {:day, date.day} | rest]
    end
  end

  # The day Calendrical's arithmetic reaches `day - 1` days after the
  # season's first day, provided it falls before the season ends. Season
  # boundaries are Gregorian dates.
  defp nth_day_of_season(%Date{} = start_date, %Date{} = end_date, day)
       when is_integer(day) and day >= 1 do
    {year, month, day_of_month} =
      Gregorian.plus(start_date.year, start_date.month, start_date.day, :days, day - 1)

    season_date_before(Date.new(year, month, day_of_month), end_date, day)
  end

  defp nth_day_of_season(_start_date, end_date, day), do: season_day_error(day, end_date)

  defp season_date_before({:ok, date}, end_date, day) do
    case Compare.compare_days(date, end_date) do
      :lt -> {:ok, date}
      _on_or_after -> season_day_error(day, end_date)
    end
  end

  defp season_date_before({:error, _reason}, end_date, day),
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

  # The first month of a meteorological season and the month after its
  # last.
  defp meteorological_months(21), do: {3, 6}
  defp meteorological_months(22), do: {6, 9}
  defp meteorological_months(23), do: {9, 12}

  # A meteorological season runs over whole months; a day of the season is
  # its nth day, reached as after an astronomical season.
  defp meteorological_span(start_date, end_date, [{:day, day} | rest], _calendar) do
    season_day(start_date, end_date, day, rest)
  end

  defp meteorological_span(start_date, end_date, rest, calendar) do
    season_interval(
      [{:year, start_date.year}, {:month, start_date.month} | rest],
      [{:year, end_date.year}, {:month, end_date.month} | rest],
      calendar
    )
  end

  # A year with unspecified digits (`20XX-21`) keeps them in both bounds of
  # a spring, summer or autumn. A winter starts in the year before and an
  # astronomical season on the day its year's equinox or solstice falls,
  # so those, a day of any season, and a season in another calendar need
  # the year itself.
  defp unspecified_year_season(_year, code, [{:day, day} | _rest], _calendar) do
    {:error,
     InvalidDateError.exception(
       reason:
         "Day #{inspect(day)} of season #{code} cannot be placed in a year with unspecified digits"
     )}
  end

  defp unspecified_year_season(year, code, rest, Gregorian) when code in 21..23 do
    {start_month, end_month} = meteorological_months(code)

    season_interval(
      [{:year, year}, {:month, start_month} | rest],
      [{:year, year}, {:month, end_month} | rest],
      Gregorian
    )
  end

  defp unspecified_year_season(_year, code, _rest, calendar) do
    {:error,
     InvalidDateError.exception(
       reason:
         "Season #{code} cannot be placed in a year with unspecified digits in #{inspect(calendar)}"
     )}
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

  # The season `code` that starts within `year` of a calendar other than
  # the Gregorian, found among the Gregorian seasons of the years it
  # overlaps: its span, or its nth day, in that calendar.
  defp calendar_season(year, code, rest, calendar) do
    with {:ok, first, last} <- gregorian_year_bounds(year, calendar),
         {:ok, start_date, end_date} <- season_starting_within(code, first, last, year, calendar) do
      calendar_season_span(start_date, end_date, rest, calendar)
    end
  end

  # The first and last days of `year` of `calendar`, as Gregorian dates.
  defp gregorian_year_bounds(year, calendar) do
    with true <- Code.ensure_loaded?(calendar) and function_exported?(calendar, :year, 1),
         %Date.Range{first: first, last: last} <- Calendrical.Interval.year(year, calendar),
         {:ok, first} <- Date.convert(first, Gregorian),
         {:ok, last} <- Date.convert(last, Gregorian) do
      {:ok, first, last}
    else
      _other ->
        {:error,
         InvalidDateError.exception(
           reason: "#{inspect(calendar)} has no year #{year} to place a season in"
         )}
    end
  end

  # The seasons of one kind start in successive Gregorian years, so the
  # first to start on or after the year's first day starts within it if
  # any does. A winter (24) is labelled with the year it ends in, so the
  # labels run to the year after the last.
  defp season_starting_within(code, first, last, year, calendar) do
    first.year..(last.year + 1)//1
    |> Enum.reduce_while(:none, fn label, :none ->
      code |> gregorian_season(label) |> starting_within(first, last)
    end)
    |> season_found(code, year, calendar)
  end

  defp starting_within({:ok, start_date, _end_date} = season, first, last) do
    cond do
      Compare.compare_days(start_date, first) == :lt -> {:cont, :none}
      Compare.compare_days(start_date, last) == :gt -> {:halt, :none}
      true -> {:halt, season}
    end
  end

  defp starting_within({:error, _reason} = error, _first, _last), do: {:halt, error}

  defp season_found(:none, code, year, calendar) do
    {:error,
     InvalidDateError.exception(
       reason: "No season #{code} starts in #{year} of #{inspect(calendar)}"
     )}
  end

  defp season_found(found, _code, _year, _calendar), do: found

  defp calendar_season_span(start_date, end_date, [{:day, day} | rest], calendar) do
    with {:ok, date} <- nth_day_of_season(start_date, end_date, day) do
      calendar_date_components(date, rest, calendar)
    end
  end

  defp calendar_season_span(start_date, end_date, rest, calendar) do
    with from when is_list(from) <- calendar_date_components(start_date, rest, calendar),
         to when is_list(to) <- calendar_date_components(end_date, rest, calendar) do
      [interval: [datetime: from, datetime: to]]
      |> Parser.parse(calendar)
      |> season_interval_result()
    end
  end

  # A Gregorian date's components in `calendar`, followed by `rest`. A
  # week-based calendar numbers its weeks in the date's `month` field and
  # the day of the week in its `day`.
  defp calendar_date_components(date, rest, calendar) do
    case Date.convert(date, calendar) do
      {:ok, %Date{year: year, month: month, day: day}} ->
        date_components(year_division_unit(calendar), year, month, day) ++ rest

      {:error, _reason} ->
        {:error,
         InvalidDateError.exception(reason: "#{date} has no date in #{inspect(calendar)}")}
    end
  end

  defp date_components(:month, year, month, day), do: [year: year, month: month, day: day]
  defp date_components(:week, year, week, day), do: [year: year, week: week, day_of_week: day]

  ## Calendar weeks

  defp calendar_week(year, week, rest, calendar) do
    case calendar.calendar_base() do
      :week -> [{:year, year}, {:week, week} | rest]
      :month -> month_calendar_week(year, week, rest, calendar)
    end
  end

  # A negative week counts back from the year's last, as `-1W` does.
  defp month_calendar_week(year, week, rest, calendar) do
    with {:ok, weeks} <- UnitValues.in_period(:calendar_week, [year: year], calendar),
         {:ok, week} <- Validation.conform(week, weeks) do
      calendar_week_days(year, week, rest, calendar)
    else
      {:error, _reason} ->
        {:error,
         InvalidDateError.exception(
           reason: "#{inspect(calendar)} numbers no week #{week} in #{year}"
         )}
    end
  end

  # A negative day of the week counts back from the week's last, as `-7K`
  # does in an ISO 8601 week.
  defp calendar_week_days(year, week, [{:day_of_week, day} | rest], calendar)
       when is_integer(day) do
    with {:ok, days} <- UnitValues.in_period(:day_of_week, [], calendar),
         {:ok, day} <- Validation.conform(day, days),
         {:ok, date} <- Validation.date_from_calendar_week(year, week, day, calendar) do
      [{:year, date.year}, {:month, date.month}, {:day, date.day} | rest]
    else
      _not_a_day -> calendar_week_day_error(year, week, day, calendar)
    end
  end

  defp calendar_week_days(year, week, [{:day_of_week, day} | _rest], _calendar) do
    {:error,
     InvalidDateError.exception(
       reason:
         "Calendar week #{week} of #{year} takes a single day of the week, not #{inspect(day)}"
     )}
  end

  # The week's days, from its first to the day after its last: a week the
  # calendar cuts short at the start or end of its year spans only its own.
  defp calendar_week_days(year, week, rest, calendar) do
    case Validation.calendar_week_range(year, week, calendar) do
      %Date.Range{first: first, last: last} ->
        next = Calendrical.next(last, :day)

        [
          interval: [
            datetime: [{:year, first.year}, {:month, first.month}, {:day, first.day} | rest],
            datetime: [{:year, next.year}, {:month, next.month}, {:day, next.day} | rest]
          ]
        ]
        |> Parser.parse(calendar)
        |> season_interval_result()

      {:error, _reason} ->
        {:error,
         InvalidDateError.exception(
           reason: "Calendar week #{week} of #{year} is not a week of #{inspect(calendar)}"
         )}
    end
  end

  defp calendar_week_day_error(year, week, day, calendar) do
    {:error,
     InvalidDateError.exception(
       reason:
         "Day #{inspect(day)} of calendar week #{week} of #{year} " <>
           "is not a date in #{inspect(calendar)}"
     )}
  end
end
