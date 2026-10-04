defmodule Tempo.ShiftZoneTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare

  describe "Tempo.shift_zone/2" do
    test "Paris 14:00 → New York is 08:00 EDT in June" do
      paris = Tempo.from_iso8601!("2026-06-15T14:00:00[Europe/Paris]")
      {:ok, ny} = Tempo.shift_zone(paris, "America/New_York")

      assert ny.extended.zone_id == "America/New_York"

      assert Keyword.take(ny.time, [:year, :month, :day, :hour, :minute]) ==
               [year: 2026, month: 6, day: 15, hour: 8, minute: 0]
    end

    test "round-trips via UTC: Paris → UTC → Paris returns same wall time" do
      original = Tempo.from_iso8601!("2026-06-15T14:00:00[Europe/Paris]")
      {:ok, utc} = Tempo.shift_zone(original, "Etc/UTC")
      {:ok, back} = Tempo.shift_zone(utc, "Europe/Paris")

      assert back.extended.zone_id == "Europe/Paris"

      assert Keyword.take(back.time, [:year, :month, :day, :hour, :minute]) ==
               [year: 2026, month: 6, day: 15, hour: 14, minute: 0]
    end

    test "preserves the UTC instant across projections" do
      original = Tempo.from_iso8601!("2026-06-15T14:00:00[Europe/Paris]")
      {:ok, ny} = Tempo.shift_zone(original, "America/New_York")

      assert Compare.to_utc_seconds(original) ==
               Compare.to_utc_seconds(ny)
    end

    test "crosses the date line: Tokyo 07:30 on the 16th is previous-day UTC" do
      tokyo = Tempo.from_iso8601!("2026-06-16T07:30:00[Asia/Tokyo]")
      {:ok, utc} = Tempo.shift_zone(tokyo, "Etc/UTC")

      assert Keyword.take(utc.time, [:year, :month, :day, :hour, :minute]) ==
               [year: 2026, month: 6, day: 15, hour: 22, minute: 30]
    end

    test "shifts a UTC-anchored Tempo into a named zone" do
      utc = Tempo.from_iso8601!("2026-06-15T12:00:00Z")
      {:ok, paris} = Tempo.shift_zone(utc, "Europe/Paris")

      assert paris.extended.zone_id == "Europe/Paris"
      # June = CEST = UTC+2.
      assert Keyword.get(paris.time, :hour) == 14
    end

    test "rejects a floating Tempo" do
      floating = Tempo.from_iso8601!("2026-06-15T14:00:00")

      assert {:error, %Tempo.FloatingTempoError{operation: :shift_zone}} =
               Tempo.shift_zone(floating, "Europe/Paris")
    end

    test "rejects an unanchored Tempo" do
      non_anchored = %Tempo{time: [hour: 10, minute: 30, second: 0]}

      assert {:error, %Tempo.UnanchoredError{operation: :shift_zone}} =
               Tempo.shift_zone(non_anchored, "Europe/Paris")
    end

    test "returns an error for an unknown zone" do
      paris = Tempo.from_iso8601!("2026-06-15T14:00:00[Europe/Paris]")

      assert {:error, %Tempo.UnknownZoneError{zone_id: "Moon/Tranquility"}} =
               Tempo.shift_zone(paris, "Moon/Tranquility")
    end
  end

  describe "Tempo.shift_zone/2 keeps the value's calendar" do
    test "1 Tishri 5787 at 10:00 in Jerusalem is 07:00 that day in UTC" do
      jerusalem = Tempo.from_iso8601!("5787-01-01T10:00:00[Asia/Jerusalem][u-ca=hebrew]")
      {:ok, utc} = Tempo.shift_zone(jerusalem, "Etc/UTC")

      assert utc.calendar == Calendrical.Hebrew

      assert Keyword.take(utc.time, [:year, :month, :day, :hour, :minute]) ==
               [year: 5787, month: 1, day: 1, hour: 7, minute: 0]

      assert Compare.to_utc_seconds(utc) == Compare.to_utc_seconds(jerusalem)
    end

    test "its ISO 8601 form reads back as the same instant in the same calendar" do
      jerusalem = Tempo.from_iso8601!("5787-01-01T10:00:00[Asia/Jerusalem][u-ca=hebrew]")
      {:ok, paris} = Tempo.shift_zone(jerusalem, "Europe/Paris")
      read_back = paris |> Tempo.to_iso8601!() |> Tempo.from_iso8601!()

      assert read_back.calendar == Calendrical.Hebrew
      assert Compare.to_utc_seconds(read_back) == Compare.to_utc_seconds(jerusalem)
    end

    test "a day that starts the evening before in UTC runs from that evening's date" do
      # Midnight starting 1 Tishri in Jerusalem is 21:00 UTC on 29 Elul 5786,
      # and the day runs to 21:00 on 1 Tishri.
      new_year = Tempo.from_iso8601!("5787-01-01[Asia/Jerusalem][u-ca=hebrew]")
      {:ok, utc} = Tempo.shift_zone(new_year, "Etc/UTC")

      assert Keyword.take(utc.from.time, [:year, :month, :day, :hour]) ==
               [year: 5786, month: 12, day: 29, hour: 21]

      assert Keyword.take(utc.to.time, [:year, :month, :day, :hour]) ==
               [year: 5787, month: 1, day: 1, hour: 21]
    end

    test "a half-hour zone, an offset and a lunar calendar" do
      tehran = Tempo.from_iso8601!("1405-06-20T10:00:00[Asia/Tehran][u-ca=persian]")
      {:ok, utc} = Tempo.shift_zone(tehran, "Etc/UTC")

      assert {utc.calendar, Keyword.take(utc.time, [:month, :day, :hour, :minute])} ==
               {Calendrical.Persian, [month: 6, day: 20, hour: 6, minute: 30]}

      offset = Tempo.from_iso8601!("5787-01-01T10:00:00+03:00[u-ca=hebrew]")
      {:ok, paris} = Tempo.shift_zone(offset, "Europe/Paris")

      assert Keyword.take(paris.time, [:year, :month, :day, :hour]) ==
               [year: 5787, month: 1, day: 1, hour: 9]

      riyadh = Tempo.from_iso8601!("1448-03-15T10:00:00[Asia/Riyadh][u-ca=islamic-umalqura]")
      {:ok, utc} = Tempo.shift_zone(riyadh, "Etc/UTC")

      assert Keyword.take(utc.time, [:year, :month, :day, :hour]) ==
               [year: 1448, month: 3, day: 15, hour: 7]
    end
  end

  describe "one time zone annotation, as RFC 9557 gives a value" do
    test "a shifted value, the current time and a DateTime's value name their zone alone" do
      paris = Tempo.from_iso8601!("2026-06-15T14:00:00[Europe/Paris]")
      {:ok, new_york} = Tempo.shift_zone(paris, "America/New_York")
      winter = DateTime.new!(~D[2026-03-07], ~T[09:00:00], "America/New_York")

      assert Tempo.to_iso8601!(new_york) == "2026Y6M15DT8H0M0SZ-4H[America/New_York]"

      assert Tempo.to_iso8601!(Tempo.from_elixir(winter)) ==
               "2026Y3M7DT9H0M0SZ-5H[America/New_York]"

      assert Tempo.to_iso8601!(Tempo.utc_now()) =~ ~r/Z\[Etc\/UTC\]$/
    end

    test "the offset follows the value across a change of offset" do
      winter = Tempo.from_elixir(DateTime.new!(~D[2026-03-07], ~T[09:00:00], "America/New_York"))

      assert Tempo.to_iso8601!(Tempo.shift(winter, ~o"P1D")) ==
               "2026Y3M8DT9H0M0SZ-4H[America/New_York]"
    end

    test "the second of two equal wall times keeps its offset" do
      # 01:30 happens twice in New York on 1 November 2026: EDT, then EST.
      {:ambiguous, _first, second} =
        DateTime.new(~D[2026-11-01], ~T[01:30:00], "America/New_York")

      {:ok, round_trip} = second |> Tempo.from_elixir() |> Tempo.to_datetime()

      assert round_trip.utc_offset + round_trip.std_offset == -5 * 3600
    end

    test "an offset annotation is written alone, and beside a zone name not at all" do
      assert Tempo.to_iso8601!(Tempo.from_iso8601!("2026-06-15T14:00:00[+08:45]")) ==
               "2026Y6M15DT14H0M0S[+08:45]"

      paris = Tempo.from_iso8601!("2026-06-15T14:00:00+02:00[Europe/Paris]")
      both = %{paris | extended: %{paris.extended | zone_offset: 120}}

      assert Tempo.to_iso8601!(both) == "2026Y6M15DT14H0M0SZ2H0M[Europe/Paris]"
    end
  end

  # The user's decision of 2026-10-03: the result names the span the value
  # names. It was the moment the value starts at, to the second: an hour, a
  # day and a month each became one second, and a fraction of a second was
  # dropped.
  describe "Tempo.shift_zone/2 keeps the span a value names" do
    test "a second and a fraction of one are the same second on the other clock" do
      assert Tempo.shift_zone(~o"2026-06-15T10:30:45[Europe/Paris]", "America/New_York") ==
               {:ok, ~o"2026-06-15T04:30:45-04[America/New_York]"}

      assert Tempo.shift_zone(~o"2026-06-15T10:30:45.5[Europe/Paris]", "America/New_York") ==
               {:ok, ~o"2026-06-15T04:30:45.5-04[America/New_York]"}
    end

    test "a minute and an hour keep their resolution where the clocks differ by whole ones" do
      assert Tempo.shift_zone(~o"2026-06-15T10:30[Europe/Paris]", "America/New_York") ==
               {:ok, ~o"2026-06-15T04:30-04[America/New_York]"}

      assert Tempo.shift_zone(~o"2026-06-15T10[Europe/Paris]", "America/New_York") ==
               {:ok, ~o"2026-06-15T04-04[America/New_York]"}

      assert Tempo.shift_zone(~o"2026-06-15T10:30Z", "Asia/Kathmandu") ==
               {:ok, ~o"2026-06-15T16:15+05:45[Asia/Kathmandu]"}
    end

    test "an hour is an interval where the clocks differ by part of one" do
      {:ok, kolkata} = Tempo.shift_zone(~o"2026-06-15T10[Europe/Paris]", "Asia/Kolkata")

      assert {kolkata.from.time, kolkata.to.time} ==
               {[year: 2026, month: 6, day: 15, hour: 13, minute: 30],
                [year: 2026, month: 6, day: 15, hour: 14, minute: 30]}

      assert Tempo.to_iso8601(kolkata) ==
               {:ok, "2026Y6M15DT13H30MZ5H30M/T14H30MZ5H30M[Asia/Kolkata]"}
    end

    test "a day is the interval it is on the other clock" do
      {:ok, new_york} = Tempo.shift_zone(~o"2026-06-15[Europe/Paris]", "America/New_York")

      assert {new_york.from.time, new_york.to.time} ==
               {[year: 2026, month: 6, day: 14, hour: 18, minute: 0],
                [year: 2026, month: 6, day: 15, hour: 18, minute: 0]}

      # The day the clocks go forward in Paris is 23 hours long.
      {:ok, utc} = Tempo.shift_zone(~o"2026-03-29[Europe/Paris]", "Etc/UTC")

      assert {Tempo.hour(utc.from), Tempo.hour(utc.to)} == {23, 22}
    end

    test "a date stays a date in a zone whose clock reads the same" do
      assert Tempo.shift_zone(~o"2026-06-15[Europe/Paris]", "Europe/Berlin") ==
               {:ok, ~o"2026-06-15[Europe/Berlin]"}

      assert Tempo.shift_zone(~o"2026-03-29[Europe/Paris]", "Europe/Berlin") ==
               {:ok, ~o"2026-03-29[Europe/Berlin]"}

      assert Tempo.shift_zone(~o"2026[Europe/Paris]", "Europe/Berlin") ==
               {:ok, ~o"2026[Europe/Berlin]"}
    end

    test "an hour the clocks show twice keeps the offset that says which it is" do
      {:ok, first} = Tempo.shift_zone(~o"2026-10-25T00Z", "Europe/Paris")
      {:ok, second} = Tempo.shift_zone(~o"2026-10-25T01Z", "Europe/Paris")

      assert {Tempo.hour(first), Tempo.hour(second)} == {2, 2}
      assert {first.shift, second.shift} == {[hour: 2], [hour: 1]}
    end

    test "the span is the same on both clocks" do
      for value <- [
            ~o"2026-06-15T10[Europe/Paris]",
            ~o"2026-06-15[Europe/Paris]",
            ~o"2026-06[Europe/Paris]",
            ~o"2026-W25[Europe/Paris]"
          ],
          zone <- ["America/New_York", "Asia/Kolkata", "Europe/Berlin", "Etc/UTC"] do
        {:ok, there} = Tempo.shift_zone(value, zone)

        assert Tempo.equal?(value, there), "#{inspect(value)} in #{zone}"
      end
    end
  end

  describe "Tempo.shift_zone/2 keeps what the value carries" do
    test "its metadata, qualification and tags" do
      paris = Tempo.from_iso8601!("2026-06-15T14:00?[Europe/Paris][foo=bar]")
      paris = Tempo.put_metadata(paris, %{event: "launch"})
      {:ok, new_york} = Tempo.shift_zone(paris, "America/New_York")

      assert Tempo.metadata(new_york) == %{event: "launch"}
      assert Tempo.qualification(new_york) == :uncertain
      assert new_york.extended.tags == %{"foo" => ["bar"]}
    end

    test "its metadata, on the interval a coarser value becomes" do
      day = Tempo.put_metadata(~o"2026-06-15[Europe/Paris]", %{event: "launch"})
      {:ok, new_york} = Tempo.shift_zone(day, "America/New_York")

      assert Tempo.metadata(new_york) == %{event: "launch"}
    end
  end
end
