defmodule Tempo.LazyTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{ConversionError, IntervalSet}

  # A set whose members are read as they are asked for (a selection over a
  # span with no end, `Tempo.IntervalSet.from_stream/2`) may have no last
  # member. What reads it one member at a time answers; a window bounds it;
  # what needs every member is refused, and nothing fails to come back.

  defp fifteenths do
    {:ok, set} = Tempo.select(~o"2026-06-01/..", ~o"15D")
    set
  end

  describe "a set with no last member" do
    test "is read one member at a time" do
      assert Enum.take(fifteenths(), 2) == [~o"2026-06-15", ~o"2026-07-15"]
      assert IntervalSet.first(fifteenths()) == ~o"2026-06-15"

      assert fifteenths() |> IntervalSet.filter(&(Tempo.month(&1) == 7)) |> Enum.take(1) ==
               [~o"2026-07-15"]

      assert fifteenths() |> IntervalSet.map(&Tempo.month/1) |> Enum.take(3) == [6, 7, 8]
    end

    test "is bounded by a window" do
      assert {:ok, members} = Tempo.members(fifteenths(), within: ~o"2026")
      assert Enum.count(members) == 7

      assert {:ok, year} = Tempo.to_interval(fifteenths(), within: ~o"2026")
      assert IntervalSet.count(year) == 7
    end

    test "says what it is" do
      refute Tempo.bounded?(fifteenths())
      refute Tempo.empty?(fifteenths())
      assert Tempo.resolution(fifteenths()) == nil
      assert Tempo.year(fifteenths()) == nil
      assert Tempo.explain(fifteenths()) =~ "may have no last member"
    end

    test "is refused by what needs every member" do
      set = fifteenths()

      for result <- [
            Tempo.shift(set, day: 1),
            Tempo.trunc(set, :month),
            Tempo.round(set, :month),
            Tempo.extend(set),
            Tempo.at_resolution(set, :hour),
            Tempo.in_zone(set, "Europe/Paris"),
            Tempo.add_workdays(set, 1, :US),
            Tempo.count_workdays(set, :US)
          ] do
        assert {:error, %ConversionError{reason: :unbounded}} = result
      end

      for result <- [
            Tempo.union(set, ~o"2026-07-15"),
            Tempo.intersection(set, ~o"2026"),
            Tempo.to_interval(set),
            Tempo.members(set),
            Tempo.to_string(set),
            IntervalSet.coalesce(set)
          ] do
        assert {:error, %ConversionError{reason: :too_many_values}} = result
      end

      assert {:error, %ConversionError{reason: :unbounded}} = Tempo.duration(set)
      assert_raise ConversionError, fn -> Tempo.overlaps?(set, ~o"2026") end
      assert_raise ConversionError, fn -> Enum.count(set) end
    end
  end

  describe "the bound on work" do
    test "is a refusal, never a part of the answer" do
      assert {:error, %ConversionError{reason: :too_many_values}} =
               Tempo.to_string(~o"R20000/2026-01-01/P1D")

      assert {:error, %ConversionError{reason: :too_many_values}} =
               Tempo.members(~o"R20000/2026-01-01/P1D")

      assert {:error, %ConversionError{reason: :too_many_values}} =
               IntervalSet.slots(~o"2026-01-01/2026-01-31", ~o"PT1M")
    end

    test "does not bound a count that is made as it is walked" do
      assert Tempo.count_workdays(~o"2000/2099", :US) == {:ok, 26_089}

      assert {:error, %ConversionError{reason: :unbounded}} =
               Tempo.count_workdays(~o"2026/..", :US)
    end
  end
end
