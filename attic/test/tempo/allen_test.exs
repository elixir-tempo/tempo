defmodule Tempo.AllenTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Allen
  alias Tempo.Interval.Relations

  doctest Tempo.Allen

  describe "Allen's relations beside the everyday predicates" do
    test "a meeting that ends when lunch starts is before lunch, but does not precede it" do
      meeting = ~o"2026-06-15T11/2026-06-15T12"
      lunch = ~o"2026-06-15T12/2026-06-15T13"

      assert Tempo.before?(meeting, lunch)
      assert Allen.meets?(meeting, lunch)
      refute Allen.precedes?(meeting, lunch)
    end

    test "December is within 2026 and finishes it, so it is not during it" do
      assert Tempo.within?(~o"2026-12", ~o"2026")
      assert Allen.finishes?(~o"2026-12", ~o"2026")
      refute Allen.during?(~o"2026-12", ~o"2026")
    end

    test "exactly one of the thirteen predicates holds" do
      holding =
        for relation <- Relations.full(),
            apply(Allen, :"#{relation}?", [~o"2026-01/2026-03", ~o"2026-02/2026-04"]),
            do: relation

      assert holding == [:overlaps]
    end
  end

  describe "a value that is not one interval" do
    test "raises rather than answering false" do
      {:ok, january_and_march} = Tempo.union(~o"2026-01", ~o"2026-03")

      assert_raise ArgumentError, fn -> Allen.meets?(january_and_march, ~o"2026-04") end
    end
  end

  describe "inverse/1 and compose/2" do
    test "the inverse of an empty set is empty" do
      assert Allen.inverse([]) == []
    end

    test "an invalid relation in a set is reported" do
      assert Allen.inverse([:precedes, :nonsense]) == {:error, {:invalid_relation, :nonsense}}
    end

    test "a relation composes with a set of relations" do
      assert Allen.compose(:precedes, [:precedes, :meets]) == [:precedes]
    end
  end
end
