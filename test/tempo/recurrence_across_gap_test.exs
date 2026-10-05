defmodule Tempo.RecurrenceAcrossGapTest do
  @moduledoc """
  A recurrence of days or weeks from a time of day in a zone keeps that time
  of day. An occurrence that lands on a reading the clock skips is moved to
  the reading that long after (RFC 5545 §3.3.5: 02:30 on the night of a
  spring-forward is 03:30), and it alone: the occurrence after it is at the
  time of day the recurrence started with.

  Each occurrence was stepped from the one before it as it was moved, so a
  daily 02:30 in New York was 03:30 from the night of the change on.

  The measure is Elixir's `NaiveDateTime.add/3` and `DateTime.from_naive/2`:
  the start's wall reading that many days on, and the instant the zone
  gives it.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  @epoch ~N[1970-01-01 00:00:00]

  # The instant of a wall reading in a zone: the first of two where the
  # clock shows it twice, and read with the offset before the gap where the
  # clock skips it.
  defp instant(%NaiveDateTime{} = reading, zone) do
    case DateTime.from_naive(reading, zone) do
      {:ok, shown} ->
        DateTime.to_unix(shown)

      {:ambiguous, first, _second} ->
        DateTime.to_unix(first)

      {:gap, just_before, _just_after} ->
        NaiveDateTime.diff(reading, @epoch) - just_before.utc_offset - just_before.std_offset
    end
  end

  defp expected(%NaiveDateTime{} = start, zone, days_apart, count),
    do:
      for(
        step <- 0..(count - 1),
        do: instant(NaiveDateTime.add(start, step * days_apart, :day), zone)
      )

  defp starts({:ok, %IntervalSet{} = occurrences}) do
    for occurrence <- IntervalSet.members(occurrences) do
      {:ok, start} = Tempo.to_datetime(Interval.from(occurrence))
      DateTime.to_unix(start)
    end
  end

  @recurrences [
    # A spring-forward in New York on 10 March 2024, 02:00 to 03:00.
    {"R6/2024-03-08T02:30:00[America/New_York]/P1D", ~N[2024-03-08 02:30:00], "America/New_York",
     1, 6},
    {"R4/2024-03-03T02:30:00[America/New_York]/P1W", ~N[2024-03-03 02:30:00], "America/New_York",
     7, 4},
    {"R5/2024-03-08T02:00:00[America/New_York]/P2D", ~N[2024-03-08 02:00:00], "America/New_York",
     2, 5},
    {"R5/2024-03-09T02:30:00[America/New_York]/P2D", ~N[2024-03-09 02:30:00], "America/New_York",
     2, 5},
    # In Paris on 29 March 2026, and on Lord Howe Island, by half an hour.
    {"R5/2026-03-27T02:15:00[Europe/Paris]/P1D", ~N[2026-03-27 02:15:00], "Europe/Paris", 1, 5},
    {"R5/2026-10-02T02:10:00[Australia/Lord_Howe]/P1D", ~N[2026-10-02 02:10:00],
     "Australia/Lord_Howe", 1, 5},
    # A fall-back, where the clock shows the reading twice.
    {"R5/2024-11-01T01:30:00[America/New_York]/P1D", ~N[2024-11-01 01:30:00], "America/New_York",
     1, 5},
    # No change of the clock at all.
    {"R5/2024-06-10T02:30:00[America/New_York]/P1D", ~N[2024-06-10 02:30:00], "America/New_York",
     1, 5}
  ]

  describe "a recurrence of days or weeks from a time of day in a zone" do
    test "has each occurrence at the start's reading that many days on" do
      for {text, start, zone, days_apart, count} <- @recurrences do
        occurrences = Tempo.to_interval(Tempo.from_iso8601!(text))

        assert {text, starts(occurrences)} == {text, expected(start, zone, days_apart, count)}
      end
    end

    test "returns to its time of day after the occurrence the clock moved" do
      {:ok, occurrences} = Tempo.to_interval(~o"R4/2024-03-09T02:30:00[America/New_York]/P1D")

      assert Enum.map(IntervalSet.members(occurrences), &Tempo.to_iso8601!(Interval.from(&1))) ==
               [
                 "2024Y3M9DT2H30M0S[America/New_York]",
                 "2024Y3M10DT3H30M0S[America/New_York]",
                 "2024Y3M11DT2H30M0S[America/New_York]",
                 "2024Y3M12DT2H30M0S[America/New_York]"
               ]
    end

    test "has each occurrence end where the next starts" do
      {:ok, occurrences} = Tempo.to_interval(~o"R4/2024-03-09T02:30:00[America/New_York]/P1D")
      members = IntervalSet.members(occurrences)

      for {occurrence, next} <- Enum.zip(members, tl(members)) do
        assert Interval.to(occurrence) == Interval.from(next)
      end
    end

    test "is so within a window, and for a rule read from an RRULE" do
      unbounded = ~o"R/2024-03-08T02:30:00[America/New_York]/P1D"
      within = Tempo.to_interval(unbounded, within: ~o"2024-03-08/2024-03-14")

      assert starts(within) == expected(~N[2024-03-08 02:30:00], "America/New_York", 1, 6)

      {:ok, rule} =
        RRule.parse("FREQ=DAILY;COUNT=6", from: ~o"2024-03-08T02:30:00[America/New_York]")

      assert starts(Tempo.to_interval(rule)) ==
               expected(~N[2024-03-08 02:30:00], "America/New_York", 1, 6)
    end
  end

  describe "a recurrence the clock does not move" do
    test "of hours counts the time that passes" do
      {:ok, occurrences} = Tempo.to_interval(~o"R4/2024-03-09T02:30:00[America/New_York]/PT24H")
      [first | _rest] = instants = starts({:ok, occurrences})

      assert instants == for(step <- 0..3, do: first + step * 86_400)
    end

    test "of days from a date, or from a time with an offset, is each day" do
      {:ok, dates} = Tempo.to_interval(~o"R3/2024-03-09[America/New_York]/P1D")

      assert Enum.map(IntervalSet.members(dates), &Tempo.to_iso8601!/1) == [
               "2024Y3M9D/10D[America/New_York]",
               "2024Y3M10D/11D[America/New_York]",
               "2024Y3M11D/12D[America/New_York]"
             ]

      {:ok, offsets} = Tempo.to_interval(~o"R3/2024-03-09T02:30:00-05:00/P1D")

      assert Enum.map(IntervalSet.members(offsets), &Tempo.to_iso8601!(Interval.from(&1))) == [
               "2024Y3M9DT2H30M0SZ-5H0M",
               "2024Y3M10DT2H30M0SZ-5H0M",
               "2024Y3M11DT2H30M0SZ-5H0M"
             ]
    end
  end
end
