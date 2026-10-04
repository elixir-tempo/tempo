defmodule Tempo.Iso8601.LeapSecond.Test do
  use ExUnit.Case, async: true

  alias Tempo.LeapSeconds

  # Policy: ISO 8601 permits `:60` syntactically as a positive
  # leap second. Tempo rejects it at parse regardless of date,
  # matching Elixir/OTP stdlib (`Calendar.ISO.valid_time?/4`,
  # `Time.new/4`, `DateTime.new/3`). Leap-second information
  # remains available as interval-level metadata — see
  # `Tempo.Interval.spans_leap_second?/1` and
  # `Tempo.Interval.leap_seconds_spanned/1`.

  describe ":second 60 is rejected at parse" do
    test "historical IERS date (2016-12-31) is rejected" do
      assert {:error, message} = Tempo.from_iso8601("2016-12-31T23:59:60Z")
      assert Exception.message(message) =~ "not accepted as a Tempo value"
      assert Exception.message(message) =~ "Tempo.LeapSeconds.dates/0"
      assert Exception.message(message) =~ "Tempo.Interval.spans_leap_second?/1"
    end

    test "non-IERS date (2026-12-31) is rejected with the same message" do
      assert {:error, message} = Tempo.from_iso8601("2026-12-31T23:59:60Z")
      assert Exception.message(message) =~ "not accepted"
    end

    test "mid-day :60 is rejected (was rejected before too, uniform message now)" do
      assert {:error, message} = Tempo.from_iso8601("2022-05-15T10:30:60")
      assert Exception.message(message) =~ "not accepted"
    end

    test "non-zero offset :60 is rejected" do
      assert {:error, message} = Tempo.from_iso8601("2016-12-31T23:59:60+05:30")
      assert Exception.message(message) =~ "not accepted"
    end

    test "time-only :60 is rejected" do
      assert {:error, _} = Tempo.from_iso8601("T23:59:60")
    end
  end

  describe "non-leap seconds" do
    test "0..59 all accepted" do
      for s <- [0, 1, 29, 30, 58, 59] do
        assert {:ok, _} = Tempo.from_iso8601("2022-05-15T10:30:#{pad(s)}")
      end
    end

    test ":61 rejected" do
      assert {:error, _} = Tempo.from_iso8601("2016-12-31T23:59:61Z")
    end

    test "negative -1 wraps to 59 (not 60)" do
      assert {:ok, tempo} = Tempo.from_iso8601("T-1S")
      assert Keyword.get(tempo.time, :second) == 59
    end
  end

  describe "Tempo.LeapSeconds — data remains available" do
    test "dates/0 still lists the 27 IERS insertions" do
      assert Enum.count(LeapSeconds.dates()) == 27
      assert {2016, 12, 31} in LeapSeconds.dates()
      assert {1972, 6, 30} in LeapSeconds.dates()
    end

    test "on_date?/3 remains a pure historical predicate" do
      assert LeapSeconds.on_date?(2016, 12, 31)
      refute LeapSeconds.on_date?(2026, 12, 31)
    end

    test "removals/0 is empty today (reserved for future negative leap seconds)" do
      # No negative leap second has ever been used. The CGPM 2022
      # agreement opens the door from ~2035; the list is the
      # extension point.
      assert LeapSeconds.removals() == []
    end
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"
end
