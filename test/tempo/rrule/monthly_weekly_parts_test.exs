defmodule Tempo.RRule.MonthlyWeeklyPartsTest do
  use ExUnit.Case, async: true

  # RFC 5545 §3.3.10 gives a monthly or a weekly rule, in each month or week
  # it steps to, the days that satisfy every part it holds, each time of day
  # it names on each of them, and of those the ones a position counts. The
  # resolver applies the parts one after another, and the measure here is
  # taken apart from it: every day of every period is asked, with `Date`
  # alone, whether each part of the rule holds for it.
  #
  # What a rule does not say is DTSTART's: its day of the month in a monthly
  # rule that names no day, its weekday in a weekly one, and its time of
  # day. A month that lacks the day has no occurrence. A position counts the
  # whole of a period's set, and an occurrence before DTSTART is none.

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  # A 31st, a day five months do not have; a leap day; and a Wednesday at
  # half past ten, for a week that starts before its first occurrence and a
  # time of day the rule does not name.
  @the_31st "2026-01-31"
  @leap_day "2024-02-29"
  @midweek "2026-06-17T10:30"

  @intervals [nil, 2, 3]
  @week_starts [nil, 7, 3]
  @months [nil, [3], [2, 6, 12]]

  # A weekday is `{nth, day}`: every such day of the period, or the nth of
  # its month, counted from the end where it is negative.
  @weekdays_of_week [
    nil,
    [{nil, 2}],
    [{nil, 1}, {nil, 3}, {nil, 5}],
    [{nil, 6}, {nil, 7}],
    [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}, {nil, 6}, {nil, 7}]
  ]

  @day_names %{1 => "MO", 2 => "TU", 3 => "WE", 4 => "TH", 5 => "FR", 6 => "SA", 7 => "SU"}

  ## The rules measured

  defp parts(named), do: Enum.reject(named, fn {_part, value} -> is_nil(value) end)

  defp weekly(intervals, week_starts, months, weekdays, positions, times) do
    for interval <- intervals,
        week_start <- week_starts,
        month <- months,
        weekday <- weekdays,
        position <- positions,
        time <- times do
      {:weekly,
       parts(interval: interval, week_start: week_start, month: month, weekday: weekday) ++
         (time || []) ++ parts(position: position)}
    end
  end

  ## The measure: `Date` and `NaiveDateTime` alone

  # Each occurrence of a rule from its start, in the two years from the
  # start of the start's year, as the moments it runs from and to.
  defp expected({frequency, parts}, start_text) do
    start = start(start_text)
    window_ends = NaiveDateTime.new!(Date.new!(start.date.year + 2, 1, 1), ~T[00:00:00])
    unit = unit_of(parts, start)

    for days <- periods(frequency, parts, start.date, NaiveDateTime.to_date(window_ends)),
        from <- days |> Enum.filter(&day?(frequency, parts, &1, start.date)) |> set(parts, start),
        NaiveDateTime.compare(from, start.moment) != :lt,
        NaiveDateTime.compare(from, window_ends) == :lt,
        do: {from, NaiveDateTime.add(from, 1, unit)}
  end

  defp start(text) do
    case String.split(text, "T") do
      [date] ->
        date = Date.from_iso8601!(date)
        %{date: date, time: nil, moment: NaiveDateTime.new!(date, ~T[00:00:00])}

      [date, time] ->
        date = Date.from_iso8601!(date)
        time = Time.from_iso8601!(time <> ":00")
        %{date: date, time: time, moment: NaiveDateTime.new!(date, time)}
    end
  end

  # An occurrence is as long as the finest unit the rule or its start names.
  defp unit_of(parts, start) do
    cond do
      Keyword.has_key?(parts, :minute) or start.time != nil -> :minute
      Keyword.has_key?(parts, :hour) -> :hour
      true -> :day
    end
  end

  # The months a monthly rule steps to from its start's, and the weeks a
  # weekly rule steps to from the week its start is in, each as its days. A
  # week starts on the day the rule names, or on a Monday.
  defp periods(:monthly, parts, start, ends) do
    start
    |> Date.beginning_of_month()
    |> Stream.iterate(&(&1 |> Date.end_of_month() |> Date.add(1)))
    |> Stream.take_every(Keyword.get(parts, :interval, 1))
    |> Enum.take_while(&(Date.compare(&1, ends) == :lt))
    |> Enum.map(&Enum.to_list(Date.range(&1, Date.end_of_month(&1))))
  end

  defp periods(:weekly, parts, start, ends) do
    week_start = Keyword.get(parts, :week_start, 1)
    days_into_week = Integer.mod(Date.day_of_week(start) - week_start, 7)

    start
    |> Date.add(-days_into_week)
    |> Stream.iterate(&Date.add(&1, 7 * Keyword.get(parts, :interval, 1)))
    |> Enum.take_while(&(Date.compare(&1, ends) == :lt))
    |> Enum.map(&Enum.to_list(Date.range(&1, Date.add(&1, 6))))
  end

  # Whether every part that names a day holds for a date, and where the rule
  # names no day, whether the date is DTSTART's day of its period.
  defp day?(frequency, parts, date, start) do
    named = Keyword.take(parts, [:month, :day_of_month, :weekday])

    Enum.all?(named ++ start_day(frequency, named, start), &holds?(&1, date))
  end

  defp start_day(:monthly, named, start) do
    if Keyword.has_key?(named, :day_of_month) or Keyword.has_key?(named, :weekday),
      do: [],
      else: [day_of_month: [start.day]]
  end

  defp start_day(:weekly, named, start) do
    if Keyword.has_key?(named, :weekday),
      do: [],
      else: [weekday: [{nil, Date.day_of_week(start)}]]
  end

  defp holds?({:month, months}, date), do: date.month in months
  defp holds?({:weekday, weekdays}, date), do: Enum.any?(weekdays, &weekday?(&1, date))

  # A day is counted from the start of its month or, by a negative number,
  # from its end.
  defp holds?({:day_of_month, days}, date),
    do: date.day in days or (date.day - Date.days_in_month(date) - 1) in days

  defp weekday?({nil, day}, date), do: Date.day_of_week(date) == day

  defp weekday?({nth, day}, date) when nth > 0,
    do: Date.day_of_week(date) == day and div(date.day - 1, 7) + 1 == nth

  defp weekday?({nth, day}, date),
    do: Date.day_of_week(date) == day and div(Date.days_in_month(date) - date.day, 7) + 1 == -nth

  # A period's set: each time of day the rule names, or its start has, on
  # each of its days, in the order of time, and of those the ones a position
  # counts, from the end where it is negative.
  defp set(days, parts, start) do
    moments =
      for day <- days,
          hour <- Enum.sort(hours(parts, start)),
          minute <- Enum.sort(minutes(parts, start)),
          do: NaiveDateTime.new!(day, Time.new!(hour, minute, 0))

    counted(moments, Keyword.get(parts, :position))
  end

  defp hours(parts, %{time: nil}), do: Keyword.get(parts, :hour, [0])
  defp hours(parts, %{time: time}), do: Keyword.get(parts, :hour, [time.hour])

  defp minutes(parts, %{time: nil}), do: Keyword.get(parts, :minute, [0])
  defp minutes(parts, %{time: time}), do: Keyword.get(parts, :minute, [time.minute])

  defp counted(moments, nil), do: moments

  defp counted(moments, positions) do
    positions
    |> Enum.map(fn
      position when position > 0 -> Enum.at(moments, position - 1)
      position -> Enum.at(moments, position)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort(NaiveDateTime)
  end

  ## The rule as an RRULE, and what the library gives for it

  defp rrule({frequency, parts}) do
    Enum.join(
      ["FREQ=#{frequency |> Atom.to_string() |> String.upcase()}" | Enum.map(parts, &by_part/1)],
      ";"
    )
  end

  defp by_part({:interval, interval}), do: "INTERVAL=#{interval}"
  defp by_part({:week_start, day}), do: "WKST=#{@day_names[day]}"
  defp by_part({:month, months}), do: "BYMONTH=#{Enum.join(months, ",")}"
  defp by_part({:day_of_month, days}), do: "BYMONTHDAY=#{Enum.join(days, ",")}"
  defp by_part({:hour, hours}), do: "BYHOUR=#{Enum.join(hours, ",")}"
  defp by_part({:minute, minutes}), do: "BYMINUTE=#{Enum.join(minutes, ",")}"
  defp by_part({:position, positions}), do: "BYSETPOS=#{Enum.join(positions, ",")}"

  defp by_part({:weekday, weekdays}),
    do: "BYDAY=" <> Enum.map_join(weekdays, ",", fn {nth, day} -> "#{nth}#{@day_names[day]}" end)

  # The occurrences of an RRULE from a start, in the two years from the
  # start of the start's year, as the moments each runs from and to.
  defp given(rrule, start_text) do
    from = Tempo.from_iso8601!(start_text)
    year = Date.from_iso8601!(String.slice(start_text, 0, 10)).year

    with {:ok, rule} <- RRule.parse(rrule, from: from),
         {:ok, %IntervalSet{} = set} <-
           Tempo.to_interval(rule, within: Tempo.from_iso8601!("#{year}Y/#{year + 2}Y")) do
      for occurrence <- IntervalSet.members(set),
          do: {moment(Interval.from(occurrence)), moment(Interval.to(occurrence))}
    end
  end

  # The moment an occurrence starts or ends at, or the value itself where it
  # names none.
  defp moment(endpoint) do
    case endpoint |> Tempo.extend_resolution(:second) |> Tempo.to_naive_datetime() do
      {:ok, moment} -> moment
      {:error, _no_moment} -> endpoint
    end
  end

  # The day each occurrence of an RRULE starts on.
  defp days(rrule, start_text) do
    for {from, _to} <- given(rrule, start_text), do: NaiveDateTime.to_date(from)
  end

  # The rules whose occurrences are not the measure's, each with the first
  # occurrences of either that the other lacks.
  defp disagreements(rules, starts) do
    for(rule <- rules, start <- starts, do: {rule, start})
    |> Task.async_stream(&disagreement/1, timeout: 60_000, ordered: true)
    |> Enum.flat_map(fn {:ok, found} -> found end)
  end

  defp disagreement({rule, start}) do
    case {given(rrule(rule), start), expected(rule, start)} do
      {same, same} ->
        []

      {given, expected} when is_list(given) ->
        [
          {rrule(rule), start,
           given: first(given -- expected), expected: first(expected -- given)}
        ]

      {not_given, _expected} ->
        [{rrule(rule), start, not_given}]
    end
  end

  defp first(occurrences), do: occurrences |> Enum.take(3) |> Enum.map(&elem(&1, 0))

  describe "a weekly rule read from an RRULE" do
    test "selects the weekdays it names in each week it steps to, counted from the day a week starts on" do
      rules = weekly(@intervals, @week_starts, @months, @weekdays_of_week, [nil], [nil])

      assert disagreements(rules, [@the_31st, @leap_day, @midweek]) == []
    end

    test "counts a position among the whole of each week's set" do
      rules =
        weekly(
          [nil, 2],
          @week_starts,
          [nil, [2, 6, 12]],
          [nil, [{nil, 1}, {nil, 3}, {nil, 5}], [{nil, 6}, {nil, 7}]],
          [[1], [-1], [2, -2], [5]],
          [nil]
        )

      assert disagreements(rules, [@the_31st, @midweek]) == []
    end

    test "asks a month of the days it makes, not of the day its start steps to" do
      # From a Saturday, the week of Monday 30 March 2026 is stepped to by
      # Saturday 4 April: its Tuesday is in March, and its Saturday is not.
      assert "FREQ=WEEKLY;BYMONTH=3;BYDAY=TU" |> days(@the_31st) |> Enum.take(5) ==
               [~D[2026-03-03], ~D[2026-03-10], ~D[2026-03-17], ~D[2026-03-24], ~D[2026-03-31]]

      in_april = days("FREQ=WEEKLY;BYMONTH=4;BYDAY=TU,SA", @the_31st)

      assert Enum.take(in_april, 2) == [~D[2026-04-04], ~D[2026-04-07]]
    end
  end

  describe "a week that limits a monthly rule" do
    test "is asked of the days the rule makes" do
      # ISO week 25 is 15 to 21 June in 2026 and 21 to 27 June in 2027, and
      # the 31st a rule from 31 January steps by is in neither.
      assert days("FREQ=MONTHLY;BYWEEKNO=25;BYDAY=MO", @the_31st) ==
               [~D[2026-06-15], ~D[2027-06-21]]

      assert days("FREQ=MONTHLY;BYWEEKNO=25;BYMONTHDAY=15,16,17", @the_31st) ==
               [~D[2026-06-15], ~D[2026-06-16], ~D[2026-06-17]]
    end
  end
end
