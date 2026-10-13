defmodule Tempo.FormatTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Explain

  # Words, inspection and explanation (`plans/architecture-redesign.md`,
  # section 19). CLDR's thin and narrow spaces are made plain for reading.

  defp words(expression, options \\ []) do
    {:ok, text} = Tempo.to_string(expression, options)
    String.replace(text, [" ", " "], " ")
  end

  describe "to_string/2" do
    test "a date is the time it covers, shown at the unit below its own" do
      assert words(~o"2026") == "Jan – Dec 2026"
      assert words(~o"2026-06") == "Jun 1 – 30, 2026"
      assert words(~o"2026-W25") == "Jun 15 – 21, 2026"
      assert words(~o"2026-06-15") == "Jun 15, 2026"
      assert words(~o"20C") == "2000 – 2099"
      assert words(~o"2026", format: :long) == "January – December 2026"
    end

    test "a value written to a clock unit is its reading" do
      assert words(~o"2026-06-15T10:30") == "Jun 15, 2026, 10:30 AM"
      assert words(~o"2026-06-15T10:30:45.5") == "Jun 15, 2026, 10:30:45 AM"
      assert words(~o"T10:30") == "10:30 AM"
    end

    test "an interval runs through a date end and to a clock end" do
      assert words(~o"2026/2026-03") == "Jan – Mar 2026"
      assert words(~o"2026/2028") == "2026 – 2028"
      assert words(~o"2026-06-15T09/2026-06-15T17") == "Jun 15, 2026, 9 AM – 5 PM"

      assert words(~o"2026-06-15T10:00+02:00/2026-06-15T12:00+01:00") ==
               "Jun 15, 2026, 10:00 AM – 12:00 PM"

      assert words(~o"6M/9M") == "Jun – Sep"
    end

    test "several spans are a list, alternatives a choice, and a mask the stretch it covers" do
      assert words(~o"R3/2026-06-15/P1D") == "Jun 15, 2026, Jun 16, 2026, and Jun 17, 2026"
      assert words(~o"[2026-06-15,2026-07-04]") == "Jun 15, 2026 or Jul 4, 2026"
      assert words(~o"{2026,2028}Y6M15D") == "Jun 15, 2026 and Jun 15, 2028"
      assert words(~o"2026-06-1X") == "Jun 10 – 19, 2026"
      assert words(~o"2026YXM15D") =~ "Jan 15, 2026, Feb 15, 2026"
      assert words(~o"L12M25DN", within: ~o"2026/2027") == "Dec 25, 2026 and Dec 25, 2027"
    end

    test "a year before 1 has its era, another calendar its own names, a duration its units" do
      assert words(~o"-0044-03-15") == "Mar 15, 45 BC"
      assert words(~o"-0044/0014") == "45 BC – 14 AD"
      assert words(~o"5786Y6M[u-ca=hebrew]") == "1 – 29 Adar 5786"
      assert words(~o"P3DT2H", format: :short) == "3 days, 2 hr"
    end

    test "what has no words is an error" do
      assert {:error, %Tempo.ConversionError{reason: :open}} = Tempo.to_string(~o"2026-06-15/..")
      assert {:error, %Tempo.ConversionError{reason: :needs_a_year}} = Tempo.to_string(~o"X*M")
    end
  end

  describe "to_relative_string/2" do
    test "counts in the first unit the two differ in, or the unit asked" do
      now = ~o"2026-06-15T12:00:00Z"
      assert Tempo.to_relative_string(~o"2026-06-14T12:00:00Z", from: now) == {:ok, "yesterday"}
      assert Tempo.to_relative_string(~o"2026-06-15T15:00:00Z", from: now) == {:ok, "in 3 hours"}
      assert Tempo.to_relative_string(~o"2027", from: ~o"2026-07-01") == {:ok, "next year"}

      assert Tempo.to_relative_string(~o"2026-06-29", from: ~o"2026-06-15", unit: :week) ==
               {:ok, "in 2 weeks"}
    end
  end

  describe "inspect and interpolation" do
    test "an expression is shown as the sigil that reads it" do
      assert inspect(~o"2026-06-15") == ~s(~o"2026Y6M15D")
      assert inspect(~o"5786Y6M[u-ca=hebrew]") == ~s(~o"5786Y6M[u-ca=hebrew]")
      assert inspect(~o"P1D") == ~s(~o"P1D")
      assert "From #{~o"2026-06-15/.."}" == "From 2026Y6M15D/.."
    end
  end

  describe "explain/1" do
    test "says what an expression is, what it covers, its frame and its walk" do
      assert Explain.lines(~o"2026-06-15T10[Europe/Paris]") == [
               "A value written to the hour: Jun 15, 2026, 10 AM.",
               "It covers 2026Y6M15DT10H[Europe/Paris] to 2026Y6M15DT11H[Europe/Paris].",
               "It is in the zone Europe/Paris.",
               "Walking it gives its minutes."
             ]

      assert hd(Explain.lines(~o"R/2026-01-01/P1Y/FL12M25DN")) ==
               "A recurrence with no end, with a rule that selects within each repeat."

      assert "Its month is approximate." in Explain.lines(~o"2026Y6~M15D")

      assert Tempo.explain(~o"P1D") ==
               "A duration, a length of time with no place on the time line: 1 day."

      assert Tempo.explain(:nope) == ":nope is not a value Tempo knows."
    end
  end
end
