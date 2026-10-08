defmodule Tempo.TimeZoneDatabaseChangesTest do
  @moduledoc """
  The changes of a zone's clock, found for a short span by its own days and
  for a year once it has been asked of often enough.

  A zone database answers from a table for some years ahead (`Tz` to 2032
  in this build) and works each answer out past them, a hundred times as
  slowly. A year of a zone's changes is a question for each of its days, so
  finding one for the sake of a day of it took fifty milliseconds, the
  first time a value of that year was asked whether its clock shows it. A
  span of half a year or less is asked of its own days, and its year found
  once it has been asked of as often as finding it takes.

  The measure is Elixir's own `DateTime`: the offset a zone is at each hour
  of a span, and each minute and second of an hour it changes in.
  """
  use ExUnit.Case, async: true

  alias Tempo.TimeZoneDatabase

  @day 86_400
  @hour 3_600

  ## The measure

  defp seconds(date, time \\ ~T[00:00:00]),
    do: :calendar.datetime_to_gregorian_seconds({Date.to_erl(date), Time.to_erl(time)})

  defp offset_at(zone, moment) do
    at = moment |> DateTime.from_gregorian_seconds() |> DateTime.shift_zone!(zone)
    at.utc_offset + at.std_offset
  end

  # Each change of a zone's offset after `from` and no later than `to`:
  # the span is asked an hour at a time, an hour its offset changes in a
  # minute at a time, and such a minute a second at a time.
  defp measured(zone, from, to), do: measured(zone, from, to, [@hour, 60, 1])

  defp measured(zone, from, to, [1]) do
    for moment <- (from + 1)..to//1,
        before = offset_at(zone, moment - 1),
        later = offset_at(zone, moment),
        before != later,
        do: {moment, before, later}
  end

  defp measured(zone, from, to, [step | finer]) do
    from
    |> Stream.iterate(&(&1 + step))
    |> Enum.take_while(&(&1 < to))
    |> Enum.flat_map(fn starts ->
      ends = min(starts + step, to)

      if offset_at(zone, starts) == offset_at(zone, ends),
        do: [],
        else: measured(zone, starts, ends, finer)
    end)
  end

  # A zone and a year, the spans of the year its clock changes in, and how
  # many changes it has in them.
  @spans [
    {"Europe/Paris", 2026, 2},
    {"America/New_York", 2027, 2},
    {"Australia/Lord_Howe", 2028, 2},
    {"Pacific/Chatham", 2029, 2},
    # Past the years the database holds a table for.
    {"Europe/Paris", 2046, 2},
    {"America/New_York", 2047, 2},
    # A zone with no change.
    {"Asia/Kolkata", 2048, 0}
  ]

  defp spring(year), do: {seconds(Date.new!(year, 3, 1)), seconds(Date.new!(year, 4, 12))}
  defp autumn(year), do: {seconds(Date.new!(year, 9, 20)), seconds(Date.new!(year, 11, 12))}

  describe "the changes of a span of half a year or less" do
    test "are those Elixir's DateTime has, each at its second, asked before and after the year is found" do
      for {zone, year, count} <- @spans do
        spans = [spring(year), autumn(year)]
        expected = Enum.map(spans, fn {from, to} -> measured(zone, from, to) end)

        assert {zone, year, expected |> List.flatten() |> Enum.count()} == {zone, year, count}

        asked = Enum.map(spans, fn {from, to} -> TimeZoneDatabase.changes(zone, from, to) end)
        assert {zone, year, asked} == {zone, year, expected}

        # A span of more than half a year finds the year, and keeps it.
        TimeZoneDatabase.changes(
          zone,
          seconds(Date.new!(year, 1, 1)),
          seconds(Date.new!(year, 12, 31))
        )

        again = Enum.map(spans, fn {from, to} -> TimeZoneDatabase.changes(zone, from, to) end)
        assert {zone, year, again} == {zone, year, expected}
      end
    end

    test "are after the span's start and no later than its end, to the second" do
      # A year no other test asks of, so that its changes are not kept.
      {from, to} = spring(2053)
      [{change, before, later}] = measured("Europe/Madrid", from, to)

      assert TimeZoneDatabase.changes("Europe/Madrid", change - 1, change) ==
               [{change, before, later}]

      assert TimeZoneDatabase.changes("Europe/Madrid", change, change + @day) == []
      assert TimeZoneDatabase.changes("Europe/Madrid", change - @day, change - 1) == []
      assert TimeZoneDatabase.changes("Europe/Madrid", change + @day, change - @day) == []

      assert TimeZoneDatabase.change_within?("Europe/Madrid", change + @hour, @hour)
      refute TimeZoneDatabase.change_within?("Europe/Madrid", change + @hour + 1, @hour)
      assert TimeZoneDatabase.change_within?("Europe/Madrid", change - @hour, @hour)
      refute TimeZoneDatabase.change_within?("Europe/Madrid", change - @hour - 1, @hour)
    end

    test "are none for a zone the database does not know" do
      {from, to} = spring(2026)

      assert TimeZoneDatabase.changes("Nowhere/Never", from, to) == []
      refute TimeZoneDatabase.change_within?("Nowhere/Never", from, @day)
    end
  end

  describe "a year's changes" do
    test "are found once the year has been asked of as often as finding them takes" do
      # A zone and a year no other test asks of. The summer is clear of
      # every change, which is known only once the year's changes are found:
      # not at the first asking, and by the hundred and twenty-third, three
      # questions being counted for each (367 find a year).
      midsummer = seconds(~D[2061-07-10], ~T[12:00:00])

      found_at =
        Enum.find(1..200, fn _asking ->
          TimeZoneDatabase.clear_of_changes?("Europe/Helsinki", midsummer, @day)
        end)

      assert found_at in 2..123

      # And answered from: a change is near at the end of October.
      {from, to} = autumn(2061)
      [{change, _before, _later}] = measured("Europe/Helsinki", from, to)

      refute TimeZoneDatabase.clear_of_changes?("Europe/Helsinki", change + @hour, @day)
      assert TimeZoneDatabase.clear_of_changes?("Europe/Helsinki", change + 2 * @day, @day)
    end

    test "are never found for a zone the database does not know" do
      midsummer = seconds(~D[2061-07-10], ~T[12:00:00])

      refute Enum.any?(1..200, fn _asking ->
               TimeZoneDatabase.clear_of_changes?("Nowhere/Never", midsummer, @day)
             end)
    end
  end
end
