defmodule Tempo.ChangeOfTheClockTest do
  @moduledoc """
  The hours of a day on which a zone's clock changes.

  A change by a whole hour on the hour is the one every implementation is
  written for, and Tempo's hours were right for it. They were not where a
  change is of another shape, which a current zone or two has every year:
  Lord Howe Island's clocks go forward and back by half an hour, and the
  Chatham Islands' go from 02:45 to 03:45. An hour the clock skips part of
  was given a span an elapsed hour long, past its own end and over the next
  hour's; the walk of its day left it out, where `Enum.count/1` counted it;
  and an hour that starts inside a gap begun before it started where it
  ends.

  `Tempo.ChangeOfTheClock` asks Elixir's `DateTime` what the clock showed in
  each minute of such a day, and gathers the minutes into hours. Each day is
  held to that: the hours a walk gives are the hours the clock showed, each
  spanning the moments it was shown; the minutes of each are the minutes of
  its span; and `Enum.count/1`, `Enum.at/2` and `Enum.member?/2`, which are
  answered without a walk where they can be, agree with the walk.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ChangeOfTheClock
  alias Tempo.Interval
  alias Tempo.TimeZoneDatabase

  @minute 60

  defp gregorian_seconds(%DateTime{} = moment),
    do: DateTime.to_gregorian_seconds(moment) |> elem(0)

  describe "the hours of a day on which the clock changes" do
    for {zone, date, change} <- ChangeOfTheClock.gaps() ++ ChangeOfTheClock.folds() do
      @zone zone
      @date date

      test "in #{zone} on #{date}, #{change}, are the hours the clock shows" do
        assert ChangeOfTheClock.hours_listed(@zone, @date) ==
                 ChangeOfTheClock.hours_shown(@zone, @date)
      end

      test "in #{zone} on #{date}, #{change}, are the day from its start to its end" do
        assert ChangeOfTheClock.span(ChangeOfTheClock.day(@zone, @date)) ==
                 ChangeOfTheClock.day_shown(@zone, @date)
      end

      test "in #{zone} on #{date}, #{change}, each have the minutes of their span" do
        for hour <- Enum.to_list(ChangeOfTheClock.day(@zone, @date)) do
          {from, to} = ChangeOfTheClock.span(hour)
          minutes = Enum.map(hour, &ChangeOfTheClock.moment/1)

          assert {hour, minutes} == {hour, Enum.to_list(from..(to - @minute)//@minute)}
        end
      end

      test "in #{zone} on #{date}, #{change}, are counted and placed as they are listed" do
        day = ChangeOfTheClock.day(@zone, @date)
        {:ok, span} = Tempo.to_interval(day)

        assert ChangeOfTheClock.walk_against_enum(day) == []
        assert ChangeOfTheClock.walk_against_enum(span) == []

        for hour <- Enum.to_list(day) do
          assert {hour, ChangeOfTheClock.walk_against_enum(hour)} == {hour, []}
        end
      end
    end
  end

  describe "the span of a day on which the clock changes, and of each of its hours" do
    for {zone, date, change} <- ChangeOfTheClock.gaps() ++ ChangeOfTheClock.folds() do
      @zone zone
      @date date

      test "in #{zone} on #{date}, #{change}, is written and read as itself" do
        day = ChangeOfTheClock.day(@zone, @date)

        for value <- [day | Enum.to_list(day)] do
          {:ok, span} = Tempo.to_interval(value)
          {:ok, text} = Tempo.to_iso8601(span)
          {:ok, read} = Tempo.from_iso8601(text)

          assert {text, Interval.from(read), Interval.to(read)} ==
                   {text, Interval.from(span), Interval.to(span)}
        end
      end
    end
  end

  describe "an hour the clock skips part of" do
    test "is the part the clock shows" do
      # Lord Howe Island's clocks go from 02:00 to 02:30, so the hour from
      # 02:00 is the half hour from 02:30, and ends where the next begins.
      hour = ~o"2026-10-04T02[Australia/Lord_Howe]"
      {:ok, span} = Tempo.to_interval(hour)

      assert Interval.from(span) == hour
      assert Interval.to(span) == ~o"2026Y10M4DT3H[Australia/Lord_Howe]"
      assert Tempo.exactly?(hour, ~o"PT30M")

      assert Enum.to_list(hour) |> List.first() == ~o"2026Y10M4DT2H30M[Australia/Lord_Howe]"
      assert Enum.count(hour) == 30
    end

    test "is an hour of its day" do
      day = ~o"2026-10-04[Australia/Lord_Howe]"

      assert Enum.count(day) == 24
      assert Enum.at(day, 2) == ~o"2026Y10M4DT2H[Australia/Lord_Howe]"
      assert Enum.member?(day, ~o"2026Y10M4DT2H[Australia/Lord_Howe]")
      assert Enum.to_list(day) == Enum.slice(day, 0, 24)
    end

    test "ends where the clock goes forward, and the hour before it where it comes out" do
      # The hour before the gap ends on the reading the clock comes out on.
      {:ok, before} = Tempo.to_interval(~o"2026-10-04T01[Australia/Lord_Howe]")
      assert Interval.to(before) == ~o"2026Y10M4DT2H30M[Australia/Lord_Howe]"

      # The Chatham Islands' clocks go from 02:45 to 03:45: three quarters
      # of the hour from 02:00, and a quarter of the hour from 03:00.
      {:ok, two} = Tempo.to_interval(~o"2026-09-27T02[Pacific/Chatham]")
      {:ok, three} = Tempo.to_interval(~o"2026-09-27T03[Pacific/Chatham]")

      assert Interval.to(two) == ~o"2026Y9M27DT3H45M[Pacific/Chatham]"
      assert Interval.to(three) == ~o"2026Y9M27DT4H[Pacific/Chatham]"
      assert Tempo.exactly?(~o"2026-09-27T02[Pacific/Chatham]", ~o"PT45M")
      assert Tempo.exactly?(~o"2026-09-27T03[Pacific/Chatham]", ~o"PT15M")
      assert Tempo.relation(two, three) == :meets

      # Pyongyang's went from 23:30 to midnight in 2018.
      assert Tempo.exactly?(~o"2018-05-04T23[Asia/Pyongyang]", ~o"PT30M")
    end

    test "starts when the clock comes out of the gap" do
      zone = "Pacific/Chatham"
      comes_out = DateTime.new!(~D[2026-09-27], ~T[03:45:00], zone)

      assert {:gap, _before, ^comes_out} = DateTime.new(~D[2026-09-27], ~T[03:00:00], zone)

      assert ChangeOfTheClock.moment(~o"2026-09-27T03[Pacific/Chatham]") ==
               DateTime.to_unix(comes_out)
    end
  end

  describe "an hour the clock shows part of twice" do
    test "runs through both where its start is shown once" do
      # Lord Howe Island's clocks go back from 02:00 to 01:30, so the hour
      # from 01:00 is an hour and a half, and its span was an elapsed hour,
      # which left the half hour shown again in no hour of the day.
      hour = ~o"2026-04-05T01[Australia/Lord_Howe]"
      {:ok, span} = Tempo.to_interval(hour)
      {:ok, next} = Tempo.to_interval(~o"2026-04-05T02[Australia/Lord_Howe]")

      assert Tempo.exactly?(hour, ~o"PT1H30M")
      assert Tempo.relation(span, next) == :meets
    end

    test "is two occurrences where its start is shown twice, the first ending where the second begins" do
      first = ~o"2024-11-03T01-04:00[America/New_York]"
      second = ~o"2024-11-03T01-05:00[America/New_York]"
      {:ok, first_span} = Tempo.to_interval(first)
      {:ok, second_span} = Tempo.to_interval(second)

      assert Tempo.exactly?(first, ~o"PT1H")
      assert Tempo.exactly?(second, ~o"PT1H")
      assert Tempo.relation(first_span, second_span) == :meets
    end

    test "ends when the clock goes back, where it goes back by less than the hour" do
      # Colombo's clocks went from 00:30 back to midnight in 2006: the first
      # hour from midnight is half an hour, and the second a whole one.
      assert Tempo.exactly?(~o"2006-04-15T00+06:00[Asia/Colombo]", ~o"PT30M")
      assert Tempo.exactly?(~o"2006-04-15T00+05:30[Asia/Colombo]", ~o"PT1H")
    end

    test "ends on what the clock shows then, where it goes back by more than the hour" do
      # Troll's clocks go back from 03:00 to 01:00. The first 01:00 ends at
      # the first 02:00, and the first 02:00 where the second 01:00 begins.
      {:ok, one} = Tempo.to_interval(~o"2024-10-27T01+02:00[Antarctica/Troll]")
      {:ok, two} = Tempo.to_interval(~o"2024-10-27T02+02:00[Antarctica/Troll]")
      {:ok, one_again} = Tempo.to_interval(~o"2024-10-27T01+00:00[Antarctica/Troll]")

      assert Tempo.relation(one, two) == :meets
      assert Tempo.relation(two, one_again) == :meets
      assert Tempo.exactly?(two, ~o"PT1H")
    end
  end

  describe "a span walked across a clock that goes back" do
    test "gives its values in the order of time" do
      # Troll's clocks go back from 03:00 to 01:00, so two hours are shown
      # twice, and the second 01:00 follows the first 02:00.
      {:ok, night} = Tempo.from_iso8601("2024-10-27T00/2024-10-27T04[Antarctica/Troll]")
      listed = Enum.to_list(night)

      assert listed == [
               ~o"2024Y10M27DT0H[Antarctica/Troll]",
               ~o"2024Y10M27DT1HZ2H[Antarctica/Troll]",
               ~o"2024Y10M27DT2HZ2H[Antarctica/Troll]",
               ~o"2024Y10M27DT1HZ[Antarctica/Troll]",
               ~o"2024Y10M27DT2HZ[Antarctica/Troll]",
               ~o"2024Y10M27DT3H[Antarctica/Troll]"
             ]

      moments = Enum.map(listed, &ChangeOfTheClock.moment/1)
      assert moments == Enum.sort(moments)
      assert ChangeOfTheClock.walk_against_enum(night) == []
    end

    test "gives the first showing alone of a span that ends in it" do
      # 00:58 to the first 01:02 on the night New York's clocks go back is
      # four minutes, and the walk gave the second 01:00 and 01:01 too.
      {:ok, span} = Tempo.from_iso8601("2024-11-03T00:58/2024-11-03T01:02[America/New_York]")

      assert Enum.to_list(span) == [
               ~o"2024Y11M3DT0H58M[America/New_York]",
               ~o"2024Y11M3DT0H59M[America/New_York]",
               ~o"2024Y11M3DT1H0MZ-4H[America/New_York]",
               ~o"2024Y11M3DT1H1MZ-4H[America/New_York]"
             ]

      assert Enum.count(span) == 4
    end

    test "goes from the first showing to the second, and starts in the second" do
      # 01:57 before the clocks go back to 01:02 after is five minutes, the
      # readings before 01:57 that follow it in time among them.
      {:ok, across} =
        Tempo.from_iso8601("2024-11-03T01:57-04:00/2024-11-03T01:02-05:00[America/New_York]")

      assert Enum.to_list(across) == [
               ~o"2024Y11M3DT1H57MZ-4H0M[America/New_York]",
               ~o"2024Y11M3DT1H58MZ-4H0M[America/New_York]",
               ~o"2024Y11M3DT1H59MZ-4H0M[America/New_York]",
               ~o"2024Y11M3DT1H0MZ-5H0M[America/New_York]",
               ~o"2024Y11M3DT1H1MZ-5H0M[America/New_York]"
             ]

      {:ok, second} =
        Tempo.from_iso8601("2024-11-03T01:58-05:00/2024-11-03T02:01[America/New_York]")

      assert Enum.to_list(second) == [
               ~o"2024Y11M3DT1H58MZ-5H0M[America/New_York]",
               ~o"2024Y11M3DT1H59MZ-5H0M[America/New_York]",
               ~o"2024Y11M3DT2H0MZ-5H0M[America/New_York]"
             ]

      for span <- [across, second] do
        assert {span, ChangeOfTheClock.walk_against_enum(span)} == {span, []}
      end
    end

    test "gives the minutes an hour is shown a second time after the minutes of the first" do
      # Lord Howe Island's clocks go back from 02:00 to 01:30: the hour from
      # 01:00 is its sixty minutes, then the thirty shown again.
      minutes = Enum.to_list(~o"2026-04-05T01[Australia/Lord_Howe]")

      assert Enum.count(minutes) == 90
      assert Enum.at(minutes, 59) == ~o"2026Y4M5DT1H59MZ11H[Australia/Lord_Howe]"
      assert Enum.at(minutes, 60) == ~o"2026Y4M5DT1H30MZ10H30M[Australia/Lord_Howe]"
      assert Enum.at(minutes, 89) == ~o"2026Y4M5DT1H59MZ10H30M[Australia/Lord_Howe]"
    end

    test "gives the first hour of a day whose midnight is shown twice with its offset" do
      # Havana's clocks go back from 01:00 to midnight.
      day = ~o"2024-11-03[America/Havana]"

      assert Enum.at(day, 0) == ~o"2024Y11M3DT0HZ-4H[America/Havana]"
      assert Enum.at(day, 1) == ~o"2024Y11M3DT0HZ-5H[America/Havana]"
      assert Enum.take(day, 2) == [Enum.at(day, 0), Enum.at(day, 1)]
    end
  end

  describe "the changes of a zone's clock" do
    test "are each moment its offset changes, with the offsets on each side" do
      zone = "America/New_York"
      {:ok, year_starts} = DateTime.new(~D[2024-01-01], ~T[00:00:00], "Etc/UTC")
      {:ok, year_ends} = DateTime.new(~D[2025-01-01], ~T[00:00:00], "Etc/UTC")

      forward = DateTime.new!(~D[2024-03-10], ~T[03:00:00], zone)
      {:ambiguous, _first, back} = DateTime.new(~D[2024-11-03], ~T[01:00:00], zone)

      assert TimeZoneDatabase.changes(
               zone,
               gregorian_seconds(year_starts),
               gregorian_seconds(year_ends)
             ) == [
               {gregorian_seconds(forward), -5 * 3600, -4 * 3600},
               {gregorian_seconds(back), -4 * 3600, -5 * 3600}
             ]
    end

    test "are those after the first moment and no later than the second" do
      zone = "America/New_York"
      forward = gregorian_seconds(DateTime.new!(~D[2024-03-10], ~T[03:00:00], zone))

      assert [{^forward, _before, _later}] = TimeZoneDatabase.changes(zone, forward - 1, forward)
      assert TimeZoneDatabase.changes(zone, forward, forward + 86_400) == []
      assert TimeZoneDatabase.changes(zone, forward - 86_400, forward - 1) == []
    end

    test "are both found where there are two in a day" do
      # Scoresbysund moved an hour west and onto summer time within an hour
      # of each other, which left its clocks where they were.
      {:ok, from} = DateTime.new(~D[2024-03-30], ~T[00:00:00], "Etc/UTC")
      {:ok, to} = DateTime.new(~D[2024-04-02], ~T[00:00:00], "Etc/UTC")

      assert [{first, -3600, -7200}, {second, -7200, -3600}] =
               TimeZoneDatabase.changes(
                 "America/Scoresbysund",
                 gregorian_seconds(from),
                 gregorian_seconds(to)
               )

      assert second - first == 3600
    end

    test "are none for a zone with none, a zone not known, and a time before any" do
      {:ok, from} = DateTime.new(~D[2020-01-01], ~T[00:00:00], "Etc/UTC")
      {:ok, to} = DateTime.new(~D[2030-01-01], ~T[00:00:00], "Etc/UTC")
      {from, to} = {gregorian_seconds(from), gregorian_seconds(to)}

      assert TimeZoneDatabase.changes("Etc/UTC", from, to) == []
      assert TimeZoneDatabase.changes("Asia/Tokyo", from, to) == []
      assert TimeZoneDatabase.changes("Made/Up_Zone", from, to) == []

      assert TimeZoneDatabase.changes("Europe/Paris", 0, 86_400 * 366 * 1700) == []
      assert TimeZoneDatabase.changes("Europe/Paris", -86_400 * 366 * 10, 0) == []
    end
  end

  describe "a count of hours answered without a walk" do
    test "is the walk's across a change by whole hours on the hour" do
      {:ok, year} = Tempo.from_iso8601("2024-01-01T00/2025-01-01T00[America/New_York]")

      # A year of days, less the hour skipped and with the hour shown twice.
      assert Enum.count(year) == 366 * 24
      assert Enum.at(year, 366 * 24 - 1) == ~o"2024Y12M31DT23H[America/New_York]"
    end

    test "is left to the walk across a change that is not" do
      {:ok, days} = Tempo.from_iso8601("2026-09-26T00/2026-09-29T00[Pacific/Chatham]")
      listed = Enum.to_list(days)

      # Three days of hours, less none: the hour from 03:00 is a quarter of
      # an hour long, and is an hour of its day all the same.
      assert Enum.count(listed) == 3 * 24
      assert Enum.count(days) == 3 * 24
      assert ChangeOfTheClock.walk_against_enum(days) == []
    end
  end
end
