defmodule Tempo.SplitTest do
  use ExUnit.Case, async: true

  # `Tempo.split/1` gives a value's date and its time of day. The shapes of
  # a date were listed one by one, and a date in a shape that was not listed
  # (a weekday of no week, a day of a year that is not named, a unit that
  # holds a group of a set) was given as the time of day: `3KT10H`, a
  # Wednesday at ten, had no date.
  #
  # The measure is the text. A value in the explicit form is written as its
  # date, then `T`, then its time of day, so its two parts are what the text
  # before the `T` reads as and what the text from the `T` reads as. Every
  # date here is written to a day, since a time of day written on a coarser
  # value is read as on its first day (`2026YT10H` is 1 January at ten).

  @dates [
    "2026Y6M15D",
    "2026Y25W3K",
    "2026Y166O",
    "6M15D",
    "25W3K",
    "15D",
    "3K",
    "166O",
    "2026Y6M{1,15}D",
    "{2025,2026}Y6M15D",
    "2026Y{1,2}G3MU15D",
    "2026Y6MXXD"
  ]

  @date_with_a_group_of_a_set "2026Y{1,2}G3MU15D"

  # A calendar of weeks holds a date as its week and its day of the week.
  @dates_in_weeks ["2026Y25W3K", "25W3K", "3K"]

  @times ["T10H", "T10H30M", "T10H30M45S", "T10H30M45.25S", "T{10,14}H", "TXXH"]

  @zones ["", "Z", "[Europe/Paris]"]

  @written for(
             {calendar, dates} <- [
               {Calendrical.Gregorian, @dates},
               {Calendrical.ISOWeek, @dates_in_weeks}
             ],
             date <- dates,
             zone <- @zones,
             do: {calendar, date, zone}
           )

  defp read(text, calendar), do: Tempo.from_iso8601!(text, calendar)

  describe "split/1" do
    test "gives the date written before the T and the time of day written from it" do
      for {calendar, date, zone} <- @written, time <- @times do
        text = date <> time <> zone
        value = read(text, calendar)

        assert {text, Tempo.split(value)} ==
                 {text, {read(date <> zone, calendar), read(time <> zone, calendar)}}
      end
    end

    # A value that holds a group of a set is not placed: `at/2` refuses it
    # by name, as every operation that reads one number from each unit does.
    test "gives parts that at/2 and on/2 place as the value" do
      for {calendar, date, zone} <- @written,
          date != @date_with_a_group_of_a_set,
          time <- @times do
        text = date <> time <> zone
        value = read(text, calendar)
        {date_part, time_part} = Tempo.split(value)

        assert {text, Tempo.at(date_part, time_part)} == {text, {:ok, value}}
        assert {text, Tempo.on(time_part, date_part)} == {text, {:ok, value}}
      end
    end

    test "gives a date no time of day" do
      for {calendar, date, zone} <- @written do
        value = read(date <> zone, calendar)

        assert {date, zone, Tempo.split(value)} == {date, zone, {value, nil}}
      end
    end

    test "gives a time of day no date" do
      for time <- @times, zone <- @zones do
        value = read(time <> zone, Calendrical.Gregorian)

        assert {time, zone, Tempo.split(value)} == {time, zone, {nil, value}}
      end
    end
  end

  # A selection that names a unit of a date is of the date: the Mondays of
  # June are days of June, and the value has no time of day. It was given as
  # the time of day (decided 2026-10-07). One that names units of the clock
  # alone is the time of day, and a time written after a selection is too.
  describe "split/1 of a value that holds a selection" do
    test "gives a selection of days with the date, and no time of day" do
      for text <- [
            "2026Y6ML1KN",
            "L1KN",
            "2026YL6M15DN",
            "2026YL1K1IN",
            "2024Y11MLLL1K1IN/P9DN2K1IN",
            "2027YLLL(easter)eN/P-3DN5K1IN"
          ] do
        value = read(text, Calendrical.Gregorian)

        assert {text, Tempo.split(value)} == {text, {value, nil}}
      end
    end

    test "gives the time written after a selection of days as the time of day" do
      for {date, time} <- [
            {"2018YL1K1IN", "T10H0M0S"},
            {"2026Y6ML1KN", "T9H"},
            {"L5KN", "T17H30M"}
          ] do
        value = read(date <> time, Calendrical.Gregorian)
        parts = {read(date, Calendrical.Gregorian), read(time, Calendrical.Gregorian)}

        assert {date, time, Tempo.split(value)} == {date, time, parts}
      end
    end

    # A selection with no period before it is not placed back in order by
    # `at/2` (`TODO.md`), so the two that have one are held to it.
    test "gives parts that at/2 places as the value, where the selection is within a period" do
      for text <- ["2018YL1K1INT10H0M0S", "2026Y6ML1KNT9H"] do
        value = read(text, Calendrical.Gregorian)
        {date, time} = Tempo.split(value)

        assert {text, Tempo.at(date, time)} == {text, {:ok, value}}
      end
    end

    test "gives a selection of times as the time of day" do
      third_twenty_past_eight = read("2018Y9MTLT8H20M3IN", Calendrical.Gregorian)
      {date, time} = Tempo.split(third_twenty_past_eight)

      assert date == read("2018Y9M", Calendrical.Gregorian)
      assert time == read("TLT8H20M3IN", Calendrical.Gregorian)
      assert Tempo.at(date, time) == {:ok, third_twenty_past_eight}
    end
  end
end
