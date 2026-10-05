defmodule Tempo.RRule.StartPartsTest do
  use ExUnit.Case, async: true

  # A rule of RFC 5545 takes from its start what it does not say: a weekly
  # rule its weekday, a monthly rule its day of the month, a yearly rule its
  # month and its day (ISO 8601-2 Annex C.3). Read from an RRULE with a start,
  # the rule states each (Annex C.4), and a day that a month or a year lacks
  # is then passed over, as RFC 5545 §3.3.10 passes over an instance with an
  # invalid date: a monthly rule from 31 January lists the months of 31 days.
  #
  # The measure is taken apart from the reader and the resolver. The dates a
  # rule lists are worked out with `Date` alone: the start moved by whole
  # weeks, or the start's day put into each month or year the rule reaches,
  # where `Date.new/3` says the date exists.

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.RRule.Rule

  doctest Rule

  # Ten years, with three leap years.
  @window ~o"2024Y/2034Y"
  @first ~D[2024-01-01]
  @last ~D[2033-12-31]

  # A day every month has, and each day some month lacks.
  @starts [
    ~D[2026-01-15],
    ~D[2026-01-28],
    ~D[2026-01-29],
    ~D[2026-01-30],
    ~D[2026-01-31],
    ~D[2024-02-29],
    ~D[2026-03-31]
  ]

  defp read(rrule, %Date{} = start), do: RRule.parse!(rrule, from: Tempo.from_date(start))

  # The day each occurrence starts on and how many days long it is.
  defp occurrences(rule) do
    {:ok, set} = Tempo.to_interval(rule, within: @window)

    for occurrence <- IntervalSet.members(set) do
      {:ok, date} = occurrence |> Interval.from() |> Tempo.to_date()
      {:ok, next} = occurrence |> Interval.to() |> Tempo.to_date()
      {date, Date.diff(next, date)}
    end
  end

  defp starts(rule) do
    {:ok, set} = Tempo.to_interval(rule, within: @window)
    for occurrence <- IntervalSet.members(set), do: Interval.from(occurrence)
  end

  defp in_window(dates, start) do
    Enum.filter(dates, fn date ->
      Date.compare(date, start) != :lt and Date.compare(date, @first) != :lt and
        Date.compare(date, @last) != :gt
    end)
  end

  # Each `interval`-th month from the start's, as `{year, month}`.
  defp months_from(%Date{year: year, month: month}, interval) do
    for step <- 0..120//interval do
      index = year * 12 + month - 1 + step
      {div(index, 12), rem(index, 12) + 1}
    end
  end

  # The dates that exist among `{year, month}` pairs with one day of the month.
  defp existing(year_months, day) do
    for {year, month} <- year_months, {:ok, date} <- [Date.new(year, month, day)], do: date
  end

  defp day_long(dates), do: Enum.map(dates, &{&1, 1})

  describe "a weekly rule read from an RRULE" do
    test "lists its start's weekday in each week it reaches" do
      for start <- @starts, interval <- [1, 2, 3] do
        expected = for step <- 0..530//interval, do: Date.add(start, 7 * step)
        rule = read("FREQ=WEEKLY;INTERVAL=#{interval}", start)

        assert {start, interval, occurrences(rule)} ==
                 {start, interval, expected |> in_window(start) |> day_long()}
      end
    end

    test "states the weekday" do
      assert read("FREQ=WEEKLY;COUNT=2", ~D[2026-06-16]) == ~o"R2/2026-06-16/P1W/FL2KN"
      assert RRule.to_string(read("FREQ=WEEKLY", ~D[2026-06-16])) == {:ok, "FREQ=WEEKLY;BYDAY=TU"}

      # A rule that names its weekdays takes none from its start.
      assert read("FREQ=WEEKLY;BYDAY=MO,FR", ~D[2026-06-16]) == ~o"R/2026-06-16/P1W/FL{1,5}KN"
    end
  end

  describe "a monthly rule read from an RRULE" do
    test "lists its start's day in each month it reaches that has the day" do
      for start <- @starts, interval <- [1, 2, 3, 5] do
        expected = start |> months_from(interval) |> existing(start.day)
        rule = read("FREQ=MONTHLY;INTERVAL=#{interval}", start)

        assert {start, interval, occurrences(rule)} ==
                 {start, interval, expected |> in_window(start) |> day_long()}
      end
    end

    test "lists it in the months the rule keeps to" do
      for start <- @starts do
        expected =
          start
          |> months_from(1)
          |> Enum.filter(fn {_year, month} -> month in [2, 4, 5] end)
          |> existing(start.day)

        rule = read("FREQ=MONTHLY;BYMONTH=2,4,5", start)
        assert {start, occurrences(rule)} == {start, expected |> in_window(start) |> day_long()}
      end
    end

    test "lists it at each time of day the rule names" do
      rule = read("FREQ=MONTHLY;BYHOUR=9,17;COUNT=4", ~D[2026-01-31])

      assert starts(rule) ==
               [~o"2026-01-31T09", ~o"2026-01-31T17", ~o"2026-03-31T09", ~o"2026-03-31T17"]
    end

    test "states the day of the month" do
      assert read("FREQ=MONTHLY;COUNT=3", ~D[2026-01-31]) == ~o"R3/2026-01-31/P1M/FL31DN"

      assert RRule.to_string(read("FREQ=MONTHLY", ~D[2026-01-31])) ==
               {:ok, "FREQ=MONTHLY;BYMONTHDAY=31"}

      # A rule that names its day, or its weekday, takes none from its start.
      assert read("FREQ=MONTHLY;BYMONTHDAY=13", ~D[2026-01-31]) == ~o"R/2026-01-31/P1M/FL13DN"
      assert read("FREQ=MONTHLY;BYDAY=FR", ~D[2026-01-31]) == ~o"R/2026-01-31/P1M/FL5KN"
    end
  end

  describe "a yearly rule read from an RRULE" do
    test "lists its start's month and day in each year it reaches that has them" do
      for start <- @starts, interval <- [1, 2, 4] do
        years = for step <- 0..12//interval, do: {start.year + step, start.month}
        rule = read("FREQ=YEARLY;INTERVAL=#{interval}", start)

        assert {start, interval, occurrences(rule)} ==
                 {start, interval, years |> existing(start.day) |> in_window(start) |> day_long()}
      end
    end

    test "lists its start's day in each month the rule names that has the day" do
      for start <- @starts, months <- [[2], [4, 8], [1, 3]] do
        year_months = for year <- start.year..2033, month <- months, do: {year, month}
        rule = read("FREQ=YEARLY;BYMONTH=#{Enum.join(months, ",")}", start)

        assert {start, months, occurrences(rule)} ==
                 {start, months,
                  year_months |> existing(start.day) |> in_window(start) |> day_long()}
      end
    end

    test "lists a day the rule names in its start's month" do
      for start <- @starts, day <- [15, 31] do
        years = for year <- start.year..2033, do: {year, start.month}
        rule = read("FREQ=YEARLY;BYMONTHDAY=#{day}", start)

        assert {start, day, occurrences(rule)} ==
                 {start, day, years |> existing(day) |> in_window(start) |> day_long()}
      end
    end

    test "lists a weekday the rule names in every month, and with a day in its start's" do
      start = ~D[2026-03-10]
      days = Date.range(start, @last)

      tuesdays = Enum.filter(days, &(Date.day_of_week(&1) == 2))
      assert occurrences(read("FREQ=YEARLY;BYDAY=TU", start)) == day_long(tuesdays)

      # Friday the 13th, of March: the month is the start's where the rule
      # names a day of the month.
      fridays_the_13th =
        Enum.filter(days, &(&1.month == 3 and &1.day == 13 and Date.day_of_week(&1) == 5))

      assert occurrences(read("FREQ=YEARLY;BYDAY=FR;BYMONTHDAY=13", start)) ==
               day_long(fridays_the_13th)
    end

    test "states the month and the day" do
      assert read("FREQ=YEARLY;COUNT=5", ~D[2026-03-10]) == ~o"R5/2026-03-10/P1Y/FL3M10DN"

      assert RRule.to_string(read("FREQ=YEARLY", ~D[2026-03-10])) ==
               {:ok, "FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=10"}

      assert read("FREQ=YEARLY;BYMONTH=4,8", ~D[2026-03-10]) == ~o"R/2026-03-10/P1Y/FL{4,8}M10DN"
      assert read("FREQ=YEARLY;BYMONTHDAY=15", ~D[2026-03-10]) == ~o"R/2026-03-10/P1Y/FL3M15DN"

      # A weekday alone is every such day of the year, a day of the year
      # names its own month, and a week of the year takes the start's weekday.
      assert read("FREQ=YEARLY;BYDAY=TU", ~D[2026-03-10]) == ~o"R/2026-03-10/P1Y/FL2KN"
      assert read("FREQ=YEARLY;BYYEARDAY=100", ~D[2026-03-10]) == ~o"R/2026-03-10/P1Y/FL100ON"
      assert read("FREQ=YEARLY;BYWEEKNO=20", ~D[1997-05-12]) == ~o"R/1997-05-12/P1Y/FL20W1KN"
    end
  end

  describe "a rule that takes nothing from its start" do
    test "is one that steps by days or less" do
      assert read("FREQ=DAILY;COUNT=2", ~D[2026-01-31]) == ~o"R2/2026-01-31/P1D"
      assert RRule.parse!("FREQ=HOURLY", from: ~o"2026-01-31T09") == ~o"R/2026-01-31T09/PT1H"
    end

    test "is one read with no start, or with a start that is no one date" do
      assert RRule.parse!("FREQ=MONTHLY") == ~o"R/../P1M"
      assert RRule.parse!("FREQ=MONTHLY", from: ~o"2026-01") == ~o"R/2026-01/P1M"
    end
  end

  describe "an ISO 8601 recurrence" do
    test "is its start and n cadences on, on the last day of a period that lacks the day" do
      # 31 January, 28 February, 31 March, 30 April and 31 May, as `Date.shift/2`
      # moves a date by months.
      monthly = for step <- 0..4, do: Date.shift(~D[2026-01-31], month: step)
      assert starts(~o"R5/2026-01-31/P1M") == Enum.map(monthly, &Tempo.from_date/1)

      assert starts(~o"R5/2024-02-29/P1Y") ==
               [~o"2024-02-29", ~o"2025-02-28", ~o"2026-02-28", ~o"2027-02-28", ~o"2028-02-29"]
    end
  end

  describe "a rule read with a start of another calendar" do
    test "lists its start's day in the months and years that have it" do
      # Heshvan, the second month, has thirty days in some Hebrew years.
      hebrew = fn text -> Tempo.from_iso8601!(text, Hebrew) end
      within = [within: hebrew.("5786Y/5796Y")]

      thirtieths =
        for year <- 5786..5795, {:ok, date} <- [Date.new(year, 2, 30, Hebrew)], do: date

      rule = RRule.parse!("FREQ=YEARLY;BYMONTH=2", from: hebrew.("5786-01-30"))
      {:ok, set} = Tempo.to_interval(rule, within)

      assert Enum.map(IntervalSet.members(set), &Tempo.to_date(Interval.from(&1))) ==
               Enum.map(thirtieths, &{:ok, &1})
    end

    test "keeps its start's month as the calendar steps its years" do
      # 18 Nisan: the seventh month of 5786 and the eighth of 5787, which
      # has a leap month before it.
      rule = RRule.parse!("FREQ=YEARLY;COUNT=3", from: Tempo.from_iso8601!("5786-07-18", Hebrew))
      {:ok, set} = Tempo.to_interval(rule)

      nisan_18 = [~D[2026-04-05], ~D[2027-04-25], ~D[2028-04-14]]

      assert Enum.map(IntervalSet.members(set), fn occurrence ->
               {:ok, date} = Tempo.to_date(Interval.from(occurrence))
               Date.convert!(date, Calendar.ISO)
             end) == nisan_18
    end
  end
end
