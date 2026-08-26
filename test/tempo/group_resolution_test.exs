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

  test "Meteorological seasons (21-24) expand to calendar months" do
    # Codes 21-24 are hemisphere-unspecified; we default to Northern
    # meteorological boundaries as a conventional interpretation.
    assert ~o"2022Y21M" == ~o"2022Y3M/5M"
    assert ~o"2022Y22M" == ~o"2022Y6M/8M"
    assert ~o"2022Y23M" == ~o"2022Y9M/11M"
    assert ~o"2022Y24M" == ~o"2021Y12M/2022Y2M"
  end
end
