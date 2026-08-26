defmodule Tempo.FormatTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  doctest Tempo, only: [to_string: 2]

  # The CLDR range separator is a thin-space + en-dash + thin-space.
  @en_dash_sep "\u2009\u2013\u2009"

  # CLDR separates a time from its meridiem with a narrow no-break
  # space, not an ordinary one.
  @nbsp "\u202F"

  describe "Tempo.to_string/1 — Rule B expansion" do
    test "year resolution expands to Jan–Dec (closed interval)" do
      assert Tempo.to_string(~o"2026") == "Jan#{@en_dash_sep}Dec 2026"
    end

    test "year :long uses full month names" do
      assert Tempo.to_string(~o"2026", format: :long) ==
               "January#{@en_dash_sep}December 2026"
    end

    test "month resolution expands to day 1–N" do
      assert Tempo.to_string(~o"2026-06") == "Jun 1#{@en_dash_sep}30, 2026"
    end

    test "month length follows the calendar (29 in a leap Feb)" do
      assert Tempo.to_string(~o"2024-02") == "Feb 1#{@en_dash_sep}29, 2024"
    end

    test "month length in a common-year Feb is 28" do
      assert Tempo.to_string(~o"2025-02") == "Feb 1#{@en_dash_sep}28, 2025"
    end

    test "day resolution collapses to a single value" do
      assert Tempo.to_string(~o"2026-06-15") == "Jun 15, 2026"
    end

    test "day :long uses full month name" do
      assert Tempo.to_string(~o"2026-06-15", format: :long) == "June 15, 2026"
    end

    test "second resolution collapses to a single datetime" do
      string = Tempo.to_string(~o"2026-06-15T14:30:00")
      assert string =~ "Jun 15, 2026"
      assert string =~ "2:30"
    end
  end

  describe "Tempo.to_string/2 — locale" do
    test "en-GB switches to DMY ordering on day values" do
      assert Tempo.to_string(~o"2026-06-15", format: :long, locale: "en-GB") ==
               "15 June 2026"
    end

    test "de renders German month names" do
      assert Tempo.to_string(~o"2026-06-15", format: :long, locale: "de") ==
               "15. Juni 2026"
    end

    test "year expansion honours the locale" do
      assert Tempo.to_string(~o"2026", locale: "de", format: :long) ==
               "Januar\u2013Dezember 2026"
    end

    test "fr month expansion" do
      assert Tempo.to_string(~o"2026-06", locale: "fr") =~ "juin"
    end
  end

  describe "Tempo.to_string/2 on Tempo.Interval — same rule" do
    test "day-resolution interval collapses to a single day when from == to − 1 day" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06-15")
      assert Tempo.to_string(iv) == "Jun 15, 2026"
    end

    test "month-resolution interval renders the day range of the month" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      assert Tempo.to_string(iv) == "Jun 1#{@en_dash_sep}30, 2026"
    end

    test "year-resolution interval renders Jan–Dec" do
      {:ok, iv} = Tempo.to_interval(~o"2026")
      assert Tempo.to_string(iv) == "Jan#{@en_dash_sep}Dec 2026"
    end

    test "multi-year range — union preserves members; coalesce for a single span" do
      # Member-preserving union keeps both years distinct; the
      # IntervalSet renders them as two comma-separated spans. For
      # the "Jan 2022 – Dec 2023" single-span rendering, coalesce
      # explicitly first.
      {:ok, yr_iv} = Tempo.union(~o"2022", ~o"2023")
      coalesced = IntervalSet.coalesce(yr_iv)

      assert Tempo.to_string(coalesced) == "Jan 2022#{@en_dash_sep}Dec 2023"
    end

    test "Tempo.to_string(tempo) matches Tempo.to_string(to_interval(tempo)) — year" do
      tempo = ~o"2026"
      {:ok, iv} = Tempo.to_interval(tempo)
      assert Tempo.to_string(tempo) == Tempo.to_string(iv)
    end

    test "Tempo.to_string(tempo) matches Tempo.to_string(to_interval(tempo)) — month" do
      tempo = ~o"2026-06"
      {:ok, iv} = Tempo.to_interval(tempo)
      assert Tempo.to_string(tempo) == Tempo.to_string(iv)
    end

    test "Tempo.to_string(tempo) matches Tempo.to_string(to_interval(tempo)) — day" do
      # The materialised interval has T00H endpoints; the
      # midnight-to-midnight trunc in Tempo.Format ensures the
      # display resolution matches the source Tempo's.
      tempo = ~o"2026-06-15"
      {:ok, iv} = Tempo.to_interval(tempo)
      assert Tempo.to_string(tempo) == Tempo.to_string(iv)
    end

    test "explicit hour-level interval preserves hour display" do
      iv = %Tempo.Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T18"}
      string = Tempo.to_string(iv)
      assert string =~ "Jun 15, 2026"
      assert string =~ "10"
      assert string =~ "5"
    end

    test "month :long uses the locale's long date format on each endpoint" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      string = Tempo.to_string(iv, format: :long)
      # Localize's :long for the :date style resolves to the locale's
      # :long date skeleton (yMMMMd for en) on each endpoint, joined
      # via the locale's interval-fallback separator. The result is
      # "June 1, 2026 – June 30, 2026" — full month name, no weekday.
      assert string =~ "June 1, 2026"
      assert string =~ "June 30, 2026"
    end

    test "month :full uses the day-of-week-and-month format" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      string = Tempo.to_string(iv, format: :full)
      # Localize's :full for the :date style resolves to the locale's
      # :full date skeleton (yMMMMEEEEd for en), which includes the
      # full weekday name, e.g. "Monday, June 1, 2026 – Tuesday, June 30, 2026".
      assert string =~ "Monday"
      assert string =~ "Tuesday"
      assert string =~ "June"
      assert string =~ "30, 2026"
    end
  end

  describe "Tempo.to_string/2 on Tempo.IntervalSet" do
    test "joins members with ', '" do
      {:ok, set} = Tempo.union(~o"2022", ~o"2024")

      assert Tempo.to_string(set) ==
               "Jan#{@en_dash_sep}Dec 2022, Jan#{@en_dash_sep}Dec 2024"
    end
  end

  describe "String.Chars protocol" do
    test "Tempo interpolates into a string" do
      assert "Date: #{~o"2026-06-15"}" == "Date: Jun 15, 2026"
    end

    test "Year interpolation expands to Jan–Dec" do
      assert "#{~o"2026"}" == "Jan#{@en_dash_sep}Dec 2026"
    end

    test "Tempo.Interval interpolates" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      assert "#{iv}" == "Jun 1#{@en_dash_sep}30, 2026"
    end

    test "Tempo.IntervalSet interpolates" do
      {:ok, set} = Tempo.union(~o"2022", ~o"2024")
      assert "#{set}" =~ "2022"
      assert "#{set}" =~ "2024"
    end

    test "to_string/1 on Tempo equals Tempo.to_string/1" do
      tempo = ~o"2026-06-15"
      assert to_string(tempo) == Tempo.to_string(tempo)
    end
  end

  describe "Tempo.to_string/2 on Tempo.Duration — Localize-backed" do
    test "year + month duration" do
      assert Tempo.to_string(~o"P1Y6M") == "1 year, 6 months"
    end

    test "day + hour duration" do
      assert Tempo.to_string(~o"P3DT2H") == "3 days, 2 hours"
    end

    test "weeks normalise to days" do
      assert Tempo.to_string(~o"P2W3D") == "17 days"
    end

    test "zero duration renders as `0 seconds`" do
      assert Tempo.to_string(~o"P0D") == "0 seconds"
    end

    test ":format short abbreviates" do
      assert Tempo.to_string(~o"P3DT2H", format: :short) == "3 days, 2 hr"
    end

    test "locale honoured" do
      assert Tempo.to_string(~o"P1Y6M", locale: :de) == "1 Jahr, 6 Monate"
    end

    test "String.Chars interpolates duration" do
      assert "Elapsed: #{~o"P1Y6M"}" == "Elapsed: 1 year, 6 months"
    end
  end

  describe "Inspect remains unchanged" do
    test "inspect returns the sigil form, not the localized form" do
      assert inspect(~o"2026-06-15") == ~s|~o"2026Y6M15D"|
      assert inspect(~o"2026") == ~s|~o"2026Y"|
    end
  end

  describe "Tempo.to_string/2 — every resolution against every format" do
    # The whole space, because the failures here were not one bug but
    # three, and each hid in a different corner of it:
    #
    #   * a skeleton naming a field the value lacks rendered the
    #     separator with nothing around it — `:hms` on a minute value
    #     gave "10:45:", `:hm` on a date gave ": ";
    #   * a skeleton naming an axis the value lacks left that half of
    #     the datetime pattern empty — ": , 10:45 am";
    #   * a skeleton on a year or month raised, because Rule B expanded
    #     it to an interval and interval formatting takes only widths.
    #
    # Nothing below may render an empty field, and nothing may raise.
    @values [
      {"year", ~o"2025"},
      {"month", ~o"2025-08"},
      {"day", ~o"2025-08-28"},
      {"datetime hour", ~o"2025-08-28T10"},
      {"datetime minute", ~o"2025-08-28T10:45"},
      {"datetime second", ~o"2025-08-28T10:45:30"},
      {"time hour", ~o"T10"},
      {"time minute", ~o"T10:45"},
      {"time second", ~o"T10:45:30"}
    ]

    @formats [nil, :short, :medium, :long, :full, :y, :yMMM, :yMMMd, :h, :hm, :hms]

    test "no combination raises" do
      for {label, value} <- @values, format <- @formats do
        options = if format, do: [format: format, locale: :en], else: [locale: :en]

        assert is_binary(Tempo.to_string(value, options)),
               "#{label} with #{inspect(format)} did not return a string"
      end
    end

    test "no combination renders an empty field" do
      # An empty field shows up as a separator with nothing before or
      # after it: a leading ":", a doubled "::", or a stray ", ".
      for {label, value} <- @values, format <- @formats do
        options = if format, do: [format: format, locale: :en], else: [locale: :en]
        rendered = Tempo.to_string(value, options)

        refute rendered =~ ~r/(^|\s):/,
               "#{label} with #{inspect(format)} rendered an empty leading field: #{inspect(rendered)}"

        refute rendered =~ "::",
               "#{label} with #{inspect(format)} rendered an empty field: #{inspect(rendered)}"

        refute rendered =~ ~r/:\s*$|,\s*$/,
               "#{label} with #{inspect(format)} rendered a trailing separator: #{inspect(rendered)}"
      end
    end

    test "a format asking for more precision than the value carries is narrowed" do
      assert Tempo.to_string(~o"2025-08-28T10", format: :hms, locale: :en) == "10#{@nbsp}AM"
      assert Tempo.to_string(~o"2025-08-28T10:45", format: :hms, locale: :en) == "10:45#{@nbsp}AM"
      assert Tempo.to_string(~o"T10", format: :hm, locale: :en) == "10#{@nbsp}AM"
      assert Tempo.to_string(~o"2025-08", format: :yMMMd, locale: :en) == "Aug 2025"
      assert Tempo.to_string(~o"2025", format: :yMMM, locale: :en) == "2025"
    end

    test "a time-only format renders the time of a value that also has a date" do
      assert Tempo.to_string(~o"2025-08-28T10:45", format: :hm, locale: :en) == "10:45#{@nbsp}AM"

      assert Tempo.to_string(~o"2025-08-28T10:45:30", format: :hms, locale: :en) ==
               "10:45:30#{@nbsp}AM"
    end

    test "a date-only format renders the date of a value that also has a time" do
      assert Tempo.to_string(~o"2025-08-28T10:45", format: :yMMMd, locale: :en) == "Aug 28, 2025"
      assert Tempo.to_string(~o"2025-08-28T10:45", format: :y, locale: :en) == "2025"
    end

    test "a format for an axis the value does not have falls back to the value" do
      assert Tempo.to_string(~o"2025-08-28", format: :hm, locale: :en) == "Aug 28, 2025"
      assert Tempo.to_string(~o"T10:45", format: :yMMMd, locale: :en) == "10:45#{@nbsp}AM"
    end

    test "the default still expands a year and a month as closed intervals" do
      assert Tempo.to_string(~o"2026", locale: :en) == "Jan#{@en_dash_sep}Dec 2026"

      assert Tempo.to_string(~o"2026", format: :medium, locale: :en) ==
               "Jan#{@en_dash_sep}Dec 2026"
    end

    test "an explicit skeleton renders the value rather than expanding it" do
      assert Tempo.to_string(~o"2026", format: :y, locale: :en) == "2026"
      assert Tempo.to_string(~o"2026-08", format: :yMMM, locale: :en) == "Aug 2026"
    end

    test "seconds appear only when the value carries them" do
      assert Tempo.to_string(~o"2025-08-28T10:45:30", locale: :en) ==
               "Aug 28, 2025, 10:45:30#{@nbsp}AM"

      refute Tempo.to_string(~o"2025-08-28T10:45", locale: :en) =~ ":30"
      refute Tempo.to_string(~o"2025-08-28T10:45", locale: :en) =~ ":00"
    end
  end
end
