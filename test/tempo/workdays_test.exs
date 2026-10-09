defmodule Tempo.WorkdaysTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet

  # Good Friday, Easter Monday and Anzac Day, with the additional day for
  # Anzac Day 2027, which fell on a Sunday.
  defp holidays do
    RecurrenceSet.new!([
      ~o"R/../P1Y/FLLL(easter)eN/P-3DN5K1IN",
      ~o"R/../P1Y/FLLL(easter)eN/P2DN1K1IN",
      ~o"R/../P1Y/FL4M25DN",
      ~o"2027-04-26"
    ])
  end

  defp school_days, do: Tempo.workdays(:AU, except: holidays())

  defp days(set), do: set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)

  describe "workdays/2" do
    test "without :except is the day-of-week selector it always was" do
      assert %Tempo{time: [day_of_week: [1, 2, 3, 4, 5]]} = Tempo.workdays(:AU)
      assert Tempo.workdays(:AU, []) == Tempo.workdays(:AU)
    end

    test "with :except is a Tempo.Workdays of the territory's week" do
      assert %Tempo.Workdays{weekdays: [1, 2, 3, 4, 5], weekend: [6, 7]} = school_days()

      assert %Tempo.Workdays{weekdays: [1, 2, 3, 4, 7], weekend: [5, 6]} =
               Tempo.workdays(:SA, except: ~o"2027-01-01")
    end

    test "an option it does not take, or holidays that are not a Tempo value, is an error" do
      assert {:error, %ArgumentError{}} = Tempo.workdays(:AU, holidays: holidays())
      assert {:error, %ArgumentError{}} = Tempo.workdays(:AU, except: "Christmas")
      assert {:error, %ArgumentError{}} = Tempo.workdays(:AU, :except)

      for territory <- [:"", "", 42, "not a territory"] do
        assert {:error, %ArgumentError{}} = Tempo.workdays(territory, except: holidays())
      end
    end
  end

  describe "the workday functions step over the holidays" do
    test "the next and previous workday" do
      # The Anzac Day additional day is Monday 26 April 2027.
      assert Tempo.next_workday(~o"2027-04-23", school_days()) == ~o"2027Y4M27D"
      assert Tempo.next_workday(~o"2027-04-23", :AU) == ~o"2027Y4M26D"

      # The last workday before Easter is the Thursday.
      assert Tempo.previous_workday(~o"2027-03-28", school_days()) == ~o"2027Y3M25D"
    end

    test "adding workdays crosses the Easter weekend both ways" do
      assert Tempo.add_workdays(~o"2027-03-25", 1, school_days()) == ~o"2027Y3M30D"
      assert Tempo.add_workdays(~o"2027-03-30", -1, school_days()) == ~o"2027Y3M25D"
      assert Tempo.add_workdays(~o"2027-03-25", 0, school_days()) == ~o"2027Y3M25D"
    end

    test "the nearest workday to Good Friday is the Thursday" do
      assert Tempo.nearest_workday(~o"2027-03-26", school_days()) == ~o"2027Y3M25D"
      assert Tempo.nearest_workday(~o"2027-03-25", school_days()) == ~o"2027Y3M25D"
    end

    test "the nearest workday to a day in a long break is the break's nearer end" do
      # Four weeks off, from Monday 5 April to Sunday 2 May 2027.
      break = Tempo.workdays(:AU, except: ~o"2027-04-05/2027-05-03")

      assert Tempo.nearest_workday(~o"2027-04-18", break) == ~o"2027Y5M3D"
      assert Tempo.nearest_workday(~o"2027-04-14", break) == ~o"2027Y4M2D"
    end

    test "workday? and weekend?" do
      refute Tempo.workday?(~o"2027-04-26", school_days())
      assert Tempo.workday?(~o"2027-04-27", school_days())
      assert Tempo.weekend?(~o"2027-04-24", school_days())
      refute Tempo.weekend?(~o"2027-04-26", school_days())
    end

    test "counting a span's workdays leaves the holidays out" do
      # Term 2 of 2027: ten weeks less the Anzac additional day and King's
      # Birthday, which this set does not hold.
      assert Tempo.count_workdays(~o"2027-04-27/2027-07-03", school_days()) == 49
      assert Tempo.count_workdays(~o"2026-06", Tempo.workdays(:AU, except: ~o"2026-06-08")) == 21
    end

    test "days off with no end, or more than a thousand in a row, are an error, not a hang" do
      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Tempo.next_workday(~o"2027-04-23", Tempo.workdays(:AU, except: ~o"2027-04-24/.."))

      closed = Tempo.workdays(:AU, except: ~o"2027-04-24/2031-01-01")
      assert {:error, %ArgumentError{}} = Tempo.next_workday(~o"2027-04-23", closed)

      decade = Tempo.workdays(:AU, except: ~o"2020-01-01/2031-01-01")
      assert {:error, %ArgumentError{}} = Tempo.nearest_workday(~o"2025-06-16", decade)
    end
  end

  describe "select/2 with a Tempo.Workdays" do
    test "a bounded span keeps each workday no holiday falls on" do
      {:ok, set} = Tempo.select(~o"2027-04-19/2027-05-01", school_days())

      assert days(set) == [
               "2027Y4M19D/20D",
               "2027Y4M20D/21D",
               "2027Y4M21D/22D",
               "2027Y4M22D/23D",
               "2027Y4M23D/24D",
               "2027Y4M27D/28D",
               "2027Y4M28D/29D",
               "2027Y4M29D/30D",
               "2027Y4M30D/5M1D"
             ]
    end

    test "an open-ended span is lazy" do
      {:ok, set} = Tempo.select(~o"2027-04-23/..", school_days())

      refute IntervalSet.bounded?(set)

      assert set |> IntervalSet.walk() |> Enum.take(3) |> Enum.map(&Tempo.to_iso8601!/1) ==
               ["2027Y4M23D/24D", "2027Y4M27D/28D", "2027Y4M28D/29D"]
    end

    # The weekdays, Monday to Friday, from one date up to another, as `Date`
    # has them.
    defp weekdays(%Date{} = from, %Date{} = before) do
      from
      |> Date.range(Date.add(before, -1))
      |> Enum.filter(&(Date.day_of_week(&1) in 1..5))
      |> Enum.map(&Tempo.to_iso8601!(Tempo.to_interval!(Tempo.from_elixir(&1))))
    end

    defp walked(base, workdays, count) do
      {:ok, set} = Tempo.select(base, workdays)
      set |> IntervalSet.walk() |> Enum.take(count) |> Enum.map(&Tempo.to_iso8601!/1)
    end

    test "an open-ended span with holidays that have no end is the error the next workday is" do
      closed = Tempo.workdays(:AU, except: ~o"2027-04-28/..")

      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Tempo.next_workday(~o"2027-04-27", closed)

      assert {:error, %Tempo.IntervalEndpointsError{}} = Tempo.select(~o"2027-04-23/..", closed)
    end

    test "an open-ended span ends where a recurrence's spans leave no day between them" do
      # An ISO 8601 recurrence's occurrences are each a cadence long: a year
      # from 25 December, and then the next. The walk was asked each day
      # after it for ever, so nothing that took more days than the four
      # before it was answered.
      every_day = Tempo.workdays(:US, except: ~o"R/2026-12-25/P1Y")

      assert walked(~o"2026-12-21/..", every_day, 10) == weekdays(~D[2026-12-21], ~D[2026-12-25])
    end

    test "an open-ended span goes on after holidays of fewer days than a step passes" do
      # A year of holidays is 261 working days: the walk passes them.
      year_off = Tempo.workdays(:AU, except: ~o"2027-04-28/2028-04-28")

      assert walked(~o"2027-04-23/..", year_off, 6) ==
               weekdays(~D[2027-04-23], ~D[2027-04-28]) ++
                 weekdays(~D[2028-04-28], ~D[2028-05-03])
    end

    test "an open-ended span ends at holidays of more days than a step passes" do
      # As `Tempo.next_workday/2` is an error for more than a thousand days
      # off in a row, the walk ends at them.
      years_off = Tempo.workdays(:AU, except: ~o"2027-04-28/2032-01-01")

      assert {:error, %ArgumentError{}} = Tempo.next_workday(~o"2027-04-27", years_off)
      assert walked(~o"2027-04-23/..", years_off, 6) == weekdays(~D[2027-04-23], ~D[2027-04-28])
    end
  end
end
