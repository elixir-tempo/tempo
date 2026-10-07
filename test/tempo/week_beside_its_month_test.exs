defmodule Tempo.WeekBesideItsMonthTest do
  @moduledoc """
  A week beside the month it is written with is a week of that month
  (decided 2026-10-08).

  `2026YL6M2WN` was the second week of the year with its month passed over,
  and a week selected from a day was kept by the week of the year the day is
  in. A week beside a month in a selection is the week of that month, as
  `2026Y6ML2WN` is, and a week selected from a day or a time of day, which
  are written with their month, keeps what is in that week of the month.

  A rule that starts on a date is asked of each day, as RFC 5545's is, and
  its week is the week of the year. An RRULE's `BYWEEKNO` is always one, so
  a rule read from an RRULE that would have it read in a month is refused.

  The measure is Elixir's own `Date`: whole weeks from a Monday, the first
  of a month the one that holds its first day, and `:calendar` for the week
  of a year.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  ## The measure

  @months for year <- 2024..2027, month <- 1..12, do: {year, month}

  defp monday_of(date), do: Date.beginning_of_week(date, :monday)

  # A week of a month, from its Monday to the Monday after.
  defp week(year, month, week) do
    start = Date.new!(year, month, 1) |> monday_of() |> Date.add(7 * (week - 1))
    {start, Date.add(start, 7)}
  end

  # How many weeks a month has: those from the week that holds its first day
  # up to the week that holds the first day of the next.
  defp weeks_in(year, month) do
    first = Date.new!(year, month, 1)
    next = first |> Date.end_of_month() |> Date.add(1)

    div(Date.diff(monday_of(next), monday_of(first)), 7)
  end

  # The week of its month a day is in, and none where its week is the first
  # of the month after.
  defp week_of_its_month(date) do
    next_month = date |> Date.end_of_month() |> Date.add(1)

    if Date.before?(Date.add(monday_of(date), 6), next_month),
      do: div(Date.diff(monday_of(date), monday_of(Date.beginning_of_month(date))), 7) + 1
  end

  defp week_of_its_year(date), do: date |> Date.to_erl() |> :calendar.iso_week_number() |> elem(1)

  defp seconds(%Date{} = date),
    do:
      date |> NaiveDateTime.new!(~T[00:00:00]) |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp seconds({%Date{} = from, %Date{} = to}), do: {seconds(from), seconds(to)}

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  defp spans({:ok, %IntervalSet{} = set}), do: set |> IntervalSet.members() |> Enum.map(&bounds/1)

  defp days(dates), do: for(date <- dates, do: seconds({date, Date.add(date, 1)}))

  defp read(text), do: Tempo.from_iso8601!(text)

  describe "a week beside a month, in a year" do
    test "is that week of the month, for each week of each month" do
      for {year, month} <- @months, week <- 1..weeks_in(year, month) do
        text = "#{year}YL#{month}M#{week}WN"

        assert {text, spans(Tempo.to_interval(read(text)))} ==
                 {text, [seconds(week(year, month, week))]}
      end
    end

    test "is the week the selection of the month alone gives" do
      for text <- ["L6M2WN", "L6M-1WN", "L{6,7}M1WN", "L6M2W3KN", "L6M{1,3}WN"] do
        {:ok, of_the_year} = Tempo.select(~o"2026", read(text))

        "L6M" <> rest = String.replace(text, "{6,7}M", "6M")
        {:ok, of_june} = Tempo.select(~o"2026-06", read("L" <> rest))

        june = spans({:ok, of_june})
        assert {text, Enum.take(spans({:ok, of_the_year}), Enum.count(june))} == {text, june}
        assert {text, june} != {text, []}
      end
    end

    test "has no week the month does not" do
      # It was the 24th week of the year, with June passed over.
      assert spans(Tempo.to_interval(~o"2026YL6M24WN")) == []
      assert spans(Tempo.to_interval(~o"2026YL6M2WN")) == [seconds(week(2026, 6, 2))]
    end

    test "and a week with no month is a week of the year, as it was" do
      {:ok, set} = Tempo.to_interval(~o"2026YL2WN")
      assert Enum.map(IntervalSet.members(set), &Interval.from/1) == [~o"2026Y2W"]
    end
  end

  describe "a week selected from a day, which is written with its month" do
    test "keeps the day where that week of its month holds it" do
      for week <- 1..6 do
        selector = read("#{week}W")
        dates = Date.range(~D[2026-01-01], ~D[2026-12-31])
        {:ok, set} = Tempo.select(~o"2026-01-01/2027-01-01", selector)

        assert {week, spans({:ok, set})} ==
                 {week, days(Enum.filter(dates, &(week_of_its_month(&1) == week)))}
      end
    end

    test "is not the week of the year the day is in" do
      # 10 June 2026 is in the second week of June, and in the 24th of 2026.
      assert {week_of_its_month(~D[2026-06-10]), week_of_its_year(~D[2026-06-10])} == {2, 24}

      for selector <- [~o"2W", ~o"L2WN", ~o"{2,3}W", ~o"2W3K"] do
        assert {selector, spans(Tempo.select(~o"2026-06-10", selector))} ==
                 {selector, days([~D[2026-06-10]])}
      end

      for selector <- [~o"24W", ~o"3W", ~o"L24WN", ~o"2W4K"] do
        assert {selector, spans(Tempo.select(~o"2026-06-10", selector))} == {selector, []}
      end
    end

    test "keeps an hour of a day by the week of the day's month" do
      {:ok, kept} = Tempo.select(~o"2026-06-10T10", ~o"2W")
      assert Enum.map(IntervalSet.members(kept), &Interval.from/1) == [~o"2026Y6M10DT10H"]

      assert spans(Tempo.select(~o"2026-06-10T10", ~o"24W")) == []
    end

    test "drops a day whose week is the first of the month after" do
      # 29 and 30 June 2026 are in the week that holds 1 July.
      assert week_of_its_month(~D[2026-06-29]) == nil

      for week <- 1..6 do
        assert {week, spans(Tempo.select(~o"2026-06-29", read("#{week}W")))} == {week, []}
      end

      assert spans(Tempo.select(~o"2026-07-01", ~o"1W")) == days([~D[2026-07-01]])
    end
  end

  describe "a week selected from a week, and in a calendar of weeks" do
    test "is the week of the year, as it was" do
      {:ok, week} = Tempo.to_interval(~o"2026-W24")
      {:ok, set} = Tempo.select(~o"2026-W24", ~o"24W")
      assert IntervalSet.members(set) == [week]

      day = Tempo.from_iso8601!("2026Y24W3K", Calendrical.ISOWeek)
      selector = Tempo.from_iso8601!("24W", Calendrical.ISOWeek)

      assert {:ok, set} = Tempo.select(day, selector)
      assert IntervalSet.count(set) == 1
    end
  end

  describe "a rule with a week beside a month" do
    test "is that week of the month where it starts from a year, or has no start" do
      expected = [seconds(week(2026, 6, 2)), seconds(week(2027, 6, 2))]

      assert spans(Tempo.to_interval(~o"R2/2026/P1Y/FL6M2WN")) == expected

      assert spans(Tempo.to_interval(~o"R/../P1Y/FL6M2WN", within: ~o"2026/2028")) == expected
    end

    test "is the week of the year where it starts on a date, as RFC 5545's is" do
      # Each day of June that is in the 24th week of its year, from the start.
      in_week_24 =
        Enum.filter(Date.range(~D[2026-06-01], ~D[2026-06-30]), &(week_of_its_year(&1) == 24))

      assert spans(Tempo.to_interval(~o"R7/2026-01-05/P1Y/FL6M24WN")) == days(in_week_24)
      assert spans(Tempo.to_interval(~o"R2/2026-01-05/P1Y/FL6M2WN")) == []

      # A rule read from an RRULE states its start's weekday beside the week.
      {:ok, rule} =
        RRule.parse("FREQ=YEARLY;BYMONTH=6;BYWEEKNO=24;COUNT=3", from: ~o"2026-01-05")

      mondays =
        for year <- 2026..2028,
            date <- Date.range(Date.new!(year, 6, 1), Date.new!(year, 6, 30)),
            week_of_its_year(date) == 24 and Date.day_of_week(date) == 1,
            do: date

      assert spans(Tempo.to_interval(rule)) == days(mondays)
    end

    test "is written as an RRULE only where its week is a week of the year" do
      assert RRule.to_string(~o"R/2026-01-05/P1Y/FL6M2WN") ==
               {:ok, "FREQ=YEARLY;BYMONTH=6;BYWEEKNO=2"}

      assert {:error, %Tempo.ConversionError{} = error} =
               RRule.to_string(~o"R/2026/P1Y/FL6M2WN")

      assert Exception.message(error) =~ "week of a month"
    end

    test "is explained as a week of the month" do
      assert to_string(Tempo.explain(~o"2026YL6M2WN")) =~ "in the 2nd week of the month"
    end
  end

  describe "an RRULE whose week number would be read in a month" do
    test "is refused where it is read, with no start that is a date" do
      for {rrule, weeks} <- [
            {"FREQ=YEARLY;BYMONTH=6;BYWEEKNO=24", 24},
            {"FREQ=YEARLY;BYMONTH=6;BYWEEKNO=24;BYDAY=MO", 24},
            {"FREQ=MONTHLY;BYWEEKNO=2", 2},
            {"FREQ=YEARLY;BYMONTH=6,7;BYWEEKNO=24,27", [24, 27]}
          ],
          start <- [nil, ~o"2026"] do
        assert {rrule, start, RRule.parse(rrule, from: start)} ==
                 {rrule, start, {:error, {:byweekno_without_a_date, weeks}}}
      end

      rule = %Rule{freq: :year, interval: 1, bymonth: [6], byweekno: [24]}
      assert Expander.to_ast(rule, nil) == {:error, {:byweekno_without_a_date, 24}}
    end

    test "is read where it starts on a date, and where it names no month" do
      assert {:ok, %Interval{}} =
               RRule.parse("FREQ=YEARLY;BYMONTH=6;BYWEEKNO=24", from: ~o"2026-01-05")

      assert {:ok, %Interval{} = rule} = RRule.parse("FREQ=YEARLY;BYWEEKNO=24")

      {:ok, set} = Tempo.to_interval(rule, within: ~o"2026")
      assert Enum.map(IntervalSet.members(set), &Interval.from/1) == [~o"2026Y24W"]
    end
  end
end
