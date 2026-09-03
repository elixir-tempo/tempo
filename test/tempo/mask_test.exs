defmodule Tempo.MaskTest do
  use ExUnit.Case, async: true

  alias Tempo.Mask

  @cal Calendrical.Gregorian

  describe "valid_values/4 across units" do
    test "month and day are calendar-bounded" do
      assert Mask.valid_values(:month, [:X, :X], [year: 1985], @cal) == {:ok, Enum.to_list(1..12)}
      assert Mask.valid_values(:month, [:X, 5], [year: 1985], @cal) == {:ok, [5]}

      assert Mask.valid_values(:day, [:X, :X], [year: 1985, month: 2], @cal) ==
               {:ok, Enum.to_list(1..28)}
    end

    test "hour spans 0..23" do
      assert Mask.valid_values(:hour, [:X, :X], [], @cal) == {:ok, Enum.to_list(0..23)}
      assert Mask.valid_values(:hour, [1, :X], [], @cal) == {:ok, Enum.to_list(10..19)}
    end

    test "year is digit-bounded, not calendar-bounded" do
      assert Mask.valid_values(:year, [1, 9, 9, :X], [], @cal) == {:ok, Enum.to_list(1990..1999)}
      assert Mask.valid_values(:year, [1, 9, :X, :X], [], @cal) == {:ok, Enum.to_list(1900..1999)}
    end

    test "minute and second span 0..59" do
      assert Mask.valid_values(:minute, [:X, 5], [], @cal) == {:ok, [5, 15, 25, 35, 45, 55]}
      assert Mask.valid_values(:second, [3, :X], [], @cal) == {:ok, Enum.to_list(30..39)}
    end
  end

  describe "matches_mask?/2" do
    test "a wildcard matches any digit, concrete digits must match" do
      assert Mask.matches_mask?(156, [1, :X, 6])
      refute Mask.matches_mask?(157, [1, :X, 6])
      refute Mask.matches_mask?(12, [1, 2, 3])
    end

    test "negative masks only match negative candidates" do
      assert Mask.matches_mask?(-5, [:negative, 5])
      refute Mask.matches_mask?(5, [:negative, 5])
    end
  end

  describe "mask_bounds/1" do
    test "each :X spans 0..9 at its position" do
      assert Mask.mask_bounds([1, 5, 6, :X]) == {1560, 1569}
      assert Mask.mask_bounds([:X, :X, :X, :X]) == {0, 9999}
    end
  end

  describe "fill_unspecified/4" do
    test ":any year resolves to the current year" do
      assert [year] = Mask.fill_unspecified(:year, :any, @cal, [])
      assert is_integer(year)
    end

    test "a positive single-digit month mask yields 1..9" do
      assert Mask.fill_unspecified(:month, [:X], @cal, year: 1985) == Enum.to_list(1..9)
    end

    test "a negative year mask yields negative two-digit years" do
      result = Mask.fill_unspecified(:year, [:negative, :X, :X], @cal, [])
      assert -10 in result
      assert -99 in result
      refute -9 in result
    end

    test "a negative month mask yields negative months" do
      assert Mask.fill_unspecified(:month, [:negative, :X], @cal, year: 1985, month: 1) ==
               Enum.to_list(-9..-1)
    end
  end
end
