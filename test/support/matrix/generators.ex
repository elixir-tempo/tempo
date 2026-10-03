defmodule Tempo.Matrix.Generators do
  @moduledoc """
  Generators of core values as data, for the properties that hold `Tempo`
  to `Tempo.Matrix.Reference` (see `plans/validated-core.md`).

  A generated datum is always a value that exists: a day its month has, a
  week its year has, a wall time its zone shows once. What a value that
  does not exist does is the matrix's question, not the reference's.

  """

  import StreamData, except: [date: 0, date: 1]

  alias Calendar.ISO
  alias Tempo.Matrix.Reference

  @zones ["Europe/Paris", "America/New_York", "Australia/Sydney", "Asia/Kolkata", "Etc/UTC"]

  # Offsets a zone has had, in minutes: whole hours, and the half and
  # three-quarter hours of India, Nepal and Newfoundland.
  @offsets [0, 60, 120, 330, 345, 540, 600, -210, -300, -480, -720, 840]

  @doc """
  A date with no time: a year, a month, a day, a week, a day of a week or
  a day of the year, in the Gregorian calendar.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec date() :: StreamData.t(Reference.point())
  def date do
    one_of([year_date(), month_date(), day_date(), week_date(), weekday_date(), ordinal_date()])
  end

  @doc """
  A day: a year, month and day, a year, week and day of the week, or a
  year and day of the year.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec day() :: StreamData.t(Reference.point())
  def day, do: one_of([day_date(), weekday_date(), ordinal_date()])

  @doc """
  A date coarser than a day: a year, a month or a week.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec coarse_date() :: StreamData.t(Reference.point())
  def coarse_date, do: one_of([year_date(), month_date(), week_date()])

  @doc """
  A day, alone or with a time of day, with or without a zone.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec dated_day() :: StreamData.t(Reference.point())
  def dated_day, do: one_of([day(), datetime(), zoned_datetime()])

  @doc """
  A day written as a year, month and day.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec calendar_day() :: StreamData.t(Reference.point())
  def calendar_day, do: day_date()

  @doc """
  A time of day with no date: an hour, a minute or a second, the second
  with or without a decimal fraction.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec time_of_day() :: StreamData.t(Reference.point())
  def time_of_day do
    map(clock(), fn {time, fraction} -> point([], time, fraction, nil) end)
  end

  @doc """
  A day and a time of day, with no zone.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec datetime() :: StreamData.t(Reference.point())
  def datetime do
    map({day(), clock()}, fn {day, {time, fraction}} ->
      %{day | time: time, fraction: fraction}
    end)
  end

  @doc """
  A day and a time of day to the second, with or without a fraction of
  one, and no zone: what a `NaiveDateTime` holds.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec datetime_to_the_second() :: StreamData.t(Reference.point())
  def datetime_to_the_second do
    map({day(), seconds()}, fn {day, {time, fraction}} ->
      %{day | time: time, fraction: fraction}
    end)
  end

  @doc """
  A day and a time of day to the minute, with no zone.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec datetime_to_the_minute() :: StreamData.t(Reference.point())
  def datetime_to_the_minute do
    map({day(), integer(0..23), integer(0..59)}, fn {day, hour, minute} ->
      %{day | time: [hour: hour, minute: minute]}
    end)
  end

  @doc """
  A time of day to the second, with or without a fraction of one, and no
  date: what a `Time` holds.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec time_to_the_second() :: StreamData.t(Reference.point())
  def time_to_the_second do
    map(seconds(), fn {time, fraction} -> point([], time, fraction, nil) end)
  end

  @doc """
  A day and a time of day in a zone: UTC, an offset or a named zone. A
  wall time the zone skips or shows twice is not generated.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec zoned_datetime() :: StreamData.t(Reference.point())
  def zoned_datetime do
    {datetime(), zone()}
    |> map(fn {datetime, zone} -> %{datetime | zone: zone} end)
    |> filter(&(Reference.span(&1) != :none))
  end

  @doc """
  A day and a time of day to the second in a named zone, which a
  `DateTime` holds as it is written.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec named_zone_datetime() :: StreamData.t(Reference.point())
  def named_zone_datetime do
    {day(), seconds(), member_of(@zones)}
    |> map(fn {day, {time, fraction}, zone} ->
      %{day | time: time, fraction: fraction, zone: {:zone, zone}}
    end)
    |> filter(&(Reference.span(&1) != :none))
  end

  @doc """
  Any point with a year: a date, or a day and a time of day with or
  without a zone.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec dated() :: StreamData.t(Reference.point())
  def dated, do: one_of([date(), datetime(), zoned_datetime()])

  @doc """
  Any point with a year and no zone.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec floating() :: StreamData.t(Reference.point())
  def floating, do: one_of([date(), datetime()])

  @doc """
  Two points on one line that are likely to be related: a point with no
  zone, and the same point, the point one unit coarser, a point one unit
  finer, two of those next to each other, or another date of its year.
  Chosen so, the pairs meet, contain, start, finish and overlap each other,
  where two dates chosen apart are nearly always years apart.

  ### Returns

  * A generator of `{point, point}`.

  """
  @spec related() :: StreamData.t({Reference.point(), Reference.point()})
  def related do
    bind(floating(), fn point ->
      one_of(
        [
          constant({point, point}),
          map(same_year(point), &{point, &1}),
          map(same_year(point), &{&1, point}),
          straddling(point)
        ] ++ within(point) ++ around(point)
      )
    end)
  end

  # A month of a point's year and the week its first day falls in, in either
  # order: unless the month starts on a Monday the two overlap, each running
  # past the other at one end.
  defp straddling(%{date: [{:year, year} | _rest]}) do
    map({integer(2..12), boolean()}, fn {month, month_first?} ->
      {week_year, week} = :calendar.iso_week_number({year, month, 1})
      month = point(year: year, month: month)
      week = point(year: week_year, week: week)

      if month_first?, do: {month, week}, else: {week, month}
    end)
  end

  # The points one unit finer than a point, each with the point, and two of
  # them that touch.
  defp within(%{fraction: {_value, 6}}), do: []

  defp within(point) do
    parts = Reference.finer(point)
    touching = parts |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&List.to_tuple/1)

    [
      map(member_of(parts), &{point, &1}),
      map(member_of(parts), &{&1, point}),
      member_of(touching),
      map(member_of(touching), fn {first, second} -> {second, first} end)
    ]
  end

  # The point one unit coarser than a point, with the point.
  defp around(point) do
    case coarser(point) do
      nil -> []
      whole -> [constant({point, whole}), constant({whole, point})]
    end
  end

  defp coarser(%{fraction: fraction} = point) when not is_nil(fraction),
    do: %{point | fraction: nil}

  defp coarser(%{time: [_ | _] = time} = point), do: %{point | time: Enum.drop(time, -1)}
  defp coarser(%{date: [year: _year]}), do: nil
  defp coarser(%{date: date} = point), do: %{point | date: Enum.drop(date, -1)}

  # A date of the year a point is in: a month, a day, a week or a day of one.
  defp same_year(%{date: [{:year, year} | _rest]}) do
    one_of([
      month_date(constant(year)),
      day_date(constant(year)),
      week_date(constant(year)),
      weekday_date(constant(year)),
      ordinal_date(constant(year))
    ])
  end

  @doc """
  The two ends of an interval: a point with no zone and no fraction of a
  second, and the point a count of its last unit after it, written in the
  same units.

  ### Returns

  * A generator of `{from, to, count}`.

  """
  @spec interval() :: StreamData.t({Reference.point(), Reference.point(), pos_integer()})
  def interval do
    {filter(floating(), &is_nil(&1.fraction)), integer(1..40)}
    |> map(fn {from, count} -> {from, Reference.stepped(from, count), count} end)
    |> filter(fn {_from, %{date: [{:year, year} | _rest]}, _count} -> year in 1..9998 end)
  end

  @doc """
  A date in a calendar other than the Gregorian: a year, a month or a day
  of the Hebrew, Persian, Coptic or civil Islamic calendar.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec other_calendar_date() :: StreamData.t(Reference.point())
  def other_calendar_date do
    bind(member_of(calendars()), fn {calendar, years} ->
      bind(integer(years), &month_of(calendar, &1, [:year, :month, :day]))
    end)
  end

  defp month_of(calendar, year, resolutions) do
    bind(
      integer(1..Reference.months_in_year(year, calendar)),
      &day_of(calendar, year, &1, resolutions)
    )
  end

  defp day_of(calendar, year, month, resolutions) do
    days = Reference.days_in_month(year, month, calendar)

    map({integer(1..days), member_of(resolutions)}, fn {day, resolution} ->
      date = Enum.take([year: year, month: month, day: day], resolution_units(resolution))
      point(date, [], nil, nil, calendar)
    end)
  end

  defp resolution_units(:year), do: 1
  defp resolution_units(:month), do: 2
  defp resolution_units(:day), do: 3

  # Each calendar with years near the present in its own count.
  defp calendars do
    [
      {Calendrical.Hebrew, 5700..5850},
      {Calendrical.Persian, 1300..1450},
      {Calendrical.Coptic, 1650..1800},
      {Calendrical.Islamic.Civil, 1350..1500}
    ]
  end

  @doc """
  A day in a calendar other than the Gregorian.

  ### Returns

  * A generator of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec other_calendar_day() :: StreamData.t(Reference.point())
  def other_calendar_day do
    bind(member_of(calendars()), fn {calendar, years} ->
      bind(integer(years), &month_of(calendar, &1, [:day]))
    end)
  end

  @doc """
  A zone: UTC, an offset from it, or a named zone.

  ### Returns

  * A generator of `:utc`, `{:offset, minutes}` or `{:zone, name}`.

  """
  @spec zone() :: StreamData.t(:utc | {:offset, integer()} | {:zone, String.t()})
  def zone do
    one_of([
      constant(:utc),
      map(member_of(@offsets), &{:offset, &1}),
      map(member_of(@zones), &{:zone, &1})
    ])
  end

  @doc """
  A duration's units: one to three of a year, month, week, day, hour,
  minute and second, in order, each a small whole number.

  ### Returns

  * A generator of keyword lists such as `[month: 2, day: 10]`.

  """
  @spec duration() :: StreamData.t(keyword(pos_integer()))
  def duration do
    units = [:year, :month, :week, :day, :hour, :minute, :second]

    {list_of(member_of(units), min_length: 1, max_length: 3), list_of(integer(1..40), length: 3)}
    |> map(fn {chosen, values} ->
      chosen = Enum.uniq(chosen)
      units |> Enum.filter(&(&1 in chosen)) |> Enum.zip(values)
    end)
  end

  ## Dates

  # Mostly years near the present, and any year `Date` holds the next of.
  defp year, do: frequency([{8, integer(1900..2100)}, {2, integer(1..9998)}])

  defp year_date, do: map(year(), &point(year: &1))

  defp month_date(year \\ year()) do
    map({year, integer(1..12)}, fn {year, month} -> point(year: year, month: month) end)
  end

  defp day_date(year \\ year()) do
    bind({year, integer(1..12)}, fn {year, month} ->
      map(integer(1..ISO.days_in_month(year, month)), fn day ->
        point(year: year, month: month, day: day)
      end)
    end)
  end

  defp week_date(year \\ year()) do
    bind(year, fn year ->
      map(integer(1..weeks_in_year(year)), fn week -> point(year: year, week: week) end)
    end)
  end

  defp weekday_date(year \\ year()) do
    map({week_date(year), integer(1..7)}, fn {week, day} ->
      %{week | date: week.date ++ [day_of_week: day]}
    end)
  end

  defp ordinal_date(year \\ year()) do
    bind(year, fn year ->
      days = if ISO.leap_year?(year), do: 366, else: 365
      map(integer(1..days), fn day -> point(year: year, day_of_year: day) end)
    end)
  end

  # The weeks from the Monday of the week that holds one 4 January to the
  # Monday of the week that holds the next (ISO 8601-1 §4.2.2): 52 or 53.
  defp weeks_in_year(year) do
    div(Date.diff(first_monday(year + 1), first_monday(year)), 7)
  end

  defp first_monday(year), do: year |> Date.new!(1, 4) |> Date.beginning_of_week(:monday)

  ## Times

  defp clock do
    one_of([
      map(integer(0..23), &{[hour: &1], nil}),
      map({integer(0..23), integer(0..59)}, fn {hour, minute} ->
        {[hour: hour, minute: minute], nil}
      end),
      seconds()
    ])
  end

  defp seconds do
    map({integer(0..23), integer(0..59), integer(0..59), fraction()}, fn
      {hour, minute, second, fraction} ->
        {[hour: hour, minute: minute, second: second], fraction}
    end)
  end

  # A decimal fraction of a second of one to six places, or none.
  defp fraction do
    frequency([
      {3, constant(nil)},
      {1,
       bind(integer(1..6), fn digits ->
         map(integer(0..(Integer.pow(10, digits) - 1)), &{&1, digits})
       end)}
    ])
  end

  defp point(date, time \\ [], fraction \\ nil, zone \\ nil, calendar \\ Calendrical.Gregorian) do
    %{date: date, time: time, fraction: fraction, zone: zone, calendar: calendar}
  end
end
