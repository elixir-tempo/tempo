defmodule Tempo.Scale do
  @moduledoc false

  # Positions and frames: where a value's span begins and ends, on the
  # frame it lies on.
  #
  # A value with a year lies on a line, the UTC line when it has a zone or
  # a written shift and the floating line when it has neither, and its
  # positions are ticks (microseconds since 0000-01-01). A value with no
  # year lies on the cycle of its coarsest unit, and its positions are
  # tuples of its units from that unit down to a part of a second, which
  # Erlang orders as the cycle does. Two positions compare only on one
  # frame; `Tempo.Algebra` and `Tempo.Allen` see to that.
  #
  # By law 3 a value's span is `[v, next(v))`. A span of a calendar
  # resolution ends where the next period begins on the calendar, each end
  # read on the clock of its own moment, so a day across a change of the
  # clock is 23 or 25 hours long. A span of a clock resolution is one unit
  # of elapsed time from its start.

  alias Tempo.Unit
  alias Tempo.Zone

  @day 86_400_000_000

  @type frame :: :utc | :floating | {:cycle, Unit.t()}
  @type position :: integer() | tuple()

  @doc "The frame a value's units lie on, given its zone and shift."
  @spec frame(Unit.units(), Zone.t() | nil, Zone.shift() | nil) :: frame()
  def frame(units, zone, shift) do
    cond do
      not Unit.anchored?(units) -> {:cycle, Unit.coarsest(units)}
      zone != nil or shift != nil -> :utc
      true -> :floating
    end
  end

  @doc """
  The half-open extent of a concrete value: its start and its end on its
  frame. The units are concrete and coarsest first.
  """
  @spec extent(Unit.units(), module(), Zone.t() | nil, Zone.shift() | nil) ::
          {:ok, {position(), position()}} | {:error, term()}
  def extent(units, calendar, zone, shift) do
    case frame(units, zone, shift) do
      {:cycle, coarsest} -> cycle_extent(units, coarsest)
      frame -> line_extent(units, calendar, zone, shift, frame)
    end
  end

  @doc "Orders two positions of one frame."
  @spec compare(position(), position()) :: :lt | :eq | :gt
  def compare(a, b) when a < b, do: :lt
  def compare(a, b) when a > b, do: :gt
  def compare(_a, _b), do: :eq

  @doc "The ticks in a day."
  @spec ticks_per_day() :: 86_400_000_000
  def ticks_per_day, do: @day

  # ── A value on a line ─────────────────────────────────────────────────

  defp line_extent(units, calendar, zone, shift, frame) do
    date_units = Unit.date_units(units)
    clock_units = Unit.clock_units(units)

    with {:ok, {first, after_last}} <- Tempo.Calendar.span_of(calendar, date_units) do
      start_wall = first * @day + clock_ticks(clock_units)
      start = placed(start_wall, zone, shift, frame)

      stop =
        case clock_units do
          [] -> placed(after_last * @day, zone, shift, frame)
          _ -> start + resolution_ticks(clock_units)
        end

      {:ok, {start, stop}}
    end
  end

  defp placed(wall, _zone, _shift, :floating), do: wall
  defp placed(wall, zone, shift, :utc), do: Zone.utc_of_wall(zone, shift, wall)

  defp clock_ticks(clock_units) do
    Enum.reduce(clock_units, 0, fn
      {:microsecond, {microseconds, _precision}}, sum -> sum + microseconds
      {unit, value}, sum -> sum + value * Unit.ticks(unit)
    end)
  end

  # One unit of the finest clock unit written: a second written to one
  # decimal place is a tenth of a second long.
  defp resolution_ticks(clock_units) do
    case List.last(clock_units) do
      {:microsecond, {_, precision}} -> Integer.pow(10, 6 - precision)
      {unit, _} -> Unit.ticks(unit)
    end
  end

  # ── A value on a cycle ────────────────────────────────────────────────

  # The position is the tuple of the chain's units, each as written or at its
  # minimum; the end is the same tuple with the finest written unit one on.
  defp cycle_extent(units, coarsest) do
    case Unit.cycle_chain(coarsest) do
      nil ->
        {:error, {:no_cycle, coarsest}}

      chain ->
        {resolution, _} = List.last(units)
        start = Enum.map(chain, fn unit -> written(units, unit) end)

        stop =
          Enum.map(chain, fn
            ^resolution -> written(units, resolution) + step(units, resolution)
            unit -> written(units, unit)
          end)

        {:ok, {List.to_tuple(start), List.to_tuple(stop)}}
    end
  end

  defp written(units, :microsecond) do
    case Keyword.get(units, :microsecond) do
      {microseconds, _precision} -> microseconds
      nil -> 0
    end
  end

  defp written(units, unit), do: Keyword.get(units, unit, Unit.minimum(unit))

  defp step(units, :microsecond) do
    {_, precision} = Keyword.fetch!(units, :microsecond)
    Integer.pow(10, 6 - precision)
  end

  defp step(_units, _unit), do: 1
end
