defmodule Tempo.Reader.WrittenFormsTest do
  use ExUnit.Case, async: true

  alias Tempo.ParseError

  # The less common written forms: each is read, written in the explicit
  # form of ISO 8601-2, and read back from what was written as the same
  # expression.

  @forms [
    # Sets: a range, a step, a count from the end, an exclusion.
    {"2026Y{1..12//3}M", "2026Y{1..12//3}M"},
    {"2026Y{1..-1}M", "2026Y{1..-1}M"},
    {"{2020Y..2024Y,^2022Y}", "{2020Y..2024Y,^2022Y}"},
    # A recurrence over a domain of years, filtered to the even, the odd,
    # the leap and the common.
    {"R/{2020Y..2030Y}e/P1Y/FL7M4DN", "R/{2020Y..2030Y}e/P1Y/FL7M4DN"},
    {"R/{2020Y..2030Y}o/P1Y/FL7M4DN", "R/{2020Y..2030Y}o/P1Y/FL7M4DN"},
    {"R/{2020Y..2030Y}l/P1Y/FL7M4DN", "R/{2020Y..2030Y}l/P1Y/FL7M4DN"},
    {"R/{2020Y..2030Y}c/P1Y/FL7M4DN", "R/{2020Y..2030Y}c/P1Y/FL7M4DN"},
    # Rules: an event in a zone, a week start.
    {"R/../P1Y/FL(march-equinox@+09:00)eN", "R/../P1Y/FL(march-equinox@+09:00)eN"},
    {"R/2026-01-01/P1W/FL1KN[u-fw=sun]", "R/2026Y1M1D/P1W/FL1KN[u-fw=sun]"},
    # IXDTF suffixes: an offset, a critical zone, tags, a zone before a calendar.
    {"2026-06-15T10:00[+02:00]", "2026Y6M15DT10H0M[+02:00]"},
    {"2026-06-15T10:00[-05:30]", "2026Y6M15DT10H0M[-05:30]"},
    {"2026-06-15T10:00[!Europe/Paris]", "2026Y6M15DT10H0M[!Europe/Paris]"},
    {"2026-06-15[x-a=b][x-c=d]", "2026Y6M15D[x-a=b][x-c=d]"},
    # A fraction of an hour or a minute is the minutes and seconds it names.
    {"2026-06-15T10.5", "2026Y6M15DT10H30M"},
    {"2026-06-15T10:30.5", "2026Y6M15DT10H30M30S"},
    {"T10.25H", "T10H15M"},
    {"2026-06-15T10:30:15.25", "2026Y6M15DT10H30M15.25S"},
    # Divisions of a year: a quarter is its own unit, a third and a half are groups.
    {"2026-33", "2026Y33M"},
    {"2026-37", "2026Y1G4MU"},
    {"2026-40", "2026Y1G6MU"},
    {"2026Y2G3MU", "2026Y2G3MU"},
    # Durations: nothing, a negative, a fraction.
    {"PT0S", "PT0S"},
    {"-P1D", "P-1D"},
    {"P1.5D", "P1.5D"},
    {"PT1.5H", "PT1.5H"},
    # Qualifiers, significant digits, unspecified digits, years beyond four digits.
    {"?2026-06-15", "2026?Y6M15D"},
    {"2026-06-~15", "2026Y6M15~D"},
    {"1950S2", "1950S2Y"},
    {"XXXX-12-25", "XXXXY12M25D"},
    {"2026-1X", "2026Y1XM"},
    {"-0044-03-15", "-44Y3M15D"},
    {"Y12026", "12026Y"}
  ]

  for {text, written} <- @forms do
    test "#{text} is written #{written}, and reads back" do
      assert {:ok, read} = Tempo.from_iso8601(unquote(text))
      assert Tempo.to_iso8601(read) == {:ok, unquote(written)}
      assert Tempo.from_iso8601(unquote(written)) == {:ok, read}
    end
  end

  describe "a suffix that cannot be read" do
    test "a zone after a tag is said to be out of order" do
      assert {:error, %ParseError{reason: {:zone_after_tags, "Europe/Paris"}}} =
               Tempo.from_iso8601("2026-06-15[u-ca=hebrew][Europe/Paris]")
    end

    test "a bracket that is not closed, is empty, or holds an offset with no colon" do
      for text <- ["2026-06-15[nonsense", "2026-06-15[]", "2026-06-15T10:00[+0200]"] do
        assert {^text, {:error, %ParseError{reason: "text after the value"}}} =
                 {text, Tempo.from_iso8601(text)}
      end
    end

    test "a critical tag Tempo cannot act on is an error, and an elective one is kept" do
      assert {:error, %ParseError{reason: {:critical, "x-foo=bar"}}} =
               Tempo.from_iso8601("2026-06-15[!x-foo=bar]")

      assert {:ok, tagged} = Tempo.from_iso8601("2026-06-15[x-foo=bar]")
      assert Tempo.metadata(tagged) == %{ixdtf_tags: %{"x-foo" => ["bar"]}}
    end

    test "a calendar no name reads to is an error" do
      assert {:error, %ParseError{reason: {:calendar, _name}}} =
               Tempo.from_iso8601("2026-06-15[u-ca=klingon]")
    end
  end
end
