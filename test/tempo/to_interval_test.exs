defmodule Tempo.ToInterval.Test do
  use ExUnit.Case, async: true

  alias Tempo.Interval
  alias Tempo.IntervalSet

  # Tests for `Tempo.to_interval/1` — implicit-to-explicit interval
  # materialisation. Covers the table of input-resolution rules from
  # `plans/implicit-to-explicit-interval-conversion.md` plus mask
  # widening, metadata propagation, and iteration parity.

  # Bounds keep the value's own resolution; the implicit iteration
  # granularity (the next-finer unit) travels on the interval's
  # `:unit` field instead of being drilled into the endpoints.

  describe "concrete date resolutions" do
    test "year only → year endpoints walked at :month" do
      {:ok, tempo} = Tempo.from_iso8601("2026")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2026]
      assert interval.to.time == [year: 2027]
      assert interval.unit == :month
    end

    test "year-month → year-month endpoints walked at :day" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2026, month: 1]
      assert interval.to.time == [year: 2026, month: 2]
      assert interval.unit == :day
    end

    test "year-month-day → year-month-day endpoints walked at :hour" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2026, month: 1, day: 15]
      assert interval.to.time == [year: 2026, month: 1, day: 16]
      assert interval.unit == :hour
    end

    test "month carry to next year" do
      {:ok, tempo} = Tempo.from_iso8601("2026-12")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.to.time == [year: 2027, month: 1]
    end

    test "day carry across leap year Feb → Mar" do
      {:ok, tempo} = Tempo.from_iso8601("2024-02-29")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2024, month: 2, day: 29]
      assert interval.to.time == [year: 2024, month: 3, day: 1]
    end
  end

  describe "concrete datetime resolutions" do
    test "hour → hour endpoints walked at :minute" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15T10")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2026, month: 1, day: 15, hour: 10]
      assert interval.to.time == [year: 2026, month: 1, day: 15, hour: 11]
      assert interval.unit == :minute
    end

    test "minute → minute endpoints walked at :second" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15T10:30")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.unit == :second

      assert interval.from.time == [
               year: 2026,
               month: 1,
               day: 15,
               hour: 10,
               minute: 30
             ]

      assert interval.to.time == [
               year: 2026,
               month: 1,
               day: 15,
               hour: 10,
               minute: 31
             ]
    end

    test "second — materialises to a one-second span" do
      # Once sub-second (microsecond) resolution exists below it, a
      # second is no longer the finest unit, so it materialises to
      # `[t, t+1s)` rather than erroring.
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15T10:30:00")
      {:ok, interval} = Tempo.to_interval(tempo)

      assert interval.from.time == [
               year: 2026,
               month: 1,
               day: 15,
               hour: 10,
               minute: 30,
               second: 0
             ]

      assert interval.to.time == [
               year: 2026,
               month: 1,
               day: 15,
               hour: 10,
               minute: 30,
               second: 1
             ]
    end

    test "second carries into the next minute at :59" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15T10:30:59")
      {:ok, interval} = Tempo.to_interval(tempo)

      assert interval.to.time == [
               year: 2026,
               month: 1,
               day: 15,
               hour: 10,
               minute: 31,
               second: 0
             ]
    end
  end

  describe "mask values (widest enclosing bound)" do
    test "positive year mask `156X` → decade span" do
      {:ok, tempo} = Tempo.from_iso8601("156X")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 1560]
      assert interval.to.time == [year: 1570]
    end

    test "millennium mask `1XXX` → millennium span" do
      {:ok, tempo} = Tempo.from_iso8601("1XXX")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 1000]
      assert interval.to.time == [year: 2000]
    end

    test "fully-unspecified year `XXXX` → 0..10000 span" do
      {:ok, tempo} = Tempo.from_iso8601("XXXX")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 0]
      assert interval.to.time == [year: 10_000]
    end

    test "negative year mask `-1XXX` → signed span (most-negative first)" do
      {:ok, tempo} = Tempo.from_iso8601("-1XXX")
      {:ok, interval} = Tempo.to_interval(tempo)
      # Magnitude range 1000..1999 → signed values -1999..-1000.
      # Half-open upper = -1000 + 1 = -999.
      assert interval.from.time == [year: -1999]
      assert interval.to.time == [year: -999]
    end

    test "month-day masked widens to year resolution" do
      {:ok, tempo} = Tempo.from_iso8601("1985-XX-XX")
      {:ok, interval} = Tempo.to_interval(tempo)
      # First masked unit is month; widen to year prefix.
      assert interval.from.time == [year: 1985]
      assert interval.to.time == [year: 1986]
    end

    test "day-only masked widens to month resolution" do
      {:ok, tempo} = Tempo.from_iso8601("1985-06-XX")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 1985, month: 6]
      assert interval.to.time == [year: 1985, month: 7]
    end

    test "non-contiguous `1985-XX-15` expands to 12 day-intervals" do
      # Day is specified but month is masked — the covered moments
      # are 12 disjoint days (the 15th of each month). `to_interval/1`
      # substitutes the mask with the valid month values and
      # materialises each as a day-resolution interval.
      {:ok, tempo} = Tempo.from_iso8601("1985-XX-15")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(tempo)
      assert length(intervals) == 12

      assert Enum.map(intervals, & &1.from.time[:month]) ==
               [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]

      assert Enum.all?(intervals, fn i ->
               i.from.time[:year] == 1985 and i.from.time[:day] == 15
             end)
    end
  end

  describe "group values (century / decade / unit groups)" do
    # A group (`{:group, first..last}`) is a contiguous span, so it
    # materialises to the single enclosing interval `[first, last+1)`
    # at the group's unit — not by drilling finer, and not as a set of
    # members. Previously a year group crashed (`add_unit(:year)` did
    # arithmetic on the `{:group, …}` tuple).
    test "century `20C` → the 100-year span [2000, 2100)" do
      {:ok, tempo} = Tempo.from_iso8601("20C")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2000]
      assert interval.to.time == [year: 2100]
      # 100 years measured in seconds.
      assert Interval.duration(interval).time == [second: 3_155_760_000]
    end

    test "decade `201J` → the 10-year span [2010, 2020)" do
      {:ok, tempo} = Tempo.from_iso8601("201J")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2010]
      assert interval.to.time == [year: 2020]
    end

    test "month group `2018Y1G6MU` → the six-month span [2018-01, 2018-07)" do
      {:ok, tempo} = Tempo.from_iso8601("2018Y1G6MU")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2018, month: 1]
      assert interval.to.time == [year: 2018, month: 7]
    end

    test "group at the finest unit carries at the unit boundary" do
      # Day group ending at the last day of February carries into March.
      tempo = %Tempo{
        calendar: Calendrical.Gregorian,
        time: [year: 2018, month: 2, day: {:group, 15..28}]
      }

      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2018, month: 2, day: 15]
      assert interval.to.time == [year: 2018, month: 3, day: 1]
    end

    test "non-anchored day group `5G10DU` returns a clean error (no crash)" do
      # Days 41..50 of no particular year — the `:day` carry needs
      # year/month context the fragment doesn't carry, so it has no
      # concrete span. Must not raise.
      {:ok, tempo} = Tempo.from_iso8601("5G10DU")

      assert {:error, %Tempo.MaterialisationError{reason: :unanchored_group}} =
               Tempo.to_interval(tempo)
    end

    test "a group of a year's days is the dates it covers" do
      tempo = %Tempo{calendar: Calendrical.Gregorian, time: [year: 2022, day: {:group, 41..50}]}

      assert {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2022, month: 2, day: 10]
      assert interval.to.time == [year: 2022, month: 2, day: 20]
    end

    test "a group of a year's weeks or hours is the span it covers" do
      {:ok, weeks} = Tempo.from_iso8601("2026Y2G13WU")
      assert {:ok, interval} = Tempo.to_interval(weeks)

      assert {interval.from.time, interval.to.time} ==
               {[year: 2026, week: 14], [year: 2026, week: 27]}

      {:ok, hours} = Tempo.from_iso8601("2018Y20GT12HU")
      assert {:ok, interval} = Tempo.to_interval(hours)
      assert interval.from.time == [year: 2018, month: 1, day: 10, hour: 12]
      assert interval.to.time == [year: 2018, month: 1, day: 11, hour: 0]
    end

    test "the last group of a unit ends with its container" do
      {:ok, days} = Tempo.from_iso8601("2018Y2M3G11DU")
      assert days.time == [year: 2018, month: 2, day: {:group, 23..33}]
      assert {:ok, interval} = Tempo.to_interval(days)
      assert interval.to.time == [year: 2018, month: 3, day: 1]

      {:ok, weeks} = Tempo.from_iso8601("2028Y5G13WU")
      assert {:ok, interval} = Tempo.to_interval(weeks)

      assert {interval.from.time, interval.to.time} ==
               {[year: 2028, week: 53], [year: 2029, week: 1]}
    end

    test "a group that starts beyond its container is an error" do
      assert {:error, %Tempo.InvalidDateError{unit: :month, value: 13}} =
               Tempo.from_iso8601("2026Y5G3MU")

      assert {:error, %Tempo.InvalidDateError{unit: :week, value: 53}} =
               Tempo.from_iso8601("2026Y5G13WU")
    end
  end

  describe "non-anchored time-of-day groups materialise to a relative interval" do
    defp group(time), do: %Tempo{calendar: Calendrical.Gregorian, time: time}

    test "a minute group materialises to its relative span" do
      {:ok, interval} = Tempo.to_interval(group(hour: 16, minute: {:group, 1..15}))
      assert interval.from.time == [hour: 16, minute: 1]
      assert interval.to.time == [hour: 16, minute: 16]
    end

    test "the result is non-anchored (lives on the time-of-day axis)" do
      {:ok, interval} = Tempo.to_interval(group(hour: 16, minute: {:group, 1..15}))
      refute Tempo.anchored?(interval.from)
      refute Tempo.anchored?(interval.to)
    end

    test "the upper bound carries into the next hour" do
      {:ok, interval} = Tempo.to_interval(group(hour: 16, minute: {:group, 45..59}))
      assert interval.from.time == [hour: 16, minute: 45]
      assert interval.to.time == [hour: 17, minute: 0]
    end

    test "a second group materialises" do
      {:ok, interval} = Tempo.to_interval(group(hour: 16, minute: 30, second: {:group, 1..15}))
      assert interval.from.time == [hour: 16, minute: 30, second: 1]
      assert interval.to.time == [hour: 16, minute: 30, second: 16]
    end

    test "a bare minute group (no hour) materialises" do
      {:ok, interval} = Tempo.to_interval(group(minute: {:group, 1..15}))
      assert interval.from.time == [minute: 1]
      assert interval.to.time == [minute: 16]
    end

    test "a carry off the end of the day still errors (no absent day to carry into)" do
      assert {:error, %Tempo.MaterialisationError{reason: :unanchored_group}} =
               Tempo.to_interval(group(hour: 23, minute: {:group, 45..59}))
    end

    test "a partially-dated value still requires anchoring" do
      # A month with no year/day is not a pure time-of-day value.
      assert {:error, %Tempo.MaterialisationError{reason: :unanchored_group}} =
               Tempo.to_interval(group(month: 6, hour: 16, minute: {:group, 1..15}))
    end

    test "a fully anchored time-of-day group still produces an anchored interval" do
      {:ok, interval} =
        Tempo.to_interval(group(year: 2026, month: 6, day: 15, hour: 16, minute: {:group, 1..15}))

      assert interval.from.time == [year: 2026, month: 6, day: 15, hour: 16, minute: 1]
      assert interval.to.time == [year: 2026, month: 6, day: 15, hour: 16, minute: 16]
      assert Tempo.anchored?(interval.from)
    end
  end

  describe "week / ordinal date duration (UTC projection)" do
    # `Compare.to_utc_seconds/1` must resolve week and ordinal dates to
    # a real calendar date; otherwise both endpoints collapse to Jan 1
    # and the interval reports a zero-second duration.
    test "a week spans seven days" do
      {:ok, tempo} = Tempo.from_iso8601("2022-W24")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert Interval.duration(interval).time == [second: 604_800]
    end

    test "adjacent weeks meet (not equal)" do
      # Before the fix both projected to Jan 1, so they compared `:equals`.
      {:ok, w24} = Tempo.from_iso8601("2022-W24")
      {:ok, w25} = Tempo.from_iso8601("2022-W25")
      assert Tempo.relation(w24, w25) == :meets
    end

    test "an ordinal date spans one day" do
      {:ok, tempo} = Tempo.from_iso8601("2022-166")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert Interval.duration(interval).time == [second: 86_400]
    end
  end

  describe "passthroughs and errors" do
    test "existing %Tempo.Interval{} is idempotent" do
      {:ok, interval} = Tempo.from_iso8601("1985/1986")
      {:ok, result} = Tempo.to_interval(interval)
      assert result == interval
    end

    test "open-ended interval passes through" do
      {:ok, interval} = Tempo.from_iso8601("1985/..")
      {:ok, result} = Tempo.to_interval(interval)
      assert result == interval
    end

    test "bare Tempo.Duration returns an error" do
      {:ok, duration} = Tempo.from_iso8601("P3M")

      assert {:error, %Tempo.MaterialisationError{reason: :bare_duration} = e} =
               Tempo.to_interval(duration)

      assert Exception.message(e) =~ "Duration"
      assert Exception.message(e) =~ "no anchor"
    end

    test "to_interval!/1 raises on duration" do
      {:ok, duration} = Tempo.from_iso8601("P3M")

      assert_raise Tempo.MaterialisationError, ~r/no anchor/, fn ->
        Tempo.to_interval!(duration)
      end
    end

    test "to_interval!/1 materialises a second-resolution Tempo to a one-second span" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15T10:30:00")
      interval = Tempo.to_interval!(tempo)

      assert interval.from.time[:second] == 0
      assert interval.to.time[:second] == 1
    end
  end

  describe "Tempo.Set mapping" do
    test "one-of set (`[a,b,c]`) is epistemic disjunction — returns an error" do
      # `[…]` is one-of set syntax: "it was one of these, I don't
      # know which." Flattening to an IntervalSet would lie about
      # certainty.
      {:ok, set} = Tempo.from_iso8601("[2020Y,2021Y,2022Y]")

      assert {:error, %Tempo.MaterialisationError{reason: :one_of_set} = e} =
               Tempo.to_interval(set)

      assert Exception.message(e) =~ "one-of"
      assert Exception.message(e) =~ "epistemic"
    end

    test "all-of range (`{a..c}Y`) materialises to distinct year members" do
      {:ok, tempo} = Tempo.from_iso8601("{2020,2021,2022}Y")
      {:ok, set} = Tempo.to_interval(tempo)

      # Three distinct year members by default.
      assert length(set.intervals) == 3

      # Coalesced: the touching years merge into a single 3-year span.
      coalesced = IntervalSet.coalesce(set)
      [interval] = coalesced.intervals
      assert interval.from.time == [year: 2020]
      assert interval.to.time == [year: 2023]
    end
  end

  describe "metadata propagation" do
    test "expression-level qualification propagates to both endpoints" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y?")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.qualification == :uncertain
      assert interval.to.qualification == :uncertain
    end

    test "component-level qualifications propagate" do
      {:ok, tempo} = Tempo.from_iso8601("2022-?06-15")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.qualifications == %{month: :uncertain}
      assert interval.to.qualifications == %{month: :uncertain}
    end

    test "IXDTF extended info (zone + calendar) propagates" do
      {:ok, tempo} = Tempo.from_iso8601("2022-06-15T10:30[Europe/Paris][u-ca=hebrew]")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.from.extended.calendar == :hebrew
      assert interval.to.extended.zone_id == "Europe/Paris"
      assert interval.to.extended.calendar == :hebrew
    end

    test "calendar propagates" do
      {:ok, tempo} = Tempo.from_iso8601("2022")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.calendar == Calendrical.Gregorian
      assert interval.to.calendar == Calendrical.Gregorian
    end
  end

  describe "iteration parity (implicit vs explicit)" do
    # The central promise of `to_interval/1`: implicit iteration and
    # explicit iteration produce identical results for every shape
    # that supports both. If this test fails, either the implicit
    # enumeration or the explicit materialisation is wrong.

    for input <- ["2026Y", "2026-06", "2026-06-15", "2026-06-15T10", "2026-06-15T10:30"] do
      test "implicit vs explicit iteration match for #{inspect(input)}" do
        {:ok, tempo} = Tempo.from_iso8601(unquote(input))
        {:ok, interval} = Tempo.to_interval(tempo)

        implicit_times = tempo |> Enum.to_list() |> Enum.map(& &1.time)
        explicit_times = interval |> Enum.to_list() |> Enum.map(& &1.time)

        assert implicit_times == explicit_times,
               "implicit and explicit iteration diverge for #{unquote(input)}\n" <>
                 "implicit: #{inspect(implicit_times, limit: 3)}\n" <>
                 "explicit: #{inspect(explicit_times, limit: 3)}"
      end
    end
  end
end
