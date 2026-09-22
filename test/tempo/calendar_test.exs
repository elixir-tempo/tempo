defmodule Tempo.CalendarTest do
  use ExUnit.Case, async: true

  alias Tempo.{Interval, IntervalSet}

  # The Gregorian ISO-8601 day each interval in a materialised set falls on.
  defp gregorian_days(set) do
    set
    |> IntervalSet.to_list()
    |> Enum.map(fn interval ->
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      {:ok, gregorian} = Date.convert(date, Calendar.ISO)
      Date.to_iso8601(gregorian)
    end)
  end

  # The IXDTF `[u-ca=NAME]` suffix, when no explicit calendar
  # argument is given to `Tempo.from_iso8601/1`, resolves to a
  # concrete `Calendrical.*` module via
  # `Calendrical.calendar_from_cldr_calendar_type/1` and the
  # resulting Tempo struct's `:calendar` field is swapped
  # accordingly. Parsing and validation then use that calendar's
  # domain rules.

  describe "Tempo.from_iso8601/1 with [u-ca=NAME] suffix" do
    test "[u-ca=hebrew] swaps the struct's calendar to Calendrical.Hebrew" do
      {:ok, tempo} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
      assert tempo.calendar == Calendrical.Hebrew
      # The extended metadata still captures the raw tag value.
      assert tempo.extended.calendar == :hebrew
    end

    test "Islamic variants resolve to their nested Calendrical modules" do
      {:ok, observational} = Tempo.from_iso8601("1447-01-15[u-ca=islamic]")
      assert observational.calendar == Calendrical.Islamic.Observational

      {:ok, umalqura} = Tempo.from_iso8601("1447-01-15[u-ca=islamic-umalqura]")
      assert umalqura.calendar == Calendrical.Islamic.UmmAlQura

      {:ok, civil} = Tempo.from_iso8601("1447-01-15[u-ca=islamic-civil]")
      assert civil.calendar == Calendrical.Islamic.Civil
    end

    test "the CLDR type name ethiopic-amete-alem is not a u-ca identifier (use ethioaa)" do
      # IXDTF/TR35 u-ca values are Unicode Calendar Identifiers (`ethioaa`),
      # not CLDR's internal calendar-type names. An unknown, non-critical
      # suffix is ignored per IXDTF §3.3, so the calendar stays the default.
      {:ok, tempo} = Tempo.from_iso8601("2019-05-10[u-ca=ethiopic-amete-alem]")
      assert tempo.calendar == Calendrical.Gregorian
    end

    test "the ethioaa BCP 47 alias works" do
      {:ok, tempo} = Tempo.from_iso8601("2019-05-10[u-ca=ethioaa]")
      assert tempo.calendar == Calendrical.Ethiopic.AmeteAlem
    end

    test "[u-ca=gregory] is accepted as an alias for :gregorian" do
      {:ok, tempo} = Tempo.from_iso8601("2026-06-15[u-ca=gregory]")
      assert tempo.calendar == Calendrical.Gregorian
      assert tempo.extended.calendar == :gregorian
    end

    test "Persian, Buddhist, and other simple calendars resolve directly" do
      {:ok, persian} = Tempo.from_iso8601("1403-10-20[u-ca=persian]")
      assert persian.calendar == Calendrical.Persian

      {:ok, buddhist} = Tempo.from_iso8601("2569-06-15[u-ca=buddhist]")
      assert buddhist.calendar == Calendrical.Buddhist
    end

    test "[u-ca=julian] resolves the non-CLDR Julian calendar via Calendrical" do
      # CLDR/BCP 47 has no `julian` identifier, so Localize never validates it.
      # Calendrical implements the calendar and registers it in
      # `additional_calendars/0`, which the resolver consults ahead of CLDR.
      {:ok, tempo} = Tempo.from_iso8601("1900-12-25[u-ca=julian]")
      assert tempo.calendar == Calendrical.Julian
      assert tempo.extended.calendar == :julian
    end

    test "[u-ca=julian] round-trips losslessly through to_iso8601/1" do
      iso = "R/2025Y12M25D[u-ca=julian]/P1Y"
      {:ok, tempo} = Tempo.from_iso8601(iso)
      assert Tempo.to_iso8601(tempo) == iso
    end

    test "a Julian recurrence materialises to the Gregorian day it falls on" do
      # Orthodox Christmas: Julian 25 December, projected onto Gregorian 2026.
      {:ok, recurrence} = Tempo.from_iso8601("R/2025Y12M25D[u-ca=julian]/P1Y")
      {:ok, set} = Tempo.to_interval(recurrence, bound: Tempo.from_iso8601!("2026Y"))

      assert gregorian_days(set) == ["2026-01-07"]
    end

    test "without a u-ca tag the default calendar is Gregorian" do
      {:ok, tempo} = Tempo.from_iso8601("2026-06-15")
      assert tempo.calendar == Calendrical.Gregorian
    end

    test "critical [!u-ca=fake] fails with a clear error" do
      assert {:error, message} =
               Tempo.from_iso8601("2022-06-15[!u-ca=fakecalendar]")

      assert Exception.message(message) =~ "Unknown calendar identifier"
      assert Exception.message(message) =~ "fakecalendar"
    end

    test "non-critical [u-ca=fake] is silently ignored" do
      # Per RFC: non-critical unrecognised tags must not fail parse.
      assert {:ok, tempo} =
               Tempo.from_iso8601("2026-06-15[u-ca=fakecalendar]")

      assert tempo.calendar == Calendrical.Gregorian
    end
  end

  # The natural way to write a calendar-specific holiday: the `[u-ca=…]` suffix
  # on the whole recurrence, applying to the selection, rather than only to a
  # written-out anchor date. The selection resolves in that calendar and the
  # bound projects it onto the Gregorian year.
  describe "a [u-ca=NAME] suffix on a whole recurrence expression" do
    test "applies the calendar to the selection, not just a written-out anchor" do
      {:ok, orthodox_christmas} = Tempo.from_iso8601("R/../P1Y/FL12M25DN[u-ca=julian]")
      assert orthodox_christmas.repeat_rule.calendar == Calendrical.Julian

      {:ok, set} = Tempo.to_interval(orthodox_christmas, bound: Tempo.from_iso8601!("2026Y"))
      assert gregorian_days(set) == ["2026-01-07"]
    end

    test "projects each calendar onto the Gregorian day it falls on in 2026" do
      cases = [
        {"R/../P1Y/FL10M1DN[u-ca=islamic]", "2026-03-20"},
        {"R/../P1Y/FL1M1DN[u-ca=persian]", "2026-03-21"},
        {"R/../P1Y/FL4M29DN[u-ca=coptic]", "2026-01-07"}
      ]

      for {iso, gregorian} <- cases do
        {:ok, recurrence} = Tempo.from_iso8601(iso)
        {:ok, set} = Tempo.to_interval(recurrence, bound: Tempo.from_iso8601!("2026Y"))
        assert gregorian_days(set) == [gregorian], "#{iso} should fall on #{gregorian}"
      end
    end

    test "each materialised occurrence is tagged with its calendar, like a written anchor" do
      # A synthesised anchor still yields self-describing `[u-ca=cal]` values, so
      # a materialised occurrence is struct-equal to the date written by hand.
      {:ok, orthodox_christmas} = Tempo.from_iso8601("R/../P1Y/FL12M25DN[u-ca=julian]")
      {:ok, set} = Tempo.to_interval(orthodox_christmas, bound: Tempo.from_iso8601!("2025Y"))
      [occurrence] = IntervalSet.to_list(set)

      assert Interval.from(occurrence) == Tempo.from_iso8601!("2024Y12M25D[u-ca=julian]")
    end

    test "a lunar date that falls twice in one Gregorian year yields both" do
      # Islamic New Year fell twice in 2008 — 10 January and 29 December —
      # because the Hijri year is ~11 days shorter than the Gregorian one.
      {:ok, islamic_new_year} = Tempo.from_iso8601("R/../P1Y/FL1M1DN[u-ca=islamic]")
      {:ok, set} = Tempo.to_interval(islamic_new_year, bound: Tempo.from_iso8601!("2008Y"))

      assert gregorian_days(set) == ["2008-01-10", "2008-12-29"]
    end

    test "round-trips losslessly, keeping the suffix on the whole expression" do
      for iso <- [
            "R/../P1Y/FL12M25DN[u-ca=julian]",
            "R/../P1Y/FL10M1DN[u-ca=islamic]",
            "R/../P1Y/FL1M1DN[u-ca=persian]"
          ] do
        {:ok, recurrence} = Tempo.from_iso8601(iso)
        assert Tempo.to_iso8601(recurrence) == iso
      end
    end

    test "a Gregorian recurrence is unaffected — no suffix, its own day" do
      {:ok, christmas} = Tempo.from_iso8601("R/../P1Y/FL12M25DN")
      assert Tempo.to_iso8601(christmas) == "R/../P1Y/FL12M25DN"

      {:ok, set} = Tempo.to_interval(christmas, bound: Tempo.from_iso8601!("2026Y"))
      assert gregorian_days(set) == ["2026-12-25"]
    end
  end

  # A lunisolar intercalary month, written `<n>+M` — the leap month following
  # traditional month `n`. A Tempo extension (ISO 8601 has no such concept), it
  # is an input convenience only: it resolves to the ordinal month and renders
  # ordinal, so `%Date{}` and round-trips stay Elixir-compatible.
  describe "the `<n>+M` lunisolar leap-month input" do
    test "resolves to the ordinal month and renders ordinal" do
      # Chinese year 4662 carries a leap month 6 (閏6月) at ordinal position 7.
      {:ok, tempo} = Tempo.from_iso8601("4662Y6+M1D[u-ca=chinese]")
      assert tempo.time[:month] == 7
      assert Tempo.to_iso8601(tempo) == "4662Y7M1D[u-ca=chinese]"
    end

    test "a regular month is unaffected" do
      {:ok, tempo} = Tempo.from_iso8601("4662Y6M1D[u-ca=chinese]")
      assert tempo.time[:month] == 6
      assert Tempo.to_iso8601(tempo) == "4662Y6M1D[u-ca=chinese]"
    end

    test "a year with no such leap month is rejected" do
      # 4661 is an ordinary year; 4662's leap month follows month 6, not 7.
      assert {:error, _} = Tempo.from_iso8601("4661Y6+M1D[u-ca=chinese]")
      assert {:error, _} = Tempo.from_iso8601("4662Y7+M1D[u-ca=chinese]")
    end

    test "a non-lunisolar calendar is rejected" do
      assert {:error, message} = Tempo.from_iso8601("2026Y6+M1D")
      assert Exception.message(message) =~ "no leap months"
    end

    test "a leap-year calendar without leap months (Islamic) is rejected" do
      # The Islamic calendars have leap *years* — an extra day in the final
      # month — not leap *months*, so there is no `<n>+M` to name; every leap
      # month, valid or not, is rejected the same clean way.
      for iso <- [
            "1447Y6+M1D[u-ca=islamic-umalqura]",
            "1447Y12+M1D[u-ca=islamic]",
            "1447Y99+M1D[u-ca=islamic-civil]"
          ] do
        assert {:error, message} = Tempo.from_iso8601(iso)
        assert Exception.message(message) =~ "no leap months"
      end
    end
  end

  # Tempo borrowed the `[…]` suffix from IXDTF (which uses `[u-ca=value]`),
  # but the value is a BCP 47 Unicode Calendar Identifier, whose native form
  # is hyphenated (`u-ca-hebrew`). So Tempo reads BOTH separators (liberal in)
  # and emits the IXDTF `=` form (conservative out), via the Localize U parser.
  describe "u extension: parse `=` and `-`, emit `=`" do
    test "the hyphen (BCP 47) form parses" do
      {:ok, tempo} = Tempo.from_iso8601("2020-06-15[u-ca-hebrew]")
      assert tempo.calendar == Calendrical.Hebrew

      {:ok, tempo} = Tempo.from_iso8601("2020-06-15[u-ca-islamic-civil]")
      assert tempo.calendar == Calendrical.Islamic.Civil
    end

    test "a hyphen-form u extension is accepted after a zone" do
      {:ok, tempo} = Tempo.from_iso8601("2020-06-15T10:00[Europe/Paris][u-ca-hebrew]")
      assert tempo.calendar == Calendrical.Hebrew
    end

    test "deprecated aliases fold in either separator" do
      for string <- ["2020-06-15[u-ca=islamicc]", "2020-06-15[u-ca-islamicc]"] do
        {:ok, tempo} = Tempo.from_iso8601(string)
        assert tempo.calendar == Calendrical.Islamic.Civil
      end
    end

    test "generation always uses `=` and the preferred identifier" do
      # Parsed via the hyphen + deprecated alias, emitted as canonical `=`.
      {:ok, tempo} = Tempo.from_iso8601("2020-06-15[u-ca-islamicc]")
      assert Tempo.to_iso8601(tempo) == "2020Y6M15D[u-ca=islamic-civil]"

      # `:gregorian` encodes to the preferred `gregory`, not a naive spelling.
      {:ok, gregory} = Tempo.from_iso8601("2020-06-15[u-ca=gregorian]")
      {:ok, hebrew} = Tempo.from_iso8601("2020-06-15[u-ca-hebrew]")
      assert Tempo.to_iso8601(hebrew) == "2020Y6M15D[u-ca=hebrew]"
      assert gregory.calendar == Calendrical.Gregorian
    end

    test "the hyphen form round-trips through generation" do
      {:ok, tempo} = Tempo.from_iso8601("2020-06-15[u-ca-hebrew]")
      {:ok, reparsed} = Tempo.from_iso8601(Tempo.to_iso8601(tempo))
      assert reparsed.calendar == Calendrical.Hebrew
    end
  end

  describe "Tempo.from_iso8601/2 precedence: explicit calendar wins over IXDTF" do
    test "explicit Gregorian overrides [u-ca=hebrew]" do
      {:ok, tempo} = Tempo.from_iso8601("2022-06-15[u-ca=hebrew]", Calendrical.Gregorian)
      assert tempo.calendar == Calendrical.Gregorian
      # The hint is still recorded on extended for inspection.
      assert tempo.extended.calendar == :hebrew
    end

    test "explicit Hebrew stays Hebrew without any IXDTF suffix" do
      {:ok, tempo} = Tempo.from_iso8601("5786-10-30", Calendrical.Hebrew)
      assert tempo.calendar == Calendrical.Hebrew
    end
  end

  describe "cross-calendar comparisons via IXDTF" do
    test "overlaps?/2 works between an IXDTF-Hebrew date and a Gregorian one" do
      {:ok, hebrew_date} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
      {:ok, gregorian_date} = Tempo.from_iso8601("2026-06-15")

      # Whether they overlap depends on the calendar conversion;
      # the point is that the call succeeds and produces a boolean
      # (not an error from calendar-mismatch handling).
      assert is_boolean(Tempo.overlaps?(hebrew_date, gregorian_date))
    end
  end

  describe "Hebrew calendar — Cheshvan 30 year-by-year" do
    # Cheshvan (month 2) has 29 or 30 days depending on whether
    # the Hebrew year is `chaserah` (defective, 29), `kesidrah`
    # (regular, 29), or `shlemah` (complete, 30). Calendrical's
    # `days_in_month/2` is the source of truth.

    test "5784 — Cheshvan has 29 days (rejects day 30)" do
      assert {:error, _} = Tempo.from_iso8601("5784-02-30[u-ca=hebrew]")
    end

    test "5785 — Cheshvan has 30 days (accepts day 30)" do
      assert {:ok, _} = Tempo.from_iso8601("5785-02-30[u-ca=hebrew]")
    end

    test "5786 — Cheshvan has 29 days" do
      assert {:error, _} = Tempo.from_iso8601("5786-02-30[u-ca=hebrew]")
    end

    test "5787 — Cheshvan has 30 days" do
      assert {:ok, _} = Tempo.from_iso8601("5787-02-30[u-ca=hebrew]")
    end

    test "5788 — Cheshvan has 30 days" do
      assert {:ok, _} = Tempo.from_iso8601("5788-02-30[u-ca=hebrew]")
    end

    test "Cheshvan 29 is always valid (minimum month length)" do
      for year <- [5784, 5785, 5786, 5787, 5788] do
        assert {:ok, _} = Tempo.from_iso8601("#{year}-02-29[u-ca=hebrew]"),
               "Cheshvan 29 should be valid in year #{year}"
      end
    end
  end

  describe "Tempo.from_iso8601/2 with an unusable calendar module" do
    test "a concrete Islamic calendar parses" do
      assert {:ok, _} = Tempo.from_iso8601("1446-09", Calendrical.Islamic.Civil)
      assert {:ok, _} = Tempo.from_iso8601("2025-06-15", Calendrical.Gregorian)
    end

    test "a namespace module returns an error rather than raising" do
      # `Calendrical.Islamic` is a namespace, not a calendar — its
      # concrete forms are `.Civil`, `.UmmAlQura`, etc. Passing it used
      # to crash with UndefinedFunctionError deep in validation.
      assert {:error, %Tempo.InvalidCalendarError{calendar: Calendrical.Islamic}} =
               Tempo.from_iso8601("1446-09", Calendrical.Islamic)
    end

    test "the bang variant raises that exception cleanly" do
      assert_raise Tempo.InvalidCalendarError, fn ->
        Tempo.from_iso8601!("1446-09", Calendrical.Islamic)
      end
    end
  end
end
