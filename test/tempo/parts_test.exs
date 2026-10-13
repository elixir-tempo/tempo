defmodule Tempo.PartsTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ConversionError

  # Reading parts (`plans/architecture-redesign.md`, section 17): a unit as
  # written, through the calendar when the value lies within one period of
  # it, and nil where the expression names several or none.

  test "a unit written is read as written, annotated or not" do
    assert Tempo.year(~o"2026-06-15") == 2026
    assert Tempo.year(~o"2018±2Y") == 2018
    assert Tempo.month(~o"6M15D") == 6
    assert Tempo.minute(~o"2026-06-15T10:30") == 30
    assert Tempo.week(~o"2026Y32W") == 32
  end

  test "a unit the value lies within one period of is read through the calendar" do
    assert Tempo.week(~o"2026-06-15") == 25
    assert Tempo.day(~o"2026Y25W3K") == 17
    assert Tempo.month(~o"2026Y25W3K") == 6
    assert Tempo.day(~o"2026Y-1W3K") == 30
    assert Tempo.day_of_week(~o"2026-06-15") == 1
    assert Tempo.day_of_week(~o"2026-06-15", :sunday) == 2
    assert Tempo.day_of_week(~o"2026-06-14", :sunday) == 1
    assert Tempo.day_of_year(~o"2026-06-15") == 166
    assert Tempo.quarter_of_year(~o"2026-06-15") == 2
  end

  test "an expression that names several or none answers nil" do
    assert Tempo.year(~o"202XY6M15D") == nil
    assert Tempo.day(~o"2026Y6MXD") == nil
    assert Tempo.week(~o"2026-06") == nil
    assert Tempo.hour(~o"2026-06-15") == nil
    assert Tempo.day(~o"2026-06-15T10/2026-06-15T17") == 15
    assert Tempo.hour(~o"2026-06-15T10/2026-06-15T17") == nil
    assert Tempo.month(~o"{2026-06-01,2026-06-15}") == 6
    assert Tempo.day_of_week(~o"6M15D") == nil
  end

  test "resolution, anchored, zoned, bounded and empty" do
    assert Tempo.resolution(~o"2026-06-15T10/2026-06-15T17") == :hour
    assert Tempo.resolution(~o"{2026-01,2026-03-15}") == :day
    assert Tempo.resolution(~o"P1DT2H") == :hour
    assert Tempo.anchored?(~o"2026-06-15/..")
    refute Tempo.anchored?(~o"T10:00")
    assert Tempo.zoned?(~o"2026-06-15T10+02:00")
    assert Tempo.floating?(~o"T10:00")
    refute Tempo.bounded?(~o"{2026-01,2026-06-15/..}")
    assert Tempo.bounded?(~o"R3/2026-06-01/P1D")
    refute Tempo.empty?(~o"{2026-01}")
  end

  test "days in the month and leap years want a year" do
    assert Tempo.days_in_month(~o"2026-04") == {:ok, 30}
    assert {:error, %ConversionError{reason: :needs_a_month}} = Tempo.days_in_month(~o"2026")
    assert Tempo.leap_year?(~o"2024-02-29")
    assert {:error, %ConversionError{reason: :needs_a_year}} = Tempo.leap_year?(~o"6M")
  end

  test "qualifications and metadata" do
    assert Tempo.qualification(~o"2026-06-15?") == %{
             year: :uncertain,
             month: :uncertain,
             day: :uncertain
           }

    assert Tempo.qualification(~o"2026-06-15", :day) == nil
    assert Tempo.put_metadata(~o"2026-06-15", %{a: 1}).metadata == %{a: 1}
  end
end
