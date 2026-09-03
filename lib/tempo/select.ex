defmodule Tempo.Select do
  @moduledoc """
  Narrow a Tempo span by a selector — the composition primitive
  for "workdays of June", "the 15th of every month", "every
  Dec 25 in the next decade", and user-supplied holidays.

  ```elixir
  Tempo.select(~o"2026-06", Tempo.workdays(:US))  # workdays of June — locale-aware
  Tempo.select(~o"2026-06", Tempo.weekend(:US))   # weekend days of June
  Tempo.select(~o"2026", [1, 15])
  Tempo.select(~o"2026", ~o"12-25")
  Tempo.select(~o"2026", ~o"10O")     # ISO 8601-2 ordinal day — the 10th day of 2026
  Tempo.select(~o"2026-06", ~o"5K")   # ISO 8601-2 day-of-week — every Friday in June 2026
  Tempo.select(~o"2026", ~o"-1M")     # ISO 8601-2 negative — the last month of 2026
  Tempo.select(~o"2026-06", ~o"-1D")  # ISO 8601-2 negative — the last day of June 2026
  Tempo.select(~o"2026", &my_holidays/1)
  ```

  Every call returns `{:ok, %Tempo.IntervalSet{}}` (or
  `{:error, reason}`), consistent with the other set-algebra
  operations — the result composes directly into
  `Tempo.union/2`, `Tempo.intersection/2`, `Tempo.difference/2`.

  `Tempo.select/2` is a **pure function**. It has no `opts`, no
  ambient locale read, no implicit territory resolution. Every
  input that can affect the result is a value on the selector.
  Locale-dependent constraints like "workdays" or "weekend" are
  constructed by `Tempo.workdays/1` and `Tempo.weekend/1` (which
  read the locale once at construction time) and composed in:

      interval
      |> Tempo.select(Tempo.workdays(:US))

  That means the `workdays(:US)` call is where territory
  resolution happens — **not** inside `select/2` — and the
  resulting value is safe to capture anywhere, including
  module attributes.

  ## Selector shapes

  | Shape | Example | Meaning |
  | ----- | ------- | ------- |
  | `[integer]` / `Range` | `Tempo.select(m, [1, 15])` | Integer indices applied at base's next-finer unit |
  | `%Tempo{}` or list | `Tempo.select(y, ~o"12-25")` | Project the constraint's specified units onto the base |
  | `%Tempo{day_of_week: …}` | `Tempo.select(m, ~o"5K")` | Day-of-week pattern — every matching weekday in the base (ISO 8601-2 `K` suffix) |
  | `%Tempo{day_of_week: [...]}` | `Tempo.select(m, Tempo.workdays(:US))` | Day-of-week list — every matching weekday in the base |
  | `%Tempo{day: N}` (ordinal) | `Tempo.select(y, ~o"10O")` | Ordinal day in the year — the Nth day (ISO 8601-2 `O` suffix) |
  | Negative components | `Tempo.select(y, ~o"-1M")` | ISO 8601-2 §4.4.1 — count from the end of the containing unit |
  | `%Tempo.Interval{}` or list | `Tempo.select(days, ~o"T09/T17")` | Project as a **span** — coarser units from the base, finer from each endpoint, half-open `[from, to)` |
  | Interval duration form | `Tempo.select(days, ~o"T09/PT7H36M")` | Span from the projected start plus the duration |
  | Function | `Tempo.select(y, &fn/1)` | The function returns any of the above; evaluated against the base |

  Base can be a `t:Tempo.t/0`, `t:Tempo.Interval.t/0`, or
  `t:Tempo.IntervalSet.t/0`. IntervalSet bases flat-map the
  selector across each member and collect the results.

  ## Time-of-day windows — interval selectors project as spans

  Narrowing every member of a day set to the same part of each day is
  one expression: an interval selector keeps its whole extent, so
  "nine to five" is a single eight-hour span per member — half-open,
  written as nine to five, with no off-by-one and no `coalesce/1`. A
  list gives several windows per member (the business-hours-with-lunch
  case), and the duration form expresses windows that are not
  hour-aligned:

  ```elixir
  {:ok, workdays} = Tempo.select(~o"2026-07", Tempo.workdays(:AU))
  {:ok, open}     = Tempo.select(workdays, [~o"T09/T12", ~o"T13/T17"])
  {:ok, shift}    = Tempo.select(workdays, ~o"T09/PT7H36M")
  ```

  > *"The workdays of July, nine to five with an hour for lunch."*

  A window whose `to` is at or before its `from` crosses midnight and
  **rolls forward**: `~o"T21/T05"` on the 15th is the span from the
  15th 21:00 to the 16th 05:00 — a night shift reads the way a roster
  writes it. Use the duration form (`~o"T21/PT8H"`) to say the same
  thing explicitly.

  ## Negative components — "last N from the end"

  ISO 8601-2 §4.4.1 allows any integer component to be negative,
  meaning "count from the end of the containing time-scale unit".
  `Tempo.select/2` honours this: the resolution is context-aware
  and produces end-of-span selections without string munging or
  calendar arithmetic at the call site.

  ```elixir
  Tempo.select(~o"2026",    ~o"-1M")   #=> December 2026 (last month of year)
  Tempo.select(~o"2026",    ~o"-1D")   #=> Dec 31 2026 (last day of year)
  Tempo.select(~o"2026",    ~o"-1W")   #=> week 52 of 2026 (last ISO week)
  Tempo.select(~o"2026-06", ~o"-1D")   #=> Jun 30 2026 (last day of month)
  Tempo.select(~o"2026-02", ~o"-1D")   #=> Feb 28 2026 (leap-aware — Feb 29 in 2024)
  Tempo.select(~o"2026-06-15", ~o"-1H") #=> 23:00 (last hour of day)
  Tempo.select(~o"2026-06-15T14", ~o"T-1M") #=> 14:59 (last minute of hour)
  ```

  The resolution is calendar-aware — `Tempo.select(~o"2024-02",
  ~o"-1D")` returns Feb 29 because 2024 is a leap year. It is
  also axis-aware: `-1W` on a year base uses ISO
  weeks-in-year (52 or 53); `-1W` on a month base uses weeks of
  that month (4 or 5). `-1M` always refers to the calendar
  month; `-1K` to the week's last day-of-week; `-1O` to the
  year's last ordinal day.

  Time-of-day components (`:hour`, `:minute`, `:second`,
  `:day_of_week`) have fixed ranges and resolve at **parse time**
  — `~o"-1H"` parses directly as `hour: 23`, `~o"T-1M"` as
  `minute: 59`, `~o"T-1S"` as `second: 59`, `~o"-1K"` as
  `day_of_week: 7`. Calendar-dependent units (`:month`, `:week`,
  `:day`, `:day_of_year`) keep their negative value through parse
  and are resolved against the base context when `Tempo.select/2`
  materialises them.

  `~o"-1M"` is always "last month" (never "last minute") — use
  the `T` time designator (`~o"T-1M"`) to select minute-of-hour.

  Negative `:year` values are preserved (BC designator per ISO
  8601-2 expanded year form) — they're not flipped to "last
  year" because a time line has no "end" to count from.

  """

  alias Tempo.Compare
  alias Tempo.Duration
  alias Tempo.Interval
  alias Tempo.Interval.Steps
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError
  alias Tempo.Iso8601.Unit
  alias Tempo.MaterialisationError
  alias Tempo.Math
  alias Tempo.Validation

  @type selector ::
          [integer()]
          | Range.t()
          | Tempo.t()
          | Interval.t()
          | [Tempo.t() | Interval.t()]
          | (base() -> selector())

  @type base :: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()

  # Time units from coarsest to finest. Used for constraint-vs-base
  # resolution comparison, merged-keyword-list canonical ordering,
  # and the `propagate_last_for_negatives/3` intermediate detection.
  @unit_order_coarse_to_fine [
    :year,
    :month,
    :week,
    :day,
    :day_of_year,
    :day_of_week,
    :hour,
    :minute,
    :second
  ]

  @doc """
  Narrow `base` by `selector`, returning the selected intervals
  as a `t:Tempo.IntervalSet.t/0`.

  See the module doc for the selector vocabulary and runtime-
  resolution caveats.

  ### Supported base shapes

  `base` can be any Tempo value that materialises to an Interval
  or IntervalSet. Grouped and masked forms have their endpoints
  resolved to concrete values before the selector runs, so every
  ISO 8601-2 shape composes with every selector:

  | Base shape | Example | Materialises to |
  | ---------- | ------- | --------------- |
  | Scalar `%Tempo{}` | `~o"2026-06"` | single Interval |
  | Explicit Interval | `~o"2026-07/2026-10"` | single Interval |
  | IntervalSet | output of `Tempo.union/2` etc. | IntervalSet (flat-mapped) |
  | Quarter (`NQ`) | `~o"2026Y3Q"` | single Interval (group resolved) |
  | Season (codes 25–32) | `~o"2026Y26M"` | Interval bounded by equinox/solstice |
  | Month/day range in a slot | `~o"2026Y{6..8}M"` | IntervalSet of three members |
  | Stepped range | `~o"2026Y{1..-1//3}M"` | IntervalSet of disjoint members |
  | Set of intervals | `~o"{2026-01-05/2026-01-12,2026-02-02/2026-02-09}"` | IntervalSet (flat-mapped) |
  | Archaeological mask | `~o"156X"` | decade-long Interval |

  Example with a quarter base:

      Tempo.select(~o"2026Y3Q", Tempo.workdays(:US))
      #=> {:ok, IntervalSet with 66 members — workdays of Q3 2026}

  ### Examples

      iex> {:ok, set} = Tempo.Select.select(~o"2026-02", [1, 15])
      iex> Enum.map(Tempo.IntervalSet.to_list(set), &Tempo.day(Tempo.Interval.from(&1)))
      [1, 15]

      iex> {:ok, set} = Tempo.Select.select(~o"2026", ~o"12-25")
      iex> [xmas] = Tempo.IntervalSet.to_list(set)
      iex> xmas.from.time
      [year: 2026, month: 12, day: 25]

      iex> {:ok, set} = Tempo.Select.select(~o"2026", ~o"10O")
      iex> [day10] = Tempo.IntervalSet.to_list(set)
      iex> from = Tempo.Interval.from(day10)
      iex> {Tempo.month(from), Tempo.day(from)}
      {1, 10}

      iex> {:ok, set} = Tempo.Select.select(~o"2026-06", ~o"5K")
      iex> set |> Tempo.IntervalSet.to_list() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [5, 12, 19, 26]

      iex> {:ok, set} = Tempo.Select.select(~o"2026-02", Tempo.workdays(:US))
      iex> Tempo.IntervalSet.count(set)
      20

  """
  @spec select(base(), selector()) ::
          {:ok, IntervalSet.t()} | {:error, term()}

  # ---- IntervalSet base: flat-map then reassemble ----

  def select(%IntervalSet{} = set, selector) do
    set
    |> IntervalSet.to_list()
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case select(member, selector) do
        {:ok, %IntervalSet{} = set} -> {:cont, {:ok, acc ++ IntervalSet.to_list(set)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, all} -> IntervalSet.new(all, coalesce: false)
      err -> err
    end
  end

  # ---- Tempo base: materialise to interval, recurse ----
  #
  # For integer-index selectors we need the ORIGINAL resolution
  # (before `to_interval` fills lower-bound units), so route
  # integer / range selectors through a dedicated path.

  def select(%Tempo{} = tempo, %Range{} = range) do
    select(tempo, Enum.to_list(range))
  end

  def select(%Tempo{} = tempo, [head | _] = indices) when is_integer(head) do
    select_indices_on_tempo(tempo, indices)
  end

  def select(%Tempo{} = tempo, selector) do
    case Tempo.to_interval(tempo) do
      {:ok, %Interval{} = iv} -> select(resolve_grouped_endpoints(iv), selector)
      {:ok, %IntervalSet{} = set} -> select(set, selector)
      {:error, _} = err -> err
    end
  end

  # ---- Tempo.Set base (e.g. a set-of-intervals sigil): materialise,
  # recurse. Keeps the moduledoc's promise that any Tempo value which
  # materialises to an Interval or IntervalSet can be a base.

  def select(%Tempo.Set{} = set, selector) do
    case Tempo.to_interval(set) do
      {:ok, %Interval{} = iv} -> select(resolve_grouped_endpoints(iv), selector)
      {:ok, %IntervalSet{} = materialised} -> select(materialised, selector)
      {:error, _} = err -> err
    end
  end

  # ---- Empty selector list — explicit short-circuit ----

  def select(%Interval{} = _base, []) do
    IntervalSet.new([], coalesce: false)
  end

  # ---- Range: expand to integer list ----

  def select(%Interval{} = base, %Range{} = range) do
    select(base, Enum.to_list(range))
  end

  # ---- Integer list: indices at next-finer unit ----

  def select(%Interval{} = base, [head | _] = indices) when is_integer(head) do
    select_indices(base, indices)
  end

  # ---- Tempo / Interval projection (single or list) ----

  def select(%Interval{} = base, %Tempo{} = tempo) do
    select(base, [tempo])
  end

  def select(%Interval{} = base, %Interval{} = iv) do
    select(base, [iv])
  end

  def select(%Interval{} = base, [%Tempo{} | _] = tempos) do
    select_projections(base, tempos)
  end

  def select(%Interval{} = base, [%Interval{} | _] = intervals) do
    select_projections(base, intervals)
  end

  # ---- Function: evaluate, recurse on the result ----

  def select(%Interval{} = base, fun) when is_function(fun, 1) do
    select(base, fun.(base))
  end

  # ---- Catch-all: clearer error ----

  def select(base, selector) do
    {:error,
     ArgumentError.exception(
       "Tempo.Select.select/2 does not recognise selector #{inspect(selector)} " <>
         "for base #{inspect(base)}. See `Tempo.Select` moduledoc for the " <>
         "selector vocabulary."
     )}
  end

  ## -----------------------------------------------------------
  ## Weekday filter — consumed by the day-of-week-only projection
  ## path (see `project_onto_base/2` below)
  ## -----------------------------------------------------------

  # Walk `base` day-by-day, keeping dates whose ISO day-of-week
  # (Monday=1) is in the requested set. Returns an IntervalSet of
  # day-resolution intervals.
  defp filter_by_weekdays(%Interval{from: %Tempo{} = from, to: %Tempo{} = to}, weekdays) do
    calendar = from.calendar

    intervals =
      stream_days(from, to, calendar)
      |> Stream.filter(fn {y, m, d} ->
        dow_of(calendar, y, m, d) in weekdays
      end)
      |> Enum.map(fn {y, m, d} -> day_interval(calendar, y, m, d, from) end)

    IntervalSet.new(intervals, coalesce: false)
  end

  defp filter_by_weekdays(%Interval{} = interval, _weekdays) do
    {:error,
     IntervalEndpointsError.exception(
       interval: interval,
       operation: :select_weekdays,
       reason: "Cannot select weekdays across an open-ended interval."
     )}
  end

  defp stream_days(from, to, calendar) do
    with {:ok, start_date} <- tempo_to_date(from, calendar),
         {:ok, end_date} <- tempo_to_date(to, calendar) do
      total = Date.diff(end_date, start_date)
      Stream.unfold(0, fn i -> next_day(i, total, start_date) end)
    else
      _ -> []
    end
  end

  defp next_day(i, total, _start_date) when i >= total, do: nil

  defp next_day(i, _total, start_date) do
    d = Date.add(start_date, i)
    {{d.year, d.month, d.day}, i + 1}
  end

  defp tempo_to_date(%Tempo{time: time, calendar: calendar}, calendar) do
    if Keyword.has_key?(time, :week) do
      week_time_to_date(time, calendar)
    else
      month_time_to_date(time, calendar)
    end
  end

  defp month_time_to_date(time, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month, 1),
         day when is_integer(day) <- Keyword.get(time, :day, 1) do
      Date.new(year, month, day, calendar)
    else
      _ -> :error
    end
  end

  # Week-axis endpoint — `[year, week, day_of_week]`. Week
  # numbering is ISO-week semantics regardless of the base
  # calendar (see `Tempo.Validation`), so resolve the week date
  # under `Calendrical.ISOWeek` and convert into the base
  # calendar. A week-resolution endpoint denotes the start of its
  # week, so a missing `:day_of_week` defaults to 1.
  defp week_time_to_date(time, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         week when is_integer(week) <- Keyword.get(time, :week),
         day when is_integer(day) <- Keyword.get(time, :day_of_week, 1),
         {:ok, week_date} <- Date.new(year, week, day, Calendrical.ISOWeek) do
      Date.convert(week_date, calendar)
    else
      _ -> :error
    end
  end

  defp dow_of(calendar, y, m, d) do
    case calendar.day_of_week(y, m, d, :monday) do
      {dow, _first, _last} when is_integer(dow) -> dow
      dow when is_integer(dow) -> dow
      _ -> nil
    end
  end

  defp day_interval(calendar, y, m, d, source_from) do
    from_tempo = build_day_tempo(source_from, y, m, d, calendar)

    next = day_after(y, m, d, calendar)
    to_tempo = build_day_tempo(source_from, next.year, next.month, next.day, calendar)

    %Interval{from: from_tempo, to: to_tempo}
  end

  defp day_after(y, m, d, calendar) do
    {:ok, date} = Date.new(y, m, d, calendar)
    Date.add(date, 1)
  end

  defp build_day_tempo(%Tempo{} = source, y, m, d, calendar) do
    %Tempo{source | time: [year: y, month: m, day: d], calendar: calendar}
  end

  ## -----------------------------------------------------------
  ## Integer-index selector — apply indices at next-finer unit
  ## -----------------------------------------------------------
  ##
  ## The base_unit must be the declared resolution of the SPAN,
  ## not the resolution of the from-endpoint. `Tempo.to_interval/1`
  ## fills a from-endpoint like `[year: 2026, month: 2]` down to
  ## `[year: 2026, month: 2, day: 1]`, so asking `Tempo.resolution/1`
  ## of that endpoint would wrongly say `:day`. The span itself
  ## `[2026-02-01, 2026-03-01)` ticks forward at the month — that
  ## is the authoritative resolution for the "next finer unit"
  ## derivation.

  defp select_indices(%Interval{from: %Tempo{} = from} = _base, indices) do
    # The base's own resolution comes from its endpoint, not from where
    # the endpoints happen to differ (`Interval.resolution/1`):
    # `2026-07-31/2026-08-01` is a day-resolution span whose endpoints
    # first differ at the month, and indices must land on the hours of
    # the 31st — not the days of July, nor (at a year boundary) the
    # months of the year.
    {base_unit, _count_or_finer} = Tempo.resolution(from)
    truncated_time = truncate_to_unit(from.time, base_unit)
    select_indices_at(from, truncated_time, base_unit, indices)
  end

  defp select_indices_on_tempo(%Tempo{} = tempo, indices) do
    {base_unit, _} = Tempo.resolution(tempo)
    select_indices_at(tempo, tempo.time, base_unit, indices)
  end

  defp select_indices_at(%Tempo{calendar: calendar} = source, base_time, base_unit, indices) do
    case Unit.implicit_enumerator(base_unit, calendar) do
      nil ->
        {:error,
         MaterialisationError.exception(
           value: source,
           reason:
             "Cannot select indices under #{inspect(base_unit)} — no finer unit is " <>
               "defined for that resolution."
         )}

      {next_unit, _range} ->
        intervals =
          indices
          |> Enum.map(fn idx -> project_index(source, base_time, next_unit, idx) end)
          |> Enum.reject(&is_nil/1)

        IntervalSet.new(intervals, coalesce: false)
    end
  end

  defp project_index(%Tempo{} = source, base_time, unit, idx) do
    new_time = base_time ++ [{unit, idx}]
    new_tempo = %Tempo{source | time: new_time}

    case Tempo.to_interval(new_tempo) do
      {:ok, %Interval{} = iv} -> iv
      {:ok, %IntervalSet{} = set} -> IntervalSet.first(set)
      _ -> nil
    end
  end

  # Keep entries from head until (and including) `unit`. Anything
  # finer-grained is dropped — we're about to replace it with the
  # selected index at the next unit down.
  defp truncate_to_unit(time, unit) do
    {coarser, rest} = Enum.split_while(time, fn {u, _} -> u != unit end)

    case rest do
      [{^unit, _} = entry | _] -> coarser ++ [entry]
      [] -> coarser
    end
  end

  ## -----------------------------------------------------------
  ## Projection selector — merge constraint's units onto base
  ## -----------------------------------------------------------

  defp select_projections(%Interval{} = base, constraints) do
    constraints
    |> Enum.reduce_while({:ok, []}, fn c, {:ok, acc} ->
      case project_onto_base(base, c) do
        {:error, _} = err -> {:halt, err}
        list when is_list(list) -> {:cont, {:ok, acc ++ Enum.reject(list, &is_nil/1)}}
        nil -> {:cont, {:ok, acc}}
        other -> {:cont, {:ok, acc ++ List.wrap(other)}}
      end
    end)
    |> case do
      {:ok, intervals} -> IntervalSet.new(intervals, coalesce: false)
      {:error, _} = err -> err
    end
  end

  # Merge a constraint Tempo's time units onto base's from-endpoint
  # — units specified on the constraint take precedence; others
  # inherit from base. Then materialise and intersect with base.
  #
  # A day-of-week-only constraint (`~o"5K"` for "Friday", or
  # `Tempo.workdays(:US)` — `day_of_week: [1, 2, 3, 4, 5]`) is
  # a recurring pattern rather than a specific date, so it routes
  # to the weekday filter instead of the merge-and-materialise
  # path.
  defp project_onto_base(%Interval{} = base, %Tempo{time: c_time}) do
    case day_of_week_only(c_time) do
      {:ok, weekdays} ->
        case filter_by_weekdays(base, weekdays) do
          {:ok, %IntervalSet{} = set} -> IntervalSet.to_list(set)
          {:error, _} = err -> err
        end

      :no ->
        project_merge(base, c_time)
    end
  end

  # An interval selector projects as a *span*: the coarser units come
  # from the base member and the finer units from each endpoint, and
  # the result is `[from_projected, to_projected)` — so
  # `select(workdays, ~o"T09/T17")` is each day's eight open hours,
  # not a granule at 09:00. A window whose `to` is at or before its
  # `from` (`~o"T21/T05"`, a night shift) rolls the end forward to the
  # following day. The duration form (`~o"T09/PT7H36M"`) adds the
  # duration to the projected start. Recurring or open selectors fall
  # back to point projection of the from-endpoint.
  defp project_onto_base(%Interval{} = base, %Interval{from: %Tempo{} = c_from} = constraint) do
    case span_endpoint(constraint) do
      {:to, %Tempo{} = c_to} -> project_span(base, c_from, c_to)
      {:duration, %Duration{} = duration} -> project_span_duration(base, c_from, duration)
      :point -> project_onto_base(base, c_from)
    end
  end

  defp span_endpoint(%Interval{recurrence: recurrence}) when recurrence != 1, do: :point
  defp span_endpoint(%Interval{to: %Tempo{} = to}), do: {:to, to}

  defp span_endpoint(%Interval{to: nil, duration: %Duration{} = duration}),
    do: {:duration, duration}

  defp span_endpoint(%Interval{}), do: :point

  defp project_span(%Interval{} = base, %Tempo{} = c_from, %Tempo{} = c_to) do
    from_anchor = merged_constraint_tempo(base, c_from.time)
    to_anchor = merged_constraint_tempo(base, c_to.time)
    build_span(from_anchor, roll_past_midnight(from_anchor, to_anchor))
  end

  defp project_span_duration(%Interval{} = base, %Tempo{} = c_from, %Duration{} = duration) do
    with %Tempo{} = from_anchor <- merged_constraint_tempo(base, c_from.time),
         %Tempo{} = to_anchor <- Math.add(from_anchor, duration) do
      build_span(from_anchor, to_anchor)
    else
      _other -> nil
    end
  end

  # Both endpoints merge onto the same base member, so a window whose
  # `to` does not land after its `from` crossed midnight — its end
  # belongs to the following day. `:same` rolls too: "21:00 to 21:00"
  # reads as a full day, and a zero-extent interval is not a value.
  defp roll_past_midnight(%Tempo{} = from_anchor, %Tempo{} = to_anchor) do
    if Compare.compare_endpoints(to_anchor, from_anchor) == :later do
      to_anchor
    else
      Math.add(to_anchor, Duration.build(day: 1))
    end
  end

  defp build_span(%Tempo{} = from_anchor, %Tempo{} = to_anchor) do
    case Interval.new(from: from_anchor, to: to_anchor) do
      {:ok, %Interval{} = interval} -> interval
      _other -> nil
    end
  end

  # Merge a constraint's time units onto the base's walk-ready lower
  # bound: a materialised base carries its iteration granularity on
  # `:unit` with bounds at the value's own resolution, and merging
  # `day: 10` into an unfilled `[year: 2026]` would produce an
  # ordinal-shaped list no calendar math accepts. Fill to the unit
  # first (`[year: 2026, month: 1]`), exactly the anchor the walk
  # itself starts from.
  defp merged_constraint_tempo(
         %Interval{from: %Tempo{calendar: calendar} = base_from} = base,
         c_time
       ) do
    %Tempo{} = base_from = Steps.fill_to_unit(base_from, base.unit, calendar)
    base_time = base_from.time
    base_res = Interval.resolution(base)

    merged_time =
      base_time
      |> prune_off_axis_defaults(c_time, base_res)
      |> merge_with_constraint(c_time)
      |> propagate_last_for_negatives(c_time, base_res)
      |> trim_finer_than_constraint(c_time)
      |> reorder_coarse_to_fine()
      |> resolve_negatives(calendar)

    validated_projection(%Tempo{base_from | time: merged_time})
  end

  defp project_merge(%Interval{} = base, c_time) do
    with %Tempo{} = merged <- merged_constraint_tempo(base, c_time) do
      materialise_projection(merged, base, c_time)
    end
  end

  # The merge builds its `%Tempo{}` field-by-field rather than through the
  # parser, so nothing has checked that the result is a date that exists.
  # Selecting `~o"2M29D"` across `~o"{2026..2029}Y"` merges a 29 February
  # onto every year, and only 2028 has one — the other three materialised
  # into phantom spans.
  #
  # A member the constraint cannot land on is skipped, not an error: that
  # is what selecting across a range means, and it matches RFC 5545 §3.3.10
  # ("invalid dates are ignored") for the same rule expressed as a
  # recurrence. `Tempo.anchor/2`, which projects onto exactly one year,
  # still reports the impossible case rather than silently yielding
  # nothing.
  defp validated_projection(%Tempo{calendar: calendar} = merged) do
    case Validation.validate(merged, calendar) do
      {:ok, %Tempo{} = validated} -> validated
      {:error, %InvalidDateError{}} -> nil
      {:error, _other} -> merged
    end
  end

  defp materialise_projection(merged, base, c_time) do
    case Tempo.to_interval(merged) do
      {:ok, %Interval{} = iv} ->
        intersect_with_base(trim_iv_to_constraint(iv, c_time), base)

      {:ok, %IntervalSet{} = set} ->
        set
        |> IntervalSet.to_list()
        |> Enum.map(&intersect_with_base(trim_iv_to_constraint(&1, c_time), base))

      _ ->
        nil
    end
  end

  # ISO 8601 defines three calendar-date axes plus one time-of-day
  # axis. A constraint selects the axis it's on via its units —
  # `:week` puts us on the ISO-week axis; `:day_of_year` puts us on
  # the ordinal axis; everything else is Gregorian.
  @gregorian_axis [:year, :month, :day, :hour, :minute, :second]
  @week_axis [:year, :week, :day_of_week, :hour, :minute, :second]
  @ordinal_axis [:year, :day_of_year, :hour, :minute, :second]

  defp axis_for_constraint(c_time) do
    cond do
      Keyword.has_key?(c_time, :week) or Keyword.has_key?(c_time, :day_of_week) ->
        @week_axis

      Keyword.has_key?(c_time, :day_of_year) ->
        @ordinal_axis

      true ->
        @gregorian_axis
    end
  end

  # Drop units from `base_time` that are NOT on the constraint's
  # axis AND are finer than the base's declared resolution (i.e.
  # they were filled in by materialisation, not specified by the
  # user). This stops defaults like `month: 1` leaking into a
  # week-of-year selection and producing nonsense AST like
  # `[year, month, week]` — which Tempo's materialiser cannot
  # resolve coherently.
  #
  # User-specified units (at or coarser than base's resolution) are
  # always kept, even off-axis — on a month base, a week selector
  # should honour the base's month context, yielding Tempo's
  # non-standard "week-of-month" materialisation.
  defp prune_off_axis_defaults(base_time, c_time, base_resolution) do
    base_res_idx = unit_index(base_resolution) || -1
    axis = axis_for_constraint(c_time)

    Enum.filter(base_time, fn {unit, _} ->
      case unit_index(unit) do
        nil ->
          true

        idx when idx <= base_res_idx ->
          true

        _ ->
          unit in axis
      end
    end)
  end

  # Merge base + constraint into a single keyword list. Constraint
  # values override base values; constraint-only units are appended.
  # Final ordering is fixed up by `reorder_coarse_to_fine/1` after
  # all transformations — individual steps don't need to maintain it.
  defp merge_with_constraint(base_time, c_time) do
    base_time
    |> Enum.map(fn {unit, value} -> {unit, Keyword.get(c_time, unit, value)} end)
    |> Kernel.++(Enum.reject(c_time, fn {unit, _} -> Keyword.has_key?(base_time, unit) end))
  end

  # The natural ancestors of a time-scale unit on its ISO 8601 axis.
  # Used by `propagate_last_for_negatives/2` to identify which
  # intermediate units need "last" propagation.
  #
  #   * Gregorian axis: year → month → day → hour → minute → second
  #   * Week axis:      year → week → day_of_week
  #   * Ordinal axis:   year → day_of_year
  defp axis_ancestors(:month), do: [:year]
  defp axis_ancestors(:day), do: [:year, :month]
  defp axis_ancestors(:week), do: [:year]
  defp axis_ancestors(:day_of_week), do: [:year, :week]
  defp axis_ancestors(:day_of_year), do: [:year]
  defp axis_ancestors(:hour), do: [:year, :month, :day]
  defp axis_ancestors(:minute), do: [:year, :month, :day, :hour]
  defp axis_ancestors(:second), do: [:year, :month, :day, :hour, :minute]
  defp axis_ancestors(_), do: []

  # ISO 8601-2 §4.4.1 negative values count from the end. When the
  # constraint specifies a negative value at its finest unit (e.g.
  # `~o"-1D"` on a year base), any intermediate coarser units on
  # the constraint's axis that came from the base's start-of-span
  # materialisation should also mean "last" — otherwise `-1D` on
  # `~o"2026"` would resolve to "last day of January" (base's first
  # month) rather than "last day of year". The propagation rewrites
  # those intermediates as `-1` sentinels so the subsequent
  # resolve-negatives pass picks up their correct end-of-span value.
  #
  # `:year` is never propagated — a negative `:year` means BC, not
  # "last year", per ISO 8601-2's expanded-year form.
  #
  # Units that are user-specified by the base (at or coarser than
  # `base_resolution`) are also never propagated — on a month base,
  # a `~o"-1D"` selector should resolve to "last day of the user's
  # month", not "last day of December".
  defp propagate_last_for_negatives(merged, c_time, base_resolution) do
    if has_negative?(c_time) do
      finest = finest_unit(c_time)
      base_res_idx = unit_index(base_resolution) || -1

      intermediates =
        finest
        |> axis_ancestors()
        |> Enum.reject(&(&1 == :year))
        |> Enum.filter(fn unit ->
          idx = unit_index(unit)
          not_user_specified? = is_nil(idx) or idx > base_res_idx

          not_user_specified? and
            Keyword.has_key?(merged, unit) and
            not Keyword.has_key?(c_time, unit)
        end)

      Enum.reduce(intermediates, merged, fn unit, acc ->
        Keyword.replace!(acc, unit, -1)
      end)
    else
      merged
    end
  end

  defp has_negative?(time) do
    Enum.any?(time, fn
      {_unit, value} when is_integer(value) -> value < 0
      _ -> false
    end)
  end

  defp unit_index(unit) do
    Enum.find_index(@unit_order_coarse_to_fine, &(&1 == unit))
  end

  # Put units in canonical coarse-to-fine order. `merge_with_constraint/2`
  # can append constraint-only units at the end; if such a unit is
  # coarser than an earlier unit, materialisation would see them out
  # of order. Sort by `@unit_order_coarse_to_fine` rank.
  defp reorder_coarse_to_fine(time) do
    time
    |> Enum.sort_by(fn {unit, _} -> unit_index(unit) || 9_999 end)
  end

  # Resolve any negative component values to their positive equivalent,
  # counting from the end as specified by ISO 8601-2 §4.4.1:
  #
  #   * `month: -1` → `months_in_year(year)` (12 for Gregorian).
  #
  #   * `day: -N` → when `:month` is present, count from end of that
  #     month; otherwise count from end of year.
  #
  #   * `week: -N` → count from end of year's weeks.
  #
  #   * `day_of_year: -N` → count from end of year's days.
  #
  #   * `day_of_week: -N` → count from end of week's days.
  #
  # Negative years are NOT resolved — they remain as BC/negative year
  # designators per ISO 8601-2.
  defp resolve_negatives(time, calendar) do
    time
    |> Enum.reduce({[], []}, fn {unit, value}, {acc, ctx} ->
      resolved = resolve_negative_unit(unit, value, ctx, calendar)
      entry = {unit, resolved}
      {[entry | acc], ctx ++ [entry]}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp resolve_negative_unit(_unit, value, _ctx, _cal) when not is_integer(value),
    do: value

  defp resolve_negative_unit(_unit, value, _ctx, _cal) when value >= 0,
    do: value

  # Years keep their negative sign (BC designator).
  defp resolve_negative_unit(:year, value, _ctx, _cal), do: value

  defp resolve_negative_unit(:month, value, ctx, cal) do
    year = Keyword.fetch!(ctx, :year)
    cal.months_in_year(year) + 1 + value
  end

  defp resolve_negative_unit(:day, value, ctx, cal) do
    year = Keyword.fetch!(ctx, :year)

    case Keyword.get(ctx, :month) do
      nil -> cal.days_in_year(year) + 1 + value
      month when is_integer(month) -> cal.days_in_month(year, month) + 1 + value
      _ -> value
    end
  end

  defp resolve_negative_unit(:week, value, ctx, cal) do
    year = Keyword.fetch!(ctx, :year)

    weeks =
      case Keyword.get(ctx, :month) do
        month when is_integer(month) ->
          # Week-of-month is non-standard — approximate as the number
          # of whole or partial weeks that fit in the month. Keeps
          # `~o"-1W"` on a month base giving a sensible "last week of
          # month" (4 or 5 for Gregorian) rather than resolving to the
          # year's week 52/53, which would fall outside the base.
          days = cal.days_in_month(year, month)
          div(days + 6, 7)

        _ ->
          {w, _} = cal.weeks_in_year(year)
          w
      end

    weeks + 1 + value
  end

  defp resolve_negative_unit(:day_of_year, value, ctx, cal) do
    year = Keyword.fetch!(ctx, :year)
    cal.days_in_year(year) + 1 + value
  end

  defp resolve_negative_unit(:day_of_week, value, _ctx, cal) do
    cal.days_in_week() + 1 + value
  end

  defp resolve_negative_unit(_unit, value, _ctx, _cal), do: value

  # After materialisation, `Tempo.to_interval/1` may pad the
  # endpoints with `hour: 0` (the natural start-of-day representation
  # of a day-resolution span). For selector results we want the
  # endpoint time to match the constraint's resolution exactly —
  # a `~o"12-25"` projection should read as day-shaped, not
  # hour-shaped. Trim both endpoints to the constraint's finest
  # unit.
  defp trim_iv_to_constraint(%Interval{from: %Tempo{} = from, to: %Tempo{} = to} = iv, c_time) do
    %{
      iv
      | from: %{from | time: trim_finer_than_constraint(from.time, c_time)},
        to: %{to | time: trim_finer_than_constraint(to.time, c_time)}
    }
  end

  defp trim_iv_to_constraint(iv, _c_time), do: iv

  # The projection's natural resolution is the finest unit the
  # CONSTRAINT specifies — `~o"12-25"` means "a day" (finest unit
  # :day), `~o"12-25T14:30"` means "a minute". Anything finer
  # carried through from the base's materialisation is dropped
  # so the result is shaped at the constraint's resolution.
  #
  # Uses `filter` (not `take_while`) because the merged keyword list
  # may have constraint-only units appended out of coarse-to-fine
  # order — e.g. merging `~o"1W"` onto a day-resolution base gives
  # `[year, month, day, week]`, and a take_while stops at `:day`
  # before reaching `:week`.
  defp trim_finer_than_constraint(time, c_time) do
    case finest_unit(c_time) do
      nil -> time
      finest -> Enum.filter(time, fn {unit, _} -> not finer_than?(unit, finest) end)
    end
  end

  defp finest_unit(time) do
    time
    |> Keyword.keys()
    |> Enum.reverse()
    |> Enum.find(&(&1 in @unit_order_coarse_to_fine))
  end

  defp finer_than?(a, b) do
    i_a = Enum.find_index(@unit_order_coarse_to_fine, &(&1 == a))
    i_b = Enum.find_index(@unit_order_coarse_to_fine, &(&1 == b))
    not is_nil(i_a) and not is_nil(i_b) and i_a > i_b
  end

  # A constraint is "day-of-week-only" when its :time keyword list
  # has a `:day_of_week` entry (scalar integer or list) and no
  # date-axis key (`:year`, `:month`, `:day`, `:week`).
  defp day_of_week_only(c_time) do
    case Keyword.get(c_time, :day_of_week) do
      nil ->
        :no

      dow ->
        if Enum.any?([:year, :month, :day, :week], &Keyword.has_key?(c_time, &1)) do
          :no
        else
          {:ok, List.wrap(dow)}
        end
    end
  end

  defp intersect_with_base(%Interval{from: %Tempo{} = from} = iv, %Interval{
         from: %Tempo{} = bf,
         to: %Tempo{} = bt
       }) do
    case Compare.compare_endpoints(from, bf) do
      :earlier ->
        nil

      _ ->
        case Compare.compare_endpoints(from, bt) do
          r when r in [:earlier, :same] -> iv
          _ -> nil
        end
    end
  end

  defp intersect_with_base(_, _), do: nil

  ## ---------------------------------------------------------
  ## Grouped-endpoint resolution
  ## ---------------------------------------------------------

  # Some AST shapes — notably the ISO 8601-2 quarter designator
  # (`~o"2026Y3Q"`) — materialise into an Interval whose `:from`
  # endpoint still carries a `{:group, range}` value for one of
  # its time units. Downstream selectors (`filter_by_weekdays`,
  # integer-index selection) expect concrete integer units.
  #
  # When we find a group on `from`, resolve both endpoints from
  # the group's range:
  #
  #   * `from`  gets the group's FIRST element (the concrete start).
  #   * `to`    is rebuilt from `from`'s time with the grouped unit
  #             replaced by `group.last + 1` — the exclusive
  #             upper bound under the half-open convention.
  #
  # This replaces whatever `to` value `to_interval/1` previously
  # produced for the quarter case, which advances past the span
  # (a known quirk for the quarter designator). For other AST
  # shapes — seasons, range-in-slot, masks — `to_interval/1`
  # already produces concrete endpoints and `from` has no group,
  # so this helper is a no-op.
  defp resolve_grouped_endpoints(%Interval{from: %Tempo{time: from_time} = from, to: to} = iv) do
    case find_group(from_time) do
      {unit, %Range{first: first, last: last}} ->
        resolved_from = %{from | time: Keyword.replace(from_time, unit, first)}
        resolved_to_time = Keyword.replace(from_time, unit, last + 1)
        resolved_to = %{from | time: resolved_to_time}
        %{iv | from: resolved_from, to: merge_to_calendar(resolved_to, to)}

      nil ->
        iv
    end
  end

  defp resolve_grouped_endpoints(other), do: other

  defp find_group(time) do
    Enum.find_value(time, fn
      {unit, {:group, range}} -> {unit, range}
      _ -> nil
    end)
  end

  # Preserve calendar/extended/shift from the original `to`
  # endpoint where available; only the :time list is rebuilt.
  defp merge_to_calendar(%Tempo{} = new_to, %Tempo{} = old_to) do
    %{new_to | calendar: old_to.calendar, extended: old_to.extended, shift: old_to.shift}
  end

  defp merge_to_calendar(new_to, _), do: new_to
end
