defmodule Tempo.GroupResolution.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  test "Group resolution days to hours" do
    assert ~o"2022Y1M1G3DUT26H" == ~o"2022Y1M2DT2H"
    assert ~o"2022Y1M1G3DUT24H" == ~o"2022Y1M2DT0H"

    assert ~o"2022Y1M2G1DUT23H" == ~o"2022Y1M2DT23H"
    assert ~o"2022Y1M1G2DUT24H" == ~o"2022Y1M2DT0H"
    assert ~o"2022Y1M2G2DUT24H" == ~o"2022Y1M4DT0H"
  end

  test "Group resolution hours to minutes" do
    assert ~o"T1G1HU1M" == ~o"0H1M"
    assert ~o"T1G4HU1M" == ~o"0H1M"
    assert ~o"T2G1HU1M" == ~o"1H1M"
    assert ~o"T2G4HU1M" == ~o"4H1M"

    assert ~o"T1G4HU239M" == ~o"3H59M"

    assert {:error, %Tempo.InvalidDateError{} = e} = Tempo.from_iso8601("T1G4HU240M")
    assert Exception.message(e) =~ "240 is not valid"
  end

  test "Group resolution minutes to seconds" do
    assert ~o"T1G1MU1S" == ~o"0M1S"
    assert ~o"T1G4MU1S" == ~o"0M1S"
    assert ~o"T2G1MU1S" == ~o"1M1S"
    assert ~o"T2G4MU1S" == ~o"4M1S"

    assert {:error, %Tempo.InvalidDateError{} = e} = Tempo.from_iso8601("T2G4MU240S")
    assert Exception.message(e) =~ "480 is not valid"
  end

  test "Astronomical seasons (25-32) expand to equinox/solstice-bounded intervals" do
    # Codes 25-28 are Northern hemisphere astronomical seasons.
    # Boundaries come from Astro.equinox/2 and Astro.solstice/2.
    assert ~o"2022Y25M" == ~o"2022Y3M20D/6M21D"
    assert ~o"2022Y26M" == ~o"2022Y6M21D/9M23D"
    assert ~o"2022Y27M" == ~o"2022Y9M23D/12M21D"
    assert ~o"2022Y28M" == ~o"2022Y12M21D/2023Y3M20D"
  end

  test "a day after a season is the season's nth day, as it is after a quarter" do
    assert ~o"2026-34-10" == ~o"2026-04-10"
    assert ~o"2026-25-10" == ~o"2026-03-29"
    assert ~o"2026-28-15" == ~o"2027-01-04"
    assert ~o"2026-21-10" == ~o"2026-03-10"
    assert ~o"2026-24-10" == ~o"2025-12-10"
    assert ~o"2026-25-10T10" == ~o"2026-03-29T10"
  end

  test "an astronomical season beyond the years Astro computes is an error" do
    # Astro computes equinoxes and solstices for 1000-3000, and a winter
    # ends at the next year's March equinox.
    assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("0999-25")
    assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("0999-25/2026-27")
    assert {:error, error} = Tempo.from_iso8601("3000-28")
    assert Exception.message(error) =~ "March equinox of 3001"
    assert {:ok, _winter} = Tempo.from_iso8601("2999-28")
  end

  test "Meteorological seasons (21-24) expand to calendar months" do
    # Codes 21-24 are hemisphere-unspecified; we default to Northern
    # meteorological boundaries as a conventional interpretation.
    assert ~o"2022Y21M" == ~o"2022Y3M/5M"
    assert ~o"2022Y22M" == ~o"2022Y6M/8M"
    assert ~o"2022Y23M" == ~o"2022Y9M/11M"
    assert ~o"2022Y24M" == ~o"2021Y12M/2022Y2M"
  end

  describe "a value after a group of its own unit" do
    test "counts within the group, as ISO 8601-2 §5.4.1 reads it" do
      # 30 minutes into the third eight hours of 2 September 2018.
      assert ~o"2018Y9M2DT3GT8HU0H30M" == ~o"2018Y9M2DT16H30M"
      assert ~o"2018Y9M2DT3GT8HU-1H" == ~o"2018Y9M2DT23H"
      assert ~o"2018Y2G3MU2M" == ~o"2018Y5M"
      assert ~o"2026Y2G13WU3W" == ~o"2026Y16W"
    end

    test "outside the group is an error naming the group's range" do
      assert {:error, %Tempo.InvalidDateError{value: 4, valid_range: 1..3}} =
               Tempo.from_iso8601("2018Y2G3MU4M")

      # The last group of eleven days in February holds six.
      assert {:error, %Tempo.InvalidDateError{value: 7, valid_range: 1..6}} =
               Tempo.from_iso8601("2018Y2M3G11DU7D")
    end
  end

  describe "the year's divisions (codes 33-41)" do
    test "are the calendar's quarters, quadrimesters and semesters" do
      assert {:ok, %Tempo{time: [year: 5787, month: {:group, 4..7}]}} =
               Tempo.from_iso8601("5787-34", Calendrical.Hebrew)

      assert {:ok, %Tempo{time: [year: 5787, month: {:group, 11..13}]}} =
               Tempo.from_iso8601("5787-36", Calendrical.Hebrew)

      assert {:ok, %Tempo{time: [year: 5786, month: {:group, 10..12}]}} =
               Tempo.from_iso8601("5786-36", Calendrical.Hebrew)

      assert {:ok, %Tempo{time: [year: 1742, month: {:group, 10..13}]}} =
               Tempo.from_iso8601("1742-36", Calendrical.Coptic)

      assert {:ok, %Tempo{time: [year: 2026, month: {:group, 5..8}]}} =
               Tempo.from_iso8601("2026-38")
    end

    test "are groups of weeks in a week-based calendar" do
      assert {:ok, %Tempo{time: [year: 2026, week: {:group, 40..53}]}} =
               Tempo.from_iso8601("2026-36", Calendrical.ISOWeek)

      assert {:ok, %Tempo{time: [year: 2026, week: {:group, 27..53}]}} =
               Tempo.from_iso8601("2026-41", Calendrical.ISOWeek)
    end
  end

  describe "a group" do
    test "renders as it was declared" do
      for iso8601 <- ["T16H1GT15MU", "2026Y10M3DT3GT8HU", "2018Y2M3G11DU", "2026Y2G13WU"] do
        {:ok, tempo} = Tempo.from_iso8601(iso8601)
        assert Tempo.to_iso8601(tempo) == iso8601
      end
    end

    test "walks the values its container holds" do
      assert ~o"2026Y3G5MU" |> Enum.map(& &1.time[:month]) == [11, 12]
      assert ~o"T16H1GT15MU" |> Enum.map(& &1.time[:minute]) == Enum.to_list(0..14)
    end

    test "takes a duration as its size, not a date" do
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("2026Y1G2KU")
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("1G3KU")
    end
  end
end
