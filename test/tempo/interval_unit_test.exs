defmodule Tempo.IntervalUnitTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval

  # The `:unit` field decouples iteration granularity from endpoint
  # resolution: bounds keep their stated resolution while the walk
  # steps at `unit`, filling the anchor once at walk start. See
  # plans/interval-unit.md.

  describe "explicit :unit on Interval.new/1" do
    test "day-resolution bounds walked at :hour yield 24 hours" do
      {:ok, day} = Interval.new(from: ~o"2025-07-04", to: ~o"2025-07-05", unit: :hour)

      assert Enum.count(day) == 24
      assert Enum.count(Enum.to_list(day)) == 24
      assert Enum.at(day, 0) == ~o"2025-07-04T00"
      assert Enum.at(day, 23) == ~o"2025-07-04T23"
    end

    test "the bounds keep their stated resolution" do
      {:ok, day} = Interval.new(from: ~o"2025-07-04", to: ~o"2025-07-05", unit: :hour)

      assert day.from == ~o"2025-07-04"
      assert day.to == ~o"2025-07-05"
      assert day.unit == :hour
    end

    test "member? and slice honour the unit" do
      {:ok, day} = Interval.new(from: ~o"2025-07-04", to: ~o"2025-07-05", unit: :hour)

      assert Enum.member?(day, ~o"2025-07-04T05")
      refute Enum.member?(day, ~o"2025-07-05T00")
      assert Enum.slice(day, 1, 3) == [~o"2025-07-04T01", ~o"2025-07-04T02", ~o"2025-07-04T03"]
    end

    test "year-resolution bounds walked at :month in a 13-month calendar" do
      {:ok, from} = Tempo.from_iso8601("1740", Calendrical.Coptic)
      {:ok, to} = Tempo.from_iso8601("1741", Calendrical.Coptic)
      {:ok, year} = Interval.new(from: from, to: to, unit: :month)

      assert Enum.count(year) == 13
      assert Enum.count(Enum.to_list(year)) == 13
    end

    test "a unit equal to the endpoint resolution normalises to nil" do
      {:ok, day} = Interval.new(from: ~o"2025-07-04", to: ~o"2025-07-05", unit: :day)

      assert day.unit == nil
      assert Enum.count(day) == 1
    end

    test "a unit coarser than the endpoint resolution is rejected" do
      assert {:error, %ArgumentError{}} =
               Interval.new(from: ~o"2025-07-04", to: ~o"2025-07-05", unit: :month)
    end

    test "an unknown unit is rejected" do
      assert {:error, %Tempo.InvalidUnitError{}} =
               Interval.new(from: ~o"2025-07-04", to: ~o"2025-07-05", unit: :fortnight)
    end
  end

  describe "explicit :unit across DST transitions" do
    setup do
      Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
      :ok
    end

    test "a zoned fall-back day walked at :hour counts 25 and matches the walk" do
      {:ok, day} =
        Interval.new(
          from: ~o"2022-11-06[America/New_York]",
          to: ~o"2022-11-07[America/New_York]",
          unit: :hour
        )

      assert Enum.count(day) == 25
      assert Enum.count(Enum.to_list(day)) == 25
    end

    test "a zoned spring-forward day walked at :hour counts 23" do
      {:ok, day} =
        Interval.new(
          from: ~o"2022-03-13[America/New_York]",
          to: ~o"2022-03-14[America/New_York]",
          unit: :hour
        )

      assert Enum.count(day) == 23
      assert Enum.count(Enum.to_list(day)) == 23
    end
  end
end
