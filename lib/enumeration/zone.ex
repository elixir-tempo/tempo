defmodule Tempo.Enumeration.Zone do
  @moduledoc false

  alias Calendrical.Gregorian
  alias Tempo.Compare
  alias Tempo.TimeZoneDatabase
  alias Tempo.Validation

  @seconds_in_an_hour 3_600

  # Shared DST classification for enumeration. Both `Enumerable.Tempo`
  # (implicit-span walk) and `Enumerable.Tempo.Interval` (explicit
  # forward-stepping walk) classify each emitted moment against its
  # configured zone so the two walks — and the `Tempo.Interval.Steps`
  # fast paths for `count/1`/`slice/1` — agree under daylight saving.

  @doc """
  Classify a Tempo value against its configured zone:

    * `:ok` — no zone, not enough components to form a wall instant,
      or the wall time resolves to a single unambiguous UTC instant.

    * `:gap` — wall time falls in a DST spring-forward gap; the clock
      never shows it, so the walk skips it.

    * `{:ambiguous, first_shift, second_shift}` — wall time happens
      twice (DST fall-back). The shifts are `:shift` keyword lists
      derived from the pre- and post-transition total UTC offset; the
      walk emits the moment twice, once with each.
  """
  @spec zone_status(Tempo.t()) :: :ok | :gap | {:ambiguous, keyword(), keyword()}

  # A date is a gap where its zone leaves the day out (Samoa had no
  # 30 December 2011): the walk skips it as it skips an hour the clock
  # skips.
  def zone_status(%Tempo{extended: %{zone_id: zone}, time: [year: _, month: _, day: _]} = date)
      when is_binary(zone) do
    if on_a_day_left_out?(date), do: :gap, else: :ok
  end

  def zone_status(%Tempo{extended: %{zone_id: zone}} = tempo) when is_binary(zone),
    do: tempo |> in_gregorian() |> status_in(zone)

  def zone_status(_tempo), do: :ok

  # A zone's clock is asked by the Gregorian date of a value. One whose date
  # could not be given as one (`in_gregorian/1`) is asked nothing.
  defp status_in(%Tempo{calendar: calendar} = tempo, zone)
       when calendar in [Gregorian, Calendar.ISO, nil] do
    with %NaiveDateTime{} = naive <- naive_from_tempo(tempo),
         db when is_atom(db) <- TimeZoneDatabase.database() do
      naive |> DateTime.from_naive(zone, db) |> status(tempo, naive)
    else
      _ -> :ok
    end
  end

  defp status_in(%Tempo{}, _zone), do: :ok

  @doc """
  A value with its date as the Gregorian date of the same day, which the
  clock of every zone is read by.

  The zone database is asked by Gregorian dates, so a value of another
  calendar is asked as the day it is: 11 Nisan 5786 is 29 March 2026, the
  day Paris's clocks go from 02:00 to 03:00, and so is the Sunday of week
  13 of 2026 in a calendar of weeks. A value's units were read as Gregorian
  ones in whichever calendar they were, so a Hebrew or a Buddhist time the
  clock skips was read and walked, a day of theirs whose numbers are those
  of a change of the clock in some far year was walked an hour short, and
  a day of a week was asked nothing.

  A value that is no date, or date and time, of whole numbers is returned
  as it is, as is one whose calendar has no such date: it keeps its
  calendar, and is asked nothing of a zone.
  """
  @spec in_gregorian(Tempo.t()) :: Tempo.t()
  def in_gregorian(
        %Tempo{
          time: [{:year, year}, {:week, week}, {:day_of_week, day} | clock],
          calendar: calendar
        } = value
      )
      when is_integer(year) and is_integer(week) and is_integer(day) do
    calendar = Compare.effective_calendar(calendar)

    with {:ok, %Date{} = date} <- Validation.date_from_iso_week(year, week, day, calendar),
         {:ok, date} <- gregorian_units(date) do
      %{value | time: date ++ clock, calendar: Gregorian}
    else
      _no_such_day -> value
    end
  end

  def in_gregorian(%Tempo{calendar: calendar} = value)
      when calendar in [Gregorian, Calendar.ISO, nil],
      do: value

  def in_gregorian(
        %Tempo{
          time: [{:year, year}, {:month, month}, {:day, day} | clock],
          calendar: calendar
        } = value
      )
      when is_integer(year) and is_integer(month) and is_integer(day) do
    with {:ok, %Date{} = date} <- Date.new(year, month, day, calendar),
         {:ok, date} <- gregorian_units(date) do
      %{value | time: date ++ clock, calendar: Gregorian}
    else
      _no_such_date -> value
    end
  end

  def in_gregorian(%Tempo{} = value), do: value

  defp gregorian_units(%Date{} = date) do
    with {:ok, %Date{year: year, month: month, day: day}} <- Date.convert(date, Gregorian),
         do: {:ok, [year: year, month: month, day: day]}
  end

  # A Gregorian date and time, as `in_gregorian/1` gives one, in the units
  # and the calendar of the value it was made from: a day of a week for a
  # value written as one, in that calendar's weeks, or ISO 8601's for a
  # Gregorian value.
  defp in_calendar_of(
         %Tempo{time: [{:year, year}, {:month, month}, {:day, day} | clock]} = gregorian,
         %Tempo{time: [{:year, _year}, {:week, _week}, {:day_of_week, _day} | _clock]} = written
       ) do
    with {:ok, weeks} <- calendar_of_weeks(Compare.effective_calendar(written.calendar)),
         {:ok, %Date{} = date} <- Date.new(year, month, day, Gregorian),
         {:ok, %Date{year: year, month: week, day: day}} <- Date.convert(date, weeks) do
      {:ok,
       %{
         gregorian
         | time: [year: year, week: week, day_of_week: day] ++ clock,
           calendar: written.calendar
       }}
    else
      _no_such_week -> :error
    end
  end

  defp in_calendar_of(%Tempo{} = gregorian, %Tempo{calendar: calendar})
       when calendar in [Gregorian, Calendar.ISO, nil],
       do: {:ok, gregorian}

  defp in_calendar_of(
         %Tempo{time: [{:year, year}, {:month, month}, {:day, day} | clock]} = gregorian,
         %Tempo{calendar: calendar}
       ) do
    with {:ok, %Date{} = date} <- Date.new(year, month, day, Gregorian),
         {:ok, %Date{year: year, month: month, day: day}} <- Date.convert(date, calendar) do
      {:ok,
       %{gregorian | time: [year: year, month: month, day: day] ++ clock, calendar: calendar}}
    else
      _no_such_date -> :error
    end
  end

  defp in_calendar_of(%Tempo{}, %Tempo{}), do: :error

  # The calendar a day of a week is a date of: the calendar itself where it
  # is one of weeks, and ISO 8601's weeks for the Gregorian calendar.
  defp calendar_of_weeks(Gregorian), do: {:ok, Calendrical.ISOWeek}

  defp calendar_of_weeks(calendar),
    do: if(Tempo.week_based_calendar?(calendar), do: {:ok, calendar}, else: :error)

  defp status({:gap, _before, shown}, tempo, naive),
    do: if(shown_in_part?(tempo, naive, shown), do: :ok, else: :gap)

  defp status({:ambiguous, first, second}, _tempo, _naive),
    do: {:ambiguous, shift_from_datetime(first), shift_from_datetime(second)}

  defp status(_shown_once_or_not_known, _tempo, _naive), do: :ok

  # An hour whose first reading the clock skips is shown in part where the
  # clock comes out of the gap before the hour ends: 02:00 on Lord Howe
  # Island on the morning its clocks go from 02:00 to 02:30, and 03:00 on
  # the Chatham Islands, whose clocks go from 02:45 to 03:45. It is a value
  # the reader takes (`Tempo.Validation.validate_zone_existence/1`), and a
  # walk gives it. A minute or a second is one reading, and is skipped.
  defp shown_in_part?(%Tempo{time: time}, %NaiveDateTime{} = hour, %DateTime{} = shown) do
    match?({:hour, _hour}, List.last(time)) and
      NaiveDateTime.before?(
        DateTime.to_naive(shown),
        NaiveDateTime.add(hour, @seconds_in_an_hour)
      )
  end

  @doc """
  Whether a value is on a day its zone leaves out: a date, or a time of day
  on one, that the zone's wall clock never showed (Samoa had no 30 December
  2011).

  The days a zone leaves out are kept
  (`Tempo.TimeZoneDatabase.days_left_out/1`), so this asks nothing of the
  zone database. They are Gregorian dates, and a value of another calendar
  is asked as the Gregorian date of its day (`in_gregorian/1`), in a zone
  that leaves one out.
  """
  @spec on_a_day_left_out?(Tempo.t()) :: boolean()
  def on_a_day_left_out?(%Tempo{extended: %{zone_id: zone}} = value) when is_binary(zone) do
    case TimeZoneDatabase.days_left_out(zone) do
      [] -> false
      days -> value |> in_gregorian() |> on_one_of?(days)
    end
  end

  def on_a_day_left_out?(_value), do: false

  defp on_one_of?(
         %Tempo{
           time: [{:year, year}, {:month, month}, {:day, day} | _clock],
           calendar: calendar
         },
         days
       )
       when is_integer(year) and is_integer(month) and is_integer(day) and
              calendar in [Gregorian, Calendar.ISO, nil],
       do: {year, month, day} in days

  defp on_one_of?(%Tempo{}, _days), do: false

  @doc """
  Whether a value is one its zone's clock shows: any value but one the clock
  skips the whole of, which is the hour a spring-forward skips, a minute or
  a second inside one, and a day its zone leaves out
  (`Tempo.Validation.validate_zone_existence/1`).

  One written is refused when it is read, so this is asked of a value an
  operation has made: a member of a set in a unit, a value a mask stands
  for, the first value of a finer unit. A value the clock skips part of (a
  day whose first hour is skipped, the hour of a half-hour change) is shown.
  """
  @spec shown?(Tempo.t()) :: boolean()
  def shown?(%Tempo{time: time} = value) do
    if List.keymember?(time, :hour, 0),
      do: away_from_every_change?(value) or Validation.validate_zone_existence(value) == :ok,
      else: not on_a_day_left_out?(value)
  end

  # More than any offset a zone has had, and any change of one.
  @a_day_or_so 27 * 3_600

  @seconds_in_a_day 86_400

  # A value with no time of day is skipped whole only where it is a day its
  # zone leaves out, and the days a zone leaves out are kept. One with a
  # time of day is skipped only beside a change of the clock, so a value
  # with none within a day or so of it is shown: the changes of a zone are
  # kept too (`Tempo.TimeZoneDatabase.change_within?/3`). Either way nothing
  # is asked of the zone database for nearly every value, which matters
  # where each member of a selection is asked.
  #
  # The reading is that of the value's Gregorian date (`in_gregorian/1`). A
  # value that is no one reading (a set, a mask or a group in a unit) is
  # asked in full.
  defp away_from_every_change?(%Tempo{extended: %{zone_id: zone}} = value) when is_binary(zone) do
    case value |> in_gregorian() |> reading() do
      {:ok, reading} -> not TimeZoneDatabase.change_within?(zone, reading, @a_day_or_so)
      :no_one_reading -> false
    end
  end

  defp away_from_every_change?(%Tempo{}), do: true

  defp reading(%Tempo{
         time: [{:year, year}, {:month, month}, {:day, day} | clock],
         calendar: calendar
       })
       when is_integer(year) and year >= 1 and is_integer(month) and is_integer(day) and
              calendar in [Gregorian, Calendar.ISO, nil] do
    with {:ok, seconds} <- seconds_into_the_day(clock),
         do: {:ok, Gregorian.date_to_iso_days(year, month, day) * @seconds_in_a_day + seconds}
  end

  defp reading(%Tempo{}), do: :no_one_reading

  defp seconds_into_the_day([{:hour, hour}]) when is_integer(hour), do: {:ok, hour * 3_600}

  defp seconds_into_the_day([{:hour, hour}, {:minute, minute}])
       when is_integer(hour) and is_integer(minute),
       do: {:ok, hour * 3_600 + minute * 60}

  defp seconds_into_the_day([{:hour, hour}, {:minute, minute}, {:second, second} | fraction])
       when is_integer(hour) and is_integer(minute) and is_integer(second) do
    if Enum.all?(fraction, &match?({:microsecond, {_value, _precision}}, &1)),
      do: {:ok, hour * 3_600 + minute * 60 + second},
      else: :no_one_reading
  end

  defp seconds_into_the_day(_other_units), do: :no_one_reading

  @doc """
  A value as its zone's clock shows it: the value, or where the clock skips
  the whole of it, the reading the clock shows at that moment.

  Midnight in Cairo on 28 April 2023, when the clocks went from 00:00 to
  01:00, is 01:00, and 02:00 on Lord Howe Island on the morning its clocks
  go to 02:30 is 02:30. It is asked of the first value of a unit (the first
  hour of a day, the first minute of an hour), which starts when the clock
  first shows a reading of it: the first minute of 03:00 on the Chatham
  Islands, whose clocks go from 02:45 to 03:45, is 03:45. A time written
  inside a gap is another matter, and is the time that long after the
  clock changed (RFC 5545 §3.3.5, `Tempo.Math.add/2`).
  """
  @spec shown_by_the_clock(Tempo.t()) :: Tempo.t()
  def shown_by_the_clock(%Tempo{extended: %{zone_id: zone}} = value) when is_binary(zone) do
    if shown?(value), do: value, else: on_the_reading_shown(value, zone)
  end

  def shown_by_the_clock(%Tempo{} = value), do: value

  # The reading is found by the value's Gregorian date, and given in the
  # value's calendar.
  defp on_the_reading_shown(%Tempo{} = value, zone) do
    case value |> in_gregorian() |> gregorian_reading_shown(zone) |> in_calendar_of(value) do
      {:ok, shown} -> shown
      :error -> value
    end
  end

  # `shown?/1` is false only for a date, or a date and a time of day, each
  # unit one whole number.
  defp gregorian_reading_shown(
         %Tempo{time: [year: year, month: month, day: day] ++ clock} = value,
         zone
       ) do
    reading = {{year, month, day}, time_of_day(clock)}

    case TimeZoneDatabase.period_at_wall(zone, :calendar.datetime_to_gregorian_seconds(reading)) do
      {:gap, _before, {_later, shown}} -> %{value | time: units_at(value.time, shown)}
      _shown_or_not_known -> value
    end
  end

  defp time_of_day(clock),
    do: {clock[:hour] || 0, clock[:minute] || 0, clock[:second] || 0}

  # The units of a value at another reading of the clock: the units it has,
  # and the finer ones the reading needs. 02:00 moved to 02:30 is written
  # to the minute, and a day moved to the next midnight stays a day.
  defp units_at(time, %{
         year: year,
         month: month,
         day: day,
         hour: hour,
         minute: minute,
         second: second
       }) do
    fraction = for {:microsecond, _fraction} = unit <- time, do: unit

    [year: year, month: month, day: day] ++
      clock_units(hour, minute, second, finest_clock_unit(time)) ++ fraction
  end

  defp finest_clock_unit(time) do
    Enum.find([:second, :minute, :hour], :day, &Keyword.has_key?(time, &1))
  end

  defp clock_units(hour, minute, second, finest) when second != 0 or finest == :second,
    do: [hour: hour, minute: minute, second: second]

  defp clock_units(hour, minute, _second, finest) when minute != 0 or finest == :minute,
    do: [hour: hour, minute: minute]

  defp clock_units(hour, _minute, _second, finest) when hour != 0 or finest == :hour,
    do: [hour: hour]

  defp clock_units(_hour, _minute, _second, :day), do: []

  @doc """
  The value an hour in a named zone ends at: the reading its clock shows
  when it next leaves the hour.

  That is the next hour for nearly every hour there is. It is another
  reading where the clock changes on the way:

  * the hour before a gap ends on the gap's far side (01:00 in New York on
    the night its clocks go from 02:00 to 03:00 ends at 03:00), and an hour
    a gap begins inside ends when the gap does (02:00 on the Chatham
    Islands, whose clocks go from 02:45 to 03:45, ends at 03:45);

  * an hour that starts inside a gap ends at the next hour, having started
    when the clock came out of the gap (02:00 on Lord Howe Island, which
    its clocks show from 02:30, ends at 03:00, half an hour on);

  * an hour a fall-back shows the first reading of twice is one occurrence
    of the two, and the first ends where the second begins (01:00 in New
    York on the night its clocks go back from 02:00 to 01:00);

  * an hour a fall-back shows the end of twice runs through both (01:00 on
    Lord Howe Island, whose clocks go back from 02:00 to 01:30, ends at
    the second 02:00, an hour and a half on).

  An hour of elapsed time from the start is each of these only where the
  clock changes by whole hours on the hour.

  ### Arguments

  * `hour` is a `t:Tempo.t/0` of a date and an hour in a named zone.

  ### Returns

  * `{:ok, value}`, the value the hour ends at, written to the hour, or
    to the minute or the second where the clock comes out of a gap
    between hours.

  * `:error` for a value that is no date and hour, or in a zone the
    database does not know: the caller counts an elapsed hour.

  """
  @spec end_of_hour(Tempo.t()) :: {:ok, Tempo.t()} | :error
  def end_of_hour(%Tempo{} = value) do
    with {:ok, ending} <- value |> in_gregorian() |> end_of_gregorian_hour(),
         do: in_calendar_of(ending, value)
  end

  defp end_of_gregorian_hour(
         %Tempo{
           time: [year: year, month: month, day: day, hour: hour],
           extended: %{zone_id: zone},
           shift: shift,
           calendar: calendar
         } = value
       )
       when is_binary(zone) and is_integer(year) and year >= 1 and is_integer(month) and
              is_integer(day) and hour in 0..23 and
              calendar in [Gregorian, Calendar.ISO] do
    starts = :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, 0, 0}})

    with {:ok, ending} <-
           ending(zone, starts, TimeZoneDatabase.period_at_wall(zone, starts), shift) do
      {:ok, at_ending(value, ending)}
    end
  end

  defp end_of_gregorian_hour(%Tempo{}), do: :error

  # Where the hour that starts on the reading `starts` ends, as
  # `{reading, offset, shown twice?}`.
  #
  # An hour whose first reading the clock shows twice is the first of two
  # occurrences unless it is written with the second's offset. The first
  # runs for an hour, or until the second starts where the clock goes back
  # by less than an hour (Colombo's went from 00:30 to 00:00 in 2006), and
  # ends on whatever the clock shows then: the second 01:00 in New York,
  # and on Troll, whose clocks go back from 03:00 to 01:00, the first 02:00
  # for the first 01:00 and the second 01:00 for the first 02:00.
  defp ending(zone, starts, {:ambiguous, first, second}, shift) do
    {first, second} =
      {TimeZoneDatabase.total_offset(first), TimeZoneDatabase.total_offset(second)}

    if is_list(shift) and Compare.offset_seconds(shift) == second,
      do: at_the_next_hour(zone, starts, second),
      else: shown_at(zone, starts - first + min(@seconds_in_an_hour, first - second))
  end

  # Any other hour ends when the clock reaches the next, at the offset it
  # shows the hour at: the offset after the gap for one that starts in a
  # gap.
  defp ending(zone, starts, {:ok, period}, _shift),
    do: at_the_next_hour(zone, starts, TimeZoneDatabase.total_offset(period))

  defp ending(zone, starts, {:gap, _before, {later, _limit}}, _shift),
    do: at_the_next_hour(zone, starts, TimeZoneDatabase.total_offset(later))

  defp ending(_zone, _starts, {:error, _reason}, _shift), do: :error

  # The next hour as the clock shows it: at the offset the hour is in where
  # the clock shows that reading twice, and the reading the clock jumps to
  # where it skips it.
  defp at_the_next_hour(zone, starts, offset) do
    next = starts + @seconds_in_an_hour

    case TimeZoneDatabase.period_at_wall(zone, next) do
      {:ok, period} ->
        {:ok, {next, TimeZoneDatabase.total_offset(period), false}}

      {:ambiguous, first, second} ->
        second = TimeZoneDatabase.total_offset(second)
        shown = if offset == second, do: second, else: TimeZoneDatabase.total_offset(first)
        {:ok, {next, shown, true}}

      {:gap, _before, {later, comes_out}} ->
        {:ok, {gregorian_seconds(comes_out), TimeZoneDatabase.total_offset(later), false}}

      {:error, _reason} ->
        :error
    end
  end

  # What the clock shows at a moment.
  defp shown_at(zone, moment) do
    case TimeZoneDatabase.period_at_utc(zone, moment) do
      {:ok, period} ->
        offset = TimeZoneDatabase.total_offset(period)
        {:ok, {moment + offset, offset, true}}

      {:error, _reason} ->
        :error
    end
  end

  defp gregorian_seconds(%{
         year: year,
         month: month,
         day: day,
         hour: hour,
         minute: minute,
         second: second
       }),
       do: :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, minute, second}})

  # The value at an ending. A reading the clock shows twice carries its
  # offset, which tells its two occurrences apart, and so does one of a
  # value that was written with an offset.
  defp at_ending(%Tempo{shift: shift} = value, {reading, offset, twice?}) do
    {{year, month, day}, {hour, minute, second}} =
      :calendar.gregorian_seconds_to_datetime(reading)

    time = [year: year, month: month, day: day] ++ clock_units(hour, minute, second, :hour)

    if twice? or is_list(shift),
      do: %{value | time: time, shift: offset_as_written(offset, shift)},
      else: %{value | time: time}
  end

  @doc """
  An offset in seconds as a `:shift`, in the shape a value wrote its own:
  one given as `-05:00` keeps its minutes when it becomes `-04:00`.
  """
  @spec offset_as_written(integer(), keyword() | nil) :: keyword()
  def offset_as_written(offset, shift) do
    written = offset_to_shift(offset)

    if is_list(shift) and Keyword.has_key?(shift, :minute) and
         not Keyword.has_key?(written, :minute),
       do: written ++ [minute: 0],
       else: written
  end

  @doc """
  Convert a total UTC offset in seconds to a `%Tempo{}` `:shift`
  keyword list, dropping the `:minute` element for a whole-hour
  offset (matching the IXDTF `+HH` vs `+HH:MM` shapes).

  The sign is carried on the first non-zero component, as the ISO 8601
  parser writes it: −03:30 is `[hour: -3, minute: 30]` and −00:30 is
  `[hour: 0, minute: -30]`.

  An offset that is not a whole number of minutes keeps its seconds, as
  a zone's local mean time has them: New York's until 1883 is
  `[hour: -4, minute: 56, second: 2]`. They were dropped, so the shift
  written beside such a zone was not its offset.
  """
  @spec offset_to_shift(integer()) :: keyword()
  def offset_to_shift(total_seconds) do
    sign = if total_seconds < 0, do: -1, else: 1
    abs_total = abs(total_seconds)
    hours = div(abs_total, 3600)
    minutes = div(rem(abs_total, 3600), 60)

    signed_units(sign, hours, minutes, rem(abs_total, 60))
  end

  defp signed_units(sign, hours, 0, 0), do: [hour: sign * hours]
  defp signed_units(sign, 0, minutes, 0), do: [hour: 0, minute: sign * minutes]
  defp signed_units(sign, hours, minutes, 0), do: [hour: sign * hours, minute: minutes]

  defp signed_units(sign, 0, 0, seconds), do: [hour: 0, minute: 0, second: sign * seconds]

  defp signed_units(sign, 0, minutes, seconds),
    do: [hour: 0, minute: sign * minutes, second: seconds]

  defp signed_units(sign, hours, minutes, seconds),
    do: [hour: sign * hours, minute: minutes, second: seconds]

  # Extract `year, month, day, hour, minute, second` from a Tempo's
  # time keyword list and build a NaiveDateTime, filling missing
  # minute/second with 0. Returns `nil` if the value doesn't have
  # enough components to form a NaiveDateTime.
  defp naive_from_tempo(%Tempo{time: time}) do
    with year when is_integer(year) <- whole(time, :year, nil),
         month when is_integer(month) <- whole(time, :month, nil),
         day when is_integer(day) <- whole(time, :day, nil),
         hour when is_integer(hour) <- whole(time, :hour, nil),
         minute when is_integer(minute) <- whole(time, :minute, 0),
         second when is_integer(second) <- whole(time, :second, 0),
         {:ok, naive} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
      naive
    else
      _ -> nil
    end
  end

  # A unit's whole number, `default` where the unit is absent, and `nil` where
  # it holds anything else: a set, a mask, or a group of a set, which is held
  # as three elements that `Keyword.get/3` raises on. A value with such a
  # unit is no one wall time to place in its zone.
  defp whole(time, unit, default) do
    case List.keyfind(time, unit, 0) do
      {^unit, value} when is_integer(value) -> value
      nil -> default
      _several -> nil
    end
  end

  defp shift_from_datetime(%DateTime{utc_offset: utc, std_offset: std}),
    do: offset_to_shift(utc + std)
end
