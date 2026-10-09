defmodule Tempo.Interval.Steps do
  @moduledoc """
  Closed-form step arithmetic for interval enumeration.

  Backs the `Enumerable` protocol implementation for
  `t:Tempo.Interval.t/0` — specifically its `count/1`, `slice/1`,
  and `member?/2` callbacks — with O(1) (or near-O(1))
  implementations driven by the calendar's date algebra rather than
  walking the interval one step at a time.

  Each function takes the iteration unit and the calendar in addition
  to the endpoints:

  * `count_steps/4` — how many `unit`-wide steps fit in
    `[from, to)`.

  * `nth_step/4` — the `n`-th element from `from` at `unit`
    granularity.

  * `on_step?/4` — whether `element` falls on a `unit`-step
    boundary counted from `from`.

  Phase 1 covers `:year`, `:month`, and `:day`. Sub-day units
  (`:hour`, `:minute`, `:second`, `:microsecond`) are added in
  subsequent phases.

  """

  alias Tempo.Compare
  alias Tempo.Enumeration.Zone
  alias Tempo.Iso8601.AST
  alias Tempo.Iso8601.Unit
  alias Tempo.TimeZoneDatabase
  alias Tempo.UnitValues

  @seconds_per_minute 60
  @seconds_per_hour 3_600
  @seconds_per_day 86_400
  @microseconds_per_second 1_000_000
  @max_precision 6

  @doc false
  # Extend `tempo` with next-finer units (at their minimum values) until
  # its resolution reaches `unit`. This is the walk-time counterpart of
  # the drill that materialisation used to persist into interval bounds:
  # an interval carrying an explicit iteration `:unit` finer than its
  # endpoint resolution fills the endpoint once at the start of the walk
  # (`2025-07-04` walked at `:hour` starts from `2025-07-04T0H`), leaving
  # the stored bounds at their stated resolution. A `nil` unit, or one
  # already at (or coarser than) the value's resolution, is a no-op.
  @spec fill_to_unit(Tempo.t(), atom() | nil, module()) :: Tempo.t()
  def fill_to_unit(%Tempo{} = tempo, nil, _calendar), do: tempo

  # A year is filled below its months from its first day, which the calendar
  # is asked for where the year does not begin with its first month.
  def fill_to_unit(%Tempo{time: [{:year, year}] = time} = tempo, unit, calendar)
      when is_integer(year) and unit not in [:year, :month, :week] do
    with false <- UnitValues.year_begins_with_first_month?(year, calendar),
         {:ok, {year, month, day}} <- UnitValues.start_date(time, calendar) do
      fill_to_unit(%Tempo{tempo | time: [year: year, month: month, day: day]}, unit, calendar)
    else
      _from_its_first_month -> fill_by_unit(tempo, unit, calendar)
    end
  end

  def fill_to_unit(%Tempo{} = tempo, unit, calendar), do: fill_by_unit(tempo, unit, calendar)

  defp fill_by_unit(%Tempo{time: time} = tempo, unit, calendar) do
    {resolution_unit, _span} = Tempo.resolution(tempo)

    with :lt <- Unit.compare(unit, resolution_unit),
         {next_unit, range} <- Unit.implicit_enumerator(resolution_unit, calendar) do
      filled = %Tempo{tempo | time: with_first(time, next_unit, range_first(range), calendar)}
      fill_by_unit(filled, unit, calendar)
    else
      # :eq / :gt — already at or finer than the requested unit; nil —
      # no finer unit exists to fill with (the chain bottoms out).
      _ -> tempo
    end
  end

  defp range_first(%Range{first: first}), do: first

  # A month's first day is asked of the calendar, which counts a year's
  # months from the day the year begins (`Tempo.UnitValues.with_first_day/2`).
  defp with_first(time, :day, 1, calendar), do: UnitValues.with_first_day(time, calendar)
  defp with_first(time, unit, minimum, _calendar), do: time ++ [{unit, minimum}]

  @doc """
  Count the number of `unit`-wide steps in the half-open span
  `[from, to)`.

  ### Arguments

  * `from` is the lower-bound `t:Tempo.t/0`.

  * `to` is the exclusive upper-bound `t:Tempo.t/0`.

  * `unit` is one of `:year`, `:month`, `:day` (Phase 1 scope).

  * `calendar` is the shared calendar module of both endpoints.

  ### Returns

  * A non-negative integer count, or

  * `:not_supported` when the unit / calendar combination has no
    closed-form path. Callers should fall back to walking.

  ### Examples

      iex> from = Tempo.from_iso8601!("2026Y")
      iex> to = Tempo.from_iso8601!("2030Y")
      iex> Tempo.Interval.Steps.count_steps(from, to, :year, Calendrical.Gregorian)
      4

      iex> from = Tempo.from_iso8601!("2026-01")
      iex> to = Tempo.from_iso8601!("2027-03")
      iex> Tempo.Interval.Steps.count_steps(from, to, :month, Calendrical.Gregorian)
      14

      iex> from = Tempo.from_iso8601!("2026-01-01")
      iex> to = Tempo.from_iso8601!("2026-02-01")
      iex> Tempo.Interval.Steps.count_steps(from, to, :day, Calendrical.Gregorian)
      31

      iex> from = Tempo.from_iso8601!("1985Y")
      iex> to = Tempo.from_iso8601!("1986-06")
      iex> Tempo.Interval.Steps.count_steps(from, to, :year, Calendrical.Gregorian)
      2

  """
  @spec count_steps(Tempo.t(), Tempo.t(), atom(), module()) ::
          non_neg_integer() | :not_supported
  def count_steps(%Tempo{time: from_time} = from, %Tempo{time: to_time} = to, unit, calendar) do
    if counted_from?(from_time, unit) and date_axis?(to_time, unit) do
      from |> count_date_steps(to, unit, calendar) |> steps_before(from, to, unit, calendar)
    else
      :not_supported
    end
  end

  defp count_date_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :year, calendar) do
    UnitValues.years_between(
      fetch_integer!(from_time, :year),
      fetch_integer!(to_time, :year),
      calendar
    )
  end

  defp count_date_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :month, calendar) do
    from_y = fetch_integer!(from_time, :year)
    from_m = fetch_integer!(from_time, :month)
    to_y = fetch_integer!(to_time, :year)
    to_m = fetch_integer!(to_time, :month)
    months_between(from_y, from_m, to_y, to_m, calendar)
  end

  defp count_date_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :day, calendar) do
    Date.diff(date_of!(to_time, calendar), date_of!(from_time, calendar))
  end

  defp count_date_steps(%Tempo{} = from, %Tempo{} = to, :hour, calendar),
    do: count_on_the_clock(from, to, @seconds_per_hour, calendar)

  defp count_date_steps(%Tempo{} = from, %Tempo{} = to, :minute, calendar),
    do: count_on_the_clock(from, to, @seconds_per_minute, calendar)

  defp count_date_steps(%Tempo{} = from, %Tempo{} = to, :second, calendar) do
    elapsed_seconds(from, to, calendar)
  end

  defp count_date_steps(%Tempo{time: from_time} = from, %Tempo{} = to, :microsecond, calendar) do
    precision = microsecond_precision!(from_time)
    step = Integer.pow(10, @max_precision - precision)
    div(elapsed_microseconds(from, to, calendar), step)
  end

  defp count_date_steps(_from, _to, _unit, _calendar), do: :not_supported

  # Hours and minutes in a named zone are counted by the time elapsed, which
  # is the count of the values a walk gives only where each change of the
  # zone's clock between the two ends is by a whole number of the unit, on
  # a reading the steps land on. A walk gives the hours the clock shows, a
  # value for each: where Lord Howe Island's clocks go forward half an hour
  # an hour is half as long, and where the Chatham Islands' go from 02:45
  # to 03:45 an hour is three quarters of one and the next a quarter, so
  # steps of an elapsed hour pass over hours the clock shows. There the
  # walk answers.
  defp count_on_the_clock(from, to, unit_seconds, calendar) do
    if dst_correct?(from, to, calendar) do
      from_utc = trunc(Compare.to_utc_seconds(from))
      to_utc = trunc(Compare.to_utc_seconds(to))

      if changes_on_the_steps?(from, from_utc, to_utc, unit_seconds),
        do: div(to_utc - from_utc, unit_seconds),
        else: :not_supported
    else
      div(wall_seconds(to.time, calendar) - wall_seconds(from.time, calendar), unit_seconds)
    end
  end

  # A change at the start is not one the steps cross. One at the end is: the
  # last of the steps counted is the one that lands there (`on_step?/4`).
  defp changes_on_the_steps?(
         %Tempo{time: time, calendar: calendar} = from,
         from_utc,
         to_utc,
         unit
       ) do
    reading = wall_seconds(time, calendar)

    from
    |> zone_id()
    |> TimeZoneDatabase.changes(from_utc, to_utc)
    |> Enum.all?(fn {moment, before, later} ->
      rem(later - before, unit) == 0 and rem(moment + before - reading, unit) == 0
    end)
  end

  # `count_date_steps/4` counts the whole units between the two ends cut to
  # the unit. The steps in `[from, to)` are those, and one more when the step
  # they reach still starts before `to`, as the walk takes it: `1985/1986-06`
  # is 1985 and 1986, and `2026Y/2026Y6M15D` is 2026.
  defp steps_before(count, from, to, unit, calendar) when is_integer(count) and count >= 0,
    do: from |> nth_date_step(count, unit, calendar) |> one_more_before(to, count)

  defp steps_before(count, _from, _to, _unit, _calendar), do: count

  defp one_more_before(%Tempo{} = step, to, count) do
    if Compare.compare_endpoints(step, to) == :earlier, do: count + 1, else: count
  end

  defp one_more_before(:not_supported, _to, count), do: count

  # The closed forms count and step a calendar date — a year, a year and
  # month, or a year, month and day beneath days and clock units — each of
  # whose units is one whole number. A value on the week axis (a week's
  # days), one with no year, and one that holds a set, a mask or an
  # unspecified unit are walked instead.
  defp date_axis?([{:year, year} | rest], :year) when is_integer(year), do: whole_units?(rest)

  defp date_axis?([{:year, year}, {:month, month} | rest], :month)
       when is_integer(year) and is_integer(month),
       do: whole_units?(rest)

  defp date_axis?([{:year, year}, {:month, month}, {:day, day} | rest], unit)
       when unit not in [:year, :month] and is_integer(year) and is_integer(month) and
              is_integer(day),
       do: whole_units?(rest)

  defp date_axis?(_time, _unit), do: false

  # The value steps are counted from, which gives a microsecond step its
  # width, so it must hold one.
  defp counted_from?(time, :microsecond),
    do: date_axis?(time, :microsecond) and List.keymember?(time, :microsecond, 0)

  defp counted_from?(time, unit), do: date_axis?(time, unit)

  @doc false
  # Whether every unit of a time list is one whole number: no set, range,
  # group, mask, unspecified unit or margin of error.
  @spec whole_units?(list()) :: boolean()
  def whole_units?([{:microsecond, {value, precision}} | rest])
      when is_integer(value) and is_integer(precision),
      do: whole_units?(rest)

  def whole_units?([{_unit, value} | rest]) when is_integer(value), do: whole_units?(rest)
  def whole_units?([]), do: true
  def whole_units?(_time), do: false

  @doc """
  Return the Tempo at step `n` from `from` at `unit` granularity.

  ### Arguments

  * `from` is the `t:Tempo.t/0` the steps count from.

  * `n` is a non-negative integer step count (0 returns `from`).

  * `unit` is one of `:year`, `:month`, `:day` (Phase 1 scope).

  * `calendar` is the calendar module.

  ### Returns

  * The Tempo at step `n`, or

  * `:not_supported` for unhandled units.

  ### Examples

      iex> from = Tempo.from_iso8601!("2026-01-01")
      iex> Tempo.Interval.Steps.nth_step(from, 30, :day, Calendrical.Gregorian)
      ~o"2026Y1M31D"

      iex> from = Tempo.from_iso8601!("2026-01")
      iex> Tempo.Interval.Steps.nth_step(from, 14, :month, Calendrical.Gregorian)
      ~o"2027Y3M"

  """
  @spec nth_step(Tempo.t(), non_neg_integer(), atom(), module()) ::
          Tempo.t() | :not_supported
  def nth_step(%Tempo{time: time} = tempo, n, unit, calendar) do
    if counted_from?(time, unit),
      do: nth_date_step(tempo, n, unit, calendar),
      else: :not_supported
  end

  defp nth_date_step(%Tempo{time: time} = tempo, n, :year, calendar) do
    year = Keyword.fetch!(time, :year)
    %{tempo | time: Keyword.replace(time, :year, UnitValues.years_on(year, n, calendar))}
  end

  defp nth_date_step(%Tempo{time: time} = tempo, n, :month, calendar) do
    year = Keyword.fetch!(time, :year)
    month = Keyword.fetch!(time, :month)
    {new_year, new_month, _day} = calendar.plus(year, month, 1, :months, n)

    %{
      tempo
      | time:
          time
          |> Keyword.replace(:year, new_year)
          |> Keyword.replace(:month, new_month)
    }
  end

  defp nth_date_step(%Tempo{time: time, calendar: calendar} = tempo, n, :day, calendar) do
    date = date_of!(time, calendar)
    {y, m, d} = calendar.plus(date.year, date.month, date.day, :days, n)

    %{
      tempo
      | time:
          time
          |> Keyword.replace(:year, y)
          |> Keyword.replace(:month, m)
          |> Keyword.replace(:day, d)
    }
  end

  defp nth_date_step(%Tempo{calendar: calendar} = tempo, n, :hour, calendar) do
    nth_subday_step(tempo, n * @seconds_per_hour, calendar)
  end

  defp nth_date_step(%Tempo{calendar: calendar} = tempo, n, :minute, calendar) do
    nth_subday_step(tempo, n * @seconds_per_minute, calendar)
  end

  defp nth_date_step(%Tempo{calendar: calendar} = tempo, n, :second, calendar) do
    nth_subday_step(tempo, n, calendar)
  end

  defp nth_date_step(%Tempo{time: time, calendar: calendar} = tempo, n, :microsecond, calendar) do
    {value, precision} = Keyword.fetch!(time, :microsecond)
    step = Integer.pow(10, @max_precision - precision)
    delta_micros = value + n * step
    delta_seconds = Integer.floor_div(delta_micros, @microseconds_per_second)
    new_us_value = Integer.mod(delta_micros, @microseconds_per_second)

    base = %{tempo | time: Keyword.replace(time, :microsecond, {0, precision})}
    shifted = nth_subday_step(base, delta_seconds, calendar)

    %{shifted | time: Keyword.replace(shifted.time, :microsecond, {new_us_value, precision})}
  end

  defp nth_date_step(_from, _n, _unit, _calendar), do: :not_supported

  @doc """
  Return `true` when `element` falls on a `unit`-step boundary
  counted from `from`.

  ### Arguments

  * `element` is any `t:Tempo.t/0`.

  * `from` is the `t:Tempo.t/0` the steps count from.

  * `unit` is one of `:year`, `:month`, `:day` (Phase 1 scope).

  * `calendar` is the calendar module.

  ### Returns

  * `true` if `element` equals `from` advanced by some non-negative
    integer number of `unit` steps, `false` otherwise, or
    `:not_supported`.

  ### Examples

      iex> from = Tempo.from_iso8601!("2026-01-01")
      iex> elt = Tempo.from_iso8601!("2026-01-31")
      iex> Tempo.Interval.Steps.on_step?(elt, from, :day, Calendrical.Gregorian)
      true

  """
  @spec on_step?(Tempo.t(), Tempo.t(), atom(), module()) :: boolean() | :not_supported
  def on_step?(element, from, unit, calendar) do
    case count_steps(from, element, unit, calendar) do
      :not_supported -> :not_supported
      n when n >= 0 -> step_matches?(element, from, n, unit, calendar)
      _ -> false
    end
  end

  # Verify the candidate element exactly matches `nth_step(from, n, unit)`.
  # `count_steps` may produce a positive integer for an element that is
  # not on a step boundary (e.g. a finer-resolution element); the round-trip
  # check ensures element is precisely the n-th step.
  defp step_matches?(element, from, n, unit, calendar) do
    case nth_step(from, n, unit, calendar) do
      :not_supported -> :not_supported
      %Tempo{time: time} -> Keyword.equal?(time, element.time)
    end
  end

  ## ----------------------------------------------------------
  ## A walk by the clock
  ## ----------------------------------------------------------

  @doc false
  # The value the steps of a span are counted from: its start filled to the
  # unit they are counted in, and where the clock of its zone skips that
  # reading, the one it shows at that moment. A day in Cairo on which the
  # clocks went from midnight to 01:00 is walked from 01:00, and the first
  # of its hours was given as 00:00, which the walk passes over and no value
  # is read from, and 01:00 was held to be no hour of the day. A start
  # written to the unit is one that was read, and the clock shows it.
  @spec counted_from(Tempo.t(), atom() | nil, module()) :: Tempo.t()
  def counted_from(%Tempo{} = from, unit, calendar) do
    case fill_to_unit(from, unit, calendar) do
      ^from -> from
      filled -> Zone.shown_by_the_clock(filled)
    end
  end

  @typedoc false
  @type clock_walk :: %{
          moment: integer(),
          ends: integer(),
          unit: pos_integer(),
          offset: integer(),
          changes: [{integer(), integer(), integer()}],
          shown_twice: [{integer(), integer()}],
          from: Tempo.t()
        }

  @doc false
  # The walk of a span by hours, minutes or seconds in a named zone, as the
  # moments one unit of elapsed time apart from its start to its end, each
  # read on the zone's clock.
  #
  # A walk steps the wall clock and asks the zone of each reading, which
  # gives the values in the order of the clock's readings. That is the
  # order of time until the clock goes back: a walk gave both occurrences
  # of a reading shown twice together, so the day Troll's clocks go back
  # from 03:00 to 01:00 listed 01:00, 01:00, 02:00, 02:00; a span that ends
  # in the first showing of an hour listed its second too; and one that
  # starts in the second could not reach the readings before its start
  # that follow it in time. Stepped by the time elapsed, a span's values
  # are in order and within it whatever the clock does, a reading the
  # clock skips is never landed on, and one it shows twice is landed on
  # twice, each with the offset that tells them apart.
  #
  # The moments are a unit apart on the clock too only where each change
  # of the zone's clock within the span is by a whole number of the unit,
  # on a reading the steps land on (`changes_on_the_steps?/4`). Where one
  # is not, an hour is as long as the clock shows it and this is
  # `:not_supported`: the walk of the wall clock answers.
  #
  # The zone's changes are kept (`Tempo.TimeZoneDatabase.changes/3`), so a
  # value is read from them and the zone is asked nothing as the walk goes.
  @spec clock_walk(Tempo.t(), Tempo.t(), atom() | nil, module()) ::
          {:ok, clock_walk()} | :not_supported
  def clock_walk(%Tempo{} = from, %Tempo{} = to, unit, calendar)
      when unit in [:hour, :minute, :second] do
    # The start may come filled to the unit already, so it is asked of the
    # clock whether or not this fills it.
    from = from |> fill_to_unit(unit, calendar) |> Zone.shown_by_the_clock()
    to = fill_to_unit(to, unit, calendar)

    if counted_from?(from.time, unit) and date_axis?(to.time, unit) and
         dst_correct?(from, to, calendar),
       do: clock_walk_between(from, to, seconds_in(unit)),
       else: :not_supported
  end

  def clock_walk(_from, _to, _unit, _calendar), do: :not_supported

  defp seconds_in(:hour), do: @seconds_per_hour
  defp seconds_in(:minute), do: @seconds_per_minute
  defp seconds_in(:second), do: 1

  # More than any offset a zone has had: a change within this of the span
  # can show a reading of the span twice.
  @a_day_or_so 27 * @seconds_per_hour

  defp clock_walk_between(%Tempo{} = from, %Tempo{} = to, unit) do
    from_utc = trunc(Compare.to_utc_seconds(from))
    to_utc = trunc(Compare.to_utc_seconds(to))
    zone = zone_id(from)

    if changes_on_the_steps?(from, from_utc, to_utc, unit) do
      near = TimeZoneDatabase.changes(zone, from_utc - @a_day_or_so, to_utc + @a_day_or_so)

      {:ok,
       %{
         moment: from_utc,
         ends: to_utc,
         unit: unit,
         offset: wall_seconds(from.time, from.calendar) - from_utc,
         changes: Enum.filter(near, fn {moment, _before, _later} -> moment > from_utc end),
         shown_twice:
           for(
             {moment, before, later} <- near,
             later < before,
             do: {moment + later, moment + before}
           ),
         from: from
       }}
    else
      :not_supported
    end
  end

  @doc false
  # `Enumerable.reduce/3` over a walk by the clock.
  @spec reduce_clock_walk(clock_walk(), Enumerable.acc(), Enumerable.reducer()) ::
          Enumerable.result()
  def reduce_clock_walk(_walk, {:halt, acc}, _fun), do: {:halted, acc}

  def reduce_clock_walk(walk, {:suspend, acc}, fun),
    do: {:suspended, acc, &reduce_clock_walk(walk, &1, fun)}

  def reduce_clock_walk(%{moment: moment, ends: ends}, {:cont, acc}, _fun) when moment >= ends,
    do: {:done, acc}

  def reduce_clock_walk(%{moment: moment, unit: unit} = walk, {:cont, acc}, fun) do
    walk = past_its_changes(walk)
    reduce_clock_walk(%{walk | moment: moment + unit}, fun.(read_on_the_clock(walk), acc), fun)
  end

  # The offset the clock is at: the last change at or before the moment.
  defp past_its_changes(%{moment: moment, changes: [{changed, _before, later} | changes]} = walk)
       when changed <= moment,
       do: past_its_changes(%{walk | offset: later, changes: changes})

  defp past_its_changes(walk), do: walk

  # A reading the clock shows twice carries the offset that tells its two
  # occurrences apart, and each value of a span whose start was written
  # with an offset carries the offset its own moment has.
  defp read_on_the_clock(%{moment: moment, offset: offset, from: %Tempo{} = from} = walk) do
    reading = moment + offset
    time = replace_date_time(from.time, reading, from.calendar)

    %{from | time: time, shift: shift_read(from.shift, offset, shown_twice?(walk, reading))}
  end

  defp shift_read(written, offset, _twice?) when is_list(written),
    do: Zone.offset_as_written(offset, written)

  defp shift_read(nil, offset, true), do: Zone.offset_to_shift(offset)
  defp shift_read(nil, _offset, false), do: nil

  defp shown_twice?(%{shown_twice: readings}, reading),
    do: Enum.any?(readings, fn {from, to} -> reading >= from and reading < to end)

  ## ----------------------------------------------------------
  ## Helpers
  ## ----------------------------------------------------------

  # `Keyword.fetch!/2` is typed as returning `any()`, so arithmetic on
  # its result widens to `number()` and bubbles a stray `float()` into
  # the inferred return type of `count_steps/4`. Narrowing through a
  # guard-clause helper pins the type to `integer()` for Dialyzer.
  # No `@spec` — the success typing inferred from call sites is
  # tighter than any spec we'd write (`:month | :year` today), and
  # adding a wider spec triggers a supertype-contract warning.
  defp fetch_integer!(keyword, key) do
    case Keyword.fetch!(keyword, key) do
      value when is_integer(value) -> value
    end
  end

  @doc false
  # The months from one month to another, each written to the month with one
  # year: the count of the months themselves, in the months each year has.
  @spec months_apart(Tempo.t(), Tempo.t(), module()) :: integer() | :not_supported
  def months_apart(
        %Tempo{time: [{:year, from_year}, {:month, from_month}]},
        %Tempo{time: [{:year, to_year}, {:month, to_month}]},
        calendar
      )
      when is_integer(from_year) and is_integer(from_month) and is_integer(to_year) and
             is_integer(to_month) and from_year <= to_year,
      do: months_between(from_year, from_month, to_year, to_month, calendar)

  def months_apart(%Tempo{}, %Tempo{}, _calendar), do: :not_supported

  # Calendar-aware month difference. Where the calendar says every year has
  # the same months (the Gregorian's twelve, the Ethiopic's thirteen), it is
  # the years between times that many. Where its years differ (a Hebrew year
  # has twelve months or thirteen), the months of each year between are
  # added up.
  #
  # The count was twelve a year wherever the two end years had twelve
  # months, so a year of thirteen between them was a month short: Tishri
  # 5785 to Tishri 5788 was 36 months, where 5787 has thirteen and they are
  # 37.
  @spec months_between(integer(), integer(), integer(), integer(), module()) :: integer()
  defp months_between(from_y, from_m, to_y, to_m, calendar) do
    case UnitValues.in_any_year(:month, [], calendar) do
      {:ok, %Range{last: months}, %Range{last: months}} ->
        UnitValues.years_between(from_y, to_y, calendar) * months + (to_m - from_m)

      _its_years_differ_in_their_months ->
        months_in_years_between(from_y, to_y, calendar) + (to_m - from_m)
    end
  end

  @spec months_in_years_between(integer(), integer(), module()) :: integer()
  defp months_in_years_between(from_y, to_y, _calendar) when from_y == to_y, do: 0

  # Back from a later year the count is below none: a walk asks it of a
  # value before its start, which is on no step of it.
  defp months_in_years_between(from_y, to_y, calendar) when from_y > to_y,
    do: -months_in_years_between(to_y, from_y, calendar)

  defp months_in_years_between(from_y, to_y, calendar) when from_y < to_y do
    # `calendar.months_in_year/1` is a dynamic dispatch, so Dialyzer
    # types its result as `any()`. The accumulator addition would
    # then widen to `number()` and bubble `float()` into the spec
    # of `count_steps/4`. The case-guard narrows back to integer.
    Enum.reduce(from_y..(to_y - 1)//1, 0, fn y, acc ->
      case calendar.months_in_year(y) do
        months when is_integer(months) -> acc + months
      end
    end)
  end

  # The date a stepped value's year, month and day name, which count and
  # step through Calendrical.
  defp date_of!(time, calendar) do
    {:ok, date} =
      Date.new(
        fetch_integer!(time, :year),
        fetch_integer!(time, :month),
        fetch_integer!(time, :day),
        calendar
      )

    date
  end

  @spec to_days_since_epoch(keyword(), module()) :: integer()
  defp to_days_since_epoch(time, calendar) do
    year = fetch_integer!(time, :year)
    month = fetch_integer!(time, :month)
    day = fetch_integer!(time, :day)
    # Calendrical's `date_to_iso_days/3` has no `@spec`, so Dialyzer
    # widens its inferred return to `number()`. Narrow at the call
    # site so the day-arithmetic chain stays in `integer()`.
    case calendar.date_to_iso_days(year, month, day) do
      days when is_integer(days) -> days
    end
  end

  defp from_days_since_epoch(days, calendar) do
    calendar.date_from_iso_days(days)
  end

  # Elapsed seconds between two endpoints, DST-aware when both share
  # the same named time zone. For UTC, fixed-offset and unzoned values
  # the offset cancels in the wall-clock difference and the simpler
  # `wall_seconds` arithmetic is correct.
  #
  # `Tempo.Compare.to_utc_seconds/1` is typed as `integer() | float()`
  # because upstream zone-database field specs leak `number()` into its
  # success typing. We narrow at this call site via `trunc/1` so the
  # `count_steps/4` return type stays `non_neg_integer()`.
  @spec elapsed_seconds(Tempo.t(), Tempo.t(), module()) :: integer()
  defp elapsed_seconds(from, to, calendar) do
    if dst_correct?(from, to, calendar) do
      trunc(Compare.to_utc_seconds(to)) - trunc(Compare.to_utc_seconds(from))
    else
      wall_seconds(to.time, calendar) - wall_seconds(from.time, calendar)
    end
  end

  @spec elapsed_microseconds(Tempo.t(), Tempo.t(), module()) :: integer()
  defp elapsed_microseconds(from, to, calendar) do
    base = elapsed_seconds(from, to, calendar) * @microseconds_per_second
    base + microsecond_value(to.time) - microsecond_value(from.time)
  end

  @spec microsecond_value(keyword()) :: integer()
  defp microsecond_value(time) do
    case Keyword.get(time, :microsecond) do
      {value, _precision} when is_integer(value) -> value
      _ -> 0
    end
  end

  # Pull the precision (digit count) out of a microsecond keyword
  # entry as a narrowed integer — the value comes from `Keyword.fetch!`
  # whose `any()` return widens any arithmetic to `number()`.
  defp microsecond_precision!(time) do
    case Keyword.fetch!(time, :microsecond) do
      {_value, precision} when is_integer(precision) -> precision
    end
  end

  # Advance `from` by `delta_seconds` *elapsed* seconds. When `from`
  # is in a named zone, the resulting wall-clock time is recomputed by
  # adding the post-shift zone offset (handling DST gaps and folds
  # correctly). Otherwise wall-clock arithmetic.
  defp nth_subday_step(%Tempo{time: time, calendar: calendar} = tempo, delta_seconds, calendar) do
    cond do
      delta_seconds == 0 ->
        first_occurrence(tempo)

      in_a_named_zone?(tempo) ->
        new_utc = trunc(Compare.to_utc_seconds(tempo)) + delta_seconds
        new_offset = zone_offset_at_utc(tempo.extended.zone_id, new_utc)
        new_wall = new_utc + new_offset
        result = %{tempo | time: replace_date_time(time, new_wall, calendar)}
        disambiguate_fold(result, new_offset)

      true ->
        new_wall = wall_seconds(time, calendar) + delta_seconds
        %{tempo | time: replace_date_time(time, new_wall, calendar)}
    end
  end

  # The start the steps are counted from is a reading the clock shows twice
  # where a span starts in a fall-back, and is its first occurrence unless
  # it was written with an offset. It carries that offset as each step
  # does, and as the walk gives it: the first hour of the day Havana's
  # clocks go back from 01:00 to midnight was given with none, where the
  # walk of the day gave it one.
  defp first_occurrence(%Tempo{shift: nil} = start) do
    case Zone.zone_status(start) do
      {:ambiguous, first, _second} -> %{start | shift: first}
      _shown_once -> start
    end
  end

  defp first_occurrence(%Tempo{} = start), do: start

  # When the stepped-to wall time occurs twice (a DST fall-back fold),
  # carry the explicit offset for *this* occurrence so the two folded
  # steps are distinct values, matching the walk (`read_on_the_clock/1`).
  # `offset_seconds` already pins which side of the fold this step landed
  # on. A step from a start written with an offset carries the offset its
  # own moment has, as written: it kept the start's, which is another's
  # once the clock has changed.
  defp disambiguate_fold(%Tempo{shift: written} = result, offset_seconds) when is_list(written),
    do: %{result | shift: Zone.offset_as_written(offset_seconds, written)}

  defp disambiguate_fold(%Tempo{} = result, offset_seconds) do
    case Zone.zone_status(result) do
      {:ambiguous, _first, _second} ->
        %{result | shift: Zone.offset_to_shift(offset_seconds)}

      _ ->
        result
    end
  end

  @spec wall_seconds(keyword(), module()) :: integer()
  defp wall_seconds(time, calendar) do
    day_seconds = to_days_since_epoch(time, calendar) * @seconds_per_day
    hour = get_integer(time, :hour, 0)
    minute = get_integer(time, :minute, 0)
    second = get_integer(time, :second, 0)
    day_seconds + hour * @seconds_per_hour + minute * @seconds_per_minute + second
  end

  # Sibling of `fetch_integer!/2` with a default. Same Dialyzer
  # rationale — `Keyword.get/3` returns `any()` and any arithmetic
  # on the result would widen to `number()`.
  defp get_integer(keyword, key, default) do
    case Keyword.get(keyword, key, default) do
      value when is_integer(value) -> value
    end
  end

  # The steps go by the zone's clock when both ends carry the same named
  # zone, in whichever calendar their dates are: the clock is the zone's,
  # and a moment and a reading of it are counted in seconds from one day,
  # which each calendar is asked for. They went by the clock in the
  # Gregorian calendar alone, so a Hebrew or a Buddhist day on which the
  # clock goes forward was counted as 24 hours.
  defp dst_correct?(%Tempo{} = from, %Tempo{} = to, _calendar) do
    zone_id(from) != nil and zone_id(from) == zone_id(to)
  end

  defp in_a_named_zone?(%Tempo{} = tempo), do: zone_id(tempo) != nil

  defp zone_id(%Tempo{extended: %{zone_id: zone}}) when is_binary(zone) and zone != "", do: zone
  defp zone_id(_), do: nil

  defp zone_offset_at_utc(zone, utc_seconds) do
    # Pre-common-era instants are handled inside the adapter
    # (local-mean-time, zero offset).
    case TimeZoneDatabase.period_at_utc(zone, utc_seconds) do
      {:ok, period} -> TimeZoneDatabase.total_offset(period)
      {:error, _} -> 0
    end
  end

  # Convert a total wall-clock second count back into the date / time-
  # of-day components of `time`, preserving the original component
  # set: an hour-resolution endpoint stays hour-resolution (no minute
  # / second added), a minute-resolution endpoint stays minute-
  # resolution, and so on.
  defp replace_date_time(time, total_seconds, calendar) do
    days = Integer.floor_div(total_seconds, @seconds_per_day)
    time_of_day_seconds = Integer.mod(total_seconds, @seconds_per_day)
    hour = div(time_of_day_seconds, @seconds_per_hour)
    minute = div(rem(time_of_day_seconds, @seconds_per_hour), @seconds_per_minute)
    second = rem(time_of_day_seconds, @seconds_per_minute)
    {y, m, d} = from_days_since_epoch(days, calendar)

    time
    |> Keyword.replace(:year, y)
    |> Keyword.replace(:month, m)
    |> Keyword.replace(:day, d)
    |> maybe_replace(:hour, hour)
    |> maybe_replace(:minute, minute)
    |> maybe_replace(:second, second)
  end

  defp maybe_replace(time, key, value) do
    if Keyword.has_key?(time, key), do: Keyword.replace(time, key, value), else: time
  end

  # Suppress an unused-alias warning if `AST` ends up unreferenced in
  # later edits. Keeping the alias declaration documents the future
  # intent of using `AST.build/1,2` for reconstruction shortcuts.
  _ = AST
end
