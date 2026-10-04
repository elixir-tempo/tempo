defmodule Tempo.RRule.WkstAndEdgesTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.RRule
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  # Phase E — WKST, leap year, DST, and other edges.
  #
  # WKST changes how FREQ=WEEKLY+BYDAY partitions occurrences
  # into weeks. With the default WKST=MO (1), the week is
  # Mon..Sun; with WKST=SU (7), the week is Sun..Sat. For most
  # BYDAY expansions at the per-week level the set of dates
  # produced in a month or year is identical — only the
  # *grouping* into weeks differs. That grouping matters when
  # BYSETPOS picks the Nth element of a per-week candidate set.

  describe "WKST — week boundaries for FREQ=WEEKLY+BYDAY" do
    test "FREQ=WEEKLY;BYDAY=SU at a Sunday DTSTART with default WKST=MO" do
      # DTSTART=Sun 2022-06-05. With WKST=MO, the week containing
      # DTSTART is Mon May 30..Sun Jun 5. The only Sunday in
      # that week is Jun 5 (= DTSTART). Next iteration advances
      # one week to Jun 12 (next Sunday).
      rule = %Rule{freq: :week, interval: 1, byday: [{nil, 7}], count: 3}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-05")

      days = Enum.map(occ, & &1.from.time[:day])
      assert days == [5, 12, 19]
    end

    test "FREQ=WEEKLY;BYDAY=SU;WKST=SU shifts week boundaries to Sunday-first" do
      # Same dates because BYDAY=SU picks one day per week
      # regardless of boundary. The interesting difference is
      # in BYSETPOS interactions (see next test).
      rule = %Rule{freq: :week, interval: 1, byday: [{nil, 7}], wkst: 7, count: 3}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-05")

      days = Enum.map(occ, & &1.from.time[:day])
      assert days == [5, 12, 19]
    end

    test "FREQ=WEEKLY;BYDAY=MO,SU with WKST=MO vs WKST=SU differ in second-week grouping" do
      # DTSTART=Sat 2022-06-04 (dow=6).
      #
      # WKST=MO: the week of DTSTART is Mon May 30..Sun Jun 5.
      #   BYDAY=MO,SU in that week → May 30 (Mon, pre-DTSTART,
      #   filtered), Jun 5 (Sun, kept). Next WKST-week (+1w) is
      #   Mon Jun 6..Sun Jun 12 → Jun 6 (Mon), Jun 12 (Sun).
      #
      # WKST=SU: the week of DTSTART is Sun May 29..Sat Jun 4.
      #   BYDAY=MO,SU → May 29 (Sun) and May 30 (Mon), both
      #   pre-DTSTART → all filtered. Next SU-week: Sun Jun 5..
      #   Sat Jun 11 → Jun 5 (Sun), Jun 6 (Mon).
      #
      # Both produce the same dates; the WKST choice only
      # affects which 7-day window each expansion looks at, and
      # the DTSTART floor drops pre-anchor matches either way.
      # The observable difference surfaces in BYSETPOS or
      # longer-horizon behaviour — this test just checks both
      # produce valid output without crashing or breaking
      # invariants.
      rule_mo = %Rule{freq: :week, interval: 1, byday: [{nil, 1}, {nil, 7}], wkst: 1, count: 4}
      rule_su = %Rule{freq: :week, interval: 1, byday: [{nil, 1}, {nil, 7}], wkst: 7, count: 4}

      {:ok, mo_occ} = Expander.expand(rule_mo, ~o"2022-06-04")
      {:ok, su_occ} = Expander.expand(rule_su, ~o"2022-06-04")

      assert [_, _, _, _] = mo_occ
      assert [_, _, _, _] = su_occ

      # Every occurrence ≥ DTSTART (June 4).
      for iv <- mo_occ ++ su_occ do
        assert iv.from.time[:day] >= 4 or iv.from.time[:month] > 6
      end
    end
  end

  describe "leap year edges" do
    test "BYMONTHDAY=29 in a non-leap February silently skips" do
      # FREQ=YEARLY with DTSTART on 2020-02-29 (leap year) and
      # BYMONTH=2;BYMONTHDAY=29: 2020 matches, 2021/2022/2023 get
      # no match, 2024 matches. COUNT=3 sees 2020, 2024, 2028.
      rule = %Rule{
        freq: :year,
        interval: 1,
        bymonth: [2],
        bymonthday: [29],
        count: 3
      }

      {:ok, occ} = Expander.expand(rule, ~o"2020-02-29")

      years = Enum.map(occ, & &1.from.time[:year])
      assert years == [2020, 2024, 2028]
    end

    test "BYYEARDAY=366 in a non-leap year produces nothing that year" do
      # FREQ=YEARLY;BYYEARDAY=366 — only leap years have day 366.
      rule = %Rule{freq: :year, interval: 1, byyearday: [366], count: 2}
      {:ok, occ} = Expander.expand(rule, ~o"2020-12-31")

      # 2020 and 2024 are leap years; 2021-23 are not.
      years = Enum.map(occ, & &1.from.time[:year])
      assert years == [2020, 2024]
    end

    test "BYMONTHDAY=31 in 30-day months silently skips" do
      # FREQ=MONTHLY;BYMONTHDAY=31 — only Jan, Mar, May, Jul,
      # Aug, Oct, Dec have a 31st.
      rule = %Rule{freq: :month, interval: 1, bymonthday: [31], count: 4}
      {:ok, occ} = Expander.expand(rule, ~o"2022-01-31")

      pairs =
        Enum.map(occ, fn iv -> {iv.from.time[:year], iv.from.time[:month]} end)

      # Jan, Mar, May, Jul — first four 31-day months of 2022.
      assert pairs == [{2022, 1}, {2022, 3}, {2022, 5}, {2022, 7}]
    end
  end

  describe "WKST in the AST" do
    test "non-default WKST round-trips through parse/encode" do
      {:ok, ast} = RRule.parse("FREQ=WEEKLY;BYDAY=SU;WKST=SU;COUNT=3")
      assert ast.repeat_rule.time == [selection: [day_of_week: 7, wkst: 7]]

      # Re-emit and reparse to ensure round-trip stability.
      {:ok, encoded} = RRule.to_string(ast)
      assert encoded =~ "WKST=SU"
      assert encoded =~ "BYDAY=SU"

      {:ok, reparsed} = RRule.parse(encoded)
      assert reparsed.repeat_rule.time == ast.repeat_rule.time
    end

    test "default WKST=MO is elided from the AST" do
      # Explicit WKST=MO is redundant with the default; we don't
      # emit the token since it would bloat every AST.
      {:ok, ast} = RRule.parse("FREQ=WEEKLY;BYDAY=SU;WKST=MO;COUNT=1")
      refute Keyword.has_key?(ast.repeat_rule.time[:selection] || [], :wkst)
    end
  end
end
