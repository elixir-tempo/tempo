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

    test "unanchored time-of-day intervals (midnight-crossing) stay valid" do
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

    # An end that is one bare number is the start's last component. Read as
    # what two digits are alone, a century, `2022-02-15/20` ran from 2022
    # back to the year 2000.
    test "a bare number is the start's last component" do
      for {abbreviated, whole} <- [
            {"2026-06-15/20", "2026-06-15/2026-06-20"},
            {"20260615/20", "2026-06-15/2026-06-20"},
            {"2026-06/08", "2026-06/2026-08"},
            {"2026-06-15T10/11", "2026-06-15T10/2026-06-15T11"},
            {"2026-06-15T10:30/45", "2026-06-15T10:30/2026-06-15T10:45"},
            {"2026-06-15T10:30:15/45", "2026-06-15T10:30:15/2026-06-15T10:30:45"},
            {"2026-W25/27", "2026-W25/2026-W27"},
            {"2026-W25-1/5", "2026-W25-1/2026-W25-5"},
            {"2026-166/170", "2026-166/2026-170"},
            {"T10:30/45", "T10:30/T10:45"},
            {"R3/2026-06-15/20", "R3/2026-06-15/2026-06-20"}
          ] do
        assert Tempo.from_iso8601!(abbreviated) == Tempo.from_iso8601!(whole)
      end
    end

    test "a bare number keeps its end's suffix and the start's zone" do
      assert Tempo.from_iso8601!("2026-06-15T10:30Z/45") ==
               Tempo.from_iso8601!("2026-06-15T10:30Z/2026-06-15T10:45Z")

      assert Tempo.from_iso8601!("2026-06-15T10:30[Europe/Paris]/45") ==
               Tempo.from_iso8601!("2026-06-15T10:30[Europe/Paris]/2026-06-15T10:45")
    end

    test "a bare number that is before the start, or is no value of its unit, is an error" do
      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.from_iso8601("2026-06-15/07")
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026-06-15/45")
    end

    test "a day and a time of day take the year and the month from the start" do
      assert Tempo.from_iso8601!("2007-11-13T09:00/15T17:00") ==
               Tempo.from_iso8601!("2007-11-13T09:00/2007-11-15T17:00")

      assert Tempo.from_iso8601!("20071113T0900/15T1700") ==
               Tempo.from_iso8601!("2007-11-13T09:00/2007-11-15T17:00")
    end

    test "a week and a day of it take the year from the start" do
      assert Tempo.from_iso8601!("2026-W25-1/W26-5") ==
               Tempo.from_iso8601!("2026-W25-1/2026-W26-5")

      assert Tempo.from_iso8601!("2026W251/W265") == Tempo.from_iso8601!("2026-W25-1/2026-W26-5")
      assert Tempo.from_iso8601!("W26-5") == Tempo.from_iso8601!("26W5K")
    end

    test "a bare number after a start with no finer unit is what it is alone" do
      assert Interval.to(Tempo.from_iso8601!("2022/24")).time == [year: {:group, 2400..2499}]

      assert Interval.to(Tempo.from_iso8601!("2022-02-15/203")).time == [
               year: {:group, 2030..2039}
             ]
    end

    test "a century or a decade is written with its designator" do
      interval = Tempo.from_iso8601!("2022-02-15/24C")

      assert Interval.to(interval).time == [year: {:group, 2400..2499}]
    end

    test "one digit ends an interval only after a day of the week" do
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("2026-06-15/5")
    end

    test "a duration end is unaffected" do
      assert {:ok, interval} = Tempo.from_iso8601("2025-08-28/P1D")
      assert interval.to == nil
      assert interval.duration
    end

    test "an end of four digits in the basic format is a year, and the error says so" do
      # The omission is allowed "provided that the resulting expression is
      # unambiguous", and four digits alone are a year (§5.3.5).
      assert {:error, %Tempo.IntervalEndpointsError{} = error} =
               Tempo.from_iso8601("20260615/0720")

      message = Exception.message(error)
      assert message =~ ~s(The end "0720" of "20260615/0720" is read as the year 720)
      assert message =~ "`2026-06-15/07-20`"
      assert message =~ "`20260615/T0720`"

      assert {:error, %Tempo.IntervalEndpointsError{} = error} =
               Tempo.from_iso8601("20260615T1030/1130")

      message = Exception.message(error)
      assert message =~ "is read as the year 1130"
      assert message =~ "`20260615T1030/T1130`"

      # Digits that are no month and day are shown as a time of day alone.
      {:error, error} = Tempo.from_iso8601("20260615/1315")
      refute Exception.message(error) =~ "13-15"
      assert Exception.message(error) =~ "`20260615/T1315`"
    end

    test "an end of six digits after a basic time is a year and a month, and the error says so" do
      assert {:error, %Tempo.InvalidDateError{} = error} =
               Tempo.from_iso8601("20260615T103000/113000")

      assert Exception.message(error) =~ "is read as the year 1130 and the month 00"
      assert Exception.message(error) =~ "`20260615T103000/T113000`"
    end

    test "the forms the error names are read, and a year after the start is a year" do
      assert Tempo.from_iso8601!("2026-06-15/07-20") ==
               Tempo.from_iso8601!("2026-06-15/2026-07-20")

      assert Tempo.from_iso8601!("20260615T1030/T1130") ==
               Tempo.from_iso8601!("2026-06-15T10:30/2026-06-15T11:30")

      assert Tempo.from_iso8601!("20260615/2027") == Tempo.from_iso8601!("2026-06-15/2027")

      # An end written in full that is before its start keeps the plain error.
      {:error, error} = Tempo.from_iso8601("20260615/20260601")

      assert Exception.message(error) ==
               "interval :from endpoint is not earlier than its :to endpoint"
    end
  end
end
