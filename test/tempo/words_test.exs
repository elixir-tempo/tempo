defmodule Tempo.WordsTest do
  use ExUnit.Case, async: true

  # The words for an expression, held to what Localize says of the Elixir
  # dates and times it covers.
  #
  # Tempo decides what is shown: a day as itself, a month and a week by
  # their first and last days, a year by its first and last months, an
  # interval through a date end. Localize says it. So each expression is
  # built from parts, and its words are those Localize gives for the `Date`s
  # that `Date` itself says begin and end it, in each locale and format.
  #
  # Words relative to another are held the same way: the count is made here
  # with `Date`, and Localize is asked for the words of that count.

  alias Localize.DateTime.Relative
  alias Tempo.{Duration, Interval}

  @days [
    ~D[2026-06-15],
    ~D[2024-02-29],
    ~D[2025-02-28],
    ~D[2026-01-01],
    ~D[2026-12-31],
    ~D[2027-01-03],
    ~D[1999-12-31],
    ~D[2026-03-29],
    ~D[2026-11-01]
  ]

  @locales ["en", "en-GB", "de", "fr"]
  @formats [:short, :medium, :long, :full]

  defp value(%Date{} = date), do: Tempo.new!(year: date.year, month: date.month, day: date.day)

  defp said(expression, options) do
    {:ok, words} = Tempo.to_string(expression, options)
    words
  end

  defp from_localize({:ok, words}), do: words

  defp length_of(parts) do
    {:ok, duration} = Duration.new(parts)
    duration
  end

  describe "to_string/2, in each locale and format" do
    for locale <- @locales, format <- @formats do
      @options [locale: locale, format: format]

      test "a day is that day (#{locale}, #{format})" do
        for day <- @days do
          assert said(value(day), @options) ==
                   from_localize(Localize.Date.to_string(day, @options))
        end
      end

      test "a month is its first day to its last (#{locale}, #{format})" do
        for day <- @days do
          month = Tempo.new!(year: day.year, month: day.month)
          {first, last} = {Date.beginning_of_month(day), Date.end_of_month(day)}

          assert said(month, @options) ==
                   from_localize(Localize.Interval.to_string(first, last, @options))
        end
      end

      test "a week is its Monday to its Sunday (#{locale}, #{format})" do
        for day <- @days do
          {year, week} = :calendar.iso_week_number(Date.to_erl(day))
          {first, last} = {Date.beginning_of_week(day), Date.end_of_week(day)}

          assert said(Tempo.new!(year: year, week: week), @options) ==
                   from_localize(Localize.Interval.to_string(first, last, @options))
        end
      end

      test "a year is its first month to its last (#{locale}, #{format})" do
        for day <- @days do
          {first, last} = {Date.new!(day.year, 1, 1), Date.new!(day.year, 12, 31)}

          assert said(Tempo.new!(year: day.year), @options) ==
                   from_localize(
                     Localize.Interval.to_string(
                       first,
                       last,
                       [fields: :year_and_month] ++ @options
                     )
                   )
        end
      end

      test "an interval of days runs through its last (#{locale}, #{format})" do
        for first <- @days, length <- [1, 6, 40, 400] do
          last = Date.add(first, length)
          {:ok, interval} = Interval.new(from: value(first), to: value(last))

          assert said(interval, @options) ==
                   from_localize(Localize.Interval.to_string(first, last, @options))
        end
      end

      test "a second is its date and time (#{locale}, #{format})" do
        for day <- @days, time <- [~T[00:00:00], ~T[09:30:45], ~T[23:59:59]] do
          at = NaiveDateTime.new!(day, time)

          assert said(Tempo.from_elixir!(at), @options) ==
                   from_localize(Localize.DateTime.to_string(at, @options))
        end
      end
    end
  end

  describe "to_string/2 of an interval of days" do
    # Law 9: the day an interval is written to is the last day it holds.
    test "of one day is that day" do
      for day <- @days do
        {:ok, interval} = Interval.new(from: value(day), to: value(day))
        assert said(interval, []) == from_localize(Localize.Date.to_string(day))
      end
    end

    test "is the interval a value converts to, shown as the value is" do
      for day <- @days do
        for parts <- [[year: day.year], [year: day.year, month: day.month]] do
          written = Tempo.new!(parts)
          {:ok, interval} = Tempo.to_interval(written)

          # A year as an interval is that year and a month that month, each
          # written once: the value's words name what is in it.
          assert said(interval, []) != said(written, [])
          assert String.contains?(said(written, []), Integer.to_string(day.year))
        end

        {:ok, interval} = Tempo.to_interval(value(day))
        assert said(interval, []) == said(value(day), [])
      end
    end
  end

  describe "to_string/2 of a duration" do
    test "is its units, in the locale" do
      a_year_and_a_half = length_of(year: 1, month: 6)
      three_days = length_of(day: 3, hour: 2)
      a_fortnight = length_of(week: 2, day: 3)
      none = length_of(day: 0)

      assert Tempo.to_string(a_year_and_a_half) == {:ok, "1 year, 6 months"}
      assert Tempo.to_string(a_year_and_a_half, locale: "de") == {:ok, "1 Jahr, 6 Monate"}
      assert Tempo.to_string(three_days) == {:ok, "3 days, 2 hours"}
      assert Tempo.to_string(three_days, format: :short) == {:ok, "3 days, 2 hr"}
      assert Tempo.to_string(three_days, except: [:hour]) == {:ok, "3 days"}
      assert Tempo.to_string(a_fortnight) == {:ok, "17 days"}
      assert Tempo.to_string(none) == {:ok, "0 seconds"}
    end
  end

  describe "to_string/2 and what it is not given" do
    test "an option it does not take is refused, and names what it takes" do
      assert {:error, %ArgumentError{message: message}} =
               Tempo.to_string(value(~D[2026-06-15]), style: :long)

      assert message =~ ":style is not an option of Tempo.to_string/2"
      assert message =~ ":format"
    end

    test "options that are not a keyword list are refused" do
      assert {:error, %ArgumentError{}} = Tempo.to_string(value(~D[2026-06-15]), :long)
      assert_raise ArgumentError, fn -> Tempo.to_string!(value(~D[2026-06-15]), :long) end
    end

    test "a locale or a format Localize does not have is Localize's error" do
      day = value(~D[2026-06-15])
      assert {:error, %Localize.InvalidLocaleError{}} = Tempo.to_string(day, locale: "zz-nope")

      assert {:error, %Localize.DateTimeUnresolvedFormatError{}} =
               Tempo.to_string(day, format: :nope)
    end

    test "what is not an expression is refused" do
      assert {:error, %Tempo.ConversionError{reason: :not_an_expression}} =
               Tempo.to_string(~D[2026-06-15])
    end
  end

  # ── Relative ──────────────────────────────────────────────────────────

  @pairs for from <- [~D[2026-06-15], ~D[2026-01-31], ~D[2026-12-31], ~D[2024-02-29]],
             days <- [-800, -366, -92, -31, -8, -7, -1, 0, 1, 6, 7, 30, 31, 91, 365, 800],
             do: {Date.add(from, days), from}

  defp counted(day, from, :year), do: day.year - from.year

  defp counted(day, from, :quarter),
    do: day.year * 4 + Date.quarter_of_year(day) - (from.year * 4 + Date.quarter_of_year(from))

  defp counted(day, from, :month), do: day.year * 12 + day.month - (from.year * 12 + from.month)

  defp counted(day, from, :week),
    do: div(Date.diff(Date.beginning_of_week(day), Date.beginning_of_week(from)), 7)

  defp counted(day, from, :day), do: Date.diff(day, from)

  describe "to_relative_string/2 in a unit asked for" do
    for unit <- [:year, :quarter, :month, :week, :day], locale <- ["en", "de", "fr"] do
      test "counts the #{unit}s of the calendar between the two (#{locale})" do
        for {day, from} <- @pairs do
          options = [unit: unquote(unit), locale: unquote(locale)]
          count = counted(day, from, unquote(unit))

          assert {day, from, Tempo.to_relative_string(value(day), [from: value(from)] ++ options)} ==
                   {day, from, Relative.to_string(count, options)}
        end
      end
    end

    test "counts the hours, minutes and seconds that pass" do
      from = ~N[2026-06-15 12:00:00]

      for seconds <- [-90_000, -3_600, -61, -1, 0, 1, 59, 60, 3_599, 3_600, 172_800],
          {unit, length} <- [hour: 3_600, minute: 60, second: 1] do
        at = NaiveDateTime.add(from, seconds)

        assert Tempo.to_relative_string(Tempo.from_elixir!(at),
                 from: Tempo.from_elixir!(from),
                 unit: unit
               ) == Relative.to_string(div(seconds, length), unit: unit)
      end
    end

    test "counts a day from the time of another day by the days" do
      {:ok, late} = Tempo.new(year: 2026, month: 6, day: 15, hour: 23)

      assert Tempo.to_relative_string(value(~D[2026-06-16]), from: late, unit: :day) ==
               {:ok, "tomorrow"}

      assert Tempo.to_relative_string(value(~D[2026-06-16]), from: late, unit: :hour) ==
               {:ok, "in 1 hour"}
    end

    test "is counted, where :numeric is :always" do
      assert Tempo.to_relative_string(value(~D[2026-06-16]),
               from: value(~D[2026-06-15]),
               unit: :day,
               numeric: :always
             ) == {:ok, "in 1 day"}
    end
  end

  describe "to_relative_string/2 and where an expression starts" do
    test "a year, a month, a week and an interval are where they begin" do
      from = value(~D[2026-06-17])
      {:ok, interval} = Interval.new(from: value(~D[2026-06-22]), to: value(~D[2026-06-26]))

      assert Tempo.to_relative_string(Tempo.new!(year: 2027), from: from, unit: :year) ==
               {:ok, "next year"}

      assert Tempo.to_relative_string(Tempo.new!(year: 2026, month: 8), from: from, unit: :month) ==
               {:ok, "in 2 months"}

      assert Tempo.to_relative_string(Tempo.new!(year: 2026, week: 26), from: from, unit: :week) ==
               {:ok, "next week"}

      assert Tempo.to_relative_string(interval, from: from, unit: :day) == {:ok, "in 5 days"}
    end

    test "an interval with no start has none" do
      {:ok, open} = Interval.new(from: :open, to: value(~D[2026-06-26]))

      assert {:error, %Tempo.ConversionError{reason: :open}} =
               Tempo.to_relative_string(open, from: value(~D[2026-06-17]))
    end
  end

  describe "to_relative_string/2 across calendars and clocks" do
    test "a date of another calendar is counted in that calendar's months and years" do
      {:ok, hebrew} = Tempo.to_calendar(value(~D[2026-09-12]), Calendrical.Hebrew)
      {:ok, the_day_before} = Tempo.to_calendar(value(~D[2026-09-11]), Calendrical.Hebrew)

      # 12 September 2026 is the first day of the Hebrew year 5787.
      for from <- [the_day_before, value(~D[2026-09-11])] do
        assert Tempo.to_relative_string(hebrew, from: from, unit: :year) == {:ok, "next year"}
        assert Tempo.to_relative_string(hebrew, from: from, unit: :month) == {:ok, "next month"}
        assert Tempo.to_relative_string(hebrew, from: from, unit: :day) == {:ok, "tomorrow"}
      end

      assert Tempo.to_relative_string(value(~D[2026-09-12]), from: the_day_before, unit: :year) ==
               {:ok, "this year"}
    end

    test "a zoned value is counted on its own clock" do
      {:ok, sydney} =
        Tempo.new(year: 2026, month: 6, day: 16, hour: 1, minute: 0, zone: "Australia/Sydney")

      # 13:00 UTC is 23:00 the day before in Sydney.
      from = Tempo.from_elixir!(~U[2026-06-15 13:00:00Z])

      assert Tempo.to_relative_string(sydney, from: from, unit: :day) == {:ok, "tomorrow"}
      assert Tempo.to_relative_string(sydney, from: from, unit: :hour) == {:ok, "in 2 hours"}
    end

    test "hours across a change of the clock are the hours that pass" do
      # New York's clocks go from 02:00 to 03:00 on 8 March 2026.
      {:ok, after_it} = Tempo.new(year: 2026, month: 3, day: 8, hour: 4, zone: "America/New_York")

      {:ok, before_it} =
        Tempo.new(year: 2026, month: 3, day: 8, hour: 1, zone: "America/New_York")

      assert Tempo.to_relative_string(after_it, from: before_it, unit: :hour) ==
               {:ok, "in 2 hours"}
    end
  end

  describe "to_relative_string/2 and what it is not given" do
    test "a unit it does not count in is refused, and names those it does" do
      assert {:error, %ArgumentError{message: message}} =
               Tempo.to_relative_string(value(~D[2026-06-18]),
                 from: value(~D[2026-06-15]),
                 unit: :fortnight
               )

      assert message =~ "does not count in :fortnight"
      assert message =~ ":week"
    end

    test "an option it does not take, and options that are no keyword list, are refused" do
      day = value(~D[2026-06-18])

      assert {:error, %ArgumentError{message: message}} =
               Tempo.to_relative_string(day, relative_to: value(~D[2026-06-15]))

      assert message =~ ":relative_to is not an option of Tempo.to_relative_string/2"
      assert {:error, %ArgumentError{}} = Tempo.to_relative_string(day, :short)
    end

    test "a :from that is not an expression, or has no year, is refused" do
      day = value(~D[2026-06-18])
      {:ok, half_past_ten} = Tempo.new(hour: 10, minute: 30)

      assert {:error, %Tempo.ConversionError{reason: :not_an_expression}} =
               Tempo.to_relative_string(day, from: ~D[2026-06-15])

      assert {:error, %Tempo.ConversionError{reason: :needs_a_year}} =
               Tempo.to_relative_string(day, from: half_past_ten)

      assert {:error, %Tempo.ConversionError{reason: :needs_a_year}} =
               Tempo.to_relative_string(half_past_ten, from: day)
    end

    test "a locale Localize does not have is Localize's error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Tempo.to_relative_string(value(~D[2026-06-18]),
                 from: value(~D[2026-06-15]),
                 locale: "zz-nope"
               )
    end
  end
end
