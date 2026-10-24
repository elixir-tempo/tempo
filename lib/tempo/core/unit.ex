defmodule Tempo.Unit do
  @moduledoc false

  # The units a value is written in, and what each holds.
  #
  # A value's units run from the coarsest to the finest: a century, a decade or
  # a year; a month, a week, a day of the year, a quarter or a season; a day or
  # a day of the week; the clock's hour, minute, second and part of a second.
  # Each holds what the text wrote (`t:held/0`): a whole number, a set of them,
  # a mask, a group or a selection. This module orders the units, tells a
  # calendar unit from a clock unit, and says which unit may follow which in a
  # value and which an abbreviated end inherits.

  # The one module that knows Tempo's own units: their order, which are of
  # the calendar and which of the clock, which are labels of a day rather
  # than units of their own, what a unit holds in a written value, and how
  # long a clock unit is in ticks (microseconds).
  #
  # Nothing here is a fact of a calendar. A year, a month, a week and a day
  # are the units ISO 8601 writes; the calendar says how long each is and
  # which values it takes (`Tempo.Calendar`). The clock units are ISO
  # 8601's 24-hour clock, which no calendar Tempo is given counts otherwise.

  @calendar_units [:century, :decade, :year, :month, :week, :day]
  @clock_units [:hour, :minute, :second, :microsecond]

  # A label is read from a date rather than counted as a unit of its own:
  # the day of the week of a day, the day of the year, the quarter and the
  # season of a month, and a lunisolar calendar's name for a month. Its
  # grain is the unit that is enumerated to find it.
  @labels %{
    day_of_week: :day,
    day_of_year: :day,
    quarter: :month,
    season: :month,
    traditional_month: :month
  }

  # Coarsest first, as a value writes them; a label sorts where the unit it
  # labels does, after the unit that contains it.
  @order [
    :century,
    :decade,
    :year,
    :quarter,
    :season,
    :month,
    :traditional_month,
    :week,
    :day_of_year,
    :day,
    :day_of_week,
    :hour,
    :minute,
    :second,
    :microsecond
  ]

  # Each unit's place in that order, so that two units are compared, and a
  # list of them sorted, without a walk along it.
  @rank @order |> Enum.with_index() |> Map.new()

  # The unit a value's children are in, one below the unit it is written to.
  @child %{
    century: :year,
    decade: :year,
    year: :month,
    month: :day,
    week: :day,
    day: :hour,
    hour: :minute,
    minute: :second,
    second: :microsecond
  }

  # The units a value with no year runs through on its cycle, from the unit
  # it begins with down to a part of a second: the month and day of a year,
  # the week and weekday of a year, the weekday of a week, the hours of a day.
  @cycle_chains %{
    month: [:month, :day, :hour, :minute, :second, :microsecond],
    week: [:week, :day_of_week, :hour, :minute, :second, :microsecond],
    day_of_year: [:day_of_year, :hour, :minute, :second, :microsecond],
    day: [:day, :hour, :minute, :second, :microsecond],
    day_of_week: [:day_of_week, :hour, :minute, :second, :microsecond],
    hour: [:hour, :minute, :second, :microsecond],
    minute: [:minute, :second, :microsecond],
    second: [:second, :microsecond],
    microsecond: [:microsecond]
  }

  # The units a value is placed on the scale by as written, with no working out.
  @plain [:year, :month, :week, :day, :day_of_week, :day_of_year, :hour, :minute, :second]

  # The least a unit holds: the first month, day or week; the clock's zero.
  @minimum %{
    quarter: 1,
    month: 1,
    week: 1,
    day: 1,
    day_of_week: 1,
    day_of_year: 1,
    hour: 0,
    minute: 0,
    second: 0,
    microsecond: {0, 6}
  }

  @ticks %{
    microsecond: 1,
    second: 1_000_000,
    minute: 60_000_000,
    hour: 3_600_000_000
  }

  # The types are `Tempo`'s, where a value's form is documented.
  @type t :: Tempo.unit()
  @type units :: Tempo.units()
  @type selection :: Tempo.selection()
  @type held :: Tempo.held()

  @doc "Whether a unit is counted by the calendar: a year, a month, a week or a day."
  @spec calendar?(t()) :: boolean()
  def calendar?(unit), do: unit in @calendar_units

  @doc "Whether a unit is of the clock: an hour, a minute, a second or a part of one."
  @spec clock?(t()) :: boolean()
  def clock?(unit) when unit in @clock_units, do: true
  def clock?(_unit), do: false

  @doc "Whether a unit is a label read from a date, rather than a unit of its own."
  @spec label?(t()) :: boolean()
  def label?(unit), do: is_map_key(@labels, unit)

  @doc "The unit a value written to `unit` is made of: a year of months, a day of hours."
  @spec child(t()) :: t() | nil
  def child(unit), do: Map.get(@child, unit)

  @doc """
  Whether a unit may be written directly after another in one value: a month,
  a week, a season or a day of the year after a year; a day after a month; the
  clock after a day; a finer clock unit after a coarser.
  """
  @spec follows?(t() | :group, t() | :group) :: boolean()
  def follows?(unit, previous) when previous in [:century, :decade, :year],
    do: not clock?(unit) and compare(previous, unit) == :lt

  def follows?(unit, :week), do: unit in [:day_of_week, :group]

  def follows?(unit, previous) when previous in [:month, :season, :quarter, :traditional_month],
    do: unit in [:day, :group]

  def follows?(unit, previous) when previous in [:day, :day_of_week, :day_of_year],
    do: clock?(unit) or unit == :group

  def follows?(unit, previous) when previous in @clock_units,
    do: child(previous) == unit or unit == :group

  def follows?(_unit, _previous), do: false

  @doc """
  The leading units of a value an abbreviated end inherits, given the unit the
  end begins with: the start's chain of years, months, days and clock, cut
  where the end's first unit may follow (`follows?/2`).

  ### Examples

      iex> Tempo.Unit.inherited([year: 2026, month: 6, day: 15], :day)
      [year: 2026, month: 6]

      iex> Tempo.Unit.inherited([year: 2026, month: 6], :week)
      [year: 2026]

      iex> Tempo.Unit.inherited([year: 2026, season: 21], :month)
      [year: 2026]

  """
  @spec inherited(units(), t() | :group) :: units()
  def inherited(start_units, first) do
    start_units
    |> chained(first, nil)
    |> Enum.reverse()
    |> Enum.drop_while(fn {unit, _} -> not follows?(first, unit) end)
    |> Enum.reverse()
  end

  defp chained([{unit, held} | rest], first, previous) do
    if compare(unit, first) == :lt and (is_nil(previous) or follows?(unit, previous)) do
      [{unit, held} | chained(rest, first, unit)]
    else
      []
    end
  end

  defp chained([], _first, _previous), do: []

  @doc """
  Orders a caller's units coarsest first, refusing a key that is no unit,
  a unit given twice, or two units of one axis (a month and a week).

  ### Examples

      iex> Tempo.Unit.ordered(day: 15, year: 2026, month: 6)
      {:ok, [year: 2026, month: 6, day: 15]}

      iex> {:error, %ArgumentError{}} = Tempo.Unit.ordered(year: 2026, month: 6, week: 24)

  """
  @spec ordered(keyword()) :: {:ok, units()} | {:error, Exception.t()}
  def ordered(units) do
    keys = Enum.map(units, &ordered_as/1)

    cond do
      Enum.any?(keys, &(&1 not in @order)) ->
        {:error,
         argument("#{inspect(Enum.reject(keys, &(&1 in @order)))} are not units of a value")}

      keys != Enum.uniq(keys) ->
        {:error,
         argument("a unit is given once; #{inspect(keys -- Enum.uniq(keys))} are given twice")}

      not one_axis?(keys) ->
        {:error, argument("#{inspect(keys)} name a date two ways; a value is written one way")}

      true ->
        {:ok, Enum.sort_by(units, &rank(ordered_as(&1)))}
    end
  end

  # A group is written where the unit it groups is (`2026Y2G3MU`, two groups
  # of three months, after the year), and stands for that unit beside the rest.
  defp ordered_as({:group, {_nth, [{unit, size}]}}) when is_integer(size), do: unit
  defp ordered_as({unit, _held}), do: unit

  defp argument(message), do: ArgumentError.exception(message)

  # A year is divided one way: into months and days, weeks and weekdays,
  # days of the year, quarters or seasons.
  defp one_axis?(keys) do
    axes = [
      [:month, :day, :traditional_month],
      [:week, :day_of_week],
      [:day_of_year],
      [:quarter],
      [:season]
    ]

    Enum.count(axes, fn axis -> Enum.any?(keys, &(&1 in axis)) end) <= 1
  end

  @doc "The unit enumerated to find a label; a unit that is no label is its own grain."
  @spec grain(t()) :: t()
  def grain(unit), do: Map.get(@labels, unit, unit)

  @doc "A clock unit's length in ticks, which are microseconds."
  @spec ticks(:hour | :minute | :second | :microsecond) :: pos_integer()
  def ticks(unit), do: Map.fetch!(@ticks, unit)

  @doc "The units a value with no year runs through on its cycle, from its coarsest unit down."
  @spec cycle_chain(t()) :: [t()] | nil
  def cycle_chain(unit), do: Map.get(@cycle_chains, unit)

  @doc "The least value a unit holds."
  @spec minimum(t()) :: integer() | {0, 6}
  def minimum(unit), do: Map.fetch!(@minimum, unit)

  @doc "Every unit, coarsest first."
  @spec order() :: [t(), ...]
  def order, do: @order

  @doc "Orders two units: `:lt` when the first is the coarser."
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(unit, unit), do: :eq

  def compare(a, b) do
    if rank(a) < rank(b), do: :lt, else: :gt
  end

  @doc "A unit's place among the units, coarsest first, as `order/0` lists them; `nil` for what is no unit."
  @spec rank(term()) :: non_neg_integer() | nil
  def rank(unit), do: Map.get(@rank, unit)

  @doc """
  The finest unit a value is written to: its resolution. A value ending in a
  group is written to the group's unit, and one ending in a selection to the
  finest unit the selection names.
  """
  @spec resolution(units()) :: t()
  def resolution(units) do
    case List.last(units) do
      {:group, {_nth, duration}} ->
        resolution(duration)

      {:selection, parts} ->
        parts
        |> Enum.reject(&(elem(&1, 0) in [:instance, :event, :roll, :skip, :window]))
        |> resolution_of_parts(units)

      {unit, _} ->
        unit
    end
  end

  defp resolution_of_parts([], units), do: units |> Enum.drop(-1) |> resolution()
  defp resolution_of_parts(parts, _units), do: resolution(parts)

  @doc "The coarsest unit a value is written to."
  @spec coarsest(units()) :: t()
  def coarsest([{:group, {_nth, [{unit, _size}]}} | _]), do: unit
  def coarsest(units), do: units |> hd() |> elem(0)

  @doc """
  Whether a value has a year, a decade or a century, and so a place on the
  time line. A value's units are coarsest first (`ordered/1`), so it has one
  where its first unit is one: it is answered without a walk along them.
  """
  @spec anchored?(units()) :: boolean()
  def anchored?([{unit, _held} | _]) when unit in [:century, :decade], do: true
  def anchored?([{:year, held} | _]), do: held != :any
  def anchored?(_units), do: false

  @doc "The units with an unspecified year (`X*Y6M`) left off: what places a value on a cycle."
  @spec cyclic(units()) :: units()
  def cyclic([{:year, :any} | rest]), do: rest
  def cyclic(units), do: units

  @doc "Whether what a unit holds names one value, as a whole number does."
  @spec singular?(held()) :: boolean()
  def singular?(held) when is_integer(held), do: true
  def singular?({n, _annotation}) when is_integer(n), do: true
  def singular?(_held), do: false

  @doc "Whether every unit of a value holds one value."
  @spec concrete?(units()) :: boolean()
  def concrete?(units), do: Enum.all?(units, fn {_unit, held} -> singular?(held) end)

  @doc """
  Whether a value is placed on the scale as it stands: every unit one of the
  calendar's or the clock's own, holding a whole number counted from the
  start, a part of a second included. A count from the end, a group, a
  margin and a century are worked out first.
  """
  @spec plain?(units()) :: boolean()
  def plain?([]) do
    false
  end

  def plain?([_ | _] = units) do
    Enum.all?(units, &plain_unit?/1)
  end

  defp plain_unit?({:microsecond, {microseconds, precision}}),
    do: is_integer(microseconds) and is_integer(precision)

  defp plain_unit?({unit, n}) when is_integer(n), do: unit in @plain and (n >= 0 or unit == :year)
  defp plain_unit?(_other), do: false

  @doc "The units of a value that are of the date: before the first clock unit."
  @spec date_units(units()) :: units()
  def date_units(units), do: Enum.reject(units, fn {unit, _} -> clock?(unit) end)

  @doc "The units of a value that are of the clock."
  @spec clock_units(units()) :: units()
  def clock_units(units), do: Enum.filter(units, fn {unit, _} -> clock?(unit) end)
end
