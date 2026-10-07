defmodule Tempo.NewShiftAndZoneTest do
  @moduledoc """
  A `:shift` and a `:zone` given to `Tempo.new/1` together.

  Each says how far the value's clock is from UTC: the shift by its amount,
  and the zone by the offset it is at on that date and time. Where the two
  disagree no one value is meant, and `Tempo.new/1` refuses the pair
  (decided 2026-10-08). It built the value as it was given: ten o'clock of
  a November day in Paris, held five hours ahead of UTC
  (`2022Y11M20DT10HZ5H[Europe/Paris]`).

  The measure is Elixir's own `DateTime.from_naive/2`: the offsets the zone
  is at on that reading of its clock, two of them where the clocks go back
  through it.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ZoneOffsetMismatchError

  @zones [
    "Europe/Paris",
    "America/New_York",
    "America/St_Johns",
    "Asia/Kolkata",
    "Australia/Lord_Howe",
    "Pacific/Apia",
    "Etc/UTC"
  ]

  # A shift as it is given, and its seconds. Each is where one of the zones
  # is at some time of some year.
  @shifts [
    {[hour: -5], -18_000},
    {[hour: -4], -14_400},
    {[hour: -3, minute: 30], -12_600},
    {[hour: -2, minute: 30], -9_000},
    {[hour: 0], 0},
    {[hour: 1], 3_600},
    {[hour: 2], 7_200},
    {[hour: 5, minute: 30], 19_800},
    {[hour: 10, minute: 30], 37_800},
    {[hour: 11], 39_600},
    {[hour: 13], 46_800},
    {[hour: 14], 50_400}
  ]

  # Readings of a clock: a winter's and two summers', and the hours the
  # clocks of Paris, of New York and St John's, and of Lord Howe go back
  # through.
  @readings [
    ~N[2022-11-20 10:00:00],
    ~N[2022-07-20 10:00:00],
    ~N[2020-12-25 12:00:00],
    ~N[2022-10-30 02:30:00],
    ~N[2024-11-03 01:30:00],
    ~N[2026-04-05 01:45:00]
  ]

  ## The measure

  # The offsets a zone is at on a reading of its clock. A day whose first
  # hour the clock skips starts at the first reading it shows.
  defp offsets_at(%NaiveDateTime{} = reading, zone) do
    case DateTime.from_naive(reading, zone) do
      {:ok, at} -> [offset(at)]
      {:ambiguous, first, second} -> [offset(first), offset(second)]
      {:gap, _before, after_it} -> [offset(after_it)]
    end
  end

  defp offsets_at(%Date{} = date, zone),
    do: offsets_at(NaiveDateTime.new!(date, ~T[00:00:00]), zone)

  defp offset(%DateTime{utc_offset: utc_offset, std_offset: std_offset}),
    do: utc_offset + std_offset

  # What is to be said of a shift beside a zone that is at these offsets.
  defp to_say(shift, seconds, zone, offsets) do
    if seconds in offsets,
      do: {:built, shift, zone},
      else: {:refused, zone, seconds, Enum.sort(offsets)}
  end

  defp said({:ok, %Tempo{shift: shift, extended: %{zone_id: zone}}}), do: {:built, shift, zone}

  defp said({:error, %ZoneOffsetMismatchError{} = error}),
    do: {:refused, error.zone_id, error.stated_offset, Enum.sort(error.zone_offsets)}

  defp at(%NaiveDateTime{} = reading) do
    [
      year: reading.year,
      month: reading.month,
      day: reading.day,
      hour: reading.hour,
      minute: reading.minute,
      second: reading.second
    ]
  end

  describe "a shift and a zone given for a date and a time" do
    test "are the value where the zone is at the shift on that reading, and refused where it is not" do
      cells = for zone <- @zones, reading <- @readings, pair <- @shifts, do: {zone, reading, pair}

      verdicts =
        for {zone, reading, {shift, seconds}} <- cells do
          named = {zone, reading, shift}
          expected = to_say(shift, seconds, zone, offsets_at(reading, zone))

          assert {named, said(Tempo.new(at(reading) ++ [shift: shift, zone: zone]))} ==
                   {named, expected}

          elem(expected, 0)
        end

      # Each zone is at one of the shifts on each reading, and at two on a
      # reading its clocks go back through: Paris once, New York and
      # St John's on one night, and Lord Howe.
      assert Enum.frequencies(verdicts) == %{
               built: Enum.count(@zones) * Enum.count(@readings) + 4,
               refused: Enum.count(cells) - Enum.count(@zones) * Enum.count(@readings) - 4
             }
    end

    test "are either of the two offsets of an hour the clocks go back through" do
      back = [year: 2022, month: 10, day: 30, hour: 2, minute: 30, zone: "Europe/Paris"]

      assert Tempo.new(back ++ [shift: [hour: 2]]) ==
               {:ok, ~o"2022Y10M30DT2H30MZ2H[Europe/Paris]"}

      assert Tempo.new(back ++ [shift: [hour: 1]]) ==
               {:ok, ~o"2022Y10M30DT2H30MZ1H[Europe/Paris]"}

      assert {:error, %ZoneOffsetMismatchError{zone_offsets: [7_200, 3_600]}} =
               Tempo.new(back ++ [shift: [hour: 3]])
    end

    test "are asked of the zone to the second" do
      # Paris kept its own mean time, nine minutes and twenty-one seconds
      # ahead of Greenwich, until 1911.
      paris = [year: 1900, month: 6, day: 1, hour: 10, zone: "Europe/Paris"]

      assert offsets_at(~N[1900-06-01 10:00:00], "Europe/Paris") == [561]
      assert {:ok, %Tempo{}} = Tempo.new(paris ++ [shift: [hour: 0, minute: 9, second: 21]])

      assert {:error, %ZoneOffsetMismatchError{stated_offset: 540, zone_offsets: [561]}} =
               Tempo.new(paris ++ [shift: [hour: 0, minute: 9]])
    end
  end

  describe "a shift and a zone given for a date" do
    @days [
      {~D[2022-11-20], "Europe/Paris"},
      # It starts two hours ahead of UTC and ends one ahead.
      {~D[2022-10-30], "Europe/Paris"},
      # The clocks skip its first hour, and it starts at one o'clock.
      {~D[2018-11-04], "America/Sao_Paulo"},
      # Its first hour comes twice.
      {~D[2022-11-06], "America/Havana"}
    ]

    test "are asked where the day starts" do
      assert offsets_at(~D[2018-11-04], "America/Sao_Paulo") == [-7_200]
      assert offsets_at(~D[2022-11-06], "America/Havana") == [-14_400, -18_000]

      for {date, zone} <- @days, hours <- [-5, -4, -3, -2, 1, 2] do
        named = {date, zone, hours}
        shift = [hour: hours]
        expected = to_say(shift, hours * 3_600, zone, offsets_at(date, zone))

        assert {named,
                said(
                  Tempo.new(
                    year: date.year,
                    month: date.month,
                    day: date.day,
                    shift: shift,
                    zone: zone
                  )
                )} == {named, expected}
      end
    end
  end

  describe "a shift and a zone given for a year, a month, a week or a part of a year" do
    # What is given, and the day it starts on.
    @spans [
      {[year: 2022], ~D[2022-01-01]},
      {[year: 2022, month: 7], ~D[2022-07-01]},
      {[year: 2026, week: 24], ~D[2026-06-08]},
      {[year: 2026, day_of_year: 100], ~D[2026-04-10]},
      {[year: 2026, quarter: 2], ~D[2026-04-01]}
    ]

    test "are asked where it starts" do
      # The days the spans start on, by Elixir's own calendar.
      assert :calendar.iso_week_number({2026, 6, 8}) == {2026, 24}
      assert Date.day_of_week(~D[2026-06-08]) == 1
      assert Date.add(~D[2026-01-01], 99) == ~D[2026-04-10]

      for {given, starts} <- @spans,
          zone <- ["Europe/Paris", "America/New_York"],
          hours <- [-5, -4, 1, 2] do
        named = {given, zone, hours}
        shift = [hour: hours]
        expected = to_say(shift, hours * 3_600, zone, offsets_at(starts, zone))

        assert {named, said(Tempo.new(given ++ [shift: shift, zone: zone]))} == {named, expected}
      end
    end

    test "are asked of the day a date of another calendar is" do
      # 1 Kislev 5783 is 25 November 2022, when Paris is an hour ahead.
      {:ok, kislev} = Date.new(5783, 3, 1, Calendrical.Hebrew)
      assert Date.convert!(kislev, Calendar.ISO) == ~D[2022-11-25]

      hebrew = [
        year: 5783,
        month: 3,
        day: 1,
        hour: 10,
        zone: "Europe/Paris",
        calendar: Calendrical.Hebrew
      ]

      assert {:ok, %Tempo{calendar: Calendrical.Hebrew, shift: [hour: 1]}} =
               Tempo.new(hebrew ++ [shift: [hour: 1]])

      assert {:error, %ZoneOffsetMismatchError{stated_offset: 7_200, zone_offsets: [3_600]}} =
               Tempo.new(hebrew ++ [shift: [hour: 2]])
    end
  end

  describe "a shift and a zone that disagree" do
    test "are refused with an error that names the two and the reading" do
      given = [year: 2022, month: 11, day: 20, hour: 10, shift: [hour: 5], zone: "Europe/Paris"]

      assert {:error, %ZoneOffsetMismatchError{} = error} = Tempo.new(given)

      assert Exception.message(error) ==
               ~s|Stated offset +05:00 disagrees with "Europe/Paris" (+01:00) at 2022-11-20T10:00:00.|

      assert Tempo.new(Map.new(given)) == {:error, error}
      assert_raise ZoneOffsetMismatchError, fn -> Tempo.new!(given) end
    end

    test "are built as given where the value has no year, there being no date to ask the zone of" do
      assert Tempo.new(hour: 10, shift: [hour: 5], zone: "Europe/Paris") ==
               {:ok, ~o"T10HZ5H[Europe/Paris]"}

      assert Tempo.new(month: 6, day: 15, hour: 10, shift: [hour: 5], zone: "Europe/Paris") ==
               {:ok, ~o"6M15DT10HZ5H[Europe/Paris]"}
    end
  end
end
