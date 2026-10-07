defmodule Tempo.Enumeration.SkippedReadings do
  @moduledoc false

  # The readings a zone's clock skips among those a value names in a set.
  #
  # One value that names a reading the clock skips is refused when it is
  # read (`Tempo.Validation.validate_zone_existence/1`), and so is a value
  # that holds a set in a unit where the set names such a reading (decided
  # 2026-10-07): `2026Y3M{28,29}DT2H30M` in Paris names 02:30 on the 29th,
  # which its clock skips, and `2011Y12M{29,30}D` in Samoa the day its zone
  # left out. Each was read, with the skipped member no value of it.
  #
  # The values a set names can be many, a day's seconds or the hours of ten
  # years, so they are not asked one by one. A reading is skipped only where
  # the clock goes forward, so the zone's changes are asked for the years
  # the value names, and each reading a change skips is asked whether the
  # value names it: its date as the value writes one (a month and a day, a
  # week and a day of it, or a day of the year, in the value's calendar),
  # and its time of day. A date is skipped whole only where its zone leaves
  # the day out, and those days are kept.

  alias Calendrical.Gregorian
  alias Tempo.Compare
  alias Tempo.Enumeration.Zone
  alias Tempo.TimeZoneDatabase

  @seconds_in %{day: 86_400, hour: 3_600, minute: 60, second: 1}

  # A year's changes are found once for a zone and kept, which takes a
  # millisecond or so the first time, so a value that names more years than
  # this is asked nothing.
  @years_asked 400

  # A year of weeks, and a year of another calendar, starts some days from
  # the first day its number has in the Gregorian calendar, and a moment is
  # within a day of the reading a clock shows at it.
  @margin 10 * 86_400

  @doc """
  The first reading a zone's clock skips among those a value names.

  ### Arguments

  * `value` is a `t:Tempo.t/0` that holds a set of whole numbers in a unit: a date, or a date and a time of day to the hour, the minute or the second, written with a month and a day, a week and a day of it, or a day of the year.

  * `zone` is the name of the value's zone.

  ### Returns

  * `{reading, unit}`, a Gregorian `{date, time}` the clock skips the whole of and the unit the value is written to (`:day`, `:hour`, `:minute` or `:second`), where the value names one.

  * `nil` where it names none, and for a value that is asked nothing: one of another shape, one that holds unspecified digits, a group or a count from the end in a unit, one with a year before the first, and one that names more than four hundred years.

  """
  @spec first_named(Tempo.t(), String.t()) :: {:calendar.datetime(), atom()} | nil
  def first_named(%Tempo{time: time} = value, zone) when is_binary(zone) do
    case named(time) do
      {:ok, named} ->
        named |> skipped(zone, value) |> Enum.find_value(&named_in(&1, named, value))

      :error ->
        nil
    end
  end

  ## What the value names

  # The values each unit names, as ranges, with the shape its date is
  # written in and the unit it is written to.
  defp named(time) do
    time = Enum.reject(time, &match?({:microsecond, {_value, _precision}}, &1))

    with {:ok, shape, date, clock} <- shape_of(time),
         {:ok, [years | _rest] = date} <- each_as_ranges(date),
         {:ok, clock} <- each_as_ranges(clock),
         true <- Enum.all?(years, &(&1.first >= 1)) do
      {:ok, %{shape: shape, date: date, clock: clock, written_to: written_to(clock)}}
    else
      _not_asked -> :error
    end
  end

  defp shape_of([{:year, year}, {:month, month}, {:day, day} | clock]),
    do: with_clock(:month_and_day, [year, month, day], clock)

  defp shape_of([{:year, year}, {:week, week}, {:day_of_week, day} | clock]),
    do: with_clock(:week_and_day, [year, week, day], clock)

  defp shape_of([{:year, year}, {:day, day} | clock]),
    do: with_clock(:day_of_year, [year, day], clock)

  defp shape_of(_another_shape), do: :error

  defp with_clock(shape, date, []), do: {:ok, shape, date, []}
  defp with_clock(shape, date, hour: hour), do: {:ok, shape, date, [hour]}

  defp with_clock(shape, date, hour: hour, minute: minute),
    do: {:ok, shape, date, [hour, minute]}

  defp with_clock(shape, date, hour: hour, minute: minute, second: second),
    do: {:ok, shape, date, [hour, minute, second]}

  defp with_clock(_shape, _date, _other_units), do: :error

  defp written_to([]), do: :day
  defp written_to([_hour]), do: :hour
  defp written_to([_hour, _minute]), do: :minute
  defp written_to([_hour, _minute, _second]), do: :second

  defp each_as_ranges(values) do
    ranges = Enum.map(values, &as_ranges/1)
    if :error in ranges, do: :error, else: {:ok, ranges}
  end

  # One whole number, or a set of whole numbers and ranges of them. A count
  # from the end (`{1..-1}D` under several months) names other values in
  # each period it is under, and is asked nothing.
  defp as_ranges(value) when is_integer(value) and value >= 0, do: [value..value]

  defp as_ranges([_ | _] = values) do
    if Enum.all?(values, &whole?/1), do: Enum.map(values, &as_range/1), else: :error
  end

  defp as_ranges(_unspecified_digits_or_a_group), do: :error

  defp whole?(value) when is_integer(value), do: value >= 0

  defp whole?(first..last//1) when is_integer(first) and is_integer(last),
    do: first >= 0 and last >= first

  defp whole?(_other), do: false

  defp as_range(value) when is_integer(value), do: value..value
  defp as_range(%Range{} = range), do: range

  defp among?(value, ranges), do: Enum.any?(ranges, &(value in &1))

  ## What the clock skips

  # The stretches of the wall clock a zone skips that a reading of the value
  # could be in, each from its first reading to the first after it.
  defp skipped(%{written_to: :day}, zone, _value) do
    for date <- TimeZoneDatabase.days_left_out(zone) do
      first = :calendar.datetime_to_gregorian_seconds({date, {0, 0, 0}})
      {first, first + @seconds_in.day}
    end
  end

  defp skipped(%{date: [years | _rest]}, zone, %Tempo{calendar: calendar}) do
    if years |> Enum.map(&Range.size/1) |> Enum.sum() <= @years_asked,
      do: skipped_in(years, zone, Compare.effective_calendar(calendar)),
      else: []
  end

  defp skipped_in(years, zone, calendar) do
    for range <- years,
        year <- range,
        {moment, before, later} <- changes_in(year, zone, calendar),
        later > before,
        uniq: true,
        do: {moment + before, moment + later}
  end

  defp changes_in(year, zone, calendar) do
    TimeZoneDatabase.changes(
      zone,
      starts(year, calendar) - @margin,
      starts(year + 1, calendar) + @margin
    )
  end

  defp starts(year, calendar),
    do: trunc(Compare.to_wall_seconds(%Tempo{time: [year: year], calendar: calendar}))

  ## Whether the value names a reading in a stretch the clock skips

  # Each reading of the unit the value is written to that the stretch holds
  # the whole of.
  defp named_in({from, to}, %{written_to: unit} = named, value) do
    step = Map.fetch!(@seconds_in, unit)

    (from + Integer.mod(-from, step))
    |> Stream.iterate(&(&1 + step))
    |> Stream.take_while(&(&1 + step <= to))
    |> Enum.find_value(&reading_named(&1, named, value))
  end

  defp reading_named(seconds, %{clock: clock, written_to: unit} = named, value) do
    {date, {hour, minute, second}} = reading = :calendar.gregorian_seconds_to_datetime(seconds)

    if each_among?([hour, minute, second], clock) and date_named?(date, named, value),
      do: {reading, unit}
  end

  # A reading's units, each among the values the value names for it. The
  # value names no unit finer than the one it is written to.
  defp each_among?(units, named) do
    units |> Enum.zip(named) |> Enum.all?(fn {unit, ranges} -> among?(unit, ranges) end)
  end

  # A Gregorian date as the value writes one, in its calendar.
  defp date_named?({year, month, day}, %{shape: shape, date: date}, value) do
    gregorian = %Tempo{time: [year: year, month: month, day: day], calendar: Gregorian}

    case Zone.in_calendar_of(gregorian, value) do
      {:ok, %Tempo{time: units}} -> units_named?(shape, Keyword.values(units), date, value)
      :error -> false
    end
  end

  defp units_named?(:day_of_year, [year, month, day], [years, days], %Tempo{calendar: calendar}) do
    calendar = Compare.effective_calendar(calendar)

    among?(year, years) and among?(calendar.day_of_year(year, month, day), days)
  end

  defp units_named?(_month_or_week_and_day, units, named, _value), do: each_among?(units, named)
end
