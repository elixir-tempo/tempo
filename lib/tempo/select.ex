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

  A constraint is the selection of the same parts: `~o"15D"` selects
  what `~o"L15DN"` does, and one implementation resolves both. A day
  either selects is the day's own value, as `Tempo.to_interval/1` gives
  it, so it is walked by its hours; a month is walked by its days and an
  hour by its minutes. A day selected by its weekday (`~o"1K"`,
  `Tempo.workdays/1`) is that value too, and a weekday selected from an
  hour keeps the hour where its day is that weekday.

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

  A week selected from a year is kept whole. It is a week of that year's
  ISO 8601 week-year, which runs from the Monday of its week 1 and so
  starts up to three days before 1 January, or after it:
  `Tempo.select(~o"2026", ~o"1W")` is the week from 29 December 2025, and
  `~o"1W1K"` that Monday. Each week is one year's, so a span of years
  still selects none twice.

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

  A window whose start names a day of the week is the window on each
  such day: `~o"1KT9H/T17H"` is Monday's nine to five, and
  `~o"{1..5}KT9H/T17H"` the working week's. It starts and ends on the one
  weekday, so an end that names another (`~o"1KT9H/5KT17H"`) is an
  error: select the days, and then the times within them.

  A window written with a duration from a start that holds a set is
  the window from each of its values: `~o"T{9,14}H/PT1H"` is the hour
  from 09:00 and the hour from 14:00. Written with two ends, one of
  which holds a set (`T{9,14}H/T16H`), it names no one span and returns
  a `Tempo.IntervalEndpointsError`: give a window for each value, in a
  list.

  ## Negative components — "last N from the end"

  ISO 8601-2 §4.4.1 allows any integer component to be negative,
  meaning "count from the end of the containing time-scale unit".
  `Tempo.select/2` honours this: the resolution is context-aware
  and produces end-of-span selections without string munging or
  calendar arithmetic at the call site.

  ```elixir
  Tempo.select(~o"2026",    ~o"-1M")   #=> December 2026 (last month of year)
  Tempo.select(~o"2026",    ~o"-1D")   #=> Dec 31 2026 (last day of year)
  Tempo.select(~o"2026",    ~o"-1W")   #=> week 53 of 2026 (last ISO week)
  Tempo.select(~o"2026-06", ~o"-1D")   #=> Jun 30 2026 (last day of month)
  Tempo.select(~o"2026-02", ~o"-1D")   #=> Feb 28 2026 (leap-aware — Feb 29 in 2024)
  Tempo.select(~o"2026-06-15", ~o"-1H") #=> 23:00 (last hour of day)
  Tempo.select(~o"2026-06-15T14", ~o"T-1M") #=> 14:59 (last minute of hour)
  ```

  The resolution is calendar-aware — `Tempo.select(~o"2024-02",
  ~o"-1D")` returns Feb 29 because 2024 is a leap year. `-1W` is
  the last ISO week of a year (the 52nd or the 53rd), `-1M` its
  last month, `-1K` the week's last day and `-1O` the year's last
  day.

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

  A day with no month, selected from a year, is a day of the year, as
  the value `~o"2026Y45D"` is: `Tempo.select(~o"2026", ~o"45D")` is
  14 February and `~o"-45D"` the 45th day from the year's end.

  A value a period does not have is passed over wherever it is written.
  A set or a range keeps the values the period has, so `~o"{1,30}D"`
  selects the 1st from February and `~o"{25..35}D"` the 25th to the 30th
  from June; and a count from the end that reaches past the period's
  start, such as `~o"-45D"` from a month, selects nothing.

  ## A selector on another axis than its base

  A date is written by its month and day, by its week, or by its day of
  the year, and a selector may be written on another of those than the
  base is. What it selects are the spans it names that start in the base:

  ```elixir
  Tempo.select(~o"2026-W25", ~o"15D")    # 15 June, which is in ISO week 25
  Tempo.select(~o"2026-W27", ~o"1D")     # 1 July: the week starts on 29 June
  Tempo.select(~o"2026-06", ~o"166O")    # 15 June, the 166th day of 2026
  Tempo.select(~o"2026-06-15", ~o"100O") # nothing: the 100th day is 10 April
  ```

  A week selected from a year is an ISO 8601 week of the year. A week
  selected from a month is a week of that month, which the calendar
  numbers: in the Gregorian calendar a whole week from a Monday, the
  first of a month the one that holds its first day, so it is not
  always within its month.

  ```elixir
  Tempo.select(~o"2026-06", ~o"2W")      # 8 to 14 June
  Tempo.select(~o"2026-07", ~o"1W")      # 29 June to 5 July
  Tempo.select(~o"2026-06", ~o"-1W")     # 22 to 28 June, its fourth and last
  Tempo.select(~o"2026-06", ~o"2W3K")    # Wednesday 10 June
  Tempo.select(~o"2026-06", ~o"5W")      # nothing: June 2026 has four weeks
  ```

  A day and a time of day are written with their month, so a week
  selected from one is a week of that month too, and keeps it where
  that week holds it. A week beside a month in a selector is the week of
  that month wherever it is selected.

  ```elixir
  Tempo.select(~o"2026-06-10", ~o"2W")   # 10 June: it is in June's second week
  Tempo.select(~o"2026-06-10", ~o"24W")  # nothing: June has no 24th week
  Tempo.select(~o"2026", ~o"L6M2WN")     # 8 to 14 June
  ```

  A week of a month that is a mask is each week its digits match, with
  a day or a time under it as with none: `~o"XW3K"` from June 2026 is
  the Wednesday of each of its four weeks. A week of a month in a
  calendar whose year does not begin with its first month is not built:
  it returns a `Tempo.ConversionError` whose `:reason` is `:not_built`
  and whose `:target` is `:week_of_month`.

  ## An unspecified unit

  An unspecified unit (`X*`) stands for every value the unit takes in
  its period, as a mask of as many digits does, in a constraint and in
  a selection alike.

  ```elixir
  Tempo.select(~o"2026-06", ~o"X*D")     # each of June's thirty days
  Tempo.select(~o"2026", ~o"X*M15D")     # the 15th of each month
  Tempo.select(~o"2026-06-15", ~o"TX*H") # each of the day's hours
  ```

  ## A selector as coarse as its base, or coarser

  A selector's units that are as coarse as the period they are selected
  from, or coarser, are a filter: the period is kept where it starts in
  what they name, as a weekday selector keeps a day.

  ```elixir
  {:ok, days} = Tempo.select(~o"2026-05-25/2026-07-10", Tempo.workdays(:US))
  {:ok, june} = Tempo.select(days, ~o"6M")      # the workdays that are in June
  {:ok, week} = Tempo.select(days, ~o"25W")     # those in ISO week 25
  ```

  > *"The workdays of the span that are in June. Those in week 25."*

  Units finer than the period are placed within the periods the coarser
  ones keep: `~o"6MT10H"` is ten o'clock on each day that is in June.

  ## A calendar of weeks

  A base in a calendar of weeks, such as `Calendrical.ISOWeek`, is
  selected in by week and day of the week (`~o"25W"`, `~o"2K"`) and by
  time of day. Its year is the calendar's own, not the Gregorian year a
  month and a day belong to, so a selector naming a month, a day of one
  or a day of the year returns a `Tempo.ConversionError`.

  A day of the week is a day of the week of the value that holds it: the
  calendar's own week in a calendar of weeks, and ISO 8601's, which starts
  on Monday, in a calendar of months. So a selector is read in the calendar
  it is written in. `~o"3K"`, written in the Gregorian calendar, selects
  Wednesdays from a base in any calendar, as `Tempo.workdays/1` selects
  the weekdays it names; `~o"3K[u-ca=nrf]"`, written in a calendar whose
  weeks start on Sunday, selects Tuesdays.

  ## A selector of another calendar

  A selector is a value of its own calendar. Its year, its month, its day
  of one, its day of the year and its week are numbers of that calendar,
  and are never read in the base's: the sixth month of a Hebrew year is not
  June. So a selector that holds one selects only from a base of its own
  calendar, and from a base of another returns a `Tempo.ConversionError`
  naming both, as `Tempo.at/2` and `Tempo.on/2` do. Write the selector in
  the base's calendar: `Tempo.from_iso8601!("6M15D", Calendrical.Hebrew)`,
  or `~o"6M15D[u-ca=hebrew]"`.

  A time of day and a day of the week select from a base in any calendar,
  and what they select are values of the base's calendar. ISO 8601's weeks
  are the Gregorian calendar's and the ISO week calendar's alike, so a week
  written in either selects from a base in the other.

  """

  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Enumeration
  alias Tempo.Enumeration.Zone
  alias Tempo.Interval
  alias Tempo.Interval.Steps
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError
  alias Tempo.Iso8601.Group
  alias Tempo.Iso8601.Unit
  alias Tempo.Math
  alias Tempo.NotBuilt
  alias Tempo.RRule.Selection
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
  # resolution comparison and merged-keyword-list canonical ordering.
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

  In a named zone, what is selected is what the zone's clock shows of
  it. A time of day the clock skips on some day is not selected on
  that day, nor is a day the zone left out: `~o"T02"` selects nothing
  on the night New York's clocks go from 02:00 to 03:00. A window is
  the part of it the clock shows, so `~o"T02/T04"` is 03:00 to 04:00
  on that night, and one written with a duration (`~o"T02/PT2H"`) runs
  that long from 03:00.

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

      iex> clocks_go_forward = ~o"2024-03-10[America/New_York]"
      iex> {:ok, skipped} = Tempo.Select.select(clocks_go_forward, ~o"T02")
      iex> Tempo.IntervalSet.count(skipped)
      0
      iex> {:ok, quiet_hours} = Tempo.Select.select(clocks_go_forward, ~o"T02/T04")
      iex> Tempo.IntervalSet.members(quiet_hours)
      [~o"2024Y3M10DT3H/T4H[America/New_York]"]

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

  def select(%Tempo{calendar: nil} = tempo, selector),
    do: select(Tempo.with_a_calendar(tempo), selector)

  def select(%Tempo{} = tempo, selector), do: select_converted(tempo, selector)
  def select(%Tempo.Set{} = set, selector), do: select_converted(set, selector)

  # ---- Interval base: select period by period ----

  # An end that is a season of 21 to 24 has no dates as it is written, and
  # the interval is selected from as the span it converts to.
  def select(%Interval{} = interval, selector) do
    if Group.abstract_season?(interval),
      do: select_converted(interval, selector),
      else: select_interval(interval, selector)
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

  # What is selected is what the clock of the base's zone shows of it. A
  # reading the clock skips is no time to select (decided 2026-10-07): 02:00
  # on the night New York's clocks go from 02:00 to 03:00, and Samoa's
  # 30 December 2011, which the 30th of a month and the Fridays of that
  # December would pick. A member that starts on one, an hour, a minute or a
  # day the clock skips the whole of, is not selected, and one that ends on
  # one ends on the reading the clock comes out of the gap on: the day
  # before a day left out ends on the next day the zone has, as the day's
  # own span does. A window is another matter, and is the part of it the
  # clock shows (`shown_span/2`).
  #
  # A member nowhere near a change of the zone's clock is as it was
  # selected, and asks nothing of the zone database
  # (`Tempo.Enumeration.Zone.shown?/1`).
  defp as_the_clock_shows(
         {:ok, %IntervalSet{} = selected},
         %Interval{from: %Tempo{extended: %{zone_id: zone}}}
       )
       when is_binary(zone) and zone != "",
       do: through_members(selected, &as_the_clock_shows/1)

  defp as_the_clock_shows(selected, _base), do: selected

  defp as_the_clock_shows(%Interval{from: %Tempo{} = from} = selected) do
    if Zone.shown?(from),
      do: [selected |> ending_as_the_clock_shows() |> at_the_offsets_of_its_ends()],
      else: []
  end

  defp as_the_clock_shows(selected), do: [selected]

  defp ending_as_the_clock_shows(%Interval{to: %Tempo{} = to} = selected) do
    case Zone.shown_by_the_clock(to) do
      ^to -> selected
      shown -> %{selected | to: shown}
    end
  end

  defp ending_as_the_clock_shows(selected), do: selected

  # A member selected from a base written with an offset is at the offset
  # its zone is at on each of its ends (`Tempo.Enumeration.Zone.at_its_offset/1`):
  # it took the base's, which is another's once the clock has changed.
  defp at_the_offsets_of_its_ends(
         %Interval{from: %Tempo{shift: [_ | _]} = from, to: to} = selected
       ),
       do: %{selected | from: Zone.at_its_offset(from), to: at_its_offset(to)}

  defp at_the_offsets_of_its_ends(selected), do: selected

  defp at_its_offset(%Tempo{} = to), do: Zone.at_its_offset(to)
  defp at_its_offset(open_or_none), do: open_or_none

  # A set's members, each as the members `fun` gives for it, in a set that
  # is walked as the set is: at once where it is bounded, and member by
  # member where it is not.
  defp through_members(set, fun) do
    metadata = IntervalSet.metadata(set)

    if IntervalSet.bounded?(set) do
      members = IntervalSet.members(set)

      # A set none of whose members `fun` changes is the set it was.
      case Enum.flat_map(members, fun) do
        ^members -> {:ok, set}
        changed -> IntervalSet.new(changed, coalesce: false, metadata: metadata)
      end
    else
      {:ok,
       set
       |> IntervalSet.walk()
       |> Stream.flat_map(fun)
       |> IntervalSet.from_stream(metadata: metadata)}
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
       |> Stream.transform(0, &kept_or_passed(&1, &2, except))
       |> IntervalSet.from_stream()}
    else
      nil -> {:ok, days}
      {:error, _reason} = error -> error
    end
  end

  # A day no holiday falls on is kept, and one a holiday falls on is passed.
  # The walk ends where more days in a row are passed than a step to the
  # next workday passes (`Tempo.next_workday/2` is an error there): holidays
  # that hold every day from some day on, as a span with no end does, were
  # walked for ever, and what asked for the next workday was never answered.
  @most_days_off_in_a_row Tempo.Limit.days_off_in_a_row()

  defp kept_or_passed(_day, passed, _except) when passed > @most_days_off_in_a_row,
    do: {:halt, passed}

  defp kept_or_passed(day, passed, except) do
    if holiday?(day, except), do: {[], passed + 1}, else: {[day], 0}
  end

  defp holiday?(day, except) do
    with {:ok, %IntervalSet{} = holidays} <- Tempo.to_interval_set(except, within: day),
         {:ok, %IntervalSet{} = on_the_day} <- Tempo.members_overlapping(holidays, day) do
      IntervalSet.count(on_the_day) > 0
    else
      _no_holidays -> false
    end
  end

  defp select_interval(%Interval{metadata: metadata} = interval, selector) do
    interval
    |> select_span(selector)
    |> as_the_clock_shows(interval)
    |> with_base_metadata(metadata)
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
    case weekdays_of_whole_days(span, selector) do
      {:ok, weekdays} ->
        span |> weekdays_in(weekdays) |> Enum.to_list() |> IntervalSet.new(coalesce: false)

      :no ->
        span |> periods() |> collect(&period_selection(&1, selector)) |> selection_set()
    end
  end

  # A day-of-week selector keeps the days of a span of whole days, each the
  # day's own value. A span written to a time of day is selected period by
  # period, as by any other selector, so a weekday selected from an hour
  # keeps the hour where its day is that weekday (decided 2026-10-08): it
  # selected nothing there, an hour holding no whole day, and from a span of
  # hours that ran into the next day it selected the whole of a day the
  # span starts part way through.
  defp weekdays_of_whole_days(%Interval{from: from, to: to}, selector) do
    if time_of_day?(from) or time_of_day?(to),
      do: :no,
      else: weekday_selector(selector)
  end

  defp time_of_day?(%Tempo{time: time}) when is_list(time),
    do: Enum.any?(time, &(is_tuple(&1) and elem(&1, 0) in [:hour, :minute, :second]))

  defp time_of_day?(_open_or_no_end), do: false

  # An open-ended span's selection, as a lazy set: a day-of-week
  # selector's days from the span's first day on, or any other selector
  # applied to each period as the walk reaches it.
  defp select_open_end(_span, []), do: IntervalSet.new([], coalesce: false)

  defp select_open_end(span, selector) do
    case weekdays_of_whole_days(span, selector) do
      {:ok, weekdays} -> lazy_weekdays(span, weekdays)
      :no -> lazily_by_period(span, selector)
    end
  end

  # A weekday is selected among days, and a span that starts on no day (a
  # time of day with no date, `T10H/..`) has none: it selects nothing, as a
  # span of days that starts on none does (`lazy_weekdays/2`).
  defp lazily_by_period(%Interval{from: %Tempo{calendar: calendar} = from} = span, selector) do
    if weekday_selector(selector) != :no and
         not match?({:ok, _day}, tempo_to_date(from, calendar)),
       do: IntervalSet.new([], coalesce: false),
       else: span |> periods() |> select_lazily(selector, &select_in_period/2)
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
  defp select_in_period(period, selector) when is_function(selector, 1),
    do: select_in_period(period, selector.(period))

  defp select_in_period(period, selector) do
    with {:ok, %IntervalSet{} = selected} <- select_period(period, selector) do
      {:ok, selected |> IntervalSet.members() |> starting_in(period, selector)}
    end
  end

  # What each constraint of a list selects is kept by that constraint's own
  # span, where the list is resolved (`select_period/2`).
  defp starting_in(members, _period, [%Tempo{} | _]), do: members

  defp starting_in(members, period, selector) do
    span = span_selected_in(period, selector)
    Enum.filter(members, &starts_in?(&1, span))
  end

  # The span a selection is kept by starting in: the period, but for a week
  # selected from a year. A week of a year is a week of its ISO 8601
  # week-year (decided 2026-10-05), which runs from the Monday of its week 1
  # to the Monday of the next year's and so starts up to three days before
  # the calendar year or after it: week 1 of 2026 starts on 29 December 2025
  # and is 2026's, as the value `2026YL1WN` has it, and the week that starts
  # on 28 December 2026 is 2026's week 53 and no week of 2027. Each week is
  # the week of one year, so a span of years still selects none twice.
  defp span_selected_in(
         %Interval{from: %Tempo{time: [year: year], calendar: calendar} = from} = period,
         selector
       )
       when is_integer(year) do
    with true <- names_week?(selector),
         false <- Tempo.week_based_calendar?(Compare.effective_calendar(calendar)),
         {:ok, first} <- week_time_to_date([year: year, week: 1], calendar),
         {:ok, next} <- week_time_to_date([year: year + 1, week: 1], calendar) do
      %Interval{
        from: build_day_tempo(from, first.year, first.month, first.day, calendar),
        to: build_day_tempo(from, next.year, next.month, next.day, calendar)
      }
    else
      _the_period -> period
    end
  end

  # A week selected from a month is a week of that month, which the calendar
  # numbers and which is not always within it: the first week of July 2026
  # starts on 29 June. It is kept by starting among the month's weeks, from
  # the first date of the first to the day after the last date of the last,
  # so each week is the week of one month and a span of months selects none
  # twice.
  defp span_selected_in(
         %Interval{from: %Tempo{time: [year: year, month: month], calendar: calendar} = from} =
           period,
         selector
       )
       when is_integer(year) and is_integer(month) do
    with true <- names_week?(selector),
         {:ok, [%Date.Range{first: first} | _weeks] = weeks} <-
           UnitValues.weeks_of_month(year, month, Compare.effective_calendar(calendar)),
         %Date.Range{last: last} <- List.last(weeks),
         %Date{} = next <- Calendrical.next(last, :day) do
      %Interval{
        from: build_day_tempo(from, first.year, first.month, first.day, calendar),
        to: build_day_tempo(from, next.year, next.month, next.day, calendar)
      }
    else
      _the_period -> period
    end
  end

  defp span_selected_in(period, _selector), do: period

  defp names_week?(%Tempo{time: time}) when is_list(time) do
    Enum.any?(time, fn
      {:week, _weeks} -> true
      {:selection, selection} -> List.keymember?(selection, :week, 0)
      _other -> false
    end)
  end

  defp names_week?(_selector), do: false

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

  # A season of 21 to 24 has no dates as it is written, and selects as the
  # span it converts to (`select_projections/2`).
  defp select_period(period, %Tempo{time: [{:year, _year}, {:season, _season}]} = season),
    do: select_projections(period, [season])

  defp select_period(period, %Tempo{time: time} = constraint) do
    with :ok <- one_calendar(period, constraint) do
      case selection_parts(time) do
        :none -> select_constraint(period, constraint)
        {[], selection} -> select_by_rule(period, %{constraint | time: [selection: selection]})
        {units, selection} -> select_narrowed(period, constraint, units, selection)
        :unreadable -> {:error, unrecognised_selector(constraint)}
      end
    end
  end

  defp select_period(period, %Interval{} = constraint) do
    with :ok <- one_calendar(period, constraint),
         do: select_projections(period, [constraint])
  end

  defp select_period(period, [%Tempo{} | _] = constraints) do
    with :ok <- one_calendar(period, constraints),
         do: constraints |> collect(&select_in_period(period, &1)) |> selection_set()
  end

  defp select_period(period, [%Interval{} | _] = constraints) do
    with :ok <- one_calendar(period, constraints),
         do: select_projections(period, constraints)
  end

  defp select_period(period, fun) when is_function(fun, 1),
    do: select_period(period, fun.(period))

  defp select_period(_period, {:error, _reason} = error), do: error
  defp select_period(_period, selector), do: {:error, unrecognised_selector(selector)}

  # The units a rule counts, each with its place from the coarsest: a
  # period or a part of another unit (a fraction of a second, a group's) is
  # none of the resolver's.
  @coarseness %{
    year: 0,
    month: 1,
    week: 2,
    day: 3,
    day_of_year: 3,
    day_of_week: 3,
    hour: 4,
    minute: 5,
    second: 6
  }

  # A constraint is the selection of the same parts, and is resolved as one
  # where the resolver counts them (`resolved_as_a_rule?/2`). Its units that
  # are as coarse as the period or coarser are then a filter (decided
  # 2026-10-05): they keep the period where it starts in what they name, so
  # `~o"6M"` keeps each day that is in June. Units finer than the period
  # name spans within it.
  defp select_constraint(
         %Interval{from: %Tempo{} = from} = period,
         %Tempo{time: time} = constraint
       ) do
    if resolved_as_a_rule?(time, from),
      do: select_by_rule(period, %{constraint | time: [selection: time]}),
      else: select_placed(period, constraint)
  end

  # A constraint whose units are whole numbers, or sets and ranges of them,
  # is the selection of the same parts (`~o"15D"` is `~o"L15DN"`), and the
  # resolver serves both (decided 2026-10-07): one implementation, which the
  # two forms were held to give the same spans of before. What the resolver
  # has no reading for is still placed on its period: a part it cannot count
  # (an unspecified unit, a fraction of a second, a group), and a week of a
  # month with a day or a time of it, which it resolves by the week of the
  # year.
  defp resolved_as_a_rule?(time, %Tempo{} = from) do
    {unit, _precision} = Tempo.resolution(from)

    is_map_key(@coarseness, unit) and Enum.all?(time, &counted_unit?/1) and
      not within_a_week_of_a_month?(time, from)
  end

  defp within_a_week_of_a_month?([_week, _finer | _rest] = time, %Tempo{time: [year: _, month: _]}),
       do: List.keymember?(time, :week, 0)

  defp within_a_week_of_a_month?(_time, _from), do: false

  # A constraint placed on its period: its units are merged onto the
  # period's start, and what they name there is the value read. A week is
  # the one period that runs across a month or a year, so a month and a day
  # of it selected from a week are merged onto each month the week touches
  # (`on_each_period/3`).
  defp select_placed(period, constraint), do: select_projections(period, [constraint])

  # A mask is each value its digits match, as it is in a selection (decided
  # 2026-10-08): `~o"1XD"` from June is its ten days from the 10th. Placed
  # on its period it was the one span the value `2026Y6M1XD` is, and a day
  # it was asked to keep was dropped.
  #
  # An unspecified unit (`~o"X*D"`) is every value the unit takes, as the
  # mask of as many digits is: placed on its period it was the one span the
  # period is, and from a day it selected nothing.
  defp counted_unit?({unit, {:mask, mask}}) when is_list(mask), do: is_map_key(@coarseness, unit)
  defp counted_unit?({unit, :any}), do: is_map_key(@coarseness, unit)
  defp counted_unit?({unit, value}), do: is_map_key(@coarseness, unit) and counted?(value)
  defp counted_unit?(_other), do: false

  # An ISO 8601-2 selection — a computed event, a §12.10 window, any
  # `L…N` — is a recurrence's rule, and what it selects in a period is that
  # recurrence's occurrences there at the period's own cadence: Easter in
  # a year, the first Monday in a month.
  defp select_by_rule(%Interval{from: %Tempo{} = from} = period, rule) do
    {unit, _precision} = Tempo.resolution(from)
    freq = cadence_unit(unit)

    with :ok <- week_of_month_built(rule, unit, from) do
      rule = in_calendar_of(rule, from)

      if Selection.expands?(rule, freq) or week_of_month_rule?(rule, unit),
        do: occurrences_in(period, rule, freq),
        else: kept_or_dropped(period, rule, freq)
    end
  end

  # What a rule that makes points within its period selects there: what the
  # period's own value selects with the rule written after it, so June
  # selected by `L15DN` is `2026Y6ML15DN`. The rule is resolved in the one
  # period, where a recurrence of it, walked within the period, took four
  # times as long to give the same.
  defp occurrences_in(
         %Interval{from: %Tempo{time: time} = from},
         %Tempo{time: [selection: selection]},
         _freq
       ) do
    case selected_in(%{from | time: time ++ [selection: selection]}, selection) do
      {:ok, %IntervalSet{}} = selected -> selected
      {:ok, %Interval{} = selected} -> IntervalSet.new([selected], coalesce: false)
      {:error, _reason} = error -> error
    end
  end

  # A point a rule selects is the value it is, and is walked as
  # `Tempo.to_interval/1` has the value walked: a day by its hours (decided
  # 2026-10-07). A day selected by a constraint or by a selection is then
  # the same value, where one placed on its period was walked by hours and
  # one the resolver gave was walked as the one day. A day selected by its
  # weekday alone is such a value too (decided 2026-10-08), as the days a
  # weekday selector gives are (`day_interval/5`).
  defp selected_in(value, _selection), do: Tempo.selected_in(value)

  # A rule that only keeps or drops its period is asked of the period itself,
  # the candidate the resolver answers for: no recurrence is walked, so a
  # span of many periods costs each of them one question, and the period kept
  # is the period as it is written.
  defp kept_or_dropped(
         %Interval{from: %Tempo{calendar: calendar} = from} = period,
         %Tempo{time: [selection: selection]} = rule,
         freq
       ) do
    with :ok <- filters_in(selection, from, calendar) do
      case Selection.apply(period, read_in_its_period(rule, from), freq) do
        {:error, _reason} = error -> error
        [] -> IntervalSet.new([], coalesce: false)
        [_kept | _] -> IntervalSet.new([period], coalesce: false)
      end
    end
  end

  defp kept_or_dropped(period, rule, freq), do: occurrences_in(period, rule, freq)

  # The rule as it is read in the period it is asked of
  # (`Tempo.RRule.Selection.read_in_its_period/1`), which a value with the
  # rule written after it is: a week asked of a day written with its month
  # is a week of that month.
  defp read_in_its_period(%Tempo{time: [selection: selection]} = rule, %Tempo{time: time} = from) do
    %Tempo{time: read} =
      Selection.read_in_its_period(%{from | time: time ++ [selection: selection]})

    %{rule | time: [List.last(read)]}
  end

  # What a merged constraint is asked before it is merged
  # (`merged_constraint_tempo/2`): a calendar of weeks has no month to
  # filter by, and a selector Tempo does not yet answer for in the period's
  # calendar is refused, and named.
  defp filters_in(selection, from, calendar) do
    if Validation.written_in_another_calendar?(selection, calendar),
      do: {:error, selects_by_month_error(calendar, selection)},
      else: NotBuilt.selector(selection, from)
  end

  # A week selected from a month is a week of the month, which the resolver
  # gives as the span of its dates: an occurrence within the month's weeks,
  # where every other part that only keeps or drops its period leaves the
  # period as it is.
  defp week_of_month_rule?(%Tempo{time: [selection: selection]}, :month),
    do: List.keymember?(selection, :week, 0)

  defp week_of_month_rule?(_rule, _unit), do: false

  # A week of the calendar's own numbering (`w`) is a week of its year, and
  # is not selected from a month: the refusal names what was asked
  # (`Tempo.RRule.Selection.calendar_week_in_its_year/2`).
  defp week_of_month_built(%Tempo{time: [selection: selection]}, :month, %Tempo{} = from) do
    with {:error, %ConversionError{} = refusal} <-
           Selection.calendar_week_in_its_year(selection, from) do
      asked = "the selection of #{inspect(selection)} from #{inspect(from)}"
      {:error, %{refusal | value: asked}}
    end
  end

  defp week_of_month_built(_rule, _unit, _from), do: :ok

  # A rule written in another calendar than the period's holds only what
  # selects in any calendar (`one_calendar/2`), and is resolved in the
  # period's, so that what it selects are values of the period's calendar:
  # its days of the week are written as the days that calendar gives the
  # same weekdays.
  defp in_calendar_of(
         %Tempo{time: [selection: selection], calendar: written} = rule,
         %Tempo{calendar: calendar}
       ) do
    from = Compare.effective_calendar(written)
    to = Compare.effective_calendar(calendar)

    if from == to do
      rule
    else
      selection = Selection.days_of_week_in_calendar(selection, from, to)
      %{rule | time: [selection: selection], calendar: calendar}
    end
  end

  defp in_calendar_of(rule, _period_start), do: rule

  defp cadence_unit(unit) when unit in [:day_of_year, :day_of_week], do: :day
  defp cadence_unit(unit), do: unit

  # Units before a selection narrow the period first, and the selection
  # applies within what they select: `4ML1K1IN` is the first Monday of
  # April.
  defp select_narrowed(period, constraint, units, selection) do
    rule = %{constraint | time: [selection: selection]}

    with {:ok, %IntervalSet{} = narrowed} <-
           select_constraint(period, %{constraint | time: units}) do
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

  # A value's units and its ISO 8601-2 selection: the units before the
  # selection, `:none` without one, and `:unreadable` when units follow it.
  defp selection_parts(time) do
    case Enum.split_while(time, &(not selection_unit?(&1))) do
      {_units, []} -> :none
      {units, [{:selection, selection}]} -> {units, selection}
      {_units, _selection_and_more} -> :unreadable
    end
  end

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

  # The day a span's end starts on: its day, or the first day of its month
  # or its year, which the calendar is asked for where the year does not
  # begin with its first month (`Tempo.UnitValues.start_date/2`).
  defp month_time_to_date(time, calendar) do
    with {:ok, {year, month, day}} <- UnitValues.start_date(time, calendar) do
      Date.new(year, month, day, calendar)
    end
  end

  # Week-axis endpoint — `[year, week, day_of_week]`, a date of the
  # ISO 8601 weeks `Tempo.UnitValues.date_from_iso_week/4` counts,
  # converted into the base calendar. A week-resolution endpoint
  # denotes the start of its week, so a missing `:day_of_week`
  # defaults to 1.
  defp week_time_to_date(time, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         week when is_integer(week) <- Keyword.get(time, :week),
         day when is_integer(day) <- Keyword.get(time, :day_of_week, 1),
         {:ok, week_date} <- UnitValues.date_from_iso_week(year, week, day, calendar) do
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

  # A day a weekday selects is the day's own value, walked by its hours as
  # `Tempo.to_interval/1` has a day walked (decided 2026-10-08), as a day
  # selected by its number is. It was the span of the day with no unit, and
  # was walked as the one day.
  defp day_interval(calendar, y, m, d, source_from) do
    from_tempo = build_day_tempo(source_from, y, m, d, calendar)

    next = day_after(y, m, d, calendar)
    to_tempo = build_day_tempo(source_from, next.year, next.month, next.day, calendar)

    %Interval{from: from_tempo, to: to_tempo, unit: :hour}
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
        select_built_indices(source, base_time, next_unit, indices)
    end
  end

  # An index is a value of the unit below the base's: a day of a month, a
  # month of a year. One Tempo does not yet answer for in the base's
  # calendar is refused, and named.
  defp select_built_indices(source, base_time, next_unit, indices) do
    case NotBuilt.selector([{next_unit, indices}], %{source | time: base_time}) do
      :ok ->
        indices
        |> Enum.map(fn idx -> project_index(source, base_time, next_unit, idx) end)
        |> Enum.reject(&is_nil/1)
        |> IntervalSet.new(coalesce: false)

      {:error, _not_built} = error ->
        error
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
    with {:ok, constraints} <- collect(constraints, &with_its_seasons_dated/1),
         {:ok, intervals} <- project_each(base, constraints) do
      IntervalSet.new(intervals, coalesce: false)
    end
  end

  defp project_each(base, constraints) do
    Enum.reduce_while(constraints, {:ok, []}, fn c, {:ok, acc} ->
      case project_onto_base(base, c) do
        {:error, _} = err -> {:halt, err}
        list when is_list(list) -> {:cont, {:ok, acc ++ Enum.reject(list, &is_nil/1)}}
        nil -> {:cont, {:ok, acc}}
        other -> {:cont, {:ok, acc ++ List.wrap(other)}}
      end
    end)
  end

  # A selector that holds a season of 21 to 24, the season alone or an
  # interval with one at an end, has no dates as it is written: it selects
  # as the span it converts to, in the hemisphere of the territory in force,
  # as a base that holds one is selected from.
  defp with_its_seasons_dated(constraint) do
    if Group.abstract_season?(constraint),
      do: constraint |> Tempo.to_interval() |> dated_spans(),
      else: {:ok, [constraint]}
  end

  defp dated_spans({:ok, %Interval{} = span}), do: {:ok, [span]}
  defp dated_spans({:ok, %IntervalSet{} = set}), do: {:ok, IntervalSet.members(set)}
  defp dated_spans({:error, _reason} = error), do: error

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
  defp project_onto_base(%Interval{} = base, %Tempo{time: c_time, calendar: selector_calendar}) do
    c_time = read_in(c_time, base)

    case day_of_week_only(c_time, selector_calendar) do
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
    c_from = %{c_from | time: read_in(c_from.time, base)}

    case weekdays_of_span(c_from, constraint.to) do
      {:ok, weekdays} -> span_on_each_weekday(base, weekdays, constraint)
      :none -> project_span_onto_base(base, c_from, constraint)
      :at_its_end_alone -> {:error, weekday_span_error(constraint)}
    end
  end

  defp project_onto_base(_base, constraint), do: {:error, unrecognised_selector(constraint)}

  defp project_span_onto_base(base, c_from, constraint) do
    case span_endpoint(constraint) do
      {:to, %Tempo{} = c_to} ->
        c_to = %{c_to | time: read_in(c_to.time, base)}
        on_each_period(base, c_from.time, &project_span(&1, c_from, c_to))

      {:duration, %Duration{} = duration} ->
        on_each_period(base, c_from.time, &project_span_duration(&1, c_from, duration))

      :point ->
        project_onto_base(base, c_from)

      {:each, which, values} ->
        span_from_each(values, which, base, constraint)

      {:error, _several_values} = error ->
        error
    end
  end

  # A span whose start names a day of the week (`1KT9H/T17H`, Monday's nine
  # to five) is the span of the rest of each end, on each such day of the
  # base, as a value that names one is the rest of it on each (`1KT10H`).
  # The ends were merged as they stood onto every day of the base, so each
  # day was given the span, in a value that held its date and the weekday
  # both: 16 June 2026, a Tuesday, and Monday. A span that does not start
  # and end on the one weekday is no span within a day, and is refused: an
  # end that names another (`1KT9H/5KT17H`), or a weekday and no time after
  # it (`1K/1K`), or a weekday the start does not name (`T9H/1KT17H`).
  defp weekdays_of_span(%Tempo{time: time, calendar: calendar}, c_to) do
    case {day_of_week_only(time, calendar), weekday_alone?(c_to)} do
      {{:ok, weekdays}, _at_its_end} -> {:ok, weekdays}
      {:no, true} -> :at_its_end_alone
      {:no, false} -> :none
    end
  end

  defp weekday_alone?(%Tempo{time: time, calendar: calendar}),
    do: day_of_week_only(time, calendar) != :no

  defp weekday_alone?(_open_or_none), do: false

  defp span_on_each_weekday(base, weekdays, %Interval{from: c_from, to: c_to} = constraint) do
    case end_on_the_same_day(c_from, c_to) do
      {:ok, c_to} ->
        on_the_day = %{constraint | from: without_day_of_week(c_from), to: c_to}
        base |> weekdays_in(weekdays) |> gathered(&project_onto_base(&1, on_the_day))

      :another_day ->
        {:error, weekday_span_error(constraint)}
    end
  end

  defp end_on_the_same_day(%Tempo{time: from_time}, %Tempo{time: to_time} = c_to) do
    weekday = Keyword.get(from_time, :day_of_week)

    case Keyword.pop(to_time, :day_of_week) do
      {nil, _to_time} -> {:ok, c_to}
      {^weekday, [_ | _] = time_of_day} -> {:ok, %{c_to | time: time_of_day}}
      {_another_or_alone, _rest} -> :another_day
    end
  end

  defp end_on_the_same_day(_c_from, open_or_none), do: {:ok, open_or_none}

  defp without_day_of_week(%Tempo{time: time} = value),
    do: %{value | time: Keyword.delete(time, :day_of_week)}

  defp weekday_span_error(selector) do
    IntervalEndpointsError.exception(
      interval: selector,
      operation: :select,
      reason:
        "#{inspect(selector)} does not run within one day of the week: a span selected by a " <>
          "weekday starts on that day and ends by a time of day (`1KT9H/T17H`). Select the " <>
          "days, and then the times within them."
    )
  end

  # The span from each value of a start that holds a set, or to each value
  # of an end that does, each projected as the span of that one value is.
  defp span_from_each(values, which, base, constraint) do
    Enum.reduce_while(values, [], fn value, spans ->
      case project_onto_base(base, Map.put(constraint, which, value)) do
        {:error, _reason} = error -> {:halt, error}
        projected -> {:cont, spans ++ List.wrap(projected)}
      end
    end)
  end

  # A day with no month, selected from a year, is a day of the year, as a
  # value's is (`2026Y45D`) and a selection's (`Tempo.RRule.Selection`): the
  # 45th is 14 February and the last 31 December. A calendar of weeks has no
  # months, and refuses a day of one where it is merged.
  defp read_in(c_time, %Interval{from: %Tempo{time: [{:year, _year}], calendar: calendar}}) do
    if Tempo.week_based_calendar?(Compare.effective_calendar(calendar)),
      do: c_time,
      else: Selection.days_of_year_where_no_month(c_time)
  end

  defp read_in(c_time, _period), do: c_time

  # The units a constraint names after its weekday, merged onto each day the
  # weekday selects.
  defp after_day_of_week(c_time), do: Keyword.delete(c_time, :day_of_week)

  defp on_each_day(days, []), do: Enum.to_list(days)
  defp on_each_day(days, units), do: gathered(days, &project_merge(&1, units))

  # What `project` gives each period in turn, as one list, or the first error.
  defp gathered(periods, project) do
    Enum.reduce_while(periods, [], fn period, selected ->
      case project.(period) do
        {:error, _reason} = error -> {:halt, error}
        projected -> {:cont, selected ++ (projected |> List.wrap() |> Enum.reject(&is_nil/1))}
      end
    end)
  end

  # A constraint is merged onto the start of its period, which is right where
  # it is written in the units the period's own start is: a day of a month
  # onto a month, a day of the year onto a year. One written on another axis
  # names no value there (`2026Y6M15D100O`), so it is merged onto the periods
  # of its own axis that the period touches, and what does not start in the
  # period is dropped as any selection is (`select_in_period/2`):
  #
  # * a day of the year onto the calendar years a month, a week or a day
  #   touches, so `166O` is 15 June from June and from its week;
  #
  # * a month or a day of one onto the months a week touches, so `1D` is
  #   1 July from the week that starts on 29 June.
  #
  # A week under a month is the week of the month, which the calendar
  # numbers: one week selected from a month is merged onto the month it is
  # of (`week_of_month/2`). What is not built is refused by name
  # (`Tempo.NotBuilt.week_of_month/2`): a week that is no one whole number,
  # and a week merged with finer units onto a period within a month. A week
  # alone selected from a day or a time is a filter and is not merged
  # (`select_constraint/2`). A calendar of weeks has no other axis, and
  # refuses a month or a day of one where it is merged.
  defp on_each_period(%Interval{} = base, c_time, project) do
    case periods_on_axis(base, c_time) do
      {:ok, [^base]} -> project.(base)
      {:ok, periods} -> periods |> gathered(project) |> each_once()
      {:error, _not_built} = error -> error
    end
  end

  defp each_once(projected) when is_list(projected), do: Enum.uniq(projected)
  defp each_once({:error, _reason} = error), do: error

  defp periods_on_axis(%Interval{from: %Tempo{time: time, calendar: calendar}} = base, c_time) do
    if Tempo.week_based_calendar?(Compare.effective_calendar(calendar)),
      do: {:ok, [base]},
      else: periods_on_axis(written_on(c_time), written_on(time), base, c_time)
  end

  defp periods_on_axis(:ordinal, period_axis, base, _c_time) when period_axis in [:month, :week],
    do: periods_touched(base, &[year: &1.year])

  defp periods_on_axis(:month, :week, base, _c_time),
    do: periods_touched(base, &[year: &1.year, month: &1.month])

  defp periods_on_axis(:week, :month, %Interval{from: from} = base, c_time) do
    if week_of_month?(from, c_time),
      do: {:ok, [base]},
      else: NotBuilt.week_of_month(c_time, from)
  end

  defp periods_on_axis(_axis, _period_axis, base, _c_time), do: {:ok, [base]}

  # The axis a time list is written on below its year: the day of the year,
  # the week, or the month and its day. A year alone, a day of the week and a
  # time of day are on none, and go with any.
  defp written_on(time) do
    cond do
      List.keymember?(time, :day_of_year, 0) -> :ordinal
      List.keymember?(time, :week, 0) -> :week
      List.keymember?(time, :month, 0) or List.keymember?(time, :day, 0) -> :month
      true -> :none
    end
  end

  # The periods a span touches, of the units `named` gives a date: those of
  # the day it starts on and of the day it ends on. A span that ends where
  # such a period begins touches it at no day, and what is merged onto that
  # one starts at or after the span's end.
  defp periods_touched(%Interval{from: %Tempo{calendar: calendar} = from, to: to}, named) do
    with {:ok, %Date{} = first} <- tempo_to_date(from, calendar),
         {:ok, %Date{} = last} <- end_date(to, calendar) do
      [first, last] |> Enum.map(named) |> Enum.uniq() |> periods_named(from)
    else
      _no_one_day -> {:ok, []}
    end
  end

  # Each time list as the period of the value it is, or the first error.
  defp periods_named(times, %Tempo{} = from) do
    Enum.reduce_while(times, {:ok, []}, fn time, {:ok, periods} ->
      case period_of(%{from | time: time}) do
        {:ok, period} -> {:cont, {:ok, periods ++ [period]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # How a selector that is a span ends: at its own end, by a duration from
  # its start, or as the point its start is. A span runs from one point to
  # another, so an end that holds a set names a span for each of its
  # values. Written with a duration from a start that holds a set it is the
  # span from each of the start's values (decided 2026-10-07): `T{9,14}H/PT1H`
  # is the hour from 09:00 and the hour from 14:00. Written with two ends,
  # one of which holds a set, it is the span from each value to the other
  # end, or to each from it (decided 2026-10-08): `T{9,14}H/T16H` is nine to
  # four and two to four. It was refused, the ends having been merged as
  # they stood into a span that held the sets. A set at each end names no
  # one span for any value, and is refused still.
  defp span_endpoint(%Interval{recurrence: recurrence}) when recurrence != 1, do: :point

  defp span_endpoint(%Interval{from: %Tempo{} = from, to: nil, duration: %Duration{}} = selector) do
    case Enumeration.expand(from) do
      {:ok, starts} -> {:each, :from, starts}
      {:error, _exception} = error -> error
      :not_expandable -> span_end(selector)
    end
  end

  defp span_endpoint(%Interval{from: from, to: to} = selector) do
    case {names_several?(from), names_several?(to)} do
      {false, false} -> span_end(selector)
      {true, false} -> each_value(:from, from)
      {false, true} -> each_value(:to, to)
      {true, true} -> {:error, several_values_error(selector, "start", from)}
    end
  end

  defp each_value(which, %Tempo{} = endpoint) do
    with {:ok, values} <- Enumeration.expand(endpoint), do: {:each, which, values}
  end

  defp span_end(%Interval{to: %Tempo{} = to}), do: {:to, to}
  defp span_end(%Interval{to: nil, duration: %Duration{} = duration}), do: {:duration, duration}
  defp span_end(%Interval{}), do: :point

  defp names_several?(%Tempo{} = value), do: Enumeration.names_each_value?(value)
  defp names_several?(_no_value), do: false

  defp several_values_error(selector, end_name, value) do
    IntervalEndpointsError.exception(
      interval: selector,
      operation: :select,
      reason:
        "#{inspect(selector)} has no one #{end_name} to select a span by: #{inspect(value)} " <>
          "names several values. Select by each of them, or by the values themselves."
    )
  end

  # A span either end of which cannot land on the member (29 February, in a
  # common year) is skipped, as a point that cannot land is.
  defp project_span(%Interval{} = base, %Tempo{} = c_from, %Tempo{} = c_to) do
    with %Tempo{} = span_from <- merged_start(base, c_from.time),
         %Tempo{} = span_to <- merged_start(base, c_to.time) do
      shown_span(span_from, roll_past_midnight(span_from, span_to))
    end
  end

  # A window written with a duration runs that long from the reading it
  # starts on, which for a start the clock skips is the reading the clock
  # comes out of the gap on, as a window's start is (`shown_span/2`):
  # `T02/PT2H` on the night New York's clocks go from 02:00 to 03:00 is
  # 03:00 to 05:00.
  defp project_span_duration(%Interval{} = base, %Tempo{} = c_from, %Duration{} = duration) do
    with %Tempo{} = span_from <- merged_start(base, c_from.time),
         %Tempo{} = shown_from <- Zone.shown_by_the_clock(span_from),
         %Tempo{} = span_to <- Math.add(shown_from, duration) do
      build_span(shown_from, span_to)
    else
      {:error, %ConversionError{}} = error -> error
      _other -> nil
    end
  end

  # A window is the part of it the clock of its zone shows. An end inside a
  # gap is on the reading the clock comes out of the gap on, so `T02/T04`
  # on the night New York's clocks go from 02:00 to 03:00 is 03:00 to 04:00
  # and `T01/T02:30` is 01:00 to 03:00, the hour the clock shows of each. A
  # window the clock skips the whole of (`T02/T03`) is nothing.
  defp shown_span(%Tempo{} = span_from, %Tempo{} = span_to) do
    case {Zone.shown_by_the_clock(span_from), Zone.shown_by_the_clock(span_to)} do
      {^span_from, ^span_to} -> build_span(span_from, span_to)
      {shown_from, shown_to} -> span_with_some_time(shown_from, shown_to)
    end
  end

  defp shown_span(_span_from, {:error, _reason} = error), do: error

  defp span_with_some_time(%Tempo{} = from, %Tempo{} = to) do
    if Compare.compare_endpoints(from, to) == :earlier, do: build_span(from, to), else: nil
  end

  # Both endpoints merge onto the same base member, so a window whose
  # `to` does not land after its `from` crossed midnight — its end
  # belongs to the following day. `:same` rolls too: "21:00 to 21:00"
  # reads as a full day, and a zero-extent interval is not a value.
  defp roll_past_midnight(%Tempo{} = span_from, %Tempo{} = span_to) do
    if Compare.compare_endpoints(span_to, span_from) == :later,
      do: span_to,
      else: a_day_on(span_to)
  end

  # The same reading of the clock on the day after, as it is written. A step
  # of a day lands on it, or that long after it where the clock skips the
  # reading (`Tempo.Math.add/2`), which is where an occurrence a recurrence
  # steps to is. A window ends on the reading the clock comes out of the gap
  # on (`shown_span/2`), so the reading is given as written, in the zone and
  # at the offset the step landed in.
  defp a_day_on(%Tempo{} = reading) do
    day = Duration.build(day: 1)

    with %Tempo{} = stepped <- Math.add(reading, day),
         %Tempo{time: written} <- Math.add(%{reading | extended: nil, shift: nil}, day) do
      %{stepped | time: written}
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
      else: merge_built_constraint(base, c_time)
  end

  # A selector Tempo answers for in the base's calendar is merged onto the
  # base; one it does not yet is refused, and named.
  defp merge_built_constraint(%Interval{from: from} = base, c_time) do
    case NotBuilt.selector(c_time, from) do
      :ok -> merged_onto(base, from, c_time)
      {:error, _not_built} = error -> error
    end
  end

  defp merged_onto(base, from, c_time) do
    if week_of_month?(from, c_time),
      do: week_of_month(from, c_time),
      else: merge_constraint(base, c_time)
  end

  # A selector is a value of its own calendar. Its year, its month, its day
  # of one, its day of the year and its week are numbers of that calendar, so
  # they are selected only from a span of the same calendar and are never
  # read in the span's: the sixth month of a Hebrew year is not June, as
  # `Tempo.at/2` and `Tempo.on/2` have it. A time of day is the same in every
  # calendar and a day of the week names a weekday (`day_of_week_only/2`), so
  # both select from any span. ISO 8601's weeks are the Gregorian calendar's
  # and the ISO week calendar's alike, so a week written in one selects from
  # the other.
  defp one_calendar(%Interval{from: %Tempo{calendar: calendar}}, selectors) do
    span_calendar = Compare.effective_calendar(calendar)

    selectors
    |> List.wrap()
    |> Enum.find_value(:ok, &of_another_calendar(&1, span_calendar))
  end

  defp one_calendar(_period, _selectors), do: :ok

  # The error for a selector that holds a unit numbered by another calendar
  # than the span's, and `nil` for one that selects from the span.
  defp of_another_calendar(%Tempo{time: time, calendar: written} = selector, span_calendar)
       when is_list(time) do
    written = Compare.effective_calendar(written)

    if written != span_calendar and numbered_by_calendar?(time, written, span_calendar),
      do: {:error, another_calendar_error(selector, written, span_calendar)}
  end

  defp of_another_calendar(%Interval{from: from, to: to}, span_calendar),
    do: Enum.find_value([from, to], &of_another_calendar(&1, span_calendar))

  defp of_another_calendar(_selector, _span_calendar), do: nil

  @numbered_by_calendar [
    :year,
    :month,
    :traditional_month,
    :day,
    :day_of_year,
    :calendar_week,
    :nearest_weekday,
    :or_day
  ]

  @iso_week_calendars [Calendrical.Gregorian, Calendrical.ISOWeek]

  defp numbered_by_calendar?(time, written, span_calendar) do
    same_weeks? = written in @iso_week_calendars and span_calendar in @iso_week_calendars
    Enum.any?(time, &unit_numbered_by_calendar?(&1, same_weeks?))
  end

  # A selection's tokens are a rule's units, and a window in one holds dates.
  defp unit_numbered_by_calendar?({:selection, selection}, same_weeks?),
    do: Enum.any?(selection, &unit_numbered_by_calendar?(&1, same_weeks?))

  defp unit_numbered_by_calendar?({:interval, %Interval{from: from, to: to}}, same_weeks?) do
    Enum.any?([from, to], fn
      %Tempo{time: time} when is_list(time) ->
        Enum.any?(time, &unit_numbered_by_calendar?(&1, same_weeks?))

      _open_or_counted ->
        false
    end)
  end

  defp unit_numbered_by_calendar?({:week, _weeks}, same_weeks?), do: not same_weeks?

  defp unit_numbered_by_calendar?(entry, _same_weeks?) when is_tuple(entry),
    do: elem(entry, 0) in @numbered_by_calendar

  defp unit_numbered_by_calendar?(_other, _same_weeks?), do: false

  # A span in a calendar of weeks keeps the error that says what such a
  # calendar is selected by.
  defp another_calendar_error(%Tempo{time: time} = selector, written, span_calendar) do
    if Tempo.week_based_calendar?(span_calendar) and selects_by_month?(time) do
      selects_by_month_error(span_calendar, time)
    else
      ConversionError.exception(
        value: selector,
        target: span_calendar,
        reason:
          "#{inspect(selector)} is a selector written in #{inspect(written)}, and the span it " <>
            "selects from is in #{inspect(span_calendar)}. A month, a week and a day are " <>
            "numbered by their calendar, so a selector that holds one selects only from a " <>
            "span of its own: write it in the span's calendar, which `Tempo.from_iso8601/2` " <>
            "takes and a `[u-ca=…]` suffix names. A time of day and a day of the week select " <>
            "from a span in any calendar."
      )
    end
  end

  @by_month [:month, :traditional_month, :day, :day_of_year]

  defp selects_by_month?(time) do
    Enum.any?(time, fn
      {:selection, selection} -> selects_by_month?(selection)
      entry when is_tuple(entry) -> elem(entry, 0) in @by_month
      _other -> false
    end)
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

    base_time
    |> prune_off_axis_defaults(c_time, base_res)
    |> merge_with_constraint(c_time)
    |> trim_finer_than_constraint(c_time)
    |> reorder_coarse_to_fine()
    |> named_in_period(calendar)
    |> validated_merge(base_from)
  end

  defp validated_merge({:ok, merged_time}, %Tempo{} = base_from),
    do: validated_projection(%{base_from | time: merged_time})

  defp validated_merge(:none, _base_from), do: nil

  defp project_merge(%Interval{} = base, c_time) do
    case each_week_of_month(base, c_time) do
      [^c_time] -> on_each_period(base, c_time, &project_merged(&1, c_time))
      weeks -> gathered(weeks, &project_merge(base, &1))
    end
  end

  # A week of a month alone is the span of its dates, which the merge gives
  # whole; any other constraint is a value, and is its span.
  defp project_merged(%Interval{} = base, c_time) do
    case merged_constraint_tempo(base, c_time) do
      %Tempo{} = merged -> materialise_projection(merged, c_time)
      %Interval{} = week_of_a_month -> week_of_a_month
      nothing_or_an_error -> nothing_or_an_error
    end
  end

  # A constraint merged onto its period as the end of a span: where the
  # value it names starts, which for a week of a month is its first date.
  defp merged_start(%Interval{} = base, c_time) do
    case merged_constraint_tempo(base, c_time) do
      %Interval{from: %Tempo{} = start} -> start
      a_value_nothing_or_an_error -> a_value_nothing_or_an_error
    end
  end

  # The weeks a constraint names in the month it is selected from, as a
  # constraint for each. A week of a month is one week, so a set or a range
  # of them (`{1,3}W`, `{2..-1}W`) is each week it names among those the
  # month has, as a set of days is each day.
  defp each_week_of_month(
         %Interval{from: %Tempo{time: [year: year, month: month], calendar: calendar}},
         c_time
       )
       when is_integer(year) and is_integer(month) do
    calendar = Compare.effective_calendar(calendar)

    c_time
    |> each_named(:week, fn -> weeks_in(year, month, calendar) end)
    |> Enum.flat_map(&each_named(&1, :day_of_week, fn -> days_of_week_in(&1, calendar) end))
  end

  defp each_week_of_month(_base, c_time), do: [c_time]

  # A constraint for each value a set or a range names in `unit`, among the
  # values `values` gives it, and the constraint as it is where it names one
  # value there, or none that can be counted.
  defp each_named(c_time, unit, values) do
    with {^unit, written} when not is_integer(written) <- List.keyfind(c_time, unit, 0),
         true <- counted?(written) or masked?(written),
         {:ok, valid} <- values.() do
      written
      |> UnitValues.named(valid)
      |> Enum.map(&List.keyreplace(c_time, unit, 0, {unit, &1}))
    else
      _one_value_or_none_to_name -> [c_time]
    end
  end

  defp weeks_in(year, month, calendar) do
    with {:ok, weeks} <- UnitValues.weeks_of_month(year, month, calendar),
         do: {:ok, 1..Enum.count(weeks)//1}
  end

  # A day of the week is named among a week's seven only under a week of a
  # month, where each is found among the week's dates.
  defp days_of_week_in(c_time, calendar) do
    if List.keymember?(c_time, :week, 0),
      do: UnitValues.in_period(:day_of_week, [], calendar),
      else: {:error, :no_week}
  end

  # A week selected from a month is a week of that month, which the calendar
  # numbers (`Tempo.UnitValues.weeks_of_month/3`): one week, written as a
  # whole number, selected from a period that is a month.
  defp week_of_month?(%Tempo{time: [year: year, month: month]}, c_time)
       when is_integer(year) and is_integer(month),
       do: match?({:week, week} when is_integer(week), List.keyfind(c_time, :week, 0))

  defp week_of_month?(_from, _c_time), do: false

  # The week of the month a constraint names in its period, as a value
  # written with a week after its month is read (`2026Y6M2W`): the span of
  # the week's dates, or with a day of the week and a time of day the value
  # they name. It is not always within its month: the first week of July
  # 2026 starts on 29 June. A week the month does not have, and a day a
  # week cut short does not have, select nothing, as a day a month does not
  # have does.
  defp week_of_month(%Tempo{time: time, calendar: calendar} = from, c_time) do
    case Group.expand_groups(%{from | time: time ++ c_time}, Compare.effective_calendar(calendar)) do
      {:ok, selected} -> selected
      {:error, %InvalidDateError{unit: unit}} when unit in [:week, :day_of_week] -> nil
      {:error, _reason} = error -> error
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

  # A time of day alone is on no one of them and goes with any, so it takes
  # no unit from what it is merged onto. It was held to be on the month's
  # axis, and the day of a week was taken from the last day of a week,
  # whose span ends in the next: 09:00 of the Sunday of a week, in a
  # calendar of weeks, was 09:00 of its Monday, and so no time of the day.
  @date_units [:year, :month, :day, :week, :day_of_week, :day_of_year]

  defp axis_for_constraint(c_time) do
    cond do
      Keyword.has_key?(c_time, :week) or Keyword.has_key?(c_time, :day_of_week) ->
        @week_axis

      Keyword.has_key?(c_time, :day_of_year) ->
        @ordinal_axis

      Enum.any?(@date_units, &Keyword.has_key?(c_time, &1)) ->
        @gregorian_axis

      true ->
        :any
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
  # The units the base's own start is written in are kept: a
  # constraint on another axis than those is merged onto periods of
  # its own axis first (`on_each_period/3`), so none is off its axis
  # here.
  defp prune_off_axis_defaults(base_time, c_time, base_resolution),
    do: pruned_to_axis(base_time, axis_for_constraint(c_time), base_resolution)

  defp pruned_to_axis(base_time, :any, _base_resolution), do: base_time

  defp pruned_to_axis(base_time, axis, base_resolution) do
    base_res_idx = unit_index(base_resolution) || -1

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

  # What a unit is written as names values among those the unit takes in the
  # units before it (`Tempo.UnitValues`): the months of the year, the days of
  # the month, the weeks and the days of the year, the hours of the day. A
  # count from the end (ISO 8601-2 §4.4.1) is the value it counts back to, and
  # a value the period does not have is passed over, as an index is: `{1,30}D`
  # selects the 1st from February, and a count that reaches past the period's
  # start (`-45D` from a month) selects nothing. So does a constraint one of
  # whose units names no value there, which is `:none`.
  #
  # A day with no month before it is a day of the year, as a value's is. A
  # year is never counted from the end: a negative year is a year before
  # year 1.
  defp named_in_period(time, calendar) do
    Enum.reduce_while(time, {:ok, []}, fn {unit, written}, {:ok, context} ->
      case named(unit, written, context, calendar) do
        :none -> {:halt, :none}
        value -> {:cont, {:ok, context ++ [{unit, value}]}}
      end
    end)
  end

  # The values are asked for where the units before fix them: under a set of
  # months a day is left as it is written, and each of the dates the merged
  # value names is checked when it is converted.
  defp named(unit, written, context, calendar) when unit != :year do
    with true <- counted?(written) and Enum.all?(context, &one_value?/1),
         {:ok, values} <- unit_values(unit, context, calendar) do
      named_among(written, values)
    else
      _as_written -> written
    end
  end

  defp named(_year, written, _context, _calendar), do: written

  # The values named, each once however it is written: `{1,-31}D` names the
  # 1st of January once.
  defp named_among(written, values) do
    case UnitValues.named(written, values) do
      [] -> :none
      [value] -> value
      several -> several
    end
  end

  # A whole number, a range of them, or several of either: what
  # `Tempo.UnitValues.named/2` counts. A fraction, a mask and a group are
  # read by the conversion.
  defp counted?(written) when is_integer(written) or is_struct(written, Range), do: true

  defp counted?([_ | _] = written),
    do: Enum.all?(written, &(is_integer(&1) or is_struct(&1, Range)))

  defp counted?(_written), do: false

  # A mask, and an unspecified unit, stand for each value their digits
  # match among those the unit takes.
  defp masked?({:mask, mask}) when is_list(mask), do: true
  defp masked?(:any), do: true
  defp masked?(_written), do: false

  defp one_value?({_unit, value}), do: is_integer(value)

  defp unit_values(:day, context, calendar) do
    if Keyword.has_key?(context, :month),
      do: UnitValues.in_period(:day, context, calendar),
      else: UnitValues.in_period(:day_of_year, context, calendar)
  end

  defp unit_values(unit, context, calendar), do: UnitValues.in_period(unit, context, calendar)

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
  #
  # A day of the week is read in the calendar of the value that holds it,
  # which is the selector's: the third day is Wednesday in a selector
  # written in a calendar of months, and Tuesday in one written in a
  # calendar of weeks that start on Sunday. The weekdays it names are
  # given as ISO 8601 numbers them, which is how a day of any span's
  # calendar is asked for its weekday (`weekdays_in/2`), so a selector
  # selects the same weekdays in whatever calendar the span is in.
  defp day_of_week_only(c_time, selector_calendar) do
    case Keyword.get(c_time, :day_of_week) do
      nil ->
        :no

      dow ->
        if Enum.any?([:year, :month, :day, :week], &Keyword.has_key?(c_time, &1)) do
          :no
        else
          {:ok, weekdays_named(dow, Compare.effective_calendar(selector_calendar))}
        end
    end
  end

  defp weekdays_named(written, calendar) do
    case UnitValues.in_period(:day_of_week, [], calendar) do
      {:ok, days} ->
        written
        |> UnitValues.named(days)
        |> Enum.map(&UnitValues.iso_weekday_from_day_of_week(&1, calendar))

      {:error, _reason} ->
        []
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
