defmodule Tempo.Format do
  @moduledoc false
  # Words for an expression, in a locale, through Localize.
  #
  # An expression is shown as the time it covers. A value written to the day
  # is that day; one written coarser is shown from the first to the last of
  # the next unit down (a year its months, a month or a week its days); one
  # written to a clock unit is its date and time. A span is shown from its
  # first end to its last as the finer of the two is written, a date end
  # through (law 9) and a clock end as the reading it is. An expression that
  # names several spans is the list of them, and a one-of set its
  # alternatives. A value with no year is shown by the units it has. A year
  # before 1 is shown with its era unless a format is asked for.

  alias Localize.DateTime.Relative
  alias Localize.Interval
  alias Tempo.{Calendar, ConversionError, Duration, Limit, Shift, Spans, Unit, Walk}

  @to_minus " – "
  # The units a difference is counted in, coarsest first.
  @by_size [:year, :quarter, :month, :week, :day, :hour, :minute, :second]
  # Those a whole one of which may lie between two starts.
  @lying_between [:year, :month, :week, :day, :hour, :minute, :second]
  @day 86_400_000_000

  @doc "A locale's words for an expression or a duration."
  @spec to_string(Tempo.t() | Duration.t(), keyword()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(%Duration{units: units}, options) do
    {weeks, rest} = Keyword.pop(units, :week, 0)
    rest = if weeks == 0, do: rest, else: Keyword.update(rest, :day, weeks * 7, &(&1 + weeks * 7))

    Localize.Duration.to_string(
      struct(Localize.Duration, Keyword.put_new(rest, :microsecond, {0, 6})),
      Keyword.put_new(options, :except, [])
    )
  end

  def to_string(%Tempo{form: {:one, members}}, options),
    do: listed(members, &__MODULE__.to_string(&1, options), :or, options)

  def to_string(%Tempo{} = expression, options) do
    {within, options} = Keyword.pop(options, :within)

    cond do
      cyclic?(expression) and within == nil -> cyclic(expression, options)
      Spans.singular?(expression) -> single(expression, options)
      masked?(expression) -> masked(expression, within, options)
      true -> plural(expression, within, options)
    end
  end

  def to_string(other, _options),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_expression)}

  # A value with unspecified digits is some one of the values they allow,
  # and is shown as the stretch those values cover.
  defp masked?(%Tempo{form: {:value, units}}),
    do: Enum.any?(units, fn {_, held} -> held == :any or match?({:mask, _}, held) end)

  defp masked?(_expression), do: false

  # Where the values are one unbroken stretch it is shown as that stretch;
  # where they are apart, as the list of them.
  defp masked(%Tempo{} = value, within, options) do
    with {:ok, spans} <- Spans.spans(value, if(within, do: [within: within], else: [])),
         {:ok, spans} <- Limit.take(spans, value) do
      extents = Enum.map(spans, &Spans.extent/1)

      if spans != [] and unbroken?(extents),
        do: cover(value, hd(spans), hd(extents), List.last(extents), options),
        else: plural(value, within, options)
    end
  end

  defp unbroken?(extents) do
    extents
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [{:ok, {_, stop}}, {:ok, {start, _}}] -> stop == start end)
  end

  defp cover(value, first, {:ok, {start, _}}, {:ok, {_, stop}}, options) do
    frame = Spans.frame_of(first)
    unit = shown_unit(value)
    from = at(start, unit, frame)

    rendered(
      from,
      at(last_position(stop, unit), unit, frame),
      unit,
      with_era(options, from, unit)
    )
  end

  defp cyclic?(expression), do: match?({:cycle, _}, Spans.frame(expression))

  # Each member in its own words: a value as a value, a span as a span.
  defp plural(expression, within, options) do
    with {:ok, members} <- Spans.members(expression, if(within, do: [within: within], else: [])),
         {:ok, members} <- Limit.take(members, expression) do
      case members do
        [one] -> __MODULE__.to_string(one, options)
        many -> listed(many, &__MODULE__.to_string(&1, options), :standard, options)
      end
    end
  end

  defp listed(items, fun, style, options) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, text} -> {:cont, {:ok, acc ++ [text]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> joined(style, options)
  end

  defp joined({:ok, texts}, style, options),
    do: Localize.List.to_string(texts, [list_style: style] ++ Keyword.take(options, [:locale]))

  defp joined(error, _style, _options), do: error

  # ── One span ──────────────────────────────────────────────────────────

  # A value written to a clock unit is the reading it is; a date is the time it covers.
  defp single(%Tempo{form: {:value, _}} = value, options) do
    unit = shown_unit(value)

    with {:ok, span} <- Spans.as_span(value) do
      if Unit.clock?(unit), do: reading_of(span, unit, options), else: shown(span, unit, options)
    end
  end

  defp single(%Tempo{form: {:span, _, _}} = span, options) do
    with {:ok, [resolved]} <- one_span(span), do: span(resolved, options)
  end

  defp reading_of(span, unit, options) do
    with {:ok, {start, _}} <- extent(span) do
      first = at(start, unit, Spans.frame_of(span))
      rendered(first, first, unit, with_era(options, first, unit))
    end
  end

  defp one_span(span) do
    with {:ok, spans} <- Spans.spans(span), do: {:ok, Enum.take(spans, 1)}
  end

  defp span(%Tempo{form: {:span, from, to}} = span, options) do
    shown(span, shown_as(finer(resolution(from), resolution(to))), options)
  end

  defp shown_as(:microsecond), do: :second

  defp shown_as(unit),
    do: if(unit in [:year, :month, :day] or Unit.clock?(unit), do: unit, else: :day)

  defp resolution(%Tempo{form: {:value, units}}), do: Unit.grain(Unit.resolution(units))
  defp resolution(_other), do: :day

  defp finer(a, b),
    do: Enum.max_by([a, b], fn unit -> Enum.find_index(Unit.order(), &(&1 == unit)) || 0 end)

  # The unit a value is shown at: itself when it is a day or finer, else the unit below.
  defp shown_unit(%Tempo{form: {:value, units}}) do
    case Unit.grain(Unit.resolution(units)) do
      :microsecond -> :second
      unit when unit in [:century, :decade] -> :year
      unit when unit in [:year, :quarter] -> :month
      unit when unit in [:month, :week] -> :day
      unit -> unit
    end
  end

  # A span shown from its first to its last value of a unit.
  defp shown(%Tempo{} = span, unit, options) do
    frame = Spans.frame_of(span)

    with {:ok, {start, stop}} <- extent(span) do
      first = at(start, unit, frame)
      last = at(last_position(stop, unit), unit, end_frame(span, frame))
      rendered(first, last, unit, with_era(options, first, unit))
    end
  end

  # An end written with a time shift of its own is shown on its own clock.
  defp end_frame(%Tempo{form: {:span, _, %Tempo{shift: shift}}}, frame) when is_list(shift),
    do: %{frame | shift: shift}

  defp end_frame(_span, frame), do: frame

  defp extent(span) do
    case Spans.extent(span) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> {:ok, {start, stop}}
      {:ok, _open} -> {:error, ConversionError.exception(value: span, reason: :open)}
      error -> error
    end
  end

  # A date unit's last value holds the instant before the end; a clock end is the reading it is.
  defp last_position(stop, unit), do: if(Unit.clock?(unit), do: stop, else: stop - 1)

  defp at(position, unit, frame),
    do: position |> Shift.period_units(unit, frame) |> locale_map(frame.calendar)

  defp locale_map(units, calendar), do: units |> Map.new() |> Map.put(:calendar, calendar)

  defp rendered(same, same, unit, options) when unit in [:year, :month, :day],
    do: Localize.Date.to_string(same, options)

  defp rendered(same, same, _clock, options), do: Localize.DateTime.to_string(same, options)

  defp rendered(%{year: first} = from, %{year: last} = to, :year, options)
       when first < 1 or last < 1 do
    with {:ok, a} <- Localize.Date.to_string(from, Keyword.put(options, :format, :Gy)),
         {:ok, b} <- Localize.Date.to_string(to, Keyword.put(options, :format, :Gy)),
         do: {:ok, a <> @to_minus <> b}
  end

  defp rendered(from, to, _unit, options), do: Interval.to_string(from, to, options)

  defp with_era(options, %{year: year}, unit) when year < 1 do
    if Keyword.has_key?(options, :format),
      do: options,
      else: Keyword.put(options, :format, era_format(unit))
  end

  defp with_era(options, _first, _unit), do: options

  defp era_format(:year), do: :Gy
  defp era_format(:month), do: :GyMMM
  defp era_format(:day), do: :GyMMMd
  defp era_format(_clock), do: :GyMMMd

  # ── No year ───────────────────────────────────────────────────────────

  # A value with no year is the units it is written in; a span its two ends.
  defp cyclic(%Tempo{form: {:value, units}} = value, options) do
    units = Unit.cyclic(units)

    if Unit.plain?(units) and Unit.concrete?(units),
      do: cyclic_text(locale_map(units, value.calendar), units, options),
      else: {:error, ConversionError.exception(value: value, reason: :needs_a_year)}
  end

  defp cyclic(
         %Tempo{form: {:span, %Tempo{form: {:value, a}} = from, %Tempo{form: {:value, b}}}} = span,
         options
       ) do
    if Unit.plain?(a) and Unit.concrete?(a) and Unit.plain?(b) and Unit.concrete?(b),
      do:
        Interval.to_string(
          locale_map(a, from.calendar),
          locale_map(b, from.calendar),
          options
        ),
      else: {:error, ConversionError.exception(value: span, reason: :needs_a_year)}
  end

  defp cyclic(expression, _options),
    do: {:error, ConversionError.exception(value: expression, reason: :needs_a_year)}

  defp cyclic_text(map, units, options) do
    case {Unit.date_units(units), Unit.clock_units(units)} do
      {[], _clock} -> Localize.Time.to_string(map, options)
      {_date, []} -> Localize.Date.to_string(map, options)
      {_date, _clock} -> Localize.DateTime.to_string(map, options)
    end
  end

  # ── Relative ──────────────────────────────────────────────────────────

  @doc "A locale's words for where an expression starts relative to another: yesterday, in 3 hours."
  @spec to_relative_string(Tempo.t(), keyword()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_relative_string(%Tempo{} = value, options) do
    {from, options} = Keyword.pop_lazy(options, :from, &Tempo.utc_now/0)
    {unit, options} = Keyword.pop(options, :unit)

    with {:ok, there} <- reading(value, Spans.frame_of(value)),
         {:ok, here} <- reading(from, here_frame(from, value)) do
      {unit, count} = counted(unit, value, there, here)
      Relative.to_string(count, [unit: unit] ++ options)
    end
  end

  def to_relative_string(other, _options),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_expression)}

  # Where both are zoned the reference is read on the value's clock.
  defp here_frame(from, value) do
    {here, there} = {Spans.frame_of(from), Spans.frame_of(value)}
    if here.frame == :utc and there.frame == :utc, do: there, else: here
  end

  # The start of an expression as a wall reading on a frame: its units to the second.
  defp reading(%Tempo{} = expression, frame) do
    with :ok <- anchored(expression),
         {:ok, [first | _]} <- one_span(expression),
         {:ok, {start, _}} <- extent_start(first) do
      wall = Walk.wall(start, frame)
      units = Walk.at_tick(wall, :second, frame.calendar)
      {:ok, %{units: units, wall: wall, at: start, line: frame.frame, calendar: frame.calendar}}
    end
  end

  defp extent_start(span) do
    case Spans.extent(span) do
      {:ok, {start, _}} = ok when is_integer(start) -> ok
      _ -> {:error, ConversionError.exception(value: span, reason: :open)}
    end
  end

  defp anchored(expression) do
    if cyclic?(expression),
      do: {:error, ConversionError.exception(value: expression, reason: :needs_a_year)},
      else: :ok
  end

  # A unit asked for is the unit counted in. Where none is, it is the
  # largest of which a whole one lies between the two starts, and never one
  # finer than the expression is written to: two minutes across midnight are
  # two minutes, and the year a day is in is this year.
  defp counted(nil, value, there, here) do
    own = own_unit(value)
    between = Enum.find(@lying_between, own, &whole?(there, here, &1))

    if coarser?(between, own),
      do: {between, difference(there, here, between)},
      else: {own, periods(there, here, own)}
  end

  defp counted(unit, _value, there, here), do: {unit, difference(there, here, unit)}

  defp coarser?(unit, other), do: size(unit) < size(other)

  defp size(unit), do: Enum.find_index(@by_size, &(&1 == unit))

  # The unit an expression is written to, among those counted in.
  defp own_unit(%Tempo{form: {:value, _}} = value), do: counted_as(resolution(value))
  defp own_unit(%Tempo{form: {:span, %Tempo{} = from, _}}), do: own_unit(from)
  defp own_unit(_other), do: :second

  defp counted_as(unit) when unit in [:century, :decade], do: :year
  defp counted_as(unit), do: if(unit in @by_size, do: unit, else: :second)

  # Whether a whole one of a unit lies between two starts: a year and a
  # month by the calendar's own, from a day and a time to the same again.
  defp whole?(there, here, :year) do
    {earlier, later} = in_order(there, here)
    reached = if within_year(later) < within_year(earlier), do: 1, else: 0
    later.units[:year] - earlier.units[:year] - reached >= 1
  end

  defp whole?(there, here, :month) do
    {earlier, later} = in_order(there, here)
    reached = if within_month(later) < within_month(earlier), do: 1, else: 0
    difference(later, earlier, :month) - reached >= 1
  end

  defp whole?(there, here, :week), do: abs(passed(there, here)) >= 7 * @day
  defp whole?(there, here, :day), do: abs(passed(there, here)) >= @day
  defp whole?(there, here, unit), do: abs(passed(there, here)) >= Unit.ticks(unit)

  defp in_order(there, here),
    do: if(passed(there, here) < 0, do: {there, here}, else: {here, there})

  defp within_year(%{units: units} = reading),
    do: {units[:month], units[:day], Integer.mod(reading.wall, @day)}

  defp within_month(%{units: units} = reading), do: {units[:day], Integer.mod(reading.wall, @day)}

  # The time that passes between two starts, and the periods of a unit of
  # the clock it carries one into from the other: half past twelve is in
  # the hour of twelve.
  defp passed(%{line: :utc} = there, %{line: :utc} = here), do: there.at - here.at
  defp passed(there, here), do: there.wall - here.wall

  defp periods(there, here, unit) when unit in [:hour, :minute, :second] do
    ticks = Unit.ticks(unit)
    Integer.floor_div(Integer.mod(here.wall, ticks) + passed(there, here), ticks)
  end

  defp periods(there, here, unit), do: difference(there, here, unit)

  defp difference(there, here, :year), do: there.units[:year] - here.units[:year]

  # A quarter and a week are counted as a year and a month are, by the
  # periods of the calendar: the first of July is next quarter from the
  # last of June, and a Monday next week from the Friday before it.
  defp difference(there, here, :quarter), do: quarter(there) - quarter(here)

  defp difference(there, here, :month),
    do:
      there.units[:year] * 12 + there.units[:month] -
        (here.units[:year] * 12 + here.units[:month])

  defp difference(there, here, :week),
    do: div(week_begins(there) - week_begins(here), Calendar.days_in_week(there.calendar))

  defp difference(there, here, :day),
    do: Integer.floor_div(there.wall, @day) - Integer.floor_div(here.wall, @day)

  # Hours, minutes and seconds are those that pass: across a change of a
  # zone's clock that is not the difference of the two readings.
  defp difference(there, here, unit), do: div(passed(there, here), Unit.ticks(unit))

  defp day_of(%{wall: wall}), do: Integer.floor_div(wall, @day)

  defp quarter(%{calendar: calendar} = reading) do
    [year: year, quarter: quarter] = Walk.at_day(day_of(reading), :quarter, calendar)
    year * 4 + quarter
  end

  defp week_begins(%{calendar: calendar} = reading) do
    {:ok, day} = Calendar.first_day(calendar, Walk.at_day(day_of(reading), :week, calendar))
    day
  end
end
