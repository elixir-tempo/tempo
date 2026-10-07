defmodule Tempo.ZoneValidationTest do
  use ExUnit.Case, async: true

  alias Tempo.Compare
  alias Tempo.Interval

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  doctest Tempo.ZoneOffsetMismatchError

  # Parse-time validation of zoned wall times: during a DST
  # spring-forward, an hour of local time doesn't exist. ISO 8601
  # permits the syntax; Tempo rejects the semantics so downstream
  # operations never encounter a phantom value.
  #
  # The test fixtures use America/New_York because its DST
  # schedule is well-defined in the IANA data and stable:
  #
  #   * Spring forward: second Sunday of March at 02:00 →  03:00.
  #     2024-03-10 02:00..03:00 local doesn't exist.
  #
  #   * Fall back: first Sunday of November at 02:00 → 01:00.
  #     2024-11-03 01:00..02:00 local exists twice (ambiguous).

  describe "zone-aware enumeration (DST gap is skipped)" do
    # A zoned Tempo's enumeration honours its zone: wall-clock
    # hours that don't exist on the date (because the clock
    # jumped over them) are omitted from the enumerated sequence.

    test "enumerating a day that enters DST skips the non-existent hour" do
      import Tempo.Sigils

      # Sydney spring-forward: clocks jump 2026-10-04 02:00 → 03:00.
      # The wall clock never reads 02:00 on this date.
      hours =
        ~o"2026-10-04[Australia/Sydney]"
        |> Enum.take(5)
        |> Enum.map(& &1.time[:hour])

      assert hours == [0, 1, 3, 4, 5]
    end

    test "enumerating a day that enters DST in New York skips the non-existent hour" do
      import Tempo.Sigils

      # 2024-03-10 America/New_York: clocks jump 02:00 → 03:00.
      hours =
        ~o"2024-03-10[America/New_York]"
        |> Enum.take(5)
        |> Enum.map(& &1.time[:hour])

      assert hours == [0, 1, 3, 4, 5]
    end

    test "enumerating a normal day is unaffected" do
      import Tempo.Sigils

      hours =
        ~o"2026-06-15[Australia/Sydney]"
        |> Enum.take(5)
        |> Enum.map(& &1.time[:hour])

      assert hours == [0, 1, 2, 3, 4]
    end

    test "enumerating a day without a zone is unaffected" do
      import Tempo.Sigils

      # No zone attached → no gap information available, enumerate
      # the abstract wall-clock units.
      hours =
        ~o"2026-10-04"
        |> Enum.take(5)
        |> Enum.map(& &1.time[:hour])

      assert hours == [0, 1, 2, 3, 4]
    end
  end

  describe "zone-aware enumeration (DST fold is doubled)" do
    # A wall-clock hour that occurs twice (DST fall-back) is emitted
    # twice — first with the pre-transition offset, then with the
    # post-transition offset. RFC 9557 IXDTF uses the explicit numeric
    # offset to disambiguate folds; the two Tempos round-trip as
    # distinct values and project to distinct UTC instants.

    test "enumerating a day that exits DST emits 02:00 twice with distinct shifts" do
      import Tempo.Sigils

      # Sydney fall-back: clocks go 2026-04-05 03:00 AEDT → 02:00 AEST.
      # The 02:00 hour happens twice — first in AEDT (+11), then AEST (+10).
      values =
        ~o"2026-04-05[Australia/Sydney]"
        |> Enum.take(6)

      hours = Enum.map(values, & &1.time[:hour])
      assert hours == [0, 1, 2, 2, 3, 4]

      [two_a, two_b] = Enum.filter(values, &(&1.time[:hour] == 2))
      assert two_a.shift == [hour: 11]
      assert two_b.shift == [hour: 10]
    end

    test "the two fold occurrences project to distinct UTC instants" do
      import Tempo.Sigils

      [two_a, two_b] =
        ~o"2026-04-05[Australia/Sydney]"
        |> Enum.take(6)
        |> Enum.filter(&(&1.time[:hour] == 2))

      # AEDT (+11) 02:00 ≡ 15:00 UTC; AEST (+10) 02:00 ≡ 16:00 UTC.
      # The second occurrence is exactly 3600 seconds after the first.
      assert Compare.to_utc_seconds(two_b) -
               Compare.to_utc_seconds(two_a) == 3600
    end

    test "the fold occurrences round-trip through the sigil/parser" do
      import Tempo.Sigils

      [two_a, two_b] =
        ~o"2026-04-05[Australia/Sydney]"
        |> Enum.take(6)
        |> Enum.filter(&(&1.time[:hour] == 2))

      # Inspect form encodes the disambiguating shift; re-parsing
      # yields a Tempo with the same shift.
      round_a = Tempo.from_iso8601!(Tempo.to_iso8601!(two_a))
      round_b = Tempo.from_iso8601!(Tempo.to_iso8601!(two_b))
      assert round_a.shift == two_a.shift
      assert round_b.shift == two_b.shift
    end

    test "a day without fold transitions is unaffected" do
      import Tempo.Sigils

      hours =
        ~o"2026-06-15[Australia/Sydney]"
        |> Enum.take(6)
        |> Enum.map(& &1.time[:hour])

      assert hours == [0, 1, 2, 3, 4, 5]
    end
  end

  describe "zone-gap rejection (DST spring-forward)" do
    test "2024-03-10 02:30 America/New_York is rejected" do
      assert {:error, message} =
               Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")

      assert Exception.message(message) =~ "does not exist"
      assert Exception.message(message) =~ "America/New_York"
    end

    test "every minute in the gap is rejected" do
      for minute <- [0, 15, 30, 45, 59] do
        assert {:error, _} =
                 Tempo.from_iso8601("2024-03-10T02:#{pad(minute)}:00[America/New_York]"),
               "Expected 2024-03-10T02:#{pad(minute)} to be rejected"
      end
    end

    test "the error message points at the zone name" do
      assert {:error, message} =
               Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")

      assert Exception.message(message) =~ "\"America/New_York\""
    end
  end

  describe "valid zoned wall times (adjacent to DST gap)" do
    test "01:30 (one minute before the gap) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T01:30:00[America/New_York]")
    end

    test "01:59:59 (immediately before) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T01:59:59[America/New_York]")
    end

    test "03:00 (first valid instant after the gap) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T03:00:00[America/New_York]")
    end

    test "03:30 (in the post-DST hour) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T03:30:00[America/New_York]")
    end
  end

  describe "DST fall-back ambiguity" do
    # Nov 3 2024 at 01:30 exists twice in America/New_York — once
    # at UTC-4 (EDT) before the fall-back, once at UTC-5 (EST)
    # after. Without an explicit disambiguator, Tempo picks the
    # first period (EDT); an explicit offset via `±HH:MM[zone]`
    # picks the matching period per RFC 9557 §4.5.

    test "2024-11-03 01:30 America/New_York parses" do
      assert {:ok, _} = Tempo.from_iso8601("2024-11-03T01:30:00[America/New_York]")
    end

    test "explicit -04:00 picks the EDT (pre-fall-back) period" do
      pre_fb = Tempo.from_iso8601!("2024-11-03T01:30:00-04:00[America/New_York]")
      plain = Tempo.from_iso8601!("2024-11-03T01:30:00[America/New_York]")

      # Same UTC instant as the no-offset default (which also
      # picks EDT as the first period).
      assert Compare.to_utc_seconds(pre_fb) == Compare.to_utc_seconds(plain)
    end

    test "explicit -05:00 picks the EST (post-fall-back) period" do
      post_fb = Tempo.from_iso8601!("2024-11-03T01:30:00-05:00[America/New_York]")
      pre_fb = Tempo.from_iso8601!("2024-11-03T01:30:00-04:00[America/New_York]")

      # One hour later in UTC — the repeated hour.
      assert Compare.to_utc_seconds(post_fb) -
               Compare.to_utc_seconds(pre_fb) == 3600
    end

    test "an offset that is neither of the two gives the moment, shown on the zone's clock" do
      # +00:00 is neither EDT (-04) nor EST (-05), so it disagrees with the
      # zone, and the offset gives the moment (RFC 9557 §3.4, decided
      # 2026-10-07): 01:30 UTC, which New York's clock shows as 21:30 the
      # evening before. It was read as the first 01:30 on that clock.
      read = Tempo.from_iso8601!("2024-11-03T01:30:00+00:00[America/New_York]")

      shown =
        ~D[2024-11-03]
        |> DateTime.new!(~T[01:30:00], "Etc/UTC")
        |> DateTime.shift_zone!("America/New_York")

      assert Compare.to_utc_seconds(read) - @unix_epoch == DateTime.to_unix(shown)
      assert {Tempo.day(read), Tempo.hour(read), Tempo.minute(read)} == {2, 21, 30}
      assert Compare.offset_seconds(read.shift) == shown.utc_offset + shown.std_offset
    end
  end

  describe "check is inert when not applicable" do
    test "no zone → no check" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T02:30:00")
    end

    test "a day that holds a skipped hour is still a day" do
      # `2024-03-10` in New York is the twenty-three hours the clock shows.
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10[America/New_York]")
      assert {:ok, _} = Tempo.from_iso8601("2024-03[America/New_York]")
    end

    test "numeric-offset zones (not IANA) → no check" do
      # `+05:30` isn't an IANA zone — no zone-database lookup possible,
      # and the offset is a first-class wall-clock shift.
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T02:30:00+05:30")
    end
  end

  describe "IANA backward-compat aliases" do
    # The IANA data carries the `backward` alias file which maps
    # retired/renamed zone names to their modern equivalents.
    # Tempo accepts these transparently — the alias label is
    # preserved on the struct; `to_utc_seconds/1` resolves via
    # the zone database using the alias's canonical zone.

    test "US/Pacific parses and round-trips" do
      assert {:ok, tempo} = Tempo.from_iso8601("2024-06-15T12:00:00[US/Pacific]")
      assert tempo.extended.zone_id == "US/Pacific"
      # Offset matches America/Los_Angeles (the canonical zone).
      assert is_integer(Compare.to_utc_seconds(tempo))
    end

    test "Asia/Calcutta (renamed to Asia/Kolkata) parses" do
      assert {:ok, _} = Tempo.from_iso8601("2024-06-15T12:00:00[Asia/Calcutta]")
    end

    test "Pacific/Kanton (renamed from Pacific/Enderbury) parses" do
      assert {:ok, _} = Tempo.from_iso8601("2024-06-15T12:00:00[Pacific/Kanton]")
    end
  end

  describe "historical zone offsets" do
    test "Europe/London during British Double Summer Time (1941) projects to UTC+2" do
      # BDST applied 1941-05-04 to 1945-07-15 — clocks ran 2h
      # ahead of UTC instead of the usual 1h summer offset. A
      # correct implementation must consult the zone database's historical
      # period table rather than today's offset.
      {:ok, london} = Tempo.from_iso8601("1941-06-15T12:00:00[Europe/London]")
      {:ok, utc} = Tempo.from_iso8601("1941-06-15T12:00:00Z")

      # London wall = UTC wall + 2h, so London's UTC projection
      # is 2h earlier than the same wall-clock at UTC.
      diff = Compare.to_utc_seconds(utc) - Compare.to_utc_seconds(london)
      assert diff == 7200
    end
  end

  describe "exact DST gap boundary seconds" do
    test "02:00:00 (first instant of the gap) is rejected" do
      assert {:error, _} = Tempo.from_iso8601("2024-03-10T02:00:00[America/New_York]")
    end

    test "02:59:59 (last instant of the gap) is rejected" do
      assert {:error, _} = Tempo.from_iso8601("2024-03-10T02:59:59[America/New_York]")
    end

    test "01:59:59 (last valid instant before the gap) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T01:59:59[America/New_York]")
    end

    test "03:00:00 (first valid instant after the gap) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T03:00:00[America/New_York]")
    end
  end

  # A value names a time in its zone. One whose every reading the clock
  # skips names none and is refused (decided 2026-10-06): a minute or a
  # second in the gap, the hour a spring-forward skips, and a day a zone
  # leaves out. The hour and the day were read, and ordered by their fields:
  # the skipped hour in Paris was "finished by" the hour after it.
  #
  # The measure is Elixir's own lookup of the first and the last reading
  # the value spans: it is skipped whole where one gap holds both.
  describe "a value the clock skips the whole of" do
    import Tempo.Sigils

    defp gap(%NaiveDateTime{} = reading, zone) do
      case DateTime.from_naive(reading, zone) do
        {:gap, just_before, just_after} -> {just_before, just_after}
        _shown -> nil
      end
    end

    defp skipped_whole?(first, last, zone),
      do: gap(first, zone) != nil and gap(first, zone) == gap(last, zone)

    @spans [
      # The hour a spring-forward skips.
      {"2026-03-29T02[Europe/Paris]", ~N[2026-03-29 02:00:00], ~N[2026-03-29 02:59:59],
       "Europe/Paris"},
      {"2024-03-10T02[America/New_York]", ~N[2024-03-10 02:00:00], ~N[2024-03-10 02:59:59],
       "America/New_York"},
      # Clocks went forward at midnight in Cairo: the first hour of the day.
      {"2023-04-28T00[Africa/Cairo]", ~N[2023-04-28 00:00:00], ~N[2023-04-28 00:59:59],
       "Africa/Cairo"},
      # Samoa left out 30 December 2011, and Manila 31 December 1844.
      {"2011-12-30[Pacific/Apia]", ~N[2011-12-30 00:00:00], ~N[2011-12-30 23:59:59],
       "Pacific/Apia"},
      {"2011-12-30T12[Pacific/Apia]", ~N[2011-12-30 12:00:00], ~N[2011-12-30 12:59:59],
       "Pacific/Apia"},
      {"1844-12-31[Asia/Manila]", ~N[1844-12-31 00:00:00], ~N[1844-12-31 23:59:59],
       "Asia/Manila"},
      # Skipped in part, or not at all.
      {"2026-10-04T02[Australia/Lord_Howe]", ~N[2026-10-04 02:00:00], ~N[2026-10-04 02:59:59],
       "Australia/Lord_Howe"},
      {"2023-04-28[Africa/Cairo]", ~N[2023-04-28 00:00:00], ~N[2023-04-28 23:59:59],
       "Africa/Cairo"},
      {"2024-03-10[America/New_York]", ~N[2024-03-10 00:00:00], ~N[2024-03-10 23:59:59],
       "America/New_York"},
      {"2024-03-10T01[America/New_York]", ~N[2024-03-10 01:00:00], ~N[2024-03-10 01:59:59],
       "America/New_York"},
      {"2024-03-10T03[America/New_York]", ~N[2024-03-10 03:00:00], ~N[2024-03-10 03:59:59],
       "America/New_York"},
      {"2011-12-29[Pacific/Apia]", ~N[2011-12-29 00:00:00], ~N[2011-12-29 23:59:59],
       "Pacific/Apia"},
      {"2011-12-31[Pacific/Apia]", ~N[2011-12-31 00:00:00], ~N[2011-12-31 23:59:59],
       "Pacific/Apia"}
    ]

    test "is refused when it is read, and one the clock shows any of is read" do
      for {text, first, last, zone} <- @spans do
        refused = match?({:error, %Tempo.ZoneGapError{}}, Tempo.from_iso8601(text))

        assert {text, refused} == {text, skipped_whole?(first, last, zone)}
      end
    end

    test "is six of the spans above" do
      skipped =
        for {text, first, last, zone} <- @spans, skipped_whole?(first, last, zone), do: text

      assert skipped == [
               "2026-03-29T02[Europe/Paris]",
               "2024-03-10T02[America/New_York]",
               "2023-04-28T00[Africa/Cairo]",
               "2011-12-30[Pacific/Apia]",
               "2011-12-30T12[Pacific/Apia]",
               "1844-12-31[Asia/Manila]"
             ]
    end

    test "is refused by new/1 and in_zone/2, as it is when read" do
      assert {:error, %Tempo.ZoneGapError{}} =
               Tempo.new(year: 2024, month: 3, day: 10, hour: 2, zone: "America/New_York")

      assert {:error, %Tempo.ZoneGapError{}} =
               Tempo.new(
                 year: 2024,
                 month: 3,
                 day: 10,
                 hour: 2,
                 minute: 30,
                 zone: "America/New_York"
               )

      assert {:error, %Tempo.ZoneGapError{}} =
               Tempo.new(year: 2011, month: 12, day: 30, zone: "Pacific/Apia")

      assert {:error, %Tempo.ZoneGapError{}} =
               Tempo.in_zone(~o"2024-03-10T02", "America/New_York")

      assert {:error, %Tempo.ZoneGapError{}} =
               Tempo.in_zone(~o"2024-03-10T02:30", "America/New_York")

      assert {:error, %Tempo.ZoneGapError{}} = Tempo.in_zone(~o"2011-12-30", "Pacific/Apia")

      assert {:ok, _hour} =
               Tempo.new(year: 2024, month: 3, day: 10, hour: 3, zone: "America/New_York")

      assert {:ok, _day} = Tempo.in_zone(~o"2024-03-10", "America/New_York")
    end

    test "is refused by at/2 and on/2, as it is when read" do
      day = ~o"2024-03-10[America/New_York]"

      assert {:error, %Tempo.ZoneGapError{}} = Tempo.at(day, ~o"T02")
      assert {:error, %Tempo.ZoneGapError{}} = Tempo.at(day, ~o"T02:30")
      assert {:error, %Tempo.ZoneGapError{}} = Tempo.on(~o"T02:30", day)
      assert {:error, %Tempo.ZoneGapError{}} = Tempo.on(~o"30D", ~o"2011-12[Pacific/Apia]")

      # An interval is placed end by end.
      assert {:error, %Tempo.ZoneGapError{}} = Tempo.on(~o"T02/T05", day)

      assert {:ok, _hour} = Tempo.at(day, ~o"T03")
      assert {:ok, _minute} = Tempo.at(day, ~o"T01:30")
      assert {:ok, _span} = Tempo.on(~o"T03/T05", day)
      assert {:ok, _day} = Tempo.on(~o"29D", ~o"2011-12[Pacific/Apia]")
    end

    test "is refused at an end of an interval and as a member of a set" do
      for text <- [
            "2024-03-10T02[America/New_York]/2024-03-10T05[America/New_York]",
            "2011-12-30/2011-12-31[Pacific/Apia]",
            "{2011-12-29,2011-12-30}[Pacific/Apia]"
          ] do
        assert {^text, {:error, %Tempo.ZoneGapError{}}} = {text, Tempo.from_iso8601(text)}
      end

      assert {:ok, _days} = Tempo.from_iso8601("2011-12-29/2011-12-31[Pacific/Apia]")
    end

    test "is named as it is written, with its zone" do
      for {text, written} <- [
            {"2024-03-10T02[America/New_York]", "2024-03-10T02"},
            {"2024-03-10T02:30[America/New_York]", "2024-03-10T02:30:00"},
            {"2011-12-30[Pacific/Apia]", "2011-12-30"}
          ] do
        assert {:error, %Tempo.ZoneGapError{wall_time: ^written} = error} =
                 Tempo.from_iso8601(text)

        assert Exception.message(error) =~ "Wall time #{written} does not exist"
      end
    end

    test "is left out of the walk of a set of hours that names it" do
      {:ok, hours} = Tempo.from_iso8601("2024-03-10T{01,02,03}[America/New_York]")

      assert Enum.map(hours, &Tempo.hour/1) == [1, 3]
    end
  end

  # A value the clock skips part of is some time: the hour of a half-hour
  # change, and the day or the month whose first hour is skipped, where
  # clocks go forward at midnight. Its first reading had no offset to be
  # read with and was taken as UTC, so a day in Cairo started two hours late.
  # It is read with the offset before the gap (RFC 5545 §3.3.5), which is
  # the time the clock shows that long after it changed.
  describe "a value the clock skips the start of" do
    import Tempo.Sigils

    # The instant of a skipped reading, read with the offset before the gap,
    # from Elixir's own lookup and none of Tempo's.
    defp before_the_gap(%NaiveDateTime{} = reading, zone) do
      {:gap, just_before, _just_after} = DateTime.from_naive(reading, zone)
      {seconds, _microseconds} = NaiveDateTime.to_gregorian_seconds(reading)

      seconds - just_before.utc_offset - just_before.std_offset
    end

    test "is read with the offset before the gap" do
      for {text, reading, zone} <- [
            # Lord Howe Island goes forward half an hour, from 02:00 to 02:30.
            {"2026-10-04T02[Australia/Lord_Howe]", ~N[2026-10-04 02:00:00],
             "Australia/Lord_Howe"},
            # Clocks went forward at midnight: a day and a month start in the gap.
            {"2023-04-28[Africa/Cairo]", ~N[2023-04-28 00:00:00], "Africa/Cairo"},
            {"2023-10[America/Asuncion]", ~N[2023-10-01 00:00:00], "America/Asuncion"}
          ] do
        assert {text, Compare.to_utc_seconds(Tempo.from_iso8601!(text))} ==
                 {text, before_the_gap(reading, zone)}
      end
    end

    test "starts a day whose first hour is skipped when the clock changes" do
      {:gap, _just_before, first_reading} =
        DateTime.from_naive(~N[2023-04-28 00:00:00], "Africa/Cairo")

      an_hour_on = DateTime.add(first_reading, 1, :hour)

      assert Tempo.shift(~o"2023-04-28[Africa/Cairo]", hour: 1) ==
               Tempo.from_iso8601!("2023Y4M28DT#{an_hour_on.hour}H[Africa/Cairo]")

      # The day is its twenty-three hours, and follows the day before it.
      {:ok, day} = Tempo.to_interval(~o"2023-04-28[Africa/Cairo]")

      assert Compare.to_utc_seconds(Interval.to(day)) - Compare.to_utc_seconds(Interval.from(day)) ==
               23 * 3600

      assert Enum.count(~o"2023-04-28[Africa/Cairo]") == 23
      assert Tempo.relation(~o"2023-04-27[Africa/Cairo]", ~o"2023-04-28[Africa/Cairo]") == :meets
    end
  end

  describe "numeric offset bounds — reject nonsensical offsets" do
    # Real UTC offsets are bounded. The widest modern zone is
    # +14:00 (Pacific/Kiritimati) and the narrowest is −12:00
    # (Pacific/Midway until 2011, and a few others).  ±24h is a
    # permissive bound that rejects clear nonsense like +25:00.

    test "+25:00 inline is rejected" do
      assert {:error, message} = Tempo.from_iso8601("2024-03-10T12:00:00+25:00")
      assert Exception.message(message) =~ "out of range"
    end

    test "-25:00 inline is rejected" do
      assert {:error, message} = Tempo.from_iso8601("2024-03-10T12:00:00-25:00")
      assert Exception.message(message) =~ "out of range"
    end

    test "+14:00 inline (Pacific/Kiritimati) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00+14:00")
    end

    test "-12:00 inline is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00-12:00")
    end

    test "+24:00 (the boundary) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00+24:00")
    end

    test "Z (UTC) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00Z")
    end

    test "IXDTF [+25:00] is rejected" do
      assert {:error, message} = Tempo.from_iso8601("2024-03-10T12:00:00[+25:00]")
      assert Exception.message(message) =~ "out of range"
    end

    test "IXDTF [+14:00] is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00[+14:00]")
    end
  end

  describe "zone-gap check applies recursively to intervals" do
    test "interval with gap endpoint is rejected" do
      assert {:error, _} =
               Tempo.from_iso8601(
                 "2024-03-10T02:30:00[America/New_York]/2024-03-10T05:00:00[America/New_York]"
               )
    end

    test "interval with both valid endpoints is accepted" do
      assert {:ok, _} =
               Tempo.from_iso8601(
                 "2024-03-10T01:30:00[America/New_York]/2024-03-10T05:00:00[America/New_York]"
               )
    end
  end

  describe "duration correctness across DST (no bug to fix; guard test)" do
    # These tests assert that `Tempo.Interval.duration/1` already
    # accounts for DST transitions via `to_utc_seconds/1` —
    # protecting against future regressions.

    test "24 wall-clock hours across spring-forward = 23 real hours" do
      from = Tempo.from_iso8601!("2024-03-09T12:00:00[America/New_York]")
      to = Tempo.from_iso8601!("2024-03-10T12:00:00[America/New_York]")
      iv = %Tempo.Interval{from: from, to: to}

      # 23h = 82800s. The hour between 02:00 and 03:00 was skipped.
      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 82_800]}
    end

    test "24 wall-clock hours across fall-back = 25 real hours" do
      from = Tempo.from_iso8601!("2024-11-02T12:00:00[America/New_York]")
      to = Tempo.from_iso8601!("2024-11-03T12:00:00[America/New_York]")
      iv = %Tempo.Interval{from: from, to: to}

      # 25h = 90000s. The hour between 01:00 and 02:00 was repeated.
      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 90_000]}
    end

    test "24 wall-clock hours outside any transition = 24 real hours" do
      from = Tempo.from_iso8601!("2024-06-15T12:00:00[America/New_York]")
      to = Tempo.from_iso8601!("2024-06-16T12:00:00[America/New_York]")
      iv = %Tempo.Interval{from: from, to: to}

      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 86_400]}
    end

    test "unzoned interval ignores zone math" do
      from = Tempo.from_iso8601!("2024-03-09T12:00:00")
      to = Tempo.from_iso8601!("2024-03-10T12:00:00")
      iv = %Tempo.Interval{from: from, to: to}

      # No zone → plain wall-clock delta of 24h.
      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 86_400]}
    end
  end

  describe "IXDTF offset/zone consistency (strict mode, RFC 9557 §3.4)" do
    test "validate_zone_offset accepts an offset that matches the zone" do
      {:ok, t} = Tempo.from_iso8601("2022-11-20T10:37:00+01:00[Europe/Paris]")
      assert Tempo.validate_zone_offset(t) == :ok
    end

    test "validate_zone_offset flags an offset that disagrees with the zone" do
      # A value read from text is at its zone's offset once it is read, so
      # one that holds a disagreement is made of its parts.
      {:ok, t} =
        Tempo.new(
          year: 2022,
          month: 11,
          day: 20,
          hour: 10,
          minute: 37,
          second: 0,
          shift: [hour: 5],
          zone: "Europe/Paris"
        )

      assert {:error, %Tempo.ZoneOffsetMismatchError{} = error} = Tempo.validate_zone_offset(t)
      assert error.zone_id == "Europe/Paris"
      assert error.stated_offset == 5 * 3600
      assert error.zone_offsets == [3600]
      assert Exception.message(error) =~ "+05:00 disagrees with"
    end

    test "strict: true rejects the inconsistent value at parse time" do
      assert {:error, %Tempo.ZoneOffsetMismatchError{}} =
               Tempo.from_iso8601("2022-11-20T10:37:00+05:00[Europe/Paris]", strict: true)
    end

    test "strict: true accepts a consistent value" do
      assert {:ok, %Tempo{}} =
               Tempo.from_iso8601("2022-11-20T10:37:00+01:00[Europe/Paris]", strict: true)
    end

    test "from_iso8601! with strict: true raises on disagreement" do
      assert_raise Tempo.ZoneOffsetMismatchError, fn ->
        Tempo.from_iso8601!("2022-11-20T10:37:00+05:00[Europe/Paris]", strict: true)
      end
    end

    test "the default (non-strict) still accepts an inconsistent value" do
      assert {:ok, %Tempo{}} = Tempo.from_iso8601("2022-11-20T10:37:00+05:00[Europe/Paris]")
    end

    test "a DST fall-back offset disambiguates rather than disagrees" do
      # 2024-11-03 01:30 New York occurs twice; both the pre-fall-back
      # (EDT, -04:00) and post-fall-back (EST, -05:00) offsets are valid.
      {:ok, edt} = Tempo.from_iso8601("2024-11-03T01:30:00-04:00[America/New_York]")
      {:ok, est} = Tempo.from_iso8601("2024-11-03T01:30:00-05:00[America/New_York]")
      assert Tempo.validate_zone_offset(edt) == :ok
      assert Tempo.validate_zone_offset(est) == :ok
    end

    test "nothing to check: zone without an offset, or offset without a zone" do
      assert Tempo.validate_zone_offset(Tempo.from_iso8601!("2022-11-20T10:37:00[Europe/Paris]")) ==
               :ok

      assert Tempo.validate_zone_offset(Tempo.from_iso8601!("2022-11-20T10:37:00+05:00")) == :ok
    end

    test "calendar and strict options compose (both honored)" do
      # `:calendar` swaps the calendar; `strict: true` has nothing to
      # check here (an offset with no zone), so both apply cleanly.
      assert {:ok, %Tempo{calendar: Calendrical.Hebrew}} =
               Tempo.from_iso8601("5786-09-30T10:37:00+02:00",
                 calendar: Calendrical.Hebrew,
                 strict: true
               )
    end
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"
end
