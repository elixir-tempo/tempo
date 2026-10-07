defmodule Tempo.SelectFunctionSelectorTest do
  @moduledoc """
  A selector of `Tempo.select/2` that is a function.

  A function is given each period of the base and returns the selector to
  apply in it: any shape `Tempo.select/2` takes, another function among
  them, or an error, which is returned as it is.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  defp days({:ok, %IntervalSet{} = set}),
    do: for(member <- IntervalSet.members(set), do: Tempo.day(Interval.from(member)))

  describe "a selector that is a function" do
    test "selects by what it returns for the period: indexes, a range of them, a value or nothing" do
      assert days(Tempo.select(~o"2026-06", fn _period -> [1, 15] end)) == [1, 15]
      assert days(Tempo.select(~o"2026-06", fn _period -> 1..3 end)) == [1, 2, 3]
      assert days(Tempo.select(~o"2026-06", fn _period -> ~o"15D" end)) == [15]
      assert days(Tempo.select(~o"2026-06", fn _period -> [] end)) == []
    end

    test "is given each period, and may return a function for it" do
      # The last day of each month of a quarter, found from the period.
      last_day = fn %Interval{} = month ->
        fn _the_same_month -> [Tempo.days_in_month(Interval.from(month))] end
      end

      assert days(Tempo.select(~o"2026-04/2026-07", last_day)) == [30, 31, 30]
    end

    test "returns the error the function gives, and refuses what is no selector" do
      refusal = ArgumentError.exception("no holidays are known for that month")

      assert Tempo.select(~o"2026-06", fn _period -> {:error, refusal} end) == {:error, refusal}

      assert {:error, %ArgumentError{} = error} =
               Tempo.select(~o"2026-06", fn _period -> :every_day end)

      assert Exception.message(error) =~ "does not recognise selector :every_day"
    end
  end
end
