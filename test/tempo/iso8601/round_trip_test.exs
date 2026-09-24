defmodule Tempo.Iso8601.RoundTripTest do
  use ExUnit.Case, async: true

  # One representative value per ISO 8601 / ISO 8601-2 / IXDTF / project-specific
  # token, drawn from `guides/iso8601-conformance.md`. The guarantee under test:
  # parsing a value and then re-parsing the ISO 8601 string that `inspect/1`
  # shows inside `~o"…"` yields the *identical* value — no component silently
  # dropped, mangled, or made unparseable.
  #
  # This is the gate the ordinal-`BYDAY` (`1K2I`) and IXDTF numeric-offset
  # (`[+08:45]`) round-trip bugs slipped through: inspect-stability on its own
  # never proved that the rendered form re-parses to the same value. Every valid
  # token needs at least one case here.
  #
  # Deliberately excluded (they are not valid `%Tempo{}` values, so there is
  # nothing to round-trip): leap seconds (`23:59:60`, rejected — see
  # `leap_second_test.exs`) and the deprecated truncated month-day forms
  # (`--06-15`, `--0615`). The plain `06-15` month-day is covered below.
  @cases [
    # --- ISO 8601 Part 1 ---
    {"year", "2022"},
    {"year — negative", "-2000"},
    {"year — zero", "0000"},
    {"year — expanded", "+002022"},
    {"year-month", "2022-06"},
    {"year-month-day", "2022-06-15"},
    {"ordinal date", "2022-166"},
    {"week date", "2022-W24"},
    {"week date with day", "2022-W24-3"},
    {"month-day", "06-15"},
    {"time — hour", "T10"},
    {"time — hour:minute", "T10:30"},
    {"time — hour:minute:second", "T10:30:00"},
    {"fractional seconds", "T10:30:00.5"},
    {"zone — Z (UTC)", "2022-06-15T10:30:00Z"},
    {"zone — numeric offset", "2022-06-15T10:30:00+05:30"},
    {"duration — calendar", "P1Y"},
    {"duration — time", "PT30M"},
    {"duration — full", "P3Y6M4DT12H30M5S"},
    {"duration — negative", "-P100D"},
    {"interval — fixed endpoints", "2022-01/2022-06"},
    {"interval — duration on right", "2022-01-01/P1Y"},
    {"interval — duration on left", "P1Y/2022-12-31"},
    {"recurring — unbounded", "R/2022-01/P1M"},
    {"recurring — bounded count", "R5/2022-01/P1M"},
    {"recurring — unanchored (no start)", "R/../P1W"},
    {"recurring — unanchored with weekday+time selection", "R/../P1W/FL5KT17H0MN"},

    # --- ISO 8601-2 Part 2 ---
    {"mask — decade", "156X"},
    {"mask — month", "2022-XX"},
    {"mask — day", "1985-XX-XX"},
    {"mask — significant block", "X*Y12M28D"},
    {"qualifier — uncertain", "2022?"},
    {"qualifier — approximate", "2022~"},
    {"qualifier — both", "2022%"},
    {"component qualifier — group", "2004-06~-11"},
    {"component qualifier — individual", "2004-?06-11"},
    {"component qualifier — leading", "?2022-06-15"},
    {"per-endpoint qualifier", "1984?/2004~"},
    {"open interval — right", "1985/.."},
    {"open interval — left", "../1985"},
    {"open interval — both", "../.."},
    {"set — all of", "{1960,1961,1962}"},
    {"set — all of, range", "{1960..1970}"},
    {"set — one of", "[1984,1986,1988]"},
    {"set — one of, range", "[1667..1672]"},
    {"group", "5G10DU"},
    {"group — nested", "2018Y4G60DU6D"},
    {"group — days", "2022Y3G4DU"},
    {"selection — month/weekday", "2018Y3ML1KN"},
    {"selection — ordinal BYDAY (2nd Monday)", "R/2025-01-01/P1M/FL1K2IN"},
    {"selection — weekday+instance (postfix)", "R/2018-09-05/P1D/F1YL9M3K1IN"},
    {"selection — day-of-year (BYYEARDAY)", "R/2025-01-01/P1Y/FL100ON"},
    {"selection — consolidated weekday range", "R/2025-01-01/P1W/FL{1..5}KN"},
    # Set-position is the ISO 8601-2 §12.9 position `I`. WKST has no ISO form, so
    # it takes the Tempo project-specific lowercase designator `q` (week start).
    {"selection — set-position (I, ISO §12.9)", "R/2025-01-01/P1M/FL1K-1IN"},
    {"selection — week-start (q, Tempo ext.)", "R/2025-01-01/P1W/FL1K7qN"},
    {"season — meteorological", "2022-21"},
    {"season — astronomical", "2022-25"},
    {"quarter", "2022-33"},
    {"quadrimester", "2022-37"},
    {"semestral", "2022-40"},
    {"negative calendar qualifier", "-2004?"},
    {"margin of error", "1200±60Y"},
    {"exponent on year", "2018E3"},
    {"significant digits", "1950S2"},
    {"significant digits + exponent", "Y3388E2S3"},
    {"stepped range", "2023Y{1..-1//2}W"},

    # --- IXDTF (RFC 9557) ---
    {"IXDTF — IANA zone", "2026-06-15T10:00[Europe/Paris]"},
    {"IXDTF — numeric offset", "2026-06-15T10:00[+08:45]"},
    {"IXDTF — numeric offset, negative", "2026-06-15T10:00[-03:30]"},
    {"IXDTF — calendar", "5786-10-30[u-ca=hebrew]"},
    {"IXDTF — generic tag", "2026-06-15[_foo=bar-baz]"},
    {"IXDTF — critical calendar", "5786-10-30[!u-ca=hebrew]"}
  ]

  describe "every ISO 8601 token round-trips through inspect/1" do
    for {category, iso} <- @cases do
      test "#{category} (#{iso})" do
        assert {:ok, value} = Tempo.from_iso8601(unquote(iso))
        assert reparse_inspected(value) == {:ok, value}
      end
    end
  end

  test "the legacy uppercase week-start `Q` is accepted and canonicalised to `q`" do
    # `Q` shipped in 1.6.x before the lowercase-extension convention, so it is
    # still parsed (liberal in) but re-emitted as `q` (conservative out).
    {:ok, from_upper} = Tempo.from_iso8601("R/2025-01-01/P1W/FL1K7QN")
    {:ok, from_lower} = Tempo.from_iso8601("R/2025-01-01/P1W/FL1K7qN")

    assert from_upper == from_lower
    assert Tempo.to_iso8601(from_upper) == "R/2025Y1M1D/P1W/FL1K7qN"
  end

  test "inspect renders the canonical ISO 8601 form as a ~o sigil expression" do
    # Ties the round-trip above to the `~o"…"` form: for the default calendar,
    # `inspect/1` is exactly the canonical `Tempo.to_iso8601/1` string wrapped
    # in the sigil, and re-parsing that inner string restores the value.
    {:ok, value} = Tempo.from_iso8601("2022-06-15")

    assert inspect(value) == ~s(~o"2022Y6M15D")
    assert inspect(value) == ~s(~o") <> Tempo.to_iso8601(value) <> ~s(")
  end

  # Re-parse the ISO 8601 string `inspect/1` renders — inside `~o"…"` for the
  # default calendar, inside `Tempo.from_iso8601!("…", Calendar)` for others.
  # Either way the first double-quoted run is the round-trippable ISO 8601.
  defp reparse_inspected(value) do
    [iso] = Regex.run(~r/"((?:[^"\\]|\\.)*)"/, inspect(value), capture: :all_but_first)
    Tempo.from_iso8601(iso)
  end
end
