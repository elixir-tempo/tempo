defmodule Tempo.WeekCalendarTest do
  use ExUnit.Case, async: true

  # A week-based calendar (the ISO week calendar, the NRF retail calendar, a
  # retail calendar built with `Calendrical.new/3`) numbers its weeks within
  # its year. Its dates are a year, a month of its pattern of weeks and a day
  # of that month, as every calendar's are (decided 2026-10-13), so a value in
  # one is read, held, stepped and written as a value of any calendar is. A
  # week date written for it (`2026-W25-2`) is the date it names: the second
  # day of the calendar's own week 25.

  import Tempo.Sigils

  alias Calendrical.ISOWeek
  alias Calendrical.NRF
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError
  alias Tempo.ResolutionError
  alias Tempo.RRule

  defp read_back(value) do
    value
    |> Tempo.to_iso8601!()
    |> Tempo.from_iso8601!()
  end

  describe "one shape, however the value is made" do
    test "parsed, built from an Elixir date, converted and shifted into a zone" do
      tuesday = ~o"2026-W25-2"W

      {:ok, zoned} =
        Tempo.shift_zone(
          Tempo.from_iso8601!("2026-W25-2T10:30[Europe/Paris][u-ca=iso-week]"),
          "Etc/UTC"
        )

      assert tuesday.time == [year: 2026, month: 6, day: 16]
      assert Tempo.from_elixir(ISOWeek.date_from_week_date(2026, 25, 2)) == tuesday
      assert Tempo.from_elixir(Date.new!(2026, 6, 16, ISOWeek)) == tuesday
      assert Tempo.to_calendar!(~o"2026-06-16", ISOWeek) == tuesday

      assert Keyword.take(zoned.time, [:month, :day, :hour]) == [month: 6, day: 16, hour: 8]

      naive = Tempo.from_elixir(NaiveDateTime.new!(2026, 6, 16, 10, 30, 0, {0, 0}, ISOWeek))
      assert naive.time == [year: 2026, month: 6, day: 16, hour: 10, minute: 30, second: 0]
    end

    # The NRF year 2026 begins on Sunday 1 February, and its week 20 on
    # Sunday 14 June: the third day of it is Tuesday 16 June, the seventeenth
    # day of the calendar's fifth month.
    test "the NRF retail calendar's weeks" do
      parsed = Tempo.from_iso8601!("2026-W20-3[u-ca=nrf]")

      assert parsed.time == [year: 2026, month: 5, day: 17]
      assert Tempo.to_calendar(parsed, Calendar.ISO) == {:ok, ~o"2026-06-16"}

      built = Tempo.from_elixir(NRF.date_from_week_date(2026, 20, 3))
      assert {built.calendar, built.time} == {NRF, parsed.time}
    end
  end

  # A calendar of weeks has months of its own, the months of its pattern of
  # weeks, each 28 days or 35 (decided 2026-10-13, where a month written for
  # one was an error for a day and, before that, the Gregorian day
  # converted). A date written with a month, a day of the year or a season is
  # read in it as in every calendar.
  describe "a date written with a month, for a calendar of weeks" do
    test "is the calendar's own month and day" do
      for calendar <- [ISOWeek, NRF] do
        assert {:ok, %Tempo{calendar: ^calendar, time: [year: 2026, month: 6, day: 15]}} =
                 Tempo.from_iso8601("2026-06-15", calendar)

        assert {:ok, %Tempo{time: [year: 2026, month: 6, day: 15, hour: 10, minute: 30]}} =
                 Tempo.from_iso8601("2026-06-15T10:30", calendar)

        assert {:ok, %Tempo{calendar: ^calendar, time: [year: 2026, month: 6]}} =
                 Tempo.from_iso8601("2026-06", calendar)

        # The fifteenth day of the sixth month is the first day of week 25.
        assert Tempo.from_iso8601("2026-06-15", calendar) ==
                 Tempo.from_iso8601("2026-W25-1", calendar)
      end

      assert Tempo.from_iso8601("2026-06-15[u-ca=iso-week]") == {:ok, ~o"2026Y6M15D"W}

      # The same text is another day in each: the ISO week calendar's sixth
      # month begins on Monday 1 June 2026 and NRF's on Sunday 5 July.
      assert Tempo.to_calendar(~o"2026Y6M15D"W, Calendar.ISO) == {:ok, ~o"2026-06-15"}

      assert Tempo.to_calendar(Tempo.from_iso8601!("2026-06-15", NRF), Calendar.ISO) ==
               {:ok, ~o"2026-07-19"}
    end

    # The ISO week calendar's 2026 begins on Monday 29 December 2025, and its
    # day 166 is Friday 12 June 2026, the twelfth day of its sixth month.
    test "a day of the year is counted in the calendar's own year" do
      for text <- ["2026-166", "2026Y166O"] do
        assert Tempo.from_iso8601(text, ISOWeek) == {:ok, ~o"2026Y6M12D"W}, text
      end

      assert Tempo.to_calendar(~o"2026Y6M12D"W, Calendar.ISO) == {:ok, ~o"2026-06-12"}
    end

    test "is read in part as it is whole" do
      for text <- [
            "6M15D",
            "15D",
            "2026-{06,07}",
            "2026-06-{01,15}",
            "2026-0X",
            "2022Y3G4DU",
            "2026Y1G2MU"
          ],
          calendar <- [ISOWeek, NRF] do
        assert {:ok, %Tempo{calendar: ^calendar}} = Tempo.from_iso8601(text, calendar), text
      end
    end

    # Both calendars lay their weeks out 4-5-4 in a quarter, so the first
    # month has 28 days and the second 35.
    test "is checked against the calendar's own months" do
      for calendar <- [ISOWeek, NRF] do
        assert {:ok, %Tempo{time: [year: 2026, month: 2, day: 30]}} =
                 Tempo.from_iso8601("2026-02-30", calendar)

        assert {:error, %InvalidDateError{unit: :day, value: 29, calendar: ^calendar}} =
                 Tempo.from_iso8601("2026-01-29", calendar)

        assert {:error, %InvalidDateError{unit: :month, value: 13, calendar: ^calendar}} =
                 Tempo.from_iso8601("2026-13-01", calendar)
      end
    end

    test "is read at an end of an interval and at a recurrence's start" do
      for text <- ["2026-06-15/2026-06-20", "2026-06/2026-08", "R3/2026-06-15/P1W"] do
        assert {:ok, %Interval{from: %Tempo{calendar: ISOWeek, time: time}}} =
                 Tempo.from_iso8601(text, ISOWeek),
               text

        assert Keyword.take(time, [:year, :month]) == [year: 2026, month: 6], text
      end
    end

    test "is built as it is parsed" do
      assert Tempo.new(year: 2026, month: 6, day: 15, calendar: ISOWeek) ==
               {:ok, ~o"2026Y6M15D"W}

      assert Tempo.new(year: 2026, day_of_year: 166, calendar: ISOWeek) ==
               {:ok, ~o"2026Y6M12D"W}

      assert Tempo.new(year: 2026, month: 6, calendar: ISOWeek) == {:ok, ~o"2026Y6M"W}
    end

    test "a date of another calendar is brought to it by converting it" do
      assert Tempo.to_calendar(~o"2026-06-15", ISOWeek) == {:ok, ~o"2026-W25-1"W}
      assert Tempo.to_calendar(~o"2025-12-29", ISOWeek) == {:ok, ~o"2026-W01-1"W}
      assert Tempo.to_calendar(~o"2026-06-15T10:30", ISOWeek) == {:ok, ~o"2026-W25-1T10:30"W}

      {:ok, retail} = Tempo.to_calendar(~o"2026-06-15", NRF)
      assert {retail.calendar, retail.time} == {NRF, [year: 2026, month: 5, day: 16]}
      assert NRF.week_date_from_date(2026, 5, 16) == {2026, 20, 2}

      {:ok, uncertain} = Tempo.to_calendar(~o"2026-?06-15", ISOWeek)
      assert inspect(uncertain) == ~s(~o"2026Y6M15D?"W)
    end

    # A season is the astronomical one, wherever the calendar's months fall,
    # and a division of the year is the calendar's own: spring of 2026 begins
    # on 20 March, so its second day is 21 March in each calendar, and the
    # fifth day of the first quarter is the fifth day of the calendar's year.
    test "a season and a division of the year are read, and a day after one is a day of it" do
      for calendar <- [ISOWeek, NRF] do
        assert {:ok, _quarter} = Tempo.from_iso8601("2026Y33M", calendar)
        assert {:ok, _spring} = Tempo.from_iso8601("2026Y25M", calendar)

        {:ok, second_day_of_spring} = Tempo.from_iso8601("2026Y25M2D", calendar)
        assert Tempo.to_calendar(second_day_of_spring, Calendar.ISO) == {:ok, ~o"2026-03-21"}

        assert {:ok, %Tempo{time: [year: 2026, month: 1, day: 5]}} =
                 Tempo.from_iso8601("2026Y33M5D", calendar)
      end

      assert Tempo.from_iso8601("2026Y25M2D") == {:ok, ~o"2026-03-21"}
    end
  end

  # A month, a week and a day are numbered by their calendar, so a value of
  # one calendar is not placed on, nor selected from, a value of another: the
  # NRF year 2026 holds January 2027.
  describe "a month or a day of one calendar, and a week calendar's value" do
    test "is not placed on it" do
      for {value, other} <- [
            {~o"2026"W, ~o"6M15D"},
            {~o"6M15D", ~o"2026"W},
            {~o"2026"W, ~o"6M"},
            {~o"2026"W, ~o"166O"},
            {~o"2026"W, ~o"25W2K"},
            {~o"2026-W25-1"W, ~o"7M1D"}
          ] do
        assert {:error, %ConversionError{target: target} = error} = Tempo.at(value, other),
               inspect({value, other})

        assert target == other.calendar
        assert Exception.message(error) =~ "read both in one calendar"
      end
    end

    test "does not select in it" do
      for selector <- [~o"6M15D", ~o"6M", ~o"10D", ~o"166O", ~o"{6,7}M15D", ~o"6M1D/7M1D"] do
        assert {:error, %ConversionError{target: ISOWeek}} = Tempo.select(~o"2026"W, selector),
               inspect(selector)
      end
    end

    test "is placed and selected where both are read in the calendar of weeks" do
      month_and_day = Tempo.from_iso8601!("6M15D", ISOWeek)

      assert Tempo.at(~o"2026"W, month_and_day) == {:ok, ~o"2026Y6M15D"W}

      {:ok, selected} = Tempo.select(~o"2026"W, month_and_day)
      assert [%{from: from}] = IntervalSet.members(selected)
      assert from == ~o"2026Y6M15D"W
    end
  end

  describe "a value placed or extended in its own calendar" do
    test "a week date is the date it names when a time or a week is placed in it" do
      assert Tempo.at(~o"2026-W25-2"W, ~o"T10") == {:ok, ~o"2026-W25-2T10"W}
      assert Tempo.at(~o"2026"W, ~o"25W2K"W) == {:ok, ~o"2026-W25-2"W}

      {:ok, tuesdays} = Tempo.select(~o"2026-W25"W, ~o"2K")
      assert [%{from: from}] = IntervalSet.members(tuesdays)
      assert from.time == [year: 2026, month: 6, day: 16]
    end

    test "a month is checked against the value's calendar, not the Gregorian one" do
      # 5787 is a Hebrew leap year, with thirteen months.
      leap_year = Tempo.from_iso8601!("5787[u-ca=hebrew]")
      last_month = Tempo.from_iso8601!("13M1D", Calendrical.Hebrew)

      assert {:ok, placed} = Tempo.at(leap_year, last_month)
      assert placed.time == [year: 5787, month: 13, day: 1]

      assert {:ok, months} = Tempo.extend(leap_year)
      assert months.time == [year: 5787, month: [1..13]]

      common_year = Tempo.from_iso8601!("5786[u-ca=hebrew]")
      assert {:error, %InvalidDateError{}} = Tempo.at(common_year, last_month)
    end
  end

  describe "a recurrence in a calendar of weeks" do
    # A day steps by the calendar's own months, as a day of any calendar
    # does; a week alone has no month to step by, in any calendar.
    test "steps by months from a day, and is an error from a week alone" do
      {:ok, monthly} = Tempo.to_interval(Tempo.from_iso8601!("R3/2026-W25-1/P1M", ISOWeek))

      assert monthly
             |> IntervalSet.members()
             |> Enum.map(&Interval.from/1) == [
               ~o"2026Y6M15D"W,
               ~o"2026Y7M15D"W,
               ~o"2026Y8M15D"W
             ]

      for rule <- [
            Tempo.from_iso8601!("R3/2026-W25/P1M", ISOWeek),
            Tempo.from_iso8601!("R3/2026-W25/P1M")
          ] do
        assert {:error, %ResolutionError{target: :month}} = Tempo.to_interval(rule)
      end
    end

    # The fifteenth of the sixth month in each of three years, and day 166
    # of the year, which falls before the start in 2026.
    test "selects by a month or a day of the year of the calendar's own" do
      starts = fn text ->
        {:ok, set} = Tempo.to_interval(Tempo.from_iso8601!(text, ISOWeek))

        set
        |> IntervalSet.members()
        |> Enum.map(&Interval.from/1)
      end

      assert starts.("R3/2026-W25-1/P1Y/FL6M15DN") == [
               ~o"2026Y6M15D"W,
               ~o"2027Y6M15D"W,
               ~o"2028Y6M15D"W
             ]

      assert starts.("R3/2026-W25-1/P1Y/FL166ON") == [
               ~o"2027Y6M12D"W,
               ~o"2028Y6M12D"W,
               ~o"2029Y6M12D"W
             ]

      assert starts.("2026YL6M15DN") == [~o"2026Y6M15D"W]
    end
  end

  describe "the ISO 8601 form reads back as the value" do
    test "a week date is written as the date it names" do
      assert Tempo.to_iso8601!(~o"2026-W25-2"W) == "2026Y6M16D[u-ca=iso-week]"
      assert inspect(~o"2026-W25-2"W) == ~s|~o"2026Y6M16D"W|
      back = read_back(~o"2026-W25-2"W)
      assert {back.calendar, back.time} == {ISOWeek, [year: 2026, month: 6, day: 16]}
    end

    test "a week, a date and time, a zoned value and an NRF quarter" do
      week = Tempo.from_iso8601!("2026-W25[u-ca=iso-week]")
      datetime = Tempo.from_iso8601!("2026-W25-2T10:30:00[u-ca=iso-week]")
      zoned = Tempo.from_iso8601!("2026-W25-2T10:30:00[Europe/Paris][u-ca=iso-week]")
      {:ok, quarter} = Tempo.from_elixir(NRF.quarter(2026, 1))

      assert week.time == [year: 2026, week: 25]
      assert Tempo.to_iso8601!(week) == "2026Y25W[u-ca=iso-week]"

      for value <- [week, datetime, zoned] do
        back = read_back(value)
        assert {back.calendar, back.time} == {ISOWeek, value.time}
      end

      assert Tempo.to_iso8601!(quarter) == "2026Y1M1D/4M1D[u-ca=nrf]"
      assert Tempo.equal?(read_back(quarter), quarter)
    end

    test "a week-based calendar ISO 8601 cannot name is an error, and inspect names it" do
      {:ok, retail} =
        Calendrical.new(Tempo.WeekCalendarTest.Retail, :week, weeks_in_month: [4, 4, 5])

      week = Tempo.from_iso8601!("2026Y20W3K", retail)

      assert {:error, %Tempo.Iso8601EncodeError{construct: :calendar}} = Tempo.to_iso8601(week)

      {evaluated, _binding} = Code.eval_string(inspect(week))
      assert evaluated == week
    end
  end

  describe "operations on a week date" do
    test "it names the same day as the Gregorian date and meets it in set operations" do
      assert Tempo.equal?(~o"2026-W25-2"W, ~o"2026-06-16")
      assert Tempo.relation(~o"2026-W25-2"W, ~o"2026-06-16") == :equals

      assert Tempo.equal?(
               Tempo.from_iso8601!("2026-W20-3[u-ca=nrf]"),
               Tempo.from_elixir(NRF.date_from_week_date(2026, 20, 3))
             )

      assert {:ok, overlap} = Tempo.intersection(~o"2026-W25"W, ~o"2026-06-16/2026-06-18")
      assert IntervalSet.count(overlap) == 1
    end

    # A day on from the last day of a week is the first of the next, and a
    # month on from the sixteenth of the sixth month is the sixteenth of the
    # seventh, where a month was an error for a calendar of weeks.
    test "days, weeks and months step it as they step a date of any calendar" do
      assert Tempo.shift(~o"2026-W25-7"W, ~o"P1D") == ~o"2026-W26-1"W
      assert Tempo.shift(~o"2026-W25-2"W, ~o"P1W") == ~o"2026-W26-2"W
      assert Tempo.shift(~o"2026-W25-2"W, ~o"P1M") == ~o"2026Y7M16D"W
    end

    # A day is rounded to the first day of its week or of the next, as a
    # Gregorian day is, and NRF's weeks begin on Sunday: its Monday rounds
    # back to the Sunday and its Thursday on to the next.
    test "its day of the week and year, its rounding, and its date and time" do
      tuesday = ~o"2026-W25-2"W
      datetime = Tempo.from_iso8601!("2026-W25-2T10:30:00[u-ca=iso-week]")

      assert {Tempo.day_of_week(tuesday), Tempo.day_of_year(tuesday)} == {2, 170}
      assert Tempo.round(tuesday, :week) == ~o"2026-W25-1"W
      assert Tempo.round(~o"2026-W25-5"W, :week) == ~o"2026-W26-1"W
      assert Tempo.round(~o"2026-06-16", :week) == ~o"2026-06-15"

      assert Tempo.round(Tempo.from_iso8601!("2026-W25-2", NRF), :week) ==
               Tempo.from_iso8601!("2026-W25-1", NRF)

      assert Tempo.round(Tempo.from_iso8601!("2026-W25-5", NRF), :week) ==
               Tempo.from_iso8601!("2026-W26-1", NRF)

      # Each part keeps what the value carries, its calendar annotation too.
      assert Tempo.split(datetime) ==
               {Tempo.from_iso8601!("2026-W25-2[u-ca=iso-week]"),
                Tempo.from_iso8601!("T10:30:00[u-ca=iso-week]")}

      assert Tempo.split(~o"2026-W25-2T10:30:00"W) == {tuesday, ~o"T10:30:00"W}

      assert Tempo.to_naive_datetime(datetime) ==
               NaiveDateTime.new(2026, 6, 16, 10, 30, 0, {0, 0}, ISOWeek)
    end
  end

  describe "to_string/2" do
    test "a week date is the day it names" do
      assert Tempo.to_string(Tempo.new!(year: 2026, week: 25, day_of_week: 2)) ==
               {:ok, "Jun 16, 2026"}

      assert Tempo.to_string(
               Tempo.new!(year: 2026, week: 25, day_of_week: 2, hour: 10, minute: 30)
             ) ==
               {:ok, "Jun 16, 2026, 10:30 AM"}
    end

    test "a week is its first and last day, across a month or a year" do
      assert Tempo.to_string(~o"2026-W25") == {:ok, "Jun 15 – 21, 2026"}
      assert Tempo.to_string(~o"2026-W27") == {:ok, "Jun 29 – Jul 5, 2026"}
      assert Tempo.to_string(~o"2026-W53") == {:ok, "Dec 28, 2026 – Jan 3, 2027"}
    end

    test "a range of weeks runs to the last day of its last week" do
      assert Tempo.to_string(Tempo.from_iso8601!("2026-W25/2026-W27")) ==
               {:ok, "Jun 15 – 28, 2026"}
    end

    test "a week-based calendar's date is handed to Localize in its own calendar" do
      {:ok, localized} = Localize.Date.to_string(Date.new!(2026, 6, 16, ISOWeek))

      assert Tempo.to_string(~o"2026-W25-2"W) == {:ok, localized}
    end

    # Its months are named as CLDR's generic calendar names them, and its
    # week is its days, as a week of any calendar is.
    test "a week-based calendar's day is written in the locale's formats of its calendar" do
      assert Tempo.to_string(~o"2026-W25-2"W) == {:ok, "M06 16, 2026 AD"}

      assert Tempo.to_string(~o"2026-W25-2"W, format: :full, locale: :de) ==
               {:ok, "Dienstag, 16. M06 2026 n. Chr."}

      assert Tempo.to_string(~o"2026-W25"W) == {:ok, "M06 15 – 21, 2026 AD"}
    end

    # A year is written as its months, from the first to the last, as the
    # Gregorian year is "Jan – Dec 2026".
    test "a week-based calendar's year is written, alone and across a range" do
      assert Tempo.to_string(~o"2026") == {:ok, "Jan – Dec 2026"}
      assert Tempo.to_string(~o"2026"W) == {:ok, "M01 – M12 2026 AD"}

      assert Tempo.to_string(Tempo.from_iso8601!("2026/2028", ISOWeek)) ==
               {:ok, "2026 AD – 2027 AD"}
    end
  end

  # The user's decision of 2026-10-03: in the Gregorian calendar a week and
  # a day of it are the calendar date they name, built or read.
  describe "a Gregorian ISO week date" do
    test "is the calendar date it names, with its day of the week" do
      tuesday = Tempo.new!(year: 2026, week: 25, day_of_week: 2)

      assert tuesday == ~o"2026-06-16"
      assert tuesday == ~o"2026-W25-2"
      assert Tempo.day_of_week(tuesday) == 2
    end

    test "splits and rounds as the date it is" do
      tuesday = Tempo.new!(year: 2026, week: 25, day_of_week: 2)

      # A date rounds to the day its week begins on.
      assert Tempo.round(tuesday, :week) == ~o"2026-06-15"

      assert Tempo.split(Tempo.new!(year: 2026, week: 25, day_of_week: 2, hour: 10)) ==
               {tuesday, ~o"T10"}
    end

    test "a week alone is a week, and rounds in its year" do
      assert Tempo.new!(year: 2026, week: 25) == ~o"2026-W25"
      assert Tempo.round(~o"2026-W25", :year) == ~o"2026Y"
    end
  end

  # A recurrence's selection read a candidate's month and day, which a week
  # date has none of, so a weekday was not selected and a week and a weekday
  # selected nothing.
  describe "a recurrence's selection by day of the week" do
    defp occurrence_starts(text, calendar) do
      {:ok, set} =
        text
        |> Tempo.from_iso8601!(calendar)
        |> Tempo.to_interval()

      set
      |> IntervalSet.members()
      |> Enum.map(&Interval.from/1)
    end

    test "picks each week's day" do
      assert occurrence_starts("R3/2026-W01-1/P1W/FL2KN", ISOWeek) ==
               Enum.map(
                 ["2026-W01-2", "2026-W02-2", "2026-W03-2"],
                 &Tempo.from_iso8601!(&1, ISOWeek)
               )

      # The NRF calendar's weeks start on a Sunday, and the second day of one
      # is the day its values hold as 2: a Monday.
      assert occurrence_starts("R3/2026-W01-1/P1W/FL2KN", NRF) ==
               Enum.map(["2026-W01-2", "2026-W02-2", "2026-W03-2"], &Tempo.from_iso8601!(&1, NRF))
    end

    # A date of a calendar of weeks holds its week where a month is held,
    # and a year's weekdays were taken from its first twelve "months".
    test "picks that day of each week of a year" do
      {2026, weeks} = :calendar.iso_week_number({2026, 12, 28})
      assert weeks == 53

      assert occurrence_starts("2026YL1KN", ISOWeek) ==
               Enum.map(1..weeks, &Tempo.from_iso8601!("2026Y#{&1}W1K", ISOWeek))

      # The year's last Friday and its twentieth Monday.
      assert occurrence_starts("2026YL5K-1IN", ISOWeek) ==
               [Tempo.from_iso8601!("2026Y53W5K", ISOWeek)]

      assert occurrence_starts("2026YL1K20IN", ISOWeek) ==
               [Tempo.from_iso8601!("2026Y20W1K", ISOWeek)]

      {nrf_weeks, _days_in_last_week} = NRF.weeks_in_year(2026)
      assert length(occurrence_starts("2026YL1KN", NRF)) == nrf_weeks
    end

    test "picks a day of a selected week each year" do
      assert occurrence_starts("R3/2026-W25-1/P1Y/FL25W2KN", ISOWeek) ==
               Enum.map(
                 ["2026-W25-2", "2027-W25-2", "2028-W25-2"],
                 &Tempo.from_iso8601!(&1, ISOWeek)
               )
    end
  end

  # A calendar of weeks has no day of the month, so taking a week value to
  # day resolution found no path, and a value's selection, a `:within` window
  # and `select/2` gave the whole span or a `ResolutionError`.
  describe "a value's selection, a window and select/2" do
    test "a week value at day resolution is its first day of the week" do
      assert Tempo.at_resolution(Tempo.from_iso8601!("2026-W25", ISOWeek), :day) ==
               Tempo.from_iso8601!("2026-W25-1", ISOWeek)

      assert Tempo.at_resolution(Tempo.from_iso8601!("2026-W25", NRF), :day) ==
               Tempo.from_iso8601!("2026-W25-1", NRF)
    end

    test "a value's selection" do
      assert {:ok, set} = Tempo.to_interval(Tempo.from_iso8601!("2026YL1K1IN", ISOWeek))

      assert Enum.map(IntervalSet.members(set), &Interval.from/1) == [
               Tempo.from_iso8601!("2026-W01-1", ISOWeek)
             ]
    end

    test "a recurrence within a week year, and select/2" do
      tuesday = Tempo.from_iso8601!("2026-W25-2", ISOWeek)
      week_year = Tempo.from_iso8601!("2026", ISOWeek)

      assert {:ok, set} =
               Tempo.to_interval(Tempo.from_iso8601!("R/../P1Y/FL25W2KN"), within: week_year)

      assert Enum.map(IntervalSet.members(set), &Interval.from/1) == [tuesday]

      assert {:ok, selected} = Tempo.select(Tempo.from_iso8601!("2026-W25", ISOWeek), ~o"L2KN")
      assert Enum.map(IntervalSet.members(selected), &Interval.from/1) == [tuesday]
    end
  end

  # `K` counts the days of the week of the value that holds it: the
  # calendar's own week in a calendar of weeks, and ISO 8601's, which starts
  # on Monday, in a calendar of months. The NRF calendar's weeks start on a
  # Sunday, so its third day is a Tuesday, where the ISO week calendar's and
  # the Gregorian calendar's is a Wednesday. A selection read it as ISO
  # 8601's in every calendar, and so disagreed with the value beside it.
  describe "a day of the week is a day of its value's own week" do
    @monday 1
    @tuesday 2
    @wednesday 3
    @saturday 6
    @sunday 7

    defp read(text, calendar) do
      Tempo.from_iso8601!(text, calendar)
    end

    # The weekday of the day a value starts on, from Elixir's own calendar.
    defp weekday(%Tempo{} = value) do
      {:ok, date} =
        value
        |> Tempo.trunc(:day)
        |> Tempo.to_date()

      date
      |> Date.convert!(Calendar.ISO)
      |> Date.day_of_week()
    end

    defp weekdays({:ok, %IntervalSet{} = set}) do
      set
      |> IntervalSet.members()
      |> Enum.map(
        &(&1
          |> Interval.from()
          |> weekday())
      )
    end

    defp starts({:ok, %IntervalSet{} = set}) do
      set
      |> IntervalSet.members()
      |> Enum.map(&Interval.from/1)
    end

    test "in a value" do
      assert weekday(read("2026Y25W3K", NRF)) == @tuesday
      assert weekday(read("2026Y25W3K", ISOWeek)) == @wednesday
      assert weekday(~o"2026-W25-3") == @wednesday
    end

    test "in a value's selection, which is the value's own day" do
      assert starts(Tempo.to_interval(read("2026Y25WL3KN", NRF))) == [read("2026Y25W3K", NRF)]
      assert weekdays(Tempo.to_interval(read("2026Y25WL3KN", NRF))) == [@tuesday]
      assert weekdays(Tempo.to_interval(read("2026Y25WL3KN", ISOWeek))) == [@wednesday]
    end

    test "counted from the end of the week, and in a range" do
      assert weekdays(Tempo.to_interval(read("2026Y25WL-1KN", NRF))) == [@saturday]
      assert weekdays(Tempo.to_interval(read("2026Y25WL-1KN", ISOWeek))) == [@sunday]
      assert weekdays(Tempo.to_interval(read("2026Y25WL{2..6}KN", NRF))) == [1, 2, 3, 4, 5]
      assert weekdays(Tempo.to_interval(read("2026Y25WL{1,7}KN", NRF))) == [@sunday, @saturday]
    end

    test "in a recurrence's rule, with a week and with a position" do
      assert weekdays(Tempo.to_interval(read("R3/2026Y25W/P1W/FL3KN", NRF))) ==
               [@tuesday, @tuesday, @tuesday]

      assert starts(Tempo.to_interval(read("2026YL10W3KN", NRF))) == [read("2026Y10W3K", NRF)]
      assert starts(Tempo.to_interval(read("2026YL3K1IN", NRF))) == [read("2026Y1W3K", NRF)]

      {weeks, _days_in_the_last} = NRF.weeks_in_year(2026)

      assert starts(Tempo.to_interval(read("2026YL3K-1IN", NRF))) ==
               [read("2026Y#{weeks}W3K", NRF)]
    end

    test "in a selector, which is read in the calendar it is written in" do
      week = read("2026Y25W", NRF)

      assert starts(Tempo.select(week, read("3K", NRF))) == [read("2026Y25W3K", NRF)]
      assert weekdays(Tempo.select(week, read("3K", NRF))) == [@tuesday]

      # A selector written with the sigil is in the Gregorian calendar, where
      # the third day of the week is ISO 8601's Wednesday.
      assert weekdays(Tempo.select(week, ~o"3K")) == [@wednesday]
      assert weekdays(Tempo.select(week, read("3K", ISOWeek))) == [@wednesday]
      assert weekdays(Tempo.select(week, [~o"1K", ~o"3K"])) == [@monday, @wednesday]
      assert weekdays(Tempo.select(week, read("3KT10H", NRF))) == [@tuesday]
    end

    test "in a selector written in a calendar of weeks, for a span in a calendar of months" do
      # 19 to 25 July 2026 is NRF week 25, a Sunday to a Saturday.
      days = ~o"2026-07-19/2026-07-26"

      assert starts(Tempo.select(days, read("3K", NRF))) == [~o"2026-07-21"]
      assert starts(Tempo.select(days, ~o"3K")) == [~o"2026-07-22"]
      assert weekdays(Tempo.select(days, read("{1,-1}K", NRF))) == [@sunday, @saturday]
    end

    test "in a rule given as a selector" do
      week = read("2026Y25W", NRF)

      assert weekdays(Tempo.select(week, read("L3KN", NRF))) == [@tuesday]
      assert weekdays(Tempo.select(week, ~o"L3KN")) == [@wednesday]
    end

    test "leaves workdays and weekends the weekdays they name" do
      week = read("2026Y25W", NRF)

      assert weekdays(Tempo.select(week, Tempo.workdays(:US))) == [1, 2, 3, 4, 5]
      assert weekdays(Tempo.select(week, Tempo.weekends(:US))) == [@sunday, @saturday]
      assert weekdays(Tempo.select(week, Tempo.workdays(:SA))) == [@sunday, 1, 2, 3, 4]
    end

    test "is named by its calendar's weekday in an explanation and an RRULE" do
      assert to_string(Tempo.explain(read("2026Y25WL3KN", NRF))) =~ "selects on a Tuesday"
      assert to_string(Tempo.explain(read("2026Y25WL3KN", ISOWeek))) =~ "selects on a Wednesday"

      assert RRule.to_string(read("R2/2026Y25W/P1W/FL3KN", NRF)) ==
               {:ok, "FREQ=WEEKLY;COUNT=2;BYDAY=TU;WKST=SU"}

      assert RRule.to_string(read("R2/2026Y25W/P1W/FL{1,-1}KN", NRF)) ==
               {:ok, "FREQ=WEEKLY;COUNT=2;BYDAY=SU,SA;WKST=SU"}

      assert RRule.to_string(read("R2/2026Y25W/P1W/FL3KN", ISOWeek)) ==
               {:ok, "FREQ=WEEKLY;COUNT=2;BYDAY=WE"}
    end
  end
end
