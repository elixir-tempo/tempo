defmodule Tempo.Children do
  @moduledoc false

  # What `Enum` yields for an expression (law 6) and its readings. A
  # singular expression's children are its values one unit below its
  # resolution, walked lazily; a plural one's are its members. The
  # readings of an expression are the values an uncertain one may be, for
  # `Tempo.certainty/3`: each margin's year, each member of a one-of set.

  # ── Children (law 6) ──────────────────────────────────────────────────

  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Expand
  alias Tempo.Limit
  alias Tempo.Scale
  alias Tempo.Season
  alias Tempo.Spans
  alias Tempo.Unit
  alias Tempo.Walk

  @doc """
  What `Enum` yields for an expression (law 6): a singular expression's
  children, the values one unit below its resolution (the finer of its ends'
  for a written span), each a value in the expression's frame; a plural
  expression's members.
  """
  @spec children(Tempo.t() | Duration.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def children(expression, options \\ [])

  def children(%Tempo{} = expression, options) do
    if Spans.singular?(expression),
      do: walk(expression, child_unit(expression), options),
      else: Spans.members(expression, options)
  end

  def children(%Duration{} = duration, _options),
    do: {:error, conversion(duration, :bare_duration)}

  @doc "The unit one below an expression's resolution: what its walk yields when none is named."
  @spec child_unit(Tempo.t()) :: Unit.t() | {:microsecond, 1..6} | nil
  def child_unit(%Tempo{form: {:value, units}}) do
    case List.last(units) do
      {:group, {_nth, [{unit, _size}]}} -> unit
      _ -> below(Unit.resolution(units), units)
    end
  end

  def child_unit(%Tempo{form: {:span, from, to}}) do
    [from, to]
    |> Enum.flat_map(&end_resolution/1)
    |> Enum.max_by(fn {unit, _} -> Unit.rank(unit) || 0 end, fn ->
      nil
    end)
    |> then(fn
      nil -> nil
      {unit, units} -> own(unit, units)
    end)
  end

  def child_unit(_plural), do: nil

  defp end_resolution(%Tempo{form: {:value, units}}), do: [{Unit.resolution(units), units}]
  defp end_resolution(%Duration{units: units}), do: [{units |> List.last() |> elem(0), units}]
  defp end_resolution(_open), do: []

  # A value's children are one unit down; a label's are the hours of its day, a group's the units it groups.
  defp below(:microsecond, units) do
    case Keyword.fetch!(units, :microsecond) do
      {_, 6} -> nil
      {_, precision} -> {:microsecond, precision + 1}
    end
  end

  defp below(:second, _units), do: {:microsecond, 1}
  defp below(unit, _units) when unit in [:day_of_week, :day_of_year], do: :hour
  defp below(unit, _units) when unit in [:quarter, :season, :traditional_month], do: :day
  defp below(:group, units), do: units |> Keyword.fetch!(:group) |> elem(1) |> hd() |> elem(0)
  defp below(unit, _units), do: Unit.child(unit)

  # A span is walked at its own resolution: `2026/2028` by years, `T09/T17` by hours.
  defp own(:microsecond, units),
    do: {:microsecond, units |> Keyword.fetch!(:microsecond) |> elem(1)}

  defp own(unit, _units) when unit in [:day_of_week, :day_of_year], do: :day
  defp own(:traditional_month, _units), do: :month

  # A meteorological season is whole months; an astronomical one is not.
  defp own(:season, units) do
    if Season.abstract?(Keyword.fetch!(units, :season)), do: :month, else: :day
  end

  defp own(:group, units), do: units |> Keyword.fetch!(:group) |> elem(1) |> hd() |> elem(0)
  defp own(unit, _units), do: unit

  @doc """
  An expression walked at a unit: a singular expression's extent stepped at
  the unit (`Tempo.Walk`), each step a value in the expression's frame; a
  plural expression's members each walked in turn.
  """
  @spec walk(Tempo.t(), Unit.t() | {:microsecond, 1..6} | nil, keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def walk(expression, unit, options \\ [])

  def walk(%Tempo{} = expression, nil, _options),
    do: {:error, conversion(expression, :nothing_finer)}

  def walk(%Tempo{} = expression, unit, options) do
    if Spans.singular?(expression) do
      with {:ok, {start, stop}} <- Spans.extent(expression),
           :ok <- walkable(start, expression),
           {:ok, steps} <- steps(expression, {start, stop}, unit) do
        {:ok, Stream.map(steps, &stepped(expression, &1))}
      end
    else
      with {:ok, members} <- Spans.members(expression, options) do
        {:ok, Stream.flat_map(members, fn member -> walk!(member, unit, options) end)}
      end
    end
  end

  # On a line the extent is stepped; on a cycle a value's children come from
  # the calendar's counts, and a span's from the cycle's values run through
  # its end (`12M/2M` is December, January and February).
  defp steps(expression, extent, unit) do
    case Spans.frame(expression) do
      {:cycle, coarsest} -> cycle_steps(expression, extent, unit, coarsest)
      _line -> Walk.steps(extent, unit, Spans.frame_of(expression)) |> walk_error(expression)
    end
  end

  # A cycle value's children come from the calendar's counts; a cycle span is
  # stepped by the clock through midnight, or through the cycle's own values
  # from its start through its end (`12M/2M` is December, January and February).
  defp cycle_steps(%Tempo{form: {:value, units}} = value, {start, stop}, unit, coarsest) do
    if Spans.clock_unit?(unit) and Unit.clock?(coarsest) do
      {:ok, Walk.cycle_clock_steps(start, stop, unit)}
    else
      case Expand.children(units, unit, Spans.frame_of(value)) do
        {:ok, children} ->
          {:ok, Enum.map(children, &cycle_child(&1, units, unit, coarsest, value.calendar))}

        {:error, reason} ->
          {:error, conversion(value, reason)}
      end
    end
  end

  defp cycle_steps(%Tempo{form: {:span, from, to}} = span, {start, stop}, unit, coarsest) do
    cond do
      Spans.clock_unit?(unit) and Unit.clock?(coarsest) ->
        {:ok, Walk.cycle_clock_steps(start, stop, unit)}

      unit == coarsest and match?(%Tempo{}, from) and match?(%Tempo{}, to) ->
        with {:ok, children} <-
               Expand.children([], unit, Spans.frame_of(span)) |> walk_error(span) do
          values = Enum.map(children, &elem(&1, 0))
          {:ok, Enum.map(rotated(values, held(from, unit), held(to, unit)), &[{unit, &1}])}
        end

      true ->
        {:error, conversion(span, :needs_a_year)}
    end
  end

  defp held(%Tempo{form: {:value, units}}, unit), do: Keyword.get(units, unit)

  # A child of a group on a cycle is read back from its place on the cycle (`6M2G10DU` walks `6M11D`).
  defp cycle_child({held, span}, units, unit, coarsest, calendar) do
    case {Keyword.has_key?(units, :group), span} do
      {true, {start, _}} when is_integer(start) ->
        Scale.cycle_units(start, coarsest, unit, calendar)

      _ ->
        Unit.cyclic(units) ++ [{unit, held}]
    end
  end

  # The cycle's values from one through another, running on through the cycle's end.
  defp rotated(values, from, through) do
    rotated =
      values |> Stream.cycle() |> Stream.drop_while(&(&1 != from)) |> Enum.take(length(values))

    case Enum.find_index(rotated, &(&1 == through)) do
      nil -> rotated
      index -> Enum.take(rotated, index + 1)
    end
  end

  defp walkable(nil, expression), do: {:error, conversion(expression, :open)}
  defp walkable(_start, _expression), do: :ok

  defp walk_error({:ok, steps}, _expression), do: {:ok, steps}
  defp walk_error({:error, reason}, expression), do: {:error, conversion(expression, reason)}

  defp walk!(member, unit, options) do
    case walk(member, unit, options) do
      {:ok, stream} -> stream
      {:error, exception} -> raise exception
    end
  end

  # A step as a value of the expression's frame, keeping the marks on the units it shares with its source.
  defp stepped(source, {:shifted, units, shift}), do: %{stepped(source, units) | shift: shift}

  defp stepped(%Tempo{form: {:span, from, to}} = span, units),
    do: stepped(%{Spans.first_value([from, to]) | metadata: span.metadata}, units)

  defp stepped(%Tempo{form: {:value, own}} = source, units) do
    %Tempo{
      form: {:value, units},
      calendar: source.calendar,
      zone: source.zone,
      shift: source.shift,
      qualifications: shared_marks(source.qualifications, own, units),
      metadata: source.metadata
    }
  end

  defp stepped(%Tempo{} = source, units),
    do: %Tempo{
      form: {:value, units},
      calendar: source.calendar,
      zone: source.zone,
      metadata: source.metadata
    }

  defp shared_marks(nil, _own, _units), do: nil

  defp shared_marks(marks, own, units) do
    kept =
      for {unit, mark} <- marks,
          Keyword.get(own, unit) == Keyword.get(units, unit),
          into: %{},
          do: {unit, mark}

    if kept == %{}, do: nil, else: kept
  end

  # ── Readings ──────────────────────────────────────────────────────────

  @doc """
  The readings of an uncertain expression, each as an extent: the members of
  a one-of set, each placing of a year with a margin, each value a mask
  allows; an interval with uncertain ends, each pairing of their readings in
  order. An expression with one reading is its own extent.
  """
  @spec readings(Tempo.t() | Duration.t()) ::
          {:ok, [{Scale.position(), Scale.position()}]} | {:error, Exception.t()}
  def readings(%Tempo{form: {:one, members}}), do: each_readings(members, &readings/1)
  def readings(%Duration{} = duration), do: {:error, conversion(duration, :bare_duration)}

  def readings(%Tempo{form: {:value, units}} = value) do
    with {:ok, placings} <- placings(value, units), do: closed_extents(placings, value)
  end

  def readings(%Tempo{form: {:span, from, to}} = span) do
    if margin?(from) or margin?(to),
      do: paired_readings(span),
      else: spans_readings(span)
  end

  # A recurrence with no end has no finite readings to judge.
  def readings(%Tempo{form: {:every, _, :infinity, _}} = recurrence),
    do: {:error, conversion(recurrence, :unbounded)}

  # A set, a recurrence or a member with conditions has the readings of the spans it names.
  def readings(%Tempo{} = expression), do: spans_readings(expression)

  # The extents of each of several, or the first error.
  defp each_readings(expressions, read) do
    Enum.reduce_while(expressions, {:ok, []}, fn expression, {:ok, acc} ->
      case read.(expression) do
        {:ok, extents} -> {:cont, {:ok, acc ++ extents}}
        error -> {:halt, error}
      end
    end)
  end

  # The extent of each expression, every one closed at both ends.
  defp closed_extents(expressions, source) do
    each_readings(expressions, fn expression ->
      case Spans.extent(expression) do
        {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> {:ok, [{start, stop}]}
        {:ok, _open} -> {:error, conversion(source, :open)}
        error -> error
      end
    end)
  end

  defp margin?(%Tempo{form: {:value, units}}),
    do: Enum.any?(units, &match?({_, {n, [margin: _]}} when is_integer(n), &1))

  defp margin?(_other), do: false

  # A span with a margin at an end is each pairing of its ends' readings in order, on through a cycle's end.
  defp paired_readings(%Tempo{form: {:span, from, to}} = span) do
    with {:ok, starts} <- readings(from),
         {:ok, ends} <- readings(to) do
      pairs =
        for {start, _} <- starts,
            stop <- Enum.map(ends, &end_of_reading(&1, to)),
            stop = wrapped_stop(start, stop, span),
            start < stop,
            do: {start, stop}

      if pairs == [], do: {:error, conversion(span, :open)}, else: {:ok, pairs}
    end
  end

  defp end_of_reading({stop_start, stop_end}, to),
    do: if(Spans.clock_resolution?(to), do: stop_start, else: stop_end)

  defp wrapped_stop(start, stop, span) when stop <= start do
    case Spans.frame(span) do
      {:cycle, coarsest} ->
        case Scale.cycle_length(coarsest, span.calendar) do
          {:ok, length} -> stop + length
          {:error, _} -> stop
        end

      _line ->
        stop
    end
  end

  defp wrapped_stop(_start, stop, _span), do: stop

  # Any other span is the spans it names, each an extent: a plural end gives one for each value.
  defp spans_readings(span) do
    with {:ok, spans} <- Spans.spans(span),
         {:ok, spans} <- Limit.take(spans, span),
         do: closed_extents(spans, span)
  end

  # A year with a margin is each year it may be; a value with a mask or a set each value it allows.
  defp placings(value, units) do
    case Enum.find(units, fn {_, held} -> match?({n, [margin: _]} when is_integer(n), held) end) do
      {unit, {n, [margin: m]}} ->
        {:ok,
         for(
           placed <- (n - m)..(n + m),
           do: %{value | form: {:value, Keyword.put(units, unit, placed)}}
         )}

      nil ->
        single_or_members(value, units)
    end
  end

  defp single_or_members(value, units) do
    if Expand.one_span?(units),
      do: {:ok, [value]},
      else: with({:ok, members} <- Spans.members(value), do: Limit.take(members, value))
  end

  defp conversion(expression, {:no_such_value, _}),
    do: ConversionError.exception(value: expression, reason: :no_such_value)

  defp conversion(expression, reason),
    do: ConversionError.exception(value: expression, reason: reason)
end
