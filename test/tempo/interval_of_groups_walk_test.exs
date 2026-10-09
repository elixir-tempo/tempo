defmodule Tempo.IntervalOfGroupsWalkTest do
  @moduledoc """
  The walk of an interval with a group at an end.

  A group is several of a unit taken as one (a quarter, `2026Y1Q`), and at
  an end of an interval it is where its span starts: `2026Y1Q/2026Y2Q` is
  January to April, as `Tempo.to_interval/1` converts it. `Enum` raised for
  it, a step having no one value to count from, where every other operation
  read it as that span.

  The measure is `Date` alone: the months from January 2026 up to April,
  and each form is held to the same span written with months.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  defp read(text), do: Tempo.from_iso8601!(text)

  # The months of 2026 from one up to another, as `Calendar.strftime/2`
  # writes a year and a month.
  defp months(first, before) do
    for month <- first..(before - 1)//1 do
      read(Calendar.strftime(Date.new!(2026, month, 1), "%Y-%m"))
    end
  end

  @written_with_months [
    {"2026Y1Q/2026Y2Q", "2026-01/2026-04"},
    {"2026Y1Q/2026-04", "2026-01/2026-04"},
    {"2026-01/2026Y2Q", "2026-01/2026-04"},
    {"2026Y1H/2026Y2H", "2026-01/2026-07"},
    {"2026Y2G2MU/2026Y5G2MU", "2026-03/2026-09"}
  ]

  describe "an interval with a group at an end" do
    test "is walked by the months it spans" do
      assert Enum.to_list(read("2026Y1Q/2026Y2Q")) == months(1, 4)
      assert Enum.to_list(read("2026Y1H/2026Y2H")) == months(1, 7)
      assert Enum.to_list(read("2026Y2G2MU/2026Y5G2MU")) == months(3, 9)
    end

    test "is walked, counted and asked of as the same span written with months" do
      for {grouped, plain} <- @written_with_months do
        grouped_interval = read(grouped)
        plain_interval = read(plain)

        assert {grouped, Enum.to_list(grouped_interval)} ==
                 {grouped, Enum.to_list(plain_interval)}

        assert {grouped, Enum.count(grouped_interval)} == {grouped, Enum.count(plain_interval)}
        assert {grouped, Enum.at(grouped_interval, 1)} == {grouped, Enum.at(plain_interval, 1)}

        assert {grouped, Enum.slice(grouped_interval, 1, 2)} ==
                 {grouped, Enum.slice(plain_interval, 1, 2)}

        for month <- [~o"2026-02", ~o"2026-11"] do
          assert {grouped, month, Enum.member?(grouped_interval, month)} ==
                   {grouped, month, Enum.member?(plain_interval, month)}
        end
      end
    end

    test "with no end is walked from the month its group starts in" do
      assert Enum.take(read("2026Y1Q/.."), 5) == months(1, 6)
      assert Enum.take(read("2026Y1Q/.."), 5) == Enum.take(~o"2026-01/..", 5)
    end

    test "written with a duration is walked as the span it is" do
      assert Enum.to_list(read("2026Y1Q/P2M")) == Enum.to_list(~o"2026-01/P2M")
    end
  end
end
