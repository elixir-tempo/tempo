defmodule Tempo.RRule.CountOneTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ICal
  alias Tempo.IntervalSet

  # A rule with one occurrence steps nothing, so its occurrence spans
  # the event, not the rule's frequency.

  defp occurrences(dtstart, dtend, rule) do
    ics = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//Test//EN
    BEGIN:VEVENT
    UID:count-one
    DTSTAMP:20220101T000000Z
    #{dtstart}
    #{dtend}
    RRULE:#{rule}
    SUMMARY:Once
    END:VEVENT
    END:VCALENDAR
    """

    {:ok, set} = ICal.parse(ics)
    IntervalSet.to_list(set)
  end

  describe "a rule with one occurrence" do
    test "an hour-long weekly event occurs once, for an hour" do
      [once] =
        occurrences("DTSTART:20220601T090000Z", "DTEND:20220601T100000Z", "FREQ=WEEKLY;COUNT=1")

      assert Tempo.exactly?(once, ~o"PT1H")
    end

    test "an all-day yearly event occurs once, for a day" do
      [once] =
        occurrences(
          "DTSTART;VALUE=DATE:20220704",
          "DTEND;VALUE=DATE:20220705",
          "FREQ=YEARLY;COUNT=1"
        )

      assert once.from.time == [year: 2022, month: 7, day: 4]
      assert once.to.time == [year: 2022, month: 7, day: 5]
    end

    test "an event's DURATION is its one occurrence's length" do
      [once] = occurrences("DTSTART:20220601T090000Z", "DURATION:PT90M", "FREQ=WEEKLY;COUNT=1")

      assert Tempo.exactly?(once, ~o"PT90M")
    end

    test "an ISO 8601 repetition of one still spans its duration" do
      {:ok, week} = Tempo.to_interval(Tempo.from_iso8601!("R1/2022-06-01/P1W"))

      assert Tempo.exactly?(week, ~o"P1W")
    end
  end
end
