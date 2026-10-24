defmodule Tempo.DomainTest do
  use ExUnit.Case, async: true

  # A recurrence's domain, the set written in its start's place
  # (`R/{2020Y..2030Y,^2026Y}/P1Y/F…`), and a set's exclusions (`^`): the
  # cases the `tempo_holidays` work added, where holidays are kept only in
  # the years a rule names. The measure is the years, read with `Date`, and
  # the dates of other calendars converted by Calendrical alone.

  import Tempo.Sigils
  import Tempo.Builder

  alias Tempo.{Interval, IntervalSet}

  defp years({:ok, set}), do: years(set)

  defp years(set) do
    set
    |> IntervalSet.members()
    |> Enum.map(&(&1 |> Interval.from() |> Tempo.year()))
    |> Enum.sort()
  end

  # Mawlid, the 12th of Rabi al-awwal, in a domain of Islamic years.
  defp mawlid_in(years) do
    {:ok, mawlid} =
      every(:year)
      |> on(month: 3, day: 12)
      |> in_calendar(Calendrical.Islamic.UmmAlQura)
      |> in_years(years)

    mawlid
  end

  defp gregorian_starts(text, window) when is_binary(text),
    do: gregorian_starts(Tempo.from_iso8601!(text), window)

  defp gregorian_starts(%Tempo{} = recurrence, window) do
    {:ok, set} = Tempo.to_interval(recurrence, within: window)

    for interval <- IntervalSet.members(set) do
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      Date.convert!(date, Calendar.ISO)
    end
  end

  describe "an exclusion in a set" do
    test "takes out a member, or a member of a range" do
      assert years(Tempo.to_interval(~o"{2024Y,2026Y,2028Y,^2026Y}")) == [2024, 2028]

      assert years(Tempo.to_interval(~o"{2020Y..2030Y,^2026Y}")) ==
               Enum.to_list(2020..2030) -- [2026]
    end

    test "cuts a range with no end around what it takes out" do
      assert Tempo.to_interval(~o"{2017Y..,^2020Y}", within: ~o"2019Y/2022Y") ==
               {:ok, ~o"{2017Y/2019Y,2021Y/2022Y}"}

      assert years(Tempo.to_interval(~o"R/{2017Y..,^2020Y}/P1Y/FL1M2DN", within: ~o"2019Y/2022Y")) ==
               [2019, 2021, 2022]
    end

    test "leaves a range whole without one, and a range of months its months" do
      assert years(Tempo.to_interval(~o"{2020Y..2030Y}")) == Enum.to_list(2020..2030)
      assert {:ok, months} = Tempo.to_interval(~o"{2020-06..2020-09}")
      assert IntervalSet.count(months) == 4
    end
  end

  describe "a domain" do
    test "bounds the recurrence, less what it takes out" do
      assert years(Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN")) ==
               Enum.to_list(2020..2030)

      assert years(Tempo.to_interval(~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN")) ==
               Enum.to_list(2020..2030) -- [2026]

      assert {:ok, set} = Tempo.to_interval(~o"R/{2025Y}/P1Y/FL12M25DN")
      assert Enum.map(IntervalSet.members(set), &Interval.from/1) == [~o"2025Y12M25D"]
    end

    test "of exclusions alone takes its years from the window, written with braces or without" do
      for text <- ["R/{^2026Y}/P1Y/FL12M25DN", "R/^2026Y/P1Y/FL12M25DN"] do
        domain = Tempo.from_iso8601!(text)

        assert {text, years(Tempo.to_interval(domain, within: ~o"2024Y/2029Y"))} ==
                 {text, [2024, 2025, 2027, 2028, 2029]}
      end
    end

    test "is narrowed by a window" do
      domain = ~o"R/{2020Y..2049Y}/P1Y/FL11M1DN"
      assert years(Tempo.to_interval(domain, within: ~o"2029Y")) == [2029]
      assert years(Tempo.to_interval(domain, within: ~o"2028Y/2031Y")) == [2028, 2029, 2030, 2031]

      christmas = ~o"R/{2020Y..2030Y}/P1Y/FL12M25DN"
      assert [] = years(Tempo.to_interval(christmas, within: ~o"2060Y"))
      assert years(Tempo.to_interval(christmas, within: ~o"2025Y12M")) == [2025]
      assert [] = years(Tempo.to_interval(christmas, within: ~o"2025Y11M"))
    end

    test "keeps its exclusions and its filter within a window" do
      excluding = ~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN"
      assert [] = years(Tempo.to_interval(excluding, within: ~o"2026Y"))
      assert years(Tempo.to_interval(excluding, within: ~o"2025Y/2028Y")) == [2025, 2027, 2028]

      assert years(Tempo.to_interval(~o"R/{2020Y..2030Y}e/P1Y/FL1M1DN", within: ~o"2021Y/2024Y")) ==
               [2022, 2024]
    end
  end

  describe "a domain of another calendar" do
    test "is years of the calendar written after the recurrence" do
      # Rosh Hashanah 5787 and 5788, by Calendrical's own conversion.
      expected =
        for year <- [5787, 5788],
            do: Date.convert!(Date.new!(year, 1, 1, Calendrical.Hebrew), Calendar.ISO)

      assert gregorian_starts("R/{5787Y..5788Y}/P1Y/FL1M1DN[u-ca=hebrew]", ~o"2026Y/2028Y") ==
               expected

      # The Gregorian years a rule of another calendar falls in are a window,
      # another expression: 2026 through 2027 holds the same two.
      assert gregorian_starts("R/../P1Y/FL1M1DN[u-ca=hebrew]", ~o"2026Y/2027Y") == expected
    end

    test "is narrowed by a Gregorian window" do
      new_year_4663 = Date.convert!(Date.new!(4663, 1, 1, Calendrical.Chinese), Calendar.ISO)

      assert gregorian_starts("R/{4661Y..4664Y}/P1Y/FL1m1DN[u-ca=chinese]", ~o"2026Y") ==
               [new_year_4663]
    end

    test "open at either end is closed in its own calendar" do
      # 12 Rabi al-awwal 1435 falls in 2014, and in no other year of 1434 to 1436.
      mawlid = fn year ->
        Date.convert!(Date.new!(year, 3, 12, Calendrical.Islamic.UmmAlQura), Calendar.ISO)
      end

      assert mawlid.(1435).year == 2014

      for domain <- [
            [through: 1435],
            [from: 1435],
            [{:through, 1433}, 1435, {:from, 1439}],
            [through: 1436],
            [from: 1434]
          ] do
        assert {domain, gregorian_starts(mawlid_in(domain), ~o"2014Y")} ==
                 {domain, [mawlid.(1435)]}
      end

      for domain <- [[through: 1434], [from: 1436], [through: 1434, from: 1436]] do
        assert {domain, gregorian_starts(mawlid_in(domain), ~o"2014Y")} == {domain, []}
      end
    end

    test "gives what the rule with no domain gives, in the years it holds" do
      # 12 Rabi al-awwal falls twice in 2015: in 1436 and in 1437.
      expected =
        for year <- 1434..1439,
            do: Date.convert!(Date.new!(year, 3, 12, Calendrical.Islamic.UmmAlQura), Calendar.ISO)

      open = gregorian_starts("R/../P1Y/FL3M12DN[u-ca=islamic-umalqura]", ~o"2013Y/2017Y")
      assert open == expected

      assert gregorian_starts("R/{1436Y..}/P1Y/FL3M12DN[u-ca=islamic-umalqura]", ~o"2013Y/2017Y") ==
               Enum.drop(expected, 2)

      assert gregorian_starts("R/{..1436Y}/P1Y/FL3M12DN[u-ca=islamic-umalqura]", ~o"2013Y/2017Y") ==
               Enum.take(expected, 3)
    end
  end

  describe "a domain open at an end" do
    test "takes the end it lacks from the window" do
      window = ~o"2021Y/2027Y"

      assert years(Tempo.to_interval(~o"R/{2023Y..}/P1Y/FL1M2DN", within: window)) ==
               Enum.to_list(2023..2027)

      assert years(Tempo.to_interval(~o"R/{..2023Y}/P1Y/FL1M2DN", within: window)) == [
               2021,
               2022,
               2023
             ]

      assert years(
               Tempo.to_interval(~o"R/{..2019Y,2021Y..}/P1Y/FL1M2DN", within: ~o"2019Y/2022Y")
             ) ==
               [2019, 2021, 2022]
    end

    test "keeps its exclusions and its filter" do
      assert years(Tempo.to_interval(~o"R/{2017Y..,^2020Y}/P1Y/FL1M2DN", within: ~o"2019Y/2022Y")) ==
               [2019, 2021, 2022]

      assert years(Tempo.to_interval(~o"R/{2024Y..}e/P1Y/FL1M2DN", within: ~o"2021Y/2027Y")) ==
               [2024, 2026]
    end

    test "has nothing in a window before it, and with no window has no end" do
      assert [] = years(Tempo.to_interval(~o"R/{2030Y..}/P1Y/FL1M2DN", within: ~o"2026Y"))
      assert {:error, %Tempo.ConversionError{}} = Tempo.to_interval(~o"R/{2023Y..}/P1Y/FL1M2DN")
    end
  end

  describe "a cadence of several years" do
    test "is counted from the domain's first year, not the window's" do
      assert years(Tempo.to_interval(~o"R/{2020Y..2040Y}/P4Y/FL11M3DN", within: ~o"2019Y/2028Y")) ==
               [2020, 2024, 2028]

      assert years(Tempo.to_interval(~o"R/{2021Y..}/P4Y/FL7M1DN", within: ~o"2020Y/2030Y")) ==
               [2021, 2025, 2029]
    end

    test "keeps its phase past a year taken out" do
      assert years(
               Tempo.to_interval(~o"R/{2000Y..2040Y,^2024Y}/P4Y/FL11M3DN",
                 within: ~o"2019Y/2030Y"
               )
             ) == [2020, 2028]
    end

    test "gives the United States' election day, every four years since 1848" do
      # The Tuesday after the first Monday of November, by `Date` alone.
      election = fn year ->
        first_monday =
          Enum.find(1..7, &(Date.day_of_week(Date.new!(year, 11, &1)) == 1))

        Date.new!(year, 11, first_monday + 1)
      end

      assert gregorian_starts("R/{1848Y..}/P4Y/FLLL11M1K1IN/P7DN2K-1IN", ~o"2019Y/2028Y") ==
               Enum.map([2020, 2024, 2028], election)
    end
  end

  describe "a counted domain" do
    test "keeps its first occurrences, across the domain's runs" do
      assert years(Tempo.to_interval(~o"R3/{2020Y..2022Y,2025Y..2027Y}/P1Y/FL12M25DN")) ==
               [2020, 2021, 2022]

      assert years(Tempo.to_interval(~o"R4/{2020Y..2022Y,2025Y..2027Y}/P1Y/FL12M25DN")) ==
               [2020, 2021, 2022, 2025]

      assert years(Tempo.to_interval(~o"R1/{2020Y..2030Y}/P1Y/FL12M25DN")) == [2020]
    end

    test "counts from the domain's first period, not the window's" do
      assert years(Tempo.to_interval(~o"R3/{2020Y..2030Y}/P1Y/FL12M25DN", within: ~o"2021Y")) ==
               [2021]

      assert years(Tempo.to_interval(~o"R3/{2020Y..2030Y}/P1Y/FL12M25DN", within: ~o"2025Y")) ==
               []
    end
  end

  describe "the written form" do
    test "is read back as it is written" do
      for text <- [
            "R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN",
            "{2020Y..2030Y,^2026Y}",
            "{^2026Y}"
          ] do
        assert {:ok, value} = Tempo.from_iso8601(text)
        assert Tempo.to_iso8601(value) == {:ok, text}
      end
    end

    test "with a range open at an end is written as an interval, and reads back" do
      for text <- [
            "{2017Y..,^2020Y}",
            "R/{..2019Y,2021Y..}/P1Y/FL1M2DN",
            "R/{1848Y..}/P4Y/FL11MLL1K1IN/P9DN2K1IN"
          ] do
        assert {:ok, value} = Tempo.from_iso8601(text)
        assert Tempo.from_iso8601(Tempo.to_iso8601!(value)) == {:ok, value}
      end
    end

    test "of an exclusion alone in a start is written with braces" do
      assert Tempo.to_iso8601(~o"R/^2026Y/P1Y/FL12M25DN") == {:ok, "R/{^2026Y}/P1Y/FL12M25DN"}
    end
  end

  describe "a filter of years" do
    # Even and odd by the year's number, leap and common by `Date`.
    defp kept_by(:even, year), do: rem(year, 2) == 0
    defp kept_by(:odd, year), do: rem(year, 2) != 0
    defp kept_by(:leap, year), do: Date.leap_year?(Date.new!(year, 1, 1))
    defp kept_by(:common, year), do: not Date.leap_year?(Date.new!(year, 1, 1))

    defp christmas, do: every(:year) |> on(month: 12, day: 25)

    test "keeps the years of a domain it names" do
      for filter <- [:even, :odd, :leap, :common],
          {first, last} <- [{2000, 2010}, {2096, 2104}] do
        {:ok, christmas} = christmas() |> in_years(first..last) |> in_years(filter)

        assert {filter, first, years(Tempo.to_interval(christmas))} ==
                 {filter, first, Enum.filter(first..last, &kept_by(filter, &1))}
      end
    end

    test "keeps the years of a window, on a domain with no ends" do
      for filter <- [:even, :odd, :leap, :common] do
        {:ok, christmas} = christmas() |> in_years(filter)

        assert {filter, years(Tempo.to_interval(christmas, within: ~o"2000Y/2010Y"))} ==
                 {filter, Enum.filter(2000..2010, &kept_by(filter, &1))}

        assert {:error, _} = Tempo.to_interval(christmas)
      end
    end

    test "keeps a domain's exclusions" do
      assert years(Tempo.to_interval(~o"R/{2000Y..2010Y,^2004Y}e/P1Y/FL12M25DN")) ==
               [2000, 2002, 2006, 2008, 2010]
    end

    test "is written back as it was read" do
      for text <- [
            "R/{2000Y..2010Y}e/P1Y/FL12M25DN",
            "R/{2000Y..2010Y}o/P1Y/FL12M25DN",
            "R/{2000Y..2010Y}l/P1Y/FL12M25DN",
            "R/{2000Y..2010Y}c/P1Y/FL12M25DN",
            "R/..e/P1Y/FL12M25DN",
            "R/..o/P1Y/FL12M25DN",
            "R/..l/P1Y/FL12M25DN",
            "R/..c/P1Y/FL12M25DN"
          ] do
        assert Tempo.to_iso8601(Tempo.from_iso8601!(text)) == {:ok, text}
      end
    end
  end

  describe "an occurrence that runs on past its year" do
    # A holiday of forty days from 19 December, in 2026 only: its occurrence
    # runs to 27 January 2027, so a window of 2027 holds it.
    test "is in the window of the next year, from a domain or none" do
      in_2026 =
        Tempo.every!(~o"P1Y",
          from: IntervalSet.new!([Tempo.new!(year: 2026)]),
          select: [selection: [month: 12, day: 19], window: ~o"P40D"]
        )

      every_year =
        Tempo.every!(~o"P1Y", select: [selection: [month: 12, day: 19], window: ~o"P40D"])

      assert Tempo.to_interval(in_2026, within: ~o"2027") == {:ok, ~o"{2026-12-19/2027-01-27}"}
      assert Tempo.to_interval(in_2026, within: ~o"2028") == {:ok, ~o"{}"}

      assert Tempo.to_interval(every_year, within: ~o"2027") ==
               {:ok, ~o"{2026-12-19/2027-01-27,2027-12-19/2028-01-27}"}
    end
  end

  describe "a domain of several ranges" do
    # England's Early May bank holiday, the first Monday of May, every year
    # but 2020, when it moved to 8 May.
    test "steps through each range by the cadence" do
      until_2019 = Interval.new!(from: :open, to: Tempo.new!(year: 2019))
      from_2021 = Interval.new!(from: Tempo.new!(year: 2021), to: :open)

      early_may =
        Tempo.every!(~o"P1Y",
          from: IntervalSet.new!([until_2019, from_2021]),
          select: [month: 5, day_of_week: 1, instance: 1]
        )

      for year <- 2018..2026 do
        expected =
          if year == 2020,
            do: [],
            else: [first_monday_of_may(year)]

        {:ok, window} = Tempo.new(year: year)
        {:ok, days} = Tempo.to_interval(early_may, within: window)

        assert IntervalSet.map(days, &date_of/1) == expected, "#{year}"
      end
    end
  end

  defp date_of(span) do
    {:ok, date} = Tempo.to_date(Interval.from(span))
    date
  end

  defp first_monday_of_may(year) do
    Date.range(Date.new!(year, 5, 1), Date.new!(year, 5, 7))
    |> Enum.find(&(Date.day_of_week(&1) == 1))
  end

  describe "a window's carry-back" do
    # The day after Orthodox Easter, from 2000: the period before a window is
    # looked in for an occurrence that runs on into it, but never one before
    # the domain's first.
    test "stops at the domain's first year" do
      from_2000 =
        IntervalSet.new!([Interval.new!(from: Tempo.new!(year: 2000), to: :open)])

      monday_after =
        Tempo.every!(~o"P1Y",
          from: from_2000,
          select: [
            selection: [event: "orthodox-easter"],
            window: ~o"P2D",
            day_of_week: 1,
            instance: -1
          ]
        )

      assert Tempo.to_interval(monday_after, within: ~o"1999") == {:ok, ~o"{}"}

      assert Tempo.to_interval(monday_after, within: ~o"2000") ==
               {:ok, ~o"{2000-05-01/2000-05-01}"}
    end
  end
end
