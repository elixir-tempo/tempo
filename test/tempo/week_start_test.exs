defmodule Tempo.WeekStartTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{Interval, RRule}

  # The day a week begins on is of the whole expression, written
  # `[u-fw=sun]`, BCP 47's first day of the week (`plans/decisions.md`, 14
  # and 24). It is what an RRULE's `WKST` reads to where it counts.

  defp dates(recurrence, window) do
    {:ok, members} = Tempo.members(recurrence, within: window)

    Enum.map(members, fn member ->
      {:ok, date} = Tempo.to_date(Interval.from(member))
      date |> Date.convert!(Calendar.ISO) |> Date.to_iso8601()
    end)
  end

  describe "the suffix" do
    test "is read and written at the end of the expression" do
      for text <- [
            "2026Y25W[u-fw=sun]",
            "2026Y6M15D/20D[u-fw=sat]",
            "R/1997Y8M5D/P2W/FL{2,7}KN[u-fw=sun]",
            "2026Y6M15DT10H[Europe/Paris][u-fw=sun]"
          ] do
        assert Tempo.to_iso8601(Tempo.from_iso8601!(text)) == {:ok, text}
      end
    end

    test "names Monday by saying nothing" do
      assert Tempo.from_iso8601("2026-W25[u-fw=mon]") == {:ok, ~o"2026-W25"}
      assert Tempo.week_start(~o"2026-W25") == 1
      assert Tempo.week_start(~o"2026-W25[u-fw=sun]") == 7
    end

    test "names a day, and is for the Gregorian calendar" do
      assert {:error, %Tempo.ParseError{} = no_day} = Tempo.from_iso8601("2026-W25[u-fw=xyz]")
      assert Exception.message(no_day) =~ "mon, tue, wed, thu, fri, sat and sun"

      assert {:error, %Tempo.ParseError{} = other} =
               Tempo.from_iso8601("5786-07-15[u-ca=hebrew][u-fw=sun]")

      assert Exception.message(other) =~ "Gregorian calendar only"
      assert Tempo.week_start(~o"5786-07-15[u-ca=hebrew]") == nil
    end

    test "is written once, after the whole expression" do
      assert {:error, _} = Tempo.from_iso8601("2026-W25[u-fw=sun]/2026-W26")
    end
  end

  describe "a week" do
    # Week 1 of 2026 where weeks begin on Sunday is 4 to 10 January, the
    # first with four days of the year in it; week 25 is 21 to 27 June.
    test "begins on the day named, and is numbered by ISO 8601's rule from it" do
      assert Enum.at(~o"2026-W01[u-fw=sun]", 0) == ~o"2026-01-04[u-fw=sun]"
      assert Enum.at(~o"2026-W25[u-fw=sun]", 0) == ~o"2026-06-21[u-fw=sun]"
      assert Enum.at(~o"2026-W25[u-fw=sun]", -1) == ~o"2026-06-27[u-fw=sun]"
      assert Enum.at(~o"2026-W25", 0) == ~o"2026-06-15"
    end

    test "has its days counted from the day it begins on" do
      assert Tempo.to_calendar(~o"2026-W25-1[u-fw=sun]", Calendar.ISO) == {:ok, ~o"2026-06-21"}
      assert Tempo.to_calendar(~o"2026-W25-7[u-fw=sun]", Calendar.ISO) == {:ok, ~o"2026-06-27"}
    end

    test "of a date is the week of the expression's weeks" do
      assert Tempo.week(~o"2026-06-20") == 25
      assert Tempo.week(~o"2026-06-20[u-fw=sun]") == 24
    end

    # A day of the week is counted from the day the week begins on,
    # whether a week is written or not (decision 80).
    test "counts a weekday on its own from the day it begins on" do
      assert Tempo.day_of_week(~o"2026-06-21[u-fw=sun]") == 1
      assert Tempo.day_of_week(~o"2026-06-22[u-fw=sun]") == 2
      assert Tempo.day_of_week(~o"2026-06-22[u-fw=sun]", :monday) == 1
    end
  end

  describe "Tempo.to_week_start/2" do
    test "is the same days in the weeks of another start, and back" do
      assert Tempo.to_week_start(~o"2026-06-21", 7) == {:ok, ~o"2026-06-21[u-fw=sun]"}
      assert Tempo.to_week_start(~o"2026-06-21[u-fw=sun]", 1) == {:ok, ~o"2026-06-21"}
      assert Tempo.to_week_start(~o"2026-06-21", 1) == {:ok, ~o"2026-06-21"}
    end

    test "is an error for a day that is none and a calendar with its own weeks" do
      assert {:error, %ArgumentError{}} = Tempo.to_week_start(~o"2026-06-21", 8)
      assert {:error, %ArgumentError{}} = Tempo.to_week_start(~o"5786-07-15[u-ca=hebrew]", 7)
    end
  end

  describe "two expressions of different week starts" do
    test "relate and combine by their days" do
      sunday_week = ~o"2026-W25[u-fw=sun]"
      assert Tempo.relation(sunday_week, ~o"2026-W25") == :overlapped_by
      assert Tempo.overlaps?(sunday_week, ~o"2026-06-21")
      # The two weeks share their Sunday, 21 June.
      {:ok, shared} = Tempo.intersection(sunday_week, ~o"2026-W25")
      assert Tempo.equal?(shared, ~o"2026-06-21")
      assert Tempo.week_start(shared) == 7
    end
  end

  describe "an RRULE's WKST" do
    # RFC 5545 section 3.8.5.3, "an example where the days generated makes
    # a difference because of WKST": with MO the days are 5, 10, 19 and 24
    # August 1997, and with SU 5, 17, 19 and 31.
    test "is the recurrence's week start where it changes the weeks counted" do
      {:ok, monday} =
        RRule.parse("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=MO", from: ~o"1997-08-05")

      {:ok, sunday} =
        RRule.parse("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=SU", from: ~o"1997-08-05")

      assert Tempo.week_start(monday) == 1
      assert Tempo.week_start(sunday) == 7

      window = ~o"1997-08/1997-09"
      assert dates(monday, window) == ~w(1997-08-05 1997-08-10 1997-08-19 1997-08-24)
      assert dates(sunday, window) == ~w(1997-08-05 1997-08-17 1997-08-19 1997-08-31)
    end

    test "is read and not kept where it changes nothing" do
      assert RRule.parse("FREQ=WEEKLY;BYDAY=TU,SU;WKST=SU") == {:ok, ~o"R/../P1W/FL{2,7}KN"}
    end

    test "is written back" do
      for text <- [
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,SU;WKST=SU",
            "FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO;WKST=SU"
          ] do
        {:ok, recurrence} = RRule.parse(text)
        assert RRule.to_string(recurrence) == {:ok, text}
      end
    end

    # Week 20 of 1998 is 11 to 17 May where weeks begin on Monday, and 17 to
    # 23 May where they begin on Sunday: its Monday is the 11th or the 18th.
    test "numbers the weeks of the year from its day" do
      {:ok, monday} = RRule.parse("FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO", from: ~o"1997-05-12")

      {:ok, sunday} =
        RRule.parse("FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO;WKST=SU", from: ~o"1997-05-12")

      assert dates(monday, ~o"1998") == ["1998-05-11"]
      assert dates(sunday, ~o"1998") == ["1998-05-18"]
      assert Tempo.to_iso8601!(sunday) == "R/1997Y5M12D/P1Y/FL20W2KN[u-fw=sun]"
    end

    test "is for the Gregorian calendar" do
      assert {:error, %ArgumentError{}} =
               RRule.parse("FREQ=WEEKLY;INTERVAL=2;BYDAY=TU;WKST=SU",
                 from: ~o"5786-07-15[u-ca=hebrew]"
               )
    end
  end
end
