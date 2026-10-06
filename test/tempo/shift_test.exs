defmodule Tempo.ShiftTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Math

  describe "Tempo.shift/2" do
    test "mixed units apply largest-to-smallest" do
      assert Tempo.shift(~o"2026-06-15", month: 1, day: -5) == ~o"2026Y7M10D"
    end

    test "negative values move the Tempo backwards" do
      assert Tempo.shift(~o"2026-06-15", day: -10) == ~o"2026Y6M5D"
    end

    test "rolls a year boundary backwards" do
      assert Tempo.shift(~o"2026-01-05", day: -10) == ~o"2025Y12M26D"
    end

    test "clamps the day-of-month after month arithmetic" do
      # Jan 31 + 1 month in a non-leap year is Feb 28, not Feb 31.
      assert Tempo.shift(~o"2026-01-31", month: 1) == ~o"2026Y2M28D"
      # Leap year gives Feb 29.
      assert Tempo.shift(~o"2024-01-31", month: 1) == ~o"2024Y2M29D"
    end

    test "time-of-day shifts work" do
      assert Tempo.shift(~o"2026-06-15T10:00:00", hour: -3) ==
               ~o"2026Y6M15DT7H0M0S"

      assert Tempo.shift(~o"2026-06-15T10:00:00", minute: 45, second: 30) ==
               ~o"2026Y6M15DT10H45M30S"
    end

    test "week is normalised to days" do
      assert Tempo.shift(~o"2026-06-15", week: 2) == ~o"2026Y6M29D"
    end

    test "empty keyword list is a no-op" do
      assert Tempo.shift(~o"2026-06-15", []) == ~o"2026Y6M15D"
    end
  end

  describe "Tempo.shift/2 by a count of any size" do
    test "of months or years is what the calendar says in one step" do
      # The measure is `Date.shift/2`. A month and a year were stepped one
      # at a time, so a hundred thousand months took thirty milliseconds
      # where one takes ten microseconds, and a recurrence that steps to
      # its nth candidate by one shift took the square of its count.
      for date <- [~D[2026-01-31], ~D[2024-02-29], ~D[2026-06-15], ~D[0001-01-01]],
          {unit, counts} <- [
            month: [1, 11, 12, 13, 1_000, 100_000, -1, -13, -24_000],
            year: [1, 4, 100, 10_000, -1, -400, -2_000]
          ],
          count <- counts do
        {:ok, shifted} =
          date
          |> Tempo.from_date()
          |> Tempo.shift(%Tempo.Duration{time: [{unit, count}]})
          |> Tempo.to_date()

        assert {date, unit, count, shifted} ==
                 {date, unit, count, Date.shift(date, [{unit, count}])}
      end
    end

    test "of hours, minutes or seconds from a time of day with no date is the clock's" do
      # The measure is `Time.add/3`, which comes round at midnight as a time
      # of day with no date does. An hour at a time took as many steps as
      # the count: 22 ms for a hundred thousand hours.
      for {time, start} <- [
            {~o"T22H", ~T[22:00:00]},
            {~o"T22H30M", ~T[22:30:00]},
            {~o"T23H59M59S", ~T[23:59:59]}
          ],
          {unit, counts} <- [
            hour: [1, 2, 25, 100_000, -1, -49],
            minute: [1, 61, 1_440, 100_000, -31],
            second: [1, 86_400, 86_401, -1]
          ],
          count <- counts do
        shifted =
          time
          |> Tempo.shift(%Tempo.Duration{time: [{unit, count}]})
          |> Tempo.extend_resolution(:second)
          |> Tempo.to_time()

        assert {time, unit, count, shifted} ==
                 {time, unit, count, {:ok, Time.add(start, count, unit)}}
      end
    end

    test "of weeks, days or hours in a calendar of weeks is the calendar's" do
      # The measure is `Date` and `NaiveDateTime` in `Calendrical.ISOWeek`,
      # whose dates are a year, a week and a day of the week.
      for {week, day} <- [{1, 1}, {25, 3}, {53, 7}], count <- [1, 7, 53, 1_000, -1, -400] do
        date = Date.new!(2026, week, day, Calendrical.ISOWeek)
        value = Tempo.from_date(date)

        assert {week, day, count, Tempo.to_date(Tempo.shift(value, ~o"P1W" |> times(count)))} ==
                 {week, day, count, {:ok, Date.shift(date, week: count)}}

        assert {week, day, count, Tempo.to_date(Tempo.shift(value, ~o"P1D" |> times(count)))} ==
                 {week, day, count, {:ok, Date.add(date, count)}}
      end

      at_ten = Tempo.from_iso8601!("2026-W25-3T10", Calendrical.ISOWeek)
      naive = NaiveDateTime.new!(2026, 25, 3, 10, 0, 0, {0, 0}, Calendrical.ISOWeek)

      for count <- [1, 14, 15, 60_000, -11, -60_000] do
        expected = NaiveDateTime.add(naive, count, :hour)
        shifted = Tempo.shift(at_ten, %Tempo.Duration{time: [hour: count]})

        assert {count, Tempo.to_iso8601!(shifted)} ==
                 {count,
                  "#{expected.year}Y#{expected.month}W#{expected.day}KT#{expected.hour}H[u-ca=iso-week]"}
      end
    end

    test "of weeks from a week of a Gregorian year is ISO 8601's week that many on" do
      # The measure is `:calendar.iso_week_number/1` of the Monday that many
      # weeks on from the week's own, which is 4 January's week for week 1.
      for {year, week} <- [{2026, 1}, {2026, 25}, {2026, 53}, {2020, 53}],
          count <- [1, 52, 53, 1_000, -1, -53, -1_000] do
        fourth = Date.new!(year, 1, 4)
        monday = Date.add(fourth, 1 - Date.day_of_week(fourth) + 7 * (week - 1))
        {on_year, on_week} = :calendar.iso_week_number(Date.to_erl(Date.add(monday, 7 * count)))

        shifted =
          "#{year}Y#{week}W"
          |> Tempo.from_iso8601!()
          |> Tempo.shift(%Tempo.Duration{time: [week: count]})

        assert {year, week, count, Tempo.to_iso8601!(shifted)} ==
                 {year, week, count, "#{on_year}Y#{on_week}W"}
      end
    end

    test "of months is the months counted on where a value names no day" do
      assert Tempo.shift(~o"2026-06", ~o"P100000M") == ~o"10359Y10M"
      assert Tempo.shift(~o"2026-06", ~o"P-24000M") == ~o"26Y6M"
      assert Tempo.shift(~o"2026", ~o"P10000Y") == ~o"12026Y"
    end
  end

  defp times(%Tempo.Duration{time: [{unit, 1}]}, count),
    do: %Tempo.Duration{time: [{unit, count}]}

  describe "Tempo.shift/2 with a duration value" do
    test "accepts a Tempo.Duration directly" do
      assert Tempo.shift(~o"2026", ~o"P2Y") == ~o"2028Y"
      assert Tempo.shift(~o"2026-06-15", ~o"P1M") == ~o"2026Y7M15D"
    end

    test "agrees with the keyword-list form and with Tempo.Math.add/2" do
      assert Tempo.shift(~o"2026-06-15", ~o"P1M") == Tempo.shift(~o"2026-06-15", month: 1)
      assert Tempo.shift(~o"2026-06-15", ~o"P1M") == Math.add(~o"2026-06-15", ~o"P1M")
    end

    test "month-end clamping applies the same as the keyword form" do
      assert Tempo.shift(~o"2026-01-31", ~o"P1M") == ~o"2026Y2M28D"
    end
  end

  describe "Tempo.shift/2 on unanchored values (no :year)" do
    # A value with no year lives on a repeating month/day axis. Cases
    # the calendar can resolve without a year are computed; cases that
    # depend on the missing year return {:error, %UnanchoredError{}}
    # — never a raise.

    test "day arithmetic that stays within a month is computed" do
      assert Tempo.shift(~o"2M15D", ~o"P1D") == ~o"2M16D"
      assert Tempo.shift(~o"2M15D", day: -1) == ~o"2M14D"
    end

    test "a month-crossing carry into a fixed-length month is computed" do
      assert Tempo.shift(~o"1M31D", ~o"P1D") == ~o"2M1D"
      assert Tempo.shift(~o"2M1D", day: -1) == ~o"1M31D"
    end

    test "a year-boundary carry wraps the month (the year is immaterial)" do
      assert Tempo.shift(~o"12M31D", ~o"P1D") == ~o"1M1D"
      assert Tempo.shift(~o"1M1D", day: -1) == ~o"12M31D"
    end

    test "arithmetic that depends on the missing year returns an error, not a raise" do
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.shift(~o"1M31D", ~o"P1M")
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.shift(~o"2M28D", ~o"P1D")
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.shift(~o"3M1D", day: -1)
    end

    test "a whole-year step is a no-op — the untracked year moves, the date does not" do
      assert Tempo.shift(~o"1M31D", ~o"P1Y") == ~o"1M31D"
      assert Tempo.shift(~o"6M15D", year: -1) == ~o"6M15D"
    end

    test "a year step on Feb 29 needs an anchor — next year may not be a leap year" do
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.shift(~o"2M29D", ~o"P1Y")
    end

    test "a month step that keeps a valid day is computed, and wraps the year" do
      assert Tempo.shift(~o"1M15D", ~o"P1M") == ~o"2M15D"
      assert Tempo.shift(~o"3M31D", ~o"P1M") == ~o"4M30D"
      assert Tempo.shift(~o"12M31D", ~o"P1M") == ~o"1M31D"
      assert Tempo.shift(~o"1M15D", month: -1) == ~o"12M15D"
    end

    test "a time step never spuriously requires an anchor for an ambiguous day" do
      # `2M29D` sits on an ambiguous day, but a time shift doesn't touch it.
      assert Tempo.shift(~o"2M29D", ~o"PT1H") == ~o"2M29DT1H"
    end

    test "a fractional week counts whole days, truncated" do
      assert Tempo.shift(~o"2026-01-01", ~o"P1.5W") == ~o"2026-01-11"
    end

    test "a fractional amount is whole units of the next smaller unit, truncated" do
      assert Tempo.shift(~o"2026-01-01", ~o"P1.3D") == ~o"2026-01-02T07"
      assert Tempo.shift(~o"2026-01-01T10", ~o"PT1.5H") == ~o"2026-01-01T11:30"
      assert Tempo.shift(~o"2026-01-01T10:00", ~o"PT1.7M") == ~o"2026-01-01T10:01:42"
      assert Tempo.shift(~o"2026-03-10", ~o"P1.5Y") == ~o"2027-09-10"
      assert Tempo.shift(~o"2026-01-01", ~o"-P1.5D") == ~o"2025-12-30T12"
    end

    test "a fractional month is its fraction of the days to one month later" do
      # ISO 8601-2 D.4.4: half of the 31 days from 23 January, truncated.
      assert Tempo.shift(~o"2018-01-23", ~o"P0.5M") == ~o"2018-02-07"
      assert Tempo.shift(~o"2018-01-31", ~o"P0.5M") == ~o"2018-02-14"
      assert Tempo.shift(~o"2018-01-23", ~o"P1.5M") == ~o"2018-03-10"
    end

    test "a fractional month needs a year to measure the month in" do
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.shift(~o"3M", ~o"P0.5M")
    end

    test "a month-only value carries a month/year step and extends for finer steps" do
      assert Tempo.shift(~o"3M", ~o"P1M") == ~o"4M"
      assert Tempo.shift(~o"3M", ~o"P1Y") == ~o"3M"
      assert Tempo.shift(~o"3M", ~o"P1D") == ~o"3M2D"
      assert Tempo.shift(~o"3M", ~o"P1W") == ~o"3M8D"
    end

    test "a day-only value advances while every month has that day, else errors" do
      assert Tempo.shift(~o"15D", ~o"P1D") == ~o"16D"
      assert Tempo.shift(~o"15D", ~o"P1W") == ~o"22D"
      assert Tempo.shift(~o"27D", ~o"P1D") == ~o"28D"
      assert Tempo.shift(~o"15D", day: -1) == ~o"14D"
      # A month/year step leaves a bare day untouched.
      assert Tempo.shift(~o"15D", ~o"P1M") == ~o"15D"
      # The 29th isn't in every month, and the 1st's predecessor is unknown.
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.shift(~o"28D", ~o"P1D")
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.shift(~o"1D", day: -1)
    end
  end
end
