defmodule Tempo.ClockSelectionTest do
  use ExUnit.Case, async: true

  # A time of day selected in a day of a zone is each moment the zone's
  # clock shows that time: none where the clock skips it, two where it shows
  # it twice. The engine finds a reading by arithmetic where the clock keeps
  # one offset through the day, and walks the day where it changes, so the
  # days are ordinary days and days the clock changes, in zones whose offsets
  # are whole hours, half hours and three quarters of an hour.
  #
  # The measure is `DateTime`, which reads the zone database apart from the
  # library: each wall time of the day it is asked for is the moment, or the
  # two moments, or none, it gives.

  alias Tempo.IntervalSet

  @days [
    {"America/Chicago", ~D[2026-03-08]},
    {"America/Chicago", ~D[2026-11-01]},
    {"America/Chicago", ~D[2026-06-15]},
    {"Europe/Paris", ~D[2026-03-29]},
    {"Europe/Paris", ~D[2026-10-25]},
    {"Asia/Kolkata", ~D[2026-06-15]},
    {"Australia/Lord_Howe", ~D[2026-04-05]},
    {"Australia/Lord_Howe", ~D[2026-10-04]},
    {"Pacific/Chatham", ~D[2026-04-05]},
    {"Pacific/Chatham", ~D[2026-09-27]},
    {"Asia/Kathmandu", ~D[2026-01-01]}
  ]

  @selections [
    {[minute: 59], for(hour <- 0..23, do: {hour, 59, 0})},
    {[minute: 15], for(hour <- 0..23, do: {hour, 15, 0})},
    {[hour: 2, minute: 30], [{2, 30, 0}]},
    {[hour: 1, minute: 45], [{1, 45, 0}]},
    {[second: 30], for(hour <- 0..23, minute <- 0..59, do: {hour, minute, 30})}
  ]

  # Every moment the zone's clock shows a wall time on a day.
  defp shown(zone, day, times) do
    times
    |> Enum.flat_map(fn {hour, minute, second} ->
      case DateTime.new(day, Time.new!(hour, minute, second), zone) do
        {:ok, moment} -> [moment]
        {:ambiguous, first, second_showing} -> [first, second_showing]
        {:gap, _before, _after} -> []
      end
    end)
    |> Enum.map(&DateTime.to_unix/1)
    |> Enum.sort()
  end

  defp selected(zone, day, parts) do
    {:ok, value} = Tempo.new(year: day.year, month: day.month, day: day.day, zone: zone)
    {:ok, selection} = Tempo.selection(parts)
    {:ok, set} = Tempo.select(value, selection)

    set
    |> IntervalSet.members()
    |> Enum.map(fn member ->
      {:ok, moment} = Tempo.to_datetime(member)
      DateTime.to_unix(moment)
    end)
    |> Enum.sort()
  end

  for {zone, day} <- @days do
    test "a time of day in #{zone} on #{day} is each moment its clock shows it" do
      for {parts, times} <- @selections do
        assert {unquote(zone), parts, selected(unquote(zone), unquote(Macro.escape(day)), parts)} ==
                 {unquote(zone), parts, shown(unquote(zone), unquote(Macro.escape(day)), times)}
      end
    end
  end
end
