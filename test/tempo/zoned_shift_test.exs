defmodule Tempo.ZonedShiftTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  # New York springs forward on 8 March 2026 (02:00 becomes 03:00) and
  # falls back on 1 November 2026 (02:00 EDT becomes 01:00 EST).

  describe "hours are time on the time line" do
    test "five hours after 23:00 on the night the clocks spring forward is 05:00" do
      assert Tempo.shift(~o"2026-03-07T23[America/New_York]", hour: 5) ==
               ~o"2026-03-08T05[America/New_York]"

      assert Tempo.shift(~o"2026-03-08T05[America/New_York]", hour: -5) ==
               ~o"2026-03-07T23[America/New_York]"
    end

    test "shifting by the duration between two times lands on the second" do
      from = ~o"2026-03-07T23[America/New_York]"
      to = ~o"2026-03-08T05[America/New_York]"

      assert Tempo.shift(from, Tempo.duration!(from, to)) == to
    end

    test "half an hour of daylight saving keeps its half hour" do
      assert Tempo.shift(~o"2026-10-04T01[Australia/Lord_Howe]", hour: 1) ==
               ~o"2026-10-04T02:30[Australia/Lord_Howe]"
    end

    test "the hours of a fall-back night name their side of the fold" do
      first = Tempo.shift(~o"2026-11-01T00:30[America/New_York]", hour: 1)
      second = Tempo.shift(~o"2026-11-01T00:30[America/New_York]", hour: 2)

      assert first == Tempo.from_iso8601!("2026-11-01T01:30-04[America/New_York]")
      assert second == Tempo.from_iso8601!("2026-11-01T01:30-05[America/New_York]")

      assert Tempo.shift(~o"2026-11-01T00:30[America/New_York]", hour: 3) ==
               ~o"2026-11-01T02:30[America/New_York]"
    end

    test "a floating value has no clock change to cross" do
      assert Tempo.shift(~o"2026-03-07T23", hour: 5) == ~o"2026-03-08T04"
    end
  end

  describe "days, months and years keep the wall clock" do
    test "a day after noon is noon, and twenty-four hours after it is 13:00" do
      assert Tempo.shift(~o"2026-03-07T12[America/New_York]", day: 1) ==
               ~o"2026-03-08T12[America/New_York]"

      assert Tempo.shift(~o"2026-03-07T12[America/New_York]", hour: 24) ==
               ~o"2026-03-08T13[America/New_York]"
    end

    test "a day that lands in the spring-forward gap moves on by the gap" do
      assert Tempo.shift(~o"2026-03-07T02:30[America/New_York]", day: 1) ==
               ~o"2026-03-08T03:30[America/New_York]"
    end

    test "a day that lands on a repeated reading is its first occurrence" do
      assert Tempo.shift(~o"2026-10-31T01:30[America/New_York]", day: 1) ==
               ~o"2026-11-01T01:30[America/New_York]"
    end

    test "an offset the value carries is kept to the reading it lands on" do
      march = Tempo.from_iso8601!("2026-03-01T12:00-05:00[America/New_York]")

      assert Tempo.shift(march, month: 1) ==
               Tempo.from_iso8601!("2026-04-01T12:00-04:00[America/New_York]")
    end

    test "days go before hours" do
      assert Tempo.shift(~o"2026-03-07T01[America/New_York]", ~o"P1DT2H") ==
               ~o"2026-03-08T04[America/New_York]"
    end
  end

  describe "spans in a named zone" do
    test "the hour a fall-back repeats is one hour long" do
      {:ok, hour} = Tempo.to_interval(~o"2026-11-01T01[America/New_York]")

      assert hour.to == Tempo.from_iso8601!("2026-11-01T01-05[America/New_York]")
      assert Tempo.duration(hour) == ~o"PT1H"
    end

    test "the hour before the spring-forward gap ends on its far side" do
      {:ok, hour} = Tempo.to_interval(~o"2026-03-08T01[America/New_York]")

      assert hour.to == ~o"2026-03-08T03[America/New_York]"
      assert Tempo.duration(hour) == ~o"PT1H"
    end

    test "a start and a number of hours ends that many hours later" do
      {:ok, night} =
        Tempo.to_interval(Tempo.from_iso8601!("2026-03-07T23[America/New_York]/PT5H"))

      assert night.to == ~o"2026-03-08T05[America/New_York]"
    end

    test "an hourly recurrence steps over the hour the clocks skip" do
      {:ok, hours} =
        Tempo.to_interval(Tempo.from_iso8601!("R4/2026-03-08T00[America/New_York]/PT1H"))

      starts = hours |> IntervalSet.to_list() |> Enum.map(&Tempo.hour(&1.from))

      assert starts == [0, 1, 3, 4]
    end
  end
end
