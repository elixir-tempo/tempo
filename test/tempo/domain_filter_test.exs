defmodule Tempo.DomainFilterTest do
  # The `e` / `o` / `l` year-filter markers on a recurrence domain:
  # `R/{2000Y..2020Y}e/P1Y/…` (bounded) and `R/..e/P1Y/…` (open, needs a bound).
  # even/odd are arithmetic on the year; leap delegates to the recurrence
  # calendar's own `leap_year?/1`.
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

  describe "bounded domain filter {…}e/o/l" do
    test "e keeps the even years" do
      {:ok, set} = Tempo.to_interval(~o"R/{2000Y..2010Y}e/P1Y/FL12M25DN")
      assert years(set) == [2000, 2002, 2004, 2006, 2008, 2010]
    end

    test "o keeps the odd years" do
      {:ok, set} = Tempo.to_interval(~o"R/{2000Y..2010Y}o/P1Y/FL12M25DN")
      assert years(set) == [2001, 2003, 2005, 2007, 2009]
    end

    test "l keeps the leap years" do
      {:ok, set} = Tempo.to_interval(~o"R/{2000Y..2010Y}l/P1Y/FL12M25DN")
      assert years(set) == [2000, 2004, 2008]
    end

    test "no marker keeps every year" do
      {:ok, set} = Tempo.to_interval(~o"R/{2000Y..2010Y}/P1Y/FL12M25DN")
      assert length(years(set)) == 11
    end

    test "the filter composes with a ^ exclusion" do
      {:ok, set} = Tempo.to_interval(~o"R/{2000Y..2010Y,^2004Y}e/P1Y/FL12M25DN")
      assert years(set) == [2000, 2002, 2006, 2008, 2010]
    end
  end

  describe "open domain filter ..e/o/l" do
    test "e keeps the even years within the bound" do
      {:ok, set} = Tempo.to_interval(~o"R/..e/P1Y/FL12M25DN", bound: ~o"{2000..2010}Y")
      assert years(set) == [2000, 2002, 2004, 2006, 2008, 2010]
    end

    test "l keeps the leap years within the bound" do
      {:ok, set} = Tempo.to_interval(~o"R/..l/P1Y/FL12M25DN", bound: ~o"{2000..2010}Y")
      assert years(set) == [2000, 2004, 2008]
    end

    test "needs a bound" do
      {:ok, recurrence} = Tempo.from_iso8601("R/..e/P1Y/FL12M25DN")
      assert {:error, _} = Tempo.to_interval(recurrence)
    end
  end

  describe "leap uses the calendar's rule, not naive divisibility" do
    test "the Gregorian century rule excludes 2100" do
      # 2100 is divisible by 4 but is not a leap year (divisible by 100, not
      # 400), so a naive `rem(year, 4)` would wrongly include it. The filter
      # delegates to the year's calendar `leap_year?/1`, so it does not.
      {:ok, set} = Tempo.to_interval(~o"R/{2096Y..2104Y}l/P1Y/FL1M1DN")
      assert years(set) == [2096, 2104]
    end
  end

  describe "round-trip" do
    test "every filter form re-emits as written" do
      for iso <- [
            "R/{2000Y..2010Y}e/P1Y/FL12M25DN",
            "R/{2000Y..2010Y}o/P1Y/FL12M25DN",
            "R/{2000Y..2010Y}l/P1Y/FL12M25DN",
            "R/{2000Y..2010Y,^2004Y}e/P1Y/FL12M25DN",
            "R/..e/P1Y/FL12M25DN",
            "R/..o/P1Y/FL12M25DN",
            "R/..l/P1Y/FL12M25DN"
          ] do
        {:ok, value} = Tempo.from_iso8601(iso)
        assert Tempo.to_iso8601(value) == iso
      end
    end
  end
end
