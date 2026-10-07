defmodule Tempo.RRule.LastDayTest do
  use ExUnit.Case, async: true

  # An ISO 8601 recurrence is its start and n cadences on, and keeps the last
  # day of a month that lacks its start's day: 31 January, 28 February, 31
  # March. A reader of RFC 5545 passes over such a month, so the rule
  # `Tempo.RRule.to_string/1` writes says the days outright: the last day of
  # the month, or the last of the days up to the start's.
  #
  # The measure is the dates. Those the recurrence lists are worked out with
  # `Date` alone, the start moved by `Date.shift/2` or its day put into each
  # month the rule names and kept to the month's length, and the rule written
  # is read again from the same start, as a reader of RFC 5545 would read it.

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  @starts [
    ~D[2026-01-15],
    ~D[2026-01-28],
    ~D[2026-01-29],
    ~D[2026-01-30],
    ~D[2026-01-31],
    ~D[2024-02-29],
    ~D[2026-03-31]
  ]

  defp dates(recurrence) do
    {:ok, set} = Tempo.to_interval(recurrence)

    for occurrence <- IntervalSet.members(set) do
      {:ok, date} = occurrence |> Interval.from() |> Tempo.to_date()
      date
    end
  end

  # The dates a reader of RFC 5545 lists for the rule written, from the
  # recurrence's own start.
  defp dates_as_written(%Interval{from: from} = recurrence) do
    {:ok, rule} = RRule.to_string(recurrence)
    dates(RRule.parse!(rule, from: from))
  end

  defp recurrence(text), do: Tempo.from_iso8601!(text)

  # Whether one BYMONTHDAY says a day in each of a year's months: the day
  # itself where every month has it, or the last day where it is at or past
  # the end of every month. 2024 has the longest February and 2025 the
  # shortest.
  defp one_rule?(day, months) do
    shortest = for month <- months, do: Date.days_in_month(Date.new!(2025, month, 1))
    longest = for month <- months, do: Date.days_in_month(Date.new!(2024, month, 1))

    match?([_], months) or Enum.all?(shortest, &(day <= &1)) or Enum.all?(longest, &(day >= &1))
  end

  # An answer that is the writer's error for a recurrence no one rule says.
  defp no_one_rule({:error, %ConversionError{target: :rrule}} = refused), do: refused
  defp no_one_rule(_written), do: :refused

  describe "a recurrence that steps by months and selects no day" do
    test "is written as a rule that lists the days it does" do
      for start <- @starts, months <- [1, 2, 3, 12] do
        every = recurrence("R12/#{start}/P#{months}M")
        expected = for step <- 0..11, do: Date.shift(start, month: step * months)

        assert {start, months, dates(every)} == {start, months, expected}
        assert {start, months, dates_as_written(every)} == {start, months, expected}
      end
    end

    test "is written so with the months its rule keeps to" do
      for start <- @starts, months <- [[2, 4], [4, 6], [1, 2]] do
        limited = recurrence("R8/#{start}/P1M/FL{#{Enum.join(months, ",")}}MN")

        expected =
          for step <- 0..60,
              date = Date.shift(start, month: step),
              date.month in months,
              do: date

        assert {start, months, dates_as_written(limited)} ==
                 {start, months, Enum.take(expected, 8)}
      end
    end

    test "says the last day of the month, or the last of the days up to its start's" do
      assert RRule.to_string(~o"R5/2026-01-31/P1M") == {:ok, "FREQ=MONTHLY;COUNT=5;BYMONTHDAY=-1"}

      assert RRule.to_string(~o"R4/2026-01-30/P1M") ==
               {:ok, "FREQ=MONTHLY;COUNT=4;BYMONTHDAY=28,29,30;BYSETPOS=-1"}

      assert RRule.to_string(~o"R4/2026-01-29/P2M") ==
               {:ok, "FREQ=MONTHLY;INTERVAL=2;COUNT=4;BYMONTHDAY=28,29;BYSETPOS=-1"}

      # The start's time of day is one time, which a position does not count.
      assert RRule.to_string(~o"R4/2026-01-30T09:30/P1M") ==
               {:ok, "FREQ=MONTHLY;COUNT=4;BYMONTHDAY=28,29,30;BYSETPOS=-1"}

      assert RRule.to_string(~o"R/2026-01-31/P1M/FLT{9,17}HN") ==
               {:ok, "FREQ=MONTHLY;BYMONTHDAY=-1;BYHOUR=9,17"}
    end

    test "is written as it was where every month it reaches has its start's day" do
      assert RRule.to_string(~o"R5/2026-01-28/P1M") == {:ok, "FREQ=MONTHLY;COUNT=5"}

      assert RRule.to_string(~o"R5/2026-01-30/P1M/FL{4,6}MN") ==
               {:ok, "FREQ=MONTHLY;COUNT=5;BYMONTH=4,6"}
    end
  end

  describe "a recurrence that steps by years and selects no day" do
    test "is written as a rule that lists the days it does" do
      for start <- @starts, years <- [1, 4] do
        every = recurrence("R8/#{start}/P#{years}Y")
        expected = for step <- 0..7, do: Date.shift(start, year: step * years)

        assert {start, years, dates(every)} == {start, years, expected}
        assert {start, years, dates_as_written(every)} == {start, years, expected}
      end
    end

    test "is written so with the months its rule names, where one rule says them" do
      for start <- @starts, months <- [[2], [2, 4], [4, 6], [1, 3], [1, 2]] do
        named = recurrence("R8/#{start}/P1Y/FL{#{Enum.join(months, ",")}}MN")

        expected =
          for year <- start.year..(start.year + 8),
              month <- months,
              day = min(start.day, Date.days_in_month(Date.new!(year, month, 1))),
              date = Date.new!(year, month, day),
              Date.compare(date, start) != :lt,
              do: date

        if one_rule?(start.day, months) do
          assert {start, months, dates_as_written(named)} ==
                   {start, months, Enum.take(expected, 8)}
        else
          assert {start, months, RRule.to_string(named)} ==
                   {start, months, no_one_rule(RRule.to_string(named))}
        end
      end
    end

    test "says the last day of its start's month from 29 February" do
      assert RRule.to_string(~o"R3/2024-02-29/P1Y") ==
               {:ok, "FREQ=YEARLY;COUNT=3;BYMONTH=2;BYMONTHDAY=-1"}

      assert RRule.to_string(~o"R/2026-01-31/P1Y/FL{2,4}MN") ==
               {:ok, "FREQ=YEARLY;BYMONTH=2,4;BYMONTHDAY=-1"}

      assert RRule.to_string(~o"R3/2026-03-31/P1Y") == {:ok, "FREQ=YEARLY;COUNT=3"}
    end
  end

  describe "a recurrence no one rule says" do
    test "holds a position, or several times of day, that the idiom's position would count" do
      for text <- ["R6/2026-01-30/P1M/FLT{9,17}HN", "R6/2026-01-30/P1M/FL1IN"] do
        assert {:error, %ConversionError{target: :rrule, reason: reason}} =
                 RRule.to_string(recurrence(text))

        assert reason =~ "BYSETPOS"
      end
    end

    test "names months of a year that are of different lengths about its start's day" do
      # The 30th of January and the end of February.
      assert {:error, %ConversionError{target: :rrule, reason: reason}} =
               RRule.to_string(~o"R6/2026-01-30/P1Y/FL{1,2}MN")

      assert reason =~ "months are of different lengths"
    end
  end

  describe "a recurrence written as it was" do
    test "names its day, steps by weeks or less, or has no start" do
      assert RRule.to_string(~o"R6/2026-01-31/P1M/FL15DN") ==
               {:ok, "FREQ=MONTHLY;COUNT=6;BYMONTHDAY=15"}

      assert RRule.to_string(~o"R6/2026-01-31/P1M/FL5KN") ==
               {:ok, "FREQ=MONTHLY;COUNT=6;BYDAY=FR"}

      assert RRule.to_string(~o"R6/2026-01-31/P1W") == {:ok, "FREQ=WEEKLY;COUNT=6"}
      assert RRule.to_string(~o"R6/2026-01-31/P1D") == {:ok, "FREQ=DAILY;COUNT=6"}
      assert RRule.to_string(~o"R/../P1M") == {:ok, "FREQ=MONTHLY"}
    end

    test "is a rule read from an RRULE, which states its day" do
      rule = RRule.parse!("FREQ=MONTHLY;COUNT=3", from: ~o"2026-01-31")
      assert RRule.to_string(rule) == {:ok, "FREQ=MONTHLY;COUNT=3;BYMONTHDAY=31"}
    end
  end
end
