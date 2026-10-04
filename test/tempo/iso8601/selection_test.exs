defmodule Tempo.Parser.Selection.Test do
  use ExUnit.Case, async: true

  alias Calendrical.Hebrew
  alias Tempo.Interval
  alias Tempo.IntervalSet

  test "selections" do
    # First Monday in March, 2018
    assert Tempo.from_iso8601("2018Y3ML1K1IN") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 3, selection: [day_of_week: 1, instance: 1]]
              }}

    # September 2018, 3rd instance of 08:20
    assert Tempo.from_iso8601("2018Y9MTLT8H20M3IN") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 9, selection: [hour: 8, minute: 20, instance: 3]]
              }}

    # First instance of February 29th in the years 2018..2022
    assert Tempo.from_iso8601("{2018,2019,2020,2021,2022}YL2M29D1IN") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: [2018..2022], selection: [month: 2, day: 29, instance: 1]]
              }}

    # Second Sunday in May
    assert Tempo.from_iso8601("L5M7K2IN") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [selection: [month: 5, day_of_week: 7, instance: 2]]
              }}

    # 5:00:00 p.m. of the fourth Thursday in November, in UTC-05:00
    assert Tempo.from_iso8601("X*YL11M4K4INT17HZ-5H") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [
                  year: :any,
                  selection: [month: 11, day_of_week: 4, instance: 4],
                  hour: 17
                ],
                shift: [hour: -5]
              }}

    # first Thursday after April 18th
    assert Tempo.from_iso8601("L4M{19..26}D4K1IN") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [
                  selection: [
                    month: 4,
                    day: [19..26],
                    day_of_week: 4,
                    instance: 1
                  ]
                ]
              }}

    # Tuesday following the first Monday of November of any four-digit even numbered year
    assert Tempo.from_iso8601("XXX{0,2,4,6,8}Y11MLLL1K1IN/P9DN2K1IN") ==
             {
               :ok,
               %Tempo{
                 calendar: Calendrical.Gregorian,
                 time: [
                   year: {:mask, [:X, :X, :X, [0, 2, 4, 6, 8]]},
                   month: 11,
                   selection: [
                     interval: %Tempo.Interval{
                       from: %Tempo{
                         calendar: Calendrical.Gregorian,
                         time: [selection: [day_of_week: 1, instance: 1]]
                       },
                       to: nil,
                       duration: %Tempo.Duration{time: [day: 9]}
                     },
                     day_of_week: 2,
                     instance: 1
                   ]
                 ]
               }
             }

    # First Monday in 2018
    assert Tempo.from_iso8601("2018YL1K1IN") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, selection: [day_of_week: 1, instance: 1]]
              }}

    # First Monday in 2018 at 10am
    assert Tempo.from_iso8601("2018YL1K1INT10H0M0S") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [
                  year: 2018,
                  selection: [day_of_week: 1, instance: 1],
                  hour: 10,
                  minute: 0,
                  second: 0
                ]
              }}

    # Every Monday, Tuesday and Friday in 2018
    assert Tempo.from_iso8601("2018YL{1,2,5}KN") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, selection: [day_of_week: [1..2, 5]]]
              }}

    # First Monday in September for 5 days
    assert Tempo.from_iso8601("2018Y9ML1K1IN/P5D") ==
             {
               :ok,
               %Tempo.Interval{
                 duration: %Tempo.Duration{time: [day: 5]},
                 from: %Tempo{
                   calendar: Calendrical.Gregorian,
                   time: [year: 2018, month: 9, selection: [day_of_week: 1, instance: 1]]
                 },
                 to: nil
               }
             }

    # First and third Monday in September for 5 days
    assert Tempo.from_iso8601("2018Y9ML{1,3}K1IN/P5D") ==
             {
               :ok,
               %Tempo.Interval{
                 duration: %Tempo.Duration{time: [day: 5]},
                 from: %Tempo{
                   calendar: Calendrical.Gregorian,
                   time: [year: 2018, month: 9, selection: [day_of_week: [1, 3], instance: 1]]
                 },
                 to: nil
               }
             }
  end

  test "when time units are out of order in a selection" do
    assert {:error, %Tempo.ParseError{} = e} = Tempo.from_iso8601("2018YL1K2MN1D")

    assert Exception.message(e) =~
             "Selection time units must be in decreasing time scale order"
  end

  test "when subsequent time units are greater than the prior selection" do
    assert {:error, %Tempo.ParseError{} = e} = Tempo.from_iso8601("L1DN1M")
    assert Exception.message(e) =~ ":month is greater than the selection max of :day"
  end

  # A time of day selected in a month is on the month's first day, as a time
  # of day under a month is in a value (user, 2026-10-04). ISO 8601-2
  # §12.11.1 example 2 reads it on each day, the third instance of 08:20 in
  # September being 3 September: a divergence, recorded in the conformance
  # guide. The days are named to select among them.
  describe "a time of day selected in a month" do
    defp starts(text) do
      {:ok, set} = text |> Tempo.from_iso8601!() |> Tempo.to_interval()
      Enum.map(IntervalSet.members(set), &Interval.from/1)
    end

    test "is that time on the month's first day" do
      assert starts("2018Y9MLT8H20MN") == [Tempo.from_iso8601!("2018-09-01T08:20")]
      assert starts("2018YLT8H20MN") == [Tempo.from_iso8601!("2018-01-01T08:20")]
    end

    test "has no third instance" do
      assert starts("2018Y9MTLT8H20M3IN") == []
    end

    test "is selected among the days that are named" do
      assert starts("2018Y9ML{1..30}DT8H20M3IN") == [Tempo.from_iso8601!("2018-09-03T08:20")]
    end

    test "is not read with its position after the selection's N" do
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("2018Y9MTLT8H20MN3I")
    end
  end

  # The units before a selection name the period it selects in, and are read
  # as they are with no selection after them. A month or a week followed by
  # a selection was held only to the most any year has, so a week its year
  # does not have was read, and converted to a week that does not exist, or
  # in a calendar of weeks raised.
  describe "the period a selection is in" do
    test "is a week its year has" do
      # ISO 8601's 2026 has 53 weeks and its 2027 has 52.
      assert :calendar.iso_week_number({2026, 12, 28}) == {2026, 53}
      assert :calendar.iso_week_number({2027, 12, 28}) == {2027, 52}

      # The Monday of the last week of 2026, a date in a calendar of months.
      assert starts("2026Y53WL1KN") == [Tempo.from_iso8601!("2026-12-28")]

      assert [%Tempo{time: [year: 2026, week: 53, day_of_week: 1]}] =
               "2026Y53WL1KN"
               |> Tempo.from_iso8601!(Calendrical.ISOWeek)
               |> Tempo.to_interval()
               |> elem(1)
               |> IntervalSet.members()
               |> Enum.map(&Interval.from/1)

      for calendar <- [Calendrical.Gregorian, Calendrical.ISOWeek] do
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2027Y53WL1KN", calendar)
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2027Y54WL1KN", calendar)

        assert {:error, %Tempo.InvalidDateError{}} =
                 Tempo.from_iso8601("2027Y{1,53}WL1KN", calendar)
      end
    end

    test "is a month its year has" do
      # A Hebrew year has twelve months or thirteen: 5786 twelve, 5787 thirteen.
      assert Hebrew.months_in_year(5786) == 12
      assert Hebrew.months_in_year(5787) == 13

      assert {:ok, _thirteenth} = Tempo.from_iso8601("5787Y13ML1KN", Hebrew)

      assert {:error, %Tempo.InvalidDateError{}} =
               Tempo.from_iso8601("5786Y13ML1KN", Hebrew)

      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026Y13ML1KN")
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026Y{1,13}ML15DN")
    end

    test "is counted from the end of its year as it is with no selection" do
      assert Tempo.from_iso8601!("2026Y-1ML1KN") == Tempo.from_iso8601!("2026Y12ML1KN")
      assert Tempo.from_iso8601!("2026Y-1WL1KN") == Tempo.from_iso8601!("2026Y53WL1KN")
      assert starts("2026Y-1ML-1DN") == [Tempo.from_iso8601!("2026-12-31")]
    end

    test "is read the same with a selection after it as with none" do
      for period <- ~w(2026Y 2026Y6M 2026Y25W 2026Y6M15D 2026Y200O 2026Y6M15DT10H) do
        {:ok, %Tempo{time: alone}} = Tempo.from_iso8601(period)
        {:ok, %Tempo{time: selected}} = Tempo.from_iso8601(period <> "LT30MN")

        assert Enum.take_while(selected, &(not match?({:selection, _}, &1))) == alone, period
      end
    end
  end

  # A clock second takes no significant digits, and neither does a position
  # (ISO 8601-2 §4.4.3, §12.9), so the `S` after a second is its designator
  # whatever follows it: `0S1I` was read as position 0 to one significant
  # digit, and the second was lost.
  describe "a second followed by a position" do
    test "is the second and the position" do
      assert {:ok, %Tempo{time: time}} = Tempo.from_iso8601("2018Y9ML1KT10H0M0S1IN")

      assert time == [
               year: 2018,
               month: 9,
               selection: [day_of_week: 1, hour: 10, minute: 0, second: 0, instance: 1]
             ]

      assert {:ok, %Tempo{time: [year: 2018, month: 9, selection: selection]}} =
               Tempo.from_iso8601("2018Y9ML1KT10H0M30S2IN")

      assert selection == [day_of_week: 1, hour: 10, minute: 0, second: 30, instance: 2]
    end

    test "in a recurrence's rule" do
      assert {:ok, recurrence} = Tempo.from_iso8601("R/2018-01-01/P1W/FL1KT10H0M0S1IN")

      assert recurrence.repeat_rule.time ==
               [selection: [day_of_week: 1, hour: 10, minute: 0, second: 0, instance: 1]]
    end

    test "is that second of the day the position selects" do
      {:ok, value} = Tempo.from_iso8601("2018Y9ML1KT10H0M30S1IN")
      {:ok, set} = Tempo.to_interval(value)

      assert [first_monday] = IntervalSet.members(set)
      assert Interval.from(first_monday) == Tempo.from_iso8601!("2018-09-03T10:00:30")
    end

    test "reads back from its own text" do
      {:ok, value} = Tempo.from_iso8601("2018Y9ML1KT10H0M30S1IN")

      assert Tempo.from_iso8601(Tempo.to_iso8601!(value)) == {:ok, value}
    end

    test "a position given to significant digits is a parse error" do
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("2018Y9ML1K1950S2IN")
    end
  end

  # FIXME Raises on inspection
  test "fix inspection of me" do
    assert Tempo.from_iso8601("LL4M4D/-P20DN7K-2IN") ==
             {
               :ok,
               %Tempo{
                 calendar: Calendrical.Gregorian,
                 time: [
                   selection: [
                     interval: %Tempo.Interval{
                       from: %Tempo{calendar: Calendrical.Gregorian, time: [month: 4, day: 4]},
                       to: nil,
                       duration: %Tempo.Duration{time: [day: -20]}
                     },
                     day_of_week: 7,
                     instance: -2
                   ]
                 ]
               }
             }
  end
end
