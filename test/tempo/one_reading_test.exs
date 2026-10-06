defmodule Tempo.OneReadingTest do
  @moduledoc """
  A value means the spans `Tempo.to_interval/2` gives it, and every
  operation reads it so: the defects the matrix of
  `plans/validated-core.md` found where two operations read one value two
  ways.
  """

  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet

  # A mask is a tuple, and a tuple sorts after every number: the comparison
  # ordered the terms as they were written.
  describe "a value that is not one point compares as the point its span starts at" do
    test "a mask, significant digits and a group" do
      assert Tempo.compare(~o"202X", ~o"2026-06-15") == :lt
      assert Tempo.compare(~o"2026-06-15", ~o"202X") == :gt
      assert Tempo.compare(~o"1950S2", ~o"2026-06-15") == :lt
      assert Tempo.compare(~o"2026Y2G3MU", ~o"2026-06-15") == :lt
      assert Tempo.compare(~o"2026Y-1M", ~o"2026-06-15") == :gt
    end

    test "a value that names several spans compares as the first" do
      assert Tempo.compare(~o"2026Y{6,7}M", ~o"2026-06-15") == :lt
      assert Tempo.compare(~o"2026Y{25,27}W", ~o"2026-06-15") == :eq
    end

    test "an interval from such a value is in order where its span is" do
      assert {:ok, _interval} = Interval.new(~o"202X", ~o"2026-06-15")
      assert Tempo.duration(~o"202X", ~o"2026-06-15") == {:ok, ~o"P2357D"}
      assert {:error, %Tempo.IntervalEndpointsError{}} = Interval.new(~o"2026-1X", ~o"2026-06-15")
    end

    test "a value whose span starts at no point is its conversion's error" do
      assert_raise Tempo.ConversionError, fn ->
        Tempo.compare(~o"2026Y[1,2]G3MU", ~o"2026-06-15")
      end

      assert {:error, %Tempo.ConversionError{}} =
               Interval.new(~o"2026Y[1,2]G3MU", ~o"2026-06-15")
    end

    test "a group of a set is the point its first group starts at" do
      assert Tempo.compare(~o"2026Y{2,3}G3MU", ~o"2026-04-01") == :eq
      assert Tempo.compare(~o"2026Y{2,3}G3MU", ~o"2026-06-15") == :lt
    end

    test "a year and a week of it are not one moment" do
      # ISO 8601's first week of 2027 starts on 4 January.
      assert Tempo.compare(~o"2027", ~o"2027-W01") == :lt
      assert Tempo.relation(~o"2026", ~o"2026-W53") == :overlaps
      refute Tempo.within?(~o"2026-W53", ~o"2026")
    end

    test "a day of the year under a year with a margin of error is that day" do
      assert Tempo.compare(~o"2026±2Y166O", ~o"2026-06-15") == :eq
    end
  end

  # A month with no year was `:eq` to any dated day, and before or after
  # one by the order of the terms.
  describe "two values with no line to share have no order" do
    test "a value with a year and one without" do
      assert_raise Tempo.UnanchoredError, fn -> Tempo.compare(~o"6M", ~o"2026-06-15") end

      assert {:error, %Tempo.UnanchoredError{value: ~o"6M"}} =
               Tempo.relation(~o"6M", ~o"2026-06-15")

      assert {:error, %Tempo.UnanchoredError{}} = Interval.new(~o"T10H", ~o"2026-06-15")
    end

    test "two values with no year that lead with different units" do
      assert_raise Tempo.UnanchoredError, fn -> Tempo.compare(~o"25W", ~o"7M") end
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.relation(~o"25W", ~o"7M")
    end

    test "two values with no year on one axis are ordered on it" do
      assert Tempo.compare(~o"6M", ~o"7M") == :lt
      assert Tempo.compare(~o"T10:30", ~o"T09") == :gt
    end

    test "a set does not hold members with no order between them" do
      {:ok, dated} = Tempo.to_interval(~o"2026-06-15")
      {:ok, time_of_day} = Tempo.to_interval(~o"T10H")

      assert {:error, %Tempo.UnanchoredError{}} = IntervalSet.new([dated, time_of_day])
    end
  end

  # ISO 8601-2 §4.6.2: `X*Y12M28D` is 28 December of an unspecified year.
  describe "an unspecified year is no year" do
    test "it is not anchored, and compares as the same value with no year" do
      refute Tempo.anchored?(~o"X*Y6M")
      assert Tempo.compare(~o"X*Y6M", ~o"7M") == :lt
      assert_raise Tempo.UnanchoredError, fn -> Tempo.compare(~o"X*Y6M", ~o"2026-06-15") end
    end

    test "the set operations treat it as they treat a value with no year" do
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.union(~o"X*Y6M", ~o"2026-06-15")
      assert {:ok, _both} = Tempo.union(~o"X*Y6M", ~o"X*Y7M")
    end

    test "it is placed on a year, and on its own places nothing" do
      assert Tempo.at(~o"2026", ~o"X*Y6M") == {:ok, ~o"2026Y6M"}
      assert Tempo.at(~o"2026-06-15", ~o"X*Y") == {:ok, ~o"2026Y6M15D"}
      assert Tempo.at(~o"X*Y", ~o"X*Y") == {:ok, ~o"X*Y"}
    end

    test "a day it cannot hold is no value, as with no year" do
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("X*Y2M30D")
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2M30D")
    end
  end

  # ISO 8601-2 §5.4.2: `2018Y2G3MU50D` is the fiftieth day of the second
  # quarter. The walk yielded the unit in each of the group's values where
  # validation could not count it from the group's start.
  describe "a unit after a group" do
    test "counted from the group's start, it is one value" do
      assert ~o"2026Y2G3MU15D" == ~o"2026Y4M15D"
      assert ~o"2018Y2G3MU50D" == ~o"2018Y5M20D"
    end

    test "that cannot be counted from the group's start is an error, not each of its values" do
      for value <- [~o"2G3MU15D", ~o"2026Y2G3MU{1,15}D", ~o"2026Y2G3MU1XD"] do
        assert {:error, %Tempo.ConversionError{reason: :counted_in_group}} =
                 Tempo.to_interval(value)

        assert_raise Tempo.ConversionError, fn -> Enum.take(value, 1) end
      end
    end

    test "counted in each of the group's values by its nature is the spans the walk yields" do
      {:ok, wednesdays} = Tempo.to_interval(~o"2026Y2G4WU3K")

      assert Enum.map(IntervalSet.members(wednesdays), &Tempo.day(&1.from)) == [28, 4, 11, 18]
      assert Enum.count(~o"2026Y2G4WU3K") == 4
      assert Tempo.duration(~o"2026Y2G4WU3K") == ~o"P4D"
    end

    test "a group of a set of hours is written as it is read" do
      value = ~o"2026Y6M15D{1,2}GT6HU30M"

      assert {:ok, text} = Tempo.to_iso8601(value)
      assert Tempo.from_iso8601!(text) == value
    end
  end

  describe "the spans to_interval/2 gives are those the walk yields" do
    test "significant digits with a unit after them" do
      {:ok, junes} = Tempo.to_interval(~o"1950S2Y6M")

      assert IntervalSet.count(junes) == 100
      assert IntervalSet.first(junes).from == ~o"1900Y6M"
    end

    test "every week of a year, which is not the year" do
      # ISO 8601's weeks of 2026 run from 29 December 2025 to 3 January 2027.
      assert Tempo.to_interval(~o"2026YXXW") == {:ok, ~o"2026Y1W/2027Y1W"}
      assert Tempo.to_interval(~o"2026YX*W") == {:ok, ~o"2026Y1W/2027Y1W"}
      refute Tempo.equal?(~o"2026YXXW", ~o"2026")
    end

    test "an unspecified year alone is no span" do
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"X*Y")
    end
  end

  # The hour a clock shows twice was yielded twice for each value of a time
  # in it, in turn, so `Enum.count/1` and `Enum.to_list/1` disagreed.
  defp offsets_walked(value) do
    value |> Enum.to_list() |> Enum.map(&Compare.offset_seconds(&1.shift)) |> Enum.uniq()
  end

  describe "the walk of a wall time a clock shows twice" do
    test "is the occurrence the value names" do
      first = Tempo.from_iso8601!("2026-10-25T02:30[Europe/Paris]")
      second = Tempo.from_iso8601!("2026-10-25T02:30+01:00[Europe/Paris]")

      assert Enum.count(first) == 60
      assert Enum.count(Enum.to_list(first)) == 60
      assert offsets_walked(first) == [2 * 3600]
      assert offsets_walked(second) == [3600]

      # A value written with an offset is walked in the shape it wrote it,
      # so its first second is the value's own start.
      assert second |> Enum.to_list() |> Enum.map(& &1.shift) |> Enum.uniq() ==
               [[hour: 1, minute: 0]]

      assert hd(Enum.to_list(second)) ==
               Tempo.from_iso8601!("2026-10-25T02:30:00+01:00[Europe/Paris]")
    end

    test "is both occurrences for a value that holds the hour" do
      day = Tempo.from_iso8601!("2026-10-25[Europe/Paris]")

      assert Enum.count(day) == 25
      assert Enum.count(Enum.to_list(day)) == 25
    end
  end

  describe "a floating value and a zoned one are not combined" do
    setup do
      %{
        meeting: Tempo.from_iso8601!("2026-06-15T00:30/2026-06-15T01:30[Europe/Paris]"),
        holiday: ~o"2026-06-15"
      }
    end

    test "by the set operations", %{meeting: meeting, holiday: holiday} do
      for operation <- [
            &Tempo.union/2,
            &Tempo.intersection/2,
            &Tempo.difference/2,
            &Tempo.symmetric_difference/2,
            &Tempo.members_overlapping/2,
            &Tempo.members_outside/2
          ] do
        assert {:error, %Tempo.FloatingTempoError{value: ^holiday}} = operation.(meeting, holiday)
        assert {:error, %Tempo.FloatingTempoError{value: ^holiday}} = operation.(holiday, meeting)
      end

      assert {:error, %Tempo.FloatingTempoError{}} = Tempo.complement(meeting, within: holiday)
    end

    test "nor ordered by the sorter", %{meeting: meeting, holiday: holiday} do
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.compare(meeting.from, holiday) end
      assert_raise Tempo.FloatingTempoError, fn -> Enum.sort([meeting.from, holiday], Tempo) end
    end

    test "and are once the floating one is placed", %{meeting: meeting, holiday: holiday} do
      {:ok, in_paris} = Tempo.in_zone(holiday, "Europe/Paris")

      assert {:ok, left} = Tempo.difference(meeting, in_paris)
      assert IntervalSet.empty?(left)
    end

    test "a set that holds both is refused whichever its first member is", %{meeting: meeting} do
      {:ok, all_day} = Tempo.to_interval(~o"2026-06-20")
      calendar = IntervalSet.new!([meeting, all_day])

      assert {:error, %Tempo.FloatingTempoError{}} = Tempo.intersection(calendar, meeting)
      assert {:error, %Tempo.FloatingTempoError{}} = Tempo.intersection(meeting, calendar)
    end

    test "a time of day placed on a zoned window is in the window's zone" do
      day = Tempo.from_iso8601!("2026-06-15[Europe/Paris]")

      assert {:ok, ten} = Tempo.intersection(~o"T10H", day, within: day)
      assert [%Interval{from: from}] = IntervalSet.members(ten)
      assert from == Tempo.from_iso8601!("2026-06-15T10[Europe/Paris]")
    end
  end

  describe "the set operations" do
    # A B that ended inside one A was dropped for the next, which it reached.
    test "difference/2 cuts each of two overlapping members" do
      bookings = IntervalSet.new!([~o"2026-06-01/2026-06-20", ~o"2026-06-10/2026-06-30"])
      {:ok, left} = Tempo.difference(bookings, ~o"2026-06-12/2026-06-15")

      assert IntervalSet.members(left) == [
               ~o"2026-06-01/2026-06-12",
               ~o"2026-06-10/2026-06-12",
               ~o"2026-06-15/2026-06-20",
               ~o"2026-06-15/2026-06-30"
             ]
    end

    # A window that lies within one day touched no day, so nothing was placed.
    test "a window within one day has the time of day placed on that day" do
      {:ok, free} = Tempo.complement(~o"T10H", within: ~o"2025-01-01T10:00")

      assert IntervalSet.empty?(free)
    end
  end

  describe "Interval.new/2" do
    # The start was named as a day of the Hebrew year 2025.
    test "keeps each end in the calendar it has" do
      hebrew = Tempo.from_iso8601!("5786Y6M15D[u-ca=hebrew]")
      {:ok, mixed} = Interval.new(~o"2025-01-01", hebrew)

      assert {mixed.from.calendar, mixed.to.calendar} ==
               {Calendrical.Gregorian, Calendrical.Hebrew}

      {:ok, text} = Tempo.to_iso8601(mixed)
      again = Tempo.from_iso8601!(text)

      assert {again.from.calendar, again.to.calendar} ==
               {Calendrical.Gregorian, Calendrical.Hebrew}

      assert {:error, %ArgumentError{}} = Tempo.duration(~o"2025-01-01", hebrew)
    end
  end

  describe "bounded?/1" do
    test "a recurrence of a count is as bounded as its occurrences" do
      assert Tempo.bounded?(~o"R3/2026-06-01/P1D")
      assert Tempo.bounded?(~o"R3/P1W/2026-06-22")
      assert Tempo.bounded?(~o"R3/2026Y6M{1,15}D/P1M")
      refute Tempo.bounded?(~o"2026-06-01/..")
    end
  end

  describe "the offset of a zoned value is checked at the start of each span it names" do
    test "a set of months in which the offset is right in one and wrong in another" do
      assert {:error, %Tempo.ZoneOffsetMismatchError{}} =
               Tempo.from_iso8601("2026-{01,07}-15T10:00+01:00[Europe/Paris]", strict: true)

      assert {:ok, _value} =
               Tempo.from_iso8601("2026-{01,02}-15T10:00+01:00[Europe/Paris]", strict: true)
    end
  end

  # The user's decision of 2026-10-03: the window takes the frame of what it
  # bounds. Read as UTC, 1 to 3 June kept the occurrence of 30 May in New
  # York and dropped that of 2 June.
  describe "a :within window with no zone" do
    @new_york Tempo.from_iso8601!("R/2026-05-30T23:30[America/New_York]/P1D")

    defp starts(value, window) do
      {:ok, occurrences} = Tempo.to_interval(value, within: window)

      occurrences
      |> IntervalSet.members()
      |> Enum.map(&{Tempo.month(&1.from), Tempo.day(&1.from)})
    end

    test "bounds a value in a zone in that zone" do
      assert starts(@new_york, ~o"2026-06-01/2026-06-03") == [{5, 31}, {6, 1}, {6, 2}]
    end

    test "gives what it gives a value with no zone" do
      floating = Tempo.from_iso8601!("R/2026-05-30T23:30/P1D")
      window = ~o"2026-06-01/2026-06-03"

      assert starts(@new_york, window) == starts(floating, window)
    end

    test "is the moments it names when it is written with a zone" do
      utc = Tempo.from_iso8601!("2026-06-01T00:00Z/2026-06-03T00:00Z")

      assert starts(@new_york, utc) == [{5, 30}, {5, 31}, {6, 1}]
    end

    test "takes an offset as it takes a zone" do
      offset = Tempo.from_iso8601!("R/2026-05-30T23:30-04:00/P1D")

      assert starts(offset, ~o"2026-06-01/2026-06-03") == [{5, 31}, {6, 1}, {6, 2}]
    end

    test "that has no end starts in the value's zone too" do
      {:ok, occurrences} = Tempo.to_interval(@new_york, within: ~o"2026-06-01/..")
      first = IntervalSet.first(occurrences)

      assert {Tempo.month(first.from), Tempo.day(first.from)} == {5, 31}
    end
  end

  # A set or a range of a clock unit was not held to the unit's values when
  # the value was read, where one of days or months was: the walk yielded
  # hours 24 and 25, `to_interval/2` refused the value, and a set's walk
  # passed over the member the unit lacks.
  describe "a set or a range of hours, minutes, seconds or weekdays past the unit's values" do
    test "is an InvalidDateError when it is read, as one of days is" do
      for text <-
            ~w(2026Y6M15DT{22..25}H 2026Y6M15DT{22,25}H T{22..25}H 2026Y6M15DT10H{58..61}M
                     2026Y6M15DT10H{0,61}M 2026Y6M15DT10H30M{58..61}S 2026Y25W{1,8}K 2026Y6M{28..31}D) do
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601(text), text
      end
    end

    test "names the value the unit lacks and the values it has" do
      {:error, error} = Tempo.from_iso8601("2026Y6M15DT{22..25}H")
      assert Exception.message(error) == "25 is not valid for an hour. The valid values are 0..23"
    end

    test "is read where every value is one the unit has" do
      assert Enum.map(~o"2026Y6M15DT{22..-1}H", &Tempo.hour/1) == [22, 23]
      assert Enum.map(~o"2026Y6M15DT{20..23}H", &Tempo.hour/1) == [20, 21, 22, 23]
      assert Enum.map(~o"2026Y6M15DT10H{0..-1//15}M", &Tempo.minute/1) == [0, 15, 30, 45]
      assert Enum.count(~o"2026Y6M15DT10H30M{0..59}S") == 60
    end
  end

  describe "duration!/2" do
    test "raises what duration/2 returns for what is no value" do
      # Read at run time, so that the compiler does not see a call that can
      # only raise.
      not_a_value = Tempo.from_iso8601!("P1D")

      assert {:error, %ArgumentError{} = error} = Tempo.duration(not_a_value, ~o"2026")

      assert_raise ArgumentError, Exception.message(error), fn ->
        Tempo.duration!(not_a_value, ~o"2026")
      end
    end
  end
end
