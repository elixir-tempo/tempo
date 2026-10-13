defmodule Tempo.Core.UnitTest do
  use ExUnit.Case, async: true

  alias Tempo.Unit

  test "units are of the calendar, of the clock, or labels of a date" do
    assert Enum.all?([:year, :month, :week, :day], &Unit.calendar?/1)
    assert Enum.all?([:hour, :minute, :second, :microsecond], &Unit.clock?/1)

    assert Enum.all?(
             [:day_of_week, :day_of_year, :quarter, :season, :traditional_month],
             &Unit.label?/1
           )

    refute Unit.label?(:day)
  end

  test "a label's grain is the unit enumerated to find it" do
    assert Unit.grain(:day_of_week) == :day
    assert Unit.grain(:quarter) == :month
    assert Unit.grain(:hour) == :hour
  end

  test "the order is coarsest first and compare follows it" do
    assert Unit.compare(:year, :month) == :lt
    assert Unit.compare(:second, :day) == :gt
    assert Unit.compare(:week, :week) == :eq

    assert Unit.order()
           |> Enum.chunk_every(2, 1, :discard)
           |> Enum.all?(fn [a, b] -> Unit.compare(a, b) == :lt end)
  end

  test "a value's resolution is its finest unit and its children one below" do
    units = [year: 2026, month: 6, day: 15, hour: 10]
    assert Unit.resolution(units) == :hour
    assert Unit.coarsest(units) == :year
    assert Unit.child(:hour) == :minute
    assert Unit.child(:microsecond) == nil
    assert Unit.anchored?(units)
    refute Unit.anchored?(month: 6, day: 15)
  end

  test "concrete units hold one value each" do
    assert Unit.concrete?(year: 2026, month: 6)
    assert Unit.concrete?(year: {1950, [significant: 2]})
    refute Unit.concrete?(year: 2026, month: [1, 3])
    refute Unit.concrete?(year: 2026, day: {:mask, [1, :x]})
  end

  test "date units come before the clock" do
    units = [year: 2026, month: 6, day: 15, hour: 10, minute: 30]
    assert Unit.date_units(units) == [year: 2026, month: 6, day: 15]
    assert Unit.clock_units(units) == [hour: 10, minute: 30]
  end

  test "a cycle runs from a unit down to a part of a second" do
    assert Unit.cycle_chain(:month) == [:month, :day, :hour, :minute, :second, :microsecond]
    assert Unit.cycle_chain(:hour) == [:hour, :minute, :second, :microsecond]
    assert Unit.minimum(:month) == 1
    assert Unit.minimum(:hour) == 0
  end
end
