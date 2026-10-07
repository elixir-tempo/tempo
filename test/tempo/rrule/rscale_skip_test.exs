defmodule Tempo.RRule.RscaleSkipTest do
  use ExUnit.Case, async: true

  # RFC 7529 adds two parts to an RRULE: `RSCALE`, the calendar the rule
  # counts its months and days in, and `SKIP`, what it does with a date that
  # does not exist, such as the 31st of a month of thirty days. `OMIT`, the
  # default and RFC 5545's rule, passes over it, `BACKWARD` takes the last
  # day of the month and `FORWARD` the first day of the month after.
  #
  # The measure is `Date` alone: `Date.new/3` says whether a month has the
  # day, `Date.end_of_month/1` its last day, and the day after that is the
  # first of the month after. `Date.shift/2` keeps the last day of a month
  # without the day it started on, which is `BACKWARD` for a start's day.

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

  # Where a day of the month is in a month: the day where the month has it,
  # and otherwise nowhere, the month's last day or the first of the month
  # after.
  defp day_or_moved(%Date{} = month, day, skip) do
    last = Date.end_of_month(month)

    case {Date.new(month.year, month.month, day), skip} do
      {{:ok, date}, _skip} -> [date]
      {{:error, :invalid_date}, :omit} -> []
      {{:error, :invalid_date}, :backward} -> [last]
      {{:error, :invalid_date}, :forward} -> [Date.add(last, 1)]
    end
  end

  # The days a monthly rule for some days of the month selects in each
  # month from January 2026, a day two of them are moved to once, and of
  # those the ones `keep` keeps.
  defp days_selected(days, skip, keep \\ & &1) do
    for step <- 0..59,
        month = Date.shift(~D[2026-01-01], month: step),
        date <- days |> Enum.flat_map(&day_or_moved(month, &1, skip)) |> Enum.uniq() |> keep.(),
        uniq: true,
        do: {date, 1}
  end

  defp skip_part(skip), do: "SKIP=#{skip |> Atom.to_string() |> String.upcase()}"

  describe "SKIP=FORWARD" do
    test "takes the first day of the month after a month without the start's day" do
      for start <- @starts, interval <- [1, 2, 5] do
        expected =
          for step <- 0..11,
              month = Date.shift(Date.beginning_of_month(start), month: step * interval),
              date <- day_or_moved(month, start.day, :forward),
              do: {date, 1}

        rule = "RSCALE=GREGORIAN;FREQ=MONTHLY;INTERVAL=#{interval};SKIP=FORWARD;COUNT=12"

        assert {start, interval, occurrences(read(rule, start))} == {start, interval, expected}
      end
    end

    test "takes 1 March in a year without a 29 February" do
      expected =
        for step <- 0..7,
            date <- day_or_moved(Date.new!(2024 + step, 2, 1), 29, :forward),
            do: {date, 1}

      rule = "RSCALE=GREGORIAN;FREQ=YEARLY;SKIP=FORWARD;COUNT=8"

      assert occurrences(read(rule, ~D[2024-02-29])) == expected
      assert {~D[2025-03-01], 1} in expected
    end

    test "is written as it is read, and has no ISO 8601 form" do
      {:ok, rule} = read("RSCALE=GREGORIAN;FREQ=MONTHLY;SKIP=FORWARD;COUNT=3", ~D[2026-01-31])

      assert {:ok, written} = RRule.to_string(rule)
      assert written == "RSCALE=GREGORIAN;FREQ=MONTHLY;COUNT=3;BYMONTHDAY=31;SKIP=FORWARD"
      assert read(written, ~D[2026-01-31]) == {:ok, rule}

      assert {:error, %Tempo.Iso8601EncodeError{construct: :skip}} = Tempo.to_iso8601(rule)
      assert Tempo.explain(rule) =~ "on the first day of the month after"
    end
  end

  describe "a day of the month the rule writes" do
    test "is moved as the start's is, and two days moved to one are one occurrence" do
      for skip <- [:backward, :forward, :omit],
          days <- [[31], [30, 31], [15, 31], [1, 31], [29, 30, 31]] do
        rule =
          "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=#{Enum.join(days, ",")};" <>
            "#{skip_part(skip)};COUNT=30"

        expected = days |> days_selected(skip) |> Enum.take(30)

        assert {rule, occurrences(read(rule, ~D[2026-01-01]))} == {rule, expected}
      end
    end

    test "is kept by a weekday beside it where the day it is moved to is that weekday" do
      rule = "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=31;BYDAY=SU,MO;SKIP=FORWARD;COUNT=5"

      on_sunday_or_monday = fn dates ->
        Enum.filter(dates, &(Date.day_of_week(&1) in [7, 1]))
      end

      expected = [31] |> days_selected(:forward, on_sunday_or_monday) |> Enum.take(5)

      assert occurrences(read(rule, ~D[2026-01-01])) == expected
      assert hd(expected) == {~D[2026-03-01], 1}
    end

    test "is counted by a position among the days as they are moved" do
      for skip <- [:backward, :forward] do
        rule =
          "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=29,30,31;BYSETPOS=-1;" <>
            "#{skip_part(skip)};COUNT=12"

        last = fn dates -> dates |> Enum.sort(Date) |> Enum.take(-1) end
        expected = [29, 30, 31] |> days_selected(skip, last) |> Enum.take(12)

        assert {skip, occurrences(read(rule, ~D[2026-01-01]))} == {skip, expected}
      end
    end

    test "counted from the end that a month can lack is reported" do
      for skip <- [:backward, :forward] do
        rule = "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=15,-29,-31;#{skip_part(skip)}"

        assert {skip, read(rule, ~D[2026-01-31])} ==
                 {skip, {:error, {:unsupported_skip, {skip, [bymonthday: [-29, -31]]}}}}
      end
    end

    test "that every month has is every month's, and the rule is the one without a skip" do
      for skip <- [:backward, :forward] do
        with_skip = "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=15,-1;#{skip_part(skip)};COUNT=4"
        without = "FREQ=MONTHLY;BYMONTHDAY=15,-1;COUNT=4"

        assert {skip, read(with_skip, ~D[2026-01-31])} == {skip, read(without, ~D[2026-01-31])}
      end
    end
  end

  describe "a day of the year" do
    test "is no day of the month, and is passed over in a year without it whatever the skip" do
      for skip <- [:backward, :forward] do
        rule = "RSCALE=GREGORIAN;FREQ=YEARLY;BYYEARDAY=366;#{skip_part(skip)};COUNT=2"

        assert {skip, occurrences(read(rule, ~D[2024-01-01]))} ==
                 {skip, [{~D[2024-12-31], 1}, {~D[2028-12-31], 1}]}
      end
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
      {:ok, %Interval{} = rule} =
        read("RSCALE=GREGORIAN;FREQ=MONTHLY;SKIP=BACKWARD;COUNT=3", ~D[2026-01-31])

      assert %{rule | metadata: %{}} == ~o"R3/2026-01-31/P1M"
      assert RRule.to_string(rule) == {:ok, "FREQ=MONTHLY;COUNT=3;BYMONTHDAY=-1"}
    end

    test "beside a time of day keeps each occurrence as long as the time is precise" do
      {:ok, rule} =
        read("RSCALE=GREGORIAN;FREQ=MONTHLY;BYHOUR=9;SKIP=BACKWARD;COUNT=3", ~D[2026-01-31])

      {:ok, set} = Tempo.to_interval(rule)

      # An hour from nine on the month's last day. It was a day long, the
      # length a rule with no part is given.
      assert Enum.map(IntervalSet.members(set), &Tempo.to_iso8601!/1) ==
               ["2026Y1M31DT9H/T10H", "2026Y2M28DT9H/T10H", "2026Y3M31DT9H/T10H"]
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
    test "a SKIP that is none of the three" do
      assert RRule.parse("RSCALE=GREGORIAN;FREQ=MONTHLY;SKIP=SIDEWAYS") ==
               {:error, {:unsupported_skip, "SIDEWAYS"}}
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
