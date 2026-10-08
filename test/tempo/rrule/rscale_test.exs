defmodule Tempo.RRule.RscaleTest do
  @moduledoc """
  A rule counted in another calendar (RFC 7529's `RSCALE`, JSCalendar's
  `rscale`; decided 2026-10-07).

  `RSCALE` names the calendar a rule counts its months and its days in. It
  is one of the notations that carry a calendar's name by definition, and
  is resolved to the calendar module where the rule is read. The rule's
  start, which iCalendar writes as a Gregorian date, is brought into that
  calendar and the rule is counted from it there: a yearly rule in the
  Hebrew calendar from 2 April 2026 recurs on 15 Nisan. It was
  `{:unsupported_rscale, "HEBREW"}`.

  The measure is the dates the festivals are published on, and the
  calendar's own dates through Elixir's `Date`: `Date.new!/4` in the
  calendar and `Date.convert!/2` to the Gregorian. A month is numbered as
  RFC 7529 numbers it, which in a Hebrew year with a leap month is one less
  than its place in the year from Adar on.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.Islamic.Civil
  alias Calendrical.Persian
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  ## The measure

  # The first day of Passover, 15 Nisan, as it is published.
  @passover [~D[2026-04-02], ~D[2027-04-22], ~D[2028-04-11], ~D[2029-03-31], ~D[2030-04-18]]

  # Rosh Hashanah, 1 Tishri.
  @rosh_hashanah [~D[2026-09-12], ~D[2027-10-02], ~D[2028-09-21]]

  # Nisan is the seventh month of a Hebrew year, and the eighth in order in
  # a year with a leap month.
  defp nisan(year), do: if(Hebrew.leap_year?(year), do: 8, else: 7)

  defp gregorian(year, month, day, calendar),
    do: year |> Date.new!(month, day, calendar) |> Date.convert!(Calendar.ISO)

  # The Gregorian date each occurrence starts on.
  defp starts({:ok, rule}, options \\ []) do
    {:ok, set} = Tempo.to_interval(rule, options)

    for occurrence <- IntervalSet.members(set) do
      {:ok, date} = occurrence |> Interval.from() |> Tempo.to_calendar(Calendrical.Gregorian)
      Date.new!(Tempo.year(date), Tempo.month(date), Tempo.day(date))
    end
  end

  describe "the measure" do
    test "is the calendar's own: 15 Nisan of each year is Passover's published date" do
      assert Enum.map(5786..5790, &gregorian(&1, nisan(&1), 15, Hebrew)) == @passover
      assert Enum.map(5787..5789, &gregorian(&1, 1, 1, Hebrew)) == @rosh_hashanah
    end
  end

  describe "a yearly rule in the Hebrew calendar" do
    test "recurs on its start's Hebrew date, in a year with a leap month too" do
      rule = RRule.parse("RSCALE=HEBREW;FREQ=YEARLY;COUNT=5", from: ~o"2026-04-02")

      assert starts(rule) == @passover
    end

    test "is counted from its start in that calendar" do
      {:ok, rule} = RRule.parse("RSCALE=HEBREW;FREQ=YEARLY;COUNT=5", from: ~o"2026-04-02")

      assert Tempo.to_iso8601!(Interval.from(rule)) == "5786Y7M15D[u-ca=hebrew]"
    end

    test "numbers a month as RFC 7529 does: Nisan is month 7 of every year" do
      rule =
        RRule.parse("RSCALE=HEBREW;FREQ=YEARLY;COUNT=5;BYMONTH=7;BYMONTHDAY=15",
          from: ~o"2026-04-02"
        )

      assert starts(rule) == @passover

      # 5787 has a leap month, and its seventh month in order is Adar II.
      assert Hebrew.leap_year?(5787)
      refute gregorian(5787, 7, 15, Hebrew) in @passover
    end

    test "names its months from any start: the first of Tishri from a day in winter" do
      rule =
        RRule.parse("RSCALE=HEBREW;FREQ=YEARLY;COUNT=3;BYMONTH=1;BYMONTHDAY=1",
          from: ~o"2026-01-01"
        )

      assert starts(rule) == @rosh_hashanah
    end

    test "is written in any case" do
      assert starts(RRule.parse("rscale=hebrew;FREQ=YEARLY;COUNT=5", from: ~o"2026-04-02")) ==
               @passover
    end

    test "keeps its start's time of day and its zone" do
      {:ok, rule} =
        RRule.parse("RSCALE=HEBREW;FREQ=YEARLY;COUNT=3",
          from: ~o"2026-04-02T19:30[Asia/Jerusalem]"
        )

      {:ok, set} = Tempo.to_interval(rule)

      for {occurrence, date} <- Enum.zip(IntervalSet.members(set), @passover) do
        {:ok, start} = Tempo.to_calendar(Interval.from(occurrence), Calendrical.Gregorian)
        {:ok, expected} = Tempo.from_iso8601("#{date}T19:30[Asia/Jerusalem]")

        assert start == expected
      end
    end
  end

  describe "a monthly rule in the Hebrew calendar" do
    test "has the first of each month, thirteen of them in a year with a leap month" do
      # 1 Tishri 5787 is 12 September 2026.
      rule = RRule.parse("RSCALE=HEBREW;FREQ=MONTHLY;COUNT=14", from: ~o"2026-09-12")

      firsts = for month <- 1..13, do: gregorian(5787, month, 1, Hebrew)

      assert Hebrew.months_in_year(5787) == 13
      assert starts(rule) == firsts ++ [gregorian(5788, 1, 1, Hebrew)]
    end

    test "with SKIP=BACKWARD keeps the last day of a month without its start's" do
      # 17 April 2026 is 30 Nisan 5786, and Iyar has 29 days.
      assert Date.convert!(~D[2026-04-17], Hebrew) == Date.new!(5786, 7, 30, Hebrew)

      rule =
        RRule.parse("RSCALE=HEBREW;FREQ=MONTHLY;COUNT=6;SKIP=BACKWARD", from: ~o"2026-04-17")

      expected =
        for month <- 7..12 do
          gregorian(5786, month, min(30, Hebrew.days_in_month(5786, month)), Hebrew)
        end

      assert Enum.map(7..12, &Hebrew.days_in_month(5786, &1)) == [30, 29, 30, 29, 30, 29]
      assert starts(rule) == expected
    end
  end

  describe "a rule in a calendar whose years have the same months" do
    test "counts the Persian new year from its date" do
      rule =
        RRule.parse("RSCALE=PERSIAN;FREQ=YEARLY;COUNT=4;BYMONTH=1;BYMONTHDAY=1",
          from: ~o"2026-03-21"
        )

      assert starts(rule) == Enum.map(1405..1408, &gregorian(&1, 1, 1, Persian))
    end

    test "counts a year of the civil Islamic calendar, eleven days short of the Gregorian" do
      {:ok, shawwal} = Date.convert(~D[2026-03-20], Civil)
      rule = RRule.parse("RSCALE=ISLAMIC-CIVIL;FREQ=YEARLY;COUNT=4", from: ~o"2026-03-20")

      assert starts(rule) ==
               Enum.map(0..3, &gregorian(shawwal.year + &1, shawwal.month, shawwal.day, Civil))
    end

    test "is the rule it was in the Gregorian calendar" do
      with_rscale = RRule.parse("RSCALE=GREGORIAN;FREQ=MONTHLY;COUNT=4", from: ~o"2026-01-15")
      without = RRule.parse("FREQ=MONTHLY;COUNT=4", from: ~o"2026-01-15")

      assert with_rscale == without
    end

    test "brings a start of another calendar into its own" do
      {:ok, hebrew_start} = Tempo.to_calendar(~o"2026-01-15", Hebrew)

      assert RRule.parse("RSCALE=GREGORIAN;FREQ=MONTHLY;COUNT=4", from: hebrew_start) ==
               RRule.parse("FREQ=MONTHLY;COUNT=4", from: ~o"2026-01-15")
    end
  end

  describe "a rule with no start" do
    test "says its calendar by the parts that select, and is counted in it within a window" do
      rule = RRule.parse("RSCALE=HEBREW;FREQ=YEARLY;BYMONTH=7;BYMONTHDAY=15")

      assert starts(rule, within: ~o"2026/2031") == @passover
    end

    test "with no part that selects has nothing to say its calendar with" do
      assert RRule.parse("RSCALE=HEBREW;FREQ=YEARLY") ==
               {:error, {:rscale_without_a_start, Hebrew}}

      assert {:ok, _gregorian} = RRule.parse("RSCALE=GREGORIAN;FREQ=YEARLY")
    end
  end

  describe "what a rule cannot be read as" do
    test "a name that is no calendar's" do
      for name <- ["KLINGON", "", "hebrew ", String.duplicate("x", 5_000)] do
        assert RRule.parse("RSCALE=#{name};FREQ=YEARLY", from: ~o"2026-04-02") ==
                 {:error, {:unsupported_rscale, name}}
      end
    end

    test "a start that is no date has no place in another calendar" do
      for start <- [~o"2026-04", ~o"2026", ~o"T10:30"] do
        assert RRule.parse("RSCALE=HEBREW;FREQ=YEARLY", from: start) ==
                 {:error, {:from_is_no_date, start}}
      end
    end

    test "a leap month is not read yet" do
      assert {:error, _reason} =
               RRule.parse("RSCALE=HEBREW;FREQ=YEARLY;BYMONTH=5L", from: ~o"2026-04-02")
    end
  end

  describe "the calendar an RSCALE names" do
    test "is a calendar module, whatever the case of its name" do
      assert Rule.calendar_from_rscale("HEBREW") == {:ok, Hebrew}
      assert Rule.calendar_from_rscale("Hebrew") == {:ok, Hebrew}
      assert Rule.calendar_from_rscale("ISLAMIC-CIVIL") == {:ok, Civil}
      assert Rule.calendar_from_rscale("gregorian") == {:ok, Calendrical.Gregorian}
      assert Rule.calendar_from_rscale(nil) == {:ok, nil}
    end

    test "is no calendar for what is no name" do
      assert Rule.calendar_from_rscale(:hebrew) == {:error, {:unsupported_rscale, :hebrew}}
      assert Rule.calendar_from_rscale(42) == {:error, {:unsupported_rscale, 42}}
    end
  end

  describe "a rule built as a struct" do
    test "is counted in the calendar it names, from its start there" do
      rule = %Rule{freq: :year, count: 5, rscale: Hebrew}

      {:ok, occurrences} = Expander.expand(rule, ~o"2026-04-02")

      dates =
        for occurrence <- occurrences do
          {:ok, date} = Tempo.to_calendar(Interval.from(occurrence), Calendrical.Gregorian)
          Date.new!(Tempo.year(date), Tempo.month(date), Tempo.day(date))
        end

      assert dates == @passover
    end

    test "refuses a start that is no date" do
      rule = %Rule{freq: :year, count: 2, rscale: Hebrew}

      assert Expander.to_ast(rule, ~o"2026-04") == {:error, {:from_is_no_date, ~o"2026-04"}}
    end
  end
end
