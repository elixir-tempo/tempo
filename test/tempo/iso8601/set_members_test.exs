defmodule Tempo.Iso8601.SetMembersTest do
  @moduledoc """
  The members of a set written for one unit (`{28..30,-1}D`) are put in a
  normal form when the set is read: in order, neighbours joined into ranges
  and none twice. The form must name the values the set was written with,
  which `Tempo.UnitValues.named/2` lists from either.

  The joining took a count from the end for a number beside the others, so
  `{-1,0}` became the range from the last to the first, which names nothing,
  and it took a list with a negative member to be in ascending order, so
  `{28..30,-1}` lost its last day.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Tempo.Sigils

  alias Tempo.IntervalSet
  alias Tempo.Iso8601.Parser
  alias Tempo.UnitValues

  # A number or a range, from either end, the range by any step.
  defp members do
    number = integer(-40..40)

    range =
      gen all(first <- number, last <- number, step <- member_of([1, 2, 3, -1])) do
        first..last//step
      end

    list_of(one_of([number, range]), max_length: 6)
  end

  defp values do
    gen all(first <- member_of([0, 1]), last <- integer(0..40)) do
      first..last//1
    end
  end

  describe "consolidate_ranges/1" do
    property "names the values the members name, whatever values the unit takes" do
      check all(members <- members(), values <- values()) do
        assert UnitValues.named(Parser.consolidate_ranges(members), values) ==
                 UnitValues.named(members, values)
      end
    end

    property "has nothing left to join once it is done" do
      check all(members <- members()) do
        consolidated = Parser.consolidate_ranges(members)
        assert Parser.consolidate_ranges(consolidated) == consolidated
      end
    end

    # One pass left `0` beside `1..7`, which run on from one another, where
    # a member between them was written out of order.
    test "joins members a member written out of order had kept apart" do
      assert Parser.consolidate_ranges([0, 2, 1..7]) == [0..7]
      assert Parser.consolidate_ranges([0, 2, 1..7, -1]) == [0..7, -1]
    end

    test "joins neighbours that count from one end" do
      assert Parser.consolidate_ranges([1, 2, 3]) == [1..3]
      assert Parser.consolidate_ranges([-2, -1]) == [-2..-1]
      assert Parser.consolidate_ranges([1..3, 4..6]) == [1..6]
      assert Parser.consolidate_ranges([1..10, 2..3, 11]) == [1..11]
    end

    test "does not join the last to the first" do
      assert Parser.consolidate_ranges([-1, 0]) == [-1, 0]
      assert Parser.consolidate_ranges([-1, 0, 1]) == [-1, 0..1]
    end

    test "keeps a member it cannot see another holds" do
      assert Parser.consolidate_ranges([28..30, -1]) == [28..30, -1]
      assert Parser.consolidate_ranges([1..5, -3..-1]) == [1..5, -3..-1]
      assert Parser.consolidate_ranges([-5..-3, -9]) == [-5..-3, -9]
    end

    test "does not run a stepped range on into its neighbour" do
      assert Parser.consolidate_ranges([1..9//2, 10]) == [1..9//2, 10]
      assert Parser.consolidate_ranges([0, 1..9//2]) == [0, 1..9//2]
    end
  end

  describe "a set that holds a count from the end" do
    test "keeps the last beside the first" do
      assert ~o"2026Y6M15DT{-1,0}H" == ~o"2026Y6M15DT{0,23}H"
      assert Enum.map(~o"2026Y6M15DT{-1,0}H", &Tempo.hour/1) == [0, 23]
    end

    test "keeps the last after a range" do
      assert ~o"2026Y1M{28..30,-1}D" == ~o"2026Y1M{28..31}D"
      assert Enum.map(~o"2026Y6M{5..10,-1}D", &Tempo.day/1) == [5, 6, 7, 8, 9, 10, 30]
    end

    test "keeps a range from the end after one from the start" do
      assert Enum.map(~o"2026Y6M{1..5,-3..-1}D", &Tempo.day/1) == [1, 2, 3, 4, 5, 28, 29, 30]
    end

    test "is the set of its numbers, in order and with none twice" do
      assert ~o"2026Y6M{-1,1}D" == ~o"2026Y6M{1,30}D"
      assert ~o"2026Y6M{30,-1}D" == ~o"2026Y6M30D"
      assert ~o"2026Y25W{-1,1}K" == ~o"2026Y25W{1,7}K"
    end

    test "is counted in each year it is read in" do
      assert Enum.to_list(~o"{2026,2028}Y2M{28,-1}D") ==
               [~o"2026Y2M28D", ~o"2028Y2M28D", ~o"2028Y2M29D"]
    end

    test "reads back from its own text" do
      for text <- ~w(2026Y6M15DT{-1,0}H 2026Y1M{28..30,-1}D 2026Y6M{-1,1}D 2M{-1,1}D) do
        value = Tempo.from_iso8601!(text)
        assert Tempo.from_iso8601!(Tempo.to_iso8601!(value)) == value, text
      end
    end
  end

  describe "a stepped range in a set" do
    test "keeps its own steps beside its neighbour" do
      assert Enum.map(~o"2026Y6M{1..9//2,10}D", &Tempo.day/1) == [1, 3, 5, 7, 9, 10]
    end
  end

  describe "a set of years" do
    test "is in order whatever the signs of its years" do
      assert ~o"{2020,-3}Y" == ~o"{-3,2020}Y"
      assert Enum.to_list(~o"{2020,-3}Y") == [~o"-3Y", ~o"2020Y"]
    end
  end

  describe "a range of years before the era" do
    # A year below zero is a year before year 1 (ISO 8601-2 §4.4.1), never a
    # count from the end, so a range of them is each of its years. The walk
    # took a negative end of a range for a count from the end and refused to
    # list it.
    defp years(value), do: Enum.map(value, &Tempo.year/1)

    test "is each of its years" do
      for {text, expected} <- [
            {"{-5..-3}Y", -5..-3//1},
            {"{-3..2}Y", -3..2//1},
            {"{-1..1}Y", -1..1//1},
            {"{-9..-1//4}Y", -9..-1//4},
            {"{-0005..-0003}", -5..-3//1}
          ] do
        value = Tempo.from_iso8601!(text)

        assert {text, years(value)} == {text, Enum.to_list(expected)}
        assert {text, Enum.count(value)} == {text, Range.size(expected)}
      end
    end

    test "is each of its years beside another member, and under finer units" do
      assert years(~o"{-5..-3,10}Y") == [-5, -4, -3, 10]

      assert Enum.to_list(~o"{-5..-3}Y6M15D") == [~o"-5Y6M15D", ~o"-4Y6M15D", ~o"-3Y6M15D"]

      assert Enum.to_list(~o"{-2..-1}Y{1,2}M") ==
               [~o"-2Y1M", ~o"-2Y2M", ~o"-1Y1M", ~o"-1Y2M"]
    end

    test "converts to the span of each year" do
      {:ok, set} = Tempo.to_interval(~o"{-5..-3}Y")

      assert Enum.map(IntervalSet.members(set), &Tempo.to_iso8601!/1) ==
               ["-5Y/-4Y", "-4Y/-3Y", "-3Y/-2Y"]
    end

    test "a count from the end of another unit is still counted" do
      assert Enum.to_list(~o"-5Y{-2..-1}M") == [~o"-5Y11M", ~o"-5Y12M"]
    end
  end
end
