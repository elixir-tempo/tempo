defmodule Tempo.ExplainTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  # `Tempo.explain/1` says in prose what an expression is, what it covers,
  # the frame it is in and what walking it gives. Each line is held here for
  # each kind of expression.

  defp lines(expression), do: expression |> Tempo.explain() |> String.split("\n")
  defp first_line(expression), do: hd(lines(expression))

  describe "what it is" do
    test "a value, by how it is written" do
      assert first_line(~o"2026-06-15") == "A value written to the day: Jun 15, 2026."
      assert first_line(~o"T10:30") == "A value written to the minute: 10:30 AM."
      assert first_line(~o"1K") == "A value written to the day of week."

      assert first_line(~o"2026Y{1,3}M") =~ "A value that names several, written to the month"
      assert first_line(~o"156X") =~ "A value with unspecified digits"
      assert first_line(~o"2026Y6ML1K1IN") =~ "A selection: the values its rule picks"
    end

    test "an interval, by its ends" do
      assert first_line(~o"2026-06-15/2026-06-20") =~ "An interval"
      assert first_line(~o"../..") == "An interval open at both ends: all of time."
      assert first_line(~o"../2026") == "An interval with an open start."
      assert first_line(~o"2026/..") == "An interval with an open end."
    end

    test "a set, by what its members are" do
      assert first_line(~o"{2026-06-15,2026-06-17}") ==
               "A set of 2 members, all of which it names."

      assert first_line(~o"[2026-06-15,2026-06-17]") ==
               "A choice of 2 alternatives, one of which is meant."

      assert Tempo.explain(~o"{P1D,P2D}") ==
               "A set of 2 durations: lengths of time, with no place on the time line."
    end

    test "a duration, and what is no expression" do
      assert Tempo.explain(~o"PT1H30M") ==
               "A duration, a length of time with no place on the time line: 1 hour, 30 minutes."

      assert Tempo.explain(:nonsense) == ":nonsense is not a value Tempo knows."
    end
  end

  describe "a recurrence" do
    test "says how it ends" do
      assert first_line(~o"R3/2026-06-01/P1W") == "A recurrence of 3 occurrences."
      assert first_line(~o"R/2026-01-01/P1D/2026-03-01") == "A recurrence until 2026Y3M1D."
    end

    test "says what its rule selects, part by part" do
      for {text, words} <- [
            {"R/2026-01-01/P1M/FL1K2IN", "Monday, the 2nd of them"},
            {"R/2026-01-01/P1M/FL{1..5}K-1IN", "Monday to Friday, the last of them"},
            {"R/2026-01-01/P1M/FL1K{1,-1}IN", "Monday, the 1st and last of them"},
            {"R/2026-01-01/P1M/FL1K{11,22,23}IN", "Monday, the 11th, 22nd and 23rd of them"},
            {"R/2026-01-01/P1M/FL1K-2IN", "Monday, the 2nd from the last of them"},
            {"R/2026-01-01/P1Y/FL12M25DN", "month 12, day 25"},
            {"R/2026-01-01/P1M/FL-1DN", "the last day"},
            {"R/2026-01-01/P1M/FL-2DN", "the 2nd from the last day"},
            {"R/2026-01-01/P1Y/FL100ON", "day 100 of the year"},
            {"R/2026-01-01/P1D/FLT9H30MN", "hour 9, minute 30"},
            {"R/2026-01-01/P1Y/FL(easter)eN", "the day of easter"}
          ] do
        cadence = text |> String.split("/") |> Enum.at(2)
        repeat = %{"P1M" => "1 month", "P1Y" => "1 year", "P1D" => "1 day"}[cadence]

        assert {text, first_line(Tempo.from_iso8601!(text))} ==
                 {text,
                  "A recurrence with no end. In each repeat of #{repeat} it selects #{words}."}
      end
    end

    test "says a selection made first, and the window it opens" do
      assert first_line(~o"R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN") ==
               "A recurrence with no end. In each repeat of 1 year it selects " <>
                 "((the day of easter), a window of P-7D), Friday, the last of them."
    end

    test "with no start is placed by a window" do
      assert Enum.at(lines(~o"R/../P1Y/FL12M25DN"), 1) ==
               "It has no start of its own; a `:within` window places it."
    end
  end

  describe "what it covers" do
    test "one span, to its end or through it" do
      assert Enum.at(lines(~o"2026-06"), 1) == "It covers 2026Y6M through 2026Y6M."

      assert Enum.at(lines(~o"2026-06-15T10[Europe/Paris]"), 1) ==
               "It covers 2026Y6M15DT10H[Europe/Paris] to 2026Y6M15DT11H[Europe/Paris]."
    end

    test "several values, or one of them" do
      assert Enum.at(lines(~o"2026Y{1,3}M"), 1) == "It names 2 values, each a span of its own."
      assert Enum.at(lines(~o"156X"), 1) == "It is one of 10 values."
      assert Enum.at(lines(~o"{2026-06-15,2026-06-17}"), 1) == "It covers 2 spans."
    end

    test "a value with no year names a place in a cycle" do
      assert Enum.at(lines(~o"6M15D"), 1) =~ "names a place in every year"
      assert Enum.at(lines(~o"1K"), 1) =~ "names a place in every week"
      assert Enum.at(lines(~o"T10:30"), 1) =~ "names a place in every day"
    end

    test "an open end needs a window" do
      assert Enum.at(lines(~o"2026/.."), 1) ==
               "It has no end of its own; a `:within` window bounds it."

      assert lines(~o"../..") == [
               "An interval open at both ends: all of time.",
               "It is floating: a reading of a clock in no zone.",
               "It is written to the finest unit and has nothing finer to walk."
             ]
    end
  end

  describe "its frame and its qualifiers" do
    test "the calendar, when it is not Elixir's own" do
      assert "It is in the Calendrical.Hebrew calendar." in lines(~o"5786-03-15[u-ca=hebrew]")
      refute Enum.any?(lines(~o"2026-06-15"), &(&1 =~ "calendar"))
    end

    test "the zone, UTC, a shift, or none" do
      assert "It is in the zone Europe/Paris." in lines(~o"2026-06-15T10[Europe/Paris]")
      assert "It is in UTC (`Z`)." in lines(~o"2026-06-15T10Z")
      assert "It is at a fixed shift from UTC." in lines(~o"2026-06-15T10+02:00")
      assert "It is floating: a reading of a clock in no zone." in lines(~o"2026-06-15T10")
    end

    test "what is uncertain, approximate or both" do
      assert "Its year is uncertain." in lines(~o"2026?-06-15")
      assert "Its month is approximate." in lines(~o"2026Y6~M15D")
      assert "Its day is uncertain and approximate." in lines(~o"2026-06-15%")
    end
  end

  describe "what walking it gives" do
    test "the unit below, its members, or nothing finer" do
      assert List.last(lines(~o"2026")) == "Walking it gives its months."
      assert List.last(lines(~o"2026-06-15")) == "Walking it gives its hours."
      assert List.last(lines(~o"2026Y{1,3}M")) == "Walking it gives its members."

      assert List.last(lines(~o"2026-06-15T10:30:00.5")) ==
               "Walking it gives its fractions of a second."
    end
  end
end
