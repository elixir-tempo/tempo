defmodule Tempo.Builder do
  @moduledoc """
  Builds an expression a step at a time, so that a pipeline reads as the
  sentence it means.

      import Tempo.Builder

      every(:week)
      |> on(:monday)
      |> at(hour: 9)
      |> starting(~o"2026-06-01")
      |> times(10)

  > *Every week, on Monday, at nine, starting the 1st of June, ten times.*

  Each step takes an expression, or the result of the step before it, and
  returns `{:ok, expression}` or `{:error, exception}`. An error passes
  through every step after it untouched, so a pipeline ends with the first
  error it met. What each step returns is a complete expression, the one
  its ISO 8601 text reads to: `every(:week) |> on(:monday)` is
  `~o"R/../P1W/FL1KN"`, as usable as the finished pipeline.

  The steps refine any expression where they have a meaning: the same
  `on/3` and `at/2` that refine a recurrence refine a value, so
  `~o"2026-06" |> on(:monday) |> at(hour: 9)` is the Mondays of June 2026
  at nine.

  The steps, by what they say:

  * What repeats: `every/1`.

  * What is selected in each repeat, or in a value: `on/3` for days,
    `at/2` for times of day, and `lasting/2` for days that run on.

  * Where a recurrence begins and ends: `starting/2`, `until/2`,
    `times/2` and `ending/2`.

  * Its frame: `in_zone/2`, `in_calendar/2`, `weeks_beginning/2` and
    `in_years/3`.

  * What is left out, what is kept with it, and what goes beside it:
    `except/2`, `with_metadata/2` and `all_of/1`.

  The module is meant to be imported. Its names are English words, and
  `at/2` and `on/3` are not `Tempo.at/2` and `Tempo.on/2`, which place one
  value on another.

  """

  alias Tempo.{Build, Duration, Interval, IntervalSet, InvalidCalendarError, Options}

  @weekdays [monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6, sunday: 7]
  @weekday_names Keyword.keys(@weekdays)
  @cadence_units [:year, :quarter, :month, :week, :day, :hour, :minute, :second]
  @clock [:hour, :minute, :second]

  # What a recurrence is given once: its start, its end, its count, its years.
  @once [:from, :to, :count, :until, :years]

  @typedoc "An expression, or the result of a step: what each step takes."
  @type step :: Tempo.t() | {:ok, Tempo.t()} | {:error, Exception.t()}

  @typedoc "What each step returns."
  @type result :: {:ok, Tempo.t()} | {:error, Exception.t()}

  @typedoc "A day of the week by its name."
  @type weekday :: :monday | :tuesday | :wednesday | :thursday | :friday | :saturday | :sunday

  @doc """
  A recurrence of a cadence, with no start and no end yet: the first step
  of a rule.

  ### Arguments

  * `cadence` is the length of each repeat: a unit (`:year`, `:quarter`,
    `:month`, `:week`, `:day`, `:hour`, `:minute` or `:second`), a
    `t:Tempo.Duration.t/0`, or a duration's units (`[week: 2]`).

  ### Returns

  * `{:ok, recurrence}`, a `t:Tempo.t/0` that repeats with no start of its
    own until `starting/2` gives it one.

  * `{:error, exception}` for a cadence that is no length.

  ### Examples

      iex> Tempo.Builder.every(:week)
      {:ok, ~o"R/../P1W"}

      iex> Tempo.Builder.every(week: 2)
      {:ok, ~o"R/../P2W"}

      iex> Tempo.Builder.every(~o"P1M")
      {:ok, ~o"R/../P1M"}

  """
  @spec every(atom() | Duration.t() | keyword()) :: result()
  def every(unit) when unit in @cadence_units, do: Tempo.every([{unit, 1}])
  def every(%Duration{} = cadence), do: Tempo.every(cadence)
  def every(units) when is_list(units), do: Tempo.every(units)

  def every(other),
    do:
      {:error,
       ArgumentError.exception(
         "a cadence is one of #{inspect(@cadence_units)}, a duration or its units, not #{inspect(other)}"
       )}

  @doc """
  Selects days: in each repeat of a recurrence, or in a value.

  ### Arguments

  * `step` is an expression, or the result of the step before.

  * `days` is what is selected: a day of the week by its name
    (`:monday`), a list of them, the parts of a selection of days
    (`[day: 15]`, `[month: 12, day: 25]`, `[event: "easter"]`), or a
    selection `Tempo.selection/1` made.

  * `options` is a keyword list of options.

  ### Options

  * `:nth` is which of the days a repeat holds: `2` for the second, `-1`
    for the last.

  * `:within` is a length counted from what the expression already
    selects, a `t:Tempo.Duration.t/0` or its units (`[day: 8]`, `[day: -3]`
    for the days before it): the days are selected in that window. It says
    the day a holiday is moved to, and a day counted from Easter.

  ### Returns

  * `{:ok, expression}`, the expression with the days selected in it.

  * `{:error, exception}` for an error passed on, days that are none of the
    above, or a unit the expression already selects.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:month) |> on(:monday, nth: 2)
      {:ok, ~o"R/../P1M/FL1K2IN"}

      iex> import Tempo.Builder
      iex> every(:year) |> on(month: 12, day: 25)
      {:ok, ~o"R/../P1Y/FL12M25DN"}

      iex> import Tempo.Builder
      iex> on(~o"2026-06", [:monday, :wednesday])
      {:ok, ~o"2026Y6ML{1,3}KN"}

  Pentecost, the last Sunday in the fifty days from Easter, and a Sunday
  the 25th of December moved to the Monday in the eight days from it:

      iex> import Tempo.Builder
      iex> every(:year) |> on(event: "easter") |> on(:sunday, nth: -1, within: [day: 50])
      {:ok, ~o"R/../P1Y/FLL(easter)eN/P50D7K-1IN"}

      iex> import Tempo.Builder
      iex> every(:year) |> on(month: 12, day: 25) |> on(:sunday) |> on(:monday, nth: -1, within: [day: 8])
      {:ok, ~o"R/../P1Y/FLL12M25D7KN/P8D1K-1IN"}

  """
  @spec on(step(), weekday() | [weekday()] | keyword() | Tempo.t(), keyword()) :: result()
  def on(step, days, options \\ []) do
    with {:ok, expression} <- Build.expression(step),
         :ok <- Options.check(options, [:nth, :within], "Tempo.Builder.on/3"),
         {:ok, parts} <- day_parts(days),
         {:ok, parts} <- nth(parts, Keyword.get(options, :nth)),
         {:ok, expression} <- within(expression, Keyword.get(options, :within)) do
      Build.selecting(expression, parts)
    end
  end

  defp within(expression, nil), do: {:ok, expression}

  defp within(expression, window) do
    with {:ok, window} <- a_length(window), do: Build.nesting(expression, window)
  end

  defp a_length(%Duration{} = length), do: {:ok, length}
  defp a_length([_ | _] = units), do: Duration.new(units)

  defp a_length(other),
    do:
      {:error,
       ArgumentError.exception("a length is a duration or its units, not #{inspect(other)}")}

  @doc """
  The days an expression selects, each the start of a stretch of a length:
  a holiday of several days.

  ### Arguments

  * `step` is an expression that selects days, or the result of the step
    before.

  * `length` is a `t:Tempo.Duration.t/0`, or its units (`[day: 8]`).

  ### Returns

  * `{:ok, expression}`, the expression selecting the stretches.

  * `{:error, exception}` for an error passed on, a length that is none,
    or an expression that selects nothing.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:year) |> on(month: 8, day: 16) |> lasting(day: 2)
      {:ok, ~o"R/../P1Y/FLL8M16DN/P2DN"}

  """
  @spec lasting(step(), Duration.t() | keyword()) :: result()
  def lasting(step, length) do
    with {:ok, expression} <- Build.expression(step),
         {:ok, length} <- a_length(length),
         do: Build.nesting(expression, length)
  end

  defp day_parts(day) when day in @weekday_names,
    do: {:ok, [day_of_week: Keyword.fetch!(@weekdays, day)]}

  defp day_parts([day | _] = days) when is_atom(day) do
    if Enum.all?(days, &(&1 in @weekday_names)),
      do: {:ok, [day_of_week: Enum.map(days, &Keyword.fetch!(@weekdays, &1))]},
      else: no_days(days)
  end

  defp day_parts([{_unit, _held} | _] = parts), do: {:ok, parts}
  defp day_parts(%Tempo{} = selection), do: Build.parts(selection)
  defp day_parts(other), do: no_days(other)

  defp no_days(other),
    do:
      {:error,
       ArgumentError.exception(
         "days are a weekday's name, a list of them, the parts of a selection or a selection, not #{inspect(other)}"
       )}

  defp nth(parts, nil), do: {:ok, parts}
  defp nth(parts, n) when is_integer(n) and n != 0, do: {:ok, parts ++ [instance: n]}

  defp nth(_parts, other),
    do:
      {:error,
       ArgumentError.exception(":nth is a whole number other than zero, not #{inspect(other)}")}

  @doc """
  Selects a time of day: in each repeat of a recurrence, or in a value.

  ### Arguments

  * `step` is an expression, or the result of the step before.

  * `time` is the time of day: its parts (`[hour: 9]`, `[hour: 9, minute: 30]`)
    or a time of day written as a value (`~o"T09:30"`).

  ### Returns

  * `{:ok, expression}`, the expression with the time of day selected in it.

  * `{:error, exception}` for an error passed on, a time with a date in it,
    or a unit the expression already selects.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:week) |> on(:monday) |> at(hour: 9)
      {:ok, ~o"R/../P1W/FL1KT9HN"}

      iex> import Tempo.Builder
      iex> ~o"2026-06" |> on(:monday) |> at(~o"T09:30")
      {:ok, ~o"2026Y6ML1KT9H30MN"}

  """
  @spec at(step(), keyword() | Tempo.t()) :: result()
  def at(step, time) do
    with {:ok, expression} <- Build.expression(step),
         {:ok, parts} <- clock_parts(time) do
      Build.selecting(expression, parts)
    end
  end

  defp clock_parts(%Tempo{form: {:value, units}, zone: nil, shift: nil}), do: clock_parts(units)

  defp clock_parts([_ | _] = parts) do
    if Keyword.keyword?(parts) and Enum.all?(Keyword.keys(parts), &(&1 in @clock)),
      do: {:ok, parts},
      else: no_time(parts)
  end

  defp clock_parts(other), do: no_time(other)

  defp no_time(other),
    do:
      {:error,
       ArgumentError.exception(
         "a time of day is its hours, minutes and seconds, or a value of them with no zone, not #{inspect(other)}"
       )}

  @doc """
  Where a recurrence begins: its first repeat is the one that holds this
  value.

  ### Arguments

  * `step` is a recurrence, or the result of the step before.

  * `from` is a `t:Tempo.t/0` value, or a set of them, each a domain the
    rule is applied in (`~o"{2026Y..2030Y}"`).

  ### Returns

  * `{:ok, recurrence}`, the recurrence beginning there.

  * `{:error, exception}` for an error passed on, or as `Tempo.every/2`
    refuses the start.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:week) |> on(:monday) |> starting(~o"2026-06-01")
      {:ok, ~o"R/2026-06-01/P1W/FL1KN"}

  """
  @spec starting(step(), Tempo.t()) :: result()
  def starting(step, from), do: rebuilt(step, from: from)

  @doc """
  Where an expression ends, the value it runs through: a recurrence's last
  repeat is the one that holds it, and a value runs through it as an
  interval.

  ### Arguments

  * `step` is a recurrence or a value, or the result of the step before.

  * `until` is a `t:Tempo.t/0` value.

  ### Returns

  * `{:ok, expression}`, the recurrence ending there, or the interval from
    the value through `until`.

  * `{:error, exception}` for an error passed on, a recurrence that already
    ends by a count, or an end before the start.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:day) |> starting(~o"2026-06-01") |> until(~o"2026-06-30")
      {:ok, ~o"R/2026-06-01/P1D/2026-06-30"}

      iex> import Tempo.Builder
      iex> until(~o"2026-06-01", ~o"2026-06-12")
      {:ok, ~o"2026-06-01/2026-06-12"}

  """
  @spec until(step(), Tempo.t()) :: result()
  def until(step, until) do
    with {:ok, expression} <- Build.expression(step), do: until_of(expression, until)
  end

  defp until_of(%Tempo{form: {:every, _, _, _}} = recurrence, until),
    do: rebuilt(recurrence, until: until)

  defp until_of(%Tempo{form: {:value, _}} = value, until),
    do: Interval.new(from: value, to: until)

  defp until_of(other, _until),
    do:
      {:error,
       ArgumentError.exception(
         "a recurrence or a value runs until a value, not #{inspect(other)}"
       )}

  @doc """
  How many occurrences a recurrence has.

  ### Arguments

  * `step` is a recurrence, or the result of the step before.

  * `count` is a whole number above zero.

  ### Returns

  * `{:ok, recurrence}`, the recurrence with that many occurrences.

  * `{:error, exception}` for an error passed on, a count that is not a
    whole number above zero, or a recurrence that already ends by a value.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:week) |> starting(~o"2026-06-01") |> times(10)
      {:ok, ~o"R10/2026-06-01/P1W"}

  """
  @spec times(step(), pos_integer()) :: result()
  def times(step, count), do: rebuilt(step, count: count)

  @doc """
  Where a recurrence counted back from its end ends: its last repeat ends
  with this value.

  ### Arguments

  * `step` is a recurrence, or the result of the step before.

  * `to` is a `t:Tempo.t/0` value.

  ### Returns

  * `{:ok, recurrence}`, the recurrence counted back from `to`.

  * `{:error, exception}` for an error passed on, or a recurrence that
    already has a start.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:month) |> ending(~o"2026-06-01") |> times(5)
      {:ok, ~o"R5/P1M/2026-06-01"}

  """
  @spec ending(step(), Tempo.t()) :: result()
  def ending(step, to), do: rebuilt(step, to: to)

  @doc """
  An expression in a time zone: its clock readings are the zone's.

  ### Arguments

  * `step` is an expression, or the result of the step before.

  * `zone` is a time zone's name (`"Europe/Paris"`).

  ### Returns

  * `{:ok, expression}`, the expression in the zone, as `Tempo.in_zone/2`
    places it.

  * `{:error, exception}` for an error passed on, or as `Tempo.in_zone/2`
    refuses it.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:week) |> on(:monday) |> at(hour: 9) |> in_zone("Europe/Paris")
      {:ok, ~o"R/../P1W/FL1KT9HN[Europe/Paris]"}

  """
  @spec in_zone(step(), String.t()) :: result()
  def in_zone(step, zone) do
    with {:ok, expression} <- Build.expression(step), do: Tempo.in_zone(expression, zone)
  end

  @doc """
  The calendar a recurrence with no start of its own counts its years,
  months and days in. The years of a domain `in_years/3` gave it are read as
  years of this calendar. A recurrence with a start is in its start's
  calendar, and a value is converted with `Tempo.to_calendar/2`.

  ### Arguments

  * `step` is a recurrence with no start, or the result of the step before.

  * `calendar` is a calendar module (`Calendrical.Hebrew`).

  ### Returns

  * `{:ok, recurrence}`, the recurrence in that calendar.

  * `{:error, exception}` for an error passed on, a calendar Tempo does not
    know, or a recurrence with a start.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:year) |> on(month: 7, day: 1) |> in_calendar(Calendrical.Hebrew)
      {:ok, ~o"R/../P1Y/FL7M1DN[u-ca=hebrew]"}

      iex> import Tempo.Builder
      iex> every(:year) |> on(traditional_month: 2, day: 12) |> in_years(from: 5758) |> in_calendar(Calendrical.Hebrew)
      {:ok, ~o"R/{5758Y/..}/P1Y/FL2m12DN[u-ca=hebrew]"}

  """
  @spec in_calendar(step(), module()) :: result()
  def in_calendar(step, calendar) do
    with {:ok, expression} <- Build.expression(step),
         {:ok, recurrence} <- a_recurrence(expression, calendar: calendar),
         {:ok, calendar} <- a_calendar(calendar) do
      {cadence, options} = Build.every_options(recurrence)

      with {:ok, change} <- domain_in(Keyword.get(options, :from), calendar),
           do: remade(recurrence, cadence, Keyword.merge(options, change))
    end
  end

  defp a_calendar(calendar) do
    if Tempo.Calendar.calendar?(calendar),
      do: {:ok, calendar},
      else: {:error, InvalidCalendarError.exception(calendar: calendar)}
  end

  # A domain's years are numbers of the rule's calendar; a start is a value
  # of its own, which the calendar given must be.
  defp domain_in(%Tempo{form: {:all, _}} = domain, calendar) do
    with {:ok, domain} <- Build.years_in(domain, calendar),
         do: {:ok, [from: domain, calendar: calendar]}
  end

  defp domain_in(_start, calendar), do: {:ok, [calendar: calendar]}

  @doc """
  An expression whose weeks begin on another day than Monday: its numbered
  weeks are counted from that day, and a recurrence of every second week or
  more steps in those weeks. It is RFC 5545's `WKST`, written `[u-fw=sun]`.

  ### Arguments

  * `step` is an expression of the Gregorian calendar, or the result of the
    step before.

  * `day` is the weekday weeks begin on, by its name (`:sunday`).

  ### Returns

  * `{:ok, expression}`, the expression with its weeks begun on that day,
    as `Tempo.to_week_start/2` makes it.

  * `{:error, exception}` for an error passed on, a day that is no
    weekday's name, or an expression of another calendar.

  ### Examples

      iex> import Tempo.Builder
      iex> every(week: 2) |> on([:tuesday, :thursday]) |> weeks_beginning(:sunday)
      {:ok, ~o"R/../P2W/FL{2,4}KN[u-fw=sun]"}

  """
  @spec weeks_beginning(step(), weekday()) :: result()
  def weeks_beginning(step, day) when day in @weekday_names do
    with {:ok, expression} <- Build.expression(step),
         do: weeks_from(expression, Keyword.fetch!(@weekdays, day))
  end

  def weeks_beginning(step, other) do
    with {:ok, _expression} <- Build.expression(step),
         do: no_days(other)
  end

  # A recurrence is in the calendar of weeks from the day, its start and
  # its ends with it, as RFC 5545's WKST is read; another expression is
  # given those weeks as `Tempo.to_week_start/2` gives them.
  defp weeks_from(%Tempo{form: {:every, _, _, _}} = recurrence, day) do
    with {:ok, calendar} <- Tempo.Calendar.with_week_start(recurrence.calendar, day) do
      {cadence, options} = Build.every_options(recurrence)

      with {:ok, options} <- ends_in(options, calendar),
           do: remade(recurrence, cadence, Keyword.put(options, :calendar, calendar))
    end
  end

  defp weeks_from(expression, day), do: Tempo.to_week_start(expression, day)

  defp ends_in(options, calendar) do
    Enum.reduce_while(options, {:ok, []}, fn
      {key, %Tempo{} = value}, {:ok, acc} when key in [:from, :to, :until] ->
        case Tempo.to_calendar(value, calendar) do
          {:ok, value} -> {:cont, {:ok, acc ++ [{key, value}]}}
          {:error, _} = error -> {:halt, error}
        end

      option, {:ok, acc} ->
        {:cont, {:ok, acc ++ [option]}}
    end)
  end

  @doc """
  The years a recurrence repeats in: a domain of years, or every year of a
  kind.

  ### Arguments

  * `step` is a recurrence, or the result of the step before.

  * `years` is either a filter, one of `:even`, `:odd`, `:leap` and
    `:common`, which keeps those years of every year or of the domain; or the
    years themselves: a year (`2021`), a range of them (`1949..1988`), the
    years from one on (`from: 2005`) or up to one (`through: 2005`), or a
    list of those. The years are of the recurrence's calendar.

  * `options` is a keyword list of options.

  ### Options

  * `:except` is a year, or a list of years, left out of the domain.

  ### Returns

  * `{:ok, recurrence}`, the recurrence in those years only.

  * `{:error, exception}` for an error passed on, years that are none of
    the above, a recurrence that already has a start or a domain, or a
    filter of a recurrence that starts at one value.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:year) |> on(month: 2, day: 29) |> in_years(:leap)
      {:ok, ~o"R/..l/P1Y/FL2M29DN"}

      iex> import Tempo.Builder
      iex> every(:year) |> on(month: 9, day: 15) |> in_years(from: 2005)
      {:ok, ~o"R/{2005Y/..}/P1Y/FL9M15DN"}

      iex> import Tempo.Builder
      iex> every(:year) |> on(month: 6, day: 19) |> in_years([from: 1961], except: 2011)
      {:ok, ~o"R/{1961Y/..,^2011Y}/P1Y/FL6M19DN"}

  """
  @spec in_years(step(), atom() | integer() | Range.t() | keyword() | list(), keyword()) ::
          result()
  def in_years(step, years, options \\ [])

  def in_years(step, filter, []) when is_atom(filter), do: rebuilt(step, years: filter)

  def in_years(step, years, options) do
    with {:ok, expression} <- Build.expression(step),
         {:ok, recurrence} <- a_recurrence(expression, years: years),
         {:ok, domain} <- domain(years, options, recurrence.calendar) do
      rebuilt(recurrence, from: domain)
    end
  end

  defp domain(years, options, calendar) do
    with :ok <- Options.check(options, [:except], "Tempo.Builder.in_years/3"),
         {:ok, members} <- each_year(List.wrap(years), calendar),
         {:ok, excepted} <- each_year(List.wrap(Keyword.get(options, :except, [])), calendar) do
      IntervalSet.new(members, except: excepted)
    end
  end

  defp each_year([], _calendar), do: {:ok, []}

  defp each_year(years, calendar) do
    Enum.reduce_while(years, {:ok, []}, fn year, {:ok, acc} ->
      case year_member(year, calendar) do
        {:ok, member} -> {:cont, {:ok, acc ++ [member]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp year_member(year, calendar) when is_integer(year),
    do: Tempo.new(year: year, calendar: calendar)

  defp year_member(%Range{step: 1} = years, calendar),
    do: Tempo.new(year: years, calendar: calendar)

  defp year_member({:from, year}, calendar) when is_integer(year) do
    with {:ok, first} <- Tempo.new(year: year, calendar: calendar),
         do: Interval.new(from: first, to: :open)
  end

  defp year_member({:through, year}, calendar) when is_integer(year) do
    with {:ok, last} <- Tempo.new(year: year, calendar: calendar),
         do: Interval.new(from: :open, to: last)
  end

  defp year_member(other, _calendar),
    do:
      {:error,
       ArgumentError.exception(
         "years are a year, a range of them, from: or through: a year, not #{inspect(other)}"
       )}

  @doc """
  A set of expressions, each a member: a holiday and the day it is moved to,
  a rule and the dates given beside it.

  ### Arguments

  * `steps` is a list of expressions, or the results of pipelines; the
    first error among them is returned.

  ### Returns

  * `{:ok, set}`, a set of them, as `Tempo.IntervalSet.new/2` makes one.

  * `{:error, exception}` for an error passed on, or as
    `Tempo.IntervalSet.new/2` refuses the members.

  ### Examples

      iex> import Tempo.Builder
      iex> all_of([
      ...>   every(:year) |> on(month: 12, day: 25, day_of_week: 1..5),
      ...>   every(:year) |> on(selection: [month: 12, day: 25, day_of_week: 6..7], window: ~o"P8D", day_of_week: 1, instance: -1)
      ...> ])
      {:ok, ~o"{R/../P1Y/FL12M25D{1..5}KN,R/../P1Y/FLL12M25D{6..7}KN/P8D1K-1IN}"}

  """
  @spec all_of([step()]) :: result()
  def all_of(steps) when is_list(steps) do
    with {:ok, members} <- each_step(steps), do: IntervalSet.new(members)
  end

  def all_of(other),
    do: {:error, ArgumentError.exception("all_of/1 takes a list of steps, not #{inspect(other)}")}

  defp each_step(steps) do
    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, acc} ->
      case Build.expression(step) do
        {:ok, expression} -> {:cont, {:ok, acc ++ [expression]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  An expression with some values left out of it: a set of it, and the
  values excluded.

  ### Arguments

  * `step` is an expression, or the result of the step before.

  * `values` is a `t:Tempo.t/0` value, or a list of them.

  ### Returns

  * `{:ok, set}`, a set of the expression's members with the values
    excluded, as `Tempo.IntervalSet.new/2` makes one with `:except`.

  * `{:error, exception}` for an error passed on, or as
    `Tempo.IntervalSet.new/2` refuses it.

  ### Examples

      iex> import Tempo.Builder
      iex> every(:week) |> starting(~o"2026-06-01") |> except(~o"2026-06-08")
      {:ok, ~o"{R/2026-06-01/P1W,^2026-06-08}"}

  """
  @spec except(step(), Tempo.t() | [Tempo.t()]) :: result()
  def except(step, %Tempo{} = value), do: except(step, [value])

  def except(step, values) when is_list(values) do
    with {:ok, expression} <- Build.expression(step), do: excluding(expression, values)
  end

  def except(step, other) do
    with {:ok, _expression} <- Build.expression(step),
         do:
           {:error,
            ArgumentError.exception(
              "what is excepted is a value or a list of them, not #{inspect(other)}"
            )}
  end

  # A set already excluding some values excludes these as well.
  defp excluding(%Tempo{form: {:all, members}} = set, values) when is_list(members) do
    {out, kept} = Enum.split_with(members, &match?({:except, _}, &1))
    excluded = Enum.map(out, fn {:except, value} -> value end)
    IntervalSet.new(kept, except: excluded ++ values, metadata: set.metadata)
  end

  defp excluding(expression, values), do: IntervalSet.new([expression], except: values)

  @doc """
  An expression carrying a caller's map: a recurrence's every occurrence
  carries it too.

  ### Arguments

  * `step` is an expression, or the result of the step before.

  * `metadata` is a map, merged into the metadata the expression has.

  ### Returns

  * `{:ok, expression}`, the expression with the metadata.

  * `{:error, exception}` for an error passed on, or metadata that is no
    map.

  ### Examples

      iex> import Tempo.Builder
      iex> {:ok, standup} = every(:day) |> at(hour: 9) |> with_metadata(%{title: "Standup"})
      iex> Tempo.metadata(standup)
      %{title: "Standup"}

  """
  @spec with_metadata(step(), map()) :: result()
  def with_metadata(step, metadata) when is_map(metadata) do
    with {:ok, expression} <- Build.expression(step),
         do: {:ok, Tempo.put_metadata(expression, metadata)}
  end

  def with_metadata(step, other) do
    with {:ok, _expression} <- Build.expression(step),
         do: {:error, ArgumentError.exception("metadata is a map, not #{inspect(other)}")}
  end

  # A recurrence built again from its own parts with one changed, kept in
  # its zone, as `Tempo.every/2` would have built it given them all. What a
  # recurrence has once (a start, an end, a count, its years) is refused a
  # second time, where keeping either would say the other was wrong.
  defp rebuilt(step, change) do
    with {:ok, expression} <- Build.expression(step),
         {:ok, recurrence} <- a_recurrence(expression, change) do
      {cadence, options} = Build.every_options(recurrence)

      with :ok <- given_once(options, change),
           {:ok, options, change} <- in_its_calendar(options, change, recurrence.calendar),
           do: remade(recurrence, cadence, Keyword.merge(options, change))
    end
  end

  # A rule with no start whose calendar is still the default takes the
  # calendar of the start or end it is given; one whose calendar was chosen
  # has its start and ends brought to that calendar, as an operation on two
  # expressions brings its second to the first's.
  defp in_its_calendar(options, change, calendar) do
    if Keyword.get(options, :calendar) == Tempo.Calendar.default() and
         (Keyword.has_key?(change, :from) or Keyword.has_key?(change, :to)) do
      {:ok, Keyword.delete(options, :calendar), change}
    else
      with {:ok, change} <- ends_in(change, calendar), do: {:ok, options, change}
    end
  end

  defp given_once(options, change) do
    case Enum.find(Keyword.keys(change), &(&1 in @once and Keyword.has_key?(options, &1))) do
      nil ->
        :ok

      option ->
        {:error,
         ArgumentError.exception(
           "the recurrence already has #{inspect(option)} (#{inspect(Keyword.get(options, option))})"
         )}
    end
  end

  defp remade(recurrence, cadence, options) do
    cadence
    |> Tempo.every(options)
    |> in_zone_of(recurrence.zone)
  end

  defp a_recurrence(%Tempo{form: {:every, _, _, _}} = recurrence, _change), do: {:ok, recurrence}

  defp a_recurrence(other, [{option, _}]),
    do:
      {:error,
       ArgumentError.exception(
         "#{inspect(option)} is given to a recurrence (start one with every/1), not #{inspect(other)}"
       )}

  defp in_zone_of({:ok, %Tempo{zone: nil} = built}, %Tempo.Zone{} = zone),
    do: Build.in_zone(built, zone)

  defp in_zone_of(result, _zone), do: result
end
