defmodule Tempo.IntervalSetTableTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Table.Reader
  alias Tempo.Interval
  alias Tempo.IntervalSet

  setup do
    {:ok, holidays} =
      IntervalSet.new([
        Interval.new!(
          from: ~o"2026-12-25",
          to: ~o"2026-12-26",
          metadata: %{name: "Christmas Day"}
        ),
        Interval.new!(
          from: ~o"2026-12-28",
          to: ~o"2026-12-29",
          metadata: %{name: "Boxing Day", substitute: true}
        )
      ])

    %{holidays: holidays}
  end

  test "a set's rows are its members' from, to and metadata", %{holidays: holidays} do
    assert holidays |> Table.to_rows() |> Enum.to_list() == [
             %{from: ~o"2026-12-25", to: ~o"2026-12-26", name: "Christmas Day", substitute: nil},
             %{from: ~o"2026-12-28", to: ~o"2026-12-29", name: "Boxing Day", substitute: true}
           ]
  end

  test "the columns are from and to, then each metadata key as it first appears",
       %{holidays: holidays} do
    assert {:rows, %{columns: [:from, :to, :name, :substitute], count: 2}, _rows} =
             Reader.init(holidays)
  end

  test "a set without metadata has only from and to" do
    {:ok, days} = Tempo.to_interval_set(~o"R3/2026-01-01/P1D")

    assert {:rows, %{columns: [:from, :to], count: 3}, _rows} = Reader.init(days)
  end

  test "a lazy set is not tabular" do
    assert Reader.init(Tempo.weekends()) == :none
  end
end
