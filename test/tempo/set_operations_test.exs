defmodule Tempo.SetOperationsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # The set operations held to `Tempo.Matrix.Sets`, which works each answer
  # out on whole numbers apart from the code under test. Spans are built
  # between numbered points, the days of January 2026, each written as an
  # interval through its last day (law 9) and carrying the mark of the member
  # it is; an answer is read back as positions on the day scale. Every pair
  # of sets of up to two members between four points is run, and generated
  # sets of up to four members between nine.

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Matrix.Sets
  alias Tempo.Spans

  @day 86_400_000_000
  @epoch Tempo.Calendar.iso_days(Calendar.ISO, 2026, 1, 1)

  defp interval({from, to, id}) do
    Interval.new!(
      from: Tempo.new!(year: 2026, month: 1, day: from),
      to: Tempo.new!(year: 2026, month: 1, day: to - 1),
      metadata: %{id: id}
    )
  end

  defp set(spans) do
    {:ok, set} = IntervalSet.new(Enum.map(spans, &interval/1))
    set
  end

  # A member's positions as points of the line, with its mark.
  defp read(%Tempo{} = member) do
    {:ok, {start, stop}} = Spans.extent(member)
    {div(start, @day) - @epoch + 1, div(stop, @day) - @epoch + 1, member.metadata[:id]}
  end

  defp stretches(%Tempo{form: {:all, members}}),
    do: members |> Enum.map(&read/1) |> Enum.map(fn {a, b, _} -> {a, b} end)

  defp marked(%Tempo{form: {:all, members}}), do: members |> Enum.map(&read/1) |> Enum.sort()

  defp spans_between(points, count) do
    singles = for from <- 1..(points - 1), to <- (from + 1)..points, do: {from, to}

    for n <- 1..count, combo <- combinations(singles, n) do
      combo |> Enum.with_index(1) |> Enum.map(fn {{from, to}, id} -> {from, to, id} end)
    end
  end

  defp combinations(_list, 0), do: [[]]
  defp combinations([], _n), do: []

  defp combinations([head | tail], n),
    do: Enum.map(combinations(tail, n - 1), &[head | &1]) ++ combinations(tail, n)

  defp agree(a, b) do
    sa = set(a)
    sb = set(b)
    {:ok, intersection} = Tempo.intersection(sa, sb)
    {:ok, difference} = Tempo.difference(sa, sb)
    {:ok, symmetric} = Tempo.symmetric_difference(sa, sb)
    {:ok, union} = Tempo.union(sa, sb)
    {:ok, coalesced} = IntervalSet.coalesce(union)
    {:ok, overlapping} = Tempo.members_overlapping(sa, sb)
    {:ok, outside} = Tempo.members_outside(sa, sb)

    assert stretches(intersection) == Sets.shared(a, b),
           "intersection of #{inspect(a)} and #{inspect(b)}"

    assert stretches(difference) == unmarked(Sets.difference(a, b)),
           "difference of #{inspect(a)} and #{inspect(b)}"

    assert stretches(symmetric) == Sets.cover(Sets.symmetric_difference(a, b)),
           "symmetric difference of #{inspect(a)} and #{inspect(b)}"

    assert stretches(coalesced) == Sets.cover(a ++ b),
           "coalesced union of #{inspect(a)} and #{inspect(b)}"

    # A member both hold is one member of the union (decision 38).
    assert marked(union) == Enum.uniq(Enum.sort(a ++ b)),
           "union of #{inspect(a)} and #{inspect(b)}"

    assert marked(overlapping) == Enum.sort(Sets.members_overlapping(a, b)),
           "members overlapping of #{inspect(a)} and #{inspect(b)}"

    assert marked(outside) == Enum.sort(Sets.members_outside(a, b)),
           "members outside of #{inspect(a)} and #{inspect(b)}"

    assert Tempo.overlaps?(sa, sb) == (Sets.shared(a, b) != [])
    assert Tempo.within?(sa, sb) == (Sets.difference(a, b) == [])
    assert Tempo.equal?(sa, sb) == (Sets.cover(a) == Sets.cover(b))
  end

  # The model's difference keeps the marks of cut members; the operations' answers are compared as the time covered.
  defp unmarked(spans), do: Sets.cover(spans)

  test "every pair of sets of up to two members between four points agrees with the model" do
    sets = spans_between(4, 2)
    for a <- sets, b <- sets, do: agree(a, b)
  end

  property "generated sets of up to four members between nine points agree with the model" do
    span =
      gen(all(from <- integer(1..8), length <- integer(1..(9 - from)), do: {from, from + length}))

    spans =
      gen(
        all(
          list <- list_of(span, min_length: 1, max_length: 4),
          do: list |> Enum.with_index(1) |> Enum.map(fn {{f, t}, id} -> {f, t, id} end)
        )
      )

    check all(a <- spans, b <- spans, max_runs: 150) do
      agree(a, b)
    end
  end

  test "the laws hold on covered time" do
    [a, b, c] = Enum.map([[{1, 3, 1}, {5, 7, 2}], [{2, 6, 1}], [{4, 8, 1}, {8, 9, 2}]], &set/1)
    {:ok, ab} = Tempo.intersection(a, b)
    {:ok, ba} = Tempo.intersection(b, a)
    assert Tempo.equal?(ab, ba)
    {:ok, a_or_b} = Tempo.union(a, b)
    {:ok, left} = Tempo.union(a_or_b, c)
    {:ok, b_or_c} = Tempo.union(b, c)
    {:ok, right} = Tempo.union(a, b_or_c)
    assert Tempo.equal?(left, right)
    {:ok, nothing} = Tempo.difference(a, a)
    assert IntervalSet.count(nothing) == 0
    window = Tempo.from_iso8601!("2026-01-01/2026-01-09")
    {:ok, not_a} = Tempo.complement(a, within: window)
    {:ok, not_b} = Tempo.complement(b, within: window)
    {:ok, not_a_or_b} = Tempo.complement(a_or_b, within: window)
    {:ok, not_a_and_not_b} = Tempo.intersection(not_a, not_b)
    assert Tempo.equal?(not_a_or_b, not_a_and_not_b)
  end

  describe "a member both operands of a union hold" do
    # Decision 38: the same member, in span, form and metadata, is one
    # member of the union; members that differ in any of those are two.
    test "is one member" do
      june = Tempo.new!(year: 2026, month: 6)
      {:ok, july} = Tempo.new(year: 2026, month: 7)
      {:ok, june_and_july} = IntervalSet.new([june, july])

      assert {:ok, union} = Tempo.union(june, june)
      assert IntervalSet.count(union) == 1

      assert {:ok, union} = Tempo.union(june_and_july, june)
      assert IntervalSet.count(union) == 2
    end

    test "is two where their forms or their metadata differ" do
      june = Tempo.new!(year: 2026, month: 6)

      {:ok, days_of_june} =
        Interval.new(
          from: Tempo.new!(year: 2026, month: 6, day: 1),
          to: Tempo.new!(year: 2026, month: 6, day: 30)
        )

      {:ok, nine} = Tempo.new(year: 2026, month: 6, day: 15, hour: 9)

      assert {:ok, union} = Tempo.union(june, days_of_june)
      assert IntervalSet.count(union) == 2

      assert {:ok, union} =
               Tempo.union(%{nine | metadata: %{who: "Ann"}}, %{nine | metadata: %{who: "Bob"}})

      assert IntervalSet.count(union) == 2
    end

    test "is one member of a union with no end" do
      {:ok, mondays} =
        Tempo.every([week: 1],
          from: Tempo.new!(year: 2026, month: 6, day: 1),
          select: [day_of_week: 1]
        )

      {:ok, union} = Tempo.union(mondays, Tempo.new!(year: 2026, month: 6, day: 8))

      assert union |> Enum.take(3) |> Enum.map(&Interval.from/1) ==
               [
                 Tempo.new!(year: 2026, month: 6, day: 1),
                 Tempo.new!(year: 2026, month: 6, day: 8),
                 Tempo.new!(year: 2026, month: 6, day: 15)
               ]
    end
  end
end
