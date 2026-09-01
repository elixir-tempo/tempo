defmodule Tempo.GroupNegativeComponentTest do
  @moduledoc """
  ISO 8601-2 §4.4.1 negative components under set-valued containers:
  `2026Y{1..12}M-1D` resolves `-1D` against each expanded member's
  own month — leap-aware — instead of leaking an unresolved `-1`
  into the materialised intervals.
  """
  use ExUnit.Case, async: true

  alias Tempo.Interval
  alias Tempo.IntervalSet

  defp expand_dates(iso) do
    {:ok, set} = iso |> Tempo.from_iso8601!() |> Tempo.to_interval()

    set
    |> IntervalSet.to_list()
    |> Enum.map(&(&1 |> Interval.from() |> Tempo.to_date() |> elem(1)))
  end

  test "the last day of each month of a year" do
    assert expand_dates("2026Y{1..12}M-1D") == [
             ~D[2026-01-31],
             ~D[2026-02-28],
             ~D[2026-03-31],
             ~D[2026-04-30],
             ~D[2026-05-31],
             ~D[2026-06-30],
             ~D[2026-07-31],
             ~D[2026-08-31],
             ~D[2026-09-30],
             ~D[2026-10-31],
             ~D[2026-11-30],
             ~D[2026-12-31]
           ]
  end

  test "a leap-year February resolves to the 29th" do
    assert expand_dates("2024Y{1..3}M-1D") == [
             ~D[2024-01-31],
             ~D[2024-02-29],
             ~D[2024-03-31]
           ]
  end

  test "a negative month resolves against each grouped year" do
    {:ok, set} = "{2025,2026}Y-1M" |> Tempo.from_iso8601!() |> Tempo.to_interval()

    months =
      set |> IntervalSet.to_list() |> Enum.map(&{&1.from.time[:year], &1.from.time[:month]})

    assert months == [{2025, 12}, {2026, 12}]
  end

  test "all three spellings of last-day-of-each-month agree" do
    literal = expand_dates("2026Y{1..12}M-1D")
    recurrence = expand_dates("R12/2026-01-01/P1M/FL-1DN")

    {:ok, selected} =
      Tempo.select(Tempo.from_iso8601!("2026Y{1..12}M"), Tempo.from_iso8601!("-1D"))

    selection_dates =
      selected
      |> IntervalSet.to_list()
      |> Enum.map(&(&1 |> Interval.from() |> Tempo.to_date() |> elem(1)))

    assert literal == recurrence
    assert literal == selection_dates
  end
end
