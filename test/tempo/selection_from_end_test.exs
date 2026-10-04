defmodule Tempo.SelectionFromEndTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  # A count from the end in a selection (`L…N`) is counted in the period the
  # selection resolves in: the days of its month, the months of its year, the
  # hours of a day. Each was read as written, where a negative number matches
  # no day, month or hour, and a range to the end (`{1..-1}`) as the empty
  # range Elixir takes it for, so the selection selected nothing.

  # The start of each span a value converts to, as ISO 8601 text.
  defp starts(text, calendar \\ Calendrical.Gregorian) do
    {:ok, value} = Tempo.from_iso8601(text, calendar)
    {:ok, %IntervalSet{} = spans} = Tempo.to_interval(value)

    spans |> IntervalSet.members() |> Enum.map(&(&1 |> Interval.from() |> Tempo.to_iso8601!()))
  end

  defp rrule_starts(rrule) do
    {:ok, recurrence} = RRule.parse(rrule, from: ~o"2026-01-01")
    {:ok, %IntervalSet{} = spans} = Tempo.to_interval(recurrence)

    spans |> IntervalSet.members() |> Enum.map(&(&1 |> Interval.from() |> Tempo.to_iso8601!()))
  end

  describe "a range that reaches the end of its period" do
    test "of days is the days to the month's last" do
      assert starts("2026Y6ML{28..-1}DN") == ~w(2026Y6M28D 2026Y6M29D 2026Y6M30D)
      assert starts("2026Y6ML{1..-1}DN") == starts("2026Y6ML{1..30}DN")
      assert length(starts("2026Y6ML{1..-1}DN")) == 30
    end

    test "keeps its step" do
      assert starts("2026Y6ML{1..-1//7}DN") ==
               ~w(2026Y6M1D 2026Y6M8D 2026Y6M15D 2026Y6M22D 2026Y6M29D)
    end

    test "of months, weeks and days of the year" do
      assert starts("2026YL{11..-1}MN") == ~w(2026Y11M 2026Y12M)
      assert starts("2026YL{52..-1}WN") == ~w(2026Y52W 2026Y53W)
      assert starts("2026YL{364..-1}ON") == ~w(2026Y12M30D 2026Y12M31D)
    end

    test "of weekdays is the weekdays to the week's last" do
      assert starts("2026Y6ML{6..-1}KN") == starts("2026Y6ML{6,7}KN")
      assert length(starts("2026Y6ML{6..-1}KN")) == 8
    end

    test "of hours is the hours to the day's last" do
      assert starts("2026Y6M15DLT{22..-1}HN") == ~w(2026Y6M15DT22H 2026Y6M15DT23H)
    end

    test "of positions is the occurrences to the last" do
      workdays = starts("2026Y6ML{1..5}KN")

      assert starts("2026Y6ML{1..5}K{2..-1}IN") == tl(workdays)
      assert starts("2026Y6ML{1..5}K{1..-1}IN") == workdays
    end

    test "far longer than its period costs no more than the period" do
      assert length(starts("2026Y6ML{1..999999999}DN")) == 30
    end
  end

  describe "a unit counted from the end" do
    test "a month is counted in the year" do
      assert starts("2026YL-1MN") == ~w(2026Y12M)
      assert starts("2026YL{-2,-1}MN") == ~w(2026Y11M 2026Y12M)
      assert starts("2026YL-1M-1DN") == ~w(2026Y12M31D)
      assert starts("2026YL-1M{30..-1}DN") == ~w(2026Y12M30D 2026Y12M31D)
    end

    test "a month is counted in a year of thirteen" do
      assert starts("5787YL-1MN", Calendrical.Hebrew) == ["5787Y13M[u-ca=hebrew]"]
      assert starts("5788YL-1MN", Calendrical.Hebrew) == ["5788Y12M[u-ca=hebrew]"]
    end

    test "a weekday is counted in the week" do
      assert starts("2026Y6ML-1KN") == ~w(2026Y6M7D 2026Y6M14D 2026Y6M21D 2026Y6M28D)
      assert starts("2026Y6ML-1K-1IN") == ~w(2026Y6M28D)
      assert starts("2026YL-1W-1KN") == starts("2026YL53W7KN")
    end

    test "a weekday is counted in a week calendar's week" do
      assert starts("2026Y25WL-1KN", Calendrical.ISOWeek) == ["2026Y25W7K[u-ca=iso-week]"]
    end

    test "an hour, a minute and a second are counted in the day, the hour and the minute" do
      assert starts("2026Y6M15DLT-1HN") == ~w(2026Y6M15DT23H)
      assert starts("2026Y6M15DT10HLT-1MN") == ~w(2026Y6M15DT10H59M)
      assert starts("2026Y6M15DT10H30MLT-1SN") == ~w(2026Y6M15DT10H30M59S)
    end

    test "at the start of a window" do
      # The Monday in the seven days before 31 December.
      assert starts("2026YLL-1M-1D/-P7DN1K1IN") == ~w(2026Y12M28D)
    end
  end

  describe "a count from the end in a recurrence's rule" do
    test "expands each period" do
      assert starts("R4/2026-01-01/P1Y/FL-1M-1DN") ==
               ~w(2026Y12M31D 2027Y12M31D 2028Y12M31D 2029Y12M31D)

      assert starts("R2/2026-06-22/P1W/FL-1KN") == ~w(2026Y6M28D 2026Y7M5D)
      assert starts("R2/2026-06-15/P1D/FLT-1HN") == ~w(2026Y6M15DT23H 2026Y6M16DT23H)
    end

    test "limits the periods of a finer cadence" do
      assert starts("R3/2026-06-25/P1D/FL{30..-1}DN") == ~w(2026Y6M30D 2026Y7M30D 2026Y7M31D)
      assert starts("R2/2026-06-01/P1M/FL-1MN") == ~w(2026Y12M1D 2027Y12M1D)
      assert starts("R2/2026-06-25/P1D/FL-1KN") == ~w(2026Y6M28D 2026Y7M5D)

      assert starts("R2/2026-06-15T00/PT1H/FLT-1HN") == ~w(2026Y6M15DT23H 2026Y6M16DT23H)
    end

    test "in a unit after the selection" do
      assert starts("R2/2026-01-01/P1Y/FL6MN-1D") == ~w(2026Y6M30D 2027Y6M30D)
      assert starts("R2/2026-06-01/P1M/FL1K1INT-1H") == ~w(2026Y6M1DT23H 2026Y7M6DT23H)
    end

    test "a month as it is written is still found where the start has no year" do
      assert starts("R2/6M/P1M/FL{6,8}MN") == ~w(6M 8M)
    end
  end

  describe "the values a selection names" do
    test "are taken in the order of time" do
      assert starts("2026Y6ML{-1,1}D1IN") == ~w(2026Y6M1D)
      assert starts("R3/2026-06-01/P1M/FL{-1,1}DN") == ~w(2026Y6M1D 2026Y6M30D 2026Y7M1D)
    end

    test "are taken once each" do
      assert starts("2026Y6ML{30,-1}DN") == ~w(2026Y6M30D)
    end

    test "in an RRULE whose lists are in any order" do
      assert rrule_starts("FREQ=MONTHLY;BYMONTHDAY=15,1;COUNT=3") ==
               ~w(2026Y1M1D 2026Y1M15D 2026Y2M1D)

      assert rrule_starts("FREQ=DAILY;BYHOUR=17,9;BYSETPOS=1;COUNT=2") ==
               ~w(2026Y1M1DT9H 2026Y1M2DT9H)

      assert rrule_starts("FREQ=MONTHLY;BYDAY=-1FR,1MO;BYSETPOS=1;COUNT=2") ==
               ~w(2026Y1M5D 2026Y2M2D)
    end

    test "pass over a value the period lacks" do
      assert starts("2026Y6M15DLT25HN") == []
      assert starts("R2/2026-06-15/P1D/FLT{9,25}HN") == ~w(2026Y6M15DT9H 2026Y6M16DT9H)
    end
  end

  describe "a unit after a selection, in a value" do
    test "is counted from the end of the date the selection picks" do
      assert starts("2026YL6MN-1D") == ~w(2026Y6M30D)
      assert starts("2026YL{1,2}MN-1D") == ~w(2026Y1M31D 2026Y2M28D)
    end

    test "passes over a date it does not make" do
      assert starts("2026YL{1,2}MN30D") == ~w(2026Y1M30D)
      assert starts("2026YL6MN31D") == []
    end
  end
end
