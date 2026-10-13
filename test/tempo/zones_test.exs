defmodule Tempo.ZonesTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  describe "a reading the clock skips" do
    test "is no value, read, built or placed" do
      for text <- [
            "2024-03-10T02:30:00[America/New_York]",
            "2024-03-10T02[America/New_York]",
            "2024-W10-7T02:30[America/New_York]",
            "2011-12-30[Pacific/Apia]",
            "2011-12-30T12:00[Pacific/Apia]",
            "2011-12-29/2011-12-30[Pacific/Apia]",
            "2011-10-02T02:15[Australia/Lord_Howe]"
          ] do
        assert {:error, %Tempo.ZoneError{reason: :gap}} = Tempo.from_iso8601(text), text
      end

      assert {:error, %Tempo.ZoneError{reason: :gap}} =
               Tempo.new(
                 year: 2024,
                 month: 3,
                 day: 10,
                 hour: 2,
                 minute: 30,
                 zone: "America/New_York"
               )

      assert {:error, %Tempo.ZoneError{reason: :gap} = error} =
               Tempo.in_zone(~o"2024-03-10T02:30", "America/New_York")

      assert Exception.message(error) =~ "skips"
    end

    test "a value the clock shows a part of is a value" do
      for text <- [
            "2024-03-10[America/New_York]",
            "2024-03-10T03[America/New_York]",
            "2011-12[Pacific/Apia]",
            "2011-12-29/2011-12-31[Pacific/Apia]",
            "2011-10-02T02[Australia/Lord_Howe]",
            "2024-11-03T01:30[America/New_York]"
          ] do
        assert {:ok, _} = Tempo.from_iso8601(text), text
      end
    end

    test "a shift beside the zone gives the moment, whatever the clock showed" do
      assert {:ok, value} = Tempo.from_iso8601("2024-03-10T02:30:00-05:00[America/New_York]")
      assert {:ok, datetime} = Tempo.to_datetime(value)
      assert DateTime.to_naive(datetime) == ~N[2024-03-10 03:30:00]
    end

    test "a walk and a selection leave a skipped day out" do
      december = ~o"2011-12[Pacific/Apia]"

      assert Enum.count(december) == 30
      assert december |> Enum.map(&Tempo.day/1) |> Enum.take(-3) == [28, 29, 31]

      {:ok, fridays} = Tempo.select(december, ~o"5K")
      assert IntervalSet.count(fridays) == 4
    end

    test "a shift passes over a skipped day and lands past a skipped hour" do
      assert Tempo.shift(~o"2011-12-29[Pacific/Apia]", day: 1) ==
               {:ok, ~o"2011-12-31[Pacific/Apia]"}

      assert Tempo.shift(~o"2024-03-09T02:30[America/New_York]", day: 1) ==
               {:ok, ~o"2024-03-10T03:30[America/New_York]"}
    end

    test "a step back lands before a skipped day, and a month back likewise" do
      assert Tempo.shift(~o"2011-12-31[Pacific/Apia]", day: -1) ==
               {:ok, ~o"2011-12-29[Pacific/Apia]"}

      assert Tempo.shift(~o"2012-01-30[Pacific/Apia]", month: -1) ==
               {:ok, ~o"2011-12-29[Pacific/Apia]"}

      assert Tempo.relation(~o"2011-12-29[Pacific/Apia]", ~o"2011-12-31[Pacific/Apia]") == :meets
    end

    test "a recurrence and a set pass over a skipped day" do
      assert Enum.to_list(~o"R4/2011-12-28/P1D[Pacific/Apia]") == [
               ~o"2011-12-28/2011-12-28[Pacific/Apia]",
               ~o"2011-12-29/2011-12-29[Pacific/Apia]",
               ~o"2011-12-31/2011-12-31[Pacific/Apia]",
               ~o"2012-01-01/2012-01-01[Pacific/Apia]"
             ]

      assert Enum.to_list(~o"2011Y12M{29,30,31}D[Pacific/Apia]") == [
               ~o"2011-12-29[Pacific/Apia]",
               ~o"2011-12-31[Pacific/Apia]"
             ]

      assert Enum.to_list(~o"2024Y3M{9,10}DT2H30M[America/New_York]") == [
               ~o"2024-03-09T02:30[America/New_York]"
             ]
    end

    test "a day of a change of the clock has the hours its clock shows" do
      assert Enum.count(~o"2024-03-10[America/New_York]") == 23
      assert Enum.count(~o"2024-11-03[America/New_York]") == 25
    end
  end

  describe "a reading the clock shows twice" do
    test "is two values in a walk, each with the offset it had" do
      shift = ~o"2026-10-31T21/2026-11-01T05[America/New_York]"
      hours = Enum.to_list(shift)

      assert Enum.count(hours) == 9
      assert hours == Enum.uniq(hours)

      assert Enum.slice(hours, 4, 2) == [
               ~o"2026-11-01T01-04:00[America/New_York]",
               ~o"2026-11-01T01-05:00[America/New_York]"
             ]

      [first, second] = Enum.slice(hours, 4, 2)
      assert Tempo.relation(first, second) == :meets
      assert Tempo.duration(first, second) == {:ok, ~o"PT1H"}
    end

    test "each value of the walk reads back from its text" do
      for hour <- ~o"2026-11-01[America/New_York]" do
        assert Tempo.from_iso8601(Tempo.to_iso8601!(hour)) == {:ok, hour}
      end
    end

    test "a reading shown once carries no offset" do
      assert Enum.take(~o"2026-11-01[America/New_York]", 1) == [
               ~o"2026-11-01T00[America/New_York]"
             ]
    end
  end
end
