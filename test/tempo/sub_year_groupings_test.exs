defmodule Tempo.SubYearGroupingsTest do
  use ExUnit.Case, async: true

  # ISO 8601-2 section 4.8.1: the sub-year groupings 33 to 41 are the
  # quarters (three months each), the quadrimesters (four) and the
  # semestrals (six). Each is held to the months the standard names, the
  # instants made with `Date`.

  import Tempo.Sigils

  alias Tempo.Interval

  @groupings [
    {~o"2026-33", 1, 3},
    {~o"2026-34", 4, 3},
    {~o"2026-35", 7, 3},
    {~o"2026-36", 10, 3},
    {~o"2026-37", 1, 4},
    {~o"2026-38", 5, 4},
    {~o"2026-39", 9, 4},
    {~o"2026-40", 1, 6},
    {~o"2026-41", 7, 6}
  ]

  defp first_of(year, month), do: NaiveDateTime.new!(Date.new!(year, month, 1), ~T[00:00:00])

  defp after_months(year, month, months) do
    next = month + months
    if next > 12, do: first_of(year + 1, next - 12), else: first_of(year, next)
  end

  test "each grouping is the months the standard names" do
    for {grouping, first_month, months} <- @groupings do
      {:ok, span} = Tempo.to_interval(grouping)

      assert {grouping, Interval.instants(span)} ==
               {grouping,
                {:ok, {first_of(2026, first_month), after_months(2026, first_month, months)}}}
    end
  end

  test "each grouping holds the days of its months" do
    for {grouping, first_month, months} <- @groupings do
      days =
        Date.diff(
          NaiveDateTime.to_date(after_months(2026, first_month, months)),
          Date.new!(2026, first_month, 1)
        )

      {:ok, walked} = Tempo.walk(grouping, :day)

      assert {grouping, Enum.count(walked)} == {grouping, days}
    end
  end

  test "a year walked at the quarter is its four quarters" do
    assert {:ok, quarters} = Tempo.walk(~o"2026", :quarter)
    assert Enum.to_list(quarters) == [~o"2026-33", ~o"2026-34", ~o"2026-35", ~o"2026-36"]
  end
end
