defmodule Tempo.Network.Normalize do
  @moduledoc """
  Reduce a `t:Tempo.Network.t/0` to a Simple Temporal Problem: a
  set of boundary nodes and integer-weighted constraints of the single
  shape `b₁ − b₂ ≤ k`.

  Every period contributes a `start` and an `end` boundary; a single
  shared origin `z₀` (`:origin`) is what absolute dates count from. The
  network's **axis** is set by the finest unit among its bounds, its
  durations and its relation delays, a week counting in days: a date
  becomes a position on it, and a duration a count of it.

  Every value is placed by its actual length, never a mean one:

  * **The axis** counts the years of the network's calendar when all its
    bounds share one, Gregorian months at month resolution, and days
    otherwise, whose positions (Calendrical's iso days) are the same in
    every calendar. A network in hours, minutes or seconds counts seconds
    on the time line: the wall clock when its bounds are floating, UTC
    when they are zoned. Its results are shown in its own unit.

  * **A bound is the span it names**: a lower bound takes the first unit
    of its span and an upper bound the last, so `~o"1300Y"` as the latest
    a period can start is, on a day axis, 31 December 1300, and
    `~o"2026-06-01"` in a network of hours is 23:00 that day.

  * **A duration** in the axis unit (or in hours, minutes and seconds on
    the time line) is a count, and a fraction of a unit is an error. A
    coarser one (years or months on a day axis, years on a month axis,
    days and longer on the time line) is **measured**: added, in its
    period's calendar and zone, to every position its start can take, the
    shortest and longest runs bound its length, and where they end bounds
    its end, so a day across a daylight-saving change is its 23 or 25
    hours. `Tempo.Network.Solver` measures again as it narrows the starts,
    until nothing changes, so a period whose start is known takes the
    exact length of its days, months and years. A start with no bound
    takes the Gregorian calendar's shortest and longest over its 400-year
    cycle, on a wall clock, and is an error in a zone or any other
    calendar.

  """

  alias Tempo.Calendars
  alias Tempo.Compare
  alias Tempo.Enumeration.Zone
  alias Tempo.Math
  alias Tempo.Network
  alias Tempo.Network.Relation

  # Coarsest → finest. The finest unit *present* fixes the axis.
  @unit_order [:year, :month, :day, :hour, :minute, :second, :microsecond]

  # A duration's components, coarsest to finest.
  @duration_units [:year, :month, :week, :day, :hour, :minute, :second, :microsecond]

  # Units counted on the time line, in seconds.
  @time_units [:hour, :minute, :second]

  # Units a duration names that are measured on the time line.
  @calendar_units [:day, :week, :month, :year]

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
  Where a network in hours counts: the wall clock, a named zone, or a
  fixed offset in seconds.
  """
  @type zone :: :floating | {:zone, String.t()} | {:offset, integer()}

  @typedoc """
  A duration measured from the positions its `from` boundary can take:
  `to − from` is at least (`:min`) or at most (`:max`) the length of
  `duration`, counted in `calendar` and `zone`, from there.
  """
  @type measure :: %{
          from: boundary(),
          to: boundary(),
          bound: :min | :max,
          duration: Tempo.Duration.t(),
          calendar: Calendar.calendar(),
          zone: zone() | nil,
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
          unit: :year | :month | :day | :second,
          display: :year | :month | :day | :hour | :minute | :second,
          calendar: Calendar.calendar(),
          zone: zone() | nil
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
    measures from the bounds of their starts), `:unit` (the unit positions
    count in), `:display` (the unit results are shown in), `:calendar` and,
    for a network in hours, `:zone` (where its time line runs); or

  * `{:error, reason}` when the network names a unit finer than a second,
    mixes floating and zoned bounds in hours, or has a bound it cannot
    place.

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
    with {:ok, axis} <- axis(network),
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

      {:ok, Map.merge(axis, %{nodes: nodes, edges: edges, measures: measures})}
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

      iex> Tempo.Network.new()
      ...> |> Tempo.Network.add_period(:a, duration: ~o"PT4H")
      ...> |> Tempo.Network.Normalize.finest_unit()
      :hour

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
  # Every measure has a length: a start still unbounded in a calendar or
  # zone with no known extremes once the solver has settled is an error.
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
  # A position on the axis as a value in the axis calendar (and, on the
  # time line, its zone), at the network's unit where that loses nothing.
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

  def date_at(position, %{unit: :second, display: display, calendar: calendar, zone: zone}) do
    with {:ok, value} <- value_at(position, calendar, zone) do
      {:ok, displayed(value, display)}
    end
  end

  @doc false
  # A count of the axis unit as a duration, on the time line in the
  # network's unit where that loses nothing.
  @spec duration_of(integer(), t()) :: {:ok, Tempo.Duration.t()} | {:error, term()}
  def duration_of(count, %{unit: :year}), do: Tempo.from_iso8601("P#{count}Y")
  def duration_of(count, %{unit: :month}), do: Tempo.from_iso8601("P#{count}M")
  def duration_of(count, %{unit: :day}), do: Tempo.from_iso8601("P#{count}D")

  def duration_of(count, %{unit: :second, display: display}) do
    unit = Enum.find([display, :minute, :second], &(rem(count, unit_seconds(&1)) == 0))
    Tempo.from_iso8601("PT#{div(count, unit_seconds(unit))}#{time_designator(unit)}")
  end

  # --- the axis --------------------------------------------------

  # The axis: the unit positions count in, the unit results are shown in,
  # the calendar and, on the time line, the zone. Years count in the
  # network's calendar when all its bounds share one, months only in the
  # Gregorian calendar, whose months are numbered year by year, days in
  # any calendar, and hours, minutes and seconds as seconds on the time
  # line of the network's bounds.
  defp axis(%Network{} = network) do
    bounds = network.periods |> Map.values() |> Enum.flat_map(&date_bounds/1)
    calendars = bounds |> Enum.map(&Calendars.effective(&1.calendar)) |> Enum.uniq()
    zones = bounds |> Enum.map(&zone_key/1) |> Enum.uniq()

    network |> finest_unit() |> axis(calendars, zones)
  end

  defp axis(:microsecond, _calendars, _zones) do
    {:error,
     ArgumentError.exception(
       "Tempo.Network places periods to the second, and :microsecond is finer."
     )}
  end

  defp axis(unit, calendars, zones) when unit in @time_units do
    with {:ok, zone} <- network_zone(zones) do
      {:ok, %{unit: :second, display: unit, calendar: single_calendar(calendars), zone: zone}}
    end
  end

  defp axis(:year, [], _zones), do: {:ok, calendar_axis(:year, single_calendar([]))}
  defp axis(:year, [calendar], _zones), do: {:ok, calendar_axis(:year, calendar)}

  defp axis(:month, calendars, _zones) when calendars in [[], [Calendrical.Gregorian]],
    do: {:ok, calendar_axis(:month, Calendrical.Gregorian)}

  defp axis(_unit, calendars, _zones), do: {:ok, calendar_axis(:day, single_calendar(calendars))}

  defp calendar_axis(unit, calendar),
    do: %{unit: unit, display: unit, calendar: calendar, zone: nil}

  defp single_calendar([calendar]), do: calendar
  defp single_calendar(_calendars), do: Calendars.default()

  # The time line a network in hours counts on: the wall clock when its
  # bounds are floating, their zone or offset when they share one, and UTC
  # when they are in several. Floating and zoned bounds share no time line.
  defp network_zone([]), do: {:ok, :floating}
  defp network_zone([zone]), do: {:ok, zone}

  defp network_zone(zones) do
    if :floating in zones,
      do: {:error, mixed_zones_error()},
      else: {:ok, {:zone, "Etc/UTC"}}
  end

  # A value's time line: a named zone, a fixed offset in seconds, or the
  # wall clock.
  defp zone_key(%Tempo{extended: %{zone_id: zone}}) when is_binary(zone), do: {:zone, zone}

  defp zone_key(%Tempo{shift: shift}) when is_list(shift),
    do: {:offset, Compare.offset_seconds(shift)}

  defp zone_key(%Tempo{}), do: :floating

  # --- period → constraints --------------------------------------

  defp period_constraints({id, period}, axis) do
    start = {:start, id}
    finish = {:end, id}

    context = %{
      unit: axis.unit,
      calendar: period_calendar(period, axis.calendar),
      zone: period_zone(period, axis.zone)
    }

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
  defp duration_constraint(from, to, duration, bound, context, source) do
    case duration_count(duration, context.unit) do
      {:ok, count} ->
        {:ok, count_edge(from, to, count, bound, source)}

      :measured ->
        {:ok,
         %{
           from: from,
           to: to,
           bound: bound,
           duration: duration,
           calendar: context.calendar,
           zone: context.zone,
           source: source
         }}

      :fractional ->
        {:error, fractional_error(duration, context.unit)}
    end
  end

  defp count_edge(from, to, count, :min, source), do: {from, to, -count, source}
  defp count_edge(from, to, count, :max, source), do: {to, from, count, source}

  # A period's durations count in the calendar and zone of its bounds, and
  # a floating period's in the network's.
  defp period_calendar(nil, network_calendar), do: network_calendar

  defp period_calendar(period, network_calendar) do
    case date_bounds(period) do
      [%Tempo{calendar: calendar} | _rest] -> Calendars.effective(calendar)
      [] -> network_calendar
    end
  end

  defp period_zone(_period, nil), do: nil
  defp period_zone(nil, network_zone), do: network_zone

  defp period_zone(period, network_zone) do
    case date_bounds(period) do
      [%Tempo{} = bound | _rest] -> zone_key(bound)
      [] -> network_zone
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
  # period's calendar and zone.
  defp relation_constraints(%Relation{} = relation, network, axis) do
    period = Map.get(network.periods, relation.from)

    context = %{
      unit: axis.unit,
      calendar: period_calendar(period, axis.calendar),
      zone: period_zone(period, axis.zone)
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

  # The first and last axis positions in the span a bound names: the last
  # is the start of its last unit, an hour before its end in a network of
  # hours.
  defp span_positions(%Tempo{} = value, axis) do
    with {:ok, %Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to}} <-
           Tempo.to_interval(value),
         {:ok, first} <- position(from, axis),
         {:ok, next} <- position(to, axis) do
      {:ok, {first, next - step(axis)}}
    else
      {:error, _reason} = error -> error
      _other -> {:error, unplaceable_error(value)}
    end
  end

  defp step(%{unit: :second, display: display}), do: unit_seconds(display)
  defp step(_axis), do: 1

  # A value's position on the axis: its year, its Gregorian month numbered
  # year by year, its first day's iso days, or its seconds on the time line.
  defp position(%Tempo{time: time} = value, %{unit: :year}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> {:ok, year}
      _other -> {:error, unplaceable_error(value)}
    end
  end

  defp position(%Tempo{time: time} = value, %{unit: :month}) do
    case {Keyword.get(time, :year), Keyword.get(time, :month, 1)} do
      {year, month} when is_integer(year) and is_integer(month) -> {:ok, year * 12 + month - 1}
      _other -> {:error, unplaceable_error(value)}
    end
  end

  defp position(%Tempo{} = value, %{unit: :day}) do
    with %Tempo{} = day <- Tempo.at_resolution(value, :day),
         {:ok, date} <- Tempo.to_date(day) do
      {:ok, Calendrical.date_to_iso_days(date)}
    else
      _unplaceable -> {:error, unplaceable_error(value)}
    end
  end

  defp position(%Tempo{} = value, %{unit: :second}), do: seconds_of(value)

  # A value's seconds on the time line: UTC for a zoned value, the wall
  # clock's for a floating one.
  defp seconds_of(%Tempo{} = value) do
    if Tempo.anchored?(value) do
      case Compare.to_utc_seconds(value) do
        seconds when is_integer(seconds) -> {:ok, seconds}
        _fraction -> {:error, unplaceable_error(value)}
      end
    else
      {:error, unplaceable_error(value)}
    end
  end

  # The value at `seconds` on the time line, in `calendar`: a floating
  # value on the wall clock, or the instant in its zone or at its offset.
  defp value_at(seconds, calendar, :floating), do: wall_value(seconds, calendar, [])

  defp value_at(seconds, calendar, {:offset, offset}),
    do: wall_value(seconds + offset, calendar, shift: Zone.offset_to_shift(offset))

  defp value_at(seconds, calendar, {:zone, zone}) do
    with {:ok, utc} <- wall_value(seconds, calendar, zone: "Etc/UTC"),
         do: Tempo.shift_zone(utc, zone)
  end

  defp wall_value(seconds, calendar, options) do
    days = Integer.floor_div(seconds, 86_400)
    time_of_day = Integer.mod(seconds, 86_400)

    case Calendrical.date_from_iso_days(days, calendar) do
      %Date{year: year, month: month, day: day} ->
        year
        |> Tempo.date_units(month, day, calendar)
        |> Kernel.++(
          hour: div(time_of_day, 3600),
          minute: div(rem(time_of_day, 3600), 60),
          second: rem(time_of_day, 60),
          calendar: calendar
        )
        |> Kernel.++(options)
        |> Tempo.new()

      {:error, _reason} = error ->
        error
    end
  end

  # A value at the coarsest of the network's unit, minutes and seconds that
  # loses nothing: 13:00 in a network of hours, 14:30 where an offset or a
  # half-hour zone puts it.
  defp displayed(%Tempo{time: time} = value, display) do
    unit = Enum.find([display, :minute, :second], &whole_at?(time, &1))

    case Tempo.at_resolution(value, unit) do
      %Tempo{} = shown -> shown
      _unchanged -> value
    end
  end

  defp whole_at?(time, :hour),
    do: Keyword.get(time, :minute, 0) == 0 and Keyword.get(time, :second, 0) == 0

  defp whole_at?(time, :minute), do: Keyword.get(time, :second, 0) == 0
  defp whole_at?(_time, :second), do: true

  defp unit_seconds(:hour), do: 3600
  defp unit_seconds(:minute), do: 60
  defp unit_seconds(:second), do: 1

  defp time_designator(:hour), do: "H"
  defp time_designator(:minute), do: "M"
  defp time_designator(:second), do: "S"

  # --- durations -------------------------------------------------

  # A duration's count of the axis unit, when it names no coarser unit (a
  # week counting in days, and hours and minutes in seconds on the time
  # line); `:measured` when it does.
  defp duration_count(%Tempo.Duration{time: time}, unit) do
    counts =
      Enum.map(time, fn {component, amount} -> component_count(component, amount, unit) end)

    cond do
      :fractional in counts -> :fractional
      :measured in counts -> :measured
      true -> {:ok, Enum.reduce(counts, 0, fn {:ok, count}, total -> total + count end)}
    end
  end

  defp component_count(component, amount, :second)
       when component in @time_units and is_integer(amount),
       do: {:ok, amount * unit_seconds(component)}

  defp component_count(component, amount, :second)
       when component in @calendar_units and is_integer(amount),
       do: :measured

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
    same = {measure.duration, measure.calendar, measure.zone, range}
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
  # the narrower measures still move the bounds; once they settle, one
  # whose lengths repeat with the Gregorian cycle takes the cycle's, and
  # any other stays pending while it is unbounded.
  defp lengths_over(measure, {from_range, to_range}, unit, :deferring) do
    if wide?(measure, from_range, unit),
      do: {:ok, :pending},
      else: runs_over(measure, from_range, to_range, unit)
  end

  defp lengths_over(measure, {from_range, to_range}, unit, :final) do
    cond do
      cyclic?(measure, unit) and spans_cycle?(from_range, unit) -> cycle_runs(measure, unit)
      unbounded?(from_range) -> {:ok, :pending}
      true -> runs_over(measure, from_range, to_range, unit)
    end
  end

  defp wide?(measure, range, unit),
    do: unbounded?(range) or (cyclic?(measure, unit) and spans_cycle?(range, unit))

  defp unbounded?({first, last}), do: :unbounded in [first, last]

  # The Gregorian calendar's lengths repeat every cycle, on a wall clock; a
  # zone's do not.
  defp cyclic?(%{calendar: Calendrical.Gregorian, zone: zone}, :second), do: zone == :floating
  defp cyclic?(%{calendar: Calendrical.Gregorian}, _unit), do: true
  defp cyclic?(_measure, _unit), do: false

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

  defp gregorian_cycle(:second) do
    {first_day, last_day} = gregorian_cycle(:day)
    {first_day * 86_400, (last_day + 1) * 86_400 - 1}
  end

  # The runs from every start in `first..last`, summarised against the range
  # the end can take.
  defp runs_over(measure, {first, last}, {to_first, to_last}, unit) do
    with {:ok, segments} <- segments(measure, first, last, unit) do
      {:ok,
       %{
         shortest: segments |> Enum.map(&segment_length/1) |> Enum.min(),
         longest: segments |> Enum.map(&segment_length/1) |> Enum.max(),
         earliest_end:
           segments |> Enum.map(fn {from, _to, length} -> from + length end) |> Enum.min(),
         latest_end:
           segments |> Enum.map(fn {_from, to, length} -> to + length end) |> Enum.max(),
         latest_start: latest_start_ending_by(segments, to_last),
         earliest_start: earliest_start_ending_from(segments, to_first)
       }}
    end
  end

  # A start free across a whole cycle takes the cycle's shortest and longest
  # runs; where it ends, and which starts fit, stay open.
  defp cycle_runs(measure, unit) do
    {first, last} = gregorian_cycle(unit)

    with {:ok, segments} <- segments(measure, first, last, unit) do
      {:ok,
       %{
         shortest: segments |> Enum.map(&segment_length/1) |> Enum.min(),
         longest: segments |> Enum.map(&segment_length/1) |> Enum.max(),
         earliest_end: :unbounded,
         latest_end: :unbounded,
         latest_start: :unbounded,
         earliest_start: :unbounded
       }}
    end
  end

  defp segment_length({_from, _to, length}), do: length

  # The latest start whose run ends by `to_last`, or `:none`. Within a
  # segment of one length a later start ends later.
  defp latest_start_ending_by(_segments, :unbounded), do: :unbounded

  defp latest_start_ending_by(segments, to_last) do
    segments
    |> Enum.filter(fn {from, _to, length} -> from + length <= to_last end)
    |> Enum.map(fn {_from, to, length} -> min(to, to_last - length) end)
    |> Enum.max(fn -> :none end)
  end

  # The earliest start whose run ends at `to_first` or later, or `:none`.
  defp earliest_start_ending_from(_segments, :unbounded), do: :unbounded

  defp earliest_start_ending_from(segments, to_first) do
    segments
    |> Enum.filter(fn {_from, to, length} -> to + length >= to_first end)
    |> Enum.map(fn {from, _to, length} -> max(from, to_first - length) end)
    |> Enum.min(fn -> :none end)
  end

  # The starts in `first..last` as segments `{from, to, length}` of one
  # length each. On a day or month axis every position is its own. On the
  # time line a length changes only where the start's wall date does, or
  # in a zone where an offset does: a floating start range is cut at its
  # wall midnights, and a zoned one sampled every hour, a change between
  # two samples found by bisection.
  defp segments(measure, first, last, unit) when unit in [:day, :month] do
    Enum.reduce_while(last..first//-1, {:ok, []}, fn position, {:ok, segments} ->
      case length_from(position, measure, unit) do
        {:ok, length} -> {:cont, {:ok, [{position, position, length} | segments]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp segments(%{zone: :floating} = measure, first, last, :second) do
    first
    |> sample_points(last, 86_400)
    |> lengths_at(measure)
    |> in_segments(last)
  end

  defp segments(measure, first, last, :second) do
    with {:ok, sampled} <- first |> sample_points(last, 3600) |> lengths_at(measure),
         {:ok, points} <- with_changes(sampled, measure) do
      in_segments({:ok, points}, last)
    end
  end

  # `first`, then every multiple of `every` after it up to `last`.
  defp sample_points(first, last, every) do
    next = (Integer.floor_div(first, every) + 1) * every
    [first | Enum.to_list(next..last//every)]
  end

  defp lengths_at(points, measure) do
    points
    |> Enum.reduce_while({:ok, []}, fn point, {:ok, measured} ->
      case length_from(point, measure, :second) do
        {:ok, length} -> {:cont, {:ok, [{point, length} | measured]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, measured} -> {:ok, Enum.reverse(measured)}
      {:error, _reason} = error -> error
    end
  end

  # Every point where the length changes between two samples, found by
  # bisection (always strictly between them) and added in order.
  defp with_changes([first | rest], measure) do
    rest
    |> Enum.reduce_while({:ok, [first], first}, fn point, {:ok, reversed, previous} ->
      case changes(previous, point, measure) do
        {:ok, found} -> {:cont, {:ok, [point | Enum.reverse(found, reversed)], point}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed, _last} -> {:ok, Enum.reverse(reversed)}
      {:error, _reason} = error -> error
    end
  end

  # The points in `(x, y)` where the length changes: none when the two
  # agree, and otherwise found by halving until they are a second apart.
  defp changes({_x, length}, {_y, length}, _measure), do: {:ok, []}
  defp changes({x, _lx}, {y, _ly}, _measure) when y - x <= 1, do: {:ok, []}

  defp changes({x, _lx} = lower, {y, _ly} = upper, measure) do
    middle = div(x + y, 2)

    with {:ok, length} <- length_from(middle, measure, :second),
         {:ok, below} <- changes(lower, {middle, length}, measure),
         {:ok, above} <- changes({middle, length}, upper, measure) do
      {:ok, below ++ [{middle, length}] ++ above}
    end
  end

  # Consecutive points with their lengths as segments reaching to the
  # next point, the last reaching to `last`.
  defp in_segments({:ok, points}, last) do
    {:ok,
     points
     |> Enum.chunk_every(2, 1)
     |> Enum.map(fn
       [{from, length}, {next, _next_length}] -> {from, next - 1, length}
       [{from, length}] -> {from, last, length}
     end)}
  end

  defp in_segments({:error, _reason} = error, _last), do: error

  # How many axis units `duration` runs from `position`, by calendar
  # arithmetic in the measure's calendar and, on the time line, its zone.
  defp length_from(position, %{duration: duration, calendar: calendar}, :day) do
    with %Date{} = date <- Calendrical.date_from_iso_days(position, calendar),
         %Tempo{} = later <- date |> Tempo.from_elixir() |> Math.add(duration),
         {:ok, later_date} <- Tempo.to_date(later) do
      {:ok, Calendrical.date_to_iso_days(later_date) - position}
    else
      _unmeasurable -> {:error, unmeasurable_error(duration, calendar)}
    end
  end

  defp length_from(position, %{duration: duration, calendar: calendar}, :month) do
    month = Integer.mod(position, 12) + 1

    with {:ok, value} <-
           Tempo.new(year: Integer.floor_div(position, 12), month: month, calendar: calendar),
         %Tempo{} = later <- Math.add(value, duration),
         {:ok, later_position} <- position(later, %{unit: :month}) do
      {:ok, later_position - position}
    else
      _unmeasurable -> {:error, unmeasurable_error(duration, calendar)}
    end
  end

  defp length_from(position, %{duration: duration, calendar: calendar, zone: zone}, :second) do
    with {:ok, start} <- value_at(position, calendar, zone),
         %Tempo{} = later <- Math.add(start, duration),
         {:ok, later_seconds} <- seconds_of(later) do
      {:ok, later_seconds - position}
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

  defp mixed_zones_error do
    ArgumentError.exception(
      "Tempo.Network places a network in hours on one time line, and its bounds mix " <>
        "floating values with zoned ones."
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

  defp unbounded_error(%{duration: duration, source: source} = measure) do
    ArgumentError.exception(
      "#{describe_source(source)} counts #{inspect(duration)} in #{describe_frame(measure)}, " <>
        "whose length depends on where it starts, and nothing bounds that start. Bound it, " <>
        "or give the duration in the network's unit."
    )
  end

  defp describe_frame(%{zone: {:zone, zone}}), do: zone
  defp describe_frame(%{calendar: calendar}), do: inspect(calendar)

  defp describe_source({:duration, _bound, id, _duration}), do: "The duration of #{inspect(id)}"

  defp describe_source({:relation, %Relation{from: from, to: to}}),
    do: "The delay between #{inspect(from)} and #{inspect(to)}"
end
