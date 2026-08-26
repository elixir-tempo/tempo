defmodule Tempo.Parser.Interval.Test do
  use ExUnit.Case, async: true

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.Iso8601.Tokenizer

  test "Intervals" do
    assert Tokenizer.tokenize("2018-01-15/02-20") ==
             {:ok,
              {[
                 interval: [
                   date: [year: 2018, month: 1, day: 15],
                   date: [month: 2, day: 20]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("2018-01-15/2018-02-20") ==
             {:ok,
              {[
                 interval: [
                   date: [year: 2018, month: 1, day: 15],
                   date: [year: 2018, month: 2, day: 20]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("2018-01-15+05:00/2018-02-20") ==
             {:ok,
              {[
                 interval: [
                   date: [
                     year: 2018,
                     month: 1,
                     day: 15,
                     time_shift: [hour: 5, minute: 0]
                   ],
                   date: [year: 2018, month: 2, day: 20]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("19850412T232050/19850625T103000") ==
             {:ok,
              {[
                 interval: [
                   datetime: [
                     year: 1985,
                     month: 4,
                     day: 12,
                     hour: 23,
                     minute: 20,
                     second: 50
                   ],
                   datetime: [
                     year: 1985,
                     month: 6,
                     day: 25,
                     hour: 10,
                     minute: 30,
                     second: 0
                   ]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-04-12T23:20:50/1985-06-25T10:30:00") ==
             {:ok,
              {[
                 interval: [
                   datetime: [
                     year: 1985,
                     month: 4,
                     day: 12,
                     hour: 23,
                     minute: 20,
                     second: 50
                   ],
                   datetime: [
                     year: 1985,
                     month: 6,
                     day: 25,
                     hour: 10,
                     minute: 30,
                     second: 0
                   ]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("19850412T232050/P1Y2M15DT12H30M0S") ==
             {:ok,
              {[
                 interval: [
                   datetime: [
                     year: 1985,
                     month: 4,
                     day: 12,
                     hour: 23,
                     minute: 20,
                     second: 50
                   ],
                   duration: [year: 1, month: 2, day: 15, hour: 12, minute: 30, second: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-04-12T23:20:50/P1Y2M15DT12H30M0S") ==
             {:ok,
              {[
                 interval: [
                   datetime: [
                     year: 1985,
                     month: 4,
                     day: 12,
                     hour: 23,
                     minute: 20,
                     second: 50
                   ],
                   duration: [year: 1, month: 2, day: 15, hour: 12, minute: 30, second: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("P1Y2M15DT12H30M0S/19850412T232050") ==
             {:ok,
              {[
                 interval: [
                   duration: [year: 1, month: 2, day: 15, hour: 12, minute: 30, second: 0],
                   datetime: [
                     year: 1985,
                     month: 4,
                     day: 12,
                     hour: 23,
                     minute: 20,
                     second: 50
                   ]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("P1Y2M15DT12H30M0S/1985-04-12T23:20:50") ==
             {:ok,
              {[
                 interval: [
                   duration: [year: 1, month: 2, day: 15, hour: 12, minute: 30, second: 0],
                   datetime: [
                     year: 1985,
                     month: 4,
                     day: 12,
                     hour: 23,
                     minute: 20,
                     second: 50
                   ]
                 ]
               ], nil}}
  end

  test "Interval with recurrence" do
    assert Tokenizer.tokenize("R12/19850412T232050/19850625T103000") ==
             {:ok,
              {[
                 interval: [
                   recurrence: 12,
                   datetime: [
                     year: 1985,
                     month: 4,
                     day: 12,
                     hour: 23,
                     minute: 20,
                     second: 50
                   ],
                   datetime: [
                     year: 1985,
                     month: 6,
                     day: 25,
                     hour: 10,
                     minute: 30,
                     second: 0
                   ]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("R/19850412T232050/19850625T103000") ==
             {:ok,
              {[
                 interval: [
                   recurrence: :infinity,
                   datetime: [
                     year: 1985,
                     month: 4,
                     day: 12,
                     hour: 23,
                     minute: 20,
                     second: 50
                   ],
                   datetime: [
                     year: 1985,
                     month: 6,
                     day: 25,
                     hour: 10,
                     minute: 30,
                     second: 0
                   ]
                 ]
               ], nil}}
  end

  test "Intervals with undefined beginning or end" do
    assert Tokenizer.tokenize("-13.787E9S4±20E6Y/..") ==
             {:ok,
              {[
                 interval: [
                   {:date,
                    [
                      year:
                        {-13_787_000_000, [significant_digits: 4, margin_of_error: 20_000_000]}
                    ]},
                   :undefined
                 ]
               ], nil}}

    assert Tokenizer.tokenize("../13.787E9S4±20E6Y") ==
             {:ok,
              {[
                 interval: [
                   :undefined,
                   {:date,
                    [year: {13_787_000_000, [significant_digits: 4, margin_of_error: 20_000_000]}]}
                 ]
               ], nil}}
  end

  test "Intervals where trailing century should be month" do
    assert Tokenizer.tokenize("2018-01/02") ==
             {:ok, {[interval: [date: [year: 2018, month: 1], date: [month: 2]]], nil}}
  end

  # Part 2 section 13
  test "Parsing interval with repeat rule but no selection" do
    assert Tokenizer.tokenize("R12/20150929T140000/20150929T153000/F2W") ==
             {:ok,
              {[
                 interval: [
                   recurrence: 12,
                   datetime: [year: 2015, month: 9, day: 29, hour: 14, minute: 0, second: 0],
                   datetime: [year: 2015, month: 9, day: 29, hour: 15, minute: 30, second: 0],
                   repeat_rule: [week: 2]
                 ]
               ], nil}}
  end

  test "Parsing interval with repeat rule and selection" do
    assert Tokenizer.tokenize("R/2018-08-08/P1D/F1YL{3,8}M8DN") ==
             {:ok,
              {[
                 interval: [
                   recurrence: :infinity,
                   date: [year: 2018, month: 8, day: 8],
                   duration: [day: 1],
                   repeat_rule: [year: 1, selection: [month: {:all_of, [3, 8]}, day: 8]]
                 ]
               ], nil}}
  end

  test "Parsing interval with repeat rule and time selector" do
    assert Tokenizer.tokenize("1ML{1,10}DT10H20M0SN") ==
             {:ok,
              {[
                 date: [
                   month: 1,
                   selection: [day: {:all_of, [1, 10]}, hour: 10, minute: 20, second: 0]
                 ]
               ], nil}}
  end

  test "Parsing interval with repeat rule and instance selector" do
    assert Tokenizer.tokenize("R/2018-09-05/P1D/F1YL9M3K1IN") ==
             {:ok,
              {[
                 interval: [
                   recurrence: :infinity,
                   date: [year: 2018, month: 9, day: 5],
                   duration: [day: 1],
                   repeat_rule: [year: 1, selection: [month: 9, day_of_week: 3, instance: 1]]
                 ]
               ], nil}}
  end

  describe "inverted intervals (end before start)" do
    test "a genuinely inverted concrete interval is rejected" do
      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.from_iso8601("2026/2025")
      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.from_iso8601("2027-06/2025")
    end

    test "EDTF reduced-precision and masked intervals stay valid" do
      # The end is a coarser/masked span, not an inversion.
      assert {:ok, _} = Tempo.from_iso8601("1111-01-01/1111")
      assert {:ok, _} = Tempo.from_iso8601("0000/0000")
      assert {:ok, _} = Tempo.from_iso8601("1919-XX-02/1919-XX-01")
      assert {:ok, _} = Tempo.from_iso8601("198X/1999")
    end

    test "non-anchored time-of-day intervals (midnight-crossing) stay valid" do
      # `from > to` here represents a span that crosses midnight.
      assert {:ok, _} = Tempo.from_iso8601("T22/T02")
      assert {:ok, _} = Tempo.from_iso8601("T11/T10")
    end

    test "open, duration, and forward intervals are unaffected" do
      assert {:ok, _} = Tempo.from_iso8601("2026/2027")
      assert {:ok, _} = Tempo.from_iso8601("2026/..")
      assert {:ok, _} = Tempo.from_iso8601("../2026")
      assert {:ok, _} = Tempo.from_iso8601("2026/P1Y")
    end
  end

  describe "ISO 8601-1 §5.5.1 — an end that omits higher order components" do
    # "higher order time scale components may be omitted from the 'end
    # of time interval' … In this case the omitted higher order
    # components from the 'start of time interval' expression apply."
    test "the spec's own example expands to the full form" do
      assert Tempo.from_iso8601!("2018-01-15/02-20") ==
               Tempo.from_iso8601!("2018-01-15/2018-02-20")
    end

    test "a time-only end takes the date from the start" do
      assert Tempo.from_iso8601!("2025-08-28T09:00/T10:15") ==
               Tempo.from_iso8601!("2025-08-28T09:00/2025-08-28T10:15")
    end

    test "the end is anchored, so it can be projected onto the time line" do
      # The defect this guards: an unanchored end compares equal via
      # `compare_endpoints/2` but raises in `to_utc_seconds/1`, so the
      # value looks correct until something needs an instant from it.
      interval = Tempo.from_iso8601!("2025-08-28T09:00/T10:15")

      assert is_integer(Compare.to_utc_seconds(Interval.to(interval)))
    end

    test "an end that is already complete is left alone" do
      assert Tempo.from_iso8601!("2025-08-28/2025-09-02") ==
               Tempo.from_iso8601!("2025-08-28/2025-09-02")

      interval = Tempo.from_iso8601!("2018-01-15/2019-02-20")

      assert Tempo.year(Interval.to(interval)) == 2019
    end

    test "only components coarser than the end's own coarsest unit are taken" do
      # The end states an hour, so it inherits the date and stops. The
      # start's own minute must not follow it in.
      interval = Tempo.from_iso8601!("2022-02-15T10:00/T11:30")

      assert Interval.to(interval).time ==
               [year: 2022, month: 2, day: 15, hour: 11, minute: 30]
    end

    test "a two-digit end is a century, not a day, so nothing is inherited" do
      # §5.5.1 allows the omission only "provided that the resulting
      # expression is unambiguous", and §5.2.2.2 makes a bare two-digit
      # date component a century. `2022-02-15/04` is therefore century 04,
      # not April, and must not quietly acquire the start's year.
      interval = Tempo.from_iso8601!("2022-02-15/04")

      assert Interval.to(interval).time == [year: {:group, 400..499}]
    end

    test "a duration end is unaffected" do
      assert {:ok, interval} = Tempo.from_iso8601("2025-08-28/P1D")
      assert interval.to == nil
      assert interval.duration
    end
  end
end
