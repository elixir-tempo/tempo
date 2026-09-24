defmodule Tempo.ExclusionDomainTest do
  # The `^` exclusion-member syntax: in a set (`{2020Y..2030Y,^2026Y}`) and as a
  # recurrence domain in the interval slot (`R/{…}/P1Y`, `R/^2026Y/P1Y`).
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  defp years(%IntervalSet{} = set) do
    set
    |> IntervalSet.to_list()
    |> Enum.map(&(&1 |> Interval.from() |> Tempo.year()))
    |> Enum.sort()
  end

  describe "^ exclusion members in a set" do
    test "subtracts a discrete member" do
      {:ok, set} = Tempo.to_interval(~o"{2024Y,2026Y,2028Y,^2026Y}")
      assert years(set) == [2024, 2028]
    end

    test "subtracts from a range member" do
      {:ok, set} = Tempo.to_interval(~o"{2020Y..2030Y,^2026Y}")
      result = years(set)
      assert length(result) == 10
      refute 2026 in result
      assert List.first(result) == 2020
      assert List.last(result) == 2030
    end

    test "a plain range member materialises inclusively" do
      {:ok, set} = Tempo.to_interval(~o"{2020Y..2030Y}")
      assert years(set) == Enum.to_list(2020..2030)
    end

    test "a month range materialises to its months" do
      {:ok, set} = Tempo.to_interval(~o"{2020-06..2020-09}")
      assert IntervalSet.count(set) == 4
    end

    test "an open-ended range cannot materialise" do
      assert {:error, %Tempo.MaterialisationError{reason: :open_range}} =
               Tempo.to_interval(%Tempo.Set{
                 type: :all,
                 set: [%Tempo.Range{first: ~o"2020Y", last: :undefined}]
               })
    end
  end

  describe "a recurrence domain in the interval slot" do
    test "a plain-member domain is self-bounding" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN")
      assert years(set) == Enum.to_list(2020..2030)
    end

    test "a domain with ^ drops the excluded year" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN")
      result = years(set)
      assert length(result) == 10
      refute 2026 in result
    end

    test "each occurrence is the selection's date within its year" do
      {:ok, set} = Tempo.to_interval(~o"R/{2025Y}/P1Y/FL12M25DN")
      assert [interval] = IntervalSet.to_list(set)
      assert Interval.from(interval) == ~o"2025Y12M25D"
    end

    test "an exclusions-only domain (braces) needs a bound and subtracts" do
      {:ok, set} = Tempo.to_interval(~o"R/{^2026Y}/P1Y/FL12M25DN", bound: ~o"2024Y/2029Y")
      result = years(set)
      assert length(result) == 4
      refute 2026 in result
    end

    test "the bare ^value form (no braces) excludes a single value" do
      {:ok, set} = Tempo.to_interval(~o"R/^2026Y/P1Y/FL12M25DN", bound: ~o"2024Y/2029Y")
      result = years(set)
      assert length(result) == 4
      refute 2026 in result
    end
  end

  # A self-bounding domain needs no `:bound`, but one that is supplied still
  # narrows it: occurrences are kept only when they start within the bound's
  # window, exactly as for a recurrence without a domain.
  describe "a supplied :bound narrows a self-bounding domain" do
    test "a single-year bound keeps only that year" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2049Y}/P1Y/FL11M1DN", bound: ~o"2029Y")
      assert years(set) == [2029]
    end

    test "a multi-year bound keeps the domain years it spans" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2049Y}/P1Y/FL11M1DN", bound: ~o"2028Y/2031Y")
      assert years(set) == [2028, 2029, 2030]
    end

    test "a bound outside the domain keeps nothing" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN", bound: ~o"2060Y")
      assert years(set) == []
    end

    test "a bound finer than the domain period keeps only the occurrences inside it" do
      {:ok, december} = Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN", bound: ~o"2025Y12M")
      assert years(december) == [2025]

      {:ok, november} = Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN", bound: ~o"2025Y11M")
      assert years(november) == []
    end

    test "exclusions still apply inside the bound" do
      domain = ~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN"

      {:ok, excluded} = Tempo.to_interval(domain, bound: ~o"2026Y")
      assert years(excluded) == []

      {:ok, around} = Tempo.to_interval(domain, bound: ~o"2025Y/2028Y")
      assert years(around) == [2025, 2027]
    end

    test "a year filter still applies inside the bound" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2030Y}e/P1Y/FL1M1DN", bound: ~o"2021Y/2024Y")
      assert years(set) == [2022]
    end

    test "a calendar recurrence's domain narrows to the bound" do
      {:ok, set} =
        Tempo.to_interval(~o"R/{2024Y..2027Y}/P1Y/FL1m1DN[u-ca=chinese]", bound: ~o"2026Y")

      assert [interval] = IntervalSet.to_list(set)
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      assert Date.convert!(date, Calendar.ISO) == ~D[2026-02-17]
    end
  end

  describe "round-trip" do
    test "a domain recurrence with ^ round-trips faithfully" do
      value = ~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN"
      iso = Tempo.to_iso8601(value)
      assert iso == "R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN"
      assert {:ok, ^value} = Tempo.from_iso8601(iso)
    end

    test "a standalone set with ^ round-trips" do
      assert Tempo.to_iso8601(~o"{2020Y..2030Y,^2026Y}") == "{2020Y..2030Y,^2026Y}"
    end

    test "an exclusions-only set renders with braces" do
      assert Tempo.to_iso8601(~o"{^2026Y}") == "{^2026Y}"
    end

    test "the bare ^ form canonicalises to braces" do
      assert Tempo.to_iso8601(~o"R/^2026Y/P1Y/FL12M25DN") == "R/{^2026Y}/P1Y/FL12M25DN"
    end
  end
end
