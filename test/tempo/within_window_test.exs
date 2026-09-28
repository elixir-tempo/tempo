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
    do: set |> IntervalSet.to_list() |> Enum.map(&Tempo.to_iso8601(Interval.from(&1)))

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

    test "a recurrence set's one-off member outside the window is not among its occurrences" do
      holidays = RecurrenceSet.new([~o"2026-06-15", ~o"R/../P1Y/FL12M25DN"])

      assert starts(Tempo.to_interval_set(holidays, within: ~o"2027")) == ["2027Y12M25D"]
    end

    test "an iCalendar's one-off events outside the window are not returned" do
      calendar =
        ics(
          vevent("in-the-week", "20260616T090000Z", "20260616T100000Z") <>
            vevent("the-week-after", "20260623T090000Z", "20260623T100000Z")
        )

      assert {:ok, events} = ICal.from_ical(calendar, within: ~o"2026-06-15/2026-06-22")
      assert Enum.map(IntervalSet.to_list(events), &Interval.metadata(&1).uid) == ["in-the-week"]
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
               JSCalendar.from_jscalendar(json, within: ~o"2026-06-15/2026-06-22")

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

      assert {:error, %ArgumentError{}} = ICal.from_ical(calendar, bound: ~o"2026")

      assert {:error, %ArgumentError{}} =
               ICal.available_from_ical(calendar, bound: ~o"2026")

      assert {:error, %ArgumentError{}} = JSCalendar.from_jscalendar(json, bound: ~o"2026")

      assert {:error, %ArgumentError{}} =
               Expander.expand(
                 %Rule{freq: :day},
                 ~o"2022-06-01",
                 bound: ~o"2022-06"
               )
    end
  end
end
