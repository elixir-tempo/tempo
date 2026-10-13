defmodule Tempo.ParseDurationTest do
  @moduledoc """
  `Tempo.parse_duration/1` — the caller declares the profile, so only
  a duration is admitted and the whole string must be one.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  @durations [
    "PT1H",
    "PT1H30M",
    "P1D",
    "P1Y2M3DT4H5M6S",
    "P3W",
    "PT1.5S",
    "PT0S",
    "-PT30M",
    "PT-30M"
  ]

  describe "durations parse" do
    test "each shape agrees with the general parser" do
      for iso <- @durations do
        assert {:ok, %Tempo.Duration{} = duration} = Tempo.parse_duration(iso),
               "#{iso} did not parse as a duration"

        assert duration == Tempo.from_iso8601!(iso),
               "#{iso} disagreed with Tempo.from_iso8601/1"
      end
    end

    test "components survive" do
      assert Tempo.parse_duration!("P1Y2M3DT4H5M6S").time ==
               [year: 1, month: 2, day: 3, hour: 4, minute: 5, second: 6]
    end

    test "a leading sign negates, as in the general parser" do
      assert Tempo.parse_duration!("-PT30M") == ~o"PT-30M"
    end
  end

  describe "the profile is the boundary" do
    test "a date-time is rejected rather than succeeding as the wrong type" do
      # The reason this function exists: `from_iso8601/1` returns a
      # `%Tempo{}` here, and an iCalendar DURATION property holding a
      # date-time would be accepted silently.
      assert {:ok, %Tempo{}} = Tempo.from_iso8601("2026-06-15")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_duration("2026-06-15")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_duration("2026-06-15T09:00:00Z")
    end

    test "a value that merely begins with a duration is not truncated" do
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_duration("P1D/2026-06-15")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_duration("R12/2026-01-01/P1M")
    end

    test "a set of durations is not a duration" do
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_duration("{P1D,P2D}")
    end

    test "a qualifier is refused rather than dropped" do
      # `from_iso8601/1` accepts this and discards the qualifier.
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_duration("P1D~")
    end

    test "junk and empty input are rejected" do
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_duration("")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_duration("not a duration")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_duration("P")
    end

    test "the error names the input and what was expected" do
      {:error, %Tempo.ParseError{} = error} = Tempo.parse_duration("2026-06-15")
      message = Exception.message(error)

      assert message =~ "as a duration"
      assert message =~ "2026-06-15"
    end
  end

  describe "parse_duration!/1" do
    test "returns the duration or raises" do
      assert Tempo.parse_duration!("PT1H30M") == ~o"PT1H30M"

      assert_raise Tempo.ParseError, fn -> Tempo.parse_duration!("2026-06-15") end
    end
  end
end
