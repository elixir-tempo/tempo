defmodule Tempo.Math.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Math

  # `Tempo.Math`'s examples were not executed by anything, so the
  # `add_unit/3` and `subtract_unit/3` examples went on documenting a
  # bare return long after the functions began threading `{:ok, _}`.
  doctest Tempo.Math, import: true

  describe "large day-count arithmetic (absolute-day fast path)" do
    defp add_days(tempo, n), do: Math.add(tempo, %Tempo.Duration{time: [day: n]})

    test "a large day count matches stepped arithmetic and is fast" do
      # Fast path (Date.add) must equal single-day stepping across
      # month/year rollover, leap years, and a negative count.
      assert add_days(~o"2020-01-01", 10_000) == ~o"2047Y5M19D"
      assert add_days(~o"2020-01-31", 1) == ~o"2020Y2M1D"
      assert add_days(~o"2020-12-31", 1) == ~o"2021Y1M1D"
      assert add_days(~o"2020-03-01", -1) == ~o"2020Y2M29D"

      {us, _} = :timer.tc(fn -> add_days(~o"2020-01-01", 1_000_000) end)
      assert us < 100_000, "adding a million days should be O(1), took #{us}µs"
    end

    test "day arithmetic on a value with a time component keeps the time" do
      assert add_days(~o"2020-01-01T10:30:00", 40) == ~o"2020Y2M10DT10H30M0S"
    end
  end

  # Tests for `Tempo.Math.add/2`, `subtract/2`, and the low-level
  # `subtract_unit/3` mirror of `add_unit/3`. Covers clamping,
  # carry/borrow, leap years, negative durations, and the
  # extend-to-needed-resolution behaviour.

  describe "add/2 — single components" do
    test "adds years" do
      assert Math.add(~o"2022Y", ~o"P3Y") == ~o"2025Y"
    end

    test "adds months with year carry" do
      assert Math.add(~o"2022Y11M", ~o"P3M") == ~o"2023Y2M"
    end

    test "adds days with month carry" do
      assert Math.add(~o"2022Y1M31D", ~o"P1D") == ~o"2022Y2M1D"
    end

    test "adds days across year boundary" do
      assert Math.add(~o"2022Y12M31D", ~o"P1D") == ~o"2023Y1M1D"
    end

    test "adds weeks as 7 days" do
      # `P2W` = 14 days.
      assert Math.add(~o"2022Y1M1DT0H", ~o"P2W") == ~o"2022Y1M15DT0H"
    end

    test "adds hours with day carry" do
      assert Math.add(~o"2022Y1M1DT23H", ~o"PT2H") == ~o"2022Y1M2DT1H"
    end

    test "adds seconds with minute carry" do
      assert Math.add(~o"2022Y1M1DT10H30M", ~o"PT100S") == ~o"2022Y1M1DT10H31M40S"
    end
  end

  describe "add/2 — day clamping after month arithmetic" do
    test "Jan 31 + P1M clamps to Feb 28 in a non-leap year" do
      assert Math.add(~o"2022Y1M31D", ~o"P1M") == ~o"2022Y2M28D"
    end

    test "Jan 31 + P1M clamps to Feb 29 in a leap year" do
      assert Math.add(~o"2024Y1M31D", ~o"P1M") == ~o"2024Y2M29D"
    end

    test "Feb 29 + P1Y clamps to Feb 28 on a non-leap target year" do
      assert Math.add(~o"2024Y2M29D", ~o"P1Y") == ~o"2025Y2M28D"
    end

    test "Mar 31 + P1M lands on Apr 30 (clamp)" do
      assert Math.add(~o"2022Y3M31D", ~o"P1M") == ~o"2022Y4M30D"
    end

    test "Jan 31 + P2M lands on Mar 31 (no clamp needed)" do
      # Because the duration is applied atomically — one clamp at
      # the end. Not the same as (Jan 31 + P1M) + P1M.
      assert Math.add(~o"2022Y1M31D", ~o"P2M") == ~o"2022Y3M31D"
    end
  end

  describe "add/2 — compound durations" do
    test "P1Y2M3D applied atomically" do
      assert Math.add(~o"2022Y1M1D", ~o"P1Y2M3D") == ~o"2023Y3M4D"
    end

    test "order is year → month → day → hour → minute → second" do
      # Verifies the documented order by checking a case where the
      # order matters: Jan 31 + P1M1D. Year step → no effect; month
      # step → Feb 31 → clamp to Feb 28; day step → +1 day → Mar 1.
      assert Math.add(~o"2022Y1M31D", ~o"P1M1D") == ~o"2022Y3M1D"
    end

    test "negative components in one duration" do
      # Adding `P1Y-1M` is "+1 year, -1 month" = "+11 months".
      duration = %Tempo.Duration{time: [year: 1, month: -1]}
      assert Math.add(~o"2022Y6M", duration) == ~o"2023Y5M"
    end
  end

  describe "add/2 — fully negative durations" do
    test "`-P100D` subtracts 100 days" do
      assert Math.add(~o"2022Y4M10D", ~o"P-100D") == ~o"2021Y12M31D"
    end
  end

  describe "add/2 — resolution extension" do
    test "duration finer than Tempo's resolution extends the Tempo first" do
      # `~o"2022Y"` is year-resolution. Adding `P1M` requires month
      # resolution; the Tempo is extended to month-precision first.
      assert Math.add(~o"2022Y", ~o"P1M") == ~o"2022Y2M"
    end

    test "duration at the same resolution doesn't extend" do
      assert Math.add(~o"2022Y6M", ~o"P1M") == ~o"2022Y7M"
    end
  end

  describe "subtract/2" do
    test "simple day subtraction with month borrow" do
      assert Math.subtract(~o"2023Y1M1D", ~o"P1D") == ~o"2022Y12M31D"
    end

    test "month subtraction with clamp" do
      assert Math.subtract(~o"2023Y3M31D", ~o"P1M") == ~o"2023Y2M28D"
    end

    test "compound subtract" do
      assert Math.subtract(~o"2022Y1M1D", ~o"P1Y2M3D") == ~o"2020Y10M29D"
    end

    test "subtracting 0-duration is idempotent" do
      source = ~o"2022Y6M15D"
      assert Math.subtract(source, %Tempo.Duration{time: []}) == source
    end
  end

  describe "subtract_unit/3 — primitive" do
    test "day with month borrow" do
      assert Math.subtract_unit(~o"2022Y2M1D", :day, Calendrical.Gregorian) ==
               {:ok, ~o"2022Y1M31D"}
    end

    test "day with year borrow" do
      assert Math.subtract_unit(~o"2023Y1M1D", :day, Calendrical.Gregorian) ==
               {:ok, ~o"2022Y12M31D"}
    end

    test "month across year boundary" do
      assert Math.subtract_unit(~o"2022Y1M", :month, Calendrical.Gregorian) == {:ok, ~o"2021Y12M"}
    end

    test "hour with day borrow" do
      assert Math.subtract_unit(~o"2022Y1M2DT0H", :hour, Calendrical.Gregorian) ==
               {:ok, ~o"2022Y1M1DT23H"}
    end

    test "minute with hour borrow" do
      assert Math.subtract_unit(~o"2022Y1M1DT1H0M", :minute, Calendrical.Gregorian) ==
               {:ok, ~o"2022Y1M1DT0H59M"}
    end

    test "week across year boundary" do
      # Week 1 - 1 week → previous year's last week. Gregorian has
      # 52 or 53 ISO weeks per year.
      {:ok, result} = Math.subtract_unit(~o"2023Y1W", :week, Calendrical.Gregorian)
      assert result.time[:year] == 2022
      assert result.time[:week] in [52, 53]
    end
  end

  describe "metadata preservation" do
    test "calendar is preserved across add" do
      source = ~o"2022Y1M1D"
      result = Math.add(source, ~o"P1M")
      assert result.calendar == source.calendar
    end

    test "shift is preserved across add" do
      {:ok, source} = Tempo.from_iso8601("2022-06-15T10:00:00+02:00")
      result = Math.add(source, ~o"PT1H")
      assert result.shift == source.shift
    end

    test "extended info is preserved across add" do
      {:ok, source} = Tempo.from_iso8601("2022-06-15T10:00:00Z[Europe/Paris]")
      result = Math.add(source, ~o"PT1H")
      assert result.extended == source.extended
    end

    test "margin-of-error (±) rides along with the shifted component (formerly crashed)" do
      assert Math.add(~o"2018±2Y", ~o"P1Y") == ~o"2019±2Y"
      assert Math.subtract(~o"2000±1Y", ~o"P1Y") == ~o"1999±1Y"
    end

    test "significant-digits (S) is preserved across arithmetic (formerly crashed)" do
      assert Math.add(~o"1950S3", ~o"P1Y") == ~o"1951S3"
    end
  end

  describe "unspecified-digit mask arithmetic (formerly crashed)" do
    test "a block-aligned year shift stays a mask" do
      assert Math.add(~o"195X", ~o"P10Y") == ~o"196X"
      assert Math.add(~o"195X", ~o"P20Y") == ~o"197X"
      assert Math.add(~o"19XX", ~o"P100Y") == ~o"20XX"
      assert Math.subtract(~o"196X", ~o"P10Y") == ~o"195X"
    end

    test "a misaligned year shift becomes a one-of set of the shifted block" do
      assert inspect(Math.add(~o"195X", ~o"P1Y")) == ~S|~o"[1951Y..1960Y]"|
    end

    test "a shift coarser than the mask keeps the mask intact" do
      assert Math.add(~o"2020-XX", ~o"P1Y") == ~o"2021-XX"
      assert Math.add(~o"2020-06-XX", ~o"P1M") == ~o"2020-07-XX"
    end

    test "a shift that reaches a sub-year mask crosses boundaries as a one-of set" do
      assert inspect(Math.add(~o"2020-XX", ~o"P1M")) == ~S|~o"[2020Y2M..2021Y1M]"|
      assert inspect(Math.add(~o"2020-06-XX", ~o"P1D")) == ~S|~o"[2020Y6M2D..2020Y7M1D]"|
    end

    test "masks in more than one component fill every mask (clean endpoints)" do
      # Both year and month masked — the shifted set's endpoints are fully
      # resolved, not left carrying a mask.
      assert inspect(Math.add(~o"19XX-XX", ~o"P1Y")) == ~S|~o"[1901Y1M..2000Y12M]"|

      assert inspect(Math.add(~o"2020-XX-XX", ~o"P1M")) ==
               ~S|~o"[2020Y2M1D..2021Y1M31D]"|
    end

    test "a shift coarser than every mask keeps all of them" do
      assert Math.add(~o"2020-XX-XX", ~o"P1Y") == ~o"2021-XX-XX"
    end

    test "a mask with a concrete component after it expands to disjoint spans" do
      # `199X-06-XX` is the Junes of 1990-1999 — ten *disjoint* month
      # spans, not one continuous range. Shifting must stay accurate, so
      # the result is a coalesced IntervalSet, not an over-covering range.
      result = Math.add(~o"199X-06-XX", ~o"P1Y")

      assert %Tempo.IntervalSet{intervals: intervals} = result
      assert length(intervals) == 10
      assert inspect(hd(intervals)) =~ "1991Y6M1D"
      assert inspect(List.last(intervals)) =~ "2000Y6M1D"
    end
  end
end
