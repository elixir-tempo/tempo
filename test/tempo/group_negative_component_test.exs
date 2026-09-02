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

  test "all four spellings of last-day-of-each-month agree" do
    literal = expand_dates("2026Y{1..12}M-1D")
    # `{1..-1}` — first through last month — resolves at parse time
    # against the year, so nothing hard-codes the month count.
    open_ended = expand_dates("2026Y{1..-1}M-1D")
    recurrence = expand_dates("R12/2026-01-01/P1M/FL-1DN")

    {:ok, selected} =
      Tempo.select(Tempo.from_iso8601!("2026Y{1..12}M"), Tempo.from_iso8601!("-1D"))

    selection_dates =
      selected
      |> IntervalSet.to_list()
      |> Enum.map(&(&1 |> Interval.from() |> Tempo.to_date() |> elem(1)))

    assert literal == open_ended
    assert literal == recurrence
    assert literal == selection_dates
  end

  describe "ranges in any combination of positions" do
    test "the reported case expands rather than hanging" do
      # `{2000..2010}Y{1..-1}M{1..-1}D` — open ranges in three
      # positions at once. Eleven years, three of them leap.
      assert length(expand_dates("{2000..2010}Y{1..-1}M{1..-1}D")) == 3 * 366 + 8 * 365
    end

    test "a set-valued year resolves each member's own month lengths" do
      by_year =
        "{2020,2021}Y2M{1..-1}D"
        |> expand_dates()
        |> Enum.group_by(& &1.year)
        |> Map.new(fn {year, days} -> {year, length(days)} end)

      assert by_year == %{2020 => 29, 2021 => 28}
    end

    test "a Hebrew leap year expands its thirteenth month, a common year does not" do
      {:ok, set} =
        "{5784,5785}Y{1..-1}M"
        |> Tempo.from_iso8601!(Calendrical.Hebrew)
        |> Tempo.to_interval()

      months_per_year =
        set
        |> IntervalSet.to_list()
        |> Enum.group_by(& &1.from.time[:year])
        |> Map.new(fn {year, months} -> {year, length(months)} end)

      assert months_per_year == %{5784 => 13, 5785 => 12}
    end

    test "materialisation and enumeration agree" do
      iso = "{2026,2027}Y{1..-1}M{1..-1}D"
      enumerated = iso |> Tempo.from_iso8601!() |> Enum.map(&(&1 |> Tempo.to_date() |> elem(1)))

      assert expand_dates(iso) == enumerated
      assert length(enumerated) == 730
    end
  end

  describe "a day set beyond its month" do
    test "clips per member when the month varies" do
      # September has no 31st, October does.
      days =
        "2026Y{9..10}M{28..31}D"
        |> expand_dates()
        |> Enum.map(&{&1.month, &1.day})

      assert days == [{9, 28}, {9, 29}, {9, 30}, {10, 28}, {10, 29}, {10, 30}, {10, 31}]
    end

    test "is refused when the month is concrete, whose length is then known" do
      # A concrete month determines its own maximum length whatever the
      # year, so the literal names days that exist in no year.
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026Y9M{28..31}D")
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("{2020,2021}Y2M30D")
    end
  end
end
