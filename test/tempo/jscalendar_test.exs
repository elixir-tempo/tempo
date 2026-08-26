# `Tempo.JSCalendar` is deliberately not aliased: the alias would be
# `JSCalendar`, which is the name of the package whose structs the
# doctests construct, and it would shadow it.
# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule Tempo.JSCalendarTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  doctest Tempo.JSCalendar

  defp event(properties) do
    ~s({"@type":"Event","uid":"e","updated":"2026-06-01T09:00:00Z",#{properties}})
  end

  defp spans(set) do
    set
    |> IntervalSet.to_list()
    |> Enum.map(&Tempo.to_iso8601/1)
  end

  describe "a single event" do
    test "becomes one interval, start to start plus duration" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(
                 event(~s("start":"2026-06-02T09:00:00","duration":"PT1H"))
               )

      assert spans(set) == ["2026Y6M2DT9H0M0S/T10H0M0S"]
    end

    test "a missing duration is an instant, per the PT0S default" do
      # Tempo has no zero-extent interval, so a punctual event becomes
      # the one-unit span of its start and says so — the same
      # treatment `Tempo.ICal` gives a zero-duration VEVENT.
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s("start":"2026-06-02T09:00:00")))

      assert [interval] = IntervalSet.to_list(set)
      assert interval.metadata.punctual == true
      refute Tempo.Compare.compare_endpoints(interval.from, interval.to) == :same
    end

    test "a multi-part duration is applied whole" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(
                 event(~s("start":"2026-06-02T09:00:00","duration":"P1DT2H30M"))
               )

      assert spans(set) == ["2026Y6M2DT9H0M0S/3DT11H30M0S"]
    end

    test "an event with no start is skipped, not fatal" do
      assert {:ok, set} = Tempo.JSCalendar.from_jscalendar(event(~s("title":"Someday")))

      assert IntervalSet.count(set) == 0
    end

    test "metadata rides along on the interval" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(
                 event(~s("start":"2026-06-02T09:00:00","title":"Review","status":"confirmed"))
               )

      assert [interval] = IntervalSet.to_list(set)
      assert interval.metadata.uid == "e"
      assert interval.metadata.title == "Review"
      assert interval.metadata.status == "confirmed"
    end
  end

  describe "time zones" do
    test "a zoned event is anchored to that zone" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(
                 event(
                   ~s("start":"2026-06-02T09:00:00","timeZone":"Australia/Sydney","duration":"PT1H")
                 )
               )

      assert [interval] = IntervalSet.to_list(set)
      assert interval.from.extended.zone_id == "Australia/Sydney"
    end

    test "an event with no zone floats, rather than adopting the reader's" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s("start":"2026-06-02T09:00:00")))

      assert [interval] = IntervalSet.to_list(set)
      assert interval.from.extended == nil
    end

    test "an explicit null zone floats too" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(
                 event(~s("start":"2026-06-02T09:00:00","timeZone":null))
               )

      assert [interval] = IntervalSet.to_list(set)
      assert interval.from.extended == nil
    end

    test "an hour-long meeting stays an hour long across a DST boundary" do
      # This is why RFC 8984 stores start-and-duration rather than
      # start-and-end. Sydney leaves daylight saving at 03:00 on
      # 5 April 2026; an event at 02:30 that morning is one hour of
      # wall clock either way.
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(
                 event(
                   ~s("start":"2026-04-05T01:00:00","timeZone":"Australia/Sydney","duration":"PT1H")
                 )
               )

      assert [interval] = IntervalSet.to_list(set)
      assert interval.to.time[:hour] == 2
    end

    test "an unknown zone is an error naming it" do
      assert {:error, {:invalid_time_zone, "Mars/Olympus_Mons", _reason}} =
               Tempo.JSCalendar.from_jscalendar(
                 event(~s("start":"2026-06-02T09:00:00","timeZone":"Mars/Olympus_Mons"))
               )
    end
  end

  describe "recurrence" do
    test "a counted rule expands to that many occurrences" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":3}]
                 )))

      assert IntervalSet.count(set) == 3
    end

    test "each occurrence keeps the event's own span, not a stub" do
      # The bug this guards: materialising a recurrence yields start
      # moments with a one-unit span unless the duration is carried.
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":2}]
                 )))

      for interval <- IntervalSet.to_list(set) do
        assert interval.to.time[:hour] - interval.from.time[:hour] == 1
      end
    end

    test "an unbounded rule needs a :bound" do
      json =
        event(~s(
          "start":"2026-06-01T09:00:00","duration":"PT1H",
          "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily"}]
        ))

      assert {:error, _needs_bound} = Tempo.JSCalendar.from_jscalendar(json)

      assert {:ok, set} = Tempo.JSCalendar.from_jscalendar(json, bound: ~o"2026Y6M1D/5D")
      assert IntervalSet.count(set) == 4
    end

    test "byDay carries its ordinal" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"monthly","count":3,
                     "byDay":[{"@type":"NDay","day":"mo","nthOfPeriod":1}]}]
                 )))

      # The first Monday of three consecutive months.
      assert IntervalSet.count(set) == 3

      for interval <- IntervalSet.to_list(set) do
        assert interval.from.time[:day] <= 7
      end
    end

    test "excludedRecurrenceRules removes occurrences" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":6}],
                   "excludedRecurrenceRules":[
                     {"@type":"RecurrenceRule","frequency":"daily","interval":2,"count":3}]
                 )))

      # Six daily occurrences, every second one excluded.
      assert IntervalSet.count(set) == 3
    end

    test "an unsupported frequency is reported, not guessed at" do
      assert {:error, {:unsupported_frequency, "fortnightly"}} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"fortnightly"}]
                 )))
    end

    test "a lunisolar leap month is reported rather than rounded" do
      # RFC 8984 writes byMonth as strings so `"3L"` can name a leap
      # month. There is no honest ordinal for it, so it is refused.
      assert {:error, {:unsupported_month, "3L"}} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"yearly",
                     "byMonth":["3L"],"count":1}]
                 )))
    end
  end

  describe "recurrence overrides" do
    test "an override with no matching rule adds an occurrence" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":2}],
                   "recurrenceOverrides":{"2026-06-05T09:00:00":{}}
                 )))

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M2DT9H0M0S/T10H0M0S",
               "2026Y6M5DT9H0M0S/T10H0M0S"
             ]
    end

    test "an excluded override removes one occurrence" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":3}],
                   "recurrenceOverrides":{"2026-06-02T09:00:00":{"excluded":true}}
                 )))

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M3DT9H0M0S/T10H0M0S"
             ]
    end

    test "a patched start moves an occurrence without duplicating it" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":3}],
                   "recurrenceOverrides":{
                     "2026-06-02T09:00:00":{"start":"2026-06-02T14:00:00"}
                   }
                 )))

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M2DT14H0M0S/T15H0M0S",
               "2026Y6M3DT9H0M0S/T10H0M0S"
             ]
    end

    test "a patched duration changes only that occurrence" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":2}],
                   "recurrenceOverrides":{"2026-06-02T09:00:00":{"duration":"PT3H"}}
                 )))

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M2DT9H0M0S/T12H0M0S"
             ]
    end

    test "an event with overrides and no rules is still recurring" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceOverrides":{"2026-06-08T09:00:00":{"duration":"PT2H"}}
                 )))

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M8DT9H0M0S/T11H0M0S"
             ]
    end

    test "an override matches on the recurrence id in the event's own zone" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "timeZone":"Australia/Sydney",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":3}],
                   "recurrenceOverrides":{"2026-06-02T09:00:00":{"excluded":true}}
                 )))

      assert IntervalSet.count(set) == 2
    end

    test "an override title reaches the interval metadata" do
      assert {:ok, set} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H","title":"Standup",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":2}],
                   "recurrenceOverrides":{"2026-06-02T09:00:00":{"title":"Retro"}}
                 )))

      assert [first, second] = IntervalSet.to_list(set)
      assert first.metadata.title == "Standup"
      assert second.metadata.title == "Retro"
      assert second.metadata.uid == "e"
    end

    test "an invalid patch fails the import rather than being half applied" do
      assert {:error, _reason} =
               Tempo.JSCalendar.from_jscalendar(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceOverrides":{"2026-06-08T09:00:00":{"a":1,"a/b":2}}
                 )))
    end
  end

  describe "tasks and groups" do
    test "a task occupies no time" do
      json = ~s({"@type":"Task","uid":"t","title":"Write it up","due":"2026-06-02T17:00:00"})

      assert {:ok, set} = Tempo.JSCalendar.from_jscalendar(json)
      assert IntervalSet.count(set) == 0
    end

    test "a group contributes its events" do
      json = ~s({
        "@type":"Group","uid":"g",
        "entries":[
          {"@type":"Event","uid":"e1","start":"2026-06-02T09:00:00","duration":"PT1H"},
          {"@type":"Event","uid":"e2","start":"2026-06-03T09:00:00","duration":"PT1H"},
          {"@type":"Task","uid":"t1","title":"Not on the timeline"}
        ]
      })

      assert {:ok, set} = Tempo.JSCalendar.from_jscalendar(json)

      assert spans(set) == [
               "2026Y6M2DT9H0M0S/T10H0M0S",
               "2026Y6M3DT9H0M0S/T10H0M0S"
             ]
    end
  end

  describe "bad input" do
    test "a malformed document is an error, not a crash" do
      assert {:error, :invalid_json} = Tempo.JSCalendar.from_jscalendar("{{{")
    end

    test "an unrecognised object type is reported" do
      assert {:error, {:unknown_type, "Sandwich"}} =
               Tempo.JSCalendar.from_jscalendar(~s({"@type":"Sandwich"}))
    end
  end

  describe "alongside iCalendar" do
    test "both formats reach the same interval algebra" do
      # The point of the module: JSCalendar and iCalendar are two
      # spellings of the same calendar, and both land on a timeline
      # where set operations work.
      {:ok, from_js} =
        Tempo.JSCalendar.from_jscalendar(
          event(~s("start":"2026-06-02T09:00:00","duration":"PT8H"))
        )

      {:ok, busy} =
        Tempo.JSCalendar.from_jscalendar(
          ~s({"@type":"Event","uid":"lunch","start":"2026-06-02T12:00:00","duration":"PT1H"})
        )

      assert {:ok, free} = Tempo.difference(from_js, busy)
      assert IntervalSet.count(free) == 2
    end
  end
end
