defmodule Tempo.SetOperationOperandsTest do
  use ExUnit.Case, async: true

  # A set operation's second operand may be a list, taken one by one as
  # 1.6 took it (decision 67): mutual free time for any number of people
  # is one call, and an empty list imposes nothing.

  import Tempo.Sigils

  alias Tempo.IntervalSet

  @workday ~o"2026-06-15T09/2026-06-15T17"

  test "a list is taken one operand after another" do
    alice = ~o"2026-06-15T10/2026-06-15T15"
    bob = ~o"2026-06-15T13/2026-06-15T18"
    carol = ~o"2026-06-15T14/2026-06-15T16"

    {:ok, step_by_step} = Tempo.intersection(@workday, alice)
    {:ok, step_by_step} = Tempo.intersection(step_by_step, bob)
    {:ok, step_by_step} = Tempo.intersection(step_by_step, carol)

    assert Tempo.intersection(@workday, [alice, bob, carol]) == {:ok, step_by_step}
    assert Tempo.intersection!(@workday, [alice, bob, carol]) == step_by_step
  end

  test "a union and a difference take each in turn" do
    {:ok, months} = Tempo.union(~o"2026-01", [~o"2026-03", ~o"2026-05"])
    assert IntervalSet.count(months) == 3

    {:ok, left} =
      Tempo.difference(@workday, [
        ~o"2026-06-15T10/2026-06-15T11",
        ~o"2026-06-15T13/2026-06-15T14"
      ])

    assert Tempo.to_iso8601!(left) ==
             "{2026Y6M15DT9H/T10H,2026Y6M15DT11H/T13H,2026Y6M15DT14H/T17H}"
  end

  test "an empty list leaves the first operand as it is" do
    assert Tempo.intersection(@workday, []) == {:ok, @workday}
    assert Tempo.union(@workday, []) == {:ok, @workday}
    assert Tempo.difference(@workday, []) == {:ok, @workday}
  end

  test "the metadata option applies at each step" do
    tagged = fn interval, name -> Tempo.put_metadata(interval, %{free: [name]}) end
    merge = fn a, b -> Map.merge(a, b, fn _key, x, y -> x ++ y end) end

    {:ok, shared} =
      Tempo.intersection(
        tagged.(@workday, "room"),
        [
          tagged.(~o"2026-06-15T10/2026-06-15T15", "alice"),
          tagged.(~o"2026-06-15T13/2026-06-15T18", "bob")
        ],
        metadata: merge
      )

    assert [only] = IntervalSet.members(shared)
    assert Tempo.metadata(only) == %{free: ["room", "alice", "bob"]}
  end

  test "an operand that is no expression stops the operation with its error" do
    assert {:error, %Tempo.ConversionError{reason: :not_an_expression}} =
             Tempo.intersection(@workday, [~o"2026-06-15T10/2026-06-15T15", 42])
  end

  test "an option it does not take is refused even with no operands" do
    assert {:error, %ArgumentError{}} = Tempo.intersection(@workday, [], bound: 1)
  end
end
