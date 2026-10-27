defmodule Tempo.DateRuleTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{DateRule, Interval, IntervalSet, ParseError, RecurrenceSet}

  doctest DateRule

  @fixture Path.expand("../fixtures/date_holidays_parser_tokens.json", __DIR__)
  @external_resource @fixture
  @fixture_rules @fixture
                 |> File.read!()
                 |> :json.decode()
                 |> Map.fetch!("rules")
                 |> Map.keys()

  @dates_fixture Path.expand("../fixtures/date_holidays_parser_dates.json", __DIR__)
  @external_resource @dates_fixture
  @parser_dates @dates_fixture
                |> File.read!()
                |> :json.decode()
                |> Map.fetch!("cases")

  # The rules of date-holidays-parser's fixture not read yet, each a part of
  # the grammar still to be built (plans/date-rule.md): a rule that is not a
  # date, an `if is holiday` move by more than one, `if equal`, and the
  # Bengali calendar and the years of the sexagenary cycle, which Calendrical
  # does not have. None is a rule of the date-holidays dataset but the
  # Bengali ones.
  @not_read_yet [
    "#1111",
    "03-01 and if Saturday, Sunday then next Monday if is holiday then 2nd next Tuesday since 2022",
    "2nd sunday after 05-01 if equal easter 49 then 3rd sunday after 05-01",
    "bengali-revised 1-1",
    "bengali-revised 1425-1-1",
    "chinese 78-32-8-15 solarterm",
    "friday before chinese 78-32-8-15 solarterm"
  ]

  # The rules of the parser's own tests not read yet.
  @dates_not_read_yet ["bengali-revised 1-1", "bengali-revised 12-1"]

  defp written(rule) do
    {:ok, expression} = DateRule.parse(rule)
    Tempo.to_iso8601!(expression)
  end

  test "every rule of the parser's fixture is read, but those not read yet" do
    not_read =
      for rule <- @fixture_rules, match?({:error, _}, DateRule.parse(rule)) do
        rule
      end

    assert Enum.sort(not_read) == Enum.sort(@not_read_yet)
  end

  test "every rule of the parser's own tests falls on the dates they expect" do
    differ =
      for %{"rule" => rule, "year" => year, "dates" => expected} <- @parser_dates,
          rule not in @dates_not_read_yet,
          found = dates_in(rule, year),
          found != {:ok, Enum.sort(expected)} do
        {rule, year, expected, found}
      end

    assert [] = differ
    assert Enum.all?(@dates_not_read_yet, &match?({:error, _}, DateRule.parse(&1)))
  end

  describe "a date" do
    test "fixed, in a month, or a month alone" do
      assert written("12-25") == "R/../P1Y/FL12M25DN"
      assert written("February") == "R/../P1Y/FL2M1DN"
      assert written("2015-10-09") == "R/{2015Y}/P1Y/FL10M9DN"
    end

    test "the nth weekday of a month, the fifth running on into the next" do
      assert written("2nd Monday in June") == "R/../P1Y/FL6M1K2IN"
      assert written("2nd sunday after 05-01") == "R/../P1Y/FL5M7K2IN"
      assert written("5th monday in October") == "R/../P1Y/FLL10M1DN/P35D1K-1IN"
    end

    test "a weekday before or after a date, or after the nth weekday after one" do
      assert written("monday before 06-01") == "R/../P1Y/FLL6M1DN/P-7D1K1IN"
      assert written("Friday after 4th Thursday in November") == "R/../P1Y/FLL11M4K4IN/P7D5K-1IN"

      assert written("Thursday before 2nd Friday after 01-01") ==
               "R/../P1Y/FLL1M5K2IN/P-7D4K1IN"

      assert written("monday after 3rd sunday after 09-01") == "R/../P1Y/FLL9M7K3IN/P7D1K-1IN"
    end

    test "Easter, its feasts, an equinox in a zone and a solar term are events" do
      assert written("easter") == "R/../P1Y/FL(easter)eN"
      assert written("easter -2") == "R/../P1Y/FLL(easter)eN/P-3D5K1IN"
      # Pentecost, seven weeks on, is a Sunday.
      assert written("orthodox 49") == "R/../P1Y/FLL(orthodox-easter)eN/P50D7K-1IN"
      assert written("march equinox in Asia/Tokyo") == "R/../P1Y/FL(march-equinox@Asia/Tokyo)eN"
      assert written("chinese 5-01 solarterm") == "R/../P1Y/FL(qingming)eN"
    end

    test "a date in another calendar is in that calendar" do
      assert written("10 Dhu al-Hijjah") == "R/../P1Y/FL12M10DN[u-ca=islamic-umalqura]"
      assert written("15 Nisan") == "R/../P1Y/FL7m15DN[u-ca=hebrew]"
      assert written("1 Farvardin") == "R/../P1Y/FL1M1DN[u-ca=persian]"
      assert written("julian 12-25") == "R/../P1Y/FL12M25DN[u-ca=julian]"
      assert written("chinese 01-0-01") == "R/../P1Y/FL1m1DN[u-ca=chinese]"
      assert written("korean 01-0-01") == "R/../P1Y/FL1m1DN[u-ca=dangi]"
    end

    test "a count of days or a weekday from any date, step by step" do
      assert written("4 days after 11-27") == "R/../P1Y/FLL11M27DN/P5D{1..7}K-1IN"

      assert written("4 days before march equinox in Europe/Vienna") ==
               "R/../P1Y/FLL(march-equinox@Europe/Vienna)eN/P-4D{1..7}K1IN"

      assert written("3rd monday before December solstice") ==
               "R/../P1Y/FLL(december-solstice)eN/P-21D1K1IN"

      # Fat Thursday, the Thursday before Ash Wednesday.
      assert written("Thursday before easter -46") ==
               "R/../P1Y/FLLL(easter)eN/P-47D3K1IN/P-7D4K1IN"

      assert written("friday before 1st monday before 06-01") ==
               "R/../P1Y/FLLL6M1DN/P-7D1K1IN/P-7D5K1IN"
    end

    test "a later day of a solar term is days from it" do
      assert written("chinese 8-15 solarterm") == "R/../P1Y/FLL(xiaoman)eN/P15D{1..7}K-1IN"
    end

    test "a date of another calendar with its year is in that year of it" do
      assert written("31 Shahrivar 1401") == "R/{1401Y}/P1Y/FL6M31DN[u-ca=persian]"
      assert written("julian 2015-01-09") == "R/{2015Y}/P1Y/FL1M9DN[u-ca=julian]"
    end

    test "Adar is the sixth month in order, Adar I in a leap year; AdarII is Purim's" do
      assert written("6 Adar") == "R/../P1Y/FL6M6DN[u-ca=hebrew]"
      assert written("14 AdarII") == "R/../P1Y/FL6m14DN[u-ca=hebrew]"
    end

    test "the eve of a lunisolar month is the day before its first" do
      assert written("chinese 01-0-00") == "R/../P1Y/FLL1m1DN/P-1D{1..7}K1IN[u-ca=chinese]"
    end

    test "the 30th of a short Islamic month runs on into the next" do
      assert written("30 Ramadan") ==
               "R/../P1Y/FLL9M1DN/P30D{1..7}K-1IN[u-ca=islamic-umalqura]"
    end
  end

  describe "a span" do
    test "in days, or in hours from the start of the day, the days it reaches into" do
      assert written("10 Dhu al-Hijjah P4D") ==
               "R/../P1Y/FLL12M10DN/P4DN[u-ca=islamic-umalqura]"

      assert written("1 Shawwal PT90H") == "R/../P1Y/FLL10M1DN/P4DN[u-ca=islamic-umalqura]"
      assert written("easter -50 PT48H") == "R/../P1Y/FLLL(easter)eN/P-51D6K1IN/P2DN"
    end

    test "from the time of day it starts at, which alone lasts to midnight" do
      assert written("12-31 14:00") == "R/../P1Y/FL12M31DN"
      assert written("12-31 14:00 PT12H") == "R/../P1Y/FLL12M31DN/P2DN"
      assert written("easter -3 14:00 P3D") == "R/../P1Y/FLLL(easter)eN/P-4D4K1IN/P4DN"
    end

    test "of a weekday step" do
      assert written("1st saturday in October P2D") == "R/../P1Y/FLL10M6K1IN/P2DN"
      assert written("1st Friday after 07-10 P4D") == "R/../P1Y/FLLL7M10DN/P7D5K-1IN/P4DN"
    end

    test "of an observed day, its date's or its clause's" do
      {:ok, before_clause} = DateRule.parse("01-01 P2D and if sunday then next monday")
      {:ok, in_clause} = DateRule.parse("01-01 and if sunday then next monday P2D")

      assert members(before_clause) == [
               "R/../P1Y/FLL1M1DN/P2DN",
               "R/../P1Y/FLLL1M1D7KN/P8D1K-1IN/P2DN"
             ]

      assert members(in_clause) == ["R/../P1Y/FL1M1DN", "R/../P1Y/FLLL1M1D7KN/P8D1K-1IN/P2DN"]
    end
  end

  describe "the years and days a rule is kept in" do
    test "since and prior to" do
      assert written("12-25 since 2020 prior to 2025") == "R/{2020Y..2024Y}/P1Y/FL12M25DN"
      # 21 September 2020 is before 1 November 2020, so 2020 is kept.
      assert written("09-21 prior to 2020-11") == "R/{../2020Y}/P1Y/FL9M21DN"
    end

    test "in a Gregorian year, a date of another calendar in its own years" do
      assert written("12 Cheshvan since 1997") == "R/{5758Y/..}/P1Y/FL2m12DN[u-ca=hebrew]"
    end

    test "every N years since a year, and even years" do
      assert written("12-01 every 6 years since 1980") == "R/{1980Y/..}/P6Y/FL12M1DN"
      assert written("03-02 in even years") == "R/..e/P1Y/FL3M2DN"
    end

    test "on some weekdays" do
      assert written("02-01 on Monday, Tuesday") == "R/../P1Y/FL2M1D{1..2}KN"
      assert written("12-26 not on Friday, Monday") == "R/../P1Y/FL12M26D{2..4,6..7}KN"
    end
  end

  describe "an observed day" do
    test "moves the date, or is added to it, or stands alone" do
      {:ok, moved} = DateRule.parse("01-01 if sunday then next monday")
      {:ok, added} = DateRule.parse("01-01 and if sunday then next monday")
      {:ok, alone} = DateRule.parse("substitutes 01-01 if sunday then next monday")

      assert members(moved) == ["R/../P1Y/FL1M1D{1..6}KN", "R/../P1Y/FLL1M1D7KN/P8D1K-1IN"]
      assert members(added) == ["R/../P1Y/FL1M1DN", "R/../P1Y/FLL1M1D7KN/P8D1K-1IN"]
      assert Tempo.to_iso8601!(alone) == "R/../P1Y/FLL1M1D7KN/P8D1K-1IN"
    end

    test "is marked as a substitute day" do
      {:ok, added} = DateRule.parse("01-01 and if sunday then next monday")
      metadata = added |> RecurrenceSet.members() |> Enum.map(&Tempo.metadata/1)

      assert metadata == [%{}, %{substitute: true}]
    end

    test "a time it changes the start to is no change of the day" do
      assert written("12-31 14:00 if Sunday then 00:00") == "R/../P1Y/FL12M31DN"
    end
  end

  describe "a rule decided by other dates" do
    test "a bridge keeps its day when the dates beside it are holidays of its type" do
      {:ok, bridge} = DateRule.parse("09-22 if 09-21 and 09-23 is public holiday")

      {:ok, holidays} =
        RecurrenceSet.new([public(~o"2026-09-21"), public(~o"2026-09-23"), bridge])

      {:ok, days} = Tempo.to_interval(holidays, within: ~o"2026")

      assert IntervalSet.map(days, &Tempo.day/1) == [21, 22, 23]
    end

    test "an if is holiday move takes the next weekday off a holiday of its type" do
      {:ok, move} =
        DateRule.parse("Thursday after 04-02 if is observance holiday then next Thursday")

      assert %Tempo{form: {:when, _member, [move: [falls_on: %{type: :observance}, to_next: _]]}} =
               move
    end

    test "an if is holiday move to the next day skips the weekdays it omits" do
      {:ok, may_day} = DateRule.parse("05-01 if is holiday then next day omit Sunday, Saturday")
      {:ok, holidays} = RecurrenceSet.new([public(~o"2026-05-01"), may_day])
      {:ok, days} = Tempo.to_interval(holidays, within: ~o"2026")

      # 1 May 2026 is a Friday, so the day after it that is no weekend day is
      # Monday 4 May.
      assert IntervalSet.map(days, &Tempo.day/1) == [1, 4]
    end
  end

  describe "an error" do
    test "names the text not read, or the part not read yet" do
      assert {:error, %ParseError{rest: "tomorrow", as: "a date rule"}} =
               DateRule.parse("12-25 tomorrow")

      assert {:error, %ParseError{reason: "the Bengali calendar is not one Calendrical has"}} =
               DateRule.parse("bengali-revised 1-1")

      assert {:error, %ParseError{reason: "a year of the sexagenary cycle is not read yet" <> _}} =
               DateRule.parse("chinese 78-32-8-15 solarterm")

      assert {:error, %ParseError{reason: "a clause that changes the time of a date" <> _}} =
               DateRule.parse("12-31 14:00 PT12H if Sunday then 00:00")
    end

    test "is returned for what is no text" do
      assert {:error, %ParseError{}} = DateRule.parse(:christmas)
      assert_raise ParseError, fn -> DateRule.parse!("12-25 tomorrow") end
    end
  end

  # The Gregorian dates a rule falls on in a Gregorian year, as the parser's
  # tests write them.
  defp dates_in(rule, year) do
    with {:ok, expression} <- DateRule.parse(rule),
         {:ok, within} <- Tempo.new(year: year),
         {:ok, occurrences} <- Tempo.to_interval(expression, within: within) do
      dates =
        occurrences
        |> IntervalSet.members()
        |> Enum.map(&gregorian_date/1)

      {:ok, Enum.sort(dates)}
    end
  end

  defp gregorian_date(occurrence) do
    {:ok, date} = Tempo.to_date(Interval.from(occurrence))
    {:ok, gregorian} = Date.convert(date, Calendar.ISO)
    Date.to_iso8601(gregorian)
  end

  defp members(set) do
    set
    |> RecurrenceSet.members()
    |> Enum.map(&Tempo.to_iso8601!/1)
  end

  defp public(value) do
    Tempo.put_metadata(value, %{type: :public})
  end
end
