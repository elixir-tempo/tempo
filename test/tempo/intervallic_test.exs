defmodule Tempo.IntervallicTest do
  use ExUnit.Case, async: true

  # A value of the caller's that implements `Tempo.Intervallic` is accepted
  # wherever two expressions are compared or combined, read once as the
  # expression it stands for (decisions 101 to 104).

  import Tempo.Sigils

  alias Tempo.{Allen, ConversionError, IntervalEndpointsError, Intervallic, IntervalSet}
  alias Tempo.Test.{Booking, Nonsense}

  doctest Tempo.Intervallic

  defp booking(guest, from, to) do
    %Booking{guest: guest, check_in: from, check_out: to}
  end

  defp alice, do: booking("Alice", ~o"2026-06-15", ~o"2026-06-18")
  defp bob, do: booking("Bob", ~o"2026-06-20", ~o"2026-06-22")
  defp carol, do: booking("Carol", ~o"2026-06-01", ~o"2026-06-03")

  defp guests(set) do
    set
    |> IntervalSet.members()
    |> Enum.map(& &1.metadata.booking.guest)
  end

  describe "a caller's struct" do
    test "is related and tested as the interval it stands for" do
      assert Tempo.relation(alice(), bob()) == :precedes
      assert Tempo.relation(~o"2026-06-16", alice()) == :during
      assert Tempo.overlaps?(alice(), ~o"2026-06-18")
      assert Tempo.within?(alice(), ~o"2026-06")
      refute Tempo.overlaps?(alice(), bob())
      assert Allen.during?(~o"2026-06-16", alice())
      assert Allen.relation(alice(), bob()) == :precedes
    end

    test "is sorted by the time it covers" do
      assert Enum.sort([bob(), alice(), carol()], Tempo) == [carol(), alice(), bob()]
    end

    test "is a member of a set, and is found again in the members an answer keeps" do
      assert {:ok, bookings} = IntervalSet.new([alice(), bob(), carol()])
      assert guests(bookings) == ["Alice", "Bob", "Carol"]

      assert {:ok, overlapping} = Tempo.members_overlapping(bookings, ~o"2026-06-17/2026-06-21")
      assert guests(overlapping) == ["Alice", "Bob"]

      assert {:ok, outside} = Tempo.members_outside(bookings, ~o"2026-06-10/2026-06-30")
      assert guests(outside) == ["Carol"]
    end

    test "is combined as the time it covers" do
      assert {:ok, bookings} = IntervalSet.new([alice(), bob()])

      assert Tempo.difference(~o"2026-06-14/2026-06-22", bookings) ==
               {:ok, ~o"{2026-06-14/2026-06-14,2026-06-19/2026-06-19}"}

      assert {:ok, last_nights} = Tempo.intersection(alice(), ~o"2026-06-17/2026-06-30")
      assert Tempo.to_iso8601(last_nights) == Tempo.to_iso8601(~o"{2026-06-17/2026-06-18}")
      assert last_nights.metadata.booking == alice()

      assert {:ok, both} = Tempo.union(alice(), bob())
      assert Enum.count(IntervalSet.members(both)) == 2

      assert {:ok, [[:precedes]]} = IntervalSet.relation_matrix(alice(), bob())
    end
  end

  describe "Elixir's own structs" do
    test "are related and combined as from_elixir/2 reads them" do
      assert Tempo.overlaps?(~D[2026-06-15], ~o"2026-06")
      assert Tempo.relation(~D[2026-06-15], ~D[2026-06-16]) == :meets
      assert Tempo.within?(Date.range(~D[2026-06-15], ~D[2026-06-20]), ~o"2026-06")

      paris = DateTime.new!(~D[2026-06-15], ~T[10:30:00], "Europe/Paris")
      assert Tempo.within?(paris, ~o"2026-06-15T10[Europe/Paris]")

      assert Tempo.intersection(
               Date.range(~D[2026-06-15], ~D[2026-06-20]),
               ~o"2026-06-18/2026-06-30"
             ) ==
               {:ok, ~o"{2026-06-18/2026-06-20}"}
    end
  end

  describe "a value that stands for no expression" do
    test "is refused by name, as any argument that is no expression is" do
      assert {:error, %ConversionError{reason: :not_an_expression, value: %URI{}}} =
               Tempo.relation(%URI{}, ~o"2026")

      assert {:error, %ConversionError{reason: :not_an_expression, value: %Nonsense{}}} =
               Tempo.union(~o"2026", %Nonsense{})

      assert {:error, %ConversionError{reason: :not_an_expression}} =
               IntervalSet.new([alice(), %URI{}])

      assert {:error, %ConversionError{reason: :not_an_expression}} =
               Intervallic.to_tempo(42)

      assert_raise ConversionError, fn -> Tempo.overlaps?(%URI{}, ~o"2026") end
      assert_raise ConversionError, fn -> Allen.relation(%URI{}, ~o"2026") end
    end

    test "is the error its implementation returns where it returns one" do
      backwards = booking("Dan", ~o"2026-06-20", ~o"2026-06-15")

      assert {:error, %IntervalEndpointsError{}} = Tempo.relation(backwards, ~o"2026")
      assert_raise IntervalEndpointsError, fn -> Tempo.overlaps?(backwards, ~o"2026") end
    end
  end
end
