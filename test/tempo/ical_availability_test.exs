defmodule Tempo.ICal.AvailabilityTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Boundaries
  alias Tempo.ICal
  alias Tempo.IntervalSet

  # Monday the first through Sunday the seventh.
  @week ~o"2026Y6M1D/7D"

  # Office hours, nine to five, Monday 1 June 2026 to Friday the 5th.
  @office_hours """
  BEGIN:VCALENDAR
  VERSION:2.0
  BEGIN:VAVAILABILITY
  UID:office
  DTSTAMP:20260601T000000Z
  DTSTART:20260601T000000Z
  DTEND:20260608T000000Z
  BEGIN:AVAILABLE
  UID:office-available
  DTSTAMP:20260601T000000Z
  DTSTART:20260601T090000Z
  DTEND:20260601T170000Z
  RRULE:FREQ=DAILY;COUNT=5
  END:AVAILABLE
  END:VAVAILABILITY
  END:VCALENDAR
  """

  defp available(calendar, window \\ @week) do
    {:ok, free} = ICal.available(calendar, within: window)
    free
  end

  defp spans(free) do
    free
    |> IntervalSet.members()
    |> Enum.map(fn interval ->
      {Boundaries.from(interval)[:day], Boundaries.from(interval)[:hour],
       Boundaries.to(interval)[:hour]}
    end)
    |> Enum.sort()
  end

  describe "a single VAVAILABILITY" do
    test "one AVAILABLE with no recurrence yields one window" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:once
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        BEGIN:AVAILABLE
        UID:once-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T170000Z
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert spans(free) == [{1, 9, 17}]
    end

    test "an RRULE expands into one window per occurrence" do
      free = available(@office_hours)

      assert spans(free) == [{1, 9, 17}, {2, 9, 17}, {3, 9, 17}, {4, 9, 17}, {5, 9, 17}]
    end

    test "occurrences carry the subcomponent's own span, not a stub" do
      # The bug this guards: materialising a recurrence yields start
      # moments with a one-second span unless DTEND − DTSTART is
      # applied to each occurrence.
      free = available(@office_hours)

      for {_day, from, to} <- spans(free) do
        assert {from, to} == {9, 17}
      end
    end

    test "EXDATE removes an occurrence" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:with-exdate
        DTSTAMP:20260601T000000Z
        BEGIN:AVAILABLE
        UID:with-exdate-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T170000Z
        RRULE:FREQ=DAILY;COUNT=5
        EXDATE:20260603T090000Z
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert spans(free) == [{1, 9, 17}, {2, 9, 17}, {4, 9, 17}, {5, 9, 17}]
    end

    test "several AVAILABLE subcomponents union together" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:split-day
        DTSTAMP:20260601T000000Z
        BEGIN:AVAILABLE
        UID:morning
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T120000Z
        END:AVAILABLE
        BEGIN:AVAILABLE
        UID:afternoon
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T140000Z
        DTEND:20260601T170000Z
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert spans(free) == [{1, 9, 12}, {1, 14, 17}]
    end

    test "DURATION works as an alternative to DTEND" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:by-duration
        DTSTAMP:20260601T000000Z
        BEGIN:AVAILABLE
        UID:by-duration-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DURATION:PT8H
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert spans(free) == [{1, 9, 17}]
    end
  end

  describe "the component's own period bounds what it offers" do
    test "an AVAILABLE recurring past DTEND is clipped to it" do
      # The AVAILABLE repeats for five days, but the component only
      # covers the first three.
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:short-period
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260604T000000Z
        BEGIN:AVAILABLE
        UID:short-period-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T170000Z
        RRULE:FREQ=DAILY;COUNT=5
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert spans(free) == [{1, 9, 17}, {2, 9, 17}, {3, 9, 17}]
    end

    test "an unbounded component is bounded by the query window" do
      free =
        available(
          """
          BEGIN:VCALENDAR
          VERSION:2.0
          BEGIN:VAVAILABILITY
          UID:unbounded
          DTSTAMP:20260601T000000Z
          DTSTART:20260601T000000Z
          DTEND:20260608T000000Z
          BEGIN:AVAILABLE
          UID:unbounded-available
          DTSTAMP:20260601T000000Z
          DTSTART:20260601T090000Z
          DTEND:20260601T170000Z
          RRULE:FREQ=DAILY
          END:AVAILABLE
          END:VAVAILABILITY
          END:VCALENDAR
          """,
          ~o"2026Y6M1D/3D"
        )

      assert spans(free) == [{1, 9, 17}, {2, 9, 17}, {3, 9, 17}]
    end

    test "a component with no AVAILABLE offers nothing" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:busy-all-week
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert IntervalSet.count(free) == 0
    end

    test "a calendar with no VAVAILABILITY asserts nothing" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        END:VCALENDAR
        """)

      assert IntervalSet.count(free) == 0
    end
  end

  describe "PRIORITY resolves overlapping components" do
    # Two components covering the same week. The high-priority one
    # offers mornings; the low-priority one offers whole days. RFC
    # 7953 says the higher priority decides its *whole* period, so the
    # afternoons it does not offer are unavailable — the low-priority
    # component must not fill them in.
    test "the higher priority wins, and its silence means busy" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:high
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        PRIORITY:1
        BEGIN:AVAILABLE
        UID:high-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T120000Z
        END:AVAILABLE
        END:VAVAILABILITY
        BEGIN:VAVAILABILITY
        UID:low
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        PRIORITY:9
        BEGIN:AVAILABLE
        UID:low-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T170000Z
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      # Mornings only — the low-priority afternoon is overridden.
      assert spans(free) == [{1, 9, 12}]
    end

    test "1 outranks 9 regardless of document order" do
      # Same two components, priorities swapped: now the whole day
      # wins because it is the stronger statement.
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:high
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        PRIORITY:9
        BEGIN:AVAILABLE
        UID:high-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T120000Z
        END:AVAILABLE
        END:VAVAILABILITY
        BEGIN:VAVAILABILITY
        UID:low
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        PRIORITY:1
        BEGIN:AVAILABLE
        UID:low-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T170000Z
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert spans(free) == [{1, 9, 17}]
    end

    test "an absent PRIORITY ranks below every explicit one" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:high
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        BEGIN:AVAILABLE
        UID:high-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T120000Z
        END:AVAILABLE
        END:VAVAILABILITY
        BEGIN:VAVAILABILITY
        UID:low
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        PRIORITY:1
        BEGIN:AVAILABLE
        UID:low-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T170000Z
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert spans(free) == [{1, 9, 17}]
    end

    test "PRIORITY:0 also ranks below every explicit one" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:high
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        PRIORITY:0
        BEGIN:AVAILABLE
        UID:high-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T120000Z
        END:AVAILABLE
        END:VAVAILABILITY
        BEGIN:VAVAILABILITY
        UID:low
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        PRIORITY:1
        BEGIN:AVAILABLE
        UID:low-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T170000Z
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert spans(free) == [{1, 9, 17}]
    end

    test "non-overlapping components both contribute" do
      free =
        available("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:first-half
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260603T000000Z
        PRIORITY:1
        BEGIN:AVAILABLE
        UID:first-half-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T120000Z
        END:AVAILABLE
        END:VAVAILABILITY
        BEGIN:VAVAILABILITY
        UID:second-half
        DTSTAMP:20260601T000000Z
        DTSTART:20260603T000000Z
        DTEND:20260608T000000Z
        PRIORITY:2
        BEGIN:AVAILABLE
        UID:second-half-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260603T140000Z
        DTEND:20260603T170000Z
        END:AVAILABLE
        END:VAVAILABILITY
        END:VCALENDAR
        """)

      assert spans(free) == [{1, 9, 12}, {3, 14, 17}]
    end
  end

  describe "the query window" do
    test "clips what is returned" do
      free = available(@office_hours, ~o"2026Y6M2D/3D")

      assert spans(free) == [{2, 9, 17}, {3, 9, 17}]
    end

    test "is required, since an unbounded RRULE cannot be materialised without one" do
      assert {:error, %Tempo.ConversionError{reason: :unbounded}} =
               ICal.available(@office_hours)
    end
  end

  describe "availability and busy time are complements, not variants" do
    test "the same calendar answers both questions" do
      ics =
        """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VAVAILABILITY
        UID:office
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T000000Z
        DTEND:20260608T000000Z
        BEGIN:AVAILABLE
        UID:office-available
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T090000Z
        DTEND:20260601T170000Z
        RRULE:FREQ=DAILY;COUNT=5
        END:AVAILABLE
        END:VAVAILABILITY
        BEGIN:VEVENT
        UID:standup
        DTSTAMP:20260601T000000Z
        DTSTART:20260601T100000Z
        DTEND:20260601T103000Z
        SUMMARY:Standup
        END:VEVENT
        END:VCALENDAR
        """

      assert {:ok, free} = ICal.available(ics, within: @week)
      assert {:ok, busy} = ICal.parse(ics)

      # Open hours come from VAVAILABILITY, claims from VEVENT.
      assert IntervalSet.count(free) == 5
      assert [standup] = IntervalSet.members(busy)
      assert standup.metadata.summary == "Standup"

      # And they compose the way a scheduler needs.
      assert {:ok, bookable} = Tempo.difference(free, busy)
      assert IntervalSet.count(bookable) == 6
    end
  end
end
