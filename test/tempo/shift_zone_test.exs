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
end
