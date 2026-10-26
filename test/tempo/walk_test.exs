defmodule Tempo.WalkTest do
  use ExUnit.Case, async: true

  # Walking an expression at a unit, and enumerating one at the unit below
  # its resolution: the paths a span of an unusual resolution takes, and the
  # errors a walk returns rather than raises.

  import Tempo.Sigils

  alias Tempo.Walk

  describe "a span is walked at the resolution of its ends" do
    test "a span of groups walks the units it groups" do
      halves = ~o"2026Y1G6MU/2026Y2G6MU"

      assert Enum.count(halves) == 12
      assert Enum.at(halves, 0) == ~o"2026-01"
    end

    test "a span of traditional months walks the months they are, a leap month among them" do
      # Chinese year 4722 has a leap month after its fifth, so its eighth
      # traditional month is its ninth month.
      months = Tempo.from_iso8601!("4722Y8m/4722Y9m[u-ca=chinese]")

      assert Enum.to_list(months) == [
               Tempo.from_iso8601!("4722Y9M[u-ca=chinese]"),
               Tempo.from_iso8601!("4722Y10M[u-ca=chinese]")
             ]
    end

    test "a tick inside a fraction of a second is in the fraction that holds it" do
      # 10:00:00.749999 is in the hundredth 0.74, as 10:59 is in the hour 10.
      tick = 36_000_749_999

      assert Walk.clock_at(tick, {:microsecond, 2}) ==
               [hour: 10, minute: 0, second: 0, microsecond: {740_000, 2}]

      assert Walk.clock_at(tick, :hour) == [hour: 10]
    end

    test "a span written to a fraction of a second walks that fraction" do
      span = ~o"2026-06-15T10:00:00.5/2026-06-15T10:00:01.5"

      assert Enum.count(span) == 10
      assert Enum.take(span, 2) == [~o"2026-06-15T10:00:00.5", ~o"2026-06-15T10:00:00.6"]
    end
  end

  describe "a value is walked at the unit below it" do
    test "a century before year one holds the years its number names" do
      # ISO 8601-2 §4.4.1.8: -12C is the years -1299 through -1200.
      century = ~o"-12C"

      assert Enum.count(century) == 100
      assert {Enum.at(century, 0), Enum.at(century, -1)} == {~o"-1299Y", ~o"-1200Y"}
    end

    test "a decade before year one holds the years its number names" do
      # ISO 8601-2 §4.4.1.7: -12J is the years -129 through -120.
      decade = Tempo.from_iso8601!("-12J")

      assert Enum.count(decade) == 10
      assert Enum.at(decade, 0) == ~o"-129Y"
    end

    test "a year walked by quarters is its four quarters" do
      assert {:ok, quarters} = Tempo.walk(~o"2026", :quarter)
      assert Enum.to_list(quarters) == [~o"2026Y33M", ~o"2026Y34M", ~o"2026Y35M", ~o"2026Y36M"]
    end

    test "a span walked by a calendar unit is each period its days fall in" do
      assert {:ok, quarters} = Tempo.walk(~o"2026-02/2026-07", :quarter)
      assert Enum.to_list(quarters) == [~o"2026Y33M", ~o"2026Y34M", ~o"2026Y35M"]
    end

    test "a second, or a part of one, with no year is walked by the cycle's tenths and hundredths" do
      assert Enum.take(~o"T10:00:00", 2) == [~o"T10:00:00.0", ~o"T10:00:00.1"]
      assert Enum.take(~o"T10:00:00.5", 2) == [~o"T10:00:00.50", ~o"T10:00:00.51"]
    end

    test "a tenth of a second on the line is its ten hundredths" do
      assert Enum.count(~o"2026-06-15T10:00:00.5") == 10
    end
  end

  describe "what cannot be walked" do
    test "a set with a member that cannot be walked is the member's error, before any step" do
      assert {:error, %Tempo.ConversionError{value: ~o"12M/2M", reason: :needs_a_year}} =
               Tempo.walk(~o"{12M/2M,2026}", :day)
    end

    test "a recurrence with no end is walked as it is read" do
      assert {:ok, days} = Tempo.walk(~o"R/2022-01-01/P1M", :day)
      assert Enum.take(days, 3) == [~o"2022-01-01", ~o"2022-01-02", ~o"2022-01-03"]
    end

    test "a value written to the microsecond has nothing finer" do
      assert_raise Tempo.ConversionError, ~r/has nothing finer to walk or enumerate/, fn ->
        Enum.to_list(~o"2026-06-15T10:00:00.123456")
      end
    end

    test "a unit a span does not step through is named" do
      assert {:error, %Tempo.ConversionError{reason: {:no_walk, :season}} = error} =
               Tempo.walk(~o"2026", :season)

      assert Exception.message(error) =~ "cannot be walked by the season"
    end
  end
end
