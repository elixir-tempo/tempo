defmodule Tempo.Iso8601.ParserTest do
  use ExUnit.Case, async: true
  alias Tempo.Iso8601.Tokenizer

  describe "input guard" do
    test "over-long input is rejected before tokenizing" do
      big = String.duplicate("9", 20_000)
      assert {:error, %Tempo.ParseError{reason: reason}} = Tokenizer.tokenize(big)
      assert reason =~ "exceeds the"
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601(big)
    end

    test "input at the limit still tokenizes normally" do
      assert {:ok, _} = Tokenizer.tokenize("2026-06-15")
    end

    test "deeply nested brackets are rejected fast, not parsed exponentially" do
      deep = String.duplicate("{", 30) <> "1" <> String.duplicate("}", 30) <> "Y"
      assert {:error, %Tempo.ParseError{reason: reason}} = Tokenizer.tokenize(deep)
      assert reason =~ "nesting exceeds"
    end

    test "an unbalanced run of openers is rejected" do
      assert {:error, %Tempo.ParseError{reason: reason}} =
               Tokenizer.tokenize(String.duplicate("{", 40) <> "1Y")

      assert reason =~ "nesting exceeds"
    end

    test "a day or a month out of range is refused by the value's calendar, and by name" do
      # The reader held a month to thirteen and a day to thirty-one before
      # the calendar was asked (decided 2026-10-09: dropped). The calendar
      # says which months a year has and which days a month has.
      for {text, unit, valid} <- [
            {"2026Y1M40D", :day, 1..31},
            {"2026Y6M31D", :day, 1..30},
            {"2026-06-32", :day, 1..30},
            {"2026Y14M", :month, 1..12},
            {"2026-14", :month, 1..12},
            {"2026-99-99", :month, 1..12},
            {"5787-14-01[u-ca=hebrew]", :month, 1..13},
            {"2018-13-07[u-ca=ethiopic]", :day, 1..5}
          ] do
        assert {^text, {:error, %Tempo.InvalidDateError{unit: ^unit, valid_range: ^valid}}} =
                 {text, Tempo.from_iso8601(text)}
      end

      # A thirteenth month is a month of the calendar that has one.
      assert {:ok, _hebrew} = Tempo.from_iso8601("5787-13-01[u-ca=hebrew]")
      assert {:ok, _ethiopic} = Tempo.from_iso8601("2018-13-05[u-ca=ethiopic]")
    end

    test "a run of digits alone is a time of day where it is no date" do
      # The same digits can be a date or a time of day, and the reader tells
      # them apart by the month and the day they would be: this is its
      # choice between two notations, and the one place the bounds stay.
      assert Tempo.from_iso8601("093455.8") == Tempo.from_iso8601("T09:34:55.8")
      assert Tempo.from_iso8601("202614") == Tempo.from_iso8601("T20:26:14")
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("20261402")
    end

    test "legitimate shallow set/group nesting still tokenizes" do
      assert {:ok, _} = Tokenizer.tokenize("{1,2,3}M")
      assert {:ok, _} = Tokenizer.tokenize("[2020Y/2021Y,2022Y/2023Y]")
    end
  end

  describe "iso8601/1" do
    test "parsing simple iso dates" do
      assert {:ok,
              [
                datetime: [
                  year: 2020,
                  month: 11,
                  day: 14,
                  hour: 10,
                  minute: 11,
                  second: 12
                ]
              ], "", _, _, _} = Tokenizer.iso8601("2020-11-14T10:11:12")

      assert {:ok, [date: [year: 2020, week: 28]], "", _, _, _} = Tokenizer.iso8601("2020W28")

      assert {:ok, [date: [year: 2020, day_of_year: 193]], "", _, _, _} =
               Tokenizer.iso8601("2020193")

      assert {:ok, [date: [year: 2020, month: 11]], "", _, _, _} = Tokenizer.iso8601("2020-11")
    end

    test "parsing simple iso durations" do
      assert {:ok, [duration: [day: 1]], "", _, _, _} = Tokenizer.iso8601("P1D")
      assert {:ok, [duration: [hour: 24]], "", _, _, _} = Tokenizer.iso8601("PT24H")
      assert {:ok, [duration: [day: 1, hour: 3]], "", _, _, _} = Tokenizer.iso8601("P1DT3H")
    end

    test "parsing simple iso intervals" do
      assert {:ok,
              [
                interval: [
                  date: [year: 2020, month: 11, day: 14],
                  date: [year: 2020, month: 11, day: 17]
                ]
              ], "", _, _, _} = Tokenizer.iso8601("2020-11-14/2020-11-17")

      assert {:ok,
              [
                interval: [
                  datetime: [
                    year: 2020,
                    month: 11,
                    day: 14,
                    hour: 10,
                    minute: 11,
                    second: 12
                  ],
                  date: [year: 2020, month: 11, day: 17]
                ]
              ], "", _, _, _} = Tokenizer.iso8601("2020-11-14T10:11:12/2020-11-17")

      assert {:ok,
              [
                interval: [
                  date: [year: 2020, month: 11, day: 14],
                  duration: [day: 1]
                ]
              ], "", _, _, _} = Tokenizer.iso8601("2020-11-14/P1D")

      assert {:ok,
              [
                interval: [
                  duration: [day: 1],
                  date: [year: 2020, month: 11, day: 14]
                ]
              ], "", _, _, _} = Tokenizer.iso8601("P1D/2020-11-14")
    end
  end
end
