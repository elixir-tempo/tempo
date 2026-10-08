defmodule Tempo.ZonedStepClearOfChangesTest do
  @moduledoc """
  A step by hours or minutes from a value in a zone, taken on the wall clock
  where no change of the zone's clock is near.

  A step by time passed asks the zone database for the offset it starts at,
  the offset it lands at and whether the reading it lands on is shown twice.
  A value two days and the step's length from every change of its zone's
  clock lands on the reading its wall clock steps to, so nothing is asked
  for it, where the zone's changes have been found already: an occurrence a
  selection makes in a zone took four times what one in no zone does.

  The measure is Elixir's own `DateTime`: the reading a zone's clock shows a
  number of seconds after another.
  """
  use ExUnit.Case, async: true

  alias Tempo.Enumeration.Zone
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.TimeZoneDatabase

  @zones ["Europe/Paris", "Australia/Lord_Howe", "Pacific/Chatham", "America/New_York"]

  ## The measure

  # The reading a zone's clock shows `seconds` after a reading it shows
  # once, as the units a value written to the minute holds.
  defp reading_after(date, time, zone, seconds) do
    {:ok, starts} = DateTime.new(date, time, zone)
    lands = DateTime.add(starts, seconds, :second)
    [year: lands.year, month: lands.month, day: lands.day, hour: lands.hour, minute: lands.minute]
  end

  defp shown_once?(date, time, zone), do: match?({:ok, _reading}, DateTime.new(date, time, zone))

  defp found_changes(zone) do
    from = :calendar.datetime_to_gregorian_seconds({{2025, 1, 1}, {0, 0, 0}})
    to = :calendar.datetime_to_gregorian_seconds({{2028, 1, 1}, {0, 0, 0}})
    TimeZoneDatabase.changes(zone, from, to)
  end

  defp gregorian_seconds(date, time),
    do: :calendar.datetime_to_gregorian_seconds({Date.to_erl(date), Time.to_erl(time)})

  defp at(date, time, zone, :hour),
    do: Tempo.from_iso8601!("#{date}T#{pad(time.hour)}[#{zone}]")

  defp at(date, time, zone, :minute),
    do: Tempo.from_iso8601!("#{date}T#{pad(time.hour)}:#{pad(time.minute)}[#{zone}]")

  defp pad(number), do: String.pad_leading(Integer.to_string(number), 2, "0")

  defp units(reading, :hour), do: Keyword.delete(reading, :minute)
  defp units(reading, :minute), do: reading

  describe "the changes found for a zone" do
    test "show a moment clear of them, or not, once they are found" do
      for zone <- @zones do
        [{change, _before, _later} | _others] = found_changes(zone)
        midwinter = gregorian_seconds(~D[2026-01-10], ~T[12:00:00])
        midsummer = gregorian_seconds(~D[2026-07-10], ~T[12:00:00])

        assert TimeZoneDatabase.clear_of_changes?(zone, midwinter, 86_400)
        assert TimeZoneDatabase.clear_of_changes?(zone, midsummer, 86_400)
        refute TimeZoneDatabase.clear_of_changes?(zone, change + 3_600, 86_400)
        refute TimeZoneDatabase.clear_of_changes?(zone, change - 86_400, 86_400)
        assert TimeZoneDatabase.clear_of_changes?(zone, change - 86_401, 86_400)
      end
    end

    test "show nothing of a zone the database does not know, and nothing is asked for it" do
      midsummer = gregorian_seconds(~D[2026-07-10], ~T[12:00:00])

      refute TimeZoneDatabase.change_within?("Nowhere/Never", midsummer, 86_400)
      refute TimeZoneDatabase.clear_of_changes?("Nowhere/Never", midsummer, 86_400)
    end

    test "show a value clear of them for a step, by its first reading" do
      found_changes("Europe/Paris")

      assert Zone.clear_of_changes?(Tempo.from_iso8601!("2026-06-15T10[Europe/Paris]"), 3_600)
      # The clocks go forward on 29 March 2026.
      refute Zone.clear_of_changes?(Tempo.from_iso8601!("2026-03-28T10[Europe/Paris]"), 3_600)
      # Three days before is clear for an hour, and not for two days.
      assert Zone.clear_of_changes?(Tempo.from_iso8601!("2026-03-26T00[Europe/Paris]"), 3_600)
      refute Zone.clear_of_changes?(Tempo.from_iso8601!("2026-03-26T00[Europe/Paris]"), 172_800)
      refute Zone.clear_of_changes?(Tempo.from_iso8601!("2026-06-15T10"), 3_600)
    end
  end

  describe "a value in a zone stepped by hours" do
    test "is the reading the clock shows that long after, on every hour of a year" do
      # A change by an hour, and one by half an hour.
      for zone <- ["Europe/Paris", "Australia/Lord_Howe"] do
        found_changes(zone)

        for date <- Date.range(~D[2026-01-01], ~D[2026-12-31]),
            hour <- 0..23,
            time = Time.new!(hour, 0, 0),
            shown_once?(date, time, zone),
            hours <- [1, -1, 25] do
          stepped = Tempo.shift(at(date, time, zone, :hour), hour: hours)

          # A step that lands between hours is written to the minute.
          assert {zone, date, hour, hours, units(stepped.time, :minute)} ==
                   {zone, date, hour, hours,
                    reading_after(date, time, zone, hours * 3_600)
                    |> units(resolution(stepped))}
        end
      end
    end
  end

  describe "a value in a zone stepped by minutes" do
    test "is the reading the clock shows that long after, about each change of a year" do
      for zone <- @zones do
        for {change, _before, _later} <- found_changes(zone),
            {{year, _month, _day}, _time} = :calendar.gregorian_seconds_to_datetime(change),
            year == 2026,
            date <- about(change),
            minute_of_day <- 0..1_439//15,
            time = Time.new!(div(minute_of_day, 60), rem(minute_of_day, 60), 0),
            shown_once?(date, time, zone),
            minutes <- [30, -45, 600] do
          stepped = Tempo.shift(at(date, time, zone, :minute), minute: minutes)

          assert {zone, date, time, minutes, stepped.time} ==
                   {zone, date, time, minutes, reading_after(date, time, zone, minutes * 60)}
        end
      end
    end
  end

  describe "an hour a selection makes in a zone" do
    test "ends at the reading the clock shows an hour after it starts" do
      found_changes("Europe/Paris")

      # June is clear of every change, and the clocks go back on 25 October.
      for {selection, month} <- [
            {"2026Y6ML{1..28}DT{0..23}HN[Europe/Paris]", 6},
            {"2026Y10ML{20..28}DT{0..23}HN[Europe/Paris]", 10}
          ] do
        {:ok, hours} = Tempo.to_interval(Tempo.from_iso8601!(selection))

        compared =
          for occurrence <- IntervalSet.members(hours),
              [year: 2026, month: ^month, day: day, hour: hour] = Interval.from(occurrence).time,
              date = Date.new!(2026, month, day),
              time = Time.new!(hour, 0, 0),
              shown_once?(date, time, zone = "Europe/Paris") do
            assert {date, hour, Interval.to(occurrence).time} ==
                     {date, hour, units(reading_after(date, time, zone, 3_600), :hour)}
          end

        assert length(compared) >= 8 * 24
      end
    end
  end

  # The days from three before a change to three after it.
  defp about(change) do
    {date, _time} = :calendar.gregorian_seconds_to_datetime(change)
    on = Date.from_erl!(date)
    Date.range(Date.add(on, -3), Date.add(on, 3))
  end

  defp resolution(%Tempo{time: time}),
    do: if(Keyword.has_key?(time, :minute), do: :minute, else: :hour)
end
