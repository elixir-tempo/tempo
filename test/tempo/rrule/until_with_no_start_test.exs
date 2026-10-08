defmodule Tempo.RRule.UntilWithNoStartTest do
  @moduledoc """
  A rule with no start that runs until an end, as an RRULE with `UNTIL`
  read with no start is.

  It starts where its `:within` window does, as a rule with no start and no
  end does, and runs on to its end, which is its last occurrence where the
  rule names it (RFC 5545 §3.3.10: `UNTIL` "bounds the recurrence rule in
  an inclusive manner"). `FREQ=DAILY;UNTIL=20190108` with no start was
  handed back as it was given, as if that were its conversion, and with a
  part that selects it was refused as a rule written to its end.

  The measure is Elixir's own `Date`: each day from the window's start to
  the end, asked whether the rule names it.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.RRule

  @until ~D[2019-01-08]

  # A rule's parts, and whether it names a day.
  @rules [
    {"FREQ=DAILY", :every_day},
    {"FREQ=DAILY;BYDAY=SU", :sunday},
    {"FREQ=WEEKLY;BYDAY=MO,TH", :monday_or_thursday},
    {"FREQ=MONTHLY;BYMONTHDAY=1,15", :first_or_fifteenth}
  ]

  ## The measure

  defp named?(:every_day, _date), do: true
  defp named?(:sunday, date), do: Date.day_of_week(date) == 7
  defp named?(:monday_or_thursday, date), do: Date.day_of_week(date) in [1, 4]
  defp named?(:first_or_fifteenth, date), do: date.day in [1, 15]

  # The days a rule names from a day to its end, which is one of them.
  defp named_until(name, from),
    do: from |> Date.range(@until) |> Enum.filter(&named?(name, &1))

  defp days_of({:ok, %IntervalSet{} = set}) do
    for occurrence <- IntervalSet.members(set) do
      {:ok, date} = Tempo.to_date(Interval.from(occurrence))
      Date.convert!(date, Calendar.ISO)
    end
  end

  defp rule(parts) do
    {:ok, rule} = RRule.parse("#{parts};UNTIL=#{Calendar.strftime(@until, "%Y%m%d")}")
    rule
  end

  describe "a rule with an UNTIL and no start, in a window" do
    test "has each day it names from the window's start to its end" do
      for {parts, name} <- @rules, from <- [~D[2018-11-20], ~D[2018-12-30], ~D[2019-01-08]] do
        window = Tempo.from_iso8601!("#{from}/2019-03-01")

        assert {parts, from, days_of(Tempo.to_interval(rule(parts), within: window))} ==
                 {parts, from, named_until(name, from)}
      end
    end

    test "is the rule read with the window's start for its own" do
      for {parts, _name} <- @rules do
        {:ok, from_the_start} =
          RRule.parse("#{parts};UNTIL=#{Calendar.strftime(@until, "%Y%m%d")}",
            from: ~o"2018-12-03"
          )

        assert {parts, days_of(Tempo.to_interval(rule(parts), within: ~o"2018-12-03/2019-03-01"))} ==
                 {parts, days_of(Tempo.to_interval(from_the_start))}
      end
    end

    test "has no occurrence in a window that opens after its end" do
      assert Tempo.to_interval(rule("FREQ=DAILY"), within: ~o"2019-02-01/2019-03-01") ==
               IntervalSet.new([])
    end

    test "runs to its end in a window that has none" do
      assert days_of(Tempo.to_interval(rule("FREQ=DAILY;BYDAY=SU"), within: ~o"2018-12-20/..")) ==
               named_until(:sunday, ~D[2018-12-20])
    end
  end

  describe "a rule with an UNTIL and no start, with no window" do
    test "has nowhere to start, and says so" do
      for {parts, _name} <- @rules do
        assert {^parts, {:error, %IntervalEndpointsError{reason: :open_start}}} =
                 {parts, Tempo.to_interval(rule(parts))}
      end
    end
  end
end
