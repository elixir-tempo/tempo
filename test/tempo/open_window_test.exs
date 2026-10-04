defmodule Tempo.OpenWindowTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Clock.Test
  alias Tempo.ICal
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet

  defp starts(set, count) do
    set |> IntervalSet.walk() |> Enum.take(count) |> Enum.map(&Interval.from/1)
  end

  describe "an open-ended :within window" do
    test "walks a recurrence with no end from the window's start, the one under way first" do
      {:ok, years} = Tempo.to_interval_set(~o"R/2020-01-01/P1Y", within: ~o"2026-06-01/..")

      assert starts(years, 3) == [~o"2026-01-01", ~o"2027-01-01", ~o"2028-01-01"]
    end

    test "an open-start rule's next occurrence is IntervalSet.first/1" do
      {:ok, christmases} =
        Tempo.to_interval_set(~o"R/../P1Y/FL12M25DN", within: ~o"2026-12-26/..")

      assert christmases |> IntervalSet.first() |> Interval.from() == ~o"2027-12-25"
    end

    test "an open domain walks its years: US Election Day in even years" do
      {:ok, elections} =
        Tempo.to_interval_set(~o"R/{2000Y..}e/P1Y/FL11M{2..8}D2K1IN", within: ~o"2026-11-04/..")

      assert starts(elections, 2) == [~o"2028-11-07", ~o"2030-11-05"]
    end
  end

  describe "an open-ended :within window over other values" do
    test "a recurrence set's members come in time order" do
      holidays = RecurrenceSet.new!([~o"R/../P1Y/FL12M25DN", ~o"R/../P1Y/FL1M1DN"])
      {:ok, upcoming} = Tempo.to_interval_set(holidays, within: ~o"2026-12-26/..")

      assert starts(upcoming, 3) == [~o"2027-01-01", ~o"2027-12-25", ~o"2028-01-01"]
    end

    test "an occurrence across the edge of a walked window comes once" do
      {:ok, weeks} = Tempo.to_interval_set(~o"R/2026-01-05/P1W", within: ~o"2026-01-01/..")
      mondays = starts(weeks, 12)

      assert Enum.count(Enum.uniq(mondays)) == 12
      assert mondays == Enum.sort(mondays, Tempo)
    end

    test "a value with an end of its own stays a bounded set" do
      {:ok, years} = Tempo.to_interval_set(~o"R5/2024-01-01/P1Y", within: ~o"2026-06-01/..")

      assert IntervalSet.count(years) == 3
    end

    test "a rule with no occurrence ends its walk" do
      {:ok, never} = Tempo.to_interval_set(~o"R/../P1Y/FL2M30DN", within: ~o"2026/..")

      assert IntervalSet.first(never) == nil
    end

    test "a window from today, built at run time" do
      Process.put({Tempo.Clock, :clock}, Test)
      Test.put(~U[2026-09-28 01:00:00Z])

      {:ok, from_today} = Interval.new(from: Tempo.today())
      {:ok, christmases} = Tempo.to_interval_set(~o"R/../P1Y/FL12M25DN", within: from_today)

      assert christmases |> IntervalSet.first() |> Interval.from() == ~o"2026-12-25"
    end
  end

  describe "the window's start" do
    test "a masked start begins where the span it names does" do
      {:ok, christmases} = Tempo.to_interval_set(~o"R/../P1Y/FL12M25DN", within: ~o"202X/..")

      assert christmases |> IntervalSet.first() |> Interval.from() == ~o"2020-12-25"
    end

    test "a start with no date is an error" do
      assert {:error, %ArgumentError{}} =
               Tempo.to_interval_set(~o"R/../P1Y/FL12M25DN", within: ~o"T10/..")
    end
  end

  describe "a function that needs a window with an end" do
    test "a set operation returns an error" do
      assert {:error, %ArgumentError{}} =
               Tempo.intersection(~o"2026", ~o"2026-06", within: ~o"2026/..")
    end

    test "complement/2 returns an error" do
      assert {:error, %ArgumentError{}} = Tempo.complement(~o"2026-06", within: ~o"2026/..")
    end

    test "an iCalendar import returns an error" do
      assert {:error, %ArgumentError{}} = ICal.parse("", within: ~o"2026/..")
    end
  end
end
