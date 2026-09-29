defmodule Tempo.WithinWindowTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.ICal
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.JSCalendar
  alias Tempo.RecurrenceSet
  alias Tempo.RRule
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  # `:within` is the window whose occurrences a caller wants, with one rule
  # for every recurrence and every calendar format: an occurrence is kept when
  # it overlaps the window.

  defp starts({:ok, %IntervalSet{} = set}),
    do: set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!(Interval.from(&1)))

  # A recurrence whose every occurrence spans `duration` from its start, as an
  # iCalendar DTEND and a multi-day holiday carry it.
  defp spanned(recurrence, duration),
    do: %{recurrence | metadata: Map.put(recurrence.metadata, :occurrence_duration, duration)}

  defp ics(events) do
    """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//Test//EN
    #{events}END:VCALENDAR
    """
  end

  defp vevent(uid, dtstart, dtend) do
    """
    BEGIN:VEVENT
    UID:#{uid}
    DTSTAMP:20260101T000000Z
    DTSTART:#{dtstart}
    DTEND:#{dtend}
    END:VEVENT
    """
  end

  describe "every recurrence keeps the occurrences that overlap the window" do
    test "an anchored recurrence keeps the window's occurrences, not all since its start" do
      assert starts(Tempo.to_interval(~o"R/2020-01-01/P1Y", within: ~o"2026")) == ["2026Y1M1D"]
    end

    test "a counted recurrence keeps those of its occurrences that overlap the window" do
      # Each occurrence of `R10/…/P1M` runs one month, so a window starting on
      # the 15th begins exactly where the previous occurrence ends.
      assert starts(Tempo.to_interval(~o"R10/2026-01-15/P1M", within: ~o"2026-03-15/2026-06-15")) ==
               ["2026Y3M15D", "2026Y4M15D", "2026Y5M15D"]
    end

    test "a recurrence with an UNTIL keeps those of its occurrences that overlap the window" do
      {:ok, rule} = RRule.parse("FREQ=MONTHLY;UNTIL=20261231", from: ~o"2026-01-15")

      assert starts(Tempo.to_interval(rule, within: ~o"2026-11-15/2027-02")) ==
               ["2026Y11M15D", "2026Y12M15D"]
    end

    test "an occurrence already in progress when the window opens is kept" do
      assert starts(
               Tempo.to_interval(~o"R/2026-06-14T22/P1W", within: ~o"2026-06-14T22:30/2026-06-15")
             ) == ["2026Y6M14DT22H"]

      # The Christmas break that began in 2026 is among the first week of 2027's.
      assert starts(
               Tempo.to_interval(~o"R/../P1Y/FLL12M21DN/P16DN", within: ~o"2027-01-04/2027-01-11")
             ) == ["2026Y12M21D"]
    end

    test "an occurrence whose span runs into the window from the period before is kept" do
      # A 40-day summer break from 19 December is among 2027's holidays, whether
      # its recurrence has an open start, a domain or an open-ended window.
      summer = spanned(~o"R/../P1Y/FL12M19DN", ~o"P40D")

      assert starts(Tempo.to_interval_set(summer, within: ~o"2027")) ==
               ["2026Y12M19D", "2027Y12M19D"]

      assert starts(
               Tempo.to_interval_set(spanned(~o"R/{2026Y}/P1Y/FL12M19DN", ~o"P40D"),
                 within: ~o"2027"
               )
             ) == ["2026Y12M19D"]

      {:ok, from_2027} = Tempo.to_interval_set(summer, within: ~o"2027/..")
      assert [first | _rest] = from_2027 |> IntervalSet.walk() |> Enum.take(2)
      assert Interval.from(first) == ~o"2026Y12M19D"

      # A monthly one reaches back as many months as its span does, and one that
      # ends before the window opens stays out of it.
      assert starts(
               Tempo.to_interval_set(spanned(~o"R/../P1M/FL20DN", ~o"P40D"), within: ~o"2027-02")
             ) == ["2027Y1M20D", "2027Y2M20D"]

      assert starts(
               Tempo.to_interval_set(spanned(~o"R/../P1Y/FL12M19DN", ~o"P10D"), within: ~o"2027")
             ) == ["2027Y12M19D"]
    end

    test "an occurrence a window moves back from the period after is kept" do
      # The five days before 3 January: 2026's run from 29 December 2025, so they
      # are among 2026's, whether the window is a day, a year or open-ended.
      before_new_year = ~o"R/../P1Y/FLL1M3DN/-P5DN"

      assert starts(Tempo.to_interval_set(before_new_year, within: ~o"2026-01-01/2026-01-02")) ==
               ["2025Y12M29D"]

      assert starts(Tempo.to_interval_set(before_new_year, within: ~o"2026")) ==
               ["2025Y12M29D", "2026Y12M29D"]

      {:ok, from_2026} = Tempo.to_interval_set(before_new_year, within: ~o"2026/..")
      assert [first | _rest] = from_2026 |> IntervalSet.walk() |> Enum.take(2)
      assert Interval.from(first) == ~o"2025Y12M29D"

      # A recurrence with a start of its own reaches as far past the window's end.
      assert starts(Tempo.to_interval_set(~o"R/2020-01-01/P1Y/FLL1M3DN/-P5DN", within: ~o"2026")) ==
               ["2025Y12M29D", "2026Y12M29D"]
    end

    test "a reach of many periods keeps every occurrence it carries into the window" do
      # Two-day sittings every hour at half past: each of the 49 that started from
      # 10:30 two days before is still running within the hour from 10:00.
      sittings = spanned(~o"R/../PT1H/FLT30MN", ~o"P2D")
      {:ok, set} = Tempo.to_interval_set(sittings, within: ~o"2027-01-02T10/2027-01-02T11")

      assert IntervalSet.count(set) == 49
      assert Interval.from(IntervalSet.first(set)) == ~o"2026Y12M31DT10H30M"
    end

    test "the reach steps through the recurrence's own calendar" do
      # Fifteen days from the 25th of each Coptic month: the twelfth month's run
      # through the five days of the thirteenth into the new year's first.
      assert starts(
               Tempo.to_interval_set(~o"R/../P1M/FLL25DN/P15DN[u-ca=coptic]",
                 within: ~o"2026-09-11/2026-09-12"
               )
             ) == ["1742Y12M25D[u-ca=coptic]"]

      # A month from the 25th of every other Coptic month keeps the phase the
      # window's own month sets, as the same rule without a window does: the
      # first month's run, from 5 October.
      early_october = ~o"2026-10-01/2026-10-20"

      assert starts(
               Tempo.to_interval_set(~o"R/../P2M/FLL25DN/P1MN[u-ca=coptic]",
                 within: early_october
               )
             ) == ["1743Y1M25D[u-ca=coptic]"]

      assert starts(
               Tempo.to_interval_set(~o"R/../P2M/FL25DN[u-ca=coptic]", within: early_october)
             ) == ["1743Y1M25D[u-ca=coptic]"]
    end

    test "a cadence finer than a day reaches as far as its occurrences do" do
      # Sittings every hour at half past: one of 90 minutes from 09:30 is still
      # running at 10:00, one of 150 minutes from 08:30 too, and one of 20 is not.
      half_past = ~o"R/../PT1H/FLT30MN"
      ten_to_eleven = ~o"2027-01-02T10/2027-01-02T11"

      assert starts(Tempo.to_interval_set(spanned(half_past, ~o"PT90M"), within: ten_to_eleven)) ==
               ["2027Y1M2DT9H30M", "2027Y1M2DT10H30M"]

      assert starts(Tempo.to_interval_set(spanned(half_past, ~o"PT150M"), within: ten_to_eleven)) ==
               ["2027Y1M2DT8H30M", "2027Y1M2DT9H30M", "2027Y1M2DT10H30M"]

      assert starts(Tempo.to_interval_set(spanned(half_past, ~o"PT20M"), within: ten_to_eleven)) ==
               ["2027Y1M2DT10H30M"]

      # The same sittings as §12.10 windows, and the 90 minutes before each.
      assert starts(Tempo.to_interval_set(~o"R/../PT1H/FLLT30MN/PT90MN", within: ten_to_eleven)) ==
               ["2027Y1M2DT9H30M", "2027Y1M2DT10H30M"]

      assert starts(Tempo.to_interval_set(~o"R/../PT1H/FLLT30MN/-PT90MN", within: ten_to_eleven)) ==
               ["2027Y1M2DT9H0M", "2027Y1M2DT10H0M"]
    end

    test "a week a year numbers reaches into the years either side" do
      # ISO 8601 week 1 of 2026 starts on Monday 29 December 2025, and week 53
      # of 2026 ends on Sunday 3 January 2027.
      december = ~o"2025Y12M"

      for recurrence <- [
            ~o"R/../P1Y/FL1W1KN",
            ~o"R/2020-01-01/P1Y/FL1W1KN",
            ~o"R/{2020Y..2030Y}/P1Y/FL1W1KN"
          ] do
        assert starts(Tempo.to_interval_set(recurrence, within: december)) == ["2025Y12M29D"]
      end

      assert starts(Tempo.to_interval_set(~o"R/../P1Y/FL53W7KN", within: ~o"2027Y1M")) ==
               ["2027Y1M3D"]

      # A whole week is still a week
      {:ok, weeks} = Tempo.to_interval_set(~o"R/../P1Y/FL1WN", within: december)
      assert Enum.map(IntervalSet.members(weeks), &Tempo.to_iso8601!/1) == ["2026Y1W/2W"]
    end

    test "a weekday in a weekly period reaches back to its week's start" do
      # Weekly from Thursday 1 January 2026, on Mondays: the period from
      # Thursday 15 January selects Monday 12 January.
      assert starts(
               Tempo.to_interval_set(~o"R/2026-01-01/P1W/FL1KN",
                 within: ~o"2026-01-01/2026-01-13"
               )
             ) == ["2026Y1M5D", "2026Y1M12D"]
    end

    test "an occurrence's span runs from the time of day its selection picks" do
      # Every night from 22:00 for four hours, the first of them already running
      # when the window opens.
      nights = spanned(~o"R/../P1D/FLT22HN", ~o"PT4H")
      {:ok, set} = Tempo.to_interval_set(nights, within: ~o"2027-01-01/2027-01-03")

      assert set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1) ==
               ["2026Y12M31DT22H/2027Y1M1DT2H", "2027Y1M1DT22H/2DT2H", "2027Y1M2DT22H/3DT2H"]
    end

    test "a recurrence set's one-off member outside the window is not among its occurrences" do
      holidays = RecurrenceSet.new!([~o"2026-06-15", ~o"R/../P1Y/FL12M25DN"])

      assert starts(Tempo.to_interval_set(holidays, within: ~o"2027")) == ["2027Y12M25D"]
    end

    test "an iCalendar's one-off events outside the window are not returned" do
      calendar =
        ics(
          vevent("in-the-week", "20260616T090000Z", "20260616T100000Z") <>
            vevent("the-week-after", "20260623T090000Z", "20260623T100000Z")
        )

      assert {:ok, events} = ICal.parse(calendar, within: ~o"2026-06-15/2026-06-22")
      assert Enum.map(IntervalSet.members(events), &Interval.metadata(&1).uid) == ["in-the-week"]
    end

    test "a JSCalendar event outside the window is not returned" do
      json = ~s({
        "@type": "Event",
        "uid": "review",
        "updated": "2026-06-01T09:00:00Z",
        "start": "2026-06-23T09:00:00",
        "duration": "PT1H"
      })

      assert {:ok, events} =
               JSCalendar.parse(json, within: ~o"2026-06-15/2026-06-22")

      assert IntervalSet.empty?(events)
    end
  end

  describe "a leftover :bound is an error naming :within" do
    test "to_interval/2 and to_interval_set/2" do
      assert {:error, %ArgumentError{message: message}} =
               Tempo.to_interval(~o"R/../P1Y/FL12M25DN", bound: ~o"2026")

      assert message =~ ":within"
      assert {:error, %ArgumentError{}} = Tempo.to_interval_set(~o"2026", bound: ~o"2026")
    end

    test "the set operations and complement/2" do
      assert {:error, %ArgumentError{}} =
               Tempo.intersection(~o"2026-06", ~o"2026-06-15", bound: ~o"2026")

      assert {:error, %ArgumentError{}} =
               Tempo.complement(~o"2026-06-15T12/2026-06-15T13", bound: ~o"2026-06-15")
    end

    test "iCalendar, JSCalendar and the RRULE expander" do
      calendar = ics(vevent("one", "20260616T090000Z", "20260616T100000Z"))

      json =
        ~s({"@type": "Event", "uid": "e", "start": "2026-06-02T09:00:00", "duration": "PT1H"})

      assert {:error, %ArgumentError{}} = ICal.parse(calendar, bound: ~o"2026")

      assert {:error, %ArgumentError{}} =
               ICal.available(calendar, bound: ~o"2026")

      assert {:error, %ArgumentError{}} = JSCalendar.parse(json, bound: ~o"2026")

      assert {:error, %ArgumentError{}} =
               Expander.expand(
                 %Rule{freq: :day},
                 ~o"2022-06-01",
                 bound: ~o"2022-06"
               )
    end
  end
end
