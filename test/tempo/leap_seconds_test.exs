defmodule Tempo.LeapSecondsTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.LeapSeconds

  describe "a second numbered 60" do
    test "is no value, on any date" do
      for text <- [
            "2016-12-31T23:59:60Z",
            "2026-12-31T23:59:60Z",
            "2022-05-15T10:30:60",
            "2016-12-31T23:59:60+05:30",
            "T23:59:60"
          ] do
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601(text), text
      end
    end
  end

  describe "spanned/1" do
    test "a leap second lies between 23:59:59 and the midnight after it" do
      assert LeapSeconds.spanned(~o"2016-12-31T23:59:59Z/2017-01-01T00:00:00Z") ==
               {:ok, [{2016, 12, 31}]}

      assert LeapSeconds.spanned(~o"2016-12-31T23:59:59Z") == {:ok, [{2016, 12, 31}]}
      assert LeapSeconds.spanned(~o"2016-12-31T23:59:58Z") == {:ok, []}
      assert LeapSeconds.spanned(~o"2017-01-01T00:00:00Z") == {:ok, []}
      assert LeapSeconds.spanned(~o"2016-12-31") == {:ok, [{2016, 12, 31}]}
      assert LeapSeconds.spanned(~o"2017-01-01") == {:ok, []}
    end

    test "it is one moment, whatever the zone" do
      assert LeapSeconds.spanned(~o"2016-12-31T18:59:00/2016-12-31T19:01:00[America/New_York]") ==
               {:ok, [{2016, 12, 31}]}

      assert LeapSeconds.spanned(~o"2016-12-31T23:59:00/2017-01-01T00:01:00[America/New_York]") ==
               {:ok, []}
    end

    test "a set and a recurrence span those their members span" do
      {:ok, new_years} = Tempo.to_interval(~o"R3/2015-12-31/P1Y")

      assert LeapSeconds.spanned(new_years) == {:ok, [{2016, 12, 31}]}

      assert LeapSeconds.spanned(~o"{2012-06-30,2015-06-30,2016-06-30}") ==
               {:ok, [{2012, 6, 30}, {2015, 6, 30}]}
    end

    test "an expression with no year or no end has none to list" do
      assert {:error, %ConversionError{reason: :needs_a_year}} =
               LeapSeconds.spanned(~o"12M31D")

      assert {:error, %ConversionError{reason: :unbounded}} =
               LeapSeconds.spanned(~o"2015/..")
    end
  end

  describe "a length with leap seconds" do
    test "counts a second for each spanned, in the expression's own unit and seconds" do
      assert Tempo.duration(~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z", leap_seconds: true) ==
               ~o"PT121S"

      assert Tempo.duration(~o"2016-12-31T23:59Z/2017-01-01T00:01Z", leap_seconds: true) ==
               ~o"PT2M1S"

      assert Tempo.duration(~o"2026-06-15T09:00Z/2026-06-15T10:00Z", leap_seconds: true) ==
               ~o"PT60M"

      assert Tempo.duration(~o"2015/..", leap_seconds: true) == :infinity
    end

    test "the option is true or false" do
      assert {:error, %ArgumentError{}} = Tempo.duration(~o"2026", leap_seconds: :yes)
      assert {:error, %ArgumentError{}} = Tempo.duration(~o"2026", seconds: true)
      assert Tempo.duration(~o"2026", leap_seconds: false) == ~o"P1Y"
    end

    test "the interval's questions" do
      assert Interval.spans_leap_second?(~o"2016-12-31T23:00:00Z/2017-01-01T01:00:00Z")
      refute Interval.spans_leap_second?(~o"2026-06-15/2026-06-16")
      assert Interval.leap_seconds_spanned(~o"2026-06-15/2026-06-16") == []
      assert_raise ConversionError, fn -> Interval.spans_leap_second?(~o"2015/..") end
    end
  end
end
