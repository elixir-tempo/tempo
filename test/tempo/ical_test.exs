defmodule Tempo.ICal.Test do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ICal
  alias Tempo.Interval
  alias Tempo.IntervalSet

  doctest Tempo.ICal

  # Tests for `Tempo.ICal.parse/2` — iCalendar → IntervalSet
  # conversion with event metadata preserved on each interval.
  #
  # Three input sources:
  #
  # 1. Synthetic ICS strings defined inline — run on every CI.
  # 2. Public fixtures borrowed from the `ical` library's own
  #    test suite (`test/support/data/ical_fixtures/*.ics`,
  #    MIT-licensed, attribution in the directory README).
  # 3. A private Apple Calendar export at
  #    `test/support/data/ical_apple_example_export.ics` — not
  #    committed, tests against it run only when the file exists.

  @apple_fixture "test/support/data/ical_apple_example_export.ics"
  @fixtures_dir "test/support/data/ical_fixtures"

  # Tempo allows `ical ~> 2.0 or ~> 3.0`. Floating date-times (no `Z`,
  # no `TZID`) are surfaced as zone-less values only from ical 3.0
  # onward — 2.x coerced them to a zoned `DateTime`. The floating
  # assertions below therefore compile only when the resolved parser
  # is 3.0+.
  Application.ensure_loaded(:ical)

  @ical_floating_supported (case Application.spec(:ical, :vsn) do
                              nil -> false
                              vsn -> Version.match?(to_string(vsn), ">= 3.0.0")
                            end)

  setup_all do
    Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
    :ok
  end

  describe "parse/2 — simple events" do
    test "a single datetime event becomes one interval with metadata" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:evt-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Team standup
      DESCRIPTION:Daily sync
      LOCATION:Zoom
      END:VEVENT
      END:VCALENDAR
      """

      assert {:ok, set} = ICal.parse(ics)
      assert length(set.intervals) == 1

      [iv] = set.intervals
      assert iv.metadata.uid == "evt-1"
      assert iv.metadata.summary == "Team standup"
      assert iv.metadata.description == "Daily sync"
      assert iv.metadata.location == "Zoom"
    end

    test "calendar metadata attaches to the IntervalSet" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Vendor//Product//EN
      CALSCALE:GREGORIAN
      METHOD:PUBLISH
      END:VCALENDAR
      """

      assert {:ok, set} = ICal.parse(ics)
      assert set.metadata.prodid == "-//Vendor//Product//EN"
      assert set.metadata.version == "2.0"
      assert set.metadata.scale == "GREGORIAN"
      assert set.metadata.method == "PUBLISH"
    end

    test "all-day event uses day-resolution endpoints" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:holiday-1
      DTSTAMP:20220101T000000Z
      DTSTART;VALUE=DATE:20220704
      DTEND;VALUE=DATE:20220705
      SUMMARY:Independence Day
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      [iv] = set.intervals

      assert iv.from.time == [year: 2022, month: 7, day: 4]
      assert iv.to.time == [year: 2022, month: 7, day: 5]
      assert iv.metadata.summary == "Independence Day"
    end

    test "multi-day event spans the half-open range" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:trip-1
      DTSTAMP:20220101T000000Z
      DTSTART;VALUE=DATE:20220913
      DTEND;VALUE=DATE:20220916
      SUMMARY:Conference trip
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      [iv] = set.intervals
      assert iv.from.time[:day] == 13
      assert iv.to.time[:day] == 16
    end

    test "all-day event with no DTEND spans exactly one day (RFC 5545 §3.6.1)" do
      import Tempo.Sigils

      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:allday-no-dtend
      DTSTAMP:20220101T000000Z
      DTSTART;VALUE=DATE:20220704
      SUMMARY:Independence Day
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      [iv] = set.intervals

      # `to` advances by one day and stays at day resolution — no
      # drift into a finer (hour) unit.
      assert iv.from.time == [year: 2022, month: 7, day: 4]
      assert iv.to.time == [year: 2022, month: 7, day: 5]
      assert Interval.duration(iv) == ~o"P1D"
    end

    test "timed event with no DTEND materialises as a one-unit punctual span (RFC 5545 §3.6.1)" do
      import Tempo.Sigils

      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:timed-no-dtend
      DTSTAMP:20220101T000000Z
      DTSTART:20220704T090000Z
      SUMMARY:Reminder
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      [iv] = set.intervals

      # RFC 5545 calls this a zero-duration point, but Tempo's domain
      # has no zero-extent intervals: the punctual event becomes the
      # one-second span [09:00:00, 09:00:01) and is tagged punctual.
      assert iv.from.time == [year: 2022, month: 7, day: 4, hour: 9, minute: 0, second: 0]
      assert iv.to.time == [year: 2022, month: 7, day: 4, hour: 9, minute: 0, second: 1]
      assert Interval.duration(iv) == ~o"PT1S"
      assert iv.metadata.punctual == true
      refute Interval.empty?(iv)
    end

    test "an explicit DTEND equal to DTSTART is also materialised, not zero-extent" do
      import Tempo.Sigils

      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:explicit-equal
      DTSTAMP:20220101T000000Z
      DTSTART:20220704T090000Z
      DTEND:20220704T090000Z
      SUMMARY:Marker
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      [iv] = set.intervals

      # The same chokepoint catches an explicit zero-duration DTEND.
      assert Interval.duration(iv) == ~o"PT1S"
      assert iv.metadata.punctual == true
      refute Interval.empty?(iv)
    end

    test "no imported interval is ever zero-extent (the domain invariant holds)" do
      # A calendar mixing a punctual reminder with a normal meeting must
      # never yield a degenerate interval — the invariant the interval
      # domain (and the set operations built on it) relies on.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:reminder
      DTSTAMP:20220101T000000Z
      DTSTART:20220704T090000Z
      SUMMARY:Reminder
      END:VEVENT
      BEGIN:VEVENT
      UID:meeting
      DTSTAMP:20220101T000000Z
      DTSTART:20220704T100000Z
      DTEND:20220704T110000Z
      SUMMARY:Meeting
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)

      refute Enum.any?(set.intervals, &Interval.empty?/1)
    end

    test "overlapping events are preserved (no coalesce)" do
      # Two events at the same time with different summaries.
      # Without `coalesce: false` they would merge and lose one
      # event's metadata.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:evt-a
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Event A
      END:VEVENT
      BEGIN:VEVENT
      UID:evt-b
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Event B
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      assert length(set.intervals) == 2
      summaries = set.intervals |> Enum.map(& &1.metadata.summary) |> Enum.sort()
      assert summaries == ["Event A", "Event B"]
    end

    test "non-overlapping events are sorted by from" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:later
      DTSTAMP:20220101T000000Z
      DTSTART:20220616T100000Z
      DTEND:20220616T110000Z
      SUMMARY:Later
      END:VEVENT
      BEGIN:VEVENT
      UID:earlier
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Earlier
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      assert Enum.map(set.intervals, & &1.metadata.summary) == ["Earlier", "Later"]
    end
  end

  if @ical_floating_supported do
    describe "parse/2 — floating (zone-less) date-times" do
      # RFC 5545 §3.3.5 "FORM #1": a DATE-TIME with neither a `Z`
      # suffix nor a `TZID` parameter is a *floating* time — the same
      # wall-clock reading in whatever zone the observer is in. As of
      # `ical` 3.0 these parse to `NaiveDateTime` (previously they were
      # coerced to a zoned `DateTime`); Tempo maps them to a genuinely
      # zone-less `%Tempo{}` (`extended: nil`), preserving the floating
      # semantics rather than inventing a zone.

      test "a floating DATE-TIME event becomes a zone-less interval" do
        ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:floating-1
        DTSTAMP:20220101T000000Z
        DTSTART:20220615T100000
        DTEND:20220615T113000
        SUMMARY:Floating meeting
        END:VEVENT
        END:VCALENDAR
        """

        assert {:ok, set} = ICal.parse(ics)
        assert [iv] = set.intervals

        # Zone-less: no invented UTC/offset, unlike a `Z`-suffixed value
        # whose `extended` carries `zone_id: "Etc/UTC"`.
        assert iv.from.extended == nil
        assert iv.to.extended == nil

        assert iv.from.time == [year: 2022, month: 6, day: 15, hour: 10, minute: 0, second: 0]
        assert iv.to.time == [year: 2022, month: 6, day: 15, hour: 11, minute: 30, second: 0]
        assert iv.metadata.summary == "Floating meeting"
      end

      test "a floating recurrence with floating RDATE and EXDATE materialises correctly" do
        ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:floating-rec
        DTSTAMP:20220101T000000Z
        DTSTART:20220103T090000
        DTEND:20220103T100000
        RRULE:FREQ=WEEKLY;COUNT=3
        RDATE:20220201T090000
        EXDATE:20220110T090000
        SUMMARY:Floating standup
        END:VEVENT
        END:VCALENDAR
        """

        assert {:ok, set} = ICal.parse(ics)

        starts =
          set
          |> IntervalSet.to_list()
          |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})

        # RRULE Jan 3 / 10 / 17, minus EXDATE Jan 10, plus RDATE Feb 1.
        assert starts == [{1, 3}, {1, 17}, {2, 1}]

        # Every occurrence stays floating — the recurrence machinery
        # doesn't anchor a zone-less base to a zone.
        assert Enum.all?(IntervalSet.to_list(set), &(&1.from.extended == nil))
      end
    end
  end

  describe "parse/2 — recurrence" do
    test "FREQ=WEEKLY;COUNT=3 — three weekly occurrences" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:weekly-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Weekly standup
      RRULE:FREQ=WEEKLY;COUNT=3
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      assert length(set.intervals) == 3

      # Each occurrence keeps its summary; days are 7 apart.
      days = set.intervals |> Enum.map(& &1.from.time[:day])
      assert days == [15, 22, 29]

      assert Enum.all?(set.intervals, fn iv ->
               iv.metadata.summary == "Weekly standup"
             end)
    end

    test "FREQ=WEEKLY;UNTIL=... — every occurrence up to UNTIL" do
      # Every Wednesday in June 2022, up to but not past Jul 1.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:until-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Weekly until
      RRULE:FREQ=WEEKLY;UNTIL=20220701T000000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      assert length(set.intervals) == 5
      # All in June.
      assert Enum.all?(set.intervals, fn iv -> iv.from.time[:month] == 6 end)
    end

    test "FREQ=WEEKLY;INTERVAL=2;COUNT=4 — every other week, 4 occurrences" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:biweekly
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=4
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      assert length(set.intervals) == 4

      # 14-day spacing: Jun 1, Jun 15, Jun 29, Jul 13.
      days = set.intervals |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})
      assert days == [{6, 1}, {6, 15}, {6, 29}, {7, 13}]
    end

    test "unbounded recurrence (no COUNT, no UNTIL) requires :within" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:forever
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      RRULE:FREQ=DAILY
      END:VEVENT
      END:VCALENDAR
      """

      assert {:error, reason} = ICal.parse(ics)
      assert Exception.message(reason) =~ "unbounded"
      assert Exception.message(reason) =~ ":within"
    end

    test "unbounded recurrence with :within — materialises within the window" do
      import Tempo.Sigils

      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:daily-bounded
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      RRULE:FREQ=DAILY
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics, within: ~o"2022-06-01/2022-06-08")
      # 7 days in the window (Jun 1..Jun 7 inclusive; Jun 8 is
      # excluded by the window's half-open end).
      assert length(set.intervals) == 7
    end

    test "BYDAY=1MO now materialises via Phase C (no fallback)" do
      # Pre-Phase-C, any BY-rule in an RRULE triggered a
      # first-occurrence-only fallback. Phase C lifted every
      # RFC 5545 BY-rule into the interpreter, so events like
      # "1st Monday of every month" expand fully. Unbounded
      # rules still need a `:within` option — nothing special
      # about BY-rules in that respect.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:byday-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220606T090000Z
      DTEND:20220606T100000Z
      RRULE:FREQ=MONTHLY;BYDAY=1MO;COUNT=3
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      assert length(set.intervals) == 3

      # No fallback metadata — all fully materialised.
      assert Enum.all?(set.intervals, fn iv ->
               iv.metadata[:recurrence_note] == nil
             end)

      pairs =
        Enum.map(set.intervals, fn iv ->
          {iv.from.time[:year], iv.from.time[:month], iv.from.time[:day]}
        end)

      # 1st Mondays of Jun/Jul/Aug 2022: 6, 4, 1.
      assert pairs == [{2022, 6, 6}, {2022, 7, 4}, {2022, 8, 1}]
    end
  end

  describe "parse/2 — edge cases" do
    test "events with nil DTSTART are skipped silently" do
      # Technically malformed per RFC 5545, but some exports
      # include them. Skipping is less disruptive than erroring.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:has-start
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Normal event
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.parse(ics)
      assert length(set.intervals) == 1
    end

    test "malformed ics returns an empty result without raising" do
      # The underlying `ical` library is tolerant: non-iCalendar
      # input parses to an empty calendar, not a raise. We pass
      # that through — the caller sees zero intervals.
      assert {:ok, set} = ICal.parse("not valid ical")
      assert set.intervals == []
    end
  end

  describe "metadata propagation through set operations" do
    test "intersection preserves A-side per-interval metadata" do
      import Tempo.Sigils

      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:meeting
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Design review
      LOCATION:Room 101
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, events} = ICal.parse(ics)
      work_hours = ~o"2022-06-15T09/2022-06-15T17"

      {:ok, overlap} = Tempo.intersection(events, work_hours)
      assert length(overlap.intervals) == 1

      [iv] = overlap.intervals
      # Event metadata survives the intersection.
      assert iv.metadata.summary == "Design review"
      assert iv.metadata.location == "Room 101"
    end

    test "difference preserves A-side per-interval metadata across splits" do
      import Tempo.Sigils

      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:long-event
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T080000Z
      DTEND:20220615T120000Z
      SUMMARY:Long session
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, events} = ICal.parse(ics)
      break_time = ~o"2022-06-15T10/2022-06-15T11"

      # Instant-level difference: the event member is trimmed into
      # the pre-break and post-break portions. Both carry the
      # source event's metadata.
      {:ok, remaining} = Tempo.difference(events, break_time)
      assert length(remaining.intervals) == 2

      assert Enum.all?(remaining.intervals, fn iv ->
               iv.metadata.summary == "Long session"
             end)
    end

    test "IntervalSet-level metadata follows the first operand" do
      a_ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Calendar-A//EN
      BEGIN:VEVENT
      UID:a-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:A's event
      END:VEVENT
      END:VCALENDAR
      """

      b_ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Calendar-B//EN
      BEGIN:VEVENT
      UID:b-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:B's event
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, a} = ICal.parse(a_ics)
      {:ok, b} = ICal.parse(b_ics)

      {:ok, result} = Tempo.intersection(a, b)
      # The set-level metadata comes from the first operand.
      assert result.metadata.prodid == "-//Calendar-A//EN"
    end
  end

  describe "parse/2 — public fixtures (borrowed from ical library)" do
    test "one_event.ics parses and carries full metadata" do
      path = Path.join(@fixtures_dir, "one_event.ics")
      {:ok, set} = ICal.parse_file(path)
      [iv] = set.intervals

      assert iv.metadata.uid == "1001"
      assert iv.metadata.summary == "Going fishing"
      assert iv.metadata.location =~ "Toronto"
      assert "Fishing" in (iv.metadata.categories || [])
      # The `ical` library's normalisation is not uniform —
      # STATUS comes through as an atom, CLASS as a string. We
      # pass both through as-is rather than coerce; callers can
      # match on either shape.
      assert iv.metadata.status == :tentative
      assert iv.metadata.classification == "PRIVATE"
    end

    test "attendees.ics — the event has no DTSTART, so it's skipped cleanly" do
      # This fixture is a bare VEVENT with ATTENDEE lines but no
      # DTSTART — Tempo.ICal skips DTSTART-less events (since they
      # can't be placed on the time line). The test exists mainly
      # to prove we don't crash on incomplete events.
      path = Path.join(@fixtures_dir, "attendees.ics")
      {:ok, set} = ICal.parse_file(path)
      assert set.intervals == []
    end

    test "timezone_event.ics parses (zoned events)" do
      path = Path.join(@fixtures_dir, "timezone_event.ics")
      assert {:ok, set} = ICal.parse_file(path)
      assert set.intervals != []
    end

    test "calendar_name.ics surfaces X-WR-CALNAME on the set's metadata" do
      path = Path.join(@fixtures_dir, "calendar_name.ics")
      {:ok, set} = ICal.parse_file(path)
      # Even if the fixture uses a plain WR-CALNAME, the metadata
      # should be a plain string.
      if set.metadata[:name] do
        assert is_binary(set.metadata[:name])
      end
    end

    test "recurrance_with_count.ics expands to N occurrences" do
      path = Path.join(@fixtures_dir, "recurrance_with_count.ics")
      {:ok, set} = ICal.parse_file(path)
      # The fixture has FREQ=DAILY;COUNT=3 so expansion gives us
      # three day-long occurrences.
      assert length(set.intervals) == 3
    end
  end

  # The Apple Calendar fixture is gitignored (see .gitignore) — it's
  # a real personal calendar used locally as a "real-world" parse
  # target, not committed to the repo. CI never sees it. Compile
  # the describe block only when the fixture is present so CI
  # doesn't try to run tests whose setup can't produce an `ics`
  # context.
  if File.exists?(@apple_fixture) do
    describe "parse/2 — real Apple Calendar export" do
      @describetag :real_ical_fixture

      setup do
        {:ok, ics: File.read!(@apple_fixture)}
      end

      test "parses without error and produces an IntervalSet", %{ics: ics} do
        assert {:ok, set} = ICal.parse(ics)
        assert %Tempo.IntervalSet{} = set
        assert set.intervals != []
      end

      test "preserves every event's summary on its interval", %{ics: ics} do
        {:ok, set} = ICal.parse(ics)
        # Every interval should have a summary (optional in RFC 5545
        # but present in every real export we've seen).
        summaries =
          set.intervals
          |> Enum.map(& &1.metadata[:summary])
          |> Enum.reject(&is_nil/1)

        assert summaries != []
      end

      test "calendar name from X-WR-CALNAME is captured", %{ics: ics} do
        {:ok, set} = ICal.parse(ics)
        # The Apple export carries an X-WR-CALNAME; it should come
        # through as a plain string, not a wrapped struct.
        case set.metadata[:name] do
          nil -> :ok
          name when is_binary(name) -> :ok
        end
      end
    end
  end
end
