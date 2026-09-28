defmodule Tempo.ParseTest do
  @moduledoc """
  `Tempo.parse/2` reads ISO 8601 first, with the whole grammar
  `Tempo.from_iso8601/2` reads, and a locale's own words after that.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  describe "ISO 8601 first" do
    test "every shape from_iso8601/1 reads, read the same way" do
      for iso <- [
            "2026-06-15T10:30",
            "2026-06-15T10:30Z",
            "2026-06-15T10:30[Europe/Paris]",
            "2026-06",
            "2026-W12",
            "2026-06-15?",
            "2026-06-15/2026-06-20",
            "R5/2026-06-15/P1D",
            "P1DT12H",
            "{2025,2026}Y"
          ] do
        assert Tempo.parse(iso, locale: :en) == Tempo.from_iso8601(iso), "#{iso} read differently"
      end
    end

    test "ISO 8601 that names no real date is that error, not a reading as text" do
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.parse("2026-02-30", locale: :en)
    end

    test "strict: true checks the zone of an ISO 8601 reading" do
      assert {:error, %Tempo.ZoneOffsetMismatchError{}} =
               Tempo.parse("2026-06-15T10:30+05:00[Europe/Paris]", strict: true)
    end
  end

  describe "then the locale's words" do
    test "a date, a time, a datetime and a range" do
      assert Tempo.parse("15 June 2026", locale: :en) == {:ok, ~o"2026-06-15"}
      assert Tempo.parse("2:30 PM", locale: :en) == {:ok, ~o"T14:30"}
      assert Tempo.parse("15 June 2026 14:30", locale: :en) == {:ok, ~o"2026-06-15T14:30"}

      assert {:ok, %Tempo.Interval{} = range} = Tempo.parse("May 5 – May 10, 2026", locale: :en)
      assert Tempo.to_iso8601(range) == "2026Y5M5D/10D"
    end

    test "text that names nothing keeps the locale's error" do
      assert {:error, %Localize.DateTimeParseError{}} = Tempo.parse("tomorrow", locale: :en)
    end
  end
end
