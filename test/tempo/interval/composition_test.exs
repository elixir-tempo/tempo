defmodule Tempo.Interval.CompositionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tempo.Allen

  # Allen's 13 relations in canonical order.
  @order [
    :precedes,
    :meets,
    :overlaps,
    :finished_by,
    :contains,
    :starts,
    :equals,
    :started_by,
    :during,
    :finishes,
    :overlapped_by,
    :met_by,
    :preceded_by
  ]

  describe "compose/2 — the composition table" do
    test "every cell equals an independent difference-bound derivation" do
      # The shipped table is a literal; this re-derives each of the 169 cells
      # from the endpoint encoding via a difference-bound consistency check
      # (an oracle independent of the literal) and demands an exact match —
      # catching both a missing relation and a spurious one.
      for relation1 <- @order, relation2 <- @order do
        assert Allen.compose(relation1, relation2) == derive(relation1, relation2),
               "compose(#{relation1}, #{relation2}) drifted from its derivation"
      end
    end

    test "matches Allen (1983) on landmark cells" do
      assert Allen.compose(:precedes, :precedes) == [:precedes]
      assert Allen.compose(:precedes, :during) == [:precedes, :meets, :overlaps, :starts, :during]
      assert Allen.compose(:overlaps, :overlaps) == [:precedes, :meets, :overlaps]
      assert Allen.compose(:meets, :during) == [:overlaps, :starts, :during]
      assert Allen.compose(:meets, :met_by) == [:finished_by, :equals, :finishes]
      assert Allen.compose(:starts, :started_by) == [:starts, :equals, :started_by]
      assert Allen.compose(:finishes, :finished_by) == [:finished_by, :equals, :finishes]

      # contains ∘ during — the nine "concurrent" relations.
      assert Allen.compose(:contains, :during) == [
               :overlaps,
               :finished_by,
               :contains,
               :starts,
               :equals,
               :started_by,
               :during,
               :finishes,
               :overlapped_by
             ]
    end

    test "equals is the identity on both sides" do
      for relation <- @order do
        assert Allen.compose(:equals, relation) == [relation]
        assert Allen.compose(relation, :equals) == [relation]
      end
    end

    test "opposite disjoint relations lose all information" do
      # before ∘ after (and after ∘ before) admit every relation.
      assert Allen.compose(:precedes, :preceded_by) == @order
      assert Allen.compose(:preceded_by, :precedes) == @order
      assert Allen.compose(:during, :contains) == @order
    end

    test "every cell is a non-empty subset in canonical order" do
      for relation1 <- @order, relation2 <- @order do
        cell = Allen.compose(relation1, relation2)
        assert cell != []
        assert Enum.all?(cell, &(&1 in @order))
        # No duplicates, and listed in Allen's canonical order.
        assert cell == Enum.filter(@order, &(&1 in cell))
      end
    end

    property "soundness: relation(A, C) always lies in compose(relation(A, B), relation(B, C))" do
      # Over random ground triples, the actual A–C relation must be among those
      # the table predicts from the A–B and B–C relations.
      check all(
              a_start <- integer(0..1000),
              a_len <- integer(1..500),
              b_start <- integer(0..1000),
              b_len <- integer(1..500),
              c_start <- integer(0..1000),
              c_len <- integer(1..500)
            ) do
        a = interval(a_start, a_len)
        b = interval(b_start, b_len)
        c = interval(c_start, c_len)

        relation_ac = Tempo.relation(a, c)
        composed = Allen.compose(Tempo.relation(a, b), Tempo.relation(b, c))

        assert relation_ac in composed,
               "A #{Tempo.relation(a, b)} B, B #{Tempo.relation(b, c)} C, " <>
                 "but A #{relation_ac} C is not in #{inspect(composed)}"
      end
    end
  end

  describe "compose/2 — sets and error handling" do
    test "an unknown relation atom returns the offending atom" do
      assert Allen.compose(:precedes, :nonsense) ==
               {:error, {:invalid_relation, :nonsense}}

      assert Allen.compose(:bogus, :during) ==
               {:error, {:invalid_relation, :bogus}}
    end

    test "a non-atom argument is rejected without raising" do
      assert Allen.compose("precedes", 42) ==
               {:error, {:invalid_relation, "precedes"}}

      assert Allen.compose(:precedes, nil) ==
               {:error, {:invalid_relation, nil}}
    end

    test "a set composes every pair and returns the union" do
      for relation1 <- @order, relation2 <- @order do
        assert Allen.compose([relation1], [relation2]) == Allen.compose(relation1, relation2)
      end

      assert Allen.compose([:precedes, :meets], :precedes) == [:precedes]
      assert Allen.compose(:equals, [:during, :starts]) == [:starts, :during]
      assert Allen.compose([], [:precedes]) == []
    end

    test "an invalid relation inside a set is reported" do
      assert Allen.compose([:precedes, :nonsense], [:during]) ==
               {:error, {:invalid_relation, :nonsense}}
    end
  end

  # --- Independent oracle: derive compose(r1, r2) from endpoint constraints ---
  #
  # Each relation constrains the order of a pair's endpoints (a1 < a2 for the
  # first interval, b1 < b2 for the second). compose(r1, r2) is the set of r3
  # for which some assignment of six endpoints satisfies r1(A,B) ∧ r2(B,C) ∧
  # r3(A,C), checked as a difference-bound network with no negative cycle.

  @encodings [
    precedes: [{:a2, :lt, :b1}],
    meets: [{:a2, :eq, :b1}],
    overlaps: [{:a1, :lt, :b1}, {:b1, :lt, :a2}, {:a2, :lt, :b2}],
    finished_by: [{:a1, :lt, :b1}, {:a2, :eq, :b2}],
    contains: [{:a1, :lt, :b1}, {:b2, :lt, :a2}],
    starts: [{:a1, :eq, :b1}, {:a2, :lt, :b2}],
    equals: [{:a1, :eq, :b1}, {:a2, :eq, :b2}],
    started_by: [{:a1, :eq, :b1}, {:b2, :lt, :a2}],
    during: [{:b1, :lt, :a1}, {:a2, :lt, :b2}],
    finishes: [{:a2, :eq, :b2}, {:b1, :lt, :a1}],
    overlapped_by: [{:b1, :lt, :a1}, {:a1, :lt, :b2}, {:b2, :lt, :a2}],
    met_by: [{:a1, :eq, :b2}],
    preceded_by: [{:b2, :lt, :a1}]
  ]

  @nodes [:a1, :a2, :b1, :b2, :c1, :c2]
  @proper [{:a1, :a2, -1}, {:b1, :b2, -1}, {:c1, :c2, -1}]
  @map_ab %{a1: :a1, a2: :a2, b1: :b1, b2: :b2}
  @map_bc %{a1: :b1, a2: :b2, b1: :c1, b2: :c2}
  @map_ac %{a1: :a1, a2: :a2, b1: :c1, b2: :c2}

  defp derive(relation1, relation2) do
    fixed = @proper ++ instantiate(relation1, @map_ab) ++ instantiate(relation2, @map_bc)
    for relation3 <- @order, satisfiable?(fixed ++ instantiate(relation3, @map_ac)), do: relation3
  end

  defp instantiate(relation, mapping) do
    Enum.flat_map(@encodings[relation], fn {left, op, right} ->
      edge(op, Map.fetch!(mapping, left), Map.fetch!(mapping, right))
    end)
  end

  defp edge(:lt, from, to), do: [{from, to, -1}]
  defp edge(:eq, from, to), do: [{from, to, 0}, {to, from, 0}]

  defp satisfiable?(edges) do
    edges
    |> Enum.reduce(initial_distances(), fn {from, to, weight}, acc ->
      Map.update(acc, {from, to}, weight, &tighten(&1, weight))
    end)
    |> close()
    |> consistent?()
  end

  defp initial_distances do
    for from <- @nodes, to <- @nodes, into: %{} do
      {{from, to}, if(from == to, do: 0, else: :inf)}
    end
  end

  defp close(distances) do
    for k <- @nodes, i <- @nodes, j <- @nodes, reduce: distances do
      acc ->
        via = add(Map.get(acc, {i, k}), Map.get(acc, {k, j}))
        if less?(via, Map.get(acc, {i, j})), do: Map.put(acc, {i, j}, via), else: acc
    end
  end

  defp consistent?(distances) do
    Enum.all?(@nodes, fn node -> Map.get(distances, {node, node}, 0) >= 0 end)
  end

  defp tighten(:inf, weight), do: weight
  defp tighten(current, weight), do: min(current, weight)

  defp add(:inf, _weight), do: :inf
  defp add(_weight, :inf), do: :inf
  defp add(left, right), do: left + right

  defp less?(_left, :inf), do: true
  defp less?(:inf, _right), do: false
  defp less?(left, right), do: left < right

  # A ground interval [start, start + length) as a Tempo value, in years.
  defp interval(start, length) do
    Tempo.from_iso8601!("#{start}Y/#{start + length}Y")
  end
end
