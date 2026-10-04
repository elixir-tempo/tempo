defmodule Tempo.Select do
  @moduledoc """
  Narrow a Tempo span by a selector — the composition primitive
  for "workdays of June", "the 15th of every month", "every
  Dec 25 in the next decade", and user-supplied holidays.

  ```elixir
  Tempo.select(~o"2026-06", Tempo.workdays(:US))  # workdays of June — locale-aware
  Tempo.select(~o"2026-06", Tempo.weekends(:US))  # weekend days of June
  Tempo.select(~o"2026-06-15/..", Tempo.weekends(:US))  # weekend days from the 15th on, lazily
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
  Locale-dependent constraints like "workdays" or "weekends" are
  constructed by `Tempo.workdays/1` and `Tempo.weekends/1` (which
  read the locale once at construction time) and composed in:

      interval
      |> Tempo.select(Tempo.workdays(:US))

  That means the `workdays(:US)` call is where territory
  resolution happens — **not** inside `select/2` — and the
  resulting value is safe to capture anywhere, including
  module attributes. A territory that cannot be resolved gives an
  `{:error, reason}` selector, which `select/2` returns as it is.

  ## Selector shapes

  | Shape | Example | Meaning |
  | ----- | ------- | ------- |
  | `[integer]` / `Range` | `Tempo.select(m, [1, 15])` | Integer indices applied at base's next-finer unit |
  | `%Tempo{}` or list | `Tempo.select(y, ~o"12-25")` | Project the constraint's specified units onto the base |
  | `%Tempo{day_of_week: …}` | `Tempo.select(m, ~o"5K")` | Day-of-week pattern — every matching weekday in the base (ISO 8601-2 `K` suffix) |
  | `%Tempo{day_of_week: [...]}` | `Tempo.select(m, Tempo.workdays(:US))` | Day-of-week list — every matching weekday in the base |
  | `t:Tempo.Workdays.t/0` | `Tempo.select(m, Tempo.workdays(:AU, except: holidays))` | The workdays no holiday falls on |
  | ISO 8601-2 selection | `Tempo.select(y, ~o"L(easter)eN")` | A computed event, a §12.10 window or any `L…N`, applied in each period at the period's own cadence; units before it narrow the period first (`~o"4ML1K1IN"`) |
  | `%Tempo{day_of_year: N}` (ordinal) | `Tempo.select(y, ~o"10O")` | Ordinal day in the year — the Nth day (ISO 8601-2 `O` suffix) |
  | Negative components | `Tempo.select(y, ~o"-1M")` | ISO 8601-2 §4.4.1 — count from the end of the containing unit |
  | `%Tempo.Interval{}` or list | `Tempo.select(days, ~o"T09/T17")` | Project as a **span** — coarser units from the base, finer from each endpoint, half-open `[from, to)` |
  | Interval duration form | `Tempo.select(days, ~o"T09/PT7H36M")` | Span from the projected start plus the duration |
  | Function | `Tempo.select(y, &fn/1)` | The function returns any of the above; evaluated against each period of the base |

  Base can be a `t:Tempo.t/0`, `t:Tempo.Interval.t/0`, or
  `t:Tempo.IntervalSet.t/0`. IntervalSet bases flat-map the
  selector across each member and collect the results; a lazy
  set's members are selected as the walk reaches them.

  ## Spans — period by period

  A span is selected one period at a time, at the resolution of its
  start: `~o"2026/2029"` is the years 2026, 2027 and 2028, so it holds
  three Christmases, and `~o"2026-06/2026-09"` holds three 15ths. Each
  selection starts in the period it was selected from, so nothing is
  selected twice or outside the span. A day-of-week selector keeps the
  matching days of the whole span.

  An open-ended span gives a lazy set, selected period by period as it
  is walked:

  ```elixir
  {:ok, weekends}    = Tempo.select(~o"2026-06-15/..", Tempo.weekends(:AU))
  {:ok, christmases} = Tempo.select(~o"2026/..", ~o"12-25")
  ```

  > *"The weekend days from the 15th of June on. Every Christmas from this year on."*

  Take the members you need from `Tempo.IntervalSet.walk/1`, or pass
  the set to `Tempo.shift/3` as a `:skipping` busy set. The walk ends
  once it passes the last year a selector names, or a thousand years
  with nothing selected. A span with an open start has no first period
  to walk from, so it returns a `Tempo.IntervalEndpointsError`.

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
  converts them.

  `~o"-1M"` is always "last month" (never "last minute") — use
  the `T` time designator (`~o"T-1M"`) to select minute-of-hour.

  Negative `:year` values are preserved (BC designator per ISO
  8601-2 expanded year form) — they're not flipped to "last
  year" because a time line has no "end" to count from.

  A negative integer index counts from the end in the same way:
  `Tempo.select(~o"2026", [-1])` is December. An index the period
  does not have, such as `[30]` on February, selects nothing there.

  ## A calendar of weeks

  A base in a calendar of weeks, such as `Calendrical.ISOWeek`, is
  selected in by week and day of the week (`~o"25W"`, `~o"2K"`) and by
  time of day. Its year is the calendar's own, not the Gregorian year a
  month and a day belong to, so a selector naming a month, a day of one
  or a day of the year returns a `Tempo.ConversionError`.

  """

  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Interval
  alias Tempo.Interval.Steps
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError
  alias Tempo.Iso8601.Unit
  alias Tempo.Math
  alias Tempo.UnboundedSetError
  alias Tempo.UnitValues
  alias Tempo.Validation

  @type selector ::
          [integer()]
          | Range.t()
          | Tempo.t()
          | Interval.t()
          | Tempo.Workdays.t()
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

  `base` can be any Tempo value that converts to an Interval
  or IntervalSet. Grouped and masked forms have their endpoints
  resolved to concrete values before the selector runs, so every
  ISO 8601-2 shape composes with every selector:

  | Base shape | Example | Converts to |
  |---|---|---|
  | Scalar `%Tempo{}` | `~o"2026-06"` | single Interval |
  | Explicit Interval | `~o"2026-07/2026-10"` | single Interval |
  | IntervalSet | output of `Tempo.union/2` etc. | IntervalSet (flat-mapped) |
  | Quarter (`NQ`) | `~o"2026Y3Q"` | single Interval (group resolved) |
  | Season (codes 25–32) | `~o"2026Y26M"` | Interval bounded by equinox/solstice |
  | Month/day range in a slot | `~o"2026Y{6..8}M"` | IntervalSet of three members |
  | Stepped range | `~o"2026Y{1..-1//3}M"` | IntervalSet of disjoint members |
  | Set of intervals | `~o"{2026-01-05/2026-01-12,2026-02-02/2026-02-09}"` | IntervalSet (flat-mapped) |
  | Archaeological mask | `~o"156X"` | decade-long Interval |
  | Open-ended span | `~o"2026-06-15/.."` | lazy IntervalSet, selected as it is walked |
  | Duration form or recurrence | `~o"2026-06-15/P14D"` | the span or occurrences it converts to |

  A span is selected period by period at its start's resolution, so
  the quarter `~o"2026Y3Q"` selects in July, August and September.

  What is selected keeps the metadata of what it is selected from:
  each school day of a term tagged `%{term: 3}` is tagged `%{term: 3}`
  too, and a set's own metadata stays with the set.

  Example with a quarter base:

      Tempo.select(~o"2026Y3Q", Tempo.workdays(:US))
      #=> {:ok, IntervalSet with 66 members — workdays of Q3 2026}

  ### Examples

      iex> {:ok, set} = Tempo.Select.select(~o"2026-02", [1, 15])
      iex> Enum.map(Tempo.IntervalSet.members(set), &Tempo.day(Tempo.Interval.from(&1)))
      [1, 15]

      iex> {:ok, set} = Tempo.Select.select(~o"2026", ~o"12-25")
      iex> [xmas] = Tempo.IntervalSet.members(set)
      iex> xmas.from.time
      [year: 2026, month: 12, day: 25]

      iex> {:ok, set} = Tempo.Select.select(~o"2026", ~o"10O")
      iex> [day10] = Tempo.IntervalSet.members(set)
      iex> from = Tempo.Interval.from(day10)
      iex> {Tempo.month(from), Tempo.day(from)}
      {1, 10}

      iex> {:ok, set} = Tempo.Select.select(~o"2026-06", ~o"5K")
      iex> set |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [5, 12, 19, 26]

      iex> {:ok, set} = Tempo.Select.select(~o"2026-02", Tempo.workdays(:US))
      iex> Tempo.IntervalSet.count(set)
      20

      iex> {:ok, set} = Tempo.Select.select(~o"2026/2029", ~o"12-25")
      iex> set |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.year(Tempo.Interval.from(&1)))
      [2026, 2027, 2028]

      iex> {:ok, weekends} = Tempo.Select.select(~o"2026-06-15/..", Tempo.weekends(:US))
      iex> weekends |> Tempo.IntervalSet.walk() |> Enum.take(2) |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [20, 21]

  """
  @spec select(base(), selector() | {:error, term()}) ::
          {:ok, IntervalSet.t()} | {:error, term()}

  # ---- A selector that is an error: returned as it is ----
  #
  # `Tempo.workdays/1` and `Tempo.weekends/1` return an error for a
  # territory they cannot resolve, so a pipeline reports that error.

  def select(_base, {:error, _reason} = error), do: error

  def select(base, %Range{} = range), do: select(base, Enum.to_list(range))

  # ---- IntervalSet base: select within each member ----

  def select(%IntervalSet{} = set, selector) do
    set
    |> select_members(selector)
    |> with_set_metadata(IntervalSet.metadata(set))
  end

  # ---- Workdays less holidays: the weekdays, then those no holiday
  # falls on ----

  def select(base, %Tempo.Workdays{weekdays: weekdays, except: except}) do
    with {:ok, %IntervalSet{} = days} <- select(base, day_of_week_selector(weekdays)) do
      if IntervalSet.bounded?(days),
        do: without_holidays(days, except, base),
        else: lazily_without_holidays(days, except)
    end
  end

  # ---- Tempo and Tempo.Set bases: select across the span they
  # convert to ----

  def select(%Tempo{} = tempo, selector), do: select_converted(tempo, selector)
  def select(%Tempo.Set{} = set, selector), do: select_converted(set, selector)

  # ---- Interval base: select period by period ----

  def select(%Interval{metadata: metadata} = interval, selector) do
    interval
    |> select_span(selector)
    |> with_base_metadata(metadata)
  end

  # ---- Catch-all: clearer error ----

  def select(base, _selector) do
    {:error,
     ArgumentError.exception(
       "Tempo.select/2 cannot select from #{inspect(base)}: the base is a Tempo value, " <>
         "an interval or an interval set."
     )}
  end

  defp select_members(set, selector) do
    if IntervalSet.bounded?(set) do
      set
      |> IntervalSet.members()
      |> collect(&member_selection(&1, selector))
      |> selection_set()
    else
      set
      |> IntervalSet.walk()
      |> Stream.map(&{:ok, &1})
      |> select_lazily(selector, &member_selection/2)
    end
  end

  defp select_span(interval, selector) do
    case span(interval) do
      {:closed, span} -> select_closed(span, selector)
      {:open_end, span} -> select_open_end(span, selector)
      {:set, set} -> select(set, selector)
      {:error, _reason} = error -> error
    end
  end

  # What is selected from a base keeps the base's metadata — the school days
  # of a term are tagged with the term — and a selected member's own
  # metadata wins where the two share a key.
  defp with_base_metadata(selected, metadata) when map_size(metadata) == 0, do: selected

  defp with_base_metadata({:ok, %IntervalSet{} = set}, metadata) do
    tagged = &%{&1 | metadata: Map.merge(metadata, &1.metadata)}

    if IntervalSet.bounded?(set) do
      set
      |> IntervalSet.members()
      |> Enum.map(tagged)
      |> IntervalSet.new(coalesce: false, metadata: IntervalSet.metadata(set))
    else
      {:ok,
       set
       |> IntervalSet.walk()
       |> Stream.map(tagged)
       |> IntervalSet.from_stream(metadata: IntervalSet.metadata(set))}
    end
  end

  defp with_base_metadata(error, _metadata), do: error

  # A set's selection keeps the set's own metadata.
  defp with_set_metadata({:ok, %IntervalSet{} = selected}, metadata),
    do: {:ok, %{selected | metadata: metadata}}

  defp with_set_metadata(error, _metadata), do: error

  defp day_of_week_selector(weekdays),
    do: %Tempo{time: [day_of_week: weekdays], calendar: Calendrical.Gregorian}

  # The days no holiday falls on, the holidays converted within the base.
  defp without_holidays(days, except, base) do
    with {:ok, %IntervalSet{} = holidays} <- Tempo.to_interval_set(except, within: base) do
      Tempo.members_outside(days, holidays)
    end
  end

  # An open-ended base's days, each kept when no holiday falls on it, the
  # holidays converted around each day as the walk reaches it.
  defp lazily_without_holidays(days, except) do
    with %Interval{} = first <- IntervalSet.first(days),
         {:ok, _holidays} <- Tempo.to_interval_set(except, within: first) do
      {:ok,
       days
       |> IntervalSet.walk()
       |> Stream.reject(&holiday?(&1, except))
       |> IntervalSet.from_stream()}
    else
      nil -> {:ok, days}
      {:error, _reason} = error -> error
    end
  end

  defp holiday?(day, except) do
    with {:ok, %IntervalSet{} = holidays} <- Tempo.to_interval_set(except, within: day),
         {:ok, %IntervalSet{} = on_the_day} <- Tempo.members_overlapping(holidays, day) do
      IntervalSet.count(on_the_day) > 0
    else
      _no_holidays -> false
    end
  end

  defp select_converted(value, selector) do
    case Tempo.to_interval(value) do
      {:ok, %Interval{} = interval} -> select(resolve_grouped_endpoints(interval), selector)
      {:ok, %IntervalSet{} = set} -> select(set, selector)
      {:error, _reason} = error -> error
    end
  end

  # What a base interval spans: a closed span, one open at its end, or,
  # for a duration-form interval or a recurrence, what
  # `Tempo.to_interval/1` converts it to. A span with an open start has
  # no first period to select from.
  defp span(%Interval{from: :undefined, duration: nil} = interval) do
    {:error,
     IntervalEndpointsError.exception(interval: interval, operation: :select, reason: :open_start)}
  end

  # A closed span is walked from its start to its end, so its ends are held
  # to one order here: two that have none (a start with a year and an end
  # without, or an end that names no moment) are that error.
  defp span(%Interval{from: %Tempo{} = from, to: %Tempo{} = to, recurrence: 1} = interval) do
    with {:ok, _order} <- Compare.order(from, to), do: {:closed, interval}
  end

  defp span(%Interval{from: %Tempo{}, to: :undefined, duration: nil, recurrence: 1} = interval),
    do: {:open_end, interval}

  defp span(%Interval{} = interval) do
    case Tempo.to_interval(interval) do
      {:ok, %Interval{from: %Tempo{}, to: %Tempo{}} = converted} ->
        {:closed, converted}

      {:ok, %IntervalSet{} = set} ->
        {:set, set}

      {:ok, _unconverted} ->
        {:error, IntervalEndpointsError.exception(interval: interval, operation: :select)}

      {:error, _reason} = error ->
        error
    end
  end

  # A closed span's selection. A day-of-week selector keeps the span's
  # matching days; any other applies to each period of the span in turn.
  defp select_closed(_span, []), do: IntervalSet.new([], coalesce: false)

  defp select_closed(span, selector) do
    case weekday_selector(selector) do
      {:ok, weekdays} ->
        span |> weekdays_in(weekdays) |> Enum.to_list() |> IntervalSet.new(coalesce: false)

      :no ->
        span |> periods() |> collect(&period_selection(&1, selector)) |> selection_set()
    end
  end

  # An open-ended span's selection, as a lazy set: a day-of-week
  # selector's days from the span's first day on, or any other selector
  # applied to each period as the walk reaches it.
  defp select_open_end(_span, []), do: IntervalSet.new([], coalesce: false)

  defp select_open_end(span, selector) do
    case weekday_selector(selector) do
      {:ok, weekdays} -> lazy_weekdays(span, weekdays)
      :no -> span |> periods() |> select_lazily(selector, &select_in_period/2)
    end
  end

  # While one day of the week matches, the matching days never run out,
  # so their walk needs no horizon. A selector that matches no day of
  # the week, or a span that starts on no day, selects nothing.
  defp lazy_weekdays(%Interval{from: %Tempo{calendar: calendar} = from} = span, weekdays) do
    with [_ | _] <- weekdays,
         {:ok, _first_day} <- tempo_to_date(from, calendar) do
      {:ok, span |> weekdays_in(weekdays) |> IntervalSet.from_stream()}
    else
      _nothing_to_select -> IntervalSet.new([], coalesce: false)
    end
  end

  # A selector that names only days of the week (`Tempo.workdays/1`,
  # `Tempo.weekends/1`, `~o"5K"`, or a list of them), and the ISO days
  # it names. One that names a time of day too (`~o"1KT10H"`) selects that
  # time on each of the days, period by period.
  defp weekday_selector(%Tempo{time: [day_of_week: _days] = time, calendar: calendar}),
    do: day_of_week_only(time, calendar)

  defp weekday_selector([_ | _] = selectors),
    do: Enum.reduce_while(selectors, {:ok, []}, &add_weekdays/2)

  defp weekday_selector(_selector), do: :no

  defp add_weekdays(
         %Tempo{time: [day_of_week: _days] = time, calendar: calendar},
         {:ok, weekdays}
       ) do
    case day_of_week_only(time, calendar) do
      {:ok, more} -> {:cont, {:ok, weekdays ++ more}}
      :no -> {:halt, :no}
    end
  end

  defp add_weekdays(_selector, _weekdays), do: {:halt, :no}

  # The periods of a span at its start's resolution, as a stream of
  # `{:ok, period}`: the days of `~o"2026-06-15/.."`, the months of
  # `~o"2026-06/2026-09"`. Each period is the span of one value
  # (`Tempo.to_interval/1`), the next begins where it ends, and the
  # last is cut at the span's end. A period that cannot be formed ends
  # the stream with its error.
  defp periods(%Interval{from: from, to: to}) do
    Stream.unfold({:from, from}, &next_period(&1, to))
  end

  defp next_period(:done, _to), do: nil

  defp next_period({:from, start}, to) do
    if starts_before?(start, to), do: period_at(start, to), else: nil
  end

  defp period_at(start, to) do
    case period_of(start) do
      {:ok, %Interval{to: period_end} = period} -> {{:ok, cut(period, to)}, {:from, period_end}}
      {:error, _reason} = error -> {error, :done}
    end
  end

  defp period_of(start) do
    with {:ok, %Interval{to: %Tempo{} = period_end} = period} <- Tempo.to_interval(start),
         {:ok, :later} <- Compare.order(period_end, start) do
      {:ok, period}
    else
      {:error, _reason} = error -> error
      _not_one_span -> {:error, not_one_span(start)}
    end
  end

  defp not_one_span(start) do
    ConversionError.exception(
      value: start,
      target: Interval,
      reason:
        "`Tempo.select/2` walks a span from its start, and #{inspect(start)} is not one span."
    )
  end

  defp starts_before?(_start, :undefined), do: true
  defp starts_before?(start, to), do: Compare.compare_endpoints(start, to) == :earlier

  defp cut(period, :undefined), do: period

  defp cut(%Interval{to: period_end} = period, to) do
    if Compare.compare_endpoints(period_end, to) == :later, do: %{period | to: to}, else: period
  end

  # Each item's selection in turn, concatenated, stopping at the first
  # error.
  defp collect(items, select_one) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, selected} ->
      case select_one.(item) do
        {:ok, more} -> {:cont, {:ok, [more | selected]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> concatenated()
  end

  defp concatenated({:ok, selected}), do: {:ok, selected |> Enum.reverse() |> Enum.concat()}
  defp concatenated({:error, _reason} = error), do: error

  defp selection_set({:ok, selected}), do: IntervalSet.new(selected, coalesce: false)
  defp selection_set({:error, _reason} = error), do: error

  defp period_selection({:ok, period}, selector), do: select_in_period(period, selector)
  defp period_selection({:error, _reason} = error, _selector), do: error

  # The selection in one period: the selector applied to the period,
  # keeping what starts in it, so no two periods select the same span
  # and nothing outside the span is selected.
  defp select_in_period(period, selector) do
    with {:ok, %IntervalSet{} = selected} <- select_period(period, selector) do
      {:ok, selected |> IntervalSet.members() |> Enum.filter(&starts_in?(&1, period))}
    end
  end

  # A selected span with no place in the period's order (a day of no year
  # selected from a time of day) starts nowhere in it.
  defp starts_in?(%Interval{from: %Tempo{} = from}, %Interval{from: period_from, to: period_to}) do
    match?({:ok, order} when order != :earlier, Compare.order(from, period_from)) and
      match?({:ok, :earlier}, Compare.order(from, period_to))
  end

  defp starts_in?(_selected, _period), do: false

  # A member's selection, as a list. A lazy set's members are checked as
  # the walk reaches them, so one that is not a closed span stops it.
  defp member_selection(member, selector) do
    case select(member, selector) do
      {:ok, %IntervalSet{} = selected} -> members_of(selected)
      {:error, _reason} = error -> error
    end
  end

  defp members_of(set) do
    if IntervalSet.bounded?(set) do
      {:ok, IntervalSet.members(set)}
    else
      {:error, UnboundedSetError.exception(operation: "Tempo.select/2", set: set)}
    end
  end

  # How far a lazy selection walks without selecting anything before it
  # ends. A calendar rule repeats within its calendar's cycle — 400
  # years in the Gregorian — so a selector that selects nothing in a
  # thousand years has nothing to select.
  @horizon %Duration{time: [year: 1_000]}

  # A lazy selection: each base in turn (a period of an open-ended
  # span, or a member of a lazy set) selected as the walk reaches it.
  # The first base's error is returned; a later one ends the walk, as
  # does passing the end of the last year the selector names, or a
  # thousand years passing with nothing selected.
  defp select_lazily(bases, selector, select_one) do
    case Enum.take(bases, 1) do
      [] -> IntervalSet.new([], coalesce: false)
      [{:ok, first}] -> lazy_selection(first, bases, selector, select_one)
      [{:error, _reason} = error] -> error
    end
  end

  defp lazy_selection(%Interval{from: from} = first, bases, selector, select_one) do
    with {:ok, found} <- select_one.(first, selector) do
      limits = {horizon_after(Math.add(from, @horizon), found), year_limit(selector, from)}

      later =
        bases
        |> Stream.drop(1)
        |> Stream.transform(limits, &walk_base(&1, &2, selector, select_one))

      {:ok, IntervalSet.from_stream(Stream.concat(found, later))}
    end
  end

  defp walk_base(
         {:ok, %Interval{from: from} = base},
         {horizon, last} = limits,
         selector,
         select_one
       ) do
    if passed?(from, horizon) or passed?(from, last) do
      {:halt, limits}
    else
      base |> select_one.(selector) |> walked(limits)
    end
  end

  defp walk_base(_error, limits, _selector, _select_one), do: {:halt, limits}

  defp walked({:ok, found}, {horizon, last}), do: {found, {horizon_after(horizon, found), last}}
  defp walked({:error, _reason}, limits), do: {:halt, limits}

  # The walk ends a thousand years after the last selection.
  defp horizon_after(horizon, []), do: horizon
  defp horizon_after(_horizon, found), do: found |> List.last() |> horizon_from()

  defp horizon_from(%Interval{from: from}), do: Math.add(from, @horizon)

  defp passed?(_from, :none), do: false

  defp passed?(%Tempo{} = from, %Tempo{} = limit),
    do: Compare.compare_endpoints(from, limit) != :earlier

  # A horizon beyond the calendar's range ends the walk.
  defp passed?(_from, _no_horizon), do: true

  # The start of the year after the last one the selector names, when
  # every constraint in it names a year: nothing is selected after it.
  defp year_limit(selector, %Tempo{} = from) do
    case named_years(selector) do
      [_ | _] = years -> %Tempo{from | time: [year: Enum.max(years) + 1]}
      _no_year -> :none
    end
  end

  defp named_years(%Tempo{time: time}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> [year]
      _no_year -> :none
    end
  end

  defp named_years(%Interval{from: %Tempo{} = from}), do: named_years(from)

  defp named_years([_ | _] = constraints) do
    years = Enum.map(constraints, &named_years/1)
    if :none in years, do: :none, else: Enum.concat(years)
  end

  defp named_years(_selector), do: :none

  # The selection in one period, by the selector's shape.
  defp select_period(period, %Range{} = range), do: select_period(period, Enum.to_list(range))
  defp select_period(_period, []), do: IntervalSet.new([], coalesce: false)

  defp select_period(period, [head | _] = indices) when is_integer(head),
    do: select_indices(period, indices)

  defp select_period(period, %Tempo{time: time} = constraint) do
    case selection_parts(time) do
      :none -> select_projections(period, [constraint])
      {[], selection} -> select_by_rule(period, %{constraint | time: [selection: selection]})
      {units, selection} -> select_narrowed(period, constraint, units, selection)
      :unreadable -> {:error, unrecognised_selector(constraint)}
    end
  end

  defp select_period(period, %Interval{} = constraint),
    do: select_projections(period, [constraint])

  defp select_period(period, [%Tempo{} | _] = constraints) do
    if Enum.any?(constraints, &holds_selection?/1),
      do: constraints |> collect(&selected_members(period, &1)) |> selection_set(),
      else: select_projections(period, constraints)
  end

  defp select_period(period, [%Interval{} | _] = constraints),
    do: select_projections(period, constraints)

  defp select_period(period, fun) when is_function(fun, 1),
    do: select_period(period, fun.(period))

  defp select_period(_period, {:error, _reason} = error), do: error
  defp select_period(_period, selector), do: {:error, unrecognised_selector(selector)}

  # An ISO 8601-2 selection — a computed event, a §12.10 window, any
  # `L…N` — is a recurrence's rule, and what it selects in a period is that
  # recurrence's occurrences there at the period's own cadence: Easter in
  # a year, the first Monday in a month.
  defp select_by_rule(%Interval{from: %Tempo{} = from} = period, rule) do
    {unit, _precision} = Tempo.resolution(from)
    cadence = %Duration{time: [{cadence_unit(unit), 1}]}
    recurrence = %Interval{recurrence: :infinity, duration: cadence, repeat_rule: rule}

    Tempo.to_interval_set(recurrence, within: period)
  end

  defp cadence_unit(unit) when unit in [:day_of_year, :day_of_week], do: :day
  defp cadence_unit(unit), do: unit

  # Units before a selection narrow the period first, and the selection
  # applies within what they select: `4ML1K1IN` is the first Monday of
  # April.
  defp select_narrowed(period, constraint, units, selection) do
    rule = %{constraint | time: [selection: selection]}

    with {:ok, %IntervalSet{} = narrowed} <-
           select_projections(period, [%{constraint | time: units}]) do
      narrowed
      |> IntervalSet.members()
      |> collect(&rule_members(&1, rule))
      |> selection_set()
    end
  end

  defp rule_members(period, rule) do
    with {:ok, %IntervalSet{} = selected} <- select_by_rule(period, rule),
         do: {:ok, IntervalSet.members(selected)}
  end

  defp selected_members(period, selector) do
    with {:ok, %IntervalSet{} = selected} <- select_period(period, selector),
         do: {:ok, IntervalSet.members(selected)}
  end

  # A value's units and its ISO 8601-2 selection: the units before the
  # selection, `:none` without one, and `:unreadable` when units follow it.
  defp selection_parts(time) do
    case Enum.split_while(time, &(not selection_unit?(&1))) do
      {_units, []} -> :none
      {units, [{:selection, selection}]} -> {units, selection}
      {_units, _selection_and_more} -> :unreadable
    end
  end

  defp holds_selection?(%Tempo{time: time}), do: Enum.any?(time, &selection_unit?/1)
  defp holds_selection?(_constraint), do: false

  defp selection_unit?({:selection, _selection}), do: true
  defp selection_unit?(_unit), do: false

  defp unrecognised_selector(selector) do
    ArgumentError.exception(
      "Tempo.select/2 does not recognise selector #{inspect(selector)}. See `Tempo.Select` " <>
        "for the selector vocabulary."
    )
  end

  ## -----------------------------------------------------------
  ## Weekday filter — a day-of-week selector across a span, and a
  ## day-of-week constraint within a period (`project_onto_base/2`)
  ## -----------------------------------------------------------

  # The days of a span whose ISO day of week (Monday = 1) is one of
  # `weekdays`, as a stream of day intervals: the whole days from the
  # day the span starts on up to, not including, the day it ends on,
  # and without end for an open-ended span.
  defp weekdays_in(%Interval{from: %Tempo{calendar: calendar} = from, to: to}, weekdays) do
    from
    |> stream_days(to, calendar)
    |> Stream.filter(fn {year, month, day} -> dow_of(calendar, year, month, day) in weekdays end)
    |> Stream.map(fn {year, month, day} -> day_interval(calendar, year, month, day, from) end)
  end

  # The days from `from` up to, not including, `to` (without end when
  # `to` is `:undefined`), each the day Calendrical gives after the one
  # before.
  defp stream_days(from, to, calendar) do
    with {:ok, start_date} <- tempo_to_date(from, calendar),
         {:ok, end_date} <- end_date(to, calendar) do
      Stream.unfold(start_date, &next_day(&1, end_date))
    else
      _ -> []
    end
  end

  defp end_date(:undefined, _calendar), do: {:ok, :undefined}
  defp end_date(to, calendar), do: tempo_to_date(to, calendar)

  defp next_day(%Date{} = date, :undefined),
    do: {{date.year, date.month, date.day}, Calendrical.next(date, :day)}

  defp next_day(%Date{} = date, end_date) do
    case Compare.compare_days(date, end_date) do
      :lt -> {{date.year, date.month, date.day}, Calendrical.next(date, :day)}
      _on_or_after_the_end -> nil
    end
  end

  # Past the last day the calendar can express.
  defp next_day(_no_date, _end_date), do: nil

  defp tempo_to_date(%Tempo{time: time, calendar: calendar}, calendar) do
    if Keyword.has_key?(time, :week) do
      week_time_to_date(time, calendar)
    else
      month_time_to_date(time, calendar)
    end
  end

  # An endpoint in another calendar than the span's start.
  defp tempo_to_date(_endpoint, _calendar), do: :error

  defp month_time_to_date(time, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month, 1),
         day when is_integer(day) <- Keyword.get(time, :day, 1) do
      Date.new(year, month, day, calendar)
    else
      _ -> :error
    end
  end

  # Week-axis endpoint — `[year, week, day_of_week]`, a date of the
  # ISO 8601 weeks `Tempo.Validation.date_from_iso_week/4` counts,
  # converted into the base calendar. A week-resolution endpoint
  # denotes the start of its week, so a missing `:day_of_week`
  # defaults to 1.
  defp week_time_to_date(time, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         week when is_integer(week) <- Keyword.get(time, :week),
         day when is_integer(day) <- Keyword.get(time, :day_of_week, 1),
         {:ok, week_date} <- Validation.date_from_iso_week(year, week, day, calendar) do
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
    Calendrical.next(date, :day)
  end

  # A day in the units its calendar holds a date in: a month and a day, or a
  # calendar of weeks' week and day of the week.
  defp build_day_tempo(%Tempo{} = source, y, m, d, calendar) do
    %Tempo{source | time: Tempo.date_units(y, m, d, calendar), calendar: calendar}
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

  defp select_indices_at(%Tempo{calendar: calendar} = source, base_time, base_unit, indices) do
    case Unit.implicit_enumerator(base_unit, calendar) do
      nil ->
        {:error,
         ConversionError.exception(
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

  # An index names a component nothing has checked, so one the period
  # does not have (30 February, month 13) selects nothing, as a
  # projection that cannot land does, and a negative index counts from
  # the end (ISO 8601-2 §4.4.1): `-1` on a year is December.
  defp project_index(%Tempo{} = source, base_time, unit, idx) do
    indexed = %Tempo{source | time: base_time ++ [{unit, idx}]}

    with %Tempo{} = valid <- validated_projection(indexed) do
      case Tempo.to_interval(valid) do
        {:ok, %Interval{} = iv} -> iv
        {:ok, %IntervalSet{} = set} -> IntervalSet.first(set)
        _ -> nil
      end
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
  # inherit from base. Then materialise; the walk keeps what starts in
  # the period.
  #
  # A day-of-week-only constraint (`~o"5K"` for "Friday", or
  # `Tempo.workdays(:US)` — `day_of_week: [1, 2, 3, 4, 5]`) is
  # a recurring pattern rather than a specific date, so it routes
  # to the weekday filter instead of the merge-and-materialise
  # path.
  #
  # Units after the weekday (`~o"1KT10H"`, each Monday at 10:00) are merged
  # onto each of the days it selects.
  defp project_onto_base(
         %Interval{from: %Tempo{calendar: calendar}} = base,
         %Tempo{time: c_time}
       ) do
    case day_of_week_only(c_time, calendar) do
      {:ok, weekdays} -> base |> weekdays_in(weekdays) |> on_each_day(after_day_of_week(c_time))
      :no -> project_merge(base, c_time)
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

  defp project_onto_base(_base, constraint), do: {:error, unrecognised_selector(constraint)}

  # The units a constraint names after its weekday, merged onto each day the
  # weekday selects.
  defp after_day_of_week(c_time), do: Keyword.delete(c_time, :day_of_week)

  defp on_each_day(days, []), do: Enum.to_list(days)

  defp on_each_day(days, units) do
    Enum.reduce_while(days, [], fn day, selected ->
      case project_merge(day, units) do
        {:error, _reason} = error -> {:halt, error}
        on_the_day -> {:cont, selected ++ (on_the_day |> List.wrap() |> Enum.reject(&is_nil/1))}
      end
    end)
  end

  defp span_endpoint(%Interval{recurrence: recurrence}) when recurrence != 1, do: :point
  defp span_endpoint(%Interval{to: %Tempo{} = to}), do: {:to, to}

  defp span_endpoint(%Interval{to: nil, duration: %Duration{} = duration}),
    do: {:duration, duration}

  defp span_endpoint(%Interval{}), do: :point

  # A span either end of which cannot land on the member (29 February, in a
  # common year) is skipped, as a point that cannot land is.
  defp project_span(%Interval{} = base, %Tempo{} = c_from, %Tempo{} = c_to) do
    with %Tempo{} = span_from <- merged_constraint_tempo(base, c_from.time),
         %Tempo{} = span_to <- merged_constraint_tempo(base, c_to.time) do
      build_span(span_from, roll_past_midnight(span_from, span_to))
    end
  end

  defp project_span_duration(%Interval{} = base, %Tempo{} = c_from, %Duration{} = duration) do
    with %Tempo{} = span_from <- merged_constraint_tempo(base, c_from.time),
         %Tempo{} = span_to <- Math.add(span_from, duration) do
      build_span(span_from, span_to)
    else
      {:error, %ConversionError{}} = error -> error
      _other -> nil
    end
  end

  # Both endpoints merge onto the same base member, so a window whose
  # `to` does not land after its `from` crossed midnight — its end
  # belongs to the following day. `:same` rolls too: "21:00 to 21:00"
  # reads as a full day, and a zero-extent interval is not a value.
  defp roll_past_midnight(%Tempo{} = span_from, %Tempo{} = span_to) do
    if Compare.compare_endpoints(span_to, span_from) == :later do
      span_to
    else
      Math.add(span_to, Duration.build(day: 1))
    end
  end

  defp build_span(%Tempo{} = span_from, %Tempo{} = span_to) do
    case Interval.new(from: span_from, to: span_to) do
      {:ok, %Interval{} = interval} -> interval
      _other -> nil
    end
  end

  # Merge a constraint's time units onto the base's walk-ready lower
  # bound: a materialised base carries its iteration granularity on
  # `:unit` with bounds at the value's own resolution, and merging
  # `day: 10` into an unfilled `[year: 2026]` would produce an
  # ordinal-shaped list no calendar math accepts. Fill to the unit
  # first (`[year: 2026, month: 1]`), exactly the start the walk
  # itself takes.
  #
  # A calendar of weeks has no months, and its year is not the Gregorian
  # year a month and a day belong to (the NRF year 2026 holds January 2027),
  # so a month, a day of one or a day of the year selects nothing it could be
  # held to: it is an error, as it is in a recurrence's selection.
  defp merged_constraint_tempo(%Interval{from: %Tempo{calendar: calendar}} = base, c_time) do
    if Validation.written_in_another_calendar?(c_time, calendar),
      do: {:error, selects_by_month_error(calendar, c_time)},
      else: merge_constraint(base, c_time)
  end

  defp selects_by_month_error(calendar, c_time) do
    ConversionError.exception(
      value: c_time,
      target: calendar,
      reason:
        "#{inspect(calendar)} is a calendar of weeks, with no months, so a selection in it " <>
          "cannot be by a month, a day of one or a day of the year; select by week (W) " <>
          "and day of the week (K)."
    )
  end

  defp merge_constraint(
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
      materialise_projection(merged, c_time)
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
  # recurrence. `Tempo.on/2`, which places the day on exactly one year,
  # still reports the impossible case rather than silently yielding
  # nothing.
  defp validated_projection(%Tempo{calendar: calendar} = merged) do
    case Validation.validate(merged, calendar) do
      {:ok, %Tempo{} = validated} -> validated
      {:error, %InvalidDateError{}} -> nil
      {:error, _other} -> merged
    end
  end

  defp materialise_projection(merged, c_time) do
    case Tempo.to_interval(merged) do
      {:ok, %Interval{} = iv} ->
        trim_iv_to_constraint(iv, c_time)

      {:ok, %IntervalSet{} = set} ->
        set
        |> IntervalSet.members()
        |> Enum.map(&trim_iv_to_constraint(&1, c_time))

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

  # A unit counted from the end (ISO 8601-2 §4.4.1) is the value
  # `Tempo.UnitValues` counts back to among those the unit takes in the units
  # before it: the months of the year, the days of the month, the weeks and
  # the days of the year, the days of the week, the hours of the day. A day
  # with no month before it is a day of the year, as a value's is. A year is
  # never counted from the end: a negative year is a year before year 1.
  defp resolve_negatives(time, calendar) do
    time
    |> Enum.reduce({[], []}, fn {unit, value}, {resolved, context} ->
      entry = {unit, from_end(unit, value, context, calendar)}
      {[entry | resolved], context ++ [entry]}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp from_end(unit, value, context, calendar)
       when is_integer(value) and value < 0 and unit != :year do
    case unit_values(unit, context, calendar) do
      {:ok, values} -> UnitValues.from_end(value, values)
      {:error, _reason} -> value
    end
  end

  defp from_end(_unit, value, _context, _calendar), do: value

  defp unit_values(:day, context, calendar) do
    if Keyword.has_key?(context, :month),
      do: UnitValues.in_period(:day, context, calendar),
      else: UnitValues.in_period(:day_of_year, context, calendar)
  end

  defp unit_values(:week, context, calendar) do
    case {Keyword.get(context, :year), Keyword.get(context, :month)} do
      {year, month} when is_integer(year) and is_integer(month) ->
        {:ok, 1..weeks_in_month(year, month, calendar)//1}

      _no_month ->
        UnitValues.in_period(:week, context, calendar)
    end
  end

  defp unit_values(unit, context, calendar), do: UnitValues.in_period(unit, context, calendar)

  # Week-of-month is non-standard: the number of whole or partial weeks that
  # fit in the month, so that `~o"-1W"` on a month is its last week (the
  # fourth or the fifth) and not the year's, which lies outside the month.
  # See "Week-of-month selections" in `TODO.md`.
  defp weeks_in_month(year, month, calendar), do: div(calendar.days_in_month(year, month) + 6, 7)

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
  # has a `:day_of_week` entry and no date-axis key (`:year`, `:month`,
  # `:day`, `:week`). The days it names are those `Tempo.UnitValues` reads
  # among the days of the week: a number, a count from the end (`-1`, the
  # last), a range (`{6..-1}`) or several of them.
  defp day_of_week_only(c_time, calendar) do
    case Keyword.get(c_time, :day_of_week) do
      nil ->
        :no

      dow ->
        if Enum.any?([:year, :month, :day, :week], &Keyword.has_key?(c_time, &1)) do
          :no
        else
          {:ok, weekdays_named(dow, calendar)}
        end
    end
  end

  defp weekdays_named(written, calendar) do
    case UnitValues.in_period(:day_of_week, [], Compare.effective_calendar(calendar)) do
      {:ok, days} -> UnitValues.named(written, days)
      {:error, _reason} -> []
    end
  end

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
