defmodule Tempo.SeasonTest do
  @moduledoc """
  A season with no hemisphere, and the dates it has in one
  (`plans/seasons-by-locale.md`, decided 2026-10-08 and 2026-10-09).

  ISO 8601-2 numbers four seasons "independent of location": 21 is spring,
  22 summer, 23 autumn and 24 winter, wherever they are read. They were
  read as the northern seasons everywhere, so the spring of 2026 was March
  to May in Sydney. A season is now kept as it is written. It is given its
  dates by a territory or a locale where it is read, by
  `Tempo.in_territory/2`, and by `Tempo.to_interval/2` and what is built
  on it, which ask the application's default territory and then the
  current locale where none is named. What else needs its dates says so by
  name.

  The measure is the meteorological seasons as they are published: three
  whole months each, spring from March north of the equator and from
  September south of it. The dates are Elixir's own `Date`, and the side
  of the equator a territory lies on is written here, apart from the
  library that gives it. A value's span is read by `Tempo.Matrix.Extent`,
  which reads its units with `Date` and none of Tempo's comparisons.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.AbstractSeasonError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Matrix.Extent

  ## The measure

  # The month each season starts in, by the side of the equator.
  @first_month %{
    northern: %{21 => 3, 22 => 6, 23 => 9, 24 => 12},
    southern: %{21 => 9, 22 => 12, 23 => 3, 24 => 6}
  }

  # Territories wholly on one side of the equator, and some it runs through.
  @northern [:GB, :US, :JP, :DE, :CA, :IN, :EG, :MX]
  @southern [:AU, :NZ, :ZA, :AR, :CL, :UY]
  @both_sides [:BR, :ID, :EC, :KE, :CO]

  @day 86_400_000_000

  # The span of a season in a hemisphere, from the first day of its first
  # month to the first day of the month three on, in microseconds.
  defp expected(year, season, hemisphere) do
    first = Date.new!(year, @first_month[hemisphere][season], 1)
    {microseconds(first), microseconds(Date.shift(first, month: 3))}
  end

  defp microseconds(%Date{} = date), do: Date.to_gregorian_days(date) * @day

  defp span(value) do
    {:ok, %{spans: [span]}} = Extent.of(value)
    span
  end

  defp season(year, season), do: Tempo.from_iso8601!("#{year}-#{season}")

  defp dated(value, territory) do
    {:ok, dated} = Tempo.in_territory(value, territory)
    dated
  end

  describe "the measure" do
    test "has a year's four seasons one after another, a quarter of the year each" do
      for hemisphere <- [:northern, :southern] do
        spans = for season <- 21..24, do: expected(2026, season, hemisphere)
        in_time = Enum.sort(spans)

        for {{_from, to}, {next, _to}} <- Enum.zip(in_time, Enum.drop(in_time, 1)) do
          assert to == next
        end

        assert spans |> Enum.map(fn {from, to} -> div(to - from, @day) end) |> Enum.sum() == 365
      end
    end

    test "has a season six months apart either side of the equator" do
      for season <- 21..24 do
        {north, _to} = expected(2026, season, :northern)
        {south, _to} = expected(2026, season, :southern)

        assert abs(div(north - south, @day)) in 181..186
      end
    end
  end

  describe "a season of 21 to 24" do
    test "is kept as it is written, in every way it is written" do
      for {text, written_back} <- [
            {"2026-21", "2026Y21M"},
            {"2026Y21M", "2026Y21M"},
            {"2026-24", "2026Y24M"},
            {"-0044-22", "-44Y22M"}
          ] do
        value = Tempo.from_iso8601!(text)

        assert %Tempo{time: [year: _year, season: season]} = value
        assert season in 21..24
        assert Tempo.to_iso8601!(value) == written_back
        assert Tempo.from_iso8601!(written_back) == value
      end

      assert inspect(~o"2026-21") == ~s(~o"2026Y21M")
    end

    test "is coarser than a month and finer than a year" do
      assert Tempo.resolution(~o"2026-21") == {:season, 1}
      assert Tempo.year(~o"2026-21") == 2026
      assert Tempo.month(~o"2026-21") == nil
      assert Tempo.trunc(~o"2026-21", :year) == ~o"2026"
      assert Tempo.trunc(~o"2026-21", :month) == ~o"2026-21"
    end

    test "is read by Tempo.season/1, which is nil for what holds none" do
      for season <- 21..24 do
        assert Tempo.season(season(2026, season)) == season
      end

      assert Tempo.season(~o"2026-22?") == 22
      assert Tempo.season(~o"2026-06") == nil
      assert Tempo.season(~o"2026-25") == nil
      assert Tempo.season(~o"2026-21/2026-23") == nil
      assert Tempo.season(dated(~o"2026-21", :AU)) == nil
      assert_raise ArgumentError, fn -> Tempo.season(~o"{2026-21,2026-23}") end
      assert_raise ArgumentError, fn -> Tempo.season(:spring) end
    end

    test "is not expanded where the sigil is compiled" do
      assert %Tempo{time: [year: 2026, season: 23]} = ~o"2026-23"
      assert %Interval{from: %Tempo{time: [year: 2026, season: 21]}} = ~o"2026-21/2026-23"
    end

    test "is not the season of a hemisphere, which is its dates as it is read" do
      assert {:ok, %Interval{}} = Tempo.from_iso8601("2026-25")
      assert {:ok, %Interval{}} = Tempo.from_iso8601("2026-30")
    end
  end

  describe "Tempo.in_territory/2" do
    test "gives a season the months it has on the territory's side of the equator" do
      for {territories, hemisphere} <- [{@northern, :northern}, {@southern, :southern}],
          territory <- territories,
          year <- [1999, 2024, 2026],
          season <- 21..24 do
        assert {territory, year, season, span(dated(season(year, season), territory))} ==
                 {territory, year, season, expected(year, season, hemisphere)}
      end
    end

    test "gives a winter in the north and a summer in the south the year they start in" do
      assert dated(~o"2026-24", :GB) == ~o"2026-12/2027-03"
      assert dated(~o"2026-22", :AU) == ~o"2026-12/2027-03"
      assert dated(~o"2026-24", :AU) == ~o"2026-06/2026-09"
    end

    test "takes a territory, a locale and a language tag" do
      {:ok, tag} = Localize.validate_locale("es-CL")

      for territory <- [:AU, "AU", "au", "en-AU", :"en-AU", tag] do
        assert {territory, Tempo.in_territory(~o"2026-21", territory)} ==
                 {territory, {:ok, ~o"2026-09/2026-12"}}
      end
    end

    test "has no dates for a territory on both sides of the equator" do
      for territory <- @both_sides ++ [:"001"] do
        assert {^territory, {:error, %AbstractSeasonError{territory: ^territory} = error}} =
                 {territory, Tempo.in_territory(~o"2026-21", territory)}

        assert Exception.message(error) =~ "both sides of the equator"
        assert Exception.message(error) =~ "25 to 28 are the northern seasons"
      end
    end

    test "is an error for what is no territory" do
      assert {:error, %Localize.UnknownTerritoryError{}} = Tempo.in_territory(~o"2026-21", :ZZ)

      for junk <- ["nonsense", "", 42, :"", %{}, String.duplicate("x", 5_000)] do
        assert {^junk, {:error, %ArgumentError{}}} =
                 {junk, Tempo.in_territory(~o"2026-21", junk)}
      end
    end

    test "returns a value that holds no such season as it is, whatever the territory" do
      for value <- [~o"2026-03", ~o"2026-25", ~o"2026-03/2026-06", ~o"{2026,2027}", ~o"P1M"],
          territory <- [:AU, :BR, "nonsense", nil] do
        assert Tempo.in_territory(value, territory) == {:ok, value}
      end
    end

    test "gives each season of a set its dates, and each end of an interval where it starts" do
      assert dated(~o"{2026-21,2026-23}", :AU) == ~o"{2026-09/2026-12,2026-03/2026-06}"
      assert dated(~o"2026-22/2027-21", :NZ) == ~o"2026-12/2027-09"
      assert dated(~o"2026-21/2026-10-15", :ZA) == ~o"2026-09/2026-10-15"
    end

    test "keeps what qualifies the season, and its zone" do
      assert dated(~o"2026-21?", :AU) == ~o"2026-09?/2026-12?"
      assert dated(~o"2026-21[Australia/Sydney]", :AU) == ~o"2026-09/2026-12[Australia/Sydney]"
    end
  end

  describe "a season read with a territory or a locale" do
    test "is its dates there" do
      assert Tempo.from_iso8601("2026-21", territory: :AU) == {:ok, ~o"2026-09/2026-12"}
      assert Tempo.from_iso8601("2026-21", territory: :GB) == {:ok, ~o"2026-03/2026-06"}
      assert Tempo.from_iso8601("2026-21", locale: "en-AU") == {:ok, ~o"2026-09/2026-12"}
      assert Tempo.from_iso8601("2026-21/2026-10", territory: :NZ) == {:ok, ~o"2026-09/2026-10"}
    end

    test "is in the territory where both are given" do
      assert Tempo.from_iso8601("2026-21", locale: "en-AU", territory: :GB) ==
               {:ok, ~o"2026-03/2026-06"}
    end

    test "reads a locale as a locale: Arabic is no Argentina" do
      # `ar` is the Arabic language, whose territory is Egypt, and `AR` the
      # territory Argentina.
      assert Tempo.from_iso8601("2026-21", locale: "ar") == {:ok, ~o"2026-03/2026-06"}
      assert Tempo.from_iso8601("2026-21", territory: :AR) == {:ok, ~o"2026-09/2026-12"}
    end

    test "is kept as it is written with neither" do
      assert Tempo.from_iso8601("2026-21") == {:ok, ~o"2026Y21M"}
      assert Tempo.from_iso8601("2026-21", []) == {:ok, ~o"2026Y21M"}
      assert Tempo.from_iso8601("2026-21", strict: true) == {:ok, ~o"2026Y21M"}
    end

    test "is an error in a territory with no one hemisphere, and for what is none" do
      assert {:error, %AbstractSeasonError{territory: :BR}} =
               Tempo.from_iso8601("2026-21", territory: :BR)

      assert {:error, %ArgumentError{}} = Tempo.from_iso8601("2026-21", territory: "nonsense")
      assert {:error, %Localize.InvalidLocaleError{}} = Tempo.from_iso8601("2026-21", locale: 42)
    end

    test "leaves what holds no season alone, and does not read the option for it" do
      assert Tempo.from_iso8601("2026-03", territory: "nonsense") == {:ok, ~o"2026-03"}
      assert Tempo.from_iso8601("2026-25", territory: :AU) == Tempo.from_iso8601("2026-25")
    end
  end

  describe "Tempo.to_interval/2" do
    test "gives a season its dates in the territory or the locale it is given" do
      for {territories, hemisphere} <- [{@northern, :northern}, {@southern, :southern}],
          territory <- territories,
          season <- 21..24 do
        {:ok, interval} = Tempo.to_interval(season(2026, season), territory: territory)

        assert {territory, season, span(interval)} ==
                 {territory, season, expected(2026, season, hemisphere)}
      end

      assert Tempo.to_interval(~o"2026-21", locale: "en-NZ") == {:ok, ~o"2026-09/2026-12"}
      assert Tempo.to_interval(~o"2026-21", locale: "ar") == {:ok, ~o"2026-03/2026-06"}
    end

    test "asks the current locale where it is given neither" do
      for {locale, hemisphere} <- [
            {"en-AU", :southern},
            {"en-GB", :northern},
            {"en-ZA", :southern}
          ] do
        Localize.put_locale(locale)
        {:ok, interval} = Tempo.to_interval(~o"2026-22")

        assert {locale, span(interval)} == {locale, expected(2026, 22, hemisphere)}
      end
    end

    test "is the named error where the locale's territory has no one hemisphere" do
      Localize.put_locale("en-KE")

      assert {:error, %AbstractSeasonError{territory: :KE}} = Tempo.to_interval(~o"2026-21")
      assert Tempo.to_interval(~o"2026-21", territory: :GB) == {:ok, ~o"2026-03/2026-06"}

      # What is built on the conversion says so too, and a predicate, with
      # only true and false to give, raises it.
      assert {:error, %AbstractSeasonError{}} = Tempo.duration(~o"2026-21/2026-23")
      assert {:error, %AbstractSeasonError{}} = Tempo.relation(~o"2026-21", ~o"2026-04")
      assert {:error, %AbstractSeasonError{}} = Tempo.union(~o"2026-21", ~o"2026-04")
      assert_raise AbstractSeasonError, fn -> Tempo.overlaps?(~o"2026-21", ~o"2026-04") end
    end

    test "gives a season that is the window its dates too" do
      {:ok, monthly} =
        Tempo.to_interval(~o"R/2026-01-01/P1M", within: ~o"2026-21", territory: :AU)

      assert Enum.map(IntervalSet.members(monthly), &span/1) == month_spans(9..11)

      {:ok, in_the_north} =
        Tempo.to_interval(~o"R/2026-01-01/P1M", within: ~o"2026-21", territory: :GB)

      assert Enum.map(IntervalSet.members(in_the_north), &span/1) == month_spans(3..5)
    end

    test "passes the territory to to_interval_set/2" do
      {:ok, set} = Tempo.to_interval_set(~o"2026-21", territory: :AU)

      assert IntervalSet.members(set) == [~o"2026-09/2026-12"]
    end
  end

  # Each month of 2026 from its first day to the first day of the next.
  defp month_spans(months) do
    for month <- months do
      first = Date.new!(2026, month, 1)
      {microseconds(first), microseconds(Date.shift(first, month: 1))}
    end
  end

  describe "what is built on to_interval/2" do
    # Each is asked of the season with no hemisphere in a locale, and of the
    # season given the dates the measure has for that locale's hemisphere:
    # the two agree.
    for {locale, territory} <- [{"en-GB", :GB}, {"en-AU", :AU}] do
      test "answers as the season's dates in #{locale}" do
        Localize.put_locale(unquote(locale))

        for season <- 21..24, other <- [~o"2026-04", ~o"2026-10-15", ~o"2026", ~o"2027-01"] do
          abstract = season(2026, season)
          there = dated(abstract, unquote(territory))

          assert Tempo.relation(abstract, other) == Tempo.relation(there, other)
          assert Tempo.overlaps?(abstract, other) == Tempo.overlaps?(there, other)
          assert Tempo.contains?(abstract, other) == Tempo.contains?(there, other)
          assert Tempo.before?(abstract, other) == Tempo.before?(there, other)
          assert Tempo.compare(abstract, other) == Tempo.compare(Interval.from(there), other)
          assert Tempo.intersection(abstract, other) == Tempo.intersection(there, other)
          assert Tempo.union(abstract, other) == Tempo.union(there, other)
          assert Tempo.duration(abstract) == Tempo.duration(there)
          assert Tempo.select(abstract, [1]) == Tempo.select(there, [1])
          assert Tempo.select(~o"2026/2028", abstract) == Tempo.select(~o"2026/2028", there)
        end
      end

      test "answers for an interval of seasons as its dates in #{locale}" do
        Localize.put_locale(unquote(locale))

        for text <- ["2026-22/2027-21", "2026-21/2026-10-15", "2026-21/P1M"],
            other <- [~o"2026-10", ~o"2027-02"] do
          abstract = Tempo.from_iso8601!(text)
          there = dated(abstract, unquote(territory))

          assert Tempo.relation(abstract, other) == Tempo.relation(there, other)
          assert Tempo.overlaps?(abstract, other) == Tempo.overlaps?(there, other)
          assert Tempo.duration(abstract) == Tempo.duration(there)
          assert Tempo.at_least?(abstract, ~o"P3M") == Tempo.at_least?(there, ~o"P3M")
          assert Tempo.select(abstract, [1]) == Tempo.select(there, [1])
          assert Tempo.count_workdays(abstract, :US) == Tempo.count_workdays(there, :US)
        end
      end
    end

    test "orders seasons and months by where each starts" do
      Localize.put_locale("en-AU")

      # South of the equator: autumn in March, April, winter in June, spring.
      assert Enum.sort([~o"2026-21", ~o"2026-24", ~o"2026-04", ~o"2026-23"], Tempo) ==
               [~o"2026-23", ~o"2026-04", ~o"2026-24", ~o"2026-21"]
    end

    test "says an interval of seasons is none where the hemisphere has them in another order" do
      Localize.put_locale("en-GB")
      autumn_to_spring = ~o"2026-23/2026-21"

      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.to_interval(autumn_to_spring)
      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.duration(autumn_to_spring)

      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Tempo.relation(autumn_to_spring, ~o"2026-04")

      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.select(autumn_to_spring, [1])

      assert_raise Tempo.IntervalEndpointsError, fn ->
        Tempo.overlaps?(autumn_to_spring, ~o"2026")
      end

      assert_raise Tempo.IntervalEndpointsError, fn ->
        Tempo.at_least?(autumn_to_spring, ~o"P1M")
      end

      Localize.put_locale("en-AU")

      assert Tempo.to_interval(autumn_to_spring) == {:ok, ~o"2026-03/2026-09"}
      assert Tempo.duration(autumn_to_spring) == ~o"P6M"
    end
  end

  describe "what needs a season's dates and is given none" do
    test "is the named error, which says how the season is given a hemisphere" do
      season = ~o"2026-21"

      for {operation, result} <- [
            {"shift by a month", Tempo.shift(season, ~o"P1M")},
            {"shift by a day", Tempo.shift(season, day: 1)},
            {"shift by a year and a month", Tempo.shift(season, ~o"P1Y1M")},
            {"extend", Tempo.extend(season)},
            {"extend_resolution", Tempo.extend_resolution(season, :day)},
            {"at_resolution month", Tempo.at_resolution(season, :month)},
            {"at_resolution day", Tempo.at_resolution(season, :day)},
            {"round", Tempo.round(season, :year)},
            {"at", Tempo.at(season, ~o"T10")},
            {"on", Tempo.on(~o"T10", season)},
            {"shift an interval", Tempo.shift(~o"2026-21/2026-23", ~o"P1M")},
            {"truncate an interval", Tempo.trunc(~o"2026-21/2026-23", :month)},
            {"round an interval", Tempo.round(~o"2026-21/2026-10-15", :month)},
            {"at an interval", Tempo.at(~o"2026-21/2026-23", ~o"T10")}
          ] do
        assert {^operation, {:error, %AbstractSeasonError{} = error}} = {operation, result}
        assert Exception.message(error) =~ "Tempo.in_territory/2"
        assert Exception.message(error) =~ ":territory"
      end
    end

    test "is raised by a walk and by what reads a date" do
      for walk <- [
            fn -> Enum.take(~o"2026-21", 1) end,
            fn -> Enum.count(~o"2026-21") end,
            fn -> Enum.member?(~o"2026-21", ~o"2026-04") end,
            fn -> Enum.take(~o"2026-21/2026-23", 1) end,
            fn -> Enum.member?(~o"2026-21/2026-10-15", ~o"2026-04-01") end,
            fn -> Enum.take(~o"R3/2026-21/P1Y", 1) end,
            fn -> Tempo.day_of_week(~o"2026-21") end,
            fn -> Tempo.day_of_year(~o"2026-21") end,
            fn -> Tempo.quarter_of_year(~o"2026-21") end
          ] do
        assert_raise AbstractSeasonError, walk
      end
    end

    test "is answered where no dates are needed: a year on is a season as this one is" do
      assert Tempo.shift(~o"2026-21", ~o"P1Y") == ~o"2027-21"
      assert Tempo.shift(~o"2026-21", year: -2) == ~o"2024-21"
      assert Tempo.shift(~o"2026-21/2026-23", ~o"P1Y") == ~o"2027-21/2027-23"
      assert Enum.to_list(~o"{2026-21..2026-23}") == [~o"2026-21", ~o"2026-22", ~o"2026-23"]
      assert {:ok, ~o"2026Y21M[Europe/Paris]"} = Tempo.in_zone(~o"2026-21", "Europe/Paris")
    end

    test "is answered once it has its dates" do
      spring = dated(~o"2026-21", :AU)

      assert Tempo.shift(spring, ~o"P1M") == ~o"2026-10/2027-01"
      assert Enum.map(spring, &Tempo.month/1) == [9, 10, 11]
      assert {:ok, ~o"2026Y9MT10H/12MT10H"} = Tempo.at(spring, ~o"T10")
    end
  end

  describe "a season written out" do
    test "is its dates in the territory of the locale it is rendered in" do
      for {locale, territory} <- [{"en-AU", :AU}, {"en-GB", :GB}, {"fr", :FR}] do
        assert {locale, Tempo.to_string(~o"2026-21", locale: locale)} ==
                 {locale, Tempo.to_string(dated(~o"2026-21", territory), locale: locale)}
      end

      assert Tempo.to_string(~o"2026-21", locale: "en-AU") !=
               Tempo.to_string(~o"2026-21", locale: "en-GB")
    end

    test "is told from where it starts there" do
      assert Tempo.to_relative_string(~o"2026-21", locale: "en-AU", relative_to: ~o"2026-08") ==
               Tempo.to_relative_string(~o"2026-09", locale: "en-AU", relative_to: ~o"2026-08")
    end

    test "is explained by its name, and given no hemisphere" do
      for {season, name} <- [{21, "spring"}, {22, "summer"}, {23, "autumn"}, {24, "winter"}] do
        explained = Tempo.explain(season(2026, season))

        assert explained =~ "The #{name} of 2026, in no hemisphere."
        assert explained =~ "Tempo.in_territory/2"
        refute explained =~ "Span:"
      end

      assert Tempo.explain(~o"2026-21/2026-23") =~ "From: the spring of 2026, in no hemisphere."
    end
  end

  describe "a season in another calendar" do
    test "is the season of that kind that starts within the year, either side of the equator" do
      # Hebrew 5787 runs from 12 September 2026 to 1 October 2027: the March
      # that starts a northern spring within it is 2027's, and so is the
      # September that starts a southern one, 1 September 2026 being of the
      # year before.
      first = Date.convert!(Date.new!(5787, 1, 1, Calendrical.Hebrew), Calendar.ISO)
      next = Date.convert!(Date.new!(5788, 1, 1, Calendrical.Hebrew), Calendar.ISO)

      assert {first, next} == {~D[2026-09-12], ~D[2027-10-02]}

      {:ok, hebrew} = Tempo.from_iso8601("5787-21[u-ca=hebrew]")
      {:ok, north} = Tempo.in_territory(hebrew, :IL)
      {:ok, south} = Tempo.in_territory(hebrew, :AU)

      assert Tempo.relation(north, ~o"2027-03/2027-06") == :equals
      assert Tempo.relation(south, ~o"2027-09/2027-12") == :equals
    end
  end
end
