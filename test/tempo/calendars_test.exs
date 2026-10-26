defmodule Tempo.CalendarsTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.FiscalYear
  alias Tempo.{ICal, IntervalSet, JSCalendar, RecurrenceSet}

  # iCalendar, JSCalendar and recurrence sets read through the one
  # occurrences engine (`plans/architecture-redesign.md`, section 18).

  defp texts({:ok, set}), do: IntervalSet.map(set, &Tempo.to_iso8601!/1)

  describe "Tempo.ICal" do
    test "an all-day event is a span of days, written to its last day" do
      assert texts(
               ICal.parse("""
               BEGIN:VCALENDAR
               VERSION:2.0
               PRODID:-//Test//Test//EN
               BEGIN:VEVENT
               UID:event-1
               DTSTAMP:20260101T000000Z
               DTSTART;VALUE=DATE:20260615
               DTEND;VALUE=DATE:20260618
               SUMMARY:Offsite
               END:VEVENT
               END:VCALENDAR
               """)
             ) ==
               ["2026Y6M15D/17D"]

      assert texts(
               ICal.parse("""
               BEGIN:VCALENDAR
               VERSION:2.0
               PRODID:-//Test//Test//EN
               BEGIN:VEVENT
               UID:event-1
               DTSTAMP:20260101T000000Z
               DTSTART;VALUE=DATE:20260615
               END:VEVENT
               END:VCALENDAR
               """)
             ) == [
               "2026Y6M15D/2026Y6M15D"
             ]
    end

    test "a recurring event gives its occurrences, with RDATE added and EXDATE removed" do
      ics =
        """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:event-1
        DTSTAMP:20260101T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T100000Z
        RRULE:FREQ=DAILY;COUNT=4
        EXDATE:20260602T090000Z
        RDATE:20260610T090000Z
        SUMMARY:Standup
        END:VEVENT
        END:VCALENDAR
        """

      {:ok, set} = ICal.parse(ics)
      assert IntervalSet.map(set, &Tempo.day/1) == [1, 3, 4, 10]
      assert IntervalSet.map(set, &Tempo.metadata(&1).summary) |> Enum.uniq() == ["Standup"]
      assert Tempo.metadata(set).prodid == "-//Test//Test//EN"
    end

    test "an endless rule needs a window, and a window keeps what overlaps it" do
      ics =
        """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:event-1
        DTSTAMP:20260101T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T100000Z
        RRULE:FREQ=WEEKLY
        END:VEVENT
        END:VCALENDAR
        """

      assert {:error, %Tempo.ConversionError{reason: :unbounded}} = ICal.parse(ics)
      {:ok, set} = ICal.parse(ics, within: ~o"2026-06-01T00Z/2026-06-16T00Z")
      assert IntervalSet.map(set, &Tempo.day/1) == [1, 8, 15]
    end

    test "a window with no zone is read on each event's clock" do
      ics =
        """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:event-1
        DTSTAMP:20260101T000000Z
        DTSTART;TZID=Europe/London:20260601T093000
        DTEND;TZID=Europe/London:20260601T094500
        RRULE:FREQ=DAILY
        END:VEVENT
        END:VCALENDAR
        """

      {:ok, set} = ICal.parse(ics, within: ~o"2026-06-01/2026-06-02")

      assert texts({:ok, set}) == [
               "2026Y6M1DT9H30M0S/T9H45M0S[Europe/London]",
               "2026Y6M2DT9H30M0S/T9H45M0S[Europe/London]"
             ]
    end

    test "events in several zones are one set in the first's, and one with no zone is placed there" do
      text = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:london
      DTSTAMP:20260101T000000Z
      DTSTART;TZID=Europe/London:20260601T093000
      DTEND;TZID=Europe/London:20260601T094500
      SUMMARY:London
      END:VEVENT
      BEGIN:VEVENT
      UID:new-york
      DTSTAMP:20260101T000000Z
      DTSTART;TZID=America/New_York:20260601T093000
      DTEND;TZID=America/New_York:20260601T094500
      SUMMARY:New York
      END:VEVENT
      BEGIN:VEVENT
      UID:lunch
      DTSTAMP:20260101T000000Z
      DTSTART:20260601T120000
      DTEND:20260601T130000
      SUMMARY:Lunch
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(text)

      assert Tempo.to_iso8601!(set) ==
               "{2026Y6M1DT9H30M0S/T9H45M0S,2026Y6M1DT12H0M0S/T13H0M0S,2026Y6M1DT14H30M0S/T14H45M0S}[Europe/London]"

      assert IntervalSet.map(set, &Tempo.metadata(&1).summary) == ["London", "Lunch", "New York"]
    end

    test "events are busy time that availability is cut by" do
      {:ok, busy} =
        ICal.parse("""
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:event-1
        DTSTAMP:20260101T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T100000Z
        END:VEVENT
        END:VCALENDAR
        """)

      {:ok, free} = Tempo.difference(~o"2026-06-01T08:00:00Z/2026-06-01T12:00:00Z", busy)
      assert texts({:ok, free}) == ["2026Y6M1DT8H0M0SZ/T9H0M0SZ", "2026Y6M1DT10H0M0SZ/T12H0M0SZ"]
    end
  end

  describe "Tempo.JSCalendar" do
    test "a recurring event gives its occurrences in its zone" do
      json = ~s({
        "@type": "Event", "uid": "standup", "updated": "2026-06-01T09:00:00Z", "title": "Standup",
        "start": "2026-06-01T09:00:00", "timeZone": "Europe/Paris", "duration": "PT30M",
        "recurrenceRules": [{"@type": "RecurrenceRule", "frequency": "weekly", "count": 3}]
      })

      {:ok, set} = JSCalendar.parse(json)
      assert IntervalSet.map(set, &Tempo.day/1) == [1, 8, 15]
      assert texts({:ok, set}) |> hd() == "2026Y6M1DT9H0M0S/T9H30M0S[Europe/Paris]"
    end

    test "a task takes no time, and a rule Tempo does not read is an error" do
      task =
        ~s({"@type": "Task", "uid": "t", "updated": "2026-06-01T09:00:00Z", "title": "Do it"})

      assert [] = texts(JSCalendar.parse(task))

      json = ~s({
        "@type": "Event", "uid": "e", "updated": "2026-06-01T09:00:00Z", "start": "2026-06-01T09:00:00",
        "recurrenceRules": [{"@type": "RecurrenceRule", "frequency": "yearly", "rscale": "klingon"}]
      })

      assert {:error, %ArgumentError{message: message}} = JSCalendar.parse(json)
      assert message =~ "RSCALE=KLINGON names no calendar"
    end
  end

  describe "Tempo.RecurrenceSet" do
    test "its occurrences within a window are its members', in time order, each with its metadata" do
      {:ok, holidays} =
        RecurrenceSet.new([
          Tempo.put_metadata(~o"R/2020-01-01/P1Y/FL12M25DN", %{name: "Christmas"}),
          Tempo.put_metadata(~o"R/2020-01-01/P1Y/FL(easter)eN", %{name: "Easter"})
        ])

      {:ok, days} = Tempo.to_interval(holidays, within: ~o"2026")

      assert IntervalSet.map(days, &{Tempo.month(&1), Tempo.day(&1), Tempo.metadata(&1).name}) ==
               [{4, 5, "Easter"}, {12, 25, "Christmas"}]
    end

    test "is the days off of a territory's workdays" do
      {:ok, holidays} = RecurrenceSet.new([~o"R/2020-01-01/P1Y/FL12M25DN"])
      {:ok, workdays} = Tempo.workdays(:US, except: holidays)
      assert Tempo.next_workday(~o"2026-12-24", workdays) == {:ok, ~o"2026-12-28"}
    end

    test "a bridge day is kept only between two holidays" do
      bridge =
        RecurrenceSet.keep_when(~o"2026-09-22",
          at: [~o"-P1D", ~o"P1D"],
          falls_on: %{type: :public}
        )

      {:ok, lone} =
        RecurrenceSet.new([Tempo.put_metadata(~o"2026-09-21", %{type: :public}), bridge])

      assert IntervalSet.map(elem(Tempo.to_interval(lone), 1), &Tempo.day/1) == [21]
    end
  end

  describe "a calendar no name reads back to" do
    test "has no text, where its CLDR type names another calendar" do
      {:ok, fiscal} = FiscalYear.calendar_for(:AU)
      {:ok, quarter} = Tempo.from_elixir(fiscal.quarter(2027, 1))

      assert quarter.calendar == fiscal

      assert {:error, %Tempo.Iso8601EncodeError{reason: {:calendar, ^fiscal}}} =
               Tempo.to_iso8601(quarter)

      assert inspect(quarter) =~ "%Tempo{"

      assert Tempo.to_calendar(quarter, Calendrical.Gregorian) ==
               {:ok, ~o"2026-07-01/2026-09-30[u-ca=gregorian]"}
    end
  end
end
