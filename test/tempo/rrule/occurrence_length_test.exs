defmodule Tempo.RRule.OccurrenceLengthTest do
  @moduledoc """
  How long an occurrence of a rule is (decided 2026-10-09, user).

  An occurrence of a rule is as long as its start is precise: a day for a
  date, an hour for a time written to the hour. A rule that takes a part
  from its start, or states one, was that already. One with no part ran a
  whole cadence, as an ISO 8601 recurrence's occurrences do, so
  `FREQ=DAILY` from 10:00 was a day long where `FREQ=WEEKLY` from the same
  start was an hour. It is the hour.

  A start as coarse as the rule's step, or coarser, is the step's own
  length: an hourly rule from a date is an hour of it.

  The measure is `NaiveDateTime` alone: each occurrence's start, so many
  steps on from the rule's, and its end, the length on from that.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ICal
  alias Tempo.JSCalendar
  alias Tempo.Matrix.Extent
  alias Tempo.RRule
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  @epoch ~N[0000-01-01 00:00:00]

  defp microseconds(%NaiveDateTime{} = moment),
    do: NaiveDateTime.diff(moment, @epoch, :microsecond)

  # The spans of the occurrences, each from its start to its end.
  defp spans({:ok, rule}) do
    {:ok, set} = Tempo.to_interval(rule)
    {:ok, members} = Extent.members(set)
    Enum.map(members, fn %{spans: [span]} -> span end)
  end

  # `count` occurrences from `start`, a step of `step` apart and `length` long.
  defp expected(%NaiveDateTime{} = start, count, step, length) do
    for index <- 0..(count - 1) do
      from =
        NaiveDateTime.shift(
          start,
          Enum.map(step, fn {unit, amount} -> {unit, amount * index} end)
        )

      {microseconds(from), microseconds(NaiveDateTime.shift(from, length))}
    end
  end

  describe "a rule with no part, from a start finer than it steps" do
    test "has occurrences as long as its start is precise" do
      for {rule, start, moment, step, length} <- [
            {"FREQ=DAILY", ~o"2026-01-31T10", ~N[2026-01-31 10:00:00], [day: 1], [hour: 1]},
            {"FREQ=DAILY", ~o"2026-01-31T10:30", ~N[2026-01-31 10:30:00], [day: 1], [minute: 1]},
            {"FREQ=DAILY", ~o"2026-01-31T10:30:15", ~N[2026-01-31 10:30:15], [day: 1],
             [second: 1]},
            {"FREQ=HOURLY", ~o"2026-01-31T10:30", ~N[2026-01-31 10:30:00], [hour: 1],
             [minute: 1]},
            {"FREQ=MINUTELY", ~o"2026-01-31T10:30:15", ~N[2026-01-31 10:30:15], [minute: 1],
             [second: 1]},
            {"FREQ=YEARLY", ~o"2026-06", ~N[2026-06-01 00:00:00], [year: 1], [month: 1]},
            {"FREQ=DAILY;INTERVAL=3", ~o"2026-01-31T10", ~N[2026-01-31 10:00:00], [day: 3],
             [hour: 1]}
          ] do
        assert {rule, start, spans(RRule.parse(rule <> ";COUNT=4", from: start))} ==
                 {rule, start, expected(moment, 4, step, length)}
      end
    end

    test "is the length a weekly, a monthly or a yearly rule from the same start already had" do
      # Each takes a part from its start, and was an hour long.
      for {rule, step} <- [
            {"FREQ=WEEKLY", [week: 1]},
            {"FREQ=MONTHLY", [month: 1]},
            {"FREQ=YEARLY", [year: 1]}
          ] do
        assert {rule, spans(RRule.parse(rule <> ";COUNT=3", from: ~o"2026-06-15T09"))} ==
                 {rule, expected(~N[2026-06-15 09:00:00], 3, step, hour: 1)}
      end
    end

    test "keeps the length where its parts only keep or drop its periods" do
      # 2 February 2026 is a Monday.
      assert Date.day_of_week(~D[2026-02-02]) == 1

      assert spans(RRule.parse("FREQ=DAILY;BYDAY=MO;COUNT=3", from: ~o"2026-02-02T10")) ==
               expected(~N[2026-02-02 10:00:00], 3, [week: 1], hour: 1)
    end

    test "is so for a rule built as a struct" do
      assert spans(Expander.to_ast(%Rule{freq: :day, count: 3}, ~o"2026-01-31T10")) ==
               expected(~N[2026-01-31 10:00:00], 3, [day: 1], hour: 1)
    end

    test "is written as the rule it is, and read back from that as itself" do
      {:ok, rule} = RRule.parse("FREQ=DAILY;COUNT=3", from: ~o"2026-01-31T10")

      assert RRule.to_string(rule) == {:ok, "FREQ=DAILY;COUNT=3"}
      assert RRule.parse("FREQ=DAILY;COUNT=3", from: ~o"2026-01-31T10") == {:ok, rule}
    end
  end

  describe "a rule with no part, from a start as coarse as it steps or coarser" do
    test "has occurrences as long as it steps" do
      for {rule, start, moment, step} <- [
            {"FREQ=DAILY", ~o"2026-01-31", ~N[2026-01-31 00:00:00], [day: 1]},
            {"FREQ=HOURLY", ~o"2026-01-31", ~N[2026-01-31 00:00:00], [hour: 1]},
            {"FREQ=HOURLY", ~o"2026-01-31T10", ~N[2026-01-31 10:00:00], [hour: 1]},
            {"FREQ=MONTHLY", ~o"2026", ~N[2026-01-01 00:00:00], [month: 1]}
          ] do
        assert {rule, start, spans(RRule.parse(rule <> ";COUNT=3", from: start))} ==
                 {rule, start, expected(moment, 3, step, step)}
      end
    end

    test "is the ISO 8601 recurrence of the same start" do
      assert RRule.parse("FREQ=DAILY;COUNT=3", from: ~o"2026-01-31") ==
               {:ok, ~o"R3/2026-01-31/P1D"}
    end
  end

  describe "a rule of an event with no end" do
    # A time of day in iCalendar and in JSCalendar is written to the second.
    test "is a second long in iCalendar, whatever the rule steps by" do
      for {rule, step} <- [
            {"FREQ=HOURLY", [hour: 1]},
            {"FREQ=DAILY", [day: 1]},
            {"FREQ=WEEKLY", [week: 1]}
          ] do
        event =
          Enum.join(
            [
              "BEGIN:VCALENDAR",
              "VERSION:2.0",
              "PRODID:-//tempo//occurrence length//EN",
              "BEGIN:VEVENT",
              "UID:occurrence-length@tempo",
              "DTSTAMP:20260101T000000Z",
              "DTSTART:20260131T100000",
              "RRULE:#{rule};COUNT=3",
              "END:VEVENT",
              "END:VCALENDAR",
              ""
            ],
            "\r\n"
          )

        assert {rule, spans(ICal.parse(event))} ==
                 {rule, expected(~N[2026-01-31 10:00:00], 3, step, second: 1)}
      end
    end

    test "is a second long in JSCalendar, whatever the rule steps by" do
      for {frequency, step} <- [{"hourly", [hour: 1]}, {"daily", [day: 1]}, {"weekly", [week: 1]}] do
        event = """
        {
          "@type": "Event",
          "uid": "occurrence-length",
          "title": "An event with no duration",
          "start": "2026-01-31T10:00:00",
          "recurrenceRules": [
            {"@type": "RecurrenceRule", "frequency": "#{frequency}", "count": 3}
          ]
        }
        """

        assert {frequency, spans(JSCalendar.parse(event))} ==
                 {frequency, expected(~N[2026-01-31 10:00:00], 3, step, second: 1)}
      end
    end
  end

  describe "a length the caller gives" do
    test "is the length, whatever the start is precise to" do
      rule = RRule.parse("FREQ=DAILY;COUNT=3", from: ~o"2026-01-31T10", duration: ~o"PT2H")

      assert spans(rule) == expected(~N[2026-01-31 10:00:00], 3, [day: 1], hour: 2)
    end
  end

  describe "an ISO 8601 recurrence" do
    test "runs its cadence, as it is written to" do
      assert spans({:ok, ~o"R3/2026-01-31T10/P1D"}) ==
               expected(~N[2026-01-31 10:00:00], 3, [day: 1], day: 1)
    end
  end
end
