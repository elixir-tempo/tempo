defmodule Tempo.Duration.Compare.Test do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Duration

  doctest Tempo.Duration

  describe "compare/3" do
    test "orders by length" do
      assert Duration.compare(~o"PT30M", ~o"PT2H") == :lt
      assert Duration.compare(~o"PT2H", ~o"PT30M") == :gt
    end

    test "compares length, not shape" do
      assert Duration.compare(~o"PT90M", ~o"PT1H30M") == :eq
      assert Duration.compare(~o"P1D", ~o"PT24H") == :eq
    end

    test "the module sorts, as Date and Tempo do" do
      assert Enum.sort([~o"PT2H", ~o"PT30M", ~o"PT1H"], Duration) ==
               [~o"PT30M", ~o"PT1H", ~o"PT2H"]
    end

    test "and answers max and min" do
      durations = [~o"PT30M", ~o"PT2H", ~o"PT45M"]

      assert Enum.max(durations, Duration) == ~o"PT2H"
      assert Enum.min(durations, Duration) == ~o"PT30M"
    end

    test "negative durations order below zero" do
      assert Duration.compare(~o"PT-1H", ~o"PT1H") == :lt
    end

    test "a calendar-variable duration raises without an anchor" do
      # February and August are not the same size, so a month has no
      # length to compare until a date says which month.
      assert_raise ArgumentError, ~r/no fixed length/, fn ->
        Duration.compare(~o"P1M", ~o"P30D")
      end
    end

    test "and resolves against one when given" do
      # February 2026 is 28 days, so a month is shorter than thirty.
      assert Duration.compare(~o"P1M", ~o"P30D", relative_to: ~o"2026-02-01") == :lt

      # August is 31, so it is longer.
      assert Duration.compare(~o"P1M", ~o"P30D", relative_to: ~o"2026-08-01") == :gt
    end
  end
end
