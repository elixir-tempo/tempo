defmodule Tempo.RRule.RscaleSkipTest do
  use ExUnit.Case, async: true

  # RFC 7529 adds two parts to an RRULE: `RSCALE`, the calendar the rule
  # counts its months and days in, and `SKIP`, what it does with a date that
  # does not exist, such as the 31st of a month of thirty days. `OMIT`, the
  # default and RFC 5545's rule, passes over it, and `BACKWARD` takes the
  # last day of the month. `Tempo.RRule.parse/2` returned
  # `{:error, {:unknown_rule_part, "SKIP"}}` for each.
  #
  # The measure is `Date` alone: `Date.shift/2` keeps the last day of a month
  # without the day it started on, which is `BACKWARD`, and `Date.new/3` says
  # whether a month has the day, which is `OMIT`.

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  @starts [~D[2026-01-28], ~D[2026-01-29], ~D[2026-01-30], ~D[2026-01-31], ~D[2024-02-29]]

  defp read(rule, %Date{} = start), do: RRule.parse(rule, from: Tempo.from_date(start))

  # The day each occurrence starts on and how many days long it is.
  defp occurrences({:ok, rule}) do
    {:ok, set} = Tempo.to_interval(rule)

    for occurrence <- IntervalSet.members(set) do
      {:ok, from} = occurrence |> Interval.from() |> Tempo.to_date()
      {:ok, to} = occurrence |> Interval.to() |> Tempo.to_date()
      {from, Date.diff(to, from)}
    end
  end

  describe "SKIP=BACKWARD" do
    test "keeps the last day of a month without the start's day" do
      for start <- @starts, interval <- [1, 2, 5] do
        expected = for step <- 0..11, do: {Date.shift(start, month: step * interval), 1}

        rule =
          "RSCALE=GREGORIAN;FREQ=MONTHLY;INTERVAL=#{interval};SKIP=BACKWARD;COUNT=12"

        assert {start, interval, occurrences(read(rule, start))} == {start, interval, expected}
      end
    end

    test "keeps the last day of February in a year without its 29th" do
      expected = for step <- 0..7, do: {Date.shift(~D[2024-02-29], year: step), 1}
      rule = "RSCALE=GREGORIAN;FREQ=YEARLY;SKIP=BACKWARD;COUNT=8"

      assert occurrences(read(rule, ~D[2024-02-29])) == expected
    end

    test "is the ISO 8601 recurrence of the same start, each occurrence as long as the start" do
      {:ok, rule} = read("RSCALE=GREGORIAN;FREQ=MONTHLY;SKIP=BACKWARD;COUNT=3", ~D[2026-01-31])

      assert %Interval{rule | metadata: %{}} == ~o"R3/2026-01-31/P1M"
      assert RRule.to_string(rule) == {:ok, "COUNT=3;FREQ=MONTHLY;BYMONTHDAY=-1"}
    end

    test "beside a day the rule writes that a month or a year can lack is reported" do
      for {parts, missing} <- [
            {"FREQ=MONTHLY;BYMONTHDAY=31", [bymonthday: [31]]},
            {"FREQ=MONTHLY;BYMONTHDAY=15,30,-29", [bymonthday: [30, -29]]},
            {"FREQ=YEARLY;BYYEARDAY=366", [byyearday: [366]]}
          ] do
        assert {parts, read("RSCALE=GREGORIAN;SKIP=BACKWARD;" <> parts, ~D[2026-01-31])} ==
                 {parts, {:error, {:unsupported_skip, {:backward, missing}}}}
      end

      # A day every month has is every month's.
      assert {:ok, _rule} =
               read("RSCALE=GREGORIAN;SKIP=BACKWARD;FREQ=MONTHLY;BYMONTHDAY=15", ~D[2026-01-31])
    end
  end

  describe "SKIP=OMIT, and a rule with no SKIP" do
    test "pass over a month without the start's day, as RFC 5545 does" do
      for start <- @starts,
          rule <- ["RSCALE=GREGORIAN;SKIP=OMIT;FREQ=MONTHLY", "RSCALE=GREGORIAN;FREQ=MONTHLY"] do
        months = for step <- 0..40, do: Date.shift(Date.beginning_of_month(start), month: step)

        expected =
          for month <- months,
              {:ok, date} <- [Date.new(month.year, month.month, start.day)],
              do: {date, 1}

        assert {start, rule, occurrences(read(rule <> ";COUNT=12", start))} ==
                 {start, rule, Enum.take(expected, 12)}
      end
    end

    test "read as the rule without them" do
      start = Tempo.from_date(~D[2026-01-31])

      assert RRule.parse("RSCALE=GREGORIAN;SKIP=OMIT;FREQ=MONTHLY;COUNT=3", from: start) ==
               RRule.parse("FREQ=MONTHLY;COUNT=3", from: start)

      assert RRule.parse("rscale=gregorian;freq=monthly;count=3", from: start) ==
               RRule.parse("FREQ=MONTHLY;COUNT=3", from: start)
    end
  end

  describe "what is not built is reported" do
    test "SKIP=FORWARD, the first day of the month after" do
      assert RRule.parse("RSCALE=GREGORIAN;FREQ=MONTHLY;SKIP=FORWARD") ==
               {:error, {:unsupported_skip, "FORWARD"}}
    end

    test "a rule counted in another calendar than the Gregorian" do
      assert RRule.parse("RSCALE=HEBREW;FREQ=YEARLY") == {:error, {:unsupported_rscale, "HEBREW"}}
    end

    test "SKIP with no RSCALE, which RFC 7529 forbids" do
      assert RRule.parse("FREQ=MONTHLY;SKIP=BACKWARD") ==
               {:error, {:skip_without_rscale, :backward}}
    end
  end
end
