defmodule Tempo.ExclusionDomainTest do
  # The `^` exclusion-member syntax: in a set (`{2020Y..2030Y,^2026Y}`) and as a
  # recurrence domain in the interval slot (`R/{…}/P1Y`, `R/^2026Y/P1Y`).
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  defp years(%IntervalSet{} = set) do
    set
    |> IntervalSet.members()
    |> Enum.map(
      &(&1
        |> Interval.from()
        |> Tempo.year())
    )
    |> Enum.sort()
  end

  describe "^ exclusion members in a set" do
    test "subtracts a discrete member" do
      {:ok, set} = Tempo.to_interval(~o"{2024Y,2026Y,2028Y,^2026Y}")
      assert years(set) == [2024, 2028]
    end

    test "subtracts from a range member" do
      {:ok, set} = Tempo.to_interval(~o"{2020Y..2030Y,^2026Y}")
      result = years(set)
      assert Enum.count(result) == 10
      refute 2026 in result
      assert List.first(result) == 2020
      assert List.last(result) == 2030
    end

    test "a plain range member materialises inclusively" do
      {:ok, set} = Tempo.to_interval(~o"{2020Y..2030Y}")
      assert years(set) == Enum.to_list(2020..2030)
    end

    test "a month range materialises to its months" do
      {:ok, set} = Tempo.to_interval(~o"{2020-06..2020-09}")
      assert IntervalSet.count(set) == 4
    end

    test "an open-ended range cannot materialise" do
      assert {:error, %Tempo.ConversionError{reason: :open_range}} =
               Tempo.to_interval(%Tempo.Set{
                 type: :all,
                 set: [%Tempo.Range{first: ~o"2020Y", last: :undefined}]
               })
    end
  end

  describe "a recurrence domain in the interval slot" do
    test "a plain-member domain is self-bounding" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN")
      assert years(set) == Enum.to_list(2020..2030)
    end

    test "a domain with ^ drops the excluded year" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN")
      result = years(set)
      assert Enum.count(result) == 10
      refute 2026 in result
    end

    test "each occurrence is the selection's date within its year" do
      {:ok, set} = Tempo.to_interval(~o"R/{2025Y}/P1Y/FL12M25DN")
      assert [interval] = IntervalSet.members(set)
      assert Interval.from(interval) == ~o"2025Y12M25D"
    end

    test "an exclusions-only domain (braces) needs a window and subtracts" do
      {:ok, set} = Tempo.to_interval(~o"R/{^2026Y}/P1Y/FL12M25DN", within: ~o"2024Y/2029Y")
      result = years(set)
      assert [_, _, _, _] = result
      refute 2026 in result
    end

    test "the bare ^value form (no braces) excludes a single value" do
      {:ok, set} = Tempo.to_interval(~o"R/^2026Y/P1Y/FL12M25DN", within: ~o"2024Y/2029Y")
      result = years(set)
      assert [_, _, _, _] = result
      refute 2026 in result
    end
  end

  # A self-bounding domain needs no `:within` window, but one that is supplied
  # still narrows it: occurrences are kept when they overlap the window, exactly
  # as for a recurrence without a domain.
  describe "a supplied :within window narrows a self-bounding domain" do
    test "a single-year window keeps only that year" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2049Y}/P1Y/FL11M1DN", within: ~o"2029Y")
      assert years(set) == [2029]
    end

    test "a multi-year window keeps the domain years it spans" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2049Y}/P1Y/FL11M1DN", within: ~o"2028Y/2031Y")
      assert years(set) == [2028, 2029, 2030]
    end

    test "a window outside the domain keeps nothing" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN", within: ~o"2060Y")
      assert years(set) == []
    end

    test "a window finer than the domain period keeps only the occurrences inside it" do
      {:ok, december} =
        Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN", within: ~o"2025Y12M")

      assert years(december) == [2025]

      {:ok, november} =
        Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN", within: ~o"2025Y11M")

      assert years(november) == []
    end

    test "exclusions still apply inside the window" do
      domain = ~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN"

      {:ok, excluded} = Tempo.to_interval(domain, within: ~o"2026Y")
      assert years(excluded) == []

      {:ok, around} = Tempo.to_interval(domain, within: ~o"2025Y/2028Y")
      assert years(around) == [2025, 2027]
    end

    test "a year filter still applies inside the window" do
      {:ok, set} = Tempo.to_interval(~o"R/{2020Y..2030Y}e/P1Y/FL1M1DN", within: ~o"2021Y/2024Y")
      assert years(set) == [2022]
    end

    test "a calendar recurrence's domain narrows to the window" do
      # The years of the domain are of the recurrence's calendar: 4663 of
      # the Chinese calendar starts on 17 February 2026.
      {:ok, set} =
        Tempo.to_interval(~o"R/{4661Y..4664Y}/P1Y/FL1m1DN[u-ca=chinese]", within: ~o"2026Y")

      assert [interval] = IntervalSet.members(set)

      {:ok, date} =
        interval
        |> Interval.from()
        |> Tempo.to_date()

      assert Date.convert!(date, Calendar.ISO) == ~D[2026-02-17]
    end

    test "a domain's years are of the calendar written after the recurrence" do
      # A calendar is written once, after the whole expression, and is the
      # calendar of every part of it: the domain's years are Hebrew years.
      # Rosh Hashanah 5787 and 5788 fall in 2026 and 2027.
      {:ok, set} = Tempo.to_interval(~o"R/{5787Y..5788Y}/P1Y/FL1M1DN[u-ca=hebrew]")

      dates =
        for interval <- IntervalSet.members(set) do
          {:ok, date} =
            interval
            |> Interval.from()
            |> Tempo.to_date()

          Date.convert!(date, Calendar.ISO)
        end

      assert dates == [~D[2026-09-12], ~D[2027-10-02]]

      # The Gregorian years a rule of another calendar falls in are a
      # window, which is another expression.
      {:ok, windowed} =
        Tempo.to_interval(~o"R/../P1Y/FL1M1DN[u-ca=hebrew]", within: ~o"2026Y/2028Y")

      assert Enum.map(IntervalSet.members(windowed), &Interval.from/1) ==
               Enum.map(IntervalSet.members(set), &Interval.from/1)
    end
  end

  describe "an open-ended domain beside a window of another calendar" do
    # A window is another expression, and may be of another calendar. The
    # end it gives an open range is a year of the range's calendar: a
    # Gregorian year closed a range of Islamic years as the Islamic year of
    # that number, and `{..1435Y}` within 2014 selected nothing.
    defp gregorian_starts(text, window) do
      {:ok, set} = Tempo.to_interval(Tempo.from_iso8601!(text), within: window)

      for interval <- IntervalSet.members(set) do
        {:ok, date} =
          interval
          |> Interval.from()
          |> Tempo.to_date()

        Date.convert!(date, Calendar.ISO)
      end
    end

    test "is closed in its own calendar, at either end" do
      # 12 Rabi al-awwal 1435 is 13 January 2014.
      for domain <- [
            "{..1435Y}",
            "{1435Y..}",
            "{..1433Y,1435Y,1439Y..}",
            "{..1436Y}",
            "{1434Y..}"
          ] do
        text = "R/#{domain}/P1Y/FL3M12DN[u-ca=islamic-umalqura]"
        assert {domain, gregorian_starts(text, ~o"2014Y")} == {domain, [~D[2014-01-13]]}
      end
    end

    test "leaves out the years its range leaves out" do
      for domain <- ["{..1434Y}", "{1436Y..}", "{..1434Y,1436Y..}"] do
        text = "R/#{domain}/P1Y/FL3M12DN[u-ca=islamic-umalqura]"
        assert {domain, gregorian_starts(text, ~o"2014Y")} == {domain, []}
      end
    end

    test "gives what the rule with no domain gives, in the years the domain holds" do
      # The date falls twice in 2015: 3 January (1436) and 23 December (1437).
      open = gregorian_starts("R/../P1Y/FL3M12DN[u-ca=islamic-umalqura]", ~o"2013Y/2018Y")

      assert open ==
               [~D[2013-01-24], ~D[2014-01-13], ~D[2015-01-03], ~D[2015-12-23], ~D[2016-12-11]] ++
                 [~D[2017-11-30]]

      from_1436 = "R/{1436Y..}/P1Y/FL3M12DN[u-ca=islamic-umalqura]"
      assert gregorian_starts(from_1436, ~o"2013Y/2018Y") == Enum.drop(open, 2)

      to_1436 = "R/{..1436Y}/P1Y/FL3M12DN[u-ca=islamic-umalqura]"
      assert gregorian_starts(to_1436, ~o"2013Y/2018Y") == Enum.take(open, 3)
    end

    test "is closed as before by a window of its own calendar" do
      assert gregorian_starts("R/{..2019Y,2021Y..}/P1Y/FL12M25DN", ~o"2019Y/2023Y") ==
               [~D[2019-12-25], ~D[2021-12-25], ~D[2022-12-25]]
    end
  end

  describe "an open-ended domain takes its missing end from the window" do
    test "an open upper end runs to the window's end" do
      {:ok, set} = Tempo.to_interval(~o"R/{2023Y..}/P1Y/FL1M2DN", within: ~o"{2021..2027}Y")
      assert years(set) == [2023, 2024, 2025, 2026, 2027]
    end

    test "an open lower end runs from the window's start" do
      {:ok, set} = Tempo.to_interval(~o"R/{..2023Y}/P1Y/FL1M2DN", within: ~o"{2021..2027}Y")
      assert years(set) == [2021, 2022, 2023]
    end

    test "two open ranges leave out the years between them" do
      {:ok, set} =
        Tempo.to_interval(~o"R/{..2019Y,2021Y..}/P1Y/FL1M2DN", within: ~o"{2019..2022}Y")

      assert years(set) == [2019, 2021, 2022]
    end

    test "an exclusion and a year filter still apply" do
      {:ok, excluded} =
        Tempo.to_interval(~o"R/{2017Y..,^2020Y}/P1Y/FL1M2DN", within: ~o"{2019..2022}Y")

      assert years(excluded) == [2019, 2021, 2022]

      {:ok, even} = Tempo.to_interval(~o"R/{2024Y..}e/P1Y/FL1M2DN", within: ~o"{2021..2027}Y")
      assert years(even) == [2024, 2026]
    end

    test "a window before the range yields nothing" do
      {:ok, set} = Tempo.to_interval(~o"R/{2030Y..}/P1Y/FL1M2DN", within: ~o"2026Y")
      assert years(set) == []
    end

    test "without a window an open range is an error, not a raise" do
      assert {:error, %Tempo.ConversionError{reason: :open_range}} =
               Tempo.to_interval(~o"R/{2023Y..}/P1Y/FL1M2DN")
    end
  end

  describe "a multi-period cadence steps through the domain" do
    test "every fourth year, counted from the domain's first year" do
      {:ok, set} =
        Tempo.to_interval(~o"R/{2020Y..2040Y}/P4Y/FL11M3DN", within: ~o"{2019..2028}Y")

      assert years(set) == [2020, 2024, 2028]
    end

    test "the domain, not the window, sets the phase" do
      {:ok, set} = Tempo.to_interval(~o"R/{2021Y..}/P4Y/FL7M1DN", within: ~o"{2020..2030}Y")
      assert years(set) == [2021, 2025, 2029]
    end

    test "US presidential Election Day, every four years since 1848" do
      {:ok, set} =
        Tempo.to_interval(~o"R/{1848Y..}/P4Y/FLLL11M1K1IN/P7DN2K-1IN", within: ~o"{2019..2028}Y")

      dates =
        set
        |> IntervalSet.members()
        |> Enum.map(fn interval ->
          {:ok, date} =
            interval
            |> Interval.from()
            |> Tempo.to_date()

          date
        end)

      assert dates == [~D[2020-11-03], ~D[2024-11-05], ~D[2028-11-07]]
    end

    test "an excluded year keeps the phase of the others" do
      {:ok, set} =
        Tempo.to_interval(~o"R/{2000Y..2040Y,^2024Y}/P4Y/FL11M3DN", within: ~o"{2019..2030}Y")

      assert years(set) == [2020, 2028]
    end
  end

  describe "a counted domain" do
    test "keeps its first occurrences, across the domain's runs" do
      {:ok, set} = Tempo.to_interval(~o"R3/{2020Y..2022Y,2025Y..2027Y}/P1Y/FL12M25DN")
      assert years(set) == [2020, 2021, 2022]

      {:ok, set} = Tempo.to_interval(~o"R4/{2020Y..2022Y,2025Y..2027Y}/P1Y/FL12M25DN")
      assert years(set) == [2020, 2021, 2022, 2025]

      {:ok, set} = Tempo.to_interval(~o"R1/{2020Y..2030Y}/P1Y/FL12M25DN")
      assert years(set) == [2020]
    end

    test "counts from the domain's first period, not the window's" do
      {:ok, set} = Tempo.to_interval(~o"R3/{2020Y..2030Y}/P1Y/FL12M25DN", within: ~o"2021Y")
      assert years(set) == [2021]

      {:ok, set} = Tempo.to_interval(~o"R3/{2020Y..2030Y}/P1Y/FL12M25DN", within: ~o"2025Y")
      assert years(set) == []
    end
  end

  describe "round-trip" do
    test "a domain recurrence with ^ round-trips faithfully" do
      value = ~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN"
      iso = Tempo.to_iso8601!(value)
      assert iso == "R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN"
      assert {:ok, ^value} = Tempo.from_iso8601(iso)
    end

    test "a standalone set with ^ round-trips" do
      assert Tempo.to_iso8601!(~o"{2020Y..2030Y,^2026Y}") == "{2020Y..2030Y,^2026Y}"
    end

    test "an exclusions-only set renders with braces" do
      assert Tempo.to_iso8601!(~o"{^2026Y}") == "{^2026Y}"
    end

    test "the bare ^ form canonicalises to braces" do
      assert Tempo.to_iso8601!(~o"R/^2026Y/P1Y/FL12M25DN") == "R/{^2026Y}/P1Y/FL12M25DN"
    end
  end
end
