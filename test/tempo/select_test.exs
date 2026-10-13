defmodule Tempo.SelectTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  # Selection (`plans/architecture-redesign.md`, section 7.4 and section 18):
  # one engine for selectors, selections written in a value, repeat rules,
  # domains, exclusions and workdays.

  defp days(result), do: result |> ok() |> IntervalSet.map(&Tempo.day/1)
  defp texts(result), do: result |> ok() |> IntervalSet.map(&Tempo.to_iso8601!/1)
  defp ok({:ok, value}), do: value

  describe "select/3" do
    test "selects by the parts a value with no year names" do
      assert days(Tempo.select(~o"2026-02", [1, 15])) == [1, 15]
      assert days(Tempo.select(~o"2026-06", ~o"5K")) == [5, 12, 19, 26]
      assert texts(Tempo.select(~o"2026", ~o"12M25D")) == ["2026Y12M25D"]
      assert texts(Tempo.select(~o"2026", ~o"10O")) == ["2026Y10O"]

      assert texts(Tempo.select(~o"2026/2028", ~o"12M25D")) == [
               "2026Y12M25D",
               "2027Y12M25D",
               "2028Y12M25D"
             ]
    end

    test "selects a time of day through the zone, and nothing where the clock skips" do
      assert texts(Tempo.select(~o"2026-06-15T09:00Z/2026-06-15T17:00Z", ~o"T10:30")) == [
               "2026Y6M15DT10H30MZ"
             ]

      assert texts(Tempo.select(~o"2024-03-10[America/New_York]", ~o"T02")) == []

      assert texts(Tempo.select(~o"2024-03-10[America/New_York]", ~o"T02/T04")) == [
               "2024Y3M10DT2H/T4H[America/New_York]"
             ]
    end

    test "selects by a selection, a recurrence, a list of selectors and a function" do
      assert texts(Tempo.select(~o"2026", ~o"L1K1IN")) == ["2026Y1M5D"]
      assert texts(Tempo.select(~o"P1M/2026-07-01", ~o"L5K-1IN")) == ["2026Y6M26D"]
      assert days(Tempo.select(~o"2026-06", ~o"R/2026-01-01/P1D/FL1KN")) == [1, 8, 15, 22, 29]
      assert days(Tempo.select(~o"2026-06", [~o"1D", ~o"5K"])) == [1, 5, 12, 19, 26]
      assert days(Tempo.select(~o"2026-06", fn _period -> 1..3 end)) == [1, 2, 3]
      assert {:error, %ArgumentError{}} = Tempo.select(~o"2026-06", fn _period -> :every_day end)
      assert {:error, %ArgumentError{}} = Tempo.select(~o"2026-06", ~o"2026-06-15")
    end

    test "a list answers in the order of time, each span once" do
      assert days(Tempo.select(~o"2026-06", [~o"20D", ~o"5D", ~o"5D"])) == [5, 20]
      assert days(Tempo.select(~o"2026-06", [20, 5, 5, 4..6])) == [4, 5, 6, 20]

      assert texts(Tempo.select(~o"2026-06/2026-07", [~o"20D", ~o"5D"])) ==
               ["2026Y6M5D", "2026Y6M20D", "2026Y7M5D", "2026Y7M20D"]
    end

    test "keeps the period's metadata on each value" do
      term = Tempo.put_metadata(~o"2027-07-19/2027-07-21", %{term: 3})
      {:ok, days} = Tempo.select(term, Tempo.workdays(:AU))
      assert IntervalSet.map(days, &Tempo.metadata/1) == [%{term: 3}, %{term: 3}, %{term: 3}]
    end
  end

  describe "a base with no end" do
    test "is selected as it is walked" do
      {:ok, workdays} = Tempo.select(~o"2026-06-15/..", Tempo.workdays(:US))
      assert Enum.at(workdays, 5) == ~o"2026-06-22"
      assert IntervalSet.first(workdays) == ~o"2026-06-15"

      assert workdays |> IntervalSet.walk() |> Enum.take(2) |> Enum.map(&Tempo.to_iso8601!/1) == [
               "2026Y6M15D/2026Y6M15D",
               "2026Y6M16D/2026Y6M16D"
             ]

      assert {:error, %Tempo.Iso8601EncodeError{reason: :lazy_set}} = Tempo.to_iso8601(workdays)
    end

    test "is busy time a shift skips, read only as far as the shift reaches" do
      {:ok, weekends} = Tempo.select(~o"2026-06-18/..", Tempo.weekends(:US))

      assert Tempo.shift(~o"2026-06-18T16:00", ~o"P3D", skipping: weekends) ==
               {:ok, ~o"2026-06-23T16:00"}

      assert Tempo.shift(~o"2026-06-18", ~o"P3D", skipping: weekends) == {:ok, ~o"2026-06-23"}

      assert {:error, %Tempo.ConversionError{reason: :unbounded}} =
               Tempo.shift(~o"2026-06-18", ~o"-P3D", skipping: weekends)
    end
  end

  describe "a selection written in a value" do
    test "names the values it picks, with the units after it on each" do
      assert texts(Tempo.to_interval(~o"2026Y6ML1K1IN")) == ["2026Y6M1D/2026Y6M1D"]

      assert Enum.map(ok(Tempo.members(~o"2026Y6ML1KNT10H")), &Tempo.to_iso8601!/1) ==
               [
                 "2026Y6M1DT10H",
                 "2026Y6M8DT10H",
                 "2026Y6M15DT10H",
                 "2026Y6M22DT10H",
                 "2026Y6M29DT10H"
               ]

      assert Enum.count(~o"2026Y6ML1KN") == 5
      assert texts(Tempo.to_interval(~o"2026YL-1M-1DN")) == ["2026Y12M31D/2026Y12M31D"]
      assert texts(Tempo.to_interval(~o"2026Y6M15DLT-1HN")) == ["2026Y6M15DT23H/16DT0H"]
      assert texts(Tempo.to_interval(~o"2026Y6ML-1K1IN")) == ["2026Y6M7D/2026Y6M7D"]
    end

    test "with no year is placed by the window" do
      assert texts(Tempo.to_interval(~o"L12M25DN", within: ~o"2026/2027")) == [
               "2026Y12M25D/2026Y12M25D",
               "2027Y12M25D/2027Y12M25D"
             ]

      assert {:error, %Tempo.ConversionError{reason: :needs_a_year}} =
               Tempo.to_interval(~o"L12M25DN")
    end

    test "nests, with a window" do
      assert texts(Tempo.to_interval(~o"2026Y6MLL3K4IN/P5DN")) == ["2026Y6M24D/28D"]
      assert texts(Tempo.to_interval(~o"2026YL(easter)eN")) == ["2026Y4M5D/2026Y4M5D"]
    end
  end

  describe "a repeat rule" do
    test "selects within each repeating interval, counting the occurrences selected" do
      assert texts(Tempo.to_interval(~o"R3/2026-01-01/P1Y/FL12M25DN")) ==
               ["2026Y12M25D/2026Y12M25D", "2027Y12M25D/2027Y12M25D", "2028Y12M25D/2028Y12M25D"]

      assert texts(Tempo.to_interval(~o"R3/2026-01-01/P1M/FL5K-1IN")) ==
               ["2026Y1M30D/2026Y1M30D", "2026Y2M27D/2026Y2M27D", "2026Y3M27D/2026Y3M27D"]

      assert texts(Tempo.to_interval(~o"R/2026-01-01/P1Y/FL12M25DN", within: ~o"2026/2027")) ==
               ["2026Y12M25D/2026Y12M25D", "2027Y12M25D/2027Y12M25D"]
    end

    test "inherits the start's finer units" do
      assert texts(Tempo.to_interval(~o"R2/2026-01-01T10:00/P1Y/FL12M25DN")) ==
               ["2026Y12M25DT10H0M/T1M", "2027Y12M25DT10H0M/T1M"]
    end

    test "over a domain selects in each member, filtered" do
      assert texts(Tempo.to_interval(~o"R/{2020Y..2024Y}/P1Y/FL12M25DN")) |> length() == 5

      assert texts(Tempo.to_interval(~o"R/{2020Y..2024Y}e/P1Y/FL12M25DN")) == [
               "2020Y12M25D/2020Y12M25D",
               "2022Y12M25D/2022Y12M25D",
               "2024Y12M25D/2024Y12M25D"
             ]

      assert texts(Tempo.to_interval(~o"R/{2020Y..2024Y}l/P1Y/FL12M25DN")) == [
               "2020Y12M25D/2020Y12M25D",
               "2024Y12M25D/2024Y12M25D"
             ]
    end
  end

  describe "an exclusion" do
    test "removes a member from a set" do
      assert texts(Tempo.to_interval(~o"{2020Y..2024Y,^2022Y}")) == [
               "2020Y/2020Y",
               "2021Y/2021Y",
               "2023Y/2023Y",
               "2024Y/2024Y"
             ]
    end
  end

  describe "workdays" do
    test "step over the weekend and the days off" do
      {:ok, holidays} = Tempo.workdays(:US, except: ~o"{2026-07-03}")
      assert Tempo.next_workday(~o"2026-07-02", holidays) == {:ok, ~o"2026-07-06"}
      assert Tempo.add_workdays(~o"2026-07-01", 2, holidays) == {:ok, ~o"2026-07-06"}
      assert Tempo.workday?(~o"2026-07-03", holidays) == false
      assert Tempo.count_workdays(~o"2026-07", holidays) == {:ok, 22}
    end

    test "take a territory's weekend from CLDR" do
      assert Tempo.weekend?(~o"2026-06-12", :SA)
      refute Tempo.weekend?(~o"2026-06-14", :SA)

      assert days(Tempo.select(~o"2026-06-15/2026-06-21", Tempo.workdays(:SA))) == [
               15,
               16,
               17,
               18,
               21
             ]
    end
  end

  describe "numbered weeks" do
    test "a week of a year is selected from the year that numbers it" do
      assert Tempo.select(~o"2026", ~o"1W") == {:ok, ~o"{2026Y1W}"}
      assert Tempo.select(~o"2026", ~o"53W") == {:ok, ~o"{2026Y53W}"}
      assert Tempo.select(~o"2026", ~o"-1W") == {:ok, ~o"{2026Y53W}"}
      assert Tempo.select(~o"2026/2027", ~o"1W") == {:ok, ~o"{2026Y1W,2027Y1W}"}
    end

    test "a week that runs out of a period which is not its whole year is not selected" do
      assert Tempo.select(~o"2026-06/2026-12", ~o"53W") == {:ok, ~o"{}"}
      assert Tempo.select(~o"2026-06/2026-12", ~o"30W") == {:ok, ~o"{2026Y30W}"}
    end

    test "the weeks asked of a month are the weeks the calendar numbers in it" do
      assert Tempo.select(~o"2026-06", ~o"1W") == {:ok, ~o"{2026Y6M1W}"}
      assert Tempo.select(~o"2026-06", ~o"-1W") == {:ok, ~o"{2026Y6M4W}"}
      assert Tempo.select(~o"2026-06", ~o"5W") == {:ok, ~o"{}"}

      {:ok, first_of_july} = Tempo.select(~o"2026-07", ~o"1W")

      assert Enum.map(IntervalSet.first(first_of_july), &Tempo.day/1) == [
               29,
               30,
               1,
               2,
               3,
               4,
               5
             ]
    end
  end

  describe "windows and domains of a rule" do
    defp starts(text, options) do
      {:ok, set} = Tempo.to_interval(Tempo.from_iso8601!(text), options)
      IntervalSet.map(set, &Tempo.to_iso8601!(Interval.from(&1)))
    end

    test "a nested selection is made where the parts before it say" do
      assert starts("R/../P1Y/FL11MLL1K1IN/P9DN2K1IN", within: ~o"2026") == ["2026Y11M3D"]
      assert Tempo.select(~o"2026", ~o"L11MLL1K1IN/P9DN2K1IN") == {:ok, ~o"{2026Y11M3D}"}
    end

    test "a window of a negative length runs back from its date" do
      assert starts("R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN", within: ~o"2026") == ["2026Y4M3D"]
      assert Tempo.to_interval(~o"2026YLL(easter)eN/-P7DN") == {:ok, ~o"{2026Y3M29D/4M4D}"}
    end

    test "a window carries what it selects out of its period, into the window asked for" do
      observed = "R/../P1Y/FLLL1M1D6KN/-P7DN5K1IN"
      assert starts(observed, within: ~o"2021") == ["2021Y12M31D"]
      assert starts(observed, within: ~o"2022") == []
    end

    test "a traditional month is selected as its year numbers it" do
      assert Tempo.select(~o"4662[u-ca=chinese]", ~o"8m15D") ==
               {:ok, ~o"{4662Y8m15D}[u-ca=chinese]"}

      assert Enum.count(Enum.take(~o"R/4662Y1M1D/P1Y/FL8m15DN[u-ca=chinese]", 2)) == 2
    end

    test "a domain of exclusions alone takes its periods from the window" do
      assert starts("R/^2022Y/P1Y/FL12M25DN", within: ~o"2020/2023") ==
               ["2020Y12M25D", "2021Y12M25D", "2023Y12M25D"]
    end

    test "a cadence of several units steps through a domain from its start" do
      assert starts("R/{1848Y..}/P4Y/FL11MLL1K1IN/P9DN2K1IN", within: ~o"2019/2028") ==
               ["2020Y11M3D", "2024Y11M5D", "2028Y11M7D"]

      assert starts("R/{2020Y..2026Y}/P2Y/FL1M1DN", []) ==
               ["2020Y1M1D", "2022Y1M1D", "2024Y1M1D", "2026Y1M1D"]

      assert starts("R/{2000Y..}e/P1Y/FL11MLL1K1IN/P7DN2K-1IN", within: ~o"2025/2030") ==
               ["2026Y11M3D", "2028Y11M7D", "2030Y11M5D"]
    end

    test "a solar term is found in a Gregorian rule, and a rule of another calendar in a Gregorian window" do
      assert starts("R/../P1Y/FL(qingming)eN", within: ~o"2026") == ["2026Y4M5D"]

      {:ok, new_year} =
        Tempo.to_interval(~o"R/../P1Y/FL1M1DN[u-ca=islamic-umalqura]", within: ~o"2026")

      assert IntervalSet.map(new_year, &Tempo.to_calendar!(&1, Calendrical.Gregorian)) == [
               ~o"2026-06-16/2026-06-16[u-ca=gregorian]"
             ]
    end

    test "a recurrence over a domain has no RRULE" do
      assert {:error, %Tempo.ConversionError{reason: {:no_rrule, :domain}}} =
               RRule.to_string(~o"R/{2025Y..2027Y}/P1Y/FL12M25DN")
    end

    test "a week of a selection begins on Monday" do
      assert {:ok, _} = Tempo.from_iso8601("R/2026-01-01/P1W/FL2K1qN")

      assert {:error, %Tempo.InvalidDateError{unit: :week_start}} =
               Tempo.from_iso8601("R/2026-01-01/P1W/FL2K7qN")
    end

    test "an event no resolver knows is no value" do
      assert {:error, %Tempo.InvalidDateError{unit: :event, reason: {:unknown_event, "nonsense"}}} =
               Tempo.from_iso8601("R/../P1Y/FL(nonsense)eN")

      assert {:ok, _} = Tempo.from_iso8601("R/../P1Y/FL(easter)eN")
    end
  end

  describe "a base with no end and no year" do
    test "needs a year, as a base with an end does" do
      for base <- [~o"6M/..", ~o"T10H/..", ~o"1K/.."] do
        assert {:error, %ConversionError{reason: :needs_a_year}} = Tempo.select(base, ~o"15D")

        assert {:error, %ConversionError{reason: :needs_a_year}} =
                 Tempo.select(base, Tempo.workdays!(:US))
      end
    end
  end
end
