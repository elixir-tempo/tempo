defmodule Tempo.Expand do
  @moduledoc false

  # The values a unit takes under a concrete prefix, and the expansion of a
  # value's units into every concrete value they allow (section 6.5 of the
  # plan). This is the one engine for a set in a unit, a mask, a count from
  # the end, a group, a gap between units and, in a later phase, a selection.
  #
  # A calendar unit's children are found by walking the prefix's span on the
  # day scale period by period, asking the calendar which period holds a day
  # and where it ends; a label (a day of the week, a day of the year) is read
  # from each day. A clock unit's children are the ticks of the prefix's
  # extent on its frame, stepped and shown as wall readings through the zone,
  # so a day across a change of the clock has 23 or 25 hours with nothing
  # done by hand. A prefix with no year has children only where every year
  # counts the same (`Tempo.Calendar.days_in_month_bounds/2`).

  alias Tempo.Calendar
  alias Tempo.ConversionError
  alias Tempo.Scale
  alias Tempo.Season
  alias Tempo.Unit
  alias Tempo.Zone

  @typedoc "A frame: the calendar, zone and shift an expression is in."
  @type frame :: %{
          :calendar => module(),
          :zone => Zone.t() | nil,
          :shift => Zone.shift() | nil,
          optional(:frame) => Scale.frame()
        }

  @typedoc "A child: its value, and its span on the day scale (days) or the tick scale (ticks); nil on a cycle."
  @type child :: {term(), {integer(), integer()} | nil}

  # ── One span or many ──────────────────────────────────────────────────

  @doc """
  Whether concrete units name one span: each unit held as one value, each
  within the one before it (a month in a year, a day in a month, an hour in
  a day), with no gap a calendar would fill several ways.
  """
  @spec one_span?(Unit.units()) :: boolean()
  def one_span?(units) do
    units = Unit.cyclic(units)

    Unit.concrete?(units) and annotation_last?(units) and
      units
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [{parent, held}, {child, _}] -> single?(parent, held, child) end) and
      (units == [] or match?([{unit, _} | _] when unit in [:century, :decade, :year], units) or
         not Unit.anchored?(units))
  end

  # A year with significant digits or a margin is one span alone; with units under it, one per year.
  defp annotation_last?(units) do
    units
    |> Enum.drop(-1)
    |> Enum.all?(fn
      {_unit, {n, [{kind, _}]}} when is_integer(n) and kind in [:significant, :margin] -> false
      _ -> true
    end)
  end

  # A label names one span only within the period it is a label of: a day
  # of the week within a week, a day of the year within a year.
  defp single?(parent, _held, :day_of_week), do: parent == :week
  defp single?(:group, _held, child), do: child not in [:day_of_year]
  defp single?(parent, _held, :day_of_year), do: parent == :year
  defp single?(parent, held, child), do: contains?(parent, held, child)

  # The units a unit directly holds, so that a value written with both is one span.
  defp contains?(unit, _held, child) when unit in [:century, :decade], do: child == :year

  defp contains?(:year, _held, child),
    do:
      child in [
        :month,
        :week,
        :day_of_year,
        :day_of_week,
        :quarter,
        :season,
        :traditional_month,
        :group
      ]

  # A day of the year written after a month is a label of that month's
  # days: `3M80O` is the eightieth day of the year, if it is in March.
  defp contains?(unit, _held, child) when unit in [:month, :traditional_month, :quarter],
    do: child in [:day, :week, :day_of_week, :day_of_year, :group]

  defp contains?(:week, _held, child), do: child in [:day_of_week, :group]

  # A day of the week or of the year written after a day is that day's
  # label, with no gap between them to fill: `13D5K` is a thirteenth that is
  # a Friday.
  defp contains?(:day, _held, child), do: child in [:hour, :group, :day_of_week, :day_of_year]
  defp contains?(:day_of_year, _held, child), do: child in [:hour, :group, :day_of_week]

  defp contains?(:day_of_week, _held, child), do: child in [:hour, :group]

  defp contains?(:hour, _held, child), do: child in [:minute, :group]
  defp contains?(:minute, _held, child), do: child in [:second, :group]
  defp contains?(:second, _held, child), do: child == :microsecond

  defp contains?(:group, {_nth, [{unit, _}]}, child),
    do: contains?(unit, nil, child) or child == unit

  defp contains?(_unit, _held, _child), do: false

  @doc """
  The units with the gaps between them filled by `:any`, so that `2026YT17H`
  is every day's seventeenth hour and `2026Y15D` the fifteenth of every month.
  """
  @spec filled(Unit.units()) :: Unit.units()
  def filled([]), do: []

  def filled([{unit, held} | rest]) do
    [{unit, held} | fill_from(unit, held, rest)]
  end

  defp fill_from(_unit, _held, []), do: []

  defp fill_from(unit, held, [{next, next_held} | rest]) do
    cond do
      contains?(unit, held, next) ->
        [{next, next_held} | fill_from(next, next_held, rest)]

      Unit.child(unit) == nil ->
        [{next, next_held} | fill_from(next, next_held, rest)]

      true ->
        child = filler(unit)
        [{child, :any} | fill_from(child, :any, [{next, next_held} | rest])]
    end
  end

  # The unit a gap under a unit is filled with: a week's is its weekday.
  defp filler(:week), do: :day_of_week
  defp filler(unit), do: Unit.child(unit)

  @doc """
  A prefix with the units between its last and a unit filled with their first
  values: `[year: 2026, month: 6]` down to `:hour` is the first day's clock.
  """
  @spec filled_to(Unit.units(), Unit.t()) :: Unit.units()
  def filled_to(prefix, unit) do
    {last, _} = List.last(prefix) || {nil, nil}

    if last == nil or contains?(last, Keyword.get(prefix, last), unit) do
      prefix
    else
      case filler(last) do
        nil -> prefix
        child -> filled_to(prefix ++ [{child, Unit.minimum(child)}], unit)
      end
    end
  end

  # ── The day span of a concrete prefix ─────────────────────────────────

  @doc """
  The span of days a concrete prefix of date units names, on the day scale.
  A plain form is the calendar's period; a century or a decade is its years;
  a quarter, a traditional month and a group are what the calendar's periods
  make of them; a season is the days `Tempo.Season` gives it.
  """
  @spec day_span(module(), Unit.units()) ::
          {:ok, Calendar.span()} | {:error, ConversionError.reason()}
  def day_span(_calendar, []), do: {:error, :needs_a_year}

  def day_span(calendar, century: c) when is_integer(c), do: years_span(calendar, c, 100)
  def day_span(calendar, decade: d) when is_integer(d), do: years_span(calendar, d, 10)

  # A year with significant digits is the years its digits leave open; one with a margin is the years either side.
  def day_span(calendar, year: {y, [significant: n]}) when is_integer(y) do
    width = Integer.pow(10, max(Integer.digits(abs(y)) |> length() |> Kernel.-(n), 0))
    first = div(y, width) * width
    years(calendar, first, first + width - 1)
  end

  def day_span(calendar, year: {y, [margin: m]}) when is_integer(y),
    do: years(calendar, y - m, y + m)

  def day_span(calendar, year: y, quarter: q) when is_integer(y) and is_integer(q),
    do: calendar_answer(Calendar.period(calendar, :quarter, y, q))

  def day_span(calendar, year: y, season: s) when is_integer(y) and is_integer(s),
    do: Season.day_span(calendar, y, s)

  def day_span(_calendar, year: _y, season: _s), do: {:error, :season}

  def day_span(calendar, [year: y, traditional_month: named] = prefix) when is_integer(y) do
    case Calendar.month_from_traditional(calendar, y, unwrap(named)) do
      {:error, _} -> {:error, {:no_such_value, prefix}}
      month -> day_span(calendar, year: y, month: month)
    end
  end

  def day_span(calendar, prefix) do
    if Unit.plain?(prefix) do
      calendar_answer(Calendar.span_of(calendar, prefix))
    else
      resolved_span(calendar, prefix)
    end
  end

  # The last unit found among the children of the units before it.
  defp resolved_span(calendar, prefix) do
    {before, [{unit, held}]} = Enum.split(prefix, -1)
    frame = %{calendar: calendar, zone: nil, shift: nil}

    with :ok <- of_days(unit, held),
         {:ok, candidates} <- candidates(before, unit, held, frame) do
      case candidates do
        [{_value, {first, after_last}}] when is_integer(first) -> {:ok, {first, after_last}}
        [] -> {:error, {:no_such_value, prefix}}
        _several -> {:error, {:several, prefix}}
      end
    end
  end

  defp of_days(:group, {_nth, [{unit, _size}]}),
    do: if(Unit.clock?(unit), do: {:error, :clock_group}, else: :ok)

  defp of_days(_unit, _held), do: :ok

  @doc """
  The children a unit's held shape selects under a prefix: a group's are the
  groups of its size among the children of its unit, numbered from one.
  """
  @spec candidates(Unit.units(), Unit.t() | :group, Unit.held(), frame()) ::
          {:ok, [child()]} | {:error, ConversionError.reason()}
  def candidates(prefix, :group, {nth, [{unit, size}] = size_units}, frame)
      when is_integer(size) and size > 0 do
    with {:ok, children} <- children(prefix, unit, frame) do
      groups =
        children
        |> Enum.chunk_every(size)
        |> Enum.with_index(1)
        |> Enum.map(fn {chunk, index} -> {index, chunk_span(chunk)} end)

      {:ok, for({index, span} <- select(nth, groups), do: {{index, size_units}, span})}
    end
  end

  def candidates(_prefix, :group, held, _frame), do: {:error, {:group_size, held}}

  def candidates(prefix, unit, held, frame) do
    with {:ok, children} <- children(prefix, unit, frame), do: {:ok, select(held, children)}
  end

  defp chunk_span([{_, {first, _}} | _] = chunk) do
    case List.last(chunk) do
      {_, {_, after_last}} -> {first, after_last}
      _ -> nil
    end
  end

  defp chunk_span(_chunk), do: nil

  defp unwrap({n, :leap}), do: {n, :leap}
  defp unwrap({n, _annotation}) when is_integer(n), do: n
  defp unwrap(n), do: n

  defp calendar_answer({:ok, span}), do: {:ok, span}
  defp calendar_answer({:error, reason}), do: {:error, {:no_such_value, reason}}

  # `20C` is the years 2000 to 2099 and `-19C` the years -1999 to -1900 (ISO 8601-2 §4.4.1.8).
  defp years_span(calendar, n, width) when n >= 0,
    do: years(calendar, n * width, n * width + width - 1)

  defp years_span(calendar, n, width), do: years(calendar, n * width - width + 1, n * width)

  defp years(calendar, first_year, last_year) do
    with {:ok, {first, _}} <- Calendar.period(calendar, :year, first_year, nil),
         {:ok, {_, after_last}} <- Calendar.period(calendar, :year, last_year, nil) do
      {:ok, {first, after_last}}
    end
  end

  # ── The extent of a concrete prefix on its frame ──────────────────────

  @doc """
  The half-open extent of a concrete prefix on its frame: ticks on a line,
  a tuple on a cycle. Plain units go to `Tempo.Scale`; a count from the end,
  a group, a century or a quarter is first resolved to the plain units the
  calendar gives it, through its children.
  """
  @spec extent(Unit.units(), frame()) ::
          {:ok, {Scale.position(), Scale.position()}} | {:error, ConversionError.reason()}
  def extent(units, %{calendar: calendar, zone: zone, shift: shift} = frame) do
    units = Unit.cyclic(units)

    cond do
      Unit.plain?(units) ->
        Scale.extent(units, calendar, zone, shift)

      clock_group?(units) ->
        {before, [{:group, held}]} = Enum.split(units, -1)
        group_extent(before, held, frame, units)

      true ->
        with {:ok, concrete} <- resolved(units, frame) do
          resolved_extent(concrete, frame)
        end
    end
  end

  # Each unit's one child under the units before it, so `-1D` becomes the day it counts to.
  defp resolved(units, frame) do
    Enum.reduce_while(units, {:ok, []}, fn {unit, held}, {:ok, prefix} ->
      case resolve_unit(prefix, unit, held, frame) do
        {:ok, value} -> {:cont, {:ok, prefix ++ [{unit, value}]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_unit(_prefix, unit, held, _frame)
       when is_integer(held) and held >= 0 and unit != :group,
       do: {:ok, held}

  defp resolve_unit([], unit, held, _frame) when unit in [:century, :decade, :year],
    do: {:ok, held}

  defp resolve_unit(prefix, unit, held, frame) do
    case candidates(prefix, unit, held, frame) do
      {:ok, [{value, _span}]} -> {:ok, value}
      {:ok, []} -> {:error, {:no_such_value, prefix ++ [{unit, held}]}}
      {:ok, _several} -> {:error, {:several, prefix ++ [{unit, held}]}}
      {:error, _} = error -> error
    end
  end

  defp resolved_extent(units, %{calendar: calendar, zone: zone, shift: shift} = frame) do
    cond do
      Unit.plain?(units) ->
        Scale.extent(units, calendar, zone, shift)

      Keyword.has_key?(units, :group) ->
        last_child_extent(units, frame)

      not Unit.anchored?(units) ->
        Scale.extent(units, calendar, zone, shift)

      true ->
        with {:ok, day_span} <- day_span(calendar, Unit.date_units(units)) do
          Scale.extent_of(day_span, Unit.clock_units(units), zone, shift)
        end
    end
  end

  # The span of the last unit's one child under the units before it: days for
  # a calendar unit under a year, ticks for a clock unit or on a cycle.
  defp last_child_extent(units, %{zone: zone, shift: shift} = frame) do
    {before, [{unit, held}]} = Enum.split(units, -1)

    case candidates(before, unit, held, frame) do
      {:ok, [{_value, {first, after_last}}]} ->
        if Unit.anchored?(before) and not Unit.clock?(unit) and not clock_group?(units),
          do: Scale.extent_of({first, after_last}, [], zone, shift),
          else: {:ok, {first, after_last}}

      {:ok, [{_value, nil}]} ->
        {:error, :needs_a_year}

      {:ok, []} ->
        {:error, {:no_such_value, units}}

      {:ok, _several} ->
        {:error, {:several, units}}

      {:error, _} = error ->
        error
    end
  end

  defp clock_group?(units) do
    match?({:group, {_, [{unit, _}]}} when unit in [:hour, :minute, :second], List.last(units))
  end

  defp group_extent(before, held, frame, units) do
    case candidates(before, :group, held, frame) do
      {:ok, [{_value, span}]} -> {:ok, span}
      {:ok, []} -> {:error, {:no_such_value, units}}
      {:ok, _several} -> {:error, {:several, units}}
      {:error, _} = error -> error
    end
  end

  # ── Children ──────────────────────────────────────────────────────────

  @doc """
  The values a unit takes under a concrete prefix, in order, each with its
  span: days on the day scale for a calendar unit or a label, ticks on the
  frame for a clock unit, nil on a cycle.
  """
  @spec children(Unit.units(), Unit.t() | :group, frame()) ::
          {:ok, [child()]} | {:error, ConversionError.reason()}
  def children(prefix, unit, frame) do
    prefix = Unit.cyclic(prefix)

    case found(prefix, unit, frame) do
      {:ok, children} -> {:ok, within_group(prefix, unit, children)}
      error -> error
    end
  end

  # Units after a group count within it (ISO 8601-2 §5.4.2): `2018Y4G60DU6D`
  # is the sixth day of the fourth group of sixty days.
  # Units after a group count within it (ISO 8601-2 §5.4.2): a calendar unit
  # from one (`2018Y4G60DU6D`, the sixth day), a clock unit from zero
  # (`T3GT8HU0H30M`, half past the group's first hour); a label keeps its value.
  defp within_group(prefix, unit, children) do
    case List.last(prefix) do
      {:group, _} when not is_map_key(%{day_of_week: 1, day_of_year: 1}, unit) ->
        first = if Unit.clock?(unit), do: 0, else: 1
        Enum.with_index(children, fn {_value, span}, index -> {index + first, span} end)

      _ ->
        children
    end
  end

  defp found(prefix, unit, frame) do
    case List.last(prefix) do
      {:group, held} -> within_group_children(Enum.drop(prefix, -1), held, unit, frame)
      _ -> found_under(prefix, unit, frame)
    end
  end

  defp within_group_children(parent, {_nth, [{group_unit, _}]} = held, unit, frame) do
    with {:ok, [{_value, span}]} <- group_span(parent, held, frame),
         {:ok, children} <- found(parent, unit, frame) do
      {first, after_last} = comparable(span, group_unit, unit, parent, frame)
      {:ok, Enum.filter(children, fn {_, {a, b}} -> a >= first and b <= after_last end)}
    end
  end

  defp group_span(parent, held, frame) do
    case candidates(parent, :group, held, frame) do
      {:ok, [one]} -> {:ok, [one]}
      {:ok, _} -> {:error, :group_size_needed}
      {:error, _} = error -> error
    end
  end

  # A group of days holds its hours: the group's span of days as ticks, to compare with the clock's.
  defp comparable(span, group_unit, unit, parent, %{zone: zone, shift: shift}) do
    if Unit.clock?(unit) and not Unit.clock?(group_unit) and Unit.anchored?(parent) do
      {:ok, ticks} = Scale.extent_of(span, [], zone, shift)
      ticks
    else
      span
    end
  end

  defp found_under(prefix, unit, frame) do
    cond do
      Unit.clock?(unit) ->
        clock_children(prefix, unit, frame)

      unit in [:century, :decade, :year] and prefix == [] ->
        {:error, :unbounded}

      not Unit.anchored?(prefix) ->
        cycle_children(prefix, unit, frame.calendar)

      unit == :group ->
        {:error, :group_size_needed}

      true ->
        with {:ok, span} <- day_span(frame.calendar, Unit.date_units(prefix)),
             {:ok, children} <- day_children(span, prefix, unit, frame.calendar),
             do: {:ok, shown(children, unit, frame)}
    end
  end

  # A day the zone's clock leaves out is no child of its month, week or year.
  defp shown(children, unit, %{zone: %Zone{name: name} = zone, shift: nil})
       when unit in [:day, :day_of_week, :day_of_year] and is_binary(name) do
    Enum.reject(children, fn {_value, {day, _next}} -> Zone.day_skipped?(zone, nil, day) end)
  end

  defp shown(children, _unit, _frame), do: children

  # Calendar units and labels, over the days of the prefix's span.
  defp day_children({lo, hi}, _prefix, :year, calendar) do
    {:ok,
     periods(lo, hi, fn day ->
       {y, _, _} = Calendar.date(calendar, day)
       {y, period!(calendar, :year, y, nil)}
     end)}
  end

  defp day_children({lo, hi}, _prefix, :month, calendar) do
    {:ok,
     periods(lo, hi, fn day ->
       {y, m, _} = Calendar.date(calendar, day)
       {m, period!(calendar, :month, y, m)}
     end)}
  end

  defp day_children({lo, hi}, _prefix, :quarter, calendar) do
    {:ok,
     periods(lo, hi, fn day ->
       {y, m, d} = Calendar.date(calendar, day)
       q = Calendar.quarter_of_year(calendar, y, m, d)
       {q, period!(calendar, :quarter, y, q)}
     end)}
  end

  defp day_children({lo, hi}, _prefix, :traditional_month, calendar) do
    {:ok,
     periods(lo, hi, fn day ->
       {y, m, _} = Calendar.date(calendar, day)
       {Calendar.traditional_month(calendar, y, m), period!(calendar, :month, y, m)}
     end)}
  end

  # The weeks of a month are the calendar's, numbered within it; the weeks of anything else are the year's.
  defp day_children(span, prefix, :week, calendar) do
    case Keyword.get(prefix, :month) do
      month when is_integer(month) -> month_weeks(calendar, prefix[:year], month)
      _ -> year_weeks(span, calendar)
    end
  end

  defp day_children({lo, hi}, _prefix, :day, calendar) do
    {:ok,
     for(day <- lo..(hi - 1)//1, do: {Calendar.date(calendar, day) |> elem(2), {day, day + 1}})}
  end

  # Within a week a day of the week is the nth of the week's own days, whatever
  # day the calendar's week begins on; elsewhere it is the calendar's label.
  defp day_children({lo, hi}, prefix, :day_of_week, calendar) do
    case List.last(prefix) do
      {:week, _} -> {:ok, for(day <- lo..(hi - 1)//1, do: {day - lo + 1, {day, day + 1}})}
      _ -> {:ok, for(day <- lo..(hi - 1)//1, do: {weekday(calendar, day), {day, day + 1}})}
    end
  end

  defp day_children({lo, hi}, _prefix, :day_of_year, calendar) do
    {:ok, for(day <- lo..(hi - 1)//1, do: {ordinal(calendar, day), {day, day + 1}})}
  end

  defp day_children(_span, _prefix, :season, _calendar), do: {:error, :season}

  defp day_children(_span, _prefix, unit, _calendar), do: {:error, {:no_children, unit}}

  defp month_weeks(calendar, year, month) do
    with {:ok, weeks} <- Calendar.weeks_of_month(calendar, year, month) do
      {:ok, Enum.with_index(weeks, fn span, index -> {index + 1, span} end)}
    end
  end

  defp year_weeks({lo, hi}, calendar) do
    {:ok,
     periods(lo, hi, fn day ->
       {y, m, d} = Calendar.date(calendar, day)
       {:ok, {wy, w}} = Calendar.week_of_year(calendar, y, m, d)
       {w, period!(calendar, :week, wy, w)}
     end)}
  end

  defp weekday(calendar, day) do
    {y, m, d} = Calendar.date(calendar, day)
    Calendar.day_of_week(calendar, y, m, d)
  end

  defp ordinal(calendar, day) do
    {y, _, _} = Calendar.date(calendar, day)
    {first, _} = period!(calendar, :year, y, nil)
    day - first + 1
  end

  defp period!(calendar, kind, year, part) do
    {:ok, span} = Calendar.period(calendar, kind, year, part)
    span
  end

  # Walking a span period by period: `step` gives the value for the period holding a day and the period's span.
  defp periods(lo, hi, _step) when lo >= hi, do: []

  defp periods(lo, hi, step) do
    {value, {first, next}} = step.(lo)
    [{value, {first, next}} | periods(next, hi, step)]
  end

  # Clock children: the ticks of the prefix's extent, stepped at the unit and
  # shown as wall readings; with no year, the readings of the cycle.
  defp clock_children(prefix, unit, frame) do
    if Unit.anchored?(prefix) do
      with {:ok, {start, stop}} <- extent(prefix, frame) do
        {:ok, tick_children(start, stop, unit, prefix, frame)}
      end
    else
      cycle_children(prefix, unit, frame.calendar)
    end
  end

  defp tick_children(start, stop, :microsecond, prefix, _frame) do
    precision = next_precision(prefix)
    step = Integer.pow(10, 6 - precision)

    for tick <- Stream.iterate(start, &(&1 + step)) |> Stream.take_while(&(&1 < stop)),
        do: {{Integer.mod(tick, 1_000_000), precision}, {tick, tick + step}}
  end

  # The hours, minutes or seconds of a span, each from where the clock comes
  # to it to where the clock leaves it: an hour is sixty minutes long except
  # where a zone's clock changes within it (`Tempo.Zone.unit_end/4`).
  defp tick_children(start, stop, unit, _prefix, %{zone: zone, shift: shift}) do
    step = Unit.ticks(unit)

    start
    |> Stream.unfold(fn
      tick when tick >= stop ->
        nil

      tick ->
        ends = min(Zone.unit_end(zone, shift, tick, step), stop)
        {wall, _offset} = Zone.wall_of_utc(zone, shift, tick)
        {{reading(wall, unit), {tick, ends}}, ends}
    end)
    |> Enum.to_list()
  end

  defp reading(wall, :hour), do: Integer.mod(Integer.floor_div(wall, Unit.ticks(:hour)), 24)
  defp reading(wall, :minute), do: Integer.mod(Integer.floor_div(wall, Unit.ticks(:minute)), 60)
  defp reading(wall, :second), do: Integer.mod(Integer.floor_div(wall, Unit.ticks(:second)), 60)

  # A second's children are its tenths; a fraction's the next decimal place.
  defp next_precision(prefix) do
    case Keyword.get(prefix, :microsecond) do
      {_, precision} -> precision + 1
      nil -> 1
    end
  end

  # With no year a unit's children are what every year counts alike, each
  # with its span of ticks on the cycle (`Tempo.Scale.cycle_span/2`).
  defp cycle_children(prefix, unit, calendar) do
    with {:ok, values} <- cycle_values(prefix, unit, calendar) do
      {:ok,
       Enum.map(values, fn value -> {value, cycle_span!(prefix ++ [{unit, value}], calendar)} end)}
    end
  end

  defp cycle_span!(units, calendar) do
    case Scale.cycle_span(units, calendar) do
      {:ok, span} -> span
      {:error, _} -> nil
    end
  end

  defp cycle_values([], :month, calendar), do: counted(Calendar.months_in_year_bounds(calendar))

  defp cycle_values(prefix, :day, calendar) do
    case Keyword.get(prefix, :month) do
      month when is_integer(month) -> counted(Calendar.days_in_month_bounds(calendar, month))
      _ -> {:error, :needs_a_year}
    end
  end

  defp cycle_values(_prefix, :day_of_week, calendar),
    do: {:ok, Enum.to_list(1..Calendar.days_in_week(calendar))}

  defp cycle_values(_prefix, :hour, _calendar), do: {:ok, Enum.to_list(0..23)}
  defp cycle_values(_prefix, :minute, _calendar), do: {:ok, Enum.to_list(0..59)}
  defp cycle_values(_prefix, :second, _calendar), do: {:ok, Enum.to_list(0..59)}

  defp cycle_values(prefix, :microsecond, _calendar) do
    precision = next_precision(prefix)
    step = Integer.pow(10, 6 - precision)
    {:ok, for(n <- 0..9, do: {n * step, precision})}
  end

  defp cycle_values(_prefix, _unit, _calendar), do: {:error, :needs_a_year}

  defp counted({:error, _}), do: {:error, :needs_a_year}
  defp counted({n, n}), do: {:ok, Enum.to_list(1..n)}
  defp counted({_fewest, _most}), do: {:error, :needs_a_year}

  # ── What a held shape selects ─────────────────────────────────────────

  @doc """
  The children a held shape keeps, in the order written: one by number
  (negative from the end), a set and its ranges, a mask, every one for
  `:any`, the nth group of a size.
  """
  @spec select(Unit.held(), [child()]) :: [child()]
  def select(:any, children), do: children

  def select(n, children) when is_integer(n) and n > 0,
    do: Enum.filter(children, &match?({^n, _}, &1))

  def select(n, children) when is_integer(n) and n < 0 do
    case Enum.at(children, length(children) + n) do
      nil -> []
      child -> [child]
    end
  end

  def select(0, children), do: Enum.filter(children, &match?({0, _}, &1))
  def select({n, :leap}, children), do: Enum.filter(children, &match?({{^n, :leap}, _}, &1))
  def select({n, _annotation}, children) when is_integer(n), do: select(n, children)

  def select(members, children) when is_list(members),
    do: Enum.flat_map(members, &select_member(&1, children))

  def select({:mask, [:negative | digits]}, children) do
    count = length(children)
    for {child, index} <- Enum.with_index(children), masked?(count - index, digits), do: child
  end

  def select({:mask, digits}, children),
    do: Enum.filter(children, fn {value, _} -> masked?(value, digits) end)

  def select(_held, _children), do: []

  defp select_member(%Range{} = range, children) do
    last = length(children)
    first = if range.first < 0, do: last + range.first + 1, else: range.first
    final = if range.last < 0, do: last + range.last + 1, else: range.last
    for n <- first..final//abs(range.step), child <- select(n, children), do: child
  end

  defp select_member(n, children), do: select(n, children)

  # `1X` is 10 to 19; `X5` is 5, 15 and 25; a leading `:negative` a value counted from the end.
  defp masked?(value, [:negative | digits]) when is_integer(value) and value < 0,
    do: masked?(-value, digits)

  defp masked?(value, [:negative | _digits]), do: is_integer(value) and false

  defp masked?(value, digits) when is_integer(value) and value >= 0 do
    written = Integer.digits(value)
    padded = List.duplicate(0, max(length(digits) - length(written), 0)) ++ written

    length(padded) == length(digits) and
      Enum.zip(padded, digits) |> Enum.all?(fn {d, m} -> m == :x or m == d end)
  end

  defp masked?(_value, _digits), do: false

  # ── Expansion ─────────────────────────────────────────────────────────

  @doc """
  Every concrete value a value's units allow, lazily and in order, coarsest
  unit first; a value the calendar has no room for drops out, as RFC 5545
  drops a date that does not exist. The first unit, which has no prefix to
  take children from, is read from what it holds.
  """
  @spec expand(Unit.units(), frame()) ::
          {:ok, Enumerable.t()} | {:error, ConversionError.reason()}
  def expand(units, frame) do
    units = units |> Unit.cyclic() |> filled()

    [{first, held} | rest] = units

    with :ok <- expandable(units),
         {:ok, firsts} <- first_values(first, held, frame) do
      {:ok, Enum.reduce(rest, Stream.map(firsts, &[{first, &1}]), &under_each(&1, &2, frame))}
    end
  end

  defp under_each({unit, held}, prefixes, frame),
    do: Stream.flat_map(prefixes, fn prefix -> under(prefix, unit, held, frame) end)

  defp expandable(units) do
    Enum.find_value(units, :ok, fn
      {:season, _} -> {:error, :season}
      {:selection, _} -> {:error, :selection}
      _ -> nil
    end)
  end

  # The first unit's values: a year, a century or a decade from its own shape;
  # a unit with no year from the calendar's counts.
  defp first_values(unit, held, _frame) when unit in [:century, :decade, :year] do
    case literal_values(held) do
      {:ok, values} -> {:ok, values}
      :error -> {:error, :unbounded}
    end
  end

  defp first_values(unit, held, frame) do
    with {:ok, candidates} <- candidates([], unit, held, frame) do
      {:ok, Enum.map(candidates, &elem(&1, 0))}
    end
  end

  defp literal_values(n) when is_integer(n), do: {:ok, [n]}
  # `1950S2` is the years 1900 to 1999 and `2018±2` the years 2016 to 2020.
  defp literal_values({n, [significant: s]}) when is_integer(n) do
    width = Integer.pow(10, max(length(Integer.digits(abs(n))) - s, 0))
    first = div(n, width) * width
    {:ok, Enum.to_list(first..(first + width - 1))}
  end

  defp literal_values({n, [margin: m]}) when is_integer(n),
    do: {:ok, Enum.to_list((n - m)..(n + m))}

  # A leap month is the month it is, and no month with a note on it.
  defp literal_values({n, :leap}) when is_integer(n), do: {:ok, [{n, :leap}]}
  defp literal_values({n, _annotation}) when is_integer(n), do: {:ok, [n]}

  defp literal_values(members) when is_list(members) do
    values =
      Enum.flat_map(members, fn
        %Range{first: first, last: last, step: step} when first >= 0 and last >= 0 ->
          Enum.to_list(first..last//step)

        n when is_integer(n) ->
          [n]

        _ ->
          []
      end)

    {:ok, values}
  end

  defp literal_values({:mask, digits}) do
    if length(digits) - Enum.count(digits, &(&1 == :x)) >= 0 and
         Enum.count(digits, &(&1 == :x)) <= 4,
       do: {:ok, mask_values(digits)},
       else: :error
  end

  defp literal_values(_held), do: :error

  # The numbers a mask of digits names, in order: `201X` is 2010 to 2019.
  defp mask_values([:negative | digits]),
    do: digits |> mask_values() |> Enum.map(&(-&1)) |> Enum.reverse()

  defp mask_values(digits) do
    digits
    |> Enum.reduce([0], fn
      :x, acc -> for n <- acc, d <- 0..9, do: n * 10 + d
      d, acc -> for n <- acc, do: n * 10 + d
    end)
  end

  defp under(prefix, unit, held, frame) do
    case candidates(prefix, unit, held, frame) do
      {:ok, candidates} ->
        for {value, span} <- candidates, do: expanded(prefix, unit, value, span, frame)

      {:error, _} ->
        []
    end
  end

  # A label picked out of a period is the date it names (`2026Y6M3K` is each
  # Wednesday of June); one within its own period keeps its form (`2026Y25W3K`).
  defp expanded(prefix, unit, value, {day, _}, %{calendar: calendar})
       when unit in [:day_of_week, :day_of_year] and is_integer(day) do
    if Unit.anchored?(prefix) and not label_in_place?(prefix, unit) do
      {y, m, d} = Calendar.date(calendar, day)
      [year: y, month: m, day: d]
    else
      prefix ++ [{unit, value}]
    end
  end

  defp expanded(prefix, unit, value, _span, _frame), do: prefix ++ [{unit, value}]

  defp label_in_place?(prefix, unit) do
    case List.last(prefix) do
      {parent, held} -> single?(parent, held, unit)
      nil -> false
    end
  end
end
