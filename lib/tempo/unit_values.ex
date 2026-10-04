defmodule Tempo.UnitValues do
  @moduledoc """
  The values a unit takes, and the values a written value names among them.

  A date or a time is counted in units, and each unit takes a run of values that the units before it and the calendar decide: the months of a year, the days of a month, the hours of a day. A value is written against that run as a number, as a count from its end (`-1`, the last), as a range from one of its values to another (`{28..-1}`), or as several of these.

  This module is the one place where either is worked out, so that there is one place to verify. `in_period/3` gives the run, and `in_any_year/3` the run a unit takes with no year to count it in; `first/3`, `last/3`, `following/4`, `preceding/4` and `at_or_before/4` are what a step asks of it; `named/2` lists the values a written value names in it, and `resolve/2` reads a written value against it in the shape it is written in; `from_end/2` is the count from the end that all rest on. How many values a unit takes is always asked of the calendar, which is Calendrical's to answer: nothing here is calendar arithmetic.

  A selection's resolver (`Tempo.RRule.Selection`), `Tempo.select/2`, the walk, the reading of a value (`Tempo.Validation`) and its masks (`Tempo.Mask`), a step from a value and `Tempo.explain/1` count through it. What stays with the calendar's own counts is the arithmetic of a group and of a fraction (the nth day of a group of months, half of a year), which counts a period's units.

  """

  alias Tempo.Iso8601.Unit
  alias Tempo.Validation

  @typedoc """
  A value as it is written: a whole number, counted from the end when it is negative, a range, or a list of either.
  """
  @type written :: integer() | Range.t() | [integer() | Range.t()]

  @doc """
  Returns the values a unit takes in the period the units before it name.

  ### Arguments

  * `unit` is the unit counted: `:month`, `:week`, `:calendar_week`, `:day_of_year`, `:day`, `:day_of_week`, `:hour`, `:minute` or `:second`.

  * `context` is a keyword list of the units before it, as a value's `:time` holds them. Only the units that decide the answer are read: the year for a month, a week or a day of the year, and the year and the month for a day.

  * `calendar` is the calendar module the units are counted in.

  ### Returns

  * `{:ok, range}`, the values from the first to the last, counted up by one.

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

  """
  @spec in_period(atom(), keyword(), module()) ::
          {:ok, Range.t()} | {:error, :unanchored | :uncounted | :no_period}
  def in_period(unit, context, calendar) do
    with {:ok, last} <- last_in_period(unit, context, calendar) do
      {:ok, first_value(unit)..last//1}
    end
  end

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
      year -> counted(Validation.iso_weeks_in_year(year, calendar))
    end
  end

  defp last_in_period(:calendar_week, context, calendar) do
    case whole(context, :year) do
      nil -> {:error, :unanchored}
      year -> counted(Validation.calendar_weeks_in_year(year, calendar))
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
    case calendar.calendar_base() do
      :week -> month <= Validation.calendar_weeks_in_year(year, calendar)
      _month -> month <= fewest_months(calendar) or month <= last_month(year, calendar)
    end
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
  defp last_in_any_year(:month, _context, calendar) do
    # `months_in_year/0` is an optional callback of a calendar.
    if exported?(calendar, :months_in_year, 0),
      do: counted_in_any_year(calendar.months_in_year()),
      else: {:error, :unanchored}
  end

  defp last_in_any_year(:day, context, calendar) do
    month = whole(context, :month)

    if is_integer(month) and month > 0 and exported?(calendar, :days_in_month, 1),
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

  # `function_exported?/3` is false for a module that is not yet loaded, so
  # one that seems not to export the function is loaded and asked again.
  defp exported?(calendar, function, arity) do
    function_exported?(calendar, function, arity) or
      (Code.ensure_loaded?(calendar) and function_exported?(calendar, function, arity))
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
  def first(unit, _context, _calendar) when unit in @counted, do: {:ok, first_value(unit)}
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
  def preceding(unit, value, _context, _calendar) when is_integer(value) and unit in @counted do
    if value > first_value(unit), do: {:ok, value - 1}, else: :first
  end

  def preceding(_unit, _value, _context, _calendar), do: {:error, :uncounted}

  @doc """
  Returns the values a written value names among those a unit takes, in order and once each.

  A count from the end is counted in `values`, and a range is resolved end by end, so `1..-1//1` is every value and `28..-1//1` the 28th to the last. A value the unit does not take is passed over, as a selection passes over the 31st of a month of thirty days.

  ### Arguments

  * `written` is a `t:written/0`.

  * `values` is the range of values the unit takes, as `in_period/3` gives it.

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
  @spec named(written(), Range.t()) :: [integer()]
  def named(written, %Range{} = values) do
    written
    |> List.wrap()
    |> Enum.flat_map(&values_named(&1, values))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A range's members are looked for among the unit's own values, so a range
  # far longer than them (`{1..999999999}D`) costs no more than they do.
  defp values_named(%Range{first: first, last: last, step: step}, values) do
    named = Range.new(from_end(first, values), from_end(last, values), step)
    Enum.filter(values, &(&1 in named))
  end

  defp values_named(index, values) when is_integer(index) do
    value = from_end(index, values)
    if value in values, do: [value], else: []
  end

  defp values_named(_not_a_number, _values), do: []

  @doc """
  Returns a written value with each count from the end counted among the values a unit takes, in the shape it is written in.

  Where `named/2` lists the values a written value names, passing over those the unit does not take, this keeps a range a range and a list a list, as a value holds them and writes them back, and refuses a value the unit does not take: it is how a value is read.

  ### Arguments

  * `written` is a `t:written/0`, or a float for a fraction of a unit.

  * `values` is the range of values the unit takes, as `in_period/3` gives it.

  ### Returns

  * `{:ok, resolved}`, where a whole number counted from the end is the value it names, a range has each end so counted and counts up by its own step, and a list has each of its members so resolved.

  * `{:error, {:not_taken, value}}` for the first written value, or end of a range, that is not one of `values`.

  * `{:error, {:not_taken, value, counted}}` for the first count from the end that reaches past their start, with the value it counts to.

  ### Examples

      iex> Tempo.UnitValues.resolve(-1, 1..30//1)
      {:ok, 30}

      iex> Tempo.UnitValues.resolve([1, 28..-1//1], 1..30//1)
      {:ok, [1, 28..30]}

      iex> Tempo.UnitValues.resolve(22..25//1, 0..23//1)
      {:error, {:not_taken, 25}}

      iex> Tempo.UnitValues.resolve(-31, 1..30//1)
      {:error, {:not_taken, -31, 0}}

  """
  @spec resolve(written() | float(), Range.t()) ::
          {:ok, written() | float()}
          | {:error, {:not_taken, term()} | {:not_taken, integer(), integer()}}
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

  def resolve(%Range{first: from, last: to} = range, %Range{first: first, last: last})
      when from in first..last//1 and to in first..last//1,
      do: {:ok, range}

  def resolve(%Range{first: from, last: to, step: step}, %Range{} = values) do
    with {:ok, from} <- resolve(from, values),
         {:ok, to} <- resolve(to, values) do
      {:ok, from..to//abs(step)}
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

  @doc """
  Returns the value a count from the end names among those a unit takes.

  ### Arguments

  * `index` is a whole number: negative, it is counted back from the last value, `-1` being the last; otherwise it is returned as it is.

  * `values` is the range of values the unit takes.

  ### Returns

  * A whole number, which is one of `values` only when the count does not reach past their start.

  ### Examples

      iex> Tempo.UnitValues.from_end(-1, 1..30//1)
      30

      iex> Tempo.UnitValues.from_end(-1, 0..23//1)
      23

      iex> Tempo.UnitValues.from_end(15, 1..30//1)
      15

  """
  @spec from_end(integer(), Range.t()) :: integer()
  def from_end(index, %Range{last: last}) when is_integer(index) and index < 0,
    do: last + 1 + index

  def from_end(index, %Range{}) when is_integer(index), do: index
end
