defmodule Tempo.LengthPredicatesTest do
  @moduledoc """
  How long a span is beside a duration: `Tempo.at_least?/2`,
  `Tempo.at_most?/2`, `Tempo.exactly?/2`, `Tempo.longer_than?/2` and
  `Tempo.shorter_than?/2`.

  A span with a year is as long as the duration that reaches its end from
  its start, counted on the calendar, so a month is the month's own length.
  A span with no year is on a cycle, a day's clock or a week's days, and is
  measured there.

  The measure is Elixir's own `NaiveDateTime`: the start shifted by the
  duration, beside the end. For a span on a cycle it is the seconds from
  the one reading round to the other.
  """
  use ExUnit.Case, async: true

  # A span as it is written, and its two ends.
  @spans [
    {"2026-06-15T09/2026-06-15T10", ~N[2026-06-15 09:00:00], ~N[2026-06-15 10:00:00]},
    {"2026-06-15/2026-06-22", ~N[2026-06-15 00:00:00], ~N[2026-06-22 00:00:00]},
    {"2026-06-15T09:00:00/2026-06-15T09:00:30", ~N[2026-06-15 09:00:00], ~N[2026-06-15 09:00:30]},
    {"2026-01-31/2026-02-28", ~N[2026-01-31 00:00:00], ~N[2026-02-28 00:00:00]},
    {"2026-01-31/2026-03-01", ~N[2026-01-31 00:00:00], ~N[2026-03-01 00:00:00]},
    {"2024-02-29/2025-02-28", ~N[2024-02-29 00:00:00], ~N[2025-02-28 00:00:00]},
    {"2026-06-15T09:00:00/2026-06-15T09:00:00.5", ~N[2026-06-15 09:00:00],
     ~N[2026-06-15 09:00:00.5]},
    {"2026-06-15T09:30/2026-06-16T09:30", ~N[2026-06-15 09:30:00], ~N[2026-06-16 09:30:00]},
    {"2026/2027", ~N[2026-01-01 00:00:00], ~N[2027-01-01 00:00:00]},
    {"2026-06/2026-07", ~N[2026-06-01 00:00:00], ~N[2026-07-01 00:00:00]}
  ]

  # A duration as it is written, and as Elixir's `Duration` holds it.
  @durations [
    {"PT1H", [hour: 1]},
    {"PT60M", [minute: 60]},
    {"PT3600S", [second: 3600]},
    {"PT59M", [minute: 59]},
    {"PT61M", [minute: 61]},
    {"P7D", [day: 7]},
    {"P1W", [week: 1]},
    {"PT168H", [hour: 168]},
    {"P1D", [day: 1]},
    {"PT24H", [hour: 24]},
    {"P2W", [week: 2]},
    {"PT0.5S", [microsecond: {500_000, 6}]},
    {"PT30S", [second: 30]},
    {"PT30.5S", [second: 30, microsecond: {500_000, 6}]},
    {"PT29.5S", [second: 29, microsecond: {500_000, 6}]},
    {"P1M", [month: 1]},
    {"P1Y", [year: 1]},
    {"P28D", [day: 28]},
    {"P30D", [day: 30]},
    {"P365D", [day: 365]},
    {"P1M1D", [month: 1, day: 1]},
    {"P1DT12H", [day: 1, hour: 12]},
    {"PT1H30M", [hour: 1, minute: 30]}
  ]

  # A span with no year, and the seconds from its first reading round to its
  # second: a time of day on the clock of a day, and a day of the week in a
  # week. A reading to itself is the whole cycle.
  @on_a_cycle [
    {"T09/T10", 3_600},
    {"T09:00/T09:30", 1_800},
    {"T23/T01", 2 * 3_600},
    {"T09:00:00/T09:00:30", 30},
    {"T00/T23", 23 * 3_600},
    {"T09:30/T09:30", 86_400},
    {"1K/3K", 2 * 86_400},
    {"6K/2K", 3 * 86_400}
  ]

  # A duration and its seconds, or what has no one length on a cycle.
  @lasting [
    {"PT1H", 3_600},
    {"PT30M", 1_800},
    {"PT1800S", 1_800},
    {"PT2H", 7_200},
    {"PT30S", 30},
    {"PT29.5S", 29.5},
    {"PT30.5S", 30.5},
    {"P1D", 86_400},
    {"P2D", 2 * 86_400},
    {"P3D", 3 * 86_400},
    {"P1W", 7 * 86_400},
    {"PT23H", 23 * 3_600},
    {"PT48H", 48 * 3_600},
    {"P1M", :a_month_or_more},
    {"P1Y", :a_month_or_more}
  ]

  ## The measure

  # How the span is beside the duration: longer, exactly as long, or shorter.
  defp beside(%NaiveDateTime{} = from, %NaiveDateTime{} = to, shift) do
    case NaiveDateTime.compare(NaiveDateTime.shift(from, shift), to) do
      :lt -> :longer
      :eq -> :exactly
      :gt -> :shorter
    end
  end

  defp beside(_seconds, :a_month_or_more), do: :shorter
  defp beside(seconds, lasting) when seconds > lasting, do: :longer
  defp beside(seconds, lasting) when seconds == lasting, do: :exactly
  defp beside(_seconds, _lasting), do: :shorter

  # What each predicate says, as the one word they come to.
  defp said(span, duration) do
    interval = Tempo.from_iso8601!(span)
    duration = Tempo.from_iso8601!(duration)

    %{
      one_of:
        for(
          {word, true} <- [
            longer: Tempo.longer_than?(interval, duration),
            exactly: Tempo.exactly?(interval, duration),
            shorter: Tempo.shorter_than?(interval, duration)
          ],
          do: word
        ),
      at_least: Tempo.at_least?(interval, duration),
      at_most: Tempo.at_most?(interval, duration)
    }
  end

  defp to_say(word),
    do: %{
      one_of: [word],
      at_least: word in [:longer, :exactly],
      at_most: word in [:shorter, :exactly]
    }

  describe "a span with a year" do
    test "is as long as the duration that reaches its end from its start" do
      for {span, from, to} <- @spans, {duration, shift} <- @durations do
        assert {span, duration, said(span, duration)} ==
                 {span, duration, to_say(beside(from, to, shift))}
      end
    end

    test "counts a month and a year on the calendar" do
      # A month on from 31 January is the last of February, so the 28 days to
      # it are exactly a month, and less than thirty days.
      assert Date.shift(~D[2026-01-31], month: 1) == ~D[2026-02-28]

      january_to_february = Tempo.from_iso8601!("2026-01-31/2026-02-28")
      assert Tempo.exactly?(january_to_february, Tempo.from_iso8601!("P1M"))
      assert Tempo.exactly?(january_to_february, Tempo.from_iso8601!("P28D"))
      assert Tempo.shorter_than?(january_to_february, Tempo.from_iso8601!("P30D"))

      # A year on from 29 February is 28 February.
      assert Date.shift(~D[2024-02-29], year: 1) == ~D[2025-02-28]

      assert Tempo.exactly?(
               Tempo.from_iso8601!("2024-02-29/2025-02-28"),
               Tempo.from_iso8601!("P1Y")
             )
    end
  end

  describe "a span with no year" do
    test "is as long as its cycle measures it" do
      for {span, seconds} <- @on_a_cycle, {duration, lasting} <- @lasting do
        assert {span, duration, said(span, duration)} ==
                 {span, duration, to_say(beside(seconds, lasting))}
      end
    end

    test "comes round its cycle, and is shorter than any month or year" do
      # From 23:00 to 01:00 is two hours, and from a reading to itself the
      # whole day.
      assert Tempo.exactly?(Tempo.from_iso8601!("T23/T01"), Tempo.from_iso8601!("PT2H"))
      assert Tempo.exactly?(Tempo.from_iso8601!("T09:30/T09:30"), Tempo.from_iso8601!("P1D"))

      # From Saturday to Tuesday is three days.
      assert Tempo.exactly?(Tempo.from_iso8601!("6K/2K"), Tempo.from_iso8601!("P3D"))
      assert Tempo.shorter_than?(Tempo.from_iso8601!("6K/2K"), Tempo.from_iso8601!("P1W"))
      assert Tempo.shorter_than?(Tempo.from_iso8601!("T00/T23"), Tempo.from_iso8601!("P1M"))
    end
  end
end
