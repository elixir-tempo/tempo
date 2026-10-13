defmodule Tempo.Scale do
  @moduledoc false

  # Positions on the time line and on the cycles: where a value's span begins
  # and ends, as ticks (microseconds) from 0000-01-01 on the UTC or the
  # floating line, or from a cycle's start for a value with no year; the frame a
  # value lies on; and the comparison of two positions. Every relation and set
  # operation works on these positions, asking the calendar and the zone once
  # per end.

  # Positions and frames: where a value's span begins and ends, on the
  # frame it lies on.
  #
  # A value with a year lies on a line, the UTC line when it has a zone or
  # a written shift and the floating line when it has neither, and its
  # positions are ticks (microseconds since 0000-01-01). A value with no
  # year lies on the cycle of its coarsest unit, and its positions are
  # tuples of its units from that unit down to a part of a second, which
  # Erlang orders as the cycle does. Two positions compare only on one
  # frame; `Tempo.Algebra` and `Tempo.Allen` see to that.
  #
  # By law 3 a value's span is `[v, next(v))`. A span of a calendar
  # resolution ends where the next period begins on the calendar, each end
  # read on the clock of its own moment, so a day across a change of the
  # clock is 23 or 25 hours long. A span of a clock resolution is one unit
  # of elapsed time from its start.

  alias Tempo.Unit
  alias Tempo.Zone

  @day 86_400_000_000

  @type frame :: :utc | :floating | {:cycle, Unit.t()}
  @type position :: integer()

  @doc "The frame a value's units lie on, given its zone and shift."
  @spec frame(Unit.units(), Zone.t() | nil, Zone.shift() | nil) :: frame()
  def frame(units, zone, shift) do
    cond do
      Unit.cyclic(units) == [] -> {:cycle, :year}
      not Unit.anchored?(units) -> {:cycle, Unit.coarsest(Unit.cyclic(units))}
      zone != nil or shift != nil -> :utc
      true -> :floating
    end
  end

  @doc """
  The half-open extent of a concrete value: its start and its end on its
  frame. The units are concrete and coarsest first.
  """
  @spec extent(Unit.units(), module(), Zone.t() | nil, Zone.shift() | nil) ::
          {:ok, {position(), position()}} | {:error, term()}
  def extent(units, calendar, zone, shift) do
    case frame(units, zone, shift) do
      {:cycle, coarsest} -> cycle_extent(Unit.cyclic(units), coarsest, calendar)
      frame -> line_extent(units, calendar, zone, shift, frame)
    end
  end

  @doc """
  The extent of a value whose span of days is already known, with its clock
  units: the same reading as `extent/4` makes of plain units.
  """
  @spec extent_of({integer(), integer()}, Unit.units(), Zone.t() | nil, Zone.shift() | nil) ::
          {:ok, {position(), position()}}
  def extent_of({first, after_last}, clock_units, zone, shift) do
    frame = if zone != nil or shift != nil, do: :utc, else: :floating
    {:ok, line_extent_of({first, after_last}, clock_units, zone, shift, frame)}
  end

  @doc "The clock units of a tick within a day, down to a unit; a part of a second at the precision its step needs."
  @spec clock_at(non_neg_integer(), Unit.t() | {:microsecond, 1..6}) :: Unit.units()
  def clock_at(ticks, unit) do
    hour = div(ticks, Unit.ticks(:hour))
    minute = div(rem(ticks, Unit.ticks(:hour)), Unit.ticks(:minute))
    second = div(rem(ticks, Unit.ticks(:minute)), Unit.ticks(:second))
    microsecond = rem(ticks, Unit.ticks(:second))

    case unit do
      :hour ->
        [hour: hour]

      :minute ->
        [hour: hour, minute: minute]

      :second ->
        [hour: hour, minute: minute, second: second]

      {:microsecond, precision} ->
        [hour: hour, minute: minute, second: second, microsecond: {microsecond, precision}]
    end
  end

  @doc "Orders two positions of one frame."
  @spec compare(position(), position()) :: :lt | :eq | :gt
  def compare(a, b) when a < b, do: :lt
  def compare(a, b) when a > b, do: :gt
  def compare(_a, _b), do: :eq

  @doc "The ticks in a day."
  @spec ticks_per_day() :: 86_400_000_000
  def ticks_per_day, do: @day

  # ── A value on a line ─────────────────────────────────────────────────

  defp line_extent(units, calendar, zone, shift, frame) do
    date_units = Unit.date_units(units)
    clock_units = Unit.clock_units(units)

    with {:ok, span} <- Tempo.Calendar.span_of(calendar, date_units) do
      {:ok, line_extent_of(span, clock_units, zone, shift, frame)}
    end
  end

  defp line_extent_of({first, after_last}, clock_units, zone, shift, frame) do
    start_wall = first * @day + clock_ticks(clock_units)
    start = placed(start_wall, zone, shift, frame)

    stop =
      case clock_units do
        [] -> placed(after_last * @day, zone, shift, frame)
        _ -> start + resolution_ticks(clock_units)
      end

    {start, stop}
  end

  defp placed(wall, _zone, _shift, :floating), do: wall
  defp placed(wall, zone, shift, :utc), do: Zone.utc_of_wall(zone, shift, wall)

  defp clock_ticks(clock_units) do
    Enum.reduce(clock_units, 0, fn
      {:microsecond, {microseconds, _precision}}, sum -> sum + microseconds
      {unit, value}, sum -> sum + value * Unit.ticks(unit)
    end)
  end

  # One unit of the finest clock unit written: a second written to one
  # decimal place is a tenth of a second long.
  defp resolution_ticks(clock_units) do
    case List.last(clock_units) do
      {:microsecond, {_, precision}} -> Integer.pow(10, 6 - precision)
      {unit, _} -> Unit.ticks(unit)
    end
  end

  # ── A value on a cycle ────────────────────────────────────────────────

  # A position on a cycle is ticks from the cycle's start on the longest cycle
  # the calendar counts: a month cycle's days are the most each month has, so
  # every value has a place and two positions compare as numbers. A value with
  # no year that depends on the year (the 29th of a month that may have 28
  # days) still has a place; whether a year has it is asked of the walk.
  defp cycle_extent(units, coarsest, calendar) do
    case Unit.cycle_chain(coarsest) do
      nil -> {:error, {:no_cycle, coarsest}}
      _chain -> cycle_span(units, calendar)
    end
  end

  @doc "The half-open span of concrete units on their cycle, as ticks from the cycle's start."
  @spec cycle_span(Unit.units(), module()) :: {:ok, {integer(), integer()}} | {:error, term()}
  def cycle_span(units, calendar) do
    with {:ok, start} <- cycle_position(units, calendar),
         {:ok, step} <- cycle_step(List.last(units), calendar) do
      {:ok, {start, start + step}}
    end
  end

  @doc "The position of concrete units on their cycle, as ticks from the cycle's start."
  @spec cycle_position(Unit.units(), module()) :: {:ok, integer()} | {:error, term()}
  def cycle_position(units, calendar) do
    with {:ok, days} <- cycle_days(Unit.date_units(units), calendar) do
      {:ok, days * @day + clock_ticks(Unit.clock_units(units))}
    end
  end

  defp cycle_days([], _calendar), do: {:ok, 0}

  defp cycle_days([{:month, month} | rest], calendar) do
    with {:ok, before} <- days_before(calendar, month),
         {:ok, within} <- cycle_days(rest, calendar) do
      {:ok, before + within}
    end
  end

  defp cycle_days([{unit, n} | rest], calendar) when unit in [:day, :day_of_week, :day_of_year] do
    with {:ok, within} <- cycle_days(rest, calendar), do: {:ok, n - 1 + within}
  end

  defp cycle_days([{:week, week} | rest], calendar) do
    with {:ok, within} <- cycle_days(rest, calendar), do: {:ok, (week - 1) * 7 + within}
  end

  defp cycle_days(_units, _calendar), do: {:error, :needs_a_year}

  # The most days the months before a month have in any year.
  defp days_before(calendar, month) do
    Enum.reduce_while(1..(month - 1)//1, {:ok, 0}, fn m, {:ok, sum} ->
      case Tempo.Calendar.days_in_month_bounds(calendar, m) do
        {:error, _} -> {:halt, {:error, :needs_a_year}}
        {_fewest, most} -> {:cont, {:ok, sum + most}}
      end
    end)
  end

  # One unit of the finest written: a month its most days, a week seven, a day one, a clock unit its ticks.
  defp cycle_step({:month, month}, calendar) do
    case Tempo.Calendar.days_in_month_bounds(calendar, month) do
      {:error, _} -> {:error, :needs_a_year}
      {_fewest, most} -> {:ok, most * @day}
    end
  end

  defp cycle_step({:week, _}, _calendar), do: {:ok, 7 * @day}

  defp cycle_step({unit, _}, _calendar) when unit in [:day, :day_of_week, :day_of_year],
    do: {:ok, @day}

  defp cycle_step({:microsecond, {_, precision}}, _calendar),
    do: {:ok, Integer.pow(10, 6 - precision)}

  defp cycle_step({unit, _}, _calendar), do: {:ok, Unit.ticks(unit)}

  @doc """
  The length of a cycle in ticks: the day for a time of day, the week for a
  weekday, the longest year the calendar counts for a month or a day of the
  year, the longest month for a day.
  """
  @spec cycle_length(Unit.t(), module()) :: {:ok, integer()} | {:error, term()}
  def cycle_length(:month, calendar) do
    case Tempo.Calendar.months_in_year_bounds(calendar) do
      {:error, _} ->
        {:error, :needs_a_year}

      {_fewest, most} ->
        with {:ok, days} <- days_before(calendar, most + 1), do: {:ok, days * @day}
    end
  end

  def cycle_length(:day, calendar) do
    case Tempo.Calendar.months_in_year_bounds(calendar) do
      {:error, _} -> {:error, :needs_a_year}
      {_fewest, most} -> {:ok, longest_month(calendar, most) * @day}
    end
  end

  def cycle_length(:day_of_week, calendar),
    do: {:ok, Tempo.Calendar.days_in_week(calendar) * @day}

  def cycle_length(:week, _calendar), do: {:ok, 53 * 7 * @day}
  def cycle_length(:day_of_year, calendar), do: cycle_length(:month, calendar)
  def cycle_length(_clock, _calendar), do: {:ok, @day}

  defp longest_month(calendar, months) do
    1..months
    |> Enum.map(fn month ->
      case Tempo.Calendar.days_in_month_bounds(calendar, month) do
        {:error, _} -> 0
        {_fewest, most} -> most
      end
    end)
    |> Enum.max()
  end

  @doc """
  The concrete units a position on a cycle names, down to a resolution: the
  inverse of `cycle_position/2`.
  """
  @spec cycle_units(integer(), Unit.t(), Unit.t() | {:microsecond, 1..6}, module()) ::
          Unit.units()
  def cycle_units(ticks, coarsest, resolution, calendar) do
    days = Integer.floor_div(ticks, @day)
    clock = Integer.mod(ticks, @day)
    date = cycle_date(days, coarsest, calendar)

    Enum.take_while(date, fn {unit, _} -> Unit.compare(unit, unit_of(resolution)) != :gt end) ++
      clock_part(clock, resolution)
  end

  defp unit_of({:microsecond, _}), do: :microsecond
  defp unit_of(unit), do: unit

  defp cycle_date(days, :month, calendar) do
    month =
      Enum.find(1..40, 1, fn m ->
        match?({:ok, before} when before > days, days_before(calendar, m + 1))
      end)

    {:ok, before} = days_before(calendar, month)
    [month: month, day: days - before + 1]
  end

  defp cycle_date(days, :week, _calendar),
    do: [week: div(days, 7) + 1, day_of_week: rem(days, 7) + 1]

  defp cycle_date(days, :day, _calendar), do: [day: days + 1]
  defp cycle_date(days, :day_of_week, _calendar), do: [day_of_week: days + 1]
  defp cycle_date(days, :day_of_year, _calendar), do: [day_of_year: days + 1]
  defp cycle_date(_days, _clock, _calendar), do: []

  defp clock_part(_clock, resolution)
       when resolution in [:month, :week, :day, :day_of_week, :day_of_year], do: []

  defp clock_part(clock, resolution), do: clock_at(clock, resolution)
end
