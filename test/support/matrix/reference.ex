defmodule Tempo.Matrix.Reference do
  @moduledoc """
  What a core value means, worked out from the numbers it is built from
  (see `plans/validated-core.md`).

  A datum is a core value as data: the whole numbers of a date, of a time
  of day or of both, with the zone and the calendar they are written in.
  This module computes, from a datum alone and with `Date`,
  `NaiveDateTime`, `DateTime`, `Time` and a calendar module's own
  functions, the span the value covers, the values its walk yields and the
  Elixir value it converts to. Nothing here calls `Tempo`, so an answer of
  `Tempo`'s that equals one of these is evidence about `Tempo`.

  A span is an extent, as `Tempo.Matrix.Extent` measures one: half-open
  pairs of microseconds on a line, the time line for a value with a zone,
  the wall clock of no zone for a value without, and the day for a time of
  day with no date.

  """

  alias Calendar.ISO

  @microseconds 1_000_000
  @day 86_400 * @microseconds

  @typedoc """
  A date, a time of day or a date and time, as data.

  * `:date` is the date's units in order: none, a year, a year and month,
    a year, month and day, a year and week, a year, week and day of the
    week, or a year and day of the year.

  * `:time` is the time of day's units in order: none, an hour, an hour
    and minute, or an hour, minute and second.

  * `:fraction` is a decimal fraction of the second as `{digits, count}`
    (`{5, 1}` is `.5` and `{250, 3}` is `.250`), or `nil`.

  * `:zone` is `nil`, `:utc`, `{:offset, minutes}` or `{:zone, name}`.

  * `:calendar` is the calendar module the date is written in.

  """
  @type point :: %{
          date: keyword(integer()),
          time: keyword(integer()),
          fraction: {non_neg_integer(), pos_integer()} | nil,
          zone: nil | :utc | {:offset, integer()} | {:zone, String.t()},
          calendar: module()
        }

  @type extent :: Tempo.Matrix.Extent.t()

  ## The span

  @doc """
  The span a point covers.

  ### Arguments

  * `point` is a `t:point/0`.

  ### Returns

  * `{:ok, extent}`, or `:none` for a wall time its zone does not have or
    has twice, which the datum does not say enough to place.

  """
  @spec span(point()) :: {:ok, extent()} | :none
  def span(%{date: []} = point) do
    {from, to} = clock_span(point)
    {:ok, %{line: {:cycle, :hour}, spans: on_day(from, to), whole?: true}}
  end

  def span(point) do
    {from, to} = wall_span(point)

    with {:ok, from} <- position(from, point.zone),
         {:ok, to} <- position(to, point.zone) do
      {:ok, %{line: line(point.zone), spans: nonempty(from, to), whole?: true}}
    end
  end

  @doc """
  The start of a point's span, as `span/1` places it.

  ### Arguments

  * `point` is a `t:point/0`.

  ### Returns

  * `{:ok, line, microseconds}` or `:none`.

  """
  @spec start(point()) :: {:ok, Tempo.Matrix.Extent.line(), integer()} | :none
  def start(%{date: []} = point), do: {:ok, {:cycle, :hour}, elem(clock_span(point), 0)}

  def start(point) do
    {from, _to} = wall_span(point)
    with {:ok, from} <- position(from, point.zone), do: {:ok, line(point.zone), from}
  end

  @doc """
  The span from the start of one point to the start of another: an
  interval's.

  ### Arguments

  * `from` and `to` are `t:point/0`.

  ### Returns

  * `{:ok, extent}`, or `:none` when either has no place or they lie on
    two lines.

  """
  @spec between(point(), point()) :: {:ok, extent()} | :none
  def between(from, to) do
    with {:ok, line, from} <- start(from),
         {:ok, ^line, to} <- start(to) do
      {:ok, %{line: line, spans: nonempty(from, to), whole?: true}}
    else
      _no_place -> :none
    end
  end

  @doc """
  The spans a point's walk yields: the point's span cut into the unit
  after its last.

  A year is walked by its months, a month by its days, a week by its days,
  a day by its hours, an hour by its minutes, a minute by its seconds and a
  second by the next decimal place.

  ### Arguments

  * `point` is a `t:point/0`.

  ### Returns

  * `{:ok, [extent]}` in order, or `:none`.

  """
  @spec parts(point()) :: {:ok, [extent()]} | :none
  def parts(point) do
    point
    |> finer()
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, spans} ->
      case span(part) do
        {:ok, span} -> {:cont, {:ok, [span | spans]}}
        :none -> {:halt, :none}
      end
    end)
    |> case do
      {:ok, spans} -> {:ok, Enum.reverse(spans)}
      :none -> :none
    end
  end

  @doc """
  The points a point's walk yields.

  ### Arguments

  * `point` is a `t:point/0`.

  ### Returns

  * A list of `t:point/0`, in order.

  """
  @spec finer(point()) :: [point()]
  def finer(%{time: [], date: [year: year]} = point) do
    for month <- 1..months_in_year(year, point.calendar),
        do: %{point | date: [year: year, month: month]}
  end

  def finer(%{time: [], date: [year: year, month: month]} = point) do
    for day <- 1..days_in_month(year, month, point.calendar),
        do: %{point | date: [year: year, month: month, day: day]}
  end

  def finer(%{time: [], date: [year: year, week: week]} = point) do
    for day <- 1..7, do: %{point | date: [year: year, week: week, day_of_week: day]}
  end

  def finer(%{time: []} = point), do: for(hour <- 0..23, do: %{point | time: [hour: hour]})

  def finer(%{time: [hour: hour]} = point),
    do: for(minute <- 0..59, do: %{point | time: [hour: hour, minute: minute]})

  def finer(%{time: [hour: hour, minute: minute], fraction: nil} = point) do
    for second <- 0..59, do: %{point | time: [hour: hour, minute: minute, second: second]}
  end

  def finer(%{time: [hour: _, minute: _, second: _], fraction: nil} = point),
    do: for(tenth <- 0..9, do: %{point | fraction: {tenth, 1}})

  def finer(%{time: [hour: _, minute: _, second: _], fraction: {value, digits}} = point)
      when digits < 6 do
    for next <- 0..9, do: %{point | fraction: {value * 10 + next, digits + 1}}
  end

  ## Stepping

  @doc """
  A point a count of its own last unit on, written as it is: a day a week
  of days on is a day, on the axis the point is on.

  ### Arguments

  * `point` is a `t:point/0` with a date and no fraction of a second.

  * `count` is the units to step by, which may be negative.

  ### Returns

  * A `t:point/0` of the same units.

  """
  @spec stepped(point(), integer()) :: point()
  def stepped(%{time: [], date: date} = point, count) do
    {unit, _value} = List.last(date)
    %{point | date: dated(date, Date.shift(first_date(point), [{date_unit(unit), count}]))}
  end

  def stepped(%{time: time, date: date, fraction: nil} = point, count) do
    {unit, _value} = List.last(time)
    {from, _to} = wall_span(point)
    moved = NaiveDateTime.shift(from, [{unit, count}])
    day = dated(date, NaiveDateTime.to_date(moved))
    clock = Enum.map(time, fn {present, _value} -> {present, Map.fetch!(moved, present)} end)

    %{point | date: day, time: clock}
  end

  defp date_unit(unit) when unit in [:day_of_week, :day_of_year], do: :day
  defp date_unit(unit), do: unit

  # A proleptic Gregorian date in the units a date is written in.
  defp dated([year: _], %Date{year: year}), do: [year: year]
  defp dated([year: _, month: _], %Date{year: year, month: month}), do: [year: year, month: month]

  defp dated([year: _, month: _, day: _], %Date{} = date),
    do: [year: date.year, month: date.month, day: date.day]

  defp dated([year: _, day_of_year: _], %Date{} = date),
    do: [year: date.year, day_of_year: Date.day_of_year(date)]

  defp dated([{:year, _year}, {:week, _week} | day], %Date{} = date) do
    {year, week} = :calendar.iso_week_number(Date.to_erl(date))
    weekday = if day == [], do: [], else: [day_of_week: Date.day_of_week(date)]

    [year: year, week: week] ++ weekday
  end

  ## The wall clock

  @doc """
  The wall clock times a point's span starts and ends at, in the proleptic
  Gregorian calendar.

  ### Arguments

  * `point` is a `t:point/0` with a date.

  ### Returns

  * `{from, to}`, each a `t:NaiveDateTime.t/0` with microsecond precision.

  """
  @spec wall_span(point()) :: {NaiveDateTime.t(), NaiveDateTime.t()}
  def wall_span(%{time: []} = point) do
    {midnight(first_date(point)), midnight(next_date(point))}
  end

  def wall_span(point) do
    {from, to} = clock_span(point)
    midnight = midnight(first_date(point))

    {NaiveDateTime.add(midnight, from, :microsecond),
     NaiveDateTime.add(midnight, to, :microsecond)}
  end

  @doc """
  The first day a point's date covers, as a proleptic Gregorian date.

  ### Arguments

  * `point` is a `t:point/0` with a date.

  ### Returns

  * A `t:Date.t/0` in `Calendar.ISO`.

  """
  @spec first_date(point()) :: Date.t()
  def first_date(%{date: date, calendar: calendar}), do: first_date(date, calendar)

  defp first_date([year: year], calendar), do: date(year, 1, 1, calendar)
  defp first_date([year: year, month: month], calendar), do: date(year, month, 1, calendar)

  defp first_date([year: year, month: month, day: day], calendar),
    do: date(year, month, day, calendar)

  defp first_date([year: year, week: week], _calendar), do: week_start(year, week)

  defp first_date([year: year, week: week, day_of_week: day], _calendar),
    do: Date.add(week_start(year, week), day - 1)

  defp first_date([year: year, day_of_year: day], _calendar),
    do: Date.add(Date.new!(year, 1, 1), day - 1)

  # The day after the last a point's date covers.
  defp next_date(%{date: [year: year], calendar: calendar}), do: date(year + 1, 1, 1, calendar)

  defp next_date(%{date: [year: year, month: month], calendar: calendar}) do
    if month == months_in_year(year, calendar),
      do: date(year + 1, 1, 1, calendar),
      else: date(year, month + 1, 1, calendar)
  end

  defp next_date(%{date: [year: _, week: _]} = point), do: Date.add(first_date(point), 7)
  defp next_date(point), do: Date.add(first_date(point), 1)

  # ISO 8601-1 §4.2.2: weeks begin on Monday, and a year's first week is the
  # one that holds its 4 January.
  defp week_start(year, week) do
    year
    |> Date.new!(1, 4)
    |> Date.beginning_of_week(:monday)
    |> Date.add((week - 1) * 7)
  end

  defp date(year, month, day, Calendrical.Gregorian), do: Date.new!(year, month, day)

  defp date(year, month, day, calendar),
    do: year |> Date.new!(month, day, calendar) |> Date.convert!(ISO)

  @doc """
  The months a year has in a calendar.

  ### Arguments

  * `year` is a year of `calendar`.

  * `calendar` is a calendar module.

  ### Returns

  * A positive integer.

  """
  @spec months_in_year(integer(), module()) :: pos_integer()
  def months_in_year(_year, Calendrical.Gregorian), do: 12
  def months_in_year(year, calendar), do: calendar.months_in_year(year)

  @doc """
  The days a month has in a calendar.

  ### Arguments

  * `year` and `month` are a month of `calendar`.

  * `calendar` is a calendar module.

  ### Returns

  * A positive integer.

  """
  @spec days_in_month(integer(), pos_integer(), module()) :: pos_integer()
  def days_in_month(year, month, Calendrical.Gregorian),
    do: ISO.days_in_month(year, month)

  def days_in_month(year, month, calendar), do: calendar.days_in_month(year, month)

  defp midnight(date), do: NaiveDateTime.new!(date, Time.new!(0, 0, 0, {0, 6}))

  # The microseconds after midnight a point's time of day starts and ends
  # at: the unit after its last is the hour, the minute, the second or the
  # decimal place it is written to.
  defp clock_span(%{time: time, fraction: fraction}) do
    seconds = (time[:hour] || 0) * 3_600 + (time[:minute] || 0) * 60 + (time[:second] || 0)
    from = seconds * @microseconds + fraction_microseconds(fraction)
    {from, from + unit_microseconds(time, fraction)}
  end

  defp fraction_microseconds(nil), do: 0
  defp fraction_microseconds({value, digits}), do: value * Integer.pow(10, 6 - digits)

  defp unit_microseconds(_time, {_value, digits}), do: Integer.pow(10, 6 - digits)
  defp unit_microseconds([hour: _], nil), do: 3_600 * @microseconds
  defp unit_microseconds([hour: _, minute: _], nil), do: 60 * @microseconds
  defp unit_microseconds([hour: _, minute: _, second: _], nil), do: @microseconds

  ## Positions

  defp line(nil), do: :floating
  defp line(_zone), do: :time

  defp position(naive, nil), do: {:ok, gregorian(naive)}
  defp position(naive, :utc), do: {:ok, gregorian(naive)}

  defp position(naive, {:offset, minutes}),
    do: {:ok, gregorian(naive) - minutes * 60 * @microseconds}

  # A wall time a zone's clocks skip, or show twice, is no one moment.
  defp position(naive, {:zone, name}) do
    case DateTime.from_naive(naive, name) do
      {:ok, %DateTime{utc_offset: utc, std_offset: std}} ->
        {:ok, gregorian(naive) - (utc + std) * @microseconds}

      _gap_or_ambiguous ->
        :none
    end
  end

  defp gregorian(naive) do
    {seconds, microseconds} = NaiveDateTime.to_gregorian_seconds(naive)
    seconds * @microseconds + microseconds
  end

  defp nonempty(from, to) when from < to, do: [{from, to}]
  defp nonempty(_from, _to), do: []

  # A time of day lies on the day, and a span that runs through midnight
  # is cut there.
  defp on_day(from, to) when to <= @day, do: [{from, to}]
  defp on_day(from, to), do: [{0, to - @day}, {from, @day}]

  ## Elixir values

  @doc """
  The Elixir value a point is: a `Date` for a day, a `Time` for a time of
  day to the second, a `NaiveDateTime` for a date and such a time with no
  zone, and a `DateTime` for one with a zone.

  A second with no fraction has a precision of zero, as it has when
  Elixir reads it from ISO 8601 text (`~T[10:30:45]`).

  ### Arguments

  * `point` is a `t:point/0`.

  ### Returns

  * `{:ok, value}`, or `:none` for a point no Elixir type holds: a year, a
    month, a week, an hour or a minute.

  """
  @spec elixir(point()) :: {:ok, Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t()} | :none
  def elixir(%{time: []} = point), do: elixir_date(point)

  def elixir(%{date: [], time: [hour: hour, minute: minute, second: second]} = point),
    do: {:ok, Time.new!(hour, minute, second, precision(point.fraction))}

  def elixir(%{time: [hour: _, minute: _, second: _], zone: nil} = point), do: naive(point)
  def elixir(%{time: [hour: _, minute: _, second: _]} = point), do: datetime(point)
  def elixir(_point), do: :none

  @doc """
  The `Date` a point of a day is, in its own calendar.

  ### Arguments

  * `point` is a `t:point/0`.

  ### Returns

  * `{:ok, date}`, or `:none` for a point that is not one day.

  """
  @spec elixir_date(point()) :: {:ok, Date.t()} | :none
  def elixir_date(%{date: [year: year, month: month, day: day], calendar: calendar}) do
    case calendar do
      Calendrical.Gregorian -> {:ok, Date.new!(year, month, day)}
      calendar -> {:ok, Date.new!(year, month, day, calendar)}
    end
  end

  def elixir_date(%{date: [year: _, week: _, day_of_week: _]} = point),
    do: {:ok, first_date(point)}

  def elixir_date(%{date: [year: _, day_of_year: _]} = point), do: {:ok, first_date(point)}
  def elixir_date(_point), do: :none

  @doc """
  The `NaiveDateTime` a point of a date and a time to the second is, its
  zone left out.

  ### Arguments

  * `point` is a `t:point/0`.

  ### Returns

  * `{:ok, naive_datetime}` or `:none`.

  """
  @spec naive(point()) :: {:ok, NaiveDateTime.t()} | :none
  def naive(%{time: [hour: hour, minute: minute, second: second]} = point) do
    with {:ok, date} <- elixir_date(%{point | time: []}) do
      {:ok, NaiveDateTime.new!(date, Time.new!(hour, minute, second, precision(point.fraction)))}
    end
  end

  def naive(_point), do: :none

  @doc """
  The `DateTime` a point with a zone is: in its zone when it names one,
  and in UTC when it is written with an offset.

  ### Arguments

  * `point` is a `t:point/0`.

  ### Returns

  * `{:ok, datetime}` or `:none`.

  """
  @spec datetime(point()) :: {:ok, DateTime.t()} | :none
  def datetime(%{zone: nil}), do: :none

  def datetime(%{zone: {:zone, name}} = point) do
    with {:ok, naive} <- naive(point),
         {:ok, datetime} <- DateTime.from_naive(naive, name) do
      {:ok, datetime}
    else
      _no_one_moment -> :none
    end
  end

  def datetime(%{zone: zone} = point) do
    with {:ok, naive} <- naive(point) do
      naive
      |> NaiveDateTime.add(-offset_seconds(zone), :second)
      |> DateTime.from_naive("Etc/UTC")
    end
  end

  defp offset_seconds(:utc), do: 0
  defp offset_seconds({:offset, minutes}), do: minutes * 60

  defp precision(nil), do: {0, 0}
  defp precision({value, digits}), do: {value * Integer.pow(10, 6 - digits), digits}
end
