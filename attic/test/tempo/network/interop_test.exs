defmodule Tempo.Network.InteropTest do
  use ExUnit.Case, async: true

  # Every period boundary is an ordinary Tempo value, so a network
  # interoperates with other EDTF / ISO 8601 tooling for free: bounds
  # parse from ISO 8601 / EDTF strings on the way in and serialise back
  # on the way out.

  import Tempo.Sigils

  alias Tempo.Network
  alias Tempo.Network.{Solver, TimePeriod}

  test "ISO 8601 / EDTF strings are accepted as bounds" do
    period = TimePeriod.new!(:k, from: "1200Y", to: "1250Y", duration: "P50Y")

    assert period.earliest_start == ~o"1200Y"
    assert period.latest_end == ~o"1250Y"
    assert period.min_duration == ~o"P50Y"
  end

  test "tightened bounds serialise back to ISO 8601" do
    {:ok, solved} =
      Network.new()
      |> Network.add_period(:k1, from: ~o"1200Y", duration: {:at_least, ~o"P20Y"})
      |> Network.add_period(:k2, duration: {:at_least, ~o"P35Y"})
      |> Network.add_sequence([:k1, :k2])
      |> Solver.propagate()

    assert Tempo.to_iso8601!(solved.periods[:k2].earliest_end) == "1255Y"
  end

  test "a day-resolution boundary round-trips" do
    {:ok, solved} =
      Network.new()
      |> Network.add_period(:a, from: ~o"1200-06-15", duration: {:at_least, ~o"P100D"})
      |> Network.add_period(:b, [])
      |> Network.add_sequence([:a, :b])
      |> Solver.propagate()

    # 1200-06-15 + 100 days = 1200-09-23.
    boundary = solved.periods[:b].earliest_start
    assert Tempo.to_iso8601!(boundary) == "1200Y9M23D"
    assert {:ok, ^boundary} = Tempo.from_iso8601(Tempo.to_iso8601!(boundary))
  end

  test "an EDTF uncertainty qualifier is carried as metadata, not arithmetic" do
    # `~720` (circa) parses; the qualifier rides along on the value
    # (here as a per-component approximation) and does not move the bound.
    period = TimePeriod.new!(:k, from: ~o"~720Y")

    assert period.earliest_start.qualifications == %{year: :approximate}
    assert TimePeriod.year(period.earliest_start) == 720
  end
end
