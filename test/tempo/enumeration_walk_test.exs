defmodule Tempo.EnumerationWalk.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Tempo.Interval
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
      # The days of a week of a calendar of months are the dates they name:
      # 2026-W25 runs from Monday 15 June to Sunday 21 June.
      assert units(~o"2026Y25WXK", :day) == Enum.to_list(15..21)
      assert units(~o"2026Y25WX*K", :day) == Enum.to_list(15..21)
      assert Enum.to_list(~o"X*K") == [~o"1K", ~o"2K", ~o"3K", ~o"4K", ~o"5K", ~o"6K", ~o"7K"]

      week = Tempo.from_iso8601!("2026Y25WX*K", Calendrical.ISOWeek)
      assert units(week, :day_of_week) == Enum.to_list(1..7)
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

      assert Enum.count(days) == 122
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

      assert Enum.count(days) == 10
      assert Enum.take(days, 2) == [~o"2020Y2M29D", ~o"2021Y2M28D"]

      # An unspecified year is no year, and with no year the last day of a
      # February cannot be counted: it is kept as written, as it is with no
      # year written.
      assert ~o"X*Y2M-1D".time == [year: :any, month: 2, day: -1]
      assert ~o"2M-1D".time == [month: 2, day: -1]
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

    # A day after a group of months counts from the group's start, which the
    # walk read as the day of each month of the group under a set of years.
    test "a day after a group of months under a set of years counts from the group's start" do
      assert Enum.to_list(~o"{2026,2028}Y2G2MU15D") == [~o"2026Y3M15D", ~o"2028Y3M15D"]
      assert Enum.to_list(~o"{2026,2028}Y2G2MU40D") == [~o"2026Y4M9D", ~o"2028Y4M9D"]

      assert member_starts(Tempo.to_interval(~o"{2026,2028}Y2G2MU15D")) ==
               [~o"2026Y3M15D", ~o"2028Y3M15D"]

      assert Enum.count(Enum.to_list(~o"{2026,2028}Y2G2MU")) == 4
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

  # With no year, a day counted from the end of a month whose length depends
  # on the year cannot be counted until the value is placed on one (user,
  # 2026-10-04). It was counted in the month's longest length, so the last
  # day of February was the 29th whatever year the value was then placed on.
  describe "a day counted from the end of a month with no year" do
    test "is kept as written where the month's length depends on the year" do
      assert ~o"2M-1D".time == [month: 2, day: -1]
      assert ~o"2M{1..-1}D".time == [month: 2, day: [1..-1//1]]
      assert Tempo.to_iso8601(~o"2M-1D") == {:ok, "2M-1D"}
    end

    test "is counted where every year's month is as long" do
      assert ~o"6M-1D" == ~o"6M30D"
      assert ~o"6M{1..-1}D" == ~o"6M{1..30}D"
    end

    test "is counted in the year the value is placed on" do
      assert Tempo.on(~o"2M-1D", ~o"2027") == {:ok, ~o"2027-02-28"}
      assert Tempo.on(~o"2M-1D", ~o"2028") == {:ok, ~o"2028-02-29"}
      assert Tempo.on(~o"2M-2D", ~o"2027") == {:ok, ~o"2027-02-27"}
      assert Tempo.on(~o"2M{1..-1}D", ~o"2027") == {:ok, ~o"2027Y2M{1..28}D"}
    end

    test "is selected in each year of a span" do
      {:ok, last_days} = Tempo.select(~o"2026/2029", ~o"2M-1D")

      assert Enum.map(IntervalSet.members(last_days), &Interval.from/1) ==
               [~o"2026-02-28", ~o"2027-02-28", ~o"2028-02-29"]
    end

    # A value is placed on a year of its own calendar (decided 2026-10-04):
    # the Gregorian `2M-1D` was read in the Hebrew year's calendar.
    test "is counted in the year it is placed on, a year of its own calendar" do
      hebrew_year = Tempo.from_iso8601!("5787Y", Hebrew)
      last_of_the_second_month = Tempo.from_iso8601!("2M-1D", Hebrew)

      assert Tempo.on(last_of_the_second_month, hebrew_year) ==
               Tempo.from_iso8601("5787Y2M30D", Hebrew)

      assert {:error, %Tempo.ConversionError{}} = Tempo.on(~o"2M-1D", hebrew_year)
    end

    test "has to be a day the month can have" do
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2M-30D")
    end

    test "cannot be walked or converted until the value has a year" do
      assert_raise Tempo.UnanchoredError, fn -> Enum.to_list(~o"2M{1..-1}D") end
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"2M-1D")
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"-1M")
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

  describe "an interval whose ends differ in resolution is walked by the finer of them" do
    # An explicit span is iterated at the highest resolution of its boundaries,
    # so its values are the interval and none runs past its end. It was walked
    # by its start's unit, and the last value ran on to the end of that unit.
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

    test "the values are the interval, in the finer unit" do
      assert Enum.to_list(~o"2026/2026-03") == [~o"2026Y1M", ~o"2026Y2M"]
      assert Enum.count(~o"1985/1986-06") == 17
      assert Enum.at(~o"1985/1986-06", 16) == ~o"1986Y5M"
      assert Enum.count(~o"2026Y/2026Y6M15D") == 165
      assert Enum.count(~o"2026-06-15T10/2026-06-15T12:30") == 150
      assert Enum.at(~o"2026-06-15T10/2026-06-15T12:30", 149) == ~o"2026Y6M15DT12H29M"
    end

    test "an end that is the coarser is where the walk stops" do
      hours = Enum.to_list(~o"2026-06-15T10/2026-06-16")

      assert Enum.count(hours) == 14
      assert List.last(hours) == ~o"2026Y6M15DT23H"
    end

    test "an interval written with a duration is walked to the end the duration gives" do
      hours = Enum.to_list(~o"2026-06-15/PT36H")

      assert Enum.count(hours) == 36
      assert List.last(hours) == ~o"2026Y6M16DT11H"
    end

    test "ends on two axes, or in two zones, are ordered as the moments they are" do
      days = Enum.to_list(~o"2026-W25/2026-07-01")

      assert Enum.count(days) == 16
      assert Enum.count(~o"2026-W25/2026-07-01") == 16

      minutes = ~o"2026-06-15T10:00+02:00/2026-06-15T12:00Z"

      assert Enum.count(minutes) == 240
      assert Enum.count(Enum.to_list(minutes)) == 240
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

    # With no year, what depends on the year is refused (decided 2026-10-04):
    # an unspecified day of a February listed the 29 days one can have.
    test "an unspecified unit follows the count, as a mask and a count from the end do" do
      for value <- [~o"2MX*D", ~o"2MXXD", ~o"2M{1..-1}D", ~o"2M", ~o"2M-XD"] do
        assert_raise Tempo.UnanchoredError, fn -> Enum.take(value, 1) end
      end

      # The days of January are listed before February's are asked for.
      assert_raise Tempo.UnanchoredError, fn -> Enum.to_list(~o"X*MX*D") end

      assert {:ok, february} = Tempo.to_interval(~o"2MX*D")
      assert Tempo.to_iso8601!(february) == "2M/3M"
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"2MX*DT10H")

      hebrew_months = Tempo.from_iso8601!("X*M", Calendrical.Hebrew)
      assert_raise Tempo.UnanchoredError, fn -> Enum.take(hebrew_months, 1) end
    end

    test "an unspecified unit that takes the same values every year is listed with no year" do
      assert Enum.count(~o"6MX*D") == 30
      assert Enum.count(~o"X*M") == 12
      assert Enum.count(~o"XXM") == 12
      assert Enum.count(~o"2026Y2MX*D") == 28
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

    test "a group of a set counted from the end of no year" do
      assert_raise Tempo.UnanchoredError, fn -> Enum.take(~o"{1..-1}G3MU", 1) end
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

    # Every minute of an hour is the hour, as a minute with every digit
    # masked is, so the two hours are a span each.
    test "an unspecified minute after a set of hours" do
      assert member_starts(Tempo.to_interval(~o"2026Y6M15DT{9,17}HX*M")) ==
               [~o"2026Y6M15DT9H", ~o"2026Y6M15DT17H"]
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

  # ISO 8601-2 §4.6.2 reads `X*Y12M28D` as 28 December of an unspecified
  # calendar year. The walk read the year as the current one, where every
  # other operation read it as no year in particular.
  describe "an unspecified year is no year in particular" do
    test "the units after it are walked as they are with no year written" do
      assert Enum.take(~o"X*Y12M28D", 2) == [~o"X*Y12M28DT0H", ~o"X*Y12M28DT1H"]
      assert Enum.count(~o"X*Y6M") == Enum.count(~o"6M")
      assert Enum.take(~o"X*YX*MX*D", 2) == [~o"X*Y1M1D", ~o"X*Y1M2D"]

      # A February's days depend on its year, so with none they are not listed.
      assert_raise Tempo.UnanchoredError, fn -> Enum.count(~o"X*Y2M") end
      assert_raise Tempo.UnanchoredError, fn -> Enum.count(~o"2M") end
    end

    test "in a calendar whose months change with the year it is not listed, as with no year" do
      assert_raise Tempo.UnanchoredError, fn ->
        Enum.count(Tempo.from_iso8601!("X*Y6M[u-ca=hebrew]"))
      end

      assert_raise Tempo.UnanchoredError, fn ->
        Enum.count(Tempo.from_iso8601!("6M[u-ca=hebrew]"))
      end
    end

    test "on its own it names nothing to list" do
      assert_raise Tempo.UnanchoredError, fn -> Enum.to_list(~o"X*Y") end
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"X*Y")
    end

    test "it is not anchored, and is placed on a year" do
      refute Tempo.anchored?(~o"X*Y6M")
      assert Tempo.at(~o"2026", ~o"X*Y6M") == {:ok, ~o"2026Y6M"}
    end
  end

  describe "the order and the worth of what a walk yields" do
    test "a year mask below zero is walked from its earliest year" do
      assert Enum.take(~o"-1XXX", 2) == [~o"-1999Y", ~o"-1998Y"]
    end

    test "a value holding a selection is the values it selects" do
      assert Enum.to_list(~o"2026Y4ML1K1IN") == [~o"2026Y4M6D"]
      assert Enum.count(~o"2026Y6ML2KN") == 5

      # A time after the selection is the hour it selects, not that hour's
      # minutes: the span is walked as the day before it is.
      assert Enum.to_list(~o"2026Y4ML1K1INT10H") == [~o"2026Y4M6DT10H"]
      assert Enum.to_list(~o"2026Y4ML1K1INT10H30M") == [~o"2026Y4M6DT10H30M"]

      {:ok, selected} = Tempo.to_interval(~o"2026Y4ML1K1INT10H")
      assert Enum.map(IntervalSet.members(selected), & &1.unit) == [nil]

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
    end

    test "nor ends with no line to share, one with a year and one with none" do
      assert_raise Tempo.UnanchoredError, fn -> Enum.take(~o"X*Y/2030Y", 2) end
      assert_raise Tempo.UnanchoredError, fn -> Enum.take(~o"X*Y6M15D/2030Y", 2) end

      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"X*Y6M15D/2030Y")
    end

    test "but a selection is walked as the spans the interval converts to" do
      assert Enum.to_list(~o"2026Y6ML2KN/P1D") ==
               [~o"2026Y6M2D", ~o"2026Y6M9D", ~o"2026Y6M16D", ~o"2026Y6M23D", ~o"2026Y6M30D"]

      assert_raise Tempo.IntervalEndpointsError, ~r/names several spans/, fn ->
        Enum.take(~o"2026Y6ML2KN/2026Y7M", 2)
      end
    end
  end

  # `Enum.count/1`, and `Enum.member?/2` of a value the walk does not reach,
  # fall back to a walk, which never ended.
  # A range that reaches past the values its unit has in one of the periods
  # it is read in names those of its own values the period has. They are read
  # by `Tempo.UnitValues`, as every range is; the walk clipped the range's
  # ends itself, which moved a stepped range onto days it does not name.
  describe "a range that reaches past the values a period has" do
    test "names the values the period has" do
      assert Enum.to_list(~o"2026Y{1,2}M{28..31}D") ==
               [~o"2026Y1M28D", ~o"2026Y1M29D", ~o"2026Y1M30D", ~o"2026Y1M31D", ~o"2026Y2M28D"]

      assert Enum.to_list(~o"{2026,2028}Y2M{27..-1}D") ==
               [~o"2026Y2M27D", ~o"2026Y2M28D", ~o"2028Y2M27D", ~o"2028Y2M28D", ~o"2028Y2M29D"]
    end

    test "keeps its own steps" do
      # The 3rd and every seventh day on: 3, 10, 17, 24 and 31, of which
      # February has the first four.
      assert units(~o"{1,2}M{3..31//7}D", :day) == [3, 10, 17, 24, 31, 3, 10, 17, 24]
    end
  end

  # A set drops the values its context cannot hold (`2026Y{1,2}M31D` is 31
  # January). One none of whose values exists names no date, as a mask no
  # value matches does (decided 2026-10-04): it walked nothing and converted
  # to an empty set.
  describe "a set none of whose values exists" do
    test "names no date, in the walk and in the conversion" do
      for text <- [
            "2026Y{2,6}M31D",
            "{2,6}M31D",
            "2026Y{2,4,6}M31D",
            "{2026,2027}Y2M29D",
            "{2027,2028}Y53W",
            "{2026,2027}Y366O"
          ] do
        value = Tempo.from_iso8601!(text)

        assert {:error, %Tempo.InvalidDateError{} = error} = Tempo.to_interval(value), text
        assert Exception.message(error) =~ "names no date"
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.to_interval_set(value), text
        assert_raise Tempo.InvalidDateError, ~r/names no date/, fn -> Enum.to_list(value) end
      end
    end

    test "is refused in another calendar's terms too" do
      value = Tempo.from_iso8601!("{5786,5788}Y13M1D", Calendrical.Hebrew)

      assert {:error, %Tempo.InvalidDateError{}} = Tempo.to_interval(value)
    end

    test "is what a mask no value matches is" do
      set = ~o"2026Y{2,6}M31D"
      mask = Tempo.from_iso8601!("1985-02-3X")

      for value <- [set, mask] do
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.to_interval(value)
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.to_string(value)
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.duration(value)
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.union(value, ~o"2026-07")
        assert_raise Tempo.InvalidDateError, fn -> Enum.count(value) end
      end
    end

    test "one of whose values exists still names those" do
      assert Enum.to_list(~o"2026Y{1,2}M31D") == [~o"2026Y1M31D"]
      assert Enum.to_list(~o"2026Y{1,2}M{30..31}D") == [~o"2026Y1M30D", ~o"2026Y1M31D"]
      assert Enum.to_list(~o"{2026,2028}Y2M29D") == [~o"2028Y2M29D"]
      assert Enum.to_list(~o"{2026,2027}Y53W") == [~o"2026Y53W"]
    end
  end

  describe "an interval with no end" do
    test "has no count" do
      assert_raise Tempo.IntervalEndpointsError,
                   ~r/`Enum.count\/1` needs every value of ~o"2026Y\/\.\."/,
                   fn -> Enum.count(~o"2026Y/..") end

      {:ok, from_2026} = Interval.new(from: ~o"2026Y")
      assert_raise Tempo.IntervalEndpointsError, fn -> Enum.count(from_2026) end
    end

    test "holds the values its walk yields, and no others" do
      assert ~o"2030Y" in ~o"2026Y/.."
      refute ~o"2020Y" in ~o"2026Y/.."
      refute ~o"2030Y6M" in ~o"2026Y/.."
      refute ~o"{2030,2031}Y" in ~o"2026Y/.."
      refute ~o"6M" in ~o"2026Y/.."
      refute :year in ~o"2026Y/.."

      assert ~o"2026Y6M15DT12H" in ~o"2026Y6M15DT10H/.."
      refute ~o"2026Y6M15DT9H" in ~o"2026Y6M15DT10H/.."
    end

    test "is searched, on the week axis, until the walk has passed the value" do
      assert Enum.member?(~o"2026Y25W/..", ~o"2030Y1W")
      refute Enum.member?(~o"2026Y25W/..", ~o"2026Y20W")
      refute Enum.member?(~o"2026Y25W/..", ~o"2030Y6M")
    end

    test "with no year comes round for ever, so a search of it is refused" do
      assert_raise Tempo.IntervalEndpointsError, ~r/`Enum.member\?\/2` needs every value/, fn ->
        Enum.member?(~o"T10H/..", ~o"T12H")
      end

      refute Enum.member?(~o"T10H/..", :noon)
    end

    test "is walked as far as it is asked" do
      assert Enum.take(~o"2026Y/..", 3) == [~o"2026Y", ~o"2027Y", ~o"2028Y"]
      assert ~o"2026Y/.." |> Stream.drop(3) |> Enum.take(1) == [~o"2029Y"]
      assert Enum.find(~o"2026Y/..", &(Tempo.year(&1) == 2028)) == ~o"2028Y"
      refute Interval.empty?(~o"2026Y/..")
    end

    # An answer that needs an unbounded walk refuses and never hangs (decided
    # 2026-10-04): `Enum.at/2` with a positive index and `Enum.empty?/1` were
    # answered, and `Enum.at(_, -1)` and `Enum.random/1` walked for ever.
    test "refuses what a slice answers, as a lazy interval set does" do
      {:ok, weekends} = Tempo.select(~o"2026-06-15/..", Tempo.weekends(:US))

      for endless <- [~o"2026Y/..", ~o"2026Y6M15DT10H/..", ~o"T10H/.."] do
        for ask <- [
              &Enum.at(&1, 3),
              &Enum.at(&1, -1),
              &Enum.fetch(&1, 0),
              &Enum.empty?/1,
              &Enum.random/1,
              &Enum.slice(&1, 0, 2),
              &Enum.take(&1, -2)
            ] do
          assert_raise Tempo.IntervalEndpointsError, ~r/has no end/, fn -> ask.(endless) end
          assert_raise Tempo.UnboundedSetError, fn -> ask.(weekends) end
        end
      end
    end

    test "with an end answers them" do
      assert Enum.at(~o"2026Y/2030Y", 3) == ~o"2029Y"
      assert Enum.at(~o"2026Y/2030Y", -1) == ~o"2029Y"
      refute Enum.empty?(~o"2026Y/2030Y")
    end
  end
end
