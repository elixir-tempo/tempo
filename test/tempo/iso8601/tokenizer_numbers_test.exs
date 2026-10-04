defmodule Tempo.Iso8601.TokenizerNumbersTest do
  use ExUnit.Case, async: true

  alias Tempo.Iso8601.Tokenizer
  alias Tempo.ParseError

  # These exercise the numeric grammar in `Tempo.Iso8601.Tokenizer.Numbers`
  # (and the `Grammar` combinators that drive it): plain integers, signed
  # integers, decimal fractions, integer sets, ranges, and unspecified
  # (masked) digits.

  defp tokens(string) do
    assert {:ok, {tokens, _extended}} = Tokenizer.tokenize(string)
    tokens
  end

  test "a plain positive-integer datetime" do
    assert [datetime: parts] = tokens("2022Y6M15DT10H30S")
    assert parts[:year] == 2022
    assert parts[:month] == 6
    assert parts[:second] == 30
  end

  test "a duration of positive integers" do
    assert [duration: parts] = tokens("P1Y2M3DT4H5M6S")
    assert parts[:year] == 1
    assert parts[:second] == 6
  end

  test "a decimal fraction (comma separator) yields a float" do
    assert [duration: parts] = tokens("PT1,5H")
    assert parts[:hour] == 1.5
  end

  test "a signed (negative) year" do
    assert [date: parts] = tokens("-2000Y")
    assert parts[:year] == -2000
  end

  test "an explicit integer set" do
    assert [date: parts] = tokens("{1,2,3}M")
    assert parts[:month] == {:all_of, [1, 2, 3]}
  end

  test "a range inside a set" do
    assert [date: parts] = tokens("{1..5}M")
    assert parts[:month] == {:all_of, [1..5]}
  end

  test "unspecified (masked) trailing digits" do
    assert [date: parts] = tokens("201XY")
    assert parts[:year] == {:mask, [2, 0, 1, :X]}
  end

  test "a fractional second tokenizes" do
    assert [datetime: parts] = tokens("2022Y6M15DT10H30,25S")
    assert parts[:second] == 30
  end

  test "a malformed number is a ParseError" do
    assert {:error, %ParseError{}} = Tokenizer.tokenize("+12022Y6M")
  end

  # Significant digits are given to an integer value (ISO 8601-2 §4.4.3). A
  # fraction with them parsed to a value `to_iso8601/1` raised on.
  test "a fraction takes significant digits only once an exponent has scaled it" do
    assert tokens("-13.787E9S4Y") == [date: [year: {-13_787_000_000, significant_digits: 4}]]

    assert {:error, %ParseError{}} = Tokenizer.tokenize("2026.5S1Y")
    assert {:error, %ParseError{}} = Tokenizer.tokenize("P1.5S1Y")
  end
end
