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
  #
  # A day counted from the end that the month lacks lies before its first
  # day (decided 2026-10-09, the RFCs not saying): moved on it is the 1st,
  # and moved back the last day of the month before.
  defp day_or_moved(%Date{} = month, day, skip) when day < 0 do
    first = Date.beginning_of_month(month)
    counted = Date.days_in_month(month) + 1 + day

    cond do
      counted >= 1 -> [Date.new!(month.year, month.month, counted)]
      skip == :omit -> []
      skip == :backward -> [Date.add(first, -1)]
      skip == :forward -> [first]
    end
  end

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

    test "counted from the end that a month lacks is the day before its first" do
      # It was reported and not read (`:unsupported_skip`).
      for skip <- [:backward, :forward, :omit],
          days <- [[-31], [-30], [-29, -31], [15, -29, -31], [1, -31], [-1, -31], [31, -31]] do
        rule =
          "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=#{Enum.join(days, ",")};" <>
            "#{skip_part(skip)};COUNT=30"

        expected =
          days |> days_selected(skip) |> Enum.sort_by(&elem(&1, 0), Date) |> Enum.take(30)

        assert {rule, occurrences(read(rule, ~D[2026-01-01]))} == {rule, expected}
      end

      # The 31st from the end of each month of 2026 that has thirty days or
      # fewer is the last day of the month before it, moved back, and the
      # month's first, moved on.
      back =
        occurrences(
          read(
            "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=-31;SKIP=BACKWARD;COUNT=4",
            ~D[2026-01-01]
          )
        )

      on =
        occurrences(
          read(
            "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=-31;SKIP=FORWARD;COUNT=4",
            ~D[2026-01-01]
          )
        )

      assert Enum.map(back, &elem(&1, 0)) == [
               ~D[2026-01-01],
               ~D[2026-01-31],
               ~D[2026-03-01],
               ~D[2026-03-31]
             ]

      assert Enum.map(on, &elem(&1, 0)) == [
               ~D[2026-01-01],
               ~D[2026-02-01],
               ~D[2026-03-01],
               ~D[2026-04-01]
             ]
    end

    test "moved back before the rule's start is no occurrence" do
      # April has no 31st from its end, and 31 March is before a start of 10 April.
      rule = "RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=-31;SKIP=BACKWARD;COUNT=3"

      assert Enum.map(occurrences(read(rule, ~D[2026-04-10])), &elem(&1, 0)) ==
               [~D[2026-05-01], ~D[2026-05-31], ~D[2026-07-01]]
    end

    test "counted from the end of a February is moved in a year without its 29th" do
      for {skip, moved} <- [backward: ~D[2026-01-31], forward: ~D[2026-02-01]] do
        rule = "RSCALE=GREGORIAN;FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-29;#{skip_part(skip)};COUNT=3"

        # 2028 has a 29th of February, and the 29th from its end is its 1st.
        assert {skip, Enum.map(occurrences(read(rule, ~D[2026-01-01])), &elem(&1, 0))} ==
                 {skip, [moved, Date.shift(moved, year: 1), ~D[2028-02-01]]}
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

  describe "a calendar whose shortest month is not the Gregorian calendar's" do
    alias Calendrical.Ethiopic
    alias Calendrical.Hebrew

    # The Gregorian date each occurrence starts on.
    defp gregorian_starts({:ok, rule}) do
      {:ok, set} = Tempo.to_interval(rule)

      for occurrence <- IntervalSet.members(set) do
        {:ok, date} = occurrence |> Interval.from() |> Tempo.to_calendar(Calendrical.Gregorian)
        Date.new!(Tempo.year(date), Tempo.month(date), Tempo.day(date))
      end
    end

    defp in_gregorian(year, month, day, calendar),
      do: year |> Date.new!(month, day, calendar) |> Date.convert!(Calendar.ISO)

    test "has its own days moved: the sixth of an Ethiopic year's thirteenth month" do
      # The thirteenth month has five days, and six in a leap year. Its 6th
      # was not moved, a day up to the 28th having been taken for one every
      # month of every calendar has.
      years = 2010..2014
      assert Enum.map(years, &Ethiopic.days_in_month(&1, 13)) == [5, 6, 5, 5, 5]

      rule = fn skip ->
        RRule.parse("RSCALE=ETHIOPIC;FREQ=YEARLY;BYMONTH=13;BYMONTHDAY=6#{skip};COUNT=5",
          from: ~o"2018-01-01"
        )
      end

      sixth_or = fn moved ->
        for year <- years do
          if Ethiopic.days_in_month(year, 13) == 6,
            do: in_gregorian(year, 13, 6, Ethiopic),
            else: moved.(year)
        end
      end

      assert gregorian_starts(rule.(";SKIP=BACKWARD")) ==
               sixth_or.(&in_gregorian(&1, 13, 5, Ethiopic))

      assert gregorian_starts(rule.(";SKIP=FORWARD")) ==
               sixth_or.(&in_gregorian(&1 + 1, 1, 1, Ethiopic))

      assert Enum.take(gregorian_starts(rule.("")), 1) == [in_gregorian(2011, 13, 6, Ethiopic)]
    end

    test "is RFC 7529's example of the Ethiopic thirteenth month" do
      # §4.3.2: the first day of the thirteenth month, from 6 September 2013.
      rule = RRule.parse("RSCALE=ETHIOPIC;FREQ=MONTHLY;BYMONTH=13;COUNT=5", from: ~o"2013-09-06")

      assert gregorian_starts(rule) ==
               [~D[2013-09-06], ~D[2014-09-06], ~D[2015-09-06], ~D[2016-09-06], ~D[2017-09-06]]
    end

    test "is RFC 7529's example of the Gregorian leap day" do
      # §4.3.4: 29 February, forward to 1 March in a year without it.
      rule =
        RRule.parse("RSCALE=GREGORIAN;FREQ=YEARLY;SKIP=FORWARD;COUNT=6", from: ~o"2012-02-29")

      assert gregorian_starts(rule) ==
               [~D[2012-02-29], ~D[2013-03-01], ~D[2014-03-01], ~D[2015-03-01]] ++
                 [~D[2016-02-29], ~D[2017-03-01]]
    end

    test "has the 30th from the end of a Hebrew month of twenty-nine days moved" do
      # From 1 Shevat 5786: Shevat, Nisan and Sivan have thirty days, and
      # Adar, Iyar and Tammuz twenty-nine.
      months = 5..10
      assert Enum.map(months, &Hebrew.days_in_month(5786, &1)) == [30, 29, 30, 29, 30, 29]

      back =
        RRule.parse("RSCALE=HEBREW;FREQ=MONTHLY;BYMONTHDAY=-30;SKIP=BACKWARD;COUNT=6",
          from: ~o"2026-01-19"
        )

      expected =
        for month <- months do
          if Hebrew.days_in_month(5786, month) == 30,
            do: in_gregorian(5786, month, 1, Hebrew),
            else: Date.add(in_gregorian(5786, month, 1, Hebrew), -1)
        end

      assert gregorian_starts(back) == expected
    end
  end

  describe "what is not built is reported" do
    test "a SKIP that is none of the three" do
      assert RRule.parse("RSCALE=GREGORIAN;FREQ=MONTHLY;SKIP=SIDEWAYS") ==
               {:error, {:unsupported_skip, "SIDEWAYS"}}
    end

    test "an RSCALE that names no calendar" do
      assert RRule.parse("RSCALE=KLINGON;FREQ=YEARLY") ==
               {:error, {:unsupported_rscale, "KLINGON"}}
    end

    test "SKIP with no RSCALE, which RFC 7529 forbids" do
      assert RRule.parse("FREQ=MONTHLY;SKIP=BACKWARD") ==
               {:error, {:skip_without_rscale, :backward}}
    end
  end
end
