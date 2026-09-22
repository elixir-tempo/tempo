defmodule Tempo.IntervalRegressionTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils
  alias Tempo.RRule

  # Regressions for two bugs surfaced by the RRule AST-validation
  # spike (see docs/rrule-ast-validation.md).

  describe "Tempo.Interval.new/1 shape coverage" do
    test "date/date interval with a repeat rule (formerly crashed)" do
      # Before the fix the 3-arg clause pattern-matched the literal
      # atom `:to` for the second element, but the tokenizer emits
      # `:date`-tagged tuples. This combination crashed with
      # FunctionClauseError.
      assert {:ok, %Tempo.Interval{} = interval} =
               Tempo.from_iso8601("R/2022-01-01/2022-12-31/F2022-11-24")

      assert interval.recurrence == :infinity
      assert interval.from == ~o"2022-01-01"
      assert interval.to == ~o"2022-12-31"
      assert interval.repeat_rule == ~o"2022-11-24"
    end

    test "datetime/datetime interval with a repeat rule" do
      # Same fix covers datetime endpoints.
      assert {:ok, %Tempo.Interval{}} =
               Tempo.from_iso8601(
                 "R5/2022-01-01T10:00:00/2022-01-01T18:00:00/F2022-01-01T12:00:00"
               )
    end

    test "duration/date interval no longer misclassifies the duration as a date" do
      # Before the fix the wildcard `[{_from, time}, {_to, to}]`
      # clause swallowed the `{:duration, ...}` token and built an
      # interval with a date-shaped "from" of `[day: 1]`, producing
      # `~o"1D/2022Y1M1D"`. After the fix the duration is carried
      # on the `:duration` field.
      assert {:ok, interval} = Tempo.from_iso8601("P1D/2022-01-01")
      assert interval.from == :undefined
      assert interval.to == ~o"2022-01-01"
      assert interval.duration == %Tempo.Duration{time: [day: 1]}
    end

    test "duration/date interval with a repeat rule" do
      assert {:ok, %Tempo.Interval{} = interval} =
               Tempo.from_iso8601("P1D/2022-06-30/F2022-06-15")

      assert interval.duration == %Tempo.Duration{time: [day: 1]}
      assert interval.to == ~o"2022-06-30"
      assert interval.repeat_rule == ~o"2022-06-15"
    end
  end

  describe "Tempo.Inspect for intervals with nil endpoints" do
    test "Interval with nil from and count-bounded recurrence renders as R<n>/../P<dur>" do
      # RRULE parsers (and any future caller building an interval
      # directly without a DTSTART) produce a struct with from: nil.
      # Before the fix this crashed Inspect with BadMapError on
      # `nil.time`.
      interval = %Tempo.Interval{
        recurrence: 10,
        duration: %Tempo.Duration{time: [day: 1]},
        from: nil,
        to: nil
      }

      assert inspect(interval) == ~S|~o"R10/../P1D"|
    end

    test "Interval with nil from and a bounded to renders with both anchors" do
      interval = %Tempo.Interval{
        recurrence: :infinity,
        duration: %Tempo.Duration{time: [week: 1]},
        from: nil,
        to: ~o"2022-12-31"
      }

      assert inspect(interval) == ~S|~o"R/../2022Y12M31D/P1W"|
    end

    test "Interval with nil from and a repeat rule" do
      interval = %Tempo.Interval{
        recurrence: :infinity,
        duration: %Tempo.Duration{time: [month: 1]},
        from: nil,
        to: nil,
        repeat_rule: %Tempo{time: [selection: [day_of_week: 5, instance: -1]]}
      }

      # Shape is `R/../P1M/FL5K-1IN` — the selection inspects weekday-then-
      # position (`L5K-1IN`) per the ISO 8601-2 §12.9 order.
      rendered = inspect(interval)
      assert rendered =~ "R/../P1M/F"
      assert rendered =~ "L"
      assert rendered =~ "K"
    end

    test "recurring interval with an ordinal BYDAY repeat rule inspects without crashing" do
      # `FREQ=MONTHLY;BYDAY=2MO` ("the 2nd Monday") lowers to the ISO 8601-2
      # §12.9 position form — resolve the weekday (`K`), then take the Nth
      # (`I`) — and renders weekday-then-position rather than raising.
      second_monday = RRule.parse!("FREQ=MONTHLY;BYDAY=2MO", from: ~o"2025-01-01")
      assert inspect(second_monday) == ~S|~o"R/2025Y1M1D/P1M/FL1K2IN"|

      # Negative and multi-entry ordinals render the same way.
      last_friday = RRule.parse!("FREQ=MONTHLY;BYDAY=-1FR", from: ~o"2025-01-01")
      assert inspect(last_friday) == ~S|~o"R/2025Y1M1D/P1M/FL5K-1IN"|

      first_and_third = RRule.parse!("FREQ=MONTHLY;BYDAY=1MO,3MO", from: ~o"2025-01-01")
      assert inspect(first_and_third) == ~S|~o"R/2025Y1M1D/P1M/FL1K{1,3}IN"|
    end

    test "open-ended interval (existing behaviour) still renders as ../.." do
      assert {:ok, interval} = Tempo.from_iso8601("../..")
      assert inspect(interval) == ~S|~o"../.."|
    end

    test "duration/date interval inspects without crashing" do
      # Requires both the Interval.new fix (to build the right
      # struct) and a corresponding inspect clause for
      # `from: :undefined, to: %Tempo{}, duration: %Duration{}`.
      assert {:ok, interval} = Tempo.from_iso8601("P1D/2022-01-01")
      assert inspect(interval) == ~S|~o"P1D/2022Y1M1D"|
    end
  end

  describe "margin of error (±) is crisp-inert, not a crash" do
    # Before the fix, a validly-parsed `±` value crashed the crisp
    # machinery with an ArithmeticError (the boundary/comparison
    # primitives did arithmetic on the `{value, [margin_of_error: n]}`
    # tuple). The margin is dropped for crisp materialisation and
    # comparison, and preserved on the value. See
    # plans/uncertainty-roadmap.md.
    test "to_interval materialises a ±-bearing value to its crisp span" do
      assert {:ok, iv} = Tempo.to_interval(~o"2018±2Y")
      assert {:ok, crisp} = Tempo.to_interval(~o"2018Y")
      assert iv == crisp
    end

    test "relation ignores ± on bare values and on interval endpoints" do
      assert Tempo.relation(~o"2018±2Y", ~o"2019Y") == :meets

      assert Tempo.relation(~o"2018±2Y", ~o"2019Y") ==
               Tempo.relation(~o"2018Y", ~o"2019Y")

      assert Tempo.relation(~o"2018±2Y/2020±2Y", ~o"2019Y") ==
               Tempo.relation(~o"2018Y/2020Y", ~o"2019Y")
    end

    test "the ± annotation is preserved on the value" do
      assert ~o"2018±2Y".time == [year: {2018, [margin_of_error: 2]}]
    end
  end

  describe "significant digits (S) materialise as the value block, not a crash" do
    # `1950S3` ("3 significant digits") denotes the block of values
    # sharing those leading digits — the decade 1950..1959, exactly the
    # mask `195X`. Before the fix it crashed the crisp machinery with an
    # ArithmeticError; it now rewrites to the equivalent mask for crisp
    # materialisation, and the `S` annotation is preserved on the value.
    test "materialises to the same block interval as the equivalent mask" do
      assert {:ok, block} = Tempo.to_interval(~o"1950S3")
      assert {:ok, mask} = Tempo.to_interval(~o"195X")
      assert block == mask
      assert inspect(block) == ~S|~o"1950Y/1960Y"|
    end

    test "non-terminal significant digits widen to the block without crashing" do
      assert Tempo.to_interval(~o"1950S2-06") == Tempo.to_interval(~o"19XX")
    end

    test "relation matches the equivalent mask" do
      assert Tempo.relation(~o"1950S3", ~o"1965Y") ==
               Tempo.relation(~o"195X", ~o"1965Y")
    end

    test "the S annotation is preserved on the value" do
      assert ~o"1950S3".time == [year: {1950, [significant_digits: 3]}]
    end
  end
end
