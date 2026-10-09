defmodule Tempo.SelectFromGroupsTest do
  @moduledoc """
  A selection from an interval with a group at an end.

  A group is several of a unit taken as one: a quarter (`2026Y1Q`), a half
  (`2026Y1H`), any `nGnMU`. At an end of an interval it is where its span
  starts, as a month is, so `2026Y1Q/2026Y2Q` is January to April, which is
  what `Tempo.to_interval/1` converts it to.

  `Tempo.select/2` walked the interval as it stood, with the months of the
  group at its start: it gave no weekday of the three months, the 15th of
  one of them, and from an interval with no end the months of the group's
  start and then those from its end.

  The measure is `Date` alone: the days from 1 January 2026 to 31 March
  that the selector names. Each form is also held to the same span written
  with months.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.Matrix.Extent

  @epoch ~N[0000-01-01 00:00:00]
  @first_quarter Date.range(~D[2026-01-01], ~D[2026-03-31])

  defp read(text), do: Tempo.from_iso8601!(text)

  defp microseconds(%Date{} = date),
    do: NaiveDateTime.diff(NaiveDateTime.new!(date, ~T[00:00:00]), @epoch, :microsecond)

  defp selected(base, selector) do
    {:ok, set} = Tempo.select(base, selector)
    {:ok, members} = Extent.members(set)
    Enum.map(members, fn %{spans: [span]} -> span end)
  end

  # The days of `dates` that `keep?` holds, each from its midnight to the next.
  defp days(dates, keep?) do
    for date <- dates, keep?.(date), do: {microseconds(date), microseconds(Date.add(date, 1))}
  end

  describe "an interval from one quarter to the next" do
    test "is selected from as the months it spans" do
      for base <- ["2026Y1Q/2026Y2Q", "2026Y1G3MU/2026Y2G3MU", "2026Y33M/2026Y34M"] do
        assert {base, selected(read(base), ~o"1K")} ==
                 {base, days(@first_quarter, &(Date.day_of_week(&1) == 1))}

        assert {base, selected(read(base), ~o"15D")} ==
                 {base, days(@first_quarter, &(&1.day == 15))}

        assert {base, selected(read(base), [1, 2])} ==
                 {base, days(@first_quarter, &(&1.day in [1, 2]))}

        assert {base, selected(read(base), Tempo.workdays(:US))} ==
                 {base, days(@first_quarter, &(Date.day_of_week(&1) in 1..5))}
      end

      # The first quarter of 2026 has thirteen Mondays.
      assert [_ | _] = mondays = days(@first_quarter, &(Date.day_of_week(&1) == 1))
      assert Enum.count(mondays) == 13
    end
  end

  describe "an interval with an end that names several values" do
    # A set or a range at an end is the span from each of its values, and
    # unspecified digits the span of all they stand for, as
    # `Tempo.to_interval/1` converts each. Such an interval was walked as it
    # stood: `2026-XX/2027` gave no Monday of its year.
    test "is selected from as what it converts to" do
      for base <- [
            "2026Y{1,3}M/2026-06",
            "2026-01/2026Y{3,6}M",
            "2026Y{1..2}M/2026-04",
            "2026-XX/2027",
            "2026Y6M{1,15}D/P1D"
          ],
          selector <- [~o"1K", ~o"15D", [1, 2], Tempo.workdays(:US)] do
        {:ok, converted} = Tempo.to_interval(read(base))

        assert {base, selector, Tempo.select(read(base), selector)} ==
                 {base, selector, Tempo.select(converted, selector)}
      end
    end

    test "gives the Mondays of the year unspecified months stand for" do
      year = Date.range(~D[2026-01-01], ~D[2026-12-31])

      assert selected(read("2026-XX/2027"), ~o"1K") == days(year, &(Date.day_of_week(&1) == 1))
    end

    test "gives the Mondays of the span from each month of a set" do
      # From January to June and from March to June, each span's Mondays.
      from_january =
        days(Date.range(~D[2026-01-01], ~D[2026-05-31]), &(Date.day_of_week(&1) == 1))

      from_march = days(Date.range(~D[2026-03-01], ~D[2026-05-31]), &(Date.day_of_week(&1) == 1))

      assert Enum.sort(selected(read("2026Y{1,3}M/2026-06"), ~o"1K")) ==
               Enum.sort(from_january ++ from_march)
    end

    test "is the error of an interval that converts to none" do
      assert {:error, %IntervalEndpointsError{}} = Tempo.select(read("2026Y{1,3}M/.."), ~o"1K")
    end
  end

  describe "an interval with a group at one end, or at each" do
    @written_with_months [
      {"2026Y1Q/2026Y2Q", "2026-01/2026-04"},
      {"2026Y1Q/2026-04", "2026-01/2026-04"},
      {"2026-01/2026Y2Q", "2026-01/2026-04"},
      {"2026Y1H/2026Y2H", "2026-01/2026-07"},
      {"2026Y3Q/2027Y1Q", "2026-07/2027-01"},
      {"2026Y1Q/P2M", "2026-01/P2M"},
      {"2026Y2G2MU/2026Y5G2MU", "2026-03/2026-09"}
    ]

    test "is selected from as the same span written with months" do
      for {grouped, plain} <- @written_with_months,
          selector <- [~o"1K", ~o"15D", ~o"1D", [1, 2], Tempo.workdays(:US), ~o"L1K1IN"] do
        assert {grouped, selector, Tempo.select(read(grouped), selector)} ==
                 {grouped, selector, Tempo.select(read(plain), selector)}
      end
    end

    test "is counted as the same span is" do
      for {grouped, plain} <- @written_with_months do
        assert {grouped, Tempo.count_workdays(read(grouped), :US)} ==
                 {grouped, Tempo.count_workdays(read(plain), :US)}
      end
    end

    test "with no end is walked from the month its group starts in" do
      for selector <- [~o"1K", ~o"15D", [1, 2], Tempo.workdays(:US)] do
        {:ok, grouped} = Tempo.select(read("2026Y1Q/.."), selector)
        {:ok, plain} = Tempo.select(~o"2026-01/..", selector)

        refute IntervalSet.bounded?(grouped)

        assert {selector, grouped |> IntervalSet.walk() |> Enum.take(40)} ==
                 {selector, plain |> IntervalSet.walk() |> Enum.take(40)}
      end
    end
  end
end
