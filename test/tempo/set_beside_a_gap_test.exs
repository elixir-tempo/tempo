defmodule Tempo.SetBesideAGapTest do
  @moduledoc """
  A set that names a reading its zone's clock skips.

  One value that names such a reading is refused when it is read: 02:30 in
  Paris on the night its clocks go from 02:00 to 03:00, the day Samoa left
  out. A value that holds a set in a unit names each value the set does,
  and was read with the skipped one no value of it. It is refused as the
  one value is (decided 2026-10-07), in whichever form the set is written.

  The measure is Elixir's own `DateTime`: each reading a value names, by
  the values of its sets, asked whether the zone's clock shows it.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  # A change of a zone's clock that skips readings: the zone, the day, and
  # the hour the first reading skipped is in. Paris and New York skip an
  # hour, Lord Howe Island half of one, Cairo its first hour of the day,
  # and Samoa left the day out.
  @gaps [
    {"Europe/Paris", ~D[2026-03-29], 2},
    {"America/New_York", ~D[2026-03-08], 2},
    {"Australia/Lord_Howe", ~D[2026-10-04], 2},
    {"Africa/Cairo", ~D[2023-04-28], 0},
    {"Pacific/Apia", ~D[2011-12-30], 12}
  ]

  ## The measure

  # Whether the clock skips the whole of a reading: a minute it never
  # shows, an hour whose first and last second it never shows, a day whose.
  defp skipped?(zone, date, nil, nil),
    do: gap?(zone, date, ~T[00:00:00]) and gap?(zone, date, ~T[23:59:59])

  defp skipped?(zone, date, hour, nil),
    do: gap?(zone, date, Time.new!(hour, 0, 0)) and gap?(zone, date, Time.new!(hour, 59, 59))

  defp skipped?(zone, date, hour, minute), do: gap?(zone, date, Time.new!(hour, minute, 0))

  defp gap?(zone, date, time),
    do: match?({:gap, _before, _after}, DateTime.new(date, time, zone))

  # The readings a value names: one for each value of each of its sets.
  defp readings(%{date: date, days: days, hours: hours, minutes: minutes}) do
    for day <- days, hour <- hours || [nil], minute <- minutes || [nil] do
      {%{date | day: day}, hour, minute}
    end
  end

  ## The value as text

  defp text(%{zone: zone, date: date, days: days, hours: hours, minutes: minutes}) do
    "#{date.year}Y#{date.month}M#{set(days)}D" <>
      if(hours, do: "T#{set(hours)}H", else: "") <>
      if(minutes, do: "#{set(minutes)}M", else: "") <> "[#{zone}]"
  end

  defp set([value]), do: "#{value}"
  defp set(values), do: "{" <> Enum.join(values, ",") <> "}"

  # Values beside a gap: its day with the days about it, its hour with the
  # hours about it, and minutes of the hour.
  defp beside({zone, %Date{day: day} = date, hour}) do
    hours = fn values -> values |> Enum.filter(&(&1 in 0..23)) |> Enum.uniq() end

    for days <- [[day], [day - 1, day], [day - 2, day - 1], [day, day + 1], [day - 1, day + 1]],
        hours <- [nil, [hour], hours.([hour - 1, hour]), hours.([hour - 1, hour + 1])],
        minutes <- if(hours, do: [nil, [0, 30], [15, 45], [59]], else: [nil]) do
      %{zone: zone, date: date, days: days, hours: hours, minutes: minutes}
    end
  end

  describe "a value that holds a set in a unit" do
    test "is refused where it names a reading the clock skips, and read where it names none" do
      verdicts =
        for gap <- @gaps, value <- beside(gap) do
          {zone, _date, _hour} = gap

          skipped =
            for {date, hour, minute} <- readings(value),
                skipped?(zone, date, hour, minute),
                do: date

          read =
            case Tempo.from_iso8601(text(value)) do
              {:ok, _value} -> :read
              {:error, %Tempo.ZoneGapError{zone_id: ^zone}} -> :refused
            end

          assert {text(value), read} ==
                   {text(value), if(skipped == [], do: :read, else: :refused)}

          read
        end

      # Both are met, many times.
      assert %{read: read, refused: refused} = Enum.frequencies(verdicts)
      assert read > 100 and refused > 100
    end

    test "is refused in the texts it was decided on" do
      for {text, reading} <- [
            {"2026Y3M{28,29}DT2H30M[Europe/Paris]", "2026-03-29T02:30:00"},
            {"2011-12-{29,30}[Pacific/Apia]", "2011-12-30"},
            {"{2026-03-28T02:30,2026-03-29T02:30}[Europe/Paris]", "2026-03-29T02:30:00"},
            # A range in a unit names each value from its first to its last.
            {"2026Y3M29DT{1..3}H[Europe/Paris]", "2026-03-29T02"},
            {"2011Y12M{29..31}D[Pacific/Apia]", "2011-12-30"},
            # A set in any unit: the months, the years, the seconds.
            {"2026Y{3,4}M29DT2H30M[Europe/Paris]", "2026-03-29T02:30:00"},
            {"{2026,2027}Y3M29DT2H30M[Europe/Paris]", "2026-03-29T02:30:00"},
            {"2026Y3M29DT2H30M{0,30}S[Europe/Paris]", "2026-03-29T02:30:00"},
            # An hour the clock skips, by its minutes.
            {"2026Y3M29DT2H{0,30}M[Europe/Paris]", "2026-03-29T02:00:00"}
          ] do
        assert {text, {:error, %Tempo.ZoneGapError{wall_time: named}}} =
                 {text, Tempo.from_iso8601(text)}

        assert {text, named} == {text, reading}
      end
    end

    test "is refused as its date is written: a day of the year, of a week, of another calendar" do
      # 29 March 2026 is the 88th day of its year, the Sunday of its week 13
      # and 11 Nisan 5786, the seventh month of the Hebrew year.
      assert Date.day_of_year(~D[2026-03-29]) == 88
      assert :calendar.iso_week_number({2026, 3, 29}) == {2026, 13}

      assert Date.convert!(~D[2026-03-29], Calendrical.Hebrew) ==
               Date.new!(5786, 7, 11, Calendrical.Hebrew)

      for {named, names_none} <- [
            {"2026Y{87,88}DT2H30M[Europe/Paris]", "2026Y{86,87}DT2H30M[Europe/Paris]"},
            {"2026Y13W{6,7}KT2H30M[Europe/Paris]", "2026Y13W{5,6}KT2H30M[Europe/Paris]"},
            {"5786-07-{10,11}T02:30[Europe/Paris][u-ca=hebrew]",
             "5786-07-{9,10}T02:30[Europe/Paris][u-ca=hebrew]"}
          ] do
        assert {named, {:error, %Tempo.ZoneGapError{wall_time: "2026-03-29T02:30:00"}}} =
                 {named, Tempo.from_iso8601(named)}

        assert {names_none, {:ok, %Tempo{}}} = {names_none, Tempo.from_iso8601(names_none)}
      end
    end

    test "is refused when a zone is given to it" do
      assert {:error, %Tempo.ZoneGapError{wall_time: "2026-03-29T02:30:00"}} =
               Tempo.in_zone(~o"2026Y3M{28,29}DT2H30M", "Europe/Paris")

      assert {:ok, %Tempo{}} = Tempo.in_zone(~o"2026Y3M{27,28}DT2H30M", "Europe/Paris")
    end

    test "is read in no zone, and in a zone written as an offset, whose clock skips nothing" do
      assert {:ok, %Tempo{}} = Tempo.from_iso8601("2026Y3M{28,29}DT2H30M")
      assert {:ok, %Tempo{}} = Tempo.from_iso8601("2026Y3M{28,29}DT2H30M[+01:00]")
    end

    test "is read with unspecified digits, which stand for the values the clock has" do
      {:ok, some_day} = Tempo.from_iso8601("2026Y3M2XDT2H30M[Europe/Paris]")

      days =
        for day <- 20..29, not skipped?("Europe/Paris", Date.new!(2026, 3, day), 2, 30), do: day

      assert days == Enum.to_list(20..28)
      assert Enum.map(some_day, &Keyword.fetch!(&1.time, :day)) == days
    end
  end

  describe "a range of whole values in a set" do
    test "is refused where an end of it is a reading the clock skips, as an end of an interval is" do
      for text <- [
            "{2026-03-28T02:30..2026-03-29T02:30}[Europe/Paris]",
            "{2026-03-29T02:30..2026-03-30T02:30}[Europe/Paris]",
            "{2011-12-28..2011-12-30}[Pacific/Apia]"
          ] do
        assert {text, {:error, %Tempo.ZoneGapError{}}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "is the readings the clock shows from one end to the other" do
      {:ok, set} = Tempo.from_iso8601("{2026-03-29T01:30..2026-03-29T03:30}[Europe/Paris]")
      {:ok, %IntervalSet{} = spans} = Tempo.to_interval(set)

      minutes =
        ~N[2026-03-29 01:30:00]
        |> Stream.iterate(&NaiveDateTime.add(&1, 1, :minute))
        |> Enum.take_while(&(NaiveDateTime.compare(&1, ~N[2026-03-29 03:30:00]) != :gt))
        |> Enum.reject(&match?({:gap, _, _}, DateTime.from_naive(&1, "Europe/Paris")))

      # Half an hour before the gap, and thirty-one minutes after it.
      assert Enum.count(minutes) == 61

      assert Enum.map(IntervalSet.members(spans), &hour_and_minute/1) ==
               Enum.map(minutes, &{&1.hour, &1.minute})
    end
  end

  describe "a value written by its next finer unit" do
    test "is written by the values its clock shows, and is read back as it is written" do
      for {zone, date, hour} <- @gaps do
        day = shown("#{date}[#{zone}]")
        day_before = Date.add(date, -1)
        month = shown("#{Calendar.strftime(date, "%Y-%m")}[#{zone}]")

        days =
          for d <- 1..Date.days_in_month(date),
              not skipped?(zone, %{date | day: d}, nil, nil),
              do: d

        hours = for h <- 0..23, not skipped?(zone, date, h, nil), do: h

        for {value, shown} <- [
              {month, days},
              {day, hours},
              {at_hour(day_before, hour, zone), minutes_shown(zone, day_before, hour)},
              {at_hour(date, hour, zone), minutes_shown(zone, date, hour)},
              {at_hour(date, hour + 1, zone), minutes_shown(zone, date, hour + 1)}
            ],
            value != nil do
          {:ok, written} = Tempo.extend(value)
          {_unit, values} = List.last(written.time)

          assert {inspect(value), Enum.flat_map(values, &each/1)} == {inspect(value), shown}

          assert {inspect(value), Tempo.from_iso8601(Tempo.to_iso8601!(written))} ==
                   {inspect(value), {:ok, written}}
        end
      end
    end

    test "is the hours of the day Paris's clocks go forward but the one they skip" do
      assert Tempo.extend(~o"2026-03-29[Europe/Paris]") ==
               {:ok, ~o"2026Y3M29DT{0..1,3..23}H[Europe/Paris]"}

      assert Tempo.extend(~o"2026-03-28[Europe/Paris]") ==
               {:ok, ~o"2026Y3M28DT{0..23}H[Europe/Paris]"}

      assert Tempo.extend(~o"2011-12[Pacific/Apia]") ==
               {:ok, ~o"2011Y12M{1..29,31}D[Pacific/Apia]"}

      # The half hour Lord Howe Island's clocks skip is the first of its hour.
      assert Tempo.extend(~o"2026-10-04T02[Australia/Lord_Howe]") ==
               {:ok, ~o"2026Y10M4DT2H{30..59}M[Australia/Lord_Howe]"}
    end

    test "is no one value under days whose hours the clock shows are not the same" do
      assert {:error, %Tempo.ConversionError{}} = Tempo.extend(~o"2026Y3M{28,29}D[Europe/Paris]")

      assert Tempo.extend(~o"2026Y3M{27,28}D[Europe/Paris]") ==
               {:ok, ~o"2026Y3M{27..28}DT{0..23}H[Europe/Paris]"}
    end
  end

  defp minutes_shown(zone, date, hour),
    do: for(minute <- 0..59, not skipped?(zone, date, hour, minute), do: minute)

  defp each(value) when is_integer(value), do: [value]
  defp each(%Range{} = values), do: Enum.to_list(values)

  defp hour_and_minute(%Interval{} = member) do
    time = Interval.from(member).time
    {Keyword.fetch!(time, :hour), Keyword.fetch!(time, :minute)}
  end

  # A date and an hour in a zone, or none where the clock skips the hour.
  defp at_hour(date, hour, zone),
    do: shown("#{date}T#{String.pad_leading("#{hour}", 2, "0")}[#{zone}]")

  # A value read, or none where the clock skips the whole of it.
  defp shown(text) do
    case Tempo.from_iso8601(text) do
      {:ok, value} -> value
      {:error, %Tempo.ZoneGapError{}} -> nil
    end
  end
end
