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

    test "an open end is placed where the window ends or begins, as a span with a year's is" do
      for {undated, dated, window} <- [
            {~o"6M/..", ~o"2026-06/..", ~o"2026"},
            {~o"T10H/..", ~o"2026-06-15T10/..", ~o"2026-06-15"},
            {~o"../6M", ~o"../2026-06", ~o"2026"},
            {~o"../T10H", ~o"../2026-06-15T10", ~o"2026-06-15"}
          ] do
        assert Tempo.to_interval(undated, within: window) ==
                 Tempo.to_interval(dated, within: window)

        assert Tempo.complement(undated, within: window) ==
                 Tempo.complement(dated, within: window)

        assert Tempo.intersection(window, undated, within: window) ==
                 Tempo.intersection(window, dated, within: window)
      end

      assert Tempo.complement(~o"6M/..", within: ~o"2026") == {:ok, ~o"{2026Y/5M}"}
    end

    test "a window finer than a span's start places the start whole, where the window holds its first instant" do
      first_days = ~o"2026-06-01T00/2026-06-03T00"
      mid_june = ~o"2026-06-10T00/2026-06-12T00"
      saturday_morning = ~o"2026-06-06T10/2026-06-06T12"

      assert Tempo.to_interval(~o"6M/8M", within: first_days) == {:ok, ~o"2026Y6M/8M"}
      assert Tempo.to_interval(~o"6M/8M", within: mid_june) == {:ok, ~o"{}"}
      assert Tempo.to_interval(~o"6M/8M", within: saturday_morning) == {:ok, ~o"{}"}
      assert Tempo.to_interval(~o"6K/2K", within: saturday_morning) == {:ok, ~o"{}"}
      assert Tempo.to_interval(~o"T09/T17", within: saturday_morning) == {:ok, ~o"{}"}

      assert Tempo.intersection(first_days, ~o"6M/8M", within: first_days) ==
               {:ok, ~o"{2026Y6M1DT0H/3DT0H}"}

      assert Tempo.intersection(mid_june, ~o"6M/8M", within: mid_june) == {:ok, ~o"{}"}
    end

    test "an open end placed at a window edge finer than its span is written to read back to the edge" do
      first_days = ~o"2026-06-01T00/2026-06-03T00"

      for open <- [~o"2026-06/..", ~o"6M/.."] do
        {:ok, placed} = Tempo.to_interval(open, within: first_days)

        assert placed == ~o"2026Y6M/3DT0H"

        assert Tempo.intersection(first_days, placed) ==
                 Tempo.intersection(first_days, open, within: first_days)
      end

      assert Tempo.to_interval(~o"../2026-06", within: ~o"2026-06-10T12/2026-06-20") ==
               {:ok, ~o"2026Y6M10DT12H/2026Y6M"}

      assert Tempo.to_interval(~o"2026-06/..", within: ~o"2026") == {:ok, ~o"2026Y6M/12M"}

      # Written in the span's calendar: 20 October 2026 is 9 Heshvan 5787.
      assert Tempo.to_interval(~o"5787Y/..[u-ca=hebrew]", within: ~o"2026-10-01/2026-10-20") ==
               {:ok, ~o"5787Y/2M9D[u-ca=hebrew]"}
    end

    test "with no window, an intersection places it on the other operand, in either order" do
      fortnight = ~o"2026-06-01/2026-06-14"
      weekend = ~o"{6,7}K"

      assert Tempo.intersection(fortnight, weekend) ==
               Tempo.intersection(fortnight, weekend, within: fortnight)

      assert Tempo.intersection(weekend, fortnight) ==
               Tempo.intersection(weekend, fortnight, within: fortnight)

      assert {:ok, weekend_days} = Tempo.intersection(fortnight, weekend)
      assert IntervalSet.count(weekend_days) == 4
    end

    test "with no window, a difference from the operand with a year places it there" do
      fortnight = ~o"2026-06-01/2026-06-14"
      fourth_of_june = ~o"R/../P1Y/FL6M4DN"

      assert Tempo.difference(fortnight, ~o"{6,7}K") ==
               {:ok, ~o"{2026Y6M1D/5D,2026Y6M8D/12D}"}

      assert Tempo.difference(fortnight, [~o"{6,7}K", fourth_of_june]) ==
               {:ok, ~o"{2026-06-01/2026-06-03,2026-06-05/2026-06-05,2026-06-08/2026-06-12}"}
    end

    test "with no window, an operation whose answer has no first or last member needs one" do
      fortnight = ~o"2026-06-01/2026-06-14"
      weekend = ~o"{6,7}K"

      for {operation, a, b} <- [
            {:union, fortnight, weekend},
            {:union, weekend, fortnight},
            {:symmetric_difference, fortnight, weekend},
            {:difference, weekend, fortnight}
          ] do
        assert {:error, %Tempo.FrameError{reason: :needs_a_year}} =
                 apply(Tempo, operation, [a, b])
      end
    end

    test "with no window, it is placed on the stretch of every shape of operand with a year" do
      operands = [~o"6K", ~o"{6,7}K", ~o"12M25D", ~o"T09/T17", ~o"12M/2M"]

      # Each operand with a year, and its stretch, from its first day to its last.
      dated = [
        {~o"2026-06", ~o"2026-06"},
        {~o"2026-01-02/2026-03-31", ~o"2026-01-02/2026-03-31"},
        {~o"2026/2027", ~o"2026/2027"},
        {~o"{2026-01,2026-03}", ~o"2026-01/2026-03"}
      ]

      for {a, stretch} <- dated, b <- operands do
        assert Tempo.intersection(a, b) == Tempo.intersection(a, b, within: stretch),
               "intersection of #{inspect(a)} and #{inspect(b)}"

        assert Tempo.difference(a, b) == Tempo.difference(a, b, within: stretch),
               "difference of #{inspect(a)} and #{inspect(b)}"
      end
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
