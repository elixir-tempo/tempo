defmodule Tempo.IntervalSet.Backend.Tree do
  @moduledoc """
  An interval-tree `Tempo.IntervalSet.Backend`: a balanced binary tree
  over the members, ordered by `from` endpoint, with each node
  augmented by the maximum `to` endpoint in its subtree.

  The augmentation is what makes the tree an *interval* tree: an
  `overlapping/2` query prunes every subtree whose maximum end lies at
  or before the queried range, answering stabbing and overlap questions
  in O(log n + k) instead of a full scan. Construction is O(n) — the
  member list `Tempo.IntervalSet.new/2` supplies is already sorted, so
  the tree is built perfectly balanced with no rebalancing.

  Endpoint positions are precomputed once at construction as gregorian
  UTC seconds (`Tempo.Compare.to_utc_seconds/1`), so tree comparisons
  are integer comparisons and remain correct across calendars and
  zones.

  Because that projection needs a year, **members must be anchored**
  (and bounded, as every set member already is). Building a tree from
  unanchored members (`~o"T10:00/T11:00"`) raises an
  `ArgumentError` — keep those sets on the default list backend.

  Choose this backend for large, query-heavy sets — multi-year
  calendar feeds probed with `Tempo.IntervalSet.covered?/2` or used as
  a `skipping:` busy set:

      Tempo.IntervalSet.new(events, backend: :tree)

  """

  use Tempo.IntervalSet.Backend

  alias Tempo.Compare
  alias Tempo.Interval

  # State: `{:tree, count, root}` where a node is
  # `{interval, from_s, to_s, max_end, left, right}` and an empty
  # subtree is `nil`.

  @impl true
  def from_list(intervals, _options) do
    count = length(intervals)

    {root, []} =
      intervals
      |> Enum.map(&node_payload/1)
      |> build_balanced(count)

    {:tree, count, root}
  end

  @impl true
  def to_list({:tree, _count, root}), do: inorder(root, [])

  @impl true
  def walk({:tree, _count, root}), do: inorder(root, [])

  @impl true
  def bounded?(_state), do: true

  @impl true
  def count({:tree, count, _root}), do: count

  @impl true
  def empty?({:tree, count, _root}), do: count == 0

  @impl true
  def first({:tree, _count, root}), do: leftmost(root)

  @impl true
  def overlapping({:tree, _count, root}, {lo, hi}) do
    root |> query(lo, hi, []) |> Enum.reverse()
  end

  ## Construction ---------------------------------------------------

  defp node_payload(%Interval{from: %Tempo{} = from, to: %Tempo{} = to} = interval) do
    if Tempo.anchored?(from) and Tempo.anchored?(to) do
      {interval, Compare.to_utc_seconds(from), Compare.to_utc_seconds(to)}
    else
      raise ArgumentError, tree_requires_anchored(interval)
    end
  end

  defp node_payload(%Interval{} = interval) do
    raise ArgumentError, tree_requires_anchored(interval)
  end

  defp tree_requires_anchored(interval) do
    "the Tree backend requires anchored, bounded members so their " <>
      "timeline positions can be indexed; got #{inspect(interval)}. " <>
      "Use the default list backend for unanchored or open-ended sets."
  end

  # Build a perfectly balanced tree from a sorted payload list in one
  # pass: recurse on the left half, take the pivot, recurse on the
  # remainder.
  defp build_balanced(payloads, 0), do: {nil, payloads}

  defp build_balanced(payloads, n) do
    left_count = div(n - 1, 2)
    {left, [{interval, from_s, to_s} | rest]} = build_balanced(payloads, left_count)
    {right, remaining} = build_balanced(rest, n - 1 - left_count)

    max_end = to_s |> max_seconds(max_end_of(left)) |> max_seconds(max_end_of(right))
    {{interval, from_s, to_s, max_end, left, right}, remaining}
  end

  defp max_end_of(nil), do: :neg_infinity
  defp max_end_of({_iv, _f, _t, max_end, _l, _r}), do: max_end

  defp max_seconds(:neg_infinity, b), do: b
  defp max_seconds(a, :neg_infinity), do: a
  defp max_seconds(a, b), do: max(a, b)

  ## Queries --------------------------------------------------------

  defp inorder(nil, acc), do: acc

  defp inorder({interval, _f, _t, _m, left, right}, acc) do
    inorder(left, [interval | inorder(right, acc)])
  end

  defp leftmost(nil), do: nil
  defp leftmost({interval, _f, _t, _m, nil, _right}), do: interval
  defp leftmost({_iv, _f, _t, _m, left, _right}), do: leftmost(left)

  # Members whose `[from_s, to_s)` intersects `[lo, hi)`:
  # `from_s < hi and to_s > lo`. Prune a subtree when its maximum end
  # is at or below `lo` (nothing in it reaches the range); skip the
  # right child when this node already starts at or beyond `hi`
  # (everything right of it starts later still).
  defp query(nil, _lo, _hi, acc), do: acc

  defp query({interval, from_s, to_s, max_end, left, right}, lo, hi, acc) do
    if max_end <= lo do
      acc
    else
      acc = query(left, lo, hi, acc)
      acc = if from_s < hi and to_s > lo, do: [interval | acc], else: acc
      if from_s < hi, do: query(right, lo, hi, acc), else: acc
    end
  end
end
