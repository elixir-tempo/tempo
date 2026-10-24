defmodule Tempo.PlacedTest do
  use ExUnit.Case, async: true

  # The engine hands a span on with its place (`Tempo.Placed`, decision 74).
  # Two defects the change found and fixed are held here: a sequence that
  # ends with a member (a recurrence with a count) lost that member where
  # it was merged with another, and a recurrence whose start names several
  # values gave the first span's values and no repeat of them.

  import Tempo.Sigils

  alias Tempo.{Placed, Spans}

  test "a placed span carries the extent its span has" do
    {:ok, [placed]} = Spans.placed(~o"2026-06-15")
    assert %Placed{span: ~o"2026Y6M15D/15D"} = placed
    assert {:ok, Placed.extent(placed)} == Spans.extent(placed.span)
    assert Placed.bounded?(placed)
  end

  test "a span with an open end is placed with no position at that end" do
    {:ok, [placed]} = Spans.placed(~o"2026-06-15/..")
    assert is_integer(placed.start)
    assert is_nil(placed.stop)
    refute Placed.bounded?(placed)
  end

  test "a set keeps the last occurrence of a counted member beside another member" do
    {:ok, spans} = Spans.spans(~o"{R3/2026-06-01/P1M,2027}")

    assert Enum.to_list(spans) == [
             ~o"2026Y6M1D/30D",
             ~o"2026Y7M1D/31D",
             ~o"2026Y8M1D/31D",
             ~o"2027Y/2027Y"
           ]
  end

  test "a recurrence whose start names several values is each value's series, in time order" do
    assert Enum.to_list(~o"R3/2026Y6M{1,15}D/P1M") == [
             ~o"2026Y6M1D/30D",
             ~o"2026Y6M15D/7M14D",
             ~o"2026Y7M1D/31D",
             ~o"2026Y7M15D/8M14D",
             ~o"2026Y8M1D/31D",
             ~o"2026Y8M15D/9M14D"
           ]
  end

  # A rule's periods are the cadence's whole periods from the one the start
  # is in, so a start that names several values of one period names it.
  test "a rule from a start that names several values selects in the period the start is in" do
    assert Tempo.to_interval(~o"R3/2026Y6M{1,15}D/P1M/FL1KN") ==
             {:ok, ~o"{2026Y6M1D/2026Y6M1D,2026Y6M8D/2026Y6M8D,2026Y6M15D/2026Y6M15D}"}
  end
end
