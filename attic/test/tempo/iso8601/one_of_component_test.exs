defmodule Tempo.Iso8601.OneOfComponentTest do
  use ExUnit.Case, async: true

  # A component-level "one of a set" (`[1,2,3]M`) is the one-of
  # counterpart of the all-of `{1,2,3}M` shorthand. It distributes
  # across the surrounding components to a one-of `Tempo.Set`.

  describe "designated component one-of" do
    test "a bare component yields a one-of set of that component" do
      assert {:ok, set} = Tempo.from_iso8601("[1,2,3]M")
      assert %Tempo.Set{type: :one} = set
      assert inspect(set) == ~s|~o"[1M,2M,3M]"|
    end

    test "distributes across the surrounding components" do
      assert {:ok, set} = Tempo.from_iso8601("2020Y[1,2,3]M")
      assert inspect(set) == ~s|~o"[2020Y1M,2020Y2M,2020Y3M]"|
    end

    test "a trailing component distributes too" do
      assert {:ok, set} = Tempo.from_iso8601("2020Y6M[1,15]D")
      assert inspect(set) == ~s|~o"[2020Y6M1D,2020Y6M15D]"|
    end

    test "a range inside the set expands to its members" do
      assert {:ok, set} = Tempo.from_iso8601("[1..3]M")
      assert inspect(set) == ~s|~o"[1M,2M,3M]"|
    end

    test "multiple one-of components form the cartesian product" do
      assert {:ok, set} = Tempo.from_iso8601("2020Y[1,2]M[10,20]D")
      assert inspect(set) == ~s|~o"[2020Y1M10D,2020Y1M20D,2020Y2M10D,2020Y2M20D]"|
    end

    test "works in the time of day" do
      assert {:ok, set} = Tempo.from_iso8601("T[10,12]H")
      assert inspect(set) == ~s|~o"[T10H,T12H]"|
    end
  end

  describe "one-of inside intervals" do
    test "an explicit one-of set of intervals builds interval members" do
      assert {:ok, set} = Tempo.from_iso8601("[2020Y/2021Y,2022Y/2023Y]")
      assert %Tempo.Set{type: :one, set: [%Tempo.Interval{}, %Tempo.Interval{}]} = set
      assert inspect(set) == ~s|~o"[2020Y/2021Y,2022Y/2023Y]"|
    end

    test "a one-of in the start endpoint distributes to a set of intervals" do
      assert {:ok, set} = Tempo.from_iso8601("2020Y[1,2]M/2021Y")
      assert inspect(set) == ~s|~o"[2020Y1M/2021Y,2020Y2M/2021Y]"|
    end

    test "a one-of in the end endpoint distributes too" do
      assert {:ok, set} = Tempo.from_iso8601("2020Y/2021Y[3,6]M")
      assert inspect(set) == ~s|~o"[2020Y/2021Y3M,2020Y/2021Y6M]"|
    end

    test "one-of in both endpoints forms the cartesian product" do
      assert {:ok, set} = Tempo.from_iso8601("2020Y[1,2]M/2021Y[3,6]M")

      assert inspect(set) ==
               ~s|~o"[2020Y1M/2021Y3M,2020Y1M/2021Y6M,2020Y2M/2021Y3M,2020Y2M/2021Y6M]"|
    end

    test "a plain interval is unchanged" do
      assert {:ok, %Tempo.Interval{}} = Tempo.from_iso8601("2020Y6M/2021Y")
    end
  end

  describe "regressions: the sibling forms are unchanged" do
    test "all-of {…} stays a multi-valued single Tempo, not a set" do
      assert {:ok, %Tempo{}} = Tempo.from_iso8601("{1,2,3}M")
      assert inspect(Tempo.from_iso8601!("{1,2,3}M")) == ~s|~o"{1..3}M"|
    end

    test "a bare top-level one-of set still parses as a set of years" do
      assert {:ok, %Tempo.Set{type: :one}} = Tempo.from_iso8601("[1984,1986,1988]")
    end

    test "a top-level one-of of full dates is unchanged" do
      assert {:ok, %Tempo.Set{type: :one}} = Tempo.from_iso8601("[2020-01,2020-02]")
    end
  end
end
