defmodule Tempo.RecurrenceWindowTest do
  use ExUnit.Case, async: true

  # The occurrences of a recurrence within a window, where the window is a
  # long way on from the recurrence's start.
  #
  # A walk began at the start and took ten thousand periods at most, with no
  # word when it was cut short. A recurrence of days from 1990 never came to
  # June 2026 and gave no occurrences there, as if it had none; one of
  # minutes with thirty occurrences a month gave seven; and
  # `R20000/2026-06-01/P1D` gave ten thousand.
  #
  # A walk kept to a window now begins at the first period that can reach
  # it, and a walk that is cut short fails by name.
  #
  # The first measure is Elixir's `Date` and `NaiveDateTime`: the starts a
  # plain recurrence has are counted on from its start by their own
  # arithmetic. The second is the walk from the start itself: for a rule with
  # parts, the occurrences in a window are those of the walk that begins at
  # the recurrence's start which overlap it, where the window is near enough
  # for that walk to be made.

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule
  alias Tempo.UnboundedRecurrenceError

  defp read(text), do: Tempo.from_iso8601!(text)

  defp starts(value, within) do
    {:ok, set} = Tempo.to_interval(value, within: within)
    Enum.map(IntervalSet.members(set), &Interval.from/1)
  end

  defp rule(text, from, options \\ []) do
    {:ok, value} = RRule.parse(text, [from: from] ++ options)
    value
  end

  # An occurrence of a plain recurrence is one cadence long, and is kept
  # where it overlaps the window: it starts before the window closes, and
  # the occurrence after it starts after the window opens.
  describe "a plain recurrence, in a window long after its start" do
    test "of days has the days Date counts on from the start" do
      start = ~D[1990-01-01]

      for every <- [1, 2, 7, 30] do
        expected =
          for date <- Date.range(~D[2026-04-01], ~D[2026-06-30]),
              rem(Date.diff(date, start), every) == 0,
              Date.compare(Date.add(date, every), ~D[2026-06-01]) == :gt,
              do: Tempo.from_date(date)

        assert {every, starts(read("R/1990-01-01/P#{every}D"), read("2026-06"))} ==
                 {every, expected}

        daily = rule("FREQ=DAILY;INTERVAL=#{every}", Tempo.from_date(start))
        assert {every, starts(daily, read("2026-06"))} == {every, expected}
      end
    end

    test "of weeks has the days Date counts on from the start" do
      start = ~D[1800-01-06]

      for every <- [1, 2, 5] do
        expected =
          for date <- Date.range(~D[2026-04-01], ~D[2026-07-31]),
              rem(Date.diff(date, start), 7 * every) == 0,
              Date.compare(Date.add(date, 7 * every), ~D[2026-06-01]) == :gt,
              do: Tempo.from_date(date)

        assert {every, starts(read("R/1800-01-06/P#{every}W"), read("2026-06-01/2026-08-01"))} ==
                 {every, expected}
      end
    end

    test "of hours and of minutes has the times NaiveDateTime counts on from the start" do
      day = ~N[2026-06-15 00:00:00]

      for {unit, designator, from, every} <- [
            {:hour, "H", ~N[2020-01-01 00:00:00], 1},
            {:hour, "H", ~N[2020-01-01 00:00:00], 5},
            {:minute, "M", ~N[2026-01-01 00:07:00], 15},
            {:minute, "M", ~N[2026-06-01 00:00:00], 1}
          ] do
        in_a_day = if unit == :hour, do: 24, else: 1_440

        # From a cadence before the day opens, to its close.
        expected =
          for step <- -every..(in_a_day - 1),
              time = NaiveDateTime.add(day, step, unit),
              rem(NaiveDateTime.diff(time, from, unit), every) == 0,
              NaiveDateTime.compare(NaiveDateTime.add(time, every, unit), day) == :gt,
              do: Tempo.from_elixir(time)

        text = "R/#{NaiveDateTime.to_iso8601(from)}/PT#{every}#{designator}"

        assert {text, starts(read(text), read("2026-06-15"))} == {text, expected}
      end
    end

    test "of months and of years has the dates Date.shift gives the start" do
      # The 31st and a leap day, which a month and a year do not all have.
      for {text, start, unit, every, window, opens, closes} <- [
            {"R/1990-01-31/P1M", ~D[1990-01-31], :month, 1, "2026", ~D[2026-01-01],
             ~D[2027-01-01]},
            {"R/1990-01-31/P5M", ~D[1990-01-31], :month, 5, "2026/2030", ~D[2026-01-01],
             ~D[2030-01-01]},
            {"R/0004-02-29/P1Y", ~D[0004-02-29], :year, 1, "2026/2033", ~D[2026-01-01],
             ~D[2033-01-01]}
          ] do
        nth = fn step -> Date.shift(start, [{unit, step * every}]) end

        expected =
          Stream.iterate(0, &(&1 + 1))
          |> Stream.map(&{nth.(&1), nth.(&1 + 1)})
          |> Stream.drop_while(fn {_starts, next} -> Date.compare(next, opens) != :gt end)
          |> Enum.take_while(fn {starts, _next} -> Date.compare(starts, closes) == :lt end)
          |> Enum.map(fn {starts, _next} -> Tempo.from_date(starts) end)

        assert {text, starts(read(text), read(window))} == {text, expected}
      end
    end
  end

  describe "a rule with parts, in a window some thousands of periods on" do
    @from_2010 "2010-01-01"
    @from_2025 "2025-06-01T00:00:00"
    @from_9_june "2026-06-09T00:00:00"

    # Each rule and where it starts.
    @rules [
      {"FREQ=DAILY", @from_2010},
      {"FREQ=DAILY;INTERVAL=3", @from_2010},
      {"FREQ=DAILY;BYDAY=MO,WE", @from_2010},
      {"FREQ=DAILY;BYMONTHDAY=1,15,-1", @from_2010},
      {"FREQ=DAILY;BYMONTH=6;BYDAY=FR", @from_2010},
      {"FREQ=WEEKLY", @from_2010},
      {"FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH", @from_2010},
      {"FREQ=WEEKLY;BYDAY=SU;WKST=SU", @from_2010},
      {"FREQ=MONTHLY", "2010-01-31"},
      {"FREQ=MONTHLY;BYMONTHDAY=31", @from_2010},
      {"FREQ=MONTHLY;BYDAY=1MO,-1FR", @from_2010},
      {"FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=-1", @from_2010},
      {"FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", @from_2010},
      {"RSCALE=GREGORIAN;FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD", @from_2010},
      {"FREQ=YEARLY", "2010-06-15"},
      {"FREQ=YEARLY;BYMONTH=6;BYDAY=2MO", @from_2010},
      {"FREQ=YEARLY;BYWEEKNO=25;BYDAY=MO", @from_2010},
      {"FREQ=YEARLY;BYYEARDAY=166,-1", @from_2010},
      {"FREQ=YEARLY;INTERVAL=4;BYMONTH=2;BYMONTHDAY=29", "2008-02-29"},
      {"FREQ=HOURLY", @from_2025},
      {"FREQ=HOURLY;INTERVAL=5", @from_2025},
      {"FREQ=HOURLY;BYHOUR=9,17", @from_2025},
      {"FREQ=HOURLY;BYDAY=MO;BYHOUR=9", @from_2025},
      {"FREQ=MINUTELY;INTERVAL=15", @from_9_june},
      {"FREQ=MINUTELY;BYHOUR=9;BYMINUTE=0,30", @from_9_june},
      # In a zone, where a window holds the night the clocks go forward.
      {"FREQ=DAILY", "2010-01-01T02:30:00[America/New_York]"},
      {"FREQ=WEEKLY;BYDAY=SU", "2010-01-03T02:30:00[America/New_York]"}
    ]

    # An occurrence longer than its period: it runs on past the start of the
    # next, and into a window that opens after its own start.
    @long_occurrences [
      {"FREQ=DAILY", "2010-01-01T10:00:00", :duration, "P2DT2H"},
      {"FREQ=WEEKLY;BYDAY=MO", "2010-01-04T09:00:00", :duration, "P9D"},
      {"FREQ=DAILY", "2010-01-01T10:00:00", :base_to, "2010-01-03T12:00:00"},
      {"FREQ=MONTHLY;BYMONTHDAY=28", "2010-01-28", :duration, "P40D"}
    ]

    # Rules written in ISO 8601, with a window of their own after an anchor.
    @iso_rules [
      "R/2010-01-01/P1Y/FL11MLL1K1IN/P9DN2K1IN",
      "R/2010-01-01/P1Y/FLLL(easter)eN/P-3DN5K1IN",
      "R/2010-01-01/P1M/FLL25DN/P10DN",
      "R/2010-01-01/P1Y/FL6M2K1IN"
    ]

    @windows [
      "2026-06",
      "2026-06-15",
      "2026-03-08",
      "2026-06-15T09/2026-06-15T18",
      "2026-01/2027-01",
      "2009-06"
    ]

    test "is what the walk from the start has in the window" do
      plain = for {text, from} <- @rules, do: {text, rule(text, read(from))}

      long =
        for {text, from, option, value} <- @long_occurrences do
          {"#{text} #{option} #{value}", rule(text, read(from), [{option, read(value)}])}
        end

      written = for text <- @iso_rules, do: {text, read(text)}

      cases =
        for {text, value} <- plain ++ long ++ written,
            window <- @windows,
            do: {text, value, window}

      compared =
        cases
        |> Task.async_stream(&kept_and_walked/1, timeout: :infinity, ordered: false)
        |> Enum.map(fn {:ok, compared} -> compared end)
        # The walk from the start is cut short where the window closes more
        # than ten thousand periods on, and is then no measure.
        |> Enum.reject(fn {_text, _window, _kept, walked} -> walked == :cut_short end)

      differing = for {_text, _window, kept, walked} = pair <- compared, kept != walked, do: pair

      assert differing == []
      assert Enum.count(compared) > 180
    end
  end

  # What a rule gives kept to a window, and what the walk from its start to
  # the window's close has that overlaps the window: each occurrence as the
  # moments it starts and ends at. A window that holds more occurrences than
  # a walk gives is cut short on both ways.
  defp kept_and_walked({text, value, window}) do
    {:ok, %Interval{} = span} = Tempo.to_interval(read(window))
    {window_from, window_to} = bounds(span)

    kept =
      case Tempo.to_interval(value, within: read(window)) do
        {:ok, set} -> Enum.map(IntervalSet.members(set), &bounds/1)
        {:error, %UnboundedRecurrenceError{}} -> :cut_short
      end

    in_window =
      case walked_from_the_start(value, Interval.to(span)) do
        :cut_short -> :cut_short
        walked -> for {from, to} <- walked, from < window_to and to > window_from, do: {from, to}
      end

    {text, window, kept, in_window}
  end

  # Every occurrence from a rule's start to where a window closes, or none
  # where the window closes before the rule starts.
  defp walked_from_the_start(%Interval{from: start} = value, window_to) do
    if Compare.to_utc_seconds(start) < Compare.to_utc_seconds(window_to),
      do: walked_within(value, Interval.new!(from: start, to: window_to)),
      else: []
  end

  defp walked_within(value, window) do
    case Tempo.to_interval(value, within: window) do
      {:ok, walked} -> Enum.map(IntervalSet.members(walked), &bounds/1)
      {:error, %UnboundedRecurrenceError{}} -> :cut_short
    end
  end

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  describe "a walk that is cut short" do
    test "fails by name, where it gave the occurrences it had come to" do
      for {text, from} <- [
            {"FREQ=DAILY;COUNT=10001", "2026-06-01"},
            # A Monday, and the Tuesday the walk goes on from to the next,
            # are two periods.
            {"FREQ=DAILY;BYDAY=MO;COUNT=5100", "2026-06-01"},
            # And so are the first second of a minute and the one after it.
            {"FREQ=SECONDLY;BYSECOND=0;COUNT=6000", "2026-06-01T00:00:00"},
            # A week runs across a month and a year, so each is asked: ten
            # Mondays that are 29 February are nearly three centuries of them.
            {"FREQ=WEEKLY;BYMONTH=2;BYMONTHDAY=29;BYDAY=MO;COUNT=10", "2026-01-01"}
          ] do
        assert {:error, %UnboundedRecurrenceError{} = error} =
                 Tempo.to_interval(rule(text, read(from)))

        assert {text, Exception.message(error) =~ "at most 10000 periods"} == {text, true}
      end

      assert {:error, %UnboundedRecurrenceError{}} =
               Tempo.to_interval(read("R20000/2026-06-01/P1D"))

      # More occurrences in a window than are given at once.
      assert {:error, %UnboundedRecurrenceError{} = error} =
               Tempo.to_interval(read("R/2026-06-15T00:00:00/PT1S"), within: read("2026-06-15"))

      assert Exception.message(error) =~ "at most 10000 occurrences"
    end

    test "is no failure where the walk has what it was asked for by then" do
      assert {:ok, set} = Tempo.to_interval(rule("FREQ=DAILY;COUNT=10000", read("2026-06-01")))
      assert IntervalSet.count(set) == 10_000

      # Rules whose occurrences are far apart for their frequency, each of
      # which was cut short: thirty mornings are 43,000 minutes, and the
      # next 29 February that is a Monday is eighteen years of days on.
      for {text, from, count} <- [
            {"FREQ=MINUTELY;BYHOUR=9;BYMINUTE=0;COUNT=30", "2026-06-01T00:00:00", 30},
            {"FREQ=HOURLY;BYHOUR=9;COUNT=500", "2026-06-01T00:00:00", 500},
            {"FREQ=DAILY;BYDAY=MO;COUNT=2000", "2026-06-01", 2000},
            {"FREQ=DAILY;BYMONTH=2;BYMONTHDAY=29;BYDAY=MO;COUNT=3", "2026-01-01", 3},
            {"FREQ=DAILY;BYYEARDAY=100;COUNT=40", "2026-01-01", 40}
          ] do
        assert {:ok, set} = Tempo.to_interval(rule(text, read(from)))
        assert {text, IntervalSet.count(set)} == {text, count}
      end

      # A rule that selects no date has no occurrence to come to, and none.
      april_31st = rule("FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=31;COUNT=2", read("2026-01-31"))

      assert {:ok, nothing} = Tempo.to_interval(april_31st)
      assert IntervalSet.count(nothing) == 0

      # The rule of 29 February on a Monday, a year at a time, comes to each.
      yearly = rule("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;BYDAY=MO;COUNT=3", read("2026-01-01"))
      {:ok, mondays} = Tempo.to_interval(yearly)

      expected =
        for year <- 2026..2200,
            Date.leap_year?(Date.new!(year, 1, 1)),
            date = Date.new!(year, 2, 29),
            Date.day_of_week(date) == 1,
            do: Tempo.from_date(date)

      assert Enum.map(IntervalSet.members(mondays), &Interval.from/1) == Enum.take(expected, 3)
    end
  end
end
