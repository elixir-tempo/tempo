defmodule Tempo.SelectOneImplementationTest do
  @moduledoc """
  A constraint of `Tempo.select/2` and the selection of the same parts are
  one implementation (decided 2026-10-07).

  A constraint (`~o"15D"`) was merged onto the start of its period and a
  selection (`~o"L15DN"`) was resolved by `Tempo.RRule.Selection`: two
  implementations that gave the same spans, a merged day walked by its
  hours and a resolved one as the one day. The resolver serves both, and a
  point it makes is the value it is, with the span and the unit
  `Tempo.to_interval/1` gives the value.

  The measure of what is selected is Elixir's own `Date`, `NaiveDateTime`
  and `DateTime`. What a selected point is, is `Tempo.to_interval/1` of the
  value itself.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.ISOWeek
  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet

  ## The measure

  defp seconds(%Date{} = date), do: seconds(NaiveDateTime.new!(date, ~T[00:00:00]))

  defp seconds(%NaiveDateTime{} = moment),
    do: moment |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  defp members({:ok, %IntervalSet{} = set}), do: IntervalSet.members(set)

  defp spans(selected), do: selected |> members() |> Enum.map(&bounds/1)

  defp read(text, calendar \\ Calendrical.Gregorian), do: Tempo.from_iso8601!(text, calendar)

  # Bases of each resolution, a span of several periods, a zoned day, and a
  # month and a year of two other calendars.
  @bases [
    {"2026", Calendrical.Gregorian},
    {"2024", Calendrical.Gregorian},
    {"2026-06", Calendrical.Gregorian},
    {"2024-02", Calendrical.Gregorian},
    {"2026-W25", Calendrical.Gregorian},
    {"2026-06-15", Calendrical.Gregorian},
    {"2026-06-15T10", Calendrical.Gregorian},
    {"2026-06/2026-09", Calendrical.Gregorian},
    {"2026/2028", Calendrical.Gregorian},
    {"2026-06-15[Europe/Paris]", Calendrical.Gregorian},
    {"5786Y6M", Hebrew},
    {"5787Y", Hebrew},
    {"2026Y", ISOWeek},
    {"2026Y25W", ISOWeek}
  ]

  # Parts a constraint and a selection both write, of whole numbers and of
  # sets and ranges of them.
  @parts [
    "15D",
    "-1D",
    "{1,15}D",
    "{28..-1}D",
    "31D",
    "6M",
    "{6,8}M",
    "6M15D",
    "2M29D",
    "166O",
    "25W",
    "-1W",
    "{1,-1}W",
    "T10H",
    "T{9,14}H",
    "T10H30M",
    "15DT10H",
    "3KT10H"
  ]

  describe "a constraint and the selection of the same parts" do
    test "select the same values, in every period and calendar" do
      for {base_text, calendar} <- @bases, part <- @parts do
        base = read(base_text, calendar)

        with {:ok, %Tempo{} = constraint} <- Tempo.from_iso8601(part, calendar),
             {:ok, selection} <- Tempo.from_iso8601("L#{part}N", calendar) do
          by_constraint = Tempo.select(base, constraint)
          by_selection = Tempo.select(base, selection)

          assert {base_text, part, answer(by_constraint)} ==
                   {base_text, part, answer(by_selection)}
        end
      end
    end

    # An answer as its members, each whole, or the error it is.
    defp answer({:ok, %IntervalSet{} = set}), do: IntervalSet.members(set)
    defp answer({:error, exception}), do: {:error, exception.__struct__}

    test "select the same day of a week of the year" do
      # A day of a week of a month is the constraint's alone, and is below.
      for base <- [~o"2026", ~o"2026/2028", ~o"2026-W25"] do
        assert members(Tempo.select(base, ~o"25W3K")) == members(Tempo.select(base, ~o"L25W3KN"))
      end

      assert spans(Tempo.select(~o"2026", ~o"L25W3KN")) ==
               [{seconds(~D[2026-06-17]), seconds(~D[2026-06-18])}]
    end

    test "select a day that is the day's own value, walked by its hours" do
      day = Tempo.to_interval!(~o"2026-06-15")
      assert %Interval{unit: :hour} = day

      for selector <- [~o"15D", ~o"L15DN"] do
        assert members(Tempo.select(~o"2026-06", selector)) == [day]
        assert Enum.count(hd(members(Tempo.select(~o"2026-06", selector)))) == 24
      end

      # A month selected from a year is walked by its days, and an hour
      # selected from a day by its minutes.
      for selector <- [~o"6M", ~o"L6MN"] do
        assert members(Tempo.select(~o"2026", selector)) == [Tempo.to_interval!(~o"2026-06")]
      end

      for selector <- [~o"T10H", ~o"LT10HN"] do
        assert members(Tempo.select(~o"2026-06-15", selector)) ==
                 [Tempo.to_interval!(~o"2026-06-15T10")]
      end
    end

    test "select each point as the value it is" do
      for {base_text, calendar} <- @bases, part <- @parts do
        with {:ok, selection} <- Tempo.from_iso8601("L#{part}N", calendar),
             {:ok, %IntervalSet{} = selected} <-
               Tempo.select(read(base_text, calendar), selection) do
          for %Interval{unit: unit} = member when unit != nil <- IntervalSet.members(selected) do
            assert {base_text, part, member} ==
                     {base_text, part, Tempo.to_interval!(Interval.from(member))}
          end
        end
      end
    end
  end

  describe "what a constraint selects, by the resolver" do
    test "is each day of the month that has the number, and none where the month has no such day" do
      for month <- 1..12, day <- [1, 15, 28, 29, 30, 31], year <- [2024, 2026] do
        expected =
          case Date.new(year, month, day) do
            {:ok, date} -> [{seconds(date), seconds(Date.add(date, 1))}]
            {:error, _no_such_day} -> []
          end

        base = read("#{year}Y#{month}M")

        assert {year, month, day, spans(Tempo.select(base, read("#{day}D")))} ==
                 {year, month, day, expected}
      end
    end

    test "is the day of each month of a year, and the last of each" do
      {:ok, fifteenths} = Tempo.select(~o"2026-01/2027-01", ~o"15D")
      {:ok, lasts} = Tempo.select(~o"2026-01/2027-01", ~o"-1D")

      assert spans({:ok, fifteenths}) ==
               for(
                 month <- 1..12,
                 date = Date.new!(2026, month, 15),
                 do: {seconds(date), seconds(Date.add(date, 1))}
               )

      assert spans({:ok, lasts}) ==
               for(
                 month <- 1..12,
                 date = Date.end_of_month(Date.new!(2026, month, 1)),
                 do: {seconds(date), seconds(Date.add(date, 1))}
               )
    end

    test "is the hours and the minutes it names on its day" do
      assert spans(Tempo.select(~o"2026-06-15", ~o"T{9,14}H")) ==
               for(
                 hour <- [9, 14],
                 from = NaiveDateTime.new!(2026, 6, 15, hour, 0, 0),
                 do: {seconds(from), seconds(NaiveDateTime.add(from, 3600))}
               )

      assert spans(Tempo.select(~o"2026-06-15/2026-06-18", ~o"T10H30M")) ==
               for(
                 day <- 15..17,
                 from = NaiveDateTime.new!(2026, 6, day, 10, 30, 0),
                 do: {seconds(from), seconds(NaiveDateTime.add(from, 60))}
               )
    end
  end

  describe "a time of day the clock skips part of" do
    test "is the part its clock shows, by a constraint and by a selection" do
      # Lord Howe's clocks go from 02:00 to 02:30 on 4 October 2026, so the
      # hour from 02:00 is the half hour from 02:30.
      zone = "Australia/Lord_Howe"
      assert {:gap, _before, _after} = DateTime.new(~D[2026-10-04], ~T[02:15:00], zone)

      epoch = :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
      shown = DateTime.to_unix(DateTime.new!(~D[2026-10-04], ~T[02:30:00], zone)) + epoch
      ends = DateTime.to_unix(DateTime.new!(~D[2026-10-04], ~T[03:00:00], zone)) + epoch

      assert ends - shown == 1800

      for selector <- [~o"T02", ~o"LT2HN"] do
        assert spans(Tempo.select(~o"2026-10-04[Australia/Lord_Howe]", selector)) ==
                 [{shown, ends}]
      end
    end
  end

  describe "a week selected in a year of a calendar of weeks" do
    test "is the week, by a constraint, by a selection and by the value written with one" do
      # Week 25 of 2026 starts on Monday 15 June.
      assert :calendar.iso_week_number({2026, 6, 15}) == {2026, 25}
      assert Date.day_of_week(~D[2026-06-15]) == 1

      week = {seconds(~D[2026-06-15]), seconds(~D[2026-06-22])}
      year = read("2026Y", ISOWeek)

      assert spans(Tempo.select(year, read("25W", ISOWeek))) == [week]
      assert spans(Tempo.select(year, read("L25WN", ISOWeek))) == [week]
      assert spans(Tempo.to_interval(read("2026YL25WN", ISOWeek))) == [week]

      assert spans(Tempo.to_interval(read("R2/2026Y/P1Y/FL25WN", ISOWeek))) ==
               [week, {seconds(~D[2027-06-21]), seconds(~D[2027-06-28])}]

      # The year has 53 weeks, the last from Monday 28 December.
      assert :calendar.iso_week_number({2026, 12, 28}) == {2026, 53}

      assert spans(Tempo.to_interval(read("2026YL{1,-1}WN", ISOWeek))) ==
               [
                 {seconds(~D[2025-12-29]), seconds(~D[2026-01-05])},
                 {seconds(~D[2026-12-28]), seconds(~D[2027-01-04])}
               ]
    end
  end

  describe "what the resolver has no reading for" do
    # It was left the span it was, with no unit, until 2026-10-08
    # (`Tempo.SelectedByWeekdayTest`).
    test "is not a day selected by its weekday alone, which is the day's own value" do
      for selector <- [~o"1K", ~o"L1KN"] do
        mondays = members(Tempo.select(~o"2026-06", selector))

        assert Enum.map(mondays, & &1.unit) == [:hour, :hour, :hour, :hour, :hour]
      end

      {:ok, workdays} = Tempo.select(~o"2026-08-10/2026-08-15", Tempo.workdays(:AU))
      assert {IntervalSet.count(workdays), Enum.count(workdays)} == {5, 5 * 24}
    end

    test "is still placed on its period: a part it cannot count" do
      # A mask is counted since 2026-10-08, and is each value its digits
      # match (`Tempo.MaskedConstraintTest`): each of the ten hours from
      # 10:00 on each Monday of June 2026, where it was the one span of them.
      assert spans(Tempo.select(~o"2026-06", ~o"1KT1XH")) ==
               for(
                 day <- [1, 8, 15, 22, 29],
                 hour <- 10..19,
                 from = NaiveDateTime.new!(2026, 6, day, hour, 0, 0),
                 do: {seconds(from), seconds(NaiveDateTime.add(from, 3600))}
               )

      # A fraction of a second, and the second group of three months.
      {:ok, tenth} = Tempo.select(~o"2026-06-15", ~o"T10H30M15.5S")
      assert [%Interval{} = tenth] = IntervalSet.members(tenth)
      assert Interval.from(tenth) == ~o"2026-06-15T10:30:15.5"

      assert spans(Tempo.select(~o"2026", ~o"2G3MU")) ==
               [{seconds(~D[2026-04-01]), seconds(~D[2026-07-01])}]
    end

    test "is still placed on its period: a span between two ends and a day of a week of a month" do
      assert spans(Tempo.select(~o"2026-06-15", ~o"T09/T17")) ==
               [{seconds(~N[2026-06-15 09:00:00]), seconds(~N[2026-06-15 17:00:00])}]

      assert spans(Tempo.select(~o"2026-06", ~o"2W3K")) ==
               [{seconds(~D[2026-06-10]), seconds(~D[2026-06-11])}]
    end
  end
end
