defmodule Tempo.CronTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  doctest Tempo.Cron

  alias Tempo.Cron
  alias Tempo.IntervalSet
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  describe "pure-step shortcut (FREQ=unit, INTERVAL=n)" do
    test "`* * * * *` → every minute" do
      assert {:ok, %Rule{freq: :minute, interval: 1}} = Cron.to_rule("* * * * *")
    end

    test "`*/15 * * * *` → every 15 minutes" do
      assert {:ok, %Rule{freq: :minute, interval: 15, byminute: nil}} =
               Cron.to_rule("*/15 * * * *")
    end

    test "`* */2 * * *` → every 2 hours" do
      assert {:ok, %Rule{freq: :hour, interval: 2}} = Cron.to_rule("* */2 * * *")
    end

    test "6-field `* * * * * *` → every second" do
      assert {:ok, %Rule{freq: :second, interval: 1}} = Cron.to_rule("* * * * * *")
    end

    test "6-field `*/10 * * * * *` → every 10 seconds" do
      assert {:ok, %Rule{freq: :second, interval: 10}} = Cron.to_rule("*/10 * * * * *")
    end
  end

  describe "time-of-day filters (FREQ cascades)" do
    test "`0 9 * * *` → 9am daily" do
      assert {:ok, rule} = Cron.to_rule("0 9 * * *")
      assert rule.freq == :day
      assert rule.byhour == [9]
      assert rule.byminute == [0]
    end

    test "`30 9 * * *` → 9:30am daily" do
      assert {:ok, rule} = Cron.to_rule("30 9 * * *")
      assert rule.freq == :day
      assert rule.byhour == [9]
      assert rule.byminute == [30]
    end

    test "`0 9,12,17 * * *` → 9am, noon, 5pm" do
      assert {:ok, rule} = Cron.to_rule("0 9,12,17 * * *")
      assert rule.byhour == [9, 12, 17]
    end

    test "`0 9-17 * * *` → every hour 9..17" do
      assert {:ok, rule} = Cron.to_rule("0 9-17 * * *")
      assert rule.byhour == [9, 10, 11, 12, 13, 14, 15, 16, 17]
    end

    test "`0 9-17/2 * * *` → every 2 hours 9..17" do
      assert {:ok, rule} = Cron.to_rule("0 9-17/2 * * *")
      assert rule.byhour == [9, 11, 13, 15, 17]
    end
  end

  describe "weekly schedules (FREQ=WEEKLY)" do
    test "`0 9 * * 1-5` → 9am weekdays (RFC 5545 Mon=1..Fri=5)" do
      assert {:ok, rule} = Cron.to_rule("0 9 * * 1-5")
      assert rule.freq == :week
      assert rule.byday == [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}]
      assert rule.byhour == [9]
      assert rule.byminute == [0]
    end

    test "`0 9 * * MON-FRI` same as numeric 1-5" do
      {:ok, named} = Cron.to_rule("0 9 * * MON-FRI")
      {:ok, numeric} = Cron.to_rule("0 9 * * 1-5")
      assert named.byday == numeric.byday
    end

    test "day-of-week 0 and 7 both map to RFC 5545 Sunday (7)" do
      {:ok, a} = Cron.to_rule("0 0 * * 0")
      {:ok, b} = Cron.to_rule("0 0 * * 7")
      assert a.byday == [{nil, 7}]
      assert b.byday == [{nil, 7}]
    end

    test "day-of-week names are case-insensitive" do
      {:ok, rule} = Cron.to_rule("0 0 * * mon,wed,fri")
      assert rule.byday == [{nil, 1}, {nil, 3}, {nil, 5}]
    end
  end

  describe "monthly and yearly schedules" do
    test "`0 0 1 * *` → midnight on the 1st" do
      assert {:ok, rule} = Cron.to_rule("0 0 1 * *")
      assert rule.freq == :month
      assert rule.bymonthday == [1]
      assert rule.byhour == [0]
      assert rule.byminute == [0]
    end

    test "`0 0 1 1 *` → midnight January 1st" do
      assert {:ok, rule} = Cron.to_rule("0 0 1 1 *")
      assert rule.freq == :year
      assert rule.bymonth == [1]
      assert rule.bymonthday == [1]
    end

    test "`0 0 * JAN-JUN *` → first half of year" do
      assert {:ok, rule} = Cron.to_rule("0 0 * JAN-JUN *")
      assert rule.freq == :year
      assert rule.bymonth == [1, 2, 3, 4, 5, 6]
    end
  end

  describe "aliases" do
    test "@yearly" do
      assert {:ok, rule} = Cron.to_rule("@yearly")
      assert rule.freq == :year
      assert rule.bymonth == [1]
      assert rule.bymonthday == [1]
      assert rule.byhour == [0]
      assert rule.byminute == [0]
    end

    test "@annually — synonym for @yearly" do
      {:ok, a} = Cron.to_rule("@yearly")
      {:ok, b} = Cron.to_rule("@annually")
      assert a == b
    end

    test "@monthly" do
      assert {:ok, rule} = Cron.to_rule("@monthly")
      assert rule.freq == :month
      assert rule.bymonthday == [1]
    end

    test "@weekly" do
      assert {:ok, rule} = Cron.to_rule("@weekly")
      assert rule.freq == :week
      assert rule.byday == [{nil, 7}]
    end

    test "@daily" do
      assert {:ok, rule} = Cron.to_rule("@daily")
      assert rule.freq == :day
      assert rule.byhour == [0]
      assert rule.byminute == [0]
    end

    test "@midnight — synonym for @daily" do
      {:ok, a} = Cron.to_rule("@daily")
      {:ok, b} = Cron.to_rule("@midnight")
      assert a == b
    end

    test "@hourly" do
      assert {:ok, rule} = Cron.to_rule("@hourly")
      assert rule.freq == :hour
      assert rule.byminute == [0]
    end

    test "aliases are case-insensitive" do
      {:ok, a} = Cron.to_rule("@Yearly")
      {:ok, b} = Cron.to_rule("@YEARLY")
      {:ok, c} = Cron.to_rule("@yearly")
      assert a == b
      assert b == c
    end
  end

  describe "Vixie-cron extensions" do
    test "`L` as day-of-month → last day of month" do
      assert {:ok, rule} = Cron.to_rule("0 0 L * *")
      assert rule.bymonthday == [-1]
    end

    test "`5L` as day-of-week → last Friday of month" do
      assert {:ok, rule} = Cron.to_rule("0 0 * * 5L")
      assert rule.byday == [{-1, 5}]
    end

    test "`5#2` → second Friday of month" do
      assert {:ok, rule} = Cron.to_rule("0 0 * * 5#2")
      assert rule.byday == [{2, 5}]
    end

    test "`FRI#2` — named second Friday" do
      {:ok, a} = Cron.to_rule("0 0 * * 5#2")
      {:ok, b} = Cron.to_rule("0 0 * * FRI#2")
      assert a.byday == b.byday
    end
  end

  describe "day-of-week step (cron-numbered expansion)" do
    # A day-of-week step iterates in cron numbering (Sunday = 0) then
    # maps to RFC (Sunday = 7), so a Sunday start participates.
    defp dow_days(expression) do
      {:ok, rule} = Cron.to_rule(expression)
      Enum.map(rule.byday, fn {nil, day} -> day end)
    end

    test "`5/2` (FRI/2) steps to the end of the week → Fri, Sun" do
      assert dow_days("0 0 * * 5/2") == [5, 7]
    end

    test "`MON-FRI/2` steps within the named range → Mon, Wed, Fri" do
      assert dow_days("0 0 * * MON-FRI/2") == [1, 3, 5]
    end

    test "`0/3` starts at Sunday and steps forward → Wed, Sat, Sun" do
      # Sunday-as-0 is the week start: cron 0, 3, 6 → RFC 3 (Wed),
      # 6 (Sat), 7 (Sun). Without cron-space expansion this collapsed
      # to just Sunday.
      assert dow_days("0 0 * * 0/3") == [3, 6, 7]
    end

    test "`*/2` covers every second cron day → Tue, Thu, Sat, Sun" do
      assert dow_days("0 0 * * */2") == [2, 4, 6, 7]
    end
  end

  describe "7-field cron with year" do
    test "single year becomes UNTIL" do
      assert {:ok, rule} = Cron.to_rule("0 0 0 1 1 * 2026")
      assert rule.freq == :year
      assert rule.until.time == [year: 2027]
    end

    test "multi-year list becomes a :byyear filter bounded by UNTIL" do
      assert {:ok, rule} = Cron.to_rule("0 0 0 1 1 * 2025,2027,2029")
      assert rule.byyear == [2025, 2027, 2029]
      assert rule.until.time == [year: 2030]
    end

    test "a year range expands to a contiguous :byyear list" do
      assert {:ok, rule} = Cron.to_rule("0 0 0 1 1 * 2025-2028")
      assert rule.byyear == [2025, 2026, 2027, 2028]
      assert rule.until.time == [year: 2029]
    end

    test "expansion keeps only the listed years, skipping the gaps" do
      {:ok, rule} = Cron.to_rule("0 0 0 1 1 * 2025,2027,2029")
      {:ok, occurrences} = Expander.expand(rule, ~o"2025-01-01T00:00:00")
      assert Enum.map(occurrences, & &1.from.time[:year]) == [2025, 2027, 2029]
    end
  end

  describe "nearest-weekday (W) day-of-month" do
    # Resolve the day-of-month each monthly occurrence of 2026 lands on.
    defp w_days_2026(expression) do
      {:ok, rule} = Cron.to_rule(expression)

      {:ok, occurrences} =
        Expander.expand(rule, ~o"2026-01-01T09:00:00", within: ~o"2026Y")

      Enum.map(occurrences, fn occurrence ->
        {occurrence.from.time[:month], occurrence.from.time[:day]}
      end)
    end

    test "`15W` parses to a :bymonthday_nearest filter at MONTHLY freq" do
      assert {:ok, rule} = Cron.to_rule("0 0 9 15W * *")
      assert rule.freq == :month
      assert rule.bymonthday_nearest == [15]
    end

    test "`LW` parses to a last-weekday filter" do
      assert {:ok, rule} = Cron.to_rule("0 0 9 LW * *")
      assert rule.bymonthday_nearest == [:last]
    end

    test "`15W` snaps a Saturday back to Friday and a Sunday forward to Monday" do
      days = w_days_2026("0 0 9 15W * *")
      # Feb 15 2026 is a Sunday → Mon 16; Aug 15 2026 is a Saturday → Fri 14.
      assert {2, 16} in days
      assert {8, 14} in days
      # A weekday stays put: Jan 15 2026 is a Thursday.
      assert {1, 15} in days
    end

    test "`1W` clamps forward without crossing into the previous month" do
      days = w_days_2026("0 0 9 1W * *")
      # Aug 1 2026 is a Saturday → Mon 3 (never Jul 31).
      assert {8, 3} in days
    end

    test "`31W` clamps to the month length, then to the nearest weekday" do
      days = w_days_2026("0 0 9 31W * *")
      # Feb has no 31st → clamp to 28 (Sat 2026) → Fri 27.
      assert {2, 27} in days
      # May 31 2026 is a Sunday → Fri 29 (never Jun 1).
      assert {5, 29} in days
    end

    test "`LW` lands on the last weekday of each month" do
      days = w_days_2026("0 0 9 LW * *")
      # Jan 31 2026 is a Saturday → Fri 30; Feb ends Sat 28 → Fri 27.
      assert {1, 30} in days
      assert {2, 27} in days
    end

    test "a nearest-weekday rule has no ISO 8601 form — clear error, no crash" do
      {:ok, rule} = Cron.parse("0 0 9 15W * *")

      # to_iso8601 returns a descriptive error, and to_iso8601! raises it.
      assert {:error, %Tempo.Iso8601EncodeError{construct: :nearest_weekday} = error} =
               Tempo.to_iso8601(rule)

      assert Exception.message(error) =~ "nearest-weekday"

      assert_raise Tempo.Iso8601EncodeError, ~r/nearest-weekday/, fn ->
        Tempo.to_iso8601!(rule)
      end

      # inspect never crashes — it falls back to a labelled struct view.
      assert inspect(rule) == "#Tempo.Interval<not ISO 8601 expressible>"
    end
  end

  describe "POSIX day-of-month OR day-of-week" do
    # The {month, day} of each 2026 occurrence.
    defp or_dates_2026(expression) do
      {:ok, rule} = Cron.to_rule(expression)

      {:ok, occurrences} =
        Expander.expand(rule, ~o"2026-01-01T00:00:00", within: ~o"2026Y")

      occurrences
      |> Enum.map(fn occurrence ->
        {occurrence.from.time[:year], occurrence.from.time[:month], occurrence.from.time[:day]}
      end)
      |> Enum.filter(fn {year, _, _} -> year == 2026 end)
      |> Enum.map(fn {_, month, day} -> {month, day} end)
    end

    test "`13 * 5` parses to a daily cadence with a :bymonthday_or_byday union" do
      assert {:ok, rule} = Cron.to_rule("0 0 13 * 5")
      assert rule.freq == :day
      assert rule.bymonthday_or_byday == {[13], [{nil, 5}]}
      # The AND-composing fields are left clear so the union is not also filtered.
      assert rule.bymonthday == nil
      assert rule.byday == nil
    end

    test "`13 * 5` matches every 13th OR every Friday (the union, not the intersection)" do
      dates = or_dates_2026("0 0 13 * 5")

      fridays =
        for month <- 1..12,
            day <- 1..31,
            match?({:ok, _}, Date.new(2026, month, day)),
            Date.day_of_week(Date.new!(2026, month, day)) == 5,
            do: {month, day}

      thirteenths = for month <- 1..12, do: {month, 13}
      expected = Enum.sort(Enum.uniq(fridays ++ thirteenths))

      assert Enum.sort(dates) == expected
      # Sanity: 52 Fridays + 12 thirteenths − 3 Friday-the-13ths in 2026.
      assert length(dates) == 61
    end

    test "month still AND-composes with the day union" do
      dates = or_dates_2026("0 0 13 6 5")
      assert Enum.all?(dates, fn {month, _day} -> month == 6 end)
      # June 2026: Fridays (5, 12, 19, 26) ∪ the 13th.
      assert Enum.sort(dates) == [{6, 5}, {6, 12}, {6, 13}, {6, 19}, {6, 26}]
    end

    test "an ordinal day-of-week (`5#2`) opts out — keeps AND-composition" do
      assert {:ok, rule} = Cron.to_rule("0 0 13 * 5#2")
      assert rule.bymonthday_or_byday == nil
      assert rule.bymonthday == [13]
      assert rule.byday == [{2, 5}]
    end

    test "a `W` day-of-month opts out — keeps AND-composition" do
      assert {:ok, rule} = Cron.to_rule("0 0 15W * 5")
      assert rule.bymonthday_or_byday == nil
      assert rule.bymonthday_nearest == [15]
      assert rule.byday == [{nil, 5}]
    end

    test "a restricted day-of-month alone (dow = `*`) does not trigger the union" do
      assert {:ok, rule} = Cron.to_rule("0 0 13 * *")
      assert rule.bymonthday_or_byday == nil
      assert rule.bymonthday == [13]
    end
  end

  describe "error reporting" do
    test "not enough fields" do
      assert {:error, %Tempo.CronError{} = e} = Cron.to_rule("wibble")
      assert Exception.message(e) =~ "5, 6, or 7 fields"
    end

    test "value out of range" do
      assert {:error, %Tempo.CronError{field: :hour} = e} = Cron.to_rule("0 25 * * *")
      assert Exception.message(e) =~ "outside the valid range"
    end

    test "W (nearest-weekday) is rejected in a list or range" do
      assert {:error, %Tempo.CronError{field: :day_of_month, reason: :unsupported_w}} =
               Cron.to_rule("0 0 0 1-15W * *")

      assert {:error, %Tempo.CronError{field: :day_of_month, reason: :unsupported_w}} =
               Cron.to_rule("0 0 0 15W,20W * *")
    end

    test "invalid day-of-week name" do
      assert {:error, %Tempo.CronError{field: :day_of_week} = e} =
               Cron.to_rule("0 0 * * WIBBLE")

      assert Exception.message(e) =~ "Invalid day-of-week"
    end
  end

  describe "parse!/2" do
    test "raises on invalid input" do
      assert_raise Tempo.CronError, fn -> Cron.parse!("wibble") end
    end

    test "returns a recurring interval on success" do
      assert %Tempo.Interval{recurrence: :infinity} = Cron.parse!("@daily")
    end
  end

  describe "materialisation via Tempo.to_interval/2" do
    # Smoke-test that a parsed cron rule can actually be expanded.
    test "every 15 minutes — materialises within an hour-resolution bound" do
      {:ok, cron} = Cron.parse("*/15 * * * *", from: ~o"2026-06-15T10:00:00")

      # Bound `~o"2026-06-15T10"` is the implicit one-hour span
      # `[10:00, 11:00)`; at 15-minute intervals that's 4 occurrences.
      {:ok, set} = Tempo.to_interval(cron, within: ~o"2026-06-15T10", coalesce: false)

      # 10:00, 10:15, 10:30, 10:45.
      assert IntervalSet.count(set) == 4
    end
  end

  describe "round-trips through its ISO 8601 form" do
    # A parsed cron is a recurring `%Tempo.Interval{}`; re-parsing the string
    # `Tempo.to_iso8601!/1` renders must return the identical value. Two shapes
    # broke this: an unanchored schedule (`from: nil`) inspects as `R/../P1W/…`
    # (the `..` open-start needed a parser branch), and a weekday+time selection
    # must serialise the weekday before the time (`FL5KT17H0MN`, not the
    # out-of-order `FLT17H0M5KN`) to re-parse.

    test "every Friday at 17:00 (unanchored, weekday + time)" do
      cron = Cron.parse!("0 17 * * 5")

      assert Tempo.to_iso8601!(cron) == "R/../P1W/FL5KT17H0MN"
      assert Tempo.from_iso8601(Tempo.to_iso8601!(cron)) == {:ok, cron}
    end

    test "a range of cron shapes each round-trip" do
      for expression <- ["0 9 * * 1", "30 8 15 * *", "0 0 1 1 *", "*/15 * * * *"] do
        cron = Cron.parse!(expression)
        assert Tempo.from_iso8601(Tempo.to_iso8601!(cron)) == {:ok, cron}
      end
    end
  end
end
