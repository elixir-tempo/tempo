defmodule Tempo.Interval.StepsTest do
  @moduledoc """
  Closed-form step arithmetic used by `Enumerable.Tempo.Interval`
  for `count/1`, `slice/1`, and `member?/2`.
  """

  use ExUnit.Case, async: true

  # Doctests evaluate the expected output as code; `~o"…"` requires
  # `sigil_o` to be in scope.
  import Tempo.Sigils

  doctest Tempo.Interval.Steps

  alias Tempo.Interval.Steps

  describe "count_steps/4" do
    test "year step count is the year difference" do
      from = Tempo.from_iso8601!("2026Y")
      to = Tempo.from_iso8601!("2030Y")
      assert Steps.count_steps(from, to, :year, Calendrical.Gregorian) == 4
    end

    test "month step count crosses year boundaries" do
      from = Tempo.from_iso8601!("2026-10")
      to = Tempo.from_iso8601!("2027-03")
      assert Steps.count_steps(from, to, :month, Calendrical.Gregorian) == 5
    end

    test "day step count handles leap years correctly" do
      # 2024 is a leap year (Feb has 29 days).
      from = Tempo.from_iso8601!("2024-02-01")
      to = Tempo.from_iso8601!("2024-03-01")
      assert Steps.count_steps(from, to, :day, Calendrical.Gregorian) == 29

      # 2026 is not a leap year.
      from = Tempo.from_iso8601!("2026-02-01")
      to = Tempo.from_iso8601!("2026-03-01")
      assert Steps.count_steps(from, to, :day, Calendrical.Gregorian) == 28
    end

    test "day count across multiple years matches a calendar walk" do
      from = Tempo.from_iso8601!("2020-01-01")
      to = Tempo.from_iso8601!("2026-01-01")
      # 6 years including one leap day each on 2020, 2024 = 2 leap days
      # 6 * 365 + 2 = 2192
      assert Steps.count_steps(from, to, :day, Calendrical.Gregorian) == 2192
    end

    test "hour count" do
      from = Tempo.from_iso8601!("2026-06-15T10")
      to = Tempo.from_iso8601!("2026-06-16T10")
      assert Steps.count_steps(from, to, :hour, Calendrical.Gregorian) == 24
    end

    test "minute count" do
      from = Tempo.from_iso8601!("2026-06-15T10:00")
      to = Tempo.from_iso8601!("2026-06-15T11:00")
      assert Steps.count_steps(from, to, :minute, Calendrical.Gregorian) == 60
    end

    test "second count" do
      from = Tempo.from_iso8601!("2026-06-15T10:00:00")
      to = Tempo.from_iso8601!("2026-06-15T11:00:00")
      assert Steps.count_steps(from, to, :second, Calendrical.Gregorian) == 3600
    end

    test "microsecond count uses the precision-aware ulp" do
      # precision 3 (millisecond) — step is 1000 µs.
      from = Tempo.from_iso8601!("2026-06-15T10:00:00.000")
      to = Tempo.from_iso8601!("2026-06-15T10:00:00.010")
      assert Steps.count_steps(from, to, :microsecond, Calendrical.Gregorian) == 10

      # precision 6 (microsecond) — step is 1 µs.
      from = Tempo.from_iso8601!("2026-06-15T10:00:00.000000")
      to = Tempo.from_iso8601!("2026-06-15T10:00:00.000010")
      assert Steps.count_steps(from, to, :microsecond, Calendrical.Gregorian) == 10
    end
  end

  describe "months_apart/3" do
    # The measure is the calendar's own count of each year's months. The
    # count was twelve a year wherever the two end years had twelve, so a
    # Hebrew year of thirteen between them was a month short.
    defp months_counted(from_year, to_year, calendar),
      do: from_year..(to_year - 1)//1 |> Enum.map(&calendar.months_in_year/1) |> Enum.sum()

    test "counts a year of thirteen months between two years of twelve" do
      hebrew = Calendrical.Hebrew
      assert Enum.map(5785..5788, &hebrew.months_in_year/1) == [12, 12, 13, 12]

      from = Tempo.from_iso8601!("5785-01", hebrew)
      to = Tempo.from_iso8601!("5788-01", hebrew)

      assert Steps.months_apart(from, to, hebrew) == months_counted(5785, 5788, hebrew)
      assert Steps.months_apart(from, to, hebrew) == 37
    end

    test "counts back from a later year, where it raised for a calendar of differing years" do
      hebrew = Calendrical.Hebrew
      early = Tempo.from_iso8601!("5785-01", hebrew)
      late = Tempo.from_iso8601!("5788-01", hebrew)

      assert Steps.count_steps(late, early, :month, hebrew) ==
               -months_counted(5785, 5788, hebrew)

      # A value of another calendar is on no step of a year's walk.
      refute Enum.member?(Tempo.from_iso8601!("5786Y[u-ca=hebrew]"), ~o"2026-06-15")
    end

    test "counts by the months the calendar says every year has" do
      for {calendar, from_year, to_year} <- [
            {Calendrical.Gregorian, 2020, 2031},
            {Calendrical.Ethiopic, 2010, 2021},
            {Calendrical.Hebrew, 5770, 5800},
            {Calendrical.Persian, 1400, 1410}
          ],
          {from_month, to_month} <- [{1, 1}, {3, 11}, {11, 3}] do
        from = Tempo.new!(year: from_year, month: from_month, calendar: calendar)
        to = Tempo.new!(year: to_year, month: to_month, calendar: calendar)

        assert {calendar, from_month, to_month, Steps.months_apart(from, to, calendar)} ==
                 {calendar, from_month, to_month,
                  months_counted(from_year, to_year, calendar) + to_month - from_month}
      end
    end
  end

  describe "nth_step/4" do
    test "nth year is the year plus n" do
      from = Tempo.from_iso8601!("2026Y")
      assert Steps.nth_step(from, 4, :year, Calendrical.Gregorian).time[:year] == 2030
    end

    test "nth month rolls into the next year" do
      from = Tempo.from_iso8601!("2026-10")
      t = Steps.nth_step(from, 5, :month, Calendrical.Gregorian)
      assert t.time[:year] == 2027
      assert t.time[:month] == 3
    end

    test "nth day crosses leap February" do
      from = Tempo.from_iso8601!("2024-02-28")
      t = Steps.nth_step(from, 2, :day, Calendrical.Gregorian)
      # 2024 is a leap year: 28 → 29 → Mar 1.
      assert t.time[:month] == 3 and t.time[:day] == 1
    end
  end

  describe "on_step?/4" do
    test "an element exactly on a day step is recognised" do
      from = Tempo.from_iso8601!("2026-01-01")
      element = Tempo.from_iso8601!("2026-01-31")
      assert Steps.on_step?(element, from, :day, Calendrical.Gregorian)
    end

    test "a finer-resolution element is not on a step" do
      from = Tempo.from_iso8601!("2026-01-01")
      element = Tempo.from_iso8601!("2026-01-15T10:00:00")
      refute Steps.on_step?(element, from, :day, Calendrical.Gregorian)
    end
  end

  describe "DST-aware sub-day counts (zoned, same named zone, Gregorian)" do
    test "spring-forward day at hour resolution skips the non-existent hour" do
      iv =
        Tempo.from_iso8601!("2025-03-09T00[America/New_York]/2025-03-09T06[America/New_York]")

      # NY spring-forward: 02:00 → 03:00. Wall-clock 6h, elapsed 5h.
      assert Enum.count(iv) == 5
    end

    test "fall-back day at hour resolution emits the doubled hour" do
      iv =
        Tempo.from_iso8601!("2025-11-02T00[America/New_York]/2025-11-02T06[America/New_York]")

      # NY fall-back: 02:00 → 01:00. Wall-clock 6h, elapsed 7h.
      assert Enum.count(iv) == 7
    end

    test "UTC values on a NY-DST day are unaffected" do
      iv = Tempo.from_iso8601!("2025-03-09T00Z/2025-03-09T06Z")
      assert Enum.count(iv) == 6
    end

    test "slice across spring-forward yields the elapsed-time elements" do
      iv =
        Tempo.from_iso8601!("2025-03-09T00[America/New_York]/2025-03-09T06[America/New_York]")

      hours =
        iv
        |> Enum.slice(0, 5)
        |> Enum.map(&Tempo.hour/1)

      # 00, 01, 03, 04, 05 — 02 is the gap.
      assert hours == [0, 1, 3, 4, 5]
    end
  end

  describe "Enumerable.Tempo.Interval integration" do
    test "Enum.count on a day interval is O(1) (returns the day count)" do
      iv = Tempo.from_iso8601!("2026-01-01/2026-02-01")
      assert Enum.count(iv) == 31
    end

    test "Enum.count on a month interval crosses years" do
      iv = Tempo.from_iso8601!("2026-10/2027-03")
      assert Enum.count(iv) == 5
    end

    test "Enum.slice returns a window without walking from the start" do
      iv = Tempo.from_iso8601!("2026-01-01/2026-02-01")

      assert Enum.map(Enum.slice(iv, 10, 3), &Tempo.to_iso8601!/1) == [
               "2026Y1M11D",
               "2026Y1M12D",
               "2026Y1M13D"
             ]
    end

    test "membership test is true for an element on a step within bounds" do
      iv = Tempo.from_iso8601!("2026-01-01/2026-02-01")
      assert Enum.member?(iv, Tempo.from_iso8601!("2026-01-15"))
    end

    test "membership test is false for an element outside the interval" do
      iv = Tempo.from_iso8601!("2026-01-01/2026-02-01")
      refute Enum.member?(iv, Tempo.from_iso8601!("2027-01-01"))
    end
  end
end
