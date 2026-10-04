defmodule Tempo.ToInterval.Test do
  use ExUnit.Case, async: true

  import Tempo.Sigils

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

  describe "mask values (the span their digits allow)" do
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

    test "a partly masked day is the span from its first candidate to its last" do
      {:ok, interval} = Tempo.to_interval(~o"2026-06-1X")
      assert {interval.from.time, interval.to.time} == {ymd(2026, 6, 10), ymd(2026, 6, 20)}

      {:ok, interval} = Tempo.to_interval(~o"2026-06-0X")
      assert {interval.from.time, interval.to.time} == {ymd(2026, 6, 1), ymd(2026, 6, 10)}
    end

    test "a partly masked day narrows to the days its month has" do
      {:ok, interval} = Tempo.to_interval(~o"2026-06-3X")
      assert {interval.from.time, interval.to.time} == {ymd(2026, 6, 30), ymd(2026, 7, 1)}

      assert {:error, %Tempo.InvalidDateError{}} = Tempo.to_interval(~o"2026-02-3X")
    end

    test "scattered candidates are spans of their own" do
      {:ok, set} = Tempo.to_interval(~o"2026-06-X5")
      assert spans(set) == [ymd_span(2026, 6, 5), ymd_span(2026, 6, 15), ymd_span(2026, 6, 25)]
    end

    test "a partly masked month, hour or minute narrows as a day does" do
      {:ok, months} = Tempo.to_interval(~o"2026-1X")

      assert {months.from.time, months.to.time} ==
               {[year: 2026, month: 10], [year: 2027, month: 1]}

      {:ok, hours} = Tempo.to_interval(~o"2026-06-15T1X")
      assert {hours.from.time[:hour], hours.to.time[:hour]} == {10, 20}

      {:ok, minutes} = Tempo.to_interval(~o"2026-06-15T10:3X")
      assert {minutes.from.time[:minute], minutes.to.time[:minute]} == {30, 40}
    end

    # A day of the year (`O`), or a day written straight after its year, was
    # left as the candidate it is: the first gave bounds that measured
    # nothing (`2026Y30O/40O`), the second an `UnanchoredError` for a value
    # that has a year.
    test "a partly masked day of the year is the span of the dates it names" do
      for masked <- [~o"2026Y3XD", ~o"2026Y3XO"] do
        assert Tempo.to_interval(masked) == {:ok, ~o"2026Y1M30D/2026Y2M9D"}
        assert Tempo.duration(masked) == ~o"P10D"
      end

      assert Tempo.to_interval(~o"2026Y1XXD") == {:ok, ~o"2026Y4M10D/2026Y7M19D"}
      assert Tempo.to_interval(~o"2026Y36XD") == {:ok, ~o"2026Y12M26D/2027Y1M1D"}
      assert Tempo.to_interval(~o"2024Y36XO") == {:ok, ~o"2024Y12M25D/2025Y1M1D"}
    end

    test "a partly masked day of the year in each of a set of years, and as an interval's end" do
      {:ok, set} = Tempo.to_interval(~o"{2026,2027}Y3XD")

      assert spans(set) == [
               {ymd(2026, 1, 30), ymd(2026, 2, 9)},
               {ymd(2027, 1, 30), ymd(2027, 2, 9)}
             ]

      assert Tempo.to_interval(~o"2026Y3XD/2026Y6M") == {:ok, ~o"2026Y1M30D/2026Y6M"}
      assert Tempo.duration(~o"2026Y1M/2026Y3XO") == ~o"P29D"
    end

    test "a partly masked day of the year in another calendar" do
      {:ok, interval} = Tempo.to_interval(Tempo.from_iso8601!("5786Y3XD[u-ca=hebrew]"))

      assert {interval.from.time, interval.to.time} ==
               {[year: 5786, month: 1, day: 30], [year: 5786, month: 2, day: 10]}
    end

    test "a mask before a partly masked day is one span per candidate" do
      {:ok, set} = Tempo.to_interval(~o"2026-XX-1X")
      members = IntervalSet.members(set)

      assert Enum.map(members, & &1.from.time[:month]) == Enum.to_list(1..12)
      assert Enum.all?(members, &(&1.from.time[:day] == 10 and &1.to.time[:day] == 20))
    end

    test "a candidate with no day drops out, as a set's does" do
      {:ok, set} = Tempo.to_interval(~o"2026-XX-3X")
      months = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:month]) |> Enum.uniq()

      assert months == [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    end

    test "a set before a mask is a context for it" do
      {:ok, set} = Tempo.to_interval(~o"2026-{6,7}-1X")

      assert spans(set) == [
               {ymd(2026, 6, 10), ymd(2026, 6, 20)},
               {ymd(2026, 7, 10), ymd(2026, 7, 20)}
             ]

      {:ok, set} = Tempo.to_interval(~o"2026-{6,7}-XX")

      assert spans(set) == [
               {[year: 2026, month: 6], [year: 2026, month: 7]},
               {[year: 2026, month: 7], [year: 2026, month: 8]}
             ]
    end

    test "a mask without a year narrows when every year agrees" do
      {:ok, set} = Tempo.to_interval(~o"XX-1X")
      february = Enum.at(IntervalSet.members(set), 1)

      assert {february.from.time, february.to.time} ==
               {[month: 2, day: 10], [month: 2, day: 20]}
    end

    test "a masked week with a day of the week is that day of each week" do
      {:ok, set} = Tempo.to_interval(~o"2026-W1X-3")
      wednesdays = IntervalSet.members(set)

      assert length(wednesdays) == 10
      assert hd(wednesdays).from.time == ymd(2026, 3, 4)
    end
  end

  # An unspecified unit (`X*D`, any day) was stepped as one value, so its
  # span started at the value itself (`2026Y6MX*D/7M1D`), which is no point:
  # `duration/1` and `to_relative_string/2` raised.
  describe "an unspecified unit (the span a unit with every digit masked has)" do
    test "with nothing narrower after it is the span of the units before it" do
      assert Tempo.to_interval(~o"2026Y6MX*D") == {:ok, ~o"2026Y6M/2026Y7M"}
      assert Tempo.to_interval(~o"2026YX*M") == {:ok, ~o"2026Y/2027Y"}
      assert Tempo.to_interval(~o"2026YX*MX*D") == {:ok, ~o"2026Y/2027Y"}
      assert Tempo.to_interval(~o"2026Y6M15DTX*H") == {:ok, ~o"2026Y6M15D/2026Y6M16D"}
      assert Tempo.to_interval(~o"2026Y6M15DT10HX*M") == {:ok, ~o"2026Y6M15DT10H/2026Y6M15DT11H"}
      assert Tempo.to_interval(~o"2026Y25WX*K") == {:ok, ~o"2026Y25W/2026Y26W"}
      assert Tempo.to_interval(~o"2026YX*O") == {:ok, ~o"2026Y/2027Y"}
    end

    test "is read as the mask of all its digits is" do
      for {unspecified, masked} <- [
            {~o"2026Y6MX*D", ~o"2026Y6MXXD"},
            {~o"2026YX*M15D", ~o"2026YXXM15D"},
            {~o"2026YX*M1XD", ~o"2026YXXM1XD"},
            {~o"2026Y6MX*DT10H", ~o"2026Y6MXXDT10H"},
            {~o"2026Y{6,7}MX*D", ~o"2026Y{6,7}MXXD"},
            {~o"2026YX*W3K", ~o"2026YXXW3K"},
            {~o"2026YX*OT10H", ~o"2026YXXXOT10H"},
            {~o"6MX*D", ~o"6MXXD"},
            {~o"T10HX*M", ~o"T10HXXM"}
          ] do
        assert Tempo.to_interval(unspecified) == Tempo.to_interval(masked)
      end
    end

    test "before a narrower unit is a span for each value it takes" do
      {:ok, set} = Tempo.to_interval(~o"2026YX*M15D")

      assert Enum.map(IntervalSet.members(set), & &1.from) ==
               Enum.map(1..12, &%{~o"2026Y1M15D" | time: ymd(2026, &1, 15)})

      {:ok, set} = Tempo.to_interval(~o"2026Y6MX*DT10H")
      assert IntervalSet.count(set) == 30

      {:ok, set} = Tempo.to_interval(~o"2026Y{6,7}MX*D")

      assert spans(set) == [
               {[year: 2026, month: 6], [year: 2026, month: 7]},
               {[year: 2026, month: 7], [year: 2026, month: 8]}
             ]
    end

    test "in another calendar and in a zone" do
      {:ok, adar} = Tempo.to_interval(Tempo.from_iso8601!("5786Y6MX*D[u-ca=hebrew]"))
      assert {adar.from.time, adar.to.time} == {[year: 5786, month: 6], [year: 5786, month: 7]}
      assert adar.from.calendar == Calendrical.Hebrew

      {:ok, paris} = Tempo.to_interval(Tempo.from_iso8601!("2026Y6MX*D[Europe/Paris]"))
      assert paris.from.time == [year: 2026, month: 6]
      assert paris.from.extended.zone_id == "Europe/Paris"
    end

    test "is a span that can be measured" do
      assert Tempo.duration(~o"2026Y6MX*D") == ~o"P1M"
      assert Tempo.duration(~o"2026YX*M") == ~o"P1Y"
      assert Tempo.duration(~o"2026Y6M15DTX*H") == ~o"P1D"
      assert Tempo.duration(~o"2026YX*M15D") == ~o"P12D"

      assert Tempo.to_relative_string(~o"2026Y6MX*D", from: ~o"2026-10-03") ==
               {:ok, "4 months ago"}

      assert Tempo.relation(~o"2026Y6MX*D", ~o"2026Y9M") == :precedes
      assert Tempo.within?(~o"2026-06-15", ~o"2026Y6MX*D")
    end

    test "alone, with no unit before it, has no span" do
      for value <- [~o"X*M", ~o"X*D", ~o"X*W", ~o"X*K", ~o"TX*H"] do
        assert {:error, %Tempo.ConversionError{}} = Tempo.to_interval(value)
      end
    end
  end

  describe "sets of week dates" do
    test "a set of weeks or of days of the week is each date it names" do
      {:ok, set} = Tempo.to_interval(~o"2026-W{10,11}-3")
      assert spans(set) == [ymd_span(2026, 3, 4), ymd_span(2026, 3, 11)]

      {:ok, set} = Tempo.to_interval(~o"2026-W25-{1,3}")
      assert spans(set) == [ymd_span(2026, 6, 15), ymd_span(2026, 6, 17)]
    end
  end

  describe "a recurrence written with an end (ISO 8601-1 §5.6.1)" do
    test "a start and an end are its first occurrence, and the rest follow it" do
      {:ok, set} = Tempo.to_interval(~o"R5/2026-06-15/2026-06-20")

      assert spans(set) == [
               {ymd(2026, 6, 15), ymd(2026, 6, 20)},
               {ymd(2026, 6, 20), ymd(2026, 6, 25)},
               {ymd(2026, 6, 25), ymd(2026, 6, 30)},
               {ymd(2026, 6, 30), ymd(2026, 7, 5)},
               {ymd(2026, 7, 5), ymd(2026, 7, 10)}
             ]
    end

    test "each occurrence is as long as the first, in the unit its endpoints are written in" do
      {:ok, months} = Tempo.to_interval(~o"R3/2026-01/2026-03")

      assert spans(months) == [
               {[year: 2026, month: 1], [year: 2026, month: 3]},
               {[year: 2026, month: 3], [year: 2026, month: 5]},
               {[year: 2026, month: 5], [year: 2026, month: 7]}
             ]

      {:ok, days} = Tempo.to_interval(~o"R2/2026-01-31/2026-02-28")

      assert spans(days) == [
               {ymd(2026, 1, 31), ymd(2026, 2, 28)},
               {ymd(2026, 2, 28), ymd(2026, 3, 28)}
             ]
    end

    test "a duration and an end are its last occurrence, and the rest precede it" do
      {:ok, set} = Tempo.to_interval(~o"R5/P1D/2026-06-20")
      assert spans(set) == Enum.map(15..19, &ymd_span(2026, 6, &1))
    end

    test "a month cadence back from an end keeps the end" do
      {:ok, set} = Tempo.to_interval(~o"R3/P1M/2026-07-31")

      assert spans(set) == [
               {ymd(2026, 4, 30), ymd(2026, 5, 31)},
               {ymd(2026, 5, 31), ymd(2026, 6, 30)},
               {ymd(2026, 6, 30), ymd(2026, 7, 31)}
             ]
    end

    test "a fraction of a second steps back as it steps forward" do
      {:ok, set} = Tempo.to_interval(~o"R3/PT0.5S/2026-06-15T10:00:00")
      [_, _, last] = IntervalSet.members(set)

      assert length(IntervalSet.members(set)) == 3
      assert last.to.time == [year: 2026, month: 6, day: 15, hour: 10, minute: 0, second: 0]
    end

    test "an unending one needs a :within window, and names itself without one" do
      unending = ~o"R/2026-06-15/2026-06-20"

      assert {:error, %Tempo.UnboundedRecurrenceError{interval: ^unending}} =
               Tempo.to_interval(unending)

      {:ok, june} = Tempo.to_interval(unending, within: ~o"2026-06")
      assert length(IntervalSet.members(june)) == 4

      assert {:error, %Tempo.UnboundedRecurrenceError{}} = Tempo.to_interval(~o"R/P1D/2026-06-20")

      {:ok, june} = Tempo.to_interval(~o"R/P1D/2026-06-20", within: ~o"2026-06")
      assert spans(june) == Enum.map(1..19, &ymd_span(2026, 6, &1))
    end

    test "a recurrence of no occurrences is an empty set" do
      {:ok, set} = Tempo.to_interval(~o"R0/2026-06-15/P1D")
      assert IntervalSet.members(set) == []
    end
  end

  defp ymd(year, month, day), do: [year: year, month: month, day: day]

  # One mid-month day's span.
  defp ymd_span(year, month, day), do: {ymd(year, month, day), ymd(year, month, day + 1)}

  defp spans(%IntervalSet{} = set) do
    for %Interval{from: from, to: to} <- IntervalSet.members(set), do: {from.time, to.time}
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
      assert Interval.duration(interval).time == [year: 100]
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

    test "unanchored day group `5G10DU` returns a clean error (no crash)" do
      # Days 41..50 of no particular year — the `:day` carry needs
      # year/month context the fragment doesn't carry, so it has no
      # concrete span. Must not raise.
      {:ok, tempo} = Tempo.from_iso8601("5G10DU")

      assert {:error, %Tempo.ConversionError{reason: :unanchored_group}} =
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

      # 2026 has 53 ISO 8601 weeks, so its fifth group of thirteen is week 53.
      {:ok, weeks} = Tempo.from_iso8601("2026Y5G13WU")
      assert {:ok, interval} = Tempo.to_interval(weeks)

      assert {interval.from.time, interval.to.time} ==
               {[year: 2026, week: 53], [year: 2027, week: 1]}
    end

    test "a group that starts beyond its container is an error" do
      assert {:error, %Tempo.InvalidDateError{unit: :month, value: 13}} =
               Tempo.from_iso8601("2026Y5G3MU")

      assert {:error, %Tempo.InvalidDateError{unit: :week, value: 53}} =
               Tempo.from_iso8601("2028Y5G13WU")
    end
  end

  describe "unanchored time-of-day groups materialise to a relative interval" do
    defp group(time), do: %Tempo{calendar: Calendrical.Gregorian, time: time}

    test "a minute group materialises to its relative span" do
      {:ok, interval} = Tempo.to_interval(group(hour: 16, minute: {:group, 1..15}))
      assert interval.from.time == [hour: 16, minute: 1]
      assert interval.to.time == [hour: 16, minute: 16]
    end

    test "the result is unanchored (lives on the time-of-day axis)" do
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
      assert {:error, %Tempo.ConversionError{reason: :unanchored_group}} =
               Tempo.to_interval(group(hour: 23, minute: {:group, 45..59}))
    end

    test "a partially-dated value still requires anchoring" do
      # A month with no year/day is not a pure time-of-day value.
      assert {:error, %Tempo.ConversionError{reason: :unanchored_group}} =
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
    # and the interval is empty, with a duration of zero.
    test "a week spans one week" do
      {:ok, tempo} = Tempo.from_iso8601("2022-W24")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert Interval.duration(interval).time == [week: 1]
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
      assert Interval.duration(interval).time == [day: 1]
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

      assert {:error, %Tempo.ConversionError{reason: :bare_duration} = e} =
               Tempo.to_interval(duration)

      assert Exception.message(e) =~ "Duration"
      assert Exception.message(e) =~ "no place on the time line"
    end

    test "to_interval!/1 raises on duration" do
      {:ok, duration} = Tempo.from_iso8601("P3M")

      assert_raise Tempo.ConversionError, ~r/no place on the time line/, fn ->
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

      assert {:error, %Tempo.ConversionError{reason: :one_of_set} = e} =
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
      assert Tempo.qualification(interval.from) == :uncertain
      assert Tempo.qualification(interval.to) == :uncertain
    end

    test "component-level qualifications propagate" do
      {:ok, tempo} = Tempo.from_iso8601("2022-?06-15")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.qualifications == %{month: :uncertain}
      assert interval.to.qualifications == %{month: :uncertain}
    end

    test "an IXDTF zone, and the calendar a suffix names, propagate" do
      {:ok, tempo} = Tempo.from_iso8601("2022-06-15T10:30[Europe/Paris][u-ca=hebrew]")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.from.calendar == Calendrical.Hebrew
      assert interval.to.extended.zone_id == "Europe/Paris"
      assert interval.to.calendar == Calendrical.Hebrew
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
