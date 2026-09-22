defmodule Tempo.RRule.ExpanderTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.RRule
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  # The Expander is a thin adapter, not a parallel engine. These
  # tests lock in that architecture:
  #
  # * `to_ast/3` produces the same AST shape as
  #   `Tempo.RRule.parse/2`, so either input flows through the
  #   same interpreter.
  # * `expand/3` delegates to `Tempo.to_interval/2` and returns a
  #   flat list of uncoalesced occurrences.
  # * Iteration, termination, and per-step arithmetic all live in
  #   `Tempo.to_interval/2` — never duplicated here.

  describe "to_ast/3 — AST projection" do
    test "bounded COUNT becomes an Interval with recurrence: n" do
      rule = %Rule{freq: :day, interval: 1, count: 5}
      {:ok, ast} = Expander.to_ast(rule, ~o"2022-06-01")

      assert ast.recurrence == 5
      assert ast.duration.time == [day: 1]
      assert ast.from == ~o"2022-06-01"
      assert ast.to == nil
      assert ast.repeat_rule == nil
    end

    test "unbounded becomes an Interval with recurrence: :infinity" do
      rule = %Rule{freq: :week, interval: 2}
      {:ok, ast} = Expander.to_ast(rule, ~o"2022-06-01")

      assert ast.recurrence == :infinity
      assert ast.duration.time == [week: 2]
    end

    test "UNTIL maps to the interval's `:to` endpoint" do
      rule = %Rule{freq: :week, until: ~o"2022-07-01"}
      {:ok, ast} = Expander.to_ast(rule, ~o"2022-06-01")

      assert ast.to == ~o"2022-07-01"
    end

    test "BY-rules become selection tokens on `:repeat_rule`" do
      # FREQ=YEARLY;BYMONTH=11;BYDAY=4TH — 4th Thursday of November.
      rule = %Rule{
        freq: :year,
        interval: 1,
        bymonth: [11],
        byday: [{4, 4}]
      }

      {:ok, ast} = Expander.to_ast(rule, ~o"2022-11-24")

      # An ordinal on a single weekday is the ISO 8601-2 §12.9 position form:
      # resolve the weekday, then take the Nth (`:instance`). `:byday` is kept
      # only for ordinals spread across distinct weekdays.
      assert ast.repeat_rule.time ==
               [selection: [month: 11, day_of_week: 4, instance: 4]]
    end

    test ":duration option is attached via metadata.occurrence_duration" do
      rule = %Rule{freq: :week, count: 3}

      {:ok, ast} =
        Expander.to_ast(rule, ~o"2022-06-01", duration: %Tempo.Duration{time: [hour: 1]})

      assert ast.metadata.occurrence_duration == %Tempo.Duration{time: [hour: 1]}
    end

    test ":base_to option is attached via metadata.occurrence_base_to" do
      rule = %Rule{freq: :week, count: 3}

      {:ok, ast} = Expander.to_ast(rule, ~o"2022-06-01T10", base_to: ~o"2022-06-01T11")

      assert ast.metadata.occurrence_base_to == ~o"2022-06-01T11"
    end

    test ":metadata option flows onto the AST" do
      rule = %Rule{freq: :day, count: 3}
      {:ok, ast} = Expander.to_ast(rule, ~o"2022-06-01", metadata: %{summary: "Daily"})

      assert ast.metadata.summary == "Daily"
    end
  end

  describe "expand/3 — materialisation via Tempo.to_interval/2" do
    test "bounded COUNT yields the expected occurrence count" do
      rule = %Rule{freq: :day, count: 5}
      {:ok, occurrences} = Expander.expand(rule, ~o"2022-06-01")

      assert length(occurrences) == 5
      assert Enum.map(occurrences, & &1.from.time[:day]) == [1, 2, 3, 4, 5]
    end

    test "UNTIL terminates the expansion before the endpoint" do
      rule = %Rule{freq: :week, until: ~o"2022-07-01"}
      {:ok, occurrences} = Expander.expand(rule, ~o"2022-06-01")

      # Jun 1, 8, 15, 22, 29 — all before Jul 1.
      assert length(occurrences) == 5
      assert Enum.map(occurrences, & &1.from.time[:day]) == [1, 8, 15, 22, 29]
    end

    test "unbounded rule with :bound materialises within the bound" do
      rule = %Rule{freq: :day}
      {:ok, occurrences} = Expander.expand(rule, ~o"2022-06-01", bound: ~o"2022-06-01/2022-06-08")

      assert length(occurrences) == 7
    end

    test "unbounded rule with no :bound errors cleanly" do
      rule = %Rule{freq: :day}
      {:error, reason} = Expander.expand(rule, ~o"2022-06-01")

      assert Exception.message(reason) =~ "unbounded"
    end

    test ":base_to preserves each occurrence's event span" do
      # iCal-shaped input: 1-hour event repeated weekly, 3 times.
      rule = %Rule{freq: :week, count: 3}

      {:ok, occurrences} =
        Expander.expand(rule, ~o"2022-06-01T10", base_to: ~o"2022-06-01T11")

      spans =
        Enum.map(occurrences, fn iv ->
          {iv.from.time[:day], iv.from.time[:hour], iv.to.time[:day], iv.to.time[:hour]}
        end)

      # Every occurrence is a 10:00-11:00 window on a day 7 apart.
      assert spans == [{1, 10, 1, 11}, {8, 10, 8, 11}, {15, 10, 15, 11}]
    end

    test "occurrences are uncoalesced even when adjacent" do
      # Five contiguous day-length intervals would normally
      # coalesce to a single 5-day span under the default
      # `Tempo.to_interval/2` semantics; the Expander forces
      # `coalesce: false` so event identity is preserved.
      rule = %Rule{freq: :day, count: 5}
      {:ok, occurrences} = Expander.expand(rule, ~o"2022-06-01")

      assert length(occurrences) == 5
    end
  end

  describe "AST equivalence — Expander output ≡ RRule.parse/2 output" do
    # This is the whole point of the AST-first architecture: an
    # RRULE string parsed by `RRule.parse/2` and a `%Rule{}`
    # struct projected by `Expander.to_ast/3` produce the same
    # `%Tempo.Interval{}`. They flow through the same interpreter.

    test "COUNT-only rule" do
      rule = %Rule{freq: :day, count: 10}
      {:ok, ast_from_expander} = Expander.to_ast(rule, ~o"2022-06-01")
      {:ok, ast_from_parser} = RRule.parse("FREQ=DAILY;COUNT=10", from: ~o"2022-06-01")

      assert ast_from_expander.recurrence == ast_from_parser.recurrence
      assert ast_from_expander.duration == ast_from_parser.duration
      assert ast_from_expander.from == ast_from_parser.from
      assert ast_from_expander.repeat_rule == ast_from_parser.repeat_rule
    end

    test "BYMONTH selection shape" do
      rule = %Rule{freq: :year, bymonth: [6]}
      {:ok, from_expander} = Expander.to_ast(rule, ~o"2022-06-01")
      {:ok, from_parser} = RRule.parse("FREQ=YEARLY;BYMONTH=6", from: ~o"2022-06-01")

      assert from_expander.repeat_rule.time == from_parser.repeat_rule.time
    end

    test "BYDAY with ordinal selection shape" do
      rule = %Rule{freq: :month, byday: [{-1, 5}]}
      {:ok, from_expander} = Expander.to_ast(rule, ~o"2022-06-24")
      {:ok, from_parser} = RRule.parse("FREQ=MONTHLY;BYDAY=-1FR", from: ~o"2022-06-24")

      assert from_expander.repeat_rule.time == from_parser.repeat_rule.time
    end
  end
end
