defmodule Tempo.RecurrenceSetTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet

  doctest Tempo.RecurrenceSet

  defp named(iso, name), do: %{Tempo.from_iso8601!(iso) | metadata: %{name: name}}

  defp isos(set),
    do: set |> IntervalSet.to_list() |> Enum.map(&Tempo.to_iso8601(Interval.from(&1)))

  defp years(set),
    do:
      set
      |> IntervalSet.to_list()
      |> Enum.map(&(&1 |> Interval.from() |> Tempo.year()))
      |> Enum.sort()

  describe "materialisation" do
    test "materialises each member against a bound and unions" do
      rset =
        RecurrenceSet.new([
          named("R/../P1Y/FL12M25DN", "Christmas"),
          named("R/../P1Y/FL1M1DN", "New Year")
        ])

      {:ok, set} = Tempo.to_interval_set(rset, bound: ~o"2026Y")
      assert isos(set) == ["2026Y1M1D", "2026Y12M25D"]
    end

    test "propagates each member's metadata onto its occurrences" do
      rset = RecurrenceSet.new([named("R/../P1Y/FL12M25DN", "Christmas")])
      {:ok, set} = Tempo.to_interval_set(rset, bound: ~o"2026Y")

      assert [interval] = IntervalSet.to_list(set)
      assert Interval.metadata(interval)[:name] == "Christmas"
    end

    test "a member's span directive shapes its occurrences but is not copied onto them" do
      # A three-day holiday: the member carries its span as `:occurrence_duration`.
      member = %{
        Tempo.from_iso8601!("R/../P1Y/FL12M24DN")
        | metadata: %{name: "Christmas break", occurrence_duration: ~o"P3D"}
      }

      {:ok, set} = Tempo.to_interval_set(RecurrenceSet.new([member]), bound: ~o"2026Y")
      assert [interval] = IntervalSet.to_list(set)
      assert Tempo.to_iso8601(interval) == "2026Y12M24D/27D"
      assert Interval.metadata(interval) == %{name: "Christmas break"}
    end

    test "a member with a domain is narrowed to the bound, not materialised whole" do
      rset =
        RecurrenceSet.new([
          named("R/{2020Y..2049Y}/P1Y/FL11M1DN", "One-off"),
          named("R/../P1Y/FL12M25DN", "Christmas")
        ])

      {:ok, set} = Tempo.to_interval_set(rset, bound: ~o"2026Y")
      assert years(set) == [2026, 2026]
    end

    test "a member with a ^ domain drops the excluded year" do
      rset = RecurrenceSet.new([named("R/{2024Y..2027Y,^2026Y}/P1Y/FL12M25DN", "Xmas")])
      {:ok, set} = Tempo.to_interval_set(rset)
      assert years(set) == [2024, 2025, 2027]
    end

    test "a concrete-interval member passes through" do
      rset =
        RecurrenceSet.new([
          Tempo.to_interval!(~o"2026Y7M4D"),
          named("R/../P1Y/FL12M25DN", "Christmas")
        ])

      {:ok, set} = Tempo.to_interval_set(rset, bound: ~o"2026Y")
      assert "2026Y7M4D" in isos(set)
      assert "2026Y12M25D" in isos(set)
    end

    test "a plain Tempo member stands for its own span" do
      rset = RecurrenceSet.new([~o"2026Y7M4D", named("R/../P1Y/FL12M25DN", "Christmas")])

      {:ok, set} = Tempo.to_interval_set(rset, bound: ~o"2026Y")
      assert isos(set) == ["2026Y7M4D", "2026Y12M25D"]
    end

    test "a member that is not a Tempo value is an error, not a raise" do
      rset = RecurrenceSet.new([named("R/../P1Y/FL12M25DN", "Christmas"), :not_a_member])

      assert {:error, %Tempo.MaterialisationError{reason: :recurrence_set_member}} =
               Tempo.to_interval_set(rset, bound: ~o"2026Y")
    end
  end

  describe "set algebra — the motivating query" do
    test "intersecting a diary with a recurrence set finds the clashes, no explicit bound" do
      {:ok, diary} =
        ["2026Y1M1D", "2026Y6M15D", "2026Y12M25D"]
        |> Enum.map(&Tempo.to_interval!(Tempo.from_iso8601!(&1)))
        |> IntervalSet.new()

      holidays =
        RecurrenceSet.new([
          named("R/../P1Y/FL12M25DN", "Christmas"),
          named("R/../P1Y/FL1M1DN", "New Year")
        ])

      {:ok, clashes} = Tempo.intersection(diary, holidays)
      assert isos(clashes) == ["2026Y1M1D", "2026Y12M25D"]
    end

    test "with the recurrence set first, occurrences keep their names" do
      {:ok, diary} = IntervalSet.new([Tempo.to_interval!(~o"2026Y12M25D")])
      holidays = RecurrenceSet.new([named("R/../P1Y/FL12M25DN", "Christmas")])

      {:ok, clashes} = Tempo.intersection(holidays, diary)
      assert [interval] = IntervalSet.to_list(clashes)
      assert Interval.metadata(interval)[:name] == "Christmas"
    end
  end
end
