defmodule Tempo.IntervalSet.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Interval

  doctest Tempo.IntervalSet

  # `%Tempo.IntervalSet{}` is the multi-interval value. The tests
  # below cover the constructor invariants (sort + coalesce),
  # the Enumerable protocol (walks each interval in time order),
  # and error cases (open-ended inputs).

  describe "new/1 — sort and coalesce" do
    test "separate non-touching intervals remain separate, in sorted order" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      may = interval(~o"2022Y5M")

      {:ok, set} = Tempo.IntervalSet.new([may, jan, mar])

      assert length(set.intervals) == 3

      assert Enum.map(set.intervals, & &1.from.time) == [
               [year: 2022, month: 1],
               [year: 2022, month: 3],
               [year: 2022, month: 5]
             ]
    end

    test "touching intervals stay as distinct members (member-preserving default)" do
      jan = interval(~o"2022Y1M")
      feb = interval(~o"2022Y2M")

      {:ok, set} = Tempo.IntervalSet.new([jan, feb])
      assert length(set.intervals) == 2

      # Explicit coalescing merges touching members under the
      # half-open convention: `[Jan, Feb) ++ [Feb, Mar)` = `[Jan, Mar)`.
      coalesced = Tempo.IntervalSet.coalesce(set)
      assert length(coalesced.intervals) == 1
      [interval] = coalesced.intervals
      assert interval.from.time == [year: 2022, month: 1]
      assert interval.to.time == [year: 2022, month: 3]
    end

    test "overlapping intervals stay distinct by default; coalesce to merge" do
      jan = interval(~o"2022Y1M")
      q1 = %Tempo.Interval{from: ~o"2022Y1M15D", to: ~o"2022Y3M15D"}

      {:ok, set} = Tempo.IntervalSet.new([jan, q1])
      assert length(set.intervals) == 2

      coalesced = Tempo.IntervalSet.coalesce(set)
      assert length(coalesced.intervals) == 1
      [interval] = coalesced.intervals
      assert interval.from.time == [year: 2022, month: 1]
      assert interval.to.time == [year: 2022, month: 3, day: 15]
    end

    test "three touching intervals — distinct by default; coalesce to one" do
      {:ok, tempo} = Tempo.from_iso8601("{2020,2021,2022}Y")
      {:ok, %Tempo.IntervalSet{intervals: intervals} = set} = Tempo.to_interval(tempo)

      # Three separate year members.
      assert length(intervals) == 3

      # Coalesced: touching years merge into a single 3-year span.
      coalesced = Tempo.IntervalSet.coalesce(set)
      assert length(coalesced.intervals) == 1
    end

    test "empty list yields an empty set" do
      assert {:ok, %Tempo.IntervalSet{intervals: []}} = Tempo.IntervalSet.new([])
    end

    test "rejects open-ended intervals" do
      {:ok, open} = Tempo.from_iso8601("1985/..")
      assert {:error, message} = Tempo.IntervalSet.new([open])
      assert Exception.message(message) =~ "open-ended"
    end
  end

  describe "new!/1" do
    test "raises on open-ended input" do
      {:ok, open} = Tempo.from_iso8601("../1985")

      assert_raise ArgumentError, fn ->
        Tempo.IntervalSet.new!([open])
      end
    end

    test "returns the set directly on success" do
      assert %Tempo.IntervalSet{} = Tempo.IntervalSet.new!([interval(~o"2022Y1M")])
    end
  end

  describe "Enumerable protocol — walks sub-points" do
    # An IntervalSet's Enumerable is consistent with Tempo and
    # Tempo.Interval: iterating walks the sub-points at the
    # next-finer resolution, not the member intervals
    # themselves. For member-interval iteration use
    # `Tempo.IntervalSet.to_list/1`.

    test "iterates each interval's values in time order" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      list = Enum.take(set, 35)
      # First 31 days = Jan. Day 32 must be Mar 1 (crossing the
      # non-touching boundary skips Feb entirely).
      assert length(list) == 35
      assert Enum.at(list, 0).time == [year: 2022, month: 1, day: 1]
      assert Enum.at(list, 30).time == [year: 2022, month: 1, day: 31]
      assert Enum.at(list, 31).time == [year: 2022, month: 3, day: 1]
    end

    test "Enum.to_list yields the full sequence" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      # Jan (31 days) + Mar (31 days) = 62.
      assert length(Enum.to_list(set)) == 62
    end

    test "halt during iteration works" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      # `Enum.find/2` halts as soon as the predicate matches.
      found = Enum.find(set, fn v -> v.time[:day] == 15 end)
      assert found.time == [year: 2022, month: 1, day: 15]
    end

    test "count/member?/slice return {:error, __MODULE__}" do
      {:ok, set} = Tempo.IntervalSet.new([interval(~o"2022Y1M")])
      assert Enumerable.count(set) == {:error, Enumerable.Tempo.IntervalSet}
      assert Enumerable.member?(set, :anything) == {:error, Enumerable.Tempo.IntervalSet}
      assert Enumerable.slice(set) == {:error, Enumerable.Tempo.IntervalSet}
    end
  end

  describe "to_list/1 — member intervals as a plain list" do
    test "returns the constituent %Tempo.Interval{} values" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      assert [a, b] = Tempo.IntervalSet.to_list(set)
      assert %Tempo.Interval{} = a
      assert a.from.time == [year: 2022, month: 1]
      assert b.from.time == [year: 2022, month: 3]
    end

    test "pipes into Enum for member-level filtering" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      long_enough =
        set
        |> Tempo.IntervalSet.to_list()
        |> Enum.filter(&Tempo.at_least?(&1, ~o"P28D"))

      assert length(long_enough) == 2
    end

    test "empty set → empty list" do
      {:ok, set} = Tempo.IntervalSet.new([])
      assert Tempo.IntervalSet.to_list(set) == []
    end
  end

  describe "count/1" do
    test "returns the number of member intervals" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      may = interval(~o"2022Y5M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar, may])

      assert Tempo.IntervalSet.count(set) == 3
    end

    test "returns 0 for an empty set" do
      {:ok, set} = Tempo.IntervalSet.new([])
      assert Tempo.IntervalSet.count(set) == 0
    end
  end

  describe "first/1 and last/1" do
    test "first/1 is the earliest member and last/1 the latest, in time order not input order" do
      {:ok, set} =
        Tempo.IntervalSet.new([
          interval(~o"2022Y5M"),
          interval(~o"2022Y1M"),
          interval(~o"2022Y3M")
        ])

      assert Tempo.month(Tempo.IntervalSet.first(set)) == 1
      assert Tempo.month(Tempo.IntervalSet.last(set)) == 5
    end

    test "both return nil for an empty set" do
      {:ok, set} = Tempo.IntervalSet.new([])
      assert Tempo.IntervalSet.first(set) == nil
      assert Tempo.IntervalSet.last(set) == nil
    end
  end

  describe "map/2" do
    test "applies the mapper to each member interval" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      assert Tempo.IntervalSet.map(set, &Tempo.month/1) == [1, 3]
    end

    test "mappers can return arbitrary values (not just intervals)" do
      jan = interval(~o"2022Y1M")
      feb = interval(~o"2022Y4M")
      {:ok, set} = Tempo.IntervalSet.new([jan, feb])

      result = Tempo.IntervalSet.map(set, fn iv -> {Tempo.year(iv), Tempo.month(iv)} end)
      assert result == [{2022, 1}, {2022, 4}]
    end

    test "empty set maps to empty list" do
      {:ok, set} = Tempo.IntervalSet.new([])
      assert Tempo.IntervalSet.map(set, & &1) == []
    end
  end

  describe "filter/2" do
    test "keeps only members where the predicate returns truthy" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      only_january = Tempo.IntervalSet.filter(set, &(Tempo.month(&1) == 1))

      assert Tempo.IntervalSet.count(only_january) == 1
      [only] = Tempo.IntervalSet.to_list(only_january)
      assert Tempo.month(only) == 1
    end

    test "returns an IntervalSet, not a plain list" do
      jan = interval(~o"2022Y1M")
      {:ok, set} = Tempo.IntervalSet.new([jan])

      assert %Tempo.IntervalSet{} = Tempo.IntervalSet.filter(set, fn _ -> true end)
    end

    test "filtering to empty still returns an IntervalSet" do
      jan = interval(~o"2022Y1M")
      {:ok, set} = Tempo.IntervalSet.new([jan])

      empty = Tempo.IntervalSet.filter(set, fn _ -> false end)
      assert %Tempo.IntervalSet{} = empty
      assert Tempo.IntervalSet.count(empty) == 0
    end
  end

  describe "to_interval/1 routing — multi-interval shapes" do
    test "range in a time slot → IntervalSet with distinct members (coalesce to merge)" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y{1..3}M")
      {:ok, set} = Tempo.to_interval(tempo)

      # Three separate month members by default.
      assert length(set.intervals) == 3

      # Explicit coalesce merges the touching months into one span.
      coalesced = Tempo.IntervalSet.coalesce(set)
      assert length(coalesced.intervals) == 1
      [q1] = coalesced.intervals
      assert q1.from.time == [year: 2022, month: 1]
      assert q1.to.time == [year: 2022, month: 4]
    end

    test "stepped range → multiple disjoint intervals" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y{1..-1//3}M")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(tempo)
      assert length(intervals) == 4
      assert Enum.map(intervals, & &1.from.time[:month]) == [1, 4, 7, 10]
    end

    test "cartesian range expansion — distinct members by default" do
      # `{1..2}M{1..2}D` gives four point-members: Jan 1, Jan 2,
      # Feb 1, Feb 2. All are distinct under member-preserving
      # semantics; `coalesce/1` merges touching pairs.
      {:ok, tempo} = Tempo.from_iso8601("2022Y{1..2}M{1..2}D")
      {:ok, set} = Tempo.to_interval(tempo)
      assert length(set.intervals) == 4

      coalesced = Tempo.IntervalSet.coalesce(set)
      # Jan 1 + Jan 2 touch → merged; Feb 1 + Feb 2 touch → merged;
      # gap between Jan 3 and Feb 1 → stays two spans.
      assert length(coalesced.intervals) == 2
    end

    test "scalar input still returns a single Interval" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y6M")
      assert {:ok, %Tempo.Interval{}} = Tempo.to_interval(tempo)
    end
  end

  describe "to_interval_set/1" do
    test "wraps a single interval in a 1-element set" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y6M")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval_set(tempo)
      assert length(intervals) == 1
    end

    test "passes IntervalSet through unchanged" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y{1..-1//3}M")
      {:ok, set} = Tempo.to_interval_set(tempo)
      assert length(set.intervals) == 4

      assert {:ok, ^set} = Tempo.to_interval_set(set)
    end

    test "errors on a bare Duration" do
      {:ok, duration} = Tempo.from_iso8601("P3M")
      assert {:error, _} = Tempo.to_interval_set(duration)
    end

    test "errors on a one-of Tempo.Set (epistemic)" do
      {:ok, set} = Tempo.from_iso8601("[2020Y,2021Y,2022Y]")
      assert {:error, message} = Tempo.to_interval_set(set)
      assert Exception.message(message) =~ "epistemic"
    end
  end

  describe "overlapping/2" do
    defp at(from, to) do
      Interval.new!(
        from: Tempo.from_iso8601!("2026-06-15T#{from}:00:00"),
        to: Tempo.from_iso8601!("2026-06-15T#{to}:00:00")
      )
    end

    defp spans(set) do
      set |> Tempo.IntervalSet.to_list() |> Enum.map(&Tempo.to_iso8601/1)
    end

    test "at_least: 1 is the covered region" do
      set = Tempo.IntervalSet.new!([at("09", "11"), at("10", "12")])

      assert spans(Tempo.IntervalSet.overlapping(set, at_least: 1)) ==
               spans(Tempo.IntervalSet.coalesce(set))
    end

    test "at_least: 2 keeps only the doubled part" do
      set = Tempo.IntervalSet.new!([at("09", "12"), at("11", "14")])

      assert spans(Tempo.IntervalSet.overlapping(set, at_least: 2)) ==
               ["2026Y6M15DT11H0M0S/2026Y6M15DT12H0M0S"]
    end

    test "a threshold no member reaches yields nothing" do
      set = Tempo.IntervalSet.new!([at("09", "10"), at("11", "12")])

      assert Tempo.IntervalSet.overlapping(set, at_least: 2) |> Tempo.IntervalSet.empty?()
    end

    test "members that merely meet never count as overlapping" do
      set = Tempo.IntervalSet.new!([at("09", "10"), at("10", "11"), at("11", "12")])

      assert Tempo.IntervalSet.overlapping(set, at_least: 2) |> Tempo.IntervalSet.empty?()
    end

    test "depth is tracked across three members" do
      set = Tempo.IntervalSet.new!([at("09", "14"), at("10", "13"), at("11", "12")])

      assert spans(Tempo.IntervalSet.overlapping(set, at_least: 3)) ==
               ["2026Y6M15DT11H0M0S/2026Y6M15DT12H0M0S"]

      assert spans(Tempo.IntervalSet.overlapping(set, at_least: 2)) ==
               ["2026Y6M15DT10H0M0S/2026Y6M15DT13H0M0S"]
    end

    test "several separate regions can reach the threshold" do
      set =
        Tempo.IntervalSet.new!([
          at("09", "11"),
          at("10", "12"),
          at("14", "16"),
          at("15", "17")
        ])

      assert spans(Tempo.IntervalSet.overlapping(set, at_least: 2)) == [
               "2026Y6M15DT10H0M0S/2026Y6M15DT11H0M0S",
               "2026Y6M15DT15H0M0S/2026Y6M15DT16H0M0S"
             ]
    end

    test "raising the threshold never widens the result" do
      set =
        Tempo.IntervalSet.new!([at("09", "14"), at("10", "13"), at("11", "12"), at("09", "17")])

      widths =
        for depth <- 1..4 do
          set
          |> Tempo.IntervalSet.overlapping(at_least: depth)
          |> Tempo.IntervalSet.total_duration()
          |> Map.get(:time)
          |> Keyword.get(:second)
        end

      assert widths == Enum.sort(widths, :desc)
    end

    test "an empty set has no overlap at any depth" do
      set = Tempo.IntervalSet.new!([])

      assert Tempo.IntervalSet.overlapping(set, at_least: 1) |> Tempo.IntervalSet.empty?()
    end
  end

  describe "slots/3 metadata" do
    test "every slot carries the metadata of the member it was cut from" do
      work =
        Interval.new!(
          from: ~o"2026-06-15T09:00:00",
          to: ~o"2026-06-15T12:00:00",
          metadata: %{resource: "Boardroom"}
        )

      metadata =
        work
        |> Tempo.IntervalSet.slots(~o"PT1H")
        |> Tempo.IntervalSet.to_list()
        |> Enum.map(&Interval.metadata/1)

      assert metadata == List.duplicate(%{resource: "Boardroom"}, 3)
    end

    test "each member's slots carry that member's own metadata" do
      set =
        Tempo.IntervalSet.new!([
          Interval.new!(
            from: ~o"2026-06-15T09:00:00",
            to: ~o"2026-06-15T10:00:00",
            metadata: %{resource: "Boardroom"}
          ),
          Interval.new!(
            from: ~o"2026-06-15T14:00:00",
            to: ~o"2026-06-15T15:00:00",
            metadata: %{resource: "Annexe"}
          )
        ])

      metadata =
        set
        |> Tempo.IntervalSet.slots(~o"PT1H")
        |> Tempo.IntervalSet.to_list()
        |> Enum.map(&Interval.metadata/1)

      assert metadata == [%{resource: "Boardroom"}, %{resource: "Annexe"}]
    end

    test "a member with no metadata still yields slots with none" do
      work = ~o"2026-06-15T09:00:00/2026-06-15T11:00:00"

      metadata =
        work
        |> Tempo.IntervalSet.slots(~o"PT1H")
        |> Tempo.IntervalSet.to_list()
        |> Enum.map(&Interval.metadata/1)

      assert metadata == [%{}, %{}]
    end
  end

  describe "slots/3" do
    test "cuts a single interval into back-to-back fixed-length slots" do
      work = ~o"2026-06-15T09:00:00/2026-06-15T12:00:00"
      slots = Tempo.IntervalSet.slots(work, ~o"PT1H")

      assert Tempo.IntervalSet.count(slots) == 3

      assert slots |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:hour]) ==
               [9, 10, 11]
    end

    test "slots stay distinct (back-to-back, not coalesced)" do
      work = ~o"2026-06-15T09:00:00/2026-06-15T11:00:00"
      slots = Tempo.IntervalSet.slots(work, ~o"PT1H")

      assert Tempo.IntervalSet.count(slots) == 2
      [first, second] = Tempo.IntervalSet.to_list(slots)
      assert first.to.time == second.from.time
    end

    test ":every spaces overlapping slots" do
      work = ~o"2026-06-15T09:00:00/2026-06-15T12:00:00"
      slots = Tempo.IntervalSet.slots(work, ~o"PT1H", every: ~o"PT30M")

      # 09:00, 09:30, 10:00, 10:30, 11:00 — each a 1-hour slot inside [09, 12).
      assert Tempo.IntervalSet.count(slots) == 5
    end

    test "a partial tail that does not fit is dropped" do
      # [09:00, 10:40) holds one 1-hour slot; the 10:00–11:00 slot overflows.
      work = ~o"2026-06-15T09:00:00/2026-06-15T10:40:00"
      assert Tempo.IntervalSet.count(Tempo.IntervalSet.slots(work, ~o"PT1H")) == 1
    end

    test "slots each member of a set independently" do
      mutual =
        Tempo.IntervalSet.new!([
          ~o"2026-06-15T11:00:00/2026-06-15T14:00:00",
          ~o"2026-06-15T15:00:00/2026-06-15T16:30:00"
        ])

      slots = Tempo.IntervalSet.slots(mutual, ~o"PT1H")

      # 11–12, 12–13, 13–14 from the first window; 15–16 from the second
      # (16–17 would overflow its 16:30 end).
      assert Tempo.IntervalSet.count(slots) == 4
    end

    test "a window shorter than the slot yields nothing" do
      work = ~o"2026-06-15T09:00:00/2026-06-15T09:30:00"
      assert Tempo.IntervalSet.count(Tempo.IntervalSet.slots(work, ~o"PT1H")) == 0
    end
  end

  ## Helpers

  defp interval(tempo) do
    {:ok, interval} = Tempo.to_interval(tempo)
    interval
  end

  describe "members/1" do
    test "returns the member intervals, not the points inside them" do
      {:ok, set} =
        Tempo.IntervalSet.new([
          ~o"2026-06-15T09:00:00/2026-06-15T12:00:00",
          ~o"2026-06-15T13:00:00/2026-06-15T17:00:00"
        ])

      assert [%Interval{}, %Interval{}] = Tempo.IntervalSet.members(set)
      assert length(Tempo.IntervalSet.members(set)) == 2
    end

    test "and that is a different answer from Enum" do
      # The trap the name exists to avoid: `Enum` walks every second
      # in the set, which is seven hours' worth.
      {:ok, set} =
        Tempo.IntervalSet.new([
          ~o"2026-06-15T09:00:00/2026-06-15T12:00:00",
          ~o"2026-06-15T13:00:00/2026-06-15T17:00:00"
        ])

      assert length(Tempo.IntervalSet.members(set)) == 2
      assert Enum.count(set) == 25_200
    end

    test "the two agree at day resolution, which is why the trap hides" do
      {:ok, set} = Tempo.select(~o"2026-08-10/2026-08-15", Tempo.workdays(:AU))

      assert length(Tempo.IntervalSet.members(set)) == 5
      assert Enum.count(set) == 5
    end

    test "is exactly to_list/1" do
      {:ok, set} =
        Tempo.IntervalSet.new([
          ~o"2026-06-01/2026-06-10",
          ~o"2026-07-01/2026-07-10"
        ])

      assert Tempo.IntervalSet.members(set) == Tempo.IntervalSet.to_list(set)
    end

    test "agrees with count/1" do
      {:ok, set} =
        Tempo.IntervalSet.new([
          ~o"2026-06-01/2026-06-10",
          ~o"2026-07-01/2026-07-10"
        ])

      assert length(Tempo.IntervalSet.members(set)) == Tempo.IntervalSet.count(set)
    end

    test "an empty set has no members" do
      assert Tempo.IntervalSet.members(Tempo.IntervalSet.new!([])) == []
    end

    test "members are in time order" do
      {:ok, set} =
        Tempo.IntervalSet.new([
          ~o"2026-07-01/2026-07-10",
          ~o"2026-06-01/2026-06-10"
        ])

      assert [first, second] = Tempo.IntervalSet.members(set)
      assert Tempo.compare(Interval.from(first), Interval.from(second)) == :lt
    end
  end
end
