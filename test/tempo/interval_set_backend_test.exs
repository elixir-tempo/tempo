defmodule Tempo.IntervalSetBackendTest do
  @moduledoc """
  The `Tempo.IntervalSet.Backend` contract: dispatch through the
  behaviour, the list backend as reference, and `use`-provided
  defaults on a minimal custom backend.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  defmodule TupleBackend do
    @moduledoc false
    # A deliberately minimal backend: state is `{:tuple, members}`.
    # Implements only the required callbacks, so `count/1`,
    # `empty?/1`, and `first/1` exercise the `use`-provided defaults.
    use Tempo.IntervalSet.Backend

    @impl true
    def from_list(intervals, _options), do: {:tuple, intervals}

    @impl true
    def to_list({:tuple, intervals}), do: intervals

    @impl true
    def walk({:tuple, intervals}), do: intervals

    @impl true
    def bounded?(_state), do: true
  end

  defp members do
    [
      %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"},
      %Tempo.Interval{from: ~o"2026-07-01", to: ~o"2026-07-10"}
    ]
  end

  describe "the default list backend" do
    test "a struct literal is a valid list-backed set" do
      set = %IntervalSet{intervals: members()}
      assert set.backend == IntervalSet.Backend.List
      assert IntervalSet.count(set) == 2
    end

    test "new/2 accepts the :list shorthand" do
      {:ok, set} = IntervalSet.new(members(), backend: :list)
      assert set.backend == IntervalSet.Backend.List
    end

    test "walk/1 yields the members in time order" do
      {:ok, set} = IntervalSet.new(Enum.reverse(members()))
      assert set |> IntervalSet.walk() |> Enum.map(& &1.from.time[:month]) == [6, 7]
    end
  end

  describe "a custom backend" do
    test "new/2 builds state through from_list/2" do
      {:ok, set} = IntervalSet.new(members(), backend: TupleBackend)
      assert set.backend == TupleBackend
      assert {:tuple, _} = set.intervals
    end

    test "accessors dispatch through the backend" do
      {:ok, set} = IntervalSet.new(members(), backend: TupleBackend)

      assert IntervalSet.count(set) == 2
      refute IntervalSet.empty?(set)
      assert IntervalSet.first(set).from.time[:month] == 6
      assert set |> IntervalSet.walk() |> Enum.count() == 2
      assert IntervalSet.count(set) == 2
    end

    test "the use-provided defaults answer over the walk" do
      {:ok, empty} = IntervalSet.new([], backend: TupleBackend)

      assert IntervalSet.empty?(empty)
      assert IntervalSet.count(empty) == 0
      assert IntervalSet.first(empty) == nil
    end

    test "member-preserving rewrites keep the backend" do
      {:ok, set} = IntervalSet.new(members(), backend: TupleBackend)

      filtered = IntervalSet.filter(set, &(&1.from.time[:month] == 6))
      assert filtered.backend == TupleBackend
      assert IntervalSet.count(filtered) == 1

      coalesced = IntervalSet.coalesce(set)
      assert coalesced.backend == TupleBackend
    end

    test "covered? and duration work through the contract" do
      {:ok, set} = IntervalSet.new(members(), backend: TupleBackend)

      assert IntervalSet.covered?(set, ~o"2026-06-05")
      refute IntervalSet.covered?(set, ~o"2026-06-20")
    end

    test "results agree with the list backend on the same members" do
      {:ok, tuple_set} = IntervalSet.new(members(), backend: TupleBackend)
      {:ok, list_set} = IntervalSet.new(members())

      assert IntervalSet.members(tuple_set) == IntervalSet.members(list_set)
      assert IntervalSet.count(tuple_set) == IntervalSet.count(list_set)
      assert Enum.to_list(tuple_set) == Enum.to_list(list_set)
    end
  end
end
