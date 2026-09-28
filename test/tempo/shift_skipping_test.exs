defmodule Tempo.ShiftSkippingTest do
  @moduledoc """
  `Tempo.shift/3` with `skipping:` — advancing through free time only,
  jumping busy spans at no cost.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  describe "forward shifts through a busy set" do
    test "a clear path is a plain shift" do
      busy = ~o"2026-06-15T10:00/2026-06-15T11:00"

      assert Tempo.shift(~o"2026-06-15T07:00", ~o"PT1H", skipping: busy) ==
               ~o"2026-06-15T08:00:00"
    end

    test "a busy span in the path costs nothing to cross" do
      # 30 minutes free before the meeting, the meeting is skipped,
      # 30 minutes free after it.
      meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"

      assert Tempo.shift(~o"2026-06-15T09:30", ~o"PT1H", skipping: meeting) ==
               ~o"2026-06-15T11:30:00"
    end

    test "multiple busy spans are each skipped" do
      blocks = [~o"2026-06-15T10:00/2026-06-15T11:00", ~o"2026-06-15T12:00/2026-06-15T13:00"]

      assert Tempo.shift(~o"2026-06-15T09:30", ~o"PT3H", skipping: blocks) ==
               ~o"2026-06-15T14:30:00"
    end

    test "consuming exactly the free run lands on the busy start" do
      meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"

      assert Tempo.shift(~o"2026-06-15T09:00", ~o"PT1H", skipping: meeting) ==
               ~o"2026-06-15T10:00:00"
    end

    test "an origin inside a busy span first ejects to its end" do
      meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"

      assert Tempo.shift(~o"2026-06-15T10:30", ~o"PT30M", skipping: meeting) ==
               ~o"2026-06-15T11:30:00"
    end

    test "a zero shift inside a busy span moves to the span's end" do
      meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"

      assert Tempo.shift(~o"2026-06-15T10:30", ~o"PT0S", skipping: meeting) ==
               ~o"2026-06-15T11:00"
    end

    test "a zero shift at a free position is the identity" do
      meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"
      free = ~o"2026-06-15T09:30"
      assert Tempo.shift(free, ~o"PT0S", skipping: meeting) == free
    end

    test "the half-open exclusive end of a busy span is free" do
      meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"

      assert Tempo.shift(~o"2026-06-15T11:00", ~o"PT15M", skipping: meeting) ==
               ~o"2026-06-15T11:15:00"
    end

    test "a day of free time jumps whole busy days" do
      # 4 hours free before midnight, two busy days skipped, 20 hours
      # into the next free day.
      busy_days = [~o"2026-06-16", ~o"2026-06-17"]

      assert Tempo.shift(~o"2026-06-15T20:00", ~o"P1D", skipping: busy_days) ==
               ~o"2026-06-18T20:00:00"
    end

    test "a bounded recurrence is a valid busy set" do
      busy = ~o"R3/2026-01-05/P1D"

      assert Tempo.shift(~o"2026-01-04T22:00", ~o"PT4H", skipping: busy) ==
               ~o"2026-01-08T02:00:00"
    end
  end

  describe "backward shifts" do
    test "a negative duration walks backward through free time" do
      meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"

      assert Tempo.shift(~o"2026-06-15T11:30", second: -3600, skipping: meeting) ==
               ~o"2026-06-15T09:30:00"
    end

    test "an origin inside a busy span ejects backward to its start" do
      meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"

      assert Tempo.shift(~o"2026-06-15T10:30", second: -900, skipping: meeting) ==
               ~o"2026-06-15T09:45:00"
    end

    test "forward then backward round-trips across a busy span" do
      meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"
      start = ~o"2026-06-15T09:30"

      arrived = Tempo.shift(start, ~o"PT1H", skipping: meeting)
      assert Tempo.shift(arrived, second: -3600, skipping: meeting) == ~o"2026-06-15T09:30:00"
    end
  end

  describe "refusals" do
    test "a month of free time has no fixed length" do
      busy = ~o"2026-06-16"

      assert {:error, %Tempo.InvalidUnitError{unit: :month}} =
               Tempo.shift(~o"2026-06-15", ~o"P1M", skipping: busy)
    end

    test "a year of free time has no fixed length" do
      busy = ~o"2026-06-16"

      assert {:error, %Tempo.InvalidUnitError{unit: :year}} =
               Tempo.shift(~o"2026-06-15", ~o"P1Y", skipping: busy)
    end

    test "an origin without a year is an error" do
      busy = ~o"2026-06-16"

      assert {:error, %Tempo.UnanchoredError{}} =
               Tempo.shift(~o"T10:00", ~o"PT1H", skipping: busy)
    end

    test "a busy span without a year is an error" do
      assert {:error, %Tempo.UnanchoredError{}} =
               Tempo.shift(~o"2026-06-15T09:00", ~o"PT1H", skipping: ~o"T10:00/T11:00")
    end

    test "an open-ended busy span cannot be walked past" do
      {:ok, endless} = Tempo.to_interval(~o"2026-06-16/..")

      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Tempo.shift(~o"2026-06-15T09:00", ~o"PT1H", skipping: endless)
    end
  end

  describe "shift/3 without :skipping" do
    test "behaves exactly as shift/2" do
      assert Tempo.shift(~o"2026-06-15", [day: 2], []) == Tempo.shift(~o"2026-06-15", day: 2)
    end
  end
end
