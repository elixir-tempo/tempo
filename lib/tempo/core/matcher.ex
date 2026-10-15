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

  @enforce_keys [:months, :days, :weekdays, :instances, :clock]
  defstruct [:months, :days, :weekdays, :instances, :clock]

  @type t :: %__MODULE__{
          months: [pos_integer()] | nil,
          days: {[pos_integer()], [neg_integer()]} | nil,
          weekdays: [pos_integer()] | nil,
          instances: [integer()] | nil,
          clock: [{Unit.t(), [non_neg_integer()]}]
        }

  # ── Compiling ─────────────────────────────────────────────────────────

  @doc """
  The matcher for a rule's parts and the unit of its cadence, or nil for a
  rule that is not plain: one with parts the matcher does not test, a mask,
  a range it cannot count, or a period finer than a day.
  """
  @spec compile(Unit.selection(), Unit.t() | nil, module()) :: t() | nil
  def compile(parts, unit, calendar) when unit in @period_units do
    if Enum.all?(parts, fn {key, _held} -> key in @plain_keys end),
      do: compiled(parts, calendar),
      else: nil
  end

  def compile(_parts, _unit, _calendar), do: nil

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
        clock: clock
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
      first_day = Integer.floor_div(Walk.wall(start, frame), @day)
      last_day = Integer.floor_div(Walk.wall(stop - 1, frame), @day)

      with {:ok, days} <- days_of(matcher, first_day, last_day, period.calendar) do
        {:ok, occurrences(matcher, days, period, frame)}
      end
    end
  end

  def in_period(_matcher, _unplaced), do: :engine

  # A period of one day (a daily rule) asks its date once, and the month's
  # span only for a day counted from the month's end; a longer period
  # walks its months.
  defp days_of(matcher, day, day, calendar) do
    {year, month, label} = Calendar.date(calendar, day)

    wanted? =
      month_wanted?(matcher, month) and label_wanted?(matcher, label, day, calendar) and
        weekday_wanted?(matcher, year, month, label, calendar)

    if wanted?, do: {:ok, [{day, year, month, label}]}, else: {:ok, []}
  end

  defp days_of(matcher, first_day, last_day, calendar),
    do: days(matcher, first_day, last_day, calendar, week_from(matcher, first_day, calendar))

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
      %{zone: %Zone{}, shift: shift} when shift != nil -> :engine
      frame -> frame
    end
  end

  # The weekday of the period's first day, asked once, where weekdays are tested.
  defp week_from(%__MODULE__{weekdays: nil}, _first_day, _calendar), do: nil

  defp week_from(_matcher, first_day, calendar) do
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
            labels == nil or label in labels,
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
  defp wanted_labels(%__MODULE__{days: nil}, _month), do: nil

  defp wanted_labels(%__MODULE__{days: {from_start, from_end}}, month) do
    last_label = month.label + (month.after_last - month.first) - 1
    from_start ++ Enum.map(from_end, &(last_label + &1 + 1))
  end

  defp weekday_wanted?(%__MODULE__{weekdays: nil}, _day, _week), do: true

  defp weekday_wanted?(%__MODULE__{weekdays: weekdays}, day, {first_day, first_weekday, days}),
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
