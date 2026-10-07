defmodule Tempo.RRule.PeriodPartsTest do
  use ExUnit.Case, async: true

  # A selection in a whole week or a whole month: `Tempo.select/2` from one,
  # a value such as `2026Y25WL15DN`, and a recurrence that starts at its
  # cadence's own resolution or has no start. The resolver's table is RFC
  # 5545's, whose candidate at every frequency is a day, so a part the table
  # does not give a frequency limited the whole period by the day it starts
  # on: the 15th selected from a week was the whole week where the week began
  # on a 15th, and nothing where the 15th fell later in it.
  #
  # What each part selects there (decided 2026-10-05): a day (`D`) is each
  # day of the period that is that day of its month, and a day of the year
  # (`O`) each day that is that day of its year; a month or a week keeps the
  # period that starts in it; a week under a month is the week of the month,
  # which is not built.
  #
  # The measure is `Date` and `:calendar` alone: every day of the period is
  # asked whether the part names it.

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  # What is written, as text and as the numbers and ranges it names.
  @days_of_month [
    {"15", [15]},
    {"1", [1]},
    {"-1", [-1]},
    {"{1,15}", [1, 15]},
    {"{14..16}", [14..16//1]},
    {"{28..-1}", [28..-1//1]}
  ]

  @days_of_year [
    {"166", [166]},
    {"1", [1]},
    {"-1", [-1]},
    {"{1,60,366}", [1, 60, 366]},
    {"{165..167}", [165..167//1]}
  ]

  defp named_among(written, last) do
    written
    |> Enum.flat_map(fn
      %Range{first: from, last: to, step: step} ->
        Enum.to_list(counted(from, last)..counted(to, last)//step)

      number ->
        [counted(number, last)]
    end)
    |> Enum.filter(&(&1 in 1..last))
  end

  defp counted(number, last) when number < 0, do: last + 1 + number
  defp counted(number, _last), do: number

  defp day_of_month?(date, written),
    do: date.day in named_among(written, Date.days_in_month(date))

  defp day_of_year?(date, written) do
    days = if Date.leap_year?(date), do: 366, else: 365
    Date.day_of_year(date) in named_among(written, days)
  end

  # The Monday of an ISO 8601 week: 4 January is always in week 1.
  defp monday(year, week) do
    fourth = Date.new!(year, 1, 4)
    Date.add(fourth, 1 - Date.day_of_week(fourth) + 7 * (week - 1))
  end

  defp weeks_of(year) do
    {^year, last} = :calendar.iso_week_number({year, 12, 28})
    1..last
  end

  defp days_of_week(year, week), do: for(day <- 0..6, do: Date.add(monday(year, week), day))

  defp days_of_month(year, month) do
    first = Date.new!(year, month, 1)
    Enum.to_list(Date.range(first, Date.end_of_month(first)))
  end

  # The day each selected span starts on, and how many days long it is.
  defp spans({:ok, %IntervalSet{} = set}) do
    for member <- IntervalSet.members(set) do
      {:ok, from} = member |> Interval.from() |> Tempo.extend_resolution(:day) |> Tempo.to_date()
      {:ok, to} = member |> Interval.to() |> Tempo.extend_resolution(:day) |> Tempo.to_date()
      {from, Date.diff(to, from)}
    end
  end

  defp read(text), do: Tempo.from_iso8601!(text)

  # A selection in a period, by each way it is asked: selected from the
  # period, written after it in a value, and as the rule of a recurrence that
  # starts at the period.
  defp each_way(period, cadence, selection) do
    recurrence = read("R/#{period}/#{cadence}/FL#{selection}N")

    [
      {"select/2", Tempo.select(read(period), read("L#{selection}N"))},
      {"a value", Tempo.to_interval(read("#{period}L#{selection}N"))},
      {"a recurrence", Tempo.to_interval(recurrence, within: read(period))}
    ]
  end

  describe "a day of the month, selected in a week" do
    test "is each day of the week that is that day of its month" do
      for year <- [2025, 2026], week <- weeks_of(year), {text, written} <- @days_of_month do
        expected =
          for date <- days_of_week(year, week), day_of_month?(date, written), do: {date, 1}

        for {way, answer} <- each_way("#{year}Y#{week}W", "P1W", "#{text}D") do
          assert {year, week, text, way, spans(answer)} == {year, week, text, way, expected}
        end
      end
    end

    test "with a weekday beside it is the days that are both" do
      for year <- [2025, 2026], week <- weeks_of(year) do
        expected =
          for date <- days_of_week(year, week),
              date.day == 15 and Date.day_of_week(date) == 1,
              do: {date, 1}

        selected = spans(Tempo.select(read("#{year}Y#{week}W"), ~o"L15D1KN"))
        assert {year, week, selected} == {year, week, expected}
      end
    end
  end

  describe "a day of the year, selected in a week or a month" do
    test "is each day of the week that is that day of its year" do
      for year <- [2024, 2026], week <- weeks_of(year), {text, written} <- @days_of_year do
        expected =
          for date <- days_of_week(year, week), day_of_year?(date, written), do: {date, 1}

        for {way, answer} <- each_way("#{year}Y#{week}W", "P1W", "#{text}O") do
          assert {year, week, text, way, spans(answer)} == {year, week, text, way, expected}
        end
      end
    end

    test "is each day of the month that is that day of its year" do
      for year <- [2024, 2026], month <- 1..12, {text, written} <- @days_of_year do
        expected =
          for date <- days_of_month(year, month), day_of_year?(date, written), do: {date, 1}

        for {way, answer} <- each_way("#{year}Y#{month}M", "P1M", "#{text}O") do
          assert {year, month, text, way, spans(answer)} == {year, month, text, way, expected}
        end
      end
    end
  end

  describe "a month or a week, selected in a week" do
    test "keeps the week that starts in the month" do
      for year <- [2025, 2026], week <- weeks_of(year), months <- [[6], [1, 12]] do
        start = monday(year, week)
        expected = if start.month in months, do: [{start, 7}], else: []
        text = "{#{Enum.join(months, ",")}}M"

        selected = spans(Tempo.select(read("#{year}Y#{week}W"), read("L#{text}N")))
        assert {year, week, text, selected} == {year, week, text, expected}
      end
    end

    test "beside a weekday keeps the days of the week that are both" do
      # The week of Monday 29 June 2026 starts in June, and its Wednesday
      # and its Sunday are in July: the month is asked of the days.
      for year <- [2025, 2026], week <- weeks_of(year), months <- [[6], [1, 12]] do
        expected =
          for date <- days_of_week(year, week),
              date.month in months and Date.day_of_week(date) in [3, 7],
              do: {date, 1}

        text = "{#{Enum.join(months, ",")}}M{3,7}K"

        for {way, answer} <- each_way("#{year}Y#{week}W", "P1W", text) do
          assert {year, week, text, way, spans(answer)} == {year, week, text, way, expected}
        end
      end
    end

    test "keeps the week of that number" do
      for year <- [2025, 2026],
          week <- weeks_of(year),
          {text, written} <- [{"25", [25]}, {"{1,-1}", [1, -1]}] do
        named = named_among(written, Enum.at(weeks_of(year), -1))
        expected = if week in named, do: [{monday(year, week), 7}], else: []

        for {way, answer} <- each_way("#{year}Y#{week}W", "P1W", "#{text}W") do
          assert {year, week, text, way, spans(answer)} == {year, week, text, way, expected}
        end
      end
    end
  end

  describe "a recurrence that starts at a week or a month" do
    test "selects in each week it steps to" do
      # Each 15th in the eight weeks from ISO week 25 of 2026.
      {:ok, set} = Tempo.to_interval(~o"R/2026Y25W/P1W/FL15DN", within: ~o"2026Y25W/2026Y33W")

      expected =
        for week <- 25..32, date <- days_of_week(2026, week), date.day == 15, do: {date, 1}

      assert spans({:ok, set}) == expected
      assert expected == [{~D[2026-06-15], 1}, {~D[2026-07-15], 1}]
    end

    test "is limited by a week or a month, and ends" do
      assert spans(Tempo.to_interval(~o"R2/2026Y25W/P1W/FL25WN")) ==
               [{monday(2026, 25), 7}, {monday(2027, 25), 7}]

      assert spans(Tempo.to_interval(~o"R2/2026Y25W/P1W/FL7MN")) ==
               [{~D[2026-07-06], 7}, {~D[2026-07-13], 7}]
    end

    test "selects a day of the year in each month it steps to" do
      assert spans(Tempo.to_interval(~o"R2/2026Y6M/P1M/FL166ON")) ==
               [{~D[2026-06-15], 1}, {~D[2027-06-15], 1}]
    end
  end

  describe "a week selected in a month" do
    test "is the week of the month, which the calendar numbers" do
      # A week under a month is a week of that month (decided 2026-10-07):
      # whole weeks from a Monday in the Gregorian calendar, the first the
      # one that holds the month's first day. June 2026 begins on a Monday
      # and has four, and no twenty-third.
      assert Date.day_of_week(~D[2026-06-01]) == 1

      assert spans(Tempo.select(~o"2026-06", ~o"L2WN")) == [{~D[2026-06-08], 7}]
      assert spans(Tempo.to_interval(read("2026Y6ML-1WN"))) == [{~D[2026-06-22], 7}]
      assert spans(Tempo.to_interval(read("2026Y6ML23WN"))) == []

      assert spans(Tempo.to_interval(read("R2/2026Y6M/P1M/FL2WN"))) ==
               [{~D[2026-06-08], 7}, {~D[2026-07-06], 7}]

      assert spans(Tempo.to_interval(read("R/../P1M/FL-1WN"), within: ~o"2026-06")) ==
               [{~D[2026-06-22], 7}]
    end

    test "beside a part that picks within the week is not built" do
      for answer <- [
            Tempo.select(~o"2026-06", ~o"L1W1KN"),
            Tempo.to_interval(read("2026Y6ML1W1KN")),
            Tempo.to_interval(read("R2/2026Y6M/P1M/FL1WT10HN"))
          ] do
        assert {:error, %ConversionError{reason: :not_built, target: :week_of_month}} = answer
      end
    end

    test "limits a rule whose candidates are days, as it did" do
      # A rule read from an RRULE states its start's day: the 15th of each
      # month, kept where it is in ISO week 25.
      rule = RRule.parse!("FREQ=MONTHLY;BYWEEKNO=25;COUNT=2", from: ~o"2026-01-15")
      assert spans(Tempo.to_interval(rule)) == [{~D[2026-06-15], 1}, {~D[2032-06-15], 1}]
    end
  end
end
