defmodule Tempo.Validate do
  @moduledoc false

  # What the reader builds, checked once against the calendar (law 7: what
  # cannot be is refused, never silently another value). A unit written to a
  # whole number is checked against the bounds the calendar gives it; a set in
  # a unit, each of its members and the ends of each of its ranges; a mask or
  # `:any` is a shape and has no number to check. An interval's ends must be
  # in order. Every check names the unit and the reason so the error reads.

  alias Tempo.Calendar
  alias Tempo.Duration
  alias Tempo.Event
  alias Tempo.Expand
  alias Tempo.IntervalEndpointsError
  alias Tempo.InvalidDateError
  alias Tempo.Scale
  alias Tempo.Season
  alias Tempo.Unit
  alias Tempo.Zone
  alias Tempo.ZoneError

  @minutes_in_a_day 24 * 60

  # The units a selection's parts are held to their bounds in.
  @selected_units [:month, :week, :day, :day_of_week, :day_of_year, :hour, :minute]

  # The annotations a number takes after it, read on a year alone.
  @annotations [:exponent, :significant, :margin]

  @doc "Checks an expression; a duration has nothing to check."
  @spec run(Tempo.t() | Duration.t()) ::
          {:ok, Tempo.t() | Duration.t()} | {:error, Exception.t()}
  def run(%Duration{} = duration), do: {:ok, duration}

  def run(%Tempo{form: form} = expression) do
    with :ok <- offset(expression.zone, expression),
         :ok <- form(form, expression) do
      {:ok, expression}
    end
  end

  # A zone that is a fixed offset (`[+14:00]`) is within a day of UTC, as a
  # written shift is.
  defp offset(%Zone{name: nil, offset: minutes}, expression)
       when is_integer(minutes) and abs(minutes) >= @minutes_in_a_day do
    invalid(
      expression,
      :zone,
      "an offset of #{div(minutes, 60)} hours, where an offset is within a day of UTC"
    )
  end

  defp offset(_zone, _expression), do: :ok

  defp form({:value, units}, expression) do
    with :ok <- value(units, expression),
         :ok <- parts_within(Keyword.get(units, :selection, []), expression),
         :ok <- years_named(units, expression),
         :ok <- shift(expression.shift, expression),
         :ok <- events(units, expression),
         :ok <- consistent(units, expression) do
      shown(units, expression)
    end
  end

  defp form({:span, from, to}, expression) do
    with :ok <- some_length(from, to),
         :ok <- end_of(from, expression),
         :ok <- end_of(to, expression) do
      ordered(from, to, expression)
    end
  end

  defp form({:every, first, bound, rule}, expression) do
    with :ok <- form(first.form, first),
         :ok <- events(rule || [], expression),
         :ok <- parts_within(rule || [], expression) do
      end_of(bound, expression)
    end
  end

  defp form({kind, members}, _expression) when kind in [:all, :one] do
    Enum.reduce_while(members, :ok, fn member, :ok ->
      case member(member) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp form({:when, member, _conditions}, _expression), do: form(member.form, member)

  # No span has zero extent (law 2): an end given as a duration of nothing
  # makes none, and a recurrence stepped by it would not move.
  defp some_length(from, to) do
    if nothing?(from) or nothing?(to),
      do: {:error, IntervalEndpointsError.exception(from: from, to: to, reason: :empty)},
      else: :ok
  end

  defp nothing?(%Duration{units: units}), do: Enum.all?(units, &(amount(&1) == 0))
  defp nothing?(_value_or_open), do: false

  defp amount({:microsecond, {microseconds, _precision}}), do: microseconds
  defp amount({_unit, amount}), do: amount

  # A day or a time of day in a named zone is a reading that zone's clock
  # shows: one the clock skips whole (an hour of a spring change, the day
  # Samoa left out of 2011) is no value. A shift beside the zone gives the
  # moment itself, and a coarser value is a period the clock runs through.
  defp shown(units, %Tempo{zone: %Zone{name: name} = zone, shift: nil} = expression)
       when is_binary(name) do
    if Unit.concrete?(units) and day_or_finer?(units),
      do: wall_shown(position(units, %{expression | zone: nil}), zone, expression),
      else: :ok
  end

  defp shown(_units, _expression), do: :ok

  # A time shift beside a critical zone is one the zone has then (RFC 9557
  # section 3.4): `+00:00[!Europe/London]` in July says a local time London's
  # clock does not show, and the flag says to act on it. `Z` says no local
  # time, and a zone that is not critical leaves the moment as the shift
  # gives it.
  defp consistent(units, %Tempo{zone: %Zone{critical: true} = zone, shift: shift} = expression) do
    if Zone.asserted?(shift) and Unit.concrete?(units) and day_or_finer?(units),
      do: has_shift(position(units, %{expression | zone: nil, shift: nil}), zone, expression),
      else: :ok
  end

  defp consistent(_units, _expression), do: :ok

  defp has_shift({:ok, {start, stop}}, zone, %Tempo{shift: shift} = expression)
       when is_integer(start) and is_integer(stop) do
    offset = Zone.shift_ticks(shift)

    if Zone.offset_at_utc(zone, start - offset) == offset or
         Zone.offset_at_utc(zone, stop - 1 - offset) == offset,
       do: :ok,
       else:
         {:error,
          ZoneError.exception(zone: name_of(zone), reason: :inconsistent, value: expression)}
  end

  defp has_shift(_no_position, _zone, _expression), do: :ok

  defp name_of(%Zone{name: name}) when is_binary(name), do: name

  defp name_of(%Zone{offset: minutes}) do
    sign = if minutes < 0, do: "-", else: "+"
    [hours, minutes] = Enum.map([div(abs(minutes), 60), rem(abs(minutes), 60)], &two/1)
    sign <> hours <> ":" <> minutes
  end

  defp two(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  defp day_or_finer?(units) do
    Keyword.has_key?(units, :year) and
      Unit.compare(Unit.grain(Unit.resolution(units)), :day) != :lt
  end

  defp wall_shown({:ok, {start, stop}}, zone, expression)
       when is_integer(start) and is_integer(stop) do
    if Zone.skipped?(zone, start) and Zone.skipped?(zone, stop - 1),
      do: {:error, ZoneError.exception(zone: zone.name, reason: :gap, value: expression)},
      else: :ok
  end

  defp wall_shown(_no_position, _zone, _expression), do: :ok

  # An event a selection names is one Tempo, or a resolver registered with
  # it, knows how to find: an unknown name would select nothing, and say so
  # of an event that happened.
  defp events(parts, expression) do
    case unknown_event(parts) do
      nil -> :ok
      name -> invalid(expression, :event, {:unknown_event, name})
    end
  end

  defp unknown_event(parts) do
    Enum.find_value(parts, fn
      {:selection, inner} -> unknown_event(inner)
      {:all, each} -> Enum.find_value(each, &unknown_event/1)
      {:event, {name, _zone}} -> if name in Event.known(), do: nil, else: name
      _other -> nil
    end)
  end

  defp member({:except, %Tempo{} = member}), do: form(member.form, member)
  defp member(%Tempo{} = member), do: form(member.form, member)
  defp member(%Duration{}), do: :ok

  # A clock end of a span may be written 24:00 where the day cycle has no next day to begin.
  defp end_of(%Tempo{form: {:value, [{:hour, 24} | finer]}} = value, _expression)
       when finer in [[], [minute: 0], [minute: 0, second: 0]],
       do: form({:value, [{:hour, 23} | finer]}, value)

  defp end_of(%Tempo{form: form} = value, _expression), do: form(form, value)
  defp end_of(_duration_or_open_or_count, _expression), do: :ok

  # A time shift is whole hours below a day, with minutes and seconds of the clock (RFC 3339 §5.6).
  defp shift(nil, _expression), do: :ok

  defp shift(shift, expression) do
    Enum.reduce_while(shift, :ok, fn {unit, value}, :ok ->
      limit = if unit == :hour, do: 23, else: 59

      if abs(value) <= limit,
        do: {:cont, :ok},
        else: {:halt, invalid(expression, :shift, {:out_of_range, value, -limit..limit})}
    end)
  end

  # ── A value ───────────────────────────────────────────────────────────

  defp value(units, expression) do
    with :ok <- shaped(units), do: bounded(units, expression)
  end

  defp bounded(units, %Tempo{calendar: calendar} = expression) do
    Enum.reduce_while(units, :ok, fn {unit, held}, :ok ->
      case unit(unit, held, units, calendar) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, invalid(expression, unit, reason)}
      end
    end)
  end

  # A unit holds a number, a list, a tuple or `:any`. Text or another atom
  # (`hour: "09"`, `month: :march`) is a program's mistake, named here
  # rather than met by the writer. The expression it would make cannot be
  # written, so the error carries the units.
  #
  # An exponent, significant digits or a margin (`2018±2Y`) is read on a year
  # alone, so a value built with one on another unit would be written as text
  # that is not read back.
  defp shaped(units) do
    case Enum.find_value(units, &unshaped/1) do
      nil ->
        :ok

      {unit, reason} ->
        {:error, InvalidDateError.exception(value: units, unit: unit, reason: reason)}
    end
  end

  defp unshaped({unit, held}) when is_binary(held) or is_float(held),
    do: {unit, {:not_a_unit_value, held}}

  defp unshaped({unit, held}) when is_atom(held) and held != :any,
    do: {unit, {:not_a_unit_value, held}}

  defp unshaped({unit, {n, annotations} = held}) when unit != :year and is_integer(n) do
    if annotated?(annotations), do: {unit, {:annotated, held}}
  end

  defp unshaped(_unit_and_held), do: nil

  defp annotated?(annotations) when is_list(annotations),
    do: Enum.any?(annotations, &match?({key, _} when key in @annotations, &1))

  defp annotated?(_leap), do: false

  # A century or a decade is written alone (ISO 8601-2 §4.3.5, §4.3.6), or
  # before the units a year holds: a year written after one is a year it
  # names, and a decade written after a century is refused (decision 71).
  defp years_named(units, expression) do
    case {Keyword.get(units, :century), Keyword.get(units, :decade)} do
      {century, decade} when not is_nil(century) and not is_nil(decade) ->
        invalid(expression, :decade, :after_a_century)

      {century, nil} when is_integer(century) ->
        year_named(:century, century, Keyword.get(units, :year), expression)

      {nil, decade} when is_integer(decade) ->
        year_named(:decade, decade, Keyword.get(units, :year), expression)

      _none_or_masked ->
        :ok
    end
  end

  defp year_named(unit, n, years, expression) when is_list(years) do
    Enum.reduce_while(years, :ok, fn year, :ok ->
      case year_named(unit, n, year, expression) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp year_named(unit, n, year, expression) when is_integer(year) do
    years = Expand.years_of(unit, n)
    if year in years, do: :ok, else: invalid(expression, :year, {:out_of_range, year, years})
  end

  # No year, or a range or a mask of them, each placed where it is asked.
  defp year_named(_unit, _n, _year, _expression), do: :ok

  defp invalid(expression, unit, reason),
    do: {:error, InvalidDateError.exception(value: expression, unit: unit, reason: reason)}

  # The bounds of a unit, given the units around it: a day's depend on its
  # month and year when those are whole numbers.
  defp unit(unit, held, units, calendar) do
    case bounds(unit, held, units, calendar) do
      nil -> :ok
      {:named, year} -> named_in(calendar, year, held)
      {:dates, year, month} -> within(held, {:dates, year, month}, calendar)
      {low, high} -> within(held, low, high)
    end
  end

  defp bounds(unit, _held, _units, _calendar) when unit in [:century, :decade, :year], do: nil

  defp bounds(:month, _held, units, calendar) do
    case whole(units, :year) do
      nil -> {1, Calendar.months_in_year_bounds(calendar) |> elem(1)}
      year -> {1, Calendar.months_in_year(calendar, year)}
    end
  end

  # A month by its name in a known year is a month the year has or has
  # not: a leap month is of a leap year.
  defp bounds(:traditional_month, held, units, calendar) do
    case {whole(units, :year), month_name?(held)} do
      {year, true} when is_integer(year) -> {:named, year}
      _no_year_or_several -> bounds(:month, nil, units, calendar)
    end
  end

  # A day of a known month is a date the calendar has or has not: a reform
  # calendar's September 1752 has the 2nd and the 14th and none between.
  defp bounds(:day, _held, units, calendar) do
    case {whole(units, :year), whole(units, :month)} do
      {year, month} when is_integer(year) and is_integer(month) ->
        if month in 1..Calendar.months_in_year(calendar, year),
          do: {:dates, year, month},
          else: nil

      {_year, month} when is_integer(month) ->
        month_day_bounds(calendar, month)

      _ ->
        {1, longest_month(calendar)}
    end
  end

  defp bounds(:week, _held, units, calendar) do
    case whole(units, :year) do
      nil -> {1, 54}
      year -> weeks_bounds(Calendar.weeks_in_year(calendar, year))
    end
  end

  defp bounds(:day_of_week, _held, _units, calendar), do: {1, Calendar.days_in_week(calendar)}

  defp bounds(:day_of_year, _held, units, calendar) do
    case whole(units, :year) do
      nil -> {1, 366}
      year -> days_bounds(Calendar.days_in_year(calendar, year))
    end
  end

  defp bounds(:quarter, _held, _units, _calendar), do: {1, 4}
  defp bounds(:season, _held, _units, _calendar), do: {21, 32}
  defp bounds(:hour, _held, _units, _calendar), do: {0, 23}
  defp bounds(:minute, _held, _units, _calendar), do: {0, 59}
  defp bounds(:second, _held, _units, _calendar), do: {0, 59}
  defp bounds(:microsecond, _held, _units, _calendar), do: nil

  defp bounds(:group, {nth, _duration}, _units, _calendar) when is_integer(nth) and nth < 1,
    do: {1, nth}

  defp bounds(:group, _held, _units, _calendar), do: nil
  defp bounds(:selection, _held, _units, _calendar), do: nil

  # ── A selection's parts ───────────────────────────────────────────────

  # A selection's parts are held to the bounds a unit has in any period of
  # its calendar (law 7): no thirteenth Gregorian month, no thirty-second
  # day, no eighth day of the week. A part some periods have and others lack
  # (`L31DN`) is kept, as RFC 5545 keeps a BYMONTHDAY a month lacks, and a
  # second runs to 60, as RFC 5545's BYSECOND does.
  defp parts_within(parts, %Tempo{calendar: calendar} = expression) do
    case parts_bounded(parts, calendar) do
      :ok -> :ok
      {:error, {unit, reason}} -> invalid(expression, unit, reason)
    end
  end

  defp parts_bounded(parts, calendar) when is_list(parts) do
    Enum.reduce_while(parts, :ok, fn part, :ok ->
      case part_bounded(part, calendar) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp parts_bounded(_parts, _calendar), do: :ok

  defp part_bounded({:selection, nested}, calendar), do: parts_bounded(nested, calendar)

  defp part_bounded({:all, alternatives}, calendar) when is_list(alternatives),
    do: parts_bounded(Enum.map(alternatives, &{:selection, &1}), calendar)

  defp part_bounded({:second, held}, _calendar), do: part_within(:second, held, 0, 60)

  defp part_bounded({unit, held}, calendar) when unit in @selected_units do
    {low, high} = bounds(unit, held, [], calendar)
    part_within(unit, held, low, high)
  end

  defp part_bounded(_part, _calendar), do: :ok

  defp part_within(unit, held, low, high) do
    case within(held, low, high) do
      :ok -> :ok
      {:error, reason} -> {:error, {unit, reason}}
    end
  end

  defp month_name?({month, :leap}) when is_integer(month), do: true
  defp month_name?(month), do: is_integer(month) and month > 0

  defp named_in(calendar, year, named) do
    case Calendar.month_from_traditional(calendar, year, named) do
      month when is_integer(month) -> :ok
      _the_year_lacks_it -> {:error, {:no_such_month, named, year}}
    end
  end

  defp month_day_bounds(calendar, month) do
    case Calendar.days_in_month_bounds(calendar, month) do
      {:error, _} -> {1, longest_month(calendar)}
      {_shortest, longest} -> {1, longest}
    end
  end

  defp longest_month(calendar) do
    {_fewest, most} = Calendar.months_in_year_bounds(calendar)

    1..most
    |> Enum.map(fn month ->
      case Calendar.days_in_month_bounds(calendar, month) do
        {:error, _} -> 0
        {_shortest, longest} -> longest
      end
    end)
    |> Enum.max()
  end

  defp weeks_bounds({:error, _}), do: {1, 54}
  defp weeks_bounds(weeks), do: {1, weeks}

  defp days_bounds({:error, _}), do: {1, 366}
  defp days_bounds(days), do: {1, days}

  # The whole number a unit holds, if it holds one.
  defp whole(units, unit) do
    case Keyword.get(units, unit) do
      n when is_integer(n) -> n
      {n, _annotation} when is_integer(n) -> n
      _ -> nil
    end
  end

  # ── What a unit holds, against its bounds ─────────────────────────────

  defp within(n, {:dates, year, month}, calendar) when is_integer(n) and n > 0 do
    if Calendar.valid_date?(calendar, year, month, n),
      do: :ok,
      else: {:error, {:no_such_date, n}}
  end

  defp within(n, {:dates, year, month}, calendar) when is_integer(n) and n < 0 do
    if -n <= Calendar.days_in_month(calendar, year, month),
      do: :ok,
      else: {:error, {:out_of_range, n, 1..Calendar.days_in_month(calendar, year, month)}}
  end

  defp within(n, low, high) when is_integer(n) do
    cond do
      n >= low and n <= high -> :ok
      n < 0 and -n >= low and -n <= high -> :ok
      true -> {:error, {:out_of_range, n, low..high}}
    end
  end

  defp within({n, annotation}, low, high)
       when is_integer(n) and (is_list(annotation) or annotation == :leap),
       do: within(n, low, high)

  defp within(members, low, high) when is_list(members) do
    Enum.reduce_while(members, :ok, fn member, :ok ->
      case member_within(member, low, high) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp within(_shape, _low, _high), do: :ok

  defp member_within(%Range{first: first, last: last}, {:dates, _, _} = dates, calendar) do
    case within(first, dates, calendar) do
      :ok -> within(last, dates, calendar)
      error -> error
    end
  end

  defp member_within(%Range{first: first, last: last}, low, high) do
    case within(first, low, high) do
      :ok -> within(last, low, high)
      error -> error
    end
  end

  defp member_within(member, low, high), do: within(member, low, high)

  # ── An interval's ends ────────────────────────────────────────────────

  # Two values both of which have a place on the scale must be in order: the
  # span from the start of the first to where the second ends, after its last
  # unit for a date and at its reading for a time of day (law 9), is not
  # empty and does not run backwards. On a cycle an end at or before the start
  # runs on through the cycle's end, so any order is a span.
  defp ordered(%Tempo{form: {:value, from}} = a, %Tempo{form: {:value, to}} = b, _expression) do
    with {:ok, {start, _}} <- position(from, a),
         {:ok, {to_start, to_stop}} <- position(to, b) do
      finish = if Unit.clock?(Unit.resolution(to)), do: to_start, else: to_stop

      if Unit.anchored?(from) and Scale.compare(start, finish) != :lt,
        do: {:error, IntervalEndpointsError.exception(from: a, to: b, reason: :order)},
        else: :ok
    end
    |> order_result()
    |> seasons_ordered(a, b)
  end

  defp ordered(_from, _to, _expression), do: :ok

  # A season of 21 to 24 has its dates in a hemisphere, which a text does
  # not name, so its place is not asked for as it is read. A season of a
  # hemisphere has its dates, and is held to them.
  defp abstract_season?(units), do: Season.abstract?(Keyword.get(units, :season))

  # Two seasons of 21 to 24 are in order by year, then by number, as EDTF
  # holds them (its corpus refuses `2012-24/2012-21`): spring, summer,
  # autumn, winter.
  defp seasons_ordered(
         :ok,
         %Tempo{form: {:value, [year: y1, season: s1]}} = a,
         %Tempo{form: {:value, [year: y2, season: s2]}} = b
       )
       when is_integer(y1) and s1 in 21..24 and is_integer(y2) and s2 in 21..24 do
    if {y1, s1} > {y2, s2},
      do: {:error, IntervalEndpointsError.exception(from: a, to: b, reason: :order)},
      else: :ok
  end

  defp seasons_ordered(result, _a, _b), do: result

  defp order_result({:error, %IntervalEndpointsError{}} = error), do: error
  defp order_result(_other), do: :ok

  # A value with one value in each unit has a place, a count from the end or a group included.
  defp position(units, %Tempo{calendar: calendar, zone: zone, shift: shift}) do
    if Unit.concrete?(units) and not abstract_season?(units) and
         not Keyword.has_key?(units, :selection),
       do: Expand.extent(units, %{calendar: calendar, zone: zone, shift: shift}),
       else: :skip
  end
end
