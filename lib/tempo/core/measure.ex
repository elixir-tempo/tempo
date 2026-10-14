defmodule Tempo.Measure do
  @moduledoc false
  # Lengths: the duration an expression covers, the duration between two
  # values, and the predicates that compare a length with a duration.
  #
  # A singular value is one unit of its resolution long: a month is `P1M`,
  # whichever month. Anything else is measured as the time it covers, in the
  # unit it is written to: a span of days in days, a span of hours in elapsed
  # hours, a set in the unit of its finest member, summed over the spans it
  # covers once. An open end, or a sequence with none, is `:infinity`. A
  # duration is compared with a value by laying it from the value's start,
  # so a month is as long as the month it starts in.

  alias Tempo.{
    Algebra,
    ConversionError,
    Duration,
    IntervalEndpointsError,
    Season,
    Shift,
    Spans,
    Unit,
    Walk
  }

  @type measure ::
          {:ok, :infinity | {integer(), integer(), Algebra.frame()}} | {:error, Exception.t()}

  # ── Duration ──────────────────────────────────────────────────────────

  @doc "The duration an expression covers, in its own unit."
  @spec duration(Tempo.t() | Duration.t()) :: Duration.t() | :infinity | {:error, Exception.t()}
  def duration(%Duration{} = duration), do: {:error, conversion(duration, :bare_duration)}

  def duration(%Tempo{form: {:value, units}} = value) do
    cond do
      Keyword.has_key?(units, :selection) -> {:error, conversion(value, :selection)}
      Keyword.has_key?(units, :season) -> covered_duration(value)
      shown_by_a_clock?(value, units) -> covered_duration(value)
      Unit.concrete?(units) -> unit_duration(List.last(units))
      true -> covered_duration(value)
    end
  end

  def duration(%Tempo{} = expression), do: covered_duration(expression)

  # An hour, a minute or a second in a named zone is as long as the zone's
  # clock shows it, which is not always one of it: half an hour where the
  # clock skips the other half.
  defp shown_by_a_clock?(%Tempo{zone: %Tempo.Zone{name: name}}, units) when is_binary(name),
    do: Unit.concrete?(units) and Unit.resolution(units) in [:hour, :minute, :second]

  defp shown_by_a_clock?(_value, _units), do: false

  defp unit_duration({:group, {_nth, [{unit, size}]}}),
    do: Duration.multiply(Shift.one(unit), size)

  defp unit_duration({:microsecond, {_, precision}}),
    do: %Duration{units: [second: 0, microsecond: {Integer.pow(10, 6 - precision), precision}]}

  defp unit_duration({unit, _held}), do: Shift.one(unit)

  defp covered_duration(expression) do
    case measure(expression) do
      {:ok, :infinity} ->
        :infinity

      # A set with no members covers no time, and has no resolution to count it in.
      {:ok, {_ticks, _start, _frame, []}} ->
        %Duration{units: [second: 0]}

      {:ok, {_ticks, _start, _frame, covered}} ->
        counted(covered, resolution(expression), Spans.frame_of(expression), expression)

      {:error, _} = error ->
        error
    end
  end

  # The covered spans counted in a unit and summed.
  defp counted(covered, unit, frame, expression) do
    counts =
      Enum.map(covered, fn {start, stop} -> count({start, stop}, unit, frame, expression) end)

    case Enum.find(counts, &match?({:error, _}, &1)) do
      nil when unit in [:hour, :minute, :second] ->
        clock_length(
          unit,
          covered |> Enum.map(fn {start, stop} -> stop - start end) |> Enum.sum()
        )

      nil ->
        counted_in(unit, counts |> Enum.map(&elem(&1, 1)) |> Enum.sum())

      error ->
        error
    end
  end

  # A length on the clock in a unit and, where it is not whole units of it,
  # the finer units that are left: an hour and a half is `PT1H30M` and half
  # an hour `PT30M`, where a count of whole hours would say one and none.
  defp clock_length(unit, ticks) do
    {parts, _left} =
      [:hour, :minute, :second]
      |> Enum.drop_while(&(&1 != unit))
      |> Enum.map_reduce(ticks, fn finer, left ->
        {{finer, div(left, Unit.ticks(finer))}, rem(left, Unit.ticks(finer))}
      end)

    case Enum.reject(parts, fn {_unit, count} -> count == 0 end) do
      [] -> %Duration{units: [{unit, 0}]}
      units -> %Duration{units: units}
    end
  end

  # A count of a unit as a duration; of a fraction, as seconds and their fraction.
  defp counted_in({:microsecond, precision}, microseconds) do
    %Duration{
      units: [
        second: div(microseconds, 1_000_000),
        microsecond: {rem(microseconds, 1_000_000), precision}
      ]
    }
  end

  # A unit that is a label (a quarter, a day of the week) is counted in the
  # unit it is found by, and the count is of that unit: an interval of one
  # quarter is three months counted, and is three months.
  defp counted_in(unit, count), do: Duration.multiply(Shift.one(Unit.grain(unit)), count)

  defp count({start, stop}, {:microsecond, _}, _frame, _expression), do: {:ok, stop - start}

  defp count({start, stop}, unit, frame, expression) do
    cond do
      Unit.clock?(unit) -> {:ok, div(stop - start, Unit.ticks(unit))}
      match?({:cycle, _}, frame.frame) -> {:error, conversion(expression, :needs_a_year)}
      unit in [:decade, :century] -> scaled_count({start, stop}, unit, frame, expression)
      true -> walk_count({start, stop}, Unit.grain(unit), frame, expression)
    end
  end

  defp scaled_count(span, unit, frame, expression) do
    with {:ok, years} <- walk_count(span, :year, frame, expression),
         do: {:ok, div(years, if(unit == :decade, do: 10, else: 100))}
  end

  defp walk_count(span, unit, frame, expression) do
    case Walk.count(span, unit, frame) do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, conversion(expression, reason)}
    end
  end

  # The unit an expression is written to: its finest end or member.
  defp resolution(%Tempo{form: {:value, units}}), do: finest_unit(units)

  defp resolution(%Tempo{form: {:span, from, to}}),
    do: [from, to] |> Enum.reject(&(&1 == :open)) |> Enum.map(&resolution/1) |> finest()

  defp resolution(%Duration{units: units}), do: finest_unit(units)

  defp resolution(%Tempo{form: {:every, first, _, _}}), do: resolution(first)

  defp resolution(%Tempo{form: {_kind, members}}),
    do: members |> Enum.map(&resolution/1) |> finest()

  defp finest_unit(units) do
    case List.last(units) do
      {:microsecond, {_, precision}} -> {:microsecond, precision}
      {:season, season} -> season_unit(season)
      _ -> Unit.resolution(units)
    end
  end

  # There is no unit of one season. A meteorological season is whole months
  # and is counted in them; an astronomical one begins and ends within a
  # month and is counted in days.
  defp season_unit(season), do: if(Season.abstract?(season), do: :month, else: :day)

  defp finest(units), do: Enum.max_by(units, &index/1)
  defp index({:microsecond, precision}), do: 100 + precision
  defp index(unit), do: Unit.rank(Unit.grain(unit)) || 0

  @doc "The duration from the start of one value to the start of another, in their finer unit."
  @spec between(Tempo.t(), Tempo.t()) :: {:ok, Duration.t()} | {:error, Exception.t()}
  def between(%Tempo{} = from, %Tempo{} = to) do
    with {:ok, _frame, pa, pb} <- Algebra.aligned(from, to, []),
         {:ok, {start, _}} <- Algebra.single(pa, from, to),
         {:ok, {stop, _}} <- Algebra.single(pb, from, to),
         :ok <- ordered(start, stop, from, to),
         unit = finest([resolution(from), resolution(to)]),
         {:ok, count} <- count({start, stop}, unit, Spans.frame_of(from), from) do
      {:ok, counted_in(unit, count)}
    end
  end

  def between(from, to) do
    {:error, IntervalEndpointsError.exception(from: from, to: to, reason: :not_values)}
  end

  defp ordered(start, stop, _from, _to) when start < stop, do: :ok

  defp ordered(_start, _stop, from, to),
    do: {:error, IntervalEndpointsError.exception(from: from, to: to, reason: :order)}

  # ── Measuring ─────────────────────────────────────────────────────────

  @doc "An expression's covered time: its ticks, its start, its frame and its covered spans, or :infinity."
  @spec measure(Tempo.t()) ::
          {:ok, :infinity | {integer(), integer(), Algebra.frame(), [{integer(), integer()}]}}
          | {:error, Exception.t()}
  def measure(%Tempo{form: {:every, _, :infinity, _}}), do: {:ok, :infinity}

  def measure(%Tempo{} = expression) do
    with :ok <- Spans.whole(expression) do
      if open?(expression), do: {:ok, :infinity}, else: measured(expression)
    end
  end

  defp measured(expression) do
    with {:ok, frame, positioned} <- Algebra.positioned(expression, []) do
      covered = positioned |> Algebra.covered(1, frame) |> Enum.map(&{&1.start, &1.stop})
      ticks = covered |> Enum.map(fn {s, e} -> e - s end) |> Enum.sum()
      {:ok, {ticks, covered |> Enum.map(&elem(&1, 0)) |> Enum.min(fn -> 0 end), frame, covered}}
    end
  end

  defp open?(%Tempo{form: {:span, from, to}}), do: from == :open or to == :open

  defp open?(%Tempo{form: {kind, members}}) when kind in [:all, :one],
    do: Enum.any?(members, &open?/1)

  defp open?(_expression), do: false

  # ── Predicates ────────────────────────────────────────────────────────

  @doc "Whether a comparison of an expression's length with a duration laid from its start holds."
  @spec holds?(:at_least | :at_most | :exactly | :longer | :shorter, Tempo.t(), Duration.t()) ::
          boolean() | {:error, Exception.t()}
  def holds?(comparison, %Tempo{} = expression, %Duration{} = duration) do
    case measure(expression) do
      {:ok, :infinity} ->
        comparison in [:at_least, :longer]

      {:ok, {ticks, start, _frame, _covered}} ->
        compared(comparison, ticks, laid(duration, start, Spans.frame_of(expression), expression))

      {:error, _} = error ->
        error
    end
  end

  def holds?(_comparison, %Duration{} = duration, _by),
    do: {:error, conversion(duration, :bare_duration)}

  def holds?(_comparison, %Tempo{}, by), do: {:error, conversion(by, :not_a_duration)}

  # An exact duration is its ticks anywhere; a month or a year is laid from the start.
  defp laid(duration, start, frame, expression) do
    if Duration.exact?(duration) do
      Duration.to_microseconds(duration)
    else
      with {:ok, stop} <- Spans.shifted(start, duration, frame, expression),
           do: {:ok, stop - start}
    end
  end

  defp compared(_comparison, _ticks, {:error, _} = error), do: error
  defp compared(:at_least, ticks, {:ok, length}), do: ticks >= length
  defp compared(:at_most, ticks, {:ok, length}), do: ticks <= length
  defp compared(:exactly, ticks, {:ok, length}), do: ticks == length
  defp compared(:longer, ticks, {:ok, length}), do: ticks > length
  defp compared(:shorter, ticks, {:ok, length}), do: ticks < length

  defp conversion(expression, reason),
    do: ConversionError.exception(value: expression, reason: reason)
end
