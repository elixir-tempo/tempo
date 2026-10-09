defmodule Tempo.GroupResolution.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  test "Group resolution days to hours" do
    assert ~o"2022Y1M1G3DUT26H" == ~o"2022Y1M2DT2H"
    assert ~o"2022Y1M1G3DUT24H" == ~o"2022Y1M2DT0H"

    assert ~o"2022Y1M2G1DUT23H" == ~o"2022Y1M2DT23H"
    assert ~o"2022Y1M1G2DUT24H" == ~o"2022Y1M2DT0H"
    assert ~o"2022Y1M2G2DUT24H" == ~o"2022Y1M4DT0H"
  end

  test "Group resolution hours to minutes" do
    assert ~o"T1G1HU1M" == ~o"0H1M"
    assert ~o"T1G4HU1M" == ~o"0H1M"
    assert ~o"T2G1HU1M" == ~o"1H1M"
    assert ~o"T2G4HU1M" == ~o"4H1M"

    assert ~o"T1G4HU239M" == ~o"3H59M"

    assert {:error, %Tempo.InvalidDateError{} = e} = Tempo.from_iso8601("T1G4HU240M")
    assert Exception.message(e) =~ "240 is not valid"
  end

  test "Group resolution minutes to seconds" do
    assert ~o"T1G1MU1S" == ~o"0M1S"
    assert ~o"T1G4MU1S" == ~o"0M1S"
    assert ~o"T2G1MU1S" == ~o"1M1S"
    assert ~o"T2G4MU1S" == ~o"4M1S"

    assert {:error, %Tempo.InvalidDateError{} = e} = Tempo.from_iso8601("T2G4MU240S")
    assert Exception.message(e) =~ "480 is not valid"
  end

  test "Astronomical seasons (25-32) expand to equinox/solstice-bounded intervals" do
    # Codes 25-28 are Northern hemisphere astronomical seasons.
    # Boundaries come from Astro.equinox/2 and Astro.solstice/2.
    assert ~o"2022Y25M" == ~o"2022Y3M20D/6M21D"
    assert ~o"2022Y26M" == ~o"2022Y6M21D/9M23D"
    assert ~o"2022Y27M" == ~o"2022Y9M23D/12M21D"
    assert ~o"2022Y28M" == ~o"2022Y12M21D/2023Y3M20D"
  end

  test "a day after a season of a hemisphere is the season's nth day, as it is after a quarter" do
    assert ~o"2026-34-10" == ~o"2026-04-10"
    assert ~o"2026-25-10" == ~o"2026-03-29"
    assert ~o"2026-28-15" == ~o"2027-01-04"
    assert ~o"2026-25-10T10" == ~o"2026-03-29T10"
  end

  test "nothing follows a season of 21 to 24, which has no dates to count a day in" do
    # A day after one was read as a day of the northern season's first
    # month: `2026-21-10` as 10 March.
    for text <- ["2026-21-10", "2026-24-10", "2026-24-31", "2026-21T10", "2026-22-10T10"] do
      assert {^text, {:error, %Tempo.ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
      assert Exception.message(error) =~ "A season is written as a year and the season alone"
    end
  end

  test "an astronomical season beyond the years Astro computes is an error" do
    # Astro computes equinoxes and solstices for 1000-3000, and a winter
    # ends at the next year's March equinox.
    assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("0999-25")
    assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("0999-25/2026-27")
    assert {:error, error} = Tempo.from_iso8601("3000-28")
    assert Exception.message(error) =~ "March equinox of 3001"
    assert {:ok, _winter} = Tempo.from_iso8601("2999-28")
  end

  # A season of 21 to 24 is "independent of location" (ISO 8601-2 §4.8.1),
  # and was read as the northern season everywhere. It is kept as it is
  # written, and is whole months once it has a hemisphere: those the season
  # has north of the equator, and the months of the opposite season south
  # of it (`test/tempo/season_test.exs` measures them).
  test "a season of 21 to 24 is kept as it is written, and is whole months in a hemisphere" do
    for {season, north, south} <- [
          {"2022Y21M", "2022Y3M/6M", "2022Y9M/12M"},
          {"2022Y22M", "2022Y6M/9M", "2022Y12M/2023Y3M"},
          {"2022Y23M", "2022Y9M/12M", "2022Y3M/6M"},
          {"2022Y24M", "2022Y12M/2023Y3M", "2022Y6M/9M"}
        ] do
      value = Tempo.from_iso8601!(season)

      assert Tempo.to_iso8601!(value) == season
      assert {season, Tempo.in_territory(value, :GB)} == {season, Tempo.from_iso8601(north)}
      assert {season, Tempo.in_territory(value, :AU)} == {season, Tempo.from_iso8601(south)}
    end
  end

  test "a meteorological season holds all three of its months" do
    {:ok, spring} = Tempo.in_territory(~o"2022-21", :GB)
    {:ok, winter} = Tempo.in_territory(~o"2022-24", :GB)

    assert Tempo.contains?(spring, ~o"2022-05-31")
    refute Tempo.contains?(spring, ~o"2022-06-01")
    assert Tempo.contains?(winter, ~o"2022-12-01")
    assert Tempo.contains?(winter, ~o"2023-02-28")
    refute Tempo.contains?(winter, ~o"2023-03-01")
  end

  test "a winter is of the year it starts in, the last of its year's four seasons" do
    # The winter numbered 24 was of the year it ends in, so the four seasons
    # of a year were not in the order of their numbers. The measure is the
    # months written out: December of the year to the end of the February
    # after it, the months the winter numbered 28 starts and ends in.
    for year <- [1, 1582, 1999, 2000, 2026, 9998] do
      {:ok, winter} = Tempo.in_territory(Tempo.from_iso8601!("#{four_digits(year)}-24"), :GB)
      months = Tempo.from_iso8601!("#{four_digits(year)}-12/#{four_digits(year + 1)}-03")

      assert {year, winter} == {year, months}

      assert {year, Tempo.contains?(winter, Tempo.from_date(Date.new!(year, 12, 31)))} ==
               {year, true}

      assert {year, Tempo.contains?(winter, Tempo.from_date(Date.new!(year, 2, 28)))} ==
               {year, false}
    end

    # Each season of a year begins where the one before it ends, and the
    # spring of the next year where the winter ends. South of the equator a
    # year's seasons run autumn, winter, spring, summer.
    for {territory, order} <- [GB: [21, 22, 23, 24], AU: [23, 24, 21, 22]] do
      seasons =
        for year <- 2025..2027, season <- order do
          {:ok, dated} = Tempo.in_territory(Tempo.from_iso8601!("#{year}-#{season}"), territory)
          dated
        end

      for {earlier, later} <- Enum.zip(seasons, Enum.drop(seasons, 1)) do
        assert {earlier, later, Tempo.relation(earlier, later)} == {earlier, later, :meets}
      end
    end
  end

  defp four_digits(year), do: String.pad_leading(Integer.to_string(year), 4, "0")

  describe "a season in another calendar" do
    test "is the Gregorian season that starts within its year" do
      # Hebrew 5787 runs from September 2026 to October 2027.
      assert Tempo.relation(~o"5787-25[u-ca=hebrew]", ~o"2027-25") == :equals
      # Its winter starts in December 2026, the winter of 2026.
      {:ok, hebrew_winter} = Tempo.in_territory(~o"5787-24[u-ca=hebrew]", :GB)
      {:ok, winter} = Tempo.in_territory(~o"2026-24", :GB)
      assert Tempo.relation(hebrew_winter, winter) == :equals
      assert Tempo.relation(~o"2026-25[u-ca=julian]", ~o"2026-25") == :equals

      {:ok, buddhist} = Tempo.in_territory(~o"2569-21[u-ca=buddhist]", :GB)
      {:ok, gregorian} = Tempo.in_territory(~o"2026-21", :GB)
      assert Tempo.relation(buddhist, gregorian) == :equals
    end

    test "has its endpoints in that calendar" do
      assert ~o"5787-25[u-ca=hebrew]" == ~o"5787Y7M11D/10M16D[u-ca=hebrew]"
      assert Tempo.relation(~o"5787-25-10[u-ca=hebrew]", ~o"2027-03-29") == :equals
    end

    test "is the first of two that start within a long year" do
      # Hebrew 5774 runs from 5 September 2013 to 24 September 2014.
      assert Tempo.relation(~o"5774-27[u-ca=hebrew]", ~o"2013-27") == :equals
    end

    test "is an error in a year no season of that kind starts in" do
      # Islamic 1422 runs from 26 March 2001 to 14 March 2002.
      assert {:error, %Tempo.InvalidDateError{} = error} =
               Tempo.from_iso8601("1422-25[u-ca=islamic-umalqura]")

      assert Exception.message(error) =~ "No season 25 starts in 1422"
    end
  end

  test "a season in a year with unspecified digits" do
    assert Tempo.in_territory(~o"20XX-21", :GB) == {:ok, ~o"20XXY3M/20XXY6M"}
    assert Tempo.in_territory(~o"20XX-21", :AU) == {:ok, ~o"20XXY9M/20XXY12M"}

    # The season that runs into the next year needs the year itself, a
    # winter in the north and a summer in the south, and so does a season
    # in another calendar. One of a hemisphere is refused as it is read.
    assert {:error, %Tempo.InvalidDateError{}} = Tempo.in_territory(~o"20XX-24", :GB)
    assert {:error, %Tempo.InvalidDateError{}} = Tempo.in_territory(~o"20XX-22", :AU)
    assert {:ok, _winter_in_one_year} = Tempo.in_territory(~o"20XX-24", :AU)
    assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("20XX-25")

    {:ok, hebrew} = Tempo.from_iso8601("20XX-21[u-ca=hebrew]")
    assert {:error, %Tempo.InvalidDateError{}} = Tempo.in_territory(hebrew, :GB)
  end

  describe "a value after a group of its own unit" do
    test "counts within the group, as ISO 8601-2 §5.4.1 reads it" do
      # 30 minutes into the third eight hours of 2 September 2018.
      assert ~o"2018Y9M2DT3GT8HU0H30M" == ~o"2018Y9M2DT16H30M"
      assert ~o"2018Y9M2DT3GT8HU-1H" == ~o"2018Y9M2DT23H"
      assert ~o"2018Y2G3MU2M" == ~o"2018Y5M"
      assert ~o"2026Y2G13WU3W" == ~o"2026Y16W"
    end

    test "outside the group is an error naming the group's range" do
      assert {:error, %Tempo.InvalidDateError{value: 4, valid_range: 1..3}} =
               Tempo.from_iso8601("2018Y2G3MU4M")

      # The last group of eleven days in February holds six.
      assert {:error, %Tempo.InvalidDateError{value: 7, valid_range: 1..6}} =
               Tempo.from_iso8601("2018Y2M3G11DU7D")
    end
  end

  describe "the year's divisions (codes 33-41)" do
    test "are the calendar's quarters, quadrimesters and semesters" do
      assert {:ok, %Tempo{time: [year: 5787, month: {:group, 4..7}]}} =
               Tempo.from_iso8601("5787-34", Calendrical.Hebrew)

      assert {:ok, %Tempo{time: [year: 5787, month: {:group, 11..13}]}} =
               Tempo.from_iso8601("5787-36", Calendrical.Hebrew)

      assert {:ok, %Tempo{time: [year: 5786, month: {:group, 10..12}]}} =
               Tempo.from_iso8601("5786-36", Calendrical.Hebrew)

      assert {:ok, %Tempo{time: [year: 1742, month: {:group, 10..13}]}} =
               Tempo.from_iso8601("1742-36", Calendrical.Coptic)

      assert {:ok, %Tempo{time: [year: 2026, month: {:group, 5..8}]}} =
               Tempo.from_iso8601("2026-38")
    end

    test "are groups of weeks in a week-based calendar" do
      assert {:ok, %Tempo{time: [year: 2026, week: {:group, 40..53}]}} =
               Tempo.from_iso8601("2026-36", Calendrical.ISOWeek)

      assert {:ok, %Tempo{time: [year: 2026, week: {:group, 27..53}]}} =
               Tempo.from_iso8601("2026-41", Calendrical.ISOWeek)
    end
  end

  describe "a group" do
    test "renders as it was declared" do
      for iso8601 <- ["T16H1GT15MU", "2026Y10M3DT3GT8HU", "2018Y2M3G11DU", "2026Y2G13WU"] do
        {:ok, tempo} = Tempo.from_iso8601(iso8601)
        assert Tempo.to_iso8601!(tempo) == iso8601
      end
    end

    test "walks the values its container holds" do
      assert ~o"2026Y3G5MU" |> Enum.map(& &1.time[:month]) == [11, 12]
      assert ~o"T16H1GT15MU" |> Enum.map(& &1.time[:minute]) == Enum.to_list(0..14)
    end

    test "takes a duration as its size, not a date" do
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("2026Y1G2KU")
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("1G3KU")
    end
  end

  # A group of a set (`{1,2}G3MU`, the first and the second groups of three
  # months) names a span in each of its groups. `to_interval/2` and the
  # walk refused it with a `ConversionError`.
  describe "a group of a set" do
    alias Tempo.IntervalSet

    defp spans(value) do
      {:ok, set} = Tempo.to_interval(value)
      set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
    end

    test "converts to a span for each group" do
      assert spans(~o"2026Y{1,2}G3MU") == ["2026Y1M/4M", "2026Y4M/7M"]
      assert spans(~o"2026Y6M{1,2}G10DU") == ["2026Y6M1D/11D", "2026Y6M11D/21D"]
      assert spans(~o"T{1,2}G6HU") == ["T0H/T6H", "T6H/T12H"]
      assert spans(~o"2026Y{1,2}G4WU") == ["2026Y1W/5W", "2026Y5W/9W"]
    end

    test "walks the values of each group in turn" do
      assert Enum.to_list(~o"2026Y{1,3}G3MU") ==
               [~o"2026-01", ~o"2026-02", ~o"2026-03", ~o"2026-07", ~o"2026-08", ~o"2026-09"]

      assert Enum.count(~o"2026Y6M{1,2}G10DU") == 20
    end

    test "counts a group from the end in what holds it" do
      assert spans(~o"2026Y{1..-1}G3MU") ==
               ["2026Y1M/4M", "2026Y4M/7M", "2026Y7M/10M", "2026Y10M/2027Y1M"]

      assert Enum.to_list(~o"2026Y{-1}G3MU") == [~o"2026-10", ~o"2026-11", ~o"2026-12"]

      # The third group of ten days in a February ends with the month.
      assert List.last(spans(~o"2026Y2M{1..-1}G10DU")) == "2026Y2M21D/3M1D"

      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(~o"{1..-1}G3MU")
    end

    test "passes over a group its container lacks" do
      assert spans(~o"2026Y{4,5}G3MU") == ["2026Y10M/2027Y1M"]
      assert Enum.count(~o"2026Y{4,5}G3MU") == 3
    end

    test "counts a unit after it from the start of each group" do
      assert spans(~o"2026Y{1,2}G3MU15D") == ["2026Y1M15D/16D", "2026Y4M15D/16D"]
      assert Enum.to_list(~o"2026Y{1,2}G3MU15D") == [~o"2026-01-15", ~o"2026-04-15"]
    end

    test "is measured, compared and shown as the spans it names" do
      quarters = ~o"2026Y{1,2}G3MU"

      assert Tempo.duration(quarters) == ~o"P6M"
      assert Tempo.overlaps?(quarters, ~o"2026-05")
      refute Tempo.overlaps?(quarters, ~o"2026-08")

      assert Tempo.to_string!(quarters) ==
               "Jan\u2009\u2013\u2009Mar 2026 and Apr\u2009\u2013\u2009Jun 2026"
    end

    test "of one of several groups is no one span, and walks its candidates" do
      assert {:error, %Tempo.ConversionError{reason: :one_of_set}} =
               Tempo.to_interval(~o"2026Y[1,2]G3MU")

      assert Enum.count(~o"2026Y[1,2]G3MU") == 6
    end
  end

  # A group of a set is kept as a three-element entry, which the functions
  # that read a value's units raised on (a `FunctionClauseError`, a
  # `CaseClauseError`).
  describe "a value holding a group of a set" do
    alias Tempo.ConversionError

    test "is refused by the functions that need one value" do
      grouped = ~o"2026Y{1,2}G3MU"

      for result <- [
            Tempo.trunc(grouped, :year),
            Tempo.at(~o"{1,2}G3MU", ~o"2026"),
            Tempo.on(~o"{1,2}G3MU", ~o"2026"),
            Tempo.nearest_workday(grouped),
            Tempo.at_resolution(grouped, :day),
            Tempo.extend_resolution(grouped, :day)
          ] do
        assert {:error, %ConversionError{reason: :grouped_component}} = result
      end
    end

    test "has no one month to read" do
      assert Tempo.month(~o"2026Y{1,2}G3MU") == nil
      assert Tempo.year(~o"2026Y{1,2}G3MU") == 2026
    end
  end

  # A selection has no place among the units `trunc/2` orders, and raised a
  # `KeyError`.
  describe "trunc/2 of a value holding a selection" do
    test "drops the selection at or above the units before it, and keeps it below them" do
      first_monday = ~o"2026Y4ML1K1IN"

      assert Tempo.trunc(first_monday, :month) == ~o"2026Y4M"
      assert Tempo.trunc(first_monday, :year) == ~o"2026Y"
      assert Tempo.trunc(first_monday, :day) == first_monday
      assert Tempo.at_resolution(first_monday, :day) == first_monday
    end
  end
end
