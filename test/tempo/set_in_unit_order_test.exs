defmodule Tempo.SetInUnitOrderTest do
  use ExUnit.Case, async: true

  # A set in a unit gives its values in the order of time, each once
  # (decision 88), whatever order its members are written in.

  import Tempo.Sigils

  alias Tempo.IntervalSet

  @weekend_days_of_june [6, 7, 13, 14, 20, 21, 27, 28]

  defp days(expression) do
    Enum.map(expression, &Tempo.day/1)
  end

  test "a set of weekdays comes day by day" do
    assert days(~o"2026Y6M{6,7}K") == @weekend_days_of_june
  end

  test "a set written out of order comes in the order of time, each once" do
    assert days(~o"2026Y6M{15,1}D") == [1, 15]
    assert days(~o"2026Y6M{1..3,2}D") == [1, 2, 3]
    assert days(~o"2026Y6M{-1,1}D") == [1, 30]
  end

  test "a set in the first unit, and sets in a unit after it" do
    assert Enum.map(~o"{2027,2026}Y", &Tempo.year/1) == [2026, 2027]

    assert Enum.map(~o"2026Y{7,6}M{15,1}D", &Tempo.to_iso8601!/1) ==
             ["2026Y6M1D", "2026Y6M15D", "2026Y7M1D", "2026Y7M15D"]
  end

  test "a set placed by a window, as members and as occurrences" do
    {:ok, members} = Tempo.members(~o"{6,7}K", within: ~o"2026-06")
    {:ok, occurrences} = Tempo.to_interval(~o"{6,7}K", within: ~o"2026-06")

    assert Enum.map(members, &Tempo.day/1) == @weekend_days_of_june
    assert IntervalSet.map(occurrences, &Tempo.day/1) == @weekend_days_of_june
  end
end
