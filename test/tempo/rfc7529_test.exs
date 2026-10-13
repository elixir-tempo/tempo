defmodule Tempo.Rfc7529Test do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{Interval, RRule}

  # RFC 7529: a rule counted in a calendar other than the Gregorian
  # (`RSCALE`), what is taken for a day or a month a year lacks (`SKIP`),
  # and a month number that names a leap month (`5L`). The examples are
  # those of the standard's section 4.3, each held to the Gregorian dates
  # its table lists (`standards/rfc/rfc7529.txt`; `plans/decisions.md`, 13
  # and 28).

  @examples [
    {"4.3.1 Chinese New Year", "RSCALE=CHINESE;FREQ=YEARLY", ~D[2013-02-10],
     ~w(20130210 20140131 20150219 20160208 20170128)},
    {"4.3.2 Ethiopic 13th month", "RSCALE=ETHIOPIC;FREQ=MONTHLY;BYMONTH=13", ~D[2013-09-06],
     ~w(20130906 20140906 20150906 20160906 20170906)},
    {"4.3.3 Hebrew anniversary starting in a leap month",
     "RSCALE=HEBREW;FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=8;SKIP=FORWARD", ~D[2014-02-08],
     ~w(20140208 20150227 20160217 20170306 20180223)},
    {"4.3.4 Gregorian leap day with SKIP", "RSCALE=GREGORIAN;FREQ=YEARLY;SKIP=FORWARD",
     ~D[2012-02-29], ~w(20120229 20130301 20140301 20150301 20160229 20170301)},
    {"4.3.4 Gregorian leap day with no RSCALE", "FREQ=YEARLY", ~D[2012-02-29],
     ~w(20120229 20160229)}
  ]

  defp gregorian(occurrence) do
    {:ok, date} = occurrence |> Interval.from() |> Tempo.to_date()
    date |> Date.convert!(Calendar.ISO) |> Date.to_iso8601(:basic)
  end

  describe "the standard's examples" do
    for {title, rule, start, listed} <- @examples do
      test "#{title}: #{rule}" do
        start = Tempo.from_elixir!(unquote(Macro.escape(start)))
        listed = unquote(listed)
        {:ok, recurrence} = RRule.parse(unquote(rule), from: start)

        assert recurrence |> Enum.take(length(listed)) |> Enum.map(&gregorian/1) == listed
      end
    end
  end

  describe "RSCALE" do
    test "is the calendar of the recurrence and of its occurrences" do
      {:ok, new_year} = RRule.parse("RSCALE=CHINESE;FREQ=YEARLY", from: ~o"2013-02-10")

      assert new_year == ~o"R/4650-01-01/P1Y/FL1m1DN[u-ca=chinese]"
      second = Interval.from(Enum.at(new_year, 1))
      assert Tempo.to_calendar(second, Calendar.ISO) == {:ok, ~o"2014-01-31"}
      assert Tempo.to_iso8601!(second) == "4651Y1m1D[u-ca=chinese]"
    end

    test "names a month as its calendar names it" do
      {:ok, adar} = RRule.parse("RSCALE=HEBREW;FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=8")
      assert adar == ~o"R/../P1Y/FL5+m8DN[u-ca=hebrew]"
    end

    test "is written back, with its months and its skip" do
      for text <- [
            "RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=1",
            "RSCALE=ETHIOPIC;FREQ=MONTHLY;BYMONTH=13",
            "RSCALE=HEBREW;FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=8;SKIP=FORWARD",
            "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD"
          ] do
        {:ok, recurrence} = RRule.parse(text)
        assert RRule.to_string(recurrence) == {:ok, text}
      end
    end

    test "is not written for the Gregorian calendar with no skip, nor for a rule that reads there as itself" do
      {:ok, plain} = RRule.parse("RSCALE=GREGORIAN;FREQ=YEARLY;BYMONTH=6;BYMONTHDAY=15")
      assert RRule.to_string(plain) == {:ok, "FREQ=YEARLY;BYMONTH=6;BYMONTHDAY=15"}

      {:ok, mondays} = RRule.parse("RSCALE=HEBREW;FREQ=WEEKLY;BYDAY=MO")
      assert RRule.to_string(mondays) == {:ok, "FREQ=WEEKLY;BYDAY=MO"}
    end

    test "names a calendar Tempo has" do
      assert {:error, %ArgumentError{message: message}} =
               RRule.parse("RSCALE=KLINGON;FREQ=YEARLY")

      assert message =~ "names no calendar"
    end
  end

  describe "SKIP" do
    test "is given with RSCALE, and is one of three" do
      assert {:error, %ArgumentError{message: without}} =
               RRule.parse("FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD")

      assert without =~ "given with RSCALE"

      assert {:error, %ArgumentError{}} =
               RRule.parse("RSCALE=GREGORIAN;FREQ=YEARLY;SKIP=SIDEWAYS")
    end

    test "OMIT is the rule with no skip" do
      assert RRule.parse("RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=31;SKIP=OMIT") ==
               RRule.parse("FREQ=MONTHLY;BYMONTHDAY=31")
    end

    test "a leap month is of a calendar that has one" do
      assert {:error, %ArgumentError{message: message}} = RRule.parse("FREQ=YEARLY;BYMONTH=5L")
      assert message =~ "RSCALE"
    end
  end

  describe "a skip in a selection" do
    defp days(recurrence, window) do
      {:ok, members} = Tempo.members(recurrence, within: window)
      Enum.map(members, &Tempo.to_iso8601!(Interval.from(&1)))
    end

    defp monthly(parts), do: Tempo.every!(~o"P1M", from: ~o"2026-01-01", select: parts)

    test "is read and written beside the day it moves, and built as it is read" do
      text = "R/2026Y1M1D/P1M/FL31D(backward)sT9HN"
      assert Tempo.to_iso8601(Tempo.from_iso8601!(text)) == {:ok, text}
      assert monthly(hour: 9, skip: :backward, day: 31) == Tempo.from_iso8601!(text)

      assert {:error, %ArgumentError{}} = Tempo.selection(day: 31, skip: :sideways)

      assert {:error, %Tempo.ParseError{}} =
               Tempo.from_iso8601("R/2026-01-01/P1M/FL31D(sideways)sN")
    end

    test "takes the last day of a month that lacks the day, or the first of the next" do
      window = ~o"2026-01/2026-04"

      assert days(monthly(day: 31, skip: :backward), window) ==
               ["2026Y1M31D", "2026Y2M28D", "2026Y3M31D", "2026Y4M30D"]

      assert days(monthly(day: 31, skip: :forward), window) ==
               ["2026Y1M31D", "2026Y3M1D", "2026Y3M31D"]

      assert days(monthly(day: 31), window) == ["2026Y1M31D", "2026Y3M31D"]
    end

    test "gives two days that move to one that day once, and keeps a time of day" do
      assert days(monthly(day: [30, 31], skip: :backward), ~o"2026-02") == ["2026Y2M28D"]

      assert days(monthly(day: 31, skip: :backward, hour: 9), ~o"2026-02") ==
               ["2026Y2M28DT9H"]
    end

    test "is said in words, and has no part for a rule that names no day of a month" do
      assert Tempo.explain(monthly(day: 31, skip: :forward)) =~
               "a day or a month the year lacks taken as the next there is"

      mondays =
        Tempo.every!(~o"P1W", from: ~o"2026-01-01", select: [day_of_week: 1, skip: :forward])

      assert days(mondays, ~o"2026-01-01/2026-01-14") == ["2026Y1M5D", "2026Y1M12D"]
    end
  end

  describe "a leap month" do
    # Adar I, the leap month of the Hebrew calendar, is the sixth month of
    # 5774 and is not in 5775. The eighth of it is 8 February 2014.
    test "is the month it is, where it is asked for its day" do
      assert Tempo.to_calendar(~o"5774Y5+m8D[u-ca=hebrew]", Calendar.ISO) == {:ok, ~o"2014-02-08"}
      assert Tempo.to_calendar(~o"5774Y5m8D[u-ca=hebrew]", Calendar.ISO) == {:ok, ~o"2014-01-09"}
    end
  end
end
