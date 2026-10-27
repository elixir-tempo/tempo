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

  describe "an operand with no year placed by the window" do
    test "a window that is a range places it on each of the range's periods" do
      fortnight = ~o"2026-06-01/2026-06-14"
      years = ~o"2026/2027"
      hours = ~o"2026-06-01T00/2026-06-03T00"

      assert Tempo.difference(fortnight, ~o"{6,7}K", within: fortnight) ==
               {:ok, ~o"{2026Y6M1D/5D,2026Y6M8D/12D}"}

      assert Tempo.intersection(years, ~o"12M25D", within: years) ==
               {:ok, ~o"{2026Y12M25D/2026Y12M25D,2027Y12M25D/2027Y12M25D}"}

      assert Tempo.intersection(hours, ~o"T09/T17", within: hours) ==
               {:ok, ~o"{2026Y6M1DT9H/T17H,2026Y6M2DT9H/T17H}"}
    end

    test "a span placed past the window's one value is outside it" do
      # Winter, December through February, placed by June is the winter after
      # it, none of which is in June.
      june = ~o"2026-06"

      assert Tempo.union(june, ~o"12M/2M", within: june) == {:ok, ~o"{2026Y6M/2026Y6M}"}
      assert Tempo.difference(~o"12M/2M", june, within: june) == {:ok, ~o"{}"}
    end

    test "every operation takes it as Tempo.to_interval/2 places it" do
      operands = [~o"6K", ~o"{6,7}K", ~o"12M25D", ~o"T09/T17", ~o"12M/2M"]
      windows = [~o"2026-06", ~o"2026-01-02/2026-03-31", ~o"2026/2027"]
      operations = [:union, :intersection, :difference, :symmetric_difference]

      for window <- windows, operand <- operands, operation <- operations do
        {:ok, placed} = Tempo.to_interval(operand, within: window)

        assert apply(Tempo, operation, [window, operand, [within: window]]) ==
                 apply(Tempo, operation, [window, placed]),
               "#{operation} of #{inspect(window)} and #{inspect(operand)}"

        assert apply(Tempo, operation, [operand, window, [within: window]]) ==
                 apply(Tempo, operation, [placed, window]),
               "#{operation} of #{inspect(operand)} and #{inspect(window)}"
      end
    end
  end
end
