defmodule Tempo.Validation do
  @moduledoc false

  alias Calendrical.Kday
  alias Localize.Utils.Math
  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.InvalidDateError
  alias Tempo.InvalidTimeError
  alias Tempo.Iso8601.Group
  alias Tempo.Iso8601.Parser
  alias Tempo.Microsecond
  alias Tempo.NotBuilt
  alias Tempo.ParseError
  alias Tempo.Qualification
  alias Tempo.TimeZoneDatabase
  alias Tempo.UnitValues
  alias Tempo.ZoneGapError

  # This function performs two roles (and maybe should be split):
  #
  # 1. Expand groups into basic time units where there is enough information to do so and
  # 2. Ensures that basic units are valid (days in months, months in year etc)

  # There is ample room to refactor into a more generalised solution for much of
  # the resolution task. For now, being completely explicit aids implementation and
  # debugging. Refactoring to a generalised case will come later.

  @hours_per_day 24
  @minutes_per_hour 60
  @rounding_precision 10

  # ISO 8601's weeks start on a Monday, weekday 1.
  @monday 1

  def validate(tempo, calendar \\ Calendrical.Gregorian)

  # An unspecified year (`X*Y`) is some year and no year in particular: ISO
  # 8601-2 §4.6.2 reads `X*Y12M28D` as 28 December of an unspecified calendar
  # year. The units after it are read as they are with no year written, so
  # the two cannot be read two ways, and the year is kept as it is written.
  def validate(%Tempo{time: [{:year, :any} = year | [_ | _] = units]} = tempo, calendar) do
    with {:ok, %Tempo{time: validated} = yearless} <- validate(%{tempo | time: units}, calendar) do
      {:ok, %{yearless | time: [year | validated]}}
    end
  end

  def validate(%Tempo{time: units} = tempo, calendar) do
    with :ok <- validate_leap_second(units, tempo),
         :ok <- validate_time_shift(tempo.shift),
         :ok <- NotBuilt.month(tempo, calendar),
         {:ok, units} <- in_years_of_the_calendar(units, calendar) do
      units = sets_of_one_as_their_member(units)
      written = written_calendar(units, calendar)

      case resolve_as_written(units, written, calendar) do
        {:error, reason} ->
          {:error, reason}

        resolved ->
          tempo
          |> qualify_converted(resolved, written, calendar)
          |> validated_groups(collapse_single_member_sets(resolved), calendar)
          |> NotBuilt.result()
      end
    end
  end

  # Endpoints carrying different time shifts (`...+05:00/...+02:00`)
  # need no adjustment: `Tempo.Compare` projects both to a common UTC
  # frame for ordering and duration, so the difference is already
  # accounted for.

  def validate(%Tempo.Interval{} = tempo, calendar) do
    with {:ok, from} <- validate(tempo.from, endpoint_calendar(tempo.from, calendar)),
         {:ok, to} <- validate(tempo.to, endpoint_calendar(tempo.to, calendar)),
         {:ok, duration} <- validate(tempo.duration, calendar),
         :ok <- validate_endpoint_order(from, to) do
      {:ok, %{tempo | from: from, to: to, duration: duration}}
    end
  end

  def validate(%Tempo.Duration{} = duration, _calendar) do
    {:ok, duration}
  end

  # A set's member is checked as a value is: each member, each end of a range
  # and each member the set excludes, in its own calendar.
  def validate(%Tempo.Set{set: set, except: except} = tempo, calendar) do
    with {:ok, set} <- validate_members(set, calendar),
         {:ok, except} <- validate_members(except, calendar) do
      {:ok, %{tempo | set: set, except: except}}
    end
  end

  def validate(%Tempo.Range{first: first, last: last} = range, calendar) do
    with {:ok, first} <- validate(first, endpoint_calendar(first, calendar)),
         {:ok, last} <- validate(last, endpoint_calendar(last, calendar)) do
      {:ok, %{range | first: first, last: last}}
    end
  end

  def validate(nil, _calendar) do
    {:ok, nil}
  end

  def validate(:undefined, _calendar) do
    {:ok, :undefined}
  end

  # A year the calendar does not have is no year to read: the Julian
  # calendar's year before 1 is -1, and it has no year 0
  # (`Tempo.UnitValues.year?/2`). A year written, a member of a set of years
  # and an end of a range of them are asked; the years between a range's
  # ends are those the calendar has.
  #
  # A century or a decade is the years of it that the calendar has, so the
  # Julian calendar's first century (`00C`) starts with its year 1.
  defp in_years_of_the_calendar(
         [{:year, {:group, %Range{first: first, last: last, step: 1}}} | rest] = units,
         calendar
       ) do
    cond do
      first > last ->
        {:ok, units}

      not UnitValues.year?(first, calendar) ->
        {:ok, [{:year, {:group, (first + 1)..last//1}} | rest]}

      not UnitValues.year?(last, calendar) ->
        {:ok, [{:year, {:group, first..(last - 1)//1}} | rest]}

      true ->
        {:ok, units}
    end
  end

  defp in_years_of_the_calendar([{:year, years} | _units] = units, calendar) do
    case Enum.reject(years_written(years), &UnitValues.year?(&1, calendar)) do
      [] -> {:ok, units}
      [year | _rest] -> {:error, no_such_year(year, calendar)}
    end
  end

  defp in_years_of_the_calendar(units, _calendar), do: {:ok, units}

  defp years_written(year) when is_integer(year), do: [year]
  defp years_written(%Range{first: first, last: last}), do: [first, last]
  defp years_written(years) when is_list(years), do: Enum.flat_map(years, &years_written/1)
  defp years_written(_a_mask_or_a_group), do: []

  defp no_such_year(year, calendar) do
    InvalidDateError.exception(
      unit: :year,
      value: year,
      calendar: calendar,
      reason:
        "#{year} is not a year#{calendar_text(calendar)}: the year before its year 1 is " <>
          "#{UnitValues.years_on(1, -1, calendar)}."
    )
  end

  defp validate_members(members, calendar) do
    members
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, validated} ->
      case validate(member, endpoint_calendar(member, calendar)) do
        {:ok, member} -> {:cont, {:ok, [member | validated]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> reversed()
  end

  defp reversed({:ok, members}), do: {:ok, Enum.reverse(members)}
  defp reversed({:error, _reason} = error), do: error

  @doc false
  # Whether a value's units are written in a calendar other than its own, as a
  # month and a day are in a calendar of weeks, and so are converted when it is
  # validated.
  @spec written_in_another_calendar?(keyword(), module()) :: boolean()
  def written_in_another_calendar?(units, calendar),
    do: written_calendar(units, calendar) != calendar

  # A calendar of weeks has no month or day of a month, so a date written for
  # one with them, or as a day of the year, is read in the calendar its
  # `parsing_calendar/0` names, the Gregorian calendar, and converted into it,
  # as Localize reads such a date: 15 June 2026 is day 1 of week 25. Only a
  # whole date converts. A month alone, or a set of days, names no week and no
  # day of one, and is an error.
  defp resolve_as_written(units, calendar, calendar), do: resolve_units(units, calendar)

  defp resolve_as_written(units, written, calendar),
    do: units |> resolve_units(written) |> convert_date(written, calendar)

  # The units before a selection name the period it selects in, and are read
  # as they are with no selection after them: a month or a week its year
  # does not have is refused there too (`2027Y53WL1KN`), and a count from the
  # end is counted in its year. The selection and what follows it are read as
  # they are written.
  defp resolve_units(units, calendar) do
    if selection_after_units?(units),
      do: resolve_around_selection(units, calendar),
      else: resolve_a_value(units, calendar)
  end

  defp resolve_a_value(units, calendar) do
    units
    |> first_of_skipped_date_units(calendar)
    |> resolve_fixed_extent_negatives(calendar)
    |> resolve(calendar)
    |> settle_groups(calendar)
  end

  defp resolve_around_selection(units, calendar) do
    {before, selection_and_after} = Enum.split_while(units, &(not selection?(&1)))

    with period when is_list(period) <- resolve_a_value(before, calendar),
         rest when is_list(rest) <- resolve_a_value(selection_and_after, calendar) do
      period ++ rest
    end
  end

  # Whether a selection follows at least one unit. Most values hold none, and
  # are left as the list they are.
  defp selection_after_units?([_unit | rest]) when is_list(rest),
    do: Enum.any?(rest, &selection?/1)

  defp selection_after_units?(_units), do: false

  defp selection?({:selection, _parts}), do: true
  defp selection?(_unit), do: false

  @clock_units [:hour, :minute, :second]
  @units_of_days [:year, :month, :week]

  # A time of day under a date with its month or its day left out is read on
  # the first of what is left out: `2026YT17H` is 17:00 on 1 January and
  # `2026Y6MT10H` 10:00 on 1 June, as a clock unit left out is read as zero
  # (ISO 8601-2 §7.10). The value holds the units, so every reader sees a
  # whole date. Under a group it is the first day of the group, since what
  # follows a group is one instance within it (§5.4.2): `2026Y2G3MUT10H` is
  # 10:00 on 1 April. A group of clock units is left as it is: it is
  # counted in the unit before it (`2018Y20GT12HU`, the twentieth twelve
  # hours of the year).
  defp first_of_skipped_date_units(units, calendar) do
    if skips_a_date_unit?(units), do: with_skipped_date_units(units, calendar), else: units
  end

  # Whether a clock unit follows a year, a month or a week directly. Most
  # values skip nothing, and are left as the list they are.
  defp skips_a_date_unit?([{unit, _}, {clock, value} | _rest])
       when unit in @units_of_days and clock in @clock_units,
       do: not match?({:group, _members}, value)

  defp skips_a_date_unit?([_unit | rest]), do: skips_a_date_unit?(rest)
  defp skips_a_date_unit?(_units), do: false

  # A month's first day is asked of the calendar with its year, which counts
  # the month from the day the year begins (`UnitValues.with_first_day/2`).
  defp with_skipped_date_units(
         [{:year, year}, {:month, month}, {clock, _value} = time | rest],
         calendar
       )
       when is_integer(year) and is_integer(month) and clock in @clock_units,
       do: UnitValues.with_first_day([year: year, month: month], calendar) ++ [time | rest]

  defp with_skipped_date_units([{unit, _} = date_unit, {clock, _value} = time | rest], calendar)
       when unit in @units_of_days and clock in @clock_units,
       do: first_day_of(date_unit, calendar) ++ [time | rest]

  defp with_skipped_date_units([unit | rest], calendar),
    do: [unit | with_skipped_date_units(rest, calendar)]

  # A year's first day is the first of its first month, or of its first week
  # in a calendar of weeks.
  defp first_day_of({:year, year}, calendar) do
    if Tempo.week_based_calendar?(calendar),
      do: [year: group_start(year), week: 1, day_of_week: 1],
      else: UnitValues.with_first_day([year: group_start(year), month: 1], calendar)
  end

  defp first_day_of({:month, month}, _calendar), do: [month: group_start(month), day: 1]
  defp first_day_of({:week, week}, _calendar), do: [week: group_start(week), day_of_week: 1]

  defp group_start({:group, %Range{first: first}}) when is_integer(first), do: first
  defp group_start(value), do: value

  # A unit after a group counts from the group's start (ISO 8601-2 §5.4.2),
  # which makes the group one value. A group after a group is one value only
  # once what follows it has made it so: in `2G10DU2GT6HU30M` the minutes
  # make the hours one hour, and that hour then makes the days one day. So
  # units that still hold a group before a whole unit are resolved again,
  # until they stop changing.
  defp settle_groups(units, calendar) when is_list(units) do
    if group_before_whole_unit?(units),
      do: resolve_again(units, calendar),
      else: units
  end

  defp settle_groups(error, _calendar), do: error

  defp resolve_again(units, calendar) do
    case resolve(units, calendar) do
      ^units -> units
      resolved -> settle_groups(resolved, calendar)
    end
  end

  defp group_before_whole_unit?([{_unit, {:group, %Range{}}}, {_finer, value} | _rest])
       when is_integer(value),
       do: true

  defp group_before_whole_unit?([_unit | rest]), do: group_before_whole_unit?(rest)
  defp group_before_whole_unit?([]), do: false

  # Each date unit of a date written again in other units is worked out from
  # all of the units it was written with, so a qualification of any of them
  # qualifies every one: `2026-?06-15` in a calendar of weeks is
  # `2026-W25-1?`, and a week date a value holds as a calendar date
  # (`2026-W25-1?`) is `2026-06-15?`. A qualified time of day is its own.
  #
  # A value qualified as a whole (`T10H30S~`, ISO 8601-2 §8.2.1) is qualified
  # in each unit it is read with, the ones its text leaves out among them:
  # the minute of `T10H30S~`, the month and the day of `2026YT17H?`.
  defp qualify_converted(%Tempo{qualifications: %{}} = tempo, resolved, written, calendar)
       when is_list(resolved) do
    case Qualification.whole(tempo) do
      nil ->
        if written != calendar or qualified_unit_gone?(tempo, resolved),
          do: Qualification.rewritten(tempo, resolved),
          else: tempo

      qualification ->
        %{tempo | qualifications: Qualification.complete(resolved, qualification)}
    end
  end

  defp qualify_converted(tempo, _resolved, _written, _calendar), do: tempo

  defp qualified_unit_gone?(%Tempo{qualifications: qualifications}, resolved) do
    units = for entry <- resolved, is_tuple(entry), do: elem(entry, 0)
    Enum.any?(Map.keys(qualifications), &(&1 not in units))
  end

  # The calendar a value's units are written in: the one its calendar is read
  # in when they hold a month or a day, and otherwise its own.
  defp written_calendar(units, calendar) when is_list(units) do
    reading = reading_calendar(calendar)

    if reading != calendar and Enum.any?(units, &month_or_day?/1),
      do: reading,
      else: calendar
  end

  defp written_calendar(_units, calendar), do: calendar

  defp month_or_day?({unit, _value}) when unit in [:month, :day, :day_of_year], do: true
  defp month_or_day?(_other_unit), do: false

  # The calendar a calendar's dates are read in, as it answers: itself, or the
  # Gregorian calendar for a calendar of weeks. Calendrical answers
  # `Calendar.ISO`, which is the Gregorian calendar here.
  defp reading_calendar(calendar) do
    if Code.ensure_loaded?(calendar) and function_exported?(calendar, :parsing_calendar, 0),
      do: gregorian_for_iso(calendar.parsing_calendar()),
      else: calendar
  end

  defp gregorian_for_iso(Calendar.ISO), do: Calendrical.Gregorian
  defp gregorian_for_iso(calendar), do: calendar

  # A date that does not exist as it is written (30 February) is an
  # `InvalidDateError` from resolving it. One that exists and cannot be
  # converted, being less than a whole date, is a `ConversionError`, as it is
  # from `Tempo.to_calendar/2`.
  defp convert_date({:error, _reason} = error, _written, _calendar), do: error

  defp convert_date(
         [{:year, year}, {:month, month}, {:day, day} | rest] = units,
         written,
         calendar
       )
       when is_integer(year) and is_integer(month) and is_integer(day) do
    with {:ok, date} <- Date.new(year, month, day, written),
         {:ok, %Date{} = converted} <- Date.convert(date, calendar) do
      Tempo.date_units(converted.year, converted.month, converted.day, calendar) ++ rest
    else
      {:error, reason} ->
        {:error, ConversionError.exception(value: units, target: calendar, reason: reason)}
    end
  end

  defp convert_date(month_or_day_alone, written, calendar) do
    {:error,
     ConversionError.exception(
       value: month_or_day_alone,
       target: calendar,
       reason:
         "#{inspect(calendar)} has no month or day of a month of its own. A date written " <>
           "with them is read in #{inspect(written)} and converted, which takes a whole " <>
           "date: a year with a month and a day, or with a day of the year."
     )}
  end

  # A set with one member denotes exactly what that member denotes, so
  # collapse it to the bare value: `{12..12}M` becomes `12M`. Calendar
  # arithmetic takes concrete components — `days_in_month(2020, 12)`,
  # not `days_in_month(2020, [12..12])` — and a value written as a
  # one-member set is otherwise indistinguishable from one written
  # plainly.
  defp collapse_single_member_sets(units) when is_list(units) do
    Enum.map(units, fn
      {unit, [value]} when is_integer(value) -> {unit, value}
      {unit, [first..first//_step]} -> {unit, first}
      {unit, first..first//_step} -> {unit, first}
      other -> other
    end)
  end

  defp collapse_single_member_sets(units), do: units

  # A set of one member as it is written is its member before the value is
  # read, so that it is read as its member is: a week and the one day of it
  # in a set (`2026Y25W{1}K`) are the date they name, as `2026Y25W1K` is,
  # and were a week and a day that the value written back did not read as.
  # A set of one mask is the mask (`{198X}`), and one of a year with
  # significant digits or a margin of error that year (`{1950S2}`): each
  # was a set no span could be read from.
  #
  # A range with nothing around it is not one of these. It is how the walk
  # asks for a count from the end to be resolved where it stands (`-1..-1`,
  # `Tempo.Enumeration`), and is collapsed once that is done.
  defp sets_of_one_as_their_member(units) when is_list(units) do
    Enum.map(units, fn
      {unit, [value]} when is_integer(value) -> {unit, value}
      {unit, [{:mask, _digits} = mask]} -> {unit, mask}
      {unit, [{value, [_ | _]} = annotated]} when is_integer(value) -> {unit, annotated}
      {unit, [first..first//_step]} -> {unit, first}
      other -> other
    end)
  end

  defp sets_of_one_as_their_member(units), do: units

  # A count-from-the-end bound on a unit whose extent is fixed — the
  # clock units and the day-of-week — can always be resolved, because
  # nothing about the date changes how many minutes an hour has.
  # Resolving them here keeps them consistent with the units whose
  # extent the calendar decides (`{1..-1}M` as months becomes
  # `{1..12}M`), so a set-valued clock component is recognised as
  # set-valued rather than surviving as an inverted range that would
  # enumerate to nothing.
  defp resolve_fixed_extent_negatives(units, calendar) when is_list(units) do
    Enum.map(units, fn
      {unit, value} -> {unit, resolve_fixed_extent(value, unit, calendar)}
      other -> other
    end)
  end

  defp resolve_fixed_extent_negatives(units, _calendar), do: units

  defp resolve_fixed_extent(%Range{first: first, last: last} = range, unit, calendar)
       when first < 0 or last < 0 do
    case UnitValues.in_period(unit, [], calendar) do
      {:ok, valid} ->
        %{
          range
          | first: UnitValues.from_end(first, valid),
            last: UnitValues.from_end(last, valid)
        }

      {:error, _counted_in_a_date} ->
        range
    end
  end

  defp resolve_fixed_extent(value, unit, calendar) when is_list(value) do
    Enum.map(value, &resolve_fixed_extent(&1, unit, calendar))
  end

  defp resolve_fixed_extent(value, _unit, _calendar), do: value

  # An endpoint validates against its own calendar when it carries one —
  # a per-endpoint IXDTF `u-ca` suffix can make one endpoint of an
  # interval calendar-distinct from the other — falling back to the
  # interval-level calendar otherwise.
  defp endpoint_calendar(%Tempo{calendar: calendar}, _default) when not is_nil(calendar) do
    calendar
  end

  defp endpoint_calendar(_endpoint, default), do: default

  # ISO 8601 expects an interval's end to follow its start, so reject
  # a genuinely inverted interval such as `2026/2025`. The check is
  # deliberately narrow — it only fires when both endpoints are
  # anchored (a year is present) and fully concrete (no mask, group,
  # range, or set). This leaves two legitimate shapes untouched:
  #
  #   * Unanchored time-of-day intervals, where `from > to` is the
  #     representation of a midnight-crossing span (`T22/T02`).
  #
  #   * EDTF reduced-precision and masked intervals
  #     (`1111-01-01/1111`, `0000/0000`, `1919-XX-02/1919-XX-01`),
  #     whose end is a coarser or unknown span, not a real inversion.
  #
  # Inversion is judged against `to`'s *exclusive upper bound* (the
  # end of its own span), not its start. That is what keeps
  # `1111-01-01/1111` valid (the year 1111 ends in 1112, after the
  # start) while still rejecting `2026/2025` (the year 2025 ends
  # exactly where 2026 begins).
  defp validate_endpoint_order(%Tempo{} = from, %Tempo{} = to) do
    with true <- orderable?(from) and orderable?(to),
         {:ok, {_lower, to_upper}, _unit} <- Interval.next_unit_boundary(to),
         order when order != :earlier <- Compare.compare_endpoints(from, to_upper) do
      {:error,
       IntervalEndpointsError.exception(
         interval: %Tempo.Interval{from: from, to: to},
         operation: :validate,
         reason: "interval :from endpoint is not earlier than its :to endpoint"
       )}
    else
      _ -> :ok
    end
  end

  defp validate_endpoint_order(_from, _to), do: :ok

  # Orderable: anchored (has a year, so a UTC start exists) and fully
  # concrete (every component is a plain integer or a microsecond
  # `{value, precision}` pair — no mask, group, range, or set).
  defp orderable?(%Tempo{time: time}),
    do: List.keymember?(time, :year, 0) and Enum.all?(time, &concrete?/1)

  # A group of a set is an entry of three elements, and no one number.
  defp concrete?({_unit, value}) when is_integer(value), do: true

  defp concrete?({_unit, {value, precision}}) when is_integer(value) and is_integer(precision),
    do: true

  defp concrete?(_several), do: false

  # Resolution is the process of pre-calculating concrete
  # time units from groups whereever possible.

  def resolve([{:day_of_week, day} | rest], calendar) when is_integer(day) do
    with {:ok, days} <- values_in(:day_of_week, [], calendar),
         {:ok, day} <- conform(day, days, unit: :day_of_week, calendar: calendar) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:day_of_week, day} | resolved]
      end
    end
  end

  # A group within a group of the same unit, such as a group of years
  # after a century or decade, counts from the outer group's first value.
  # The two name one run of values, so they are resolved as one set.

  def resolve(
        [{unit, {:group, %Range{} = range1}}, {unit, {:group, %Range{} = range2}} | rest],
        calendar
      ) do
    first = range1.first + range2.first - Tempo.Math.unit_minimum(unit)

    if first in range1 do
      last = min(range1.last, first + range2.last - range2.first)
      resolve([{unit, [first..last//1]} | rest], calendar)
    else
      {:error,
       InvalidDateError.exception(
         unit: unit,
         value: first,
         valid_range: range1,
         calendar: calendar
       )}
    end
  end

  # A value after a group of its own unit counts within the group
  # (ISO 8601-2 §5.4.2): from 1 for a month or a day, so the second month
  # of the second quarter is May, and from 0 for an hour, minute or
  # second, so hour 0 of the third eight hours is 16:00. A negative value
  # counts from the group's end.
  def resolve([{unit, {:group, %Range{} = range}}, {unit, value} | rest], calendar)
      when is_integer(value) do
    within =
      if value < 0,
        do: range.last + value + 1,
        else: range.first + value - Tempo.Math.unit_minimum(unit)

    if within in range do
      resolve([{unit, within} | rest], calendar)
    else
      first = Tempo.Math.unit_minimum(unit)

      {:error,
       InvalidDateError.exception(
         unit: unit,
         value: value,
         valid_range: first..(first + range.last - range.first)//1,
         calendar: calendar
       )}
    end
  end

  def resolve([{:year, {:group, %Range{} = years}}, {:month, month} | rest], calendar)
      when is_integer(month) do
    months_in_group =
      years
      |> Enum.map(&calendar.months_in_year/1)
      |> Enum.sum()

    with {:ok, month} <- conform(month, 1..months_in_group),
         {:ok, year, month} <- year_and_month(years, month, calendar) do
      resolve([{:year, year}, {:month, month} | rest], calendar)
    end
  end

  # The nth day of a group of months. A group that runs past the year's
  # last month ends with it.
  def resolve(
        [{:year, year}, {:month, {:group, %Range{} = months}}, {:day, day} | rest],
        calendar
      )
      when is_integer(year) and is_integer(day) do
    months_in_year = calendar.months_in_year(year)

    with {:ok, _first_month} <- conform(months.first, 1..months_in_year),
         months = months.first..min(months.last, months_in_year)//1,
         days_in_group =
           months |> Enum.map(&UnitValues.days_in_counted_month(year, &1, calendar)) |> Enum.sum(),
         {:ok, day} <- conform(day, 1..days_in_group),
         {:ok, month, day} <- month_and_day(year, months, day, calendar) do
      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    end
  end

  # A week date (`W`) is an ISO 8601 week: in a month-based calendar ISO
  # 8601's rule applied to the calendar's own year (weeks from Monday,
  # week 1 the one holding the year's fourth day), and in a week-based
  # calendar its own week. The calendar's own weeks are written `w`, and
  # `Tempo.Iso8601.Group` resolves them to dates.
  #
  # Resolution of (year, week, day) to a concrete calendar date
  # depends on the calendar's base:
  #
  #   * `:month`-based (Gregorian and the other civil calendars) — the
  #     day of the ISO 8601 week, as a `[year, month, day]` value.
  #
  #   * `:week`-based (`Calendrical.ISOWeek` and the week-based fiscal
  #     calendars) — keep the `[year, week, day_of_week]` shape, the
  #     calendar's own week and day.
  def resolve([{:year, year}, {:week, week}, {:day_of_week, day} | rest], calendar)
      when is_integer(year) and is_integer(week) and is_integer(day) do
    with {:ok, weeks} <- values_in(:week, [year: year], calendar),
         {:ok, week} <- conform(week, weeks, unit: :week, year: year, calendar: calendar),
         [day_of_week: day] <- resolve([day_of_week: day], calendar) do
      year_week_day(year, week, day, rest, calendar.calendar_base(), calendar)
    end
  end

  def resolve([{:year, year}, {:day, day_of_year} | rest], calendar)
      when is_integer(year) and is_integer(day_of_year) do
    with {:ok, days} <- values_in(:day_of_year, [year: year], calendar),
         {:ok, day_of_year} <-
           conform(day_of_year, days, unit: :day_of_year, year: year, calendar: calendar) do
      %{year: year, month: month, day: day} =
        Calendrical.date_from_day_of_year(year, day_of_year, calendar)

      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    end
  end

  # A day of the year (ISO 8601-2 §4.3.4) after its year is that year's
  # ordinal day, as a monthless day after a year is. A set of them stays a
  # day of the year, each resolved when the set is expanded.
  def resolve([{:year, year}, {:day_of_year, day} | rest], calendar)
      when is_integer(year) and is_number(day),
      do: resolve([{:year, year}, {:day, day} | rest], calendar)

  def resolve([{:year, year}, {:day_of_year, days}], calendar)
      when is_integer(year) and (is_list(days) or is_struct(days, Range)) do
    with {:ok, days_of_year} <- values_in(:day_of_year, [year: year], calendar),
         {:ok, days} <-
           conform(days, days_of_year, unit: :day_of_year, year: year, calendar: calendar) do
      [{:year, year}, {:day_of_year, days}]
    end
  end

  def resolve(
        [{:year, year}, {:day, {:group, %Range{} = days_of_year}}, {:day, day} | rest],
        calendar
      )
      when is_integer(year) and is_integer(day) do
    %{first: first, last: last} = days_of_year
    days_in_year = calendar.days_in_year(year)
    last = min(last, days_in_year)
    day = if day < 0, do: last + day + 1, else: first + day - 1

    if first in 1..days_in_year and day <= last do
      %{year: year, month: month, day: day} =
        Calendrical.date_from_day_of_year(year, day, calendar)

      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    else
      {:error,
       InvalidDateError.exception(
         unit: :day_of_year,
         value: abs(day),
         valid_range: days_of_year,
         year: year,
         calendar: calendar
       )}
    end
  end

  # The hours of a year count from 0 at its start, as the hours of a day
  # do, so the twentieth group of twelve hours is hours 228..239 (noon to
  # midnight on the tenth day) and an hour within it counts from the
  # group's first.
  def resolve(
        [{:year, year}, {:hour, {:group, %Range{} = hours_of_year}}, {:hour, hour} | rest],
        calendar
      )
      when is_integer(year) and is_integer(hour) do
    %{first: first, last: last} = hours_of_year
    last = min(last, calendar.days_in_year(year) * @hours_per_day - 1)
    hour_of_year = if hour < 0, do: last + hour + 1, else: first + hour

    with {:ok, hour_of_year} <- conform(hour_of_year, first..last//1) do
      day_of_year = div(hour_of_year, @hours_per_day) + 1

      %{year: year, month: month, day: day} =
        Calendrical.date_from_day_of_year(year, day_of_year, calendar)

      resolve(
        [
          {:year, year},
          {:month, month},
          {:day, day},
          {:hour, rem(hour_of_year, @hours_per_day)} | rest
        ],
        calendar
      )
    end
  end

  def resolve(
        [{:year, year}, {:month, month}, {:day, {:group, %Range{} = days}} | rest],
        calendar
      )
      when is_integer(year) and is_integer(month) do
    with {:ok, months} <- values_in(:month, [year: year], calendar),
         {:ok, month} <- conform(month, months, unit: :month, year: year, calendar: calendar),
         {:ok, days_of_month} <- days_of_month(calendar, year, month) do
      case resolve_day_group(days, last_value(days_of_month), rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:year, year}, {:month, month} | resolved]
      end
    end
  end

  # days needs to start at 1
  def resolve([{:day, {:group, %Range{} = range}}, {:hour, hours} | rest], calendar)
      when is_integer(hours) do
    first = (range.first - 1) * @hours_per_day
    last = range.last * @hours_per_day - 1
    hours = hours + first

    with {:ok, hours} <- conform(hours, first..last) do
      days = div(hours, @hours_per_day)
      hours = rem(hours, @hours_per_day)
      resolve([{:day, days + 1}, {:hour, hours} | rest], calendar)
    end
  end

  # A group of hours holds clock hours, from 0, so its minutes start at
  # its first hour's first minute.
  def resolve([{:hour, {:group, %Range{} = range}}, {:minute, minutes} | rest], calendar)
      when is_integer(minutes) do
    first = range.first * @minutes_per_hour
    last = (range.last + 1) * @minutes_per_hour - 1
    minutes = minutes + first

    with {:ok, minutes} <- conform(minutes, first..last) do
      hours = div(minutes, @minutes_per_hour)
      minutes = rem(minutes, @minutes_per_hour)

      resolve([{:hour, hours}, {:minute, minutes} | rest], calendar)
    end
  end

  # A group of minutes holds clock minutes, from 0, so its seconds start
  # at its first minute's first second.
  def resolve([{:minute, {:group, %Range{} = range}}, {:second, seconds} | rest], calendar)
      when is_integer(seconds) do
    first = range.first * @minutes_per_hour
    last = (range.last + 1) * @minutes_per_hour - 1
    seconds = seconds + first

    with {:ok, seconds} <- conform(seconds, first..last) do
      minutes = div(seconds, @minutes_per_hour)
      seconds = rem(seconds, @minutes_per_hour)

      resolve([{:minute, minutes}, {:second, seconds} | rest], calendar)
    end
  end

  # An unspecified traditional month (`X*m`) is any month of its year, however
  # the calendar numbers them, so it is an unspecified month.
  def resolve([{:traditional_month, :any} | rest], calendar),
    do: resolve([{:month, :any} | rest], calendar)

  # An intercalary month `{n, :leap}` (parsed from `<n>+m`) resolves to its
  # ordinal position for the year against a calendar with leap months; the rest of
  # the pipeline then sees an ordinary integer month. Any calendar without a
  # leap month at that traditional position is rejected.
  def resolve([{:year, year}, {:traditional_month, {month, :leap}} | rest], calendar)
      when is_integer(year) and is_integer(month) do
    case leap_month_ordinal(calendar, year, month) do
      {:ok, ordinal} -> resolve([{:year, year}, {:month, ordinal} | rest], calendar)
      {:error, _} = error -> error
    end
  end

  # A traditional month `n` (parsed from `<n>m`) resolves to its ordinal
  # position for the year against a calendar with leap months; on any other
  # calendar the traditional and ordinal numberings coincide, so it passes
  # through as `n`. The traditional→ordinal step is Calendrical's — a concrete
  # year is known, so `ordinal_month_from_traditional/3` yields the ordinal month.
  def resolve([{:year, year}, {:traditional_month, month} | rest], calendar)
      when is_integer(year) and is_integer(month) do
    case ordinal_month_from_traditional(calendar, year, month) do
      {:ok, ordinal} -> resolve([{:year, year}, {:month, ordinal} | rest], calendar)
      {:error, _} = error -> error
    end
  end

  def resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
      when is_integer(year) and is_integer(month) and
             (is_number(day) or is_struct(day, Range) or is_list(day)) do
    with [{:year, year}, {:month, month}] <- resolve([{:year, year}, {:month, month}], calendar),
         {:ok, days} <- days_of_month(calendar, year, month),
         {:ok, day} <-
           conform(day, days, unit: :day, year: year, month: month, calendar: calendar) do
      prepend_year_month(year, month, resolve([{:day, day} | rest], calendar))
    end
  end

  def resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
      when (is_integer(year) and is_integer(month)) or is_list(month) do
    with [{:year, year}, {:month, month}] <- resolve([{:year, year}, {:month, month}], calendar) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:year, year}, {:month, month}, {:day, day} | resolved]
      end
    end
  end

  def resolve([{:year, year}, {:month, months}], calendar)
      when is_integer(year) and
             (is_list(months) or is_integer(months) or is_struct(months, Range)) do
    with {:ok, months_of_year} <- values_in(:month, [year: year], calendar),
         {:ok, month} <-
           conform(months, months_of_year, unit: :month, year: year, calendar: calendar) do
      [{:year, year}, {:month, month}]
    end
  end

  # A month followed by a time of day with no day between them
  # (`2026Y-1MT10H`) is the month its year counts, and the time as it is.
  def resolve([{:year, year}, {:month, months}, {unit, _value} = time | rest], calendar)
      when is_integer(year) and unit in [:hour, :minute, :second] and
             (is_list(months) or is_integer(months) or is_struct(months, Range)) do
    with [{:year, year}, {:month, month}] <- resolve([{:year, year}, {:month, months}], calendar),
         resolved when is_list(resolved) <- resolve([time | rest], calendar) do
      [{:year, year}, {:month, month} | resolved]
    end
  end

  def resolve([{:year, year}, {:week, weeks}], calendar)
      when is_integer(year) and
             (is_list(weeks) or is_integer(weeks) or is_struct(weeks, Range)) do
    with {:ok, weeks_of_year} <- values_in(:week, [year: year], calendar),
         {:ok, weeks} <-
           conform(weeks, weeks_of_year, unit: :week, year: year, calendar: calendar) do
      [{:year, year}, {:week, weeks}]
    end
  end

  def resolve([{:year, year}, {:day, days}], calendar)
      when is_integer(year) and (is_list(days) or is_integer(days) or is_struct(days, Range)) do
    with {:ok, days_of_year} <- values_in(:day_of_year, [year: year], calendar),
         {:ok, day} <-
           conform(days, days_of_year, unit: :day_of_year, year: year, calendar: calendar) do
      [{:year, year}, {:day, day}]
    end
  end

  # A day *set* under a month whose length is not yet known — because
  # the year is absent, or set-valued and still to be expanded — is
  # bounded by the month's maximum length across years, exactly as a
  # single day is above: `2M{1..-1}D` is possible (February has a 29th
  # in some year) while `2M{30..31}D` is not. Which days actually
  # exist is settled per member during expansion, where the year is
  # concrete — so this must bound rather than refuse, or
  # `{2020,2021}Y2M{1..-1}D` could never resolve at all.
  def resolve([{:month, month}, {:day, days} | rest], calendar)
      when is_integer(month) and (is_list(days) or is_struct(days, Range)) do
    with {:month, ^month} <- resolve({:month, month}, calendar) do
      yearless_month_and_day(month, days, rest, calendar)
    end
  end

  # A day of the year counts from its year's first day, so it never follows a
  # month.
  def resolve([{:month, _month}, {:day_of_year, _day} | _rest], _calendar) do
    {:error,
     InvalidDateError.exception(
       reason:
         "A day of the year (O) counts from the first day of its year, so it cannot follow a month."
     )}
  end

  # A bare (yearless) month + integer day is a partial date — a
  # first-class Tempo value, but only when it could occur in *some*
  # year. `~o"3M2D"` is fine; `~o"2M30D"` (February 30th) happens in
  # no year and is rejected. The bound is the month's maximum length
  # across all years (see `max_day_in_month/2`); a month whose length
  # cannot be bounded without a year is left as-is, since Tempo cannot
  # prove it impossible.
  def resolve([{:month, month}, {:day, day} | rest], calendar)
      when is_integer(month) and is_integer(day) do
    with {:month, ^month} <- resolve({:month, month}, calendar) do
      yearless_month_and_day(month, day, rest, calendar)
    end
  end

  # Calculating the result of fractional time units. A fraction is the
  # part of the unit that has elapsed, as it is for a day (`5.5D` is noon
  # on the 5th), so half of 1985 is 182.5 days after its start, noon on
  # 2 July, and the day it lands on is one more than the days elapsed.
  # TODO Support negative time fractions

  def resolve([{:year, year}], calendar) when is_float(year) and year > 0 do
    int_year = trunc(year)
    fraction_of_year = year - int_year
    days_in_year = calendar.days_in_year(int_year)

    if fraction_of_year == 0 do
      resolve([{:year, int_year}], calendar)
    else
      days = Math.round(days_in_year * fraction_of_year, @rounding_precision)
      days = if trunc(days) == days, do: trunc(days), else: days
      resolve([{:year, int_year}, {:day, days + 1}], calendar)
    end
  end

  def resolve([{:year, year}, {:month, month}], calendar)
      when is_integer(year) and is_float(month) and month > 0 do
    int_month = trunc(month)
    fraction_of_month = month - int_month
    days_in_month = calendar.days_in_month(year, int_month)

    if fraction_of_month == 0 do
      resolve([{:year, year}, {:month, int_month}], calendar)
    else
      days = Math.round(days_in_month * fraction_of_month, @rounding_precision)
      days = if trunc(days) == days, do: trunc(days), else: days
      resolve([{:year, year}, {:month, int_month}, {:day, days + 1}], calendar)
    end
  end

  def resolve([{:year, year}, {:day, day}], calendar)
      when is_integer(year) and is_float(day) and day > 0 do
    int_day = trunc(day)
    fraction_of_day = day - int_day

    if fraction_of_day == 0 do
      resolve([{:year, year}, {:day, int_day}], calendar)
    else
      hours = Math.round(@hours_per_day * fraction_of_day, @rounding_precision)
      hours = if trunc(hours) == hours, do: trunc(hours), else: hours
      resolve([{:year, year}, {:day, int_day}, {:hour, hours}], calendar)
    end
  end

  def resolve([{:day, day}], calendar) when is_float(day) and day > 0 do
    int_day = trunc(day)
    fraction_of_day = day - int_day

    if fraction_of_day == 0 do
      [{:day, int_day}]
    else
      hours = Math.round(@hours_per_day * fraction_of_day, @rounding_precision)
      hours = if trunc(hours) == hours, do: trunc(hours), else: hours
      resolve([{:day, int_day}, {:hour, hours}], calendar)
    end
  end

  # A fraction of an hour is read to the minute, and a fraction of a minute
  # to the second, as ISO 8601-2 §7.12 reads them: `0,5H` is 00:30 "with
  # minute precision" and `30.5M` thirty seconds past "with second
  # precision". A fraction that does not land on a whole minute or second is
  # the minute or the second the time falls in (`T10.51` is 10:30), so the
  # value holds whole numbers: a fractional minute left in it was a value no
  # operation could read, and one its own text read back as another.
  def resolve([{:hour, hour}], _calendar) when is_float(hour) and hour > 0 do
    int_hour = trunc(hour)
    fraction_of_hour = hour - int_hour

    if fraction_of_hour == 0 do
      [{:hour, int_hour}]
    else
      minutes = Math.round(60 * fraction_of_hour, @rounding_precision)
      [{:hour, int_hour}, {:minute, trunc(minutes)}]
    end
  end

  def resolve([{:minute, minute}], _calendar) when is_float(minute) do
    int_minute = trunc(minute)
    fraction_of_minute = minute - int_minute

    if fraction_of_minute == 0 do
      [{:minute, int_minute}]
    else
      seconds = Math.round(60 * fraction_of_minute, @rounding_precision)
      [{:minute, int_minute}, {:second, trunc(seconds)}]
    end
  end

  # Fill in the blanks with default unit values
  def resolve([{unit_1, value_1}, {:minute, minute} | rest], calendar) when unit_1 != :hour do
    resolve([{unit_1, value_1}, {:hour, 0}, {:minute, minute} | rest], calendar)
  end

  def resolve([{unit_1, value_1}, {:second, second} | rest], calendar) when unit_1 != :minute do
    resolve([{unit_1, value_1}, {:minute, 0}, {:second, second} | rest], calendar)
  end

  # Make sure only the last element is a fraction

  def resolve([{_unit, fraction}, {_unit_2, _value} | _rest], _calendar)
      when is_float(fraction) do
    {:error,
     ParseError.exception(
       reason:
         "A fractional unit can only be used for the highest resolution unit (smallest time unit)"
     )}
  end

  def resolve([{:hour, hour} | rest], calendar) when is_integer(hour) do
    with {:ok, hour} <- conform(hour, 0..(@hours_per_day - 1), unit: :hour) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:hour, hour} | resolved]
      end
    end
  end

  # A set of seconds takes the fraction written after it, as one second
  # does (below): `{45,46}.5S` is 45.5 and 46.5 seconds. It stayed a
  # `:fraction`, which nothing after the parser reads.
  def resolve([{:second, seconds}, {:fraction, {digits, digit_count}} | rest], calendar)
      when is_list(seconds) and is_integer(digits) do
    microsecond = Microsecond.from_fraction(digits, digit_count)
    resolve([{:second, seconds}, {:microsecond, microsecond} | rest], calendar)
  end

  # The fractions of a second written as a set (`45.{0..9}S`, the form
  # `Tempo.extend/2` gives a second) are the microseconds of each, after
  # one second or after each of a set of them.
  def resolve([{:second, seconds}, {:fractions, written} | rest], calendar) do
    with {:ok, microseconds} <- microseconds_written(written) do
      resolve([{:second, seconds}, {:microsecond, microseconds} | rest], calendar)
    end
  end

  # A set or a range of hours, minutes, seconds or days of the week is held
  # to the values the unit takes, as one of days or months is: `T{22..25}H`
  # names two hours no day has.
  def resolve([{unit, written} | rest], calendar)
      when unit in [:hour, :minute, :second, :day_of_week] and
             (is_list(written) or is_struct(written, Range)) do
    with {:ok, valid} <- UnitValues.in_period(unit, [], calendar),
         {:ok, written} <- conform(written, valid, unit: unit) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{unit, written} | resolved]
      end
    end
  end

  def resolve([{:minute, requested} | rest], calendar) when is_integer(requested) do
    with {:ok, part} <- conform(requested, 0..(@minutes_per_hour - 1), unit: :minute) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:minute, part} | resolved]
      end
    end
  end

  # A fractional second arrives as a sibling `{:fraction, {digits,
  # count}}` token — the seconds parser keeps it separate rather than
  # folding it into a float. Lift it into a `:microsecond {value,
  # precision}` component so the digit count (and therefore the
  # resolution / interval width) is preserved; `.120` and `.12` differ.
  def resolve([{:second, second}, {:fraction, {digits, digit_count}} | rest], calendar)
      when is_integer(second) and is_integer(digits) do
    microsecond = Microsecond.from_fraction(digits, digit_count)
    resolve([{:second, second}, {:microsecond, microsecond} | rest], calendar)
  end

  # Negative seconds wrap using a 0..59 range (the end-of-minute
  # reference is 59, not 60 — `-1` means "one before the end",
  # which is 59, not the leap-second 60).
  def resolve([{:second, requested} | rest], calendar)
      when is_integer(requested) and requested < 0 do
    with {:ok, part} <- conform(requested, 0..(@minutes_per_hour - 1), unit: :second) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:second, part} | resolved]
      end
    end
  end

  # Positive seconds may take the value 60 for a leap second. The
  # context (hour = 23, minute = 59, and — if present — the calendar
  # date) is checked by `validate_leap_second/2` before we get here.
  def resolve([{:second, requested} | rest], calendar) when is_integer(requested) do
    with {:ok, part} <- conform(requested, 0..@minutes_per_hour, unit: :second) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:second, part} | resolved]
      end
    end
  end

  # Sub-second component: a `{value, precision}` microsecond tuple that
  # rides immediately after the second. Range-validate it and pass it
  # through unchanged. A *list* of microsecond tuples is the enumeration
  # form produced by `Tempo.Enumeration.add_implicit_enumeration/1`
  # when a sub-second value is iterated — validate each element.
  def resolve([{:microsecond, list} | rest], calendar) when is_list(list) do
    if Enum.all?(list, &Microsecond.valid?/1) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:microsecond, list} | resolved]
      end
    else
      {:error, ParseError.exception(reason: "Invalid microsecond enumeration #{inspect(list)}")}
    end
  end

  # Guard the value pattern as `{integer, integer}` so the
  # continuation-wrapped form `{{value, precision}, function}` produced
  # by `Enumeration.do_next/3` falls through to the generic clause and
  # passes through unchanged.
  def resolve([{:microsecond, {value, precision}} | rest], calendar)
      when is_integer(value) and is_integer(precision) do
    if Microsecond.valid?({value, precision}) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:microsecond, {value, precision}} | resolved]
      end
    else
      {:error,
       ParseError.exception(
         reason: "Invalid microsecond component #{inspect({value, precision})}"
       )}
    end
  end

  # A group of a set (`{1,2}G3MU`) is an entry of three elements, which no
  # clause above reads, so nothing after one was resolved: an hour 25 after
  # one was read (`2026Y{1,2}G3MU15DT25H`), and a fraction of a second was
  # left as the parser's `:fraction`, which nothing after the parser reads
  # and `inspect/1` raised on.
  #
  # The unit after the group is counted from the start of each group it
  # names (the day of `{1,2}G3MU32D` is 1 February and 2 May), so it is
  # bounded where each group is taken apart, in `Tempo.to_interval/2`. The
  # units after that one are what they are after any value.
  def resolve([{_unit, {:group, _members}, _size} = group | rest], calendar) do
    with rest when is_list(rest) <- resolve_after_a_group_of_a_set(rest, calendar) do
      [group | rest]
    end
  end

  # A year still to be expanded — a set, a range, a mask, an unspecified
  # year — bounds the days of its months only once each of its values is
  # known.
  def resolve([{:year, years} = year | rest], calendar) when not is_integer(years) do
    with {:year, _} = year <- resolve(year, calendar),
         rest when is_list(rest) <- resolve_under_years(rest, calendar) do
      [year | rest]
    end
  end

  def resolve([{unit, _value} = first | rest], calendar) do
    with {^unit, _} = first <- resolve(first, calendar),
         rest when is_list(rest) <- resolve(rest, calendar) do
      [first | rest]
    end
  end

  # A unit with nothing above it to bound it — a day of no month, a day of no
  # year, a month or a week of no year — names no time at 0, since each counts
  # from 1 (or back from the end when negative). A month is no further from
  # either end than the most months a year of its calendar has; a day and a
  # week are bounded once they have a year.
  def resolve({unit, value} = component, calendar)
      when unit in [:day, :day_of_year, :month, :week, :calendar_week] do
    cond do
      names_zero?(value) -> {:error, zeroth_error(unit)}
      unit == :month -> bounded_months(component, calendar)
      true -> component
    end
  end

  def resolve(other, _calendar) do
    other
  end

  ### Helpers

  # The units that count from 1, so that 0 names none of them.
  @counted_from_one [:month, :week, :calendar_week, :day, :day_of_year, :day_of_week]

  # The units after a group of a set. The first is counted in each group, and
  # is no unit at 0 where it counts from 1; the units after it are resolved
  # as the units of any value are.
  #
  # A second counted in a group (`T10H{1,2}G10MU45.25S`) takes the fraction
  # written after it, as any second does.
  defp resolve_after_a_group_of_a_set(
         [{:second, _seconds} = counted, {:fraction, {digits, digit_count}} | rest],
         calendar
       ) do
    microsecond = Microsecond.from_fraction(digits, digit_count)

    with rest when is_list(rest) <- resolve([{:microsecond, microsecond} | rest], calendar),
         do: [counted | rest]
  end

  defp resolve_after_a_group_of_a_set(
         [{:second, _seconds} = counted, {:fractions, written} | rest],
         calendar
       ) do
    with {:ok, microseconds} <- microseconds_written(written),
         rest when is_list(rest) <- resolve([{:microsecond, microseconds} | rest], calendar),
         do: [counted | rest]
  end

  defp resolve_after_a_group_of_a_set([{unit, value} = counted | rest], calendar) do
    if unit in @counted_from_one and names_zero?(value) do
      {:error, zeroth_error(unit)}
    else
      with rest when is_list(rest) <- resolve(rest, calendar), do: [counted | rest]
    end
  end

  defp resolve_after_a_group_of_a_set(units, calendar), do: resolve(units, calendar)

  # The most fractions of a second a range may name. A value holds each
  # fraction it names, so a range is listed as it is read: a thousand is each
  # millisecond of a second, and with no bound a text of twenty characters
  # would list a million.
  @most_fractions_in_a_range 1_000

  # The finest a fraction of a second is held: a microsecond.
  @most_fraction_digits 6

  # How many of the fractions written an error shows.
  @fractions_shown 8

  # The microseconds of the fractions of a second written as a set, one by
  # one (`.{0,5}`) or from a first to a last (`.{50..59}`). Each is written
  # with as many digits, which are the precision the set is held to.
  defp microseconds_written({:range, {first, digits}, {last, digits}} = written) do
    cond do
      digits > @most_fraction_digits ->
        fractions_error(written, "are finer than a microsecond")

      first > last ->
        fractions_error(written, "run back from the first to the last")

      last - first >= @most_fractions_in_a_range ->
        fractions_error(written, "are more than a thousand in one range")

      true ->
        {:ok, for(fraction <- first..last, do: Microsecond.from_fraction(fraction, digits))}
    end
  end

  defp microseconds_written({:range, _first, _last} = written),
    do: fractions_error(written, "are not written with as many digits as each other")

  defp microseconds_written([{_fraction, digits} | _rest] = written) do
    cond do
      Enum.any?(written, fn {_fraction, count} -> count != digits end) ->
        fractions_error(written, "are not written with as many digits as each other")

      digits > @most_fraction_digits ->
        fractions_error(written, "are finer than a microsecond")

      true ->
        {:ok, written |> Enum.map(&microsecond_written/1) |> Enum.sort() |> Enum.dedup()}
    end
  end

  defp microsecond_written({fraction, digits}), do: Microsecond.from_fraction(fraction, digits)

  defp fractions_error(written, what_is_wrong) do
    {:error,
     ParseError.exception(
       reason:
         "The fractions of a second in .{#{fractions_text(written)}} #{what_is_wrong}. " <>
           "A set of them is written one by one or from a first to a last, each with " <>
           "as many digits and none finer than a microsecond."
     )}
  end

  defp fractions_text({:range, first, last}),
    do: fraction_text(first) <> ".." <> fraction_text(last)

  # The first few of a long list say what was written.
  defp fractions_text(written) do
    {shown, more} = Enum.split(written, @fractions_shown)
    text = Enum.map_join(shown, ",", &fraction_text/1)
    if more == [], do: text, else: text <> ",…"
  end

  defp fraction_text({fraction, digits}),
    do: fraction |> Integer.to_string() |> String.pad_leading(digits, "0")

  # A group is kept as declared, so it renders as written; one that
  # starts beyond its container (months 13..15 of a twelve-month year)
  # names no time and is an error.
  defp validated_groups(tempo, time, calendar) do
    case Group.bound_groups(time, calendar) do
      {:ok, _bounded} -> {:ok, %{tempo | time: time}}
      {:error, _exception} = error -> error
    end
  end

  # A group of days is kept as declared (the last group of eleven days
  # in February is days 23..33); a component within it resolves against
  # the days the month has.
  defp resolve_day_group(days, _max_days, [], _calendar), do: [{:day, {:group, days}}]

  defp resolve_day_group(days, max_days, rest, calendar),
    do: resolve([{:day, {:group, %{days | last: min(max_days, days.last)}}} | rest], calendar)

  defp prepend_year_month(_year, _month, {:error, reason}), do: {:error, reason}

  defp prepend_year_month(year, month, resolved),
    do: [{:year, year}, {:month, month} | resolved]

  # The days of a month of a year, which `Tempo.UnitValues` counts. A month
  # the year does not have (a thirteenth, in a Hebrew year of twelve) is
  # reported as missing, and not as a month of no days.
  defp days_of_month(calendar, year, month) do
    case UnitValues.in_period(:day, [year: year, month: month], calendar) do
      {:ok, %Range{last: last} = days} when last > 0 ->
        {:ok, days}

      # The days a calendar lists apart from one another: those of a month
      # with days missing in it.
      {:ok, [%Range{} | _] = days} ->
        {:ok, days}

      _no_such_month ->
        {:error,
         InvalidDateError.exception(
           year: year,
           month: month,
           reason: "month #{month} does not exist in #{inspect(calendar)} year #{year}"
         )}
    end
  end

  # The values a unit takes in the period the units before it name: the
  # months, the weeks or the days of a year, the days of a week. It is
  # `Tempo.UnitValues` that asks the calendar, and a calendar that cannot
  # count them leaves no value to be valid.
  defp values_in(unit, context, calendar) do
    case UnitValues.in_period(unit, context, calendar) do
      {:ok, values} ->
        {:ok, values}

      {:error, _cannot_count} ->
        {:error,
         InvalidDateError.exception(
           unit: unit,
           calendar: calendar,
           reason:
             "#{inspect(calendar)} does not count the values of #{unit} in #{inspect(context)}"
         )}
    end
  end

  # The ordinal position of the intercalary month following traditional month
  # `month` in `year`. Only a calendar with leap months (Hebrew, lunisolar) has
  # one — it exposes `leap_month/1` (the ordinal of the leap month, or a
  # non-integer when the year has none) and `traditional_leap_month/1` (its
  # traditional number).
  defp leap_month_ordinal(calendar, year, month) do
    if function_exported?(calendar, :leap_month, 1) and
         function_exported?(calendar, :traditional_leap_month, 1) do
      resolve_leap_month_ordinal(calendar, year, month)
    else
      {:error,
       InvalidDateError.exception(
         year: year,
         month: month,
         reason: "#{inspect(calendar)} has no leap months, so `#{month}+m` is invalid"
       )}
    end
  end

  defp resolve_leap_month_ordinal(calendar, year, month) do
    with ordinal when is_integer(ordinal) <- calendar.leap_month(year),
         ^month <- calendar.traditional_leap_month(year) do
      {:ok, ordinal}
    else
      _no_such_leap_month ->
        {:error,
         InvalidDateError.exception(
           year: year,
           month: month,
           reason:
             "#{inspect(calendar)} year #{year} has no leap month following traditional month #{month}"
         )}
    end
  end

  @doc """
  Resolves a traditional month to its ordinal position in a year.

  `month` is a traditional month number, or the `{n, :leap}` tuple for the
  intercalary month following traditional `n`. On a calendar with leap months
  (Hebrew, lunisolar) a leap month shifts the numbering, so the traditional→ordinal step is Calendrical's:
  the calendar's `ordinal_month_from_traditional/2`, or, for a lunisolar calendar without it,
  `new/3` at day 1 (always valid), which builds the date and reports its
  ordinal `month`. On any other calendar the two numberings coincide and an
  integer `month` is returned unchanged. Returns `{:ok, ordinal}`, or
  `{:error, :invalid_date}` when the calendar's year carries no such month (e.g.
  a leap month it does not have). Shared by concrete-date validation and
  per-year selection materialisation.
  """
  def ordinal_month_from_traditional(calendar, year, month) do
    cond do
      function_exported?(calendar, :ordinal_month_from_traditional, 2) ->
        case calendar.ordinal_month_from_traditional(year, month) do
          {:ok, ordinal} -> {:ok, ordinal}
          {:error, _reason} -> {:error, :invalid_date}
        end

      function_exported?(calendar, :leap_month, 1) and function_exported?(calendar, :new, 3) ->
        case calendar.new(year, month, 1) do
          {:ok, %{month: ordinal}} -> {:ok, ordinal}
          {:error, _} = error -> error
        end

      true ->
        {:ok, month}
    end
  end

  # The maximum day number a month can hold across all years — the
  # bound for validating a yearless partial: the last day of the year the
  # month is longest in (February's 29th), which `Tempo.UnitValues` asks the
  # calendar for. Where the calendar cannot say without a year, the day is
  # not checked.
  defp max_day_in_month(calendar, month) do
    case UnitValues.in_any_year(:day, [month: month], calendar) do
      {:ok, _every_year, %Range{last: longest}} -> {:ok, longest}
      {:error, _cannot_say} -> :unknown
    end
  end

  # The units under a year still to be expanded. A day counted from the end of
  # its month (`{2026,2027}Y2M-1D`, the last day of each February) is left for
  # each year to resolve, as a walk of the value reads it, and not read as a
  # day of a month in no year, which made it the 29th.
  defp resolve_under_years([{:month, month} = month_unit, {:day, days} = day | rest], calendar)
       when is_integer(month) do
    if counts_from_end?(days) do
      with {:month, ^month} <- resolve(month_unit, calendar),
           rest when is_list(rest) <- resolve(rest, calendar) do
        [month_unit, day | rest]
      end
    else
      resolve([month_unit, day | rest], calendar)
    end
  end

  defp resolve_under_years(units, calendar), do: resolve(units, calendar)

  defp counts_from_end?(value) when is_integer(value), do: value < 0
  defp counts_from_end?(%Range{first: first, last: last}), do: first < 0 or last < 0
  defp counts_from_end?(values) when is_list(values), do: Enum.any?(values, &counts_from_end?/1)
  defp counts_from_end?(_value), do: false

  # A yearless month's day, bounded by the month's longest length across years
  # (see `max_day_in_month/2`). A month whose length cannot be bounded without
  # a year is left as it is, since Tempo cannot prove the day impossible.
  #
  # A day counted from the end of a month whose length depends on the year
  # cannot be counted until the value has one: the last day of February is
  # the 28th or the 29th. It is kept as written, as it is in a calendar
  # whose months have no fixed length, and placing the value on a year
  # counts it there (`~o"2M-1D"` on 2027 is 28 February). It is still
  # checked against the longest the month can be: February has no thirtieth
  # day from its end.
  defp yearless_month_and_day(month, day, rest, calendar) do
    case {max_day_in_month(calendar, month), counted_in_any_year?(day, month, calendar)} do
      {{:ok, max_day}, true} ->
        with {:ok, day} <- conform(day, 1..max_day, unit: :day, month: month, calendar: calendar),
             rest when is_list(rest) <- resolve(rest, calendar) do
          [{:month, month}, {:day, day} | rest]
        end

      {{:ok, max_day}, false} ->
        with {:ok, _possible} <-
               conform(day, 1..max_day, unit: :day, month: month, calendar: calendar),
             rest when is_list(rest) <- resolve(rest, calendar) do
          [{:month, month}, {:day, day} | rest]
        end

      {:unknown, _counted?} ->
        with rest when is_list(rest) <- resolve(rest, calendar) do
          [{:month, month}, {:day, day} | rest]
        end
    end
  end

  # Whether a yearless month's day is the same day in every year: one counted
  # from the month's start always is, and one counted from its end is where
  # the month is as long in every year.
  defp counted_in_any_year?(day, month, calendar) do
    not counts_from_end?(day) or
      match?({:ok, days, days}, UnitValues.in_any_year(:day, [month: month], calendar))
  end

  defp names_zero?(0), do: true
  defp names_zero?(%Range{first: first, last: last}), do: first == 0 or last == 0
  defp names_zero?(values) when is_list(values), do: Enum.any?(values, &names_zero?/1)
  defp names_zero?(_value), do: false

  defp zeroth_error(unit) do
    InvalidDateError.exception(
      value: 0,
      reason:
        "There is no #{zeroth_noun(unit)} 0: each counts from 1, or back from the end when negative."
    )
  end

  defp zeroth_noun(:day_of_year), do: "day of the year"
  defp zeroth_noun(:calendar_week), do: "week"
  defp zeroth_noun(unit), do: Atom.to_string(unit)

  # A month of no year, no further from either end than the most months a
  # year of its calendar has. One counted from the end is kept as written
  # even where every year has as many months: a value with no year may be
  # selected in a year of another calendar (`~o"-1M"` selected in a Hebrew
  # year is its thirteenth month in a leap year, where December read as a
  # number would be its twelfth).
  defp bounded_months({:month, months} = component, calendar) do
    case max_months_in_year(calendar) do
      {:ok, max} ->
        if months_within?(months, max),
          do: component,
          else:
            {:error,
             InvalidDateError.exception(
               unit: :month,
               value: months,
               valid_range: 1..max,
               calendar: calendar
             )}

      :unknown ->
        component
    end
  end

  # The most months a year of the calendar has, which `Tempo.UnitValues`
  # asks the calendar for without a year: the months of every year, or of
  # the longest a lunisolar calendar has (13 for the Hebrew calendar).
  defp max_months_in_year(calendar) do
    case UnitValues.in_any_year(:month, [], calendar) do
      {:ok, _every_year, %Range{last: most}} -> {:ok, most}
      {:error, _cannot_say} -> :unknown
    end
  end

  defp months_within?(month, max) when is_integer(month), do: abs(month) <= max

  defp months_within?(%Range{first: first, last: last}, max),
    do: abs(first) <= max and abs(last) <= max

  defp months_within?(months, max) when is_list(months),
    do: Enum.all?(months, &months_within?(&1, max))

  defp months_within?(_month, _max), do: true

  def year_week_day(year, week, day, rest, :month, calendar) do
    case date_from_iso_week(year, week, day, calendar) do
      {:ok, date} ->
        prepend_year(
          date.year,
          resolve([{:month, date.month}, {:day, date.day} | rest], calendar)
        )

      {:error, _reason} ->
        {:error,
         InvalidDateError.exception(
           reason:
             "Day #{inspect(day)} of week #{inspect(week)} of #{inspect(year)} " <>
               "is not a date in #{inspect(calendar)}."
         )}
    end
  end

  def year_week_day(year, week, day, rest, :week, calendar) do
    prepend_year(year, resolve([{:week, week}, {:day_of_week, day} | rest], calendar))
  end

  @doc false
  # A value that names a week of a year and a day of it, as the date it names
  # in a calendar of months: what reading it gives (`resolve/2`), for a value
  # an operation counted in the week's own units, as the walk of a week and a
  # step of days from one do. A calendar of weeks keeps its week and its day,
  # and so does a value with no year, one whose year, week or day is not one
  # whole number, and one that names a day its year's weeks do not hold.
  @spec calendar_date_from_week_date(value) :: value when value: term()
  def calendar_date_from_week_date(
        %Tempo{
          time: [{:year, year}, {:week, week}, {:day_of_week, day} | rest],
          calendar: calendar
        } = tempo
      )
      when is_integer(year) and is_integer(week) and is_integer(day) do
    calendar = Compare.effective_calendar(calendar)

    with false <- Tempo.week_based_calendar?(calendar),
         {:ok, %Date{} = date} <- date_from_iso_week(year, week, day, calendar) do
      dated = [{:year, date.year}, {:month, date.month}, {:day, date.day} | rest]
      %{Qualification.rewritten(tempo, dated) | time: dated}
    else
      _a_calendar_of_weeks_or_no_such_day -> tempo
    end
  end

  def calendar_date_from_week_date(value), do: value

  @doc false
  # A value that names a year and a day of it, as the date it names: what
  # reading it gives (`resolve/2`), for a value an operation built with the
  # day of the year, as the walk of a set of them does. A value with no
  # year, one whose year or day is not one whole number, and one that names
  # a day its year does not have are kept as they are.
  @spec calendar_date_from_ordinal_date(value) :: value when value: term()
  def calendar_date_from_ordinal_date(
        %Tempo{time: [{:year, year}, {:day_of_year, day} | _rest] = time, calendar: calendar} =
          tempo
      )
      when is_integer(year) and is_integer(day) do
    case resolve(time, Compare.effective_calendar(calendar)) do
      [{:year, _year} | _units] = dated -> %{Qualification.rewritten(tempo, dated) | time: dated}
      _no_such_day -> tempo
    end
  end

  def calendar_date_from_ordinal_date(value), do: value

  defp prepend_year(_year, {:error, reason}), do: {:error, reason}
  defp prepend_year(year, resolved), do: [{:year, year} | resolved]

  @doc false
  # The date of day `day` of ISO 8601 week `week` of `year` (`W`). A
  # week-based calendar's weeks are its own dates. A month-based calendar's
  # follow ISO 8601's rule over the calendar's own year, as RFC 7529
  # applies it to any calendar: each week starts on a Monday, and week 1 is
  # the one holding the year's fourth day.
  #
  # In the Gregorian calendar those weeks are the weeks of
  # `Calendrical.ISOWeek`, the calendar that is ISO 8601's weeks, so the date
  # is asked of it in one step: finding where the year's week 1 starts, and
  # the next year's, took ten times as long.
  def date_from_iso_week(year, week, day, Calendrical.Gregorian)
      when is_integer(year) and is_integer(week) and is_integer(day) do
    with {:ok, week_date} <- Date.new(year, week, day, Calendrical.ISOWeek),
         do: Date.convert(week_date, Calendrical.Gregorian)
  end

  def date_from_iso_week(year, week, day, calendar) do
    case calendar.calendar_base() do
      :week ->
        Date.new(year, week, day, calendar)

      :month ->
        calendar
        |> iso_week_start(year, week)
        |> date_in_week(day, calendar)
    end
  end

  @doc false
  # The date of day `day` of week `week` of `year` in the calendar's own
  # weeks (`w`): a week-based calendar's native date or, in a month-based
  # one, the day of the week with ISO 8601's number `day` (`1`, Monday, to
  # `7`, Sunday) among the days `Calendrical.Interval.week/3` gives the week,
  # so a week cut short at the start or end of its year has fewer.
  def date_from_calendar_week(year, week, day, calendar) do
    case calendar.calendar_base() do
      :week -> Date.new(year, week, day, calendar)
      :month -> weekday_in_week(calendar_week_range(year, week, calendar), day)
    end
  end

  @doc false
  # The days of week `week` of `year` in the calendar's own weeks (`w`), as
  # `Calendrical.Interval.week/3` gives them: a `Date.Range`, which is cut
  # short at the start or end of the year in a calendar whose weeks number
  # within their own year, or an error for a week the calendar does not
  # number.
  def calendar_week_range(year, week, calendar) do
    if Code.ensure_loaded?(calendar) and function_exported?(calendar, :week, 2) do
      Calendrical.Interval.week(year, week, calendar)
    else
      {:error, :not_defined}
    end
  end

  @doc false
  # How many ISO 8601 weeks (`W`) `year` has: a week-based calendar's own
  # count, or the weeks ISO 8601's rule gives a month-based calendar's year.
  # The Gregorian calendar's are the weeks of `Calendrical.ISOWeek`, as in
  # `date_from_iso_week/4`.
  def iso_weeks_in_year(year, Calendrical.Gregorian) when is_integer(year),
    do: calendar_weeks_in_year(year, Calendrical.ISOWeek)

  def iso_weeks_in_year(year, calendar) do
    case calendar.calendar_base() do
      :week -> calendar_weeks_in_year(year, calendar)
      :month -> iso_week_count(calendar, year)
    end
  end

  # The weeks from the first day of a year's week 1 to the first day of the
  # next year's, as Calendrical counts them: 52 or 53.
  defp iso_week_count(calendar, year) do
    with {:ok, first} <- first_week_start(calendar, year, @monday),
         {:ok, next_first} <- first_week_start(calendar, year + 1, @monday),
         weeks when is_integer(weeks) <- Calendrical.diff(first, next_first, :weeks) do
      weeks
    else
      _no_first_week -> 0
    end
  end

  # The first day of week `week` of `year`: that many weeks on from week 1's,
  # by Calendrical's arithmetic, when the year has the week. It is reached in
  # one step, where listing the year's weeks to find it took one for each.
  defp iso_week_start(calendar, year, week) when is_integer(week) and week >= 1 do
    with {:ok, first} <- first_week_start(calendar, year, @monday),
         {:ok, next_first} <- first_week_start(calendar, year + 1, @monday),
         {start_year, month, day} <-
           calendar.plus(first.year, first.month, first.day, :weeks, week - 1),
         {:ok, start} <- Date.new(start_year, month, day, calendar),
         :lt <- Compare.compare_days(start, next_first) do
      start
    else
      _no_such_week -> nil
    end
  end

  defp iso_week_start(_calendar, _year, _week), do: nil

  @doc false
  # How many weeks `year` has in the calendar's own numbering (`w`), or 0
  # for a calendar that numbers no weeks.
  def calendar_weeks_in_year(year, calendar) do
    case calendar.weeks_in_year(year) do
      {weeks, _days_in_last_week} when is_integer(weeks) -> weeks
      weeks when is_integer(weeks) -> weeks
      _not_defined -> 0
    end
  end

  @doc false
  # The first day of each week of `year`, week 1 first, for weeks that
  # start on weekday `first_day` (`1`, Monday, to `7`, Sunday) with week 1
  # the one holding the year's fourth day: ISO 8601's weeks for Monday, and
  # the weeks RFC 5545 counts from another WKST.
  def week_starts(calendar, year, first_day) do
    consecutive_week_starts(
      first_week_start(calendar, year, first_day),
      first_week_start(calendar, year + 1, first_day)
    )
  end

  # Each week's first day, from week 1's up to the first day of the next
  # year's week 1, each the day Calendrical gives a week after the last.
  defp consecutive_week_starts({:ok, first}, {:ok, next_first}) do
    first
    |> Stream.iterate(&Calendrical.next(&1, :week))
    |> Enum.take_while(&(Compare.compare_days(&1, next_first) == :lt))
  end

  defp consecutive_week_starts(_first, _next_first), do: []

  defp first_week_start(calendar, year, first_day) do
    case Calendrical.date_from_day_of_year(year, 4, calendar) do
      %Date{} = fourth_day -> {:ok, Kday.kday_on_or_before(fourth_day, first_day)}
      {:error, _reason} -> :error
    end
  end

  # The `day`th day of the week that starts on `week_start`, from
  # Calendrical's arithmetic.
  defp date_in_week(%Date{} = week_start, day, calendar) when is_integer(day) and day in 1..7 do
    case calendar.plus(week_start.year, week_start.month, week_start.day, :days, day - 1) do
      {year, month, day_of_month} -> Date.new(year, month, day_of_month, calendar)
      _error -> {:error, :invalid_date}
    end
  end

  defp date_in_week(_week_start, _day, _calendar), do: {:error, :invalid_date}

  # The day of `week_days` with ISO 8601's weekday number `weekday`, from
  # the calendar's own day of the week.
  defp weekday_in_week(%Date.Range{} = week_days, weekday)
       when is_integer(weekday) and weekday in 1..7 do
    case Enum.find(week_days, &(Date.day_of_week(&1, :monday) == weekday)) do
      %Date{} = date -> {:ok, date}
      nil -> {:error, :invalid_date}
    end
  end

  defp weekday_in_week(%Date.Range{}, _weekday), do: {:error, :invalid_date}
  defp weekday_in_week({:error, _reason} = error, _weekday), do: error

  # The `month`th month of a group of years, counted on from the group's
  # first month by Calendrical, so a thirteen-month year counts as the
  # calendar numbers it.
  #
  # In a year that does not begin with its first month the calendar counts
  # the year's months from the day it begins, and a date's month is not the
  # month counted, so the months are counted through each year's own.
  def year_and_month(%Range{first: first_year, last: last_year}, month, calendar) do
    if UnitValues.year_begins_with_first_month?(first_year, calendar),
      do: month_by_the_calendar(first_year, last_year, month, calendar),
      else: month_counted_through(first_year, last_year, month, month, calendar)
  end

  defp month_by_the_calendar(first_year, last_year, month, calendar) do
    case calendar.plus(first_year, 1, 1, :months, month - 1) do
      {year, month_of_year, _day} when year >= first_year and year <= last_year ->
        {:ok, year, month_of_year}

      _beyond_the_group ->
        {:error, InvalidDateError.exception(unit: :month, value: month, calendar: calendar)}
    end
  end

  defp month_counted_through(year, last_year, month, written, calendar) when year <= last_year do
    case UnitValues.in_period(:month, [year: year], calendar) do
      {:ok, %Range{last: months}} when month <= months ->
        {:ok, year, month}

      {:ok, %Range{last: months}} ->
        month_counted_through(year + 1, last_year, month - months, written, calendar)

      {:error, _reason} ->
        {:error, InvalidDateError.exception(unit: :month, value: written, calendar: calendar)}
    end
  end

  defp month_counted_through(_year, _last_year, _month, written, calendar),
    do: {:error, InvalidDateError.exception(unit: :month, value: written, calendar: calendar)}

  # The `day`th day of a group of months, counted on from the group's
  # first day by Calendrical. The group's first day is the first of its
  # first month, or in a year that does not begin with its first month the
  # first date the calendar gives that month, and the day counted to is
  # held by one of the group's months as the calendar counts them.
  def month_and_day(year, %Range{first: first_month} = months, day, calendar) do
    {start_year, start_month, start_day} =
      first_of_group(year, first_month, calendar)

    with {^year, month, day_of_month} <-
           calendar.plus(start_year, start_month, start_day, :days, day - 1),
         true <- month_of_group?(year, month, day_of_month, months, calendar) do
      {:ok, month, day_of_month}
    else
      _beyond_the_group ->
        {:error, InvalidDateError.exception(unit: :day, value: day, calendar: calendar)}
    end
  end

  defp first_of_group(year, month, calendar) do
    with false <- UnitValues.year_begins_with_first_month?(year, calendar),
         {:ok, first} <- UnitValues.first_date([year: year, month: month], calendar) do
      first
    else
      _first_of_the_month -> {year, month, 1}
    end
  end

  defp month_of_group?(year, month, day, %Range{first: first, last: last}, calendar) do
    if UnitValues.year_begins_with_first_month?(year, calendar) do
      month >= first and month <= last
    else
      match?(
        {:ok, counted} when counted >= first and counted <= last,
        UnitValues.month_of_date(year, month, day, calendar)
      )
    end
  end

  @doc false
  # A written value read against the values its unit takes: a count from the
  # end counted, a range and a list kept as they are written, and a value the
  # unit does not take an `InvalidDateError`. The reading is
  # `Tempo.UnitValues.resolve/2`; this names its refusal.
  #
  # What the value was read as is given where it is known: its unit, the
  # year and the month it is of, and the calendar. The error carries them
  # and says them, so 29 February 2027 is refused as "29 is not valid for a
  # day of 2027-02", where it was "29 is not valid".
  def conform(written, valid, read_as \\ [])

  def conform(written, %Range{} = valid, read_as), do: conform_to(written, valid, read_as)

  # Values a calendar lists apart from one another: the days of a month with
  # days missing in it.
  def conform(written, [%Range{} | _] = valid, read_as),
    do: conform_to(written, valid, read_as)

  def conform(written, not_values, read_as),
    do: not_valid_error(written, not_values, nil, read_as)

  defp conform_to(written, valid, read_as) do
    case UnitValues.resolve(written, valid) do
      {:ok, resolved} ->
        {:ok, as_its_numbers(written, resolved)}

      {:error, {:not_taken, value, counted}} ->
        normalized_error(value, counted, valid, read_as)

      {:error, {:not_taken, {:mask, digits}}} ->
        named(masked_member_error(digits, valid), read_as)

      {:error, {:not_taken, value}} ->
        not_valid_error(value, valid, valid, read_as)

      {:error, {:backwards, range}} ->
        named(backwards_error(range, range, valid), read_as)

      {:error, {:backwards, range, counted}} ->
        named(backwards_error(range, counted, valid), read_as)
    end
  end

  # The unit, the year, the month and the calendar of what was read, on an
  # error that says its own reason.
  defp named({:error, %InvalidDateError{} = error}, read_as), do: {:error, struct(error, read_as)}

  # " for a day of 2027-02", and " in Calendrical.Hebrew" for a calendar
  # other than the Gregorian.
  defp read_as_text([]), do: ""

  defp read_as_text(read_as) do
    " for " <>
      unit_text(read_as[:unit], read_as[:year], read_as[:month]) <>
      calendar_text(read_as[:calendar])
  end

  defp unit_text(:day_of_year, year, _month) when is_integer(year),
    do: "a day of the year #{year}"

  defp unit_text(unit, year, month), do: unit_name(unit) <> period_text(unit, year, month)

  defp unit_name(:day), do: "a day"
  defp unit_name(:month), do: "a month"
  defp unit_name(:week), do: "a week"
  defp unit_name(:day_of_year), do: "a day of the year"
  defp unit_name(:day_of_week), do: "a day of the week"
  defp unit_name(:hour), do: "an hour"
  defp unit_name(:minute), do: "a minute"
  defp unit_name(:second), do: "a second"
  defp unit_name(unit), do: "a #{unit}"

  defp period_text(:day, year, month) when is_integer(year) and is_integer(month),
    do: " of #{year}-#{pad2(month)}"

  defp period_text(:day, nil, month) when is_integer(month), do: " of month #{month}"

  defp period_text(unit, year, _month) when unit in [:month, :week] and is_integer(year),
    do: " of #{year}"

  defp period_text(_unit, _year, _month), do: ""

  defp calendar_text(calendar) when calendar in [nil, Calendrical.Gregorian, Calendar.ISO],
    do: ""

  defp calendar_text(calendar), do: " in #{inspect(calendar)}"

  defp last_value(%Range{last: last}), do: last
  defp last_value(ranges) when is_list(ranges), do: ranges |> List.last() |> last_value()

  # The values a unit takes, as an error names them: a range, or the ranges
  # of a month with days missing in it (`1..2 and 14..30`).
  defp values_text(%Range{} = range), do: inspect(range)

  defp values_text([%Range{} | _] = ranges),
    do: Enum.map_join(ranges, " and ", &inspect/1)

  defp values_text(other), do: inspect(other)

  # A set that held a count from the end is, once the count is taken, the
  # set written with the numbers: in order, its neighbours joined and none
  # twice, as the parser reads one. `{28..30,-1}D` in January is `{28..31}D`,
  # and `T{-1,0}H` is `T{0,23}H`.
  defp as_its_numbers(written, resolved) when is_list(written) do
    if counts_from_end?(written) and Enum.all?(resolved, &number_or_range?/1),
      do: Parser.reduce_list(resolved),
      else: resolved
  end

  defp as_its_numbers(_written, resolved), do: resolved

  defp number_or_range?(member), do: is_integer(member) or is_struct(member, Range)

  # A range runs up from its first value, as an interval does. One whose
  # ends are counted to a first value after its last (`{-1..1}D`, the last
  # day to the first) is refused as one written so is by the parser.
  defp backwards_error(%Range{} = range, %Range{first: first, last: last}, valid) do
    {:error,
     InvalidDateError.exception(
       value: range,
       valid_range: valid,
       reason:
         "#{inspect(range)} is a range written backwards, from #{first} down to #{last}: " <>
           "a range runs from its first value up to its last"
     )}
  end

  # A set in a unit holds whole numbers and ranges of them. One with
  # unspecified digits is a value of its own, some one of several, and is a
  # member of a set of whole values (`{2026-0X,2026-1X}`); a set of years
  # holds them (`{198X,199X}`), a year being a value alone.
  defp masked_member_error(digits, valid) do
    written = Enum.map_join(digits, &mask_digit/1)

    {:error,
     InvalidDateError.exception(
       value: {:mask, digits},
       valid_range: valid,
       reason:
         "#{written} has unspecified digits, and a set in a unit below the year holds whole " <>
           "numbers and ranges of them. Write it as a value of its own in a set of values, " <>
           "as `{2026-0X,2026-1X}` is"
     )}
  end

  defp mask_digit(:X), do: "X"
  defp mask_digit(:negative), do: "-"
  defp mask_digit(digit) when is_integer(digit), do: Integer.to_string(digit)
  defp mask_digit(digits) when is_list(digits), do: "{" <> Enum.join(digits, ",") <> "}"

  defp not_valid_error(value, valid, valid_range, read_as) do
    named(
      {:error,
       InvalidDateError.exception(
         value: value,
         valid_range: valid_range,
         reason:
           "#{inspect(value)} is not valid#{read_as_text(read_as)}. " <>
             "The valid values are #{values_text(valid)}"
       )},
      read_as
    )
  end

  defp normalized_error(value, normalized, range, read_as) do
    named(
      {:error,
       InvalidDateError.exception(
         value: value,
         valid_range: range,
         reason:
           "#{inspect(value)} is not valid#{read_as_text(read_as)}. The normalized value of " <>
             "#{inspect(normalized)} is outside the range #{values_text(range)}"
       )},
      read_as
    )
  end

  ## Leap-second validation

  # A `second = 60` is the ISO 8601 leap-second value. It is only valid
  # when:
  #
  # * The minute is 59 and the hour is 23 (immediately before the UTC
  #   day boundary).
  #
  # * If the calendar date is known, it must be 30 June or 31 December
  #   (the only two dates on which UTC announces leap seconds).
  #
  # * If a time-zone offset is present, it must resolve to the UTC
  #   instant at the day boundary. In practice we require the offset
  #   to be zero when the date is specified; without a date we accept
  #   any offset because the caller is describing a repeating local
  #   time.
  # Leap seconds — policy decision.
  #
  # ISO 8601 permits `:second = 60` as a positive leap second.
  # Tempo used to accept it on the 27 IERS-announced dates. That
  # put Tempo out of step with the rest of the Elixir/OTP
  # ecosystem — `Calendar.ISO.valid_time?/4`, `Time.new/4`,
  # `DateTime.new/3`, and `:calendar.datetime_to_gregorian_seconds/1`
  # all reject or silently collide on `:60`.
  #
  # Aligning with the ecosystem means rejecting `:60` at parse
  # regardless of date. Leap-second information remains available
  # as an **interval-level concern**:
  #
  # * `Tempo.LeapSeconds.dates/0` — the 27 historical insertions.
  # * `Tempo.Interval.spans_leap_second?/1` — does `[from, to)`
  #   contain an IERS leap-second boundary?
  # * `Tempo.Interval.leap_seconds_spanned/1` — list of the dates.
  # * `Tempo.Interval.duration(iv, leap_seconds: true)` — include
  #   spanned leap seconds in the returned duration.
  #
  # Scientific callers who need exact elapsed time across leap
  # seconds use those APIs; everyone else gets stdlib-compatible
  # behaviour for free.

  defp validate_leap_second(units, _tempo) when is_list(units) do
    case List.keyfind(units, :second, 0) do
      {:second, 60} ->
        {:error,
         InvalidTimeError.exception(
           unit: :second,
           value: 60,
           valid_range: 0..59,
           reason:
             "A second value of 60 (leap second) is not accepted as a Tempo value. " <>
               "Elixir's `Calendar.ISO` and `DateTime` reject it too. Use " <>
               "`Tempo.LeapSeconds.dates/0` for the historical list, or " <>
               "`Tempo.Interval.spans_leap_second?/1` to detect leap seconds in " <>
               "an interval."
         )}

      _ ->
        :ok
    end
  end

  defp validate_leap_second(_units, _tempo), do: :ok

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: Integer.to_string(n)

  defp fetch_unit(units, unit) do
    case List.keyfind(units, unit, 0) do
      {^unit, value} -> value
      _ -> nil
    end
  end

  # Bounds-check an ISO 8601 / RFC 3339 time-zone offset. The
  # tokenizer accepts any signed 2-4 digit magnitude; real zones
  # are bounded to ±24h wall-clock. The IANA data carries historical
  # offsets that never exceed about +14 (Pacific/Kiritimati) or
  # −12 (Pacific/Midway pre-2011), so ±24h is permissive.
  @max_offset_minutes 24 * 60

  defp validate_time_shift(nil), do: :ok

  # A time shift is hours, minutes and seconds from the hour down, each a
  # whole number and any left out, with its sign on the first unit that is
  # not zero (`-05:30` is `[hour: -5, minute: 30]`). The parser writes it so,
  # and `Tempo.new/1` takes its caller's: whatever else was given was held,
  # and raised where the value was written or compared.
  defp validate_time_shift(shift) do
    cond do
      not shift_units?(shift) ->
        {:error, ArgumentError.exception(shift_units_reason(shift))}

      not signed_on_first_unit?(shift) ->
        {:error, ArgumentError.exception(shift_sign_reason(shift))}

      true ->
        validate_shift_range(shift)
    end
  end

  @shift_units [:hour, :minute, :second]

  defp shift_units?([_unit | _rest] = shift) do
    Enum.all?(shift, &shift_unit?/1) and in_shift_order?(Enum.map(shift, &elem(&1, 0)))
  end

  defp shift_units?(_no_units), do: false

  defp shift_unit?({unit, amount}) when unit in @shift_units and is_integer(amount), do: true
  defp shift_unit?(_other), do: false

  # From the hour down, each unit once.
  defp in_shift_order?(units), do: units == Enum.filter(@shift_units, &(&1 in units))

  # The units after the first that is not zero take its sign, so none of
  # them is written with one.
  defp signed_on_first_unit?(shift) do
    shift
    |> Enum.map(&elem(&1, 1))
    |> Enum.drop_while(&(&1 == 0))
    |> Enum.drop(1)
    |> Enum.all?(&(&1 >= 0))
  end

  defp shift_units_reason(shift) do
    "A time shift is hours, minutes and seconds from the hour down, each a whole number " <>
      "and any of them left out, such as [hour: 5, minute: 30]; got #{inspect(shift)}."
  end

  defp shift_sign_reason(shift) do
    "A time shift behind UTC carries its sign on its first unit that is not zero, " <>
      "such as [hour: -5, minute: 30] or [hour: 0, minute: -30]; got #{inspect(shift)}."
  end

  # A shift's minutes are those of an hour and its seconds those of a
  # minute (ISO 8601-1 §4.3.13 writes it with `[hour]` and `[min]`), and no
  # shift is longer than a day.
  defp validate_shift_range(shift) do
    hour = fetch_unit(shift, :hour) || 0
    minute = fetch_unit(shift, :minute) || 0
    second = fetch_unit(shift, :second) || 0
    magnitude = abs(hour) * 3600 + abs(minute) * 60 + abs(second)

    cond do
      abs(minute) >= @minutes_per_hour or abs(second) >= @minutes_per_hour ->
        {:error,
         ParseError.exception(
           reason:
             "Time-zone offset out of range. An offset's minutes and seconds are " <>
               "from 0 to 59; got #{inspect(shift)}."
         )}

      magnitude > @max_offset_minutes * 60 ->
        {:error,
         ParseError.exception(
           reason:
             "Time-zone offset out of range. Offsets must be within ±24h; " <>
               "got #{inspect(shift)}."
         )}

      true ->
        :ok
    end
  end

  @doc """
  Validate an IXDTF numeric offset (minutes) for the `[+HH:MM]`
  form. Called from the tokenizer when the offset lands on
  `extended.zone_offset`.
  """
  @spec validate_ixdtf_offset_minutes(integer()) :: :ok | {:error, Exception.t()}
  def validate_ixdtf_offset_minutes(minutes) when is_integer(minutes) do
    if abs(minutes) > @max_offset_minutes do
      {:error,
       ParseError.exception(
         reason:
           "Numeric zone offset out of range. Offsets must be within ±24h; " <>
             "got #{format_offset(minutes)}."
       )}
    else
      :ok
    end
  end

  defp format_offset(minutes) do
    sign = if minutes < 0, do: "-", else: "+"
    m = abs(minutes)
    "#{sign}#{div(m, 60)}:#{pad2(rem(m, 60))}"
  end

  @doc """
  Check that an anchored, zoned Tempo value refers to a wall
  time that actually exists in its IANA time zone.

  During a DST spring-forward transition, an hour of local time
  ceases to exist — `02:30 America/New_York` on 2024-03-10 does
  not refer to any real UTC instant. ISO 8601 permits the
  syntax; Tempo rejects the semantics at parse time so downstream
  set operations, comparisons, and durations never encounter a
  phantom value.

  The check applies only when all of these hold:

  * The value is a bare `%Tempo{}` (Interval/Set values are
    composed of Tempos and checked via recursion).

  * The value is a date, or a date with a time of day to the hour,
    the minute or the second, each unit one whole number. It is
    refused where the clock skips every reading it spans (decided
    2026-10-06): a minute inside the gap, the hour a spring-forward
    skips, a day a zone leaves out. A value the clock skips part of
    (a day or a month whose first hour is skipped, the hour of a
    half-hour change) is not refused: it starts when the clock comes
    out of the gap, the first moment it shows a reading of the value
    (`Tempo.Compare.to_utc_seconds/1`).

  * The value carries an IANA zone id on `extended.zone_id`.

  Returns `:ok` when the wall time is valid, or `{:error, ...}`
  when it falls in a DST (or other) gap.

  Ambiguous wall times (e.g. the doubled hour during a DST
  fall-back) are accepted — the caller can disambiguate via an
  explicit zone offset in the IXDTF suffix.

  """
  @spec validate_zone_existence(Tempo.t() | Tempo.Interval.t() | Tempo.Set.t() | term()) ::
          :ok | {:error, Exception.t()}
  def validate_zone_existence(%Tempo.Interval{from: from, to: to}) do
    with :ok <- validate_zone_existence(from) do
      validate_zone_existence(to)
    end
  end

  def validate_zone_existence(%Tempo.Set{set: values, except: except}) do
    Enum.reduce_while(values ++ except, :ok, fn value, :ok ->
      case validate_zone_existence(value) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  def validate_zone_existence(%Tempo{} = tempo) do
    case zone_id(tempo) do
      nil -> :ok
      zone -> check_wall_time_in_zone(tempo, zone)
    end
  end

  def validate_zone_existence(_other), do: :ok

  defp zone_id(%Tempo{extended: %{zone_id: zone}}) when is_binary(zone) and zone != "",
    do: zone

  defp zone_id(_), do: nil

  # A value names no time in its zone where the clock skips every reading
  # it spans: a minute or a second inside a gap, the hour a spring-forward
  # skips, and the day a zone leaves out when it moves across the date line
  # (Samoa had no 30 December 2011). Its first and its last reading are
  # asked, and it is refused where one gap holds both.
  #
  # A value the clock skips only part of is some time: the hour of a
  # half-hour change (Lord Howe Island), and the day or the month whose
  # first hour is skipped where clocks go forward at midnight. It starts
  # when the clock comes out of the gap (`Tempo.Compare.to_utc_seconds/1`).
  defp check_wall_time_in_zone(%Tempo{time: time}, zone) do
    case wall_readings(time) do
      # Pre-common-era wall times cannot fall into a zone-transition
      # gap — standardised time (and every IANA rule) begins many
      # centuries later, so local mean time applies throughout. The
      # guard also matters mechanically: the zone database feeds the year to
      # `:calendar.last_day_of_the_month/2`, whose OTP ≤ 28 guards
      # reject negative years with a `FunctionClauseError`. A value
      # like `~o"2022-06-15T10:00[Europe/Paris][u-ca=hebrew]"` — the
      # units read as Hebrew year 2022, ≈ 1739 BCE Gregorian — must
      # validate cleanly, not crash.
      {:ok, {{year, _month, _day}, _time}, _last, _written} when year < 1 ->
        :ok

      {:ok, first, last, written} ->
        skipped_whole(gap_at(zone, first), last, written, zone)

      :no_one_span ->
        :ok
    end
  end

  # The gap a reading of the wall clock falls in, or `nil`: a reading the
  # clock shows, once or twice (a fall-back's repeated hour is accepted, and
  # an explicit offset tells its two readings apart), and one there is no
  # database or no such zone to ask of.
  defp gap_at(zone, {date, {_hour, _minute, _second} = time}) do
    wall = :calendar.datetime_to_gregorian_seconds({date, time})

    case TimeZoneDatabase.period_at_wall(zone, wall) do
      {:gap, {_before, starts}, {_after, ends}} -> {starts, ends}
      _shown_or_not_known -> nil
    end
  end

  # A value is skipped whole where the gap that holds its first reading
  # holds its last too, so the last is asked only where the first is in one:
  # nearly every value is asked once.
  defp skipped_whole(nil, _last, _written, _zone), do: :ok

  defp skipped_whole(gap, last, written, zone) do
    if gap_at(zone, last) == gap,
      do: {:error, skipped_error(written, zone)},
      else: :ok
  end

  defp skipped_error(written, zone) do
    ZoneGapError.exception(
      wall_time: written,
      zone_id: zone,
      reason: :dst_gap,
      detail: "it falls inside a daylight-saving or zone-transition gap"
    )
  end

  # The first and the last reading of the wall clock that a value spans,
  # and the value as it is written: one reading for a value written to the
  # minute or the second, the hour's for one written to the hour, the day's
  # for a date. A coarser value, and one that holds a set, a mask or a group
  # in a unit, is no one span that a gap could hold.
  defp wall_readings(time) do
    if Enum.all?(time, &one_reading?/1),
      do: dated_readings(time),
      else: :no_one_span
  end

  @wall_units [:year, :month, :day, :hour, :minute, :second]

  defp one_reading?({unit, value}) when unit in @wall_units and is_integer(value), do: true
  defp one_reading?({:microsecond, {_value, _precision}}), do: true
  defp one_reading?(_a_set_a_mask_or_a_group), do: false

  defp dated_readings([{:year, year}, {:month, month}, {:day, day} | clock]),
    do: clock_readings({year, month, day}, List.keydelete(clock, :microsecond, 0))

  defp dated_readings(_no_date), do: :no_one_span

  defp clock_readings({year, month, day} = date, []) do
    {:ok, {date, {0, 0, 0}}, {date, {23, 59, 59}}, "#{year}-#{pad2(month)}-#{pad2(day)}"}
  end

  defp clock_readings(date, hour: hour) do
    {:ok, {date, {hour, 0, 0}}, {date, {hour, 59, 59}}, "#{written_date(date)}T#{pad2(hour)}"}
  end

  defp clock_readings(date, [{:hour, hour}, {:minute, minute} | finer]) do
    second = Keyword.get(finer, :second, 0)
    reading = {date, {hour, minute, second}}

    {:ok, reading, reading, "#{written_date(date)}T#{pad2(hour)}:#{pad2(minute)}:#{pad2(second)}"}
  end

  defp clock_readings(_date, _other_units), do: :no_one_span

  defp written_date({year, month, day}), do: "#{year}-#{pad2(month)}-#{pad2(day)}"
end
