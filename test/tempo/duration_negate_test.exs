defmodule Tempo.Duration.NegateTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Tempo.Sigils

  alias Tempo.Duration
  alias Tempo.Test.Engine.Compare

  doctest Tempo.Duration, only: [negate: 1]

  describe "negate/1" do
    test "flips every component" do
      assert Duration.negate(~o"P1Y2M3DT4H5M6S").time ==
               [year: -1, month: -2, day: -3, hour: -4, minute: -5, second: -6]
    end

    test "a zero duration is its own negation" do
      assert Duration.negate(~o"PT0S") == ~o"PT0S"
    end

    test "mixed signs each flip independently" do
      {:ok, mixed} = Duration.new(hour: 2, minute: -30)

      assert Duration.negate(mixed).time == [hour: -2, minute: 30]
    end
  end

  describe "properties" do
    # Generate durations over the fixed-length units, so shifting is
    # exact and independent of the reference date.
    defp duration do
      gen all(
            hours <- integer(-48..48),
            minutes <- integer(-120..120),
            seconds <- integer(-3600..3600)
          ) do
        Duration.new!(hour: hours, minute: minutes, second: seconds)
      end
    end

    property "negating twice is the identity" do
      check all(d <- duration()) do
        assert d
               |> Duration.negate()
               |> Duration.negate() == d
      end
    end

    property "shifting by a duration then its negation returns the origin" do
      origin = ~o"2027-03-02T12:00:00"

      check all(d <- duration()) do
        assert origin
               |> Tempo.shift(d)
               |> Tempo.shift(Duration.negate(d)) == origin
      end
    end

    property "a negated duration moves the opposite way" do
      origin = ~o"2027-03-02T12:00:00"

      check all(d <- duration()) do
        forward = Tempo.shift(origin, d)
        backward = Tempo.shift(origin, Duration.negate(d))

        # Whatever side of the origin one lands on, the other lands on
        # the opposite side — or both sit on it for a zero duration.
        assert Compare.compare_endpoints(forward, origin) ==
                 opposite(Compare.compare_endpoints(backward, origin))
      end
    end

    defp opposite(:earlier) do
      :later
    end

    defp opposite(:later) do
      :earlier
    end

    defp opposite(:same) do
      :same
    end
  end
end
