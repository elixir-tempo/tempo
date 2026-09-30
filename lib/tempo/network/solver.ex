defmodule Tempo.Network.Solver do
  @moduledoc """
  Consistency checking and constraint propagation for a chronological
  network, by solving its Simple Temporal Problem.

  The network normalises (`Tempo.Network.Normalize`) to a directed
  weighted graph — one node per boundary plus the origin `z₀` — whose
  all-pairs shortest paths are the **minimal network**: the tightest
  bound on `b₁ − b₂` is the shortest-path weight `b₁ → b₂` (Dechter,
  Meiri & Pearl 1991; the paper's Floyd 1962). The network is
  **consistent** iff the graph has no negative cycle.

  * `consistent?/1` — does any valid assignment of dates exist?

  * `propagate/1` — the narrowest start, end, and duration each period
    can take given every constraint together.

  * `contemporaneity/3` — whether two periods can, must, or cannot overlap.

  * `relation/3` — the tightest Allen relation(s) still possible between two
    periods, with `relation_certainty/4` for a single named relation.

  These all run in O(n³) on the boundary count (Floyd–Warshall), which is
  interactive for the hundreds of periods these chronologies contain. A
  duration in a unit coarser than the network's axis (a year in a network
  of days) is measured by its actual length from where its period can
  start, and the network is solved again as those lengths narrow, until
  they settle (see `Tempo.Network.Normalize`).

  A network whose builders recorded an error (see `Tempo.Network`), or one
  it cannot place (a unit finer than a second, floating and zoned bounds
  in one network of hours, a fraction of its unit),
  returns that error from every function here, and the predicates raise
  it.

  """

  alias Tempo.Network
  alias Tempo.Network.Normalize

  @doc """
  Is the network consistent — does it admit at least one valid
  assignment of dates?

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  ### Returns

  * `true` when consistent, `false` when the constraints contradict
    (the graph has a negative cycle).

  * Raises the first error the network's builders recorded.

  ### Examples

      iex> Tempo.Network.new()
      ...> |> Tempo.Network.add_period(:k, from: ~o"1200Y", to: ~o"1180Y")
      ...> |> Tempo.Network.Solver.consistent?()
      false

  """
  @spec consistent?(Network.t()) :: boolean()
  def consistent?(%Network{} = network) do
    case solved(network) do
      {:ok, _solution} -> true
      {:error, :inconsistent} -> false
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Propagate the network's constraints to every period's narrowest
  start, end, and duration.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  ### Returns

  * `{:ok, network}` with each period's bounds replaced by the computed
    tightest bounds (a bound that the constraints leave unbounded
    becomes `nil`); or

  * `{:error, :inconsistent}` when no valid assignment exists; or

  * `{:error, reason}` for an error the network's builders recorded.

  ### Examples

      iex> {:ok, propagated} =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:k1, from: ~o"1200Y", duration: {:at_least, ~o"P20Y"})
      ...>   |> Tempo.Network.add_period(:k2, duration: {:at_least, ~o"P35Y"})
      ...>   |> Tempo.Network.add_sequence([:k1, :k2])
      ...>   |> Tempo.Network.Solver.propagate()
      iex> propagated.periods[:k2].earliest_end
      ~o"1255Y"

  """
  @spec propagate(Network.t()) :: {:ok, Network.t()} | {:error, :inconsistent | Exception.t()}
  def propagate(%Network{} = network) do
    with {:ok, %{normalized: normalized, dist: distances}} <- solved(network),
         {:ok, periods} <- tightened_periods(network.periods, distances, normalized) do
      {:ok, %{network | periods: periods}}
    end
  end

  defp tightened_periods(periods, distances, normalized) do
    Enum.reduce_while(periods, {:ok, %{}}, fn {id, period}, {:ok, tightened} ->
      case tighten_period(id, period, distances, normalized) do
        {:ok, period} -> {:cont, {:ok, Map.put(tightened, id, period)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # Normalise the network and solve it: solve with each measured duration at
  # the lengths found so far, measure them again from the bounds that gives
  # their starts, and repeat until the lengths stop changing. A round only
  # narrows the starts, so the lengths settle.
  defp solved(network) do
    with :ok <- Network.check(network),
         {:ok, normalized} <- Normalize.normalize(network) do
      settle(normalized, %{}, :deferring)
    end
  end

  defp settle(normalized, lengths, mode) do
    solving = %{
      normalized
      | edges: normalized.edges ++ Normalize.measured_edges(normalized, lengths)
    }

    %{dist: distances, next: next} = shortest_paths(solving)

    if negative_cycle?(distances) do
      {:error, :inconsistent}
    else
      case Normalize.measure(normalized, distances, lengths, mode) do
        {:ok, measured} ->
          settled(measured, lengths, mode, normalized, %{
            normalized: solving,
            dist: distances,
            next: next
          })

        {:error, _reason} = error ->
          error
      end
    end
  end

  # The lengths stopped changing. A measure left waiting on a wide start is
  # measured in the final rounds; still waiting after them, its start is
  # unbounded in a calendar with no known extremes, which is an error.
  defp settled(lengths, lengths, mode, normalized, solution) do
    case {Normalize.all_measured(normalized, lengths), mode} do
      {:ok, _mode} -> {:ok, solution}
      {{:error, _reason}, :deferring} -> settle(normalized, lengths, :final)
      {{:error, _reason} = error, :final} -> error
    end
  end

  defp settled(measured, _lengths, mode, normalized, _solution),
    do: settle(normalized, measured, mode)

  @doc """
  Classify whether two periods overlap in time, given the whole network.

  Returns `:certain` when the constraints force the periods to be
  contemporary, `:possible` when they merely allow it, and `:impossible`
  when they forbid it. The verdict is read from the minimal (propagated)
  network, so it accounts for every constraint — not just the two
  periods' own bounds — in the spirit of Geeraerts, Levy & Pluquet,
  *Models and Algorithms for Chronology* (TIME 2017), Props. 7 and 10.

  Two periods that merely touch (one ends exactly where the other
  begins) count as contemporary, matching `add_relation(:contemporary,
  …)` — the endpoints are treated as closed here.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  * `p1` and `p2` are ids of periods present in the network.

  ### Returns

  * `:certain` when every valid chronology has the periods overlapping;

  * `:possible` when some but not all valid chronologies do;

  * `:impossible` when none do;

  * `{:error, :inconsistent}` when the network has no valid chronology;
    or

  * `{:error, reason}` for an error the network's builders recorded.

  ### Examples

      iex> network =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:k1, from: {:not_before, 1200}, duration: {:at_most, 15})
      ...>   |> Tempo.Network.add_period(:k2, to: {:not_after, 1300}, duration: {30, 100})
      ...>   |> Tempo.Network.add_period(:s1, duration: {20, 100})
      ...>   |> Tempo.Network.add_period(:s2, duration: {20, 100})
      ...>   |> Tempo.Network.add_sequence([:k1, :k2])
      ...>   |> Tempo.Network.add_sequence([:s1, :s2])
      ...>   |> Tempo.Network.add_relation(:starts_during, :s1, :k1)
      ...>   |> Tempo.Network.add_relation(:ends_during, :s2, :k2)
      iex> Tempo.Network.Solver.contemporaneity(network, :k1, :s2)
      :impossible

  """
  @spec contemporaneity(Network.t(), term(), term()) ::
          :certain | :possible | :impossible | {:error, :inconsistent | Exception.t()}
  def contemporaneity(%Network{} = network, p1, p2) do
    with {:ok, %{dist: distances}} <- solved(network) do
      cond do
        sure_overlap?(distances, p1, p2) -> :certain
        possible_overlap?(distances, p1, p2) -> :possible
        true -> :impossible
      end
    end
  end

  @doc """
  Whether two periods are *certainly* contemporary — true only when
  every valid chronology has them overlapping. See `contemporaneity/3`.
  """
  @spec certainly_contemporary?(Network.t(), term(), term()) :: boolean()
  def certainly_contemporary?(%Network{} = network, p1, p2) do
    verdict(contemporaneity(network, p1, p2)) == :certain
  end

  @doc """
  Whether two periods are *possibly* contemporary — true when at least
  one valid chronology has them overlapping. See `contemporaneity/3`.
  """
  @spec possibly_contemporary?(Network.t(), term(), term()) :: boolean()
  def possibly_contemporary?(%Network{} = network, p1, p2) do
    verdict(contemporaneity(network, p1, p2)) in [:certain, :possible]
  end

  # A predicate has only true and false to give, so an error the network's
  # builders recorded, or one solving it met, raises.
  defp verdict({:error, exception}) when is_exception(exception), do: raise(exception)
  defp verdict(verdict), do: verdict

  # Prop. 7 — overlap is entailed iff both synchronism inequalities
  # beg(p₁) ≤ end(p₂) and beg(p₂) ≤ end(p₁) are already implied, i.e. the
  # tightest bound on each difference (its shortest-path weight) is ≤ 0.
  defp sure_overlap?(distances, p1, p2) do
    at_most_zero?(get(distances, {:start, p1}, {:end, p2})) and
      at_most_zero?(get(distances, {:start, p2}, {:end, p1}))
  end

  # Prop. 10 — overlap is achievable iff adding both synchronism edges
  # keeps the network satisfiable: the tight bound on each reverse
  # difference end − beg must leave room to be non-negative.
  defp possible_overlap?(distances, p1, p2) do
    at_least_zero?(get(distances, {:end, p2}, {:start, p1})) and
      at_least_zero?(get(distances, {:end, p1}, {:start, p2}))
  end

  defp at_most_zero?(:inf), do: false
  defp at_most_zero?(weight), do: weight <= 0

  defp at_least_zero?(:inf), do: true
  defp at_least_zero?(weight), do: weight >= 0

  # The thirteen Allen relations as endpoint constraints (half-open, matching
  # `Tempo.relation/2`): `:a1`/`:a2` are period p1's start/end, `:b1`/`:b2`
  # p2's. `:lt` is a strict order on the finest time-scale, `:eq` coincidence.
  # These are jointly exhaustive and pairwise disjoint for proper intervals.
  @allen_relations [
    precedes: [{:a2, :lt, :b1}],
    meets: [{:a2, :eq, :b1}],
    overlaps: [{:a1, :lt, :b1}, {:b1, :lt, :a2}, {:a2, :lt, :b2}],
    finished_by: [{:a1, :lt, :b1}, {:a2, :eq, :b2}],
    contains: [{:a1, :lt, :b1}, {:b2, :lt, :a2}],
    starts: [{:a1, :eq, :b1}, {:a2, :lt, :b2}],
    equals: [{:a1, :eq, :b1}, {:a2, :eq, :b2}],
    started_by: [{:a1, :eq, :b1}, {:b2, :lt, :a2}],
    during: [{:b1, :lt, :a1}, {:a2, :lt, :b2}],
    finishes: [{:a2, :eq, :b2}, {:b1, :lt, :a1}],
    overlapped_by: [{:b1, :lt, :a1}, {:a1, :lt, :b2}, {:b2, :lt, :a2}],
    met_by: [{:a1, :eq, :b2}],
    preceded_by: [{:b2, :lt, :a1}]
  ]

  @doc """
  The Allen interval relation(s) still possible between two periods, given
  every constraint in the network.

  Generalises `contemporaneity/3` from the single overlap question to the full
  relational answer, in the same vocabulary `Tempo.relation/2` uses for
  grounded values. It reads off the **minimal network** — the same solved
  shortest-path distances `contemporaneity/3` and `propagate/1` use — so it costs
  no extra solve: a relation is possible iff adding its endpoint constraints to
  the solved network stays consistent (no negative cycle). No qualitative
  disjunction enters, so it remains polynomial.

  Periods are treated as proper intervals (start strictly before end), matching
  Tempo's no-degenerate-intervals ontology, and endpoints are compared
  half-open — so "the end of A coincides with the start of B" is `:meets`, not
  overlap. (That boundary case is still `possibly_contemporary?/3`, which asks
  the looser "could they have coexisted" question.)

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  * `p1` and `p2` are period identifiers added with `Tempo.Network.add_period/3`.

  ### Returns

  * A single Allen relation atom (e.g. `:during`) when the constraints pin the
    relation to exactly one — it is *entailed*.

  * A list of atoms (in Allen's canonical order) when several remain possible —
    the tightest qualitative statement the constraints support.

  * `{:error, :inconsistent}` when the network has no valid assignment,
    `{:error, :unknown_period}` when an id is not in the network, or
    `{:error, reason}` for an error the network's builders recorded.

  ### Examples

      iex> Tempo.Network.new()
      ...> |> Tempo.Network.add_period(:a, from: ~o"1200Y", to: ~o"1250Y")
      ...> |> Tempo.Network.add_period(:b, from: ~o"1230Y", to: ~o"1280Y")
      ...> |> Tempo.Network.Solver.relation(:a, :b)
      :overlaps

      iex> Tempo.Network.new()
      ...> |> Tempo.Network.add_period(:a, duration: {:at_least, ~o"P1Y"})
      ...> |> Tempo.Network.add_period(:b, duration: {:at_least, ~o"P1Y"})
      ...> |> Tempo.Network.add_sequence([:a, :b])
      ...> |> Tempo.Network.Solver.relation(:a, :b)
      :meets

  """
  @spec relation(Network.t(), term(), term()) ::
          atom() | [atom()] | {:error, :inconsistent | :unknown_period | Exception.t()}
  def relation(%Network{} = network, p1, p2) do
    with :ok <- Network.check(network),
         :ok <- known_period(network, p1),
         :ok <- known_period(network, p2),
         {:ok, %{dist: distances}} <- solved(network) do
      feasible_relations(distances, p1, p2)
    end
  end

  @doc """
  Whether a specific Allen `relation` between two periods is `:certain`,
  `:possible`, or `:impossible` under the network's constraints.

  The network counterpart of `Tempo.relation_certainty/3` on grounded `±`-margin
  values — the same three-valued vocabulary, read from the solved network via
  `relation/3`. A relation is `:certain` when it is the *only* one the
  constraints allow, `:possible` when it is one of several, `:impossible` when
  ruled out.

  ### Arguments

  * `network`, `p1`, `p2` — as for `relation/3`.

  * `relation` is an Allen relation atom (e.g. `:during`, `:precedes`).

  ### Returns

  * `:certain | :possible | :impossible`, or `{:error, reason}` as `relation/3`.

  ### Examples

      iex> net =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:a, from: ~o"1200Y", to: ~o"1250Y")
      ...>   |> Tempo.Network.add_period(:b, from: ~o"1230Y", to: ~o"1280Y")
      iex> Tempo.Network.Solver.relation_certainty(net, :a, :b, :overlaps)
      :certain
      iex> Tempo.Network.Solver.relation_certainty(net, :a, :b, :during)
      :impossible

  """
  @spec relation_certainty(Network.t(), term(), term(), atom()) ::
          :certain
          | :possible
          | :impossible
          | {:error, :inconsistent | :unknown_period | Exception.t()}
  def relation_certainty(%Network{} = network, p1, p2, relation) do
    case relation(network, p1, p2) do
      {:error, _reason} = error ->
        error

      result ->
        feasible = List.wrap(result)

        cond do
          relation not in feasible -> :impossible
          length(feasible) == 1 -> :certain
          true -> :possible
        end
    end
  end

  defp known_period(%Network{periods: periods}, id) do
    if Map.has_key?(periods, id), do: :ok, else: {:error, :unknown_period}
  end

  # A relation is feasible iff adding its endpoint constraints (plus the
  # proper-interval constraints, since Tempo intervals are never degenerate) to
  # the minimal network keeps it consistent. The check is local to the four
  # boundary nodes of p1/p2: the minimal network's pairwise weights already
  # summarise every path through the rest of the graph, so a negative cycle can
  # only run through these four nodes and the added edges.
  defp feasible_relations(distances, p1, p2) do
    vars = %{a1: {:start, p1}, a2: {:end, p1}, b1: {:start, p2}, b2: {:end, p2}}
    nodes = Map.values(vars)
    base = induced(distances, nodes)
    proper = lt_edges(vars.a1, vars.a2) ++ lt_edges(vars.b1, vars.b2)

    relations =
      for {relation, comparisons} <- @allen_relations,
          feasible?(base, nodes, proper ++ instantiate(comparisons, vars)),
          do: relation

    single_or_list(relations)
  end

  defp single_or_list([single]), do: single
  defp single_or_list(list), do: list

  defp induced(distances, nodes) do
    for from <- nodes, to <- nodes, into: %{} do
      {{from, to}, if(from == to, do: 0, else: get(distances, from, to))}
    end
  end

  defp feasible?(base, nodes, added) do
    augmented =
      Enum.reduce(added, base, fn {from, to, weight}, acc ->
        Map.update(acc, {from, to}, weight, &min_weight(&1, weight))
      end)

    final =
      for k <- nodes, i <- nodes, j <- nodes, reduce: augmented do
        distances ->
          via = add_weight(distances[{i, k}], distances[{k, j}])
          if less?(via, distances[{i, j}]), do: %{distances | {i, j} => via}, else: distances
      end

    Enum.all?(nodes, fn node -> not negative?(Map.get(final, {node, node}, :inf)) end)
  end

  defp instantiate(comparisons, vars) do
    Enum.flat_map(comparisons, fn {left, op, right} ->
      edges_for(op, Map.fetch!(vars, left), Map.fetch!(vars, right))
    end)
  end

  defp edges_for(:lt, from, to), do: lt_edges(from, to)
  defp edges_for(:eq, from, to), do: eq_edges(from, to)

  # from < to ⇒ from − to ≤ −1 (strict on the integer time-scale).
  defp lt_edges(from, to), do: [{from, to, -1}]

  # from = to ⇒ from − to ≤ 0 ∧ to − from ≤ 0.
  defp eq_edges(from, to), do: [{from, to, 0}, {to, from, 0}]

  defp min_weight(:inf, other), do: other
  defp min_weight(other, :inf), do: other
  defp min_weight(a, b), do: min(a, b)

  defp negative?(:inf), do: false
  defp negative?(weight), do: weight < 0

  @doc """
  Explain a propagated bound as a trace — the chain of constraints that
  forces it.

  Reconstructs the shortest path in the constraint graph that produces
  the `:earliest` or `:latest` value of a boundary, mirroring the
  paper's Fig. 6c. Each step names the constraint responsible and the
  bound derived so far, and `:prose` renders the whole chain as a
  sentence.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  * `boundary` is `{:start, period_id}` or `{:end, period_id}`.

  * `options` is a keyword list of options.

  ### Options

  * `:bound` is `:earliest` (the default) or `:latest`.

  ### Returns

  * `{:ok, %{value: t:Tempo.t/0, steps: list, prose: String.t()}}`;

  * `{:error, :unbounded}` when the constraints leave the bound open;

  * `{:error, :inconsistent}` when the network has no valid assignment;
    or

  * `{:error, reason}` for an error the network's builders recorded, a
    boundary that is not `{:start, id}` or `{:end, id}`, or an option
    `trace/3` does not take.

  ### Examples

      iex> {:ok, trace} =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:k1, from: {:not_before, ~o"1200Y"}, duration: {:at_least, ~o"P20Y"})
      ...>   |> Tempo.Network.add_period(:k2, duration: {:at_least, ~o"P35Y"})
      ...>   |> Tempo.Network.add_sequence([:k1, :k2])
      ...>   |> Tempo.Network.Solver.trace({:end, :k2})
      iex> trace.value
      ~o"1255Y"

  """
  @spec trace(Network.t(), {:start | :end, term()}, keyword()) ::
          {:ok, map()} | {:error, :unbounded | :inconsistent | Exception.t()}
  def trace(network, boundary, options \\ [])

  def trace(%Network{} = network, {edge, _id} = boundary, options) when edge in [:start, :end] do
    with :ok <- Network.check(network),
         {:ok, bound} <- trace_bound(options) do
      traced(network, boundary, bound)
    end
  end

  def trace(%Network{}, boundary, _options) do
    {:error,
     ArgumentError.exception(
       "Tempo.Network.Solver.trace/3 takes {:start, id} or {:end, id}, not #{inspect(boundary)}."
     )}
  end

  defp trace_bound(options) do
    with true <- Keyword.keyword?(options),
         [] <- Keyword.keys(options) -- [:bound],
         bound when bound in [:earliest, :latest] <- Keyword.get(options, :bound, :earliest) do
      {:ok, bound}
    else
      _invalid ->
        {:error,
         ArgumentError.exception(
           "Tempo.Network.Solver.trace/3 takes one option, :bound, :earliest or :latest, " <>
             "not #{inspect(options)}."
         )}
    end
  end

  defp traced(network, boundary, bound) do
    with {:ok, %{dist: distances} = solution} <- solved(network) do
      {from_node, to_node} = trace_nodes(boundary, bound)

      case get(distances, from_node, to_node) do
        :inf -> {:error, :unbounded}
        _weight -> trace_of(network, boundary, bound, solution, {from_node, to_node})
      end
    end
  end

  defp trace_of(network, boundary, bound, solution, {from_node, to_node}) do
    %{normalized: normalized, dist: distances, next: next} = solution
    path = reconstruct(next, from_node, to_node)
    provenance = build_provenance(normalized.edges)

    with {:ok, steps} <- build_steps(path, distances, provenance, bound, normalized),
         {:ok, value} <- bound_value(distances, boundary, bound, normalized) do
      {:ok,
       %{
         boundary: boundary,
         bound: bound,
         value: value,
         steps: steps,
         prose: render_prose(steps, boundary, bound, network)
       }}
    end
  end

  defp trace_nodes(boundary, :earliest), do: {:origin, boundary}
  defp trace_nodes(boundary, :latest), do: {boundary, :origin}

  # --- bound extraction ------------------------------------------

  defp tighten_period(id, period, distances, normalized) do
    start = {:start, id}
    finish = {:end, id}

    with {:ok, earliest_start} <- lower(distances, start, normalized),
         {:ok, latest_start} <- upper(distances, start, normalized),
         {:ok, earliest_end} <- lower(distances, finish, normalized),
         {:ok, latest_end} <- upper(distances, finish, normalized),
         {:ok, min_duration} <- min_span(distances, start, finish, normalized),
         {:ok, max_duration} <- max_span(distances, start, finish, normalized) do
      {:ok,
       %{
         period
         | earliest_start: earliest_start,
           latest_start: latest_start,
           earliest_end: earliest_end,
           latest_end: latest_end,
           min_duration: min_duration,
           max_duration: max_duration
       }}
    end
  end

  # node ≤ origin + dist(node, origin)  → latest value of node.
  defp upper(distances, node, normalized) do
    case get(distances, node, :origin) do
      :inf -> {:ok, nil}
      weight -> Normalize.date_at(weight, normalized)
    end
  end

  # origin − node ≤ dist(origin, node)  → node ≥ −dist(origin, node).
  defp lower(distances, node, normalized) do
    case get(distances, :origin, node) do
      :inf -> {:ok, nil}
      weight -> Normalize.date_at(-weight, normalized)
    end
  end

  # end − start ≤ dist(end, start) → max duration.
  defp max_span(distances, start, finish, normalized) do
    case get(distances, finish, start) do
      :inf -> {:ok, nil}
      weight -> Normalize.duration_of(weight, normalized)
    end
  end

  # start − end ≤ dist(start, end) → end − start ≥ −dist(start, end).
  defp min_span(distances, start, finish, normalized) do
    case get(distances, start, finish) do
      :inf -> {:ok, nil}
      weight when -weight <= 0 -> {:ok, nil}
      weight -> Normalize.duration_of(-weight, normalized)
    end
  end

  # --- Floyd–Warshall --------------------------------------------

  # Floyd–Warshall returning both the all-pairs distances and a
  # next-hop map for path reconstruction (`next[{i, j}]` is the first
  # node after `i` on a shortest path to `j`).
  defp shortest_paths(%{nodes: nodes, edges: edges}) do
    distances =
      for from <- nodes, to <- nodes, into: %{} do
        {{from, to}, if(from == to, do: 0, else: :inf)}
      end

    seeded =
      Enum.reduce(edges, {distances, %{}}, fn {from, to, weight, _source}, {dist, next} ->
        if less?(weight, dist[{from, to}]) do
          {%{dist | {from, to} => weight}, Map.put(next, {from, to}, to)}
        else
          {dist, next}
        end
      end)

    {dist, next} =
      for k <- nodes, i <- nodes, j <- nodes, reduce: seeded do
        {dist, next} ->
          via = add_weight(dist[{i, k}], dist[{k, j}])

          if less?(via, dist[{i, j}]) do
            {%{dist | {i, j} => via}, Map.put(next, {i, j}, next[{i, k}])}
          else
            {dist, next}
          end
      end

    %{dist: dist, next: next}
  end

  defp negative_cycle?(distances) do
    Enum.any?(distances, fn
      {{node, node}, weight} -> weight != :inf and weight < 0
      _other -> false
    end)
  end

  defp get(distances, from, to), do: Map.get(distances, {from, to}, :inf)

  defp add_weight(:inf, _), do: :inf
  defp add_weight(_, :inf), do: :inf
  defp add_weight(a, b), do: a + b

  defp less?(_a, :inf), do: true
  defp less?(:inf, _b), do: false
  defp less?(a, b), do: a < b

  # --- trace reconstruction --------------------------------------

  defp reconstruct(_next, node, node), do: [node]

  defp reconstruct(next, from, to) do
    case Map.get(next, {from, to}) do
      nil -> [from]
      hop -> [from | reconstruct(next, hop, to)]
    end
  end

  # The source of the minimal-weight direct edge for each {from, to}.
  defp build_provenance(edges) do
    Enum.reduce(edges, %{}, fn {from, to, weight, source}, acc ->
      case acc[{from, to}] do
        {best, _} when best <= weight -> acc
        _ -> Map.put(acc, {from, to}, {weight, source})
      end
    end)
  end

  # Each path hop becomes a step naming the constraint that justifies it
  # and the bound derived at the reached boundary. The origin carries no
  # bound of its own, so it never appears as a step.
  defp build_steps(path, distances, provenance, bound, normalized) do
    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reject(fn [_prev, node] -> node == :origin end)
    |> Enum.reduce_while({:ok, []}, fn [prev, node], {:ok, steps} ->
      {_weight, source} = Map.fetch!(provenance, {prev, node})

      case bound_value(distances, node, bound, normalized) do
        {:ok, value} -> {:cont, {:ok, [%{boundary: node, value: value, source: source} | steps]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> in_order()
  end

  defp in_order({:ok, steps}), do: {:ok, Enum.reverse(steps)}
  defp in_order({:error, _reason} = error), do: error

  defp bound_value(distances, boundary, :earliest, normalized) do
    Normalize.date_at(-get(distances, :origin, boundary), normalized)
  end

  defp bound_value(distances, boundary, :latest, normalized) do
    Normalize.date_at(get(distances, boundary, :origin), normalized)
  end

  # --- trace prose -----------------------------------------------

  defp render_prose(steps, _boundary, bound, network) do
    Enum.map_join(steps, "; ", fn step ->
      "#{render_source(step.source, network)} ⇒ " <>
        "#{boundary_phrase(step.boundary, network)} #{comparison(bound)} #{year_label(step.value)}"
    end)
  end

  defp render_source({:bound, :start, :lower, id, value}, network),
    do: "#{label(network, id)} starts no earlier than #{year_label(value)}"

  defp render_source({:bound, :start, :upper, id, value}, network),
    do: "#{label(network, id)} starts no later than #{year_label(value)}"

  defp render_source({:bound, :end, :lower, id, value}, network),
    do: "#{label(network, id)} ends no earlier than #{year_label(value)}"

  defp render_source({:bound, :end, :upper, id, value}, network),
    do: "#{label(network, id)} ends no later than #{year_label(value)}"

  defp render_source({:duration, :min, id, duration}, network),
    do: "#{label(network, id)} lasts at least #{duration_label(duration)}"

  defp render_source({:duration, :max, id, duration}, network),
    do: "#{label(network, id)} lasts at most #{duration_label(duration)}"

  defp render_source({:non_negative, id}, network),
    do: "#{label(network, id)} cannot end before it starts"

  defp render_source({:sequence, a, b}, network),
    do: "#{label(network, a)} immediately precedes #{label(network, b)}"

  defp render_source({:relation, relation}, network) do
    "#{label(network, relation.from)} #{relation_phrase(relation.type)} #{label(network, relation.to)}"
  end

  defp relation_phrase(:starts_during), do: "starts during"
  defp relation_phrase(:ends_during), do: "ends during"
  defp relation_phrase(:includes_start), do: "includes the start of"
  defp relation_phrase(:includes_end), do: "includes the end of"
  defp relation_phrase(:included_in), do: "is included in"
  defp relation_phrase(:includes), do: "includes"
  defp relation_phrase(:contemporary), do: "is contemporary with"
  defp relation_phrase(:overlaps), do: "overlaps"
  defp relation_phrase(:overlapped_by), do: "is overlapped by"
  defp relation_phrase(:before), do: "is before"
  defp relation_phrase(:after), do: "is after"
  defp relation_phrase(:immediately_precedes), do: "immediately precedes"
  defp relation_phrase(:immediately_follows), do: "immediately follows"
  defp relation_phrase(:synchronous_start), do: "shares a start with"
  defp relation_phrase(:synchronous_end), do: "shares an end with"
  defp relation_phrase(:equals), do: "equals"
  defp relation_phrase({:delay, _, _, _, _}), do: "is offset from"

  defp boundary_phrase({:start, id}, network), do: "the start of #{label(network, id)}"
  defp boundary_phrase({:end, id}, network), do: "the end of #{label(network, id)}"

  defp comparison(:earliest), do: "≥"
  defp comparison(:latest), do: "≤"

  defp label(network, id) do
    case network.periods[id] do
      %{name: name} when is_binary(name) -> name
      _ -> to_string(id)
    end
  end

  defp year_label(%Tempo{time: time}), do: "#{Keyword.get(time, :year)}"

  defp duration_label(%Tempo.Duration{time: time}) do
    case Keyword.get(time, :year) do
      nil -> Inspect.inspect(%Tempo.Duration{time: time}, %Inspect.Opts{})
      years -> "#{years} years"
    end
  end
end
