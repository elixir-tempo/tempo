defmodule Tempo.Iso8601.OffsetAndZoneTest do
  @moduledoc """
  A time shift and a zone on one value (RFC 9557 §3.4).

  An IXDTF timestamp is an RFC 3339 timestamp with a zone beside it, and
  the two may say different things of the offset from UTC. `Z` says nothing
  of local time (§2.2: "the time in UTC is known, but the offset to local
  time is unknown"), so it never disagrees with a zone, and the value is the
  time in UTC as the zone's clock shows it. A numeric offset says what local
  time is. Where the zone is at another offset on that reading the two
  disagree: a critical zone, or `strict: true`, makes that an error, and
  otherwise the offset gives the moment, which the value holds as the zone's
  clock shows it (decided 2026-10-07).

  The zone was held to give the moment, so `…T00:14:07Z[Europe/Paris]` was
  00:14:07 on Paris's clock, two hours before the time written, and
  `…Z[!Europe/London]` was refused.

  The measure is Elixir's own `DateTime`: the RFC 3339 part is read by
  `DateTime.from_iso8601/1`, and shown in the zone by `DateTime.shift_zone!/2`.
  """
  use ExUnit.Case, async: true

  alias Tempo.Compare
  alias Tempo.Interval

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  # The moment Elixir reads an RFC 3339 timestamp as, on the clock of a zone.
  defp shown(rfc3339, zone) do
    {:ok, moment, _offset} = DateTime.from_iso8601(rfc3339)
    DateTime.shift_zone!(moment, zone)
  end

  # What a value holds, in the terms Elixir's `DateTime` has them: the
  # reading of the clock, the offset from UTC, and the moment.
  defp held(%Tempo{time: time, shift: shift} = value) do
    %{
      reading:
        {{time[:year], time[:month], time[:day]}, {time[:hour], time[:minute], time[:second]}},
      offset: shift && Compare.offset_seconds(shift),
      moment: Compare.to_utc_seconds(value) - @unix_epoch
    }
  end

  defp held(%DateTime{} = shown) do
    %{
      reading: {{shown.year, shown.month, shown.day}, {shown.hour, shown.minute, shown.second}},
      offset: shown.utc_offset + shown.std_offset,
      moment: DateTime.to_unix(shown)
    }
  end

  defp read(text), do: Tempo.from_iso8601!(text)

  describe "a time in UTC beside a zone" do
    @in_utc [
      {"2022-07-08T00:14:07Z", "Europe/Paris"},
      {"2022-07-08T00:14:07Z", "Europe/London"},
      {"2022-01-08T00:14:07Z", "Europe/London"},
      {"2022-07-08T00:14:07Z", "America/New_York"},
      {"2022-07-08T00:14:07Z", "Asia/Kolkata"},
      {"2022-07-08T00:14:07Z", "Australia/Lord_Howe"},
      {"2022-07-08T23:14:07Z", "Pacific/Apia"},
      {"2022-07-08T00:14:07Z", "Etc/UTC"},
      # Each side of New York's clocks going forward, and each showing of
      # the hour they go back through.
      {"2024-03-10T06:59:59Z", "America/New_York"},
      {"2024-03-10T07:00:00Z", "America/New_York"},
      {"2024-03-10T02:30:00Z", "America/New_York"},
      {"2024-11-03T05:30:00Z", "America/New_York"},
      {"2024-11-03T06:30:00Z", "America/New_York"}
    ]

    test "is that time as the zone's clock shows it" do
      for {utc, zone} <- @in_utc do
        text = utc <> "[" <> zone <> "]"

        assert {text, held(read(text))} == {text, held(shown(utc, zone))}
      end
    end

    test "is so for a zero written with a minus, which RFC 3339 had for it" do
      for {utc, zone} <- @in_utc do
        text = String.replace_suffix(utc, "Z", "-00:00") <> "[" <> zone <> "]"

        assert {text, held(read(text))} == {text, held(shown(utc, zone))}
      end
    end

    test "never disagrees with its zone, critical or read strictly" do
      for {utc, zone} <- @in_utc do
        critical = utc <> "[!" <> zone <> "]"
        elective = utc <> "[" <> zone <> "]"

        assert {critical, held(read(critical))} == {critical, held(shown(utc, zone))}

        assert {elective, Tempo.from_iso8601(elective, strict: true)} ==
                 {elective, {:ok, read(elective)}}
      end

      # RFC 9557, Figure 2.
      assert {:ok, _london} = Tempo.from_iso8601("2022-07-08T00:14:07Z[!Europe/London]")
    end

    test "is the two showings of an hour the clocks go back through, told apart" do
      first = read("2024-11-03T05:30:00Z[America/New_York]")
      second = read("2024-11-03T06:30:00Z[America/New_York]")

      assert {Tempo.hour(first), Tempo.minute(first)} == {1, 30}
      assert {Tempo.hour(second), Tempo.minute(second)} == {1, 30}
      assert held(second).moment - held(first).moment == 3_600
      assert {held(first).offset, held(second).offset} == {-4 * 3_600, -5 * 3_600}
    end

    test "keeps its zone as critical as it was written, and is written so" do
      london = read("2022-07-08T00:14:07Z[!Europe/London]")

      assert london.extended.zone_critical
      assert Tempo.to_iso8601!(london) == "2022Y7M8DT1H14M7SZ1H[!Europe/London]"
      assert read(Tempo.to_iso8601!(london)) == london
    end
  end

  describe "a numeric offset beside a zone that is at another" do
    @disagree [
      # Paris is two hours ahead of UTC in July, and New York four behind.
      {"2022-07-08T00:14:07+01:00", "Europe/Paris"},
      {"2022-07-08T00:14:07+00:00", "Europe/London"},
      {"2022-07-08T00:14:07-05:00", "America/New_York"},
      {"2022-01-01T00:00:00+05:00", "America/New_York"},
      {"2022-11-20T10:37:00+05:00", "Europe/Paris"},
      {"2022-07-08T00:14:07+05:45", "Asia/Kolkata"},
      # A reading New York's clock skips, at the offset before the gap and
      # at the offset after it: neither is that reading's, as it has none.
      {"2024-03-10T02:30:00-05:00", "America/New_York"},
      {"2024-03-10T02:30:00-04:00", "America/New_York"},
      # A reading it shows twice, at an offset that is neither's.
      {"2024-11-03T01:30:00+00:00", "America/New_York"}
    ]

    test "gives the moment, which the value holds as the zone's clock shows it" do
      for {timestamp, zone} <- @disagree do
        text = timestamp <> "[" <> zone <> "]"

        assert {text, held(read(text))} == {text, held(shown(timestamp, zone))}
      end
    end

    test "is an error where the zone is critical" do
      for {timestamp, zone} <- @disagree do
        text = timestamp <> "[!" <> zone <> "]"

        assert {text,
                match?(
                  {:error, %error{}}
                  when error in [Tempo.ZoneOffsetMismatchError, Tempo.ZoneGapError],
                  Tempo.from_iso8601(text)
                )} ==
                 {text, true}
      end

      # RFC 9557, Figure 1.
      assert {:error, %Tempo.ZoneOffsetMismatchError{zone_id: "Europe/London", stated_offset: 0}} =
               Tempo.from_iso8601("2022-07-08T00:14:07+00:00[!Europe/London]")
    end

    test "is an error where it is read strictly" do
      for {timestamp, zone} <- @disagree do
        text = timestamp <> "[" <> zone <> "]"

        assert {text,
                match?(
                  {:error, %error{}}
                  when error in [Tempo.ZoneOffsetMismatchError, Tempo.ZoneGapError],
                  Tempo.from_iso8601(text, strict: true)
                )} ==
                 {text, true}
      end
    end

    test "is the value a time in UTC beside the zone is, for an offset of nothing" do
      # ISO 8601-1 §4.3.13 has `Z` and `+00:00` be the one time.
      stated = read("2022-07-08T00:14:07+00:00[Europe/Paris]")
      in_utc = read("2022-07-08T00:14:07Z[Europe/Paris]")

      assert stated.time == in_utc.time
      assert held(stated) == held(in_utc)
    end

    test "is written at the zone's offset, and read as itself" do
      for {timestamp, zone} <- @disagree do
        value = read(timestamp <> "[" <> zone <> "]")

        assert {timestamp, zone, Tempo.validate_zone_offset(value)} == {timestamp, zone, :ok}
        assert {timestamp, zone, read(Tempo.to_iso8601!(value))} == {timestamp, zone, value}
      end
    end
  end

  describe "a numeric offset beside a zone that is at it" do
    test "is the reading as it is written" do
      for {timestamp, zone, reading} <- [
            {"2022-07-08T00:14:07+02:00", "Europe/Paris", {{2022, 7, 8}, {0, 14, 7}}},
            {"2022-07-08T00:14:07+01:00", "Europe/London", {{2022, 7, 8}, {0, 14, 7}}},
            {"2022-01-08T00:14:07+00:00", "Europe/London", {{2022, 1, 8}, {0, 14, 7}}},
            {"2024-11-03T01:30:00-04:00", "America/New_York", {{2024, 11, 3}, {1, 30, 0}}},
            {"2024-11-03T01:30:00-05:00", "America/New_York", {{2024, 11, 3}, {1, 30, 0}}}
          ],
          flag <- ["", "!"] do
        text = timestamp <> "[" <> flag <> zone <> "]"

        assert {text, held(read(text)).reading} == {text, reading}
        assert {text, held(read(text))} == {text, held(shown(timestamp, zone))}
        assert {text, Tempo.from_iso8601(text, strict: true)} == {text, {:ok, read(text)}}
      end
    end
  end

  describe "a zone written as an offset" do
    test "shows the moment a shift that disagrees with it gives" do
      value = read("2022-07-08T00:14:07+01:00[+08:45]")
      {:ok, moment, _offset} = DateTime.from_iso8601("2022-07-08T00:14:07+01:00")

      assert held(value).moment == DateTime.to_unix(moment)
      assert held(value).offset == 8 * 3_600 + 45 * 60
      assert held(value).reading == {{2022, 7, 8}, {7, 59, 7}}
      assert value.extended.zone_offset == 8 * 60 + 45
    end

    test "is an error where it is critical or read strictly, and disagrees" do
      assert {:error, %Tempo.ZoneOffsetMismatchError{zone_id: "+08:45", stated_offset: 3_600}} =
               Tempo.from_iso8601("2022-07-08T00:14:07+01:00[!+08:45]")

      assert {:error, %Tempo.ZoneOffsetMismatchError{}} =
               Tempo.from_iso8601("2022-07-08T00:14:07+01:00[+08:45]", strict: true)
    end

    test "is the reading written where the shift is that offset, or there is none" do
      for text <- [
            "2022-07-08T00:14:07+08:45[+08:45]",
            "2022-07-08T00:14:07+08:45[!+08:45]",
            "2022-07-08T00:14:07[+08:45]",
            "2022-07-08T00:14:07[!+08:45]"
          ] do
        assert {text, held(read(text)).reading} == {text, {{2022, 7, 8}, {0, 14, 7}}}
        assert {text, Tempo.from_iso8601(text, strict: true)} == {text, {:ok, read(text)}}
      end
    end

    test "shows a time in UTC, critical or not" do
      for flag <- ["", "!"] do
        value = read("2022-07-08T00:14:07Z[" <> flag <> "+08:45]")

        assert held(value).reading == {{2022, 7, 8}, {8, 59, 7}}
        assert held(value).moment == DateTime.to_unix(~U[2022-07-08 00:14:07Z])
      end
    end

    test "keeps its critical flag, which is written" do
      for text <- ["2022-07-08T00:14:07[!+08:45]", "2022-07-08T00:14:07+08:45[!+08:45]"] do
        value = read(text)

        assert {text, value.extended.zone_critical} == {text, true}
        assert {text, Tempo.to_iso8601!(value) =~ "[!+08:45]"} == {text, true}
        assert {text, read(Tempo.to_iso8601!(value))} == {text, value}
      end

      refute read("2022-07-08T00:14:07[+08:45]").extended.zone_critical
    end
  end

  describe "a shift of nothing" do
    test "is held as a time in UTC where it is `Z` or is written with a minus" do
      for text <- ["2022-07-08T00:14:07Z", "2022-07-08T00:14:07-00:00", "2022-07-08T00:14:07-00"] do
        assert {text, read(text).shift} == {text, [hour: 0]}
      end

      assert read("2022Y7M8DT0H14M7SZ").shift == [hour: 0]
      assert read("2022Y7M8DT0H14M7SZ-0H").shift == [hour: 0]
    end

    test "is held with its minutes where it says that local time is UTC's" do
      for text <- [
            "2022-07-08T00:14:07+00:00",
            "2022-07-08T00:14:07+00",
            "2022Y7M8DT0H14M7SZ0H",
            "2022Y7M8DT0H14M7SZ0H0M"
          ] do
        assert {text, read(text).shift} == {text, [hour: 0, minute: 0]}
      end
    end

    test "is one time with no zone beside it, whichever way it is written" do
      in_utc = read("2022-07-08T00:14:07Z")

      for text <- [
            "2022-07-08T00:14:07+00:00",
            "2022-07-08T00:14:07-00:00",
            "2022-07-08T00:14:07+00",
            "2022Y7M8DT0H14M7SZ0H0M"
          ] do
        assert {text, Tempo.equal?(read(text), in_utc)} == {text, true}

        assert {text, held(read(text)).moment} ==
                 {text, DateTime.to_unix(~U[2022-07-08 00:14:07Z])}
      end
    end

    test "is read back as it is held" do
      for text <- ["2022-07-08T00:14:07Z", "2022-07-08T00:14:07+00:00"] do
        value = read(text)
        assert {text, read(Tempo.to_iso8601!(value))} == {text, value}
      end
    end
  end

  describe "each end of an interval, and each member of a set" do
    test "is shown on the clock of its zone" do
      interval =
        read("2022-07-08T00:14:07+01:00[Europe/Paris]/2022-07-08T10:14:07+01:00[Europe/Paris]")

      assert held(Interval.from(interval)) ==
               held(shown("2022-07-08T00:14:07+01:00", "Europe/Paris"))

      assert held(Interval.to(interval)) ==
               held(shown("2022-07-08T10:14:07+01:00", "Europe/Paris"))

      assert %Tempo.Set{set: [first, second]} =
               read("{2022-07-08T00:14:07Z,2022-12-09T00:14:07Z}[Europe/Paris]")

      assert held(first) == held(shown("2022-07-08T00:14:07Z", "Europe/Paris"))
      assert held(second) == held(shown("2022-12-09T00:14:07Z", "Europe/Paris"))
    end

    test "is an error where it disagrees with a critical zone, or is read strictly" do
      text = "2022-07-08T00:14:07+02:00[Europe/Paris]/2022-07-08T10:14:07+01:00[!Europe/Paris]"
      assert {:error, %Tempo.ZoneOffsetMismatchError{}} = Tempo.from_iso8601(text)

      elective = String.replace(text, "!", "")
      assert {:ok, %Tempo.Interval{}} = Tempo.from_iso8601(elective)

      assert {:error, %Tempo.ZoneOffsetMismatchError{}} =
               Tempo.from_iso8601(elective, strict: true)
    end
  end

  describe "a value coarser than a second" do
    test "is the value there where the two clocks differ by whole units of it" do
      minute = read("2022-07-08T00:14Z[Asia/Kolkata]")
      assert minute.time == [year: 2022, month: 7, day: 8, hour: 5, minute: 44]

      hour = read("2022-07-08T00Z[Europe/Paris]")
      assert hour.time == [year: 2022, month: 7, day: 8, hour: 2]

      # London is at UTC in January, so a day in UTC is a day there.
      assert read("2022-01-08Z[Europe/London]").time == [year: 2022, month: 1, day: 8]
    end

    test "is the span it is on the zone's clock where they do not" do
      # An hour in UTC is half of one hour and half of the next in Kolkata.
      assert %Tempo.Interval{} = hour = read("2022-07-08T00Z[Asia/Kolkata]")

      assert held_moment(Interval.from(hour)) == DateTime.to_unix(~U[2022-07-08 00:00:00Z])
      assert held_moment(Interval.to(hour)) == DateTime.to_unix(~U[2022-07-08 01:00:00Z])
      assert {Tempo.hour(Interval.from(hour)), Tempo.minute(Interval.from(hour))} == {5, 30}

      # A day in UTC runs from 02:00 to 02:00 on Paris's clock in July.
      assert %Tempo.Interval{} = day = read("2022-07-08Z[Europe/Paris]")

      assert held_moment(Interval.from(day)) == DateTime.to_unix(~U[2022-07-08 00:00:00Z])
      assert held_moment(Interval.to(day)) == DateTime.to_unix(~U[2022-07-09 00:00:00Z])
    end

    defp held_moment(%Tempo{} = value), do: Compare.to_utc_seconds(value) - @unix_epoch
  end

  describe "a value the rule does not reach" do
    test "is left as written where it has no year, and names no moment" do
      assert read("T00:14:07Z[Europe/Paris]").time == [hour: 0, minute: 14, second: 7]
    end

    test "is an error where it names several moments in UTC, which is not built" do
      assert {:error, %Tempo.ConversionError{}} =
               Tempo.from_iso8601("2022-07-{08,09}T00:14:07Z[Europe/Paris]")

      # An offset the zone is at on each of them is read.
      assert {:ok, %Tempo{}} = Tempo.from_iso8601("2022-07-{08,09}T00:14:07+02:00[Europe/Paris]")
    end

    test "is a value with no zone, which is at its shift" do
      for text <- ["2022-07-08T00:14:07+01:00", "2022-07-08T00:14:07Z"] do
        {:ok, moment, _offset} = DateTime.from_iso8601(text)

        assert {text, held(read(text)).moment} == {text, DateTime.to_unix(moment)}
        assert {text, held(read(text)).reading} == {text, {{2022, 7, 8}, {0, 14, 7}}}
      end
    end
  end
end
