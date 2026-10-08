defmodule Tempo.ZonedWalkPastItsPartsTest do
  @moduledoc """
  A rule of hours or less in a zone that has no occurrence because of what
  it steps by, and a position no period has.

  A walk of hours steps by time passed, and a change of its zone's clock
  moves every stop after it: every twenty-fourth hour from 10:00 in Paris
  is 10:00 until the clocks go back and 09:00 after. A rule that names an
  hour the walk never stops at has no occurrence, which a rule in no zone
  was told at once. In a zone the walk made its ten thousand periods, in
  about six seconds, and was a `Tempo.UnboundedRecurrenceError`.

  The measure is Elixir's own `DateTime`, stepped by the seconds of each
  period in the zone, and asked the hour and the minute its clock shows.
  """
  use ExUnit.Case, async: true

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.TimeZoneDatabase

  # About eleven years of days, across twenty-two changes of a clock that
  # changes twice a year.
  @stops 4_000

  ## The measure

  defp started(zone, time),
    do: DateTime.new!(~D[2026-06-16], time, zone, TimeZoneDatabase.database())

  # Each stop of a walk of `seconds` at a time, as the zone's clock shows it.
  defp stops(zone, time, seconds) do
    start = started(zone, time)

    for step <- 0..(@stops - 1)//1,
        do: DateTime.add(start, step * seconds, :second, TimeZoneDatabase.database())
  end

  defp utc_seconds(%DateTime{} = at),
    do: at |> DateTime.to_unix() |> Kernel.+(62_167_219_200)

  defp starts({:ok, %IntervalSet{} = set}) do
    for occurrence <- IntervalSet.members(set),
        do: occurrence |> Interval.from() |> Compare.to_utc_seconds() |> Kernel.trunc()
  end

  defp walk(zone, cadence, rule, time \\ "T10"),
    do: Tempo.from_iso8601!("R5/2026-06-16#{time}[#{zone}]/#{cadence}/F#{rule}")

  describe "a rule of hours in a zone that names an hour its walk never stops at" do
    test "has no occurrence, and is told so" do
      for {zone, hours, rule, named} <- [
            {"Europe/Paris", 24, "LT3HN", [3]},
            {"Europe/Paris", 12, "LT{3,4}HN", [3, 4]},
            {"America/New_York", 24, "LT12HN", [12]},
            {"Asia/Kolkata", 24, "LT3HN", [3]}
          ] do
        shown = zone |> stops(~T[10:00:00], hours * 3_600) |> Enum.map(& &1.hour) |> Enum.uniq()

        # The measure: the walk's clock never shows an hour the rule names.
        assert {zone, hours, Enum.filter(named, &(&1 in shown))} == {zone, hours, []}

        assert {zone, hours, Tempo.to_interval(walk(zone, "PT#{hours}H", rule))} ==
                 {zone, hours, IntervalSet.new([])}
      end
    end

    test "has its occurrences where the clock's change brings the walk to the hour" do
      # Ten o'clock in the summer is nine once the clocks have gone back.
      for {rule, hour} <- [{"LT9HN", 9}, {"LT10HN", 10}] do
        first_five =
          "Europe/Paris"
          |> stops(~T[10:00:00], 86_400)
          |> Enum.filter(&(&1.hour == hour))
          |> Enum.take(5)
          |> Enum.map(&utc_seconds/1)

        assert {rule, starts(Tempo.to_interval(walk("Europe/Paris", "PT24H", rule)))} ==
                 {rule, first_five}
      end
    end
  end

  describe "a rule of hours in a zone whose clock changes by half an hour" do
    # Lord Howe's clock goes forward half an hour in October and back in
    # April. Every twenty-fourth hour from 10:00 in its winter is 10:30 in
    # its summer, in hour 10 still, and from 10:45 it is 11:15, in hour 11.
    @lord_howe "Australia/Lord_Howe"

    test "has no occurrence in an hour its walk never stops in, by where in its hour it starts" do
      for {time, written, rule, named} <- [
            {~T[10:00:00], "T10", "LT9HN", [9]},
            {~T[10:00:00], "T10", "LT11HN", [11]},
            {~T[10:45:00], "T10:45", "LT9HN", [9]},
            {~T[10:45:00], "T10:45", "LT{9,12}HN", [9, 12]},
            {~T[10:29:59], "T10:29:59", "LT11HN", [11]}
          ] do
        shown = @lord_howe |> stops(time, 86_400) |> Enum.map(& &1.hour) |> Enum.uniq()

        assert {written, rule, Enum.filter(named, &(&1 in shown))} == {written, rule, []}

        assert {written, rule, Tempo.to_interval(walk(@lord_howe, "PT24H", rule, written))} ==
                 {written, rule, IntervalSet.new([])}
      end
    end

    test "has its occurrences in the hour the change brings the walk into" do
      for {time, written, rule, hour} <- [
            {~T[10:00:00], "T10", "LT10HN", 10},
            {~T[10:45:00], "T10:45", "LT10HN", 10},
            {~T[10:45:00], "T10:45", "LT11HN", 11},
            {~T[10:30:00], "T10:30", "LT11HN", 11}
          ] do
        first_five =
          @lord_howe
          |> stops(time, 86_400)
          |> Enum.filter(&(&1.hour == hour))
          |> Enum.take(5)
          |> Enum.map(&utc_seconds/1)

        assert [_first, _second, _third, _fourth, _fifth] = first_five

        assert {written, rule,
                starts(Tempo.to_interval(walk(@lord_howe, "PT24H", rule, written)))} ==
                 {written, rule, first_five}
      end
    end
  end

  describe "a rule of minutes in a zone that names a minute its walk never stops at" do
    test "has no occurrence" do
      # Every sixtieth minute from a quarter past is a quarter past, a
      # change of the clock by whole hours leaving the minute as it was.
      minutes =
        "Europe/Paris" |> stops(~T[10:15:00], 3_600) |> Enum.map(& &1.minute) |> Enum.uniq()

      assert minutes == [15]

      assert Tempo.to_interval(walk("Europe/Paris", "PT60M", "LT10H30MN", "T10:15")) ==
               IntervalSet.new([])
    end
  end

  describe "a position no period has" do
    test "is no occurrence of a rule that keeps one of each period at most" do
      for rule <- ["FREQ=DAILY;BYSETPOS=2;COUNT=3", "FREQ=DAILY;BYDAY=MO;BYSETPOS=2;COUNT=3"] do
        {:ok, read} = RRule.parse(rule, from: Tempo.from_iso8601!("2026-06-16"))
        assert {rule, Tempo.to_interval(read)} == {rule, IntervalSet.new([])}
      end
    end

    test "is one where it is the first or the last of a period's one, or the period has more" do
      for {rule, count} <- [
            {"FREQ=DAILY;BYSETPOS=1;COUNT=3", 3},
            {"FREQ=DAILY;BYSETPOS=-1;COUNT=3", 3},
            {"FREQ=DAILY;BYHOUR=9,10;BYSETPOS=2;COUNT=3", 3}
          ] do
        {:ok, read} = RRule.parse(rule, from: Tempo.from_iso8601!("2026-06-16T09"))
        {:ok, set} = Tempo.to_interval(read)

        assert {rule, IntervalSet.count(set)} == {rule, count}
      end
    end
  end
end
