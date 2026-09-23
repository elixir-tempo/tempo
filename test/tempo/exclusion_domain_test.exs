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
