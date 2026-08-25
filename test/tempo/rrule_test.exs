defmodule Tempo.RRuleTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.IntervalSet
  alias Tempo.RRule

  # The purpose of this test suite is to validate that Tempo's
  # existing AST is a sufficient target for RFC 5545 RRULE
  # strings. If every assertion below passes without adding new
  # struct fields, the AST is validated as a shared target for
  # both ISO 8601-2 and RRULE. See docs/rrule-ast-validation.md
  # for the full findings.

  describe "core recurrence fields" do
    test "FREQ=DAILY is an infinite daily interval" do
      {:ok, i} = RRule.parse("FREQ=DAILY")
      assert i.recurrence == :infinity
      assert i.duration.time == [day: 1]
      assert i.to == nil
      assert i.repeat_rule == nil
    end

    test "COUNT sets recurrence" do
      {:ok, i} = RRule.parse("FREQ=DAILY;COUNT=10")
      assert i.recurrence == 10
      assert i.duration.time == [day: 1]
    end

    test "INTERVAL multiplies the duration" do
      {:ok, i} = RRule.parse("FREQ=DAILY;INTERVAL=3")
      assert i.duration.time == [day: 3]
      assert i.recurrence == :infinity
    end

    test "UNTIL sets the to bound and keeps recurrence infinite" do
      {:ok, i} = RRule.parse("FREQ=WEEKLY;UNTIL=20221231")
      assert i.duration.time == [week: 1]
      assert i.to == ~o"2022-12-31"
      assert i.recurrence == :infinity
    end

    test "RRULE: prefix is stripped" do
      {:ok, i} = RRule.parse("RRULE:FREQ=DAILY;COUNT=5")
      assert i.recurrence == 5
    end
  end

  describe "FREQ → duration unit mapping" do
    for {freq, unit} <- [
          {"SECONDLY", :second},
          {"MINUTELY", :minute},
          {"HOURLY", :hour},
          {"DAILY", :day},
          {"WEEKLY", :week},
          {"MONTHLY", :month},
          {"YEARLY", :year}
        ] do
      test "FREQ=#{freq} produces duration unit #{inspect(unit)}" do
        {:ok, i} = RRule.parse("FREQ=#{unquote(freq)}")
        assert i.duration.time == [{unquote(unit), 1}]
      end
    end
  end

  describe "BY* rules build a repeat_rule with selection tokens" do
    test "BYMONTHDAY becomes a day selection" do
      {:ok, i} = RRule.parse("FREQ=MONTHLY;BYMONTHDAY=15")
      assert i.repeat_rule.time == [selection: [day: 15]]
    end

    test "BYMONTH becomes a month selection" do
      {:ok, i} = RRule.parse("FREQ=YEARLY;BYMONTH=6")
      assert i.repeat_rule.time == [selection: [month: 6]]
    end

    test "multiple BYMONTH values become a list (consecutive runs consolidate)" do
      {:ok, i} = RRule.parse("FREQ=YEARLY;BYMONTH=6,7,8")
      # Consecutive integers consolidate to a range for readability, matching
      # what parsing the ISO 8601 selection back produces, so it round-trips.
      assert i.repeat_rule.time == [selection: [month: [6..8]]]
    end

    test "BYDAY without ordinal becomes day_of_week selection" do
      {:ok, i} = RRule.parse("FREQ=WEEKLY;BYDAY=MO,WE,FR")
      assert i.repeat_rule.time == [selection: [day_of_week: [1, 3, 5]]]
    end

    test "BYDAY with positive ordinal becomes a :byday pair token" do
      # 4th Thursday of November — US Thanksgiving.
      {:ok, i} = RRule.parse("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH")

      # BYDAY-with-ordinal uses the `:byday` token which keeps
      # the (ordinal, weekday) pair intact. `:day_of_week` is
      # reserved for the no-ordinal form.
      assert i.repeat_rule.time ==
               [selection: [month: 11, byday: [{4, 4}]]]
    end

    test "BYDAY with negative ordinal" do
      # Last Friday of every month.
      {:ok, i} = RRule.parse("FREQ=MONTHLY;BYDAY=-1FR")

      assert i.repeat_rule.time ==
               [selection: [byday: [{-1, 5}]]]
    end

    test "BYHOUR, BYMINUTE, BYSECOND for time-of-day filters" do
      {:ok, i} = RRule.parse("FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30")

      assert i.repeat_rule.time ==
               [selection: [hour: 9, minute: [0, 30]]]
    end

    test "BYSETPOS maps to a dedicated :set_position token" do
      {:ok, i} = RRule.parse("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")

      # `:set_position` is distinct from the `:instance` token
      # used by Tempo's native ISO 8601-2 selection grammar. The
      # semantics differ: BYSETPOS operates on the per-period
      # candidate set AFTER all other BY-rules, so it serialises last —
      # after the `:day_of_week` filter it selects from. Consecutive
      # weekdays consolidate to a range (`[1..5]`) for readability.
      assert i.repeat_rule.time ==
               [selection: [day_of_week: [1..5], set_position: -1]]
    end
  end

  describe "DTSTART anchor via :from option" do
    test "supplies the interval's from endpoint" do
      anchor = ~o"2022-01-01"
      {:ok, i} = RRule.parse("FREQ=DAILY;COUNT=10", from: anchor)
      assert i.from == anchor
    end

    test "without :from the interval has nil anchor" do
      {:ok, i} = RRule.parse("FREQ=DAILY;COUNT=10")
      assert i.from == nil
    end
  end

  describe "errors" do
    test "missing FREQ is rejected" do
      assert {:error, :missing_freq} = RRule.parse("BYMONTH=6")
    end

    test "unknown FREQ is rejected" do
      assert {:error, {:unknown_freq, "NONSENSE"}} =
               RRule.parse("FREQ=NONSENSE")
    end

    test "unknown rule part is rejected" do
      assert {:error, {:unknown_rule_part, "BOGUS"}} =
               RRule.parse("FREQ=DAILY;BOGUS=7")
    end

    test "malformed BYDAY entry is rejected" do
      assert {:error, {:invalid_byday, "ZZ"}} =
               RRule.parse("FREQ=WEEKLY;BYDAY=ZZ")
    end

    test "non-integer UNTIL is rejected" do
      assert {:error, {:invalid_until, _, _}} =
               RRule.parse("FREQ=DAILY;UNTIL=notadate")
    end
  end

  describe "AST equivalence with ISO 8601-2 selection tokens" do
    # The whole point of this spike: an RRULE and an ISO 8601-2
    # expression that mean the same thing should land on the same
    # AST.

    test "MONTHLY;BYDAY=-1FR lands on the :byday pair token" do
      {:ok, rrule_ast} = RRule.parse("FREQ=MONTHLY;BYDAY=-1FR")

      assert rrule_ast.repeat_rule.time == [selection: [byday: [{-1, 5}]]]
    end

    test "YEARLY;BYMONTH=6 carries a month-only selection" do
      {:ok, rrule_ast} = RRule.parse("FREQ=YEARLY;BYMONTH=6")
      assert rrule_ast.repeat_rule.time == [selection: [month: 6]]
    end

    test "an ordinal BYDAY round-trips through its native ISO 8601-2 form" do
      # `inspect/1` renders `byday: [{2, 1}]` as `R/…/FL2I1KN`; the parser
      # must fold `2I1K` back into the same `:byday` token — not leave it as
      # raw `instance`/`day_of_week` tokens (which would select *every*
      # Monday, not the *2nd*).
      rrule = RRule.parse!("FREQ=MONTHLY;BYDAY=2MO", from: ~o"2025-01-01")

      assert inspect(rrule) == ~s(~o"R/2025Y1M1D/P1M/FL2I1KN")
      assert Tempo.from_iso8601("R/2025Y1M1D/P1M/FL2I1KN") == {:ok, rrule}
      assert rrule.repeat_rule.time == [selection: [byday: [{2, 1}]]]
    end

    test "multi-weekday and multi-ordinal BYDAY round-trip too" do
      for rule <- ["FREQ=MONTHLY;BYDAY=1MO,3MO", "FREQ=MONTHLY;BYDAY=2MO,WE"] do
        rrule = RRule.parse!(rule, from: ~o"2025-01-01")
        iso = inspect(rrule) |> String.replace(~s(~o"), "") |> String.trim_trailing(~s("))

        assert Tempo.from_iso8601(iso) == {:ok, rrule}
      end
    end

    test "a weekday-plus-time selection serialises the weekday before the time" do
      # `BYDAY` (day-of-week, resolution 18) is coarser than `BYHOUR`/`BYMINUTE`,
      # so the selection must render weekday-first (`FL5KT17H0MN`) to re-parse —
      # the reverse order (`FLT17H0M5KN`) is out of resolution order.
      rrule = RRule.parse!("FREQ=WEEKLY;BYDAY=FR;BYHOUR=17;BYMINUTE=0", from: ~o"2025-01-03")

      assert rrule.repeat_rule.time == [selection: [day_of_week: 5, hour: 17, minute: 0]]
      assert Tempo.from_iso8601(Tempo.to_iso8601(rrule)) == {:ok, rrule}
    end

    test "BYYEARDAY, BYSETPOS, WKST and consecutive runs round-trip via to_iso8601/1" do
      # BYYEARDAY uses the ISO `O` designator; BYSETPOS (`V`) and WKST (`Q`) are
      # Tempo project-specific designators — RFC 5545 features with no ISO form,
      # which previously crashed `to_iso8601/1`. Consecutive values consolidate
      # to ranges; a negative sentinel mixed with a positive (`BYMONTHDAY=1,-1`)
      # keeps its source order rather than sorting. All still round-trip.
      rules = [
        "FREQ=YEARLY;BYYEARDAY=100",
        "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1",
        "FREQ=WEEKLY;BYDAY=MO;WKST=SU",
        "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
        "FREQ=MONTHLY;BYMONTHDAY=1,-1"
      ]

      for rule <- rules do
        rrule = RRule.parse!(rule, from: ~o"2025-01-01")
        assert Tempo.from_iso8601(Tempo.to_iso8601(rrule)) == {:ok, rrule}
      end
    end
  end

  describe "occurrence span matches the selection's resolution" do
    # A selection picks points at its own resolution, so "the 15th of
    # every month" is the *day* the 15th — not the month-long cadence
    # it sits in. The span is derived in materialisation, so native
    # ISO 8601-2, RRULE, and cron agree; a plain repeating interval
    # (no selection) still spans its cadence.

    test "BYMONTHDAY yields day-resolution occurrences, not month spans" do
      first = first_occurrence(RRule.parse!("FREQ=MONTHLY;BYMONTHDAY=15", from: ~o"2025-01-15"))

      assert first.from == ~o"2025-01-15"
      assert first.to == ~o"2025-01-16"
    end

    test "native selection sigil and RRULE agree on occurrence spans" do
      native = ~o"R/2025-01-15/P1M/FL15DN"
      rrule = RRule.parse!("FREQ=MONTHLY;BYMONTHDAY=15", from: ~o"2025-01-15")

      assert first_occurrence(native) == first_occurrence(rrule)
    end

    test "a plain repeating interval keeps its cadence as the occurrence span" do
      first = first_occurrence(~o"R/2025-01-15/P1M")

      assert first.from == ~o"2025-01-15"
      assert first.to == ~o"2025-02-15"
    end
  end

  describe "selection index ranges round-trip" do
    # `{2..8}` in the ISO 8601-2 sigil parses to a Range element in the
    # selection; the RRULE adapter emits an explicit integer list. Both
    # must materialise identically. The regression case is US Election
    # Day — the Tuesday falling on the 2nd–8th of November.
    test "a day-range selection matches its explicit-list form and dates" do
      range_form = ~o"R/2024Y11M1D/P1Y/FL11M{2..8}D2KN"

      rrule_form =
        RRule.parse!("FREQ=YEARLY;BYMONTH=11;BYDAY=TU;BYMONTHDAY=2,3,4,5,6,7,8",
          from: ~o"2024-11-01"
        )

      dates = range_form |> occurrences() |> Enum.map(& &1.from) |> Enum.take(3)

      assert occurrences(range_form) == occurrences(rrule_form)
      assert dates == [~o"2024-11-05", ~o"2025-11-04", ~o"2026-11-03"]
    end
  end

  describe "COUNT=1 with a BY-rule materialises the first matching occurrence" do
    # Regression: a count-1 recurrence carrying a BY-filter used to
    # return the raw DTSTART period, bypassing the selection — so
    # COUNT=1 disagreed with COUNT >= 2. DTSTART 2024-07-01 is a Monday.
    test "DAILY;BYDAY=SU;COUNT=1 selects the first Sunday, not DTSTART" do
      {:ok, i} = RRule.parse("FREQ=DAILY;BYDAY=SU;COUNT=1", from: ~o"2024-07-01")
      {:ok, %Tempo.Interval{from: from}} = Tempo.to_interval(i)
      assert {Tempo.year(from), Tempo.month(from), Tempo.day(from)} == {2024, 7, 7}
      assert Tempo.day_of_week(from) == 7
    end

    test "COUNT=1 agrees with the first occurrence of COUNT=3" do
      {:ok, one} = RRule.parse("FREQ=DAILY;BYDAY=SU;COUNT=1", from: ~o"2024-07-01")
      {:ok, three} = RRule.parse("FREQ=DAILY;BYDAY=SU;COUNT=3", from: ~o"2024-07-01")
      {:ok, %Tempo.Interval{from: one_from}} = Tempo.to_interval(one)
      {:ok, set} = Tempo.to_interval(three)
      [first | _] = IntervalSet.to_list(set)
      assert one_from == first.from
    end

    test "BYSETPOS;COUNT=1 selects the last weekday of the first month" do
      {:ok, i} =
        RRule.parse("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=1", from: ~o"2024-07-01")

      {:ok, %Tempo.Interval{from: from}} = Tempo.to_interval(i)
      assert {Tempo.year(from), Tempo.month(from), Tempo.day(from)} == {2024, 7, 31}
    end

    test "a plain COUNT=1 (no BY-rule) still returns the DTSTART period" do
      {:ok, i} = RRule.parse("FREQ=DAILY;COUNT=1", from: ~o"2024-07-01")
      {:ok, %Tempo.Interval{from: from}} = Tempo.to_interval(i)
      assert {Tempo.year(from), Tempo.month(from), Tempo.day(from)} == {2024, 7, 1}
    end
  end

  defp first_occurrence(value) do
    {:ok, set} = Tempo.to_interval(value, bound: ~o"2025")
    set |> IntervalSet.to_list() |> hd()
  end

  defp occurrences(value) do
    {:ok, set} = Tempo.to_interval(value, bound: ~o"2024/2028")
    IntervalSet.to_list(set)
  end
end
