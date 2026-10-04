defmodule Tempo.Matrix.Selections do
  @moduledoc """
  The selections of the matrix's corpus, and what each selects, worked out
  from its parts alone (see `plans/validated-core.md`).

  A selection (`L…N`) is a small language of its own within a value: the
  units it names, the way each is written (a number, a count from the end,
  a set, a range, a range that reaches the end), the period it is selected
  in and that period's calendar. `entries/0` writes one part in each of
  those ways in each of a list of periods, as `Tempo.Matrix.Shapes` does a
  value's units.

  `members/1` is what a selection selects: the days of its period that
  every part names, at the resolution of its finest part and in the order
  of time, counted with `Date`, `:calendar` and the calendar module's own
  functions. Nothing here calls `Tempo`, so a conversion that gives the
  same spans is evidence about the conversion.

  The readings it holds: a part is a condition on the days of the period,
  and a day is selected when every part names it; a count from the end is
  counted in the period its unit is in; a week is an ISO 8601 week, and a
  year's weeks keep the days they hold of the year before and after; a time
  of day is on each day the parts name. A day of the month in a year, with
  no month named, is not generated: its reading is undecided (`TODO.md`).

  """

  alias Calendrical.Gregorian
  alias Calendrical.Hebrew
  alias Calendrical.ISOWeek
  alias Tempo.Matrix.Reference

  @typedoc """
  One value of a part as it is written: a whole number, negative when it is
  counted from the end, or the two ends of a range.
  """
  @type written :: integer() | {integer(), integer()}

  @typedoc """
  A selection as data: the calendar it is read in, the period it is
  selected in as that period's units, and each part's values.
  """
  @type datum :: %{
          calendar: module(),
          period: keyword(integer()),
          parts: keyword([written()])
        }

  @unit_order [:month, :week, :day_of_year, :day, :day_of_week, :hour, :minute, :instance]

  @designators %{
    month: "M",
    week: "W",
    day_of_year: "O",
    day: "D",
    day_of_week: "K",
    hour: "H",
    minute: "M",
    instance: "I"
  }

  @clock_units [:hour, :minute]
  @day_units [:day_of_year, :day, :day_of_week]

  # The ways a part is written: one value, a count from the end, a set, a
  # range, a range that reaches the end, the first and the last, and a
  # value no period has.
  @written %{
    month: [
      one: [6],
      from_end: [-1],
      set: [6, 8],
      range: [{6, 8}],
      range_to_end: [{11, -1}],
      both_ends: [1, -1],
      absent: [14]
    ],
    week: [
      one: [25],
      from_end: [-1],
      set: [25, 27],
      range: [{25, 27}],
      range_to_end: [{52, -1}],
      both_ends: [1, -1],
      absent: [54]
    ],
    day_of_year: [
      one: [166],
      from_end: [-1],
      set: [100, 200],
      range: [{100, 102}],
      range_to_end: [{364, -1}],
      both_ends: [1, -1],
      absent: [367]
    ],
    day: [
      one: [15],
      from_end: [-1],
      set: [1, 15],
      range: [{1, 3}],
      range_to_end: [{28, -1}],
      both_ends: [1, -1],
      absent: [32]
    ],
    day_of_week: [
      one: [3],
      from_end: [-1],
      set: [1, 3],
      range: [{1, 3}],
      range_to_end: [{6, -1}],
      both_ends: [1, -1],
      absent: [8]
    ],
    hour: [
      one: [10],
      from_end: [-1],
      set: [9, 17],
      range: [{9, 11}],
      range_to_end: [{22, -1}],
      both_ends: [0, -1],
      absent: [25]
    ],
    minute: [
      one: [30],
      from_end: [-1],
      set: [0, 30],
      range: [{0, 2}],
      range_to_end: [{58, -1}],
      both_ends: [0, -1],
      absent: [61]
    ],
    instance: [
      one: [1],
      from_end: [-1],
      set: [1, 3],
      range: [{1, 2}],
      range_to_end: [{2, -1}],
      both_ends: [1, -1],
      absent: [60]
    ]
  }

  # A calendar, a period, the parts written one way throughout, and the
  # part written in each way.
  @scenarios [
    {Gregorian, [year: 2026], [], :month},
    {Gregorian, [year: 2026], [month: [6]], :day},
    {Gregorian, [year: 2026], [day: [15]], :month},
    {Gregorian, [year: 2026], [month: [6]], :day_of_week},
    {Gregorian, [year: 2026], [], :week},
    {Gregorian, [year: 2026], [week: [25]], :day_of_week},
    {Gregorian, [year: 2026], [day_of_week: [3]], :week},
    {Gregorian, [year: 2026], [], :day_of_year},
    {Gregorian, [year: 2026], [], :day_of_week},
    {Gregorian, [year: 2026], [day_of_week: [1]], :instance},
    {Gregorian, [year: 2024], [month: [2]], :day},
    {Gregorian, [year: 2026, month: 6], [], :day},
    {Gregorian, [year: 2026, month: 6], [], :day_of_week},
    {Gregorian, [year: 2026, month: 6], [day_of_week: [1]], :instance},
    {Gregorian, [year: 2026, month: 6], [day_of_week: [{1, 5}]], :instance},
    {Gregorian, [year: 2026, month: 6], [day_of_week: [1]], :hour},
    {Gregorian, [year: 2026, week: 25], [], :day_of_week},
    {Gregorian, [year: 2026, week: 53], [], :day_of_week},
    {Gregorian, [year: 2026, week: 1], [], :day_of_week},
    {Gregorian, [year: 2026, month: 6, day: 15], [], :hour},
    {Gregorian, [year: 2026, month: 6, day: 15], [hour: [10]], :minute},
    {Gregorian, [year: 2026, month: 6, day: 15, hour: 10], [], :minute},
    {Hebrew, [year: 5787], [], :month},
    {Hebrew, [year: 5788], [], :month},
    {Hebrew, [year: 5787], [month: [13]], :day},
    {Hebrew, [year: 5787, month: 6], [], :day},
    {ISOWeek, [year: 2026], [], :week},
    {ISOWeek, [year: 2026], [week: [25]], :day_of_week},
    {ISOWeek, [year: 2026], [], :day_of_week},
    {ISOWeek, [year: 2026], [day_of_week: [7]], :instance},
    {ISOWeek, [year: 2026, week: 25], [], :day_of_week}
  ]

  @doc """
  The generated selections, each a corpus entry that holds its datum.

  ### Returns

  * A list of `t:Tempo.Matrix.Corpus.entry/0`, each with a `:selection` key
    whose value is a `t:datum/0`.

  """
  @spec entries() :: [map()]
  def entries do
    for {calendar, period, fixed, varied} <- @scenarios,
        {_way, values} <- Map.fetch!(@written, varied) do
      datum = %{calendar: calendar, period: period, parts: in_order([{varied, values} | fixed])}

      %{
        class: :selection,
        level: :generated,
        text: text(datum),
        calendar: read_in(calendar),
        selection: datum
      }
    end
  end

  # A Gregorian text is read with no calendar given, as the corpus's others.
  defp read_in(Gregorian), do: nil
  defp read_in(calendar), do: calendar

  defp in_order(parts), do: Enum.sort_by(parts, fn {unit, _values} -> order(unit) end)

  defp order(unit), do: Enum.find_index(@unit_order, &(&1 == unit))

  ## The text

  @doc """
  A selection's text: its period, then its parts between `L` and `N`.

  ### Arguments

  * `datum` is a `t:datum/0`.

  ### Returns

  * The ISO 8601-2 text, `2026Y6ML{28..-1}DN`.

  """
  @spec text(datum()) :: String.t()
  def text(%{period: period, parts: parts}),
    do: period_text(period) <> "L" <> parts_text(parts) <> "N"

  @doc """
  The text of a selection's period alone, `2026Y6M`.

  ### Arguments

  * `datum` is a `t:datum/0`.

  ### Returns

  * The period's text.

  """
  @spec period_text(datum() | keyword(integer())) :: String.t()
  def period_text(%{period: period}), do: period_text(period)

  def period_text(period) do
    {date, clock} = Enum.split_with(period, fn {unit, _value} -> unit != :hour end)
    Enum.map_join(date, &period_unit/1) <> time_text(Enum.map(clock, &period_unit/1))
  end

  defp period_unit({:year, year}), do: "#{year}Y"
  defp period_unit({unit, value}), do: "#{value}#{@designators[unit]}"

  @doc """
  The text of a selection's parts alone, as a value with no year writes
  them: `-1M-1D`.

  ### Arguments

  * `parts` is a datum's parts.

  ### Returns

  * The parts' text.

  """
  @spec parts_text(keyword([written()])) :: String.t()
  def parts_text(parts) do
    {clock, rest} = Enum.split_with(parts, fn {unit, _values} -> unit in @clock_units end)
    {position, date} = Enum.split_with(rest, fn {unit, _values} -> unit == :instance end)

    Enum.map_join(date, &part_text/1) <>
      time_text(Enum.map(clock, &part_text/1)) <> Enum.map_join(position, &part_text/1)
  end

  defp time_text([]), do: ""
  defp time_text(units), do: "T" <> Enum.join(units)

  defp part_text({unit, [value]}) when is_integer(value), do: "#{value}#{@designators[unit]}"

  defp part_text({unit, values}),
    do: "{" <> Enum.map_join(values, ",", &written_text/1) <> "}#{@designators[unit]}"

  defp written_text({first, last}), do: "#{first}..#{last}"
  defp written_text(value), do: "#{value}"

  ## What it selects

  @doc """
  The spans a selection selects, in the order of time.

  ### Arguments

  * `datum` is a `t:datum/0`.

  ### Returns

  * A list of `t:Tempo.Matrix.Extent.t/0`, one for each occurrence.

  """
  @spec extents(datum()) :: [Tempo.Matrix.Extent.t()]
  def extents(datum) do
    for point <- members(datum) do
      {:ok, extent} = Reference.span(point)
      extent
    end
  end

  @doc """
  The occurrences a selection selects, in the order of time.

  ### Arguments

  * `datum` is a `t:datum/0`.

  ### Returns

  * A list of `t:Tempo.Matrix.Reference.point/0`.

  """
  @spec members(datum()) :: [Reference.point()]
  def members(%{calendar: calendar, period: period, parts: parts}) do
    period
    |> days(parts, calendar)
    |> Enum.filter(&named?(&1, parts, calendar))
    |> occurrences(parts, period, calendar)
    |> Enum.flat_map(&at_times(&1, parts, period))
    |> positions(parts[:instance])
  end

  # The days of the period, as proleptic Gregorian dates. A year whose weeks
  # are selected, and a year of a calendar of weeks, is its ISO 8601 weeks'
  # days.
  defp days([year: year], parts, calendar) do
    if calendar == ISOWeek or Keyword.has_key?(parts, :week),
      do: Date.range(week_start(year, 1), Date.add(week_start(year + 1, 1), -1)),
      else: Date.range(date(year, 1, 1, calendar), Date.add(date(year + 1, 1, 1, calendar), -1))
  end

  defp days([year: year, month: month], _parts, calendar) do
    first = date(year, month, 1, calendar)
    Date.range(first, Date.add(first, Reference.days_in_month(year, month, calendar) - 1))
  end

  defp days([year: year, week: week], _parts, _calendar) do
    first = week_start(year, week)
    Date.range(first, Date.add(first, 6))
  end

  defp days([{:year, year}, {:month, month}, {:day, day} | _hour], _parts, calendar),
    do: [date(year, month, day, calendar)]

  # ISO 8601-1 §4.2.2: weeks begin on Monday, and a year's first week is the
  # one that holds its 4 January.
  defp week_start(year, week) do
    year |> Date.new!(1, 4) |> Date.beginning_of_week(:monday) |> Date.add((week - 1) * 7)
  end

  defp date(year, month, day, Gregorian), do: Date.new!(year, month, day)

  defp date(year, month, day, calendar),
    do: year |> Date.new!(month, day, calendar) |> Date.convert!(Calendar.ISO)

  # A day is selected when every part that is a condition on a day names it.
  defp named?(%Date{} = day, parts, calendar) do
    Enum.all?(parts, fn {unit, written} -> day_named?(unit, written, day, calendar) end)
  end

  defp day_named?(:month, written, day, calendar) do
    %Date{year: year, month: month} = in_calendar(day, calendar)
    month in values(written, 1..Reference.months_in_year(year, calendar)//1)
  end

  defp day_named?(:week, written, %Date{year: year, month: month, day: day}, _calendar) do
    {week_year, week} = :calendar.iso_week_number({year, month, day})
    week in values(written, 1..weeks_in_year(week_year)//1)
  end

  defp day_named?(:day_of_year, written, day, calendar) do
    in_calendar = in_calendar(day, calendar)
    Date.day_of_year(in_calendar) in values(written, 1..days_in_year(in_calendar)//1)
  end

  defp day_named?(:day, written, day, calendar) do
    %Date{year: year, month: month, day: day_of_month} = in_calendar(day, calendar)
    day_of_month in values(written, 1..Reference.days_in_month(year, month, calendar)//1)
  end

  defp day_named?(:day_of_week, written, day, _calendar),
    do: Date.day_of_week(day) in values(written, 1..7//1)

  defp day_named?(_clock_or_position, _written, _day, _calendar), do: true

  defp in_calendar(%Date{} = day, Gregorian), do: day
  defp in_calendar(%Date{} = day, calendar), do: Date.convert!(day, calendar)

  # 28 December is always in its year's last ISO 8601 week.
  defp weeks_in_year(year), do: {year, 12, 28} |> :calendar.iso_week_number() |> elem(1)

  defp days_in_year(%Date{} = day),
    do: Date.diff(%{day | year: day.year + 1, month: 1, day: 1}, %{day | month: 1, day: 1})

  # The values a part names among those its unit takes: a negative number is
  # counted back from the last, and a range is every value from one of its
  # ends to the other.
  defp values(written, %Range{} = valid) do
    written
    |> Enum.flat_map(&named(&1, valid))
    |> Enum.filter(&(&1 in valid))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp named({first, last}, valid),
    do: Enum.filter(valid, &(&1 >= counted(first, valid) and &1 <= counted(last, valid)))

  defp named(value, valid), do: [counted(value, valid)]

  defp counted(value, %Range{last: last}) when value < 0, do: last + 1 + value
  defp counted(value, _valid), do: value

  # The occurrences are the days, or what holds them where no part names a
  # day: the weeks, the months, or the period's own first day for a time of
  # day alone.
  defp occurrences(days, parts, period, calendar) do
    cond do
      Enum.any?(@day_units, &Keyword.has_key?(parts, &1)) ->
        Enum.map(days, &day_point/1)

      Keyword.has_key?(parts, :week) ->
        days |> Enum.map(&week_point/1) |> Enum.uniq()

      Keyword.has_key?(parts, :month) ->
        days |> Enum.map(&month_point(&1, calendar)) |> Enum.uniq()

      true ->
        [period |> days(parts, calendar) |> Enum.at(0) |> day_point()]
    end
  end

  defp day_point(%Date{year: year, month: month, day: day}),
    do: point([year: year, month: month, day: day], Gregorian)

  defp week_point(%Date{year: year, month: month, day: day}) do
    {week_year, week} = :calendar.iso_week_number({year, month, day})
    point([year: week_year, week: week], Gregorian)
  end

  defp month_point(day, calendar) do
    %Date{year: year, month: month} = in_calendar(day, calendar)
    point([year: year, month: month], calendar)
  end

  defp point(date, calendar),
    do: %{date: date, time: [], fraction: nil, zone: nil, calendar: calendar}

  # An occurrence at each time of day the parts name. An hour the parts do
  # not name is the period's own.
  defp at_times(occurrence, parts, period) do
    case {hours(parts[:hour], period[:hour]), parts[:minute]} do
      {nil, nil} ->
        [occurrence]

      {hours, nil} ->
        for hour <- hours, do: %{occurrence | time: [hour: hour]}

      {hours, minutes} ->
        for hour <- hours, minute <- values(minutes, 0..59//1), do: at(occurrence, hour, minute)
    end
  end

  defp at(occurrence, hour, minute), do: %{occurrence | time: [hour: hour, minute: minute]}

  defp hours(nil, nil), do: nil
  defp hours(nil, hour), do: [hour]
  defp hours(written, _period_hour), do: values(written, 0..23//1)

  defp positions(occurrences, nil), do: occurrences

  defp positions(occurrences, written) do
    picked = values(written, 1..length(occurrences)//1)

    for {occurrence, position} <- Enum.with_index(occurrences, 1),
        position in picked,
        do: occurrence
  end
end
