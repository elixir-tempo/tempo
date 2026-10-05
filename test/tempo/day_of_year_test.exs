defmodule Tempo.DayOfYearTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.Julian.March25
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError
  alias Tempo.ParseError
  alias Tempo.UnanchoredError

  # The date of each of a year's days, worked out with `Date` and no Tempo.
  defp dates(year, days), do: for(day <- days, do: Date.add(Date.new!(year, 1, 1), day - 1))

  # The dates a value's walk yields, a set's members start on, or a range of
  # some one date runs between.
  defp walked(%Tempo{} = value), do: Enum.map(value, &date/1)

  defp walked(%IntervalSet{} = set),
    do: set |> IntervalSet.members() |> Enum.map(&(&1 |> Interval.from() |> date()))

  defp walked(%Tempo.Set{type: :one, set: [%Tempo.Range{first: first, last: last}]}),
    do: {date(first), date(last)}

  defp date(%Tempo{} = value) do
    {:ok, date} = value |> Tempo.trunc(:day) |> Tempo.to_date()
    date
  end

  describe "a day of the year (ISO 8601-2 §4.3.4)" do
    test "is its own unit, written back as O" do
      assert Tempo.to_iso8601(~o"350O") == {:ok, "350O"}
      assert inspect(~o"-1O") == ~s|~o"-1O"|
      assert inspect(Tempo.from_iso8601!("2020Y{100,200}O")) == ~s|~o"2020Y{100,200}O"|
    end

    test "after its year is the year's ordinal day" do
      assert ~o"2026Y10O" == ~o"2026-01-10"
      assert ~o"2026-166" == ~o"2026-06-15"
      assert Tempo.from_iso8601!("2024Y366O") == ~o"2024-12-31"
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("2026Y366O")
    end

    test "never follows a month" do
      assert {:error, %InvalidDateError{}} = Tempo.at(~o"3M", ~o"2O")
      assert {:error, %ParseError{}} = Tempo.from_iso8601("6M10O")
      assert {:ok, set} = Tempo.select(~o"2026-06", ~o"10O")
      assert IntervalSet.members(set) == []
    end

    test "without a year has no span, no next day and no date to show" do
      assert {:error, %UnanchoredError{}} = Tempo.to_interval(~o"10O")
      assert {:error, %UnanchoredError{}} = Tempo.shift(~o"10O", ~o"P1D")
      assert {:error, %UnanchoredError{}} = Tempo.to_string(~o"10O")
      assert Tempo.explain(~o"10O") =~ "Day 10 of any year"
    end
  end

  describe "a day with no month" do
    test "is a day of the year where a year resolves it" do
      assert ~o"2026Y32D" == ~o"2026-02-01"

      assert {:ok, set} = Tempo.select(~o"2026", ~o"10D")
      assert [january_tenth] = IntervalSet.members(set)
      assert january_tenth.from.time == [year: 2026, month: 1, day: 10]
    end

    test "is a day of a month elsewhere" do
      assert Tempo.at(~o"3M", ~o"2D") == {:ok, ~o"3M2D"}
      assert Tempo.shift(~o"15D", ~o"P1M") == ~o"15D"
      assert {:error, %UnanchoredError{}} = Tempo.shift(~o"28D", ~o"P1D")
    end
  end

  describe "a unit with nothing above it" do
    test "is never 0" do
      for string <- ["0D", "0O", "0M", "0W", "{0,1}D"] do
        assert {:error, %InvalidDateError{}} = Tempo.from_iso8601(string), string
      end
    end

    test "is a month no further from either end than a year of its calendar has" do
      for string <- ["13M", "-13M", "13M1D"] do
        assert {:error, %InvalidDateError{unit: :month}} = Tempo.from_iso8601(string), string
      end

      assert {:ok, _december} = Tempo.from_iso8601("12M")
      assert {:ok, _last_month} = Tempo.from_iso8601("-12M")
      assert {:ok, _adar_ii} = Tempo.from_iso8601("13M[u-ca=hebrew]")
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("14M[u-ca=hebrew]")
    end

    test "is a day or a week bounded once it has a year" do
      for string <- ["32D", "166D", "54W", "367O"] do
        assert {:ok, _value} = Tempo.from_iso8601(string), string
      end

      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("2026Y54W")
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("2026Y367O")
    end
  end

  describe "several days of the year" do
    test "are walked as the dates they name" do
      assert Enum.to_list(~o"2026Y{100,200}O") == [~o"2026-04-10", ~o"2026-07-19"]
      assert Enum.take(~o"2026YX*O", 2) == [~o"2026-01-01", ~o"2026-01-02"]

      assert walked(~o"2026Y{100..102}O") == dates(2026, 100..102)
      assert walked(~o"2026Y1XXO") == dates(2026, 100..199)
      assert walked(~o"2026YX*O") == dates(2026, 1..365)
      assert walked(~o"2024YX*O") == dates(2024, 1..366)
      assert walked(~o"2026Y{1,-1}O") == dates(2026, [1, 365])

      assert walked(Tempo.from_iso8601!("{2026,2027}Y100O")) ==
               dates(2026, [100]) ++ dates(2027, [100])
    end

    test "with a time of day are walked as that time on each date" do
      assert Enum.to_list(~o"2026Y{100,200}OT10H") == [~o"2026-04-10T10", ~o"2026-07-19T10"]

      assert Enum.take(Tempo.from_iso8601!("2026Y{100,200}OTX*H"), 2) ==
               [~o"2026-04-10T00", ~o"2026-04-10T01"]
    end

    test "hold the dates they name and no others" do
      assert ~o"2026-04-10" in ~o"2026Y{100,200}O"
      assert ~o"2026Y100O" in ~o"2026Y{100,200}O"
      refute ~o"2026-04-11" in ~o"2026Y{100,200}O"

      assert ~o"2026-04-11" in ~o"2026Y1XXO"
      refute ~o"2026-07-19" in ~o"2026Y1XXO"
      assert ~o"2026-01-02" in ~o"2026YX*O"
    end

    test "yield values that are read as any date is" do
      [first | _rest] = Enum.to_list(~o"2026Y{100,200}O")

      assert Tempo.to_interval(first) == Tempo.to_interval(~o"2026-04-10")
      assert Tempo.to_date(first) == {:ok, ~D[2026-04-10]}
      assert Tempo.day_of_year(first) == 100
    end

    test "are walked as the dates of the value's calendar" do
      hebrew_year = Enum.to_list(Hebrew.year(5786))
      hebrew = Tempo.from_iso8601!("5786Y{100,200}O", Hebrew)

      assert walked(hebrew) == [Enum.at(hebrew_year, 99), Enum.at(hebrew_year, 199)]

      # A year that turns on 25 March: its first day and its last.
      %Date.Range{first: first, last: last} = March25.year(1750)

      assert walked(Tempo.from_iso8601!("1750Y{1,-1}O", March25)) == [first, last]
    end

    test "with no year are walked as they are written" do
      assert Enum.to_list(~o"{100,200}O") == [~o"100O", ~o"200O"]
    end

    test "are truncated to their day as the days of the year they are" do
      assert Tempo.trunc(~o"2026Y{100,200}OT10H", :day) == ~o"2026Y{100,200}O"
    end

    test "are no one date for an accessor to read" do
      for accessor <- [&Tempo.day_of_year/1, &Tempo.day_of_week/1, &Tempo.quarter_of_year/1],
          value <- [~o"2026Y{100,200}O", ~o"2026YX*O"] do
        assert_raise ArgumentError, ~r/holds several/, fn -> accessor.(value) end
      end
    end
  end

  describe "a step from several days of the year" do
    test "reaches each as the date it is" do
      for step <- [[day: 1], [day: -1], [week: 1], [month: 1], [year: 1]] do
        assert walked(Tempo.shift(~o"2026Y{100,200}O", step)) ==
                 Enum.map(dates(2026, [100, 200]), &Date.shift(&1, step)),
               inspect(step)
      end
    end

    test "is written as days of the year where the years and days it lands on name its dates" do
      assert Tempo.shift(~o"2026Y{100,200}O", day: 1) == ~o"2026Y{101,201}O"
      assert Tempo.shift(~o"2026Y{100..102}O", day: 1) == ~o"2026Y{101..103}O"
      assert Tempo.shift(~o"2026Y{100,200}O", month: 1) == ~o"2026Y{130,231}O"
      assert Tempo.shift(~o"2026Y{100,200}OT23H", hour: 2) == ~o"2026Y{101,201}OT1H"

      assert Tempo.shift(Tempo.from_iso8601!("{2026,2027}Y100O"), day: 1) ==
               Tempo.from_iso8601!("{2026,2027}Y101O")
    end

    test "counts each date in its own year, where the years differ in length" do
      # 2024 is a leap year: its hundredth day is 9 April, the ninety-ninth
      # of 2025, and its sixtieth 29 February, which lands on the 28th.
      assert Tempo.shift(~o"2024Y{100,200}O", year: 1) == ~o"2025Y{99,199}O"
      assert Tempo.shift(~o"2024Y{59,60}O", year: 1) == ~o"2025-02-28"
    end

    test "is the set of the dates' spans where they land in two years" do
      shifted = Tempo.shift(~o"2026Y{1,365}O", day: 1)

      assert %IntervalSet{} = shifted
      assert walked(shifted) == [~D[2026-01-02], ~D[2027-01-01]]
    end

    test "from a masked or an unspecified one is some day of the block, a step on" do
      {first, last} = {hd(dates(2026, [100])), hd(dates(2026, [199]))}

      for step <- [[day: 1], [week: 1], [month: 1], [year: 1]] do
        assert walked(Tempo.shift(~o"2026Y1XXO", step)) ==
                 {Date.shift(first, step), Date.shift(last, step)},
               inspect(step)
      end

      assert walked(Tempo.shift(~o"2026YX*O", day: 1)) == {~D[2026-01-02], ~D[2027-01-01]}
    end

    test "from a mask of years with one is each year's date, a step on" do
      shifted = Tempo.shift(~o"202XY100O", day: 1)

      assert walked(shifted) == for(year <- 2020..2029, do: hd(dates(year, [101])))
    end

    test "keeps a qualification and a zone" do
      assert Tempo.shift(~o"2026Y{100,200}O?", day: 1) == ~o"2026Y{101,201}O?"

      zoned = Tempo.from_iso8601!("2026Y{100,200}OT10H[Europe/Paris]")

      assert Tempo.shift(zoned, day: 1) ==
               Tempo.from_iso8601!("2026Y{101,201}OT10H[Europe/Paris]")
    end

    test "follows the value's calendar" do
      hebrew_year = Enum.to_list(Hebrew.year(5786))
      hebrew = Tempo.from_iso8601!("5786Y{100,200}O", Hebrew)

      assert walked(Tempo.shift(hebrew, day: 1)) ==
               [Enum.at(hebrew_year, 100), Enum.at(hebrew_year, 200)]

      # The day after the last day of a year that turns on 25 March begins
      # the next.
      %Date.Range{first: first} = March25.year(1750)
      %Date.Range{first: next} = March25.year(1751)
      turning = Tempo.from_iso8601!("1750Y{1,-1}O", March25)

      assert walked(Tempo.shift(turning, day: 1)) == [Date.add(first, 1), next]
    end

    test "gives a recurrence the occurrences of each" do
      {:ok, occurrences} = Tempo.to_interval(~o"R3/2026Y{100,200}O/P1D")

      assert walked(occurrences) == dates(2026, [100, 101, 102, 200, 201, 202])
    end
  end
end
