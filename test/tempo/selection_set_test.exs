defmodule Tempo.SelectionSetTest do
  use ExUnit.Case, async: true

  # A set of selections (decision 34): several selections whose values are
  # taken together, `L{1K2I,3K2I}N`, the second Monday and the second
  # Wednesday. ISO 8601-2 has one rule of a kind in a selection and counts
  # its position among everything selected, so `L{1,3}K2IN` is the second
  # of the Mondays and Wednesdays taken together; RFC 5545's
  # `BYDAY=2MO,2WE` is the set.
  #
  # The measure is `Date`: the nth weekday of a month is found by trying its
  # days.

  import Tempo.Sigils

  alias Tempo.{Interval, IntervalSet, RRule}

  @months for year <- [2024, 2025, 2026, 2027], month <- 1..12, do: {year, month}

  # The nth of a weekday in a month, -1 the last: by `Date` alone.
  defp nth(year, month, weekday, n) do
    first = Date.new!(year, month, 1)

    days =
      first
      |> Date.range(Date.end_of_month(first))
      |> Enum.filter(&(Date.day_of_week(&1) == weekday))

    if n > 0, do: Enum.at(days, n - 1), else: Enum.at(days, n)
  end

  defp month(year, month), do: Tempo.new!(year: year, month: month)

  defp dates(set) do
    set
    |> IntervalSet.members()
    |> Enum.map(fn member ->
      {:ok, date} = Tempo.to_date(member)
      date
    end)
  end

  describe "a set of selections in a month" do
    test "is what each selects, in time order" do
      {:ok, second_monday_and_wednesday} =
        Tempo.selection(all: [[day_of_week: 1, instance: 2], [day_of_week: 3, instance: 2]])

      {:ok, first_monday_and_last_friday} =
        Tempo.selection(all: [[day_of_week: 1, instance: 1], [day_of_week: 5, instance: -1]])

      for {year, month} <- @months do
        {:ok, both} = Tempo.select(month(year, month), second_monday_and_wednesday)
        {:ok, ends} = Tempo.select(month(year, month), first_monday_and_last_friday)

        assert dates(both) == Enum.sort([nth(year, month, 1, 2), nth(year, month, 3, 2)], Date)
        assert dates(ends) == Enum.sort([nth(year, month, 1, 1), nth(year, month, 5, -1)], Date)
      end
    end

    test "is not the nth of the weekdays taken together, as one selection of them is" do
      june = month(2026, 6)

      {:ok, set} =
        Tempo.selection(all: [[day_of_week: 1, instance: 2], [day_of_week: 3, instance: 2]])

      {:ok, together} = Tempo.selection(day_of_week: [1, 3], instance: 2)

      assert {:ok, ~o"{2026-06-08,2026-06-10}"} = Tempo.select(june, set)
      assert {:ok, ~o"{2026-06-03}"} = Tempo.select(june, together)
    end

    test "takes a value two of its selections pick once" do
      {:ok, twice} =
        Tempo.selection(all: [[day_of_week: 1, instance: 2], [day_of_week: 1, instance: 2]])

      assert Tempo.select(month(2026, 6), twice) == {:ok, ~o"{2026-06-08}"}
    end

    test "has a position after it count among all it selects" do
      for {position, expected} <- [{1, ~o"{2026-07-08}"}, {-1, ~o"{2026-07-13}"}] do
        {:ok, selection} =
          Tempo.selection(
            all: [[day_of_week: 1, instance: 2], [day_of_week: 3, instance: 2]],
            instance: position
          )

        assert Tempo.select(month(2026, 7), selection) == {:ok, expected}
      end
    end

    test "has the times after it on each day it selects" do
      {:ok, selection} =
        Tempo.selection(
          all: [[day_of_week: 1, instance: 1], [day_of_week: 5, instance: -1]],
          hour: [9, 17]
        )

      assert Tempo.select(month(2026, 6), selection) ==
               {:ok, ~o"{2026-06-01T09,2026-06-01T17,2026-06-26T09,2026-06-26T17}"}
    end

    test "is made in each of the months written before it" do
      {:ok, selection} =
        Tempo.selection(
          month: [6, 7],
          all: [[day_of_week: 1, instance: 1], [day_of_week: 2, instance: 1]]
        )

      assert Tempo.select(Tempo.new!(year: 2026), selection) ==
               {:ok, ~o"{2026-06-01,2026-06-02,2026-07-06,2026-07-07}"}
    end
  end

  describe "the written form" do
    test "is read and written back" do
      for text <- ["L{1K2I,3K2I}N", "L{1K1I,5K-1I}T9HN", "L6M{1K1I,2K}N", "L{1K{1,3}I}-1IN"] do
        assert {:ok, selection} = Tempo.from_iso8601(text)
        assert Tempo.to_iso8601(selection) == {:ok, text}
      end
    end

    test "is no set of weekdays" do
      assert {:ok, %Tempo{form: {:value, [selection: [day_of_week: [1, 3], instance: 2]]}}} =
               Tempo.from_iso8601("L{1,3}K2IN")
    end

    test "with a selection left empty is no selection" do
      for text <- ["L{1K2I,}N", "L{,1K2I}N", "L{}N", "L{1K2IN"] do
        assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601(text)
      end
    end

    test "with an event no calendar knows is refused" do
      assert {:error, %Tempo.InvalidDateError{reason: {:unknown_event, "nope"}}} =
               Tempo.from_iso8601("L{(nope)e,1K2I}N")
    end
  end

  describe "the builder" do
    test "refuses :all that is no list of selections" do
      assert {:error, %ArgumentError{message: message}} = Tempo.selection(all: :mondays)
      assert message =~ ":all of a selection is a list of selections"

      assert {:error, %ArgumentError{}} = Tempo.selection(all: [[day_of_week: 1], :fridays])
      assert {:error, %ArgumentError{}} = Tempo.selection(all: [[fortnight: 1]])
    end
  end

  describe "an RRULE with numbered weekdays of several days" do
    test "is read to a set of selections and written back as it was" do
      for {rule, written} <- [
            {"FREQ=MONTHLY;BYDAY=2MO,2WE", "R/../P1M/FL{1K2I,3K2I}N"},
            {"FREQ=MONTHLY;BYDAY=1MO,-1FR", "R/../P1M/FL{1K1I,5K-1I}N"},
            {"FREQ=MONTHLY;BYDAY=MO,1TU", "R/../P1M/FL{1K,2K1I}N"},
            {"FREQ=MONTHLY;BYDAY=1MO,3MO;BYSETPOS=-1", "R/../P1M/FL{1K{1,3}I}-1IN"},
            {"FREQ=YEARLY;BYMONTH=6,7;BYDAY=1MO,1TU", "R/../P1Y/FL{6,7}M{1K1I,2K1I}N"}
          ] do
        assert {:ok, recurrence} = RRule.parse(rule)
        assert Tempo.to_iso8601(recurrence) == {:ok, written}
        assert RRule.to_string(recurrence) == {:ok, rule}
      end
    end

    test "has the occurrences each of its weekdays gives" do
      {:ok, recurrence} =
        RRule.parse("FREQ=MONTHLY;BYDAY=2MO,2WE;COUNT=24",
          from: Tempo.new!(year: 2026, month: 1, day: 1)
        )

      expected =
        for {year, month} <- @months, year == 2026, weekday <- [1, 3] do
          nth(year, month, weekday, 2)
        end

      assert Enum.map(recurrence, fn occurrence ->
               {:ok, date} = Tempo.to_date(Interval.from(occurrence))
               date
             end) == Enum.sort(expected, Date)
    end
  end
end
