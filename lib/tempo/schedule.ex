defmodule Tempo.Schedule do
  @moduledoc """
  Constraint-based project scheduling over `Tempo.Network`.

  A schedule is a set of **tasks** — each with a duration — joined by
  **dependencies** (task B starts no earlier than task A finishes) and
  bounded by **fixed starts** and **deadlines**. `solve/1` finds, for every
  task, the earliest and latest it can run and whether it sits on the
  **critical path**. This is the classic project-scheduling / critical
  path method, expressed as the Simple Temporal Problem `Tempo.Network`
  already solves: tasks are time-periods, dependencies are boundary
  relations, and the solver's propagation is the forward/backward pass.

  ## Example

      iex> import Tempo.Sigils
      iex> {:ok, plan} =
      ...>   Tempo.Schedule.new()
      ...>   |> Tempo.Schedule.task(:design, duration: ~o"P2D", start: ~o"2026-06-01")
      ...>   |> Tempo.Schedule.task(:build, duration: ~o"P3D", after: :design)
      ...>   |> Tempo.Schedule.task(:docs, duration: ~o"P1D", after: :design)
      ...>   |> Tempo.Schedule.task(:ship, duration: ~o"P2D", after: [:build, :docs], deadline: ~o"2026-06-08")
      ...>   |> Tempo.Schedule.solve()
      iex> plan[:ship].early
      ~o"2026Y6M6D/8D"
      iex> plan[:docs].critical?
      false

  Here *design* → *build*/​*docs* → *ship*, with *ship* due by the 8th.
  The solver schedules *ship* for the 6th to the 8th, and finds *docs*
  has slack (it is not on the critical path) while *design*, *build*,
  and *ship* are.

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
  alias Tempo.IntervalEndpointsError
  alias Tempo.Network
  alias Tempo.Network.Solver
  alias Tempo.Schedule.ScheduledTask

  @typedoc "A schedule under construction."
  @type t :: %__MODULE__{network: Network.t()}

  defstruct network: nil

  # A dependency is finish-to-start: the successor starts no earlier
  # than the predecessor finishes (gaps allowed).
  @finish_to_start {:boundary, :start, :at_or_after, :end}

  @task_options [:duration, :after, :start, :not_before, :deadline, :within]

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

  An option `task/3` does not take, or a value it cannot read, is
  recorded on the schedule rather than raised, and `solve/1` returns it.

  ### Arguments

  * `schedule` is the schedule to extend.

  * `id` is any term uniquely identifying the task.

  * `options` is a keyword list of options.

  ### Options

  * `:duration` is the task's duration — an exact `t:Tempo.Duration.t/0`
    or a `{min, max}` range.

  * `:after` is a task id, or list of ids, this task depends on: it
    starts no earlier than each of them finishes.

  * `:start` fixes the task's start on an exact date.

  * `:not_before` requires the task to start on or after a date.

  * `:deadline` requires the task to finish on or before a date.

  * `:within` is the window the task lies in, a Tempo value or an
    interval as every `:within` is: the task starts no earlier than the
    window does and finishes no later than it ends, so `within: ~o"2026-06"`
    is a task done in June.

  ### Returns

  * the schedule with the task added, or with an error recorded.

  ### Examples

      iex> import Tempo.Sigils
      iex> schedule = Tempo.Schedule.new() |> Tempo.Schedule.task(:a, duration: ~o"P2D")
      iex> Map.keys(schedule.network.periods)
      [:a]

  """
  @spec task(t(), term(), keyword()) :: t()
  def task(%__MODULE__{network: network} = schedule, id, options \\ []) do
    %{schedule | network: add_task(network, id, options, task_options(options))}
  end

  @doc """
  Solve the schedule, finding each task's early and late schedule.

  ### Arguments

  * `schedule` is a `t:t/0`.

  ### Returns

  * `{:ok, plan}` where `plan` is a map of
    `id => t:Tempo.Schedule.ScheduledTask.t/0`;

  * `{:error, :infeasible}` when the dependencies, durations, and bounds
    cannot all be satisfied; or

  * `{:error, reason}` for an option or a value `task/3` could not read.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, plan} =
      ...>   Tempo.Schedule.new()
      ...>   |> Tempo.Schedule.task(:a, duration: ~o"P2D", start: ~o"2026-06-01")
      ...>   |> Tempo.Schedule.task(:b, duration: ~o"P3D", after: :a)
      ...>   |> Tempo.Schedule.solve()
      iex> {plan[:a].early, plan[:b].early}
      {~o"2026Y6M1D/3D", ~o"2026Y6M3D/6D"}

      iex> import Tempo.Sigils
      iex> {:error, %ArgumentError{} = error} =
      ...>   Tempo.Schedule.new()
      ...>   |> Tempo.Schedule.task(:a, duration: ~o"P2D", earliest: ~o"2026-06-01")
      ...>   |> Tempo.Schedule.solve()
      iex> Exception.message(error)
      "Tempo.Schedule.task/3 takes :not_before where 1.x took :earliest."

  """
  @spec solve(t()) ::
          {:ok, %{optional(term()) => ScheduledTask.t()}}
          | {:error, :infeasible | Exception.t()}
  def solve(%__MODULE__{network: network}) do
    case Solver.propagate(network) do
      {:ok, propagated} ->
        {:ok, Map.new(propagated.periods, fn {id, period} -> {id, scheduled(id, period)} end)}

      {:error, :inconsistent} ->
        {:error, :infeasible}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  The critical path of a solved plan — the task ids with no slack, in
  start order.

  A task is critical when its early and late schedules start together,
  so any delay to it delays the whole project. Requires a plan with a
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
  @spec critical_path(%{optional(term()) => ScheduledTask.t()}) :: [term()]
  def critical_path(plan) when is_map(plan) do
    plan
    |> Map.values()
    |> Enum.filter(& &1.critical?)
    |> Enum.sort_by(&Interval.from(&1.early), &start_not_after?/2)
    |> Enum.map(& &1.id)
  end

  @doc """
  The project span of a solved plan — the interval from the earliest
  task start to the latest task finish.

  ### Arguments

  * `plan` is the map returned by `solve/1`.

  ### Returns

  * a `t:Tempo.Interval.t/0` covering the whole project; or

  * `{:error, reason}` when the plan has no tasks, or no fixed start or
    `:not_before` date to place them by.

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
  @spec span(%{optional(term()) => ScheduledTask.t()}) ::
          Tempo.Interval.t() | {:error, Exception.t()}
  def span(plan) when is_map(plan) do
    case plan |> Map.values() |> Enum.map(& &1.early) do
      [_ | _] = schedules -> span_of(schedules)
      [] -> {:error, no_span("A plan with no tasks has no span.")}
    end
  end

  defp span_of(schedules) do
    if Enum.all?(schedules, &match?(%Interval{}, &1)) do
      from = schedules |> Enum.map(&Interval.from/1) |> Enum.min_by(&Compare.to_utc_seconds/1)
      to = schedules |> Enum.map(&Interval.to/1) |> Enum.max_by(&Compare.to_utc_seconds/1)
      Interval.new!(from: from, to: to)
    else
      {:error,
       no_span(
         "A plan with no fixed start or :not_before date has no span: its tasks are " <>
           "placed only relative to each other."
       )}
    end
  end

  defp no_span(reason), do: IntervalEndpointsError.exception(operation: :span, reason: reason)

  # --- task options → period bounds ------------------------------

  defp add_task(network, id, options, :ok) do
    network
    |> Network.add_period(id, period_options(options))
    |> add_dependencies(id, Keyword.get(options, :after, []))
  end

  defp add_task(network, _id, _options, {:error, exception}),
    do: Network.record_error(network, exception)

  defp task_options(options) do
    if Keyword.keyword?(options) do
      options
      |> Keyword.keys()
      |> Enum.find(&(&1 not in @task_options))
      |> unknown_task_option(options)
    else
      {:error, invalid("takes a keyword list of options, not #{inspect(options)}")}
    end
  end

  defp unknown_task_option(nil, options), do: within_option(Keyword.get(options, :within))

  defp unknown_task_option(:earliest, _options),
    do: {:error, invalid("takes :not_before where 1.x took :earliest")}

  defp unknown_task_option(key, _options),
    do:
      {:error,
       invalid("does not take #{inspect(key)}; its options are #{inspect(@task_options)}")}

  # A window is a value or an interval with both its ends, as it is
  # wherever `:within` is taken. It was a `{from, to}` pair here alone.
  defp within_option(nil), do: :ok

  defp within_option({_from, _to}) do
    {:error,
     invalid(
       "takes :within as a window, a Tempo value or an interval, where 1.x took a " <>
         "{from, to} pair: write the pair as the interval from the one to the other"
     )}
  end

  defp within_option(within) do
    case window_ends(within) do
      {:ok, _ends} ->
        :ok

      :error ->
        {:error,
         invalid(
           "takes :within as a window with a start and an end, a Tempo value or an " <>
             "interval, not #{inspect(within)}"
         )}
    end
  end

  defp window_ends(%Tempo.Interval{} = window), do: ends_of(Tempo.to_interval(window))
  defp window_ends(%Tempo{} = window), do: ends_of(Tempo.to_interval(window))
  defp window_ends(_other), do: :error

  # A bound is a point: a month given as one is read as any day of it, so
  # the window's ends are written to the day they fall on, where they are
  # coarser than one. June's end is the start of 1 July.
  defp ends_of({:ok, %Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to}}),
    do: {:ok, {to_the_day(from), to_the_day(to)}}

  defp ends_of(_no_one_span), do: :error

  defp to_the_day(%Tempo{} = point) do
    case Tempo.extend_resolution(point, :day) do
      %Tempo{} = day -> day
      {:error, _finer_than_a_day} -> point
    end
  end

  defp invalid(phrase), do: ArgumentError.exception("Tempo.Schedule.task/3 #{phrase}.")

  defp period_options(options) do
    []
    |> put_duration(Keyword.get(options, :duration))
    |> put_from(options)
    |> put_to(options)
  end

  defp put_duration(opts, nil), do: opts
  defp put_duration(opts, duration), do: Keyword.put(opts, :duration, duration)

  defp put_from(opts, options) do
    cond do
      Keyword.has_key?(options, :start) ->
        Keyword.put(opts, :from, Keyword.fetch!(options, :start))

      Keyword.has_key?(options, :not_before) ->
        Keyword.put(opts, :from, {:not_before, Keyword.fetch!(options, :not_before)})

      true ->
        within(opts, :from, :not_before, options)
    end
  end

  defp put_to(opts, options) do
    if Keyword.has_key?(options, :deadline),
      do: Keyword.put(opts, :to, {:not_after, Keyword.fetch!(options, :deadline)}),
      else: within(opts, :to, :not_after, options)
  end

  # The window's start bounds the task's start and its end the task's end,
  # where no other option has bounded them.
  defp within(opts, bound, kind, options) do
    case window_ends(Keyword.get(options, :within)) do
      {:ok, {from, to}} ->
        Keyword.put(opts, bound, {kind, if(bound == :from, do: from, else: to)})

      :error ->
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

  # --- propagated period → scheduled task ------------------------

  defp scheduled(id, period) do
    %ScheduledTask{
      id: id,
      early: schedule_interval(period.earliest_start, period.earliest_end),
      late: schedule_interval(period.latest_start, period.latest_end),
      critical?: critical?(period.earliest_start, period.latest_start)
    }
  end

  # A schedule is known when both its ends are: the early one when the
  # plan is placed by a fixed start or :not_before date, the late one
  # when something bounds how late the task can run.
  defp schedule_interval(%Tempo{} = from, %Tempo{} = to), do: %Interval{from: from, to: to}
  defp schedule_interval(_from, _to), do: nil

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
