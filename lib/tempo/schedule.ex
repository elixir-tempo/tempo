defmodule Tempo.Schedule do
  @moduledoc """
  Constraint-based project scheduling over `Tempo.Network`.

  A schedule is a set of **tasks** — each with a duration — joined by
  **dependencies** (task B starts no earlier than task A finishes) and
  bounded by **anchors** and **deadlines**. `solve/1` finds, for every
  task, the earliest and latest it can run and whether it sits on the
  **critical path**. This is the classic project-scheduling / critical
  path method, expressed as the Simple Temporal Problem `Tempo.Network`
  already solves: tasks are time-periods, dependencies are boundary
  relations, and the solver's tightening is the forward/backward pass.

  ## Example

      iex> import Tempo.Sigils
      iex> {:ok, plan} =
      ...>   Tempo.Schedule.new()
      ...>   |> Tempo.Schedule.task(:design, duration: ~o"P2D", start: ~o"2026-06-01")
      ...>   |> Tempo.Schedule.task(:build, duration: ~o"P3D", after: :design)
      ...>   |> Tempo.Schedule.task(:docs, duration: ~o"P1D", after: :design)
      ...>   |> Tempo.Schedule.task(:ship, duration: ~o"P2D", after: [:build, :docs], deadline: ~o"2026-06-08")
      ...>   |> Tempo.Schedule.solve()
      iex> plan[:ship].start
      ~o"2026Y6M6D"
      iex> plan[:docs].critical?
      false

  Here *design* → *build*/​*docs* → *ship*, with *ship* due by the 8th.
  The solver schedules *ship* to start on the 6th, and finds *docs* has
  slack (it is not on the critical path) while *design*, *build*, and
  *ship* are.

  ## What it does not do

  Scheduling *around* a busy calendar — "fit this task into the first
  free gap, avoiding existing meetings" — is a disjunctive problem ("the
  task is before that meeting *or* after it") that lies outside the
  Simple Temporal Problem. For that, work with the free regions directly
  using the set operations (`Tempo.difference/2`, `Tempo.intersection/2`)
  and `Tempo.IntervalSet.slots/3`. `Tempo.Schedule` is for *dependency*
  scheduling, where the constraints compose by conjunction.

  """

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.Network
  alias Tempo.Network.Solver
  alias Tempo.Schedule.Slot

  @typedoc "A schedule under construction."
  @type t :: %__MODULE__{network: Network.t()}

  defstruct network: nil

  # A dependency is finish-to-start: the successor starts no earlier
  # than the predecessor finishes (gaps allowed).
  @finish_to_start {:boundary, :start, :at_or_after, :end}

  @doc """
  An empty schedule.

  ### Returns

  * an empty `t:t/0`.

  ### Examples

      iex> schedule = Tempo.Schedule.new()
      iex> map_size(schedule.network.periods)
      0

  """
  @spec new() :: t()
  def new, do: %__MODULE__{network: Network.new()}

  @doc """
  Add a task to the schedule.

  ### Arguments

  * `schedule` is the schedule to extend.

  * `id` is any term uniquely identifying the task.

  ### Options

  * `:duration` is the task's duration — an exact `t:Tempo.Duration.t/0`
    or a `{min, max}` range.

  * `:after` is a task id, or list of ids, this task depends on: it
    starts no earlier than each of them finishes.

  * `:start` pins the task's start to an exact date (an anchor).

  * `:earliest` requires the task to start on or after a date.

  * `:deadline` requires the task to finish on or before a date.

  * `:within` is a `{earliest_start, latest_finish}` window the task
    must fall inside.

  ### Returns

  * the schedule with the task added.

  ### Examples

      iex> import Tempo.Sigils
      iex> schedule = Tempo.Schedule.new() |> Tempo.Schedule.task(:a, duration: ~o"P2D")
      iex> Map.keys(schedule.network.periods)
      [:a]

  """
  @spec task(t(), term(), keyword()) :: t()
  def task(%__MODULE__{network: network} = schedule, id, options \\ []) do
    network =
      network
      |> Network.add_period(id, period_options(options))
      |> add_dependencies(id, Keyword.get(options, :after, []))

    %{schedule | network: network}
  end

  @doc """
  Solve the schedule, finding each task's early and late position.

  ### Arguments

  * `schedule` is a `t:t/0`.

  ### Returns

  * `{:ok, plan}` where `plan` is a map of `id => t:Tempo.Schedule.Slot.t/0`;
    or

  * `{:error, :infeasible}` when the dependencies, durations, and bounds
    cannot all be satisfied.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, plan} =
      ...>   Tempo.Schedule.new()
      ...>   |> Tempo.Schedule.task(:a, duration: ~o"P2D", start: ~o"2026-06-01")
      ...>   |> Tempo.Schedule.task(:b, duration: ~o"P3D", after: :a)
      ...>   |> Tempo.Schedule.solve()
      iex> {plan[:a].start, plan[:b].start}
      {~o"2026Y6M1D", ~o"2026Y6M3D"}

  """
  @spec solve(t()) :: {:ok, %{optional(term()) => Slot.t()}} | {:error, :infeasible}
  def solve(%__MODULE__{network: network}) do
    case Solver.tighten(network) do
      {:ok, tightened} ->
        {:ok, Map.new(tightened.periods, fn {id, period} -> {id, to_slot(id, period)} end)}

      {:error, :inconsistent} ->
        {:error, :infeasible}
    end
  end

  @doc """
  The critical path of a solved plan — the task ids with no slack, in
  start order.

  A task is critical when its earliest and latest starts coincide, so
  any delay to it delays the whole project. Requires a plan with a
  deadline; without one no task is critical and the list is empty.

  ### Arguments

  * `plan` is the map returned by `solve/1`.

  ### Returns

  * the critical task ids, ordered by start.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, plan} =
      ...>   Tempo.Schedule.new()
      ...>   |> Tempo.Schedule.task(:a, duration: ~o"P2D", start: ~o"2026-06-01")
      ...>   |> Tempo.Schedule.task(:b, duration: ~o"P3D", after: :a, deadline: ~o"2026-06-06")
      ...>   |> Tempo.Schedule.solve()
      iex> Tempo.Schedule.critical_path(plan)
      [:a, :b]

  """
  @spec critical_path(%{optional(term()) => Slot.t()}) :: [term()]
  def critical_path(plan) when is_map(plan) do
    plan
    |> Map.values()
    |> Enum.filter(& &1.critical?)
    |> Enum.sort_by(& &1.start, &start_not_after?/2)
    |> Enum.map(& &1.id)
  end

  @doc """
  The project span of a solved plan — the interval from the earliest
  task start to the latest task finish.

  ### Arguments

  * `plan` is the map returned by `solve/1`.

  ### Returns

  * a `t:Tempo.Interval.t/0` covering the whole project.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, plan} =
      ...>   Tempo.Schedule.new()
      ...>   |> Tempo.Schedule.task(:a, duration: ~o"P2D", start: ~o"2026-06-01")
      ...>   |> Tempo.Schedule.task(:b, duration: ~o"P3D", after: :a)
      ...>   |> Tempo.Schedule.solve()
      iex> span = Tempo.Schedule.span(plan)
      iex> Tempo.Interval.endpoints(span)
      {~o"2026Y6M1D", ~o"2026Y6M6D"}

  """
  @spec span(%{optional(term()) => Slot.t()}) :: Tempo.Interval.t()
  def span(plan) when is_map(plan) do
    slots = Map.values(plan)
    from = slots |> Enum.map(& &1.start) |> Enum.min_by(&Compare.to_utc_seconds/1)
    to = slots |> Enum.map(& &1.finish) |> Enum.max_by(&Compare.to_utc_seconds/1)
    Interval.new!(from: from, to: to)
  end

  # --- task options → period bounds ------------------------------

  defp period_options(options) do
    []
    |> put_duration(Keyword.get(options, :duration))
    |> put_start(options)
    |> put_end(options)
  end

  defp put_duration(opts, nil), do: opts
  defp put_duration(opts, duration), do: Keyword.put(opts, :duration, duration)

  defp put_start(opts, options) do
    cond do
      Keyword.has_key?(options, :start) ->
        Keyword.put(opts, :start, Keyword.fetch!(options, :start))

      Keyword.has_key?(options, :earliest) ->
        Keyword.put(opts, :start, {:not_before, Keyword.fetch!(options, :earliest)})

      match?({_, _}, Keyword.get(options, :within)) ->
        {earliest, _latest} = Keyword.fetch!(options, :within)
        Keyword.put(opts, :start, {:not_before, earliest})

      true ->
        opts
    end
  end

  defp put_end(opts, options) do
    cond do
      Keyword.has_key?(options, :deadline) ->
        Keyword.put(opts, :end, {:not_after, Keyword.fetch!(options, :deadline)})

      match?({_, _}, Keyword.get(options, :within)) ->
        {_earliest, latest} = Keyword.fetch!(options, :within)
        Keyword.put(opts, :end, {:not_after, latest})

      true ->
        opts
    end
  end

  defp add_dependencies(network, id, after_ids) when is_list(after_ids) do
    Enum.reduce(after_ids, network, fn dependency, network ->
      Network.add_relation(network, @finish_to_start, id, dependency)
    end)
  end

  defp add_dependencies(network, id, dependency) do
    add_dependencies(network, id, [dependency])
  end

  # --- tightened period → slot -----------------------------------

  defp to_slot(id, period) do
    %Slot{
      id: id,
      start: period.earliest_start,
      finish: period.earliest_end,
      latest_start: period.latest_start,
      latest_finish: period.latest_end,
      critical?: critical?(period.earliest_start, period.latest_start)
    }
  end

  # Critical when the early and late starts coincide (no slack). When
  # there is no deadline the late start is unbounded (`nil`) and
  # criticality is undetermined.
  defp critical?(%Tempo{} = earliest, %Tempo{} = latest) do
    Compare.compare_endpoints(earliest, latest) == :same
  end

  defp critical?(_earliest, _latest), do: nil

  defp start_not_after?(a, b) do
    Compare.compare_endpoints(a, b) in [:earlier, :same]
  end
end
