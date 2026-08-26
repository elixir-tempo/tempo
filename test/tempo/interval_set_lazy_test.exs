defmodule Tempo.IntervalSetLazyTest do
  @moduledoc """
  The lazy backend: walking works without materialising, aggregates
  refuse with `Tempo.UnboundedSetError`, and an unbounded busy set
  drives `Tempo.shift/3` with `skipping:`.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  defp mondays(from) do
    from
    |> Stream.iterate(&Tempo.shift(&1, week: 1))
    |> Stream.map(&Tempo.to_interval!/1)
    |> IntervalSet.from_stream()
  end

  describe "walking an unbounded set" do
    test "walk yields members on demand" do
      set = mondays(~o"2026-01-05")

      days = set |> IntervalSet.walk() |> Enum.take(3) |> Enum.map(& &1.from.time[:day])
      assert days == [5, 12, 19]
    end

    test "first, empty?, and bounded? answer without materialising" do
      set = mondays(~o"2026-01-05")

      assert IntervalSet.first(set).from.time[:day] == 5
      refute IntervalSet.empty?(set)
      refute IntervalSet.bounded?(set)
    end

    test "covered? terminates by walking only to the probe" do
      set = mondays(~o"2026-01-05")

      assert IntervalSet.covered?(set, ~o"2026-01-12")
      refute IntervalSet.covered?(set, ~o"2026-01-13")
    end

    test "Enum.take walks sub-points lazily" do
      set = mondays(~o"2026-01-05")

      assert set |> Enum.take(2) |> Enum.map(& &1.time[:hour]) == [0, 1]
    end
  end

  describe "aggregate refusals" do
    test "to_list and count raise with direction" do
      set = mondays(~o"2026-01-05")

      assert_raise Tempo.UnboundedSetError, ~r/walk\/1/, fn -> IntervalSet.to_list(set) end
      assert_raise Tempo.UnboundedSetError, fn -> IntervalSet.count(set) end
      assert_raise Tempo.UnboundedSetError, fn -> IntervalSet.last(set) end
    end

    test "Enum.count refuses rather than hanging" do
      set = mondays(~o"2026-01-05")
      assert_raise Tempo.UnboundedSetError, fn -> Enum.count(set) end
    end

    test "member-list rewrites refuse through to_list" do
      set = mondays(~o"2026-01-05")

      assert_raise Tempo.UnboundedSetError, fn -> IntervalSet.coalesce(set) end
      assert_raise Tempo.UnboundedSetError, fn -> IntervalSet.filter(set, fn _ -> true end) end
    end
  end

  describe "inspecting an unbounded set" do
    test "the Inspect limit bounds the walk" do
      rendered = inspect(mondays(~o"2026-01-05"), limit: 2)

      assert rendered =~ "2026Y1M5D"
      assert rendered =~ "2026Y1M12D"
      refute rendered =~ "2026Y1M19D"
      assert rendered =~ "…"
    end

    test "limit: :infinity falls back to the default rather than walking forever" do
      rendered = inspect(mondays(~o"2026-01-05"), limit: :infinity)
      assert rendered =~ "…"
    end
  end

  describe "an unbounded busy set drives shift/3 skipping:" do
    test "three free days from Thursday afternoon skip the weekend, no bound needed" do
      start = ~o"2026-06-18T16:00"
      weekends = Tempo.weekends(from: ~o"2026-06-18")

      assert Tempo.shift(start, ~o"P3D", skipping: weekends) == ~o"2026-06-23T16:00:00"
    end

    test "a Saudi weekend skips Friday and Saturday instead" do
      start = ~o"2026-06-18T16:00"
      weekends = Tempo.weekends(from: ~o"2026-06-18", territory: :SA)

      assert Tempo.shift(start, ~o"P2D", skipping: weekends) == ~o"2026-06-22T16:00:00"
    end

    test "a backward shift materialises only the finite prefix" do
      arrived = ~o"2026-06-23T16:00"
      weekends = Tempo.weekends(from: ~o"2026-06-15")

      assert Tempo.shift(arrived, [second: -3 * 86_400], skipping: weekends) ==
               ~o"2026-06-18T16:00:00"
    end
  end
end
