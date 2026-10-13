defmodule Tempo.Parts do
  @moduledoc false
  # Reading a part of an expression: the number a unit holds, or the one the
  # calendar gives a concrete value when it is written on another axis (the
  # day of the month of a week date, the week of a date), and nil where the
  # expression names several or none.

  alias Tempo.{Calendar, ConversionError, Duration, Expand, Scale, Shift, Spans, Unit, Walk}

  @day 86_400_000_000

  @doc "The number a unit holds in an expression, nil when it holds none or several."
  @spec part(Tempo.t(), Unit.t()) :: integer() | nil
  def part(%Tempo{form: {:value, units}} = value, unit) do
    case Keyword.get(units, unit) do
      n when is_integer(n) and n >= 0 -> n
      {n, _annotation} when is_integer(n) -> n
      n when is_integer(n) or is_nil(n) -> computed(value, units, unit)
      _several -> nil
    end
  end

  def part(%Tempo{form: {:span, from, to}}, unit),
    do: [from, to] |> Enum.filter(&match?(%Tempo{}, &1)) |> agreed(unit)

  def part(%Tempo{form: {:every, first, _, _}}, unit), do: part(first, unit)

  # A set read from a stream has no part its members are known to share.
  def part(%Tempo{form: {kind, members}}, _unit)
      when kind in [:all, :one] and not is_list(members),
      do: nil

  def part(%Tempo{form: {kind, members}}, unit) when kind in [:all, :one],
    do: agreed(members, unit)

  def part(_expression, _unit), do: nil

  defp agreed([], _unit), do: nil

  defp agreed(expressions, unit) do
    case expressions |> Enum.map(&part(&1, unit)) |> Enum.uniq() do
      [one] -> one
      _several -> nil
    end
  end

  # A date unit the value is not written in, read through the calendar when
  # the value lies within one period of it: the week of a day, the day of a week date.
  defp computed(value, units, unit) do
    cond do
      not Unit.concrete?(units) -> nil
      Unit.clock?(unit) -> computed_clock(value, units, unit)
      Unit.anchored?(units) and date_unit?(unit) -> computed_date(value, units, unit)
      true -> nil
    end
  end

  defp computed_date(value, units, unit) do
    frame = Spans.frame_of(value)

    case Expand.extent(plain(units), frame) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
        period = Shift.period_units(start, unit, frame)
        if within_period?(Expand.extent(period, frame), stop), do: Keyword.get(period, unit)

      _ ->
        nil
    end
  end

  defp within_period?({:ok, {_, period_stop}}, stop), do: stop <= period_stop
  defp within_period?(_error, _stop), do: false

  # A clock unit counted from the end (`T-1H`) is read at the value's position on its clock.
  defp computed_clock(value, units, unit) do
    frame = Spans.frame_of(value)

    case Keyword.has_key?(units, unit) and Expand.extent(plain(units), frame) do
      {:ok, {start, _stop}} when is_integer(start) ->
        wall = Integer.mod(Walk.wall(start, frame), @day)
        Keyword.get(Scale.clock_at(wall, unit), unit)

      _ ->
        nil
    end
  end

  defp date_unit?(unit),
    do: unit in [:year, :month, :day, :week, :day_of_week, :day_of_year, :quarter]

  defp plain(units) do
    Enum.map(units, fn
      {unit, {n, _annotation}} when is_integer(n) -> {unit, n}
      other -> other
    end)
  end

  @doc "The day of the week renumbered from a starting day: Monday is 1 by default."
  @spec weekday(integer() | nil, atom()) :: integer() | nil
  def weekday(nil, _starting_on), do: nil
  def weekday(day, starting_on) when starting_on in [:default, :monday], do: day

  def weekday(day, starting_on) do
    index =
      Enum.find_index(
        [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
        &(&1 == starting_on)
      )

    Integer.mod(day - 1 - index, 7) + 1
  end

  @doc "The unit an expression is written to: its finest end or member."
  @spec resolution(Tempo.t() | Tempo.Duration.t()) :: Unit.t() | nil
  def resolution(%Tempo{form: {:value, units}}), do: Unit.resolution(units)

  def resolution(%Tempo{form: {:span, from, to}}),
    do: [from, to] |> Enum.filter(&match?(%Tempo{}, &1)) |> Enum.map(&resolution/1) |> finest()

  def resolution(%Tempo{form: {:every, first, _, _}}), do: resolution(first)

  def resolution(%Tempo{form: {_kind, members}}) when not is_list(members), do: nil

  def resolution(%Tempo{form: {_kind, members}}),
    do: members |> Enum.map(&resolution/1) |> finest()

  def resolution(%Tempo.Duration{units: units}), do: units |> List.last() |> elem(0)

  # An interval open at both ends is written to no unit.
  defp finest(units), do: Enum.max_by(units, &index/1, fn -> nil end)
  defp index(unit), do: Enum.find_index(Unit.order(), &(&1 == Unit.grain(unit))) || 0

  @doc "Whether an expression has a year, so a place on the time line."
  @spec anchored?(Tempo.t()) :: boolean()
  def anchored?(%Tempo{} = expression), do: not match?({:cycle, _}, Spans.frame(expression))

  @doc "Whether an expression carries a zone or a time shift."
  @spec zoned?(Tempo.t()) :: boolean()
  def zoned?(%Tempo{} = expression) do
    %{zone: zone, shift: shift} = Spans.frame_of(expression)
    zone != nil or shift != nil
  end

  @doc "Whether every end an expression has is written: no open end, no sequence without one."
  @spec bounded?(Tempo.t() | Duration.t()) :: boolean()
  def bounded?(%Tempo{form: {:span, from, to}}), do: from != :open and to != :open
  def bounded?(%Tempo{form: {:every, _, bound, _}}), do: bound != :infinity

  def bounded?(%Tempo{form: {kind, members}}) when kind in [:all, :one] and is_list(members),
    do: Enum.all?(members, &bounded?/1)

  # A set whose members are a stream has no end that is written.
  def bounded?(%Tempo{form: {kind, _stream}}) when kind in [:all, :one], do: false
  def bounded?(%Tempo{}), do: true

  # A duration, as a member of a set of them, has no end to leave open.
  def bounded?(%Duration{}), do: true

  @doc "Whether an expression covers no time: a set with no members, a span of no length."
  @spec empty?(Tempo.t()) :: boolean()
  def empty?(%Tempo{form: {:all, []}}), do: true

  def empty?(%Tempo{form: {:span, _, _}} = span) do
    case Spans.extent(span) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> start == stop
      _ -> false
    end
  end

  def empty?(%Tempo{}), do: false

  @doc "The number of days in the month a value is in, through its calendar."
  @spec days_in_month(Tempo.t()) :: {:ok, pos_integer()} | {:error, Exception.t()}
  def days_in_month(%Tempo{calendar: calendar} = value) do
    case {part(value, :year), part(value, :month)} do
      {year, month} when is_integer(year) and is_integer(month) ->
        {:ok, Calendar.days_in_month(calendar, year, month)}

      _ ->
        {:error, ConversionError.exception(value: value, reason: :needs_a_month)}
    end
  end

  @doc "Whether the year a value is in is a leap year of its calendar."
  @spec leap_year?(Tempo.t()) :: boolean() | {:error, Exception.t()}
  def leap_year?(%Tempo{calendar: calendar} = value) do
    case part(value, :year) do
      year when is_integer(year) -> Calendar.leap_year?(calendar, year)
      nil -> {:error, ConversionError.exception(value: value, reason: :needs_a_year)}
    end
  end
end
