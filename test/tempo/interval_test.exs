defmodule Tempo.IntervalTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{ConversionError, Interval, IntervalEndpointsError}

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
        assert {^ends, {:error, %IntervalEndpointsError{reason: ^reason}}} =
                 {ends, Interval.new(ends)}
      end
    end

    test "an end that is neither a value nor a length is refused" do
      assert {:error, %IntervalEndpointsError{}} =
               Interval.new(from: ~o"2026-06-01", to: :tomorrow)
    end

    test "an interval or a set is not an end" do
      for ends <- [
            [from: ~o"2026-06-01/2026-06-02", to: ~o"2026-06-30"],
            [from: ~o"2026-06-01", to: ~o"{2026-06-29,2026-06-30}"],
            [from: ~o"R3/2026-06-01/P1D"],
            [to: ~o"2026-06-01/2026-06-02"]
          ] do
        assert {^ends, {:error, %IntervalEndpointsError{}}} = {ends, Interval.new(ends)}
      end
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

    test "an end given by a duration finer than the other end is written to the duration's part" do
      # Written in tenths, the end would be 0.7 and the interval a fifth of a
      # second where a quarter was asked for.
      assert Tempo.to_interval(~o"2026-06-15T10:00:00.5/PT0.25S") ==
               {:ok, ~o"2026-06-15T10:00:00.5/2026-06-15T10:00:00.75"}

      assert Tempo.to_interval(~o"PT0.25S/2026-06-15T10:00:00.5") ==
               {:ok, ~o"2026-06-15T10:00:00.25/2026-06-15T10:00:00.5"}
    end
  end

  describe "instants/1" do
    # An interval of dates runs from the first's midnight to the midnight
    # after the last, as `Date` counts them.
    test "of dates ends as the day after the last begins" do
      for first <- Date.range(~D[2026-02-25], ~D[2026-03-03]),
          last <- Date.range(first, Date.add(first, 4)) do
        span = Interval.new!(from: Tempo.from_elixir!(first), to: Tempo.from_elixir!(last))

        assert Interval.instants(span) ==
                 {:ok,
                  {NaiveDateTime.new!(first, ~T[00:00:00]),
                   NaiveDateTime.new!(Date.add(last, 1), ~T[00:00:00])}}
      end
    end

    test "of times of day at a shift are the moments, at UTC" do
      {:ok, from} = DateTime.new(~D[2026-06-15], ~T[09:00:00], "Etc/UTC")
      {:ok, to} = DateTime.new(~D[2026-06-15], ~T[17:30:00], "Etc/UTC")

      span = Interval.new!(from: Tempo.from_elixir!(from), to: Tempo.from_elixir!(to))
      assert Interval.instants(span) == {:ok, {from, to}}
    end

    test "of a zoned interval are its readings in the zone" do
      {:ok, {from, to}} =
        Interval.instants(~o"2026-03-29T01:00/2026-03-29T04:00[Europe/Paris]")

      # The clocks go forward an hour at 02:00 that night: three readings, two hours.
      assert DateTime.diff(to, from, :hour) == 2
      assert {from.hour, to.hour, to.time_zone} == {1, 4, "Europe/Paris"}
    end

    test "keep a fraction of a second, and an open end is nil" do
      assert Interval.instants(~o"2026-06-15T09:30:15.25/2026-06-15T10") ==
               {:ok, {~N[2026-06-15 09:30:15.250000], ~N[2026-06-15 10:00:00]}}

      assert Interval.instants(~o"2026-06/..") == {:ok, {~N[2026-06-01 00:00:00], nil}}
      assert Interval.instants(~o"../..") == {:ok, {nil, nil}}
    end

    test "of what is no interval with a year is refused" do
      assert {:error, %ConversionError{reason: :needs_a_year}} =
               Interval.instants(~o"6M/8M")

      assert {:error, %ConversionError{reason: :several}} =
               Interval.instants(~o"2026")

      assert {:error, %ConversionError{reason: :not_an_expression}} =
               Interval.instants(~D[2026-06-15])
    end
  end
end
