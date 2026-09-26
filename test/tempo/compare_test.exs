defmodule Tempo.CompareTest do
  @moduledoc """
  `Tempo.compare/3` is the sorter-module callback Elixir's `Enum` and
  `List` functions look for. Its job is to make `Tempo` usable exactly
  where `Date` or `DateTime` would be, so most of what matters is that
  the stdlib entry points work, not just that the function returns the
  right atom.
  """

  use ExUnit.Case, async: true

  import Tempo.Sigils

  # `Tempo.Compare` carried no `doctest` declaration, so its documented
  # examples had never been executed.
  doctest Tempo.Compare

  alias Tempo.Compare
  alias Tempo.Interval

  describe "Tempo values" do
    test "orders by start-moment on the time line" do
      assert Tempo.compare(~o"2026-06-15", ~o"2026-06-16") == :lt
      assert Tempo.compare(~o"2026-06-16", ~o"2026-06-15") == :gt
      assert Tempo.compare(~o"2026-06-15", ~o"2026-06-15") == :eq
    end

    test "a coarser value compares at the start of its span" do
      # 2026 begins before June 2026 does.
      assert Tempo.compare(~o"2026Y", ~o"2026-06") == :lt
      assert Tempo.compare(~o"2026-06", ~o"2026Y") == :gt
    end

    test "the same instant in different zones compares equal" do
      assert Tempo.compare(~o"2026-06-15T09:00:00Z", ~o"2026-06-15T10:00:00+01:00") == :eq
    end

    test "comparison is crisp — uncertainty is dropped, not honoured" do
      # A total order cannot carry doubt. `certainly_before?/2` and
      # `possibly_before?/2` are where uncertainty is respected.
      assert Tempo.compare(~o"1984?", ~o"1984") == :eq
      assert Tempo.compare(~o"2004~", ~o"2004") == :eq
    end
  end

  describe "week dates" do
    test "compare in the calendar's own weeks" do
      # Calendrical.Gregorian's week 1 of 2022 starts December 27; ISO
      # 8601's, Calendrical.ISOWeek's, starts January 3.
      assert Tempo.compare(Tempo.new!(year: 2022, week: 1, day_of_week: 1), ~o"2021-12-27") == :eq
      assert Tempo.compare(~o"2022-W01-3"W, ~o"2022-01-05") == :eq
    end
  end

  describe "as a sorter module" do
    test "Enum.sort/2 takes Tempo directly" do
      sorted = Enum.sort([~o"2026-06-16", ~o"2026-06-15", ~o"2026-06-17"], Tempo)

      assert Enum.map(sorted, &Tempo.to_iso8601/1) ==
               ["2026Y6M15D", "2026Y6M16D", "2026Y6M17D"]
    end

    test "Enum.sort_by/3 takes Tempo directly" do
      sessions = [%{at: ~o"2026-06-16"}, %{at: ~o"2026-06-15"}]

      assert [%{at: first} | _] = Enum.sort_by(sessions, & &1.at, Tempo)
      assert Tempo.to_iso8601(first) == "2026Y6M15D"
    end

    test "Enum.min/2 and Enum.max/2 take Tempo directly" do
      days = [~o"2026-06-15", ~o"2026-06-17", ~o"2026-06-16"]

      assert Tempo.to_iso8601(Enum.min(days, Tempo)) == "2026Y6M15D"
      assert Tempo.to_iso8601(Enum.max(days, Tempo)) == "2026Y6M17D"
    end

    test "sorting is stable against Erlang term order" do
      # Term order would put these in a different sequence than time
      # order does; this is the bug the function exists to prevent.
      times = [~o"2026-06-15T10:00", ~o"2026-06-15T09:00"]

      assert [earlier, _later] = Enum.sort(times, Tempo)
      assert Tempo.hour(earlier) == 9
    end
  end

  describe "durations" do
    test "order by length" do
      assert Tempo.compare(~o"PT1H", ~o"PT90M") == :lt
      assert Tempo.compare(~o"PT90M", ~o"PT1H") == :gt
    end

    test "equal lengths written differently compare equal" do
      assert Tempo.compare(~o"PT1H", ~o"PT60M") == :eq
    end

    test "a calendar-dependent duration needs a reference date" do
      # `P1M` has no fixed length, so there is no answer without
      # knowing which month.
      assert_raise ArgumentError, ~r/no fixed length/, fn ->
        Tempo.compare(~o"P1M", ~o"P30D")
      end
    end

    test "the reference date decides, and it genuinely matters" do
      # January is 31 days, so a month is longer than 30 days.
      assert Tempo.compare(~o"P1M", ~o"P30D", relative_to: ~o"2026-01-01") == :gt

      # February 2026 is 28 days, so the same comparison flips.
      assert Tempo.compare(~o"P1M", ~o"P30D", relative_to: ~o"2026-02-01") == :lt
    end
  end

  describe "intervals" do
    defp interval(from, to) do
      Interval.new!(from: Tempo.from_iso8601!(from), to: Tempo.from_iso8601!(to))
    end

    test "order by start" do
      earlier = interval("2026-06-15T09:00", "2026-06-15T10:00")
      later = interval("2026-06-15T11:00", "2026-06-15T12:00")

      assert Tempo.compare(earlier, later) == :lt
      assert Tempo.compare(later, earlier) == :gt
    end

    test "a shared start is broken by the end, shorter first" do
      shorter = interval("2026-06-15T09:00", "2026-06-15T10:00")
      longer = interval("2026-06-15T09:00", "2026-06-15T11:00")

      assert Tempo.compare(shorter, longer) == :lt
    end

    test "identical intervals compare equal" do
      assert Tempo.compare(
               interval("2026-06-15T09:00", "2026-06-15T10:00"),
               interval("2026-06-15T09:00", "2026-06-15T10:00")
             ) == :eq
    end

    test "an open start sorts before every stated one" do
      {:ok, open} = Interval.new(from: :undefined, to: Tempo.from_iso8601!("2026-06-15T10:00"))

      assert Tempo.compare(open, interval("2026-06-15T09:00", "2026-06-15T10:00")) == :lt
    end

    test "an open end sorts after every stated one" do
      {:ok, open} = Interval.new(from: Tempo.from_iso8601!("2026-06-15T09:00"), to: :undefined)

      assert Tempo.compare(open, interval("2026-06-15T09:00", "2026-06-15T10:00")) == :gt
    end

    test "a whole timetable sorts into running order" do
      unsorted = [
        interval("2026-06-15T11:00", "2026-06-15T12:00"),
        interval("2026-06-15T09:00", "2026-06-15T11:00"),
        interval("2026-06-15T09:00", "2026-06-15T10:00")
      ]

      assert [first, second, third] = Enum.sort(unsorted, Tempo)
      assert Tempo.hour(first.to) == 10
      assert Tempo.hour(second.to) == 11
      assert Tempo.hour(third.from) == 11
    end
  end

  describe "mismatched kinds" do
    test "comparing different kinds names both of them" do
      assert_raise ArgumentError, ~r/cannot compare a Tempo with a Tempo\.Duration/, fn ->
        Tempo.compare(~o"2026-06-15", ~o"PT1H")
      end
    end

    test "an interval is not comparable with a bare Tempo" do
      assert_raise ArgumentError, ~r/same kind/, fn ->
        Tempo.compare(interval("2026-06-15T09:00", "2026-06-15T10:00"), ~o"2026-06-15")
      end
    end
  end

  describe "agreement with the existing predicates" do
    test "compare/2 and before?/2 agree on disjoint values" do
      for {a, b} <- [{~o"2026-01", ~o"2026-03"}, {~o"2026-06-15", ~o"2026-08-20"}] do
        assert Tempo.compare(a, b) == :lt
        assert Tempo.before?(a, b)
      end
    end

    test "compare/2 returns :eq exactly where compare_endpoints/2 returns :same" do
      pairs = [
        {~o"2026-06-15", ~o"2026-06-15"},
        {~o"2026-06-15T09:00:00Z", ~o"2026-06-15T10:00:00+01:00"},
        {~o"2026-06-15", ~o"2026-06-16"}
      ]

      for {a, b} <- pairs do
        expected = if Compare.compare_endpoints(a, b) == :same, do: :eq, else: :lt
        assert Tempo.compare(a, b) == expected
      end
    end
  end
end
