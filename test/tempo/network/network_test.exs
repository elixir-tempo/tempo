defmodule Tempo.NetworkTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Network
  alias Tempo.Network.{Qualitative, Relation, Solver, TimePeriod}

  doctest Tempo.Network.TimePeriod
  doctest Tempo.Network.Relation
  doctest Tempo.Network

  describe "TimePeriod.new/2 bound specifications" do
    test "Tempo values are the idiomatic form, and bounds are stored as Tempo values" do
      period =
        TimePeriod.new!(:k1,
          from: {:not_before, ~o"1200Y"},
          to: {~o"1300Y", ~o"1350Y"},
          duration: {:at_least, ~o"P20Y"}
        )

      assert period.earliest_start == ~o"1200Y"
      assert period.earliest_end == ~o"1300Y"
      assert period.latest_end == ~o"1350Y"
      assert period.min_duration == ~o"P20Y"
    end

    test "an exact start fixes both start bounds" do
      period = TimePeriod.new!(:k1, from: ~o"1200Y")
      assert period.earliest_start == ~o"1200Y"
      assert period.latest_start == ~o"1200Y"
    end

    test "a range start sets the lower and upper bounds" do
      period = TimePeriod.new!(:k1, from: {1200, 1250})
      assert TimePeriod.year(period.earliest_start) == 1200
      assert TimePeriod.year(period.latest_start) == 1250
    end

    test "not_before / not_after are one-sided" do
      not_before = TimePeriod.new!(:k1, from: {:not_before, 1200})
      assert TimePeriod.year(not_before.earliest_start) == 1200
      assert not_before.latest_start == nil

      not_after = TimePeriod.new!(:k2, to: {:not_after, 1300})
      assert not_after.earliest_end == nil
      assert TimePeriod.year(not_after.latest_end) == 1300
    end

    test "duration accepts at_least / at_most / exact / range" do
      assert TimePeriod.new!(:a, duration: {:at_least, 20}).min_duration == ~o"P20Y"
      assert TimePeriod.new!(:b, duration: {:at_most, 50}).max_duration == ~o"P50Y"

      exact = TimePeriod.new!(:c, duration: 30)
      assert exact.min_duration == ~o"P30Y" and exact.max_duration == ~o"P30Y"

      ranged = TimePeriod.new!(:d, duration: {20, 50})
      assert ranged.min_duration == ~o"P20Y" and ranged.max_duration == ~o"P50Y"
    end

    test "BCE years are accepted as negative integers and Tempo values" do
      period = TimePeriod.new!(:dyn26, from: -664, to: ~o"-525Y")
      assert TimePeriod.year(period.earliest_start) == -664
      assert TimePeriod.year(period.earliest_end) == -525
    end

    test "EDTF/ISO 8601 strings are parsed" do
      period = TimePeriod.new!(:k1, from: "1200Y")
      assert TimePeriod.year(period.earliest_start) == 1200
    end

    test "metadata rides along untouched" do
      period = TimePeriod.new!(:k1, metadata: %{source: "Manetho"})
      assert period.metadata == %{source: "Manetho"}
    end
  end

  describe "Network builder" do
    test "periods, sequences, and relations accumulate" do
      network =
        Network.new()
        |> Network.add_period(:k1, from: {:not_before, 1200})
        |> Network.add_period(:k2, duration: {:at_least, 35})
        |> Network.add_sequence([:k1, :k2])
        |> Network.add_relation(:immediately_precedes, :k1, :k2)

      assert Map.keys(network.periods) |> Enum.sort() == [:k1, :k2]
      assert network.sequences == [[:k1, :k2]]
      assert [%Relation{type: :immediately_precedes, from: :k1, to: :k2}] = network.relations
    end

    test "add_period/2 with a prebuilt struct replaces a same-id period" do
      period = TimePeriod.new!(:k1, name: "first")
      replacement = TimePeriod.new!(:k1, name: "second")

      network =
        Network.new()
        |> Network.add_period(period)
        |> Network.add_period(replacement)

      assert map_size(network.periods) == 1
      assert network.periods[:k1].name == "second"
    end

    test "period_ids/1 includes ids named only in relations or sequences" do
      network =
        Network.new()
        |> Network.add_period(:k1, [])
        |> Network.add_sequence([:k1, :k2])
        |> Network.add_relation(:before, :k2, :k3)

      assert Enum.sort(Network.period_ids(network)) == [:k1, :k2, :k3]
    end
  end

  describe "bad input is recorded on the network, not raised" do
    test "TimePeriod.new/2 returns an error for 1.x's :start and :end, naming :from and :to" do
      assert {:error, %ArgumentError{} = error} = TimePeriod.new(:k1, start: ~o"1200Y")
      assert Exception.message(error) =~ "takes :from where 1.x took :start"

      assert {:error, %ArgumentError{} = error} = TimePeriod.new(:k1, end: ~o"1300Y")
      assert Exception.message(error) =~ "takes :to where 1.x took :end"
    end

    test "TimePeriod.new/2 returns an error for an option or a bound it cannot read" do
      for options <- [
            [finish: ~o"1300Y"],
            [from: "not a date"],
            [from: :tomorrow],
            [from: ~o"P20Y"],
            [to: {:not_after, "1300-13-45"}],
            [duration: "twenty years"],
            [duration: ~o"1200Y"],
            [duration: {:at_least, :long}],
            [name: :k1],
            [metadata: [:a]],
            :not_options,
            [1, 2]
          ] do
        assert {:error, %ArgumentError{}} = TimePeriod.new(:k1, options),
               "options #{inspect(options)} should be an error"
      end
    end

    test "TimePeriod.new!/2 raises what new/2 returns" do
      assert_raise ArgumentError, ~r/takes :from where 1.x took :start/, fn ->
        TimePeriod.new!(:k1, start: 1200)
      end
    end

    test "every solver function returns what the builders recorded; its predicates raise it" do
      network =
        Network.new()
        |> Network.add_period(:k1, start: ~o"1200Y")
        |> Network.add_period(:k2, duration: {:at_least, ~o"P35Y"})
        |> Network.add_sequence([:k1, :k2])

      assert [%ArgumentError{}] = network.errors
      assert {:error, %ArgumentError{} = error} = Solver.propagate(network)
      assert Exception.message(error) =~ "takes :from where 1.x took :start"
      assert {:error, %ArgumentError{}} = Solver.contemporaneity(network, :k1, :k2)
      assert {:error, %ArgumentError{}} = Solver.relation(network, :k1, :k2)
      assert {:error, %ArgumentError{}} = Solver.relation_certainty(network, :k1, :k2, :meets)
      assert {:error, %ArgumentError{}} = Solver.trace(network, {:end, :k2})
      assert {:error, %ArgumentError{}} = Qualitative.from_network(network)
      assert {:error, %ArgumentError{}} = Qualitative.refine(network)

      assert_raise ArgumentError, ~r/takes :from/, fn -> Solver.consistent?(network) end
      assert_raise ArgumentError, fn -> Solver.certainly_contemporary?(network, :k1, :k2) end
      assert_raise ArgumentError, fn -> Solver.possibly_contemporary?(network, :k1, :k2) end
    end

    test "add_period/2, add_sequence/2 and add_relation/5 record a value they cannot add" do
      for network <- [
            Network.add_period(Network.new(), :not_a_period),
            Network.add_period(Network.new(), :k1, :not_options),
            Network.add_sequence(Network.new(), :k1),
            Network.add_relation(Network.new(), :near, :k1, :k2),
            Network.add_relation(Network.new(), {:delay, :start, :end, :exactly, 5}, :k1, :k2),
            Network.add_relation(Network.new(), {:boundary, :middle, :before, :start}, :k1, :k2),
            Network.add_relation(Network.new(), :before, :k1, :k2, metadata: [:a]),
            Network.add_relation(Network.new(), :before, :k1, :k2, weight: 2)
          ] do
        assert [%ArgumentError{}] = network.errors
        assert {:error, %ArgumentError{}} = Solver.propagate(network)
      end
    end

    test "a network built without the builders is checked for the relations it names" do
      network = %Network{relations: [%Relation{type: :near, from: :a, to: :b}]}

      assert {:error, %ArgumentError{} = error} = Solver.propagate(network)
      assert Exception.message(error) =~ "Unknown relation :near"
    end

    test "trace/3 returns an error for a boundary or an option it does not take" do
      network =
        Network.add_period(Network.new(), :k1, from: ~o"1200Y", duration: {:at_least, ~o"P20Y"})

      assert {:ok, %{value: ~o"1220Y"}} = Solver.trace(network, {:end, :k1})

      for {boundary, options} <- [
            {{:middle, :k1}, []},
            {:k1, []},
            {{:end, :k1}, [bound: :soonest]},
            {{:end, :k1}, [within: ~o"1200Y"]},
            {{:end, :k1}, :latest}
          ] do
        assert {:error, %ArgumentError{}} = Solver.trace(network, boundary, options)
      end
    end
  end
end
