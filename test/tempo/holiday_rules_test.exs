defmodule Tempo.HolidayRulesTest do
  use ExUnit.Case, async: true

  # Rules a holiday is written in, from the `tempo_holidays` work: a day
  # observed on a weekday next to it, where that weekday lies in another
  # year than the day, and a rule whose start is a year where its
  # selection names a day. The measure is `Date`, and Calendrical's own
  # conversion for a rule of another calendar.

  import Tempo.Sigils

  alias Tempo.{Interval, IntervalSet}

  defp dates(rule, window) do
    {:ok, set} = Tempo.to_interval(Tempo.from_iso8601!(rule), within: window)

    for interval <- IntervalSet.members(set) do
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      Date.convert!(date, Calendar.ISO)
    end
  end

  # The weekday before a date, or after it, by `Date`.
  defp friday_before(date),
    do:
      Enum.find(1..7, &(Date.day_of_week(Date.add(date, -&1)) == 5)) |> then(&Date.add(date, -&1))

  defp monday_after(date),
    do: Enum.find(1..7, &(Date.day_of_week(Date.add(date, &1)) == 1)) |> then(&Date.add(date, &1))

  describe "a day observed on a weekday next to it" do
    test "lands in the year before, where the weekday is" do
      # 1 January 2022 is a Saturday; the Friday before is 31 December 2021.
      rule = "R/../P1Y/FLLL1M1D6KN/-P7DN5K1IN"
      assert Date.day_of_week(~D[2022-01-01]) == 6

      assert dates(rule, ~o"2021Y") == [friday_before(~D[2022-01-01])]
      assert dates(rule, ~o"2022Y") == []
    end

    test "lands in the year after, where the weekday is" do
      # 31 December 2022 is a Saturday; the Monday after is 2 January 2023.
      rule = "R/../P1Y/FLLL12M31D6KN/P8DN1K-1IN"
      assert Date.day_of_week(~D[2022-12-31]) == 6

      assert dates(rule, ~o"2022Y") == []
      assert dates(rule, ~o"2023Y") == [monday_after(~D[2022-12-31])]
      assert dates(rule, ~o"2021Y/2023Y") == [monday_after(~D[2022-12-31])]
    end

    test "of another calendar lands in the Gregorian year after" do
      # 10 Dhu al-Hijjah 1427 is a Sunday, 31 December 2006; the Monday
      # after is 1 January 2007. The calendar's weeks begin on Sunday, so
      # Sunday is its day 1 and Monday its day 2 (decision 80).
      eid = Date.convert!(Date.new!(1427, 12, 10, Calendrical.Islamic.UmmAlQura), Calendar.ISO)
      assert eid == ~D[2006-12-31] and Date.day_of_week(eid) == 7

      rule = "R/../P1Y/FLLL12M10D1KN/P8DN2K-1IN[u-ca=islamic-umalqura]"
      assert dates(rule, ~o"2006Y") == []
      assert dates(rule, ~o"2007Y") == [monday_after(eid)]
    end
  end

  describe "a rule whose start is a year" do
    test "selects the day it names in each year it steps to" do
      assert dates("R/2020Y/P4Y/FL11M3DN", ~o"2019Y/2028Y") ==
               [~D[2020-11-03], ~D[2024-11-03], ~D[2028-11-03]]
    end

    test "counts from the year" do
      {:ok, set} = Tempo.to_interval(~o"R3/2020Y/P1Y/FL6M15DN")

      assert IntervalSet.map(set, &Interval.from/1) ==
               [~o"2020Y6M15D", ~o"2021Y6M15D", ~o"2022Y6M15D"]
    end
  end
end
