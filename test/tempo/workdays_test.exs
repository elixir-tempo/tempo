defmodule Tempo.WorkdaysTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet

  # Good Friday, Easter Monday and Anzac Day, with the additional day for
  # Anzac Day 2027, which fell on a Sunday. Easter 2027 is 28 March.
  defp holidays do
    RecurrenceSet.new!([
      Tempo.every!(~o"P1Y",
        select: [selection: [event: "easter"], window: ~o"-P7D", day_of_week: 5, instance: -1]
      ),
      Tempo.every!(~o"P1Y",
        select: [selection: [event: "easter"], window: ~o"P2D", day_of_week: 1, instance: 1]
      ),
      Tempo.every!(~o"P1Y", select: [month: 4, day: 25]),
      ~o"2027-04-26"
    ])
  end

  defp school_days, do: Tempo.workdays!(:AU, except: holidays())

  defp days(set), do: IntervalSet.members(set)

  # The weekdays, Monday to Friday, from one date through another, as `Date` has them.
  defp weekdays(first, last) do
    Date.range(first, last)
    |> Enum.filter(&(Date.day_of_week(&1) <= 5))
    |> Enum.map(&Tempo.from_elixir!/1)
  end

  describe "workdays/2" do
    test "is the territory's week, with the days off given" do
      assert {:ok, %Tempo.Workdays{weekdays: [1, 2, 3, 4, 5], weekend: [6, 7]}} =
               Tempo.workdays(:AU, except: holidays())

      assert {:ok, %Tempo.Workdays{weekdays: [1, 2, 3, 4, 7], weekend: [5, 6]}} =
               Tempo.workdays(:SA, except: ~o"2027-01-01")
    end

    test "an option it does not take, or days off that are not a Tempo value, is an error" do
      assert {:error, %ArgumentError{}} = Tempo.workdays(:AU, holidays: holidays())
      assert {:error, %ArgumentError{}} = Tempo.workdays(:AU, except: "Christmas")
      assert {:error, %ArgumentError{}} = Tempo.workdays(:AU, :except)

      for territory <- [:"", "", 42, "not a territory"] do
        assert {:error, %ArgumentError{}} = Tempo.workdays(territory, except: holidays())
      end
    end
  end

  describe "the workday functions step over the days off" do
    test "the next and previous workday" do
      # The Anzac Day additional day is Monday 26 April 2027.
      assert Tempo.next_workday(~o"2027-04-23", school_days()) == {:ok, ~o"2027-04-27"}
      assert Tempo.next_workday(~o"2027-04-23", :AU) == {:ok, ~o"2027-04-26"}

      # The last workday before Easter is the Thursday.
      assert Tempo.previous_workday(~o"2027-03-28", school_days()) == {:ok, ~o"2027-03-25"}
    end

    test "adding workdays crosses the Easter weekend both ways" do
      assert Tempo.add_workdays(~o"2027-03-25", 1, school_days()) == {:ok, ~o"2027-03-30"}
      assert Tempo.add_workdays(~o"2027-03-30", -1, school_days()) == {:ok, ~o"2027-03-25"}
      assert Tempo.add_workdays(~o"2027-03-25", 0, school_days()) == {:ok, ~o"2027-03-25"}
    end

    test "the nearest workday to Good Friday is the Thursday" do
      assert Tempo.nearest_workday(~o"2027-03-26", school_days()) == {:ok, ~o"2027-03-25"}
      assert Tempo.nearest_workday(~o"2027-03-25", school_days()) == {:ok, ~o"2027-03-25"}
    end

    test "the nearest workday to a day in a long break is the break's nearer end" do
      # Four weeks off, Monday 5 April to Sunday 2 May 2027.
      break = Tempo.workdays!(:AU, except: ~o"2027-04-05/2027-05-02")

      assert Tempo.nearest_workday(~o"2027-04-18", break) == {:ok, ~o"2027-05-03"}
      assert Tempo.nearest_workday(~o"2027-04-14", break) == {:ok, ~o"2027-04-02"}
    end

    test "workday? and weekend?" do
      refute Tempo.workday?(~o"2027-04-26", school_days())
      assert Tempo.workday?(~o"2027-04-27", school_days())
      assert Tempo.weekend?(~o"2027-04-24", school_days())
      refute Tempo.weekend?(~o"2027-04-26", school_days())
    end

    test "counting a span's workdays leaves the days off out" do
      # Term 2 of 2027, Tuesday 27 April to Friday 2 July: nine weeks and four
      # days, with no day off this set holds (King's Birthday is not in it).
      term = ~o"2027-04-27/2027-07-02"

      expected =
        Enum.count(Date.range(~D[2027-04-27], ~D[2027-07-02]), &(Date.day_of_week(&1) <= 5))

      assert Tempo.count_workdays(term, school_days()) == {:ok, expected}
      assert expected == 49

      assert Tempo.count_workdays(~o"2026-06", Tempo.workdays!(:AU, except: ~o"2026-06-08")) ==
               {:ok, 21}
    end

    test "days off with no end in the direction walked are an error, not a hang" do
      endless = Tempo.workdays!(:AU, except: ~o"2027-04-24/..")

      assert {:error, %Tempo.ConversionError{reason: :open}} =
               Tempo.next_workday(~o"2027-04-23", endless)

      assert {:error, %Tempo.ConversionError{reason: :open}} =
               Tempo.add_workdays(~o"2027-04-22", 2, endless)

      # Walked back, the days off end, and the Thursday is a workday.
      assert Tempo.previous_workday(~o"2027-04-28", endless) == {:ok, ~o"2027-04-23"}
      assert Tempo.nearest_workday(~o"2027-04-28", endless) == {:ok, ~o"2027-04-23"}

      # An open start is endless walked back.
      before = Tempo.workdays!(:AU, except: ~o"../2027-04-23")

      assert {:error, %Tempo.ConversionError{reason: :open}} =
               Tempo.previous_workday(~o"2027-04-27", before)
    end

    test "days off with an end, however long, end" do
      years = Tempo.workdays!(:AU, except: ~o"2027-04-24/2030-12-31")
      assert Tempo.next_workday(~o"2027-04-23", years) == {:ok, ~o"2031-01-01"}
    end
  end

  describe "select/2 with a Tempo.Workdays" do
    test "a bounded span keeps each workday no day off falls on" do
      {:ok, set} = Tempo.select(~o"2027-04-19/2027-04-30", school_days())

      expected = Enum.reject(weekdays(~D[2027-04-19], ~D[2027-04-30]), &(&1 == ~o"2027-04-26"))

      assert days(set) == expected
    end

    test "an open-ended span ends where days off with no end begin" do
      endless = Tempo.workdays!(:AU, except: ~o"2027-04-28/..")
      {:ok, set} = Tempo.select(~o"2027-04-23/..", endless)

      assert Enum.take(set, 6) == weekdays(~D[2027-04-23], ~D[2027-04-27])
    end

    test "a recurrence with no end leaves no day from its start" do
      # Its repetitions follow one another: a year from 25 December, then
      # the next.
      every_day = Tempo.workdays!(:US, except: ~o"R/2026-12-25/P1Y")
      {:ok, set} = Tempo.select(~o"2026-12-21/..", every_day)

      assert Enum.take(set, 10) == weekdays(~D[2026-12-21], ~D[2026-12-24])

      assert {:error, %Tempo.ConversionError{reason: :open}} =
               Tempo.next_workday(~o"2026-12-24", every_day)
    end

    test "an open-ended span goes on after days off with an end" do
      year_off = Tempo.workdays!(:AU, except: ~o"2027-04-28/2028-04-27")
      {:ok, set} = Tempo.select(~o"2027-04-23/..", year_off)

      assert Enum.take(set, 6) ==
               weekdays(~D[2027-04-23], ~D[2027-04-27]) ++
                 weekdays(~D[2028-04-28], ~D[2028-05-02])

      years_off = Tempo.workdays!(:AU, except: ~o"2027-04-28/2031-12-31")
      {:ok, set} = Tempo.select(~o"2027-04-23/..", years_off)

      assert Enum.take(set, 6) ==
               weekdays(~D[2027-04-23], ~D[2027-04-27]) ++
                 weekdays(~D[2032-01-01], ~D[2032-01-05])
    end

    test "an open-ended span is lazy" do
      {:ok, set} = Tempo.select(~o"2027-04-23/..", school_days())

      assert Enum.take(set, 3) ==
               [~o"2027-04-23", ~o"2027-04-27", ~o"2027-04-28"]
    end
  end
end
