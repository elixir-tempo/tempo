defmodule Tempo.Matcher do
  @moduledoc false

  # A plain rule compiled once to a test of a day number, taken in front of
  # the selection engine (decision 76). A rule whose parts are whole numbers
  # and lists of months, days of the month and days of the week, with or
  # without positions among what they pick, and whose period is a day or
  # coarser, picks in a period the days that pass its tests: a month is read
  # from the month a day falls in, a day of the month is counted from the
  # month's first label where the month's labels count its days, and a
  # weekday is counted round the week from the period's first day. The
  # calendar is asked once a month and once a period, not once a candidate,
  # and nothing is expanded, sorted or deduplicated.
  #
  # A rule that names months and then a nested selection, or a set of them,
  # of days of the month and of the week with positions among them (the
  # fourth Thursday of November, the first Sunday and the last of April and
  # October), with readings of the clock after it, is compiled too where its
  # period is a month or a year: each nested selection picks in each month
  # the parts before it name, or in the period where they name none, and
  # its positions are counted there, before the readings of the clock.
  #
  # A rule of readings of the clock alone whose period is an hour or a
  # minute (an hourly rule at minute 59) is compiled too: the units up to
  # the period's test which periods it picks in, and the finer ones are the
  # readings, each that many ticks into its unit. A period is taken where
  # the zone's offset holds through it and the two days before, so that no
  # reading in it is skipped or shown twice; any other is the engine's.
  #
  # The engine (`Tempo.Select`) is the meaning of every rule, and the
  # measures hold the matcher to it. A rule the matcher cannot compile goes
  # to the engine, as does a period in which a month does not count its days
  # (England, September 1752), a period on a fixed offset written beside a
  # zone, and the look-ahead past a run of periods that pick nothing.

  alias Tempo.{Calendar, Placed, Scale, Select, Spans, Unit, Walk, Zone}

  @day Scale.ticks_per_day()
  @period_units [:day, :week, :month, :year]
  @clock_units [:hour, :minute, :second]
  @plain_keys [:month, :day, :day_of_week, :instance | @clock_units]
  @nested_keys [:day, :day_of_week, :instance]
  @nested_periods [:month, :year]
  @clock_periods [:hour, :minute]

  @enforce_keys [:months, :days, :weekdays, :instances, :clock, :pickers, :scope, :cycle, :tests]
  defstruct [:months, :days, :weekdays, :instances, :clock, :pickers, :scope, :cycle, :tests]

  @typedoc "A nested selection: the days of the month and of the week it tests, and its positions."
  @type picker :: %{
          days: {[pos_integer()], [neg_integer()]} | nil,
          weekdays: [pos_integer()] | nil,
          instances: [integer()] | nil
        }

  @type t :: %__MODULE__{
          months: [pos_integer()] | nil,
          days: {[pos_integer()], [neg_integer()]} | nil,
          weekdays: [pos_integer()] | nil,
          instances: [integer()] | nil,
          clock: [{Unit.t(), [non_neg_integer()]}],
          pickers: [picker()] | nil,
          scope: :month | :period | nil,
          cycle: :hour | :minute | nil,
          tests: [{Unit.t(), [non_neg_integer()]}]
        }

  # ── Compiling ─────────────────────────────────────────────────────────

  @doc """
  The matcher for a rule's parts and the unit of its cadence, or nil for a
  rule that is not plain: one with parts the matcher does not test, a mask,
  a range it cannot count, or a period finer than a day.
  """
  @spec compile(Unit.selection(), Unit.t() | nil, module()) :: t() | nil
  def compile(parts, unit, calendar) when unit in @period_units do
    parts
    |> around_nested()
    |> compiled_shape(unit, calendar)
  end

  def compile(parts, unit, _calendar) when unit in @clock_periods do
    {tests, readings} = Enum.split_while(@clock_units, &(&1 != finer_than(unit)))
    named = for unit <- readings, Keyword.has_key?(parts, unit), do: unit

    if clock_shape?(parts, readings, named) do
      clock_compiled(Keyword.take(parts, tests), Keyword.take(parts, readings), unit)
    else
      nil
    end
  end

  def compile(_parts, _unit, _calendar), do: nil

  defp finer_than(:hour), do: :minute
  defp finer_than(:minute), do: :second

  # Readings of the clock alone, the finer units named from the period's
  # next unit down without a gap, and one at least.
  defp clock_shape?(parts, readings, [_ | _] = named) do
    Enum.all?(parts, fn {key, _held} -> key in @clock_units end) and
      named == Enum.take(readings, length(named))
  end

  defp clock_shape?(_parts, _readings, []), do: false

  defp clock_compiled(tests, readings, unit) do
    with {:ok, tests} <- clock(tests),
         {:ok, readings} <- clock(readings) do
      %__MODULE__{
        months: nil,
        days: nil,
        weekdays: nil,
        instances: nil,
        clock: readings,
        pickers: nil,
        scope: nil,
        cycle: unit,
        tests: tests
      }
    end
  end

  # The parts before a nested selection or a set of them, the selections,
  # and the parts after; or the parts of a rule with none.
  defp around_nested(parts) do
    case Enum.split_while(parts, fn {key, _held} -> key not in [:selection, :all] end) do
      {plain, []} -> {:plain, plain}
      {before, [{:selection, nested} | later]} -> {:nested, before, [nested], later}
      {before, [{:all, each} | later]} -> {:nested, before, each, later}
    end
  end

  defp compiled_shape({:plain, parts}, _unit, calendar) do
    if Enum.all?(parts, fn {key, _held} -> key in @plain_keys end) do
      compiled(parts, calendar)
    else
      nil
    end
  end

  defp compiled_shape({:nested, before, nested, later}, unit, calendar)
       when unit in @nested_periods do
    if nested_shape?(before, nested, later) do
      compiled_nested(before, nested, later, unit, calendar)
    else
      nil
    end
  end

  defp compiled_shape(_shape, _unit, _calendar), do: nil

  # Months before, plain days of the month and of the week in each nested
  # selection, and readings of the clock after: nothing else, a window
  # among them, is the matcher's.
  defp nested_shape?(before, nested, later) do
    Enum.all?(before, &match?({:month, _}, &1)) and Enum.all?(nested, &picker_shape?/1) and
      Enum.all?(later, fn {key, _held} -> key in @clock_units end)
  end

  defp picker_shape?([_ | _] = parts) do
    Enum.all?(parts, fn {key, _held} -> key in @nested_keys end) and
      (Keyword.has_key?(parts, :day) or Keyword.has_key?(parts, :day_of_week))
  end

  defp picker_shape?(_parts), do: false

  defp compiled_nested(before, nested, later, unit, calendar) do
    with {:ok, months} <- numbers(Keyword.get(before, :month), :positive),
         {:ok, pickers} <- pickers(nested, calendar),
         {:ok, clock} <- clock(later) do
      %__MODULE__{
        months: months,
        days: nil,
        weekdays: nil,
        instances: nil,
        clock: clock,
        pickers: pickers,
        scope: if(is_nil(months) and unit == :year, do: :period, else: :month),
        cycle: nil,
        tests: []
      }
    end
  end

  defp pickers(nested, calendar) do
    compiled = Enum.map(nested, &picker(&1, calendar))
    if Enum.all?(compiled, &is_map/1), do: {:ok, compiled}, else: nil
  end

  defp picker(parts, calendar) do
    with {:ok, days} <- numbers(Keyword.get(parts, :day), :either_end),
         {:ok, weekdays} <- weekdays(Keyword.get(parts, :day_of_week), calendar),
         {:ok, instances} <- numbers(Keyword.get(parts, :instance), :either_end) do
      %{days: days && Enum.split_with(days, &(&1 > 0)), weekdays: weekdays, instances: instances}
    end
  end

  defp compiled(parts, calendar) do
    with {:ok, months} <- numbers(Keyword.get(parts, :month), :positive),
         {:ok, days} <- numbers(Keyword.get(parts, :day), :either_end),
         {:ok, weekdays} <- weekdays(Keyword.get(parts, :day_of_week), calendar),
         {:ok, instances} <- numbers(Keyword.get(parts, :instance), :either_end),
         {:ok, clock} <- clock(Keyword.take(parts, @clock_units)) do
      %__MODULE__{
        months: months,
        days: days && Enum.split_with(days, &(&1 > 0)),
        weekdays: weekdays,
        instances: instances,
        clock: clock,
        pickers: nil,
        scope: nil,
        cycle: nil,
        tests: []
      }
    end
  end

  # What a part holds as whole numbers: none, one, or a list of them and of
  # ranges counted from the start. A number counted from the end is a
  # negative; zero names nothing.
  defp numbers(nil, _sign), do: {:ok, nil}
  defp numbers(n, _sign) when is_integer(n) and n > 0, do: {:ok, [n]}
  defp numbers(n, :either_end) when is_integer(n) and n < 0, do: {:ok, [n]}

  defp numbers(held, sign) when is_list(held) do
    members = Enum.map(held, &member(&1, sign))
    if Enum.all?(members, &is_list/1), do: {:ok, List.flatten(members)}, else: nil
  end

  defp numbers(_other, _sign), do: nil

  defp member(n, _sign) when is_integer(n) and n > 0, do: [n]
  defp member(n, :either_end) when is_integer(n) and n < 0, do: [n]

  defp member(%Range{first: first, last: last, step: 1}, _sign) when first > 0 and last >= first,
    do: Enum.to_list(first..last)

  defp member(_other, _sign), do: nil

  # A day of the week, 1 to 7 from Monday; one counted from the end of the
  # week (`-1K`) is the week's last day, the week as long as the calendar's.
  defp weekdays(nil, _calendar), do: {:ok, nil}

  defp weekdays(held, calendar) do
    with {:ok, numbers} <- numbers(held, :either_end) do
      days = Calendar.days_in_week(calendar)
      {:ok, Enum.map(numbers, fn n -> if n < 0, do: days + n + 1, else: n end)}
    end
  end

  # The readings of the clock a rule names on each day, each a whole number
  # or a list of them, in the order of the units.
  defp clock(parts) do
    readings = for unit <- @clock_units, {^unit, held} <- parts, do: reading(unit, held)
    if Enum.all?(readings, &is_tuple/1), do: {:ok, readings}, else: nil
  end

  defp reading(unit, n) when is_integer(n) and n >= 0, do: {unit, [n]}

  defp reading(unit, list) when is_list(list),
    do: if(Enum.all?(list, &natural?/1), do: {unit, Enum.sort(list)})

  defp reading(_unit, _other), do: nil

  defp natural?(n), do: is_integer(n) and n >= 0

  # ── Matching in a period ──────────────────────────────────────────────

  @doc """
  What a matcher picks in a placed period, each occurrence placed as the
  engine would place it: `{:ok, occurrences}`, or `:engine` for a period
  the matcher leaves to the engine.
  """
  @spec in_period(t(), Placed.t()) :: {:ok, [Placed.t()]} | :engine
  def in_period(%__MODULE__{} = matcher, %Placed{start: start, stop: stop, span: period})
      when is_integer(start) and is_integer(stop) do
    frame = frame_of(period)

    if frame == :engine do
      :engine
    else
      picked_in(matcher, start, stop, period, frame)
    end
  end

  def in_period(_matcher, _unplaced), do: :engine

  defp picked_in(%__MODULE__{cycle: nil} = matcher, start, stop, period, frame) do
    first_day = Integer.floor_div(Walk.wall(start, frame), @day)
    last_day = Integer.floor_div(Walk.wall(stop - 1, frame), @day)

    with {:ok, days} <- days_of(matcher, first_day, last_day, period.calendar) do
      {:ok, occurrences(matcher, days, period, frame)}
    end
  end

  defp picked_in(matcher, start, stop, period, frame) do
    case clock_offset(frame, start, stop, Unit.ticks(matcher.cycle), period) do
      {:ok, offset} -> {:ok, readings_in(matcher, start, stop, offset, period, frame)}
      :engine -> :engine
    end
  end

  # A rule of nested selections picks in each month the parts before them
  # name, or in the whole period. A period of one day (a daily rule) asks
  # its date once, and the month's span only for a day counted from the
  # month's end; a longer period walks its months.
  defp days_of(%__MODULE__{pickers: [_ | _]} = matcher, first_day, last_day, calendar) do
    with {:ok, months} <- whole_months(matcher, first_day, last_day, calendar) do
      week = nested_week(matcher, first_day, calendar)

      picked =
        matcher
        |> scopes(months)
        |> Enum.flat_map(&picked(&1, matcher.pickers, week))

      {:ok, picked}
    end
  end

  defp days_of(matcher, day, day, calendar) do
    {year, month, label} = Calendar.date(calendar, day)

    wanted? =
      month_wanted?(matcher, month) and label_wanted?(matcher, label, day, calendar) and
        weekday_wanted?(matcher, year, month, label, calendar)

    if wanted?, do: {:ok, [{day, year, month, label}]}, else: {:ok, []}
  end

  defp days_of(matcher, first_day, last_day, calendar),
    do: days(matcher, first_day, last_day, calendar, week_from(matcher, first_day, calendar))

  # ── Nested selections ─────────────────────────────────────────────────

  # The months of a period, each with the days of it the parts before the
  # nested selections leave: `:engine` for a period that does not begin and
  # end with a month, a month at its edge being cut, or for a month whose
  # labels do not count its days.
  defp whole_months(matcher, first_day, last_day, calendar) do
    month = Calendar.month_of_day(calendar, first_day)

    if month.first == first_day do
      months_from(matcher, month, last_day, calendar, [])
    else
      :engine
    end
  end

  defp months_from(_matcher, %{counts?: false}, _last_day, _calendar, _months), do: :engine

  defp months_from(_matcher, %{after_last: after_last}, last_day, _calendar, _months)
       when after_last - 1 > last_day,
       do: :engine

  defp months_from(matcher, month, last_day, calendar, months) do
    months = kept_month(matcher, month, months)

    if month.after_last > last_day do
      {:ok, Enum.reverse(months)}
    else
      next = Calendar.month_of_day(calendar, month.after_last)
      months_from(matcher, next, last_day, calendar, months)
    end
  end

  defp kept_month(matcher, month, months) do
    if month_wanted?(matcher, month.month) do
      days =
        for day <- month.first..(month.after_last - 1)//1,
            do: {day, month.year, month.month, month.label + day - month.first}

      [{month, days} | months]
    else
      months
    end
  end

  # Where each nested selection's positions are counted: each month, or the period.
  defp scopes(%__MODULE__{scope: :month}, months), do: Enum.map(months, &[&1])
  defp scopes(%__MODULE__{scope: :period}, months), do: [months]

  # What the nested selections pick in a scope, in time order, a day two of
  # them pick once.
  defp picked(scope, [picker], week), do: picker_days(scope, picker, week)

  defp picked(scope, pickers, week) do
    pickers
    |> Enum.flat_map(&picker_days(scope, &1, week))
    |> Enum.sort()
    |> Enum.uniq()
  end

  defp picker_days(scope, picker, week) do
    scope
    |> Enum.flat_map(fn {month, days} -> picker_in_month(picker, month, days, week) end)
    |> Select.positions(picker.instances)
  end

  defp picker_in_month(picker, month, days, week) do
    labels = wanted_labels(picker, month)

    Enum.filter(days, fn {day, _year, _month, label} ->
      (is_nil(labels) or label in labels) and weekday_wanted?(picker, day, week)
    end)
  end

  # The weekday of the period's first day, where a nested selection tests weekdays.
  defp nested_week(%__MODULE__{pickers: pickers}, first_day, calendar) do
    if Enum.any?(pickers, &(not is_nil(&1.weekdays))) do
      week(first_day, calendar)
    else
      nil
    end
  end

  # ── Readings of the clock in an hour or a minute ──────────────────────

  # The offset of a period that begins on its unit of the wall clock, is a
  # whole number of them and is written as a date: `:engine` for any other.
  defp clock_offset(frame, start, stop, step, period) do
    with {:ok, offset} <- steady(frame, start, stop) do
      if aligned?(start + offset, stop - start, step) and month_day?(period) do
        {:ok, offset}
      else
        :engine
      end
    end
  end

  # The offset a period's clock keeps through it and the two days before,
  # in which a reading could be shown a second time: in a named zone the
  # zone's, where it keeps one, and otherwise the frame's own.
  defp steady(%{zone: %Zone{name: name} = zone}, start, stop) when is_binary(name) do
    case Zone.steady_offset(zone, nil, start - 2 * @day, stop) do
      {:ok, offset} -> {:ok, offset}
      :changes -> :engine
    end
  end

  defp steady(frame, start, _stop) do
    {:ok, Walk.wall(start, frame) - start}
  end

  # A period that begins on its unit of the wall clock and is a whole number of them.
  defp aligned?(wall_start, length, step) do
    Integer.mod(wall_start, step) == 0 and Integer.mod(length, step) == 0
  end

  # A period written as a date of months and days, as the occurrences are.
  defp month_day?(%Tempo{form: {:span, %Tempo{form: {:value, units}}, _to}}),
    do: month_day_units?(units)

  defp month_day?(%Tempo{form: {:value, units}}), do: month_day_units?(units)
  defp month_day?(_period), do: false

  defp month_day_units?([{:year, _}, {:month, _}, {:day, _} | _]), do: true
  defp month_day_units?(_units), do: false

  # Each unit of the period the tests pass, at each reading, in order.
  defp readings_in(matcher, start, stop, offset, period, frame) do
    step = Unit.ticks(matcher.cycle)
    readings = readings(matcher.clock)
    {finest, _values} = List.last(matcher.clock)
    length = Unit.ticks(finest)

    for boundary <- start..(stop - 1)//step,
        units = wall_units(boundary + offset, matcher.cycle, period.calendar),
        tested?(units, matcher.tests),
        reading <- readings,
        elapsed = reading_ticks(reading),
        elapsed < step do
      at = boundary + elapsed

      value = %{
        period
        | form: {:value, units ++ reading},
          qualifications: nil,
          shift: frame.shift
      }

      Placed.new(Spans.span_of(value, at + length), {at, at + length})
    end
  end

  # The date and the units of the clock to the period's unit of a wall reading.
  defp wall_units(wall, cycle, calendar) do
    day = Integer.floor_div(wall, @day)
    {year, month, label} = Calendar.date(calendar, day)
    into_day = wall - day * @day
    hour = div(into_day, Unit.ticks(:hour))
    date = [year: year, month: month, day: label, hour: hour]

    if cycle == :minute do
      date ++ [minute: div(into_day - hour * Unit.ticks(:hour), Unit.ticks(:minute))]
    else
      date
    end
  end

  defp tested?(units, tests) do
    Enum.all?(tests, fn {unit, values} -> Keyword.fetch!(units, unit) in values end)
  end

  defp reading_ticks(reading) do
    Enum.reduce(reading, 0, fn {unit, n}, sum -> sum + n * Unit.ticks(unit) end)
  end

  # ── Plain rules ───────────────────────────────────────────────────────

  defp label_wanted?(%__MODULE__{days: nil}, _label, _day, _calendar), do: true

  defp label_wanted?(%__MODULE__{days: {from_start, []}}, label, _day, _calendar),
    do: label in from_start

  defp label_wanted?(matcher, label, day, calendar) do
    month = Calendar.month_of_day(calendar, day)
    month.counts? and label in wanted_labels(matcher, month)
  end

  defp weekday_wanted?(%__MODULE__{weekdays: nil}, _year, _month, _label, _calendar), do: true

  defp weekday_wanted?(%__MODULE__{weekdays: weekdays}, year, month, label, calendar),
    do: Calendar.day_of_week(calendar, year, month, label) in weekdays

  # The frame a period is selected in: in a named zone the zone's clock, a
  # shift on the period's start saying only which showing it begins at. A
  # fixed offset written beside a shift is the engine's.
  defp frame_of(period) do
    case Spans.frame_of(period) do
      %{zone: %Zone{name: name}} = frame when is_binary(name) -> %{frame | shift: nil}
      %{zone: %Zone{}, shift: shift} when not is_nil(shift) -> :engine
      frame -> frame
    end
  end

  # The weekday of the period's first day, asked once, where weekdays are tested.
  defp week_from(%__MODULE__{weekdays: nil}, _first_day, _calendar), do: nil

  defp week_from(_matcher, first_day, calendar), do: week(first_day, calendar)

  defp week(first_day, calendar) do
    {year, month, day} = Calendar.date(calendar, first_day)
    {first_day, Calendar.day_of_week(calendar, year, month, day), Calendar.days_in_week(calendar)}
  end

  # The days of the period that pass the tests, month by month, each with
  # its date: `:engine` for a month whose labels do not count its days.
  defp days(_matcher, first_day, last_day, _calendar, _week) when first_day > last_day,
    do: {:ok, []}

  defp days(matcher, first_day, last_day, calendar, week) do
    month = Calendar.month_of_day(calendar, first_day)

    if month.counts? do
      last = min(month.after_last - 1, last_day)
      labels = wanted_labels(matcher, month)

      here =
        for day <- first_day..last//1,
            month_wanted?(matcher, month.month),
            label = month.label + day - month.first,
            is_nil(labels) or label in labels,
            weekday_wanted?(matcher, day, week),
            do: {day, month.year, month.month, label}

      with {:ok, rest} <- days(matcher, last + 1, last_day, calendar, week),
           do: {:ok, here ++ rest}
    else
      :engine
    end
  end

  defp month_wanted?(%__MODULE__{months: nil}, _month), do: true
  defp month_wanted?(%__MODULE__{months: months}, month), do: month in months

  # The labels the rule names in a month: those counted from the start, and
  # those counted from the end as the month's last label and back.
  defp wanted_labels(%{days: nil}, _month), do: nil

  defp wanted_labels(%{days: {from_start, from_end}}, month) do
    last_label = month.label + (month.after_last - month.first) - 1
    from_start ++ Enum.map(from_end, &(last_label + &1 + 1))
  end

  defp weekday_wanted?(%{weekdays: nil}, _day, _week), do: true

  defp weekday_wanted?(%{weekdays: weekdays}, day, {first_day, first_weekday, days}),
    do: (Integer.mod(first_weekday - 1 + day - first_day, days) + 1) in weekdays

  # Each day the rule picks at each reading it names, in the order of time,
  # a reading the zone's clock skips left out, the positions applied, and
  # each occurrence placed once.
  defp occurrences(matcher, days, period, frame) do
    times = readings(matcher.clock)

    for {day, year, month, label} <- days, time <- times do
      {day, %{period | form: {:value, [year: year, month: month, day: label] ++ time}}}
    end
    |> Enum.reject(fn {day, value} -> skipped?(day, value, frame) end)
    |> Enum.map(fn {_day, value} -> %{value | qualifications: nil, shift: frame.shift} end)
    |> Select.positions(matcher.instances)
    |> Enum.map(&placed/1)
  end

  # The readings of the clock, every combination of the units named, in order.
  defp readings([]), do: [[]]

  defp readings([{unit, values} | rest]) do
    for value <- values, later <- readings(rest), do: [{unit, value} | later]
  end

  # A reading the zone's clock skips is no occurrence, as the engine finds none for it.
  defp skipped?(day, %Tempo{form: {:value, units}}, %{zone: %Zone{name: name} = zone, shift: nil})
       when is_binary(name) do
    Zone.skipped?(zone, day * @day + clock_ticks(units))
  end

  defp skipped?(_day, _value, _frame), do: false

  defp clock_ticks(units) do
    Enum.reduce(units, 0, fn
      {unit, n}, sum when unit in @clock_units -> sum + n * Unit.ticks(unit)
      _date_unit, sum -> sum
    end)
  end

  defp placed(value) do
    case Spans.extent(value) do
      {:ok, {start, stop}} -> Placed.new(Spans.span_of(value, stop), {start, stop})
      {:error, exception} -> raise exception
    end
  end
end
