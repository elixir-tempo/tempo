defmodule Tempo.Network.Normalize do
  @moduledoc """
  Reduce a `t:Tempo.Network.t/0` to a Simple Temporal Problem: a
  set of boundary nodes and integer-weighted constraints of the single
  shape `b₁ − b₂ ≤ k`.

  Every period contributes a `start` and an `end` boundary; a single
  shared origin `z₀` (`:origin`) is what absolute dates count from. The
  network's **axis** is the finest unit among its bounds, its durations
  and its relation delays, a week counting in days: a date becomes a
  position on it, and a duration a count of it.

  Every value is placed by its actual length, never a mean one:

  * **The axis** counts the years of the network's calendar when all its
    bounds share one, Gregorian months at month resolution, and days
    otherwise, whose positions (Calendrical's iso days) are the same in
    every calendar. Hours, minutes and seconds are an error.

  * **A bound is the span it names**: a lower bound takes the first unit
    of its span and an upper bound the last, so `~o"1300Y"` as the latest
    a period can start is, on a day axis, 31 December 1300.

  * **A duration** in the axis unit is a count, and a fraction of the axis
    unit is an error. A coarser one (years or months on a day axis, years
    on a month axis) is **measured**: added, in its period's calendar, to
    every position its start can take, the shortest and longest runs bound
    its length, and where they end bounds its end. `Tempo.Network.Solver`
    measures again as it narrows the starts, until nothing changes, so a
    period whose start is known takes the exact length of its years and
    months. A start with no bound takes the Gregorian calendar's shortest
    and longest over its 400-year cycle, and is an error in any other
    calendar.

  """

  alias Tempo.Compare
  alias Tempo.Math
  alias Tempo.Network
  alias Tempo.Network.Relation

  # Coarsest → finest. The finest unit *present* fixes the axis.
  @unit_order [:year, :month, :day, :hour, :minute, :second, :microsecond]

  # A duration's components, coarsest to finest.
  @duration_units [:year, :month, :week, :day, :hour, :minute, :second, :microsecond]

  # A network counts no finer than a day.
  @sub_day_units [:hour, :minute, :second, :microsecond]

  # The Gregorian calendar repeats its lengths every 400 years, so its
  # shortest and longest over one cycle are those over any span. The cycle
  # measured starts in this year.
  @gregorian_cycle_start 2000
  @gregorian_cycle_years 400

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

  @typedoc """
  A duration measured from the positions its `from` boundary can take:
  `to − from` is at least (`:min`) or at most (`:max`) the length of
  `duration`, counted in `calendar`, from there.
  """
  @type measure :: %{
          from: boundary(),
          to: boundary(),
          bound: :min | :max,
          duration: Tempo.Duration.t(),
          calendar: Calendar.calendar(),
          source: source()
        }

  @typedoc """
  What was found for each measure, by its index: the ranges of its start
  and its end it was measured over, and the runs from those starts (the
  shortest and longest, where they end, and which starts can end within
  the end's range), or `:pending` while its start waits.
  """
  @type lengths :: %{
          optional(non_neg_integer()) => %{
            range: {range(), range()},
            lengths: runs() | :pending
          }
        }

  @type range :: {integer() | :unbounded, integer() | :unbounded}

  @type runs :: %{
          shortest: integer(),
          longest: integer(),
          earliest_end: integer() | :unbounded,
          latest_end: integer() | :unbounded,
          latest_start: integer() | :unbounded | :none,
          earliest_start: integer() | :unbounded | :none
        }

  @type t :: %{
          nodes: [boundary()],
          edges: [edge()],
          measures: [measure()],
          unit: :year | :month | :day,
          calendar: Calendar.calendar()
        }

  @doc """
  Normalise a network into its axis, its constraints and the durations to
  measure.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  ### Returns

  * `{:ok, normalized}`, a map with `:nodes` (boundary variables including
    `:origin`), `:edges` (`{from, to, weight, source}` constraints meaning
    `from − to ≤ weight`), `:measures` (the durations `Tempo.Network.Solver`
    measures from the bounds of their starts), `:unit` (the axis unit) and
    `:calendar` (the calendar the axis counts in); or

  * `{:error, reason}` when the network names a unit finer than a day or a
    bound it cannot place.

  ### Examples

      iex> network =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:k1, from: ~o"1200Y", duration: {:at_least, ~o"P20Y"})
      iex> {:ok, normalized} = Tempo.Network.Normalize.normalize(network)
      iex> normalized.unit
      :year
      iex> Enum.any?(normalized.edges, &match?({{:start, :k1}, {:end, :k1}, -20, _}, &1))
      true

  """
  @spec normalize(Network.t()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(%Network{} = network) do
    with {:ok, {unit, calendar} = axis} <- axis(network),
         {:ok, period_constraints} <-
           all_constraints(network.periods, &period_constraints(&1, axis)),
         {:ok, relation_constraints} <-
           all_constraints(network.relations, &relation_constraints(&1, network, axis)) do
      sequence_constraints = Enum.flat_map(network.sequences, &sequence_constraints/1)

      {measures, edges} =
        Enum.split_with(
          period_constraints ++ sequence_constraints ++ relation_constraints,
          &is_map/1
        )

      nodes =
        [:origin]
        |> Enum.concat(Enum.flat_map(edges, fn {from, to, _weight, _source} -> [from, to] end))
        |> Enum.concat(Enum.flat_map(measures, &[&1.from, &1.to]))
        |> Enum.uniq()

      {:ok, %{nodes: nodes, edges: edges, measures: measures, unit: unit, calendar: calendar}}
    end
  end

  @doc """
  The finest unit the network's bounds, durations and relation delays
  name, a week counting in days.

  Defaults to `:year` when the network names no unit.

  ### Examples

      iex> Tempo.Network.new()
      ...> |> Tempo.Network.add_period(:a, from: "1200-06-15")
      ...> |> Tempo.Network.Normalize.finest_unit()
      :day

      iex> Tempo.Network.new()
      ...> |> Tempo.Network.add_period(:a, duration: ~o"P2W")
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
    # default year axis.
    duration_units = periods |> Enum.flat_map(&period_durations/1) |> Enum.map(&duration_unit/1)

    delay_units =
      network.relations |> Enum.flat_map(&delay_duration/1) |> Enum.map(&duration_unit/1)

    (date_units ++ duration_units ++ delay_units)
    |> Enum.map(&counted_unit/1)
    |> Enum.max_by(&unit_rank/1, fn -> :year end)
  end

  @doc false
  # The edges of the measured durations at the lengths found for them: the
  # shortest bounds a `:min` measure, the longest a `:max` one. A measure
  # not yet measured, or pending, adds none.
  @spec measured_edges(t(), lengths()) :: [edge()]
  def measured_edges(%{measures: measures}, lengths) do
    measures
    |> Enum.with_index()
    |> Enum.flat_map(fn {measure, index} -> measured_edge(measure, Map.get(lengths, index)) end)
  end

  @doc false
  # Measure every duration from the positions its start can take under
  # `distances` (the solved all-pairs weights), keeping a length whose
  # start range has not changed since `lengths` was found. While `mode` is
  # `:deferring`, a start that is unbounded or free across a whole
  # Gregorian cycle waits, pending, for the narrower measures to settle;
  # at `:final` it is measured, as the calendar allows.
  @spec measure(t(), map(), lengths(), :deferring | :final) ::
          {:ok, lengths()} | {:error, Exception.t()}
  def measure(%{measures: measures} = normalized, distances, lengths, mode) do
    measures
    |> Enum.with_index()
    |> Enum.reduce_while(
      {:ok, %{}, %{}},
      &measure_one(&1, &2, distances, lengths, normalized, mode)
    )
    |> case do
      {:ok, measured, _found} -> {:ok, measured}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  # Every measure has a length: a start still unbounded in a calendar with
  # no known extremes once the solver has settled is an error.
  @spec all_measured(t(), lengths()) :: :ok | {:error, Exception.t()}
  def all_measured(%{measures: measures}, lengths) do
    measures
    |> Enum.with_index()
    |> Enum.find(fn {_measure, index} ->
      match?(%{lengths: :pending}, Map.get(lengths, index))
    end)
    |> case do
      nil -> :ok
      {measure, _index} -> {:error, unbounded_error(measure)}
    end
  end

  @doc false
  # A position on the axis as a value in the axis calendar.
  @spec date_at(integer(), t()) :: {:ok, Tempo.t()} | {:error, term()}
  def date_at(position, %{unit: :year, calendar: Calendrical.Gregorian}),
    do: Tempo.from_iso8601("#{position}Y")

  def date_at(position, %{unit: :year, calendar: calendar}),
    do: Tempo.new(year: position, calendar: calendar)

  def date_at(position, %{unit: :month}),
    do: Tempo.from_iso8601("#{Integer.floor_div(position, 12)}Y#{Integer.mod(position, 12) + 1}M")

  def date_at(position, %{unit: :day, calendar: calendar}) do
    case Calendrical.date_from_iso_days(position, calendar) do
      %Date{} = date -> {:ok, Tempo.from_elixir(date)}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  # A count of the axis unit as a duration.
  @spec duration_of(integer(), t()) :: {:ok, Tempo.Duration.t()} | {:error, term()}
  def duration_of(count, %{unit: :year}), do: Tempo.from_iso8601("P#{count}Y")
  def duration_of(count, %{unit: :month}), do: Tempo.from_iso8601("P#{count}M")
  def duration_of(count, %{unit: :day}), do: Tempo.from_iso8601("P#{count}D")

  # --- the axis --------------------------------------------------

  # The axis unit and the calendar it counts in. Years count in the
  # network's calendar when all its bounds share one, months only in the
  # Gregorian calendar, whose months are numbered year by year; any other
  # network counts in days, which every calendar shares.
  defp axis(%Network{} = network) do
    calendars =
      network.periods
      |> Map.values()
      |> Enum.flat_map(&date_bounds/1)
      |> Enum.map(&Compare.effective_calendar(&1.calendar))
      |> Enum.uniq()

    network |> finest_unit() |> axis(calendars)
  end

  defp axis(unit, _calendars) when unit in @sub_day_units do
    {:error,
     ArgumentError.exception(
       "Tempo.Network places periods in years, months or days, and " <>
         "#{inspect(unit)} is finer than a day."
     )}
  end

  defp axis(:year, []), do: {:ok, {:year, Calendrical.Gregorian}}
  defp axis(:year, [calendar]), do: {:ok, {:year, calendar}}

  defp axis(:month, calendars) when calendars in [[], [Calendrical.Gregorian]],
    do: {:ok, {:month, Calendrical.Gregorian}}

  defp axis(_unit, [calendar]), do: {:ok, {:day, calendar}}
  defp axis(_unit, _calendars), do: {:ok, {:day, Calendrical.Gregorian}}

  # --- period → constraints --------------------------------------

  defp period_constraints({id, period}, {unit, network_calendar} = axis) do
    start = {:start, id}
    finish = {:end, id}
    context = %{unit: unit, calendar: period_calendar(period, network_calendar)}

    # A period never ends before it starts.
    {:ok, [{start, finish, 0, {:non_negative, id}}]}
    |> lower_bound(start, period.earliest_start, axis, {:bound, :start, :lower, id})
    |> upper_bound(start, period.latest_start, axis, {:bound, :start, :upper, id})
    |> lower_bound(finish, period.earliest_end, axis, {:bound, :end, :lower, id})
    |> upper_bound(finish, period.latest_end, axis, {:bound, :end, :upper, id})
    |> duration_bound(start, finish, period.min_duration, context, {:duration, :min, id})
    |> duration_bound(start, finish, period.max_duration, context, {:duration, :max, id})
  end

  # value(node) ≥ bound  ⇒  origin − node ≤ −bound, the first unit of the
  # bound's span.
  defp lower_bound({:ok, constraints}, node, %Tempo{} = value, axis, {tag, edge, dir, id}) do
    with {:ok, {first, _last}} <- span_positions(value, axis) do
      {:ok, [{:origin, node, -first, {tag, edge, dir, id, value}} | constraints]}
    end
  end

  defp lower_bound(result, _node, _value, _axis, _source), do: result

  # value(node) ≤ bound  ⇒  node − origin ≤ bound, the last unit of the
  # bound's span.
  defp upper_bound({:ok, constraints}, node, %Tempo{} = value, axis, {tag, edge, dir, id}) do
    with {:ok, {_first, last}} <- span_positions(value, axis) do
      {:ok, [{node, :origin, last, {tag, edge, dir, id, value}} | constraints]}
    end
  end

  defp upper_bound(result, _node, _value, _axis, _source), do: result

  # end − start ≥ min, or end − start ≤ max.
  defp duration_bound(
         {:ok, constraints},
         start,
         finish,
         %Tempo.Duration{} = duration,
         context,
         {tag, bound, id}
       ) do
    source = {tag, bound, id, duration}

    with {:ok, constraint} <- duration_constraint(start, finish, duration, bound, context, source) do
      {:ok, [constraint | constraints]}
    end
  end

  defp duration_bound(result, _start, _finish, _duration, _context, _source), do: result

  # `to − from` at least (`:min`) or at most (`:max`) `duration`: an edge
  # when the duration counts whole axis units, a measure when it names a
  # coarser unit, and an error when it names a fraction of one.
  defp duration_constraint(from, to, duration, bound, %{unit: unit, calendar: calendar}, source) do
    case duration_count(duration, unit) do
      {:ok, count} ->
        {:ok, count_edge(from, to, count, bound, source)}

      :measured ->
        {:ok,
         %{
           from: from,
           to: to,
           bound: bound,
           duration: duration,
           calendar: calendar,
           source: source
         }}

      :fractional ->
        {:error, fractional_error(duration, unit)}
    end
  end

  defp count_edge(from, to, count, :min, source), do: {from, to, -count, source}
  defp count_edge(from, to, count, :max, source), do: {to, from, count, source}

  # A period's durations count in the calendar of its bounds, and a
  # floating period's in the network's.
  defp period_calendar(nil, network_calendar), do: network_calendar

  defp period_calendar(period, network_calendar) do
    case date_bounds(period) do
      [%Tempo{calendar: calendar} | _rest] -> Compare.effective_calendar(calendar)
      [] -> network_calendar
    end
  end

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

  # --- relations → constraints -----------------------------------

  # A delay counts from a boundary of the relation's first period, in that
  # period's calendar.
  defp relation_constraints(%Relation{} = relation, network, {unit, network_calendar}) do
    context = %{
      unit: unit,
      calendar: period_calendar(Map.get(network.periods, relation.from), network_calendar)
    }

    source = {:relation, relation}
    all_constraints(Relation.to_atomic(relation), &atomic_constraint(&1, context, source))
  end

  # `p − q ≤ duration`: `p` at most `duration` after `q`.
  defp atomic_constraint({p, q, {:duration, duration}}, context, source),
    do: duration_constraint(q, p, duration, :max, context, source)

  # `p − q ≤ −duration`: `q` at least `duration` after `p`.
  defp atomic_constraint({p, q, {:neg_duration, duration}}, context, source),
    do: duration_constraint(p, q, duration, :min, context, source)

  defp atomic_constraint({p, q, weight}, _context, source) when is_integer(weight),
    do: {:ok, {p, q, weight, source}}

  # Each item's constraints (a list, or one constraint), in order, stopping
  # at the first error.
  defp all_constraints(items, constraints_of) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, collected} ->
      case constraints_of.(item) do
        {:ok, constraints} -> {:cont, {:ok, collected ++ List.wrap(constraints)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # --- positions -------------------------------------------------

  # The first and last axis positions in the span a bound names.
  defp span_positions(%Tempo{} = value, {unit, calendar}) do
    with {:ok, %Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to}} <-
           Tempo.to_interval(value),
         {:ok, first} <- position(from, unit, calendar),
         {:ok, next} <- position(to, unit, calendar) do
      {:ok, {first, next - 1}}
    else
      {:error, _reason} = error -> error
      _other -> {:error, unplaceable_error(value)}
    end
  end

  # A value's position on the axis: its year, its Gregorian month
  # numbered year by year, or its first day's iso days.
  defp position(%Tempo{time: time} = value, :year, _calendar) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> {:ok, year}
      _other -> {:error, unplaceable_error(value)}
    end
  end

  defp position(%Tempo{time: time} = value, :month, _calendar) do
    case {Keyword.get(time, :year), Keyword.get(time, :month, 1)} do
      {year, month} when is_integer(year) and is_integer(month) -> {:ok, year * 12 + month - 1}
      _other -> {:error, unplaceable_error(value)}
    end
  end

  defp position(%Tempo{} = value, :day, _calendar) do
    with %Tempo{} = day <- Tempo.at_resolution(value, :day),
         {:ok, date} <- Tempo.to_date(day) do
      {:ok, Calendrical.date_to_iso_days(date)}
    else
      _unplaceable -> {:error, unplaceable_error(value)}
    end
  end

  # --- durations -------------------------------------------------

  # A duration's count of the axis unit, when it names no coarser unit (a
  # week counting in days); `:measured` when it does.
  defp duration_count(%Tempo.Duration{time: time}, unit) do
    counts =
      Enum.map(time, fn {component, amount} -> component_count(component, amount, unit) end)

    cond do
      :fractional in counts -> :fractional
      :measured in counts -> :measured
      true -> {:ok, Enum.reduce(counts, 0, fn {:ok, count}, total -> total + count end)}
    end
  end

  defp component_count(unit, amount, unit) when is_integer(amount), do: {:ok, amount}

  defp component_count(:week, weeks, :day) when is_integer(weeks),
    do: {:ok, Calendrical.weeks_to_days(weeks)}

  defp component_count(:year, years, unit) when is_integer(years) and unit in [:month, :day],
    do: :measured

  defp component_count(:month, months, :day) when is_integer(months), do: :measured
  defp component_count(_component, _amount, _unit), do: :fractional

  # A measure's edges from its runs: the length between its boundaries, the
  # earliest (`:min`) or latest (`:max`) its end can fall, and the latest
  # (`:min`) or earliest (`:max`) its start can take and still end within
  # its end's range.
  defp measured_edge(%{bound: :min, from: from, to: to, source: source}, %{lengths: %{} = runs}) do
    [{from, to, -runs.shortest, source}] ++
      bound_edge(:origin, to, negated(runs.earliest_end), source) ++
      bound_edge(from, :origin, runs.latest_start, source)
  end

  defp measured_edge(%{bound: :max, from: from, to: to, source: source}, %{lengths: %{} = runs}) do
    [{to, from, runs.longest, source}] ++
      bound_edge(to, :origin, runs.latest_end, source) ++
      bound_edge(:origin, from, negated(runs.earliest_start), source)
  end

  defp measured_edge(_measure, _unmeasured), do: []

  # An absolute bound the runs give: none when they give none, and a
  # contradiction (a negative loop at the origin) when no run fits.
  defp bound_edge(_from, _to, :unbounded, _source), do: []
  defp bound_edge(_from, _to, :none, source), do: [{:origin, :origin, -1, source}]
  defp bound_edge(from, to, weight, source), do: [{from, to, weight, source}]

  defp negated(weight) when is_integer(weight), do: -weight
  defp negated(bound), do: bound

  defp measure_one({measure, index}, {:ok, measured, found}, distances, lengths, normalized, mode) do
    range = {bounds_of(distances, measure.from), bounds_of(distances, measure.to)}
    same = {measure.duration, measure.calendar, range}
    previous = Map.get(lengths, index)

    case kept_lengths(previous, range, Map.get(found, same), measure, normalized, mode) do
      {:ok, measure_lengths} ->
        {:cont,
         {:ok, Map.put(measured, index, %{range: range, lengths: measure_lengths}),
          Map.put(found, same, measure_lengths)}}

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  # The lengths found before over the same start range, in the last pass or
  # for the same duration in this one, are kept; any other is measured.
  defp kept_lengths(%{range: range, lengths: %{} = runs}, range, _found, _measure, _, _),
    do: {:ok, runs}

  defp kept_lengths(_previous, _range, found, _measure, _normalized, _mode)
       when not is_nil(found),
       do: {:ok, found}

  defp kept_lengths(_previous, range, nil, measure, %{unit: unit}, mode),
    do: lengths_over(measure, range, unit, mode)

  # The earliest and latest positions a boundary can take, from the solved
  # weights between it and the origin.
  defp bounds_of(distances, node), do: {earliest(distances, node), latest(distances, node)}

  defp earliest(distances, node) do
    case Map.get(distances, {:origin, node}, :inf) do
      :inf -> :unbounded
      weight -> -weight
    end
  end

  defp latest(distances, node) do
    case Map.get(distances, {node, :origin}, :inf) do
      :inf -> :unbounded
      weight -> weight
    end
  end

  # The runs of a duration from the positions its start can take. A wide
  # start (unbounded, or free across a whole Gregorian cycle) waits while
  # the narrower measures still move the bounds; once they settle, a
  # Gregorian one takes the cycle's lengths, and one in any other calendar
  # stays pending while it is unbounded.
  defp lengths_over(measure, {from_range, to_range}, unit, :deferring) do
    if wide?(measure, from_range, unit),
      do: {:ok, :pending},
      else: runs_over(measure, from_range, to_range, unit)
  end

  defp lengths_over(
         %{calendar: Calendrical.Gregorian} = measure,
         {from_range, to_range},
         unit,
         :final
       ) do
    if spans_cycle?(from_range, unit),
      do: cycle_runs(measure, unit),
      else: runs_over(measure, from_range, to_range, unit)
  end

  defp lengths_over(_measure, {{first, last}, _to_range}, _unit, :final)
       when :unbounded in [first, last],
       do: {:ok, :pending}

  defp lengths_over(measure, {from_range, to_range}, unit, :final),
    do: runs_over(measure, from_range, to_range, unit)

  defp wide?(_measure, {first, last}, _unit) when :unbounded in [first, last], do: true
  defp wide?(%{calendar: Calendrical.Gregorian}, range, unit), do: spans_cycle?(range, unit)
  defp wide?(_measure, _range, _unit), do: false

  defp spans_cycle?({first, last}, _unit) when :unbounded in [first, last], do: true

  defp spans_cycle?({first, last}, unit) do
    {cycle_first, cycle_last} = gregorian_cycle(unit)
    last - first >= cycle_last - cycle_first
  end

  # One whole Gregorian cycle of positions on the axis.
  defp gregorian_cycle(:month) do
    first = @gregorian_cycle_start * 12
    {first, first + @gregorian_cycle_years * 12 - 1}
  end

  defp gregorian_cycle(:day) do
    {:ok, first} = Calendrical.iso_days(@gregorian_cycle_start, 1, 1, Calendrical.Gregorian)
    last_year = @gregorian_cycle_start + @gregorian_cycle_years
    {:ok, next} = Calendrical.iso_days(last_year, 1, 1, Calendrical.Gregorian)
    {first, next - 1}
  end

  # The runs from every start in `first..last`, summarised against the range
  # the end can take.
  defp runs_over(measure, {first, last}, {to_first, to_last}, unit) do
    with {:ok, runs} <- runs_from(measure, first, last, unit) do
      lengths = Enum.map(runs, fn {start, finish} -> finish - start end)
      ends = Enum.map(runs, fn {_start, finish} -> finish end)

      {:ok,
       %{
         shortest: Enum.min(lengths),
         longest: Enum.max(lengths),
         earliest_end: Enum.min(ends),
         latest_end: Enum.max(ends),
         latest_start: latest_start_ending_by(runs, to_last),
         earliest_start: earliest_start_ending_from(runs, to_first)
       }}
    end
  end

  # A start free across a whole cycle takes the cycle's shortest and longest
  # runs; where it ends, and which starts fit, stay open.
  defp cycle_runs(measure, unit) do
    {first, last} = gregorian_cycle(unit)

    with {:ok, runs} <- runs_from(measure, first, last, unit) do
      lengths = Enum.map(runs, fn {start, finish} -> finish - start end)

      {:ok,
       %{
         shortest: Enum.min(lengths),
         longest: Enum.max(lengths),
         earliest_end: :unbounded,
         latest_end: :unbounded,
         latest_start: :unbounded,
         earliest_start: :unbounded
       }}
    end
  end

  # Each start in `first..last` with the position its run ends at, in order.
  defp runs_from(%{duration: duration, calendar: calendar}, first, last, unit) do
    Enum.reduce_while(last..first//-1, {:ok, []}, fn position, {:ok, runs} ->
      case length_from(position, duration, calendar, unit) do
        {:ok, length} -> {:cont, {:ok, [{position, position + length} | runs]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # The latest start whose run ends by `to_last`, or `:none`.
  defp latest_start_ending_by(_runs, :unbounded), do: :unbounded

  defp latest_start_ending_by(runs, to_last) do
    runs
    |> Enum.filter(fn {_start, finish} -> finish <= to_last end)
    |> Enum.map(fn {start, _finish} -> start end)
    |> Enum.max(fn -> :none end)
  end

  # The earliest start whose run ends at `to_first` or later, or `:none`.
  defp earliest_start_ending_from(_runs, :unbounded), do: :unbounded

  defp earliest_start_ending_from(runs, to_first) do
    runs
    |> Enum.filter(fn {_start, finish} -> finish >= to_first end)
    |> Enum.map(fn {start, _finish} -> start end)
    |> Enum.min(fn -> :none end)
  end

  # How many axis units `duration` runs from `position`, by calendar
  # arithmetic in `calendar`.
  defp length_from(position, duration, calendar, :day) do
    with %Date{} = date <- Calendrical.date_from_iso_days(position, calendar),
         %Tempo{} = later <- date |> Tempo.from_elixir() |> Math.add(duration),
         {:ok, later_date} <- Tempo.to_date(later) do
      {:ok, Calendrical.date_to_iso_days(later_date) - position}
    else
      _unmeasurable -> {:error, unmeasurable_error(duration, calendar)}
    end
  end

  defp length_from(position, duration, calendar, :month) do
    month = Integer.mod(position, 12) + 1

    with {:ok, value} <-
           Tempo.new(year: Integer.floor_div(position, 12), month: month, calendar: calendar),
         %Tempo{} = later <- Math.add(value, duration),
         {:ok, later_position} <- position(later, :month, calendar) do
      {:ok, later_position - position}
    else
      _unmeasurable -> {:error, unmeasurable_error(duration, calendar)}
    end
  end

  # --- units -----------------------------------------------------

  defp date_bounds(period) do
    [
      period.earliest_start,
      period.latest_start,
      period.earliest_end,
      period.latest_end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp period_durations(period) do
    Enum.reject([period.min_duration, period.max_duration], &is_nil/1)
  end

  defp delay_duration(%Relation{
         type: {:delay, _edge_a, _edge_b, _comparison, %Tempo.Duration{} = duration}
       }),
       do: [duration]

  defp delay_duration(_relation), do: []

  defp unit_of(%Tempo{} = value) do
    {unit, _factor} = Tempo.resolution(value)
    unit
  end

  # The finest component a duration names.
  defp duration_unit(%Tempo.Duration{time: time}) do
    Enum.find(Enum.reverse(@duration_units), :year, &Keyword.has_key?(time, &1))
  end

  # A network counts weeks, and days of a week or a year, in days.
  defp counted_unit(unit) when unit in [:week, :day_of_week, :day_of_year], do: :day
  defp counted_unit(unit), do: unit

  defp unit_rank(unit), do: Enum.find_index(@unit_order, &(&1 == unit)) || 0

  # --- errors ----------------------------------------------------

  defp unplaceable_error(value) do
    ArgumentError.exception(
      "Tempo.Network cannot place #{inspect(value)} as a bound: it names no single span."
    )
  end

  defp fractional_error(duration, unit) do
    ArgumentError.exception(
      "Tempo.Network measures durations in whole units on its #{inspect(unit)} axis, and " <>
        "#{inspect(duration)} names a fraction of one."
    )
  end

  defp unmeasurable_error(duration, calendar) do
    ArgumentError.exception(
      "Tempo.Network cannot measure #{inspect(duration)} in #{inspect(calendar)} from a " <>
        "position its start can take."
    )
  end

  defp unbounded_error(%{duration: duration, calendar: calendar, source: source}) do
    ArgumentError.exception(
      "#{describe_source(source)} counts #{inspect(duration)} in #{inspect(calendar)}, whose " <>
        "length depends on where it starts, and nothing bounds that start. Bound it, or give " <>
        "the duration in the network's unit."
    )
  end

  defp describe_source({:duration, _bound, id, _duration}), do: "The duration of #{inspect(id)}"

  defp describe_source({:relation, %Relation{from: from, to: to}}),
    do: "The delay between #{inspect(from)} and #{inspect(to)}"
end
