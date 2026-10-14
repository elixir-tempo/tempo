defmodule Tempo.DayLeftOutTest do
  use ExUnit.Case, async: true

  # A zone that moves across the date line leaves a calendar day out: Samoa
  # went from 29 to 31 December 2011, and Manila from 30 December 1844 to
  # 1 January 1845. A value that names such a day is refused, so nothing
  # else gives one: the day before it meets the day after, and a step, a
  # walk, a recurrence and a selection pass over it.
  #
  # The measure is Elixir's `Date` and `DateTime.from_naive/2`, apart from
  # the library: a day is left out where the clock of its zone shows none of
  # its hours, and the days of a span are the dates of `Date.range/2` that
  # are not.

  alias Tempo.{Duration, Interval, IntervalSet, RRule}

  # Each zone of the IANA database that left a day out, and the day.
  @left_out [
    # Samoa, and Tokelau with it, went from 29 to 31 December 2011.
    {"Pacific/Apia", ~D[2011-12-30]},
    {"Pacific/Fakaofo", ~D[2011-12-30]},
    # The Line and the Phoenix Islands of Kiribati, from 30 December 1994.
    {"Pacific/Kiritimati", ~D[1994-12-31]},
    {"Pacific/Kanton", ~D[1994-12-31]},
    # Kwajalein, from 20 to 22 August 1993.
    {"Pacific/Kwajalein", ~D[1993-08-21]},
    # Manila, from 30 December 1844 to 1 January 1845.
    {"Asia/Manila", ~D[1844-12-31]}
  ]

  # Zones that leave no day out. Alaska crossed the line the other way in
  # 1867 and had a day twice, and Lord Howe Island changes by half an hour.
  @none_left_out [
    {"Etc/UTC", 2011},
    {"America/New_York", 2024},
    {"America/Juneau", 1867},
    {"Australia/Lord_Howe", 2026},
    {"Pacific/Auckland", 2011}
  ]

  ## The measure

  # A day is left out where the clock of its zone shows none of its hours.
  defp left_out?(%Date{} = date, zone), do: Enum.all?(0..23, &skipped?(date, &1, zone))

  defp skipped?(date, hour, zone) do
    {:ok, reading} = NaiveDateTime.new(date, Time.new!(hour, 30, 0))
    match?({:gap, _before, _after}, DateTime.from_naive(reading, zone))
  end

  defp days_of_year(year), do: Date.range(Date.new!(year, 1, 1), Date.new!(year, 12, 31))

  # The dates from `first` to `last` that the zone has.
  defp shown(first, last, zone),
    do: first |> Date.range(last) |> Enum.reject(&left_out?(&1, zone))

  # The date itself where its zone has it, or the first it has in the
  # direction of a step.
  defp settled(date, direction, zone) do
    if left_out?(date, zone),
      do: settled(Date.add(date, direction), direction, zone),
      else: date
  end

  defp direction(amount) when amount < 0, do: -1
  defp direction(_amount), do: 1

  ## Values, and the dates they are

  defp zoned(%Date{year: year, month: month, day: day}, zone),
    do: Tempo.new!(year: year, month: month, day: day, zone: zone)

  defp month_of(%Date{year: year, month: month}, zone),
    do: Tempo.new!(year: year, month: month, zone: zone)

  defp date_of(%Tempo{} = value) do
    {:ok, date} = Tempo.to_date(value)
    date
  end

  # A member is a span, of which the day it begins on, or a value, a day or
  # a time of day on one.
  defp start_of(%Tempo{form: {:span, _from, _to}} = span), do: start_of(Interval.from(span))
  defp start_of(%Tempo{} = value), do: date_of(value)

  defp starts({:ok, %Tempo{} = set}), do: IntervalSet.map(set, &start_of/1)

  defp numbered(days, numbers), do: Enum.filter(days, &(&1.day in numbers))
  defp on_weekday(days, weekday), do: Enum.filter(days, &(Date.day_of_week(&1) == weekday))

  describe "the days a zone leaves out" do
    test "are those the clock shows no hour of, and each is no value" do
      for {zone, day} <- @left_out do
        measured =
          for year <- (day.year - 1)..(day.year + 1),
              date <- days_of_year(year),
              left_out?(date, zone),
              do: date

        assert {zone, measured} == {zone, [day]}

        assert {zone, {:error, %Tempo.ZoneError{reason: :gap}}} =
                 {zone, Tempo.new(year: day.year, month: day.month, day: day.day, zone: zone)}
      end
    end

    test "are none where a zone repeats a day or changes by an hour" do
      for {zone, year} <- @none_left_out do
        assert {zone, Enum.filter(days_of_year(year), &left_out?(&1, zone))} == {zone, []}

        assert {zone, year, Enum.count(Tempo.new!(year: year, month: 12, zone: zone))} ==
                 {zone, year, 31}
      end
    end
  end

  describe "the day before a day its zone leaves out" do
    test "meets the day after, and its span is read back" do
      for {zone, day} <- @left_out do
        before = zoned(Date.add(day, -1), zone)
        next = zoned(Date.add(day, 1), zone)

        assert {zone, Tempo.relation(before, next)} == {zone, :meets}
        assert Tempo.adjacent?(before, next)

        {:ok, span} = Tempo.to_interval(before)
        assert {zone, Tempo.from_iso8601(Tempo.to_iso8601!(span))} == {zone, {:ok, span}}
      end
    end
  end

  describe "the walk of a span that holds a day its zone leaves out" do
    test "passes over it" do
      for {zone, day} <- @left_out do
        month = month_of(day, zone)
        days = shown(Date.beginning_of_month(day), Date.end_of_month(day), zone)

        assert {zone, Enum.map(month, &date_of/1)} == {zone, days}
        assert {zone, Enum.count(month)} == {zone, Enum.count(days)}
      end
    end

    test "is what a count, an index, a slice and a membership answer by" do
      for {zone, day} <- @left_out do
        {:ok, span} =
          Interval.new(from: zoned(Date.add(day, -3), zone), to: zoned(Date.add(day, 3), zone))

        days = shown(Date.add(day, -3), Date.add(day, 3), zone)

        assert {zone, Enum.count(span)} == {zone, Enum.count(days)}

        assert {zone, span |> Enum.slice(1, 4) |> Enum.map(&date_of/1)} ==
                 {zone, Enum.slice(days, 1, 4)}

        for {date, index} <- Enum.with_index(days) do
          assert {zone, index, date_of(Enum.at(span, index))} == {zone, index, date}
          assert Enum.member?(span, zoned(date, zone))
        end
      end
    end
  end

  describe "a step that lands on a day its zone leaves out" do
    test "of days is the day after, or the day before where it runs back" do
      for {zone, day} <- @left_out,
          date <- shown(Date.add(day, -5), Date.add(day, 5), zone),
          amount <- -4..4 do
        {:ok, stepped} = Tempo.shift(zoned(date, zone), day: amount)
        landed = settled(Date.add(date, amount), direction(amount), zone)

        assert {zone, date, amount, date_of(stepped)} == {zone, date, amount, landed}
      end
    end

    test "of months and of years is too" do
      # The date that unit before the day, or after it, where a step from it
      # lands on the day: none does by a month on from November to the 31st.
      for {zone, day} <- @left_out,
          unit <- [:month, :year],
          amount <- [-1, 1],
          date = Date.shift(day, [{unit, -amount}]),
          Date.shift(date, [{unit, amount}]) == day do
        {:ok, stepped} = Tempo.shift(zoned(date, zone), [{unit, amount}])

        assert {zone, unit, amount, date_of(stepped)} ==
                 {zone, unit, amount, settled(day, direction(amount), zone)}
      end
    end

    test "is where a time rounds up to, and the next workday is past it" do
      # Half past noon on the 29th rounds up to the next day Samoa had.
      afternoon =
        Tempo.new!(year: 2011, month: 12, day: 29, hour: 12, minute: 30, zone: "Pacific/Apia")

      {:ok, rounded} = Tempo.round(afternoon, :day)
      assert date_of(rounded) == settled(~D[2011-12-30], 1, "Pacific/Apia")

      # The Friday was the day left out, so the workday after Thursday the
      # 29th is the Monday.
      monday =
        ~D[2011-12-30]
        |> Date.range(~D[2012-01-10])
        |> Enum.find(&(not left_out?(&1, "Pacific/Apia") and Date.day_of_week(&1) in 1..5))

      {:ok, next} = Tempo.next_workday(zoned(~D[2011-12-29], "Pacific/Apia"), :US)
      assert date_of(next) == monday
    end
  end

  describe "a recurrence of days in a zone that leaves a day out" do
    defp every(cadence, start, zone, count),
      do: Tempo.every!(Duration.new!(cadence), from: zoned(start, zone), count: count)

    # The start that many days before the day left out, so that a step of
    # each cadence lands on it.
    test "has the occurrence that lands on it on the day after, once" do
      for {zone, day} <- @left_out, cadence <- [1, 2, 3, 7] do
        start = Date.add(day, -cadence)

        # Each step from the start, a step onto the day moved to the day
        # after, where the step after it lands too when the cadence is a day.
        expected =
          0
          |> Stream.iterate(&(&1 + 1))
          |> Stream.map(&settled(Date.add(start, &1 * cadence), 1, zone))
          |> Stream.dedup()
          |> Enum.take(5)

        assert {zone, cadence, starts(Tempo.to_interval(every([day: cadence], start, zone, 5)))} ==
                 {zone, cadence, expected}
      end
    end

    test "of weeks keeps its day of the week after it" do
      for {zone, day} <- @left_out do
        start = Date.add(day, -7)
        expected = for step <- 0..3, do: settled(Date.add(start, 7 * step), 1, zone)

        assert {zone, starts(Tempo.to_interval(every([week: 1], start, zone, 4)))} ==
                 {zone, expected}

        assert Date.day_of_week(List.last(expected)) == Date.day_of_week(start)
      end
    end

    test "of months has it on the day after, and the months after as they were" do
      for {zone, day} <- @left_out do
        start = Date.shift(day, month: -2)
        expected = for step <- 0..3, do: settled(Date.shift(start, month: step), 1, zone)

        assert Enum.at(expected, 2) == settled(day, 1, zone)

        assert {zone, starts(Tempo.to_interval(every([month: 1], start, zone, 4)))} ==
                 {zone, expected}
      end
    end

    test "that selects days selects none it does not have" do
      # The 29th, 30th and 31st of each month, of the days of December 2011.
      selecting =
        Tempo.every!(Duration.new!(month: 1),
          from: zoned(~D[2011-12-01], "Pacific/Apia"),
          select: [day: [29, 30, 31]]
        )

      days = numbered(shown(~D[2011-12-01], ~D[2011-12-31], "Pacific/Apia"), [29, 30, 31])

      assert starts(
               Tempo.to_interval(selecting, within: month_of(~D[2011-12-01], "Pacific/Apia"))
             ) ==
               days
    end

    test "read from an RRULE passes over it" do
      apia = "Pacific/Apia"

      {:ok, daily} = RRule.parse("FREQ=DAILY;COUNT=5", from: zoned(~D[2011-12-28], apia))

      assert starts(Tempo.to_interval(daily)) ==
               Enum.take(shown(~D[2011-12-28], ~D[2012-01-10], apia), 5)

      # The 30th of each month that has one: February has none in its
      # calendar, and December 2011 had none in Samoa.
      {:ok, monthly} =
        RRule.parse("FREQ=MONTHLY;BYMONTHDAY=30;COUNT=4", from: zoned(~D[2011-10-30], apia))

      thirtieths = ~D[2011-10-01] |> shown(~D[2012-04-30], apia) |> numbered([30]) |> Enum.take(4)
      assert starts(Tempo.to_interval(monthly)) == thirtieths

      # Each Friday from the 23rd: the Friday after it was the day left out.
      {:ok, weekly} =
        RRule.parse("FREQ=WEEKLY;BYDAY=FR;COUNT=3", from: zoned(~D[2011-12-23], apia))

      fridays = ~D[2011-12-23] |> shown(~D[2012-02-01], apia) |> on_weekday(5) |> Enum.take(3)
      assert starts(Tempo.to_interval(weekly)) == fridays
    end
  end

  describe "a selection from a span that holds a day its zone leaves out" do
    test "selects no day of the month it does not have" do
      for {zone, day} <- @left_out do
        month = month_of(day, zone)
        days = shown(Date.beginning_of_month(day), Date.end_of_month(day), zone)

        # The day alone, by its number and as a selection.
        assert {zone, starts(Tempo.select(month, [day.day]))} == {zone, []}
        assert {zone, starts(Tempo.select(month, Tempo.selection!(day: day.day)))} == {zone, []}

        # The day and the one before it: the one before alone.
        pair = [day.day - 1, day.day]
        assert {zone, starts(Tempo.select(month, pair))} == {zone, numbered(days, pair)}
      end
    end

    test "selects no day of the week on it" do
      for {zone, day} <- @left_out do
        month = month_of(day, zone)
        days = shown(Date.beginning_of_month(day), Date.end_of_month(day), zone)

        for weekday <- [Date.day_of_week(day), Date.day_of_week(Date.add(day, -1))] do
          assert {zone, weekday,
                  starts(Tempo.select(month, Tempo.selection!(day_of_week: weekday)))} ==
                   {zone, weekday, on_weekday(days, weekday)}
        end
      end
    end

    test "selects no time of day on it" do
      december = month_of(~D[2011-12-01], "Pacific/Apia")
      fridays = on_weekday(shown(~D[2011-12-01], ~D[2011-12-31], "Pacific/Apia"), 5)

      # Ten o'clock on each Friday: the Friday left out has no ten o'clock.
      assert starts(Tempo.select(december, Tempo.selection!(day_of_week: 5, hour: 10))) == fridays
      assert starts(Tempo.select(december, Tempo.selection!(day: 30, hour: 10))) == []
    end

    test "is so for workdays" do
      december = shown(~D[2011-12-01], ~D[2011-12-31], "Pacific/Apia")
      weekdays = Enum.reject(december, &(Date.day_of_week(&1) in [6, 7]))

      assert starts(Tempo.select(month_of(~D[2011-12-01], "Pacific/Apia"), Tempo.workdays(:US))) ==
               weekdays
    end
  end

  describe "a value placed on a day its zone leaves out" do
    test "is refused, as it is when read" do
      for {zone, day} <- @left_out do
        month = month_of(day, zone)

        assert {zone, {:error, %Tempo.ZoneError{reason: :gap}}} =
                 {zone, Tempo.on(Tempo.new!(day: day.day), month)}

        assert {:ok, placed} = Tempo.on(Tempo.new!(day: day.day - 1), month)
        assert {zone, date_of(placed)} == {zone, Date.add(day, -1)}
      end
    end
  end
end
