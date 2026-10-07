defmodule Tempo.ShiftOfSetsTest do
  use ExUnit.Case, async: true

  # A shift reaches each value a set names (decided 2026-10-04): each is
  # stepped as the one value it is, and what they land on is written as one
  # value where the values its units then hold name those and no others, and
  # as the set of their spans where they do not. A step from a unit that
  # holds a set was refused, and a step by another unit moved the set as one
  # value, which is another answer where its members do not take the step
  # alike.
  #
  # The measure is `Date`, `NaiveDateTime` and `DateTime` alone: each value
  # the set names is built and stepped there, and the answer must name the
  # spans they land on, and be one value where they are every combination of
  # the values their units hold.

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.ISOWeek
  alias Calendrical.Reform.England
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.UnanchoredError

  @letters [year: "Y", month: "M", week: "W", day: "D", day_of_week: "K", hour: "H"]
  @finest_first [:hour, :day, :month, :year]

  # What is written: `[year: [2026], month: [6], day: [1, 15]]` is
  # `2026Y6M{1,15}D`.
  defp written(units) do
    Enum.map_join(units, fn {unit, values} ->
      "#{if unit == :hour, do: "T"}#{held(values)}#{@letters[unit]}"
    end)
  end

  defp held([value]), do: "#{value}"
  defp held(values), do: "{#{Enum.join(values, ",")}}"

  # Each date and time a value names, in the order it names them: every
  # combination of what its units hold that is a date.
  defp named(units) do
    for year <- units[:year],
        month <- units[:month] || [1],
        day <- units[:day] || [1],
        hour <- units[:hour] || [0],
        {:ok, date} <- [Date.new(year, month, day)] do
      NaiveDateTime.new!(date, Time.new!(hour, 0, 0))
    end
  end

  # The unit an answer is written to: the finer of the value's and the
  # step's, a week being stepped as its days.
  defp answered_to(units, step) do
    stepped = for {unit, _amount} <- step, do: if(unit == :week, do: :day, else: unit)
    Enum.find(@finest_first, &(Keyword.has_key?(units, &1) or &1 in stepped))
  end

  # The spans the stepped values are, each one unit long, and whether one
  # value names them: whether they are every combination of the values
  # their units hold.
  defp expected(units, step) do
    unit = answered_to(units, step)
    landed = units |> named() |> Enum.map(&NaiveDateTime.shift(&1, step)) |> Enum.uniq()
    spans = for start <- landed, do: {start, NaiveDateTime.shift(start, [{unit, 1}])}

    {Enum.sort_by(spans, &elem(&1, 0), NaiveDateTime),
     every_combination?(Enum.map(landed, &fields(&1, unit)))}
  end

  defp fields(moment, :year), do: [moment.year]
  defp fields(moment, :month), do: [moment.year, moment.month]
  defp fields(moment, :day), do: [moment.year, moment.month, moment.day]
  defp fields(moment, :hour), do: [moment.year, moment.month, moment.day, moment.hour]

  defp every_combination?(rows) do
    combinations =
      rows
      |> Enum.zip_with(&(&1 |> Enum.uniq() |> Enum.count()))
      |> Enum.product()

    combinations == Enum.count(rows)
  end

  # The spans an answer names, each from its start to its end.
  defp spans(%Tempo{} = value) do
    case Tempo.to_interval(value) do
      {:ok, %Interval{} = span} -> [ends(span)]
      {:ok, %IntervalSet{} = set} -> spans(set)
    end
  end

  defp spans(%IntervalSet{} = set), do: set |> IntervalSet.members() |> Enum.map(&ends/1)

  defp ends(%Interval{} = span), do: {moment(Interval.from(span)), moment(Interval.to(span))}

  defp moment(%Tempo{} = point) do
    {:ok, moment} = point |> Tempo.extend_resolution(:second) |> Tempo.to_naive_datetime()
    moment
  end

  defp one_value?(%Tempo{}), do: true
  defp one_value?(%IntervalSet{}), do: false

  @years [[2026], [2024], [2024, 2025], [2026, 2027]]
  @months [nil, [1], [2], [6], [12], [1, 2], [6, 7], [11, 12], [1, 12]]
  @days [nil, [1], [15], [28], [31], [1, 15], [15, 30], [28, 29], [30, 31]]

  @steps [
    [day: 1],
    [day: -1],
    [day: 45],
    [week: 1],
    [month: 1],
    [month: -1],
    [month: 13],
    [year: 1],
    [year: -1],
    [month: 1, day: 1],
    [year: 1, month: -1, day: -1]
  ]

  # Every value of years, months and days that holds a set and names a date.
  # A set names the days each of its years and months has, so a day that
  # none of them has is not written under them.
  defp dates_holding_sets do
    for years <- @years,
        months <- @months,
        days <- if(months, do: @days, else: [nil]),
        units = Enum.reject([year: years, month: months, day: days], &is_nil(elem(&1, 1))),
        Enum.any?(units, &match?({_unit, [_one, _another | _more]}, &1)),
        each_day_is_a_date?(units) do
      units
    end
  end

  defp each_day_is_a_date?(year: years, month: months, day: days) do
    Enum.all?(days, fn day ->
      Enum.any?(
        for(year <- years, month <- months, do: Date.new(year, month, day)),
        &match?({:ok, _}, &1)
      )
    end)
  end

  defp each_day_is_a_date?(_units), do: true

  describe "each value a set names is stepped" do
    test "by every unit, whichever unit holds the set" do
      values = dates_holding_sets()
      assert Enum.count(values) > 200

      for units <- values do
        text = written(units)
        value = Tempo.from_iso8601!(text)

        for step <- @steps do
          answer = Tempo.shift(value, step)
          {expected_spans, expected_one_value?} = expected(units, step)

          assert {text, step, spans(answer)} == {text, step, expected_spans}
          assert {text, step, one_value?(answer)} == {text, step, expected_one_value?}
        end
      end
    end

    test "under a time of day, and through one" do
      for days <- [[15], [1, 15], [30, 31]],
          hours <- [[9], [9, 17], [0, 23]],
          units = [year: [2026], month: [12], day: days, hour: hours],
          step <- [[hour: 1], [hour: -1], [hour: 8], [hour: 30], [day: 1], [month: 2]],
          days != [15] or hours != [9] do
        text = written(units)
        answer = Tempo.shift(Tempo.from_iso8601!(text), step)
        {expected_spans, expected_one_value?} = expected(units, step)

        assert {text, step, spans(answer)} == {text, step, expected_spans}
        assert {text, step, one_value?(answer)} == {text, step, expected_one_value?}
      end
    end

    test "a date a set names in no year or month of its own is not stepped" do
      # 29 February is a date of 2024 alone, and the 31st of seven months.
      assert Tempo.shift(~o"{2024,2025}Y2M29D", day: 1) == ~o"2024Y3M1D"
      assert Tempo.shift(~o"{2024,2025}Y2M29D", year: 1) == ~o"2025Y2M28D"

      assert spans(Tempo.shift(~o"2026Y{1..12}M31D", day: 1)) ==
               for(
                 month <- [1, 3, 5, 7, 8, 10, 12],
                 next = Date.add(Date.new!(2026, month, 31), 1),
                 do:
                   {NaiveDateTime.new!(next, ~T[00:00:00]),
                    NaiveDateTime.new!(Date.add(next, 1), ~T[00:00:00])}
               )
    end
  end

  describe "what the values land on" do
    test "is one value where its units hold them all, and no others" do
      assert Tempo.shift(~o"2026Y6M{1,15}D", day: 1) == ~o"2026Y6M{2,16}D"
      assert Tempo.shift(~o"2026Y6M{1..5}D", day: 1) == ~o"2026Y6M{2..6}D"
      assert Tempo.shift(~o"2026Y{6,7}M15D", month: 1) == ~o"2026Y{7,8}M15D"
      assert Tempo.shift(~o"2026Y{6,7}M", month: 1) == ~o"2026Y{7,8}M"
      assert Tempo.shift(~o"{2026,2027}Y", year: 1) == ~o"{2027,2028}Y"
      assert Tempo.shift(~o"{2026,2027}Y12M31D", day: 1) == ~o"{2027,2028}Y1M1D"
      assert Tempo.shift(~o"2026Y{6,7}M{1,15}D", day: 1) == ~o"2026Y{6,7}M{2,16}D"
      assert Tempo.shift(~o"2026Y6M15DT{9,17}H", hour: 1) == ~o"2026Y6M15DT{10,18}H"

      # The day after the 30th of June and of July is the 1st and the 31st
      # of July.
      assert Tempo.shift(~o"2026Y{6,7}M30D", day: 1) == ~o"2026Y7M{1,31}D"
    end

    test "is one value once where several land on it" do
      assert Tempo.shift(~o"2026Y1M{28..31}D", month: 1) == ~o"2026Y2M28D"
      assert Tempo.shift(~o"2024Y2M{28,29}D", year: 1) == ~o"2025Y2M28D"
    end

    test "is the set of their spans where no one value names them" do
      assert spans(Tempo.shift(~o"2026Y6M{15,30}D", day: 1)) == [
               {~N[2026-06-16 00:00:00], ~N[2026-06-17 00:00:00]},
               {~N[2026-07-01 00:00:00], ~N[2026-07-02 00:00:00]}
             ]

      assert %IntervalSet{} = Tempo.shift(~o"2026Y6M{15,30}D", day: 1)
      assert %IntervalSet{} = Tempo.shift(~o"2026Y6M{1,15}D", day: -1)
      assert %IntervalSet{} = Tempo.shift(~o"2026Y{11,12}M", month: 1)
      assert %IntervalSet{} = Tempo.shift(~o"2026Y6M15DT{9,17}H", hour: 8)
    end

    # A margin of error and significant digits ride on a unit, as they do
    # on one value. They were lost with the set's values, and significant
    # digits were stepped as every year they stand for.
    test "carries a margin of error and significant digits on the unit they are written on" do
      assert Tempo.shift(~o"2018±2Y6M{1,15}D", day: 1) == ~o"2018±2Y6M{2,16}D"
      assert Tempo.shift(~o"2018±2Y6M{1,15}D", month: 1) == ~o"2018±2Y7M{1,15}D"
      assert Tempo.shift(~o"2018±2Y12M{30,31}D", day: 2) == ~o"2019±2Y1M{1,2}D"
      assert Tempo.shift(~o"2018Y{6,7}M15±2D", month: 1) == ~o"2018Y{7,8}M15±2D"
      assert Tempo.shift(~o"2018±2Y{100,200}O", day: 1) == ~o"2018±2Y{101,201}O"
      assert Tempo.shift(~o"1950S2Y6M{1,15}D", day: 1) == ~o"1950S2Y6M{2,16}D"
      assert Tempo.shift(~o"1950S2Y6M{1,15}D", month: 1) == ~o"1950S2Y7M{1,15}D"

      # Where no one value names what they land on, each is its span: one
      # day for a margin of error, and for significant digits the day of
      # every year they stand for, which is no one span.
      assert %IntervalSet{} = Tempo.shift(~o"2018±2Y6M{15,30}D", day: 1)

      assert {:error, %ConversionError{reason: :grouped_component}} =
               Tempo.shift(~o"1950S2Y6M{15,30}D", day: 1)
    end

    test "keeps what qualifies the value, and a fraction of a second" do
      assert Tempo.shift(~o"2026Y6M{1,15}D?", day: 1) == ~o"2026Y6M{2,16}D?"
      assert Tempo.shift(~o"2026?Y6M{1,15}D", day: 1) == ~o"2026?Y6M{2,16}D"

      assert Tempo.shift(~o"2026Y6M{1,15}DT10H30M15.5S", day: 1) ==
               ~o"2026Y6M{2,16}DT10H30M15.5S"
    end
  end

  # The Monday of an ISO 8601 week: 4 January is always in week 1.
  defp monday(year, week) do
    fourth = Date.new!(year, 1, 4)
    Date.add(fourth, 1 - Date.day_of_week(fourth) + 7 * (week - 1))
  end

  defp week_date(date) do
    {week_year, week} = :calendar.iso_week_number(Date.to_erl(date))
    [week_year, week, Date.day_of_week(date)]
  end

  defp days_spanned(answer) do
    for {from, to} <- spans(answer) do
      {NaiveDateTime.to_date(from),
       Date.diff(NaiveDateTime.to_date(to), NaiveDateTime.to_date(from))}
    end
  end

  describe "a week date" do
    test "is the date it names, stepped as that date by every unit" do
      for weeks <- [[25], [25, 26], [1, 53], [52, 53]],
          weekdays <- [[1], [1, 3], [6, 7], [1, 7]],
          weeks != [25] or weekdays != [1],
          step <- [[day: 1], [day: -1], [day: 9], [week: 1], [month: 1], [year: 1], [year: -1]] do
        text = written(year: [2026], week: weeks, day_of_week: weekdays)

        landed =
          for week <- weeks, weekday <- weekdays do
            2026 |> monday(week) |> Date.add(weekday - 1) |> Date.shift(step)
          end

        landed = Enum.uniq(landed)
        answer = Tempo.shift(Tempo.from_iso8601!(text), step)

        assert {text, step, days_spanned(answer)} ==
                 {text, step, landed |> Enum.sort(Date) |> Enum.map(&{&1, 1})}

        assert {text, step, one_value?(answer)} ==
                 {text, step, every_combination?(Enum.map(landed, &week_date/1))}
      end
    end

    test "is written again as a week and its days" do
      assert Tempo.shift(~o"2026Y25W{1,3}K", day: 1) == ~o"2026Y25W{2,4}K"
      assert Tempo.shift(~o"2026Y{25,30}W3K", week: 1) == ~o"2026Y{26,31}W3K"
      assert Tempo.shift(~o"2026Y53W{4,5}K", day: 1) == ~o"2026Y53W{5,6}K"

      # 15 and 17 June 2027, a Tuesday and a Thursday, where the set was
      # moved as one value to the Monday and the Wednesday of week 25 of 2027.
      assert Tempo.shift(~o"2026Y25W{1,3}K", year: 1) == ~o"2027Y24W{2,4}K"
      assert Tempo.shift(~o"2026Y25W{1,3}K", month: 1) == ~o"2026Y29W{3,5}K"
    end

    test "of whole weeks is stepped week by week" do
      assert Tempo.shift(~o"2026Y{25,26}W", week: 1) == ~o"2026Y{26,27}W"
      assert Tempo.shift(~o"2026Y{25,26}W", day: 1) == ~o"2026Y{25,26}W2K"

      # 2026 has 53 weeks.
      assert days_spanned(Tempo.shift(~o"2026Y{52,53}W", week: 1)) ==
               [{monday(2026, 53), 7}, {monday(2027, 1), 7}]
    end

    test "in a calendar of weeks keeps its week and its day" do
      week_date = &Tempo.from_iso8601!(&1, ISOWeek)

      assert Tempo.shift(week_date.("2026Y25W{1,3}K"), day: 1) == week_date.("2026Y25W{2,4}K")
      assert Tempo.shift(week_date.("2026Y{25,26}W"), week: 1) == week_date.("2026Y{26,27}W")
      assert Tempo.shift(week_date.("2026Y25W{1,3}K"), year: 1) == week_date.("2027Y25W{1,3}K")
      assert %IntervalSet{} = Tempo.shift(week_date.("2026Y25W{6,7}K"), day: 1)
    end
  end

  describe "days of the year" do
    test "that land on one date are that date once" do
      # 30 and 31 January a month on are both 28 February.
      set = Tempo.shift(~o"2026Y{30,31,365}O", month: 1)

      assert days_spanned(set) == [{~D[2026-02-28], 1}, {~D[2027-01-31], 1}]
    end
  end

  # A value in a zone. Years, months, weeks and days step its wall clock and
  # hours, minutes and seconds the time line, so a step of hours is another
  # reading of the clock on the day it changes.
  describe "a value in a zone" do
    defp paris(day, hour) do
      DateTime.new!(Date.new!(2026, 3, day), Time.new!(hour, 0, 0), "Europe/Paris")
    end

    defp readings(answer) do
      for {from, _to} <- zoned_spans(answer),
          do: {from.day, from.hour, from.utc_offset + from.std_offset}
    end

    defp zoned_spans(%IntervalSet{} = set) do
      for member <- IntervalSet.members(set) do
        {zoned(Interval.from(member)), zoned(Interval.to(member))}
      end
    end

    defp zoned_spans(%Tempo{} = value) do
      {:ok, set} = Tempo.to_interval_set(value)
      zoned_spans(set)
    end

    defp zoned(%Tempo{} = point) do
      {:ok, moment} = point |> Tempo.extend_resolution(:second) |> Tempo.to_datetime()
      moment
    end

    test "steps hours on the time line from each of its days" do
      # Paris moves from 02:00 to 03:00 on 29 March 2026.
      for hour <- [0, 1, 3, 12],
          hours <- [1, 2, 3, 26],
          days <- [[27, 28], [28, 29], [28, 29, 30]] do
        text = "2026Y3M{#{Enum.join(days, ",")}}DT#{hour}H[Europe/Paris]"
        answer = Tempo.shift(Tempo.from_iso8601!(text), hour: hours)

        expected =
          for day <- days do
            later = DateTime.add(paris(day, hour), hours, :hour)
            {later.day, later.hour, later.utc_offset + later.std_offset}
          end

        assert {text, hours, readings(answer)} == {text, hours, expected}
      end
    end

    test "steps days on the wall clock" do
      assert Tempo.shift(~o"2026Y3M{28,29}DT12H[Europe/Paris]", day: 1) ==
               ~o"2026Y3M{29,30}DT12H[Europe/Paris]"

      assert Tempo.shift(~o"2026Y{2,3}M15DT10H[Europe/Paris]", month: 1) ==
               ~o"2026Y{3,4}M15DT10H[Europe/Paris]"
    end

    test "names the reading a clock repeats by its offset" do
      # Paris moves from 03:00 back to 02:00 on 25 October 2026: an hour on
      # from 01:30 is the first 02:30 there, and from 02:30 the second.
      first = Tempo.shift(~o"2026Y10M{24,25}DT1H30M[Europe/Paris]", hour: 1)
      second = Tempo.shift(~o"2026Y10M{24,25}DT2H30M[Europe/Paris]", hour: 1)

      assert [{24, 2, 7200}, {25, 2, 7200}] = readings(first)
      assert [{24, 3, 7200}, {25, 2, 3600}] = readings(second)
    end
  end

  describe "a value with no year" do
    test "is stepped value by value on its own axis" do
      assert Tempo.shift(~o"T{9,17}H", hour: 1) == ~o"T{10,18}H"
      assert Tempo.shift(~o"T{9,23}H", hour: 1) == ~o"T{0,10}H"
      assert Tempo.shift(~o"6M{1,15}D", day: 1) == ~o"6M{2,16}D"
      assert Tempo.shift(~o"{6,7}M", month: 1) == ~o"{7,8}M"
      assert Tempo.shift(~o"{11,12}M", month: 1) == ~o"{1,12}M"
      assert Tempo.shift(~o"{6,7}K", day: 1) == ~o"{1,7}K"
      assert Tempo.shift(~o"25W{1,3}K", day: 1) == ~o"25W{2,4}K"
    end

    test "is the error of the first value that cannot be stepped" do
      # The day after 28 February depends on the year.
      assert {:error, %UnanchoredError{value: value}} = Tempo.shift(~o"2M{27,28}D", day: 1)
      assert value == ~o"2M28D"
    end
  end

  describe "another calendar" do
    test "steps each of its dates" do
      for {months, days} <- [{[6], [1, 15]}, {[6, 7], [29]}, {[11, 12], [29, 30]}],
          step <- [1, -1, 40] do
        text = "5786Y#{held(months)}M#{held(days)}D"

        landed =
          for month <- months, day <- days, {:ok, date} <- [Date.new(5786, month, day, Hebrew)] do
            Date.add(date, step)
          end

        answer = Tempo.shift(Tempo.from_iso8601!(text, Hebrew), day: step)

        starts =
          answer
          |> hebrew_starts()
          |> Enum.sort_by(&Date.to_gregorian_days/1)

        assert {text, step, starts} ==
                 {text, step, landed |> Enum.uniq() |> Enum.sort_by(&Date.to_gregorian_days/1)}
      end
    end

    defp hebrew_starts(%Tempo{} = value) do
      {:ok, set} = Tempo.to_interval_set(value)
      hebrew_starts(set)
    end

    defp hebrew_starts(%IntervalSet{} = set) do
      for member <- IntervalSet.members(set) do
        {:ok, date} = member |> Interval.from() |> Tempo.to_date()
        date
      end
    end

    test "skips the days its calendar does" do
      # England left out 3 to 13 September 1752.
      september = Tempo.from_iso8601!("1752Y9M{1,2}D", England)

      assert Tempo.shift(september, day: 1) == Tempo.from_iso8601!("1752Y9M{2,14}D", England)
    end
  end

  describe "a set beside a mask or a group" do
    test "is each value the two stand for, where a mask is counted from or refused" do
      # Some day of June or of July, a day on and a month on.
      assert days_spanned(Tempo.shift(~o"2026Y{6,7}MXXD", day: 1)) == [{~D[2026-06-02], 61}]

      assert days_spanned(Tempo.shift(~o"2026Y{6,7}MXXD", month: 1)) ==
               [{~D[2026-07-01], 30}, {~D[2026-08-01], 31}]

      assert Tempo.shift(~o"2026Y{6,7}MXXD", year: 1) == ~o"2027Y{6,7}MXXD"
    end

    test "keeps the refusal of a group" do
      assert {:error, %ConversionError{reason: :grouped_component}} =
               Tempo.shift(Tempo.from_iso8601!("2026Y{1,2}G3MU"), month: 1)
    end
  end

  # An interval written with a duration from a value that holds a set is
  # the span from each value (decided 2026-10-07): it had no one start, and
  # was refused. `Tempo.SpanFromEachValueTest` holds the spans to `Date`.
  describe "an interval counted from a value that holds a set" do
    test "is the span from each value, each ending where a step from it lands" do
      for {set, duration} <- [
            {"2026Y6M{1,15}D", "P1D"},
            {"2026Y6M{15,30}D", "P1D"},
            {"2026Y6M{1,15}D", "P1M"},
            {"{2026,2027}Y", "P1Y"},
            {"2026Y25W{1,3}K", "P1D"}
          ] do
        text = set <> "/" <> duration
        {:ok, values} = Tempo.to_interval(Tempo.from_iso8601!(set))
        starts = Enum.map(IntervalSet.members(values), &Interval.from/1)
        stepped = Enum.map(starts, &Tempo.shift(&1, Tempo.from_iso8601!(duration)))

        assert {:ok, spans} = Tempo.to_interval(Tempo.from_iso8601!(text))

        assert {text, Enum.map(IntervalSet.members(spans), &Interval.to/1)} ==
                 {text, stepped}

        assert {text, Enum.map(IntervalSet.members(spans), &Interval.from/1)} ==
                 {text, starts}
      end
    end

    test "has no one start with two ends" do
      assert {:error, %IntervalEndpointsError{} = error} =
               Tempo.to_interval(Tempo.from_iso8601!("2026Y6M{1,15}D/2026Y6M20D"))

      assert Exception.message(error) =~ "names several spans"
    end
  end
end
