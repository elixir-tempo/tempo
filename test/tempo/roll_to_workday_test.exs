defmodule Tempo.RollToWorkdayTest do
  @moduledoc """
  A day rolled to a workday by the business day conventions (decided
  2026-10-07).

  `Tempo.roll_to_workday/3` gives a workday as it is and rolls a day off:
  following to the first workday after it, preceding to the first before,
  and by a modified convention the other way where the workday it rolls to
  is in another month.

  The measure is Elixir's own `Date`: a day's day of the week, a weekend
  written here as the days of the week it is, the holidays a list of dates,
  and the roll walked a day at a time.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Tempo.Compare
  alias Tempo.IntervalSet

  @rolls [:following, :preceding, :modified_following, :modified_preceding]

  ## The measure

  # The ISO days of the week (1 is Monday) of each territory's weekend.
  @us_weekend [6, 7]
  @weekends %{US: @us_weekend, SA: [5, 6], IN: [7]}

  defp off?(date, weekend, holidays) do
    day_of_week = date |> Date.convert!(Calendar.ISO) |> Date.day_of_week()
    day_of_week in weekend or date in holidays
  end

  defp first_workday(date, step, weekend, holidays) do
    next = Date.add(date, step)
    if off?(next, weekend, holidays), do: first_workday(next, step, weekend, holidays), else: next
  end

  defp rolled(date, roll, weekend, holidays) do
    if off?(date, weekend, holidays), do: rolled_off(date, roll, weekend, holidays), else: date
  end

  defp rolled_off(date, :following, weekend, holidays),
    do: first_workday(date, 1, weekend, holidays)

  defp rolled_off(date, :preceding, weekend, holidays),
    do: first_workday(date, -1, weekend, holidays)

  defp rolled_off(date, :modified_following, weekend, holidays),
    do: in_its_month(date, 1, weekend, holidays)

  defp rolled_off(date, :modified_preceding, weekend, holidays),
    do: in_its_month(date, -1, weekend, holidays)

  defp in_its_month(date, step, weekend, holidays) do
    workday = first_workday(date, step, weekend, holidays)

    if {workday.year, workday.month} == {date.year, date.month},
      do: workday,
      else: first_workday(date, -step, weekend, holidays)
  end

  defp date_of(%Tempo{} = day) do
    {:ok, date} = Tempo.to_date(day)
    date
  end

  describe "a day rolled to a workday" do
    test "is the day Elixir's Date rolls to, by each convention, in three territories" do
      for {territory, weekend} <- @weekends,
          date <- Date.range(~D[2026-01-01], ~D[2027-12-31]),
          roll <- @rolls do
        expected = rolled(date, roll, weekend, [])
        workday = Tempo.roll_to_workday(Tempo.from_date(date), territory, roll: roll)

        assert {territory, date, roll, date_of(workday)} == {territory, date, roll, expected}
      end
    end

    test "is the decision's Saturday 30 May 2026, and a Sunday that begins a month" do
      assert Date.day_of_week(~D[2026-05-30]) == 6

      assert Tempo.roll_to_workday(~o"2026-05-30", :US) == ~o"2026-06-01"
      assert Tempo.roll_to_workday(~o"2026-05-30", :US, roll: :following) == ~o"2026-06-01"

      assert Tempo.roll_to_workday(~o"2026-05-30", :US, roll: :modified_following) ==
               ~o"2026-05-29"

      assert Tempo.roll_to_workday(~o"2026-05-30", :US, roll: :preceding) == ~o"2026-05-29"

      assert Tempo.roll_to_workday(~o"2026-05-30", :US, roll: :modified_preceding) ==
               ~o"2026-05-29"

      assert Date.day_of_week(~D[2026-11-01]) == 7

      assert Tempo.roll_to_workday(~o"2026-11-01", :US, roll: :preceding) == ~o"2026-10-30"

      assert Tempo.roll_to_workday(~o"2026-11-01", :US, roll: :modified_preceding) ==
               ~o"2026-11-02"
    end

    test "leaves a workday where it is, where the next workday moves it" do
      for roll <- @rolls do
        assert Tempo.roll_to_workday(~o"2026-05-29", :US, roll: roll) == ~o"2026-05-29"
      end

      assert Tempo.next_workday(~o"2026-05-29", :US) == ~o"2026-06-01"
    end

    test "is not the nearest workday, which takes the closer side" do
      # A Sunday's nearest workday is the Monday, and the one preceding it the Friday.
      assert Tempo.nearest_workday(~o"2026-06-14", :US) == ~o"2026-06-15"
      assert Tempo.roll_to_workday(~o"2026-06-14", :US, roll: :preceding) == ~o"2026-06-12"

      # A Saturday's is the Friday, and the one following it the Monday.
      assert Tempo.nearest_workday(~o"2026-06-13", :US) == ~o"2026-06-12"
      assert Tempo.roll_to_workday(~o"2026-06-13", :US, roll: :following) == ~o"2026-06-15"
    end
  end

  describe "a day rolled over holidays" do
    # The last Friday of May and the first Monday of June, the day before
    # Independence Day, and Christmas to the new year.
    @holidays [
                ~D[2026-05-29],
                ~D[2026-06-01],
                ~D[2026-07-03]
              ] ++ Enum.to_list(Date.range(~D[2026-12-24], ~D[2027-01-01]))

    defp business_days(dates) do
      days = Enum.map(dates, &(&1 |> Tempo.from_date() |> Tempo.to_interval!()))
      Tempo.workdays(:US, except: IntervalSet.new!(days))
    end

    test "is the day Elixir's Date rolls to with the holidays days off" do
      business_days = business_days(@holidays)

      for range <- [
            Date.range(~D[2026-05-20], ~D[2026-07-10]),
            Date.range(~D[2026-12-15], ~D[2027-01-10])
          ],
          date <- range,
          roll <- @rolls do
        expected = rolled(date, roll, @us_weekend, @holidays)
        workday = Tempo.roll_to_workday(Tempo.from_date(date), business_days, roll: roll)

        assert {date, roll, date_of(workday)} == {date, roll, expected}
      end
    end

    test "turns back over a holiday, and forward over one" do
      business_days = business_days(@holidays)

      # Saturday 30 May: Monday 1 June is a holiday and Tuesday is in June,
      # so the modified roll turns back, over Friday the 29th, to Thursday.
      assert Tempo.roll_to_workday(~o"2026-05-30", business_days) == ~o"2026-06-02"

      assert Tempo.roll_to_workday(~o"2026-05-30", business_days, roll: :modified_following) ==
               ~o"2026-05-28"

      # Friday 1 January 2027: the workday before it is 23 December, in
      # another month, so the modified roll goes forward to Monday the 4th.
      assert Tempo.roll_to_workday(~o"2027-01-01", business_days, roll: :preceding) ==
               ~o"2026-12-23"

      assert Tempo.roll_to_workday(~o"2027-01-01", business_days, roll: :modified_preceding) ==
               ~o"2027-01-04"
    end

    test "turns back out of a month that has no workday, as the convention has it" do
      august_off = Tempo.workdays(:US, except: ~o"2026-08")
      august = Enum.to_list(Date.range(~D[2026-08-01], ~D[2026-08-31]))

      for date <- [~D[2026-08-01], ~D[2026-08-15], ~D[2026-08-31]], roll <- @rolls do
        expected = rolled(date, roll, @us_weekend, august)
        workday = Tempo.roll_to_workday(Tempo.from_date(date), august_off, roll: roll)

        assert {date, roll, date_of(workday)} == {date, roll, expected}
      end

      # The first workday after August is in September, so the modified
      # roll takes the first before it, which is in July.
      assert Tempo.roll_to_workday(~o"2026-08-15", august_off, roll: :modified_following) ==
               ~o"2026-07-31"
    end
  end

  describe "a day rolled in each form a day is written in" do
    test "keeps its time of day and its zone" do
      assert Tempo.roll_to_workday(~o"2026-05-30T10:30", :US) == ~o"2026-06-01T10:30"

      assert Tempo.roll_to_workday(~o"2026-05-30T10:30[Europe/Paris]", :US,
               roll: :modified_following
             ) == ~o"2026-05-29T10:30[Europe/Paris]"

      # Paris's clocks go forward on Sunday 29 March 2026, between the
      # Saturday and the Monday it rolls to.
      rolled = Tempo.roll_to_workday(~o"2026-03-28T10:30[Europe/Paris]", :US)
      monday = DateTime.new!(~D[2026-03-30], ~T[10:30:00], "Europe/Paris")
      epoch = :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

      assert Compare.to_utc_seconds(rolled) - epoch == DateTime.to_unix(monday)
    end

    test "is rolled from a date of a week and from a day of the year" do
      # Saturday 30 May 2026 is the sixth day of week 22 and day 150.
      assert Date.new!(2026, 1, 1) |> Date.add(149) == ~D[2026-05-30]
      assert :calendar.iso_week_number({2026, 5, 30}) == {2026, 22}

      for text <- ["2026-W22-6", "2026-150"], roll <- @rolls do
        expected = rolled(~D[2026-05-30], roll, @us_weekend, [])
        workday = Tempo.roll_to_workday(Tempo.from_iso8601!(text), :US, roll: roll)

        assert {text, roll, date_of(workday)} == {text, roll, expected}
      end
    end

    test "stays in the month of its own calendar" do
      # The days of the Hebrew year 5786 from Kislev to Adar, each rolled
      # within its Hebrew month, which ends where no Gregorian month does.
      for gregorian <- Date.range(~D[2025-11-21], ~D[2026-03-18]),
          roll <- @rolls do
        date = Date.convert!(gregorian, Hebrew)
        expected = rolled(date, roll, @us_weekend, [])
        workday = Tempo.roll_to_workday(Tempo.from_date(date), :US, roll: roll)

        assert {date, roll, date_of(workday)} == {date, roll, expected}
      end

      # Some day of them rolls otherwise within its Gregorian month.
      assert Enum.any?(Date.range(~D[2025-11-21], ~D[2026-03-18]), fn gregorian ->
               in_hebrew =
                 gregorian |> Date.convert!(Hebrew) |> rolled(:modified_following, [6, 7], [])

               in_hebrew !=
                 Date.convert!(rolled(gregorian, :modified_following, [6, 7], []), Hebrew)
             end)
    end
  end

  describe "the options" do
    test "are taken in the territory's place, for the territory the chain gives" do
      for roll <- @rolls, day <- [~o"2026-05-30", ~o"2026-11-01", ~o"2026-05-29"] do
        assert Tempo.roll_to_workday(day, roll: roll) ==
                 Tempo.roll_to_workday(day, nil, roll: roll)
      end

      assert Tempo.roll_to_workday(~o"2026-05-30") == Tempo.roll_to_workday(~o"2026-05-30", nil)

      assert Tempo.roll_to_workday(~o"2026-05-30", []) ==
               Tempo.roll_to_workday(~o"2026-05-30", nil)

      assert %Tempo{} = Tempo.roll_to_workday(~o"2026-05-30", roll: :preceding)
    end

    test "of workdays/2 are taken in the territory's place too" do
      assert %Tempo.Workdays{} = business_days = Tempo.workdays(except: ~o"2026-06-08")

      assert business_days == Tempo.workdays(nil, except: ~o"2026-06-08")
      assert Tempo.workdays([]) == Tempo.workdays()
      assert {:error, %ArgumentError{}} = Tempo.workdays(holidays: ~o"2026-06-08")
    end

    test "are refused where they are not a convention this takes" do
      for options <- [
            [roll: :nearest],
            [roll: "following"],
            [roll: nil],
            [rolls: :following],
            [roll: :following, within: ~o"2026"],
            [roll: :following, roll: :preceding],
            :following,
            [:following]
          ] do
        assert {:error, %ArgumentError{} = error} =
                 Tempo.roll_to_workday(~o"2026-05-30", :US, options)

        assert Exception.message(error) =~ ":modified_preceding"
      end

      assert {:error, %ArgumentError{}} = Tempo.roll_to_workday(~o"2026-05-30", rolls: :following)
    end
  end

  describe "what is not rolled" do
    test "is a value that denotes no one day" do
      for roll <- @rolls do
        assert {:error, %Tempo.ResolutionError{operation: :roll_to_workday, target: :day}} =
                 Tempo.roll_to_workday(~o"2026-05", :US, roll: roll)

        assert {:error, %Tempo.ResolutionError{operation: :roll_to_workday}} =
                 Tempo.roll_to_workday(~o"2026Y5M{30,31}D", :US, roll: roll)

        assert {:error, %Tempo.UnanchoredError{operation: :roll_to_workday}} =
                 Tempo.roll_to_workday(~o"T10", :US, roll: roll)

        assert {:error, %Tempo.ConversionError{reason: :grouped_component}} =
                 Tempo.roll_to_workday(~o"2026Y{1,2}G3MU", :US, roll: roll)
      end

      for value <- [~o"2026-05-30/2026-06-02", ~o"P1D", ~D[2026-05-30], "2026-05-30", nil] do
        assert {:error, %ArgumentError{}} = Tempo.roll_to_workday(value, :US)
        assert {:error, %ArgumentError{}} = Tempo.roll_to_workday(value, roll: :preceding)
      end
    end

    test "is a day in a territory that is none" do
      for territory <- [:"", "", 42, "not a territory"] do
        assert {:error, %ArgumentError{}} =
                 Tempo.roll_to_workday(~o"2026-05-30", territory, roll: :preceding)
      end
    end

    test "is a day of a calendar of weeks by a modified convention, which has no month" do
      saturday = Tempo.from_iso8601!("2026-W22-6[u-ca=iso-week]")
      friday = Tempo.from_iso8601!("2026-W22-5[u-ca=iso-week]")

      for roll <- [:modified_following, :modified_preceding], day <- [saturday, friday] do
        assert {:error,
                %Tempo.ResolutionError{
                  operation: :roll_to_workday,
                  target: :month,
                  calendar: Calendrical.ISOWeek
                } = error} = Tempo.roll_to_workday(day, :US, roll: roll)

        assert Exception.message(error) =~ "calendar of weeks"
      end

      # The conventions that ask no month are answered there.
      assert Tempo.roll_to_workday(saturday, :US, roll: :following) ==
               Tempo.from_iso8601!("2026-W23-1[u-ca=iso-week]")

      assert Tempo.roll_to_workday(saturday, :US, roll: :preceding) == friday
      assert Tempo.roll_to_workday(friday, :US) == friday
    end
  end
end
