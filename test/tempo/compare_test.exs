defmodule Tempo.CompareTest do
  use ExUnit.Case, async: true

  # `Tempo.compare/3` orders by where two expressions begin and, by default,
  # by where they end when they begin together; `by: :start` compares where
  # they begin alone (decision 64), as a consumer ordering the starts of
  # sessions or a cutoff against a day does.

  import Tempo.Sigils

  test "by default two that begin together are ordered by where they end" do
    assert Tempo.compare(~o"2026-06-15T00", ~o"2026-06-15") == :lt
    assert Tempo.compare(~o"2026-06-15", ~o"2026-06-15T00") == :gt

    assert Tempo.compare(
             ~o"2026-06-15T09:00/2026-06-15T10:00",
             ~o"2026-06-15T09:00/2026-06-15T11:00"
           ) ==
             :lt
  end

  test "by start, two that begin together are equal however long each is" do
    assert Tempo.compare(~o"2026-06-15T00", ~o"2026-06-15", by: :start) == :eq

    assert Tempo.compare(
             ~o"2026-06-15T09:00/2026-06-15T10:00",
             ~o"2026-06-15T09:00/2026-06-15T11:00",
             by: :start
           ) ==
             :eq

    assert Tempo.compare(~o"2026-06-15T09", ~o"2026-06-15T10", by: :start) == :lt
    assert Tempo.compare(~o"2026-06-16", ~o"2026-06-15T23", by: :start) == :gt
  end

  test "by start compares the moments where each begins across zones" do
    assert Tempo.compare(~o"2026-06-15T09:00Z", ~o"2026-06-15T10:00[Europe/London]", by: :start) ==
             :eq

    assert Tempo.compare(~o"2026-06-15T09:00Z", ~o"2026-06-15T11:00[Europe/Paris]", by: :start) ==
             :eq
  end

  test "a set is placed by its first span" do
    assert Tempo.compare(~o"{2026-06-15,2026-07-01}", ~o"2026-06-15T00", by: :start) == :eq
  end

  test "sorting by start keeps those that begin together in their order" do
    day = ~o"2026-06-15"
    hour = ~o"2026-06-15T00"
    sorter = fn a, b -> Tempo.compare(a, b, by: :start) != :gt end

    assert Enum.sort([day, ~o"2026-06-14", hour], sorter) == [~o"2026-06-14", day, hour]
  end

  test "what is compared is :start_and_end or :start" do
    assert_raise ArgumentError, ~r/:by is :start_and_end or :start/, fn ->
      Tempo.compare(~o"2026-06-15", ~o"2026-06-16", by: :end)
    end
  end
end
