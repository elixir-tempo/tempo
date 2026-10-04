defmodule Tempo.UnitValues do
  @moduledoc """
  The values a unit takes, and the values a written value names among them.

  A date or a time is counted in units, and each unit takes a run of values that the units before it and the calendar decide: the months of a year, the days of a month, the hours of a day. A value is written against that run as a number, as a count from its end (`-1`, the last), as a range from one of its values to another (`{28..-1}`), or as several of these.

  This module is the one place where either is worked out, so that there is one place to verify. `in_period/3` gives the run and `named/2` the values a written value names in it; `from_end/2` is the count from the end that both rest on. How many values a unit takes is always asked of the calendar, which is Calendrical's to answer: nothing here is calendar arithmetic.

  A selection's resolver (`Tempo.RRule.Selection`) reads its parts through it. The reading of a value, the walk, `Tempo.select/2` and `Tempo.explain/1` each still hold a count from the end of their own and are to follow (`plans/enumeration-and-selection.md`).

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

  * `{:error, :unanchored}` when the answer depends on a unit the context does not hold as one whole number: the days of a month with no year.

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

  """
  @spec in_period(atom(), keyword(), module()) ::
          {:ok, Range.t()} | {:error, :unanchored | :uncounted}
  def in_period(:month, context, calendar),
    do: counted(whole(context, :year), &calendar.months_in_year/1)

  def in_period(:week, context, calendar),
    do: counted(whole(context, :year), &Validation.iso_weeks_in_year(&1, calendar))

  def in_period(:calendar_week, context, calendar),
    do: counted(whole(context, :year), &Validation.calendar_weeks_in_year(&1, calendar))

  def in_period(:day_of_year, context, calendar),
    do: counted(whole(context, :year), &calendar.days_in_year/1)

  def in_period(:day, context, calendar) do
    case whole(context, :month) do
      nil -> {:error, :unanchored}
      month -> counted(whole(context, :year), &calendar.days_in_month(&1, month))
    end
  end

  def in_period(unit, _context, calendar) do
    case Unit.value_range(unit, calendar) do
      {:ok, %Range{first: first, last: last}} -> {:ok, first..last//1}
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

  defp counted(year, count) when is_integer(year) do
    case count.(year) do
      last when is_integer(last) -> {:ok, 1..last//1}
      _not_a_count -> {:error, :unanchored}
    end
  end

  defp counted(_no_year, _count), do: {:error, :unanchored}

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
