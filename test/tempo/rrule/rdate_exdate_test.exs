defmodule Tempo.RRule.RdateExdateTest do
  use ExUnit.Case, async: true

  alias Tempo.ICal

  # Phase D — RDATE and EXDATE semantics.
  #
  # RFC 5545 §3.8.5.2 (RDATE) / §3.8.5.1 (EXDATE):
  #
  #   final_occurrences = (expand(rrule) ∪ rdates) − exdates
  #
  # RDATEs add extra occurrences with the event's own span
  # (DTEND − DTSTART). EXDATEs subtract by matching an
  # occurrence's start moment.

  describe "RDATE — additive" do
    test "a single RDATE adds one extra occurrence with the event's duration" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:rdate-single
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Weekly with one extra
      RRULE:FREQ=WEEKLY;COUNT=2
      RDATE:20220618T140000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)

      # 2 RRULE occurrences (Jun 1, Jun 8) + 1 RDATE (Jun 18 14:00).
      assert length(set.intervals) == 3

      pairs =
        Enum.map(set.intervals, fn iv ->
          {iv.from.time[:month], iv.from.time[:day], iv.from.time[:hour]}
        end)

      assert pairs == [{6, 1, 9}, {6, 8, 9}, {6, 18, 14}]
    end

    test "RDATE preserves the event's 1-hour span at its own start time" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:rdate-span
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Span preserved
      RRULE:FREQ=WEEKLY;COUNT=1
      RDATE:20220618T140000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      rdate_iv = Enum.find(set.intervals, fn iv -> iv.from.time[:day] == 18 end)

      # 14:00 + 1 hour = 15:00.
      assert rdate_iv.from.time[:hour] == 14
      assert rdate_iv.to.time[:hour] == 15
    end

    test "multiple RDATEs in one VEVENT" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:rdate-multi
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Several extras
      RRULE:FREQ=WEEKLY;COUNT=1
      RDATE:20220615T140000Z,20220620T100000Z,20220625T170000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      # 1 RRULE + 3 RDATEs.
      assert length(set.intervals) == 4
    end

    test "RDATE occurrences carry the event's metadata" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:rdate-meta
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Design review
      LOCATION:Room 101
      RRULE:FREQ=WEEKLY;COUNT=1
      RDATE:20220615T140000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)

      # Both occurrences carry the same event-level metadata.
      assert Enum.all?(set.intervals, fn iv ->
               iv.metadata.summary == "Design review" and
                 iv.metadata.location == "Room 101"
             end)
    end
  end

  describe "EXDATE — subtractive" do
    test "an EXDATE removes one matching RRULE occurrence" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:exdate-single
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Weekly minus one
      RRULE:FREQ=WEEKLY;COUNT=3
      EXDATE:20220608T090000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)

      # 3 RRULE occurrences, Jun 8 removed → 2 remain (Jun 1, Jun 15).
      assert length(set.intervals) == 2
      days = Enum.map(set.intervals, & &1.from.time[:day])
      assert days == [1, 15]
    end

    test "EXDATEs that don't match any occurrence are harmless" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:exdate-ghost
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Ghost exdate
      RRULE:FREQ=WEEKLY;COUNT=3
      EXDATE:20220704T090000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      # No match → all 3 occurrences survive.
      assert length(set.intervals) == 3
    end

    test "multiple EXDATEs remove multiple occurrences" do
      # RFC 5545 permits both:
      #   * one EXDATE property with comma-separated values
      #   * multiple EXDATE properties
      # The `ical` library we rely on only parses the latter, so
      # we emit one property per value. The downstream subtraction
      # logic is agnostic to which form the source used.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:exdate-multi
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Weekly minus two
      RRULE:FREQ=WEEKLY;COUNT=4
      EXDATE:20220608T090000Z
      EXDATE:20220622T090000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)

      # 4 RRULE occurrences minus Jun 8 and Jun 22 → Jun 1, Jun 15.
      assert length(set.intervals) == 2
      days = Enum.map(set.intervals, & &1.from.time[:day])
      assert days == [1, 15]
    end

    test "EXDATE can also subtract an RDATE (because the union happens first)" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:exdate-removes-rdate
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:EXDATE removes RDATE
      RRULE:FREQ=WEEKLY;COUNT=1
      RDATE:20220618T140000Z
      EXDATE:20220618T140000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)

      # RRULE=Jun 1; RDATE=Jun 18 14:00; EXDATE removes the
      # RDATE. Result: just Jun 1.
      assert length(set.intervals) == 1
      [iv] = set.intervals
      assert iv.from.time[:day] == 1
    end
  end

  describe "combined semantics" do
    test "RRULE ∪ RDATE − EXDATE produces the right chronological set" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:combined
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Full dance
      RRULE:FREQ=WEEKLY;COUNT=3
      RDATE:20220604T100000Z,20220619T120000Z
      EXDATE:20220608T090000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)

      # RRULE: Jun 1, Jun 8, Jun 15.
      # RDATE: + Jun 4 10:00, + Jun 19 12:00.
      # EXDATE: − Jun 8 09:00.
      # Final: Jun 1, Jun 4, Jun 15, Jun 19 (sorted).
      pairs =
        Enum.map(set.intervals, fn iv ->
          {iv.from.time[:day], iv.from.time[:hour]}
        end)

      assert pairs == [{1, 9}, {4, 10}, {15, 9}, {19, 12}]
    end

    test "output is sorted chronologically regardless of input order" do
      # Multiple RDATEs inserted out of order + an EXDATE —
      # output must still be sorted.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:sorted
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Sort check
      RRULE:FREQ=WEEKLY;COUNT=2
      RDATE:20220625T170000Z,20220604T140000Z,20220610T110000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)

      days = Enum.map(set.intervals, & &1.from.time[:day])
      assert days == Enum.sort(days)
    end
  end
end
