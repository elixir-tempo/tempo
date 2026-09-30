defmodule Tempo.ShiftZoneTest do
  use ExUnit.Case, async: true

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

    test "a day that starts the evening before in UTC falls on that evening's date" do
      # Midnight starting 1 Tishri in Jerusalem is 21:00 UTC on 29 Elul 5786
      new_year = Tempo.from_iso8601!("5787-01-01[Asia/Jerusalem][u-ca=hebrew]")
      {:ok, utc} = Tempo.shift_zone(new_year, "Etc/UTC")

      assert Keyword.take(utc.time, [:year, :month, :day, :hour]) ==
               [year: 5786, month: 12, day: 29, hour: 21]
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

  describe "Tempo.shift_zone/2 keeps what the value carries" do
    test "its metadata, qualification and tags" do
      paris = Tempo.from_iso8601!("2026-06-15T14:00?[Europe/Paris][foo=bar]")
      paris = Tempo.put_metadata(paris, %{event: "launch"})
      {:ok, new_york} = Tempo.shift_zone(paris, "America/New_York")

      assert Tempo.metadata(new_york) == %{event: "launch"}
      assert new_york.qualification == :uncertain
      assert new_york.extended.tags == %{"foo" => ["bar"]}
    end
  end
end
