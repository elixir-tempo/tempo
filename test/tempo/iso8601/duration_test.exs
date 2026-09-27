defmodule Tempo.Parser.Duration.Test do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Iso8601.Tokenizer

  doctest Tempo.Duration

  test "Alternate duration format section 5.5.2.4" do
    assert Tokenizer.tokenize("P00020110T223355") ==
             {:ok,
              {[
                 duration: [
                   datetime: [
                     year: 2,
                     month: 1,
                     day: 10,
                     hour: 22,
                     minute: 33,
                     second: 55
                   ]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("P0002-01-10T22:33:55") ==
             {:ok,
              {[
                 duration: [
                   datetime: [
                     year: 2,
                     month: 1,
                     day: 10,
                     hour: 22,
                     minute: 33,
                     second: 55
                   ]
                 ]
               ], nil}}
  end

  test "Negative durations section 4.4.1.9" do
    assert Tokenizer.tokenize("-P100D") ==
             {:ok, {[duration: [direction: :negative, day: 100]], nil}}

    assert Tokenizer.tokenize("-P1Y3D") ==
             {:ok, {[duration: [direction: :negative, year: 1, day: 3]], nil}}
  end

  describe "the alternative format (ISO 8601-1 §5.5.2.4)" do
    test "is the duration its designator form writes" do
      assert Tempo.from_iso8601("P0002-01-10T22:33:55") ==
               Tempo.from_iso8601("P2Y1M10DT22H33M55S")

      assert Tempo.from_iso8601("P00020110T223355") == Tempo.from_iso8601("P2Y1M10DT22H33M55S")
      assert Tempo.from_iso8601("P0002-178T22:33:55") == Tempo.from_iso8601("P2Y178DT22H33M55S")

      assert Tempo.from_iso8601("P0002-01-10T22:33:55.5") ==
               Tempo.from_iso8601("P2Y1M10DT22H33M55.5S")

      assert Tempo.from_iso8601("-P0002-01-10T22:33:55") ==
               Tempo.from_iso8601("-P2Y1M10DT22H33M55S")
    end

    test "a week date, a day of the week or an unspecified digit is not a duration" do
      for input <- ["P2026-W10", "P2K", "P2026-XX-15"] do
        assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601(input)
      end
    end
  end
end
