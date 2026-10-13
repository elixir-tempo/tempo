defmodule Tempo.IntervalTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{Interval, IntervalEndpointsError}

  # `Tempo.Interval.new/1` makes a span from two ends, or says why they make none.

  describe "new/1" do
    test "two values, a value and a length, or one open end" do
      assert Interval.new(from: ~o"2026-06-01", to: ~o"2026-06-30") ==
               {:ok, ~o"2026-06-01/2026-06-30"}

      assert Interval.new(from: ~o"2026-06-01", to: ~o"P1M") == {:ok, ~o"2026-06-01/P1M"}
      assert Interval.new(from: ~o"P1M", to: ~o"2026-06-30") == {:ok, ~o"P1M/2026-06-30"}
      assert Interval.new(from: ~o"2026-06-01") == {:ok, ~o"2026-06-01/.."}
      assert Interval.new(to: ~o"2026-06-30") == {:ok, ~o"../2026-06-30"}
    end

    test "keeps the caller's metadata" do
      {:ok, booking} =
        Interval.new(from: ~o"2026-06-01", to: ~o"2026-06-03", metadata: %{room: 4})

      assert Tempo.metadata(booking) == %{room: 4}
    end

    test "ends that make no span are refused, each for its reason" do
      for {ends, reason} <- [
            {[from: ~o"2026-06-30", to: ~o"2026-06-01"], :order},
            {[from: ~o"P1D", to: ~o"P2D"], :duration},
            {[], :open},
            {[from: ~o"2026-06-01", to: ~o"P0D"], :empty},
            {[from: ~o"2026-06-01", to: ~o"5786-03-15[u-ca=hebrew]"], :calendars},
            {[from: ~o"2026-06-01[Europe/Paris]", to: ~o"2026-06-30[America/New_York]"], :zones}
          ] do
        assert {ends, {:error, %IntervalEndpointsError{reason: ^reason}}} =
                 {ends, Interval.new(ends)}
      end
    end

    test "an end that is neither a value nor a length is refused" do
      assert {:error, %IntervalEndpointsError{}} =
               Interval.new(from: ~o"2026-06-01", to: :tomorrow)
    end

    test "the error says what is wrong and what to do" do
      {:error, error} = Interval.new(from: ~o"2026-06-30", to: ~o"2026-06-01")
      assert Exception.message(error) =~ "ends before it starts"

      {:error, error} = Interval.new(from: ~o"2026-06-01", to: ~o"P0D")
      assert Exception.message(error) =~ "has no length"
    end

    test "the raising form raises that error" do
      assert Interval.new!(from: ~o"2026-06-01", to: ~o"2026-06-30") == ~o"2026-06-01/2026-06-30"

      assert_raise IntervalEndpointsError, fn ->
        Interval.new!(from: ~o"2026-06-30", to: ~o"2026-06-01")
      end
    end
  end

  describe "the ends of an interval" do
    test "are what was written" do
      june = ~o"2026-06-01/2026-06-30"
      assert Interval.from(june) == ~o"2026-06-01"
      assert Interval.to(june) == ~o"2026-06-30"
      assert Interval.endpoints(june) == {~o"2026-06-01", ~o"2026-06-30"}
      assert Interval.endpoints(~o"2026-06-01/..") == {~o"2026-06-01", :open}
    end
  end
end
