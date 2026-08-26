defmodule TempoTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  doctest Tempo

  test "times with groups that can be expanded and resolved" do
    assert Tempo.from_iso8601("2018Y1G6MU") ==
             {:ok,
              %Tempo{calendar: Calendrical.Gregorian, time: [year: 2018, month: {:group, 1..6}]}}

    assert Tempo.from_iso8601("2018Y1G2MU30D") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: 2018, month: 1, day: 30]}}

    # 5.4.2 Group Example 7
    assert Tempo.from_iso8601("2018Y2G3MU50D") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: 2018, month: 5, day: 20]}}
  end

  test "times with invalid groups" do
    assert {:error, %Tempo.InvalidDateError{} = e} = Tempo.from_iso8601("2018Y1G2MU60D")
    assert Exception.message(e) =~ "60 is not valid"
  end

  test "time with month and day but no year" do
    assert Tempo.from_iso8601("4M{1..-1}D") == {:ok, ~o"4M{1..30}D"}
    assert Tempo.from_iso8601("1M{1..-1}D") == {:ok, ~o"1M{1..31}D"}

    assert {:error, %Tempo.InvalidDateError{month: 2} = e} =
             Tempo.from_iso8601("2M{1..-1}D")

    assert Exception.message(e) =~ "Cannot resolve days in month 2"
  end

  # 5.4.2 Group Example 8
  test "times that are two following groups of the same unit" do
    assert Tempo.from_iso8601("201J2G5YU3DT10H0S") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: [2015..2019], day: 3, hour: 10, minute: 0, second: 0]
              }}
  end

  test "tempo truncation" do
    assert Tempo.trunc(~o"12M31DT1H10M59S", :day) == ~o"12M31D"

    assert {:error, %Tempo.ResolutionError{operation: :trunc, reason: :empty_resolution}} =
             Tempo.trunc(~o"12M31DT1H10M59S", :year)

    assert {:error, %Tempo.InvalidUnitError{unit: :date}} =
             Tempo.trunc(~o"12M31DT1H10M59S", :date)
  end

  test "tempo merging" do
    assert {:error, %Tempo.InvalidDateError{value: 50} = e} =
             Tempo.merge(~o"50M", ~o"2022Y")

    assert Exception.message(e) =~ "50 is not valid"

    assert Tempo.merge(~o"12M", ~o"2022Y") == ~o"2022Y12M"
    assert Tempo.merge(~o"12M", ~o"2022Y1M") == ~o"2022Y1M"
  end

  test "to_date/1" do
    assert Tempo.to_date(~o"2022-11-19") == {:ok, ~D[2022-11-19]}

    assert {:error, %Tempo.ConversionError{target: Date}} =
             Tempo.to_date(~o"2022-11-19T01:02:03")

    assert {:error, %Tempo.ConversionError{target: Date}} = Tempo.to_date(~o"2022")
  end

  test "to_time/1" do
    assert Tempo.to_time(~o"01:02:03") == {:ok, ~T[01:02:03.000000]}

    assert {:error, %Tempo.ConversionError{target: Time}} =
             Tempo.to_time(~o"2022-11-19T01:02:03")

    assert {:error, %Tempo.ConversionError{target: Time}} = Tempo.to_time(~o"01:02")
  end

  test "to_naive_date_time/1" do
    assert Tempo.to_naive_date_time(~o"2022-11-19T01:02:03") ==
             {:ok, ~N[2022-11-19 01:02:03.000000]}

    assert {:error, %Tempo.ConversionError{target: NaiveDateTime}} =
             Tempo.to_naive_date_time(~o"2022-11")

    assert {:error, %Tempo.ConversionError{target: NaiveDateTime}} =
             Tempo.to_naive_date_time(~o"01:02")
  end

  test "to_naive_date_time/1 drops the zone, keeping the wall-clock reading" do
    # A zoned value projects to its wall-clock components with the
    # offset dropped — the numbers do not shift to UTC.
    assert Tempo.to_naive_date_time(~o"2022-11-19T01:02:03Z[Etc/UTC]") ==
             {:ok, ~N[2022-11-19 01:02:03.000000]}
  end

  test "to_date_time/1 preserves the named zone (lossless inverse)" do
    assert Tempo.to_date_time(~o"2022-11-19T01:02:03Z[Etc/UTC]") ==
             {:ok, ~U[2022-11-19 01:02:03.000000Z]}

    # A value with no named zone cannot name a DateTime zone.
    assert {:error, %Tempo.ConversionError{target: DateTime}} =
             Tempo.to_date_time(~o"2022-11-19T01:02:03")

    # Coarser-than-second values cannot fill a DateTime.
    assert {:error, %Tempo.ConversionError{target: DateTime}} =
             Tempo.to_date_time(~o"2022-11")
  end

  defmodule SundayStart do
    use Calendrical.Base.Month,
      month_of_year: 1,
      min_days_in_first_week: 1,
      day_of_week: Calendrical.sunday()
  end

  describe "beginning_of_week/1" do
    test "an ISO calendar puts a Sunday in the week that preceded it" do
      assert Tempo.beginning_of_week(~o"2026-08-16") == ~o"2026Y8M10DT0H0M0S"
    end

    test "a Sunday-start calendar begins its week on that Sunday" do
      sunday = Tempo.from_iso8601!("2026-08-16", SundayStart)

      assert Tempo.to_iso8601(Tempo.beginning_of_week(sunday)) == "2026Y8M16DT0H0M0S"
    end

    test "a time of day is truncated away, as beginning_of_day/1 does" do
      assert Tempo.beginning_of_week(~o"2026-06-17T14:30:00") == ~o"2026Y6M15DT0H0M0S"
    end

    test "every day of one ISO week shares a beginning" do
      week = Enum.map(15..21, &Tempo.beginning_of_week(Tempo.from_iso8601!("2026-06-#{&1}")))

      assert Enum.uniq(week) == [~o"2026Y6M15DT0H0M0S"]
    end

    test "a value with no day cannot be placed in a week" do
      assert {:error, _reason} = Tempo.beginning_of_week(~o"2026-06")
    end
  end

  describe "trunc/2 refuses to cross calendar axes" do
    test ":week names the day that week begins on, not the month" do
      # It used to answer `~o"2026Y8M"` — `trunc` walked past `:day`,
      # found `:month` still coarser than `:week`, and returned it.
      assert Tempo.trunc(~o"2026-08-16T10:00:00", :week) == ~o"2026Y8M10D"
    end

    test "every day of one week truncates to the same day" do
      week = Enum.map(10..16, &Tempo.trunc(Tempo.from_iso8601!("2026-08-#{&1}"), :week))

      assert Enum.uniq(week) == [~o"2026Y8M10D"]
    end

    test "and the day comes from the value's own calendar" do
      sunday = Tempo.from_iso8601!("2026-08-16T10:00:00", SundayStart)

      assert Tempo.to_iso8601(Tempo.trunc(sunday, :week)) == "2026Y8M16D"
      assert Tempo.trunc(~o"2026-08-16T10:00:00", :week) == ~o"2026Y8M10D"
    end

    test "a week-axis value coarsens normally instead" do
      assert %Tempo{} = Tempo.trunc(~o"2026-08-16T10:00:00", :week)
    end

    test "agrees with beginning_of_week/1 on the day it names" do
      value = ~o"2026-08-16T10:00:00"

      assert Tempo.trunc(value, :week) == Tempo.trunc(Tempo.beginning_of_week(value), :day)
    end

    test ":day_of_year on a Gregorian value is refused too" do
      assert {:error, %Tempo.ResolutionError{}} = Tempo.trunc(~o"2026-08-16", :day_of_year)
    end

    test "ordinary coarsening within an axis still works" do
      assert Tempo.trunc(~o"2026-08-16T10:30:00", :day) == ~o"2026Y8M16D"
      assert Tempo.trunc(~o"2026-08-16T10:30:00", :month) == ~o"2026Y8M"
      assert Tempo.trunc(~o"2026-08-16T10:30:00", :year) == ~o"2026Y"
    end

    test "units shared by every axis constrain nothing" do
      assert Tempo.trunc(~o"2026-08-16T10:30:45", :hour) == ~o"2026Y8M16DT10H"
      assert Tempo.trunc(~o"2026-08-16T10:30:45", :minute) == ~o"2026Y8M16DT10H30M"
    end
  end
end
