defmodule Tempo.RRule.LeapMonthTest do
  @moduledoc """
  A leap month in a rule (RFC 7529 §4.2, RFC 8984 §4.3.3).

  RFC 7529 writes a leap month as the number of the month it follows and an
  `L`: `BYMONTH=5L` is the leap month after the fifth, Adar I of a Hebrew
  year. A year that has no such month has no such date, and the rule's
  `SKIP` says what becomes of it (§4.1): `OMIT` passes over the year,
  `BACKWARD` takes the month before, and `FORWARD` the month after. It was
  an error to read one.

  A yearly rule takes its month from its start, and one that starts in a
  leap month takes the leap month: it was given the month in the leap
  month's place in every year, whatever its `SKIP`.

  The measure is the dates RFC 7529 §4.3.3 lists, and the calendar's own
  dates through Elixir's `Date`: a Hebrew year with a leap month has Adar I
  sixth and Adar II seventh, and one without has Adar sixth, Shevat being
  fifth in both.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Chinese
  alias Calendrical.Hebrew
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  doctest Tempo.RRule.Rule

  ## The measure

  # RFC 7529 §4.3.3: the 8th of Adar I from 2014, moved forward to Adar in
  # the years that have no Adar I.
  @rfc_forward [~D[2014-02-08], ~D[2015-02-27], ~D[2016-02-17], ~D[2017-03-06], ~D[2018-02-23]]

  @window ~o"2014/2026"
  @years 5774..5786

  defp gregorian(year, month, day, calendar),
    do: year |> Date.new!(month, day, calendar) |> Date.convert!(Calendar.ISO)

  # The date a day of Adar I is each Hebrew year, by what the rule does in a
  # year without one: Adar I and Adar are each a year's sixth month, and
  # Shevat its fifth.
  defp adar_one(day, skip) do
    dates =
      for year <- @years do
        cond do
          Hebrew.leap_year?(year) -> gregorian(year, 6, day, Hebrew)
          skip == :omit -> nil
          skip == :backward -> gregorian(year, 5, day, Hebrew)
          skip == :forward -> gregorian(year, 6, day, Hebrew)
        end
      end

    Enum.filter(dates, &(&1 && Date.compare(&1, ~D[2026-01-01]) == :lt))
  end

  # The Gregorian date each occurrence starts on.
  defp starts({:ok, rule}) do
    {:ok, set} = Tempo.to_interval(rule, within: @window)

    for occurrence <- IntervalSet.members(set) do
      {:ok, date} = occurrence |> Interval.from() |> Tempo.to_calendar(Calendrical.Gregorian)
      Date.new!(Tempo.year(date), Tempo.month(date), Tempo.day(date))
    end
  end

  defp hebrew(rule, from), do: RRule.parse("RSCALE=HEBREW;" <> rule, from: from)

  describe "the measure" do
    test "is the calendar's own: RFC 7529's dates are the 8th of each year's sixth month" do
      assert Enum.map(5774..5778, &gregorian(&1, 6, 8, Hebrew)) == @rfc_forward
      assert Enum.filter(5774..5778, &Hebrew.leap_year?/1) == [5774, 5776]
      assert Enum.take(adar_one(8, :forward), 5) == @rfc_forward
    end

    test "has Adar I in five years of thirteen, and a date in each year once it is moved" do
      assert Enum.count(adar_one(8, :omit)) == 5
      assert Enum.count(adar_one(8, :backward)) == 12
      assert Enum.count(adar_one(8, :forward)) == 12
      assert adar_one(8, :backward) != adar_one(8, :forward)
    end
  end

  describe "a rule that names a leap month" do
    test "is RFC 7529's example: the 8th of Adar I, forward to Adar" do
      rule = hebrew("FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=8;SKIP=FORWARD;COUNT=5", ~o"2014-02-08")

      assert starts(rule) == @rfc_forward
    end

    test "passes over a year without it, which is its default" do
      for skip <- ["", ";SKIP=OMIT"] do
        rule = hebrew("FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=8" <> skip, ~o"2014-02-08")

        assert {skip, starts(rule)} == {skip, adar_one(8, :omit)}
      end
    end

    test "is the month before it or the month after it in such a year, by its SKIP" do
      for {skip, text} <- [backward: "BACKWARD", forward: "FORWARD"] do
        rule = hebrew("FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=8;SKIP=#{text}", ~o"2014-02-08")

        assert {skip, starts(rule)} == {skip, adar_one(8, skip)}
      end
    end

    test "takes its day from its start where it names none" do
      for {skip, text} <- [omit: "OMIT", backward: "BACKWARD", forward: "FORWARD"] do
        rule = hebrew("FREQ=YEARLY;BYMONTH=5L;SKIP=#{text}", ~o"2014-02-08")

        assert {skip, starts(rule)} == {skip, adar_one(8, skip)}
      end
    end

    test "moves a day the month it is moved to lacks, in its turn" do
      # Adar I has thirty days, Shevat thirty and Adar twenty-nine: the 30th
      # moved back is the 30th of Shevat, and moved forward is no day of
      # Adar, so it is the day after Adar's last.
      assert Enum.map([5774, 5775], &Hebrew.days_in_month(&1, 6)) == [30, 29]
      assert Hebrew.days_in_month(5775, 5) == 30

      forward = hebrew("FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=30;SKIP=FORWARD", ~o"2014-03-02")
      backward = hebrew("FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=30;SKIP=BACKWARD", ~o"2014-03-02")

      assert Enum.take(starts(forward), 3) ==
               [gregorian(5774, 6, 30, Hebrew), gregorian(5775, 7, 1, Hebrew)] ++
                 [gregorian(5776, 6, 30, Hebrew)]

      assert Enum.take(starts(backward), 3) ==
               [gregorian(5774, 6, 30, Hebrew), gregorian(5775, 5, 30, Hebrew)] ++
                 [gregorian(5776, 6, 30, Hebrew)]
    end

    test "is one occurrence where it is moved to a month the rule names too" do
      rule = hebrew("FREQ=YEARLY;BYMONTH=5L,6;BYMONTHDAY=8;SKIP=FORWARD", ~o"2014-02-08")

      # Adar I and Adar II in a year with both, and Adar once in one without.
      expected =
        Enum.flat_map(@years, fn year ->
          if Hebrew.leap_year?(year),
            do: [gregorian(year, 6, 8, Hebrew), gregorian(year, 7, 8, Hebrew)],
            else: [gregorian(year, 6, 8, Hebrew)]
        end)

      assert starts(rule) == Enum.filter(expected, &(Date.compare(&1, ~D[2026-01-01]) == :lt))
    end

    test "limits a monthly rule to it" do
      omit = hebrew("FREQ=MONTHLY;BYMONTH=5L;BYMONTHDAY=8", ~o"2014-02-08")
      forward = hebrew("FREQ=MONTHLY;BYMONTH=5L;BYMONTHDAY=8;SKIP=FORWARD", ~o"2014-02-08")

      assert starts(omit) == adar_one(8, :omit)
      assert starts(forward) == adar_one(8, :forward)
    end

    test "is written in either case" do
      assert hebrew("FREQ=YEARLY;BYMONTH=5l;BYMONTHDAY=8", ~o"2014-02-08") ==
               hebrew("FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=8", ~o"2014-02-08")
    end
  end

  describe "a yearly rule that starts in a leap month" do
    test "takes the leap month from its start, and recurs by its SKIP" do
      # 8 February 2014 is 8 Adar I 5774.
      assert Date.convert!(~D[2014-02-08], Hebrew) == Date.new!(5774, 6, 8, Hebrew)
      assert Hebrew.lunar_month_of_year(5774, 6) == {5, :leap}

      for {skip, text} <- [omit: "", backward: ";SKIP=BACKWARD", forward: ";SKIP=FORWARD"] do
        rule = hebrew("FREQ=YEARLY" <> text, ~o"2014-02-08")

        assert {skip, starts(rule)} == {skip, adar_one(8, skip)}
      end
    end

    test "starting in a month every year has, has that month every year" do
      # 27 February 2015 is 8 Adar 5775, the month RFC 7529 numbers 6: Adar
      # II, the seventh month, of a year with a leap month.
      assert Date.convert!(~D[2015-02-27], Hebrew) == Date.new!(5775, 6, 8, Hebrew)

      rule = hebrew("FREQ=YEARLY", ~o"2015-02-27")

      expected =
        for year <- 5775..5786 do
          gregorian(year, if(Hebrew.leap_year?(year), do: 7, else: 6), 8, Hebrew)
        end

      assert starts(rule) == Enum.filter(expected, &(Date.compare(&1, ~D[2026-01-01]) == :lt))
    end

    test "is every month from it where the rule steps by months" do
      rule = hebrew("FREQ=MONTHLY;COUNT=3", ~o"2014-02-08")

      assert starts(rule) == Enum.map(6..8, &gregorian(5774, &1, 8, Hebrew))
    end
  end

  describe "a leap month of the Chinese calendar" do
    test "is the month the calendar has after the one it names, in the year that has it" do
      # The Chinese year that began in January 2023 has a leap month after
      # its second, the third month of the year.
      {year, ordinal} =
        Enum.find_value(4650..4670, fn year ->
          if Chinese.traditional_leap_month(year) == 2, do: {year, Chinese.leap_month(year)}
        end)

      first = gregorian(year, ordinal, 1, Chinese)

      assert ordinal == 3
      assert first.year == 2023

      omit =
        RRule.parse("RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=2L;BYMONTHDAY=1", from: ~o"2014-02-08")

      assert starts(omit) == [first]
    end

    test "is the month after it in every other year, with SKIP=FORWARD" do
      forward =
        RRule.parse("RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=2L;BYMONTHDAY=1;SKIP=FORWARD",
          from: ~o"2014-02-08"
        )

      # The third month the calendar names is its fourth in a year with a
      # leap month before it.
      {:ok, start} = Date.convert(~D[2014-02-08], Chinese)

      expected =
        for year <- start.year..(start.year + 11) do
          if Chinese.traditional_leap_month(year) == 2 do
            gregorian(year, Chinese.leap_month(year), 1, Chinese)
          else
            {:ok, third} = Chinese.ordinal_month_from_traditional(year, 3)
            gregorian(year, third, 1, Chinese)
          end
        end

      assert starts(forward) == Enum.filter(expected, &(Date.compare(&1, ~D[2026-01-01]) == :lt))
      assert Enum.count(starts(forward)) == 12
    end
  end

  describe "a rule built as a struct" do
    test "holds a leap month as the month it follows" do
      rule = %Rule{
        freq: :year,
        rscale: Hebrew,
        bymonth: [{5, :leap}],
        bymonthday: [8],
        skip: :forward
      }

      assert starts(Expander.to_ast(rule, ~o"2014-02-08")) == adar_one(8, :forward)
    end

    test "is held to what a rule that is read is" do
      assert Expander.to_ast(%Rule{freq: :year, bymonth: [{5, :leap}]}, ~o"2014-02-08") ==
               {:error, {:leap_month_without_rscale, {5, :leap}}}

      assert Expander.to_ast(
               %Rule{freq: :year, rscale: Hebrew, skip: :forward, bymonth: [{12, :leap}]},
               ~o"2014-02-08"
             ) == {:error, {:unsupported_skip, {:forward, [bymonth: [{12, :leap}]]}}}
    end
  end

  describe "what is no leap month of the rule's calendar" do
    test "a leap month in a rule that names no calendar" do
      assert RRule.parse("FREQ=YEARLY;BYMONTH=5L", from: ~o"2014-02-08") ==
               {:error, {:leap_month_without_rscale, {5, :leap}}}
    end

    test "a leap month in a calendar whose years all have the same months" do
      for {name, calendar} <- [
            {"GREGORIAN", Calendrical.Gregorian},
            {"PERSIAN", Calendrical.Persian},
            {"ISLAMIC-CIVIL", Calendrical.Islamic.Civil}
          ] do
        assert {name, RRule.parse("RSCALE=#{name};FREQ=YEARLY;BYMONTH=5L", from: ~o"2014-02-08")} ==
                 {name, {:error, {:calendar_has_no_leap_month, {{5, :leap}, calendar}}}}
      end
    end

    test "the month after a leap month that follows a year's last, which is the next year's" do
      assert hebrew("FREQ=YEARLY;BYMONTH=12L;SKIP=FORWARD", ~o"2014-02-08") ==
               {:error, {:unsupported_skip, {:forward, [bymonth: [{12, :leap}]]}}}

      # Back from it is the year's last month, Elul, in every year.
      backward =
        hebrew("FREQ=YEARLY;BYMONTH=12L;BYMONTHDAY=1;SKIP=BACKWARD;COUNT=2", ~o"2014-02-08")

      last = fn year -> Hebrew.months_in_year(year) end

      assert starts(backward) == Enum.map([5774, 5775], &gregorian(&1, last.(&1), 1, Hebrew))
    end

    test "what is no month" do
      for text <- ["L", "L5", "5LL", "0L", "-5L", "5 L", "5M", "five"] do
        assert {text, hebrew("FREQ=YEARLY;BYMONTH=#{text}", ~o"2014-02-08")} ==
                 {text, {:error, {:invalid_integer_in_list, text, :bymonth}}}
      end
    end

    test "is never an atom made from what was read" do
      assert {:ok, {_number, :leap}} = Rule.month_from_text(String.duplicate("9", 5_000) <> "L")
      assert Rule.month_from_text(nil) == :error
      assert Rule.month_from_text(5) == :error
    end
  end
end
