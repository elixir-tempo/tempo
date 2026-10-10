defmodule Tempo.Iso8601.Group do
  @moduledoc false

  alias Tempo.Calendars
  alias Tempo.Compare
  alias Tempo.IntervalEndpointsError
  alias Tempo.InvalidDateError
  alias Tempo.Iso8601.Group
  alias Tempo.Iso8601.Parser
  alias Tempo.Math
  alias Tempo.ParseError
  alias Tempo.Qualification
  alias Tempo.UnitValues
  alias Tempo.Validation

  import Tempo.Calendars, only: [is_notation: 1]

  @hours_per_day 24

  # This module expands groups into base time units. For example, it
  # expands:
  #  * quarters, quadrimesters and semesters, into the months (or, in a
  #    week-based calendar, the weeks) the calendar's periods span
  #  * groups of a unit (`2G3MU`), into the range of values they cover
  #  * seasons, astronomical and meteorological

  def expand_groups(tempo, calendar \\ Calendars.default())

  # A value is grouped in its own calendar, so a Hebrew quarter holds the
  # Hebrew months Calendrical puts in it.
  def expand_groups(%Tempo{time: time} = tempo, calendar) do
    case expand_groups(time, tempo.calendar || calendar) do
      {:error, reason} -> {:error, reason}
      %Tempo.Interval{} = interval -> {:ok, as_the_value_is(interval, tempo)}
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
      {:ok, %{tempo | from: start_of(from), to: start_of(to), duration: duration}}
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

  # A week after a month is a week of the month, which the calendar numbers
  # (`Tempo.UnitValues.weeks_of_month/3`), where a week after a year is an
  # ISO 8601 week. With a day of the week it is that day's date, and alone
  # the span of the dates the calendar numbers in it, as a calendar week of
  # a year (`w`) is. It is not always within its month: the first week of
  # July 2026 starts on 29 June. It is read before a season is, whose number
  # is no month's.
  def expand_groups([{:year, year}, {:month, month}, {:week, week} | rest], calendar)
      when is_integer(year) and is_integer(month) and is_integer(week) do
    week_of_month(year, month, week, rest, calendar)
  end

  def expand_groups([{:year, year}, {:month, month}, {:week, week} | _rest], _calendar) do
    several = Enum.find([year, month, week], &(not is_integer(&1)))

    {:error,
     ParseError.exception(
       reason:
         "A week of a month is one week of one month of one year, each written as a whole " <>
           "number, and #{inspect(several)} is not one. Select the weeks from the month with " <>
           "`Tempo.select/2`."
     )}
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

  # A season of 21 to 24 is "independent of location" (ISO 8601-2 §4.8.1):
  # spring, summer, autumn or winter wherever it is read, and so on other
  # dates either side of the equator. It is kept as it is written, a unit of
  # its own in the month's place, until it is given a hemisphere
  # (`resolve_seasons/2`): it was read as the northern season everywhere.
  # Nothing follows it, the standard writing a season as a year and its
  # season alone; a day after one was read as a day of its first month.
  def expand_groups([{:year, year}, {:month, season}], _calendar) when season in 21..24 do
    [{:year, year}, {:season, season}]
  end

  def expand_groups([{:year, _year}, {:month, season}, {unit, _value} | _rest], _calendar)
      when season in 21..24 do
    {:error,
     ParseError.exception(
       reason:
         "A season is written as a year and the season alone (ISO 8601-2 §4.8), and " <>
           "#{inspect(unit)} follows season #{season}. A season of 21 to 24 has no dates until " <>
           "it is given a hemisphere (`Tempo.in_territory/2`); write a date of it as a date."
     )}
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 25..32 and not is_notation(calendar) do
    calendar_season(year, month, rest, calendar)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 25..32 do
    with {:ok, start_date, end_date} <- gregorian_season(month, year) do
      astronomical_span(start_date, end_date, rest, calendar)
    end
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar) when month in 25..32 do
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

  ## A season given a hemisphere

  @doc false
  # Gives each season of 21 to 24 a value holds the dates it has in a
  # hemisphere: the value's own span, each end of an interval where the
  # season starts, and each member of a set.
  #
  # A meteorological season is whole months: in the north spring from March
  # to the start of June and winter from December to the start of the next
  # March, and in the south the months of the opposite season, spring from
  # September and summer from December. A winter in the north and a summer
  # in the south are of the year they start in. In a calendar other than the
  # Gregorian it is the season of that kind that starts within the year.
  @spec resolve_seasons(value, :northern | :southern) :: {:ok, term()} | {:error, Exception.t()}
        when value: term()
  def resolve_seasons(%Tempo{time: [{:year, year}, {:season, season}]} = tempo, hemisphere) do
    case season_span(year, {season, hemisphere}, Calendars.of(tempo)) do
      %Tempo.Interval{} = interval -> {:ok, as_the_value_is(interval, tempo)}
      {:error, _reason} = error -> error
    end
  end

  # An interval from one season to another runs from where the first starts
  # to where the second does, and is an interval where the hemisphere has
  # them in that order: south of the equator the autumn of a year comes
  # before its spring.
  def resolve_seasons(%Tempo.Interval{} = interval, hemisphere) do
    with {:ok, from} <- resolve_seasons(interval.from, hemisphere),
         {:ok, to} <- resolve_seasons(interval.to, hemisphere),
         resolved = %{interval | from: start_of(from), to: start_of(to)},
         :ok <- in_order(resolved, interval, hemisphere) do
      {:ok, resolved}
    end
  end

  def resolve_seasons(%Tempo.Set{set: set, except: except} = tempo, hemisphere) do
    with {:ok, set} <- resolve_each_season(set, hemisphere),
         {:ok, except} <- resolve_each_season(except, hemisphere) do
      {:ok, %{tempo | set: set, except: except}}
    end
  end

  def resolve_seasons(other, _hemisphere), do: {:ok, other}

  # A range of seasons in a set is each season between its ends by the time
  # it is read (`expand_divisions/4`), so a set holds its seasons as members.
  defp resolve_each_season(members, hemisphere) when is_list(members) do
    members
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, resolved} ->
      case resolve_seasons(member, hemisphere) do
        {:ok, member} -> {:cont, {:ok, [member | resolved]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> reversed()
  end

  defp in_order(%Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to}, written, hemisphere) do
    if Compare.compare_endpoints(to, from) == :earlier,
      do: {:error, season_order_error(written, from, to, hemisphere)},
      else: :ok
  end

  defp in_order(_an_open_end, _written, _hemisphere), do: :ok

  defp season_order_error(written, from, to, hemisphere) do
    IntervalEndpointsError.exception(
      interval: written,
      operation: :in_territory,
      reason:
        "#{inspect(written)} is no interval in the #{hemisphere} hemisphere, where it " <>
          "would run from #{inspect(from)} to #{inspect(to)}: a year's autumn and winter " <>
          "come before its spring and summer south of the equator, and after them north of it."
    )
  end

  @doc false
  # Whether a value holds a season of 21 to 24 that has no hemisphere yet.
  @spec abstract_season?(term()) :: boolean()
  def abstract_season?(%Tempo{time: time}) when is_list(time),
    do: List.keymember?(time, :season, 0)

  def abstract_season?(%Tempo.Interval{from: from, to: to}),
    do: abstract_season?(from) or abstract_season?(to)

  def abstract_season?(%Tempo.Set{set: set, except: except}),
    do:
      Enum.any?(List.wrap(set), &abstract_season?/1) or
        Enum.any?(List.wrap(except), &abstract_season?/1)

  def abstract_season?(_other), do: false

  # The northern season that has the months a season has in a hemisphere:
  # a southern spring has a northern autumn's.
  defp northern_months(season, :northern), do: season
  defp northern_months(21, :southern), do: 23
  defp northern_months(22, :southern), do: 24
  defp northern_months(23, :southern), do: 21
  defp northern_months(24, :southern), do: 22

  # ISO 8601-2's seasons are the seasons of the notation's calendar, by its
  # months.
  defp season_span(year, {season, hemisphere}, calendar)
       when is_integer(year) and is_notation(calendar) do
    with {:ok, start_date, end_date} <-
           gregorian_season(northern_months(season, hemisphere), year) do
      meteorological_span(start_date, end_date, Calendars.default())
    end
  end

  defp season_span(year, {season, hemisphere}, calendar) when is_integer(year),
    do: calendar_season(year, northern_months(season, hemisphere), [], calendar)

  # A year with unspecified digits keeps them in both ends of a season that
  # is within one year. The season that runs into the next, a northern
  # winter and a southern summer, needs the year itself, and so does a
  # season in another calendar.
  defp season_span(year, {season, hemisphere}, calendar) do
    case unspecified_year_season(year, northern_months(season, hemisphere), [], calendar) do
      {:error, _reason} ->
        written = %Tempo{time: [year: year, season: season], calendar: calendar}

        {:error,
         InvalidDateError.exception(
           reason:
             "#{inspect(written)} cannot be placed in the #{hemisphere} hemisphere: with " <>
               "unspecified digits in its year a season is placed where it lies within one " <>
               "Gregorian year."
         )}

      interval ->
        interval
    end
  end

  # A season is a span of dates, and each end of it is as the value that
  # named the season is: qualified by what qualified it, and with the zone,
  # the calendar and the tags of its own suffix. `2026-21?` was the spring of
  # 2026 with nothing uncertain about it, and a member of a set written with
  # a zone of its own a spring in no zone.
  #
  # Each end's date is worked out from the year and the season together, so
  # what qualifies either qualifies the date (`Tempo.Qualification.rewritten/2`).
  defp as_the_value_is(%Tempo.Interval{from: from, to: to} = interval, %Tempo{} = value) do
    %{interval | from: end_as_the_value_is(from, value), to: end_as_the_value_is(to, value)}
  end

  defp end_as_the_value_is(%Tempo{time: time, calendar: calendar}, %Tempo{} = value) do
    %{Qualification.rewritten(value, time) | time: time, calendar: calendar}
  end

  defp end_as_the_value_is(open_end, _value), do: open_end

  # An end of an interval is where its value starts, as a month's or a
  # day's is: an interval from the spring of a year to its autumn
  # (`2026-21/2026-23`) runs from the start of the one to the start of the
  # other. Each end was the season's whole span, an interval of two
  # intervals that nothing read.
  defp start_of(%Tempo.Interval{from: start}), do: start
  defp start_of(value_or_open_end), do: value_or_open_end

  # An error expanding the rest of the list is the list's error.
  defp prepend(_first, {:error, _reason} = error), do: error
  defp prepend(first, time), do: [first | time]

  # A set's members, and the members it excludes, each expand as a value does.
  # A range from one division of a year to another is the divisions it names,
  # each a member (`expand_member/2`).
  defp expand_members(members, calendar) do
    members
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, expanded} ->
      case expand_member(member, calendar) do
        {:ok, members} -> {:cont, {:ok, Enum.reverse(members, expanded)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> reversed()
  end

  ## A range of a year's divisions

  # A season, a quarter, a quadrimester and a semester (ISO 8601-2 Table 2,
  # the numbers 21 to 41 written where a month is) are each a span of dates,
  # so one expands to an interval. A range from one to another is all of them
  # between (§6.3 c): `{2026-21..2026-23}` is the spring, the summer and the
  # autumn of 2026, each a member. It was a range whose ends were intervals,
  # which nothing walks and whose own text was not read.
  #
  # The divisions of one kind are counted in the order of their numbers, and
  # the first of the next year follows the last of a year. A range from a
  # division to anything else, or with one end left open, names no such
  # run and is an error.
  #
  # They are a run in time as well, each beginning where the one before it
  # ends, or the range is an error: the southern seasons of one year (29 to
  # 32) are no run, its autumn and winter coming before its spring. The
  # seasons numbered 21 to 24 are one in either hemisphere, the last of a
  # year being of the year it starts in (decided 2026-10-07; it was read as
  # beginning in the December before its year, ahead of that year's spring),
  # and are not asked: they have no dates until they are given a hemisphere.
  @divisions [21..24, 25..28, 29..32, 33..36, 37..39, 40..41]

  # The most divisions a range names: a range of seasons across every year
  # of the calendar is not expanded.
  @most_divisions 1_000

  defp expand_member(%Tempo.Range{first: first, last: last} = range, calendar) do
    case {division(first), division(last)} do
      {nil, nil} ->
        expand_one(range, calendar)

      {{_kind, _from} = from, {_any_kind, _to} = to} ->
        expand_divisions(from, to, range, calendar)

      _one_end_alone ->
        {:error, division_range_error(first, last)}
    end
  end

  defp expand_member(member, calendar), do: expand_one(member, calendar)

  defp expand_one(member, calendar) do
    with {:ok, member} <- expand_groups(member, calendar), do: {:ok, [member]}
  end

  # The kind of division a value is, as the numbers its kind takes, and the
  # year and number it is: `nil` for a value that is none.
  defp division(%Tempo{time: [{:year, year}, {:month, number}]})
       when is_integer(year) and is_integer(number) do
    case Enum.find(@divisions, &(number in &1)) do
      nil -> nil
      kind -> {kind, {year, number}}
    end
  end

  defp division(_value), do: nil

  defp expand_divisions({kind, from}, {kind, to}, range, calendar) when from <= to do
    with {:ok, divisions} <- divisions_between(from, to, kind),
         {:ok, expanded} <- expand_each_division(divisions, range, calendar) do
      if kind == 21..24 or run_in_time?(expanded),
        do: {:ok, expanded},
        else: {:error, division_run_error(from, to)}
    else
      :too_many -> {:error, division_count_error(from, to)}
      {:error, _reason} = error -> error
    end
  end

  defp expand_divisions({_kind, from}, {_other_kind, to}, _range, _calendar),
    do: {:error, division_order_error(from, to)}

  defp divisions_between(from, to, kind) do
    divisions =
      from
      |> Stream.iterate(&next_division(&1, kind))
      |> Stream.take_while(&(&1 <= to))
      |> Enum.take(@most_divisions + 1)

    if Enum.count(divisions) > @most_divisions, do: :too_many, else: {:ok, divisions}
  end

  defp next_division({year, number}, first..last//_) do
    if number == last, do: {year + 1, first}, else: {year, number + 1}
  end

  # Each division as the value it is: the range's first and its last as they
  # are written, with what qualifies them, and those between as the first is
  # with nothing qualifying them.
  defp expand_each_division(divisions, %Tempo.Range{first: first, last: last}, calendar) do
    divisions
    |> Enum.reduce_while({:ok, []}, fn {year, number}, {:ok, expanded} ->
      written = division_as_written([year: year, month: number], first, last)

      case expand_groups(written, calendar) do
        {:ok, division} -> {:cont, {:ok, [division | expanded]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> reversed()
  end

  defp division_as_written(time, %Tempo{time: time} = first, _last), do: first
  defp division_as_written(time, _first, %Tempo{time: time} = last), do: last
  defp division_as_written(time, first, _last), do: %{first | time: time, qualifications: nil}

  # Whether each division begins where the one before it ends.
  defp run_in_time?(divisions) do
    spans = Enum.map(divisions, &Tempo.to_interval/1)

    spans
    |> Enum.zip(Enum.drop(spans, 1))
    |> Enum.all?(&runs_on?/1)
  end

  defp runs_on?({{:ok, %Tempo.Interval{to: ends}}, {:ok, %Tempo.Interval{from: begins}}}),
    do: Compare.compare_endpoints(ends, begins) == :same

  defp runs_on?(_no_one_span), do: false

  defp division_run_error({from_year, from}, {to_year, to}) do
    InvalidDateError.exception(
      reason:
        "The divisions of a year from #{from_year}-#{from} to #{to_year}-#{to} do not run on " <>
          "from one another in time, each beginning where the one before it ends: the seasons " <>
          "of a year are not all in the order of their numbers (a southern autumn and winter, " <>
          "31 and 32, come before that year's spring, 29). Write each of them as a member of " <>
          "the set."
    )
  end

  defp division_range_error(first, last) do
    InvalidDateError.exception(
      reason:
        "A range from #{shown(first)} to #{shown(last)} is from a division of a year (a " <>
          "season, a quarter, a quadrimester or a semester) at one end alone. A range of them " <>
          "runs from one to another of its kind, and names each of them between."
    )
  end

  defp division_order_error({from_year, from}, {to_year, to}) do
    InvalidDateError.exception(
      reason:
        "A range from #{from_year}-#{from} to #{to_year}-#{to} is no range of a year's " <>
          "divisions: it runs from one kind to another, or from a later one to an earlier."
    )
  end

  defp division_count_error({from_year, from}, {to_year, to}) do
    InvalidDateError.exception(
      reason:
        "A range from #{from_year}-#{from} to #{to_year}-#{to} names more than " <>
          "#{@most_divisions} divisions of a year, the most a range is expanded to."
    )
  end

  defp shown(:undefined), do: "an open end"
  defp shown(value), do: inspect(value)

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

  # Calendrical gives each division of a year of a calendar as its dates.
  defp year_division_date_range(calendar, year, :quarter, number),
    do: year |> calendar.quarter(number) |> year_division_date_range_result()

  defp year_division_date_range(calendar, year, :quadrimester, number),
    do: year |> calendar.quadrimester(number) |> year_division_date_range_result()

  defp year_division_date_range(calendar, year, :semester, number),
    do: year |> calendar.semester(number) |> year_division_date_range_result()

  defp year_division_date_range_result(%Date.Range{} = range), do: {:ok, range}
  defp year_division_date_range_result({:error, reason}), do: {:error, reason}

  # A week-based calendar numbers its weeks in the date's `month` field.
  defp year_division_unit(calendar) do
    if Tempo.week_based_calendar?(calendar),
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
    do: UnitValues.iso_weeks_in_year(year, calendar)

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
  # first days of the months of a meteorological one. A winter is of the
  # year it starts in and runs into the next (decided 2026-10-07): the
  # meteorological one (24) was of the year it ends in, so a year's four
  # seasons were not in the order of their numbers, and `2012-24/2012-21`,
  # which EDTF's own corpus lists as no interval, was read as one.
  defp gregorian_season(code, year) when code in 21..23 do
    {start_month, end_month} = meteorological_months(code)
    meteorological_bounds(year, start_month, year, end_month)
  end

  defp gregorian_season(24, year), do: meteorological_bounds(year, 12, year + 1, 3)

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
  # season's first day, provided it falls before the season ends. The
  # season's first day is asked of its own calendar.
  defp nth_day_of_season(%Date{calendar: calendar} = start_date, %Date{} = end_date, day)
       when is_integer(day) and day >= 1 do
    %Date{year: year, month: month, day: day_of_month} = start_date

    {year, month, day_of_month} =
      Calendars.effective(calendar).plus(year, month, day_of_month, :days, day - 1, [])

    season_date_before(Date.new(year, month, day_of_month, calendar), end_date, day)
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

  # A meteorological season runs over whole months.
  defp meteorological_span(start_date, end_date, calendar) do
    season_interval(
      [{:year, start_date.year}, {:month, start_date.month}],
      [{:year, end_date.year}, {:month, end_date.month}],
      calendar
    )
  end

  # A year with unspecified digits (`20XX-21`) keeps them in both bounds of
  # a spring, summer or autumn. A winter ends in the year after and an
  # astronomical season starts on the day its year's equinox or solstice falls,
  # so those, a day of any season, and a season in another calendar need
  # the year itself.
  defp unspecified_year_season(_year, code, [{:day, day} | _rest], _calendar) do
    {:error,
     InvalidDateError.exception(
       reason:
         "Day #{inspect(day)} of season #{code} cannot be placed in a year with unspecified digits"
     )}
  end

  defp unspecified_year_season(year, code, rest, calendar)
       when code in 21..23 and is_notation(calendar) do
    {start_month, end_month} = meteorological_months(code)

    season_interval(
      [{:year, year}, {:month, start_month} | rest],
      [{:year, year}, {:month, end_month} | rest],
      Calendars.default()
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
    with %Date.Range{first: first, last: last} <- calendar.year(year),
         {:ok, first} <- Date.convert(first, Calendars.default()),
         {:ok, last} <- Date.convert(last, Calendars.default()) do
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
  # any does. A season starts in the Gregorian year that labels it, a
  # winter too, so the labels are the Gregorian years the year touches.
  defp season_starting_within(code, first, last, year, calendar) do
    first.year..last.year//1
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

  ## Weeks of a month

  # A negative week counts back from the month's last, as `-1W` does in a
  # year. A month the calendar reads in another calendar than its own (a
  # calendar of weeks answers so, by `parsing_calendar/0`) is no month of
  # its own to number a week in.
  defp week_of_month(year, month, week, rest, calendar) do
    with false <- Validation.written_in_another_calendar?([month: month], calendar),
         {:ok, %Date.Range{} = dates} <- UnitValues.week_of_month(year, month, week, calendar) do
      week_of_month_days(dates, rest, calendar, {year, month, week})
    else
      _no_such_week -> {:error, no_week_of_month(year, month, week, calendar)}
    end
  end

  # A month has the weeks its calendar numbers in it, and no other.
  defp no_week_of_month(year, month, week, calendar) do
    InvalidDateError.exception(
      unit: :week,
      value: week,
      year: year,
      month: month,
      calendar: calendar,
      reason: "#{inspect(calendar)} numbers no week #{week} in month #{month} of #{year}"
    )
  end

  # A day of the week is the date among the week's with that weekday, so a
  # week the calendar cuts short at an end of its month has fewer, and a
  # negative one counts back from the week's last, as `-7K` does in an ISO
  # 8601 week.
  defp week_of_month_days(dates, [{:day_of_week, day} | rest], calendar, named)
       when is_integer(day) do
    with {:ok, days} <- UnitValues.in_period(:day_of_week, [], calendar),
         {:ok, day} <- Validation.conform(day, days),
         {:ok, date} <- UnitValues.date_of_weekday(dates, day) do
      [{:year, date.year}, {:month, date.month}, {:day, date.day} | rest]
    else
      _not_a_day -> week_of_month_day_error(named, day, calendar)
    end
  end

  defp week_of_month_days(_dates, [{:day_of_week, day} | _rest], _calendar, {year, month, week}) do
    {:error,
     ParseError.exception(
       reason:
         "Week #{week} of month #{month} of #{year} takes a single day of the week, " <>
           "not #{inspect(day)}. Select the days from the month with `Tempo.select/2`."
     )}
  end

  # The week's dates, from its first to the day after its last.
  defp week_of_month_days(%Date.Range{first: first, last: last}, [], calendar, _named) do
    next = Calendrical.next(last, :day)

    [
      interval: [
        datetime: [year: first.year, month: first.month, day: first.day],
        datetime: [year: next.year, month: next.month, day: next.day]
      ]
    ]
    |> Parser.parse(calendar)
    |> season_interval_result()
  end

  # A time of day under a week is on the week's first day, as it is under a
  # week of a year (`2026Y24WT10H` is 10:00 on its Monday), which here is
  # the first date the calendar numbers in the week.
  defp week_of_month_days(%Date.Range{first: first}, [{unit, _value} | _finer] = time, _, _)
       when unit in [:hour, :minute, :second] do
    [{:year, first.year}, {:month, first.month}, {:day, first.day} | time]
  end

  defp week_of_month_days(_dates, [{unit, _value} | _rest], _calendar, {year, month, week}) do
    {:error,
     ParseError.exception(
       reason:
         "Week #{week} of month #{month} of #{year} is followed by #{inspect(unit)}, and a " <>
           "week of a month takes a day of the week (`K`) and a time of day after it"
     )}
  end

  defp week_of_month_day_error({year, month, week}, day, calendar) do
    {:error,
     InvalidDateError.exception(
       unit: :day_of_week,
       value: day,
       year: year,
       month: month,
       calendar: calendar,
       reason:
         "Day #{inspect(day)} of week #{week} of month #{month} of #{year} " <>
           "is not a date in #{inspect(calendar)}"
     )}
  end

  ## Calendar weeks

  defp calendar_week(year, week, rest, calendar) do
    if Tempo.week_based_calendar?(calendar),
      do: [{:year, year}, {:week, week} | rest],
      else: month_calendar_week(year, week, rest, calendar)
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
         {:ok, date} <- UnitValues.date_from_calendar_week(year, week, day, calendar) do
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
    case UnitValues.calendar_week_range(year, week, calendar) do
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
