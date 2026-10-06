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
  #
  # A yearly rule is measured here for a numbered weekday and a position,
  # which `Tempo.RRule.YearlyPartsTest` does not write. What it takes from
  # DTSTART is what ISO 8601-2 Annex C.3 lists: its month where the rule
  # names a day of the month and no month, its day where it names a month
  # and no day, and both where it names neither.

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
  @days_of_month [nil, [15], [-1], [31], [29, 30, 31], [1, -31], [13]]

  # A weekday is `{nth, day}`: every such day of the period, or the nth of
  # its month or its year, counted from the end where it is negative.
  @weekdays_of_month [
    nil,
    [{nil, 1}],
    [{nil, 1}, {nil, 3}, {nil, 5}],
    [{1, 1}],
    [{-1, 5}],
    [{5, 1}],
    [{2, 2}, {nil, 3}],
    [{-2, 7}, {1, 6}]
  ]

  @weekdays_of_week [
    nil,
    [{nil, 2}],
    [{nil, 1}, {nil, 3}, {nil, 5}],
    [{nil, 6}, {nil, 7}],
    [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}, {nil, 6}, {nil, 7}]
  ]

  @weekdays_of_year [
    nil,
    [{nil, 1}],
    [{1, 1}],
    [{-1, 5}],
    [{20, 1}],
    [{1, 1}, {-1, 1}],
    [{2, 2}, {nil, 3}]
  ]

  # Hours written out of the order of time, and a minute with no hour, which
  # is in the day's first, or in its start's.
  @times [[hour: [9]], [hour: [14, 9]], [hour: [9], minute: [0, 30]], [minute: [15]]]

  @day_names %{1 => "MO", 2 => "TU", 3 => "WE", 4 => "TH", 5 => "FR", 6 => "SA", 7 => "SU"}

  ## The rules measured

  defp parts(named), do: Enum.reject(named, fn {_part, value} -> is_nil(value) end)

  defp monthly(intervals, months, days_of_month, weekdays, positions, times) do
    for interval <- intervals,
        month <- months,
        day_of_month <- days_of_month,
        weekday <- weekdays,
        position <- positions,
        time <- times do
      {:monthly,
       parts(interval: interval, month: month, day_of_month: day_of_month, weekday: weekday) ++
         (time || []) ++ parts(position: position)}
    end
  end

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

  defp yearly(intervals, months, days_of_month, weekdays, positions) do
    for interval <- intervals,
        month <- months,
        day_of_month <- days_of_month,
        weekday <- weekdays,
        position <- positions do
      {:yearly,
       parts(
         interval: interval,
         month: month,
         day_of_month: day_of_month,
         weekday: weekday,
         position: position
       )}
    end
  end

  ## The measure: `Date` and `NaiveDateTime` alone

  # The years a rule is measured over, from the start of its start's year.
  defp years(:yearly), do: 4
  defp years(_monthly_or_weekly), do: 2

  # Each occurrence of a rule from its start, as the moments it runs from
  # and to.
  defp expected({frequency, parts}, start_text) do
    start = start(start_text)
    ends = Date.new!(start.date.year + years(frequency), 1, 1)
    window_ends = NaiveDateTime.new!(ends, ~T[00:00:00])
    unit = unit_of(parts, start)

    for days <- periods(frequency, parts, start.date, ends),
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

  # The periods a rule steps to from its start's, each as its days: the
  # years, the months, and the weeks from the week its start is in. A week
  # starts on the day the rule names, or on a Monday.
  defp periods(:yearly, parts, start, ends) do
    start.year
    |> Stream.iterate(&(&1 + Keyword.get(parts, :interval, 1)))
    |> Enum.take_while(&(&1 < ends.year))
    |> Enum.map(&Enum.to_list(Date.range(Date.new!(&1, 1, 1), Date.new!(&1, 12, 31))))
  end

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

  # Whether every part that names a day holds for a date, with what the rule
  # takes from DTSTART where it does not say.
  defp day?(frequency, parts, date, start) do
    named = Keyword.take(parts, [:month, :day_of_month, :weekday])
    counted_in = counted_in(frequency, named)

    Enum.all?(named ++ of_start(frequency, named, start), &holds?(&1, date, counted_in))
  end

  defp of_start(:yearly, named, start) do
    case {Keyword.has_key?(named, :month), Keyword.has_key?(named, :day_of_month),
          Keyword.has_key?(named, :weekday)} do
      {true, true, _weekday} -> []
      {false, true, _weekday} -> [month: [start.month]]
      {_month, false, true} -> []
      {true, false, false} -> [day_of_month: [start.day]]
      {false, false, false} -> [month: [start.month], day_of_month: [start.day]]
    end
  end

  defp of_start(:monthly, named, start) do
    if Keyword.has_key?(named, :day_of_month) or Keyword.has_key?(named, :weekday),
      do: [],
      else: [day_of_month: [start.day]]
  end

  defp of_start(:weekly, named, start) do
    if Keyword.has_key?(named, :weekday),
      do: [],
      else: [weekday: [{nil, Date.day_of_week(start)}]]
  end

  # What a numbered weekday is counted in: the month, and in a yearly rule
  # the year where its days are of no one month — it names none, and names
  # no day of the month to be in its start's.
  defp counted_in(:yearly, named) do
    if Keyword.has_key?(named, :month) or Keyword.has_key?(named, :day_of_month),
      do: :month,
      else: :year
  end

  defp counted_in(_monthly_or_weekly, _named), do: :month

  defp holds?({:month, months}, date, _counted_in), do: date.month in months

  defp holds?({:weekday, weekdays}, date, counted_in),
    do: Enum.any?(weekdays, &weekday?(&1, date, counted_in))

  # A day is counted from the start of its month or, by a negative number,
  # from its end.
  defp holds?({:day_of_month, days}, date, _counted_in),
    do: date.day in days or (date.day - Date.days_in_month(date) - 1) in days

  defp weekday?({nil, day}, date, _counted_in), do: Date.day_of_week(date) == day

  defp weekday?({nth, day}, date, counted_in) do
    {place, last} = place_in(date, counted_in)
    nth_of_its_kind = if nth > 0, do: div(place - 1, 7) + 1, else: -(div(last - place, 7) + 1)

    Date.day_of_week(date) == day and nth_of_its_kind == nth
  end

  # A date's place in its month or its year, and the place of the last day.
  defp place_in(date, :month), do: {date.day, Date.days_in_month(date)}

  defp place_in(date, :year),
    do: {Date.day_of_year(date), if(Date.leap_year?(date), do: 366, else: 365)}

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

  # The occurrences of an RRULE from a start, in so many years from the
  # start of the start's year, as the moments each runs from and to.
  defp given(rrule, start_text, years \\ 2) do
    from = Tempo.from_iso8601!(start_text)
    year = Date.from_iso8601!(String.slice(start_text, 0, 10)).year

    with {:ok, rule} <- RRule.parse(rrule, from: from),
         {:ok, %IntervalSet{} = set} <-
           Tempo.to_interval(rule, within: Tempo.from_iso8601!("#{year}Y/#{year + years}Y")) do
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
  defp days(rrule, start_text, years \\ 2) do
    for {from, _to} <- given(rrule, start_text, years), do: NaiveDateTime.to_date(from)
  end

  # The rules whose occurrences are not the measure's, each with the first
  # occurrences of either that the other lacks.
  defp disagreements(rules, starts) do
    for(rule <- rules, start <- starts, do: {rule, start})
    |> Task.async_stream(&disagreement/1, timeout: 60_000, ordered: true)
    |> Enum.flat_map(fn {:ok, found} -> found end)
  end

  defp disagreement({{frequency, _parts} = rule, start}) do
    case {given(rrule(rule), start, years(frequency)), expected(rule, start)} do
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

  describe "a monthly rule read from an RRULE" do
    test "selects the days that satisfy every part that names one" do
      rules = monthly(@intervals, @months, @days_of_month, @weekdays_of_month, [nil], [nil])

      assert disagreements(rules, [@the_31st, @leap_day]) == []
    end

    test "counts a position among the whole of each month's set" do
      rules =
        monthly(
          [nil, 2],
          [nil, [2, 6, 12]],
          [nil, [29, 30, 31], [1, -31]],
          [nil, [{nil, 1}, {nil, 3}, {nil, 5}], [{2, 2}, {nil, 3}], [{-2, 7}, {1, 6}]],
          [[1], [-1], [2, -2], [5]],
          [nil]
        )

      assert disagreements(rules, [@the_31st, @leap_day]) == []
    end

    test "selects each time of day it names on each of those days" do
      rules =
        monthly(
          [nil],
          [nil],
          [nil, [-1]],
          [nil, [{nil, 1}, {nil, 3}, {nil, 5}], [{-1, 5}]],
          [nil, [2, -2]],
          @times
        )

      assert disagreements(rules, [@the_31st, @midweek]) == []
    end

    test "keeps a day of the month that is the numbered weekday beside it" do
      # The last day of a month that is its fifth Monday, and the 15th that
      # is a Wednesday. The 15th is never a first Monday, and it was every
      # 15th that is a Monday; beside a second Tuesday the day of the month
      # was passed over.
      assert days("FREQ=MONTHLY;BYMONTHDAY=-1;BYDAY=5MO", @the_31st) ==
               [~D[2026-08-31], ~D[2026-11-30], ~D[2027-05-31]]

      assert days("FREQ=MONTHLY;BYMONTHDAY=15;BYDAY=2TU,WE", @the_31st) ==
               [~D[2026-04-15], ~D[2026-07-15], ~D[2027-09-15], ~D[2027-12-15]]

      assert days("FREQ=MONTHLY;BYMONTHDAY=15;BYDAY=1MO", @the_31st) == []
    end
  end

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

    test "selects each time of day it names on each of those days" do
      rules =
        weekly(
          [nil, 2],
          [nil, 7],
          [nil],
          [nil, [{nil, 1}, {nil, 3}, {nil, 5}]],
          [nil, [2, -2]],
          @times
        )

      assert disagreements(rules, [@the_31st, @midweek]) == []
    end

    test "puts a minute named with no hour in the first hour of a day" do
      # The second of Monday's, Wednesday's and Friday's quarter past
      # midnight is Wednesday's. It was a quarter past no hour, a value with
      # a minute and no hour to be in.
      assert "FREQ=WEEKLY;BYDAY=MO,WE,FR;BYMINUTE=15;BYSETPOS=2"
             |> given(@the_31st)
             |> Enum.take(2) == [
               {~N[2026-02-04 00:15:00], ~N[2026-02-04 00:16:00]},
               {~N[2026-02-11 00:15:00], ~N[2026-02-11 00:16:00]}
             ]
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

  describe "a yearly rule read from an RRULE" do
    test "counts a numbered weekday in each month it names, or in the year, and a position among the year's set" do
      rules =
        yearly(
          [nil, 2],
          @months,
          [nil, [15], [-1], [1, 2, 3, 4, 5, 6, 7]],
          @weekdays_of_year,
          [nil, [1], [-1], [2, -2]]
        )

      assert disagreements(rules, [@the_31st, @leap_day]) == []
    end

    test "counts a numbered weekday in each of several months" do
      # The first Monday of March and of April. It was March's alone, the
      # first of the Mondays of both.
      assert days("FREQ=YEARLY;BYMONTH=3,4;BYDAY=1MO", @the_31st) ==
               [~D[2026-03-02], ~D[2026-04-06], ~D[2027-03-01], ~D[2027-04-05]]

      assert days("FREQ=YEARLY;BYMONTH=1,2;BYDAY=1MO,-1MO", "2026-01-01") == [
               ~D[2026-01-05],
               ~D[2026-01-26],
               ~D[2026-02-02],
               ~D[2026-02-23],
               ~D[2027-01-04],
               ~D[2027-01-25],
               ~D[2027-02-01],
               ~D[2027-02-22]
             ]
    end
  end
end
