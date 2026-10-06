defmodule Tempo.Iso8601.UnitTest do
  use ExUnit.Case, async: true

  # The order of a value's units, and the unit a walk of each steps on.
  #
  # The order is held to the units written out from the coarsest to the
  # finest, and what a walk steps on to the walk itself: the first value
  # `Enum` takes from a value of each resolution.

  alias Tempo.Iso8601.Unit

  doctest Tempo.Iso8601.Unit

  # From the coarsest to the finest. A month and a traditional month, and a
  # week and a calendar's own week, are of one scale.
  @coarsest_first [
    :century,
    :decade,
    :year,
    :month,
    :week,
    :day_of_year,
    :day,
    :day_of_week,
    :hour,
    :minute,
    :second,
    :microsecond
  ]

  defp pairs_in_order do
    for {coarser, index} <- Enum.with_index(@coarsest_first),
        finer <- Enum.drop(@coarsest_first, index + 1),
        do: {coarser, finer}
  end

  describe "compare/2" do
    test "orders the units from the coarsest to the finest" do
      for {coarser, finer} <- pairs_in_order() do
        assert {coarser, finer, Unit.compare(coarser, finer)} == {coarser, finer, :gt}
        assert {finer, coarser, Unit.compare(finer, coarser)} == {finer, coarser, :lt}
      end

      for unit <- @coarsest_first do
        assert {unit, Unit.compare(unit, unit)} == {unit, :eq}
      end
    end

    test "takes a unit with its value for the unit" do
      for {coarser, finer} <- pairs_in_order() do
        assert Unit.compare({coarser, 1}, {finer, 2}) == :gt
        assert Unit.compare({finer, 1}, coarser) == :lt
      end
    end

    test "holds the two kinds of month, and of week, to one scale" do
      assert Unit.compare(:month, :traditional_month) == :eq
      assert Unit.compare(:week, :calendar_week) == :eq
    end
  end

  describe "sort/2" do
    test "puts a value's units in order, either way" do
      in_order = Enum.map(@coarsest_first, &{&1, 1})

      every_other = Enum.take_every(in_order, 2)

      for out_of_order <- [Enum.reverse(in_order), every_other ++ (in_order -- every_other)] do
        assert Unit.sort(out_of_order) == in_order
        assert Unit.sort(out_of_order, :asc) == Enum.reverse(in_order)
      end
    end
  end

  describe "ordered?/1" do
    test "is true of units from the coarsest to the finest, and of no others" do
      for {coarser, finer} <- pairs_in_order() do
        assert {coarser, finer, Unit.ordered?([{coarser, 1}, {finer, 1}])} ==
                 {coarser, finer, true}

        assert {finer, coarser, Unit.ordered?([{finer, 1}, {coarser, 1}])} ==
                 {finer, coarser, false}

        assert {coarser, finer, Unit.ordered?([coarser, finer])} == {coarser, finer, true}
        assert {finer, coarser, Unit.ordered?([finer, coarser])} == {finer, coarser, false}
        assert {coarser, finer, Unit.ordered?([coarser, {finer, 1}])} == {coarser, finer, true}
        assert {finer, coarser, Unit.ordered?([finer, {coarser, 1}])} == {finer, coarser, false}
      end

      assert Unit.ordered?([])
      assert Unit.ordered?(year: 2026)
      refute Unit.ordered?(year: 2026, year: 2027)
    end

    test "is true of the weekdays of a selection and the position among them, in that order" do
      assert Unit.ordered?(day_of_week: 1, instance: 2)
      assert Unit.ordered?(day_of_week: 1, day_of_week: 3, day_of_week: 5, instance: -1)
      assert Unit.ordered?(month: 6, day_of_week: 1, day_of_week: 3)

      refute Unit.ordered?(instance: 2, day_of_week: 1)
      refute Unit.ordered?(day_of_week: 1, month: 6)
    end

    test "passes over what is no unit of the scale" do
      # The start of the week, what a rule does with a day a month lacks,
      # and a window.
      assert Unit.ordered?(month: 6, wkst: 7, day_of_week: 1)
      assert Unit.ordered?(month: 6, skip: :forward, day: 31)
      assert Unit.ordered?(month: 6, interval: :a_window, day: 15)

      refute Unit.ordered?(day: 31, skip: :forward, month: 6)
    end

    test "takes a group and a selection for the unit before them" do
      assert Unit.ordered?([:year, :group, :month])
      assert Unit.ordered?([:year, :select, :month])
      assert Unit.ordered?([{:year, 2026}, {:group, 1}, {:month, 6}])
      assert Unit.ordered?([{:year, 2026}, {:select, 1}, {:month, 6}])

      refute Unit.ordered?([:month, :group, :year])
      refute Unit.ordered?([{:month, 6}, {:select, 1}, {:year, 2026}])
    end

    test "orders an event as the day it is" do
      assert Unit.ordered?(month: 4, event: "easter", day_of_week: 5)
      refute Unit.ordered?(event: "easter", month: 4)
      refute Unit.ordered?(event: "easter", day: 1)
    end

    test "is false, and no raise, where a unit is not one" do
      refute Unit.ordered?(year: 2026, no_unit: 3)
      refute Unit.ordered?(no_unit: 3, day: 15)
    end
  end

  describe "implicit_enumerator/2 and walked_by/2" do
    # What a value of each resolution is walked by, in a calendar of months
    # and in a calendar of weeks.
    @walked [
      {"2026", Calendrical.Gregorian},
      {"2026-06", Calendrical.Gregorian},
      {"2026-06-15", Calendrical.Gregorian},
      {"2026-W25", Calendrical.Gregorian},
      {"2026-06-15T10", Calendrical.Gregorian},
      {"2026-06-15T10:30", Calendrical.Gregorian},
      {"T10", Calendrical.Gregorian},
      {"T10:30", Calendrical.Gregorian},
      {"2026", Calendrical.ISOWeek},
      {"2026-W25", Calendrical.ISOWeek},
      {"2026-W25-3", Calendrical.ISOWeek},
      {"2026Y25W3KT10H", Calendrical.ISOWeek}
    ]

    test "name the unit a walk of a value yields" do
      for {text, calendar} <- @walked do
        value = Tempo.from_iso8601!(text, calendar)
        {resolution, 1} = Tempo.resolution(value)
        {stepped_on, _values} = Unit.implicit_enumerator(resolution, calendar)

        [first] = Enum.take(value, 1)

        assert {text, calendar, Tempo.resolution(first)} ==
                 {text, calendar, {Unit.walked_by(stepped_on, calendar), 1}}
      end
    end

    test "name none for the finest unit, and for what is no unit" do
      assert Unit.implicit_enumerator(:second, Calendrical.Gregorian) == nil
      assert Unit.implicit_enumerator(:microsecond, Calendrical.Gregorian) == nil
      assert Unit.implicit_enumerator(:no_unit, Calendrical.Gregorian) == nil
    end
  end

  describe "value_range/2" do
    test "is the values of a unit whose extent no date changes" do
      assert Unit.value_range(:hour, Calendrical.Gregorian) == {:ok, 0..23}
      assert Unit.value_range(:second, Calendrical.Gregorian) == {:ok, 0..59}

      # A week has seven days in each of these.
      for calendar <- [Calendrical.Gregorian, Calendrical.ISOWeek, Calendrical.Hebrew] do
        assert {calendar, Unit.value_range(:day_of_week, calendar)} == {calendar, {:ok, 1..7}}
      end
    end

    test "is unknown for a unit whose extent depends on the date" do
      for unit <- [:month, :day, :week, :day_of_year] do
        assert {unit, Unit.value_range(unit, Calendrical.Gregorian)} == {unit, :unknown}
      end
    end
  end
end
