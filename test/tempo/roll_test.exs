defmodule Tempo.RollTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{Interval, IntervalSet, RRule}

  # A part of a rule that rolls each day picked to a weekday
  # (`plans/decisions.md`, 16 to 18): written `(convention)r` beside the day
  # it rolls, as an event is written `(name)e`; the weekdays are the
  # locale's.

  # The days of 2026 each convention gives the 31st, the 1st and the 15th,
  # worked out from a calendar of 2026 with Saturday and Sunday off. The
  # 31st is a Saturday in January and October and a Sunday in May; the 1st
  # is a Sunday in February, March and November and a Saturday in August.
  @thirty_firsts %{
    modified_nearest: [{1, 30}, {3, 31}, {5, 29}, {7, 31}, {8, 31}, {10, 30}, {12, 31}],
    nearest: [{1, 30}, {3, 31}, {6, 1}, {7, 31}, {8, 31}, {10, 30}, {12, 31}],
    preceding: [{1, 30}, {3, 31}, {5, 29}, {7, 31}, {8, 31}, {10, 30}, {12, 31}],
    following: [{2, 2}, {3, 31}, {6, 1}, {7, 31}, {8, 31}, {11, 2}, {12, 31}],
    modified_following: [{1, 30}, {3, 31}, {5, 29}, {7, 31}, {8, 31}, {10, 30}, {12, 31}]
  }

  defp days(recurrence, options \\ []) do
    {:ok, set} = Tempo.to_interval(recurrence, Keyword.put_new(options, :within, ~o"2026"))
    IntervalSet.map(set, &{Tempo.month(&1), Tempo.day(&1)})
  end

  defp monthly(parts), do: Tempo.every!(~o"P1M", from: ~o"2026-01-01", select: parts)

  describe "a roll" do
    test "is read and written beside the day it rolls" do
      text = "R/2026Y1M1D/P1M/FL31D(modified-nearest)rT9H0MN"
      assert Tempo.to_iso8601(Tempo.from_iso8601!(text)) == {:ok, text}
    end

    test "is built as it is read" do
      assert monthly(day: 31, roll: :modified_nearest, hour: 9, minute: 0) ==
               ~o"R/2026-01-01/P1M/FL31D(modified-nearest)rT9H0MN"

      assert monthly(hour: 9, roll: :preceding, day: -1) ==
               ~o"R/2026-01-01/P1M/FL-1D(preceding)rT9HN"
    end

    test "is one of the conventions, and no other" do
      assert {:error, %Tempo.ParseError{}} =
               Tempo.from_iso8601("R/2026-01-01/P1M/FL31D(sideways)rN")

      assert {:error, %ArgumentError{message: message}} = Tempo.selection(day: 1, roll: :sideways)
      assert message =~ ":modified_nearest"
    end

    test "has no RRULE" do
      assert {:error, _no_rrule} = RRule.to_string(monthly(day: 31, roll: :nearest))
    end

    test "is said in words" do
      assert Tempo.explain(monthly(day: 31, roll: :modified_nearest)) =~
               "day 31, each rolled to a weekday (modified nearest)"
    end
  end

  describe "each convention" do
    for {convention, expected} <- @thirty_firsts do
      test "#{convention} moves the 31st" do
        assert days(monthly(day: 31, roll: unquote(convention))) == unquote(expected)
      end
    end

    test "a day rolled out of its month is kept, where the convention lets it go" do
      # 1 February 2026 is a Sunday: the Friday before it is in January.
      assert {1, 30} in days(monthly(day: 1, roll: :preceding))
      assert {2, 2} in days(monthly(day: 1, roll: :modified_preceding))
    end

    test "two days that roll to one are that day once" do
      # 30 and 31 May 2026 are a Saturday and a Sunday.
      assert Tempo.select(~o"2026-05", Tempo.selection!(day: [30, 31], roll: :preceding)) ==
               {:ok, ~o"{2026-05-29}"}
    end

    test "a position counts the days as they are rolled" do
      first = monthly(day: [1, 15], roll: :following, instance: 1)
      assert Enum.take(days(first), 3) == [{1, 1}, {2, 2}, {3, 2}]
    end

    test "a time of day stays on the day as it is rolled" do
      nine = monthly(day: 31, roll: :modified_nearest, hour: 9)
      {:ok, [first | _]} = Tempo.members(nine, within: ~o"2026-01")
      assert Interval.from(first) == ~o"2026-01-30T09"
    end
  end

  describe "the weekdays" do
    # 15 February 2026 is a Sunday and 15 May a Friday. Saudi Arabia works
    # Sunday to Thursday.
    test "are those of the locale asked in" do
      fifteenths = monthly(day: 15, roll: :nearest)

      assert {2, 16} in days(fifteenths, locale: "en-US")
      assert {5, 15} in days(fifteenths, locale: "en-US")

      assert {2, 15} in days(fifteenths, locale: "ar-SA")
      assert {5, 14} in days(fifteenths, locale: "ar-SA")
    end

    test "are asked for by the functions that give a rule its occurrences" do
      fifteenths = monthly(day: 15, roll: :nearest)

      assert {:ok, [sunday]} = Tempo.members(fifteenths, within: ~o"2026-02", locale: "ar-SA")
      assert Tempo.day(sunday) == 15

      assert Tempo.select(~o"2026-02", Tempo.selection!(day: 15, roll: :nearest), locale: "ar-SA") ==
               {:ok, ~o"{2026-02-15}"}
    end
  end

  describe "Tempo.roll_to_workday/3" do
    test "takes the two conventions a rule takes beside its own four" do
      # 31 May 2026 is a Sunday.
      assert Tempo.roll_to_workday(~o"2026-05-31", :US, roll: :nearest) == {:ok, ~o"2026-06-01"}

      assert Tempo.roll_to_workday(~o"2026-05-31", :US, roll: :modified_nearest) ==
               {:ok, ~o"2026-05-29"}
    end
  end
end
