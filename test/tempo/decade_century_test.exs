defmodule Tempo.DecadeCenturyTest do
  use ExUnit.Case, async: true

  # ISO 8601-2 writes a decade and a century alone (§4.3.5, §4.3.6). Tempo
  # also reads one before the units a year holds, filling the years between
  # (`202J6M` is June of each year of the 2020s); a year written after one is
  # a year it names, and a decade after a century is refused (decision 71).

  import Tempo.Sigils

  test "a decade before a month is that month of each of its years" do
    junes = Tempo.from_iso8601!("202J6M")

    assert {:ok, [first | _] = members} = Tempo.members(junes)
    assert Tempo.relation(first, ~o"2020-06") == :equals
    assert Tempo.relation(List.last(members), ~o"2029-06") == :equals
  end

  test "a year after a decade or a century is a year it names" do
    assert {:ok, year} = Tempo.from_iso8601("202J2026Y")
    assert Tempo.relation(year, ~o"2026") == :equals

    assert {:ok, year} = Tempo.from_iso8601("20C2026Y")
    assert Tempo.relation(year, ~o"2026") == :equals
  end

  test "a year before year one after its decade is that year, not one counted from the end" do
    # -12J is the years -129 to -120 (ISO 8601-2 §4.4.1.7).
    assert {:ok, year} = Tempo.from_iso8601("-12J-125Y")
    assert Tempo.relation(year, Tempo.new!(year: -125)) == :equals
  end

  test "a year its decade or century does not name is refused where it is read or built" do
    assert {:error, %Tempo.InvalidDateError{unit: :year, reason: {:out_of_range, 2035, _}}} =
             Tempo.from_iso8601("202J2035Y")

    assert {:error, %Tempo.InvalidDateError{unit: :year}} = Tempo.from_iso8601("20C26Y")
    assert {:error, %Tempo.InvalidDateError{unit: :year}} = Tempo.new(decade: 202, year: 2035)

    assert {:error, %Tempo.InvalidDateError{unit: :year}} =
             Tempo.from_iso8601("202J{2026,2031}Y")
  end

  test "a decade after a century is refused" do
    assert {:error, %Tempo.InvalidDateError{unit: :decade, reason: :after_a_century} = error} =
             Tempo.from_iso8601("20C3J")

    assert Exception.message(error) =~ "written after a century"
    assert {:error, %Tempo.InvalidDateError{}} = Tempo.new(century: 20, decade: 202)
  end
end
