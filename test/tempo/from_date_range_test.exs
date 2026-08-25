defmodule Tempo.FromDateRangeTest do
  @moduledoc """
  Converting an Elixir `Date.Range` (inclusive) into a Tempo interval
  (half-open): the day-after-last bridge, calendar preservation, and
  refusal of stepped, descending, and empty ranges.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.FiscalYear
  alias Tempo.Duration
  alias Tempo.Interval
  alias Tempo.IntervalSet

  describe "the inclusive-to-half-open bridge" do
    test "the range's last day is inside the interval" do
      # The off-by-one this conversion exists to prevent: a fiscal
      # quarter's final day must count.
      {:ok, calendar} = FiscalYear.calendar_for(:AU)
      {:ok, quarter} = Tempo.from_elixir(calendar.quarter(2027, 1))
      {:ok, workdays} = Tempo.select(quarter, Tempo.workdays(:AU))

      assert IntervalSet.count(workdays) == 66
    end

    test "fiscal and Gregorian describe the same stretch of time" do
      {:ok, calendar} = FiscalYear.calendar_for(:AU)
      {:ok, quarter} = Tempo.from_elixir(calendar.quarter(2027, 1))
      {:ok, fiscal_workdays} = Tempo.select(quarter, Tempo.workdays(:AU))
      {:ok, gregorian_workdays} = Tempo.select(~o"2026-07-01/2026-10-01", Tempo.workdays(:AU))

      assert IntervalSet.count(fiscal_workdays) == IntervalSet.count(gregorian_workdays)
    end

    test "a Gregorian month covers all of its days" do
      {:ok, july} = Tempo.from_date_range(Date.range(~D[2026-07-01], ~D[2026-07-31]))

      assert july == Tempo.to_interval!(~o"2026-07-01/2026-08-01")
      assert Tempo.contains?(july, ~o"2026-07-31")
    end

    test "a whole fiscal year is 365 days, not 364" do
      {:ok, calendar} = FiscalYear.calendar_for(:AU)
      {:ok, year} = Tempo.from_elixir(calendar.year(2027))

      assert Duration.to_unit(Tempo.duration(year), :day) == {:ok, 365.0}
    end
  end

  describe "the calendar survives the conversion" do
    test "a fiscal endpoint equals its Gregorian counterpart across calendars" do
      {:ok, calendar} = FiscalYear.calendar_for(:AU)
      {:ok, quarter} = Tempo.from_elixir(calendar.quarter(2027, 1))

      assert quarter.from.calendar == FiscalYear.AU
      assert Tempo.relation(Interval.from(quarter), ~o"2026-07-01") == :equals
    end
  end

  describe "refusals" do
    test "a stepped range is a set of days, not a span" do
      assert {:error, %Tempo.ConversionError{reason: reason}} =
               Tempo.from_date_range(Date.range(~D[2026-07-01], ~D[2026-07-31], 2))

      assert reason =~ "Tempo.select/2"
    end

    test "a descending range is not a calendar period" do
      assert {:error, %Tempo.ConversionError{}} =
               Tempo.from_date_range(Date.range(~D[2026-07-31], ~D[2026-07-01], -1))
    end

    test "an empty range spans no days" do
      assert {:error, %Tempo.ConversionError{reason: reason}} =
               Tempo.from_date_range(Date.range(~D[2026-07-31], ~D[2026-07-01], 1))

      assert reason =~ "empty"
    end
  end

  describe "options and variants" do
    test "resolution defaults to day and honours the option" do
      {:ok, hour_resolution} =
        Tempo.from_date_range(Date.range(~D[2026-07-01], ~D[2026-07-31]), resolution: :hour)

      assert hour_resolution.from.time == [year: 2026, month: 7, day: 1, hour: 0]
    end

    test "the bang variant returns the interval or raises" do
      assert Tempo.from_date_range!(Date.range(~D[2026-07-01], ~D[2026-07-31])) ==
               Tempo.to_interval!(~o"2026-07-01/2026-08-01")

      assert_raise Tempo.ConversionError, fn ->
        Tempo.from_date_range!(Date.range(~D[2026-07-01], ~D[2026-07-31], 2))
      end
    end
  end
end
