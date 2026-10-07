defmodule Tempo.RRule.SparseWalkTest do
  @moduledoc """
  A rule whose occurrences are far apart for its frequency, and one that
  has none.

  A walk asks each period of a rule's frequency whether the rule keeps it,
  and takes ten thousand periods at most. `FREQ=MINUTELY;BYHOUR=9;BYMINUTE=0`
  keeps one minute in 1,440, so thirty of its occurrences are 43,000
  periods, and it was refused, as any rule was whose parts leave its
  occurrences far apart. A part that limits by the unit the rule steps by,
  or a coarser one, drops a period with every period after it until the
  next value it names, so the walk now goes on from there
  (`Tempo.RRule.Selection.rules_out/3`).

  A rule that selects no date, the 31st of April, has no occurrences: it was
  a walk that never ended until it was cut short, and is now told from its
  parts, and a rule of years or months from the periods of four hundred
  years, in which the Gregorian calendar comes round.

  The measure is a rule worked out by brute force with Elixir's own
  `NaiveDateTime`, `DateTime` and `Date`: every instant of the rule's
  frequency from its start, kept where each part holds.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.RRule.Selection

  @weekdays ~w(MO TU WE TH FR SA SU)
  @frequencies %{day: "DAILY", hour: "HOURLY", minute: "MINUTELY", second: "SECONDLY"}

  # The units of an instant from the coarsest that a part names, and the
  # number each is among the units a frequency steps by.
  @finer %{
    day: [:hour, :minute, :second],
    hour: [:minute, :second],
    minute: [:second],
    second: []
  }

  ## The rule as text

  defp text(%{freq: freq, every: every, parts: parts, until: until}) do
    ["FREQ=" <> Map.fetch!(@frequencies, freq)]
    |> Kernel.++(if every == 1, do: [], else: ["INTERVAL=#{every}"])
    |> Kernel.++(Enum.map(parts, &part_text/1))
    |> Kernel.++(["UNTIL=" <> Calendar.strftime(until, "%Y%m%dT%H%M%S")])
    |> Enum.join(";")
  end

  defp part_text({:month, months}), do: "BYMONTH=" <> Enum.join(months, ",")
  defp part_text({:day, days}), do: "BYMONTHDAY=" <> Enum.join(days, ",")
  defp part_text({:year_day, days}), do: "BYYEARDAY=" <> Enum.join(days, ",")
  defp part_text({:hour, hours}), do: "BYHOUR=" <> Enum.join(hours, ",")
  defp part_text({:minute, minutes}), do: "BYMINUTE=" <> Enum.join(minutes, ",")
  defp part_text({:second, seconds}), do: "BYSECOND=" <> Enum.join(seconds, ",")

  defp part_text({:weekday, days}),
    do: "BYDAY=" <> Enum.map_join(days, ",", &Enum.at(@weekdays, &1 - 1))

  ## The rule by brute force

  # Each instant of the frequency from the start, kept where every part of
  # its unit or a coarser one holds, and then given each value a finer part
  # names: `FREQ=DAILY;BYHOUR=9,17` is two instants of each day kept.
  defp by_brute_force(%{freq: freq, every: every, start: start, parts: parts, until: until}) do
    {expand, limit} = Enum.split_with(parts, fn {unit, _values} -> unit in @finer[freq] end)

    start
    |> Stream.iterate(&NaiveDateTime.add(&1, every, freq))
    |> Stream.take_while(&(NaiveDateTime.compare(&1, until) != :gt))
    |> Stream.filter(fn instant -> Enum.all?(limit, &holds?(&1, instant)) end)
    |> Stream.flat_map(&expanded(&1, expand))
    |> Enum.filter(&(NaiveDateTime.compare(&1, until) != :gt))
  end

  defp holds?({:month, months}, instant), do: instant.month in months
  defp holds?({:weekday, days}, instant), do: Date.day_of_week(instant) in days
  defp holds?({:hour, hours}, instant), do: instant.hour in hours
  defp holds?({:minute, minutes}, instant), do: instant.minute in minutes
  defp holds?({:second, seconds}, instant), do: instant.second in seconds

  # A day of the month counted from its end is a number below zero, and so
  # is a day of the year.
  defp holds?({:day, days}, instant),
    do: instant.day in days or (instant.day - Date.days_in_month(instant) - 1) in days

  defp holds?({:year_day, days}, instant) do
    day = Date.day_of_year(instant)
    days_in_year = if Date.leap_year?(instant), do: 366, else: 365

    day in days or (day - days_in_year - 1) in days
  end

  defp expanded(instant, []), do: [instant]

  defp expanded(instant, [{unit, values} | finer]) do
    for value <- values,
        expanded <- expanded(Map.put(instant, unit, value), finer),
        do: expanded
  end

  ## What Tempo gives

  defp occurrences(rule) do
    with {:ok, recurrence} <- RRule.parse(text(rule), from: Tempo.from_elixir(rule.start)),
         {:ok, %IntervalSet{} = set} <- Tempo.to_interval(recurrence) do
      {:ok, set |> IntervalSet.members() |> Enum.map(&instant/1)}
    end
  end

  defp instant(%Interval{from: %Tempo{time: time}}) do
    NaiveDateTime.new!(
      time[:year],
      time[:month],
      time[:day],
      time[:hour] || 0,
      time[:minute] || 0,
      time[:second] || 0
    )
  end

  ## In a zone

  @step %{hour: 3_600, minute: 60, second: 1}

  # A rule of hours, minutes or seconds in a zone, beside a change of its
  # clock: its frequency, its parts, its start on the zone's clock and how
  # many occurrences are asked for.
  @beside_a_change [
    # New York goes back at 02:00 on 1 November 2026, and each half hour of
    # the hour its clock shows twice is an occurrence twice.
    {:minute, [minute: [0, 30]], ~N[2026-10-31 22:00:00], "America/New_York", 16},
    {:second, [minute: [30], second: [0]], ~N[2026-10-31 23:00:00], "America/New_York", 6},
    {:minute, [hour: [1], minute: [0, 30]], ~N[2026-10-30 00:00:00], "America/New_York", 10},
    {:hour, [hour: [1]], ~N[2026-10-30 00:00:00], "America/New_York", 6},
    {:hour, [day: [1]], ~N[2026-10-25 00:00:00], "America/New_York", 30},
    {:minute, [weekday: [7], minute: [15]], ~N[2026-10-29 00:00:00], "America/New_York", 30},
    # It goes forward at 02:00 on 8 March, a day with no 02:00.
    {:minute, [hour: [2, 3], minute: [0, 30]], ~N[2026-03-06 00:00:00], "America/New_York", 12},
    {:hour, [hour: [2]], ~N[2026-03-06 00:00:00], "America/New_York", 5},
    # Havana goes back from 01:00 to midnight on 1 November: the first
    # reading of a month, of a day of the year and of a Sunday, shown twice.
    {:hour, [month: [11]], ~N[2026-01-15 00:00:00], "America/Havana", 6},
    {:minute, [month: [11], minute: [0, 30]], ~N[2026-10-20 00:00:00], "America/Havana", 8},
    {:minute, [day: [1], minute: [0, 30]], ~N[2026-10-20 00:00:00], "America/Havana", 8},
    {:hour, [year_day: [305]], ~N[2026-01-15 00:00:00], "America/Havana", 30},
    {:hour, [weekday: [7]], ~N[2026-10-28 00:00:00], "America/Havana", 30},
    {:minute, [hour: [0], minute: [0, 30]], ~N[2026-10-28 00:00:00], "America/Havana", 12},
    # And forward from midnight to 01:00 on 8 March, a day with no midnight.
    {:hour, [hour: [0, 1]], ~N[2026-03-06 00:00:00], "America/Havana", 8},
    {:minute, [day: [8], minute: [0]], ~N[2026-03-06 00:00:00], "America/Havana", 26},
    {:hour, [weekday: [7]], ~N[2026-03-06 00:00:00], "America/Havana", 26},
    # Lord Howe's clock changes by half an hour.
    {:minute, [hour: [1, 2], minute: [0, 15, 30, 45]], ~N[2026-04-03 00:00:00],
     "Australia/Lord_Howe", 30},
    {:minute, [hour: [1, 2], minute: [0, 15, 30, 45]], ~N[2026-10-02 00:00:00],
     "Australia/Lord_Howe", 30}
  ]

  defp text(freq, parts),
    do:
      Enum.join(["FREQ=" <> Map.fetch!(@frequencies, freq) | Enum.map(parts, &part_text/1)], ";")

  # Each instant of the frequency from the start, as many seconds on as
  # have passed, kept where every part holds on the zone's clock.
  defp by_the_clock_of_its_zone(freq, parts, %DateTime{time_zone: zone} = start, count) do
    start
    |> DateTime.to_unix()
    |> Stream.iterate(&(&1 + Map.fetch!(@step, freq)))
    |> Stream.filter(fn unix ->
      on_the_clock = unix |> DateTime.from_unix!() |> DateTime.shift_zone!(zone)
      Enum.all?(parts, &holds?(&1, on_the_clock))
    end)
    |> Enum.take(count)
  end

  # A start as it is written with its zone, and with its offset beside it.
  defp read(%DateTime{time_zone: zone} = start, :zone),
    do: read(NaiveDateTime.to_iso8601(DateTime.to_naive(start)) <> "[#{zone}]")

  defp read(%DateTime{time_zone: zone} = start, :offset_and_zone),
    do: read(DateTime.to_iso8601(start) <> "[#{zone}]")

  defp read(text) do
    {:ok, value} = Tempo.from_iso8601(text)
    value
  end

  @epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  defp moments(%IntervalSet{} = set) do
    for member <- IntervalSet.members(set),
        do: Compare.to_utc_seconds(Interval.from(member)) - @epoch
  end

  defp rule(freq, every, parts, days) do
    start = ~N[2026-01-01 00:00:00]

    %{
      freq: freq,
      every: every,
      parts: parts,
      start: start,
      until: NaiveDateTime.add(start, days, :day)
    }
  end

  # Rules whose parts leave their occurrences far apart, each over a span of
  # many more than ten thousand of its periods.
  @sparse [
    {:day, 1, [month: [2], day: [29]], 12_000},
    {:day, 1, [month: [2], day: [29], weekday: [1]], 40_000},
    {:day, 1, [month: [6, 12], day: [-1]], 15_000},
    {:day, 3, [month: [3], weekday: [5]], 40_000},
    {:day, 1, [month: [1], day: [1], hour: [9, 17]], 20_000},
    {:day, 1, [weekday: [1]], 30_000},
    {:day, 1, [day: [13], weekday: [5]], 40_000},
    {:day, 2, [day: [-1, 15]], 40_000},
    {:day, 1, [year_day: [100, -1]], 40_000},
    {:hour, 1, [year_day: [60, 366], hour: [9]], 3_000},
    {:minute, 1, [year_day: [-366, 200], hour: [0], minute: [0]], 400},
    {:hour, 1, [month: [2], day: [29], hour: [9]], 3_000},
    {:hour, 1, [weekday: [1], hour: [9]], 2_000},
    {:hour, 5, [month: [7], weekday: [6, 7]], 3_000},
    {:hour, 1, [day: [13], weekday: [5], hour: [0, 12], minute: [15, 45]], 2_000},
    {:minute, 1, [hour: [9], minute: [0]], 100},
    {:minute, 1, [month: [3], day: [1], hour: [9], minute: [0]], 70},
    {:minute, 1, [minute: [0, 20, 40]], 30},
    {:minute, 15, [weekday: [1, 2, 3, 4, 5], hour: [9, 10, 11, 12, 13, 14, 15, 16]], 120},
    {:minute, 7, [day: [1, -1], hour: [23]], 400},
    {:minute, 1, [weekday: [7], hour: [3], minute: [30], second: [0, 30]], 60},
    {:second, 1, [hour: [9], minute: [30], second: [0]], 1},
    {:second, 1, [month: [1], day: [2], hour: [12], minute: [0, 30], second: [0]], 2},
    {:second, 30, [weekday: [3], hour: [6], minute: [0]], 30},
    {:second, 1, [day: [2], hour: [23], minute: [59], second: [58, 59]], 2}
  ]

  describe "a rule whose occurrences are far apart for its frequency" do
    test "has the occurrences it has by brute force" do
      for {freq, every, parts, days} <- @sparse do
        rule = rule(freq, every, parts, days)
        expected = by_brute_force(rule)

        # The rule has occurrences, and its span is more than a walk's periods.
        assert {text(rule), expected != []} == {text(rule), true}

        assert days * 86_400 >
                 10_000 * every * %{day: 86_400, hour: 3_600, minute: 60, second: 1}[freq]

        assert {text(rule), occurrences(rule)} == {text(rule), {:ok, expected}}
      end
    end

    test "is thirty mornings, where it was more periods than a walk makes" do
      {:ok, rule} =
        RRule.parse("FREQ=MINUTELY;BYHOUR=9;BYMINUTE=0;COUNT=30", from: ~o"2026-01-01T00:00")

      {:ok, %IntervalSet{} = set} = Tempo.to_interval(rule)

      mornings = for day <- 0..29, do: NaiveDateTime.add(~N[2026-01-01 09:00:00], day, :day)

      assert set |> IntervalSet.members() |> Enum.map(&instant/1) == mornings
    end

    test "is each 29 February that is a Monday" do
      mondays =
        for year <- 2026..2200,
            Date.leap_year?(Date.new!(year, 1, 1)),
            date = Date.new!(year, 2, 29),
            Date.day_of_week(date) == 1,
            do: date

      assert Enum.take(mondays, 3) == [~D[2044-02-29], ~D[2072-02-29], ~D[2112-02-29]]

      for frequency <- ["DAILY", "HOURLY;BYHOUR=0", "MINUTELY;BYHOUR=0;BYMINUTE=0"] do
        {:ok, rule} =
          RRule.parse("FREQ=#{frequency};BYMONTH=2;BYMONTHDAY=29;BYDAY=MO;COUNT=3",
            from: ~o"2026-01-01T00:00"
          )

        {:ok, %IntervalSet{} = set} = Tempo.to_interval(rule)
        days = set |> IntervalSet.members() |> Enum.map(&NaiveDateTime.to_date(instant(&1)))

        assert {frequency, days} == {frequency, Enum.take(mondays, 3)}
      end
    end

    test "is at its time on each day's clock in a zone, across a change of it" do
      zone = "America/New_York"

      {:ok, rule} =
        RRule.parse("FREQ=MINUTELY;BYHOUR=9;BYMINUTE=0;COUNT=5",
          from: ~o"2024-03-08T00:00[America/New_York]"
        )

      {:ok, %IntervalSet{} = set} = Tempo.to_interval(rule)

      # 09:00 on each of five days, the third of them the day the clocks
      # go forward.
      nine = for day <- 8..12, do: DateTime.new!(Date.new!(2024, 3, day), ~T[09:00:00], zone)

      assert moments(set) == Enum.map(nine, &DateTime.to_unix/1)
    end

    test "has the occurrences Elixir's DateTime gives it beside a change of the clock" do
      for {freq, parts, naive, zone, count} <- @beside_a_change,
          written <- [:zone, :offset_and_zone] do
        start = DateTime.from_naive!(naive, zone)
        text = text(freq, parts) <> ";COUNT=#{count}"

        {:ok, rule} = RRule.parse(text, from: read(start, written))
        {:ok, %IntervalSet{} = set} = Tempo.to_interval(rule)

        assert {text, zone, written, moments(set)} ==
                 {text, zone, written, by_the_clock_of_its_zone(freq, parts, start, count)}
      end
    end

    test "is beside the changes of the clock its rules are written for" do
      for {naive, zone, change} <- [
            {~N[2026-11-01 01:30:00], "America/New_York", :ambiguous},
            {~N[2026-03-08 02:30:00], "America/New_York", :gap},
            {~N[2026-11-01 00:30:00], "America/Havana", :ambiguous},
            {~N[2026-03-08 00:30:00], "America/Havana", :gap},
            {~N[2026-04-05 01:45:00], "Australia/Lord_Howe", :ambiguous},
            {~N[2026-10-04 02:15:00], "Australia/Lord_Howe", :gap}
          ] do
        assert {naive, zone, elem(DateTime.from_naive(naive, zone), 0)} == {naive, zone, change}
      end
    end

    test "is still refused where it has more occurrences than a walk gives" do
      # Every minute of two months.
      {:ok, rule} = RRule.parse("FREQ=MINUTELY;UNTIL=20260301T000000", from: ~o"2026-01-01T00:00")

      assert {:error, %Tempo.UnboundedRecurrenceError{}} = Tempo.to_interval(rule)
    end

    test "is still refused in weeks, each of which is asked" do
      # Ten Mondays that are 29 February are nearly three centuries of weeks,
      # and a week runs across a month, so no week is passed over.
      {:ok, rule} =
        RRule.parse("FREQ=WEEKLY;BYMONTH=2;BYMONTHDAY=29;BYDAY=MO;COUNT=10", from: ~o"2026-01-01")

      assert {:error, %Tempo.UnboundedRecurrenceError{}} = Tempo.to_interval(rule)
    end
  end

  describe "the part of a rule that drops a candidate" do
    test "is the coarsest that does, with where the walk goes on from" do
      rule = %Tempo{
        time: [selection: [month: [2, 6], day: 29, hour: 9, minute: [0, 30]]],
        calendar: Calendrical.Gregorian
      }

      for {start, goes_on} <- [
            # January is not a month named: February is the next that is.
            {~o"2026-01-15T00:00", {:on, :month, 2}},
            # Nor is July, and the year has no month named after it.
            {~o"2026-07-15T00:00", {:next, :year}},
            # February 2026 has no 29th, and February 2028 has.
            {~o"2026-02-15T00:00", {:next, :month}},
            {~o"2028-02-15T00:00", {:on, :day, 29}},
            # Midnight is not the hour named: 09:00 is the next that is.
            {~o"2028-02-29T00:00", {:on, :hour, 9}},
            {~o"2028-02-29T10:00", {:next, :day}},
            # A minute of the frequency's own: the next named, or the next hour.
            {~o"2028-02-29T09:10", {:on, :minute, 30}},
            {~o"2028-02-29T09:45", {:next, :hour}},
            {~o"2028-02-29T09:30", nil},
            {~o"2028-02-29T09:00", nil}
          ] do
        candidate = %Interval{from: start, to: Tempo.shift(start, minute: 1)}

        assert {start, Selection.rules_out(candidate, rule, :minute)} == {start, goes_on}
      end
    end

    test "is so many days on for a day of the week" do
      weekdays = %Tempo{time: [selection: [day_of_week: [1, 5]]], calendar: Calendrical.Gregorian}

      # Each day of a week, with the days on to the next Monday or Friday.
      for {day, days_on} <- [{15, nil}, {16, 3}, {17, 2}, {18, 1}, {19, nil}, {20, 2}, {21, 1}] do
        date = Date.new!(2026, 6, day)
        start = Tempo.from_date(date)
        candidate = %Interval{from: start, to: Tempo.shift(start, day: 1)}

        next = Enum.find(1..7, &(Date.day_of_week(Date.add(date, &1)) in [1, 5]))
        expected = if Date.day_of_week(date) in [1, 5], do: nil, else: {:in_days, next}

        assert {day, expected} == {day, days_on && {:in_days, days_on}}
        assert {day, Selection.rules_out(candidate, weekdays, :day)} == {day, expected}
      end
    end

    test "is the date of the next day of the year named" do
      rule = %Tempo{time: [selection: [day_of_year: [100, -1]]], calendar: Calendrical.Gregorian}

      for year <- [2026, 2028] do
        hundredth = Date.add(Date.new!(year, 1, 1), 99)
        last = Date.new!(year, 12, 31)

        for {date, goes_on} <- [
              {Date.new!(year, 1, 15), {:on_day, hundredth.month, hundredth.day}},
              {hundredth, nil},
              {Date.add(hundredth, 1), {:on_day, 12, 31}},
              {Date.add(last, -1), {:on_day, 12, 31}},
              {last, nil}
            ] do
          start = Tempo.from_date(date)
          candidate = %Interval{from: start, to: Tempo.shift(start, day: 1)}

          assert {date, Selection.rules_out(candidate, rule, :day)} == {date, goes_on}
        end
      end

      # The year has no day named after its hundredth: the next year has.
      hundredth_alone = %Tempo{time: [selection: [day_of_year: 100]], calendar: rule.calendar}
      start = ~o"2026-04-11"
      candidate = %Interval{from: start, to: Tempo.shift(start, day: 1)}

      assert Selection.rules_out(candidate, hundredth_alone, :day) == {:next, :year}
    end

    test "is none for a rule of weeks, months or years, whose periods run across a coarser unit" do
      rule = %Tempo{time: [selection: [month: 2]], calendar: Calendrical.Gregorian}
      candidate = %Interval{from: ~o"2026-01-15", to: ~o"2026-01-22"}

      for freq <- [:week, :month, :year] do
        assert {freq, Selection.passes_over?(rule, freq)} == {freq, false}
        assert {freq, Selection.rules_out(candidate, rule, freq)} == {freq, nil}
      end
    end
  end

  describe "a rule that selects no date" do
    # The parts that name a date, each with whether any date of four hundred
    # years, the Gregorian calendar's whole cycle, has them, by `Date`.
    @dates [
      [month: [4], day: [31]],
      [month: [4], day: [30]],
      [month: [2], day: [30]],
      [month: [2], day: [30, 31]],
      [month: [2], day: [29]],
      [month: [2, 4, 6, 9, 11], day: [31]],
      [month: [2, 4, 6, 9, 11], day: [-31]],
      [month: [1], day: [-31]],
      [month: [2], day: [29], weekday: [1]],
      [month: [2], day: [-30]],
      [month: [2], day: [-29], weekday: [7]]
    ]

    defp any_date?(parts) do
      Date.range(~D[2026-01-01], ~D[2425-12-31])
      |> Enum.any?(fn date -> Enum.all?(parts, &holds?(&1, date)) end)
    end

    test "has no occurrences, at any frequency" do
      for parts <- @dates, frequency <- ["YEARLY", "MONTHLY", "DAILY", "HOURLY"] do
        rule = "FREQ=#{frequency};" <> Enum.map_join(parts, ";", &part_text/1) <> ";COUNT=2"
        {:ok, recurrence} = RRule.parse(rule, from: ~o"2026-01-01T00:00")

        found =
          case Tempo.to_interval(recurrence) do
            {:ok, %IntervalSet{} = set} -> IntervalSet.count(set) > 0
            {:error, %Tempo.UnboundedRecurrenceError{}} -> :cut_short
          end

        assert {rule, found} == {rule, any_date?(parts)}
      end
    end

    test "is told so in a zone, and with a time of day" do
      for rule <- [
            "FREQ=MINUTELY;BYMONTH=2;BYMONTHDAY=30;BYHOUR=9;BYMINUTE=0;COUNT=2",
            "FREQ=DAILY;BYMONTH=4;BYMONTHDAY=31;BYHOUR=9,17;UNTIL=99991231T000000",
            "FREQ=YEARLY;BYMONTH=6;BYYEARDAY=1;COUNT=2",
            "FREQ=YEARLY;BYMONTH=6;BYWEEKNO=1;COUNT=2"
          ] do
        {:ok, recurrence} = RRule.parse(rule, from: ~o"2026-01-31T09:00[Europe/Paris]")
        {:ok, %IntervalSet{} = set} = Tempo.to_interval(recurrence)

        assert {rule, IntervalSet.count(set)} == {rule, 0}
      end
    end

    test "is an error for a rule of one occurrence, which has no span to be" do
      {:ok, recurrence} =
        RRule.parse("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;COUNT=1", from: ~o"2026-01-31")

      assert {:error, %Tempo.IntervalEndpointsError{reason: :empty_selection}} =
               Tempo.to_interval(recurrence)
    end

    # A rule of years or months, what it steps by and what it starts on:
    # each fourth year from 2026 is no leap year and has no 29 February, and
    # no April has the 31st a rule takes from its start.
    @stepped [
      {:year, 1, [month: [4]], ~D[2026-01-31]},
      {:year, 1, [month: [4]], ~D[2026-01-30]},
      {:year, 4, [month: [2], day: [29]], ~D[2026-01-31]},
      {:year, 4, [month: [2], day: [29]], ~D[2024-01-31]},
      {:year, 3, [month: [2], day: [29]], ~D[2026-01-31]},
      {:year, 100, [month: [2], day: [29]], ~D[2100-01-01]},
      {:year, 100, [month: [2], day: [29]], ~D[2126-01-01]},
      {:month, 1, [month: [4]], ~D[2026-01-31]},
      {:month, 1, [month: [2]], ~D[2026-01-29]},
      {:month, 1, [month: [2]], ~D[2026-01-30]},
      {:month, 2, [month: [2]], ~D[2026-01-15]},
      {:month, 12, [day: [31]], ~D[2026-02-01]},
      {:month, 12, [day: [31]], ~D[2026-03-01]},
      {:month, 48, [day: [29]], ~D[2026-02-01]},
      {:month, 48, [day: [29]], ~D[2024-02-01]},
      {:month, 3, [month: [2, 4], day: [30, 31]], ~D[2026-01-01]},
      {:month, 3, [month: [2, 4], day: [30, 31]], ~D[2026-02-01]}
    ]

    # The dates of such a rule by `Date`: each period's year and month, the
    # months the rule names among them, and the days it names or the day it
    # starts on, where the month has that day. The periods of four hundred
    # years are every kind the rule comes to.
    defp stepped_dates({freq, every, parts, start}) do
      periods = %{year: 400, month: 4_800}

      for period <- 0..(Map.fetch!(periods, freq) - 1),
          first = Date.shift(Date.beginning_of_month(start), [{freq, period * every}]),
          month <- months_of(freq, parts, first),
          day <- Keyword.get(parts, :day, [start.day]),
          {:ok, date} <- [Date.new(first.year, month, day)],
          do: date
    end

    defp months_of(:year, parts, _first), do: Keyword.fetch!(parts, :month)

    defp months_of(:month, parts, first),
      do: Enum.filter([first.month], &(&1 in Keyword.get(parts, :month, 1..12)))

    test "is told of a rule of years or months by what it steps by and starts on" do
      frequencies = %{year: "YEARLY", month: "MONTHLY"}

      for {freq, every, parts, start} = stepped <- @stepped do
        rule =
          ["FREQ=" <> frequencies[freq], "INTERVAL=#{every}"]
          |> Kernel.++(Enum.map(parts, &part_text/1))
          |> Kernel.++(["COUNT=2"])
          |> Enum.join(";")

        {:ok, recurrence} = RRule.parse(rule, from: Tempo.from_date(start))
        {:ok, %IntervalSet{} = set} = Tempo.to_interval(recurrence)

        days = set |> IntervalSet.members() |> Enum.map(&NaiveDateTime.to_date(instant(&1)))

        assert {rule, start, days} == {rule, start, Enum.take(stepped_dates(stepped), 2)}
      end

      # Some of them have no date, and some have.
      assert @stepped |> Enum.map(&(stepped_dates(&1) == [])) |> Enum.frequencies() ==
               %{true => 9, false => 8}
    end

    test "is not told of a rule of days that steps past every date it could have" do
      # Every seventh day from a Tuesday is a Tuesday, so this has no
      # Monday, though a rule of every day has: its walk is cut short.
      {:ok, recurrence} =
        RRule.parse("FREQ=DAILY;INTERVAL=7;BYDAY=MO;COUNT=2", from: ~o"2026-06-02")

      assert Date.day_of_week(~D[2026-06-02]) == 2
      assert {:error, %Tempo.UnboundedRecurrenceError{}} = Tempo.to_interval(recurrence)
    end
  end
end
