defmodule Tempo.BuilderTest do
  use ExUnit.Case, async: true

  # A pipeline of steps builds the expression its text reads to (decisions
  # 45 to 47): each step's result is that expression, and an error passes
  # through the steps after it.

  import Tempo.Sigils
  import Tempo.Builder

  alias Tempo.{Interval, IntervalSet, RRule}

  @built [
    {"R/../P1W", quote(do: every(:week))},
    {"R/../P2W", quote(do: every(week: 2))},
    {"R/../P1M", quote(do: every(~o"P1M"))},
    {"R/../P1W/FL1KN", quote(do: every(:week) |> on(:monday))},
    {"R/../P1W/FL{1,3,5}KN", quote(do: every(:week) |> on([:monday, :wednesday, :friday]))},
    {"R/../P1M/FL1K2IN", quote(do: every(:month) |> on(:monday, nth: 2))},
    {"R/../P1M/FL5K-1IN", quote(do: every(:month) |> on(:friday, nth: -1))},
    {"R/../P1Y/FL12M25DN", quote(do: every(:year) |> on(month: 12, day: 25))},
    {"R/../P1Y/FL(easter)eN", quote(do: every(:year) |> on(event: "easter"))},
    {"R/../P1W/FL1KT9HN", quote(do: every(:week) |> on(:monday) |> at(hour: 9))},
    {"R/../P1W/FL1KT9HN", quote(do: every(:week) |> at(hour: 9) |> on(:monday))},
    {"R/../P1D/FLT9H30MN", quote(do: every(:day) |> at(~o"T09:30"))},
    {"R/../P1M/FL-1DT17HN", quote(do: every(:month) |> on(day: -1) |> at(hour: 17))},
    {"2026Y6ML1KN", quote(do: on(~o"2026-06", :monday))},
    {"2026Y6ML1KT9HN", quote(do: ~o"2026-06" |> on(:monday) |> at(hour: 9))},
    {"{2026Y6ML1KN,2026Y8ML1KN}", quote(do: on(~o"{2026-06,2026-08}", :monday))},
    {"R/2026-06-01/P1W/FL1KN",
     quote(do: every(:week) |> on(:monday) |> starting(~o"2026-06-01"))},
    {"R/2026-06-01/P1W/FL1KN",
     quote(do: every(:week) |> starting(~o"2026-06-01") |> on(:monday))},
    {"R10/2026-06-01/P1W/FL1KT9HN",
     quote(
       do:
         every(:week)
         |> on(:monday)
         |> at(hour: 9)
         |> starting(~o"2026-06-01")
         |> times(10)
     )},
    {"R10/2026-06-01/P1W/FL1KT9HN",
     quote(
       do:
         every(:week)
         |> times(10)
         |> at(hour: 9)
         |> starting(~o"2026-06-01")
         |> on(:monday)
     )},
    {"R/2026-06-01/P1D/2026-06-30",
     quote(do: every(:day) |> starting(~o"2026-06-01") |> until(~o"2026-06-30"))},
    {"2026-06-01/2026-06-12", quote(do: until(~o"2026-06-01", ~o"2026-06-12"))},
    {"R5/P1M/2026-06-01", quote(do: every(:month) |> ending(~o"2026-06-01") |> times(5))},
    {"R/../P1W/FL1KT9HN[Europe/Paris]",
     quote(do: every(:week) |> on(:monday) |> at(hour: 9) |> in_zone("Europe/Paris"))},
    {"R10/2026-06-01T09:00/P1W[Europe/Paris]",
     quote(
       do:
         every(:week)
         |> in_zone("Europe/Paris")
         |> starting(~o"2026-06-01T09:00")
         |> times(10)
     )},
    {"R10/2026-06-01T09:00/P1W[+02:00]",
     quote(do: every(:week) |> in_zone("+02:00") |> starting(~o"2026-06-01T09:00") |> times(10))},
    {"R/../P1Y/FL7M1DN[u-ca=hebrew]",
     quote(do: every(:year) |> on(month: 7, day: 1) |> in_calendar(Calendrical.Hebrew))},
    {"R/..l/P1Y/FL2M29DN", quote(do: every(:year) |> on(month: 2, day: 29) |> in_years(:leap))},
    {"R/{2026Y..2030Y}e/P1Y/FL7M4DN",
     quote(
       do:
         every(:year)
         |> on(month: 7, day: 4)
         |> starting(~o"{2026Y..2030Y}")
         |> in_years(:even)
     )},
    {"R/{2026Y..2030Y}/P1Y/FL7M4DN",
     quote(do: every(:year) |> on(month: 7, day: 4) |> in_years(2026..2030))},
    {"R/{2017Y..}l/P1Y/FL2M29DN",
     quote(do: every(:year) |> on(month: 2, day: 29) |> in_years(from: 2017) |> in_years(:leap))},
    {"R/../P1Y/FLL7KN/PT1HN", quote(do: every(:year) |> on(:sunday) |> lasting(hour: 1))},
    {"R/../P1Y/FL11MLL1K1IN/P1DN2KN",
     quote(
       do:
         every(:year)
         |> on(
           month: 11,
           selection: [selection: [day_of_week: 1, instance: 1], window: ~o"P1D"],
           day_of_week: 2
         )
     )},
    {"R/2025-01-01/P1M/FL{1..5}K-1IN",
     quote(do: every(:month) |> on(day_of_week: 1..5, instance: -1) |> starting(~o"2025-01-01"))},
    {"R/2025-01-01T00:00/P1M/FLL{1..5}K-1INT{9,10}HN",
     quote(
       do:
         every(:month)
         |> on(day_of_week: 1..5, instance: -1)
         |> at(hour: [9, 10])
         |> starting(~o"2025-01-01T00:00")
     )},
    {"R/../P1M/FLL1K2INT9HN", quote(do: every(:month) |> on(:monday, nth: 2) |> at(hour: 9))},
    {"R/../P1Y/FL1M1K2IN", quote(do: every(:year) |> on(:monday, nth: 2) |> on(month: 1))},
    {"{R/2026-06-01/P1W,^2026-06-08}",
     quote(do: every(:week) |> starting(~o"2026-06-01") |> except(~o"2026-06-08"))},
    {"{R/2026-06-01/P1W,^2026-06-08,^2026-06-15}",
     quote(
       do:
         every(:week)
         |> starting(~o"2026-06-01")
         |> except(~o"2026-06-08")
         |> except([~o"2026-06-15"])
     )}
  ]

  for {{text, built}, index} <- Enum.with_index(@built) do
    test "#{index}: #{text} is built as it is read" do
      assert unquote(built) == Tempo.from_iso8601(unquote(text))
    end
  end

  # RFC 5545 section 3.8.5.3's examples, each rule built with the steps and
  # held to the text the RRULE reads to with the example's DTSTART in New York.
  defp new_york(year, month, day) do
    Tempo.new!(
      year: year,
      month: month,
      day: day,
      hour: 9,
      minute: 0,
      second: 0,
      zone: "America/New_York"
    )
  end

  @rfc5545 [
    {"FREQ=DAILY;COUNT=10", "R10/1997Y9M2DT9H0M0S/P1D/FLT9HN[America/New_York]",
     quote(do: every(:day) |> at(hour: 9) |> starting(new_york(1997, 9, 2)) |> times(10))},
    {"FREQ=DAILY;UNTIL=19971224T000000Z",
     "R/1997Y9M2DT9H0M0S/P1D/1997Y12M24DT0H0M0SZ/FLT9HN[America/New_York]",
     quote(
       do:
         every(:day)
         |> at(hour: 9)
         |> starting(new_york(1997, 9, 2))
         |> until(~o"1997-12-24T00:00:00Z")
     )},
    {"FREQ=DAILY;INTERVAL=10;COUNT=5", "R5/1997Y9M2DT9H0M0S/P10D/FLT9HN[America/New_York]",
     quote(do: every(day: 10) |> at(hour: 9) |> starting(new_york(1997, 9, 2)) |> times(5))},
    {"FREQ=YEARLY;UNTIL=20000131T140000Z;BYMONTH=1;BYDAY=SU,MO,TU,WE,TH,FR,SA",
     "R/1998Y1M1DT9H0M0S/P1Y/2000Y1M31DT14H0M0SZ/FL1M{7,1,2,3,4,5,6}KN[America/New_York]",
     quote(
       do:
         every(:year)
         |> on(month: 1)
         |> on([:sunday, :monday, :tuesday, :wednesday, :thursday, :friday, :saturday])
         |> starting(new_york(1998, 1, 1))
         |> until(~o"2000-01-31T14:00:00Z")
     )},
    {"FREQ=WEEKLY;COUNT=10;WKST=SU;BYDAY=TU,TH",
     "R10/1997Y9M2DT9H0M0S/P1W/FL{2,4}KN[America/New_York]",
     quote(
       do:
         every(:week) |> on([:tuesday, :thursday]) |> starting(new_york(1997, 9, 2)) |> times(10)
     )},
    {"FREQ=WEEKLY;INTERVAL=2;UNTIL=19971224T000000Z;WKST=SU;BYDAY=MO,WE,FR",
     "R/1997Y9M1DT9H0M0S/P2W/1997Y12M24DT0H0M0SZ/FL{1,3,5}KN[America/New_York][u-fw=sun]",
     quote(
       do:
         every(week: 2)
         |> weeks_beginning(:sunday)
         |> on([:monday, :wednesday, :friday])
         |> starting(new_york(1997, 9, 1))
         |> until(~o"1997-12-24T00:00:00Z")
     )},
    {"FREQ=MONTHLY;COUNT=10;BYDAY=1FR", "R10/1997Y9M5DT9H0M0S/P1M/FL5K1IN[America/New_York]",
     quote(
       do: every(:month) |> on(:friday, nth: 1) |> starting(new_york(1997, 9, 5)) |> times(10)
     )},
    {"FREQ=MONTHLY;INTERVAL=2;COUNT=10;BYDAY=1SU,-1SU",
     "R10/1997Y9M7DT9H0M0S/P2M/FL7K{1,-1}IN[America/New_York]",
     quote(
       do:
         every(month: 2)
         |> on(day_of_week: 7, instance: [1, -1])
         |> starting(new_york(1997, 9, 7))
         |> times(10)
     )},
    {"FREQ=MONTHLY;BYMONTHDAY=-3", "R/1997Y9M28DT9H0M0S/P1M/FL-3DN[America/New_York]",
     quote(do: every(:month) |> on(day: -3) |> starting(new_york(1997, 9, 28)))},
    {"FREQ=YEARLY;INTERVAL=3;COUNT=10;BYYEARDAY=1,100,200",
     "R10/1997Y1M1DT9H0M0S/P3Y/FL{1,100,200}ON[America/New_York]",
     quote(
       do:
         every(year: 3)
         |> on(day_of_year: [1, 100, 200])
         |> starting(new_york(1997, 1, 1))
         |> times(10)
     )},
    {"FREQ=YEARLY;BYDAY=20MO", "R/1997Y5M19DT9H0M0S/P1Y/FL1K20IN[America/New_York]",
     quote(do: every(:year) |> on(:monday, nth: 20) |> starting(new_york(1997, 5, 19)))},
    {"FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO", "R/1997Y5M12DT9H0M0S/P1Y/FL20W1KN[America/New_York]",
     quote(do: every(:year) |> on(week: 20) |> on(:monday) |> starting(new_york(1997, 5, 12)))},
    {"FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13", "R/1997Y9M2DT9H0M0S/P1M/FL13D5KN[America/New_York]",
     quote(do: every(:month) |> on(day: 13) |> on(:friday) |> starting(new_york(1997, 9, 2)))},
    {"FREQ=YEARLY;INTERVAL=4;BYMONTH=11;BYDAY=TU;BYMONTHDAY=2,3,4,5,6,7,8",
     "R/1996Y11M5DT9H0M0S/P4Y/FL11M{2,3,4,5,6,7,8}D2KN[America/New_York]",
     quote(
       do:
         every(year: 4)
         |> on(month: 11, day: [2, 3, 4, 5, 6, 7, 8])
         |> on(:tuesday)
         |> starting(new_york(1996, 11, 5))
     )},
    {"FREQ=MONTHLY;COUNT=3;BYDAY=TU,WE,TH;BYSETPOS=3",
     "R3/1997Y9M4DT9H0M0S/P1M/FL{2,3,4}K3IN[America/New_York]",
     quote(
       do:
         every(:month)
         |> on([:tuesday, :wednesday, :thursday], nth: 3)
         |> starting(new_york(1997, 9, 4))
         |> times(3)
     )},
    {"FREQ=MINUTELY;INTERVAL=15;COUNT=6", "R6/1997Y9M2DT9H0M0S/PT15M/FLT0SN[America/New_York]",
     quote(do: every(minute: 15) |> at(second: 0) |> starting(new_york(1997, 9, 2)) |> times(6))},
    {"FREQ=DAILY;BYHOUR=9,10,11,12,13,14,15,16;BYMINUTE=0,20,40",
     "R/1997Y9M2DT9H0M0S/P1D/FLT{9,10,11,12,13,14,15,16}H{0,20,40}MN[America/New_York]",
     quote(
       do:
         every(:day)
         |> at(hour: [9, 10, 11, 12, 13, 14, 15, 16], minute: [0, 20, 40])
         |> starting(new_york(1997, 9, 2))
     )}
  ]

  for {{rule, text, built}, index} <- Enum.with_index(@rfc5545) do
    test "RFC 5545 #{index}: #{rule} is built as it is read" do
      {:ok, read} = Tempo.from_iso8601(unquote(text))

      assert unquote(built) == {:ok, read}
    end
  end

  test "each RFC 5545 rule built is the rule its RRULE reads to" do
    for {rule, {year, month, day}, text} <- [
          {"FREQ=DAILY;UNTIL=19971224T000000Z", {1997, 9, 2},
           "R/1997Y9M2DT9H0M0S/P1D/1997Y12M24DT0H0M0SZ/FLT9HN[America/New_York]"},
          {"FREQ=WEEKLY;INTERVAL=2;UNTIL=19971224T000000Z;WKST=SU;BYDAY=MO,WE,FR", {1997, 9, 1},
           "R/1997Y9M1DT9H0M0S/P2W/1997Y12M24DT0H0M0SZ/FL{1,3,5}KN[America/New_York][u-fw=sun]"},
          {"FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13", {1997, 9, 2},
           "R/1997Y9M2DT9H0M0S/P1M/FL13D5KN[America/New_York]"},
          {"FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO", {1997, 5, 12},
           "R/1997Y5M12DT9H0M0S/P1Y/FL20W1KN[America/New_York]"}
        ] do
      assert {rule, RRule.parse(rule, from: new_york(year, month, day))} ==
               {rule, Tempo.from_iso8601(text)}
    end
  end

  describe "what is built is used as what is read" do
    test "the second Monday of each month is the day Date says" do
      {:ok, second_mondays} = every(:month) |> on(:monday, nth: 2)

      built =
        second_mondays
        |> Tempo.to_interval!(within: ~o"2026")
        |> IntervalSet.map(&(&1 |> Interval.from() |> Tempo.to_date() |> elem(1)))

      expected =
        for month <- 1..12 do
          first = Date.new!(2026, month, 1)
          Date.add(first, rem(8 - Date.day_of_week(first), 7) + 7)
        end

      assert built == expected
    end

    test "a time given to the second Monday is that time on each second Monday" do
      {:ok, at_nine} = every(:month) |> on(:monday, nth: 2) |> at(hour: 9)

      built =
        at_nine
        |> Tempo.to_interval!(within: ~o"2026")
        |> IntervalSet.map(&(&1 |> Interval.from() |> Tempo.to_naive_datetime() |> elem(1)))

      expected =
        for month <- 1..12 do
          first = Date.new!(2026, month, 1)

          NaiveDateTime.new!(
            Date.add(first, rem(8 - Date.day_of_week(first), 7) + 7),
            ~T[09:00:00]
          )
        end

      assert built == expected
    end

    test "the Mondays of a month at nine are its Mondays, each at nine" do
      {:ok, mondays} = ~o"2026-06" |> on(:monday) |> at(hour: 9)

      assert mondays |> Tempo.to_interval!() |> IntervalSet.map(&Interval.from/1) ==
               [
                 ~o"2026-06-01T09",
                 ~o"2026-06-08T09",
                 ~o"2026-06-15T09",
                 ~o"2026-06-22T09",
                 ~o"2026-06-29T09"
               ]
    end
  end

  describe "the steps of a recurrence's frame and end" do
    test "a zone given first places the start given after it" do
      {:ok, paris} = every(:week) |> in_zone("Europe/Paris") |> starting(~o"2026-06-01T09:00")

      first =
        paris |> Tempo.to_interval!(within: ~o"2026-06") |> IntervalSet.first() |> Interval.from()

      {:ok, nine_in_paris} = Tempo.to_datetime(first)

      assert DateTime.to_unix(nine_in_paris) ==
               DateTime.to_unix(DateTime.new!(~D[2026-06-01], ~T[09:00:00], "Europe/Paris"))
    end

    test "metadata is carried by the recurrence and its occurrences" do
      {:ok, standup} =
        every(:day)
        |> starting(~o"2026-06-01")
        |> times(2)
        |> with_metadata(%{title: "Standup"})

      assert Tempo.metadata(standup) == %{title: "Standup"}

      assert Enum.map(IntervalSet.members(standup), &Tempo.metadata/1) == [
               %{title: "Standup"},
               %{title: "Standup"}
             ]
    end
  end

  describe "an error" do
    test "passes through every step after it, unchanged" do
      {:error, error} = every(:fortnight)

      assert every(:fortnight) |> on(:monday) |> at(hour: 9) == {:error, error}
    end

    test "is named for what cannot be built" do
      assert {:error, %ArgumentError{message: message}} = every(:week) |> on(:someday)
      assert message =~ "weekday"

      assert {:error, %ArgumentError{message: message}} =
               every(:week) |> on(:monday) |> on(:friday)

      assert message =~ ":day_of_week is already selected"

      assert {:error, %ArgumentError{}} = every(:week) |> at(~o"2026-06-01T09")
      assert {:error, %ArgumentError{}} = every(:month) |> on(:monday, nth: 0)
      assert {:error, %ArgumentError{}} = every(:month) |> on(:monday, first: true)
      assert {:error, %ArgumentError{}} = on(~o"2026-06-01/2026-06-30", :monday)

      assert {:error, %ArgumentError{}} = every(:week) |> times(3) |> until(~o"2026-06-30")
      assert {:error, %ArgumentError{}} = every(:week) |> times(0)

      assert {:error, %ArgumentError{}} =
               every(:week) |> starting(~o"2026-06-01") |> ending(~o"2026-07-01")

      assert {:error, %ArgumentError{}} =
               every(:year) |> starting(~o"2026") |> in_calendar(Calendrical.Hebrew)

      assert {:error, %ArgumentError{}} = every(:year) |> starting(~o"2026") |> in_years(:leap)
      assert {:error, %ArgumentError{}} = starting(~o"2026-06", ~o"2026-06-01")
      assert {:error, %ArgumentError{}} = every(:week) |> except("2026-06-08")
      assert {:error, %ArgumentError{}} = every(:week) |> with_metadata(:standup)
      assert {:error, %Tempo.IntervalEndpointsError{}} = until(~o"2026-06-12", ~o"2026-06-01")
      assert {:error, %Tempo.ZoneError{}} = every(:week) |> in_zone("Mars/Olympus_Mons")

      assert {:error, %Tempo.ConversionError{reason: :not_an_expression}} =
               on(~D[2026-06-01], :monday)
    end
  end
end
