defmodule Tempo.DayLeftOutTest do
  @moduledoc """
  A zone that moves across the date line leaves a calendar day out: Samoa
  went from 29 to 31 December 2011, and Manila from 30 December 1844 to
  1 January 1845. A value that names such a day is refused when it is read
  (`Tempo.ZoneValidationTest`), so nothing else gives one: the day before it
  ends where the day after begins, and a step, a walk, a recurrence and a
  selection pass over it.

  The day was produced by each of these, and the value could then not be
  read back.

  The measure is Elixir's `Date` and `DateTime.from_naive/2`: a day is left
  out where the clock of its zone shows none of its hours, and the days of a
  span are the dates of `Date.range/2` that are not.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.TimeZoneDatabase

  doctest Tempo.TimeZoneDatabase

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
    {:ok, time} = Time.new(hour, 30, 0)
    {:ok, reading} = NaiveDateTime.new(date, time)

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

  ## Values and what they are read as

  defp zoned(%Date{} = date, zone),
    do: Tempo.from_iso8601!("#{Date.to_iso8601(date)}[#{zone}]")

  defp month_of(%Date{} = date, zone) do
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    Tempo.from_iso8601!("#{date.year}-#{month}[#{zone}]")
  end

  defp date_of(%Tempo{} = value) do
    {:ok, date} = Tempo.to_date(value)
    date
  end

  defp dates_of(%Interval{} = span),
    do: {date_of(Interval.from(span)), date_of(Interval.to(span))}

  defp spans({:ok, %IntervalSet{} = set}), do: Enum.map(IntervalSet.members(set), &dates_of/1)

  # Each day as the span the zone gives it: to the next day it has.
  defp day_spans(dates, zone),
    do: Enum.map(dates, &{&1, settled(Date.add(&1, 1), 1, zone)})

  defp occurrence_starts(text) do
    text
    |> Tempo.from_iso8601!()
    |> Tempo.to_interval()
    |> spans()
    |> starts_of()
  end

  defp starts_of(spans), do: Enum.map(spans, &elem(&1, 0))

  defp selector(text), do: Tempo.from_iso8601!(text)

  defp numbered(days, numbers), do: Enum.filter(days, &(&1.day in numbers))
  defp on_weekday(days, weekday), do: Enum.filter(days, &(Date.day_of_week(&1) == weekday))

  describe "the days a zone leaves out" do
    test "are those the clock shows no hour of" do
      for {zone, day} <- @left_out do
        measured =
          for year <- (day.year - 1)..(day.year + 1),
              date <- days_of_year(year),
              left_out?(date, zone),
              do: date

        assert {zone, measured} == {zone, [day]}
        assert {zone, TimeZoneDatabase.days_left_out(zone)} == {zone, [Date.to_erl(day)]}
      end
    end

    test "are none where a zone repeats a day or changes by an hour" do
      for {zone, year} <- @none_left_out do
        assert {zone, Enum.filter(days_of_year(year), &left_out?(&1, zone))} == {zone, []}
        assert {zone, TimeZoneDatabase.days_left_out(zone)} == {zone, []}
      end
    end
  end

  describe "the day before a day its zone leaves out" do
    test "ends where the day after begins, and its span is read back" do
      for {zone, day} <- @left_out do
        before = Date.add(day, -1)
        {:ok, span} = Tempo.to_interval(zoned(before, zone))

        assert {zone, dates_of(span)} == {zone, {before, settled(day, 1, zone)}}

        assert {:ok, read} = Tempo.from_iso8601(Tempo.to_iso8601!(span))
        assert {zone, dates_of(read)} == {zone, dates_of(span)}
      end
    end

    test "meets the day after" do
      for {zone, day} <- @left_out do
        before = zoned(Date.add(day, -1), zone)
        next = zoned(Date.add(day, 1), zone)

        assert {zone, Tempo.relation(before, next)} == {zone, :meets}
        assert Tempo.adjacent?(before, next)
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
          Interval.new(from: zoned(Date.add(day, -3), zone), to: zoned(Date.add(day, 4), zone))

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
        stepped = Tempo.shift(zoned(date, zone), day: amount)
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
        stepped = Tempo.shift(zoned(date, zone), [{unit, amount}])

        assert {zone, unit, amount, date_of(stepped)} ==
                 {zone, unit, amount, settled(day, direction(amount), zone)}
      end
    end

    test "from a week date or a day of the year is too" do
      assert date_of(Tempo.shift(~o"2011-W52-4[Pacific/Apia]", day: 1)) == ~D[2011-12-31]
      assert date_of(Tempo.shift(~o"2011-363[Pacific/Apia]", day: 1)) == ~D[2011-12-31]
    end

    test "is where a time rounds up to, and the next workday is past it" do
      # Half past noon on the 29th rounds up to the next day Samoa had.
      assert date_of(Tempo.round(~o"2011-12-29T12:30[Pacific/Apia]", :day)) ==
               settled(~D[2011-12-30], 1, "Pacific/Apia")

      # The Friday was the day left out, so the workday after Thursday the
      # 29th is the Monday.
      monday =
        ~D[2011-12-30]
        |> Date.range(~D[2012-01-10])
        |> Enum.find(&(not left_out?(&1, "Pacific/Apia") and Date.day_of_week(&1) in 1..5))

      assert date_of(Tempo.next_workday(~o"2011-12-29[Pacific/Apia]", :US)) == monday
    end
  end

  describe "a recurrence of days in a zone that leaves a day out" do
    # The start that many days before the day left out, so that a step of
    # each cadence lands on it.
    test "has the occurrence that lands on it on the day after, once" do
      for {zone, day} <- @left_out, cadence <- [1, 2, 3, 7] do
        start = Date.add(day, -cadence)
        text = "R5/#{Date.to_iso8601(start)}[#{zone}]/P#{cadence}D"

        # Each step from the start, a step onto the day moved to the day
        # after, where the step after it lands too when the cadence is a day.
        starts =
          0
          |> Stream.iterate(&(&1 + 1))
          |> Stream.map(&settled(Date.add(start, &1 * cadence), 1, zone))
          |> Stream.dedup()
          |> Enum.take(6)

        # Each occurrence ends where the next starts.
        expected = Enum.zip(starts, tl(starts))

        assert {text, spans(Tempo.to_interval(Tempo.from_iso8601!(text)))} == {text, expected}
      end
    end

    test "of weeks keeps its day of the week after it" do
      for {zone, day} <- @left_out do
        start = Date.add(day, -7)
        text = "R4/#{Date.to_iso8601(start)}[#{zone}]/P1W"

        # The week after the start is moved a day on, and the weeks after it
        # are on the start's day of the week again.
        starts = for step <- 0..3, do: settled(Date.add(start, 7 * step), 1, zone)

        assert {text, occurrence_starts(text)} == {text, starts}
        assert Date.day_of_week(List.last(starts)) == Date.day_of_week(start)
      end
    end

    test "of months has it on the day after, and the months after as they were" do
      for {zone, day} <- @left_out do
        start = Date.shift(day, month: -2)
        text = "R4/#{Date.to_iso8601(start)}[#{zone}]/P1M"

        starts = for step <- 0..3, do: settled(Date.shift(start, month: step), 1, zone)

        assert Enum.at(starts, 2) == settled(day, 1, zone)
        assert {text, occurrence_starts(text)} == {text, starts}
      end
    end

    test "with no year, placed on a window that starts on it, starts on the day after" do
      for {zone, day} <- @left_out do
        # The day's number in each month, from the month that leaves it out.
        recurrence = Tempo.from_iso8601!("R3/#{day.day}D/P1M")

        window =
          Tempo.from_iso8601!(
            "#{Date.to_iso8601(Date.beginning_of_month(day))}[#{zone}]/" <>
              "#{Date.to_iso8601(Date.shift(day, month: 4))}[#{zone}]"
          )

        starts = for step <- 0..2, do: settled(Date.shift(day, month: step), 1, zone)

        assert {zone, recurrence |> Tempo.to_interval(within: window) |> spans() |> starts_of()} ==
                 {zone, starts}
      end
    end

    test "selects no day it does not have" do
      # The 29th, 30th and 31st of each month, of the days of December 2011.
      selected =
        Tempo.to_interval(~o"R/2011-12-01[Pacific/Apia]/P1D/FL{29,30,31}DN",
          within: ~o"2011-12[Pacific/Apia]"
        )

      days = numbered(shown(~D[2011-12-01], ~D[2011-12-31], "Pacific/Apia"), [29, 30, 31])

      assert spans(selected) == day_spans(days, "Pacific/Apia")
    end

    test "read from an RRULE passes over it" do
      {:ok, daily} = RRule.parse("FREQ=DAILY;COUNT=5", from: ~o"2011-12-28[Pacific/Apia]")
      days = Enum.take(shown(~D[2011-12-28], ~D[2012-01-10], "Pacific/Apia"), 5)

      assert spans(Tempo.to_interval(daily)) == day_spans(days, "Pacific/Apia")

      # The 30th of each month that has one: February has none in its
      # calendar, and December 2011 had none in Samoa.
      {:ok, monthly} =
        RRule.parse("FREQ=MONTHLY;BYMONTHDAY=30;COUNT=4", from: ~o"2011-10-30[Pacific/Apia]")

      thirtieths =
        ~D[2011-10-01]
        |> shown(~D[2012-04-30], "Pacific/Apia")
        |> numbered([30])
        |> Enum.take(4)

      assert spans(Tempo.to_interval(monthly)) == day_spans(thirtieths, "Pacific/Apia")

      # Each Friday from the 23rd: the Friday after it was the day left out.
      {:ok, weekly} =
        RRule.parse("FREQ=WEEKLY;BYDAY=FR;COUNT=3", from: ~o"2011-12-23[Pacific/Apia]")

      fridays =
        ~D[2011-12-23]
        |> shown(~D[2012-02-01], "Pacific/Apia")
        |> on_weekday(5)
        |> Enum.take(3)

      assert spans(Tempo.to_interval(weekly)) == day_spans(fridays, "Pacific/Apia")
    end
  end

  describe "a selection from a span that holds a day its zone leaves out" do
    test "selects no day of the month it does not have" do
      for {zone, day} <- @left_out do
        month = month_of(day, zone)
        days = shown(Date.beginning_of_month(day), Date.end_of_month(day), zone)

        # The day alone, by its number, by an index and as a selection.
        assert {zone, spans(Tempo.select(month, selector("#{day.day}D")))} == {zone, []}
        assert {zone, spans(Tempo.select(month, [day.day]))} == {zone, []}
        assert {zone, spans(Tempo.select(month, selector("L#{day.day}DN")))} == {zone, []}

        # The day and the one before it: the one before, to the day after.
        pair = [day.day - 1, day.day]
        expected = day_spans(numbered(days, pair), zone)

        assert {zone, spans(Tempo.select(month, selector("{#{day.day - 1},#{day.day}}D")))} ==
                 {zone, expected}

        assert {zone, spans(Tempo.select(month, pair))} == {zone, expected}
      end
    end

    test "selects no day of the week on it, and ends the day before on the day after" do
      for {zone, day} <- @left_out do
        month = month_of(day, zone)
        days = shown(Date.beginning_of_month(day), Date.end_of_month(day), zone)

        left_out = Date.day_of_week(day)
        before = Date.day_of_week(Date.add(day, -1))

        for weekday <- [left_out, before] do
          expected = day_spans(on_weekday(days, weekday), zone)

          assert {zone, weekday, spans(Tempo.select(month, selector("#{weekday}K")))} ==
                   {zone, weekday, expected}

          assert {zone, weekday, spans(Tempo.select(month, selector("L#{weekday}KN")))} ==
                   {zone, weekday, expected}
        end
      end
    end

    test "ends a span of days on the day after it" do
      for {zone, day} <- @left_out do
        month = month_of(day, zone)
        first = day.day - 2

        # Two days from two days before it: the second ends where the day
        # left out would begin, which is where the day after does.
        assert {zone, spans(Tempo.select(month, selector("#{first}D/#{day.day}D")))} ==
                 {zone, [{Date.add(day, -2), settled(day, 1, zone)}]}
      end
    end

    test "selects no span that starts on it" do
      # Where the month has a day after it to end the span on.
      for {zone, day} <- @left_out, day.day < Date.days_in_month(day) do
        span = selector("#{day.day}D/#{day.day + 1}D")

        assert {zone, spans(Tempo.select(month_of(day, zone), span))} == {zone, []}
      end
    end

    test "selects no time of day on it" do
      december = ~o"2011-12[Pacific/Apia]"
      fridays = on_weekday(shown(~D[2011-12-01], ~D[2011-12-31], "Pacific/Apia"), 5)

      # Ten o'clock on each Friday: the Friday left out has no ten o'clock,
      # and the reading a day on would be a Saturday's.
      {:ok, at_ten} = Tempo.select(december, ~o"5KT10H")

      assert Enum.map(
               IntervalSet.members(at_ten),
               &date_of(Tempo.trunc(Interval.from(&1), :day))
             ) == fridays

      assert {:ok, on_the_day} = Tempo.select(december, ~o"30DT10H")
      assert IntervalSet.members(on_the_day) == []

      {:ok, monthly} =
        RRule.parse("FREQ=MONTHLY;BYMONTHDAY=30;COUNT=3",
          from: ~o"2011-10-30T10:00:00[Pacific/Apia]"
        )

      thirtieths =
        Enum.take(numbered(shown(~D[2011-10-01], ~D[2012-04-30], "Pacific/Apia"), [30]), 3)

      {:ok, occurrences} = Tempo.to_interval(monthly)

      assert Enum.map(
               IntervalSet.members(occurrences),
               &date_of(Tempo.trunc(Interval.from(&1), :day))
             ) == thirtieths
    end

    test "is so for workdays, and for a span with no end" do
      december = shown(~D[2011-12-01], ~D[2011-12-31], "Pacific/Apia")
      weekdays = Enum.reject(december, &(Date.day_of_week(&1) in [6, 7]))

      assert spans(Tempo.select(~o"2011-12[Pacific/Apia]", Tempo.workdays(:US))) ==
               day_spans(weekdays, "Pacific/Apia")

      # The Fridays from Monday the 26th on: the first is in January.
      {:ok, fridays} = Tempo.select(~o"2011-12-26[Pacific/Apia]/..", ~o"5K")

      expected =
        ~D[2011-12-26]
        |> shown(~D[2012-02-01], "Pacific/Apia")
        |> on_weekday(5)
        |> Enum.take(3)

      assert fridays |> IntervalSet.walk() |> Enum.take(3) |> Enum.map(&dates_of/1) ==
               day_spans(expected, "Pacific/Apia")
    end
  end

  describe "a value placed on a day its zone leaves out" do
    test "is refused, as it is when read" do
      for {zone, day} <- @left_out do
        numbered = selector("#{day.day}D")

        assert {:error, %Tempo.ZoneGapError{zone_id: ^zone}} =
                 Tempo.on(numbered, month_of(day, zone))

        assert {:ok, placed} = Tempo.on(selector("#{day.day - 1}D"), month_of(day, zone))
        assert date_of(placed) == Date.add(day, -1)
      end
    end
  end
end
