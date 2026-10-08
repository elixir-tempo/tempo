defmodule Tempo.RuleToAnEndTest do
  @moduledoc """
  A rule on a recurrence written to its end (`R3/P1D/2019-01-08/FL7KN`).

  A recurrence written with a duration and an end is counted back from the
  end, and one with a rule has the rule asked of each period back from
  there: its occurrences are those the rule selects that are over by the
  end, nearest the end first, as many as it counts. The walk back stepped
  the cadence and never asked the rule, so the example was the three days
  before 8 January, and it was then refused by name until this was built.

  The measure is Elixir's own `Date`: each day before the end is asked
  whether the rule names it, and the last so many are taken.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.UnboundedRecurrenceError

  # A cadence and a rule, and whether the rule names a day.
  @rules [
    {"P1D", "L7KN", :sunday},
    {"P1D", "L31DN", :thirty_first},
    {"P1W", "L{1,5}KN", :monday_or_friday},
    {"P1M", "L15DN", :fifteenth},
    {"P1M", "L-1DN", :last_of_month},
    {"P1Y", "L11M3DN", :third_of_november}
  ]

  # 6 January 2019 is a Sunday, 31 March the last day of its month and
  # 3 November a day the yearly rule names.
  @ends [~D[2019-01-08], ~D[2019-01-06], ~D[2019-03-31], ~D[2019-11-03], ~D[2019-11-04]]

  ## The measure

  defp named?(:sunday, date), do: Date.day_of_week(date) == 7
  defp named?(:thirty_first, date), do: date.day == 31
  defp named?(:monday_or_friday, date), do: Date.day_of_week(date) in [1, 5]
  defp named?(:fifteenth, date), do: date.day == 15
  defp named?(:last_of_month, date), do: date == Date.end_of_month(date)
  defp named?(:third_of_november, date), do: date.month == 11 and date.day == 3

  # The days a rule names that are over by the end, which is the first
  # instant of its day: those before it.
  defp named_before(name, the_end, since) do
    since |> Date.range(Date.add(the_end, -1)) |> Enum.filter(&named?(name, &1))
  end

  defp nearest(name, the_end, count),
    do: name |> named_before(the_end, Date.add(the_end, -5 * 366)) |> Enum.take(-count)

  defp days_of({:ok, %Interval{} = one}), do: [day_of(one)]
  defp days_of({:ok, %IntervalSet{} = set}), do: Enum.map(IntervalSet.members(set), &day_of/1)

  defp day_of(%Interval{} = occurrence) do
    {:ok, date} = Tempo.to_date(Interval.from(occurrence))
    Date.convert!(date, Calendar.ISO)
  end

  describe "a rule on a recurrence written to its end" do
    test "has the occurrences nearest the end that its rule selects, as many as it counts" do
      for {cadence, rule, name} <- @rules, the_end <- @ends, count <- 1..4 do
        text = "R#{count}/#{cadence}/#{the_end}/F#{rule}"

        assert {text, days_of(Tempo.to_interval(Tempo.from_iso8601!(text)))} ==
                 {text, nearest(name, the_end, count)}
      end
    end

    test "has none that is not over by the end" do
      # 6 January 2019 is a Sunday, and is not over by its own start.
      assert days_of(Tempo.to_interval(~o"R1/P1D/2019-01-06/FL7KN")) == [~D[2018-12-30]]
      assert days_of(Tempo.to_interval(~o"R1/P1D/2019-01-07/FL7KN")) == [~D[2019-01-06]]

      # Nine o'clock on the 8th is over by ten, and not by nine.
      {:ok, by_ten} = Tempo.to_interval(~o"R2/P1D/2019-01-08T10/FLT9HN")
      {:ok, by_nine} = Tempo.to_interval(~o"R2/P1D/2019-01-08T09/FLT9HN")

      assert Enum.map(IntervalSet.members(by_ten), &Interval.from/1) ==
               [~o"2019Y1M7DT9H", ~o"2019Y1M8DT9H"]

      assert Enum.map(IntervalSet.members(by_nine), &Interval.from/1) ==
               [~o"2019Y1M6DT9H", ~o"2019Y1M7DT9H"]
    end

    test "is counted from an end written to its month or its year, as from a date" do
      # March 2019 and 2019 start on the first of March and of January.
      assert days_of(Tempo.to_interval(~o"R3/P1M/2019-03/FL15DN")) ==
               nearest(:fifteenth, ~D[2019-03-01], 3)

      assert days_of(Tempo.to_interval(~o"R2/P1Y/2019/FL11M3DN")) ==
               nearest(:third_of_november, ~D[2019-01-01], 2)
    end

    test "with no count runs back to the start of its window, and has no first occurrence without one" do
      rule = ~o"R/P1D/2019-01-08/FL7KN"

      assert days_of(Tempo.to_interval(rule, within: ~o"2018-11-20/2019-02-01")) ==
               named_before(:sunday, ~D[2019-01-08], ~D[2018-11-20])

      assert {:error, %UnboundedRecurrenceError{}} = Tempo.to_interval(rule)
    end

    test "is counted from its end, and a window keeps what it holds of the count" do
      assert days_of(Tempo.to_interval(~o"R3/P1D/2019-01-08/FL7KN", within: ~o"2019")) ==
               [~D[2019-01-06]]
    end

    test "is walked by Enum as its occurrences" do
      assert Enum.to_list(~o"R3/P1D/2019-01-08/FL7KN") ==
               [~o"2018Y12M23D", ~o"2018Y12M30D", ~o"2019Y1M6D"]
    end
  end

  describe "a rule written to its end, as an RRULE and in words" do
    test "is written as the rule that runs from its first occurrence" do
      for {text, written} <- [
            {"R3/P1D/2019-01-08/FL7KN", "FREQ=DAILY;COUNT=3;BYDAY=SU"},
            {"R3/P1M/2019-03-31/FL15DN", "FREQ=MONTHLY;COUNT=3;BYMONTHDAY=15"}
          ] do
        rule = Tempo.from_iso8601!(text)
        assert {text, RRule.to_string(rule)} == {text, {:ok, written}}

        # Read from the first of its occurrences, it has the same ones.
        [first | _] = days = days_of(Tempo.to_interval(rule))
        {:ok, read} = RRule.parse(written, from: Tempo.from_iso8601!(Date.to_iso8601(first)))

        assert {text, days_of(Tempo.to_interval(read))} == {text, days}
      end
    end

    test "is explained with what it selects, and that it is counted back" do
      words = to_string(Tempo.explain(~o"R3/P1D/2019-01-08/FL7KN"))

      assert words =~ "Selects: on a Sunday."
      assert words =~ "Counted back from the end"
      refute to_string(Tempo.explain(~o"R3/P1D/2019-01-08")) =~ "Counted back"
    end
  end

  describe "a rule written to its end that holds a window" do
    test "is refused by name, its occurrences being placed outside their periods" do
      assert {:error, %ConversionError{reason: :not_built, target: :rule_to_an_end}} =
               Tempo.to_interval(~o"R2/P1Y/2026-06-01/FL11MLL1K1IN/P7DN45W1KN")
    end
  end
end
