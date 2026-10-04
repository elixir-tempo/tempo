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

  # A duration's seconds are numbered as its other units are (ISO 8601-2
  # §4.4.3 gives a duration's units significant digits), where each of these
  # raised a `FunctionClauseError`.
  describe "a duration's seconds" do
    test "take significant digits and a set, as its other units do" do
      assert {:ok, %Tempo.Duration{time: [second: {1230, [significant_digits: 2]}]}} =
               Tempo.from_iso8601("PT1230S2S")

      assert Tempo.from_iso8601("PT-1230S2S") |> elem(1) |> Map.fetch!(:time) ==
               [second: {-1230, [significant_digits: 2]}]

      assert {:ok, %Tempo.Duration{}} = Tempo.from_iso8601("PT{1,2}S")
      assert {:ok, %Tempo.Interval{}} = Tempo.from_iso8601("2026-06-15/PT1230S2S")
    end

    test "written to significant digits read back as written" do
      assert Tempo.to_iso8601(~o"PT1230S2S") == {:ok, "PT1230S2S"}
    end

    test "a fraction after significant digits or a mask is a parse error" do
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("PT1230S2.5S")
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("PT3X.5S")
    end
  end
end
