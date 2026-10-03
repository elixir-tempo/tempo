defmodule Tempo.EnumerationWalk.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Calendrical.Gregorian
  alias Calendrical.Hebrew
  alias Tempo.Clock.Test, as: ClockTest
  alias Tempo.IntervalSet

  # The walk of a value reads its components coarse to fine, and each names
  # its values in the context of the ones before it. These pin the shapes
  # that raised an unnamed error or never returned, and the values that
  # were read without their context.

  defp units(enumerable, unit), do: Enum.map(enumerable, & &1.time[unit])

  defp member_starts({:ok, %IntervalSet{} = set}),
    do: set |> IntervalSet.members() |> Enum.map(& &1.from)

  describe "an unspecified or masked unit of every kind" do
    test "a masked and an unspecified week" do
      assert units(~o"2026Y2XW", :week) == Enum.to_list(20..29)
      assert units(~o"2026YX*W", :week) == Enum.to_list(1..53)
    end

    test "a masked and an unspecified day of the week" do
      assert units(~o"2026Y25WXK", :day_of_week) == Enum.to_list(1..7)
      assert units(~o"2026Y25WX*K", :day_of_week) == Enum.to_list(1..7)
      assert Enum.to_list(~o"X*K") == [~o"1K", ~o"2K", ~o"3K", ~o"4K", ~o"5K", ~o"6K", ~o"7K"]
    end

    test "a masked and an unspecified day of the year" do
      assert units(~o"2026Y1XXO", :day_of_year) == Enum.to_list(100..199)
      assert units(~o"2026YX*O", :day_of_year) == Enum.to_list(1..365)
      assert units(~o"2024YX*O", :day_of_year) == Enum.to_list(1..366)
    end

    test "a masked hour, minute and second" do
      assert units(~o"T1XH", :hour) == Enum.to_list(10..19)
      assert units(~o"2026Y6M15DT10H3XM", :minute) == Enum.to_list(30..39)
      assert units(~o"2026Y6M15DT10H30M1XS", :second) == Enum.to_list(10..19)
    end

    test "an unspecified hour, minute and second count from zero" do
      assert units(~o"TX*H", :hour) == Enum.to_list(0..23)
      assert units(~o"T10HX*M", :minute) == Enum.to_list(0..59)
      assert units(~o"2026Y6M15DT10H30MX*S", :second) == Enum.to_list(0..59)
    end

    test "an unspecified month and an unspecified day of a month with no year" do
      assert units(~o"X*M", :month) == Enum.to_list(1..12)
      assert units(~o"6MX*D", :day) == Enum.to_list(1..30)
    end

    test "a mask counted from the end yields the values it names" do
      assert Enum.to_list(~o"2026Y-XM") ==
               Enum.map(4..12, &%{~o"2026Y1M" | time: [year: 2026, month: &1]})

      assert units(~o"T-XH", :hour) == Enum.to_list(15..23)
      assert units(~o"2026Y6M-1XD", :day) == Enum.to_list(12..21)
    end

    test "an unspecified traditional month is an unspecified month" do
      assert Enum.to_list(~o"2026YX*m") == Enum.to_list(~o"2026YX*M")
      assert Tempo.to_interval(~o"2026YX*m") == Tempo.to_interval(~o"2026YX*M")
    end
  end

  describe "each unit is read in the context of the ones before it" do
    test "a masked month and day are the days the year has" do
      assert Enum.count(~o"1985-XX-XX") == 365
      assert Enum.count(~o"1984-XX-XX") == 366
      assert Enum.count(~o"2026YX*MX*D") == 365
    end

    test "a day its month lacks is passed over" do
      assert units(~o"1985-XX-31", :month) == [1, 3, 5, 7, 8, 10, 12]
      assert units(~o"{2023,2024}Y2M29D", :year) == [2024]
    end

    test "a mask is read in each month" do
      assert Enum.take(~o"1985-XX-3X", 3) == [~o"1985Y1M30D", ~o"1985Y1M31D", ~o"1985Y3M30D"]
      assert Enum.count(~o"1985-XX-3X") == 18
      assert Enum.to_list(~o"2026Y{2,6}M3XD") == [~o"2026Y6M30D"]
    end

    test "a set, an unspecified unit and a mask together" do
      days = Enum.to_list(~o"2026Y{6,7}MX*DT{9,17}H")

      assert length(days) == 122
      assert List.first(days) == ~o"2026Y6M1DT9H"
      assert List.last(days) == ~o"2026Y7M31DT17H"
    end

    test "a count from the end under a mask" do
      assert Enum.count(~o"2026YXXM{30..-1}D") == 18
      assert Enum.count(~o"2026YX*M{1..-1}D") == 365
      assert Enum.take(~o"202XY{1..-1}M{1..-1}D", 2) == [~o"2020Y1M1D", ~o"2020Y1M2D"]
    end

    test "a count from the end in each of a set of years" do
      assert Enum.to_list(~o"{2026,2027}Y-1W") == [~o"2026Y53W", ~o"2027Y52W"]
      assert Enum.count(~o"{2026,2027}Y{1..-1}W") == 105

      assert member_starts(Tempo.to_interval(~o"{2026,2027}Y-1D")) ==
               [~o"2026Y12M31D", ~o"2027Y12M31D"]
    end

    # A day counted from the end under one month was read as a day of that
    # month in no year, the 29th of February, before each year was known.
    test "a day counted from the end of one month in each of a set of years" do
      assert Enum.to_list(~o"{2026,2027}Y2M-1D") == [~o"2026Y2M28D", ~o"2027Y2M28D"]
      assert Enum.to_list(~o"{2024..2025}Y2M-1D") == [~o"2024Y2M29D", ~o"2025Y2M28D"]

      assert Enum.to_list(~o"{2024,2025}Y2M{1,-1}D") ==
               [~o"2024Y2M1D", ~o"2024Y2M29D", ~o"2025Y2M1D", ~o"2025Y2M28D"]

      assert member_starts(Tempo.to_interval(~o"{2026,2027}Y2M-1D")) ==
               [~o"2026Y2M28D", ~o"2027Y2M28D"]
    end

    test "a day counted from the end of one month under a masked or unspecified year" do
      days = Enum.to_list(~o"202XY2M-1D")

      assert length(days) == 10
      assert Enum.take(days, 2) == [~o"2020Y2M29D", ~o"2021Y2M28D"]

      year = Date.utc_today().year
      assert [%Tempo{time: [year: ^year, month: 2, day: last]}] = Enum.to_list(~o"X*Y2M-1D")
      assert last == Gregorian.days_in_month(year, 2)
    end

    test "a day counted from the end of a month whose length varies by year in another calendar" do
      days = Enum.to_list(Tempo.from_iso8601!("{5784,5785}Y6M-1D[u-ca=hebrew]"))

      assert Enum.map(days, & &1.time[:day]) ==
               [
                 Hebrew.days_in_month(5784, 6),
                 Hebrew.days_in_month(5785, 6)
               ]
    end

    test "a set of days of the year keeps the days it names" do
      assert member_starts(Tempo.to_interval(~o"2026Y{100,200}D")) ==
               [~o"2026Y4M10D", ~o"2026Y7M19D"]
    end

    test "a group in each of a set of months stops where the month does" do
      assert units(~o"2026Y{2,6}M3G11DU", :day) == Enum.to_list(23..28) ++ Enum.to_list(23..30)
    end

    test "a year with significant digits is each year of its block" do
      assert Enum.count(~o"1950S2Y{1,2}M") == 200
      assert Enum.take(~o"1950S2Y{1,2}M", 3) == [~o"1900Y1M", ~o"1900Y2M", ~o"1901Y1M"]
    end

    test "a margin of error is not a sequence" do
      assert Enum.take(~o"2018±2Y", 2) == [~o"2018Y1M", ~o"2018Y2M"]
      assert Enum.to_list(~o"2018±2Y{1,2}M") == [~o"2018Y1M", ~o"2018Y2M"]
    end
  end

  describe "count/1 agrees with the walk" do
    for text <- [
          "2026Y2XW",
          "2026Y25WX*K",
          "2026Y1XXO",
          "T1XH",
          "T10HX*M",
          "{2026,2027}Y{1..-1}W",
          "2026Y6M15DT10H30M15S",
          "2026Y6M15DT10H30M15.5S",
          "1950S2Y"
        ] do
      test "for #{text}" do
        value = Tempo.from_iso8601!(unquote(text))
        walked = Enum.to_list(value)

        assert Enum.count(value) == length(walked)
        assert Enum.at(value, 1) == Enum.at(walked, 1)
        assert Enum.member?(value, hd(walked))
      end
    end
  end

  describe "an interval whose ends differ in resolution counts as it walks" do
    # count/1 counted the whole units between the ends cut to the unit, so it
    # missed the step that starts after the end's own unit begins.
    for text <- [
          "1985/1986-06",
          "2026Y/2026Y6M15D",
          "2026-01/2026-03-15",
          "2026-06-15/2026-06-17T06",
          "2026-06-15T10/2026-06-15T12:30",
          "2026-06-15T10:00/2026-06-15T10:02:30",
          "1985-06/1987",
          "2026-06-15/2026-07",
          "2026/2026"
        ] do
      test "for #{text}" do
        interval = Tempo.from_iso8601!(unquote(text))
        walked = Enum.to_list(interval)

        assert Enum.count(interval) == length(walked)
        assert Enum.slice(interval, 0, 40) == Enum.take(walked, 40)
        assert Enum.at(interval, length(walked) - 1) == List.last(walked)
      end
    end

    test "the step the end's unit starts in is counted" do
      assert Enum.count(~o"1985/1986-06") == 2
      assert Enum.count(~o"2026Y/2026Y6M15D") == 1
      assert Enum.at(~o"2026-06-15T10/2026-06-15T12:30", 2) == ~o"2026Y6M15DT12H"
    end
  end

  describe "a value that cannot be walked raises the error to_interval returns" do
    test "a unit whose values depend on a year the value does not have" do
      for value <- [~o"X*W", ~o"X*O", ~o"X*D", ~o"{1..-1}W", ~o"2MXXD", ~o"3m"] do
        assert_raise Tempo.UnanchoredError, fn -> Enum.take(value, 1) end
      end

      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"{1..-1}W")
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"3m")
    end

    test "the error names the value" do
      assert_raise Tempo.UnanchoredError, ~r/~o"X\*W" has none/, fn -> Enum.count(~o"X*W") end
      assert_raise Tempo.UnanchoredError, ~r/~o"2MXXD" has none/, fn -> Enum.count(~o"2MXXD") end
    end

    test "a mask no value matches" do
      assert_raise Tempo.InvalidDateError, ~r/no day matches its mask/, fn ->
        Enum.take(~o"1985-02-3X", 1)
      end

      assert {:error, %Tempo.InvalidDateError{}} = Tempo.to_interval(~o"1985-02-3X")
    end

    test "a group that starts beyond what holds it" do
      assert_raise Tempo.InvalidDateError, fn -> Enum.to_list(~o"{2026,2027}Y5G3MU") end
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.to_interval(~o"{2026,2027}Y5G3MU")
    end

    test "a group of a set" do
      assert_raise Tempo.ConversionError, fn -> Enum.take(~o"2026Y{1,2}G3MU", 1) end
      assert_raise Tempo.ConversionError, fn -> Enum.count(~o"2026Y{1,2}G3MU") end
    end

    test "a masked traditional month" do
      assert_raise Tempo.ConversionError, ~r/masks its traditional_month/, fn ->
        Enum.take(~o"2026Y1Xm", 1)
      end
    end
  end

  describe "to_interval/2 lists a value's members without raising" do
    test "a fraction of a second after a set" do
      assert member_starts(Tempo.to_interval(~o"2026Y6M{1,15}DT10H30M15.5S")) ==
               [~o"2026Y6M1DT10H30M15.5S", ~o"2026Y6M15DT10H30M15.5S"]
    end

    test "an unspecified day of the week before a set of hours" do
      assert {:ok, set} = Tempo.to_interval(~o"2026Y25WX*KT{9,17}H")
      assert IntervalSet.count(set) == 14
    end

    test "an unspecified minute after a set of hours" do
      assert {:ok, set} = Tempo.to_interval(~o"2026Y6M15DT{9,17}HX*M")
      assert IntervalSet.count(set) == 120
    end

    test "the weeks of each of a set of years" do
      assert {:ok, set} = Tempo.to_interval(~o"{2026,2027}Y{1..-1}W")
      assert IntervalSet.count(set) == 105
    end

    test "a shift that walks the candidates of a masked hour" do
      assert %IntervalSet{} = set = Tempo.shift(~o"2026Y6M15DT1XH30M", minute: 1)
      assert IntervalSet.count(set) == 10
    end
  end

  # An unspecified year was the current Gregorian year whatever the value's
  # calendar, and read today without `Tempo.Clock`.
  describe "an unspecified year is the current year in its calendar" do
    setup do
      Process.put({Tempo.Clock, :clock}, ClockTest)
      ClockTest.put(~U[2026-10-03 12:00:00Z])
      :ok
    end

    test "by the clock, in the value's own calendar" do
      assert [%Tempo{time: [year: 5787]}] = Enum.to_list(Tempo.from_iso8601!("X*Y[u-ca=hebrew]"))
      assert [%Tempo{time: [year: 1405]}] = Enum.to_list(Tempo.from_iso8601!("X*Y[u-ca=persian]"))
      assert Enum.to_list(~o"X*Y") == [~o"2026Y"]

      ClockTest.put(~U[2031-01-01 00:00:00Z])
      assert Enum.to_list(~o"X*Y") == [~o"2031Y"]
    end
  end

  describe "the order and the worth of what a walk yields" do
    test "a year mask below zero is walked from its earliest year" do
      assert Enum.take(~o"-1XXX", 2) == [~o"-1999Y", ~o"-1998Y"]
    end

    test "a value holding a selection is the values it selects" do
      assert Enum.to_list(~o"2026Y4ML1K1IN") == [~o"2026Y4M6D"]
      assert Enum.take(~o"2026Y4ML1K1INT10H", 2) == [~o"2026Y4M6DT10H0M", ~o"2026Y4M6DT10H1M"]
      assert Enum.count(~o"2026Y6ML2KN") == 5

      assert_raise Tempo.UnboundedRecurrenceError, fn -> Enum.take(~o"X*YL5M7K2IN", 1) end
    end

    test "a struct that is no value is the walk's error" do
      not_a_month = %Tempo{time: [year: 2026, month: 13], calendar: Calendrical.Gregorian}

      assert_raise Tempo.InvalidDateError, fn -> Enum.to_list(not_a_month) end
    end
  end

  describe "an interval with no year" do
    test "that ends before it starts walks round its axis" do
      assert Enum.to_list(~o"T22H/T2H") == [~o"T22H", ~o"T23H", ~o"T0H", ~o"T1H"]
      assert Enum.to_list(~o"7K/3K") == [~o"7K", ~o"1K", ~o"2K"]
      assert Enum.to_list(~o"12M/2M") == [~o"12M", ~o"1M"]
      assert Enum.to_list(~o"12M31D/1M2D") == [~o"12M31D", ~o"1M1D"]
    end

    test "is counted, indexed and searched by its walk" do
      assert Enum.count(~o"T22H/T2H") == 4
      assert Enum.member?(~o"T22H/T2H", ~o"T23H")
      refute Enum.member?(~o"T22H/T2H", ~o"T3H")

      june = Tempo.to_interval!(~o"6M")

      assert Enum.count(june) == 30
      assert Enum.at(june, 1) == ~o"6M2D"
      assert Enum.slice(june, 28, 5) == [~o"6M29D", ~o"6M30D"]
      assert Enum.member?(june, ~o"6M15D")
      refute Enum.member?(june, ~o"2022-06-15")

      assert Enum.count(Tempo.to_interval!(~o"7K")) == 24
    end

    test "of an unspecified year walks its own span" do
      new_years_eve = Tempo.to_interval!(~o"X*Y12M31D")

      assert Enum.count(new_years_eve) == 24
      assert Enum.take(new_years_eve, 2) == [~o"X*Y12M31DT0H", ~o"X*Y12M31DT1H"]
      assert Enum.to_list(~o"X*Y12M31D/X*Y1M2D") == [~o"X*Y12M31D", ~o"X*Y1M1D"]
    end

    test "steps only as far as the walk goes" do
      assert Enum.take(~o"2M27D/..", 2) == [~o"2M27D", ~o"2M28D"]

      assert_raise Tempo.UnanchoredError, ~r/~o"2M28D" has none/, fn ->
        Enum.take(~o"2M27D/..", 3)
      end
    end

    test "whose end depends on the year it lacks" do
      assert_raise Tempo.UnanchoredError, fn -> Enum.to_list(~o"2M28D/P1D") end
      assert_raise Tempo.UnanchoredError, fn -> Enum.count(~o"2M28D/P1D") end

      adar = Tempo.to_interval!(Tempo.from_iso8601!("6M[u-ca=hebrew]"))
      assert_raise Tempo.UnanchoredError, fn -> Enum.member?(adar, ~o"2022-06-15") end
    end
  end

  describe "an interval whose end is no one point" do
    test "to stop at" do
      for interval <- [~o"2026Y/{2026,2027}Y", ~o"2026Y6M15D/2026Y6MXXD", ~o"1M/-1M"] do
        assert_raise Tempo.IntervalEndpointsError, ~r/no one point to stop at/, fn ->
          Enum.take(interval, 1)
        end

        assert_raise Tempo.IntervalEndpointsError, fn -> Enum.count(interval) end
      end
    end

    test "to step from" do
      assert_raise Tempo.ConversionError, fn -> Enum.to_list(~o"{2026,2027}Y/2030Y") end
      assert_raise Tempo.ConversionError, fn -> Enum.to_list(~o"202XY/2040Y") end
      assert_raise Tempo.ConversionError, fn -> Enum.take(~o"X*Y/2030Y", 2) end
    end

    test "but a selection is walked as the spans the interval converts to" do
      assert Enum.to_list(~o"2026Y6ML2KN/P1D") ==
               [~o"2026Y6M2D", ~o"2026Y6M9D", ~o"2026Y6M16D", ~o"2026Y6M23D", ~o"2026Y6M30D"]

      assert_raise Tempo.IntervalEndpointsError, ~r/names several spans/, fn ->
        Enum.take(~o"2026Y6ML2KN/2026Y7M", 2)
      end
    end
  end
end
