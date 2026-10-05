defmodule Tempo.RRule.YearlyPartsTest do
  use ExUnit.Case, async: true

  # RFC 5545 §3.3.10 gives a yearly rule the days that satisfy every part it
  # holds: a month, a day of the month, a day of the year, a weekday and, in
  # Tempo, a computed event. The resolver applies the parts one after another,
  # and the measure here is taken apart from it: every day of every year is
  # asked, with `Date` alone, whether each part of the rule holds for it.
  #
  # What a rule does not say is DTSTART's, as ISO 8601-2 Annex C.3 lists it: a
  # rule that names no day takes DTSTART's day of the month, and one that
  # names a day of the month and no month takes DTSTART's month. A month
  # that lacks the day has no occurrence.

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Tempo.Event
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  @years 2026..2029

  # A first occurrence at the start of a year and one on a 31st, a day five
  # months do not have.
  @starts [~D[2026-01-01], ~D[2026-01-31]]

  @months [nil, [3], [3, 4]]
  @days_of_year [nil, [100], [80, 100], [-1], [60]]
  @days_of_month [nil, [15], [-1], [29]]
  @weekdays [nil, [7]]
  @events [nil, "easter"]

  # Every rule the parts make, but for a day of the month beside an event,
  # which the grammar does not read, and the rule of no parts.
  defp rules do
    for month <- @months,
        day_of_year <- @days_of_year,
        day_of_month <- @days_of_month,
        event <- @events,
        weekday <- @weekdays,
        not (day_of_month != nil and event != nil),
        parts = parts(month, day_of_year, day_of_month, event, weekday),
        parts != [],
        do: parts
  end

  defp parts(month, day_of_year, day_of_month, event, weekday) do
    Enum.reject(
      [
        month: month,
        day_of_year: day_of_year,
        day_of_month: day_of_month,
        event: event,
        weekday: weekday
      ],
      fn {_part, value} -> is_nil(value) end
    )
  end

  # The days that satisfy every part of a rule, from DTSTART on.
  defp days_that_satisfy(parts, start) do
    parts = with_start(parts, start)

    for year <- @years,
        date <- Date.range(Date.new!(year, 1, 1), Date.new!(year, 12, 31)),
        Date.compare(date, start) != :lt,
        Enum.all?(parts, &holds?(&1, date)),
        do: date
  end

  # What a rule leaves unsaid is DTSTART's: its day where the rule names no
  # day, and its month where the rule names no month and no day of the year.
  defp with_start(parts, start) do
    named = Keyword.keys(parts)

    cond do
      :day_of_year in named or :event in named -> parts
      :day_of_month in named and :month in named -> parts
      :day_of_month in named -> parts ++ [month: [start.month]]
      :weekday in named -> parts
      :month in named -> parts ++ [start_day: start.day]
      true -> parts
    end
  end

  defp holds?({:month, months}, date), do: date.month in months
  defp holds?({:weekday, weekdays}, date), do: Date.day_of_week(date) in weekdays
  defp holds?({:event, name}, date), do: Event.date(name, date.year) == {:ok, date}
  defp holds?({:start_day, day}, date), do: date.day == day

  defp holds?({:day_of_month, days}, date),
    do: counted?(date.day, days, Date.days_in_month(date))

  defp holds?({:day_of_year, days}, date),
    do: counted?(Date.day_of_year(date), days, days_in_year(date))

  # A day is counted from the start of its period or, by a negative number,
  # from its end.
  defp counted?(day, days, last), do: day in days or (day - last - 1) in days

  defp days_in_year(date), do: if(Date.leap_year?(date), do: 366, else: 365)

  # The rule as an RRULE, and with an event, which RFC 5545 has no part for,
  # as an ISO 8601-2 selection.
  defp read(parts, start) do
    if Keyword.has_key?(parts, :event),
      do:
        Tempo.from_iso8601("R/#{Date.to_iso8601(start)}/P1Y/FL#{Enum.map_join(parts, &iso/1)}N"),
      else: RRule.parse(rrule(parts), from: Tempo.from_date(start))
  end

  defp rrule(parts),
    do: Enum.join(["FREQ=YEARLY" | Enum.map(parts, &by_part/1)], ";")

  defp by_part({:month, months}), do: "BYMONTH=#{Enum.join(months, ",")}"
  defp by_part({:day_of_year, days}), do: "BYYEARDAY=#{Enum.join(days, ",")}"
  defp by_part({:day_of_month, days}), do: "BYMONTHDAY=#{Enum.join(days, ",")}"
  defp by_part({:weekday, [7]}), do: "BYDAY=SU"

  defp iso({:month, months}), do: "#{set(months)}M"
  defp iso({:day_of_year, days}), do: "#{set(days)}O"
  defp iso({:event, name}), do: "(#{name})e"
  defp iso({:weekday, weekdays}), do: "#{set(weekdays)}K"

  defp set([value]), do: Integer.to_string(value)
  defp set(values), do: "{#{Enum.join(values, ",")}}"

  # The day each occurrence of a rule is, in the years measured. An
  # occurrence a rule's parts name is one day long.
  defp occurrences(rule) do
    {:ok, set} = Tempo.to_interval(rule, within: ~o"2026Y/2030Y")

    for occurrence <- IntervalSet.members(set) do
      {:ok, date} = occurrence |> Interval.from() |> Tempo.to_date()
      {:ok, next} = occurrence |> Interval.to() |> Tempo.to_date()
      {date, Date.diff(next, date)}
    end
  end

  describe "the parts of a yearly rule that name a day" do
    for start <- @starts do
      test "select the days that satisfy every one of them, from #{start}" do
        start = unquote(Macro.escape(start))

        for parts <- rules() do
          {:ok, rule} = read(parts, start)
          expected = for date <- days_that_satisfy(parts, start), do: {date, 1}

          assert {parts, occurrences(rule)} == {parts, expected}
        end
      end
    end

    test "a month limits a day of the year and an event beside it" do
      {:ok, day_100} = RRule.parse("FREQ=YEARLY;BYMONTH=4;BYYEARDAY=100", from: ~o"2026-01-01")

      assert Enum.map(occurrences(day_100), &elem(&1, 0)) ==
               [~D[2026-04-10], ~D[2027-04-10], ~D[2028-04-09], ~D[2029-04-10]]

      {:ok, in_march} = RRule.parse("FREQ=YEARLY;BYMONTH=3;BYYEARDAY=100", from: ~o"2026-01-01")
      assert occurrences(in_march) == []

      # Easter is in March in 2027 alone of these years.
      assert Enum.map(occurrences(~o"R/2026-01-01/P1Y/FL3M(easter)eN"), &elem(&1, 0)) ==
               [~D[2027-03-28]]
    end

    test "are each listed once where the rule names several months" do
      {:ok, rule} =
        RRule.parse("FREQ=YEARLY;BYMONTH=3,4;BYYEARDAY=80,100;COUNT=4", from: ~o"2026-01-01")

      {:ok, set} = Tempo.to_interval(rule)

      assert Enum.map(IntervalSet.members(set), &Interval.from/1) ==
               [~o"2026-03-21", ~o"2026-04-10", ~o"2027-03-21", ~o"2027-04-10"]
    end

    test "a day of the month keeps a day of the year that is one" do
      # Day 74 is 15 March, and 14 March in a leap year.
      {:ok, rule} = RRule.parse("FREQ=YEARLY;BYMONTHDAY=15;BYYEARDAY=74", from: ~o"2026-01-01")

      assert Enum.map(occurrences(rule), &elem(&1, 0)) ==
               [~D[2026-03-15], ~D[2027-03-15], ~D[2029-03-15]]
    end

    test "hold in another calendar as it counts its months and its days" do
      # The 178th day of a Hebrew year is in its sixth month or its seventh,
      # as the months before it are long.
      for month <- 6..7 do
        rule = Tempo.from_iso8601!("R/../P1Y/FL#{month}M178ON", Hebrew)
        {:ok, set} = Tempo.to_interval(rule, within: Tempo.from_iso8601!("5780Y/5791Y", Hebrew))

        selected =
          for occurrence <- IntervalSet.members(set) do
            {:ok, date} = occurrence |> Interval.from() |> Tempo.to_date()
            date
          end

        expected =
          for year <- 5780..5790,
              date = Date.add(Date.new!(year, 1, 1, Hebrew), 177),
              date.month == month,
              do: date

        assert {month, selected} == {month, expected}
      end
    end

    test "an event keeps a day of the year that is its day" do
      # Easter is day 95 of 2026, 5 April, and of no other of these years.
      assert Enum.map(occurrences(~o"R/2026-01-01/P1Y/FL95O(easter)eN"), &elem(&1, 0)) ==
               [~D[2026-04-05]]
    end
  end
end
