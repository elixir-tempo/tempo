defmodule Tempo.JSCalendarTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  doctest Tempo.JSCalendar

  # An event's document, made as data and encoded, its properties beside
  # those every event has.
  defp event(properties) do
    %{"@type" => "Event", "uid" => "e", "updated" => "2026-06-01T09:00:00Z"}
    |> Map.merge(properties)
    |> :json.encode()
    |> IO.iodata_to_binary()
  end

  # An event of an hour with one rule, its parts beside the given ones.
  defp ruled(start, given, rule) do
    event(%{
      "start" => start,
      "duration" => "PT1H",
      "recurrenceRules" => [Map.merge(%{"@type" => "RecurrenceRule"}, Map.merge(given, rule))]
    })
  end

  # The Gregorian day each member begins on.
  defp gregorian_dates(set) do
    set
    |> IntervalSet.members()
    |> Enum.map(fn member ->
      {:ok, date} = member |> Interval.from() |> Tempo.to_date()
      Date.convert!(date, Calendar.ISO)
    end)
  end

  defp spans(set) do
    set
    |> IntervalSet.members()
    |> Enum.map(&Tempo.to_iso8601!/1)
  end

  describe "a single event" do
    test "becomes one interval, start to start plus duration" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{"start" => "2026-06-02T09:00:00", "duration" => "PT1H"})
               )

      assert spans(set) == ["2026Y6M2DT9H0M0S/T10H0M0S"]
    end

    test "a missing duration is an instant, per the PT0S default" do
      # No span has zero extent, so an event with no length is the one
      # unit its start is written to: here a second.
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(%{"start" => "2026-06-02T09:00:00"}))

      assert [interval] = IntervalSet.members(set)
      assert Tempo.duration(interval) == ~o"PT1S"
    end

    test "a multi-part duration is applied whole" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{"start" => "2026-06-02T09:00:00", "duration" => "P1DT2H30M"})
               )

      assert spans(set) == ["2026Y6M2DT9H0M0S/3DT11H30M0S"]
    end

    test "an event with no start is skipped, not fatal" do
      assert {:ok, set} = Tempo.JSCalendar.parse(event(%{"title" => "Someday"}))

      assert IntervalSet.count(set) == 0
    end

    test "metadata rides along on the interval" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-02T09:00:00",
                   "title" => "Review",
                   "status" => "confirmed"
                 })
               )

      assert [interval] = IntervalSet.members(set)
      assert interval.metadata.uid == "e"
      assert interval.metadata.title == "Review"
      assert interval.metadata.status == "confirmed"
    end
  end

  describe "time zones" do
    test "a zoned event is anchored to that zone" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-02T09:00:00",
                   "timeZone" => "Australia/Sydney",
                   "duration" => "PT1H"
                 })
               )

      assert [interval] = IntervalSet.members(set)
      assert Interval.from(interval).zone.name == "Australia/Sydney"
    end

    test "an event with no zone floats, rather than adopting the reader's" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(%{"start" => "2026-06-02T09:00:00"}))

      assert [interval] = IntervalSet.members(set)
      assert Tempo.floating?(interval)
    end

    test "an explicit null zone floats too" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{"start" => "2026-06-02T09:00:00", "timeZone" => :null})
               )

      assert [interval] = IntervalSet.members(set)
      assert Tempo.floating?(interval)
    end

    test "an hour-long meeting stays an hour long across a DST boundary" do
      # This is why RFC 8984 stores start-and-duration rather than
      # start-and-end. Sydney leaves daylight saving at 03:00 on
      # 5 April 2026; an event at 02:30 that morning is one hour of
      # wall clock either way.
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-04-05T01:00:00",
                   "timeZone" => "Australia/Sydney",
                   "duration" => "PT1H"
                 })
               )

      assert [interval] = IntervalSet.members(set)
      assert Tempo.hour(Interval.to(interval)) == 2
    end

    test "an unknown zone is an error naming it" do
      assert {:error, %Tempo.ZoneError{zone: "Mars/Olympus_Mons", reason: :unknown}} =
               Tempo.JSCalendar.parse(
                 event(%{"start" => "2026-06-02T09:00:00", "timeZone" => "Mars/Olympus_Mons"})
               )
    end
  end

  describe "recurrence" do
    test "a counted rule expands to that many occurrences" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "daily", "count" => 3}
                   ]
                 })
               )

      assert IntervalSet.count(set) == 3
    end

    test "each occurrence keeps the event's own span, not a stub" do
      # The bug this guards: materialising a recurrence yields start
      # moments with a one-unit span unless the duration is carried.
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "daily", "count" => 2}
                   ]
                 })
               )

      for interval <- IntervalSet.members(set) do
        assert Tempo.hour(Interval.to(interval)) - Tempo.hour(Interval.from(interval)) ==
                 1
      end
    end

    test "an unbounded rule needs a :within window" do
      json =
        event(%{
          "start" => "2026-06-01T09:00:00",
          "duration" => "PT1H",
          "recurrenceRules" => [%{"@type" => "RecurrenceRule", "frequency" => "daily"}]
        })

      assert {:error, _needs_window} = Tempo.JSCalendar.parse(json)

      # A window written to a date runs through it: the first to the fifth.
      assert {:ok, set} = Tempo.JSCalendar.parse(json, within: ~o"2026Y6M1D/5D")
      assert IntervalSet.count(set) == 5
    end

    test "a rule passes over a month that lacks the start's day, unless it says to keep the last" do
      monthly = fn rule ->
        Tempo.JSCalendar.parse(
          ruled("2026-01-31T09:00:00", %{"frequency" => "monthly", "count" => 4}, rule)
        )
      end

      # RFC 8984 §4.3.3: `skip` is "omit" where a rule does not say.
      omitted = [
        "2026Y1M31DT9H0M0S/T10H0M0S",
        "2026Y3M31DT9H0M0S/T10H0M0S",
        "2026Y5M31DT9H0M0S/T10H0M0S",
        "2026Y7M31DT9H0M0S/T10H0M0S"
      ]

      assert {:ok, set} = monthly.(%{})
      assert spans(set) == omitted

      assert {:ok, set} = monthly.(%{"skip" => "omit"})
      assert spans(set) == omitted

      # RFC 7529's other ways with a day a month lacks: the month's last
      # day, or the first of the month after.
      assert {:ok, set} = monthly.(%{"skip" => "backward"})

      assert spans(set) == [
               "2026Y1M31DT9H0M0S/T10H0M0S",
               "2026Y2M28DT9H0M0S/T10H0M0S",
               "2026Y3M31DT9H0M0S/T10H0M0S",
               "2026Y4M30DT9H0M0S/T10H0M0S"
             ]

      assert {:ok, set} = monthly.(%{"skip" => "forward"})

      assert spans(set) == [
               "2026Y1M31DT9H0M0S/T10H0M0S",
               "2026Y3M1DT9H0M0S/T10H0M0S",
               "2026Y3M31DT9H0M0S/T10H0M0S",
               "2026Y5M1DT9H0M0S/T10H0M0S"
             ]

      assert {:error, %Tempo.ConversionError{value: "sideways", reason: {:unsupported, :skip}}} =
               monthly.(%{"skip" => "sideways"})
    end

    # RFC 8984 §4.3.3: `rscale` names the calendar a rule counts its months
    # and its days in. A rule is counted in the Gregorian calendar, which is
    # what it is where it does not say; another is the calendar of the
    # occurrences.
    test "a rule counted in another calendar has its occurrences in it" do
      yearly = fn rule ->
        Tempo.JSCalendar.parse(
          ruled("2026-04-05T09:00:00", %{"frequency" => "yearly", "count" => 2}, rule)
        )
      end

      assert {:ok, gregorian} = yearly.(%{"rscale" => "gregorian"})
      assert {:ok, unsaid} = yearly.(%{})
      assert spans(gregorian) == spans(unsaid)
      assert spans(unsaid) == ["2026Y4M5DT9H0M0S/T10H0M0S", "2027Y4M5DT9H0M0S/T10H0M0S"]

      # 5 April 2026 is 18 Nisan 5786, and 18 Nisan 5787 is 25 April 2027.
      assert {:ok, hebrew} = yearly.(%{"rscale" => "hebrew"})

      assert gregorian_dates(hebrew) == [~D[2026-04-05], ~D[2027-04-25]]

      assert {:error, %ArgumentError{}} = yearly.(%{"rscale" => "klingon"})
    end

    test "byDay carries its ordinal" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceRules" => [
                     %{
                       "@type" => "RecurrenceRule",
                       "frequency" => "monthly",
                       "count" => 3,
                       "byDay" => [%{"@type" => "NDay", "day" => "mo", "nthOfPeriod" => 1}]
                     }
                   ]
                 })
               )

      # The first Monday of three consecutive months.
      assert IntervalSet.count(set) == 3

      for interval <- IntervalSet.members(set) do
        assert Tempo.day(Interval.from(interval)) <= 7
      end
    end

    test "excludedRecurrenceRules removes occurrences" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "daily", "count" => 6}
                   ],
                   "excludedRecurrenceRules" => [
                     %{
                       "@type" => "RecurrenceRule",
                       "frequency" => "daily",
                       "interval" => 2,
                       "count" => 3
                     }
                   ]
                 })
               )

      # Six daily occurrences, every second one excluded.
      assert IntervalSet.count(set) == 3
    end

    test "an unsupported frequency is reported, not guessed at" do
      assert {:error,
              %Tempo.ConversionError{value: "fortnightly", reason: :unsupported_frequency}} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "fortnightly"}
                   ]
                 })
               )
    end

    test "a leap month is a month of a calendar that has one" do
      # RFC 8984 writes byMonth as strings so that `"5L"` can name a leap
      # month of the calendar `rscale` names.
      yearly = fn rule ->
        Tempo.JSCalendar.parse(
          ruled("2014-02-08T09:00:00", %{"frequency" => "yearly", "count" => 5}, rule)
        )
      end

      assert {:error, %ArgumentError{message: message}} = yearly.(%{"byMonth" => ["3L"]})
      assert message =~ "a leap month"

      # RFC 7529 section 4.3.3: the eighth of Adar I, taken as the eighth of
      # Adar in a year with no leap month.
      assert {:ok, anniversary} =
               yearly.(%{
                 "rscale" => "hebrew",
                 "byMonth" => ["5L"],
                 "byMonthDay" => [8],
                 "skip" => "forward"
               })

      assert gregorian_dates(anniversary) ==
               [~D[2014-02-08], ~D[2015-02-27], ~D[2016-02-17], ~D[2017-03-06], ~D[2018-02-23]]

      assert {:ok, set} = yearly.(%{"byMonth" => ["3"]})
      assert set |> IntervalSet.members() |> hd() |> Interval.from() |> Tempo.month() == 3
    end
  end

  describe "recurrence overrides" do
    test "an override with no matching rule adds an occurrence" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "daily", "count" => 2}
                   ],
                   "recurrenceOverrides" => %{"2026-06-05T09:00:00" => %{}}
                 })
               )

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M2DT9H0M0S/T10H0M0S",
               "2026Y6M5DT9H0M0S/T10H0M0S"
             ]
    end

    test "an excluded override removes one occurrence" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "daily", "count" => 3}
                   ],
                   "recurrenceOverrides" => %{"2026-06-02T09:00:00" => %{"excluded" => true}}
                 })
               )

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M3DT9H0M0S/T10H0M0S"
             ]
    end

    test "a patched start moves an occurrence without duplicating it" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "daily", "count" => 3}
                   ],
                   "recurrenceOverrides" => %{
                     "2026-06-02T09:00:00" => %{"start" => "2026-06-02T14:00:00"}
                   }
                 })
               )

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M2DT14H0M0S/T15H0M0S",
               "2026Y6M3DT9H0M0S/T10H0M0S"
             ]
    end

    test "a patched duration changes only that occurrence" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "daily", "count" => 2}
                   ],
                   "recurrenceOverrides" => %{"2026-06-02T09:00:00" => %{"duration" => "PT3H"}}
                 })
               )

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M2DT9H0M0S/T12H0M0S"
             ]
    end

    test "an event with overrides and no rules is still recurring" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceOverrides" => %{"2026-06-08T09:00:00" => %{"duration" => "PT2H"}}
                 })
               )

      assert spans(set) == [
               "2026Y6M1DT9H0M0S/T10H0M0S",
               "2026Y6M8DT9H0M0S/T11H0M0S"
             ]
    end

    test "an override matches on the recurrence id in the event's own zone" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "timeZone" => "Australia/Sydney",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "daily", "count" => 3}
                   ],
                   "recurrenceOverrides" => %{"2026-06-02T09:00:00" => %{"excluded" => true}}
                 })
               )

      assert IntervalSet.count(set) == 2
    end

    test "an override title reaches the interval metadata" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "title" => "Standup",
                   "recurrenceRules" => [
                     %{"@type" => "RecurrenceRule", "frequency" => "daily", "count" => 2}
                   ],
                   "recurrenceOverrides" => %{"2026-06-02T09:00:00" => %{"title" => "Retro"}}
                 })
               )

      assert [first, second] = IntervalSet.members(set)
      assert first.metadata.title == "Standup"
      assert second.metadata.title == "Retro"
      assert second.metadata.uid == "e"
    end

    test "an invalid patch fails the import rather than being half applied" do
      assert {:error, _reason} =
               Tempo.JSCalendar.parse(
                 event(%{
                   "start" => "2026-06-01T09:00:00",
                   "duration" => "PT1H",
                   "recurrenceOverrides" => %{"2026-06-08T09:00:00" => %{"a" => 1, "a/b" => 2}}
                 })
               )
    end
  end

  describe "tasks and groups" do
    test "a task occupies no time" do
      json = ~s({"@type":"Task","uid":"t","title":"Write it up","due":"2026-06-02T17:00:00"})

      assert {:ok, set} = Tempo.JSCalendar.parse(json)
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

      assert {:ok, set} = Tempo.JSCalendar.parse(json)

      assert spans(set) == [
               "2026Y6M2DT9H0M0S/T10H0M0S",
               "2026Y6M3DT9H0M0S/T10H0M0S"
             ]
    end
  end

  describe "bad input" do
    test "a malformed document is an error, not a crash" do
      assert {:error, :invalid_json} = Tempo.JSCalendar.parse("{{{")
    end

    test "an unrecognised object type is reported" do
      assert {:error, {:unknown_type, "Sandwich"}} =
               Tempo.JSCalendar.parse(~s({"@type":"Sandwich"}))
    end
  end

  describe "alongside iCalendar" do
    test "both formats reach the same interval algebra" do
      # The point of the module: JSCalendar and iCalendar are two
      # spellings of the same calendar, and both land on a timeline
      # where set operations work.
      {:ok, from_js} =
        Tempo.JSCalendar.parse(event(%{"start" => "2026-06-02T09:00:00", "duration" => "PT8H"}))

      {:ok, busy} =
        Tempo.JSCalendar.parse(
          ~s({"@type":"Event","uid":"lunch","start":"2026-06-02T12:00:00","duration":"PT1H"})
        )

      assert {:ok, free} = Tempo.difference(from_js, busy)
      assert IntervalSet.count(free) == 2
    end
  end

  # A rule whose step is no step, whose count is none, or whose day of the
  # week is no day (`test/tempo/recurrence_step_and_count_test.exs`). An
  # interval of 0 gave the start again for each of its count, a count of 0
  # was read as no count, and a day that is no day (`"TU"`, or one left
  # out) was read as Monday. The measure for a day of the week is Elixir's
  # own `Date.day_of_week/1`.
  defp rule_event(rule), do: ruled("2026-06-01T09:00:00", %{}, rule)

  defp starts({:ok, %Tempo{} = set}) do
    Enum.map(IntervalSet.members(set), &Interval.from/1)
  end

  defp dates({:ok, %Tempo{} = set}) do
    for member <- IntervalSet.members(set) do
      {:ok, date} =
        member
        |> Interval.from()
        |> Tempo.trunc!(:day)
        |> Tempo.to_date()

      date
    end
  end

  describe "a JSCalendar rule" do
    test "that steps by nothing is refused, and one with a count of none has no occurrences" do
      assert {:error, %Tempo.IntervalEndpointsError{reason: :empty}} =
               Tempo.JSCalendar.parse(
                 rule_event(%{"frequency" => "monthly", "count" => 3, "interval" => 0})
               )

      assert starts(Tempo.JSCalendar.parse(rule_event(%{"frequency" => "daily", "count" => 0}))) ==
               []
    end

    test "names each day of the week by its two letters" do
      # 1 June 2026 is a Monday, so the first of each day after it is in
      # that week.
      for {code, weekday} <- Enum.with_index(~w(mo tu we th fr sa su), 1) do
        rule = %{
          "frequency" => "weekly",
          "count" => 2,
          "byDay" => [%{"@type" => "NDay", "day" => code}]
        }

        on = dates(Tempo.JSCalendar.parse(rule_event(rule)))

        assert {code, Enum.map(on, &Date.day_of_week/1)} == {code, [weekday, weekday]}

        assert {code, on} ==
                 {code,
                  [Date.add(~D[2026-06-01], weekday - 1), Date.add(~D[2026-06-08], weekday - 1)]}
      end
    end

    test "with a day of the week that is no day is refused" do
      for day <- [
            %{"day" => "xx"},
            %{"day" => "TU"},
            %{"day" => "monday"},
            %{"day" => ""},
            %{"nthOfPeriod" => 1}
          ] do
        rule = %{
          "frequency" => "weekly",
          "count" => 3,
          "byDay" => [Map.merge(%{"@type" => "NDay"}, day)]
        }

        assert {^day, {:error, %Tempo.ConversionError{reason: :unsupported_day}}} =
                 {day, Tempo.JSCalendar.parse(rule_event(rule))}
      end

      # A rule's weeks start on Monday where it does not say. Another day is
      # read: where it changes the weeks counted the occurrences are of the
      # weeks that begin on it, and where it does not it changes nothing.
      assert {:ok, _events} =
               Tempo.JSCalendar.parse(
                 rule_event(%{"frequency" => "weekly", "count" => 3, "firstDayOfWeek" => "su"})
               )

      assert {:ok, %Tempo{}} =
               Tempo.JSCalendar.parse(rule_event(%{"frequency" => "weekly", "count" => 3}))
    end
  end
end
