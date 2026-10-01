defmodule Tempo.DurationResolutionTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ICal
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  defp measure(from, to), do: Interval.duration(%Interval{from: from, to: to})

  describe "a duration is counted in its endpoints' unit" do
    test "years, months, weeks and days count calendar steps" do
      assert measure(~o"2020", ~o"2026") == ~o"P6Y"
      assert measure(~o"2026-06", ~o"2026-09") == ~o"P3M"
      assert measure(~o"2026-W10", ~o"2026-W14") == ~o"P4W"
      assert measure(~o"2026-06-15", ~o"2026-07-21") == ~o"P36D"
      assert measure(~o"2026-100", ~o"2026-166") == ~o"P66D"
    end

    test "hours, minutes, seconds and fractions of a second are elapsed time" do
      assert measure(~o"2026-06-15T09", ~o"2026-06-15T17") == ~o"PT8H"
      assert measure(~o"2026-06-15T09:00", ~o"2026-06-15T10:30") == ~o"PT90M"
      assert measure(~o"2026-06-15T09:00:00", ~o"2026-06-15T09:02:05") == ~o"PT125S"

      assert measure(~o"2026-06-15T10:00:00.623", ~o"2026-06-15T10:00:01.123") ==
               ~o"PT0.500S"
    end

    test "endpoints of different resolutions count in the finer unit" do
      assert measure(~o"2020", ~o"2026-06") == ~o"P77M"
      assert measure(~o"2026-06", ~o"2026-06-15") == ~o"P14D"
      assert measure(~o"2026-06-15", ~o"2026-06-16T12") == ~o"PT36H"
      assert measure(~o"2026-06-15T09", ~o"2026-06-15T10:30") == ~o"PT90M"
    end

    test "a week against a month or a year counts days, which divide both" do
      assert measure(~o"2026-W10", ~o"2026-06") == ~o"P91D"
      assert measure(~o"2026-06", ~o"2026-W30") == ~o"P49D"
      assert measure(~o"2026", ~o"2026-W10") == ~o"P60D"
    end

    test "a week's days, as enumerating the week gives them, are days apart" do
      [monday, _tuesday, wednesday] = Enum.take(~o"2026-W40", 3)

      assert measure(monday, wednesday) == ~o"P2D"
    end

    test "a Hebrew leap year has thirteen months" do
      from = Tempo.from_iso8601!("5784-01[u-ca=hebrew]")
      to = Tempo.from_iso8601!("5786-01[u-ca=hebrew]")

      assert measure(from, to) == ~o"P25M"
    end
  end

  describe "daylight saving" do
    test "the day New York springs forward is one day, and 23 hours" do
      assert measure(~o"2026-03-08[America/New_York]", ~o"2026-03-09[America/New_York]") ==
               ~o"P1D"

      assert measure(~o"2026-03-08T00[America/New_York]", ~o"2026-03-09T00[America/New_York]") ==
               ~o"PT23H"
    end

    test "Lord Howe Island's half-hour change keeps the half hour" do
      assert measure(
               ~o"2026-10-04T00[Australia/Lord_Howe]",
               ~o"2026-10-05T00[Australia/Lord_Howe]"
             ) == ~o"PT23H30M"
    end
  end

  describe "endpoints in different zones" do
    test "hours between zones half an hour apart keep the half hour" do
      assert measure(~o"2026-06-15T09[Asia/Kolkata]", ~o"2026-06-15T10[Europe/London]") ==
               ~o"PT5H30M"
    end

    test "days and months are fitted on the time line, the rest kept in days and hours" do
      assert measure(~o"2026-06-16[Pacific/Kiritimati]", ~o"2026-06-17[Pacific/Pago_Pago]") ==
               ~o"P2DT1H"

      assert measure(~o"2026-06[Europe/London]", ~o"2026-09[America/New_York]") == ~o"P3MT5H"

      assert measure(~o"2026-06[America/New_York]", ~o"2026-09[Europe/London]") ==
               ~o"P2M30DT19H"
    end
  end

  describe "empty intervals and leap seconds" do
    test "an empty or inverted interval is zero in its unit" do
      assert measure(~o"2026-06-15", ~o"2026-06-15") == ~o"P0D"
      assert measure(~o"2026-06-15T10", ~o"2026-06-15T09") == ~o"PT0H"
    end

    test "a leap second is added as a second whatever the unit" do
      interval = %Interval{from: ~o"2016-12-31Z", to: ~o"2017-01-01Z"}

      assert Interval.duration(interval) == ~o"P1D"
      assert Interval.duration(interval, leap_seconds: true) == ~o"P1DT1S"
    end
  end

  describe "Tempo.duration/2 and sets" do
    test "the days until an election are days" do
      assert Tempo.duration(~o"2026-09-28", ~o"2026-11-03") == {:ok, ~o"P36D"}
    end

    test "a set adds its members' lengths unit by unit" do
      {:ok, christmas} = Tempo.union(~o"2026-12-25", ~o"2026-12-26")
      assert IntervalSet.duration(christmas) == ~o"P2D"

      {:ok, sessions} =
        Tempo.union(~o"2026-06-01T09/2026-06-01T12", ~o"2026-06-01T14/2026-06-01T17")

      assert IntervalSet.duration(sessions) == ~o"PT6H"
    end

    test "the empty set is zero seconds" do
      assert IntervalSet.duration(IntervalSet.new!([])) == ~o"PT0S"
    end
  end

  describe "iCalendar" do
    test "an all-day event's RDATE occurrence ends on a day" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:rdate-all-day
      DTSTAMP:20220101T000000Z
      DTSTART;VALUE=DATE:20220704
      DTEND;VALUE=DATE:20220705
      RRULE:FREQ=YEARLY;COUNT=2
      RDATE;VALUE=DATE:20220801
      SUMMARY:Holiday
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)

      rdate =
        Enum.find(IntervalSet.members(set), &(&1.from.time == [year: 2022, month: 8, day: 1]))

      assert rdate.to.time == [year: 2022, month: 8, day: 2]
    end
  end

  describe "Tempo.to_date/1 on a value that is not one day" do
    test "a group of days is an error, not a crash" do
      assert {:error, %Tempo.ConversionError{}} = Tempo.to_date(~o"2022Y1M2G3DU")
    end
  end

  describe "an endpoint that names a span is read from where its span starts" do
    test "a century, a masked month and a selection that picks one day" do
      assert Interval.duration(~o"20C/2100") == ~o"P100Y"
      assert measure(~o"2000", ~o"21C") == ~o"P100Y"
      assert Interval.duration(~o"1985-XX/1986") == ~o"P1Y"

      # Easter Sunday 2027 is 28 March.
      assert measure(~o"2027YL(easter)eN", ~o"2027-12") == ~o"P248D"
      assert Tempo.duration(~o"20C/2100") == ~o"P100Y"
    end

    test "an endpoint that names several spans is an error" do
      assert {:error, %ArgumentError{message: message}} = measure(~o"{2026,2027}Y", ~o"2028")
      assert message =~ "several spans"
    end
  end

  describe "what duration/2 cannot measure is an error, not a raise" do
    test "an endpoint without a year" do
      for interval <- [
            ~o"T09/T17",
            ~o"6M/8M",
            ~o"T09/PT2H",
            %Interval{from: ~o"2026-06-15", to: ~o"6M20D"}
          ] do
        assert {:error, %Tempo.UnanchoredError{operation: :duration}} =
                 Interval.duration(interval)
      end
    end

    test "a finite recurrence, endpoints in different calendars, or one that is not a value" do
      {:ok, hebrew} = Tempo.from_iso8601("5786-09-30[u-ca=hebrew]")

      assert {:error, %Tempo.ConversionError{reason: :recurring_duration}} =
               Interval.duration(~o"R5/2022-01-01/P1M")

      assert {:error, %ArgumentError{}} = measure(hebrew, ~o"2026-06-15")
      assert {:error, %ArgumentError{}} = measure("2026", ~o"2027")
    end

    test "a recurrence is its occurrences' length however it is written and bounded" do
      {:ok, until} = RRule.parse("FREQ=DAILY;UNTIL=20260620", from: ~o"2026-06-15")

      for recurrence <- [~o"R5/2026-06-15/2026-06-20", ~o"R0/2026-06-15/P1D", until] do
        assert {:error, %Tempo.ConversionError{reason: :recurring_duration}} =
                 Interval.duration(recurrence)
      end

      assert Interval.duration(~o"R/2026-06-15/2026-06-20") == :infinity
    end

    test "a value that is not an interval, or an option it does not take" do
      for value <- [nil, "", :"", 42, ~o"2026-06"] do
        assert {:error, %ArgumentError{}} = Interval.duration(value)
      end

      week = %Interval{from: ~o"2026-06-15", to: ~o"2026-06-22"}

      for options <- [:leap_seconds, [leap_seconds: "yes"], [leap_second: true], [1, 2]] do
        assert {:error, %ArgumentError{}} = Interval.duration(week, options)
      end
    end

    test "a set whose member has no length gives that member's error" do
      {:ok, set} = IntervalSet.new([~o"T09/T11", ~o"T10/T12"])

      assert {:error, %Tempo.UnanchoredError{}} = IntervalSet.duration(set)
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.duration(set)
    end

    test "leap_seconds_spanned/1 and duration/2 counting leap seconds" do
      {:ok, hebrew} = Tempo.from_iso8601("5786-09-30[u-ca=hebrew]")
      across_calendars = %Interval{from: hebrew, to: ~o"2026-06-15"}

      assert {:error, %ArgumentError{}} = Interval.leap_seconds_spanned(across_calendars)

      assert {:error, %Tempo.UnanchoredError{operation: :leap_seconds_spanned}} =
               Interval.leap_seconds_spanned(~o"T09/T17")

      assert {:error, %ArgumentError{}} = Interval.leap_seconds_spanned(nil)
      assert {:error, %ArgumentError{}} = Interval.duration(across_calendars, leap_seconds: true)

      # A predicate has only true and false to give.
      assert_raise ArgumentError, fn -> Interval.spans_leap_second?(across_calendars) end
    end
  end
end
