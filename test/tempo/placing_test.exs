defmodule Tempo.PlacingTest do
  use ExUnit.Case, async: true

  # One value placed on another with `Tempo.at/2` and `Tempo.on/2`: an
  # interval end by end, a selection after the units it selects in.

  import Tempo.Sigils

  describe "an interval" do
    test "is placed end by end" do
      assert Tempo.on(~o"4M2D/4M16D", ~o"2027") == {:ok, ~o"2027-04-02/2027-04-16"}
      assert Tempo.on(~o"2027", ~o"4M2D/4M16D") == {:ok, ~o"2027-04-02/2027-04-16"}
      assert Tempo.on(~o"T09/T17", ~o"2026-06-15") == {:ok, ~o"2026-06-15T09/2026-06-15T17"}
      assert Tempo.at(~o"2026-06-15", ~o"T09/T17") == {:ok, ~o"2026-06-15T09/2026-06-15T17"}
    end

    test "an open end, or one a duration gives, stays as it is" do
      assert Tempo.on(~o"4M2D/..", ~o"2027") == {:ok, ~o"2027-04-02/.."}
      assert Tempo.on(~o"4M2D/P14D", ~o"2027") == {:ok, ~o"2027-04-02/P14D"}
    end

    test "placed, must still start before it ends, on dates the year has" do
      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.on(~o"12M20D/1M5D", ~o"2027")
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.on(~o"2M29D/3M2D", ~o"2026")
    end
  end

  describe "a selection" do
    test "follows the units it selects in, with nothing filled beside it" do
      assert Tempo.on(~o"4ML1K1IN", ~o"2027") == {:ok, ~o"2027Y4ML1K1IN"}
      assert Tempo.on(~o"L(easter)eN", ~o"2027") == {:ok, ~o"2027YL(easter)eN"}
      assert Tempo.at(~o"2027Y4ML1K1IN", ~o"T09") == {:ok, ~o"2027Y4ML1K1INT9H"}
    end

    test "placed, names what it selects there" do
      {:ok, first_monday} = Tempo.on(~o"4ML1K1IN", ~o"2027")
      assert Tempo.members(first_monday) == {:ok, [~o"2027-04-05"]}

      {:ok, easter} = Tempo.on(~o"L(easter)eN", ~o"2027")
      assert Tempo.members(easter) == {:ok, [~o"2027-03-28"]}

      {:ok, at_nine} = Tempo.at(~o"2027Y4ML1K1IN", ~o"T09")
      assert Tempo.members(at_nine) == {:ok, [~o"2027-04-05T09"]}
    end
  end

  describe "a value with no year in a :within window" do
    test "is placed in a window that is one value" do
      assert Tempo.members(~o"6M", within: ~o"2026") == {:ok, [~o"2026-06"]}
    end

    test "is placed on each period of a window that is a span" do
      assert Tempo.members(~o"6M", within: ~o"2026/2027") == {:ok, [~o"2026-06", ~o"2027-06"]}

      assert Tempo.members(~o"5K", within: ~o"2026-06-01/2026-06-14") ==
               {:ok, [~o"2026-06-05", ~o"2026-06-12"]}
    end
  end

  describe "what cannot be placed" do
    test "is an error, not a raise" do
      assert {:error, %Tempo.ConversionError{reason: :selection}} =
               Tempo.on(~o"L1K1IN", ~o"L(easter)eN")

      assert {:error, %Tempo.FrameError{}} = Tempo.on(~o"4M2D/4M16D", ~o"2027/2028")
      assert {:error, %Tempo.FrameError{}} = Tempo.on(~o"2026-04-02/2026-04-16", ~o"2027")

      for value <- [nil, "", :"", 42] do
        assert {:error, %Tempo.ConversionError{reason: :not_an_expression}} =
                 Tempo.on(value, ~o"2027")

        assert {:error, %Tempo.ConversionError{reason: :not_an_expression}} =
                 Tempo.at(~o"2027", value)
      end
    end
  end
end
