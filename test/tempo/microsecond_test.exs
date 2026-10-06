defmodule Tempo.MicrosecondTest do
  use ExUnit.Case, async: true

  # The fraction of a second a value holds is the pair Elixir's `Time` holds:
  # the microseconds, and how many digits they were written to. The measure
  # is `Time.from_iso8601!/1` reading the same digits, which keeps a
  # microsecond's six and drops what is finer, as Tempo does.

  alias Tempo.Microsecond

  doctest Tempo.Microsecond

  # Fractions as they are written: with zeros before and after, and of one
  # digit to more digits than a microsecond has.
  @written ~w(0 5 05 50 500 123 0123 000001 999999 000000 1234567 9999999 123456789012345)

  defp read(digits), do: Microsecond.from_fraction(String.to_integer(digits), byte_size(digits))

  describe "from_fraction/2" do
    test "is the microsecond Elixir reads from the same digits" do
      for digits <- @written do
        assert {digits, read(digits)} ==
                 {digits, Time.from_iso8601!("00:00:00." <> digits).microsecond}
      end
    end

    test "of no digits is the microsecond of a time written with none" do
      assert Microsecond.from_fraction(0, 0) == Time.from_iso8601!("00:00:00").microsecond
    end
  end

  describe "to_digits_string/1" do
    test "writes the digits a fraction was read from, as far as a microsecond" do
      for digits <- @written do
        assert {digits, Microsecond.to_digits_string(read(digits))} ==
                 {digits, String.slice(digits, 0, 6)}
      end
    end

    test "writes the fraction Elixir writes" do
      for digits <- @written do
        time = Time.from_iso8601!("00:00:00." <> digits)

        assert {digits, "00:00:00." <> Microsecond.to_digits_string(read(digits))} ==
                 {digits, Time.to_iso8601(time)}
      end
    end

    test "writes nothing for a second with no fraction" do
      assert Microsecond.to_digits_string(Microsecond.from_fraction(0, 0)) == ""
    end
  end

  describe "valid?/1" do
    test "is true of every fraction read" do
      for digits <- @written do
        assert {digits, Microsecond.valid?(read(digits))} == {digits, true}
      end
    end

    test "is false of what is no microsecond with its precision" do
      for other <- [
            nil,
            :nope,
            "",
            123,
            [1, 3],
            {1, 2, 3},
            {-1, 3},
            {1.5, 3},
            {1_000_000, 6},
            {1, 7},
            {1, -1},
            {1, :three}
          ] do
        assert {other, Microsecond.valid?(other)} == {other, false}
      end
    end
  end
end
