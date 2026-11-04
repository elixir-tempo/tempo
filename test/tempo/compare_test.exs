defmodule Tempo.CompareTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # `Tempo.compare/3` orders by where two expressions begin and, by default,
  # by where they end when they begin together; `by: :start` compares where
  # they begin alone (decision 64), as a consumer ordering the starts of
  # sessions or a cutoff against a day does.

  import Tempo.Sigils

  alias Tempo.Order
  alias Tempo.Scale
  alias Tempo.Spans

  test "by default two that begin together are ordered by where they end" do
    assert Tempo.compare(~o"2026-06-15T00", ~o"2026-06-15") == :lt
    assert Tempo.compare(~o"2026-06-15", ~o"2026-06-15T00") == :gt

    assert Tempo.compare(
             ~o"2026-06-15T09:00/2026-06-15T10:00",
             ~o"2026-06-15T09:00/2026-06-15T11:00"
           ) ==
             :lt
  end

  test "by start, two that begin together are equal however long each is" do
    assert Tempo.compare(~o"2026-06-15T00", ~o"2026-06-15", by: :start) == :eq

    assert Tempo.compare(
             ~o"2026-06-15T09:00/2026-06-15T10:00",
             ~o"2026-06-15T09:00/2026-06-15T11:00",
             by: :start
           ) ==
             :eq

    assert Tempo.compare(~o"2026-06-15T09", ~o"2026-06-15T10", by: :start) == :lt
    assert Tempo.compare(~o"2026-06-16", ~o"2026-06-15T23", by: :start) == :gt
  end

  test "by start compares the moments where each begins across zones" do
    assert Tempo.compare(~o"2026-06-15T09:00Z", ~o"2026-06-15T10:00[Europe/London]", by: :start) ==
             :eq

    assert Tempo.compare(~o"2026-06-15T09:00Z", ~o"2026-06-15T11:00[Europe/Paris]", by: :start) ==
             :eq
  end

  test "a set is placed by its first span" do
    assert Tempo.compare(~o"{2026-06-15,2026-07-01}", ~o"2026-06-15T00", by: :start) == :eq
  end

  test "sorting by start keeps those that begin together in their order" do
    day = ~o"2026-06-15"
    hour = ~o"2026-06-15T00"
    sorter = fn a, b -> Tempo.compare(a, b, by: :start) != :gt end

    assert Enum.sort([day, ~o"2026-06-14", hour], sorter) == [~o"2026-06-14", day, hour]
  end

  test "what is compared is :start_and_end or :start" do
    assert_raise ArgumentError, ~r/:by is :start_and_end or :start/, fn ->
      Tempo.compare(~o"2026-06-15", ~o"2026-06-16", by: :end)
    end
  end

  # Two ISO values written from the year down are ordered by their units
  # (`Tempo.Order`), which must agree with placing each on the line. The
  # units are drawn from a few values each, a unit's first among them, so
  # that values beginning together, and one written as the other's prefix,
  # come up often.
  describe "two values ordered by their written units" do
    property "agree with the order of their extents" do
      check all(
              a <- written_value(),
              b <- written_value(),
              shift <- member_of([nil, [hour: 2]]),
              by <- member_of([:start_and_end, :start])
            ) do
        a = value(a, shift)
        b = value(b, shift)

        assert Order.compare(a, b, by) == placed_order(a, b, by)
        assert Tempo.compare(a, b, by: by) == placed_order(a, b, by)
      end
    end

    test "a value is the first of the coarser value it begins" do
      assert Tempo.compare(~o"2026-06-01", ~o"2026-06") == :lt
      assert Tempo.compare(~o"2026-06", ~o"2026-06-01T00") == :gt
      assert Tempo.compare(~o"2026-06-01T00", ~o"2026-06", by: :start) == :eq
      assert Tempo.compare(~o"2026-06-02", ~o"2026-06") == :gt
      assert Tempo.compare(~o"-0001-12-31", ~o"0000") == :lt
    end

    test "values it does not order are placed" do
      assert Order.compare(~o"2026-06-15[Europe/Paris]", ~o"2026-06-16", :start) ==
               :unordered

      assert Order.compare(~o"2026-06-15T09Z", ~o"2026-06-15T10+01:00", :start) ==
               :unordered

      assert Order.compare(~o"2026-W24", ~o"2026-06", :start) == :unordered
      assert Tempo.compare(~o"2026-W24", ~o"2026-06") == :gt
    end
  end

  defp written_value do
    gen all(
          year <- member_of([-1, 0, 2024, 2026]),
          depth <- integer(1..6),
          month <- member_of([1, 2, 12]),
          day <- member_of([1, 2, 28]),
          hour <- member_of([0, 1, 23]),
          minute <- member_of([0, 59]),
          second <- member_of([0, 30])
        ) do
      Enum.take(
        [year: year, month: month, day: day, hour: hour, minute: minute, second: second],
        depth
      )
    end
  end

  defp value(units, nil) do
    Tempo.new!(units)
  end

  defp value(units, shift) do
    Tempo.new!(units ++ [shift: shift])
  end

  defp placed_order(a, b, by) do
    {:ok, {a_start, a_stop}} = Spans.extent(a)
    {:ok, {b_start, b_stop}} = Spans.extent(b)

    if by == :start or a_start != b_start do
      Scale.compare(a_start, b_start)
    else
      Scale.compare(a_stop, b_stop)
    end
  end
end
