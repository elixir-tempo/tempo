defmodule Tempo.FormatTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet
  alias Tempo.RRule

  doctest Tempo, only: [to_string: 2, to_string!: 2]

  # The CLDR range separator is a thin-space + en-dash + thin-space.
  @en_dash_sep "\u2009\u2013\u2009"

  # CLDR separates a time from its meridiem with a narrow no-break
  # space, not an ordinary one.
  @nbsp "\u202F"

  describe "Tempo.to_string/1 — Rule B expansion" do
    test "year resolution expands to Jan–Dec (closed interval)" do
      assert Tempo.to_string(~o"2026") == {:ok, "Jan#{@en_dash_sep}Dec 2026"}
    end

    test "year :long uses full month names" do
      assert Tempo.to_string(~o"2026", format: :long) ==
               {:ok, "January#{@en_dash_sep}December 2026"}
    end

    test "month resolution expands to day 1–N" do
      assert Tempo.to_string(~o"2026-06") == {:ok, "Jun 1#{@en_dash_sep}30, 2026"}
    end

    test "month length follows the calendar (29 in a leap Feb)" do
      assert Tempo.to_string(~o"2024-02") == {:ok, "Feb 1#{@en_dash_sep}29, 2024"}
    end

    test "month length in a common-year Feb is 28" do
      assert Tempo.to_string(~o"2025-02") == {:ok, "Feb 1#{@en_dash_sep}28, 2025"}
    end

    test "a year in another calendar expands to that calendar's first and last months" do
      assert Tempo.to_string(Tempo.from_iso8601!("5786[u-ca=hebrew]")) ==
               {:ok, "Tishri#{@en_dash_sep}Elul 5786"}
    end

    test "day resolution collapses to a single value" do
      assert Tempo.to_string(~o"2026-06-15") == {:ok, "Jun 15, 2026"}
    end

    test "day :long uses full month name" do
      assert Tempo.to_string(~o"2026-06-15", format: :long) == {:ok, "June 15, 2026"}
    end

    test "second resolution collapses to a single datetime" do
      {:ok, string} = Tempo.to_string(~o"2026-06-15T14:30:00")
      assert string =~ "Jun 15, 2026"
      assert string =~ "2:30"
    end
  end

  describe "Tempo.to_string/2 — locale" do
    test "en-GB switches to DMY ordering on day values" do
      assert Tempo.to_string(~o"2026-06-15", format: :long, locale: "en-GB") ==
               {:ok, "15 June 2026"}
    end

    test "de renders German month names" do
      assert Tempo.to_string(~o"2026-06-15", format: :long, locale: "de") ==
               {:ok, "15. Juni 2026"}
    end

    test "year expansion honours the locale" do
      assert Tempo.to_string(~o"2026", locale: "de", format: :long) ==
               {:ok, "Januar\u2013Dezember 2026"}
    end

    test "fr month expansion" do
      {:ok, string} = Tempo.to_string(~o"2026-06", locale: "fr")
      assert string =~ "juin"
    end
  end

  describe "Tempo.to_string/2 on Tempo.Interval — same rule" do
    test "day-resolution interval collapses to a single day when from == to − 1 day" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06-15")
      assert Tempo.to_string(iv) == {:ok, "Jun 15, 2026"}
    end

    test "month-resolution interval renders the day range of the month" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      assert Tempo.to_string(iv) == {:ok, "Jun 1#{@en_dash_sep}30, 2026"}
    end

    test "year-resolution interval renders Jan–Dec" do
      {:ok, iv} = Tempo.to_interval(~o"2026")
      assert Tempo.to_string(iv) == {:ok, "Jan#{@en_dash_sep}Dec 2026"}
    end

    test "multi-year range — union preserves members; coalesce for a single span" do
      # Member-preserving union keeps both years distinct; the
      # IntervalSet renders them as two comma-separated spans. For
      # the "Jan 2022 – Dec 2023" single-span rendering, coalesce
      # explicitly first.
      {:ok, yr_iv} = Tempo.union(~o"2022", ~o"2023")
      coalesced = IntervalSet.coalesce(yr_iv)

      assert Tempo.to_string(coalesced) == {:ok, "Jan 2022#{@en_dash_sep}Dec 2023"}
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
      {:ok, string} = Tempo.to_string(iv)
      assert string =~ "Jun 15, 2026"
      assert string =~ "10"
      assert string =~ "5"
    end

    test "month :long uses the locale's long date interval pattern" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      {:ok, string} = Tempo.to_string(iv, format: :long)
      # Localize's :long for the :date style resolves to the locale's
      # :long date skeleton (yMMMMd for en) and its interval pattern,
      # which states the shared month and year once — full month name,
      # no weekday.
      assert string == "June 1 – 30, 2026"
    end

    test "month :full uses the day-of-week-and-month format" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      {:ok, string} = Tempo.to_string(iv, format: :full)
      # Localize's :full for the :date style resolves to the locale's
      # :full date skeleton (yMMMMEEEEd for en), which includes the
      # full weekday name, e.g. "Monday, June 1 – Tuesday, June 30, 2026".
      assert string =~ "Monday"
      assert string =~ "Tuesday"
      assert string =~ "June"
      assert string =~ "30, 2026"
    end
  end

  describe "Tempo.to_string/2 on Tempo.IntervalSet" do
    test "joins its members as a list in the locale" do
      {:ok, two} = Tempo.union(~o"2022", ~o"2024")

      assert Tempo.to_string(two) ==
               {:ok, "Jan#{@en_dash_sep}Dec 2022 and Jan#{@en_dash_sep}Dec 2024"}

      {:ok, three} = Tempo.union(two, ~o"2026")

      assert Tempo.to_string(three) ==
               {:ok,
                "Jan#{@en_dash_sep}Dec 2022, Jan#{@en_dash_sep}Dec 2024, and Jan#{@en_dash_sep}Dec 2026"}

      assert {:ok, german} = Tempo.to_string(two, locale: :de)
      assert german =~ " und "
    end
  end

  describe "Tempo.to_string/2 — the spans a value names" do
    test "a recurrence is its occurrences, however it is written" do
      assert Tempo.to_string(~o"R3/2026-06-15/P1D") ==
               {:ok, "Jun 15, 2026, Jun 16, 2026, and Jun 17, 2026"}

      assert Tempo.to_string(~o"R2/2026-06-15/2026-06-20") ==
               {:ok, "Jun 15#{@en_dash_sep}19, 2026 and Jun 20#{@en_dash_sep}24, 2026"}

      assert Tempo.to_string(~o"R2/P1D/2026-06-20") ==
               {:ok, "Jun 18, 2026 and Jun 19, 2026"}
    end

    test "an RRULE with an UNTIL is every occurrence up to it" do
      {:ok, rule} = RRule.parse("FREQ=DAILY;UNTIL=20260617", from: ~o"2026-06-15")

      assert Tempo.to_string(rule) == {:ok, "Jun 15, 2026, Jun 16, 2026, and Jun 17, 2026"}
    end

    test "an unending recurrence is its occurrences in a :within window" do
      weekly = ~o"R/2026-06-15/P1W"

      assert {:error, %Tempo.UnboundedRecurrenceError{}} = Tempo.to_string(weekly)

      assert Tempo.to_string(weekly, within: ~o"2026-06") ==
               {:ok,
                "Jun 15#{@en_dash_sep}21, 2026, Jun 22#{@en_dash_sep}28, 2026, " <>
                  "and Jun 29#{@en_dash_sep}Jul 5, 2026"}

      assert {:error, %Tempo.IntervalEndpointsError{reason: :open_start}} =
               Tempo.to_string(~o"R/../P1Y/FL12M25DN")

      assert Tempo.to_string(~o"R/../P1Y/FL12M25DN", within: ~o"2026") == {:ok, "Dec 25, 2026"}
    end

    test "a mask is the span its digits allow" do
      assert Tempo.to_string(~o"202X") == {:ok, "2020#{@en_dash_sep}2029"}
      assert Tempo.to_string(~o"2026-06-1X") == {:ok, "Jun 10#{@en_dash_sep}19, 2026"}

      assert Tempo.to_string(~o"2026-06-X5") ==
               {:ok, "Jun 5, 2026, Jun 15, 2026, and Jun 25, 2026"}

      assert {:error, %Tempo.InvalidDateError{}} = Tempo.to_string(~o"2026-02-3X")
    end

    test "a set is its members, and a one-of set its alternatives" do
      assert Tempo.to_string(~o"2026-{6,7}-15") == {:ok, "Jun 15, 2026 and Jul 15, 2026"}

      assert Tempo.to_string(~o"{2026,2027}") ==
               {:ok, "Jan#{@en_dash_sep}Dec 2026 and Jan#{@en_dash_sep}Dec 2027"}

      assert Tempo.to_string(~o"{2026-06-15,2026-07-04}") == {:ok, "Jun 15, 2026 and Jul 4, 2026"}

      assert Tempo.to_string(~o"[2026,2027]") ==
               {:ok, "Jan#{@en_dash_sep}Dec 2026 or Jan#{@en_dash_sep}Dec 2027"}

      assert Tempo.to_string(~o"[2020..2025,2030]") ==
               {:ok, "Jan 2020#{@en_dash_sep}Dec 2025 or Jan#{@en_dash_sep}Dec 2030"}

      assert {:ok, german} = Tempo.to_string(~o"[2026,2027]", locale: :de)
      assert german =~ " oder "
    end

    test "a group is its span" do
      assert Tempo.to_string(~o"20C") == {:ok, "2000#{@en_dash_sep}2099"}
      assert Tempo.to_string(~o"2026-33") == {:ok, "Jan#{@en_dash_sep}Mar 2026"}
    end

    test "a selection is the dates it selects" do
      assert Tempo.to_string(~o"2026YL1K1IN") == {:ok, "Jan 5, 2026"}

      assert {:error, %Tempo.UnboundedRecurrenceError{}} = Tempo.to_string(~o"L1K1IN")
      assert Tempo.to_string(~o"L1K1IN", within: ~o"2026") == {:ok, "Jan 5, 2026"}
    end

    test "a recurrence set is its occurrences in a :within window" do
      {:ok, holidays} = RecurrenceSet.new([~o"R/../P1Y/FL12M25DN", ~o"R/../P1Y/FL1M1DN"])

      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.to_string(holidays)
      assert Tempo.to_string(holidays, within: ~o"2026") == {:ok, "Jan 1, 2026 and Dec 25, 2026"}
    end

    test "a span of one value renders as that value, so a skeleton applies to it" do
      assert Tempo.to_string(~o"2026-06-15/2026-06-16", format: :yMMMd) == {:ok, "Jun 15, 2026"}
      assert Tempo.to_string(~o"2026YL1K1IN", format: :yMMMd) == {:ok, "Jan 5, 2026"}
      assert Tempo.to_string(~o"2026-06-XX", format: :yMMMd) == {:ok, "Jun 2026"}
      assert Tempo.to_string(~o"2026-06-XX") == Tempo.to_string(~o"2026-06")
    end

    test "a span of several values takes a skeleton or a pattern across its ends" do
      span = ~o"2026-06-15/2026-06-18"

      assert Tempo.to_string(span, format: :yMMMd) == {:ok, "Jun 15#{@en_dash_sep}17, 2026"}

      assert Tempo.to_string(span, format: "d MMM y") ==
               {:ok, "15 Jun 2026#{@en_dash_sep}17 Jun 2026"}
    end

    test "a month without a year is its name" do
      assert Tempo.to_string(~o"6M") == {:ok, "Jun"}
      assert Tempo.to_string(~o"6M", format: :long) == {:ok, "June"}
    end

    test "a week or a day of the week without a year is an error naming it" do
      assert {:error, %Tempo.UnanchoredError{value: ~o"25W"}} = Tempo.to_string(~o"W25")
      assert {:error, %Tempo.UnanchoredError{value: ~o"5K"}} = Tempo.to_string(~o"5K")
    end
  end

  describe "Tempo.to_string/2 — values it cannot render" do
    test "an interval without both ends is an error naming the open end" do
      assert {:error, %Tempo.IntervalEndpointsError{} = open_end} =
               Tempo.to_string(~o"2026-06-15/..")

      assert Exception.message(open_end) =~ "has no end"

      assert {:error, %Tempo.IntervalEndpointsError{} = open_start} =
               Tempo.to_string(~o"../2026-06-15")

      assert Exception.message(open_start) =~ "has no start"
    end

    test "an interval set without an end is an error" do
      mondays =
        ~o"2026-01-05"
        |> Stream.iterate(&Tempo.shift(&1, week: 1))
        |> Stream.map(&Tempo.to_interval!/1)
        |> IntervalSet.from_stream()

      assert {:error, %Tempo.UnboundedSetError{}} = Tempo.to_string(mondays)
    end

    test "a locale or format Localize does not accept is Localize's error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Tempo.to_string(~o"2026-06-15", locale: "xx-XX-bogus")

      assert {:error, %Localize.InvalidLocaleError{}} =
               Tempo.to_string(~o"2026", locale: "xx-XX-bogus")

      assert {:error, %Localize.InvalidLocaleError{}} =
               Tempo.to_string(~o"P1Y6M", locale: "xx-XX-bogus")

      assert {:error, %Localize.DateTimeUnresolvedFormatError{}} =
               Tempo.to_string(~o"2026-06-15", format: :nonsense)

      assert {:error, %Localize.DateTimeUnresolvedFormatError{}} =
               Tempo.to_string(~o"2026", format: :nonsense)
    end

    test "a member that cannot be rendered makes the set an error" do
      {:ok, set} = Tempo.union(~o"2022", ~o"2024")

      assert {:error, %Localize.InvalidLocaleError{}} =
               Tempo.to_string(set, locale: "xx-XX-bogus")
    end

    test "a value of another kind is an error" do
      assert {:error, %ArgumentError{}} = Tempo.to_string(~D[2026-06-15])
      assert {:error, %ArgumentError{}} = Tempo.to_string(nil)

      assert {:error, %ArgumentError{message: message}} = Tempo.to_string(~D[2026-06-15])
      assert message =~ "formats a Tempo, Tempo.Interval, Tempo.IntervalSet, Tempo.Set"
    end

    test "options that are not a keyword list are an error" do
      assert {:error, %ArgumentError{}} = Tempo.to_string(~o"2026", :long)
    end

    test "to_string!/2 returns the string or raises the error" do
      assert Tempo.to_string!(~o"2026-06-15") == "Jun 15, 2026"

      assert_raise Tempo.IntervalEndpointsError, fn ->
        Tempo.to_string!(~o"2026-06-15/..")
      end
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
      assert Tempo.to_string(tempo) == {:ok, to_string(tempo)}
    end

    test "a value with no localized form interpolates in its ISO 8601 form" do
      assert "From #{~o"2026-06-15/.."}" == "From 2026Y6M15D/.."
      assert "#{~o"../2026-06-15"}" == "../2026Y6M15D"
      assert "#{~o"R/2026-06-15/P1D"}" == "R/2026Y6M15D/P1D"
      assert "#{~o"W25"}" == "25W"
    end

    test "a set and a recurrence set interpolate" do
      assert "#{~o"[2026,2027]"}" == "Jan#{@en_dash_sep}Dec 2026 or Jan#{@en_dash_sep}Dec 2027"

      {:ok, holidays} = RecurrenceSet.new([~o"R/../P1Y/FL12M25DN", ~o"R/../P1Y/FL1M1DN"])
      assert "#{holidays}" == inspect(holidays)
    end

    test "a value with no ISO 8601 form either interpolates in its inspect form" do
      mondays =
        ~o"2026-01-05"
        |> Stream.iterate(&Tempo.shift(&1, week: 1))
        |> Stream.map(&Tempo.to_interval!/1)
        |> IntervalSet.from_stream()

      assert "#{mondays}" == inspect(mondays)
    end
  end

  describe "Tempo.to_string/2 on Tempo.Duration — Localize-backed" do
    test "year + month duration" do
      assert Tempo.to_string(~o"P1Y6M") == {:ok, "1 year, 6 months"}
    end

    test "day + hour duration" do
      assert Tempo.to_string(~o"P3DT2H") == {:ok, "3 days, 2 hours"}
    end

    test "weeks normalise to days" do
      assert Tempo.to_string(~o"P2W3D") == {:ok, "17 days"}
    end

    test "zero duration renders as `0 seconds`" do
      assert Tempo.to_string(~o"P0D") == {:ok, "0 seconds"}
    end

    test "a fraction of a second is kept" do
      assert Tempo.to_string(~o"PT0.5S") == {:ok, "500,000 microseconds"}
      assert Tempo.to_string(~o"PT1.5S") == {:ok, "1 second, 500,000 microseconds"}
      assert Tempo.to_string(~o"PT1.5S", except: [:microsecond]) == {:ok, "1 second"}
    end

    test ":format short abbreviates" do
      assert Tempo.to_string(~o"P3DT2H", format: :short) == {:ok, "3 days, 2 hr"}
    end

    test "locale honoured" do
      assert Tempo.to_string(~o"P1Y6M", locale: :de) == {:ok, "1 Jahr, 6 Monate"}
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
    # Nothing below may render an empty field, and nothing may fail.
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

    test "no combination fails" do
      for {label, value} <- @values, format <- @formats do
        options = if format, do: [format: format, locale: :en], else: [locale: :en]

        assert match?({:ok, string} when is_binary(string), Tempo.to_string(value, options)),
               "#{label} with #{inspect(format)} did not return a string"
      end
    end

    test "no combination renders an empty field" do
      # An empty field shows up as a separator with nothing before or
      # after it: a leading ":", a doubled "::", or a stray ", ".
      for {label, value} <- @values, format <- @formats do
        options = if format, do: [format: format, locale: :en], else: [locale: :en]
        {:ok, rendered} = Tempo.to_string(value, options)

        refute rendered =~ ~r/(^|\s):/,
               "#{label} with #{inspect(format)} rendered an empty leading field: #{inspect(rendered)}"

        refute rendered =~ "::",
               "#{label} with #{inspect(format)} rendered an empty field: #{inspect(rendered)}"

        refute rendered =~ ~r/:\s*$|,\s*$/,
               "#{label} with #{inspect(format)} rendered a trailing separator: #{inspect(rendered)}"
      end
    end

    test "a format asking for more precision than the value carries is narrowed" do
      assert Tempo.to_string(~o"2025-08-28T10", format: :hms, locale: :en) ==
               {:ok, "10#{@nbsp}AM"}

      assert Tempo.to_string(~o"2025-08-28T10:45", format: :hms, locale: :en) ==
               {:ok, "10:45#{@nbsp}AM"}

      assert Tempo.to_string(~o"T10", format: :hm, locale: :en) == {:ok, "10#{@nbsp}AM"}
      assert Tempo.to_string(~o"2025-08", format: :yMMMd, locale: :en) == {:ok, "Aug 2025"}
      assert Tempo.to_string(~o"2025", format: :yMMM, locale: :en) == {:ok, "2025"}
    end

    test "a time-only format renders the time of a value that also has a date" do
      assert Tempo.to_string(~o"2025-08-28T10:45", format: :hm, locale: :en) ==
               {:ok, "10:45#{@nbsp}AM"}

      assert Tempo.to_string(~o"2025-08-28T10:45:30", format: :hms, locale: :en) ==
               {:ok, "10:45:30#{@nbsp}AM"}
    end

    test "a date-only format renders the date of a value that also has a time" do
      assert Tempo.to_string(~o"2025-08-28T10:45", format: :yMMMd, locale: :en) ==
               {:ok, "Aug 28, 2025"}

      assert Tempo.to_string(~o"2025-08-28T10:45", format: :y, locale: :en) == {:ok, "2025"}
    end

    test "a format for an axis the value does not have falls back to the value" do
      assert Tempo.to_string(~o"2025-08-28", format: :hm, locale: :en) == {:ok, "Aug 28, 2025"}
      assert Tempo.to_string(~o"T10:45", format: :yMMMd, locale: :en) == {:ok, "10:45#{@nbsp}AM"}
    end

    test "the default still expands a year and a month as closed intervals" do
      assert Tempo.to_string(~o"2026", locale: :en) == {:ok, "Jan#{@en_dash_sep}Dec 2026"}

      assert Tempo.to_string(~o"2026", format: :medium, locale: :en) ==
               {:ok, "Jan#{@en_dash_sep}Dec 2026"}
    end

    test "an explicit skeleton renders the value rather than expanding it" do
      assert Tempo.to_string(~o"2026", format: :y, locale: :en) == {:ok, "2026"}
      assert Tempo.to_string(~o"2026-08", format: :yMMM, locale: :en) == {:ok, "Aug 2026"}
    end

    test "seconds appear only when the value carries them" do
      assert Tempo.to_string(~o"2025-08-28T10:45:30", locale: :en) ==
               {:ok, "Aug 28, 2025, 10:45:30#{@nbsp}AM"}

      {:ok, minutes} = Tempo.to_string(~o"2025-08-28T10:45", locale: :en)
      refute minutes =~ ":30"
      refute minutes =~ ":00"
    end
  end
end
