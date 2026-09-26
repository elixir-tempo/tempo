defmodule Tempo.Network.Normalize do
  @moduledoc """
  Reduce a `t:Tempo.Network.t/0` to a Simple Temporal Problem: a
  set of boundary nodes and integer-weighted constraints of the single
  shape `b₁ − b₂ ≤ k`.

  Every period contributes a `start` and an `end` boundary; a single
  shared origin `z₀` (`:origin`) anchors absolute dates. The network's
  **finest unit** (the finest resolution among its dates) fixes the
  integer axis: a date becomes its count of that unit relative to `z₀`,
  a duration its count of that unit.

  The output feeds `Tempo.Network.Solver`. Conversion is exact when the
  network is uniform-unit (as the canonical year-grained chronologies
  are); a duration expressed across units (e.g. years on a day axis)
  uses nominal calendar lengths and is rounded.

  """

  alias Tempo.Compare
  alias Tempo.Network
  alias Tempo.Network.Relation

  # Coarsest → finest. The finest unit *present* fixes the axis.
  @unit_order [:year, :month, :week, :day, :hour, :minute, :second]

  @days_per_year 365.2425
  @days_per_month 30.436875

  @type boundary :: Relation.boundary()

  @typedoc """
  A constraint `from − to ≤ weight`, tagged with the `source` that
  produced it (an absolute bound, duration, sequence link, relation, or
  the implicit non-negativity of a period) so the solver can build a
  trace.
  """
  @type edge :: {boundary(), boundary(), integer(), source()}

  @type source ::
          {:bound, :start | :end, :lower | :upper, term(), Tempo.t()}
          | {:duration, :min | :max, term(), Tempo.Duration.t()}
          | {:non_negative, term()}
          | {:sequence, term(), term()}
          | {:relation, Relation.t()}

  @type t :: %{nodes: [boundary()], edges: [edge()], unit: atom()}

  @doc """
  Normalise a network into `%{nodes, edges, unit}`.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  ### Returns

  * a map with `:nodes` (boundary variables including `:origin`),
    `:edges` (`{from, to, weight, source}` constraints meaning
    `from − to ≤ weight`), and `:unit` (the axis unit atom).

  ### Examples

      iex> network =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:k1, start: ~o"1200Y", duration: {:at_least, ~o"P20Y"})
      iex> normalized = Tempo.Network.Normalize.normalize(network)
      iex> normalized.unit
      :year
      iex> Enum.any?(normalized.edges, &match?({{:start, :k1}, {:end, :k1}, -20, _}, &1))
      true

  """
  @spec normalize(Network.t()) :: t()
  def normalize(%Network{} = network) do
    unit = finest_unit(network)

    period_edges =
      Enum.flat_map(network.periods, fn {id, period} ->
        period_constraints(id, period, unit)
      end)

    sequence_edges = Enum.flat_map(network.sequences, &sequence_constraints/1)

    relation_edges =
      Enum.flat_map(network.relations, fn relation ->
        relation
        |> Relation.to_atomic()
        |> Enum.map(fn atomic -> resolve_weight(atomic, unit, {:relation, relation}) end)
      end)

    edges = period_edges ++ sequence_edges ++ relation_edges
    nodes = edges |> Enum.flat_map(fn {from, to, _, _} -> [from, to] end) |> Enum.uniq()

    %{nodes: nodes, edges: edges, unit: unit}
  end

  @doc """
  The finest date resolution present in the network's period bounds.

  Defaults to `:year` when the network carries no dated bounds.

  ### Examples

      iex> Tempo.Network.new()
      ...> |> Tempo.Network.add_period(:a, start: "1200-06-15")
      ...> |> Tempo.Network.Normalize.finest_unit()
      :day

  """
  @spec finest_unit(Network.t()) :: atom()
  def finest_unit(%Network{} = network) do
    periods = Map.values(network.periods)

    date_units = periods |> Enum.flat_map(&date_bounds/1) |> Enum.map(&unit_of/1)

    # A relative network may carry no dates at all — only durations and
    # relations. Its durations then fix the axis, so a schedule of
    # day-length tasks measures in days rather than collapsing onto the
    # default year axis (where a `P1D` duration would round to zero).
    duration_units = periods |> Enum.flat_map(&duration_units/1)

    Enum.max_by(date_units ++ duration_units, &unit_rank/1, fn -> :year end)
  end

  # --- period → constraints --------------------------------------

  defp period_constraints(id, period, unit) do
    start = {:start, id}
    finish = {:end, id}

    [
      # A period never ends before it starts.
      {start, finish, 0, {:non_negative, id}}
    ]
    |> lower_bound(:origin, start, period.earliest_start, unit, {:bound, :start, :lower, id})
    |> upper_bound(start, :origin, period.latest_start, unit, {:bound, :start, :upper, id})
    |> lower_bound(:origin, finish, period.earliest_end, unit, {:bound, :end, :lower, id})
    |> upper_bound(finish, :origin, period.latest_end, unit, {:bound, :end, :upper, id})
    |> min_duration(start, finish, period.min_duration, unit, {:duration, :min, id})
    |> max_duration(start, finish, period.max_duration, unit, {:duration, :max, id})
  end

  # value(node) ≥ bound  ⇒  origin − node ≤ −bound.
  defp lower_bound(edges, origin, node, %Tempo{} = value, unit, {tag, edge, dir, id}) do
    [{origin, node, -date_axis(value, unit), {tag, edge, dir, id, value}} | edges]
  end

  defp lower_bound(edges, _origin, _node, nil, _unit, _source), do: edges

  # value(node) ≤ bound  ⇒  node − origin ≤ bound.
  defp upper_bound(edges, node, origin, %Tempo{} = value, unit, {tag, edge, dir, id}) do
    [{node, origin, date_axis(value, unit), {tag, edge, dir, id, value}} | edges]
  end

  defp upper_bound(edges, _node, _origin, nil, _unit, _source), do: edges

  # end − start ≥ min  ⇒  start − end ≤ −min.
  defp min_duration(edges, start, finish, %Tempo.Duration{} = duration, unit, {tag, kind, id}) do
    [{start, finish, -duration_axis(duration, unit), {tag, kind, id, duration}} | edges]
  end

  defp min_duration(edges, _start, _finish, nil, _unit, _source), do: edges

  # end − start ≤ max  ⇒  end − start ≤ max.
  defp max_duration(edges, start, finish, %Tempo.Duration{} = duration, unit, {tag, kind, id}) do
    [{finish, start, duration_axis(duration, unit), {tag, kind, id, duration}} | edges]
  end

  defp max_duration(edges, _start, _finish, nil, _unit, _source), do: edges

  # --- sequence → immediately-precedes links ---------------------

  defp sequence_constraints(period_ids) do
    period_ids
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [a, b] ->
      # end(a) = start(b).
      source = {:sequence, a, b}
      [{{:end, a}, {:start, b}, 0, source}, {{:start, b}, {:end, a}, 0, source}]
    end)
  end

  # --- relation duration weights → integers ----------------------

  defp resolve_weight({from, to, {:duration, duration}}, unit, source) do
    {from, to, duration_axis(duration, unit), source}
  end

  defp resolve_weight({from, to, {:neg_duration, duration}}, unit, source) do
    {from, to, -duration_axis(duration, unit), source}
  end

  defp resolve_weight({from, to, weight}, _unit, source) when is_integer(weight) do
    {from, to, weight, source}
  end

  # --- unit machinery --------------------------------------------

  defp date_bounds(period) do
    [
      period.earliest_start,
      period.latest_start,
      period.earliest_end,
      period.latest_end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp unit_of(%Tempo{} = value) do
    {unit, _factor} = Tempo.resolution(value)
    unit
  end

  # The finest unit present in a period's duration bounds (each a
  # `Tempo.Duration` whose `time` keyword list names its components).
  defp duration_units(period) do
    [period.min_duration, period.max_duration]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn %Tempo.Duration{time: time} ->
      Enum.find(Enum.reverse(@unit_order), :year, &Keyword.has_key?(time, &1))
    end)
  end

  defp unit_rank(unit), do: Enum.find_index(@unit_order, &(&1 == unit)) || 0

  # Convert a date to an integer count of `unit` relative to year 0, in the
  # proleptic Gregorian frame. A non-Gregorian bound is converted first, so
  # positions from different calendars share a single axis and the network's
  # difference constraints stay correct across calendars.
  defp date_axis(%Tempo{} = tempo, unit) do
    {year, month, day} = gregorian_ymd(tempo)
    axis_position(year, month, day, unit)
  end

  defp axis_position(year, _month, _day, :year), do: year
  defp axis_position(year, month, _day, :month), do: year * 12 + (month - 1)

  defp axis_position(year, month, day, :day) do
    {:ok, date} = Date.new(year, month, day)
    Date.to_gregorian_days(date)
  end

  # The bound's `{year, month, day}` in the proleptic Gregorian calendar. A
  # bare `%Tempo{}`'s `nil` calendar is resolved to Gregorian at this
  # boundary; Gregorian then passes through and any other calendar converts
  # via `Date.convert/2`.
  defp gregorian_ymd(%Tempo{time: time, calendar: calendar}) do
    gregorian_ymd(time, Compare.effective_calendar(calendar))
  end

  defp gregorian_ymd(time, Calendrical.Gregorian) do
    {Keyword.fetch!(time, :year), Keyword.get(time, :month, 1), Keyword.get(time, :day, 1)}
  end

  defp gregorian_ymd(time, calendar) do
    year = Keyword.fetch!(time, :year)
    month = Keyword.get(time, :month, 1)
    day = Keyword.get(time, :day, 1)

    with {:ok, date} <- Date.new(year, month, day, calendar),
         {:ok, gregorian} <- Date.convert(date, Calendrical.Gregorian) do
      {gregorian.year, gregorian.month, gregorian.day}
    else
      _error -> {year, month, day}
    end
  end

  # Convert a duration to an integer count of `unit`. Exact for a
  # duration already expressed in `unit`; otherwise via nominal lengths.
  defp duration_axis(%Tempo.Duration{time: time}, :year),
    do: round(duration_days(time) / @days_per_year)

  defp duration_axis(%Tempo.Duration{time: time}, :month),
    do: round(duration_days(time) / @days_per_month)

  defp duration_axis(%Tempo.Duration{time: time}, :day), do: round(duration_days(time))

  defp duration_days(time) do
    Enum.reduce(time, 0.0, fn
      {:year, years}, acc -> acc + years * @days_per_year
      {:month, months}, acc -> acc + months * @days_per_month
      {:week, weeks}, acc -> acc + weeks * 7
      {:day, days}, acc -> acc + days
      _other, acc -> acc
    end)
  end
end
