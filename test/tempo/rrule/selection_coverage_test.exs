defmodule Tempo.RRule.SelectionCoverageTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.RRule.Selection

  @cal Calendrical.Gregorian

  defp froms(date, selection, freq) do
    candidate = %Tempo.Interval{from: date}
    rule = %Tempo{time: [selection: selection], calendar: @cal}

    candidate
    |> Selection.apply(rule, freq)
    |> Enum.map(& &1.from)
  end

  describe "BYMONTHDAY as a LIMIT (non-monthly freq)" do
    test "keeps a candidate whose day-of-month is listed" do
      assert froms(~o"2022-06-15", [day: [15]], :day) == [~o"2022-06-15"]
    end

    test "drops a candidate whose day-of-month is not listed" do
      assert froms(~o"2022-06-15", [day: [20]], :day) == []
    end
  end

  describe "BYYEARDAY" do
    test "LIMIT keeps a matching ordinal day" do
      assert froms(~o"2022-06-15", [day_of_year: [166]], :day) == [~o"2022-06-15"]
    end

    test "LIMIT drops a non-matching ordinal" do
      assert froms(~o"2022-06-15", [day_of_year: [-1]], :day) == []
    end

    test "a negative index matches the last day of the year" do
      assert froms(~o"2022-12-31", [day_of_year: [-1]], :day) == [~o"2022-12-31"]
    end

    test "EXPAND (YEARLY) projects each listed ordinal, signed indices included" do
      assert froms(~o"2022-01-01", [day_of_year: [166, -1]], :year) ==
               [~o"2022-06-15", ~o"2022-12-31"]
    end
  end

  describe "BYWEEKNO" do
    test "EXPAND (YEARLY) yields the seven days of the listed ISO week" do
      week10 = froms(~o"2022-01-01", [week: [10]], :year)
      assert Enum.count(week10) == 7
      assert hd(week10) == ~o"2022-03-07"
    end

    test "LIMIT keeps a candidate inside the listed week" do
      assert froms(~o"2022-03-08", [week: [10]], :day) == [~o"2022-03-08"]
    end

    test "LIMIT drops a candidate outside the listed week" do
      assert froms(~o"2022-03-08", [week: [1]], :day) == []
    end
  end

  describe "nearest weekday (W) as a LIMIT" do
    test "keeps a candidate that is a nearest-weekday for its month" do
      assert froms(~o"2022-06-15", [nearest_weekday: [15]], :day) == [~o"2022-06-15"]
    end
  end
end
