defmodule Tempo.Protocol.InspectIntervalSetTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  defp set(sigil) do
    sigil
    |> Tempo.to_interval_set()
    |> elem(1)
  end

  test "an empty set inspects as an empty list" do
    assert inspect(%IntervalSet{intervals: []}) == "#Tempo.IntervalSet<[]>"
  end

  # Materialised members keep year-resolution bounds and carry their
  # iteration granularity as a `unit:` decoration (non-syntactic state,
  # like metadata) rather than drilled `1M` endpoint components.

  test "a small set inspects its members inline" do
    assert inspect(set(~o"{2021,2022,2023}Y")) ==
             ~s|#Tempo.IntervalSet<[#Tempo.Interval<~o"2021Y/2022Y" unit: month>, #Tempo.Interval<~o"2022Y/2023Y" unit: month>, #Tempo.Interval<~o"2023Y/2024Y" unit: month>]>|
  end

  test "a set within the inspect limit shows every member inline" do
    assert inspect(set(~o"{2021,2022,2023,2024,2025}Y")) ==
             ~s|#Tempo.IntervalSet<[#Tempo.Interval<~o"2021Y/2022Y" unit: month>, #Tempo.Interval<~o"2022Y/2023Y" unit: month>, #Tempo.Interval<~o"2023Y/2024Y" unit: month>, #Tempo.Interval<~o"2024Y/2025Y" unit: month>, #Tempo.Interval<~o"2025Y/2026Y" unit: month>]>|
  end

  test "a set larger than :limit shows that many members then the locale ellipsis" do
    assert inspect(set(~o"{2021,2022,2023,2024,2025}Y"), limit: 2) ==
             ~s|#Tempo.IntervalSet<[#Tempo.Interval<~o"2021Y/2022Y" unit: month>, #Tempo.Interval<~o"2022Y/2023Y" unit: month>, …]>|
  end

  test "the inspect limit is honoured as :infinity" do
    assert inspect(set(~o"{2021,2022,2023,2024,2025}Y"), limit: :infinity) ==
             ~s|#Tempo.IntervalSet<[#Tempo.Interval<~o"2021Y/2022Y" unit: month>, #Tempo.Interval<~o"2022Y/2023Y" unit: month>, #Tempo.Interval<~o"2023Y/2024Y" unit: month>, #Tempo.Interval<~o"2024Y/2025Y" unit: month>, #Tempo.Interval<~o"2025Y/2026Y" unit: month>]>|
  end

  test "a calendar name in metadata is shown in the tag" do
    set = %IntervalSet{intervals: [], metadata: %{name: "Holidays"}}
    assert inspect(set) == "#Tempo.IntervalSet<[] · Holidays>"
  end

  test "a prodid in metadata is shown in the tag" do
    set = %IntervalSet{intervals: [], metadata: %{prodid: "-//Acme//EN"}}
    assert inspect(set) == "#Tempo.IntervalSet<[] · -//Acme//EN>"
  end

  test "other metadata falls back to a key count" do
    set = %IntervalSet{intervals: [], metadata: %{source: :ical, imported_at: :now}}
    assert inspect(set) == "#Tempo.IntervalSet<[] · 2 metadata key(s)>"
  end
end
