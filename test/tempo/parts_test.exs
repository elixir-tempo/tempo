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
    assert is_nil(Tempo.year(~o"202XY6M15D"))
    assert is_nil(Tempo.day(~o"2026Y6MXD"))
    assert is_nil(Tempo.week(~o"2026-06"))
    assert is_nil(Tempo.hour(~o"2026-06-15"))
    assert Tempo.day(~o"2026-06-15T10/2026-06-15T17") == 15
    assert is_nil(Tempo.hour(~o"2026-06-15T10/2026-06-15T17"))
    assert Tempo.month(~o"{2026-06-01,2026-06-15}") == 6
    assert is_nil(Tempo.day_of_week(~o"6M15D"))
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

  describe "zoned?/1 and floating?/1 read the clock an expression is read on" do
    test "a set whose members carry a time shift is zoned" do
      set = ~o"{2027-06-15T09Z/2027-06-15T10Z,2027-06-15T14Z/2027-06-15T15Z}"

      assert Tempo.zoned?(set)
      refute Tempo.floating?(set)
      assert Tempo.zoned?(~o"{2027-06-15T09+02:00,2027-06-16T09+02:00}")
    end

    test "a recurrence from a value at a time shift is zoned" do
      assert Tempo.zoned?(~o"R3/2027-06-15T09Z/P1D")
      assert Tempo.zoned?(~o"R/2027-06-15T09+02:00/P1D")
    end

    test "an interval with an open start takes the shift of its end" do
      assert Tempo.zoned?(~o"../2027-06-15T09Z")
    end

    test "a set with a rule of no start takes the clock of the member that has one" do
      assert Tempo.zoned?(Tempo.from_iso8601!("{R/../P1Y,2027-06-16T10Z}"))
    end

    test "a zone written after the set, or a fixed-offset zone, is the expression's" do
      assert Tempo.zoned?(~o"{2027-06-15,2027-06-16}[Europe/Paris]")
      assert Tempo.zoned?(Tempo.from_iso8601!("2027-06-15T10[+02:00]"))
    end

    test "a set of floating members, or of floating members and cycles, is floating" do
      assert Tempo.floating?(~o"{2027-06-15,2027-06-16}")
      assert Tempo.floating?(~o"{2027-06-15,12M25D}")
    end
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

    assert is_nil(Tempo.qualification(~o"2026-06-15", :day))
    assert Tempo.put_metadata(~o"2026-06-15", %{a: 1}).metadata == %{a: 1}
  end

  describe "bounded?/1 of a set" do
    test "a set of durations is bounded, and a set with no last member is not" do
      assert Tempo.bounded?(~o"{P1D,P2D}")
      assert Tempo.bounded?(~o"[PT30M,PT1H]")

      assert {:ok, mondays} = Tempo.select(~o"2026-06-01/..", ~o"1K")
      refute Tempo.bounded?(mondays)
    end
  end
end
