defmodule Tempo.MaskTest do
  use ExUnit.Case, async: true

  alias Tempo.Mask

  doctest Tempo.Mask

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

    test "a digit set admits each of its digits" do
      assert Mask.valid_values(:year, [2, 0, [2..3], [0, 5]], [], @cal) ==
               {:ok, [2020, 2025, 2030, 2035]}

      assert Mask.valid_values(:month, [[0, 1], 2], [year: 2026], @cal) == {:ok, [2, 12]}
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

    test "a year written to four digits is matched by the digits after its leading zeros" do
      # `000X` is the years 0 to 9 and `00XX` the years 0 to 99: the zeros
      # are the padding of a year written to four digits. No year has four
      # digits that begin with a zero, so the mask matched none, and a walk
      # of `~o"000X"` raised where its span was ten years.
      assert Enum.filter(0..120, &Mask.matches_mask?(&1, [0, 0, 0, :X])) == Enum.to_list(0..9)
      assert Enum.filter(0..120, &Mask.matches_mask?(&1, [0, 0, :X, :X])) == Enum.to_list(0..99)

      assert Enum.filter(0..120, &Mask.matches_mask?(&1, [0, 0, :X, 5])) ==
               Enum.to_list(5..95//10)

      assert Enum.filter(0..1200, &Mask.matches_mask?(&1, [0, :X, 0, :X])) ==
               for(hundreds <- 0..9, units <- 0..9, do: hundreds * 100 + units)

      # A year of four digits has no padding to pass over.
      assert Enum.filter(0..2100, &Mask.matches_mask?(&1, [2, 0, 0, :X])) ==
               Enum.to_list(2000..2009)

      for {text, years} <- [
            {"000X", 0..9},
            {"00XX", 0..99},
            {"0XXX", 0..999},
            {"-000X", -9..0},
            {"00X5", 5..95//10}
          ] do
        value = Tempo.from_iso8601!(text)
        walked = for year <- value, do: Tempo.year(year)

        assert {text, walked} == {text, Enum.to_list(years)}
        assert {text, Enum.count(value)} == {text, Range.size(years)}
      end
    end

    test "negative masks only match negative candidates" do
      assert Mask.matches_mask?(-5, [:negative, 5])
      refute Mask.matches_mask?(5, [:negative, 5])
    end

    test "a digit set matches any of its digits" do
      assert Mask.matches_mask?(2028, [:X, :X, :X, [0, 2, 4, 6, 8]])
      refute Mask.matches_mask?(2027, [:X, :X, :X, [0, 2, 4, 6, 8]])
      assert Mask.matches_mask?(2035, [2, 0, [2..3], :X])
      refute Mask.matches_mask?(2045, [2, 0, [2..3], :X])
    end
  end

  describe "mask_bounds/1" do
    test "each :X spans 0..9 at its position" do
      assert Mask.mask_bounds([1, 5, 6, :X]) == {1560, 1569}
      assert Mask.mask_bounds([:X, :X, :X, :X]) == {0, 9999}
    end

    test "a digit set spans its smallest to its largest digit" do
      assert Mask.mask_bounds([:X, :X, :X, [0, 2, 4, 6, 8]]) == {0, 9998}
      assert Mask.mask_bounds([2, 0, [2..3], :X]) == {2020, 2039}
    end
  end

  describe "valid_values/4 for the units a walk masks" do
    test "a week and a day of the year are bounded by their year" do
      assert Mask.valid_values(:week, [2, :X], [year: 2026], @cal) == {:ok, Enum.to_list(20..29)}
      assert Mask.valid_values(:week, [5, :X], [year: 2026], @cal) == {:ok, [50, 51, 52, 53]}
      assert Mask.valid_values(:week, [5, :X], [year: 2027], @cal) == {:ok, [50, 51, 52]}

      assert Mask.valid_values(:day_of_year, [3, 6, :X], [year: 2026], @cal) ==
               {:ok, Enum.to_list(360..365)}

      assert Mask.valid_values(:week, [:X, :X], [], @cal) == {:error, :unanchored}
      assert Mask.valid_values(:day_of_year, [:X, :X, :X], [], @cal) == {:error, :unanchored}
    end

    test "a day of the week is the days its calendar's week has" do
      assert Mask.valid_values(:day_of_week, [:X], [], @cal) == {:ok, Enum.to_list(1..7)}
    end

    test "a day straight after a year counts through the year" do
      assert Mask.valid_values(:day, [3, 6, :X], [year: 2024], @cal) ==
               {:ok, Enum.to_list(360..366)}
    end

    test "a unit with no range of values to narrow to" do
      assert Mask.valid_values(:traditional_month, [:X, :X], [year: 2026], @cal) ==
               {:error, {:unmaskable, :traditional_month}}
    end
  end

  describe "candidates/4" do
    test "a positive single-digit month mask yields 1..9" do
      assert Mask.candidates(:month, [:X], [year: 1985], @cal) == {:ok, Enum.to_list(1..9)}
    end

    test "a negative year mask yields negative two-digit years, the earliest first" do
      assert {:ok, result} = Mask.candidates(:year, [:negative, :X, :X], [], @cal)
      assert result == Enum.to_list(-99..-10//1)
    end

    test "a month mask counted from the end yields the months it names" do
      assert Mask.candidates(:month, [:negative, :X], [year: 1985], @cal) ==
               {:ok, Enum.to_list(4..12)}

      assert Mask.candidates(:month, [:negative, 1, :X], [year: 1985], @cal) == {:ok, [1, 2, 3]}
    end

    test "a clock mask counted from the end counts back from the unit's extent" do
      assert Mask.candidates(:hour, [:negative, :X], [], @cal) == {:ok, Enum.to_list(15..23)}
      assert Mask.candidates(:hour, [:negative, 2, :X], [], @cal) == {:ok, Enum.to_list(0..4)}
    end
  end

  describe "unspecified/3" do
    test "a unit with the same extent everywhere" do
      assert Mask.unspecified(:hour, [], @cal) == {:ok, 0..23}
      assert Mask.unspecified(:minute, [hour: 10], @cal) == {:ok, 0..59}
      assert Mask.unspecified(:day_of_week, [], @cal) == {:ok, 1..7}
    end

    test "a unit bounded by the units before it" do
      assert Mask.unspecified(:month, [year: 2026], @cal) == {:ok, 1..12}
      assert Mask.unspecified(:month, [year: 5784], Calendrical.Hebrew) == {:ok, 1..13}
      assert Mask.unspecified(:day, [year: 2024, month: 2], @cal) == {:ok, 1..29}
      assert Mask.unspecified(:week, [year: 2026], @cal) == {:ok, 1..53}
      assert Mask.unspecified(:day_of_year, [year: 2026], @cal) == {:ok, 1..365}
    end

    test "a unit that takes the same values in every year needs no year" do
      assert Mask.unspecified(:month, [], @cal) == {:ok, 1..12}
      assert Mask.unspecified(:day, [month: 6], @cal) == {:ok, 1..30}
    end

    # With no year, what depends on the year is refused (decided 2026-10-04):
    # an unspecified day of a February listed 29 days, where a mask of it, a
    # count from its end and the walk of the month were each unanchored.
    test "a unit whose extent depends on a year it lacks is unanchored" do
      assert Mask.unspecified(:day, [month: 2], @cal) == {:error, :unanchored}
      assert Mask.unspecified(:month, [], Calendrical.Hebrew) == {:error, :unanchored}
    end

    test "at_most/3 takes the values of the year that has the most, where a cycle ends" do
      assert Mask.at_most(:day, [month: 2], @cal) == {:ok, 1..29}
      assert Mask.at_most(:month, [], Calendrical.Hebrew) == {:ok, 1..13}
      assert Mask.at_most(:month, [], @cal) == {:ok, 1..12}
      assert Mask.at_most(:week, [], @cal) == {:error, :unanchored}
    end

    test "a unit with nothing to bound it is unanchored" do
      assert Mask.unspecified(:week, [], @cal) == {:error, :unanchored}
      assert Mask.unspecified(:day, [], @cal) == {:error, :unanchored}
      assert Mask.unspecified(:day_of_year, [], @cal) == {:error, :unanchored}
    end
  end
end
