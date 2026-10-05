defmodule Tempo.DayWithNoMonthTest do
  use ExUnit.Case, async: true

  # A day with no month, selected in a year, is a day of the year, as the
  # value `2026Y45D` is read: `2026YL45DN` is 14 February and `2026YL-1DN`
  # 31 December (decided 2026-10-04). It was read in the year's first month,
  # so the 45th selected nothing and the last day was 31 January.
  #
  # A year is where it is selected when nothing gives it a month: a value's
  # selection after a year, the rule of a recurrence that steps by years from
  # a year or from no start, and a constraint `Tempo.select/2` selects from a
  # year. A recurrence's start that names a month gives the day that month,
  # since a rule takes from its start what it does not say (ISO 8601-2
  # §13.6.3), and a month, a week, a day of the year or an event beside the
  # day places it already.
  #
  # The measure is `Date` alone: the first day of the year and the days on
  # from it, the last counted back from the first day of the next.

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.ISOWeek
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  # What is written, as text and as the numbers and ranges it names.
  @written [
    {"1", [1]},
    {"15", [15]},
    {"32", [32]},
    {"45", [45]},
    {"60", [60]},
    {"365", [365]},
    {"366", [366]},
    {"-1", [-1]},
    {"-45", [-45]},
    {"-366", [-366]},
    {"{1,45,-1}", [1, 45, -1]},
    {"{28..33}", [28..33//1]},
    {"{360..-1}", [360..-1//1]},
    {"{1..-1//100}", [1..-1//100]}
  ]

  # The days of a year that what is written names, in order: a negative
  # number is counted back from the year's last day, and a day the year does
  # not have is passed over.
  defp days_named(written, year, calendar \\ Calendar.ISO) do
    first = Date.new!(year, 1, 1, calendar)
    last = Date.diff(Date.new!(year + 1, 1, 1, calendar), first)

    written
    |> Enum.flat_map(fn
      %Range{first: from, last: to, step: step} ->
        Enum.to_list(counted(from, last)..counted(to, last)//step)

      number ->
        [counted(number, last)]
    end)
    |> Enum.filter(&(&1 in 1..last))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&Date.add(first, &1 - 1))
  end

  defp counted(number, last) when number < 0, do: last + 1 + number
  defp counted(number, _last), do: number

  # The day each span starts on, each span a day long.
  defp days({:ok, %IntervalSet{} = set}) do
    for member <- IntervalSet.members(set) do
      {:ok, from} = member |> Interval.from() |> Tempo.to_date()
      {:ok, to} = member |> Interval.to() |> Tempo.to_date()
      assert Date.diff(to, from) == 1
      from
    end
  end

  defp read(text, calendar \\ Calendrical.Gregorian), do: Tempo.from_iso8601!(text, calendar)

  describe "a value's selection after a year" do
    test "is the days of the year it names" do
      for year <- 2023..2028, {text, written} <- @written do
        selected = days(Tempo.to_interval(read("#{year}YL#{text}DN")))
        assert {year, text, selected} == {year, text, days_named(written, year)}
      end
    end

    test "is each year's own days where the value holds several years" do
      selected = days(Tempo.to_interval(read("{2024,2026}YL{60,-1}DN")))

      assert selected == days_named([60, -1], 2024) ++ days_named([60, -1], 2026)
      assert selected == [~D[2024-02-29], ~D[2024-12-31], ~D[2026-03-01], ~D[2026-12-31]]
    end

    test "is what a day of the year written with `O` is" do
      for text <- ["45", "-1", "{1,45,-1}", "{360..-1}"] do
        assert {text, Tempo.to_interval(read("2026YL#{text}DN"))} ==
                 {text, Tempo.to_interval(read("2026YL#{text}ON"))}
      end
    end

    test "is walked, written and worded as that day" do
      assert Enum.to_list(~o"2026YL45DN") == [~o"2026-02-14"]
      assert Tempo.to_string(~o"2026YL45DN") == {:ok, "Feb 14, 2026"}
      assert Tempo.explain(~o"2026YL45DN") =~ "In 2026, selects on the 45th day of the year."

      # The value is as it was written.
      assert inspect(~o"2026YL45DN") == ~s(~o"2026YL45DN")
    end
  end

  describe "the rule of a recurrence that steps by years" do
    test "is the days of each year from a start that is a year" do
      for year <- [2023, 2024, 2027], {text, written} <- @written do
        every = read("R/#{year}/P1Y/FL#{text}DN")
        window = read("#{year}/#{year + 3}")

        expected = Enum.flat_map(year..(year + 2), &days_named(written, &1))
        selected = days(Tempo.to_interval(every, within: window))

        assert {year, text, selected} == {year, text, expected}
      end
    end

    test "is counted to its count, and steps by more than a year" do
      assert days(Tempo.to_interval(~o"R3/2026/P1Y/FL45DN")) ==
               [~D[2026-02-14], ~D[2027-02-14], ~D[2028-02-14]]

      assert days(Tempo.to_interval(~o"R3/2026/P2Y/FL-1DN")) ==
               [~D[2026-12-31], ~D[2028-12-31], ~D[2030-12-31]]

      # The 366th day, in the years that have one.
      assert days(Tempo.to_interval(~o"R2/2026/P1Y/FL366DN")) == [~D[2028-12-31], ~D[2032-12-31]]
    end

    test "is the days of each year where it has no start" do
      for {text, written} <- @written do
        selected = days(Tempo.to_interval(read("R/../P1Y/FL#{text}DN"), within: ~o"2026/2028"))
        expected = days_named(written, 2026) ++ days_named(written, 2027)

        assert {text, selected} == {text, expected}
      end
    end

    test "is not given a month by the window it is listed within" do
      # The window starts on 10 March: the 45th day of 2026 is before it.
      assert days(Tempo.to_interval(~o"R/../P1Y/FL45DN", within: ~o"2026-03-10/2028")) ==
               [~D[2027-02-14]]
    end

    test "takes its month from a start that names one" do
      # ISO 8601-2 §13.6.3: a rule inherits from its start what it does not say.
      assert days(Tempo.to_interval(~o"R2/2026-03-10/P1Y/FL15DN")) ==
               [~D[2026-03-15], ~D[2027-03-15]]

      assert days(Tempo.to_interval(~o"R2/2026-06/P1Y/FL15DN")) ==
               [~D[2026-06-15], ~D[2027-06-15]]

      # June has no 45th day.
      assert days(Tempo.to_interval(~o"R/2026-06/P1Y/FL45DN", within: ~o"2026/2030")) == []
    end

    test "that steps by months is the day of each month" do
      assert days(Tempo.to_interval(~o"R3/2026/P1M/FL15DN")) ==
               [~D[2026-01-15], ~D[2026-02-15], ~D[2026-03-15]]

      assert days(Tempo.to_interval(~o"R/../P1M/FL-1DN", within: ~o"2026-02")) == [~D[2026-02-28]]
    end
  end

  describe "a constraint of select/2 on a year" do
    test "is the days of the year it names" do
      for year <- 2023..2028, {text, written} <- @written do
        selected = days(Tempo.select(read("#{year}Y"), read("#{text}D")))
        assert {year, text, selected} == {year, text, days_named(written, year)}
      end
    end

    test "is the same written as a selection" do
      for {text, _written} <- @written do
        assert {text, days(Tempo.select(~o"2024", read("#{text}D")))} ==
                 {text, days(Tempo.select(~o"2024", read("L#{text}DN")))}
      end
    end

    test "is selected from each year of a span" do
      assert days(Tempo.select(~o"2024/2027", ~o"60D")) ==
               [~D[2024-02-29], ~D[2025-03-01], ~D[2026-03-01]]
    end

    test "holds for a time of day on it, in a list and as the ends of a span" do
      {:ok, set} = Tempo.select(~o"2026", ~o"45DT10H")
      assert Enum.map(IntervalSet.members(set), &Interval.from/1) == [~o"2026Y2M14DT10H"]

      assert days(Tempo.select(~o"2026", [~o"45D", ~o"12-25"])) ==
               [~D[2026-02-14], ~D[2026-12-25]]

      {:ok, days_45_to_50} = Interval.new(from: ~o"45D", to: ~o"50D")
      {:ok, set} = Tempo.select(~o"2026", days_45_to_50)
      assert Enum.map(IntervalSet.members(set), &Tempo.to_iso8601!/1) == ["2026Y2M14D/19D"]
    end

    test "on a month is the day of the month" do
      assert days(Tempo.select(~o"2026-06", ~o"15D")) == [~D[2026-06-15]]
      assert days(Tempo.select(~o"2026-06", ~o"45D")) == []
      assert days(Tempo.select(~o"2026-02", ~o"-1D")) == [~D[2026-02-28]]
    end
  end

  describe "a day with a part that places it" do
    test "a month beside it is the day's month" do
      assert days(Tempo.to_interval(~o"2026YL3M15DN")) == [~D[2026-03-15]]
      assert days(Tempo.to_interval(~o"2026YL2M-1DN")) == [~D[2026-02-28]]
      assert days(Tempo.select(~o"2026", ~o"3M15D")) == [~D[2026-03-15]]

      assert days(Tempo.to_interval(~o"R2/2026/P1Y/FL{3,6}M15DN")) == [
               ~D[2026-03-15],
               ~D[2026-06-15]
             ]
    end

    test "a weekday beside it keeps the days of the year that fall on it" do
      # The 45th day of the year is a Saturday in 2026, 2032 and 2037.
      saturdays =
        for year <- 2026..2040,
            [day] = days_named([45], year),
            Date.day_of_week(day) == 6,
            do: day

      assert days(Tempo.to_interval(~o"R/2026/P1Y/FL45D6KN", within: ~o"2026/2041")) == saturdays
      assert Enum.take(saturdays, 3) == [~D[2026-02-14], ~D[2032-02-14], ~D[2037-02-14]]
    end

    test "a time of day is on the day of the year" do
      {:ok, set} = Tempo.to_interval(~o"R2/2026/P1Y/FL45DT{9,17}HN")

      assert Enum.map(IntervalSet.members(set), &Interval.from/1) ==
               [~o"2026Y2M14DT9H", ~o"2026Y2M14DT17H"]
    end

    test "the start of a window is the day of the year" do
      {:ok, set} = Tempo.to_interval(~o"2026YLL45DN/P3DN")
      assert Enum.map(IntervalSet.members(set), &Tempo.to_iso8601!/1) == ["2026Y2M14D/17D"]

      {:ok, set} = Tempo.to_interval(~o"R2/2026/P1Y/FLL-1DN/P3DN")

      assert Enum.map(IntervalSet.members(set), &Tempo.to_iso8601!/1) ==
               ["2026Y12M31D/2027Y1M3D", "2027Y12M31D/2028Y1M3D"]
    end
  end

  describe "in another calendar" do
    test "a year of thirteen months is counted by its own days" do
      for year <- 5786..5788,
          {text, written} <- [{"45", [45]}, {"-1", [-1]}, {"{1,384}", [1, 384]}] do
        expected = days_named(written, year, Hebrew)

        value = Tempo.to_interval(read("#{year}YL#{text}DN", Hebrew))
        plain = Tempo.select(read("#{year}Y", Hebrew), read("#{text}D", Hebrew))

        assert {year, text, days(value)} == {year, text, expected}
        assert {year, text, days(plain)} == {year, text, expected}
      end
    end

    test "a calendar of weeks has no months, and refuses a day of one as it did" do
      assert {:error, %ConversionError{}} = Tempo.to_interval(read("2026YL45DN", ISOWeek))
      assert {:error, %ConversionError{}} = Tempo.to_interval(read("R2/2026/P1Y/FL45DN", ISOWeek))
    end
  end

  describe "the RRULE written for it" do
    # `BYMONTHDAY` is a day of a month, of DTSTART's where the rule names
    # none, so a day of the year is written `BYYEARDAY`.
    test "is BYYEARDAY where the rule's start names no month" do
      assert RRule.to_string(~o"R/2026/P1Y/FL45DN") == {:ok, "FREQ=YEARLY;BYYEARDAY=45"}
      assert RRule.to_string(~o"R/2026/P1Y/FL-1DN") == {:ok, "FREQ=YEARLY;BYYEARDAY=-1"}
      assert RRule.to_string(~o"R/../P1Y/FL{1,45}DN") == {:ok, "FREQ=YEARLY;BYYEARDAY=1,45"}
    end

    test "lists the days the recurrence does" do
      for text <- ["45", "-1", "{1,45,-1}", "366"] do
        every = read("R/2026/P1Y/FL#{text}DN")
        {:ok, rule} = RRule.to_string(every)
        window = [within: ~o"2026/2030"]

        assert {text, days(Tempo.to_interval(RRule.parse!(rule, from: ~o"2026-01-01"), window))} ==
                 {text, days(Tempo.to_interval(every, window))}
      end
    end

    test "is BYMONTHDAY where its start names the month, or the rule does" do
      assert RRule.to_string(~o"R/2026-03-10/P1Y/FL15DN") == {:ok, "FREQ=YEARLY;BYMONTHDAY=15"}

      assert RRule.to_string(~o"R/2026/P1Y/FL3M15DN") ==
               {:ok, "FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=15"}

      assert RRule.to_string(~o"R/2026/P1M/FL15DN") == {:ok, "FREQ=MONTHLY;BYMONTHDAY=15"}
    end
  end

  describe "a rule read from an RRULE" do
    test "with a start takes its day of the month in the start's month, as it did" do
      rule = RRule.parse!("FREQ=YEARLY;BYMONTHDAY=15;COUNT=2", from: ~o"2026-03-10")

      assert rule == ~o"R2/2026-03-10/P1Y/FL3M15DN"
      assert days(Tempo.to_interval(rule)) == [~D[2026-03-15], ~D[2027-03-15]]
    end

    test "with no start has no month to take, and is the rule ISO 8601 reads" do
      rule = RRule.parse!("FREQ=YEARLY;BYMONTHDAY=-1")

      assert rule == ~o"R/../P1Y/FL-1DN"
      assert days(Tempo.to_interval(rule, within: ~o"2026")) == [~D[2026-12-31]]
    end
  end
end
