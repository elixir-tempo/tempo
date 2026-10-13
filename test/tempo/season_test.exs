defmodule Tempo.SeasonTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{ConversionError, Interval, IntervalEndpointsError, IntervalSet}

  # A season's dates (`plans/seasons-by-locale.md`; `plans/decisions.md`,
  # 19 and 20). The seasons 21 to 24 are three whole months the hemisphere
  # chooses; 25 to 28 and 29 to 32 are the hemispheres' own, each from an
  # equinox or a solstice to the next.

  # The months of each season in each hemisphere, written apart from the
  # library: the first month and the year it is in, the last and its year.
  @months [
    {21, :GB, {2026, 3}, {2026, 5}},
    {22, :GB, {2026, 6}, {2026, 8}},
    {23, :GB, {2026, 9}, {2026, 11}},
    {24, :GB, {2026, 12}, {2027, 2}},
    {21, :AU, {2026, 9}, {2026, 11}},
    {22, :AU, {2026, 12}, {2027, 2}},
    {23, :AU, {2026, 3}, {2026, 5}},
    {24, :AU, {2026, 6}, {2026, 8}}
  ]

  # The days the equinoxes and solstices of 2026 and the March equinox of
  # 2027 fall on (UTC), from the almanac: each astronomical season begins
  # on one and ends the day before the next.
  @turns %{
    25 => {~o"2026-03-20", ~o"2026-06-20"},
    26 => {~o"2026-06-21", ~o"2026-09-22"},
    27 => {~o"2026-09-23", ~o"2026-12-20"},
    28 => {~o"2026-12-21", ~o"2027-03-19"},
    29 => {~o"2026-09-23", ~o"2026-12-20"},
    30 => {~o"2026-12-21", ~o"2027-03-19"},
    31 => {~o"2026-03-20", ~o"2026-06-20"},
    32 => {~o"2026-06-21", ~o"2026-09-22"}
  }

  describe "a season of 21 to 24 in a territory" do
    test "is its three months in that hemisphere" do
      for {season, territory, {first_year, first}, {last_year, last}} <- @months do
        value = Tempo.new!(year: 2026, season: season)

        {:ok, expected} =
          Interval.new(
            from: Tempo.new!(year: first_year, month: first),
            to: Tempo.new!(year: last_year, month: last)
          )

        assert Tempo.in_territory(value, territory) == {:ok, expected}
      end
    end

    test "is named by a territory or by a locale, where it is read and where it is asked for" do
      spring = ~o"2026-09/2026-11"
      assert Tempo.from_iso8601("2026-21", territory: :AU) == {:ok, spring}
      assert Tempo.from_iso8601("2026-21", locale: "en-AU") == {:ok, spring}
      assert Tempo.to_interval(~o"2026-21", territory: "AU") == {:ok, spring}
      assert Tempo.to_interval(~o"2026-21", locale: "en-AU") == {:ok, spring}
      assert Tempo.in_territory(~o"2026-21", "en-AU") == {:ok, spring}
    end

    test "has none where the equator runs through the territory" do
      for territory <- [:BR, :KE, :"001"] do
        assert {:error, %ConversionError{reason: {:no_hemisphere, ^territory}} = error} =
                 Tempo.in_territory(~o"2026-21", territory)

        assert Exception.message(error) =~ "on no one side of the equator"
      end

      assert {:error, %ArgumentError{}} = Tempo.in_territory(~o"2026-21", "nowhere at all")
    end

    test "is given to each end of an interval and each member of a set" do
      assert Tempo.in_territory(~o"2026-21/2026-22", :GB) == {:ok, ~o"2026-03/2026-08"}

      assert Tempo.in_territory(~o"{2026-21,2026-23}", :AU) ==
               {:ok, ~o"{2026-09/2026-11,2026-03/2026-05}"}
    end

    test "holds an interval to the order of its hemisphere" do
      assert {:ok, _} = Tempo.in_territory(~o"2026-21/2026-23", :GB)

      assert {:error, %IntervalEndpointsError{reason: :order}} =
               Tempo.in_territory(~o"2026-21/2026-23", :AU)
    end

    test "leaves a season of a hemisphere, and what is no season, as it was" do
      assert Tempo.in_territory(~o"2026-25", :AU) == {:ok, ~o"2026-25"}
      assert Tempo.in_territory(~o"2026-06-15", :AU) == {:ok, ~o"2026-06-15"}
    end
  end

  describe "a season of a hemisphere" do
    test "runs from its equinox or solstice to the day before the next" do
      for {season, {first, last}} <- @turns do
        value = Tempo.new!(year: 2026, season: season)
        assert Enum.at(value, 0) == first, "season #{season} begins"
        assert Enum.at(value, -1) == last, "season #{season} ends"
      end
    end

    test "is kept as it is written, and has a length in days" do
      assert Tempo.to_iso8601!(~o"2026-25") == "2026Y25M"
      assert Tempo.to_interval(~o"2026-25") == {:ok, ~o"2026-25/2026-25"}
      assert Tempo.duration(~o"2026-25") == ~o"P93D"
      assert Tempo.duration(~o"2026-25/2026-26") == ~o"P187D"
    end

    test "is held to its dates as an interval is read" do
      assert {:ok, _} = Tempo.from_iso8601("2026-31/2026-29")

      assert {:error, %IntervalEndpointsError{reason: :order}} =
               Tempo.from_iso8601("2026-29/2026-31")
    end

    test "relates and combines as the span it is" do
      assert Tempo.relation(~o"2026-25", ~o"2026-04") == :contains
      assert Tempo.before?(~o"2026-25", ~o"2026-07")
      assert Tempo.intersection(~o"2026-25", ~o"2026-06") == {:ok, ~o"{2026-06/2026-06-20}"}

      {:ok, firsts} = Tempo.select(~o"2026-25", ~o"1D")
      assert IntervalSet.map(firsts, &Tempo.month/1) == [4, 5, 6]
    end
  end

  describe "any season" do
    test "is moved by whole years, and by nothing finer" do
      assert Tempo.shift(~o"2026-25", year: 1) == {:ok, ~o"2027-25"}
      assert Tempo.shift(~o"2026-21", year: -2) == {:ok, ~o"2024-21"}

      assert {:error, %ConversionError{reason: {:season_moved, _}} = error} =
               Tempo.shift(~o"2026-21", month: 1)

      assert Exception.message(error) =~ "moved by whole years"
    end

    test "has no dates in a calendar that is not the Gregorian" do
      assert {:error, %ConversionError{reason: :season}} =
               Tempo.duration(~o"5786-25[u-ca=hebrew]")
    end

    test "of 21 to 24 is read in the order EDTF holds them to, where no territory is named" do
      assert {:ok, _} = Tempo.from_iso8601("2026-21/2026-23")

      assert {:error, %IntervalEndpointsError{reason: :order}} =
               Tempo.from_iso8601("2026-23/2026-21")
    end

    # Autumn comes before spring south of the equator: with a territory
    # named as it is read, an interval is held to the order of that
    # hemisphere and not to the order of the numbers.
    test "of 21 to 24 is read in the order of the hemisphere, where a territory is named" do
      autumn_to_spring = {:ok, ~o"2026-03/2026-11"}
      assert Tempo.from_iso8601("2026-23/2026-21", territory: :AU) == autumn_to_spring
      assert Tempo.from_iso8601("2026-23/2026-21", locale: "en-AU") == autumn_to_spring
      assert Tempo.parse("2026-23/2026-21", territory: :AU) == autumn_to_spring

      assert {:error, %IntervalEndpointsError{reason: :order}} =
               Tempo.from_iso8601("2026-23/2026-21", territory: :GB)

      assert {:error, %IntervalEndpointsError{reason: :order}} =
               Tempo.from_iso8601("2026-21/2026-23", territory: :AU)
    end
  end
end
