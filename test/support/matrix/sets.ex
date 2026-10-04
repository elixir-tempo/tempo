defmodule Tempo.Matrix.Sets do
  @moduledoc """
  What each set operation gives of two lists of spans, worked out on whole
  numbers and apart from the code under test (see `plans/set-operations.md`).

  A span is `{from, to, id}`: a half-open stretch of positions on one line,
  and a mark of the member it is, or of the member it was cut from. The
  members of a list may overlap, nest, repeat and meet. A stretch is a span
  with no mark, `{from, to}`, and on a cycle it is an arc, which may run
  through the cycle's end. Nothing here reads a Tempo value: positions
  are read by `Tempo.Matrix.Extent`, and what is done with them is
  arithmetic on whole numbers.

  """

  @type position :: integer()
  @type span :: {position(), position(), term()}
  @type stretch :: {position(), position()}

  @doc """
  Spans in the one order every answer is compared in.

  ### Arguments

  * `spans` is a list of `t:span/0`.

  ### Returns

  * The spans by their start, then their end, then their mark.

  """
  @spec ordered([span()]) :: [span()]
  def ordered(spans), do: Enum.sort(spans)

  @doc """
  The members of both lists.

  ### Arguments

  * `a` and `b` are lists of `t:span/0`.

  ### Returns

  * Every member of either, each kept as it is.

  """
  @spec union([span()], [span()]) :: [span()]
  def union(a, b), do: ordered(a ++ b)

  @doc """
  The time a list covers.

  ### Arguments

  * `spans` is a list of `t:span/0`.

  ### Returns

  * A list of `t:stretch/0` in order, members that overlap or meet merged
    into one.

  """
  @spec cover([span()]) :: [stretch()]
  def cover(spans) do
    spans
    |> Enum.map(fn {from, to, _id} -> {from, to} end)
    |> Enum.sort()
    |> Enum.reduce([], fn
      {from, to}, [{open, close} | merged] when from <= close -> [{open, max(close, to)} | merged]
      stretch, merged -> [stretch | merged]
    end)
    |> Enum.reverse()
  end

  @doc """
  The time both lists cover.

  ### Arguments

  * `a` and `b` are lists of `t:span/0`.

  ### Returns

  * A list of `t:stretch/0` in order.

  """
  @spec shared([span()], [span()]) :: [stretch()]
  def shared(a, b) do
    for {a_from, a_to} <- cover(a),
        {b_from, b_to} <- cover(b),
        max(a_from, b_from) < min(a_to, b_to) do
      {max(a_from, b_from), min(a_to, b_to)}
    end
  end

  @doc """
  Each member of the first list cut to each member of the second it overlaps.

  ### Arguments

  * `a` and `b` are lists of `t:span/0`.

  ### Returns

  * A list of `t:span/0`, one for each pair of members that overlap, with
    the mark of the first's member.

  """
  @spec pairwise([span()], [span()]) :: [span()]
  def pairwise(a, b) do
    ordered(
      for {a_from, a_to, id} <- a,
          {b_from, b_to, _b_id} <- b,
          max(a_from, b_from) < min(a_to, b_to) do
        {max(a_from, b_from), min(a_to, b_to), id}
      end
    )
  end

  @doc """
  Each member of the first list without the time the second covers.

  ### Arguments

  * `a` and `b` are lists of `t:span/0`.

  ### Returns

  * A list of `t:span/0`: what is left of each member of `a`, in as many
    parts as the second list leaves it in, each with the member's mark.

  """
  @spec difference([span()], [span()]) :: [span()]
  def difference(a, b) do
    holes = cover(b)

    ordered(
      for {from, to, id} <- a, {part_from, part_to} <- outside({from, to}, holes) do
        {part_from, part_to, id}
      end
    )
  end

  # What is left of a stretch once each hole, in order, is taken from it.
  defp outside({from, to}, holes) do
    {left, parts} =
      Enum.reduce(holes, {from, []}, fn {hole_from, hole_to}, {start, parts} ->
        cond do
          hole_to <= start or hole_from >= to -> {start, parts}
          hole_from > start -> {max(start, hole_to), [{start, hole_from} | parts]}
          true -> {max(start, hole_to), parts}
        end
      end)

    Enum.reverse(if left < to, do: [{left, to} | parts], else: parts)
  end

  @doc """
  What each list covers and the other does not, member by member.

  ### Arguments

  * `a` and `b` are lists of `t:span/0`.

  ### Returns

  * A list of `t:span/0`.

  """
  @spec symmetric_difference([span()], [span()]) :: [span()]
  def symmetric_difference(a, b), do: ordered(difference(a, b) ++ difference(b, a))

  @doc """
  The members of the first list that overlap a member of the second.

  ### Arguments

  * `a` and `b` are lists of `t:span/0`.

  ### Returns

  * A list of `t:span/0`, each a whole member of `a`.

  """
  @spec members_overlapping([span()], [span()]) :: [span()]
  def members_overlapping(a, b), do: a |> Enum.filter(&overlaps_any?(&1, b)) |> ordered()

  @doc """
  The members of the first list that overlap no member of the second.

  ### Arguments

  * `a` and `b` are lists of `t:span/0`.

  ### Returns

  * A list of `t:span/0`, each a whole member of `a`.

  """
  @spec members_outside([span()], [span()]) :: [span()]
  def members_outside(a, b), do: a |> Enum.reject(&overlaps_any?(&1, b)) |> ordered()

  @doc """
  The members of either list that overlap no member of the other.

  ### Arguments

  * `a` and `b` are lists of `t:span/0`.

  ### Returns

  * A list of `t:span/0`.

  """
  @spec members_in_exactly_one([span()], [span()]) :: [span()]
  def members_in_exactly_one(a, b),
    do: ordered(members_outside(a, b) ++ members_outside(b, a))

  defp overlaps_any?({from, to, _id}, others),
    do:
      Enum.any?(others, fn {other_from, other_to, _other_id} ->
        from < other_to and other_from < to
      end)

  @doc """
  Whether two members of one list overlap each other.

  ### Arguments

  * `spans` is a list of `t:span/0`.

  ### Returns

  * `true` or `false`. Members that only meet do not overlap.

  """
  @spec overlap_each_other?([span()]) :: boolean()
  def overlap_each_other?(spans) do
    # In order of their starts, two members overlap exactly when one starts
    # before the furthest end reached so far.
    spans
    |> ordered()
    |> Enum.reduce_while(nil, fn
      {_from, to, _id}, nil -> {:cont, to}
      {from, _to, _id}, furthest when from < furthest -> {:halt, :overlap}
      {_from, to, _id}, furthest -> {:cont, max(furthest, to)}
    end)
    |> Kernel.==(:overlap)
  end

  @doc """
  The time at least so many members of a list cover.

  ### Arguments

  * `spans` is a list of `t:span/0`.

  * `at_least` is a positive whole number.

  ### Returns

  * A list of `t:stretch/0` in order, each as long as it can be.

  """
  @spec covered([span()], pos_integer()) :: [stretch()]
  def covered(spans, at_least) do
    edges =
      spans |> Enum.flat_map(fn {from, to, _id} -> [from, to] end) |> Enum.uniq() |> Enum.sort()

    edges
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [from, to] ->
      Enum.count(spans, fn {span_from, span_to, _id} -> span_from <= from and to <= span_to end) >=
        at_least
    end)
    |> Enum.map(fn [from, to] -> {from, to, nil} end)
    |> cover()
  end

  @doc """
  The time at least so many arcs of a cycle cover.

  ### Arguments

  * `arcs` is a list of `{from, to}`, positions counted from the cycle's
    start and before its end. An arc whose end is not after its start runs
    through the cycle's end, and one that ends where it starts is once
    round.

  * `at_least` is a positive whole number.

  * `length` is the length of the cycle.

  ### Returns

  * A list of arcs in the order of their starts, each as long as it can
    be. The whole cycle, which starts nowhere, is `{0, 0}`.

  """
  @spec covered_on_cycle([stretch()], pos_integer(), pos_integer()) :: [stretch()]
  def covered_on_cycle(arcs, at_least, length) do
    arcs
    |> Enum.flat_map(fn {from, to} -> [from, to] end)
    |> Enum.uniq()
    |> Enum.sort()
    |> cells_around(length)
    |> Enum.map(fn {from, _to} = cell -> {cell, holders_at(arcs, from, length) >= at_least} end)
    |> runs_around(length)
    |> Enum.sort()
  end

  # The cycle cut at every end of an arc: between two cuts next to each
  # other every arc either holds all of the cell or none of it. The last
  # cell runs through the cycle's end to the first cut.
  defp cells_around([], _length), do: []

  defp cells_around([first | later] = cuts, length),
    do: Enum.zip(cuts, later ++ [first + length])

  # How many arcs hold a position: those it is no further round from the
  # start of than the arc is long.
  defp holders_at(arcs, position, length) do
    Enum.count(arcs, fn {from, to} ->
      Integer.mod(position - from, length) < reach(from, to, length)
    end)
  end

  defp reach(from, from, length), do: length
  defp reach(from, to, length), do: Integer.mod(to - from, length)

  # The runs of covered cells, going round from a cell that is not covered
  # so that no run is cut where the list starts.
  defp runs_around(cells, length) do
    {leading, rest} = Enum.split_while(cells, fn {_cell, covered?} -> covered? end)
    runs_from(rest, leading, length)
  end

  defp runs_from([], [], _length), do: []
  defp runs_from([], _all_covered, _length), do: [{0, 0}]

  defp runs_from(rest, leading, length) do
    next_turn =
      for {{from, to}, covered?} <- leading, do: {{from + length, to + length}, covered?}

    (rest ++ next_turn)
    |> Enum.chunk_by(fn {_cell, covered?} -> covered? end)
    |> Enum.filter(fn [{_cell, covered?} | _run] -> covered? end)
    |> Enum.map(fn run ->
      {{from, _to}, true} = hd(run)
      {{_from, to}, true} = List.last(run)
      {Integer.mod(from, length), Integer.mod(to, length)}
    end)
  end
end
