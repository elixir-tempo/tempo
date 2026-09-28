defmodule Tempo.ExplainCoverageTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Explain

  describe "anchored headlines at each precision" do
    test "year" do
      assert Tempo.explain(~o"2020Y") =~ "The year 2020."
    end

    test "month" do
      assert Tempo.explain(~o"2020Y6M") =~ "June 2020."
    end

    test "day" do
      assert Tempo.explain(~o"2020Y6M15D") =~ "June 15, 2020."
    end
  end

  describe "masked years" do
    test "a decade mask names the decade" do
      assert Tempo.explain(~o"201X") =~ "the 2010s"
    end

    test "a century mask names the century" do
      assert Tempo.explain(~o"20XX") =~ "the 2000s (century)"
    end

    test "an all-digits mask spans every 4-digit year" do
      assert Tempo.explain(~o"XXXX") =~ "all 4-digit years"
    end

    test "a masked non-year component is described" do
      assert Tempo.explain(Tempo.from_iso8601!("2020Y0XM")) =~
               "A Tempo with a masked month component."
    end
  end

  describe "intervals and sets" do
    test "a closed interval is described by its endpoints" do
      prose = Tempo.explain(~o"2020Y/2021Y")
      assert prose =~ "A closed interval."
      assert prose =~ "From: 2020-01-01."
    end

    test "a set reports how many disjoint intervals it materialises to" do
      assert Tempo.explain(~o"{2020,2021,2022,2023}Y") =~ "Converts to 4 disjoint intervals."
    end

    test "an open-lower interval" do
      assert Tempo.explain(Tempo.from_iso8601!("../2020Y")) =~ "An open-lower interval"
    end

    test "a recurrence" do
      prose = Tempo.explain(Tempo.from_iso8601!("R3/2020-01-01/P1D"))
      assert prose =~ "A recurrence of 3 occurrences."
      assert prose =~ "Cadence: 1 day."
    end
  end

  describe "qualifications and alternate calendars" do
    test "an approximate qualifier" do
      assert Tempo.explain(~o"2020~Y") =~ "%{year: :approximate}"
    end

    test "an uncertain-and-approximate qualifier" do
      assert Tempo.explain(~o"2020%Y") =~ "%{year: :uncertain_and_approximate}"
    end

    test "a non-ISO calendar is named" do
      assert Tempo.explain(Tempo.from_iso8601!("2020-06-15[u-ca=coptic]")) =~
               "Calendar: Calendrical.Coptic."
    end

    test "an explicit Calendar.ISO value still explains" do
      assert Tempo.explain(Tempo.from_iso8601!("2020-06-15", Calendar.ISO)) =~ "June 15, 2020."
    end

    test "expression-level qualifications name the EDTF symbol" do
      assert Tempo.explain(Tempo.from_iso8601!("2020Y?")) =~ "uncertain (EDTF ?)"
      assert Tempo.explain(Tempo.from_iso8601!("2020Y~")) =~ "approximate (EDTF ~)"

      assert Tempo.explain(Tempo.from_iso8601!("2020Y%")) =~
               "both uncertain and approximate (EDTF %)"
    end

    test "a millennium mask is named" do
      assert Tempo.explain(Tempo.from_iso8601!("2XXX")) =~ "millennium"
    end
  end

  describe "all-of sets and metadata" do
    test "an all-of set lists its members" do
      set = %Tempo.Set{type: :all, set: [~o"2020Y", ~o"2021Y"]}
      prose = Tempo.explain(set)
      assert prose =~ "An all-of set"
      assert prose =~ "2 member(s)"
    end

    test "an interval with non-summary metadata reports a key count" do
      iv = %Tempo.Interval{from: ~o"2020Y", to: ~o"2021Y", metadata: %{foo: 1, bar: 2}}
      assert Tempo.explain(iv) =~ "Metadata: 2 key(s)."
    end

    test "set-level producer metadata is surfaced" do
      set = %Tempo.IntervalSet{intervals: [], metadata: %{prodid: "-//A//EN"}}
      assert Tempo.explain(set) =~ "Producer: -//A//EN."
    end

    test "generic set metadata reports a key count" do
      set = %Tempo.IntervalSet{intervals: [], metadata: %{foo: 1, bar: 2}}
      assert Tempo.explain(set) =~ "Set-level metadata: 2 key(s)."
    end
  end

  describe "ANSI formatter colours each part type" do
    defp ansi(value), do: value |> Explain.explain() |> Explain.to_ansi()

    test "qualification, extended, calendar, metadata and member parts all render" do
      assert ansi(~o"2020?Y") =~ "2020"
      assert ansi(Tempo.from_iso8601!("2020-06-15T10:00[Europe/Paris]")) =~ "Europe/Paris"
      assert ansi(Tempo.from_iso8601!("2020-06-15[u-ca=coptic]")) =~ "Coptic"
      assert ansi(%Tempo.Set{type: :all, set: [~o"2020Y", ~o"2021Y"]}) =~ "member"

      iv = %Tempo.Interval{from: ~o"2020Y", to: ~o"2021Y", metadata: %{summary: "Trip"}}
      assert ansi(iv) =~ "Trip"
    end
  end
end
