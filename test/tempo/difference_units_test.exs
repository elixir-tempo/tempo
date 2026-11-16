defmodule Tempo.DifferenceUnitsTest do
  use ExUnit.Case, async: true

  # The duration between two values from a largest unit down to a smallest
  # (decision 111), and a duration in hand written from a largest unit down.
  # The calendar's units are counted from the start on its calendar, the
  # clock's as the elapsed time left.

  import Tempo.Sigils

  alias Tempo.Duration

  @noon ~o"2026-03-07T12:00[America/New_York]"
  @next_noon ~o"2026-03-08T12:00[America/New_York]"

  describe "Tempo.duration/3 with no options" do
    test "is in one unit, the finer the two values are written to, as always" do
      assert Tempo.duration(@noon, @next_noon) == {:ok, ~o"PT1380M"}
      assert Tempo.duration(~o"2026-01-31", ~o"2026-03-15") == {:ok, ~o"P43D"}
    end
  end

  describe "Tempo.duration/3 with :largest" do
    test "counts a day of the calendar as a day, however long its clock runs" do
      # New York's clock goes forward on 8 March 2026, so noon to noon is 23 hours.
      assert Tempo.duration(@noon, @next_noon, largest: :hour) == {:ok, ~o"PT23H"}
      assert Tempo.duration(@noon, @next_noon, largest: :day) == {:ok, ~o"P1D"}

      assert Tempo.duration(@noon, ~o"2026-03-08T11:30[America/New_York]", largest: :day) ==
               {:ok, ~o"PT22H30M"}
    end

    test "counts months from the start, a month on from 31 January being 28 February" do
      assert Tempo.duration(~o"2026-01-31", ~o"2026-03-15", largest: :month) ==
               {:ok, ~o"P1M15D"}

      assert Tempo.duration(~o"2026-01-31", ~o"2026-03-15T10:30", largest: :year) ==
               {:ok, ~o"P1M15DT10H30M"}

      assert Tempo.duration(~o"1990-06-15", ~o"2026-11-16", largest: :year) ==
               {:ok, ~o"P36Y5M1D"}

      assert Tempo.duration(~o"2026-01", ~o"2027-03", largest: :year) == {:ok, ~o"P1Y2M"}
    end

    test "agrees with Elixir's Date.diff/2 for days" do
      for {from, to} <- [{~D[2026-01-31], ~D[2026-03-15]}, {~D[2024-02-28], ~D[2025-03-01]}] do
        {:ok, a} = Tempo.from_elixir(from)
        {:ok, b} = Tempo.from_elixir(to)

        assert Tempo.duration(a, b, largest: :day) ==
                 {:ok, Duration.new!(day: Date.diff(to, from))}
      end
    end

    test "counts weeks only where a week is the largest or the smallest unit" do
      assert Tempo.duration(~o"2026-01-31", ~o"2026-03-15", largest: :week) == {:ok, ~o"P6W1D"}

      assert Tempo.duration(~o"2026-01-31", ~o"2026-03-15", largest: :month, smallest: :week) ==
               {:ok, ~o"P1M2W"}
    end

    test "writes the clock's units from the largest down, a fraction of a second kept" do
      assert Tempo.duration(~o"2026-01-15T10:00:30", ~o"2026-01-15T12:45:10", largest: :hour) ==
               {:ok, ~o"PT2H44M40S"}

      assert Tempo.duration(~o"2026-01-15T10:00:00.5", ~o"2026-01-15T12:00:01.75", largest: :hour) ==
               {:ok, ~o"PT2H1.25S"}

      assert Tempo.duration(~o"T22:00", ~o"T23:45", largest: :hour) == {:ok, ~o"PT1H45M"}
    end

    test "counts on the calendar of the start, between two zones" do
      # Noon in Paris is 11:00 UTC; noon the next day in New York, 16:00 UTC.
      assert Tempo.duration(
               ~o"2026-03-07T12:00[Europe/Paris]",
               ~o"2026-03-08T12:00[America/New_York]",
               largest: :day
             ) == {:ok, ~o"P1DT5H"}
    end
  end

  describe "Tempo.duration/3 with :smallest" do
    test "drops what is left below it" do
      from = ~o"2026-01-15T10:00:30"
      to = ~o"2026-01-15T12:45:10"

      assert Tempo.duration(from, to, largest: :hour, smallest: :minute) == {:ok, ~o"PT2H44M"}
      assert Tempo.duration(from, to, smallest: :minute) == {:ok, ~o"PT164M"}
      assert Tempo.duration(~o"2026-01-31", ~o"2026-03-15", smallest: :month) == {:ok, ~o"P1M"}

      assert Tempo.duration(~o"2026-01-15T10:00", ~o"2026-01-15T10:00:30",
               largest: :hour,
               smallest: :minute
             ) == {:ok, ~o"PT0M"}
    end
  end

  describe "what Tempo.duration/3 refuses" do
    test "a calendar unit between values with no year" do
      assert {:error, %Tempo.ConversionError{reason: :needs_a_year}} =
               Tempo.duration(~o"T22:00", ~o"T23:45", largest: :day)
    end

    test "a unit that is not one of the seven, or a largest finer than the smallest" do
      assert {:error, %ArgumentError{}} =
               Tempo.duration(~o"2026-01", ~o"2026-03", largest: :decade)

      assert {:error, %ArgumentError{}} =
               Tempo.duration(~o"2026-01", ~o"2026-03", largest: :day, smallest: :month)

      assert {:error, %ArgumentError{}} = Tempo.duration(~o"2026-01", ~o"2026-03", within: 1)
    end
  end

  describe "Tempo.Duration.canonical/2 with :largest" do
    test "writes a duration from that unit down" do
      assert Duration.canonical(~o"PT1500M", largest: :hour) == {:ok, ~o"PT25H"}
      assert Duration.canonical(~o"PT1380M", largest: :hour) == {:ok, ~o"PT23H"}
      assert Duration.canonical(~o"P36D", largest: :day) == {:ok, ~o"P36D"}
      assert Duration.canonical(~o"P1W", largest: :hour) == {:ok, ~o"PT168H"}
      assert Duration.canonical(~o"P14M", largest: :month) == {:ok, ~o"P14M"}
      assert Duration.canonical(~o"P14M", largest: :year) == {:ok, ~o"P1Y2M"}
      assert Duration.canonical(~o"P-2DT3H", largest: :hour) == {:ok, ~o"PT-45H"}
    end

    test "with none, writes each chain from the coarsest unit it reaches, as always" do
      assert Duration.canonical(~o"PT1500M") == {:ok, ~o"P1DT1H"}
      assert Duration.canonical(~o"P36D") == {:ok, ~o"P5W1D"}
    end

    test "refuses a unit finer than a month for a duration with months, and a unit that is not one" do
      assert {:error, %ArgumentError{}} = Duration.canonical(~o"P1M2D", largest: :day)
      assert {:error, %ArgumentError{}} = Duration.canonical(~o"PT90M", largest: :fortnight)
    end
  end
end
