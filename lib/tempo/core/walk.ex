defmodule Tempo.Walk do
  @moduledoc false

  # Stepping a span at a unit (section 6.6 of the plan): a calendar unit on
  # the day scale, through the calendar's periods; a clock unit on the tick
  # scale, each tick shown as a wall reading through the zone, so a day
  # across a change of the clock has 23 or 25 hours with nothing skipped or
  # doubled by hand. A span is given as its two positions on its frame; the
  # values stepped are concrete units, and the caller makes expressions of
  # them.

  alias Tempo.Calendar
  alias Tempo.Scale
  alias Tempo.Unit
  alias Tempo.Zone

  @day Scale.ticks_per_day()
  @second 1_000_000

  @type frame :: %{
          :calendar => module(),
          :zone => Zone.t() | nil,
          :shift => Zone.shift() | nil,
          optional(:frame) => Scale.frame()
        }

  @doc """
  The values of a unit a span holds, lazily and in order, half-open: for a
  calendar unit the periods its days fall in (`2026-02-15/2026-03-15` is
  February and March), for a clock unit each reading of the clock it
  touches (`T10:30/T12:30` is ten, eleven and twelve o'clock).
  """
  @spec steps({Scale.position(), Scale.position() | nil}, Unit.t(), frame()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  # A step is a value's units, or `{:shifted, units, shift}` for a reading a
  # zone's clock shows twice.
  def steps({start, stop}, unit, frame)
      when is_integer(start) and (is_integer(stop) or is_nil(stop)) do
    cond do
      clock_unit?(unit) -> {:ok, clock_steps(start, stop, unit, frame)}
      Unit.calendar?(unit) or unit == :quarter -> {:ok, day_steps(start, stop, unit, frame)}
      true -> {:error, {:no_walk, unit}}
    end
  end

  defp clock_unit?({:microsecond, _precision}), do: true
  defp clock_unit?(unit), do: Unit.clock?(unit)

  @doc "How many values of a unit a span holds, by the closed form where there is one."
  @spec count({Scale.position(), Scale.position()}, Unit.t(), frame()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  # In a named zone a unit of the clock is not always one unit long, so the
  # units are counted as the clock shows them (`counted/5`).
  def count({start, stop}, unit, %{zone: %Zone{name: name} = zone, shift: shift})
      when is_integer(start) and is_integer(stop) and unit in [:hour, :minute, :second] and
             is_binary(name) do
    {:ok, counted(start, stop, Unit.ticks(unit), {zone, shift}, 0)}
  end

  def count({start, stop}, unit, _frame)
      when is_integer(start) and is_integer(stop) and unit in [:hour, :minute, :second] do
    {:ok, div(stop - start, Unit.ticks(unit))}
  end

  def count(span, unit, frame) do
    with {:ok, steps} <- steps(span, unit, frame), do: {:ok, Enum.count(steps)}
  end

  # The units of the clock from a tick to an end, counted a day at a time.
  # Through a day in which the zone's offset does not change the units are
  # whole and are counted by their length; through a day in which it does,
  # each is stepped to where the clock leaves it.
  defp counted(tick, stop, _step, _zone, count) when tick >= stop, do: count

  defp counted(tick, stop, step, {zone, shift} = in_zone, count) do
    day_end = min(tick + @day, stop)
    offset = Zone.offset_at_utc(zone, tick)
    first_end = tick + step - Integer.mod(tick + offset, step)

    if Zone.offset_at_utc(zone, day_end) == offset and first_end <= day_end do
      whole = div(day_end - first_end, step)
      counted(first_end + whole * step, stop, step, in_zone, count + 1 + whole)
    else
      counted(Zone.unit_end(zone, shift, tick, step), stop, step, in_zone, count + 1)
    end
  end

  # ── Values at a place on the scale ────────────────────────────────────

  @doc "The units of a day on the day scale, written to a unit: the day's date, month, week or year."
  @spec at_day(integer(), Unit.t(), module()) :: Unit.units()
  def at_day(day, :day, calendar) do
    {y, m, d} = Calendar.date(calendar, day)
    [year: y, month: m, day: d]
  end

  def at_day(day, :month, calendar) do
    {y, m, _} = Calendar.date(calendar, day)
    [year: y, month: m]
  end

  def at_day(day, :year, calendar) do
    {y, _, _} = Calendar.date(calendar, day)
    [year: y]
  end

  def at_day(day, :decade, calendar),
    do: [decade: Integer.floor_div(at_day(day, :year, calendar)[:year], 10)]

  def at_day(day, :century, calendar),
    do: [century: Integer.floor_div(at_day(day, :year, calendar)[:year], 100)]

  def at_day(day, :week, calendar) do
    {y, m, d} = Calendar.date(calendar, day)
    {:ok, {wy, w}} = Calendar.week_of_year(calendar, y, m, d)
    [year: wy, week: w]
  end

  def at_day(day, :quarter, calendar) do
    {y, m, d} = Calendar.date(calendar, day)
    [year: y, quarter: Calendar.quarter_of_year(calendar, y, m, d)]
  end

  @doc "The units of a wall tick, written to a clock unit: the date and the clock down to the unit."
  @spec at_tick(integer(), Unit.t(), module()) :: Unit.units()
  def at_tick(wall, unit, calendar) do
    day = Integer.floor_div(wall, @day)
    at_day(day, :day, calendar) ++ clock_at(Integer.mod(wall, @day), unit)
  end

  @doc "The clock units of a tick within a day, down to a unit (`Tempo.Scale.clock_at/2`)."
  @spec clock_at(non_neg_integer(), Unit.t() | {:microsecond, 1..6}) :: Unit.units()
  defdelegate clock_at(ticks, unit), to: Scale

  # ── Steps ─────────────────────────────────────────────────────────────

  # The days of the span, each dated: within a month whose labels count its
  # days, by the count from the month's first day, the calendar asked once a
  # month (`Tempo.Calendar.month_of_day/2`); else each day's date asked. A
  # day the zone's clock leaves out is no day of a walk there.
  defp day_steps(start, stop, :day, %{calendar: calendar} = frame) do
    {first_day, last_day} = days_of(start, stop, frame)

    {first_day, nil}
    |> Stream.unfold(fn
      {day, _month} when not is_nil(last_day) and day > last_day ->
        nil

      {day, month} ->
        month = month_about(day, month, calendar)
        {{day, dated(day, month, calendar)}, {day + 1, month}}
    end)
    |> Stream.reject(fn {day, _value} -> day_skipped?(day, frame) end)
    |> Stream.map(fn {_day, value} -> value end)
  end

  # The periods of a calendar unit that begin in the span's days.
  defp day_steps(start, stop, unit, %{calendar: calendar} = frame) do
    {first_day, last_day} = days_of(start, stop, frame)

    first_day
    |> Stream.unfold(fn
      day when not is_nil(last_day) and day > last_day -> nil
      day -> {at_day(day, unit, calendar), next_period(day, unit, calendar)}
    end)
  end

  defp days_of(start, stop, frame) do
    first_day = Integer.floor_div(wall(start, frame), @day)
    last_day = if stop, do: Integer.floor_div(wall(stop, frame) - 1, @day), else: nil
    {first_day, last_day}
  end

  # The month a day is in: the one the day before was in, where it still is.
  defp month_about(day, %{first: first, after_last: after_last} = month, _calendar)
       when day >= first and day < after_last,
       do: month

  defp month_about(day, _other, calendar), do: Calendar.month_of_day(calendar, day)

  defp dated(
         day,
         %{counts?: true, year: year, month: month, first: first, label: label},
         _calendar
       ),
       do: [year: year, month: month, day: label + day - first]

  defp dated(day, _month, calendar), do: at_day(day, :day, calendar)

  # A day the zone's clock leaves out is no day of a walk there.
  defp day_skipped?(day, %{zone: zone, shift: shift}), do: Zone.day_skipped?(zone, shift, day)

  defp next_period(day, unit, calendar) do
    {_first, after_last} = period_of(at_day(day, unit, calendar), calendar)
    after_last
  end

  defp period_of([year: y], calendar), do: period!(calendar, :year, y, nil)
  defp period_of([year: y, month: m], calendar), do: period!(calendar, :month, y, m)
  defp period_of([year: y, week: w], calendar), do: period!(calendar, :week, y, w)
  defp period_of([year: y, quarter: q], calendar), do: period!(calendar, :quarter, y, q)
  defp period_of([decade: d], calendar), do: span_of_years(calendar, d * 10, d * 10 + 9)
  defp period_of([century: c], calendar), do: span_of_years(calendar, c * 100, c * 100 + 99)

  defp span_of_years(calendar, first, last) do
    {a, _} = period!(calendar, :year, first, nil)
    {_, b} = period!(calendar, :year, last, nil)
    {a, b}
  end

  defp period!(calendar, kind, year, part) do
    {:ok, span} = Calendar.period(calendar, kind, year, part)
    span
  end

  # The readings one clock unit apart; a tick's wall reading carries the offset it had.
  defp clock_steps(start, stop, unit, %{calendar: calendar} = frame) do
    step = step_of(unit)

    start
    |> Stream.iterate(&next_tick(&1, step, frame))
    |> Stream.take_while(fn tick -> is_nil(stop) or tick < stop end)
    |> Stream.map(fn tick -> reading(tick, written_unit(unit), calendar, frame) end)
  end

  # The next reading is where the clock leaves this one: the next whole unit,
  # except where a zone's clock changes within the unit
  # (`Tempo.Zone.unit_end/4`). A part of a second is below any change of a
  # clock, and of any offset.
  defp next_tick(tick, step, %{zone: zone, shift: shift}) when step >= @second,
    do: Zone.unit_end(zone, shift, tick, step)

  defp next_tick(tick, step, _frame), do: next_whole(tick, step)

  defp next_whole(tick, step) do
    Integer.floor_div(tick, step) * step + step
  end

  # A reading a named zone's clock shows twice is given with the offset it
  # had, `{:shifted, units, shift}`, so the two are two values; any other is
  # its units alone.
  defp reading(tick, unit, calendar, %{zone: %Zone{name: name} = zone, shift: nil})
       when is_binary(name) do
    {wall, offset} = Zone.wall_of_utc(zone, nil, tick)
    units = at_tick(wall, unit, calendar)

    case Zone.offsets_at_wall(zone, wall) do
      [_first, _second] -> {:shifted, units, Zone.shift_of(offset)}
      _one -> units
    end
  end

  defp reading(tick, unit, calendar, frame), do: at_tick(wall(tick, frame), unit, calendar)

  defp step_of({:microsecond, precision}), do: Integer.pow(10, 6 - precision)
  defp step_of(:microsecond), do: 1
  defp step_of(unit), do: Unit.ticks(unit)

  defp written_unit(:microsecond), do: {:microsecond, 6}
  defp written_unit(unit), do: unit

  @doc """
  The readings one clock unit apart on the day cycle, from a start to an end
  given as ticks from midnight; an end not after the start runs on through
  midnight (`T22H/T2H` is 22, 23, 0 and 1).
  """
  @spec cycle_clock_steps(integer(), integer(), Unit.t() | {:microsecond, 1..6}) :: Enumerable.t()
  def cycle_clock_steps(start, stop, unit) do
    step = step_of(unit)
    stop = if stop <= start, do: stop + @day, else: stop

    start
    |> Stream.iterate(&next_whole(&1, step))
    |> Stream.take_while(&(&1 < stop))
    |> Stream.map(&clock_at(rem(&1, @day), written_unit(unit)))
  end

  @doc "A position on the UTC line as the wall reading of the frame; a floating position is its own wall reading."
  @spec wall(integer(), frame()) :: integer()
  def wall(tick, %{zone: nil, shift: nil}), do: tick

  def wall(tick, %{zone: zone, shift: shift}) do
    {wall, _offset} = Zone.wall_of_utc(zone, shift, tick)
    wall
  end
end
