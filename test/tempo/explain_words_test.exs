defmodule Tempo.ExplainWordsTest do
  @moduledoc """
  What `Tempo.explain/1` says of a time of day, of qualifiers and of a
  domain.

  A time written to its second was worded to its minute, so
  `2026-06-15T10:30:15` was "at 10:30" with a span from 10:30 to 10:30, and
  a time shift (`Z`, `-05:00`) was not said at all. Qualifiers of single
  components were printed as the map that holds them, and a domain that is
  only a filter was called exclusions.

  The measure for a time is Elixir's own `NaiveDateTime`: the second a
  value names and the second after it, as ISO 8601 writes them.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  @seconds [
    ~N[2026-06-15 10:30:15],
    ~N[2026-06-15 00:00:00],
    ~N[2026-06-15 10:30:59],
    ~N[2026-12-31 23:59:59],
    ~N[2024-02-29 12:00:01]
  ]

  defp explain(text), do: Tempo.explain(Tempo.from_iso8601!(text))

  defp clock(%NaiveDateTime{} = moment), do: Calendar.strftime(moment, "%H:%M:%S")

  describe "a time written to its second" do
    test "is worded to the second, and spans it" do
      for moment <- @seconds do
        written = NaiveDateTime.to_iso8601(moment)
        next = moment |> NaiveDateTime.add(1, :second) |> NaiveDateTime.to_iso8601()
        explained = explain(written)

        assert {written, explained =~ " at #{clock(moment)}.\n"} == {written, true}
        assert {written, explained =~ "Span: [#{written}, #{next})."} == {written, true}
      end
    end

    test "with no date is the time of day to its second" do
      explained = explain("T10:30:15")

      assert explained =~ "The time-of-day 10:30:15 (unanchored"
      assert explained =~ "Span: [T10:30:15, T10:30:16)."
    end

    test "keeps the fraction of a second it is written with" do
      for {text, digits, next} <- [
            {"2026-06-15T10:30:15.25", "15.25", "15.26"},
            {"2026-06-15T10:30:15,5", "15.5", "15.6"},
            {"2026-06-15T10:30:15.001", "15.001", "15.002"}
          ] do
        explained = explain(text)

        assert {text, explained =~ " at 10:30:#{digits}.\n"} == {text, true}

        assert {text,
                explained =~ "Span: [2026-06-15T10:30:#{digits}, 2026-06-15T10:30:#{next})."} ==
                 {text, true}
      end
    end

    test "is each of its seconds where it holds several" do
      assert explain("2026Y6M15DT10H30M{15,45}S") =~ "June 15, 2026 at 10:30:15 and 10:30:45.\n"

      assert explain("2026Y6M15DT10H{0,30}M{15,45}S") =~
               "June 15, 2026 at 10:00:15, 10:00:45, 10:30:15, and 10:30:45.\n"
    end

    test "is said at the ends of an interval and the start of a recurrence" do
      interval = explain("2026-06-15T10:30:15/2026-06-15T10:30:45")

      assert interval =~ "From: 2026-06-15T10:30:15."
      assert interval =~ "To:   2026-06-15T10:30:45 (exclusive"

      assert explain("R3/2026-06-15T10:30:15/PT30S") =~ "Starting: 2026-06-15T10:30:15."
    end

    test "is worded to the minute where it is written to one, as it was" do
      explained = explain("2026-06-15T10:30")

      assert explained =~ "June 15, 2026 at 10:30.\n"
      assert explained =~ "Span: [2026-06-15T10:30, 2026-06-15T10:31)."
      assert explain("2026-06-15T10") =~ "Span: [2026-06-15T10:00, 2026-06-15T11:00)."
    end
  end

  describe "a time shift" do
    test "is said, and written at each end of the span" do
      for {text, shift, line} <- [
            {"2026-06-15T10:30:15Z", "Z", "Time shift: none, the time is in UTC (`Z`)."},
            {"2026-06-15T10:30:15-05:00", "-05:00", "Time shift: -05:00 from UTC."},
            {"2026-06-15T10:30:15+05:30", "+05:30", "Time shift: +05:30 from UTC."},
            {"2026-06-15T10:30:15-00:30", "-00:30", "Time shift: -00:30 from UTC."},
            {"2026-06-15T10:30:15+00:00", "+00:00", "Time shift: +00:00 from UTC."}
          ] do
        explained = explain(text)

        assert {text, explained =~ line} == {text, true}

        assert {text,
                explained =~ "Span: [2026-06-15T10:30:15#{shift}, 2026-06-15T10:30:16#{shift})."} ==
                 {text, true}
      end
    end

    test "is said beside a zone, and of a time with no date" do
      zoned = explain("2026-06-15T10:30+02:00[Europe/Paris]")

      assert zoned =~ "Time shift: +02:00 from UTC.\nTimezone: Europe/Paris."
      assert explain("T10:30Z") =~ "Span: [T10:30Z, T10:31Z).\nTime shift: none"
    end

    test "is written at the ends of an interval" do
      explained = explain("2026-06-15T10:30Z/2026-06-15T11:30Z")

      assert explained =~ "From: 2026-06-15T10:30Z."
      assert explained =~ "To:   2026-06-15T11:30Z (exclusive"
    end

    test "is not said of a value that has none" do
      refute explain("2026-06-15T10:30") =~ "Time shift"
      refute explain("2026-06-15T10[America/New_York]") =~ "Time shift"
    end
  end

  describe "qualifiers of single components" do
    test "are worded, each with the components that carry it in the order they are written" do
      assert explain("2026-06~-15") =~
               "Per-component qualifications: the year and the month approximate (EDTF ~)."

      assert explain("2026?-06-15~") =~
               "Per-component qualifications: the year both uncertain and approximate (EDTF %); " <>
                 "the month and the day approximate (EDTF ~)."
    end

    test "are the whole value's where every component carries the same" do
      assert explain("2026-06-15?") =~ "Expression-level qualification: uncertain (EDTF ?)."
      refute explain("2026-06-15?") =~ "Per-component"
    end
  end

  describe "the domain of a recurrence" do
    test "that is only a filter is said to be one" do
      for {filter, words} <- [
            {"o", "odd years only"},
            {"e", "even years only"},
            {"l", "leap years only"},
            {"c", "common (non-leap) years only"}
          ] do
        explained = explain("R/..#{filter}/P1Y/FL6M15DN")

        assert {filter, explained =~ "Domain: every period (#{words})."} == {filter, true}

        assert {filter, explained =~ "A filter only — supply a `:within` window"} ==
                 {filter, true}

        refute explained =~ "Exclusions only"
      end
    end

    test "that is only exclusions, and one with members, is said as it was" do
      assert explain("R/^2026Y/P1Y/FL6MN") =~ "Exclusions only — supply a `:within` window"

      assert Tempo.explain(~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL6M15DN") =~
               "The domain's members are the window"
    end
  end
end
