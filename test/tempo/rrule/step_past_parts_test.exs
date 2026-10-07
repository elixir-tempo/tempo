defmodule Tempo.RRule.StepPastPartsTest do
  @moduledoc """
  A rule that has no occurrence because of what it steps by.

  Every seventh day from a Tuesday is a Tuesday, so a rule of them that
  keeps the Mondays (`FREQ=DAILY;INTERVAL=7;BYDAY=MO`) has no occurrence, as
  one of every twelfth hour from 10:00 that keeps 09:00 has none. Each was
  walked for 10,000 periods and was then a `Tempo.UnboundedRecurrenceError`,
  where a rule that names the 31st of April was told it has no occurrence.

  The measure is Elixir's own `NaiveDateTime`: a start stepped until it is
  back at the place in the week it began at, which are all the places it
  ever stops at, and each asked for its day of the week and its time.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.ISOWeek
  alias Calendrical.NRF
  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  # A step's unit, the steps of it walked, and the starts walked from:
  # Tuesday 16 June 2026, to each resolution, and a Sunday.
  @walks [
    {:day, [1, 2, 3, 7, 14, 21], ["2026-06-16", "2026-06-21", "2026-06-16T10"]},
    {:hour, [1, 5, 12, 24, 36, 48, 84, 168], ["2026-06-16T10", "2026-06-16", "2026-06-16T10:15"]},
    {:minute, [45, 60, 90, 1440, 10_080], ["2026-06-16T10:15", "2026-06-16T10"]},
    {:second, [90, 3600, 86_400, 604_800], ["2026-06-16T10:15:30"]}
  ]

  # The parts a rule is given. One keeps or drops a period where it is no
  # finer than the step, and makes times in the period where it is finer.
  @parts [
    [day_of_week: [1]],
    [day_of_week: [2]],
    [day_of_week: [1, 3]],
    [day_of_week: [6, 7]],
    [hour: [9]],
    [hour: [10]],
    [hour: [22]],
    [hour: [9, 11]],
    [day_of_week: [1], hour: [10]],
    [day_of_week: [5], hour: [22]],
    [minute: [0]],
    [minute: [15]],
    [minute: [20]],
    [minute: [30]],
    [hour: [11], minute: [30]],
    [day_of_week: [2], hour: [10], minute: [15]],
    [second: [0]],
    [second: [30]],
    [second: [45]],
    [minute: [15], second: [30]]
  ]

  @finer_first [:second, :minute, :hour, :day]
  @designators %{day_of_week: "K", hour: "H", minute: "M", second: "S"}

  ## The measure

  defp read(text),
    do:
      NaiveDateTime.from_iso8601!(
        text <> String.slice("2026-06-16T00:00:00", byte_size(text)..-1//1)
      )

  defp place_in_week(%NaiveDateTime{} = stop),
    do: {Date.day_of_week(stop), stop.hour, stop.minute, stop.second}

  # Every place in the week a walk stops at: it is back where it began after
  # them, and goes round them again.
  defp places_stopped_at(%NaiveDateTime{} = start, unit, amount) do
    began_at = place_in_week(start)

    later =
      start
      |> Stream.iterate(&NaiveDateTime.add(&1, amount, unit))
      |> Stream.drop(1)
      |> Enum.take_while(&(place_in_week(&1) != began_at))

    [start | later]
  end

  defp named?(%NaiveDateTime{} = stop, parts) do
    Enum.all?(parts, fn
      {:day_of_week, days} -> Date.day_of_week(stop) in days
      {unit, values} -> Map.fetch!(stop, unit) in values
    end)
  end

  # The first three stops the parts name, and none where no place the walk
  # stops at is one of theirs.
  defp stops_named(places, {start, unit, amount}, parts) do
    if Enum.any?(places, &named?(&1, parts)) do
      start
      |> Stream.iterate(&NaiveDateTime.add(&1, amount, unit))
      |> Stream.filter(&named?(&1, parts))
      |> Enum.take(3)
    else
      []
    end
  end

  ## The rule

  defp limits?(parts, unit) do
    Enum.all?(parts, fn
      {:day_of_week, _days} -> true
      {part, _values} -> part in Enum.drop_while(@finer_first, &(&1 != unit))
    end)
  end

  defp duration(:day, amount), do: "P#{amount}D"
  defp duration(:hour, amount), do: "PT#{amount}H"
  defp duration(:minute, amount), do: "PT#{amount}M"
  defp duration(:second, amount), do: "PT#{amount}S"

  defp part({part, [value]}), do: "#{value}#{Map.fetch!(@designators, part)}"

  defp part({part, values}),
    do: "{#{Enum.join(values, ",")}}#{Map.fetch!(@designators, part)}"

  defp selection(parts) do
    {days, times} = Enum.split_with(parts, &match?({:day_of_week, _days}, &1))
    clock = if times == [], do: "", else: "T" <> Enum.map_join(times, &part/1)

    Enum.map_join(days, &part/1) <> clock
  end

  defp rule(start, unit, amount, parts),
    do: "R3/#{start}/#{duration(unit, amount)}/FL#{selection(parts)}N"

  # The moment each occurrence starts at, in seconds, as Erlang counts them.
  # The first occurrence of a walk finer than its start is written as the
  # start is, a date where the others are hours, so they are compared by
  # their moments.
  defp moments(text) do
    with {:ok, %IntervalSet{} = occurrences} <- Tempo.to_interval(Tempo.from_iso8601!(text)) do
      occurrences
      |> IntervalSet.members()
      |> Enum.map(&(&1 |> Interval.from() |> Compare.to_utc_seconds() |> trunc()))
    end
  end

  defp moment(%NaiveDateTime{} = stop),
    do: stop |> NaiveDateTime.to_erl() |> :calendar.datetime_to_gregorian_seconds()

  defp starts(text), do: text |> Tempo.from_iso8601!() |> starts_of()

  defp starts_of(%Interval{} = recurrence) do
    with {:ok, %IntervalSet{} = occurrences} <- Tempo.to_interval(recurrence) do
      Enum.map(IntervalSet.members(occurrences), &Interval.from/1)
    end
  end

  # The Gregorian date of a day of another calendar, as Calendrical converts
  # it.
  defp gregorian(%Tempo{} = day) do
    {:ok, date} = Tempo.to_date(day)
    Date.convert!(date, Calendar.ISO)
  end

  describe "a rule of days, hours, minutes or seconds whose parts keep or drop a period" do
    test "has the occurrences its steps stop at, and none where they stop at no place it names" do
      for {unit, amounts, texts} <- @walks,
          amount <- amounts,
          text <- texts,
          places = places_stopped_at(read(text), unit, amount),
          parts <- @parts,
          limits?(parts, unit) do
        rule = rule(text, unit, amount, parts)
        named = stops_named(places, {read(text), unit, amount}, parts)

        assert {rule, moments(rule)} == {rule, Enum.map(named, &moment/1)}
      end
    end

    test "names a place among those of every seventh day, twelfth hour and ninetieth second" do
      # The measure, shown: every seventh day from a Tuesday is a Tuesday.
      assert Date.day_of_week(~D[2026-06-16]) == 2

      assert ~N[2026-06-16 00:00:00]
             |> places_stopped_at(:day, 7)
             |> Enum.map(&Date.day_of_week/1) == [2]

      assert starts("R3/2026-06-16/P7D/FL1KN") == []
      assert starts("R3/2026-06-16/P7D/FL2KN") == [~o"2026-06-16", ~o"2026-06-23", ~o"2026-06-30"]

      # Every twelfth hour from 10:00 is 10:00 or 22:00.
      assert ~N[2026-06-16 10:00:00]
             |> places_stopped_at(:hour, 12)
             |> Enum.map(& &1.hour)
             |> Enum.uniq() == [10, 22]

      assert starts("R3/2026-06-16T10/PT12H/FLT9HN") == []

      assert starts("R3/2026-06-16T10/PT12H/FLT22HN") ==
               [~o"2026-06-16T22", ~o"2026-06-17T22", ~o"2026-06-18T22"]

      # Every ninetieth second from half past a minute is on the minute or
      # half past it.
      assert ~N[2026-06-16 10:15:30]
             |> places_stopped_at(:second, 90)
             |> Enum.map(& &1.second)
             |> Enum.uniq() == [30, 0]

      assert starts("R3/2026-06-16T10:15:30/PT90S/FLT45SN") == []
    end

    test "is told so with a count, an end and a window, and as an iCalendar rule" do
      tuesday = ~o"2026-06-16"

      for text <- [
            "FREQ=DAILY;INTERVAL=7;BYDAY=MO",
            "FREQ=DAILY;INTERVAL=7;BYDAY=MO;COUNT=3",
            "FREQ=DAILY;INTERVAL=14;BYDAY=MO,WE;UNTIL=20290101",
            "FREQ=DAILY;INTERVAL=7;BYDAY=MO;BYMONTH=6"
          ] do
        rule = RRule.parse!(text, from: tuesday)

        assert {:ok, %IntervalSet{} = occurrences} =
                 Tempo.to_interval(rule, within: ~o"2026/2040")

        assert {text, IntervalSet.members(occurrences)} == {text, []}
      end

      at_ten = ~o"2026-06-16T10"

      for text <- [
            "FREQ=HOURLY;INTERVAL=24;BYHOUR=9;COUNT=3",
            "FREQ=HOURLY;INTERVAL=12;BYHOUR=9;COUNT=3",
            "FREQ=MINUTELY;INTERVAL=1440;BYHOUR=9;BYMINUTE=0;COUNT=3",
            "FREQ=SECONDLY;INTERVAL=3600;BYMINUTE=30;COUNT=3"
          ] do
        assert {:ok, %IntervalSet{} = occurrences} =
                 Tempo.to_interval(RRule.parse!(text, from: at_ten))

        assert {text, IntervalSet.members(occurrences)} == {text, []}
      end
    end

    test "is counted from the end of its unit, and from a start coarser than its step" do
      # The sixth day from a week's end is its Tuesday, and its last a Sunday.
      assert starts("R3/2026-06-16/P7D/FL-6KN") == [
               ~o"2026-06-16",
               ~o"2026-06-23",
               ~o"2026-06-30"
             ]

      assert starts("R3/2026-06-16/P7D/FL-1KN") == []

      # June 2026 and its week 25 each begin on a Monday, and 2026 on a
      # Thursday.
      assert Enum.map([~D[2026-06-01], ~D[2026-06-15], ~D[2026-01-01]], &Date.day_of_week/1) ==
               [1, 1, 4]

      assert starts("R3/2026-06/P7D/FL1KN") == [~o"2026-06-01", ~o"2026-06-08", ~o"2026-06-15"]
      assert starts("R3/2026-06/P7D/FL2KN") == []
      assert starts("R3/2026-W25/P7D/FL1KN") == [~o"2026-06-15", ~o"2026-06-22", ~o"2026-06-29"]
      assert starts("R3/2026-W25/P7D/FL2KN") == []
      assert starts("R3/2026/P7D/FL4KN") == [~o"2026-01-01", ~o"2026-01-08", ~o"2026-01-15"]
      assert starts("R3/2026/P7D/FL1KN") == []

      # A start with no time of day is at the first hour of its day.
      assert starts("R3/2026-06-16/PT24H/FLT9HN") == []

      assert starts("R3/2026-06-16/PT24H/FLT0HN") ==
               [~o"2026-06-16T00", ~o"2026-06-17T00", ~o"2026-06-18T00"]
    end

    test "is told so at a time written from UTC, whose clock does not change" do
      assert starts("R3/2026-06-16T10Z/PT24H/FLT9HN") == []
      assert starts("R3/2026-06-16T10+02:00/PT24H/FLT9HN") == []

      assert starts("R3/2026-06-16T10Z/PT24H/FLT10HN") ==
               [~o"2026-06-16T10Z", ~o"2026-06-17T10Z", ~o"2026-06-18T10Z"]
    end
  end

  describe "a part finer than the step" do
    test "makes times in each period, whatever the step" do
      # Every day from 10:00, at 09:00: the hour is the part's and not the
      # start's, so a step of whole days does not pass it.
      assert starts("R3/2026-06-16T10/P1D/FLT9HN") ==
               [~o"2026-06-17T09", ~o"2026-06-18T09", ~o"2026-06-19T09"]

      assert starts("R3/2026-06-16T10/P7D/FL2KT9HN") ==
               [~o"2026-06-23T09", ~o"2026-06-30T09", ~o"2026-07-07T09"]

      assert starts("R3/2026-06-16T10:15/PT1H/FLT30MN") ==
               [~o"2026-06-16T10:30", ~o"2026-06-16T11:30", ~o"2026-06-16T12:30"]
    end
  end

  describe "a rule in another calendar" do
    test "is told so in a calendar of months, whose days of the week are ISO 8601's" do
      # 1 Tammuz 5786 is Tuesday 16 June 2026.
      assert Date.convert!(Date.new!(5786, 10, 1, Hebrew), Calendar.ISO) == ~D[2026-06-16]

      assert starts("R3/5786-10-01[u-ca=hebrew]/P7D/FL1KN") == []
      assert starts("R3/5786-10-01[u-ca=hebrew]/P7D/FL3KN") == []
      assert starts("R3/5786-10-01T10[u-ca=hebrew]/PT12H/FLT9HN") == []

      assert Enum.map(starts("R3/5786-10-01[u-ca=hebrew]/P7D/FL2KN"), &gregorian/1) ==
               [~D[2026-06-16], ~D[2026-06-23], ~D[2026-06-30]]
    end

    test "is told so in a calendar of weeks, whose days are counted from the day its weeks begin on" do
      # The second day of a week, in a calendar whose weeks begin on Monday
      # and in one whose weeks begin on Sunday.
      for calendar <- [ISOWeek, NRF] do
        read = &Tempo.from_iso8601!(&1, calendar)
        second_day = gregorian(read.("2026Y25W2K"))
        every_seventh = [second_day, Date.add(second_day, 7), Date.add(second_day, 14)]

        for {days, named} <- [{"1", []}, {"-1", []}, {"2", every_seventh}, {"-6", every_seventh}] do
          rule = read.("R3/2026Y25W2K/P7D/FL#{days}KN")

          assert {calendar, days, Enum.map(starts_of(rule), &gregorian/1)} ==
                   {calendar, days, named}
        end
      end
    end

    test "counts a rule's days of the week in the calendar the rule is written in" do
      # The second day of a week of NRF's, whose weeks begin on Sunday, is a
      # Monday: the first day of a rule written in the Gregorian calendar.
      monday = Tempo.new!(year: 2026, week: 25, day_of_week: 2, calendar: NRF)
      first = gregorian(monday)
      assert Date.day_of_week(first) == 1

      every_seventh =
        &Interval.new!(from: monday, duration: ~o"P7D", recurrence: 3, repeat_rule: &1)

      assert starts_of(every_seventh.(~o"L2KN")) == []

      assert Enum.map(starts_of(every_seventh.(~o"L1KN")), &gregorian/1) ==
               [first, Date.add(first, 7), Date.add(first, 14)]
    end
  end

  describe "a rule in a zone" do
    test "is told so where it steps by days from a date" do
      assert starts("R3/2026-06-16[Europe/Paris]/P7D/FL1KN") == []

      assert starts("R3/2026-06-16[Europe/Paris]/P7D/FL2KN") == [
               ~o"2026-06-16[Europe/Paris]",
               ~o"2026-06-23[Europe/Paris]",
               ~o"2026-06-30[Europe/Paris]"
             ]
    end

    test "has the occurrences its clock brings it to, where it steps by hours" do
      # Paris's clocks go back on 25 October 2026, and every twenty-fourth
      # hour from 10:00 is 09:00 from then on.
      before = DateTime.new!(~D[2026-10-24], ~T[10:00:00], "Europe/Paris", Tz.TimeZoneDatabase)
      later = DateTime.add(before, 24, :hour, Tz.TimeZoneDatabase)

      assert {DateTime.to_date(later), later.hour} == {~D[2026-10-25], 9}

      assert starts("R3/2026-06-16T10[Europe/Paris]/PT24H/FLT9HN") == [
               ~o"2026-10-25T09[Europe/Paris]",
               ~o"2026-10-26T09[Europe/Paris]",
               ~o"2026-10-27T09[Europe/Paris]"
             ]
    end

    test "is walked where its zone leaves a day out, whose date is moved to another day of the week" do
      # Samoa had no Friday 30 December 2011, and a date that lands on it is
      # moved a day on, to a Saturday: so every seventh day from a Friday
      # has that one Saturday. The rule starts 410 steps before it, and is
      # asked whether it has any occurrence before it comes to it.
      assert {:gap, _before, _after} =
               DateTime.new(~D[2011-12-30], ~T[12:00:00], "Pacific/Apia", Tz.TimeZoneDatabase)

      start = Date.add(~D[2011-12-30], -7 * 410)
      assert {Date.day_of_week(start), Date.day_of_week(~D[2011-12-31])} == {5, 6}

      assert {:ok, %Interval{} = occurrence} =
               Tempo.to_interval(Tempo.from_iso8601!("R1/#{start}[Pacific/Apia]/P7D/FL6KN"))

      assert Interval.from(occurrence) == ~o"2011-12-31[Pacific/Apia]"
    end

    test "is walked where it steps from a time of day, which a clock can move past midnight" do
      # North Korea's clocks went from 23:30 on Friday 4 May 2018 to
      # midnight, so 23:45 that day is 00:15 on the Saturday.
      assert {:gap, _before, %DateTime{day: 5, hour: 0, minute: 0}} =
               DateTime.new(~D[2018-05-04], ~T[23:45:00], "Asia/Pyongyang", Tz.TimeZoneDatabase)

      start = Date.add(~D[2018-05-04], -7 * 410)
      assert {Date.day_of_week(start), Date.day_of_week(~D[2018-05-05])} == {5, 6}

      assert {:ok, %Interval{} = occurrence} =
               Tempo.to_interval(
                 Tempo.from_iso8601!("R1/#{start}T23:45[Asia/Pyongyang]/P7D/FL6KN")
               )

      assert Interval.from(occurrence) == ~o"2018-05-05T00:15[Asia/Pyongyang]"
    end
  end
end
