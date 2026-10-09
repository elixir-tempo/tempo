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
    |> IntervalSet.members()
    |> Enum.map(&Tempo.to_iso8601!/1)
  end

  describe "a single event" do
    test "becomes one interval, start to start plus duration" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s("start":"2026-06-02T09:00:00","duration":"PT1H")))

      assert spans(set) == ["2026Y6M2DT9H0M0S/T10H0M0S"]
    end

    test "a missing duration is an instant, per the PT0S default" do
      # Tempo has no zero-extent interval, so a punctual event becomes
      # the one-unit span of its start and says so — the same
      # treatment `Tempo.ICal` gives a zero-duration VEVENT.
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s("start":"2026-06-02T09:00:00")))

      assert [interval] = IntervalSet.members(set)
      assert interval.metadata.punctual == true
      refute Tempo.Compare.compare_endpoints(interval.from, interval.to) == :same
    end

    test "a multi-part duration is applied whole" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(~s("start":"2026-06-02T09:00:00","duration":"P1DT2H30M"))
               )

      assert spans(set) == ["2026Y6M2DT9H0M0S/3DT11H30M0S"]
    end

    test "an event with no start is skipped, not fatal" do
      assert {:ok, set} = Tempo.JSCalendar.parse(event(~s("title":"Someday")))

      assert IntervalSet.count(set) == 0
    end

    test "metadata rides along on the interval" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(~s("start":"2026-06-02T09:00:00","title":"Review","status":"confirmed"))
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
                 event(
                   ~s("start":"2026-06-02T09:00:00","timeZone":"Australia/Sydney","duration":"PT1H")
                 )
               )

      assert [interval] = IntervalSet.members(set)
      assert interval.from.extended.zone_id == "Australia/Sydney"
    end

    test "an event with no zone floats, rather than adopting the reader's" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s("start":"2026-06-02T09:00:00")))

      assert [interval] = IntervalSet.members(set)
      assert interval.from.extended == nil
    end

    test "an explicit null zone floats too" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s("start":"2026-06-02T09:00:00","timeZone":null)))

      assert [interval] = IntervalSet.members(set)
      assert interval.from.extended == nil
    end

    test "an hour-long meeting stays an hour long across a DST boundary" do
      # This is why RFC 8984 stores start-and-duration rather than
      # start-and-end. Sydney leaves daylight saving at 03:00 on
      # 5 April 2026; an event at 02:30 that morning is one hour of
      # wall clock either way.
      assert {:ok, set} =
               Tempo.JSCalendar.parse(
                 event(
                   ~s("start":"2026-04-05T01:00:00","timeZone":"Australia/Sydney","duration":"PT1H")
                 )
               )

      assert [interval] = IntervalSet.members(set)
      assert interval.to.time[:hour] == 2
    end

    test "an unknown zone is an error naming it" do
      assert {:error, {:invalid_time_zone, "Mars/Olympus_Mons", _reason}} =
               Tempo.JSCalendar.parse(
                 event(~s("start":"2026-06-02T09:00:00","timeZone":"Mars/Olympus_Mons"))
               )
    end
  end

  describe "recurrence" do
    test "a counted rule expands to that many occurrences" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":3}]
                 )))

      assert IntervalSet.count(set) == 3
    end

    test "each occurrence keeps the event's own span, not a stub" do
      # The bug this guards: materialising a recurrence yields start
      # moments with a one-unit span unless the duration is carried.
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":2}]
                 )))

      for interval <- IntervalSet.members(set) do
        assert interval.to.time[:hour] - interval.from.time[:hour] == 1
      end
    end

    test "an unbounded rule needs a :within window" do
      json =
        event(~s(
          "start":"2026-06-01T09:00:00","duration":"PT1H",
          "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily"}]
        ))

      assert {:error, _needs_window} = Tempo.JSCalendar.parse(json)

      assert {:ok, set} = Tempo.JSCalendar.parse(json, within: ~o"2026Y6M1D/5D")
      assert IntervalSet.count(set) == 4
    end

    test "a rule passes over a month that lacks the start's day, unless it says to keep the last" do
      monthly = fn rule ->
        Tempo.JSCalendar.parse(event(~s(
          "start":"2026-01-31T09:00:00","duration":"PT1H",
          "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"monthly","count":4#{rule}}]
        )))
      end

      # RFC 8984 §4.3.3: `skip` is "omit" where a rule does not say.
      omitted = [
        "2026Y1M31DT9H0M0S/T10H0M0S",
        "2026Y3M31DT9H0M0S/T10H0M0S",
        "2026Y5M31DT9H0M0S/T10H0M0S",
        "2026Y7M31DT9H0M0S/T10H0M0S"
      ]

      assert {:ok, set} = monthly.("")
      assert spans(set) == omitted

      assert {:ok, set} = monthly.(~s(,"skip":"omit"))
      assert spans(set) == omitted

      assert {:ok, set} = monthly.(~s(,"skip":"backward"))

      assert spans(set) == [
               "2026Y1M31DT9H0M0S/T10H0M0S",
               "2026Y2M28DT9H0M0S/T10H0M0S",
               "2026Y3M31DT9H0M0S/T10H0M0S",
               "2026Y4M30DT9H0M0S/T10H0M0S"
             ]

      # "forward" is the first day of the month after.
      assert {:ok, set} = monthly.(~s(,"skip":"forward"))

      assert spans(set) == [
               "2026Y1M31DT9H0M0S/T10H0M0S",
               "2026Y3M1DT9H0M0S/T10H0M0S",
               "2026Y3M31DT9H0M0S/T10H0M0S",
               "2026Y5M1DT9H0M0S/T10H0M0S"
             ]

      # A day the rule writes itself is moved as the start's is.
      assert {:ok, set} = monthly.(~s(,"skip":"backward","byMonthDay":[31]))

      assert spans(set) == [
               "2026Y1M31DT9H0M0S/T10H0M0S",
               "2026Y2M28DT9H0M0S/T10H0M0S",
               "2026Y3M31DT9H0M0S/T10H0M0S",
               "2026Y4M30DT9H0M0S/T10H0M0S"
             ]

      # A day counted from the end that a month lacks is the day before
      # the month's first: moved on, it is the first.
      assert {:ok, set} = monthly.(~s(,"skip":"forward","byMonthDay":[-31]))

      assert spans(set) == [
               "2026Y2M1DT9H0M0S/T10H0M0S",
               "2026Y3M1DT9H0M0S/T10H0M0S",
               "2026Y4M1DT9H0M0S/T10H0M0S",
               "2026Y5M1DT9H0M0S/T10H0M0S"
             ]
    end

    # RFC 8984 §4.3.3: `rscale` names the calendar a rule counts its months
    # and its days in. A Hebrew rule was reported as not built
    # (`:unsupported_rscale`); it is counted from its start's Hebrew date.
    test "a rule counted in another calendar is counted from its start's date there" do
      yearly = fn rule ->
        Tempo.JSCalendar.parse(event(~s(
          "start":"2026-04-05T09:00:00","duration":"PT1H",
          "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"yearly","count":2#{rule}}]
        )))
      end

      assert {:ok, hebrew} = yearly.(~s(,"rscale":"hebrew"))

      # 5 April 2026 is 18 Nisan 5786, and 18 Nisan 5787 is 25 April 2027:
      # the eighth month of a year with a leap month.
      assert Date.convert!(~D[2026-04-05], Calendrical.Hebrew) ==
               Date.new!(5786, 7, 18, Calendrical.Hebrew)

      assert Date.convert!(Date.new!(5787, 8, 18, Calendrical.Hebrew), Calendar.ISO) ==
               ~D[2027-04-25]

      assert spans(hebrew) == [
               "5786Y7M18DT9H0M0S/T10H0M0S[u-ca=hebrew]",
               "5787Y8M18DT9H0M0S/T10H0M0S[u-ca=hebrew]"
             ]

      assert {:ok, gregorian} = yearly.(~s(,"rscale":"gregorian"))
      assert {:ok, unsaid} = yearly.("")
      assert spans(gregorian) == spans(unsaid)
      assert spans(unsaid) == ["2026Y4M5DT9H0M0S/T10H0M0S", "2027Y4M5DT9H0M0S/T10H0M0S"]

      # A name that is no calendar's is reported.
      assert yearly.(~s(,"rscale":"klingon")) == {:error, {:unsupported_rscale, "klingon"}}
    end

    test "byDay carries its ordinal" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"monthly","count":3,
                     "byDay":[{"@type":"NDay","day":"mo","nthOfPeriod":1}]}]
                 )))

      # The first Monday of three consecutive months.
      assert IntervalSet.count(set) == 3

      for interval <- IntervalSet.members(set) do
        assert interval.from.time[:day] <= 7
      end
    end

    test "excludedRecurrenceRules removes occurrences" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s(
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
               Tempo.JSCalendar.parse(event(~s(
                   "start":"2026-06-01T09:00:00",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"fortnightly"}]
                 )))
    end

    test "a lunisolar leap month is a month of the calendar the rule names" do
      # RFC 8984 writes byMonth as strings so `"5L"` can name a leap month:
      # Adar I of a Hebrew year. With `skip` it is the month after it in a
      # year that has none, and RFC 7529 §4.3.3 lists the dates.
      yearly = fn rule ->
        Tempo.JSCalendar.parse(event(~s(
          "start":"2014-02-08T09:00:00","duration":"PT1H",
          "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"yearly","count":5#{rule}}]
        )))
      end

      assert {:ok, set} =
               yearly.(~s(,"rscale":"hebrew","byMonth":["5L"],"byMonthDay":[8],"skip":"forward"))

      dates =
        for occurrence <- Tempo.IntervalSet.members(set) do
          {:ok, start} = Tempo.to_calendar(Tempo.Interval.from(occurrence), Calendrical.Gregorian)
          Date.new!(Tempo.year(start), Tempo.month(start), Tempo.day(start))
        end

      assert dates ==
               [~D[2014-02-08], ~D[2015-02-27], ~D[2016-02-17], ~D[2017-03-06], ~D[2018-02-23]]

      # It is a month of a calendar that has leap months, which the
      # Gregorian, a rule's calendar where it names none (RFC 8984 §4.3.3),
      # has not.
      for rscale <- ["", ~s(,"rscale":"gregorian")] do
        assert yearly.(rscale <> ~s(,"byMonth":["3L"])) ==
                 {:error, {:calendar_has_no_leap_month, {{3, :leap}, Calendrical.Gregorian}}}
      end

      assert yearly.(~s(,"rscale":"hebrew","byMonth":["L3"])) ==
               {:error, {:unsupported_month, "L3"}}
    end
  end

  describe "recurrence overrides" do
    test "an override with no matching rule adds an occurrence" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s(
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
               Tempo.JSCalendar.parse(event(~s(
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
               Tempo.JSCalendar.parse(event(~s(
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
               Tempo.JSCalendar.parse(event(~s(
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
               Tempo.JSCalendar.parse(event(~s(
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
               Tempo.JSCalendar.parse(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "timeZone":"Australia/Sydney",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":3}],
                   "recurrenceOverrides":{"2026-06-02T09:00:00":{"excluded":true}}
                 )))

      assert IntervalSet.count(set) == 2
    end

    test "an override title reaches the interval metadata" do
      assert {:ok, set} =
               Tempo.JSCalendar.parse(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H","title":"Standup",
                   "recurrenceRules":[{"@type":"RecurrenceRule","frequency":"daily","count":2}],
                   "recurrenceOverrides":{"2026-06-02T09:00:00":{"title":"Retro"}}
                 )))

      assert [first, second] = IntervalSet.members(set)
      assert first.metadata.title == "Standup"
      assert second.metadata.title == "Retro"
      assert second.metadata.uid == "e"
    end

    test "an invalid patch fails the import rather than being half applied" do
      assert {:error, _reason} =
               Tempo.JSCalendar.parse(event(~s(
                   "start":"2026-06-01T09:00:00","duration":"PT1H",
                   "recurrenceOverrides":{"2026-06-08T09:00:00":{"a":1,"a/b":2}}
                 )))
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
        Tempo.JSCalendar.parse(event(~s("start":"2026-06-02T09:00:00","duration":"PT8H")))

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
  defp rule_event(rule) do
    event(
      ~s("start":"2026-06-01T09:00:00","duration":"PT1H",) <>
        ~s("recurrenceRules":[{"@type":"RecurrenceRule",#{rule}}])
    )
  end

  defp starts({:ok, %IntervalSet{} = set}),
    do: Enum.map(IntervalSet.members(set), &Tempo.Interval.from/1)

  defp dates({:ok, %IntervalSet{} = set}) do
    for member <- IntervalSet.members(set) do
      {:ok, date} = member |> Tempo.Interval.from() |> Tempo.trunc(:day) |> Tempo.to_date()
      date
    end
  end

  describe "a JSCalendar rule" do
    test "that steps by nothing is refused, and one with a count of none has no occurrences" do
      assert Tempo.JSCalendar.parse(rule_event(~s("frequency":"monthly","count":3,"interval":0))) ==
               {:error, {:invalid_interval, 0}}

      assert starts(Tempo.JSCalendar.parse(rule_event(~s("frequency":"daily","count":0)))) == []
    end

    test "names each day of the week by its two letters" do
      # 1 June 2026 is a Monday, so the first of each day after it is in
      # that week.
      for {code, weekday} <- Enum.with_index(~w(mo tu we th fr sa su), 1) do
        rule = ~s("frequency":"weekly","count":2,"byDay":[{"@type":"NDay","day":"#{code}"}])
        on = dates(Tempo.JSCalendar.parse(rule_event(rule)))

        assert {code, Enum.map(on, &Date.day_of_week/1)} == {code, [weekday, weekday]}

        assert {code, on} ==
                 {code,
                  [Date.add(~D[2026-06-01], weekday - 1), Date.add(~D[2026-06-08], weekday - 1)]}
      end
    end

    test "with a day of the week that is no day is refused" do
      for day <- [
            ~s("day":"xx"),
            ~s("day":"TU"),
            ~s("day":"monday"),
            ~s("day":""),
            ~s("nthOfPeriod":1)
          ] do
        rule = ~s("frequency":"weekly","count":3,"byDay":[{"@type":"NDay",#{day}}])

        assert {^day, {:error, {:unsupported_day, _written}}} =
                 {day, Tempo.JSCalendar.parse(rule_event(rule))}
      end

      assert Tempo.JSCalendar.parse(
               rule_event(~s("frequency":"weekly","count":3,"firstDayOfWeek":"xx"))
             ) ==
               {:error, {:unsupported_day, "xx"}}

      # A rule's weeks start on Monday where it does not say, and on the day
      # it names where it does.
      assert {:ok, %IntervalSet{}} =
               Tempo.JSCalendar.parse(
                 rule_event(~s("frequency":"weekly","count":3,"firstDayOfWeek":"su"))
               )

      assert {:ok, %IntervalSet{}} =
               Tempo.JSCalendar.parse(rule_event(~s("frequency":"weekly","count":3)))
    end
  end
end
