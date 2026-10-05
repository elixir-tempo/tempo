defmodule Tempo.ShiftOfMasksTest do
  use ExUnit.Case, async: true

  # A mask (`1X`, `XX`) and an unspecified unit (`X*`) stand for candidate
  # values, and a step moves each of them. The answer names the values the
  # candidates land on and no others, written three ways: the value with its
  # masks, where the step passes them by; one of the values from a first to a
  # last, where the candidates are one run and the step keeps them one; and
  # the set of their spans otherwise.
  #
  # On the week axis an unspecified week or day of the week was read as its
  # last value, so a day on from some day of week 25 was the next Monday
  # alone. On the month axis a block was written by its first and last
  # candidate whatever lay between them, so a step finer than the masked
  # unit, and a mask whose candidates are not one run, named values no
  # candidate lands on.
  #
  # The measure is `Date` and `NaiveDateTime` alone: each candidate is listed
  # and stepped there, and the answer must name the units of time they land
  # on.

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.ISOWeek
  alias Calendrical.Julian.March25
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.UnanchoredError

  @midnight ~T[00:00:00]

  defp at_midnight(dates), do: Enum.map(dates, &NaiveDateTime.new!(&1, @midnight))

  defp days_of(year, keep) do
    Date.new!(year, 1, 1)
    |> Date.range(Date.new!(year, 12, 31))
    |> Enum.filter(keep)
    |> at_midnight()
  end

  defp months_of(year, months),
    do: at_midnight(for month <- months, do: Date.new!(year, month, 1))

  defp years(years), do: at_midnight(for year <- years, do: Date.new!(year, 1, 1))

  # The Monday of an ISO 8601 week: 4 January is always in week 1.
  defp monday(year, week) do
    fourth = Date.new!(year, 1, 4)
    Date.add(fourth, 1 - Date.day_of_week(fourth) + 7 * (week - 1))
  end

  defp weeks_of(year, weeks), do: at_midnight(for week <- weeks, do: monday(year, week))

  # The weeks an ISO 8601 year has: 28 December is always in the last.
  defp weeks_in(year) do
    {_week_year, week} = :calendar.iso_week_number({year, 12, 28})
    week
  end

  defp days_of_weeks(year, weeks, weekdays) do
    at_midnight(
      for week <- weeks, weekday <- weekdays, do: Date.add(monday(year, week), weekday - 1)
    )
  end

  defp hours_of(date, hours),
    do: for(hour <- hours, do: NaiveDateTime.new!(date, Time.new!(hour, 0, 0)))

  # Each value as it is written, the unit it is written to, and the
  # candidates it stands for.
  defp masked_values do
    [
      {"2026Y6MX*D", :day, days_of(2026, &(&1.month == 6))},
      {"2026Y6MXXD", :day, days_of(2026, &(&1.month == 6))},
      {"2026Y6M1XD", :day, days_of(2026, &(&1.month == 6 and &1.day in 10..19))},
      {"2026Y6MX5D", :day, days_of(2026, &(&1.month == 6 and &1.day in [5, 15, 25]))},
      {"2026YXXM15D", :day, days_of(2026, &(&1.day == 15))},
      {"2026YXXM31D", :day, days_of(2026, &(&1.day == 31))},
      {"2026YXXMXXD", :day, days_of(2026, fn _date -> true end)},
      {"2026YXXM1XD", :day, days_of(2026, &(&1.day in 10..19))},
      {"2026Y1XMXXD", :day, days_of(2026, &(&1.month in 10..12))},
      {"2026YX*O", :day, days_of(2026, fn _date -> true end)},
      {"2026Y1XXO", :day, days_of(2026, &(Date.day_of_year(&1) in 100..199))},
      {"2026Y25WX*K", :day, days_of_weeks(2026, [25], 1..7)},
      {"2026Y25WXK", :day, days_of_weeks(2026, [25], 1..7)},
      {"2026Y53WX*K", :day, days_of_weeks(2026, [53], 1..7)},
      {"2026YX*W3K", :day, days_of_weeks(2026, 1..53, [3])},
      {"2026YX*WX*K", :day, days_of_weeks(2026, 1..53, 1..7)},
      {"2026YX*W", :week, weeks_of(2026, 1..53)},
      {"2026Y2XW", :week, weeks_of(2026, 20..29)},
      {"2026Y5XW", :week, weeks_of(2026, 50..53)},
      {"2026YXXM", :month, months_of(2026, 1..12)},
      {"2026Y1XM", :month, months_of(2026, 10..12)},
      {"202XY6M", :month, at_midnight(for year <- 2020..2029, do: Date.new!(year, 6, 1))},
      {"202XY", :year, years(2020..2029)},
      {"2X2XY", :year, years(for century <- 20..29, year <- 20..29, do: century * 100 + year)},
      {"2026Y6M15DTX*H", :hour, hours_of(~D[2026-06-15], 0..23)},
      {"2026Y6M15DT1XH", :hour, hours_of(~D[2026-06-15], 10..19)},
      {"2026Y6MX*DT10H", :hour, Enum.flat_map(1..30, &hours_of(Date.new!(2026, 6, &1), [10]))}
    ]
  end

  # A step coarser than the masked unit, which passes the mask by: each
  # value with the steps it is measured by. The mask is kept where it stands
  # for what the candidates land on, and they are the answer where it would
  # name more: some day of June a month on is no 31st of July, and the days
  # of February 2023 a year on are not the 29th.
  defp coarser_steps do
    june = days_of(2026, &(&1.month == 6))
    january = days_of(2026, &(&1.month == 1))

    [
      {"2026Y6MXXD", :day, june, [[month: 1], [month: -1], [month: 8], [year: 2]]},
      {"2026Y6MX*D", :day, june, [[month: 1], [year: 1]]},
      {"2026Y6M1XD", :day, days_of(2026, &(&1.month == 6 and &1.day in 10..19)),
       [[month: 1], [month: 8]]},
      {"2026Y6MX5D", :day, days_of(2026, &(&1.month == 6 and &1.day in [5, 15, 25])),
       [[month: 1], [month: 8]]},
      {"2026Y1MXXD", :day, january, [[month: 1], [month: 2], [year: 2, month: 1]]},
      {"2026Y1M3XD", :day, days_of(2026, &(&1.month == 1 and &1.day in 30..31)),
       [[month: 1], [month: 2]]},
      {"2024Y2MXXD", :day, days_of(2024, &(&1.month == 2)),
       [[year: 1], [year: -1], [year: 4], [month: 1], [month: -1]]},
      {"2023Y2MXXD", :day, days_of(2023, &(&1.month == 2)), [[year: 1], [year: 2], [month: 12]]},
      {"2024Y2M2XD", :day, days_of(2024, &(&1.month == 2 and &1.day in 20..29)),
       [[year: 1], [year: 4]]},
      {"2026YXXMXXD", :day, days_of(2026, fn _date -> true end), [[year: 1], [year: 2]]},
      {"2024YXXMXXD", :day, days_of(2024, fn _date -> true end), [[year: 1], [year: 4]]},
      {"2026YXXM1XD", :day, days_of(2026, &(&1.day in 10..19)), [[year: 1], [year: 2]]},
      {"2024YXXM29D", :day, days_of(2024, &(&1.day == 29)), [[year: 1], [year: 4]]},
      {"2026Y1XMXXD", :day, days_of(2026, &(&1.month in 10..12)), [[year: 1], [year: 2]]},
      {"2026YXXM", :month, months_of(2026, 1..12), [[year: 1], [year: -3]]},
      {"2026Y6MX*DT10H", :hour, Enum.flat_map(1..30, &hours_of(Date.new!(2026, 6, &1), [10])),
       [[month: 1], [year: 1]]},
      {"2026Y6MXXDTXXH", :hour, Enum.flat_map(1..30, &hours_of(Date.new!(2026, 6, &1), 0..23)),
       [[month: 1], [month: 8]]}
    ]
  end

  # The steps each value is measured by: those that reach its masked unit.
  # A step coarser than it is measured with `coarser_steps/0`.
  defp steps_for("2026Y6M" <> _day_masked, :day),
    do: [[day: 1], [day: -1], [day: 45], [week: 1], [hour: 1], [hour: 25], [month: 1, day: 1]]

  defp steps_for("2026YXXMXXD", :day), do: [[day: 1], [week: -1], [hour: 25]]
  defp steps_for("2026YXXM1XD", :day), do: [[day: 1], [day: 25], [hour: 1]]
  defp steps_for("2026Y1XMXXD", :day), do: [[day: 1], [day: -1], [hour: 25]]

  defp steps_for(_text, :day),
    do: [[day: 1], [day: -1], [day: 10], [week: 1], [hour: 1], [hour: 25], [month: 1], [year: 1]]

  defp steps_for(_text, :week), do: [[week: 1], [week: -1], [week: 30], [day: 1], [day: 8]]
  defp steps_for(_text, :month), do: [[month: 1], [month: -1], [month: 14], [year: 1], [day: 1]]
  defp steps_for(_text, :year), do: [[year: 1], [year: 10], [year: -3], [month: 1], [day: 1]]

  defp steps_for(_text, :hour),
    do: [[hour: 1], [hour: -1], [hour: 20], [minute: 1], [minute: 90], [day: 1]]

  @finest_first [:minute, :hour, :day, :week, :month, :year]

  # The unit an answer is written to: the finer of the value's and the
  # step's. A day under a week or a month is a day.
  defp answered_to(unit, step) do
    Enum.find(@finest_first, &(&1 == unit or Keyword.has_key?(step, &1)))
  end

  # The start of each unit of time an answer names.
  defp named(%Tempo{} = value, unit) do
    case Tempo.to_interval(value) do
      {:ok, %Interval{} = span} -> units_in(span, unit)
      {:ok, %IntervalSet{} = set} -> named(set, unit)
    end
  end

  defp named(%IntervalSet{} = set, unit),
    do: set |> IntervalSet.members() |> Enum.flat_map(&units_in(&1, unit))

  defp named(%Tempo.Set{type: :one, set: [%Tempo.Range{first: first, last: last}]}, unit),
    do: units_from(moment(first), NaiveDateTime.shift(moment(last), [{unit, 1}]), unit)

  defp units_in(%Interval{} = span, unit),
    do: units_from(moment(Interval.from(span)), moment(Interval.to(span)), unit)

  defp units_from(from, to, unit) do
    from
    |> Stream.iterate(&NaiveDateTime.shift(&1, [{unit, 1}]))
    |> Enum.take_while(&(NaiveDateTime.compare(&1, to) == :lt))
  end

  defp moment(%Tempo{} = point) do
    {:ok, moment} = point |> Tempo.extend_resolution(:second) |> Tempo.to_naive_datetime()
    moment
  end

  defp in_order(moments), do: moments |> Enum.uniq() |> Enum.sort(NaiveDateTime)

  describe "a step that reaches a masked or an unspecified unit" do
    test "lands each value it stands for, and names those and no others" do
      for {text, unit, candidates} <- masked_values() do
        value = Tempo.from_iso8601!(text)

        for step <- steps_for(text, unit) do
          answered = answered_to(unit, step)
          expected = candidates |> Enum.map(&NaiveDateTime.shift(&1, step)) |> in_order()

          assert {text, step, in_order(named(Tempo.shift(value, step), answered))} ==
                   {text, step, expected}
        end
      end
    end
  end

  describe "a step coarser than a masked or an unspecified unit" do
    test "lands each value it stands for, and names those and no others" do
      for {text, unit, candidates, steps} <- coarser_steps(), step <- steps do
        value = Tempo.from_iso8601!(text)
        answered = answered_to(unit, step)
        expected = candidates |> Enum.map(&NaiveDateTime.shift(&1, step)) |> in_order()

        assert {text, step, in_order(named(Tempo.shift(value, step), answered))} ==
                 {text, step, expected}
      end
    end
  end

  describe "how the answer is written" do
    test "is the value with its masks where the step passes them by" do
      assert Tempo.shift(~o"2026Y6MX*D", hour: 1) == ~o"2026Y6MX*DT1H"
      assert Tempo.shift(~o"2026Y6M1XD", hour: 1) == ~o"2026Y6M1XDT1H"
      assert Tempo.shift(~o"2026YXXM", day: 1) == ~o"2026YXXM2D"
      assert Tempo.shift(~o"2026YXXM15D", day: 1) == ~o"2026YXXM16D"
      assert Tempo.shift(~o"202XY", month: 1) == ~o"202XY2M"
      assert Tempo.shift(~o"202XY6M15D", day: 1) == ~o"202XY6M16D"
      assert Tempo.shift(~o"2026Y6M15DTX*H", minute: 1) == ~o"2026Y6M15DTX*H1M"
      assert Tempo.shift(~o"2026Y25WX*K", hour: 1) == ~o"2026Y25WX*KT1H"
      assert Tempo.shift(~o"2026YX*W", day: 1) == ~o"2026YX*W2K"
      assert Tempo.shift(~o"2026YX*W3K", day: 1) == ~o"2026YX*W4K"
    end

    test "is one of a run of values where the candidates are a run the step keeps" do
      assert Tempo.shift(~o"2026Y6MX*D", day: 1) == ~o"[2026Y6M2D..2026Y7M1D]"
      assert Tempo.shift(~o"2026Y6M1XD", day: 1) == ~o"[2026Y6M11D..2026Y6M20D]"
      assert Tempo.shift(~o"2026YXXM", month: 1) == ~o"[2026Y2M..2027Y1M]"
      assert Tempo.shift(~o"202XY", year: 1) == ~o"[2021Y..2030Y]"
      assert Tempo.shift(~o"2026YX*W", week: 1) == ~o"[2026Y2W..2027Y1W]"
      assert Tempo.shift(~o"2026Y2XW", week: 1) == ~o"[2026Y21W..2026Y30W]"

      # A week and a day of it are the date they name.
      assert Tempo.shift(~o"2026Y25WX*K", day: 1) == ~o"[2026Y6M16D..2026Y6M22D]"
      assert Tempo.shift(~o"2026Y25WX*K", day: -1) == ~o"[2026Y6M14D..2026Y6M20D]"
      assert Tempo.shift(~o"2026Y25WXK", day: 1) == ~o"[2026Y6M16D..2026Y6M22D]"
    end

    test "is the mask moved where a block of years lands on a block" do
      assert Tempo.shift(~o"202XY", year: 10) == ~o"203XY"
    end

    test "is the set of the candidates' spans otherwise" do
      for {value, step} <- [
            # The candidates are not one run.
            {~o"2026Y6MX5D", [day: 1]},
            {~o"2026YXXM1XD", [day: 1]},
            {~o"2X2XY", [year: 1]},
            # The step writes a finer unit than the masked one.
            {~o"2026Y6MXXD", [hour: 25]},
            # A day is brought into the month it lands in.
            {~o"2026YX*O", [month: 1]},
            # A week and a day of it are stepped as the date they name.
            {~o"2026Y25WX*K", [year: 1]},
            {~o"2026YX*W3K", [day: 5]}
          ] do
        assert %IntervalSet{} = Tempo.shift(value, step), "#{inspect(value)} #{inspect(step)}"
      end
    end

    test "is a week of a calendar of weeks in that calendar" do
      week = &Tempo.from_iso8601!(&1, ISOWeek)

      assert Tempo.shift(week.("2026Y25WX*K"), day: 1) == week.("[2026Y25W2K..2026Y26W1K]")
      assert Tempo.shift(week.("2026YX*W"), week: 1) == week.("[2026Y2W..2027Y1W]")
      assert Tempo.shift(week.("2026Y25WX*K"), year: 1) == week.("2027Y25WX*K")
    end
  end

  # A step coarser than the masked unit moves the units it is written by, and
  # the mask is kept where it stands for what its values land on and for
  # nothing else (decided 2026-10-06). It was kept wherever the step passed it
  # by, so a month on from some day of June was some day of July, the 31st
  # among them.
  describe "how the answer of a step coarser than the masked unit is written" do
    test "is the value with its mask where the mask stands for what is landed on" do
      assert Tempo.shift(~o"2020-XX", year: 1) == ~o"2021-XX"
      assert Tempo.shift(~o"2020-XX-XX", year: 1) == ~o"2021-XX-XX"
      assert Tempo.shift(~o"2026Y25WX*K", week: 1) == ~o"2026Y26WX*K"
      assert Tempo.shift(~o"2026YX*W", year: 1) == ~o"2027YX*W"

      # Each day of February is landed on from January, the last of them
      # three times, and from the February of a leap year.
      assert Tempo.shift(~o"2020-01-XX", month: 1) == ~o"2020-02-XX"
      assert Tempo.shift(~o"2024-02-XX", year: 1) == ~o"2025-02-XX"
      assert Tempo.shift(~o"2024-02-2X", year: 1) == ~o"2025-02-2X"
      assert Tempo.shift(~o"2026-06-XX", month: 8) == ~o"2027-02-XX"

      # A mask on a time of day stands for what it did wherever the date
      # lands.
      assert Tempo.shift(~o"2024-03-XXT1X", month: -1) == ~o"2024-02-XXT1X"
      assert Tempo.shift(~o"2026Y6M15DTX*H", month: 1) == ~o"2026Y7M15DTX*H"
    end

    test "is one of the values landed on where the mask would name more" do
      assert Tempo.shift(~o"2020-06-XX", month: 1) == ~o"[2020Y7M1D..2020Y7M30D]"
      assert Tempo.shift(~o"2020-06-XX", month: -1) == ~o"[2020Y5M1D..2020Y5M30D]"
      assert Tempo.shift(~o"2023-02-XX", year: 1) == ~o"[2024Y2M1D..2024Y2M28D]"
      assert Tempo.shift(~o"6MX*D", month: 1) == ~o"[7M1D..7M30D]"
      assert Tempo.shift(~o"2020-06-XXTXX", month: 1) == ~o"[2020Y7M1DT0H..2020Y7M30DT23H]"

      # The thirties of January a month on are the last day of February.
      assert Tempo.shift(~o"2020-01-3X", month: 1) == ~o"[2020Y2M29D..2020Y2M29D]"

      # 2025 has fifty-two weeks and 2026 fifty-three.
      assert Tempo.shift(~o"2025YX*W", year: 1) == ~o"[2026Y1W..2026Y52W]"
    end

    test "of the weeks of a year, a year on, is each week's number or the last the year has" do
      for year <- 2020..2032 do
        last = min(weeks_in(year), weeks_in(year + 1))
        answer = Tempo.shift(Tempo.from_iso8601!("#{year}YX*W"), year: 1)

        assert {year, in_order(named(answer, :week))} == {year, weeks_of(year + 1, 1..last)}
      end
    end

    test "is the set of the candidates' spans where they are no one run" do
      # Every day of 2021, three years on, is every day of 2024 but the 29th
      # of February.
      assert %IntervalSet{} = days = Tempo.shift(~o"2021-XX-XX", year: 3)

      assert Enum.map(IntervalSet.members(days), &{Interval.from(&1), Interval.to(&1)}) ==
               [{~o"2024Y1M1D", ~o"2024Y2M29D"}, {~o"2024Y3M1D", ~o"2025Y1M1D"}]
    end

    test "is unanchored where what the mask stands for depends on the year" do
      assert {:error, %UnanchoredError{value: value}} = Tempo.shift(~o"2MX*D", month: 1)
      assert value == ~o"2MX*D"
    end
  end

  # A value with no year lies on an axis that comes round again, where a
  # block can land across the end: it was written as a range from a later
  # value to an earlier one, which the parser does not read.
  describe "a value with no year" do
    test "that is every value of its axis is every value of it, a step on" do
      assert Tempo.shift(~o"X*K", day: 1) == ~o"X*K"
      assert Tempo.shift(~o"TX*H", hour: 1) == ~o"TX*H"
    end

    test "is one of a run where the block does not cross the end of its axis" do
      assert Tempo.shift(~o"T2XH", hour: -5) == ~o"[T15H..T18H]"
      assert Tempo.shift(~o"6MX*D", day: 1) == ~o"[6M2D..7M1D]"
    end

    test "is the candidates' spans where it does" do
      assert %IntervalSet{} = late = Tempo.shift(~o"T2XH", hour: 2)

      assert Enum.map(IntervalSet.members(late), &{Interval.from(&1), Interval.to(&1)}) ==
               [{~o"T22H", ~o"T2H"}]

      assert %IntervalSet{} = Tempo.shift(~o"12MX*D", day: 1)
    end

    test "is unanchored where its candidates depend on the year" do
      assert {:error, %UnanchoredError{value: value}} = Tempo.shift(~o"2MX*D", day: 1)
      assert value == ~o"2MX*D"
      assert {:error, %UnanchoredError{}} = Tempo.shift(~o"X*W", week: 1)
    end
  end

  # Hours, minutes and seconds are time on the time line in a named zone, so
  # each candidate is stepped in the zone: the candidates were stepped as one
  # value with no zone, and landed an hour early on the day the clocks go
  # forward.
  describe "a value in a zone" do
    defp paris(day, hour, minute),
      do: DateTime.new!(Date.new!(2026, 3, day), Time.new!(hour, minute, 0), "Europe/Paris")

    defp zoned_starts(%IntervalSet{} = set) do
      for member <- IntervalSet.members(set) do
        {:ok, start} =
          member |> Interval.from() |> Tempo.extend_resolution(:second) |> Tempo.to_datetime()

        {start.day, start.hour, start.minute}
      end
    end

    test "steps hours from each day a mask stands for" do
      # Paris moves from 02:00 to 03:00 on 29 March 2026.
      expected =
        for day <- 1..31 do
          later = DateTime.add(paris(day, 1, 0), 2, :hour)
          {later.day, later.hour, later.minute}
        end

      assert zoned_starts(Tempo.shift(~o"2026Y3MXXDT1H[Europe/Paris]", hour: 2)) == expected
      assert {29, 4, 0} in expected
    end

    test "steps hours from each minute a mask stands for" do
      first = DateTime.add(paris(29, 1, 0), 2, :hour)
      last = DateTime.add(paris(29, 1, 59), 2, :hour)

      assert Tempo.shift(~o"2026Y3M29DT1HXXM[Europe/Paris]", hour: 2) ==
               Tempo.from_iso8601!(
                 "[2026Y3M29DT#{first.hour}H#{first.minute}M..2026Y3M29DT#{last.hour}H#{last.minute}M][Europe/Paris]"
               )
    end
  end

  # In a calendar whose year does not begin with its first month a date is
  # stepped by the calendar, and each candidate is such a date: a month on
  # from a day of March 1750, which is near that year's end, is in April
  # 1751, where the candidates were counted through and landed in April 1750.
  describe "a calendar that steps its own dates" do
    # The days an answer names in the Hebrew calendar: those its mask stands
    # for, or those from the first to the last of a run.
    defp hebrew_days(%Tempo{} = masked) do
      for day <- masked, do: day |> Tempo.to_date() |> elem(1) |> year_month_day()
    end

    defp hebrew_days(%Tempo.Set{type: :one, set: [%Tempo.Range{first: first, last: last}]}) do
      {:ok, from} = Tempo.to_date(first)
      {:ok, to} = Tempo.to_date(last)

      from
      |> Stream.iterate(&Date.add(&1, 1))
      |> Enum.take_while(&(Date.diff(to, &1) >= 0))
      |> Enum.map(&year_month_day/1)
    end

    defp year_month_day(%Date{year: year, month: month, day: day}), do: {year, month, day}

    defp march25_days(%IntervalSet{} = set) do
      for member <- IntervalSet.members(set), date <- days_between(member), do: date
    end

    defp days_between(member) do
      {:ok, first} = member |> Interval.from() |> Tempo.to_date()
      {:ok, last} = member |> Interval.to() |> Tempo.to_date()

      first
      |> Stream.iterate(&Date.add(&1, 1))
      |> Enum.take_while(&(Date.diff(last, &1) > 0))
    end

    test "keeps a mask a coarser step passes by where it stands for what is landed on" do
      # The days of a Hebrew month a year or a month on: the calendar is
      # asked where each lands, and the answer names those days. The second
      # and the third month are of 29 or 30 days by the year, and a year of
      # thirteen months is among them.
      for year <- 5784..5790,
          month <- 1..12,
          {unit, step} <- [years: [year: 1], months: [month: 1]] do
        text = "#{year}Y#{month}MXXD"

        landed =
          for day <- 1..Hebrew.days_in_month(year, month) do
            Hebrew.plus(year, month, day, unit, 1, coerce: true)
          end

        answer = Tempo.shift(Tempo.from_iso8601!(text, Hebrew), step)

        assert {text, step, hebrew_days(answer)} ==
                 {text, step, landed |> Enum.uniq() |> Enum.sort()}
      end
    end

    test "steps each date a mask stands for by the calendar" do
      for {text, days} <- [{"1750Y3M1XD", 10..19}, {"1750Y5M1XD", 10..19}, {"1750Y3MXXD", 1..31}] do
        "1750Y" <> rest = text
        {month, _rest} = Integer.parse(rest)

        expected =
          for day <- days do
            {year, month, day} = March25.plus(1750, month, day, :months, 1, coerce: true)
            Date.new!(year, month, day, March25)
          end

        answer = Tempo.shift(Tempo.from_iso8601!(text, March25), month: 1)

        assert {text, Enum.sort_by(march25_days(answer), &Date.to_gregorian_days/1)} ==
                 {text, expected |> Enum.uniq() |> Enum.sort_by(&Date.to_gregorian_days/1)}
      end
    end
  end
end
