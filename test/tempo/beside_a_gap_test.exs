defmodule Tempo.BesideAGapTest do
  @moduledoc """
  Values beside a reading their zone's clock skips.

  A value written on a reading the clock skips the whole of is refused when
  it is read: the hour a spring-forward skips, a minute inside it, a day a
  zone leaves out. An operation that gives one gives a value no one could
  have written, and several did: a set or unspecified digits that name one
  among others converted to a span that starts on it, a value extended to a
  finer unit started on it, a step of days from a week landed on it, and the
  first hour `Enum.at/2` gave of a day was it.

  `Tempo.BesideAGap` gives values beside five gaps (New York, Paris, Lord
  Howe Island, Cairo and Samoa) to every operation that makes values, some
  three and a half thousand cells, and holds each value given to being
  written and read as itself. The worked examples here hold the answers
  themselves, each against Elixir's own `DateTime`.

  A time of day the clock skips, selected on a day that has the gap, was
  given as the skipped reading until it was decided (2026-10-07): it is not
  selected, and a window is the part of it the clock shows.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.BesideAGap
  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  setup_all do
    {:ok, harvest: BesideAGap.harvest()}
  end

  defp found(%{findings: findings}, property) do
    for {^property, operation, text, detail} <- findings, do: {operation, text, detail}
  end

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  # The moment a value starts at, and the moment Elixir places a reading of
  # the wall clock at, each as seconds since 1970.
  defp moment(%Tempo{} = value), do: Compare.to_utc_seconds(value) - @unix_epoch

  defp moment(%NaiveDateTime{} = reading, zone),
    do: reading |> DateTime.from_naive!(zone) |> DateTime.to_unix()

  # The reading the clock shows at the moment it skips one.
  defp shown_instead(%NaiveDateTime{} = skipped, zone) do
    {:gap, _just_before, shown} = DateTime.from_naive(skipped, zone)
    DateTime.to_naive(shown)
  end

  defp spans(value) do
    case Tempo.to_interval(value) do
      {:ok, %Interval{} = span} -> [bounds(span)]
      {:ok, %IntervalSet{} = set} -> set |> IntervalSet.members() |> Enum.map(&bounds/1)
    end
  end

  defp bounds(%Interval{} = span), do: {moment(Interval.from(span)), moment(Interval.to(span))}

  describe "a set in a unit that names a reading the clock skips" do
    test "names the hours the clock shows, the one before the gap ending after it" do
      zone = "America/New_York"
      assert {:gap, _before, _after} = DateTime.from_naive(~N[2024-03-10 02:00:00], zone)

      assert spans(~o"2024-03-10T{01,02,03}[America/New_York]") == [
               {moment(~N[2024-03-10 01:00:00], zone), moment(~N[2024-03-10 03:00:00], zone)},
               {moment(~N[2024-03-10 03:00:00], zone), moment(~N[2024-03-10 04:00:00], zone)}
             ]
    end

    test "names the days the zone has" do
      zone = "Pacific/Apia"
      assert {:gap, _before, _after} = DateTime.from_naive(~N[2011-12-30 12:00:00], zone)

      assert spans(~o"2011-12-{29,30}[Pacific/Apia]") == [
               {moment(~N[2011-12-29 00:00:00], zone), moment(~N[2011-12-31 00:00:00], zone)}
             ]
    end

    test "is refused where the reading is the only one it names" do
      assert {:error, %Tempo.ZoneGapError{}} =
               Tempo.from_iso8601("2024-03-10T{02}[America/New_York]")
    end
  end

  describe "unspecified digits that stand for a day the zone leaves out" do
    test "stand for the days it has" do
      zone = "Pacific/Apia"

      # The thirties of December 2011 in Samoa are the 31st alone.
      assert spans(~o"2011-12-3X[Pacific/Apia]") == [
               {moment(~N[2011-12-31 00:00:00], zone), moment(~N[2012-01-01 00:00:00], zone)}
             ]

      # The span starts on the 31st, where it started on the 30th, the same
      # moment written as a day no value is read from.
      {:ok, span} = Tempo.to_interval(~o"2011-12-3X[Pacific/Apia]")
      assert Interval.from(span) == ~o"2011Y12M31D[Pacific/Apia]"

      assert Enum.to_list(~o"2011-12-3X[Pacific/Apia]") == [~o"2011Y12M31D[Pacific/Apia]"]
    end
  end

  describe "a value extended to a finer unit" do
    test "starts on the reading the clock shows where it skips the first" do
      assert %NaiveDateTime{hour: 1, minute: 0} =
               shown_instead(~N[2023-04-28 00:00:00], "Africa/Cairo")

      assert Tempo.extend_resolution(~o"2023-04-28[Africa/Cairo]", :hour) ==
               ~o"2023Y4M28DT1H[Africa/Cairo]"

      assert Tempo.extend_resolution(~o"2023-04-28[Africa/Cairo]", :minute) ==
               ~o"2023Y4M28DT1H0M[Africa/Cairo]"

      assert %NaiveDateTime{hour: 2, minute: 30} =
               shown_instead(~N[2026-10-04 02:00:00], "Australia/Lord_Howe")

      assert Tempo.extend_resolution(~o"2026-10-04T02[Australia/Lord_Howe]", :minute) ==
               ~o"2026Y10M4DT2H30M[Australia/Lord_Howe]"
    end

    test "starts where it did where the clock shows its first reading" do
      assert Tempo.extend_resolution(~o"2023-04-27[Africa/Cairo]", :hour) ==
               ~o"2023Y4M27DT0H[Africa/Cairo]"

      assert Tempo.extend_resolution(~o"2023-04-28", :hour) == ~o"2023Y4M28DT0H"
    end

    test "starts at the moment the value does" do
      for {coarse, unit} <- [
            {~o"2023-04-28[Africa/Cairo]", :hour},
            {~o"2023-04-28[Africa/Cairo]", :minute},
            {~o"2026-10-04T02[Australia/Lord_Howe]", :minute},
            {~o"2026-10-04T02[Australia/Lord_Howe]", :second}
          ] do
        extended = Tempo.extend_resolution(coarse, unit)
        assert {coarse, unit, moment(extended)} == {coarse, unit, moment(coarse)}
      end
    end
  end

  describe "a step of days or hours from a value coarser than a day" do
    test "passes over the day its zone leaves out" do
      # The Monday of the last week of 2011 was 26 December, and four days
      # on from it the 30th, which Samoa did not have.
      assert :calendar.iso_week_number({2011, 12, 26}) == {2011, 52}
      assert Date.add(~D[2011-12-26], 4) == ~D[2011-12-30]

      assert Tempo.shift(~o"2011Y52W[Pacific/Apia]", day: 4) == ~o"2011Y12M31D[Pacific/Apia]"
      assert Tempo.shift(~o"2011-12[Pacific/Apia]", day: 29) == ~o"2011Y12M31D[Pacific/Apia]"
      assert Tempo.shift(~o"2011[Pacific/Apia]", day: 363) == ~o"2011Y12M31D[Pacific/Apia]"

      # A step back lands on the day before it.
      assert Tempo.shift(~o"2012-01[Pacific/Apia]", day: -2) == ~o"2011Y12M29D[Pacific/Apia]"
    end

    test "lands on the reading the clock shows" do
      zone = "America/New_York"

      landed =
        ~N[2024-03-01 00:00:00] |> DateTime.from_naive!(zone) |> DateTime.add(218, :hour)

      assert {landed.day, landed.hour} == {10, 3}

      assert Tempo.shift(~o"2024-03[America/New_York]", hour: 218) ==
               ~o"2024Y3M10DT3H[America/New_York]"
    end

    test "lands where it did where the zone has the day" do
      assert Tempo.shift(~o"2011Y52W[Pacific/Apia]", day: 3) == ~o"2011Y12M29D[Pacific/Apia]"
      assert Tempo.shift(~o"2026-06[Europe/Paris]", day: 3) == ~o"2026Y6M4D[Europe/Paris]"
      assert Tempo.shift(~o"2011-12[Pacific/Apia]", month: 1) == ~o"2012Y1M[Pacific/Apia]"
    end
  end

  describe "a week date or a day of the year stepped onto a day its zone leaves out" do
    test "is the day after it, and the day before it for a step back" do
      # Thursday of the last week of 2011 and the 363rd day of the year were
      # 29 December.
      assert Date.add(~D[2011-12-26], 3) == ~D[2011-12-29]
      assert Date.add(~D[2011-01-01], 362) == ~D[2011-12-29]

      assert Tempo.shift(~o"2011-W52-4[Pacific/Apia]", day: 1) == ~o"2011Y12M31D[Pacific/Apia]"
      assert Tempo.shift(~o"2011-363[Pacific/Apia]", day: 1) == ~o"2011Y12M31D[Pacific/Apia]"
      assert Tempo.shift(~o"2011-W52-6[Pacific/Apia]", day: -1) == ~o"2011Y12M29D[Pacific/Apia]"
      assert Tempo.shift(~o"2011-365[Pacific/Apia]", day: -1) == ~o"2011Y12M29D[Pacific/Apia]"
    end
  end

  describe "a recurrence of days from a week" do
    test "has no occurrence on the day its zone leaves out" do
      {:ok, occurrences} = Tempo.to_interval(~o"R6/2011Y52W[Pacific/Apia]/P1D")

      starts = occurrences |> IntervalSet.members() |> Enum.map(&Interval.from/1)

      assert starts == [
               ~o"2011Y52W[Pacific/Apia]",
               ~o"2011Y12M27D[Pacific/Apia]",
               ~o"2011Y12M28D[Pacific/Apia]",
               ~o"2011Y12M29D[Pacific/Apia]",
               ~o"2011Y12M31D[Pacific/Apia]",
               ~o"2012Y1M1D[Pacific/Apia]"
             ]
    end
  end

  describe "the hours of a day whose first the clock skips" do
    test "are counted from the first the clock shows" do
      zone = "Africa/Cairo"
      day = ~o"2023-04-28[Africa/Cairo]"
      first = ~o"2023Y4M28DT1H[Africa/Cairo]"
      shown = shown_instead(~N[2023-04-28 00:00:00], zone)

      assert moment(first) == moment(shown, zone)
      assert Enum.at(day, 0) == first
      assert Enum.at(day, 0) == day |> Enum.to_list() |> List.first()
      assert Enum.slice(day, 0, 2) == [first, ~o"2023Y4M28DT2H[Africa/Cairo]"]
      assert Enum.member?(day, first)

      # The day is as many hours as there are from that reading to midnight.
      hours = div(moment(~N[2023-04-29 00:00:00], zone) - moment(shown, zone), 3600)
      assert hours == 23
      assert Enum.count(day) == hours
      assert Enum.count(Enum.to_list(day)) == hours
    end

    test "are counted so in the span of the day" do
      {:ok, span} = Tempo.to_interval(~o"2023-04-28[Africa/Cairo]")

      assert Enum.at(span, 0) == ~o"2023Y4M28DT1H[Africa/Cairo]"
      assert Enum.member?(span, ~o"2023Y4M28DT1H[Africa/Cairo]")
      assert Enum.count(span) == 23
      assert Enum.to_list(span) == Enum.slice(span, 0, 23)
    end
  end

  describe "the days of a week in a zone that left one out" do
    test "are the days the zone had" do
      had = [
        ~o"2011Y12M26D[Pacific/Apia]",
        ~o"2011Y12M27D[Pacific/Apia]",
        ~o"2011Y12M28D[Pacific/Apia]",
        ~o"2011Y12M29D[Pacific/Apia]",
        ~o"2011Y12M31D[Pacific/Apia]",
        ~o"2012Y1M1D[Pacific/Apia]"
      ]

      # The week is the seven days from its Monday, less the one Elixir
      # places no time on.
      days = for day <- 0..6, do: Date.add(~D[2011-12-26], day)

      shown =
        Enum.reject(days, fn day ->
          {:ok, noon} = NaiveDateTime.new(day, ~T[12:00:00])
          match?({:gap, _before, _after}, DateTime.from_naive(noon, "Pacific/Apia"))
        end)

      assert Enum.map(had, &Tempo.to_date/1) == Enum.map(shown, &{:ok, &1})

      {:ok, span} = Tempo.to_interval(~o"2011-W52[Pacific/Apia]")

      assert Enum.to_list(~o"2011-W52[Pacific/Apia]") == had
      assert Enum.to_list(span) == had
      assert Enum.count(span) == 6
      assert Enum.at(span, 4) == ~o"2011Y12M31D[Pacific/Apia]"

      # In no zone the week has its seven days.
      {:ok, floating} = Tempo.to_interval(~o"2011-W52")
      assert Enum.count(floating) == 7
    end
  end

  describe "a time of day the clock skips, selected" do
    # The days beside the night New York's clocks go from 02:00 to 03:00.
    @beside_the_night [~D[2024-03-09], ~D[2024-03-10], ~D[2024-03-11]]

    test "is not selected on the day the clock skips it, and is on the days beside it" do
      zone = "America/New_York"
      days = ~o"2024-03-{09..11}[America/New_York]"

      for {selector, time, seconds} <- [
            {~o"T02", ~T[02:00:00], 3_600},
            {~o"T02:30", ~T[02:30:00], 60},
            {~o"T02:59:59", ~T[02:59:59], 1}
          ] do
        # The days Elixir places the reading on.
        shown =
          for day <- @beside_the_night,
              {:ok, start} <- [DateTime.new(day, time, zone)],
              do: {DateTime.to_unix(start), DateTime.to_unix(start) + seconds}

        assert Enum.count(shown) == 2
        assert {selector, selected(days, selector)} == {selector, shown}
      end
    end

    test "is not selected by its place in the hour or the day" do
      # The third hour of the day, and the third minute of the hour Lord
      # Howe Island's clocks skip the first half of.
      assert selected(~o"2024-03-10[America/New_York]", [2]) == []
      assert selected(~o"2026-10-04T02[Australia/Lord_Howe]", [2]) == []

      assert selected(~o"2026-10-04T02[Australia/Lord_Howe]", [31]) ==
               shown_between(
                 ~N[2026-10-04 02:31:00],
                 ~N[2026-10-04 02:32:00],
                 "Australia/Lord_Howe"
               )
    end

    test "is selected where the clock shows part of it" do
      # The hour from 02:00 on Lord Howe Island is the half of it from 02:30.
      assert selected(~o"2026-10-04[Australia/Lord_Howe]", ~o"T02") ==
               shown_between(
                 ~N[2026-10-04 02:00:00],
                 ~N[2026-10-04 03:00:00],
                 "Australia/Lord_Howe"
               )

      assert [{from, to}] = selected(~o"2026-10-04[Australia/Lord_Howe]", ~o"T02")
      assert to - from == 1_800
    end

    test "is not selected at midnight where the clock skips midnight" do
      zone = "Africa/Cairo"
      assert {:gap, _before, _after} = DateTime.new(~D[2023-04-28], ~T[00:00:00], zone)

      assert selected(~o"2023-04-{27,28}[Africa/Cairo]", ~o"T00") ==
               shown_between(~N[2023-04-27 00:00:00], ~N[2023-04-27 01:00:00], zone)
    end
  end

  describe "a window selected on a day whose clock skips part of it" do
    # Each window with the readings it runs between, which Elixir is asked
    # minute by minute: the window is the minutes it places.
    @windows [
      {"2024-03-10[America/New_York]", "T02/T04", ~N[2024-03-10 02:00:00],
       ~N[2024-03-10 04:00:00]},
      {"2024-03-10[America/New_York]", "T01/T02:30", ~N[2024-03-10 01:00:00],
       ~N[2024-03-10 02:30:00]},
      {"2024-03-10[America/New_York]", "T02:30/T03:30", ~N[2024-03-10 02:30:00],
       ~N[2024-03-10 03:30:00]},
      {"2024-03-10[America/New_York]", "T01:30/T02:30", ~N[2024-03-10 01:30:00],
       ~N[2024-03-10 02:30:00]},
      {"2024-03-10[America/New_York]", "T02/T03", ~N[2024-03-10 02:00:00],
       ~N[2024-03-10 03:00:00]},
      {"2024-03-10[America/New_York]", "T02:10/T02:50", ~N[2024-03-10 02:10:00],
       ~N[2024-03-10 02:50:00]},
      {"2024-03-10[America/New_York]", "T01/T05", ~N[2024-03-10 01:00:00],
       ~N[2024-03-10 05:00:00]},
      {"2024-03-09[America/New_York]", "T23/T02:30", ~N[2024-03-09 23:00:00],
       ~N[2024-03-10 02:30:00]},
      {"2024-03-09[America/New_York]", "T23/T02", ~N[2024-03-09 23:00:00],
       ~N[2024-03-10 02:00:00]},
      {"2024-03-09[America/New_York]", "T22/T06", ~N[2024-03-09 22:00:00],
       ~N[2024-03-10 06:00:00]},
      {"2026-03-29[Europe/Paris]", "T02/T04", ~N[2026-03-29 02:00:00], ~N[2026-03-29 04:00:00]},
      {"2026-10-04[Australia/Lord_Howe]", "T02/T04", ~N[2026-10-04 02:00:00],
       ~N[2026-10-04 04:00:00]},
      {"2026-10-04[Australia/Lord_Howe]", "T02:10/T04", ~N[2026-10-04 02:10:00],
       ~N[2026-10-04 04:00:00]},
      {"2026-10-04[Australia/Lord_Howe]", "T01/T02:15", ~N[2026-10-04 01:00:00],
       ~N[2026-10-04 02:15:00]},
      {"2023-04-28[Africa/Cairo]", "T00/T02", ~N[2023-04-28 00:00:00], ~N[2023-04-28 02:00:00]},
      {"2023-04-27[Africa/Cairo]", "T22/T00:30", ~N[2023-04-27 22:00:00],
       ~N[2023-04-28 00:30:00]},
      {"2011-12-29[Pacific/Apia]", "T22/T06", ~N[2011-12-29 22:00:00], ~N[2011-12-30 06:00:00]},
      # The night the clocks go back, an hour of which the clock shows twice.
      {"2024-11-03[America/New_York]", "T01/T03", ~N[2024-11-03 01:00:00],
       ~N[2024-11-03 03:00:00]},
      # A day with no change of the clock.
      {"2024-03-11[America/New_York]", "T02/T04", ~N[2024-03-11 02:00:00],
       ~N[2024-03-11 04:00:00]}
    ]

    test "is the part of it the clock shows" do
      for {day, window, from, to} <- @windows do
        base = Tempo.from_iso8601!(day)
        %Tempo{extended: %{zone_id: zone}} = base

        assert {day, window, selected(base, Tempo.from_iso8601!(window))} ==
                 {day, window, shown_between(from, to, zone)}
      end
    end

    test "is nothing where the clock skips the whole of it" do
      assert shown_between(~N[2024-03-10 02:00:00], ~N[2024-03-10 03:00:00], "America/New_York") ==
               []

      assert selected(~o"2024-03-10[America/New_York]", ~o"T02/T03") == []
    end

    test "runs its duration from the reading the clock shows where it is written with one" do
      for {day, window, start, seconds} <- [
            {"2024-03-10[America/New_York]", "T02/PT2H", ~N[2024-03-10 02:00:00], 7_200},
            {"2024-03-10[America/New_York]", "T02:15/PT30M", ~N[2024-03-10 02:15:00], 1_800},
            {"2024-03-10[America/New_York]", "T01:30/PT1H", ~N[2024-03-10 01:30:00], 3_600},
            {"2024-03-10[America/New_York]", "T00/PT2H30M", ~N[2024-03-10 00:00:00], 9_000},
            {"2023-04-28[Africa/Cairo]", "T00/PT30M", ~N[2023-04-28 00:00:00], 1_800},
            {"2026-10-04[Australia/Lord_Howe]", "T02:10/PT1H", ~N[2026-10-04 02:10:00], 3_600},
            {"2024-03-11[America/New_York]", "T02/PT2H", ~N[2024-03-11 02:00:00], 7_200}
          ] do
        base = Tempo.from_iso8601!(day)
        %Tempo{extended: %{zone_id: zone}} = base
        starts = first_shown(start, zone)

        assert {day, window, selected(base, Tempo.from_iso8601!(window))} ==
                 {day, window, [{starts, starts + seconds}]}
      end
    end
  end

  describe "a rule's time of day or day of the month that the clock skips" do
    # RFC 5545 §3.3.10: an instance on a local time that does not exist is
    # ignored, and is not counted.
    test "is no occurrence, and is not counted" do
      for {rule, start, zone, time} <- [
            {"FREQ=DAILY;BYHOUR=2;COUNT=4", "2024-03-08T02", "America/New_York", ~T[02:00:00]},
            {"FREQ=DAILY;BYHOUR=2;BYMINUTE=30;COUNT=4", "2024-03-08T02:30", "America/New_York",
             ~T[02:30:00]},
            {"FREQ=DAILY;BYHOUR=2;COUNT=4", "2024-03-10", "America/New_York", ~T[02:00:00]},
            {"FREQ=DAILY;BYHOUR=0;COUNT=4", "2023-04-26T00", "Africa/Cairo", ~T[00:00:00]},
            {"FREQ=DAILY;BYHOUR=2;BYMINUTE=15;COUNT=4", "2026-10-02T02:15", "Australia/Lord_Howe",
             ~T[02:15:00]}
          ] do
        from = Tempo.from_iso8601!(start <> "[" <> zone <> "]")
        {:ok, first_day} = Tempo.to_date(Tempo.trunc(from, :day))

        # The first four days on which Elixir places the time.
        shown =
          for day <- Date.range(first_day, Date.add(first_day, 10)),
              {:ok, starts} <- [DateTime.new(day, time, zone)],
              do: DateTime.to_unix(starts)

        assert {rule, start, occurrence_starts(rule, from)} == {rule, start, Enum.take(shown, 4)}

        # One of the days in that run has no such time.
        assert Enum.count(shown) == 10
      end
    end

    test "is no occurrence on a day the zone left out" do
      zone = "Pacific/Apia"
      from = ~o"2011-10-30[Pacific/Apia]"

      # The 30th of each month from October 2011 that Elixir places noon on.
      shown =
        for {year, month} <- [{2011, 10}, {2011, 11}, {2011, 12}, {2012, 1}, {2012, 3}],
            {:ok, noon} <- [DateTime.new(Date.new!(year, month, 30), ~T[12:00:00], zone)],
            {:ok, midnight} <- [DateTime.new(DateTime.to_date(noon), ~T[00:00:00], zone)],
            do: DateTime.to_unix(midnight)

      assert Enum.count(shown) == 4
      assert occurrence_starts("FREQ=MONTHLY;BYMONTHDAY=30;COUNT=4", from) == shown
    end
  end

  # The spans a selection gives, each as the moments it runs between.
  defp selected(base, selector) do
    {:ok, %IntervalSet{} = set} = Tempo.select(base, selector)
    set |> IntervalSet.members() |> Enum.map(&bounds/1)
  end

  defp occurrence_starts(rule, from) do
    {:ok, recurrence} = RRule.parse(rule, from: from)
    {:ok, %IntervalSet{} = occurrences} = Tempo.to_interval(recurrence)
    occurrences |> IntervalSet.members() |> Enum.map(&moment(Interval.from(&1)))
  end

  # The part of the wall clock from one reading up to another that a zone's
  # clock shows: each minute between them is asked of Elixir, and the ones it
  # places are one run of time, from the first to a minute after the last.
  # A minute the clock shows twice is placed where it is first shown.
  defp shown_between(%NaiveDateTime{} = from, %NaiveDateTime{} = to, zone) do
    minutes = div(NaiveDateTime.diff(to, from), 60)

    placed =
      for minute <- 0..(minutes - 1)//1,
          moment <- placed(DateTime.from_naive(NaiveDateTime.add(from, minute, :minute), zone)),
          do: DateTime.to_unix(moment)

    case placed do
      [] -> []
      [first | _rest] -> [{first, List.last(placed) + 60}]
    end
  end

  defp placed({:ok, moment}), do: [moment]
  defp placed({:ambiguous, first, _second}), do: [first]
  defp placed({:gap, _just_before, _comes_out}), do: []

  # The moment of a reading, or of the reading the clock comes out of the
  # gap on where it skips the reading.
  defp first_shown(%NaiveDateTime{} = reading, zone) do
    case DateTime.from_naive(reading, zone) do
      {:ok, moment} -> DateTime.to_unix(moment)
      {:ambiguous, first, _second} -> DateTime.to_unix(first)
      {:gap, _just_before, comes_out} -> DateTime.to_unix(comes_out)
    end
  end

  describe "every operation, given a value beside a gap" do
    test "the cells are of every operation and gap", %{harvest: harvest} do
      # A harvest that runs nothing holds to every property.
      operations = Enum.map(BesideAGap.operations(), &elem(&1, 0))

      assert harvest.cells == Enum.count(BesideAGap.texts()) * Enum.count(operations)
      assert harvest.cells > 3_500
      assert Enum.uniq(operations) == operations

      for operation <- operations do
        assert {operation, Map.get(harvest.gave, operation, 0) > 0} == {operation, true}
      end
    end

    test "no operation raises", %{harvest: harvest} do
      assert found(harvest, :raises) == []
    end

    test "every value given is one the reader takes", %{harvest: harvest} do
      assert found(harvest, :not_read) == []
    end
  end
end
