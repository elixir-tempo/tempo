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
  alias Tempo.Expand
  alias Tempo.IntervalEndpointsError
  alias Tempo.InvalidDateError
  alias Tempo.Scale
  alias Tempo.Unit

  @doc "Checks an expression; a duration has nothing to check."
  @spec run(Tempo.t() | Duration.t()) ::
          {:ok, Tempo.t() | Duration.t()} | {:error, Exception.t()}
  def run(%Duration{} = duration), do: {:ok, duration}

  def run(%Tempo{form: form} = expression) do
    case form(form, expression) do
      :ok -> {:ok, expression}
      {:error, _} = error -> error
    end
  end

  defp form({:value, units}, expression) do
    case value(units, expression) do
      :ok -> shift(expression.shift, expression)
      error -> error
    end
  end

  defp form({:span, from, to}, expression) do
    with :ok <- end_of(from, expression),
         :ok <- end_of(to, expression) do
      ordered(from, to, expression)
    end
  end

  defp form({:every, first, bound, _rule}, expression) do
    with :ok <- form(first.form, first) do
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

  defp member({:except, %Tempo{} = member}), do: form(member.form, member)
  defp member(%Tempo{} = member), do: form(member.form, member)
  defp member(%Duration{}), do: :ok

  # A clock end of a span may be written 24:00 where the day cycle has no next day to begin.
  defp end_of(%Tempo{form: {:value, [{:hour, 24} | finer]}} = value, _expression)
       when finer == [] or finer == [minute: 0] or finer == [minute: 0, second: 0],
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

  defp value(units, %Tempo{calendar: calendar} = expression) do
    Enum.reduce_while(units, :ok, fn {unit, held}, :ok ->
      case unit(unit, held, units, calendar) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, invalid(expression, unit, reason)}
      end
    end)
  end

  defp invalid(expression, unit, reason),
    do: {:error, InvalidDateError.exception(value: expression, unit: unit, reason: reason)}

  # The bounds of a unit, given the units around it: a day's depend on its
  # month and year when those are whole numbers.
  defp unit(unit, held, units, calendar) do
    case bounds(unit, held, units, calendar) do
      nil -> :ok
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

  defp bounds(:traditional_month, _held, units, calendar),
    do: bounds(:month, nil, units, calendar)

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

  defp order_result({:error, %IntervalEndpointsError{}} = error), do: error
  defp order_result(_other), do: :ok

  # A value with one value in each unit has a place, a count from the end or a group included.
  defp position(units, %Tempo{calendar: calendar, zone: zone, shift: shift}) do
    if Unit.concrete?(units) and not Keyword.has_key?(units, :season) and
         not Keyword.has_key?(units, :selection),
       do: Expand.extent(units, %{calendar: calendar, zone: zone, shift: shift}),
       else: :skip
  end

  # Two seasons of one numbering (the four of 21 to 24, the northern 25 to 28,
  # the southern 29 to 32) are in order by year, then by number.
  defp seasons_ordered(
         :ok,
         %Tempo{form: {:value, [year: y1, season: s1]}} = a,
         %Tempo{form: {:value, [year: y2, season: s2]}} = b
       )
       when is_integer(y1) and is_integer(s1) and is_integer(y2) and is_integer(s2) and
              div(s1 - 21, 4) == div(s2 - 21, 4) do
    if {y1, s1} > {y2, s2},
      do: {:error, IntervalEndpointsError.exception(from: a, to: b, reason: :order)},
      else: :ok
  end

  defp seasons_ordered(result, _a, _b), do: result
end
