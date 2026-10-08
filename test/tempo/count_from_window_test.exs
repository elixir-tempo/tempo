defmodule Tempo.CountFromWindowTest do
  @moduledoc """
  The count of a rule with no start is of the occurrences from its window's
  start (decided 2026-10-08).

  A rule with no start begins where its `:within` window does, and is
  walked from the period the window starts in: the year, for a rule that
  steps by years. An occurrence of that period that was over before the
  window opened was counted and then dropped, so `R2/../P1Y/FL1M1DN` within
  June 2026 to June 2029 was 1 January 2027 alone, where
  `R2/2026-06-01/P1Y/FL1M1DN` is that day and 1 January 2028.

  The measure is Elixir's own `Date`: each day of the window is asked
  whether the rule names it, and the first so many are taken.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  @window_from ~D[2026-06-03]
  @window_to ~D[2029-06-01]

  # A rule, and whether it names a day.
  @rules [
    {"P1Y/FL1M1DN", :new_year},
    {"P1Y/FL6M-1DN", :last_of_june},
    {"P1M/FL15DN", :fifteenth},
    {"P1M/FL1K1IN", :first_monday},
    {"P1W/FL1KN", :monday},
    {"P1D/FL{6,7}KN", :weekend}
  ]

  ## The measure

  defp named?(:new_year, date), do: date.month == 1 and date.day == 1
  defp named?(:last_of_june, date), do: date.month == 6 and date.day == 30
  defp named?(:fifteenth, date), do: date.day == 15
  defp named?(:first_monday, date), do: Date.day_of_week(date) == 1 and date.day <= 7
  defp named?(:monday, date), do: Date.day_of_week(date) == 1
  defp named?(:weekend, date), do: Date.day_of_week(date) in [6, 7]

  # The first `count` days of the window a rule names.
  defp first_named(name, count, from \\ @window_from) do
    from
    |> Date.range(Date.add(@window_to, -1))
    |> Stream.filter(&named?(name, &1))
    |> Enum.take(count)
  end

  # The days a conversion gave: one interval for a rule of one occurrence,
  # and a set of them for a longer one.
  defp days_of({:ok, %Interval{} = one}), do: [day_of(one)]
  defp days_of({:ok, %IntervalSet{} = set}), do: Enum.map(IntervalSet.members(set), &day_of/1)

  defp day_of(%Interval{} = occurrence) do
    {:ok, date} = Tempo.to_date(Interval.from(occurrence))
    Date.convert!(date, Calendar.ISO)
  end

  defp window, do: Tempo.from_iso8601!("#{@window_from}/#{@window_to}")

  describe "a rule with a count and no start, in a window" do
    test "has the first of its occurrences from the window's start, as many as it counts" do
      for {rule, name} <- @rules, count <- 1..4 do
        text = "R#{count}/../#{rule}"

        assert {text, days_of(Tempo.to_interval(Tempo.from_iso8601!(text), within: window()))} ==
                 {text, first_named(name, count)}
      end
    end

    test "is the rule written from the window's start" do
      for {rule, _name} <- @rules, count <- 2..3 do
        with_no_start = Tempo.from_iso8601!("R#{count}/../#{rule}")
        from_the_start = Tempo.from_iso8601!("R#{count}/#{@window_from}/#{rule}")

        assert {rule, count, days_of(Tempo.to_interval(with_no_start, within: window()))} ==
                 {rule, count, days_of(Tempo.to_interval(from_the_start))}
      end
    end

    test "has those the window holds, where it counts more than there are" do
      rule = ~o"R9/../P1Y/FL1M1DN"

      assert days_of(Tempo.to_interval(rule, within: window())) ==
               [~D[2027-01-01], ~D[2028-01-01], ~D[2029-01-01]]
    end

    test "is counted so in a window with no end, and read from an RRULE" do
      open_ended = Tempo.from_iso8601!("#{@window_from}/..")

      assert days_of(Tempo.to_interval(~o"R2/../P1Y/FL1M1DN", within: open_ended)) ==
               first_named(:new_year, 2)

      {:ok, rule} = RRule.parse("FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=1;COUNT=2")
      assert days_of(Tempo.to_interval(rule, within: window())) == first_named(:new_year, 2)
    end
  end

  describe "an occurrence the window opens in" do
    test "is in the window, and is the first of the count" do
      # June 2026 has begun when the window opens on the 20th, and is not
      # over: the two months counted are June and July.
      {:ok, months} = Tempo.to_interval(~o"R2/../P1M", within: ~o"2026-06-20/2026-12-01")

      assert Enum.map(IntervalSet.members(months), &Interval.from/1) ==
               [~o"2026Y6M1D", ~o"2026Y7M1D"]

      # Nine o'clock has begun at half past, and is counted.
      {:ok, hours} =
        Tempo.to_interval(~o"R2/../PT1H/FLT{9,10}HN", within: ~o"2026-06-07T09:30/2026-07-01")

      assert Enum.map(IntervalSet.members(hours), &Interval.from/1) ==
               [~o"2026Y6M7DT9H", ~o"2026Y6M7DT10H"]
    end
  end

  describe "a rule with a count and a start" do
    test "is counted from its start, whatever window it is kept to" do
      # Its two occurrences are 1 January 2019 and 2020, both before the window.
      assert Tempo.to_interval(~o"R2/2019-01-01/P1Y/FL1M1DN", within: ~o"2020-06-01/2030") ==
               IntervalSet.new([])

      assert days_of(Tempo.to_interval(~o"R2/2019-01-01/P1Y/FL1M1DN", within: ~o"2020/2030")) ==
               [~D[2020-01-01]]
    end
  end
end
