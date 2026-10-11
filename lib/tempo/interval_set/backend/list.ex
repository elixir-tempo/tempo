defmodule Tempo.IntervalSet.Backend.List do
  @moduledoc """
  The default `Tempo.IntervalSet.Backend`: a sorted, disjoint plain
  list of member intervals.

  The backend state is the member list itself, so a struct literal
  `%Tempo.IntervalSet{intervals: [...]}` is a valid list-backed set and
  two list-backed sets with the same members compare equal with `==`.
  Construction is O(n log n) (the sort in `Tempo.IntervalSet.new/2`),
  the walk is the list, and every query is a linear scan — the right
  trade for the small-to-medium sets that dominate ordinary use.

  """

  use Tempo.IntervalSet.Backend

  @impl true
  def from_list(intervals, _options) do
    intervals
  end

  @impl true
  def to_list(state) do
    state
  end

  @impl true
  def walk(state) do
    state
  end

  @impl true
  def bounded?(_state) do
    true
  end

  @impl true
  def count(state) do
    length(state)
  end

  @impl true
  def empty?(state) do
    state == []
  end

  @impl true
  def first([]) do
    nil
  end

  def first([first | _rest]) do
    first
  end
end
