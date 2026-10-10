defmodule Tempo.UnitValues do
  @moduledoc """
  The values a unit takes, and the values a written value names among them.

  A date or a time is counted in units, and each unit takes a run of values that the units before it and the calendar decide: the months of a year, the days of a month, the hours of a day. A value is written against that run as a number, as a count from its end (`-1`, the last), as a range from one of its values to another (`{28..-1}`), or as several of these.

  This module is the one place where either is worked out, so that there is one place to verify. It is also where a calendar is asked how a year begins: in a year that begins on another day than the first of its first month, as the year a composite calendar changes its new year's day in does, the year's and a month's first date are the calendar's to say (`year_begins_with_first_month?/2`, `first_date/2`). `in_period/3` gives the run, and `in_any_year/3` the run a unit takes with no year to count it in; `first/3`, `last/3`, `following/4`, `preceding/4` and `at_or_before/4` are what a step asks of it; `named/2` lists the values a written value names in it, and `resolve/2` reads a written value against it in the shape it is written in; `from_end/2` is the count from the end that all rest on. How many values a unit takes is always asked of the calendar, which is Calendrical's to answer: nothing here is calendar arithmetic.

  A selection's resolver (`Tempo.RRule.Selection`), `Tempo.select/2`, the walk, the reading of a value and of its masks, a step from a value and `Tempo.explain/1` count through it. What stays with the calendar's own counts is the arithmetic of a group and of a fraction (the nth day of a group of months, half of a year), which counts a period's units.

  """

  alias Calendrical.Base.Common
  alias Calendrical.Kday
  alias Tempo.Calendars
  alias Tempo.Compare
  alias Tempo.Iso8601.Unit
  alias Tempo.Mask

  @typedoc """
  A value as it is written: a whole number, counted from the end when it is negative, a range, or a list of either.
  """
  @type written :: integer() | Range.t() | [integer() | Range.t()]

  @typedoc """
  The values a unit takes: a range counted up by one, or, where the calendar lists values that do not run on from one another, the ranges of them in order. September 1752 in `Calendrical.Reform.England` has the days `[1..2, 14..30]`.
  """
  @type values :: Range.t() | [Range.t(), ...]

  @doc """
  Returns the values a unit takes in the period the units before it name.

  ### Arguments

  * `unit` is the unit counted: `:month`, `:week`, `:calendar_week`, `:day_of_year`, `:day`, `:day_of_week`, `:hour`, `:minute` or `:second`.

  * `context` is a keyword list of the units before it, as a value's `:time` holds them. Only the units that decide the answer are read: the year for a month, a week or a day of the year, and the year and the month for a day.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, values}`, a `t:values/0`: the values from the first to the last, counted up by one, as a range. A composite calendar is asked which days a month has and which months a year has, so a month it cut short starts or ends where it does, and one with days missing in it is the ranges of the days it has.

  * `{:error, :unanchored}` when the answer depends on a unit the context does not hold as one whole number: the days of a month with no year, which `in_any_year/3` answers.

  * `{:error, :no_period}` when the units before it name a period the calendar does not have: the days of a thirteenth month in a year of twelve.

  * `{:error, :uncounted}` for a unit that takes no run of values, such as a year.

  ### Examples

      iex> Tempo.UnitValues.in_period(:day, [year: 2026, month: 2], Calendrical.Gregorian)
      {:ok, 1..28}

      iex> Tempo.UnitValues.in_period(:month, [year: 5787], Calendrical.Hebrew)
      {:ok, 1..13}

      iex> Tempo.UnitValues.in_period(:week, [year: 2026], Calendrical.Gregorian)
      {:ok, 1..53}

      iex> Tempo.UnitValues.in_period(:hour, [], Calendrical.Gregorian)
      {:ok, 0..23}

      iex> Tempo.UnitValues.in_period(:day, [month: 2], Calendrical.Gregorian)
      {:error, :unanchored}

      iex> Tempo.UnitValues.in_period(:day, [year: 2026, month: 13], Calendrical.Gregorian)
      {:error, :no_period}

      iex> Tempo.UnitValues.in_period(:day, [year: 1752, month: 9], Calendrical.Reform.England)
      {:ok, [1..2, 14..30]}

      iex> Tempo.UnitValues.in_period(:month, [year: 1751], Calendrical.Reform.England)
      {:ok, 3..12}

  """
  @spec in_period(atom(), keyword(), module()) ::
          {:ok, values()} | {:error, :unanchored | :uncounted | :no_period}
  def in_period(unit, context, calendar) do
    case listed(unit, context, calendar) do
      :counted -> counted_in_period(unit, context, calendar)
      listed -> listed
    end
  end

  defp counted_in_period(unit, context, calendar) do
    with {:ok, last} <- last_in_period(unit, context, calendar) do
      {:ok, first_value(unit)..last//1}
    end
  end

  # The values a calendar lists for a unit, where they are not the count from
  # the unit's first value that every other calendar's are. A composite
  # calendar changes from one calendar to another on a day, and the month and
  # the year that day is in have the days and the months that are left: no
  # 3 to 13 September 1752 in `Calendrical.Reform.England`, and no January or
  # February 1751. So its days are those that are dates (`valid_date?/3`),
  # and its months those that have days.
  defp listed(:day, context, calendar) do
    with true <- composite?(calendar),
         year when is_integer(year) <- whole(context, :year),
         month when is_integer(month) <- whole(context, :month) do
      listed_days(year, month, calendar)
    else
      _counted -> :counted
    end
  end

  defp listed(:month, context, calendar) do
    with true <- composite?(calendar),
         year when is_integer(year) <- whole(context, :year) do
      listed_months(year, calendar)
    else
      _counted -> :counted
    end
  end

  # The traditional months of a year are those its calendar numbers, the
  # intercalary one apart, and are counted in a year alone.
  defp listed(:traditional_month, context, calendar) do
    case whole(context, :year) do
      nil ->
        {:error, :unanchored}

      year ->
        year |> traditional_months(calendar, :numbered) |> Enum.map(&elem(&1, 0)) |> as_values()
    end
  end

  defp listed(_unit, _context, _calendar), do: :counted

  defp listed_days(year, month, calendar) do
    if month_of_year?(month, year, calendar) do
      1..last_day_number(year, month, calendar)//1
      |> Enum.filter(&calendar.valid_date?(year, month, &1))
      |> as_values()
    else
      {:error, :no_period}
    end
  end

  # The greatest number a day of the month can have: how many days it has,
  # or the day its last date is where days are missing before it.
  defp last_day_number(year, month, calendar) do
    count = last_month_day(calendar.days_in_month(year, month))

    case month_range(year, month, calendar) do
      {:ok, %Date.Range{last: %Date{day: day}}} -> max(count, day)
      {:error, :no_period} -> count
    end
  end

  defp last_month_day(count) when is_integer(count), do: count
  defp last_month_day(_cannot_say), do: 0

  defp listed_months(year, calendar) do
    1..last_month(year, calendar)//1
    |> Enum.filter(&(last_month_day(calendar.days_in_month(year, &1)) > 0))
    |> as_values()
  end

  # Whole numbers in order, as the values they are: one range where they run
  # on from one another, and the ranges of them where they do not.
  @doc false
  # Whole numbers in order as the values they are: the range they run
  # through, or the ranges where some are missing between them. None is no
  # period to hold a value.
  @spec as_values([integer()]) :: {:ok, values()} | {:error, :no_period}
  def as_values([]), do: {:error, :no_period}

  def as_values([first | rest]) do
    case runs_of_numbers(rest, first, first) do
      [range] -> {:ok, range}
      ranges -> {:ok, ranges}
    end
  end

  @doc false
  # The traditional months of a year of one kind, each with its place in the
  # year: those the calendar numbers (`:numbered`), or the intercalary months
  # (`:leap`), each by the number of the month it follows. The year's months
  # as they are named, in order, are Calendrical's (`traditional_months/2`),
  # and the place of a name among them is the month a date of the year
  # carries: the Hebrew year 5787 numbers twelve months, the sixth of them in
  # the seventh place, and has one intercalary month, after the fifth.
  @spec traditional_months(integer(), module(), :numbered | :leap) ::
          [{number :: integer(), place :: pos_integer()}]
  def traditional_months(year, calendar, kind) when is_integer(year) do
    year
    |> calendar.traditional_months()
    |> Enum.with_index(1)
    |> Enum.flat_map(&numbered_as(&1, kind))
  end

  defp numbered_as({number, place}, :numbered) when is_integer(number), do: [{number, place}]
  defp numbered_as({{number, :leap}, place}, :leap), do: [{number, place}]
  defp numbered_as(_another_kind, _kind), do: []

  defp runs_of_numbers([number | rest], first, last) when number == last + 1,
    do: runs_of_numbers(rest, first, number)

  defp runs_of_numbers([number | rest], first, last),
    do: [first..last//1 | runs_of_numbers(rest, number, number)]

  defp runs_of_numbers([], first, last), do: [first..last//1]

  # Whether a calendar is a composite of others, which Calendrical says, and
  # which is asked of each calendar once and kept: every count of a month's
  # days asks it.
  @composite_key {__MODULE__, :composite}

  defp composite?(calendar) do
    case :persistent_term.get({@composite_key, calendar}, nil) do
      nil ->
        composite? = Common.composite?(calendar)
        :persistent_term.put({@composite_key, calendar}, composite?)
        composite?

      composite? ->
        composite?
    end
  end

  @doc false
  # Whether a date of a year is stepped by its calendar, and not by counting
  # on through the values of its units: in a year that does not begin with
  # its first month, whose first days are no first, and in a composite
  # calendar, whose years and months change where its calendars do.
  #
  # `year` is a whole number, or what a time list holds for its year where
  # that is no one number (a set, a mask, nothing): `years_begin_with_first_month?/2`
  # says which years are then asked.
  @spec stepped_by_calendar?(term(), module()) :: boolean()
  def stepped_by_calendar?(year, calendar) when is_integer(year),
    do: composite?(calendar) or not year_begins_with_first_month?(year, calendar)

  def stepped_by_calendar?(years, calendar),
    do: composite?(calendar) or not years_begin_with_first_month?(years, calendar)

  ## Years

  # A calendar counts its years on through 0 unless it has no such year: the
  # Julian calendar's year before 1 is -1, as Calendrical has it, and a date
  # of its year 0 is no date. A year is a calendar's where 1 January, or the
  # first day of its first month, of that year is a date of it.

  @doc false
  # Whether a calendar has the year. Every year but 0 is taken to be one.
  @spec year?(term(), module()) :: boolean()
  def year?(0, calendar), do: Calendars.effective(calendar).valid_date?(0, 1, 1)

  def year?(_year, _calendar), do: true

  @doc false
  # The year so many years on from a year, back where the count is
  # negative, as the calendar counts its years. The count across a year the
  # calendar lacks is Calendrical's (`plus/6`): two years on from the Julian
  # calendar's -1 is 2.
  @spec years_on(integer(), integer(), module()) :: integer()
  def years_on(year, count, calendar) when is_integer(year) and is_integer(count) do
    if one_side_of_zero?(year, year + count) or year?(0, calendar),
      do: year + count,
      else: counted_by_calendar(year, count, calendar)
  end

  @doc false
  # How many years on from one year another is, the count `years_on/3` takes
  # from the first to the second.
  @spec years_between(integer(), integer(), module()) :: integer()
  def years_between(from, to, calendar) when is_integer(from) and is_integer(to) do
    cond do
      one_side_of_zero?(from, to) or year?(0, calendar) -> to - from
      to > from -> to - from - 1
      true -> to - from + 1
    end
  end

  defp one_side_of_zero?(year, other), do: (year > 0 and other > 0) or (year < 0 and other < 0)

  # A year the calendar lacks (the Julian calendar's 0, should one be held)
  # has no date to count from, and is counted on as a number.
  defp counted_by_calendar(year, count, calendar) do
    with true <- calendar.valid_date?(year, 1, 1),
         {on, _month, _day} <- calendar.plus(year, 1, 1, :years, count, []) do
      on
    else
      _as_a_number -> year + count
    end
  end

  ## Values that do not run on from one another

  # The ranges a unit's values are, the first and the last of them, each of
  # them in order, and whether a number is one.
  defp ranges(%Range{} = range), do: [range]
  defp ranges(ranges) when is_list(ranges), do: ranges

  defp first_of(%Range{first: first}), do: first
  defp first_of([%Range{first: first} | _rest]), do: first

  defp last_of(%Range{last: last}), do: last
  defp last_of(ranges) when is_list(ranges), do: ranges |> List.last() |> last_of()

  defp numbers(values), do: values |> ranges() |> Enum.flat_map(&Enum.to_list/1)

  defp taken?(value, values), do: Enum.any?(ranges(values), &(value in &1))

  # The units that take a run of values.
  @counted [
    :month,
    :week,
    :calendar_week,
    :day_of_year,
    :day,
    :day_of_week,
    :hour,
    :minute,
    :second
  ]

  # The first value a unit takes: the first month, week or day, and hour,
  # minute or second zero.
  defp first_value(unit) when unit in [:hour, :minute, :second], do: 0
  defp first_value(_unit), do: 1

  # The last value a unit takes in the period the units before it name. A
  # step asks it of the value it steps from, so no range is built here.
  defp last_in_period(:month, context, calendar) do
    case whole(context, :year) do
      nil -> {:error, :unanchored}
      year -> counted(calendar.months_in_year(year))
    end
  end

  defp last_in_period(:week, context, calendar) do
    case whole(context, :year) do
      nil -> {:error, :unanchored}
      year -> counted(iso_weeks_in_year(year, calendar))
    end
  end

  defp last_in_period(:calendar_week, context, calendar) do
    case whole(context, :year) do
      nil -> {:error, :unanchored}
      year -> counted(calendar_weeks_in_year(year, calendar))
    end
  end

  defp last_in_period(:day_of_year, context, calendar) do
    case whole(context, :year) do
      nil -> {:error, :unanchored}
      year -> counted(calendar.days_in_year(year))
    end
  end

  defp last_in_period(:day, context, calendar) do
    year = whole(context, :year)
    month = whole(context, :month)

    cond do
      is_nil(year) or is_nil(month) -> {:error, :unanchored}
      month_of_year?(month, year, calendar) -> counted(calendar.days_in_month(year, month))
      true -> {:error, :no_period}
    end
  end

  defp last_in_period(unit, _context, calendar) do
    case Unit.value_range(unit, calendar) do
      {:ok, %Range{last: last}} -> {:ok, last}
      :unknown -> {:error, :uncounted}
    end
  end

  # A unit of the context that is one whole number. A time list is not
  # always a keyword list (a group of a set is a triple), and a unit that is
  # a set, a range or a mask fixes no one period to count in.
  defp whole(context, unit) do
    case List.keyfind(context, unit, 0) do
      {^unit, value} when is_integer(value) -> value
      _absent_or_several -> nil
    end
  end

  # Whether a year has the month, which a calendar is asked before it is
  # asked for the month's days: for a month its year does not have one
  # calendar answers as if the months went round, one with no days, and one
  # not at all. A date of a calendar of weeks holds its week where a month is
  # held, and has the weeks its year has. A month every year has needs no
  # count of the year's months, which an astronomical calendar works out from
  # its new moons.
  defp month_of_year?(month, year, calendar) when month >= 1 do
    if Tempo.week_based_calendar?(calendar),
      do: month <= calendar_weeks_in_year(year, calendar),
      else: month <= fewest_months(calendar) or month <= last_month(year, calendar)
  end

  defp month_of_year?(_month, _year, _calendar), do: false

  defp fewest_months(calendar) do
    case last_in_any_year(:month, [], calendar) do
      {:ok, fewest, _most} -> fewest
      {:error, _cannot_say} -> 0
    end
  end

  defp last_month(year, calendar) do
    case calendar.months_in_year(year) do
      months when is_integer(months) -> months
      _cannot_say -> 0
    end
  end

  # What a calendar answers for a year or a month of one: a count, or that
  # it cannot say.
  defp counted(last) when is_integer(last), do: {:ok, last}
  defp counted(_not_a_count), do: {:error, :unanchored}

  @doc """
  Returns the values a unit takes with no year to count them in: those it takes in every year, and those it takes in the year that has the most.

  A month, or a day of a month, written with no year (`6M`, `2M29D`) is that month or day of any year, and how many there are may depend on the year: a Gregorian February has 28 days or 29, a Hebrew year 12 months or 13. The calendar answers without a year (`days_in_month/1` and `months_in_year/0`), and this is the one place it is asked, so that the reading of a value, its walk, its span and a step from it all take one answer.

  ### Arguments

  * `unit` is the unit counted, as for `in_period/3`.

  * `context` is a keyword list of the units before it. Only the month is read, for a day; a year it holds is not.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, every, longest}`, two ranges counted up by one from the unit's first value: the values every year has, and the values of the year that has the most. They are one range where the count does not depend on the year.

  * `{:error, :unanchored}` when the calendar cannot say without a year: a day with no month, a week or a day of the year, and a month or a day in a calendar that does not answer for it.

  * `{:error, :uncounted}` for a unit that takes no run of values, such as a year.

  ### Examples

      iex> Tempo.UnitValues.in_any_year(:day, [month: 2], Calendrical.Gregorian)
      {:ok, 1..28, 1..29}

      iex> Tempo.UnitValues.in_any_year(:day, [month: 6], Calendrical.Gregorian)
      {:ok, 1..30, 1..30}

      iex> Tempo.UnitValues.in_any_year(:month, [], Calendrical.Hebrew)
      {:ok, 1..12, 1..13}

      iex> Tempo.UnitValues.in_any_year(:hour, [], Calendrical.Gregorian)
      {:ok, 0..23, 0..23}

      iex> Tempo.UnitValues.in_any_year(:week, [], Calendrical.Gregorian)
      {:error, :unanchored}

  """
  @spec in_any_year(atom(), keyword(), module()) ::
          {:ok, every :: Range.t(), longest :: Range.t()} | {:error, :unanchored | :uncounted}
  def in_any_year(unit, context, calendar) do
    with {:ok, fewest, most} <- last_in_any_year(unit, context, calendar) do
      first = first_value(unit)
      {:ok, first..fewest//1, first..most//1}
    end
  end

  # The last value a unit takes in every year, and in the year that has the
  # most: what a calendar answers with no year, read in this one place. A
  # step asks it of the value it steps from, so no range is built here.
  defp last_in_any_year(:month, _context, calendar),
    do: counted_in_any_year(calendar.months_in_year())

  defp last_in_any_year(:day, context, calendar) do
    month = whole(context, :month)

    if is_integer(month) and month > 0,
      do: counted_in_any_year(calendar.days_in_month(month)),
      else: {:error, :unanchored}
  end

  defp last_in_any_year(unit, _context, _calendar)
       when unit in [:week, :calendar_week, :day_of_year],
       do: {:error, :unanchored}

  defp last_in_any_year(unit, context, calendar) do
    with {:ok, last} <- last_in_period(unit, context, calendar) do
      {:ok, last, last}
    end
  end

  @doc """
  The day of its month a date names.

  A calendar that counts its months from the day its year begins numbers a day by its place in the month it counts: the first day of a `Calendrical.Julian.March25` year is day 1 of month 1, and is named 25 March. The calendar is asked (`cardinal_day/3`); one that does not answer names a day by its number.

  ### Arguments

  * `year`, `month` and `day` are a date's fields.

  * `calendar` is a calendar module.

  ### Returns

  * The day the date is named by.

  ### Examples

      iex> Tempo.UnitValues.named_day(1750, 1, 1, Calendrical.Julian.March25)
      25

      iex> Tempo.UnitValues.named_day(2026, 6, 15, Calendrical.Gregorian)
      15

  """
  @spec named_day(integer(), pos_integer(), pos_integer(), module()) :: pos_integer()
  def named_day(year, month, day, calendar), do: calendar.cardinal_day(year, month, day)

  @doc """
  The year, month and day a date is named by.

  A calendar that counts its months from the day its year begins names a date otherwise than by its fields: the first day of a `Calendrical.Julian.March25` year, month 1 and day 1, is 25 March. The calendar is asked for the month the date is of (`month_of_year/3`, named by `cardinal_month/1`) and for its day (`cardinal_day/3`).

  ### Arguments

  * `year`, `month` and `day` are a date's fields.

  * `calendar` is a calendar module.

  ### Returns

  * `{year, month, day}`, the month and the day as they are named.

  ### Examples

      iex> Tempo.UnitValues.named_date(1750, 1, 1, Calendrical.Julian.March25)
      {1750, 3, 25}

      iex> Tempo.UnitValues.named_date(1750, 13, 24, Calendrical.Julian.March25)
      {1750, 3, 24}

      iex> Tempo.UnitValues.named_date(2026, 6, 15, Calendrical.Gregorian)
      {2026, 6, 15}

  """
  @spec named_date(integer(), pos_integer(), pos_integer(), module()) ::
          {integer(), pos_integer(), pos_integer()}
  def named_date(year, month, day, calendar),
    do: {year, month_named(year, month, day, calendar), named_day(year, month, day, calendar)}

  @doc """
  Whether a month is the only one of its year with its name.

  A year that begins within a month holds that month twice, as its first days and as its last: months 1 and 13 of a `Calendrical.Julian.March25` year are both March. Calendrical is asked for the spans of the named month (`Calendrical.named_month/3`).

  ### Arguments

  * `year` and `month` are a month as its calendar counts it.

  * `calendar` is a calendar module.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Tempo.UnitValues.month_named_once?(1750, 1, Calendrical.Julian.March25)
      false

      iex> Tempo.UnitValues.month_named_once?(1750, 2, Calendrical.Julian.March25)
      true

      iex> Tempo.UnitValues.month_named_once?(2026, 6, Calendrical.Gregorian)
      true

  """
  @spec month_named_once?(integer(), pos_integer(), module()) :: boolean()
  def month_named_once?(year, month, calendar) when is_integer(year) and is_integer(month) do
    case calendar.month(year, month) do
      %Date.Range{first: first} ->
        named = month_named(first.year, first.month, first.day, calendar)
        match?([_one_span], calendar.named_month(year, named))

      _no_such_month ->
        true
    end
  end

  def month_named_once?(_year, _month, _calendar), do: true

  @doc """
  Whether a year's first month and its last have different names.

  They have in a year that begins with a whole month, which its months then name from first to last. A year that begins within a month starts and ends in the month of one name (25 March to the next 24 March).

  ### Arguments

  * `year` is a year.

  * `calendar` is a calendar module.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Tempo.UnitValues.year_named_by_its_months?(2026, Calendrical.Gregorian)
      true

      iex> Tempo.UnitValues.year_named_by_its_months?(1750, Calendrical.Julian.Sept1)
      true

      iex> Tempo.UnitValues.year_named_by_its_months?(1750, Calendrical.Julian.March25)
      false

  """
  @spec year_named_by_its_months?(integer(), module()) :: boolean()
  def year_named_by_its_months?(year, calendar) when is_integer(year) do
    case calendar.year(year) do
      %Date.Range{first: first, last: last} ->
        month_named(first.year, first.month, first.day, calendar) !=
          month_named(last.year, last.month, last.day, calendar)

      _no_such_year ->
        true
    end
  end

  def year_named_by_its_months?(_year, _calendar), do: true

  # The month a date names, as its calendar numbers the months of a year by
  # name: the month its date is of (`month_of_year/3`), named once
  # (`cardinal_month/1`). A leap month is named by the calendar's own words,
  # and is its number here.
  defp month_named(year, month, day, calendar) do
    case calendar.month_of_year(year, month, day) do
      named when is_integer(named) -> calendar.cardinal_month(named)
      _named_by_its_number -> month
    end
  end

  # What a calendar answers with no year: a count, the counts its years run
  # over (a range or a list of them), or that it cannot say.
  defp counted_in_any_year(count) when is_integer(count) and count > 0,
    do: {:ok, count, count}

  defp counted_in_any_year({:ambiguous, %Range{first: first, last: last}})
       when is_integer(first) and is_integer(last) and first > 0 and last > 0,
       do: {:ok, min(first, last), max(first, last)}

  defp counted_in_any_year({:ambiguous, [_ | _] = counts}) do
    if Enum.all?(counts, &(is_integer(&1) and &1 > 0)),
      do: {:ok, Enum.min(counts), Enum.max(counts)},
      else: {:error, :unanchored}
  end

  defp counted_in_any_year(_cannot_say), do: {:error, :unanchored}

  @doc """
  Returns the first value a unit takes after the units before it.

  A step that carries puts the unit it leaves at its first value: the day after the last of a month is the first day of the next.

  ### Arguments

  * `unit` is the unit counted, as for `in_period/3`.

  * `context` is a keyword list of the units before it, as a value's `:time` holds them.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, first}`: the first month, week or day, and hour, minute or second zero.

  * `{:error, :uncounted}` for a unit that takes no run of values, such as a year.

  ### Examples

      iex> Tempo.UnitValues.first(:day, [year: 2026, month: 6], Calendrical.Gregorian)
      {:ok, 1}

      iex> Tempo.UnitValues.first(:hour, [], Calendrical.Gregorian)
      {:ok, 0}

  """
  @spec first(atom(), keyword(), module()) :: {:ok, integer()} | {:error, :uncounted}
  def first(unit, context, calendar) when unit in @counted do
    case listed(unit, context, calendar) do
      {:ok, values} -> {:ok, first_of(values)}
      _counted_from_the_first -> {:ok, first_value(unit)}
    end
  end

  def first(_unit, _context, _calendar), do: {:error, :uncounted}

  @doc """
  Returns the last value a unit takes after the units before it.

  A step back that borrows puts the unit it leaves at its last value: the day before the first of a month is the last day of the month before. With no year in the context the answer is given where every year has the same (`in_any_year/3`).

  The units before it are taken to name a period the calendar has, as those of a value that has been read do; `in_period/3` is the function that checks.

  ### Arguments

  * `unit` is the unit counted, as for `in_period/3`.

  * `context` is a keyword list of the units before it, as a value's `:time` holds them.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, last}`.

  * `{:error, :unanchored}` when the last value depends on a year the context does not hold.

  * `{:error, :uncounted}` or `{:error, :no_period}`, as `in_period/3` returns them.

  ### Examples

      iex> Tempo.UnitValues.last(:day, [year: 2028, month: 2], Calendrical.Gregorian)
      {:ok, 29}

      iex> Tempo.UnitValues.last(:day, [month: 6], Calendrical.Gregorian)
      {:ok, 30}

      iex> Tempo.UnitValues.last(:day, [month: 2], Calendrical.Gregorian)
      {:error, :unanchored}

  """
  @spec last(atom(), keyword(), module()) ::
          {:ok, integer()} | {:error, :unanchored | :uncounted | :no_period}
  def last(unit, context, calendar) do
    case listed(unit, context, calendar) do
      {:ok, values} -> {:ok, last_of(values)}
      {:error, _no_period} = error -> error
      :counted -> counted_last(unit, context, calendar)
    end
  end

  defp counted_last(unit, context, calendar) do
    case last_in_any_year(unit, context, calendar) do
      {:ok, last, last} -> {:ok, last}
      _by_the_year_or_cannot_say -> last_in_period(unit, context, calendar)
    end
  end

  @doc """
  Returns the value that follows a value among those a unit takes after the units before it.

  A step asks it of the value it steps from: the day after the 15th is the 16th, and the last day of a month is followed by none, so the step carries into the month. Where the answer is the same in every year the year is not asked for, and with no year in the context that is the only answer there is: the day after 27 February is the 28th and the 29th is the last of any February that has one, where what follows the 28th depends on the year.

  The units before it are taken to name a period the calendar has, as those of a value that has been read do; `in_period/3` is the function that checks.

  ### Arguments

  * `unit` is the unit counted, as for `in_period/3`.

  * `value` is the whole number the step counts from, or `:any` for an unspecified unit, which counts as its last value.

  * `context` is a keyword list of the units before it, as a value's `:time` holds them.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, next}`, the value after `value`.

  * `:last` when `value` is the last the unit takes there.

  * `{:error, :unanchored}` when what follows depends on a year the context does not hold.

  * `{:error, :uncounted}` or `{:error, :no_period}`, as `in_period/3` returns them.

  ### Examples

      iex> Tempo.UnitValues.following(:day, 15, [year: 2026, month: 6], Calendrical.Gregorian)
      {:ok, 16}

      iex> Tempo.UnitValues.following(:day, 30, [year: 2026, month: 6], Calendrical.Gregorian)
      :last

      iex> Tempo.UnitValues.following(:day, 28, [year: 2028, month: 2], Calendrical.Gregorian)
      {:ok, 29}

      iex> Tempo.UnitValues.following(:day, 28, [month: 2], Calendrical.Gregorian)
      {:error, :unanchored}

      iex> Tempo.UnitValues.following(:month, 12, [year: 5787], Calendrical.Hebrew)
      {:ok, 13}

  """
  @spec following(atom(), integer() | :any, keyword(), module()) ::
          {:ok, integer()} | :last | {:error, :unanchored | :uncounted | :no_period}
  def following(unit, value, context, calendar) do
    case listed(unit, context, calendar) do
      {:ok, values} -> following_among(values, value)
      {:error, _no_period} = error -> error
      :counted -> counted_following(unit, value, context, calendar)
    end
  end

  # The value after a value among those a calendar lists: the next it has,
  # which is not the next number where days are missing between them.
  defp following_among(_values, :any), do: :last

  defp following_among(values, value) do
    case Enum.find(numbers(values), &(&1 > value)) do
      nil -> :last
      next -> {:ok, next}
    end
  end

  defp counted_following(unit, value, context, calendar) do
    case last_in_any_year(unit, context, calendar) do
      {:ok, fewest, _most} when is_integer(value) and value < fewest -> {:ok, value + 1}
      {:ok, _fewest, most} when value == :any or value >= most -> :last
      _by_the_year_or_cannot_say -> following_in_period(unit, value, context, calendar)
    end
  end

  defp following_in_period(unit, value, context, calendar) do
    case last_in_period(unit, context, calendar) do
      {:ok, last} when is_integer(value) and value < last -> {:ok, value + 1}
      {:ok, _last} -> :last
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Returns the last value a unit takes, after the units before it, that is not after a value.

  A step of months may leave a day its new month does not have: "31 February" is the last day of February. With no year in the context the answer is given where it is the same in every year: the 15th of any February is the 15th, and whether a 29th is itself or the 28th depends on the year.

  The units before it are taken to name a period the calendar has, as those of a value that has been read do; `in_period/3` is the function that checks.

  ### Arguments

  * `unit` is the unit counted, as for `in_period/3`.

  * `value` is a whole number of the unit, which may be past the last the unit takes.

  * `context` is a keyword list of the units before it, as a value's `:time` holds them.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, value}` where the unit takes the value, and `{:ok, last}` where the value is past the last it takes.

  * `{:error, :unanchored}` when the answer depends on a year the context does not hold.

  * `{:error, :uncounted}` or `{:error, :no_period}`, as `in_period/3` returns them.

  ### Examples

      iex> Tempo.UnitValues.at_or_before(:day, 31, [year: 2026, month: 2], Calendrical.Gregorian)
      {:ok, 28}

      iex> Tempo.UnitValues.at_or_before(:day, 15, [month: 2], Calendrical.Gregorian)
      {:ok, 15}

      iex> Tempo.UnitValues.at_or_before(:day, 31, [month: 6], Calendrical.Gregorian)
      {:ok, 30}

      iex> Tempo.UnitValues.at_or_before(:day, 29, [month: 2], Calendrical.Gregorian)
      {:error, :unanchored}

  """
  @spec at_or_before(atom(), integer(), keyword(), module()) ::
          {:ok, integer()} | {:error, :unanchored | :uncounted | :no_period}
  def at_or_before(unit, value, context, calendar) when is_integer(value) do
    case listed(unit, context, calendar) do
      {:ok, values} -> {:ok, at_or_before_among(values, value)}
      {:error, _no_period} = error -> error
      :counted -> counted_at_or_before(unit, value, context, calendar)
    end
  end

  # The last of the values a calendar lists that is not after a value, and
  # the first of them where every one is.
  defp at_or_before_among(values, value) do
    values
    |> numbers()
    |> Enum.take_while(&(&1 <= value))
    |> List.last(first_of(values))
  end

  defp counted_at_or_before(unit, value, context, calendar) do
    case last_in_any_year(unit, context, calendar) do
      {:ok, fewest, _most} when value <= fewest -> {:ok, value}
      {:ok, last, last} -> {:ok, last}
      _by_the_year_or_cannot_say -> at_or_before_in_period(unit, value, context, calendar)
    end
  end

  defp at_or_before_in_period(unit, value, context, calendar) do
    with {:ok, last} <- last_in_period(unit, context, calendar) do
      {:ok, min(value, last)}
    end
  end

  @doc """
  Returns the value that comes before a value among those a unit takes after the units before it.

  A step back asks it of the value it steps from: the day before the 15th is the 14th, and the first day of a month has none before it, so the step borrows from the month.

  ### Arguments

  * `unit` is the unit counted, as for `in_period/3`.

  * `value` is the whole number the step counts back from.

  * `context` is a keyword list of the units before it, as a value's `:time` holds them.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, previous}`, the value before `value`.

  * `:first` when `value` is the first the unit takes there.

  * `{:error, :uncounted}` for a unit that takes no run of values, such as a year.

  ### Examples

      iex> Tempo.UnitValues.preceding(:day, 15, [year: 2026, month: 6], Calendrical.Gregorian)
      {:ok, 14}

      iex> Tempo.UnitValues.preceding(:day, 1, [year: 2026, month: 6], Calendrical.Gregorian)
      :first

      iex> Tempo.UnitValues.preceding(:hour, 0, [], Calendrical.Gregorian)
      :first

  """
  @spec preceding(atom(), integer(), keyword(), module()) ::
          {:ok, integer()} | :first | {:error, :uncounted}
  def preceding(unit, value, context, calendar) when is_integer(value) and unit in @counted do
    case listed(unit, context, calendar) do
      {:ok, values} -> preceding_among(values, value)
      _counted_from_the_first -> counted_preceding(unit, value)
    end
  end

  def preceding(_unit, _value, _context, _calendar), do: {:error, :uncounted}

  defp counted_preceding(unit, value) do
    if value > first_value(unit), do: {:ok, value - 1}, else: :first
  end

  defp preceding_among(values, value) do
    case values |> numbers() |> Enum.take_while(&(&1 < value)) |> List.last() do
      nil -> :first
      previous -> {:ok, previous}
    end
  end

  @doc """
  Returns the values a written value names among those a unit takes, in order and once each.

  A count from the end is counted in `values`, and a range is resolved end by end, so `1..-1//1` is every value and `28..-1//1` the 28th to the last. A value the unit does not take is passed over, as a selection passes over the 31st of a month of thirty days.

  ### Arguments

  * `written` is a `t:written/0`.

  * `values` is the values the unit takes, a `t:values/0` as `in_period/3` gives it.

  ### Returns

  * A list of whole numbers of `values`, ascending and with none twice.

  ### Examples

      iex> Tempo.UnitValues.named([28..-1//1], 1..30//1)
      [28, 29, 30]

      iex> Tempo.UnitValues.named([-1, 1, 31], 1..30//1)
      [1, 30]

      iex> Tempo.UnitValues.named(-1, 0..23//1)
      [23]

  """
  @spec named(written(), values()) :: [integer()]
  def named(written, values) when is_struct(values, Range) or is_list(values) do
    written
    |> List.wrap()
    |> Enum.flat_map(&values_named(&1, values))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A range's members are looked for among the unit's own values, so a range
  # far longer than them (`{1..999999999}D`) costs no more than they do. A
  # range runs up from its first value: one that counts down names nothing,
  # as one whose ends are counted to a first after its last does.
  defp values_named(%Range{step: step}, _values) when step < 1, do: []

  defp values_named(%Range{first: first, last: last, step: step}, values) do
    named = Range.new(from_end(first, values), from_end(last, values), step)
    values |> numbers() |> Enum.filter(&(&1 in named))
  end

  defp values_named(index, values) when is_integer(index) do
    value = from_end(index, values)
    if taken?(value, values), do: [value], else: []
  end

  # A mask stands for the values of the unit whose digits it matches, as it
  # does in a value (`Tempo.Mask.valid_values/4`): `1X` of a month's days is
  # the 10th to the 19th. It was passed over, so a part of a selection
  # written with one selected nothing. One counted from the end (`-X`) is
  # the values that many from the last: the last nine.
  defp values_named({:mask, [:negative | mask]}, values) when is_list(mask) do
    counted = numbers(values)

    1..Enum.count(counted)//1
    |> Mask.matching(mask)
    |> Enum.map(&Enum.at(counted, -&1))
  end

  defp values_named({:mask, mask}, values) when is_list(mask),
    do: values |> numbers() |> Mask.matching(mask)

  # An unspecified unit (`X*`) stands for every value the unit takes, as a
  # mask of as many digits does (`XX` of a month's days). It was passed
  # over, so a part written with one selected nothing.
  defp values_named(:any, values), do: numbers(values)

  defp values_named(_not_a_number, _values), do: []

  @doc """
  Returns a written value with each count from the end counted among the values a unit takes, in the shape it is written in.

  Where `named/2` lists the values a written value names, passing over those the unit does not take, this keeps a range a range and a list a list, as a value holds them and writes them back, and refuses a value the unit does not take: it is how a value is read.

  ### Arguments

  * `written` is a `t:written/0`, or a float for a fraction of a unit.

  * `values` is the values the unit takes, a `t:values/0` as `in_period/3` gives it.

  ### Returns

  * `{:ok, resolved}`, where a whole number counted from the end is the value it names, a range has each end so counted and counts up by its own step, and a list has each of its members so resolved. A range that runs through values the unit does not take, in a month with days missing, is the ranges of those it names.

  * `{:error, {:not_taken, value}}` for the first written value, or end of a range, that is not one of `values`.

  * `{:error, {:not_taken, value, counted}}` for the first count from the end that reaches past their start, with the value it counts to.

  * `{:error, {:backwards, range}}` for a range that counts down, and `{:error, {:backwards, range, counted}}` for one whose ends are counted to a first value after its last, with the range they are counted to.

  ### Examples

      iex> Tempo.UnitValues.resolve(-1, 1..30//1)
      {:ok, 30}

      iex> Tempo.UnitValues.resolve([1, 28..-1//1], 1..30//1)
      {:ok, [1, 28..30]}

      iex> Tempo.UnitValues.resolve(22..25//1, 0..23//1)
      {:error, {:not_taken, 25}}

      iex> Tempo.UnitValues.resolve(-31, 1..30//1)
      {:error, {:not_taken, -31, 0}}

      iex> Tempo.UnitValues.resolve(-1..1//1, 1..30//1)
      {:error, {:backwards, -1..1//1, 30..1//1}}

      iex> Tempo.UnitValues.resolve(1..-1//1, [1..2, 14..30])
      {:ok, [1..2, 14..30]}

      iex> Tempo.UnitValues.resolve(3, [1..2, 14..30])
      {:error, {:not_taken, 3}}

  """
  @spec resolve(written() | float(), values()) ::
          {:ok, written() | float()}
          | {:error,
             {:not_taken, term()}
             | {:not_taken, integer(), integer()}
             | {:backwards, Range.t()}
             | {:backwards, Range.t(), Range.t()}}
  def resolve(value, %Range{first: first, last: last})
      when is_integer(value) and value in first..last//1,
      do: {:ok, value}

  def resolve(value, %Range{first: first, last: last})
      when is_float(value) and value >= first and value <= last,
      do: {:ok, value}

  def resolve(value, %Range{first: first, last: last} = values)
      when is_integer(value) and value < 0 do
    counted = from_end(value, values)

    if counted >= 0 and counted in first..last//1,
      do: {:ok, counted},
      else: {:error, {:not_taken, value, counted}}
  end

  def resolve(%Range{step: step} = range, %Range{}) when step < 1,
    do: {:error, {:backwards, range}}

  def resolve(%Range{first: from, last: to} = range, %Range{first: first, last: last})
      when from <= to and from in first..last//1 and to in first..last//1,
      do: {:ok, range}

  def resolve(%Range{first: from, last: to, step: step} = range, %Range{} = values) do
    with {:ok, from} <- resolve(from, values),
         {:ok, to} <- resolve(to, values) do
      if from <= to,
        do: {:ok, from..to//step},
        else: {:error, {:backwards, range, from..to//step}}
    end
  end

  def resolve(written, %Range{} = values) when is_list(written) do
    written
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, resolved} ->
      case resolve(member, values) do
        {:ok, value} -> {:cont, {:ok, [value | resolved]}}
        {:error, _not_taken} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      {:error, _not_taken} = error -> error
    end
  end

  def resolve(value, %Range{}), do: {:error, {:not_taken, value}}

  # Values that do not run on from one another: a number is one of them or
  # it is not, a count from the end is counted among them, and a range is
  # the ranges of them it names, which are several where it runs through
  # values the calendar does not have.
  def resolve(written, [%Range{} | _] = values), do: resolve_listed(written, values)

  defp resolve_listed(value, values) when is_integer(value) and value >= 0 do
    if taken?(value, values), do: {:ok, value}, else: {:error, {:not_taken, value}}
  end

  defp resolve_listed(value, values) when is_float(value) do
    if Enum.any?(values, &(value >= &1.first and value <= &1.last)),
      do: {:ok, value},
      else: {:error, {:not_taken, value}}
  end

  defp resolve_listed(value, values) when is_integer(value) do
    counted = from_end(value, values)

    if taken?(counted, values),
      do: {:ok, counted},
      else: {:error, {:not_taken, value, counted}}
  end

  defp resolve_listed(%Range{step: step} = range, _values) when step < 1,
    do: {:error, {:backwards, range}}

  defp resolve_listed(%Range{first: from, last: to, step: step} = range, values) do
    with {:ok, from} <- resolve_listed(from, values),
         {:ok, to} <- resolve_listed(to, values) do
      if from <= to,
        do: {:ok, taken_within(from..to//step, values)},
        else: {:error, {:backwards, range, from..to//step}}
    end
  end

  defp resolve_listed(written, values) when is_list(written) do
    written
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, resolved} ->
      case resolve_listed(member, values) do
        {:ok, value} -> {:cont, {:ok, [value | resolved]}}
        {:error, _not_taken} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, resolved |> Enum.reverse() |> List.flatten()}
      {:error, _not_taken} = error -> error
    end
  end

  defp resolve_listed(value, _values), do: {:error, {:not_taken, value}}

  # The values a range names among those listed: the range where it runs
  # through none that is missing, and otherwise the ranges of those it names.
  defp taken_within(%Range{step: 1} = range, values) do
    case for(%Range{} = run <- values, within = overlap(range, run), do: within) do
      [one] -> one
      several -> several
    end
  end

  defp taken_within(%Range{} = range, values), do: Enum.filter(range, &taken?(&1, values))

  defp overlap(%Range{first: first, last: last}, %Range{first: run_first, last: run_last}) do
    if max(first, run_first) <= min(last, run_last),
      do: max(first, run_first)..min(last, run_last)//1
  end

  @doc """
  Returns the value a count from the end names among those a unit takes.

  ### Arguments

  * `index` is a whole number: negative, it is counted back from the last value, `-1` being the last; otherwise it is returned as it is.

  * `values` is the values the unit takes, a `t:values/0`. Among values that do not run on from one another the count is of the values themselves.

  ### Returns

  * A whole number, which is one of `values` only when the count does not reach past their start.

  ### Examples

      iex> Tempo.UnitValues.from_end(-1, 1..30//1)
      30

      iex> Tempo.UnitValues.from_end(-1, 0..23//1)
      23

      iex> Tempo.UnitValues.from_end(15, 1..30//1)
      15

      iex> Tempo.UnitValues.from_end(-18, [1..2, 14..30])
      2

  """
  @spec from_end(integer(), values()) :: integer()
  def from_end(index, %Range{last: last}) when is_integer(index) and index < 0,
    do: last + 1 + index

  def from_end(index, %Range{}) when is_integer(index), do: index

  # Among values that do not run on from one another the count is of the
  # values themselves: the last but seventeen of `[1..2, 14..30]` is the 2nd.
  # A count that reaches past the first names a number before it.
  def from_end(index, [%Range{} | _] = values) when is_integer(index) and index < 0 do
    numbers = numbers(values)

    case Enum.at(numbers, index) do
      nil -> first_of(values) + length(numbers) + index
      value -> value
    end
  end

  def from_end(index, [%Range{} | _]) when is_integer(index), do: index

  ## A year that does not begin with its first month
  #
  # A value's units are numbers, and a year's dates run in the order of
  # those numbers. In most years the first of them is the first day of the
  # first month: Calendrical's calendars whose year turns on another day
  # (its Julian `March25`, `March1`, `Sept1` and `Dec25`) count their months
  # from that day, so their first month is the one the year begins with. A
  # year a composite calendar changes its new year's day in is the
  # exception: 1751 in `Calendrical.Reform.England` runs from 25 March to 31
  # December, with the months March to December as they are numbered and a
  # March that begins on the 25th. So where a year and a month of it begin
  # is asked of the calendar, here, and not taken to be a first.

  @doc """
  Returns whether a year begins on the first day of its first month.

  Where it does, a value written to its year starts on the first day of the first month. Where it does not, the day it starts on is asked of the calendar (`first_date/2`): the year a composite calendar changes its new year's day in, as 1751 in `Calendrical.Reform.England`, which begins on 25 March.

  ### Arguments

  * `year` is the year, in the calendar's own numbering.

  * `calendar` is the calendar module the year is counted in.

  ### Returns

  * `true` or `false`. A calendar with no `day_of_year/3` is taken to begin its years with their first month, and a year a composite calendar does not have begins on no day.

  ### Examples

      iex> Tempo.UnitValues.year_begins_with_first_month?(2026, Calendrical.Gregorian)
      true

      iex> Tempo.UnitValues.year_begins_with_first_month?(5786, Calendrical.Hebrew)
      true

      iex> Tempo.UnitValues.year_begins_with_first_month?(1750, Calendrical.Julian.March25)
      true

      iex> Tempo.UnitValues.year_begins_with_first_month?(1751, Calendrical.Reform.England)
      false

  """
  @spec year_begins_with_first_month?(integer(), module()) :: boolean()
  def year_begins_with_first_month?(year, calendar) when is_integer(year) and is_atom(calendar) do
    case year_start(calendar, year) do
      :every_year -> true
      :no_year -> false
      # A year with no first day of a first month does not begin on one.
      :by_year -> first_day_of_first_month?(calendar, year) == true
    end
  end

  def year_begins_with_first_month?(_year, _calendar), do: true

  # How a calendar begins its years is asked once of each calendar and kept:
  # the question is asked wherever two values are compared, and the first
  # day of a year takes an astronomical calendar hundreds of microseconds to
  # find. A calendar of one rule begins every year alike, so one year
  # answers for them all. A composite calendar begins a year as the calendar
  # in effect then does, so each of its years is asked.
  @year_start_key {__MODULE__, :year_start}

  defp year_start(calendar, year) do
    case :persistent_term.get({@year_start_key, calendar}, nil) do
      nil -> calendar |> year_start_of(year) |> kept_year_start(calendar)
      year_start -> year_start
    end
  end

  defp year_start_of(calendar, year) do
    if composite?(calendar),
      do: :by_year,
      else: calendar |> first_day_of_first_month?(year) |> year_start_from()
  end

  defp year_start_from(true), do: :every_year
  defp year_start_from(false), do: :no_year
  # A year the calendar does not have answers for no other.
  defp year_start_from(:unknown), do: :unknown

  defp kept_year_start(:unknown, _calendar), do: :every_year

  defp kept_year_start(year_start, calendar) do
    :persistent_term.put({@year_start_key, calendar}, year_start)
    year_start
  end

  defp first_day_of_first_month?(calendar, year) do
    case calendar.day_of_year(year, 1, 1) do
      1 -> true
      day when is_integer(day) -> false
      _no_such_day -> :unknown
    end
  end

  @doc """
  Returns the first date of a year, or of a month of a year, as the calendar counts them.

  A year's first date is the first of the days its calendar gives it (`year/1`), and a month's the first of the days its calendar gives the month (`month/2`). They are the first of the first month and the first of the month but in a year that begins on another day: 1751 in `Calendrical.Reform.England` begins on 25 March, and so does its March.

  ### Arguments

  * `context` is `[year: year]` or `[year: year, month: month]`, each a whole number.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, {year, month, day}}`, the date in the calendar's own numbers.

  * `{:error, :no_period}` when the calendar has no such year or month, or lists no days for one.

  ### Examples

      iex> Tempo.UnitValues.first_date([year: 1750], Calendrical.Julian.March25)
      {:ok, {1750, 1, 1}}

      iex> Tempo.UnitValues.first_date([year: 1750, month: 2], Calendrical.Julian.March25)
      {:ok, {1750, 2, 1}}

      iex> Tempo.UnitValues.first_date([year: 2026, month: 6], Calendrical.Gregorian)
      {:ok, {2026, 6, 1}}

      iex> Tempo.UnitValues.first_date([year: 1751], Calendrical.Reform.England)
      {:ok, {1751, 3, 25}}

  """
  @spec first_date(keyword(), module()) ::
          {:ok, {integer(), pos_integer(), pos_integer()}} | {:error, :no_period}
  def first_date([{:year, year}], calendar) when is_integer(year) do
    case calendar.year(year) do
      %Date.Range{first: %Date{year: year, month: month, day: day}} -> {:ok, {year, month, day}}
      _no_such_year -> {:error, :no_period}
    end
  end

  def first_date([{:year, year}, {:month, month}], calendar)
      when is_integer(year) and is_integer(month) do
    with {:ok, %Date.Range{first: first}} <- month_range(year, month, calendar) do
      {:ok, {first.year, first.month, first.day}}
    end
  end

  def first_date(_context, _calendar), do: {:error, :no_period}

  @doc false
  # The date a value written to its year, its month or its day starts on:
  # the day, the first of the month, or the first of the year's first month,
  # and where the year does not begin with its first month the first date
  # the calendar gives the year or the month (`first_date/2`). `:error` for a
  # time list with no one year, or a month or a day that is no one number.
  @spec start_date(list(), module()) ::
          {:ok, {integer(), pos_integer(), pos_integer()}} | :error
  def start_date(time, calendar) when is_list(time) do
    case {whole(time, :year), one(time, :month), one(time, :day)} do
      {nil, _month, _day} -> :error
      {year, {:ok, month}, {:ok, day}} -> {:ok, {year, month, day}}
      {year, {:ok, month}, :none} -> {:ok, first_of(year, month, calendar)}
      {year, :none, :none} -> {:ok, first_of(year, nil, calendar)}
      _no_one_start -> :error
    end
  end

  defp one(time, unit) do
    case List.keyfind(time, unit, 0) do
      {^unit, value} when is_integer(value) and value > 0 -> {:ok, value}
      nil -> :none
      _several -> :several
    end
  end

  defp first_of(year, month, calendar) do
    context = if month, do: [year: year, month: month], else: [year: year]

    with false <- year_begins_with_first_month?(year, calendar),
         {:ok, first} <- first_date(context, calendar) do
      first
    else
      _first_of_the_month -> {year, month || 1, 1}
    end
  end

  @doc false
  # A time list written to its year, with the year's first month: the first,
  # or where the year begins on another day the month of the first date the
  # calendar gives it (1751 in `Calendrical.Reform.England` begins in
  # March). It is what a year is extended to when it is written to the month.
  @spec with_first_month(list(), module()) :: list()
  def with_first_month([{:year, year}] = time, calendar) when is_integer(year) do
    with false <- year_begins_with_first_month?(year, calendar),
         {:ok, {year, month, _day}} <- first_date(time, calendar) do
      [year: year, month: month]
    else
      _its_first_month -> time ++ [month: 1]
    end
  end

  def with_first_month(time, _calendar), do: time ++ [month: 1]

  @doc false
  # A time list written to its month, with the month's first day: the first
  # of the month, or where the year does not begin with its first month the
  # first date the calendar gives the month. It is what a month is extended
  # to when it is written to the day.
  @spec with_first_day(list(), module()) :: list()
  def with_first_day([{:year, year}, {:month, month}] = time, calendar)
      when is_integer(year) and is_integer(month) do
    with false <- year_begins_with_first_month?(year, calendar),
         {:ok, {year, month, day}} <- first_date(time, calendar) do
      [year: year, month: month, day: day]
    else
      _counted_from_one -> time ++ [day: 1]
    end
  end

  def with_first_day(time, _calendar), do: time ++ [day: 1]

  @doc """
  Returns the weeks of a month of a year, each as the dates the calendar numbers in it.

  A week of a month is the calendar's to number, and Calendrical gives a month's weeks as the calendar's `week_of_month/3` numbers its dates (its `weeks_in_month/2` and `month_week/3`). So a week is whatever the calendar holds it to be. In `Calendrical.Gregorian` it is a whole week that starts on a Monday, the first of a month the one that holds its first day: a month's first week may start in the month before, and its last days may be in the first week of the next. A calendar that numbers a month's weeks from its first day to its last cuts the first and the last of them short.

  ### Arguments

  * `year` is the year, in the calendar's own numbering.

  * `month` is the month of the year.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, weeks}`, a list of `t:Date.Range.t/0` in order, the first the dates of week 1.

  * `{:error, :no_period}` when the calendar has no such month, or gives it no weeks.

  ### Examples

      iex> {:ok, weeks} = Tempo.UnitValues.weeks_of_month(2026, 7, Calendrical.Gregorian)
      iex> Enum.map(weeks, &{Date.to_iso8601(&1.first), Date.to_iso8601(&1.last)})
      [
        {"2026-06-29", "2026-07-05"},
        {"2026-07-06", "2026-07-12"},
        {"2026-07-13", "2026-07-19"},
        {"2026-07-20", "2026-07-26"}
      ]

      iex> Tempo.UnitValues.weeks_of_month(2026, 13, Calendrical.Gregorian)
      {:error, :no_period}

  """
  @spec weeks_of_month(integer(), pos_integer(), module()) ::
          {:ok, [Date.Range.t(), ...]} | {:error, :no_period}
  def weeks_of_month(year, month, calendar)
      when is_integer(year) and is_integer(month) and is_atom(calendar) do
    with weeks when is_integer(weeks) <- calendar.weeks_in_month(year, month),
         dates = Enum.map(1..weeks//1, &calendar.month_week(year, month, &1)),
         true <- Enum.all?(dates, &is_struct(&1, Date.Range)) do
      {:ok, dates}
    else
      _no_weeks -> {:error, :no_period}
    end
  end

  def weeks_of_month(_year, _month, _calendar), do: {:error, :no_period}

  @doc """
  Returns the dates of a week of a month of a year, as the calendar numbers its weeks.

  ### Arguments

  * `year` is the year, in the calendar's own numbering.

  * `month` is the month of the year.

  * `week` is the week of the month: a whole number, counted from the month's last week when it is negative.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, dates}`, the `t:Date.Range.t/0` from the week's first date to its last.

  * `{:error, :no_period}` when the month has no such week, or `weeks_of_month/3` has none to give for it.

  ### Examples

      iex> {:ok, week} = Tempo.UnitValues.week_of_month(2026, 7, 1, Calendrical.Gregorian)
      iex> {Date.to_iso8601(week.first), Date.to_iso8601(week.last)}
      {"2026-06-29", "2026-07-05"}

      iex> {:ok, week} = Tempo.UnitValues.week_of_month(2026, 6, -1, Calendrical.Gregorian)
      iex> {Date.to_iso8601(week.first), Date.to_iso8601(week.last)}
      {"2026-06-22", "2026-06-28"}

      iex> Tempo.UnitValues.week_of_month(2026, 6, 5, Calendrical.Gregorian)
      {:error, :no_period}

  """
  @spec week_of_month(integer(), pos_integer(), integer(), module()) ::
          {:ok, Date.Range.t()} | {:error, :no_period}
  def week_of_month(year, month, week, calendar) when is_integer(week) and week != 0 do
    with {:ok, weeks} <- weeks_of_month(year, month, calendar),
         %Date.Range{} = dates <- Enum.at(weeks, if(week > 0, do: week - 1, else: week)) do
      {:ok, dates}
    else
      _no_such_week -> {:error, :no_period}
    end
  end

  def week_of_month(_year, _month, _week, _calendar), do: {:error, :no_period}

  # The days the calendar gives a month of a year: its `month/2`, a callback
  # of the `Calendrical` behaviour.
  defp month_range(year, month, calendar) do
    case calendar.month(year, month) do
      %Date.Range{} = dates -> {:ok, dates}
      _no_such_month -> {:error, :no_period}
    end
  end

  # A year to ask a calendar of one rule about, where the value names none.
  @any_year 2000

  @doc false
  # Whether every year a value names begins with its first month, where
  # `years` is what a time list holds for its year: a whole number, a set of
  # whole numbers and ranges, a mask, or nothing. A calendar of one rule
  # begins every year alike, so it answers for a year that is no one number
  # as it does for any. A composite calendar begins each year as the
  # calendar in effect then does: it is asked of each whole number, and of
  # the ends of each range, and a mask or no year at all is taken to begin
  # with its first month.
  @spec years_begin_with_first_month?(term(), module()) :: boolean()
  def years_begin_with_first_month?(year, calendar) when is_integer(year),
    do: year_begins_with_first_month?(year, calendar)

  def years_begin_with_first_month?(years, calendar) do
    case whole_years(years) do
      [] -> composite?(calendar) or year_begins_with_first_month?(@any_year, calendar)
      whole -> Enum.all?(whole, &year_begins_with_first_month?(&1, calendar))
    end
  end

  @doc false
  # The whole numbers a time list's year is asked by: itself, the members of
  # a set and the two ends of each range in one, the number a margin of
  # error or significant digits are written on, and the lowest and the
  # highest year a mask stands for. An unspecified year names none.
  @spec whole_years(term()) :: [integer()]
  def whole_years(year) when is_integer(year), do: [year]
  def whole_years(%Range{first: first, last: last}), do: [first, last]
  def whole_years({year, annotations}) when is_integer(year) and is_list(annotations), do: [year]

  # A mask is asked of the lowest and the highest year it stands for.
  def whole_years({:mask, [:negative | digits]}),
    do: digits |> Mask.mask_bounds() |> Tuple.to_list() |> Enum.map(&(-&1))

  def whole_years({:mask, digits}) when is_list(digits),
    do: digits |> Mask.mask_bounds() |> Tuple.to_list()

  def whole_years(years) when is_list(years), do: Enum.flat_map(years, &whole_years/1)
  def whole_years(_mask_or_none), do: []

  ## The days of a week
  #
  # `K` counts the days of the week of the value that holds it: the
  # calendar's own week in a calendar of weeks, whose dates hold that day,
  # and ISO 8601's week, which starts on Monday, in a calendar of months
  # (decided 2026-10-05). So a day of the week is a number of its value's
  # calendar, and the weekday it names is asked of that calendar, here,
  # wherever it meets a date of another calendar or a weekday's name.

  @doc """
  Returns the weekday a day of the week names in a calendar, as ISO 8601 numbers the weekdays.

  In a calendar of months a day of the week is ISO 8601's, so it is its own weekday. In a calendar of weeks it is a day of the calendar's own week, and the weekday depends on the day those weeks start on: the third day is Wednesday in `Calendrical.ISOWeek`, whose weeks start on Monday, and Tuesday in `Calendrical.NRF`, whose weeks start on Sunday.

  ### Arguments

  * `day_of_week` is a day of the week as a value of the calendar holds it, from 1 to 7.

  * `calendar` is the calendar module of the value that holds the day.

  ### Returns

  * The weekday from 1, Monday, to 7, Sunday. A number that is no day of a week is returned as it is.

  ### Examples

      iex> Tempo.UnitValues.iso_weekday_from_day_of_week(3, Calendrical.Gregorian)
      3

      iex> Tempo.UnitValues.iso_weekday_from_day_of_week(3, Calendrical.ISOWeek)
      3

      iex> Tempo.UnitValues.iso_weekday_from_day_of_week(3, Calendrical.NRF)
      2

  """
  @spec iso_weekday_from_day_of_week(integer(), module()) :: integer()
  def iso_weekday_from_day_of_week(day_of_week, calendar) when is_integer(day_of_week) do
    if day_of_week in days_of_a_week(calendar) and Tempo.week_based_calendar?(calendar),
      do: weekday_of_week_day(calendar, day_of_week),
      else: day_of_week
  end

  def iso_weekday_from_day_of_week(no_day_of_a_week, _calendar), do: no_day_of_a_week

  @doc """
  Returns the day of the week a calendar gives a weekday, the weekday numbered as ISO 8601 numbers it.

  The inverse of `iso_weekday_from_day_of_week/2`: Wednesday is the third day of the week in a calendar of months and in `Calendrical.ISOWeek`, and the fourth in `Calendrical.NRF`, whose weeks start on Sunday.

  ### Arguments

  * `iso_weekday` is the weekday from 1, Monday, to 7, Sunday.

  * `calendar` is the calendar module the day of the week is wanted in.

  ### Returns

  * The day of the week from 1 to 7, as a value of the calendar holds it. A number that is no weekday is returned as it is.

  ### Examples

      iex> Tempo.UnitValues.day_of_week_from_iso_weekday(3, Calendrical.Gregorian)
      3

      iex> Tempo.UnitValues.day_of_week_from_iso_weekday(3, Calendrical.NRF)
      4

  """
  @spec day_of_week_from_iso_weekday(integer(), module()) :: integer()
  def day_of_week_from_iso_weekday(iso_weekday, calendar) when is_integer(iso_weekday) do
    if Tempo.week_based_calendar?(calendar) do
      calendar
      |> days_of_a_week()
      |> Enum.find(iso_weekday, &(weekday_of_week_day(calendar, &1) == iso_weekday))
    else
      iso_weekday
    end
  end

  def day_of_week_from_iso_weekday(no_weekday, _calendar), do: no_weekday

  @doc false
  # The day a calendar is asked to count a week's days from, for the number
  # `K` gives one of its dates: its own first day in a calendar of weeks,
  # and Monday in a calendar of months.
  @spec week_counted_from(module()) :: :default | :monday
  def week_counted_from(calendar),
    do: if(Tempo.week_based_calendar?(calendar), do: :default, else: :monday)

  # The days of a week as a calendar numbers them, from the first to as
  # many as it says a week has.
  defp days_of_a_week(calendar), do: 1..calendar.days_in_week()//1

  # Every week of a calendar of weeks starts on the same weekday, so the
  # first week of any year answers for them all.
  defp weekday_of_week_day(calendar, day_of_week) do
    {iso_weekday, _first, _last} = calendar.day_of_week(@any_year, 1, day_of_week, :monday)
    iso_weekday
  end

  ## The weeks of a year

  # What a calendar's weeks are: how many a year has, where each starts,
  # the date a day of one is, and which week of its year a week is. ISO
  # 8601's weeks (`W`) start on Monday, the first the one that holds the
  # year's fourth day; a calendar's own (`w`) are those it numbers.

  # ISO 8601's weeks start on a Monday, weekday 1.
  @monday 1

  @doc false
  # The date of day `day` of ISO 8601 week `week` of `year` (`W`). A
  # week-based calendar's weeks are its own dates. A month-based calendar's
  # follow ISO 8601's rule over the calendar's own year, as RFC 7529
  # applies it to any calendar: each week starts on a Monday, and week 1 is
  # the one holding the year's fourth day.
  #
  # In the Gregorian calendar those weeks are the weeks of
  # `Calendrical.ISOWeek`, the calendar that is ISO 8601's weeks, so the date
  # is asked of it in one step: finding where the year's week 1 starts, and
  # the next year's, took ten times as long.
  def date_from_iso_week(year, week, day, Calendrical.Gregorian)
      when is_integer(year) and is_integer(week) and is_integer(day) do
    with {:ok, week_date} <- Date.new(year, week, day, Calendrical.ISOWeek),
         do: Date.convert(week_date, Calendrical.Gregorian)
  end

  def date_from_iso_week(year, week, day, calendar) do
    if Tempo.week_based_calendar?(calendar) do
      Date.new(year, week, day, calendar)
    else
      calendar
      |> iso_week_start(year, week)
      |> date_in_week(day, calendar)
    end
  end

  @doc false
  # The date of day `day` of week `week` of `year` in the calendar's own
  # weeks (`w`): a week-based calendar's native date or, in a month-based
  # one, the day of the week with ISO 8601's number `day` (`1`, Monday, to
  # `7`, Sunday) among the days the calendar's `week/2` gives the week,
  # so a week cut short at the start or end of its year has fewer.
  def date_from_calendar_week(year, week, day, calendar) do
    if Tempo.week_based_calendar?(calendar),
      do: Date.new(year, week, day, calendar),
      else: weekday_in_week(calendar_week_range(year, week, calendar), day)
  end

  @doc false
  # The days of week `week` of `year` in the calendar's own weeks (`w`), as
  # the calendar's `week/2` gives them: a `Date.Range`, which is cut
  # short at the start or end of the year in a calendar whose weeks number
  # within their own year, or an error for a week the calendar does not
  # number.
  def calendar_week_range(year, week, calendar), do: calendar.week(year, week)

  @doc false
  # How many ISO 8601 weeks (`W`) `year` has: a week-based calendar's own
  # count, or the weeks ISO 8601's rule gives a month-based calendar's year.
  # The Gregorian calendar's are the weeks of `Calendrical.ISOWeek`, as in
  # `date_from_iso_week/4`.
  def iso_weeks_in_year(year, Calendrical.Gregorian) when is_integer(year),
    do: calendar_weeks_in_year(year, Calendrical.ISOWeek)

  def iso_weeks_in_year(year, calendar) do
    if Tempo.week_based_calendar?(calendar),
      do: calendar_weeks_in_year(year, calendar),
      else: iso_week_count(calendar, year)
  end

  # The weeks from the first day of a year's week 1 to the first day of the
  # next year's, as Calendrical counts them: 52 or 53.
  defp iso_week_count(calendar, year) do
    with {:ok, first} <- first_week_start(calendar, year, @monday),
         {:ok, next_first} <- first_week_start(calendar, year + 1, @monday),
         weeks when is_integer(weeks) <- counted_between(first, next_first, :weeks) do
      weeks
    else
      _no_first_week -> 0
    end
  end

  # The first day of week `week` of `year`: that many weeks on from week 1's,
  # by Calendrical's arithmetic, when the year has the week. It is reached in
  # one step, where listing the year's weeks to find it took one for each.
  defp iso_week_start(calendar, year, week) when is_integer(week) and week >= 1 do
    with {:ok, first} <- first_week_start(calendar, year, @monday),
         {:ok, next_first} <- first_week_start(calendar, year + 1, @monday),
         {start_year, month, day} <-
           calendar.plus(first.year, first.month, first.day, :weeks, week - 1, []),
         {:ok, start} <- Date.new(start_year, month, day, calendar),
         :lt <- Compare.compare_days(start, next_first) do
      start
    else
      _no_such_week -> nil
    end
  end

  defp iso_week_start(_calendar, _year, _week), do: nil

  @doc false
  # How many weeks `year` has in the calendar's own numbering (`w`), or 0
  # for a calendar that numbers no weeks.
  def calendar_weeks_in_year(year, calendar) do
    case calendar.weeks_in_year(year) do
      {weeks, _days_in_last_week} when is_integer(weeks) -> weeks
      weeks when is_integer(weeks) -> weeks
      _not_defined -> 0
    end
  end

  @doc false
  # The first day of each week of `year`, week 1 first, for weeks that
  # start on weekday `first_day` (`1`, Monday, to `7`, Sunday) with week 1
  # the one holding the year's fourth day: ISO 8601's weeks for Monday, and
  # the weeks RFC 5545 counts from another WKST.
  def week_starts(calendar, year, first_day) do
    consecutive_week_starts(
      first_week_start(calendar, year, first_day),
      first_week_start(calendar, year + 1, first_day)
    )
  end

  # Each week's first day, from week 1's up to the first day of the next
  # year's week 1, each the day Calendrical gives a week after the last.
  defp consecutive_week_starts({:ok, first}, {:ok, next_first}) do
    first
    |> Stream.iterate(&week_after/1)
    |> Enum.take_while(&(Compare.compare_days(&1, next_first) == :lt))
  end

  defp consecutive_week_starts(_first, _next_first), do: []

  @doc false
  # Which week of `year` the week that starts on `week_start` is, and how
  # many weeks the year has, for weeks numbered as `week_starts/3` numbers
  # them: the weeks from the first day of the year's week 1 to it, and to
  # the first day of the next year's, as Calendrical counts them. It is
  # found in two steps, where the year's weeks were listed to find it among
  # them, which a rule of days with a week of the year asks of each day.
  def week_number(calendar, year, first_day, %Date{} = week_start) do
    with {:ok, first} <- first_week_start(calendar, year, first_day),
         {:ok, next_first} <- first_week_start(calendar, year + 1, first_day),
         :lt <- Compare.compare_days(week_start, next_first),
         before when is_integer(before) and before >= 0 <-
           counted_between(first, week_start, :weeks),
         weeks when is_integer(weeks) <- counted_between(first, next_first, :weeks) do
      {:ok, before + 1, weeks}
    else
      _not_a_week_of_the_year -> :error
    end
  end

  @doc false
  # The whole units (`:years`, `:months`, `:weeks` or `:days`) from one date
  # to another, as their calendar counts them, and `:two_calendars` for
  # dates that are not of one calendar.
  def counted_between(%Date{} = from, %Date{} = to, part) do
    calendar = Calendars.effective(from.calendar)

    if Calendars.effective(to.calendar) == calendar,
      do: calendar.diff({from.year, from.month, from.day}, {to.year, to.month, to.day}, part),
      else: :two_calendars
  end

  @doc false
  # The day after a date, the day before it and the same day a week on, each
  # as the date's calendar counts it.
  def day_after(%Date{} = date), do: stepped(date, :days, 1)

  @doc false
  def day_before(%Date{} = date), do: stepped(date, :days, -1)

  @doc false
  def week_after(%Date{} = date), do: stepped(date, :weeks, 1)

  defp stepped(%Date{year: year, month: month, day: day} = date, unit, count) do
    calendar = Calendars.effective(date.calendar)
    {year, month, day} = calendar.plus(year, month, day, unit, count, [])
    %{date | year: year, month: month, day: day}
  end

  defp first_week_start(calendar, year, first_day) do
    case calendar.date_from_day_of_year(year, 4) do
      %Date{} = fourth_day -> {:ok, Kday.kday_on_or_before(fourth_day, first_day)}
      {:error, _reason} -> :error
    end
  end

  # The `day`th day of the week that starts on `week_start`, from
  # Calendrical's arithmetic.
  defp date_in_week(%Date{} = week_start, day, calendar) when is_integer(day) do
    with true <- day in days_of_a_week(calendar),
         {year, month, day_of_month} <-
           calendar.plus(week_start.year, week_start.month, week_start.day, :days, day - 1, []) do
      Date.new(year, month, day_of_month, calendar)
    else
      _no_such_day -> {:error, :invalid_date}
    end
  end

  defp date_in_week(_week_start, _day, _calendar), do: {:error, :invalid_date}

  @doc false
  # The date among `week_days` on ISO 8601's weekday `weekday` (`1`, Monday,
  # to `7`, Sunday): a day of a week of a month, whose weeks the calendar
  # numbers and may cut short.
  def date_of_weekday(%Date.Range{} = week_days, weekday),
    do: weekday_in_week(week_days, weekday)

  # The day of `week_days` with ISO 8601's weekday number `weekday`, from
  # the calendar's own day of the week.
  defp weekday_in_week(%Date.Range{} = week_days, weekday) when is_integer(weekday) do
    case Enum.find(week_days, &(Date.day_of_week(&1, :monday) == weekday)) do
      %Date{} = date -> {:ok, date}
      nil -> {:error, :invalid_date}
    end
  end

  defp weekday_in_week(%Date.Range{}, _weekday), do: {:error, :invalid_date}
  defp weekday_in_week({:error, _reason} = error, _weekday), do: error
end
