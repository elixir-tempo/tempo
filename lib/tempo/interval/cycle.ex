defmodule Tempo.Interval.Cycle do
  @moduledoc """
  The cycle a span with no year lies on.

  A value with no year, or with an unspecified one, is on a cycle: the
  day for a time of day, the year for a month and a day, the week for a
  day of the week. A span on a cycle is written from its start to its
  end as any span is, and an end that is not after the start is in the
  cycle's next turn: `~o"T23H"` is the span `T23H/T0H`, the last hour of
  the day, `T22H/T2H` runs through midnight, and `T0H/T0H` is the whole
  day, a span that ends where it starts being once round. ISO 8601-1:2019
  has no hour 24, so the end of the day is written as the start of the
  next.

  Anything that orders a span's ends cannot read that, so this module
  cuts such a span where its cycle ends (`parts/1`), measures it
  (`microseconds/1`), and writes a part that ends at the cycle's end as
  the span it came from (`wrapped/1`). It is the one place the reading
  lives: `Tempo.relation/2`, the set operations, the length predicates,
  `Tempo.Interval.empty?/1` and `Tempo.IntervalSet.coalesce/1` all read
  a span with no year through it.

  Inside a turn the cycle's end is one past the last value its leading
  unit takes: hour 24, month 13, day of the week 8. No value is written
  with it, and it is not returned to a caller.

  """

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.Mask
  alias Tempo.UnanchoredError

  @microseconds 1_000_000
  @seconds_per_day 86_400

  @doc """
  Whether an interval lies on a cycle: it has both its ends, and its
  start has no year or an unspecified one.

  ### Arguments

  * `interval` is a `t:Tempo.Interval.t/0`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Tempo.Interval.Cycle.cyclic?(~o"T22H/T2H")
      true

      iex> Tempo.Interval.Cycle.cyclic?(~o"2026-06-15T22/2026-06-16T02")
      false

  """
  @spec cyclic?(Interval.t()) :: boolean()
  def cyclic?(%Interval{from: %Tempo{time: [{:year, year} | _rest]}, to: %Tempo{}}),
    do: year == :any

  def cyclic?(%Interval{from: %Tempo{}, to: %Tempo{}}), do: true
  def cyclic?(%Interval{}), do: false

  @doc """
  The parts of an interval, each inside one turn of its cycle.

  A span whose end is after its start, or one with a year, is its one
  part. One whose end is not after its start is cut at the cycle's end:
  the part up to the end, and the part from the cycle's start when the
  span goes on. A span that ends where it starts is a whole turn, cut the
  same way: one part when it starts with the cycle, and otherwise two.

  ### Arguments

  * `interval` is a `t:Tempo.Interval.t/0` with both its ends.

  ### Returns

  * `{:ok, parts}`, one or two intervals, each with its end after its
    start.

  * `{:error, exception}` when the ends have no order (one has a year and
    the other none), or the cycle has no length the span can be cut at: a
    bare day's month, a bare week's year.

  ### Examples

      iex> {:ok, [evening, morning]} = Tempo.Interval.Cycle.parts(~o"T22H/T2H")
      iex> {Tempo.hour(evening.from), Tempo.hour(morning.to)}
      {22, 2}

      iex> Tempo.Interval.Cycle.parts(~o"T9H/T17H")
      {:ok, [~o"T9H/T17H"]}

      iex> {:ok, [whole_day]} = Tempo.Interval.Cycle.parts(~o"T0H/T0H")
      iex> Tempo.hour(whole_day.to)
      24

  """
  @spec parts(Interval.t()) :: {:ok, [Interval.t()]} | {:error, Exception.t()}
  def parts(%Interval{from: %Tempo{time: [{:year, year} | _rest]}, to: %Tempo{}} = interval)
      when year != :any,
      do: {:ok, [interval]}

  def parts(%Interval{from: %Tempo{} = from, to: %Tempo{} = to} = interval) do
    case Compare.order(from, to) do
      {:ok, :earlier} -> {:ok, [interval]}
      {:ok, _same_or_later} -> cut_at_end(interval)
      {:error, _exception} = error -> error
    end
  end

  def parts(%Interval{} = interval), do: {:ok, [interval]}

  defp cut_at_end(%Interval{from: %Tempo{} = from, to: %Tempo{} = to} = interval) do
    {from_year, from_time} = split_unspecified_year(from.time)
    {to_year, to_time} = split_unspecified_year(to.time)

    case end_of_cycle(from_time, Compare.effective_calendar(from.calendar)) do
      {:ok, end_time} ->
        first = %{interval | to: %{from | time: from_year ++ end_time}}

        if at_start?(to_time),
          do: {:ok, [first]},
          else: {:ok, [first, %{interval | from: %{to | time: to_year ++ start_of(to_time)}}]}

      :no_cycle ->
        {:error, no_cycle_error(interval)}
    end
  end

  @doc """
  The one part of an interval, for an operation that takes one span.

  ### Arguments

  * `interval` is a `t:Tempo.Interval.t/0` with both its ends.

  ### Returns

  * `{:ok, part}`, the interval with its end where the cycle's is when it
    runs to it.

  * `{:error, exception}` for a span that runs past its cycle's end, which
    is two spans in any one turn, and for what `parts/1` refuses.

  ### Examples

      iex> {:ok, last_hour} = Tempo.Interval.Cycle.one_part(~o"T23H/T0H")
      iex> Tempo.hour(last_hour.to)
      24

      iex> {:error, %Tempo.IntervalEndpointsError{}} = Tempo.Interval.Cycle.one_part(~o"T22H/T2H")

  """
  @spec one_part(Interval.t()) :: {:ok, Interval.t()} | {:error, Exception.t()}
  def one_part(%Interval{} = interval) do
    case parts(interval) do
      {:ok, [part]} -> {:ok, part}
      {:ok, _two_parts} -> {:error, crosses_error(interval)}
      {:error, _exception} = error -> error
    end
  end

  @doc """
  An interval that ends at its cycle's end, written as the span it is: its
  end the cycle's start.

  ### Arguments

  * `interval` is a `t:Tempo.Interval.t/0`, as `parts/1` gives it.

  ### Returns

  * The interval, its end rewritten when it is the cycle's end.

  ### Examples

      iex> {:ok, [last_hour]} = Tempo.Interval.Cycle.parts(~o"T23H/T0H")
      iex> Tempo.Interval.Cycle.wrapped(last_hour) == ~o"T23H/T0H"
      true

      iex> {:ok, [whole_day]} = Tempo.Interval.Cycle.parts(~o"T0H/T0H")
      iex> Tempo.Interval.Cycle.wrapped(whole_day) == ~o"T0H/T0H"
      true

  """
  @spec wrapped(Interval.t()) :: Interval.t()
  def wrapped(%Interval{} = interval) do
    if ends_turn?(interval),
      do: %{interval | to: next_turn_start(interval)},
      else: interval
  end

  @doc """
  The parts of a set of spans, in order, written back as spans: the part
  that runs to the cycle's end and the part that starts the cycle are the
  one span that runs through it, and any other part that ends at the
  cycle's end is written as `wrapped/1` writes it.

  ### Arguments

  * `parts` is a list of `t:Tempo.Interval.t/0`, each inside one turn of
    the cycle, in order of their starts.

  ### Returns

  * A list of `t:Tempo.Interval.t/0`.

  ### Examples

      iex> {:ok, parts} = Tempo.Interval.Cycle.parts(~o"T22H/T2H")
      iex> parts |> Enum.reverse() |> Tempo.Interval.Cycle.joined()
      [~o"T22H/T2H"]

  """
  @spec joined([Interval.t()]) :: [Interval.t()]
  def joined([%Interval{from: %Tempo{time: from_time}} = first, _second | _rest] = parts) do
    last = List.last(parts)

    if at_start?(elem(split_unspecified_year(from_time), 1)) and ends_turn?(last) do
      middle = parts |> tl() |> Enum.drop(-1)
      Enum.map(middle, &wrapped/1) ++ [%{last | to: first.to}]
    else
      Enum.map(parts, &wrapped/1)
    end
  end

  def joined(parts), do: Enum.map(parts, &wrapped/1)

  @doc """
  Whether an interval, as `parts/1` gives it, ends where its cycle does.

  ### Arguments

  * `interval` is a `t:Tempo.Interval.t/0`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> {:ok, [evening, morning]} = Tempo.Interval.Cycle.parts(~o"T22H/T2H")
      iex> {Tempo.Interval.Cycle.ends_turn?(evening), Tempo.Interval.Cycle.ends_turn?(morning)}
      {true, false}

  """
  @spec ends_turn?(Interval.t()) :: boolean()
  def ends_turn?(%Interval{from: %Tempo{time: [{:year, year} | _rest]}}) when year != :any,
    do: false

  def ends_turn?(%Interval{from: %Tempo{} = from, to: %Tempo{time: to_time}}) do
    {_year, to_units} = split_unspecified_year(to_time)
    at_end?(to_units, Compare.effective_calendar(from.calendar))
  end

  def ends_turn?(%Interval{}), do: false

  @doc """
  The start of the cycle's next turn, written as the end of an interval
  that runs to the cycle's end is: each of its units at its first value.

  ### Arguments

  * `interval` is a `t:Tempo.Interval.t/0` with an end.

  ### Returns

  * A `t:Tempo.t/0`.

  ### Examples

      iex> {:ok, [evening, _morning]} = Tempo.Interval.Cycle.parts(~o"T22H/T2H")
      iex> Tempo.Interval.Cycle.next_turn_start(evening)
      ~o"T0H"

  """
  @spec next_turn_start(Interval.t()) :: Tempo.t()
  def next_turn_start(%Interval{to: %Tempo{time: to_time} = to}) do
    {to_year, to_units} = split_unspecified_year(to_time)
    %{to | time: to_year ++ start_of(to_units)}
  end

  @doc """
  The microseconds a span on a cycle of fixed units covers: a time of day,
  or a day of the week.

  ### Arguments

  * `interval` is a `t:Tempo.Interval.t/0` with no year.

  ### Returns

  * `{:ok, microseconds}`.

  * `{:error, exception}` for a span of months and days, whose length is
    the year's it has not got, and for what `parts/1` refuses.

  ### Examples

      iex> Tempo.Interval.Cycle.microseconds(~o"T22H/T2H")
      {:ok, 14_400_000_000}

      iex> Tempo.Interval.Cycle.microseconds(~o"T10H/T10H")
      {:ok, 86_400_000_000}

  """
  @spec microseconds(Interval.t()) :: {:ok, non_neg_integer()} | {:error, Exception.t()}
  def microseconds(%Interval{} = interval) do
    with {:ok, parts} <- parts(interval) do
      Enum.reduce_while(parts, {:ok, 0}, &add_length(&1, &2, interval))
    end
  end

  defp add_length(%Interval{from: from, to: to}, {:ok, total}, interval) do
    case {position(from), position(to)} do
      {{:ok, from_at}, {:ok, to_at}} -> {:cont, {:ok, total + max(to_at - from_at, 0)}}
      _no_fixed_position -> {:halt, {:error, no_length_error(interval)}}
    end
  end

  # A point's microseconds from the start of a cycle whose units have one
  # length each: the day's clock, and the days of the week.
  defp position(%Tempo{time: time}) do
    {_year, units} = split_unspecified_year(time)

    Enum.reduce_while(units, {:ok, 0}, fn
      {:day_of_week, day}, {:ok, at} ->
        {:cont, {:ok, at + (day - 1) * @seconds_per_day * @microseconds}}

      {:hour, hour}, {:ok, at} ->
        {:cont, {:ok, at + hour * 3_600 * @microseconds}}

      {:minute, minute}, {:ok, at} ->
        {:cont, {:ok, at + minute * 60 * @microseconds}}

      {:second, second}, {:ok, at} ->
        {:cont, {:ok, at + second * @microseconds}}

      {:microsecond, {value, _precision}}, {:ok, at} ->
        {:cont, {:ok, at + value}}

      _another_unit, _at ->
        {:halt, :none}
    end)
  end

  defp split_unspecified_year([{:year, :any} = year | rest]), do: {[year], rest}
  defp split_unspecified_year(time), do: {[], time}

  # The end of the cycle a time list is on: its leading unit one past the last
  # value it takes with nothing before it, and each unit after it at its first.
  defp end_of_cycle([{unit, _value} | rest], calendar) do
    case last_value(unit, calendar) do
      {:ok, last} -> {:ok, [{unit, last + 1} | start_of(rest)]}
      :none -> :no_cycle
    end
  end

  defp end_of_cycle([], _calendar), do: :no_cycle

  defp at_end?([{unit, value} | rest], calendar),
    do: last_value(unit, calendar) == {:ok, value - 1} and at_start?(rest)

  defp at_end?([], _calendar), do: false

  # The last value a unit takes with no unit before it, in the year that has
  # the most: the twelfth month, a Hebrew thirteenth, hour 23, the seventh
  # day of the week.
  defp last_value(unit, calendar) do
    case Mask.at_most(unit, [], calendar) do
      {:ok, %Range{last: last}} -> {:ok, last}
      {:error, _reason} -> :none
    end
  end

  defp start_of(time), do: Enum.map(time, &minimum/1)

  defp minimum({:microsecond, {_value, precision}}), do: {:microsecond, {0, precision}}
  defp minimum({unit, _value}), do: {unit, Compare.unit_minimum(unit)}

  defp at_start?(time), do: Enum.all?(time, &(&1 == minimum(&1)))

  # A bare day or week has no cycle of one length: the days of no month, the
  # weeks of no year.
  defp no_cycle_error(interval) do
    UnanchoredError.exception(
      operation:
        "read where #{inspect(interval)} ends: it runs past the last value of its " <>
          "leading unit, whose count depends on a year or a month the span does not have",
      reason: :comparison
    )
  end

  defp no_length_error(interval) do
    UnanchoredError.exception(
      operation:
        "measure #{inspect(interval)}: the length of a span of months and days depends " <>
          "on the year",
      reason: :measure
    )
  end

  defp crosses_error(interval) do
    IntervalEndpointsError.exception(
      interval: interval,
      operation: :compare,
      reason:
        "#{inspect(interval)} has no year and does not end after it starts, so it runs " <>
          "through the end of its cycle and is two spans in any one turn of it: ask of both with " <>
          "the set operations (`Tempo.overlaps?/2`, `Tempo.intersection/2`)."
    )
  end
end
