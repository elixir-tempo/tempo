defmodule Tempo.RoundIncrementTest do
  use ExUnit.Case, async: true

  # Rounding and truncating to a multiple of a unit, given as a duration of
  # that unit, and rounding to the nearest period, the next or the one a
  # value starts in (decision 110).

  import Tempo.Sigils

  describe "truncating to an increment" do
    test "is the multiple of the unit the value starts in, counted from the next coarser unit" do
      assert Tempo.trunc(~o"2026-06-15T10:37", ~o"PT15M") == {:ok, ~o"2026-06-15T10:30"}
      assert Tempo.trunc(~o"2026-06-15T10:37:44", ~o"PT10S") == {:ok, ~o"2026-06-15T10:37:40"}
      assert Tempo.trunc(~o"2026-06-15T23:30", ~o"PT6H") == {:ok, ~o"2026-06-15T18"}
      assert Tempo.trunc(~o"2026-08-16", ~o"P3M") == {:ok, ~o"2026-07"}
      assert Tempo.trunc(~o"2027-06", ~o"P5Y") == {:ok, ~o"2025"}
    end

    test "with an increment of one is truncating to the unit" do
      for unit <- [~o"PT1M", ~o"PT1H", ~o"P1D", ~o"P1M", ~o"P1Y"] do
        [{name, 1}] = unit.units
        assert Tempo.trunc(~o"2026-06-15T10:37", unit) == Tempo.trunc(~o"2026-06-15T10:37", name)
      end
    end

    test "is each end of an interval and each member of a set" do
      assert Tempo.trunc(~o"{2026-06-15T10:37,2026-06-15T11:52}", ~o"PT30M") ==
               {:ok, ~o"{2026-06-15T10:30,2026-06-15T11:30}"}
    end

    test "in a named zone, a multiple the clock skips is read after the change" do
      # New York's clock goes from 02:00 to 03:00 on 8 March 2026.
      assert Tempo.trunc(~o"2026-03-08T03:30[America/New_York]", ~o"PT2H") ==
               {:ok, ~o"2026-03-08T03[America/New_York]"}
    end
  end

  describe "rounding to an increment" do
    test "is the nearer multiple, half way going on" do
      assert Tempo.round(~o"2026-06-15T10:37", ~o"PT15M") == {:ok, ~o"2026-06-15T10:30"}
      assert Tempo.round(~o"2026-06-15T10:38", ~o"PT15M") == {:ok, ~o"2026-06-15T10:45"}
      assert Tempo.round(~o"2026-06-15T10:52:30", ~o"PT15M") == {:ok, ~o"2026-06-15T11:00"}
      assert Tempo.round(~o"2026-06-15T23:53", ~o"PT15M") == {:ok, ~o"2026-06-16T00:00"}
      assert Tempo.round(~o"T23:50", ~o"PT15M") == {:ok, ~o"T00:00"}
    end

    test "measures a quarter of the year by its days" do
      # July to September is 92 days; its midpoint is the start of 16 August.
      assert Tempo.round(~o"2026-08-15", ~o"P3M") == {:ok, ~o"2026-07"}
      assert Tempo.round(~o"2026-08-16", ~o"P3M") == {:ok, ~o"2026-10"}
      assert Tempo.round(~o"2026-11-20", ~o"P3M") == {:ok, ~o"2027-01"}
      assert Tempo.round(~o"2028", ~o"P5Y") == {:ok, ~o"2030"}
    end

    test "in a named zone, are readings of its clock" do
      # New York's clock goes back from 02:00 to 01:00 on 1 November 2026, so
      # midnight to 02:00 is three hours, and its midpoint 01:30 daylight time.
      assert Tempo.round(~o"2026-11-01T01:29-04:00[America/New_York]", ~o"PT2H") ==
               {:ok, ~o"2026-11-01T00[America/New_York]"}

      assert Tempo.round(~o"2026-11-01T01:30-04:00[America/New_York]", ~o"PT2H") ==
               {:ok, ~o"2026-11-01T02[America/New_York]"}

      assert Tempo.round(~o"2026-11-01T01:20-05:00[America/New_York]", ~o"PT2H") ==
               {:ok, ~o"2026-11-01T02[America/New_York]"}
    end
  end

  describe "the rounding option" do
    test ":later takes the next period unless the value starts where its period does" do
      assert Tempo.round(~o"2026-06-15T10:31", ~o"PT15M", rounding: :later) ==
               {:ok, ~o"2026-06-15T10:45"}

      assert Tempo.round(~o"2026-06-15T10:45", ~o"PT15M", rounding: :later) ==
               {:ok, ~o"2026-06-15T10:45"}

      assert Tempo.round(~o"2026-06-15T10:45:00", ~o"PT15M", rounding: :later) ==
               {:ok, ~o"2026-06-15T10:45"}

      assert Tempo.round(~o"2026-06-15T10:01", :hour, rounding: :later) ==
               {:ok, ~o"2026-06-15T11"}

      assert Tempo.round(~o"2026-02-01", :month, rounding: :later) == {:ok, ~o"2026-02"}
    end

    test ":earlier is truncating" do
      for period <- [~o"PT15M", :hour, ~o"PT6H", :day] do
        assert Tempo.round(~o"2026-06-15T10:59", period, rounding: :earlier) ==
                 Tempo.trunc(~o"2026-06-15T10:59", period)
      end
    end

    test ":nearest is the default, and rounds as round/2 always has" do
      assert Tempo.round(~o"2022-11-21T13:30:00", :day, rounding: :nearest) ==
               Tempo.round(~o"2022-11-21T13:30:00")
    end
  end

  describe "what is not an increment" do
    test "is an ArgumentError naming the increments allowed" do
      for period <- [~o"PT7M", ~o"PT5H", ~o"P5M", ~o"P2D", ~o"P2W", ~o"PT1H30M"] do
        assert {:error, %ArgumentError{} = error} = Tempo.round(~o"2026-06-15T10:37", period)
        assert Exception.message(error) =~ "divides the next coarser"
        assert {:error, %ArgumentError{}} = Tempo.trunc(~o"2026-06-15T10:37", period)
      end
    end

    test "a rounding that is not one of the three is an ArgumentError" do
      assert {:error, %ArgumentError{}} =
               Tempo.round(~o"2026-06-15T10:37", :hour, rounding: :up)
    end

    test "an increment finer than the value is written to is a ConversionError" do
      assert {:error, %Tempo.ConversionError{reason: {:finer_than_written, :minute}}} =
               Tempo.round(~o"2026-06-15T10", ~o"PT15M")
    end
  end
end
