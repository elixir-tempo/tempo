defmodule Tempo.Reader.SuffixTest do
  use ExUnit.Case, async: true

  alias Tempo.ParseError

  # A suffix is written once, after the whole expression (law 5). One written
  # inside is refused with an error that says where it belongs.

  @inside [
    "2026-06-15T10:00[Europe/Paris]/2026-06-15T12:00",
    "2026-06-15T10:00[Europe/Paris]/2026-06-15T12:00[Europe/Paris]",
    "{2026-06-15[Europe/Paris],2026-06-16}",
    "{2026-06-15,2026-06-16[u-ca=hebrew]}",
    "[2026-06-15[x-source=hr],2026-06-16]",
    "R/2026-05-30T23:30[America/New_York]/P1D",
    "2026-06-15T10:00[+02:00]/2026-06-15T12:00"
  ]

  for text <- @inside do
    test "#{text} says where its suffix belongs" do
      assert {:error, %ParseError{reason: reason} = error} = Tempo.from_iso8601(unquote(text))
      assert reason == "a zone, a calendar or a tag is written once, after the whole expression"
      assert Exception.message(error) =~ "after the whole expression"
    end
  end

  test "a suffix after the whole expression is every part's" do
    assert {:ok, interval} = Tempo.from_iso8601("2026-06-15T10:00/2026-06-15T12:00[Europe/Paris]")
    assert interval.zone.name == "Europe/Paris"
    assert {:ok, set} = Tempo.from_iso8601("{2026-06-15,2026-06-16}[u-ca=hebrew]")
    assert set.calendar == Calendrical.Hebrew
  end

  test "another error keeps its own reason" do
    assert {:error, %ParseError{reason: "not an end of an interval"}} =
             Tempo.from_iso8601("2026-06-15/20x")

    assert {:ok, _one_of} = Tempo.from_iso8601("[2026,2027]")
  end
end
