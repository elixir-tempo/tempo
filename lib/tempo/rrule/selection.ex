defmodule Tempo.RRule.Selection do
  @moduledoc """
  Resolve RRULE `BY*` selection tokens during recurrence expansion.

  Called from `Tempo.to_interval/2`'s recurrence loop. Given a
  candidate occurrence and a `repeat_rule` whose `:time` carries
  a `[{:selection, [...]}]` keyword list (the shared AST produced
  by `Tempo.RRule.parse/2` and `Tempo.RRule.Expander.to_ast/3`),
  decide whether the candidate is kept, dropped, or expanded into
  multiple occurrences.

  ## Implemented rules

  Per RFC 5545 §3.3.10's EXPAND/LIMIT table:

  | Part | Role |
  |---|---|
  | `BYMONTH` | EXPAND for `YEARLY`, LIMIT otherwise. |
  | `BYWEEKNO` | EXPAND for `YEARLY`, LIMIT otherwise. |
  | `BYYEARDAY` | EXPAND for `YEARLY`, LIMIT otherwise. |
  | `BYMONTHDAY` | EXPAND for `MONTHLY` and `YEARLY`, LIMIT otherwise. |
  | `BYDAY` (no ordinal) | EXPAND within the week, month or year; LIMIT for finer FREQs. |
  | `BYDAY` (with ordinal) | EXPAND to the nth weekday of the month or year. |
  | `BYHOUR`, `BYMINUTE`, `BYSECOND` | EXPAND when FREQ is coarser, LIMIT otherwise. |
  | `BYSETPOS` | LIMIT, applied last to each period's occurrences. |

  `BYWEEKNO` numbers weeks as RFC 5545 defines them: each starts on
  `WKST`, and week 1 is the first with at least four days in the year.
  A week keeps all seven of its days, including any in the year before
  or after. Once `BYWEEKNO` has expanded a `YEARLY` rule into those
  days, the parts after it apply to them as they would to a `DAILY`
  rule, so `BYDAY` picks weekdays within each week. A calendar-week
  selection (`w`, Tempo's extension) expands and limits as `BYWEEKNO`
  does, in the weeks the calendar numbers itself.

  In a `YEARLY` rule the parts that name a day all hold at once, so the days selected are those that satisfy every one. `BYYEARDAY`, a computed event (`e`, Tempo's extension) and `BYMONTHDAY` apply in that order: the first of them the rule holds names the days, and each after it keeps those it names too. `BYMONTH` keeps a day of the year and an event to the months it lists, each day listed once: `BYMONTH=3;BYYEARDAY=100` selects nothing, day 100 being 10 April, and `3M(easter)e` is Easter in the years it falls in March.

  A computed event is each of its days that falls in the period it is selected in: it expands a `YEARLY`, a `MONTHLY` and a `WEEKLY` rule, so the Easter of April 2026 and of its fourteenth week are both 5 April, and it limits a `DAILY` rule and a finer one to the candidates on its day. A weekday or a day of the month beside it limits that day.

  RFC 5545's candidate at every frequency is a day, and its table gives a weekly rule no `BYMONTHDAY` and no `BYYEARDAY`, and a monthly rule no `BYYEARDAY`. A selection made in a whole week or month (`Tempo.select/2` from one, a value such as `2026Y25WL15DN`, a recurrence that starts at its cadence's resolution or has no start) has that period for its candidate, and such a part is then each day of the period it names: `L15DN` in a week is the day of the week that is the 15th of its month, and `L166ON` in June is 15 June 2026. A part that names a day after it keeps the days it names too, and a weekday beside one keeps or drops them. Where the candidate is a day, as in a rule read from an RRULE, the period is the week (from `WKST`) or the month that holds it. A week resolved in a month is a week of the month, which the calendar numbers (`Tempo.UnitValues.weeks_of_month/3`): `L2WN` in June 2026 is 8 to 14 June, the span of its dates, and `L1WN` in July starts on 29 June. Beside a part that picks within the week it hands that part its days, as a week does in a year: `L2W3KN` in June 2026 is Wednesday the 10th, `L2WT10HN` ten o'clock on each of the week's seven days and `L2W1IN` its first day. `read_in_its_period/1` says which a week is, of its month or of the year: in a rule that steps by months from a date, as one read from an RRULE does, each candidate is a day, which the week keeps or drops by its week of the year. A week beside the month it is written with is a week of that month wherever it is resolved (`L6M2WN` in a year is the second week of June), and a week asked of a day or a time of day, which are written with their month, keeps it where that week of the month holds it. A week after a §12.10 window is asked of the window's days, by the week of the year each is in.

  A day with no month (`D`) in a rule that is resolved in a year, and that nothing gives a month, is a day of the year, as the value `2026Y45D` is: `2026YL45DN` and `R/2026/P1Y/FL45DN` are 14 February, and `L-1DN` there is 31 December. A recurrence's start that names a month gives the day that month (ISO 8601-2 §13.6.3), a rule read from an RRULE with a start states it (`L3M15DN`), and a month, a week, a day of the year or a computed event beside the day places it already. `read_in_its_period/1` is that reading, which the conversion, the RRULE writer and `Tempo.explain/1` all ask.

  A year (`Y`), which RFC 5545 has no part for and ISO 8601-2 §12.2 no
  selection rule, limits the periods a selection resolves in, as a
  recurrence domain's years (`R/{2027Y}/…`) do: a period that starts in
  a listed year keeps every occurrence it selects, and a period in any
  other year selects nothing. The Monday of ISO 8601 week 1 of 2026 is
  2026's occurrence although it falls on 29 December 2025, and a
  position (`I`) picks among a listed year's occurrences.

  An expansion picks its points in the calendar period of the enclosing frequency that holds the candidate's start, as RFC 5545 evaluates `BY*` rules: a daily candidate that starts at noon has its `BYHOUR=9` at 09:00 that day, three hours before it. A cadence of mixed units (`P1DT12H`) takes its frequency from its first unit.

  A value counted from the end is counted in the period its part resolves in: `-1` is the last day of the candidate's month, the last month of its year (the thirteenth of a Hebrew leap year), the last day of its week, 23:00. A range is resolved end by end, so `{1..-1}` is every value and `{28..-1}` the 28th to the last, and a value the period lacks (the 31st of June, hour 25) is passed over. The values a part names are taken in the order of time and once each, however they are written, which is the order a position (`I`, `BYSETPOS`) and a recurrence's count take the occurrences in.

  Tokens this module doesn't interpret pass through unchanged
  so partial support is correct for the partial inputs.

  """

  alias Calendrical.Kday
  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Enumeration.Zone
  alias Tempo.Event
  alias Tempo.EventError
  alias Tempo.Interval
  alias Tempo.Mask
  alias Tempo.Math
  alias Tempo.UnitValues
  alias Tempo.Validation

  @typedoc """
  A rule: a `t:Tempo.t/0` whose `:time` is a selection (`[selection: [...]]`) and any units after it, as `Tempo.RRule.Rule.to_selection/2` builds one.

  """
  @type rule :: Tempo.t()

  # ISO 8601's weeks, and RFC 5545's by default, start on a Monday, weekday 1.
  @monday 1

  # The most weekdays that are each found a week at a time in a month
  # (`weekdays_of_month/4`), where more are asked of each of its days.
  @weekdays_found_by_weeks 3

  # The most candidates of a period a position picks among: the most values
  # Tempo gives at once, the application's `:max_values_at_once`.
  @candidates_at_once Tempo.Limit.values_at_once()

  @doc """
  Apply a `repeat_rule` to one candidate occurrence and return the
  resulting list of occurrences.

  ### Arguments

  * `candidate` is a `t:Tempo.Interval.t/0` — the current
    occurrence under consideration.

  * `repeat_rule` is either `nil` (no rule — passthrough) or a
    `%Tempo{}` whose `:time` holds `[selection: [...]]`, followed by any units that apply to every date the selection picks (`L5K2INT9H` is 09:00 on the second Friday).

  * `freq` is the enclosing `FREQ` atom (`:second`, `:minute`,
    `:hour`, `:day`, `:week`, `:month`, `:year`). Drives the
    EXPAND-vs-LIMIT dispatch for rules whose role depends on
    the enclosing frequency.

  * `options` is a keyword list of options.

  ### Options

  * `:origin_day` is the day of the month the recurrence started on,
    which an expansion that moves the month clamps from. The default
    is `nil`.

  * `:keep_span` is `true` when the occurrences carry an explicit span
    (an iCalendar `DTEND`, an `:occurrence_duration`), which an hour,
    minute or second expansion keeps by moving the candidate's `to` with
    its `from`. The default is `false`: when the rule expands (see
    `expands?/2`), each occurrence is resized to its own resolution
    afterwards.

  * `:at_most` is the most occurrences the caller takes of the candidate, a whole number. Where the rule gives more it is refused, and no more than that are made to find it out: the times of day of a selection and the units after one are counted as they are made, and a position's candidates are held to the most values Tempo gives at once. A §12.10 window is made whole, and counted then. The default is `nil`, every occurrence.

  ### Returns

  * A list of `t:Tempo.Interval.t/0` occurrences — `[]` on LIMIT
    rejection, `[candidate]` on passthrough or LIMIT accept,
    `[c1, c2, …]` on EXPAND.

  * `{:error, %Tempo.EventError{}}` when the selection holds a computed event that has no date where it is asked for: a year outside those it is computed for, or a name no resolver knows.

  * `{:error, {:more_than, most}}` when the rule gives more occurrences than `:at_most` asks for, and when a position (`I`, RFC 5545's `BYSETPOS`) would pick among more candidates of the period than the most values Tempo gives at once, the application's `:max_values_at_once` (10,000 unless it is set).

  ### Examples

      iex> candidate = %Tempo.Interval{from: ~o"2022-06-15", to: ~o"2022-06-16"}
      iex> rule = %Tempo{time: [selection: [month: 6]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.apply(candidate, rule, :month)
      [candidate]

      iex> candidate = %Tempo.Interval{from: ~o"2022-07-15", to: ~o"2022-07-16"}
      iex> rule = %Tempo{time: [selection: [month: 6]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.apply(candidate, rule, :month)
      []

  """
  @spec apply(Interval.t(), rule() | nil, atom(), keyword()) ::
          [Interval.t()] | {:error, EventError.t() | {:more_than, non_neg_integer()}}
  def apply(candidate, repeat_rule, freq, options \\ [])

  def apply(%Interval{} = candidate, nil, _freq, _options), do: [candidate]

  def apply(
        %Interval{} = candidate,
        %Tempo{time: [{:selection, selection} | units], calendar: rule_calendar},
        freq,
        options
      ) do
    # The recurrence's *original* start day rides along as a tagged
    # entry: cadence stepping clamps the candidate's day (Feb 29 →
    # Feb 28 in a common year), and an expansion that repositions the
    # month must clamp from the day the rule started on, per
    # occurrence — not from an intermediate clamp. Whether the
    # occurrences carry an explicit span rides along the same way.
    # Handlers that don't consume the tags pass them through.
    context = selection_context(options)
    most = counted_to(options, selection, units)
    selection = days_of_week_in_candidate_calendar(selection, rule_calendar, candidate)

    candidate
    |> in_calendar_terms(selection, freq, fn candidate, selection, freq ->
      candidate
      |> apply_selection(selection ++ context, freq, most)
      |> with_units(units, Keyword.get(context, :keep_span, false), at_most(options))
      |> on_readings_the_clock_shows()
    end)
    |> no_more_than(at_most(options))
  end

  # What the parts of a selection give is a list of occurrences, or the
  # error of a computed event that has no date where the selection asks for
  # one (`Tempo.EventError`), which every step from there hands on as it is.

  # No selection shape we recognise — pass through rather than
  # crash. Future phases replace this catch-all with a specific
  # error once every shape is accounted for.
  def apply(%Interval{} = candidate, _, _freq, _options), do: [candidate]

  # A reading the clock skips is no time to select (decided 2026-10-07): the
  # hour a rule picks with `BYHOUR=2` on the night New York's clocks go from
  # 02:00 to 03:00, and Samoa's 30 December 2011, which the 30th of each
  # month and the Fridays of that December would pick. A time of day on a
  # day left out is on no day either: a rule for Fridays at ten selects
  # nothing in that week, where the reading moved a day on would be a
  # Saturday's. RFC 5545 §3.3.10 has an instance on a local time that does
  # not exist ignored, and not counted. An occurrence a recurrence steps to
  # is another matter, and is the reading that long after (§3.3.5).
  #
  # An occurrence of a rule whose start is written with an offset is at the
  # offset its zone is at on each of its ends
  # (`Tempo.Enumeration.Zone.at_its_offset/1`).
  defp on_readings_the_clock_shows(occurrences) when is_list(occurrences) do
    for occurrence <- occurrences,
        not starts_on_a_reading_skipped?(occurrence),
        do: at_the_offsets_of_its_ends(occurrence)
  end

  defp on_readings_the_clock_shows({:error, _reason} = error), do: error

  defp at_the_offsets_of_its_ends(
         %Interval{from: %Tempo{shift: [_ | _]} = from, to: to} = occurrence
       ),
       do: %{occurrence | from: Zone.at_its_offset(from), to: at_its_offset(to)}

  defp at_the_offsets_of_its_ends(occurrence), do: occurrence

  defp at_its_offset(%Tempo{} = to), do: Zone.at_its_offset(to)
  defp at_its_offset(open_or_none), do: open_or_none

  defp starts_on_a_reading_skipped?(%Interval{from: %Tempo{} = from}),
    do: not Zone.shown?(from)

  defp starts_on_a_reading_skipped?(_occurrence), do: false

  @doc """
  Returns whether a `repeat_rule` expands each candidate into points rather than only limiting the candidates it keeps.

  An expansion makes points within a candidate — the 15th of a monthly candidate, the Mondays of a weekly one, 09:00 of a daily one — and each point is an occurrence one unit of its own resolution long. A rule whose parts only limit keeps or drops whole candidates, so each occurrence it keeps spans its cadence, as it would without the rule: the Monday hours of an hourly recurrence are hours, and the January weeks of a weekly one are weeks. A §12.10 window expands.

  ### Arguments

  * `repeat_rule` is either `nil` or a `%Tempo{}` whose `:time` holds `[selection: [...]]`, followed by any units that refine every date the selection picks, as for `apply/4`. A rule with such units expands.

  * `freq` is the enclosing `FREQ` atom, as for `apply/4`.

  ### Returns

  * `true` when a part of the rule expands at `freq`.

  * `false` otherwise.

  ### Examples

      iex> the_15th = %Tempo{time: [selection: [day: 15]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.expands?(the_15th, :month)
      true

      iex> mondays = %Tempo{time: [selection: [day_of_week: 1]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.expands?(mondays, :hour)
      false

  """
  @spec expands?(rule() | nil, atom()) :: boolean()
  def expands?(%Tempo{time: [{:selection, _selection}, _unit | _units]}, _freq), do: true

  def expands?(%Tempo{time: [selection: selection]}, freq) do
    case split_window(selection) do
      {_scope, %Interval{}, _within} ->
        true

      :none ->
        {_years, parts} = Keyword.pop(selection, :year)
        parts |> Enum.sort_by(&application_order_key/1) |> any_part_expands?(freq, parts)
    end
  end

  def expands?(_repeat_rule, _freq), do: false

  @doc """
  Returns where a walk goes on from when a part of a rule drops a candidate with the candidates after it.

  A part that limits keeps or drops a candidate by a unit of its start: its month, its day, its hour. A candidate it drops is dropped with every candidate after it until that unit is one the part names, so a walk that learns that here passes over them without asking of each. `FREQ=MINUTELY;BYHOUR=9` drops the minute 00:00 by its hour, and with it every minute until 09:00.

  ### Arguments

  * `candidate` is a `t:Tempo.Interval.t/0`, the candidate a walk has reached.

  * `repeat_rule` is either `nil` or a `%Tempo{}` whose `:time` holds `[selection: [...]]`, as for `apply/4`.

  * `freq` is the enclosing `FREQ` atom, as for `apply/4`.

  ### Returns

  * `{:on, unit, value}` when the coarsest part that drops the candidate names a later value of `unit` in the period the candidate is in: the walk goes on from where the candidate's `unit` is `value`.

  * `{:in_days, days}` when that part names days of the week or weeks of the year: the walk goes on from the start of the day that many days on.

  * `{:on_day, month, day}` when that part names days of the year: the walk goes on from the start of that month and day of the candidate's year.

  * `{:next, unit}` when it names none: the walk goes on from the start of the next `unit`, a year, a month, a day, an hour or a minute.

  * `nil` when no such part drops the candidate, which may be an occurrence, as `apply/4` says.

  ### Examples

      iex> midnight = %Tempo.Interval{from: ~o"2026-06-15T00:00", to: ~o"2026-06-15T00:01"}
      iex> at_nine = %Tempo{time: [selection: [hour: 9]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.rules_out(midnight, at_nine, :minute)
      {:on, :hour, 9}

      iex> ten = %Tempo.Interval{from: ~o"2026-06-15T10:00", to: ~o"2026-06-15T10:01"}
      iex> at_nine = %Tempo{time: [selection: [hour: 9]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.rules_out(ten, at_nine, :minute)
      {:next, :day}

      iex> nine = %Tempo.Interval{from: ~o"2026-06-15T09:00", to: ~o"2026-06-15T09:01"}
      iex> at_nine = %Tempo{time: [selection: [hour: 9]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.rules_out(nine, at_nine, :minute)
      nil

  """
  @spec rules_out(Interval.t(), rule() | nil, atom()) ::
          {:on, atom(), integer()}
          | {:in_days, pos_integer()}
          | {:on_day, pos_integer(), pos_integer()}
          | {:next, atom()}
          | nil
  def rules_out(
        %Interval{from: %Tempo{calendar: calendar}} = candidate,
        %Tempo{time: [{:selection, selection} | _units], calendar: rule_calendar} = rule,
        freq
      ) do
    if passes_over?(rule, freq) and not week_calendar?(calendar) do
      selection
      |> days_of_week_in_candidate_calendar(rule_calendar, candidate)
      |> coarsest_part_ruling_out(dated(candidate), freq)
    end
  end

  def rules_out(_candidate, _repeat_rule, _freq), do: nil

  @doc """
  Returns whether a rule has a part that drops a candidate with the candidates after it, so that `rules_out/3` can have an answer.

  ### Arguments

  * `repeat_rule` is either `nil` or a `%Tempo{}` whose `:time` holds `[selection: [...]]`, as for `apply/4`.

  * `freq` is the enclosing `FREQ` atom, as for `apply/4`.

  ### Returns

  * `true` for a rule of days, hours, minutes or seconds with a part that limits by a coarser unit, or by the unit it steps by, and no §12.10 window.

  * `false` otherwise.

  ### Examples

      iex> at_nine = %Tempo{time: [selection: [hour: 9]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.passes_over?(at_nine, :minute)
      true

      iex> at_nine = %Tempo{time: [selection: [hour: 9]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.passes_over?(at_nine, :day)
      false

      iex> in_june = %Tempo{time: [selection: [month: 6]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.passes_over?(in_june, :week)
      false

  """
  @spec passes_over?(rule() | nil, atom()) :: boolean()
  def passes_over?(%Tempo{time: [{:selection, selection} | _units]}, freq)
      when freq in [:day, :hour, :minute, :second] do
    split_window(selection) == :none and
      Enum.any?(selection, &(limit_held_to(&1, freq, selection) != nil))
  end

  def passes_over?(_repeat_rule, _freq), do: false

  @doc false
  # Whether a selection has a part that is counted in a date: a day of a
  # month or of a year, a week, a weekday, an event, a window, or a month
  # counted from the end. A candidate with no year has no date to count them
  # in, so a recurrence that starts with none cannot resolve such a rule.
  # Months as they are written, the hours, minutes and seconds of a day and
  # a position need none.
  @spec needs_a_date?(keyword()) :: boolean()
  def needs_a_date?(selection) when is_list(selection),
    do: Enum.any?(selection, &part_needs_a_date?/1)

  @parts_counted_in_a_date [
    :traditional_month,
    :week,
    :calendar_week,
    :week_of_month,
    :day_of_year,
    :event,
    :day,
    :nearest_weekday,
    :or_day,
    :day_of_week,
    :byday,
    :interval
  ]

  @doc false
  # A recurrence, or a value that holds a selection, with the selection as it
  # is resolved in its period. In a year a day with no month is a day of the
  # year (`days_of_year_where_no_month/1`), and in a month a week is a week
  # of the month (`:week_of_month`, a part no value is written with). Every
  # reader of a rule asks here, so the occurrences, the RRULE written and
  # the words of `Tempo.explain/1` are of one reading.
  #
  # A recurrence that steps by years resolves its rule in a year, and where
  # its start names a month (a date, a month of a year) the day is that
  # month's: the rule takes from its start what it does not say (ISO 8601-2
  # §13.6.3). A start that is a year, and no start, give it no month. A value
  # resolves its selection in a year where the units before it are a year, or
  # there are none. A calendar of weeks has no months, and a selection in one
  # is as it was.
  @spec read_in_its_period(value) :: value when value: term()
  def read_in_its_period(
        %Interval{
          duration: %Tempo.Duration{time: [{:year, _count} | _finer]},
          repeat_rule: %Tempo{time: [{:selection, selection} | units]} = rule
        } = recurrence
      ) do
    if gives_no_month?(counted_from(recurrence), rule),
      do: %{recurrence | repeat_rule: %{rule | time: [{:selection, in_year(selection)} | units]}},
      else: recurrence
  end

  def read_in_its_period(
        %Interval{
          duration: %Tempo.Duration{time: [{:month, _count} | _finer]},
          repeat_rule: %Tempo{time: [{:selection, selection} | units]} = rule
        } = recurrence
      ) do
    if gives_no_day?(counted_from(recurrence), rule),
      do: %{recurrence | repeat_rule: %{rule | time: [{:selection, in_month(selection)} | units]}},
      else: recurrence
  end

  def read_in_its_period(%Tempo{time: time, calendar: calendar} = value) when is_list(time) do
    case Enum.split_while(time, &(not match?({:selection, _selection}, &1))) do
      {context, [{:selection, selection} | trailing]} ->
        read = in_period_of(context, selection, week_calendar?(calendar))
        %{value | time: context ++ [{:selection, read} | trailing]}

      {_time, []} ->
        value
    end
  end

  def read_in_its_period(value), do: value

  # What a recurrence is counted from: its start, and its end where it is
  # written to one (`R3/P1M/2019-03-31/FL15DN`), which stands where a start
  # does.
  defp counted_from(%Interval{from: :undefined, to: %Tempo{} = to}), do: to
  defp counted_from(%Interval{from: from}), do: from

  # A calendar of weeks has no months, and a selection in one is as it was.
  defp in_period_of(_context, selection, true), do: selection

  defp in_period_of(context, selection, false) do
    cond do
      a_year_or_none?(context) -> in_year(selection)
      names_a_month?(context) -> in_month(selection)
      true -> selection
    end
  end

  # A week beside the month it is written with is a week of that month
  # (decided 2026-10-08): `L6M2WN` in a year is the second week of June, as
  # `2026Y6ML2WN` is. It was a week of the year with its month passed over.
  # A week after a §12.10 window is asked of the window's days, and is the
  # week of the year each is in, as it was.
  defp in_year(selection) do
    selection = days_of_year_where_no_month(selection)

    if List.keymember?(selection, :month, 0) and not List.keymember?(selection, :interval, 0),
      do: in_month(selection),
      else: selection
  end

  defp a_year_or_none?([]), do: true
  defp a_year_or_none?([{:year, _years}]), do: true
  defp a_year_or_none?(_finer_context), do: false

  defp a_month?(context), do: match?({:month, _months}, List.last(context))

  # A value written with its month, to the month or to a day or a time of
  # day in it: a week selected from it is a week of that month (decided
  # 2026-10-08), which keeps a day where the week holds it.
  defp names_a_month?(context), do: List.keymember?(context, :month, 0)

  # A week resolved in a month is a week of the month, which the calendar
  # numbers (decided 2026-10-07): the `W` of a value whose selection follows
  # a month (`2026Y6ML2WN`), and of a rule that steps by months from a
  # month, a year or no start. A rule that steps by months from a date has a
  # day for each candidate, as RFC 5545's has, and its week keeps or drops
  # that day by its week of the year. The two are told apart here, once, and
  # the rule as it is read says which it is.
  defp in_month(selection), do: Enum.map(selection, &week_of_the_month/1)

  defp week_of_the_month({:week, weeks}), do: {:week_of_month, weeks}
  defp week_of_the_month(part), do: part

  @doc false
  # `BYWEEKNO` counts the weeks of a year (RFC 5545 §3.3.10). A rule read
  # from an RRULE that has no start on a date is resolved in its period,
  # where a week beside a month, or in a rule that steps by months, is a
  # week of that month (`read_in_its_period/1`), which an RRULE cannot say.
  # It is refused where it is read: it was answered with the week of the
  # month, and a yearly rule with the week of the year and its month passed
  # over.
  @spec week_number_of_a_year(Interval.t()) :: :ok | {:error, {:byweekno_without_a_date, term()}}
  def week_number_of_a_year(%Interval{repeat_rule: %Tempo{}} = recurrence) do
    %Interval{repeat_rule: %Tempo{time: [{:selection, read} | _units]}} =
      read_in_its_period(recurrence)

    case List.keyfind(read, :week_of_month, 0) do
      {:week_of_month, weeks} -> {:error, {:byweekno_without_a_date, weeks}}
      nil -> :ok
    end
  end

  def week_number_of_a_year(%Interval{}), do: :ok

  @doc false
  # A week of the calendar's own numbering (`w`) is a week of its year, and
  # a selection resolved in a month has no week of a year to give: in a
  # value whose selection follows a month (`2026Y6ML2wN`), and as the rule
  # of a recurrence that steps by months from a month, a year, a set of them
  # or no start. It is refused, and for good (decided 2026-10-08): a week of
  # a month is written `W`. It was refused as not yet built, since what the
  # resolver gave for it was the whole month where its first day was in the
  # week of that number. `selection` is the rule's parts and `value` what
  # they are resolved in, which the error names.
  @spec calendar_week_in_its_year(keyword(), Tempo.t() | Interval.t()) ::
          :ok | {:error, ConversionError.t()}
  def calendar_week_in_its_year(selection, value) when is_list(selection) do
    if names_a_calendar_week?(selection) and resolved_in_a_month?(value),
      do: {:error, ConversionError.exception(value: value, reason: :calendar_week_in_month)},
      else: :ok
  end

  defp names_a_calendar_week?(selection), do: Enum.any?(selection, &calendar_week_part?/1)

  defp calendar_week_part?({:selection, nested}) when is_list(nested),
    do: names_a_calendar_week?(nested)

  defp calendar_week_part?({:calendar_week, _weeks}), do: true
  defp calendar_week_part?(_part), do: false

  # Whether a selection is resolved in a month, as `read_in_its_period/1`
  # has it: the rule of a recurrence that steps by months and whose start
  # gives it no day, and the selection of a value after its month.
  defp resolved_in_a_month?(
         %Interval{
           duration: %Tempo.Duration{time: [{:month, _count} | _finer]},
           repeat_rule: %Tempo{} = rule
         } = recurrence
       ),
       do: gives_no_day?(counted_from(recurrence), rule)

  defp resolved_in_a_month?(%Tempo{time: time, calendar: calendar}) when is_list(time) do
    context = Enum.take_while(time, &(not match?({:selection, _selection}, &1)))
    not week_calendar?(calendar) and a_month?(context)
  end

  defp resolved_in_a_month?(_another), do: false

  defp gives_no_day?(%Tempo{time: time, calendar: calendar}, _rule) when is_list(time),
    do: not week_calendar?(calendar) and Enum.all?(time, &month_unit?/1)

  defp gives_no_day?(%Tempo.Set{set: [_ | _] = starts}, rule),
    do: Enum.all?(starts, &gives_no_day?(&1, rule))

  defp gives_no_day?(%Tempo.Range{first: first, last: last}, rule),
    do: gives_no_day?(first, rule) and gives_no_day?(last, rule)

  defp gives_no_day?(no_start, %Tempo{calendar: calendar}) when no_start in [nil, :undefined],
    do: not week_calendar?(calendar)

  defp gives_no_day?(_another_start, _rule), do: false

  # A start written to its month, or to a span of years, and no finer.
  defp month_unit?({:month, _months}), do: true
  defp month_unit?(unit), do: year_unit?(unit)

  defp gives_no_month?(%Tempo{time: time, calendar: calendar}, _rule) when is_list(time),
    do: not week_calendar?(calendar) and Enum.all?(time, &year_unit?/1)

  defp gives_no_month?(%Tempo.Set{set: [_ | _] = years}, rule),
    do: Enum.all?(years, &gives_no_month?(&1, rule))

  defp gives_no_month?(%Tempo.Range{first: first, last: last}, rule),
    do: gives_no_month?(first, rule) and gives_no_month?(last, rule)

  defp gives_no_month?(no_start, %Tempo{calendar: calendar}) when no_start in [nil, :undefined],
    do: not week_calendar?(calendar)

  defp gives_no_month?(_another_start, _rule), do: false

  # A start written to its year, or to a span of years, and no finer.
  defp year_unit?({unit, _value}), do: unit in [:year, :decade, :century]
  defp year_unit?(_other), do: false

  @doc false
  # A day with no month, selected in a year, is a day of the year, as the
  # value `2026Y45D` is read: `L45DN` in a year is 14 February, and `L-1DN`
  # its last day. A selection that names the day's month, a week, a day of
  # the year or a computed event places the day already, and is as it was.
  # The start of a §12.10 window in the selection is read the same way.
  @spec days_of_year_where_no_month(keyword()) :: keyword()
  def days_of_year_where_no_month(selection) when is_list(selection) do
    if Enum.any?(selection, &places_a_day?/1),
      do: selection,
      else: Enum.map(selection, &day_of_the_year/1)
  end

  @places_a_day [:month, :traditional_month, :week, :calendar_week, :day_of_year, :event]

  defp places_a_day?({part, _value}), do: part in @places_a_day
  defp places_a_day?(_other), do: false

  defp day_of_the_year({:day, days}), do: {:day_of_year, days}

  defp day_of_the_year({:interval, %Interval{from: %Tempo{time: time} = start} = window}),
    do: {:interval, %{window | from: %{start | time: window_start_in_year(time)}}}

  defp day_of_the_year(part), do: part

  defp window_start_in_year([{:selection, selection} | units]),
    do: [{:selection, days_of_year_where_no_month(selection)} | units]

  defp window_start_in_year(time), do: time

  defp part_needs_a_date?({part, _value}) when part in @parts_counted_in_a_date, do: true
  defp part_needs_a_date?({:month, months}), do: counts_from_end?(months)
  defp part_needs_a_date?(_part), do: false

  defp counts_from_end?(index) when is_integer(index), do: index < 0
  defp counts_from_end?(%Range{first: first, last: last}), do: first < 0 or last < 0

  defp counts_from_end?(indices) when is_list(indices),
    do: Enum.any?(indices, &counts_from_end?/1)

  defp counts_from_end?(_other), do: false

  # The units after a selection apply to every date it picks (ISO 8601-2
  # §12.11.2): the selection, its position applied last of all, picks the
  # day, and `T9H` then makes it 09:00 that day (§12.9 Example 5).
  #
  # Where no more than so many occurrences are asked for, each date is
  # given every unit before the next, and what that makes is counted as it
  # is made, as the times of day of a selection are (`counted_parts/4`): a
  # time of day after a position was every second of each day it picked,
  # made before any was counted.
  defp with_units({:error, _reason} = error, _units, _keep_span?, _most), do: error
  defp with_units(occurrences, [], _keep_span?, _most), do: occurrences

  defp with_units(occurrences, units, keep_span?, nil) do
    Enum.reduce(units, occurrences, fn {unit, values}, acc ->
      expand_time(acc, unit, values, keep_span?)
    end)
  end

  defp with_units(occurrences, units, keep_span?, most) do
    with :more <- each_with_units(occurrences, units, {keep_span?, most, :made}, {[], 0}),
         :more <- each_with_units(occurrences, units, {keep_span?, most, :shown}, {[], 0}) do
      {:error, {:more_than, most}}
    else
      {made, _count} -> Enum.reverse(made)
    end
  end

  defp each_with_units([], _units, _asked, made), do: made

  defp each_with_units([occurrence | others], units, asked, made) do
    case with_each_unit(occurrence, units, asked, made) do
      :more -> :more
      made -> each_with_units(others, units, asked, made)
    end
  end

  defp with_each_unit(occurrence, [], {_keep_span?, most, counted}, {made, count} = so_far) do
    cond do
      counted == :shown and starts_on_a_reading_skipped?(occurrence) -> so_far
      count == most -> :more
      true -> {[occurrence | made], count + 1}
    end
  end

  defp with_each_unit(
         occurrence,
         [{unit, values} | units],
         {keep_span?, _most, _counted} = asked,
         made
       ) do
    [occurrence]
    |> expand_time(unit, values, keep_span?)
    |> each_with_units(units, asked, made)
  end

  # A calendar of weeks numbers a date by its year, its week and its day in
  # the week, and Calendrical reads that week as the date's month, a week's
  # seven days as the month's days. A selection in such a calendar is
  # resolved in those terms — a week (`W`, `w`) the calendar's month, a
  # weekly period a month's — and what it selects is written back as weeks,
  # so `FL2KN` picks each week's Tuesday and `L1K1IN` the first Monday of the
  # week year.
  # A selection's days of the week are counted in the calendar of the rule
  # that holds them: the calendar's own week in a calendar of weeks, and ISO
  # 8601's in a calendar of months. A rule given to `Tempo.select/2` can be
  # written in another calendar than the candidate it is resolved in, and
  # where the two start their weeks on different days its days are written
  # again as the days the candidate's calendar gives the same weekdays: the
  # third day of a rule written in the Gregorian calendar, Wednesday, is the
  # fourth of a week that starts on Sunday.
  defp days_of_week_in_candidate_calendar(
         selection,
         rule_calendar,
         %Interval{from: %Tempo{calendar: calendar}}
       ) do
    days_of_week_in_calendar(
      selection,
      Compare.effective_calendar(rule_calendar),
      Compare.effective_calendar(calendar)
    )
  end

  defp days_of_week_in_candidate_calendar(selection, _rule_calendar, _candidate), do: selection

  @doc false
  # A selection's days of the week, counted in the calendar `from`, as the
  # days the calendar `to` gives the same weekdays. Two calendars that start
  # their weeks on the same day count them alike, and the selection is as it
  # was.
  @spec days_of_week_in_calendar(keyword(), module(), module()) :: keyword()
  def days_of_week_in_calendar(selection, from, to) do
    if from == to or same_week_start?(from, to),
      do: selection,
      else: Enum.map(selection, &day_of_week_in_calendar(&1, from, to))
  end

  defp same_week_start?(from, to) do
    UnitValues.iso_weekday_from_day_of_week(1, from) ==
      UnitValues.iso_weekday_from_day_of_week(1, to)
  end

  defp day_of_week_in_calendar({:day_of_week, days}, from, to) do
    case UnitValues.in_period(:day_of_week, [], from) do
      {:ok, week} ->
        {:day_of_week, days |> UnitValues.named(week) |> Enum.map(&same_weekday(&1, from, to))}

      {:error, _cannot_count} ->
        {:day_of_week, days}
    end
  end

  defp day_of_week_in_calendar({:selection, nested}, from, to),
    do: {:selection, Enum.map(nested, &day_of_week_in_calendar(&1, from, to))}

  defp day_of_week_in_calendar(entry, _from, _to), do: entry

  defp same_weekday(day, from, to) do
    day
    |> UnitValues.iso_weekday_from_day_of_week(from)
    |> UnitValues.day_of_week_from_iso_weekday(to)
  end

  defp in_calendar_terms(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         selection,
         freq,
         select
       ) do
    if week_calendar?(calendar) do
      candidate
      |> map_endpoints(&week_unit_as_month/1)
      |> select.(Enum.map(selection, &week_selector_as_month/1), week_period_as_month(freq))
      |> in_week_terms()
    else
      select.(dated(candidate), selection, freq)
    end
  end

  defp in_calendar_terms(candidate, selection, freq, select),
    do: select.(candidate, selection, freq)

  # A candidate written by its week in a calendar of months (`2026Y25W`, the
  # start of a recurrence that steps by weeks from a week) is resolved by its
  # dates, as a week's days are dates wherever a value gives one: a part asks
  # a candidate its month, its day and its week by its date.
  defp dated(%Interval{from: from, to: to} = candidate),
    do: %{candidate | from: week_as_its_first_day(from), to: week_as_its_first_day(to)}

  defp week_as_its_first_day(%Tempo{time: [{:year, year}, {:week, week} | finer]} = endpoint)
       when is_integer(year) and is_integer(week) do
    Validation.calendar_date_from_week_date(%{
      endpoint
      | time: with_day_of_week(endpoint.time, finer)
    })
  end

  defp week_as_its_first_day(endpoint), do: endpoint

  defp with_day_of_week(time, [{:day_of_week, _day} | _finer]), do: time

  defp with_day_of_week([year, week | finer], _no_day_of_week),
    do: [year, week, {:day_of_week, 1} | finer]

  defp in_week_terms({:error, _reason} = error), do: error

  defp in_week_terms(occurrences),
    do: Enum.map(occurrences, &map_endpoints(&1, fn unit -> month_unit_as_week(unit) end))

  defp week_calendar?(calendar) do
    Code.ensure_loaded?(calendar) and function_exported?(calendar, :calendar_base, 0) and
      calendar.calendar_base() == :week
  end

  defp map_endpoints(%Interval{from: from, to: to} = interval, map_unit),
    do: %{interval | from: map_units(from, map_unit), to: map_units(to, map_unit)}

  defp map_units(%Tempo{time: time} = tempo, map_unit) when is_list(time),
    do: %{tempo | time: Enum.map(time, map_unit)}

  defp map_units(endpoint, _map_unit), do: endpoint

  defp week_unit_as_month({:week, week}), do: {:month, week}
  defp week_unit_as_month({:day_of_week, day}), do: {:day, day}
  defp week_unit_as_month(unit), do: unit

  defp month_unit_as_week({:month, week}), do: {:week, week}
  defp month_unit_as_week({:day, day}), do: {:day_of_week, day}
  defp month_unit_as_week(unit), do: unit

  defp week_selector_as_month({week, weeks}) when week in [:week, :calendar_week],
    do: {:month, weeks}

  defp week_selector_as_month(selector), do: selector

  defp week_period_as_month(:week), do: :month
  defp week_period_as_month(freq), do: freq

  defp selection_context(options) do
    origin_day =
      case Keyword.get(options, :origin_day) do
        day when is_integer(day) -> [origin_day: day]
        _other -> []
      end

    keep_span = if Keyword.get(options, :keep_span) == true, do: [keep_span: true], else: []
    origin_day ++ keep_span
  end

  # The most occurrences the parts are counted to as they are made
  # (`counted_parts/4`): the most asked for (`:at_most`), and none where
  # what the parts make is not what the rule gives. A position (`I`) picks
  # among every occurrence of the period, a §12.10 window among the days of
  # each window, and the units after a selection are made from what it
  # picks: those are counted once they are all made (`no_more_than/2`).
  #
  # It is handed to the resolver beside the selection, and does not ride in
  # it as the origin day does: a part asks what else the selection holds
  # (`picks_within_a_week?/1`), and would take it for a part.
  defp counted_to(options, selection, units) do
    case at_most(options) do
      nil -> nil
      most -> if units == [] and not picked_among_all?(selection), do: most
    end
  end

  # The most occurrences asked for, a whole number, or `nil` for all.
  defp at_most(options) do
    case Keyword.get(options, :at_most) do
      most when is_integer(most) and most >= 0 -> most
      _none_asked -> nil
    end
  end

  defp picked_among_all?(selection),
    do: List.keymember?(selection, :instance, 0) or List.keymember?(selection, :interval, 0)

  defp no_more_than(occurrences, most)
       when is_list(occurrences) and is_integer(most) and length(occurrences) > most,
       do: {:error, {:more_than, most}}

  defp no_more_than(occurrences_or_an_error, _most), do: occurrences_or_an_error

  ## ------------------------------------------------------------
  ## Selection dispatch
  ## ------------------------------------------------------------

  # RFC 5545 §3.3.10 prescribes a strict application order for
  # BY-rules: BYMONTH → BYWEEKNO → BYYEARDAY → BYMONTHDAY →
  # BYDAY → BYHOUR → BYMINUTE → BYSECOND → BYSETPOS. BYSETPOS
  # is *always* last, regardless of where it sits in the input
  # AST. We sort the selection at apply time so the resolver is
  # robust to whatever order the parser/adapter emitted.
  #
  # The full `selection` list is threaded to each handler so
  # BYDAY (and future co-dependent rules) can consult sibling
  # tokens — e.g. Note 1/2 downgrades BYDAY from EXPAND to LIMIT
  # when BYMONTHDAY or BYYEARDAY is co-present.
  defp apply_selection(candidate, selection, freq, most \\ nil) do
    wkst = Keyword.get(selection, :wkst, 1)

    case split_window(selection) do
      {scope, %Interval{} = window, within} ->
        apply_windowed_selection(candidate, scope, window, within, freq, wkst)

      :none ->
        resolve_in_period(candidate, selection, freq, wkst, most)
    end
  end

  # A year (`Y`) limits the periods a selection resolves in, as a recurrence
  # domain's years do: a period that starts in a listed year keeps every date
  # it selects, wherever a week or a window carries it, and a period in any
  # other year selects nothing. (A year among a window's own selectors keeps
  # the window's days in that year instead.)
  defp resolve_in_period(candidate, selection, freq, wkst, most) do
    {years, selection} = Keyword.pop(selection, :year)

    if period_selected?(candidate, years),
      do: resolve_parts(candidate, selection, freq, wkst, most),
      else: []
  end

  # Each part in the order it applies, the scope it leaves handed to the
  # next, until one has no answer.
  defp resolve_parts(candidate, selection, freq, wkst, most) do
    parts =
      selection
      |> Enum.sort_by(&application_order_key/1)
      |> limits_after_the_days_made(freq, selection)
      |> weekday_with_its_position()

    resolved(
      Enum.split_while(parts, &(not match?({:instance, _positions}, &1))),
      most,
      {[candidate], freq},
      {selection, wkst}
    )
  end

  # The parts with no position among them, counted where their caller asks
  # for no more than so many; and a position with the parts before it, which
  # make the candidates it picks among, and those after it.
  #
  # A position picks among every candidate of its period, so every one is
  # made for it, and a period may hold no more of them than Tempo gives of
  # any value at once (`@candidates_at_once`, decided 2026-10-08): the first
  # of every minute of a year was half a million minutes made to give one,
  # and of every second, 29 million, did not come to an end. They are
  # counted as they are made, and a period with more is refused.
  defp resolved({parts, []}, most, start, asked_with) when is_integer(most),
    do: parts |> counted_parts({most, :shown}, start, asked_with) |> selected()

  defp resolved({parts, []}, _every_occurrence, start, {selection, wkst}),
    do: parts |> each_part(start, selection, wkst) |> selected()

  defp resolved({made, picked}, _most, start, {selection, wkst} = asked_with) do
    case counted_parts(made, {@candidates_at_once, :made}, start, asked_with) do
      {:error, _reason} = error ->
        error

      candidates_at_scope ->
        picked |> each_part(candidates_at_scope, selection, wkst) |> selected()
    end
  end

  defp each_part(parts, candidates_at_scope, selection, wkst),
    do: Enum.reduce_while(parts, candidates_at_scope, &resolve_part(&1, &2, selection, wkst))

  # A weekday with a position straight after it is the weekday at that
  # position in its period: `L1K1IN` in a month is its first Monday, and
  # `L4K-1IN` in a year its last Thursday, the shape a holiday is written
  # in. The two are applied as one part (`nth_weekdays/5`), which asks
  # Calendrical for that day where there is one period to find it in. Each
  # day of the period was asked its day of the week, every one that
  # matched was made an occurrence, and the position picked among them.
  defp weekday_with_its_position([{:day_of_week, day}, {:instance, positions} | parts])
       when is_integer(day) do
    if positions |> List.wrap() |> Enum.all?(&(is_integer(&1) and &1 != 0)),
      do: [{:weekday_at, {day, List.wrap(positions)}} | parts],
      else: [{:day_of_week, day}, {:instance, positions} | parts]
  end

  defp weekday_with_its_position([part | parts]), do: [part | weekday_with_its_position(parts)]
  defp weekday_with_its_position([]), do: []

  # A time of day multiplies what the parts before it made, each day by the
  # hours named, each hour by the minutes and each minute by the seconds: a
  # selection of forty characters names 29 million seconds of a year, and
  # each part applied to every candidate at once makes them all before any
  # is counted. Where no more than so many occurrences are asked for, the
  # parts from the first time of day on are applied to one candidate at a
  # time, each of what a part gives through the parts after it before the
  # next, and an occurrence is counted as it is made: the walk stops at the
  # first one past the most. What it gives short of that is what the parts
  # give applied to all at once, in the same order, each being asked of a
  # candidate alone.
  #
  # A reading the clock skips is dropped once the parts are through
  # (`on_readings_the_clock_shows/1`) and is no occurrence, so a count of
  # occurrences (`:shown`) that passes the most is taken again of the
  # readings the clock shows. A position's candidates (`:made`) are each one
  # of them, whatever the clock shows.
  #
  # What is made is given with the scope the parts leave, as `each_part/4`
  # gives it, for the parts after them.
  defp counted_parts(parts, most_counted, candidates_at_scope, {selection, wkst} = asked_with) do
    {dates, times} = Enum.split_while(parts, &(not time_of_day?(&1)))

    case each_part(dates, candidates_at_scope, selection, wkst) do
      {:error, _reason} = error -> error
      {candidates, scope} -> counted(candidates, times, scope, most_counted, asked_with)
    end
  end

  defp time_of_day?({unit, _values}), do: unit in [:hour, :minute, :second]

  defp counted(candidates, parts, scope, {most, counted}, asked_with) do
    with :more <- each_through(candidates, parts, scope, {most, :made, asked_with}, {[], 0}),
         :more <- recounted(counted, candidates, parts, scope, {most, asked_with}) do
      {:error, {:more_than, most}}
    else
      {:error, _reason} = error -> error
      {made, _count} -> {Enum.reverse(made), Enum.reduce(parts, scope, &scope_after/2)}
    end
  end

  defp recounted(:made, _candidates, _parts, _scope, _asked), do: :more

  defp recounted(:shown, candidates, parts, scope, {most, asked_with}),
    do: each_through(candidates, parts, scope, {most, :shown, asked_with}, {[], 0})

  # What is made so far, with one candidate after another through the parts:
  # the occurrences, the latest first, and how many they are, or `:more`.
  defp each_through([], _parts, _scope, _asked, made), do: made

  defp each_through([candidate | others], parts, scope, asked, made) do
    case through(candidate, parts, scope, asked, made) do
      {_occurrences, _count} = made -> each_through(others, parts, scope, asked, made)
      more_or_an_error -> more_or_an_error
    end
  end

  defp through(candidate, [], _scope, {most, counted, _asked_with}, {occurrences, count} = made) do
    cond do
      counted == :shown and starts_on_a_reading_skipped?(candidate) -> made
      count == most -> :more
      true -> {[candidate | occurrences], count + 1}
    end
  end

  defp through(
         candidate,
         [part | parts],
         scope,
         {_most, _counted, {selection, wkst}} = asked,
         made
       ) do
    case apply_entry(part, [candidate], scope, selection, wkst) do
      {:error, _reason} = error -> error
      given -> each_through(given, parts, scope_after(part, scope), asked, made)
    end
  end

  # A weekly or a monthly candidate stands for its week or its month, and a
  # part that makes days in it can make them in another month, or another
  # week, than the candidate's own day is in: the Tuesday of a week whose
  # Saturday is in April can be in March. An occurrence satisfies every part
  # of its rule (RFC 5545 §3.3.10), so a month that limits a weekly rule, and
  # a week that limits a monthly one, is asked of the days made and not of
  # the candidate they are made from: it applies after the last part that
  # makes days. With no such part the candidate is the occurrence, and the
  # order is as it was.
  defp limits_after_the_days_made(parts, scope, selection) when scope in [:week, :month] do
    {limits, others} = Enum.split_with(parts, &limits_by_another_period?(&1, scope))

    {later, made} =
      others |> Enum.reverse() |> Enum.split_while(&(not makes_days?(&1, scope, selection)))

    if limits == [] or made == [],
      do: parts,
      else: Enum.reverse(made) ++ limits ++ Enum.reverse(later)
  end

  defp limits_after_the_days_made(parts, _scope, _selection), do: parts

  defp limits_by_another_period?({unit, _value}, :week), do: unit in [:month, :traditional_month]
  defp limits_by_another_period?({unit, _value}, :month), do: unit in [:week, :calendar_week]

  # A time of day is made on the day it is given, and makes no day.
  defp makes_days?({unit, _value}, _scope, _selection) when unit in [:hour, :minute, :second],
    do: false

  defp makes_days?(part, scope, selection), do: role(part, scope, selection) != :limit

  defp resolve_part(entry, {candidates, scope}, selection, wkst) do
    case apply_entry(entry, candidates, scope, selection, wkst) do
      {:error, _reason} = error -> {:halt, error}
      selected -> {:cont, {selected, scope_after(entry, scope)}}
    end
  end

  defp selected({:error, _reason} = error), do: error
  defp selected({occurrences, _scope}), do: occurrences

  defp period_selected?(_candidate, nil), do: true
  defp period_selected?(candidate, years), do: year_selected?(year_of(candidate), years)

  # Once BYWEEKNO has expanded a YEARLY candidate into the days of its
  # weeks, the parts after it select among those days as they would for a
  # DAILY rule: BYDAY limits them (RFC 5545's special expand within the
  # week), BYYEARDAY and BYMONTHDAY intersect with them, and BYHOUR,
  # BYMINUTE and BYSECOND still expand each day.
  #
  # A week of a month hands its days on in the same way, whatever it is
  # resolved in.
  defp scope_after({:week, _weeks}, :year), do: :day
  defp scope_after({:calendar_week, _weeks}, :year), do: :day
  defp scope_after({:week_of_month, _weeks}, _scope), do: :day
  defp scope_after(_entry, scope), do: scope

  # The parts in the order and at the scope `resolve_in_period/5` applies
  # them: a BYWEEKNO that expands a year hands its days on at day scope.
  defp any_part_expands?([], _scope, _selection), do: false

  defp any_part_expands?([part | rest], scope, selection) do
    role(part, scope, selection) != :limit or
      any_part_expands?(rest, scope_after(part, scope), selection)
  end

  # Split a selection around a §12.10 window: `{scope, window, within}` where
  # `scope` are the elements before it (coarser context, e.g. a month), and
  # `within` the elements after (the selectors that pick inside the window).
  defp split_window(selection) do
    case Enum.split_while(selection, fn {key, _value} -> key != :interval end) do
      {scope, [{:interval, %Interval{} = window} | within]} -> {scope, window, within}
      _other -> :none
    end
  end

  # ISO 8601-2 §12.10 "selection with a time interval": each date the inner
  # selection resolves to becomes the START of a window of the given duration,
  # and the `within` selectors pick INSIDE each window. `LLL2K2IN/P10DN4K2IN`
  # is "the 2nd Thursday within the ten days from the 2nd Tuesday". The `scope`
  # (e.g. `11M` in US Election Day) is folded into the inner resolution so the
  # window's start is found in the right context. The window's days are enumerated and
  # the `within` selectors applied at day scope, so a weekday LIMITs to matching
  # days and a position (`I`) picks the Nth of them.
  defp apply_windowed_selection(
         candidate,
         scope,
         %Interval{from: inner, duration: duration},
         within,
         freq,
         wkst
       ) do
    inner_selection = scope ++ inner_selection(inner)

    # `:origin_day`/`:keep_span`/`:wkst`/`:skip` are passthrough context, not
    # selectors, so they do not make a window non-terminal.
    selectors =
      Enum.reject(within, fn {key, _value} ->
        key in [:origin_day, :keep_span, :wkst, :skip]
      end)

    candidate
    |> apply_selection(inner_selection, freq)
    |> selected_in_windows(duration, selectors, wkst)
  end

  defp selected_in_windows({:error, _reason} = error, _duration, _selectors, _wkst), do: error

  # A terminal window (no inner selectors) is itself the occurrence: the
  # interval from the window's start for the given duration (§12.11.3 Example 1).
  defp selected_in_windows(starts, duration, [], _wkst),
    do: Enum.map(starts, fn start -> window_interval(start, duration) end)

  defp selected_in_windows(starts, duration, selectors, wkst) do
    each_candidate(starts, fn start ->
      case select_in_window(start, duration, selectors, wkst) do
        {:error, _reason} = error -> error
        occurrences -> {:ok, occurrences}
      end
    end)
  end

  # Selectors that pick days pick among the days of the window. Those that
  # pick a time of day pick it on every day the window touches, and a time is
  # the window's where it starts within it: of the twelve hours from a
  # Monday, 09:00 is that Monday's and 13:00 is none, and of the four hours
  # from 22:00, 01:00 is the next day's. A position (`I`) counts what is left.
  defp select_in_window(start, duration, selectors, wkst) do
    if Enum.any?(selectors, &picks_time_of_day?/1),
      do: select_times_in_window(start, duration, selectors, wkst),
      else: start |> window_days(duration, :whole) |> apply_window_selectors(selectors, wkst)
  end

  defp picks_time_of_day?({unit, _values}), do: unit in [:hour, :minute, :second]

  defp select_times_in_window(start, duration, selectors, wkst) do
    {positions, parts} = Enum.split_with(selectors, &match?({:instance, _positions}, &1))

    case start
         |> window_days(duration, :touched)
         |> apply_window_selectors(parts, selectors, wkst) do
      {:error, _reason} = error ->
        error

      times ->
        times
        |> starting_in_window(start, duration)
        |> apply_window_selectors(positions, selectors, wkst)
    end
  end

  defp starting_in_window(occurrences, %Interval{from: %Tempo{} = from}, duration) do
    case Tempo.shift(from, duration) do
      %Tempo{} = shifted ->
        {lo, hi} = window_ends(from, shifted)
        Enum.filter(occurrences, &starts_within?(&1, lo, hi))

      _no_end ->
        occurrences
    end
  end

  defp starts_within?(%Interval{from: %Tempo{} = from}, lo, hi) do
    match?({:ok, order} when order != :earlier, Compare.order(from, lo)) and
      match?({:ok, :earlier}, Compare.order(from, hi))
  end

  # Each candidate's occurrences in turn, or the first error one of them is.
  defp each_candidate(candidates, occurrences_of) do
    Enum.reduce_while(candidates, [], fn candidate, selected ->
      case occurrences_of.(candidate) do
        {:ok, occurrences} -> {:cont, selected ++ occurrences}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp inner_selection(%Tempo{time: [selection: selection]}), do: selection
  defp inner_selection(%Tempo{time: time}), do: time

  # Resolve the outer selectors within a window's enumerated days. Day scope
  # makes a weekday a LIMIT (keep matching days) and leaves the position (`I`)
  # to pick the Nth survivor.
  defp apply_window_selectors(day_candidates, outer, wkst),
    do: apply_window_selectors(day_candidates, outer, outer, wkst)

  # `selectors` are those of `outer` to apply, each reading the rest of
  # `outer` as the parts beside it.
  defp apply_window_selectors(day_candidates, selectors, outer, wkst) do
    selectors
    |> Enum.sort_by(&application_order_key/1)
    |> Enum.reduce_while(day_candidates, fn entry, candidates ->
      case apply_entry(entry, candidates, :day, outer, wkst) do
        {:error, _reason} = error -> {:halt, error}
        selected -> {:cont, selected}
      end
    end)
  end

  # Each day in the window `[start, start + duration)` (a negative duration
  # extends backward), as a day-resolution candidate in the start's calendar.
  # Half-open — `lo` the earlier of start and shifted endpoint, `hi` the
  # later — so a forward duration keeps the start and a backward one
  # excludes it. The `:whole` days are those from `lo` up to `hi`, and the one
  # day of a window within a day; the days `:touched` reach the day the
  # window ends within, for a time of day to be picked on.
  defp window_days(
         %Interval{from: %Tempo{calendar: calendar, time: time} = from} = start,
         %Tempo.Duration{} = duration,
         which
       ) do
    with {:ok, start_date} <- date_of(time, calendar),
         %Tempo{time: shifted_time} <- Tempo.shift(from, duration),
         {:ok, shifted_date} <- date_of(shifted_time, calendar) do
      {lo, hi} = window_bounds(start_date, shifted_date)

      days =
        for date <- window_dates(lo, hi, which) do
          {date.year, date.month, date.day, date}
        end

      swap_dates(start, days)
    else
      _ -> []
    end
  end

  # The dates from `lo` up to `hi`, each the day Calendrical gives after the
  # one before: not including `hi` for the whole days, and including it for
  # the days touched. A window within one day has that day.
  defp window_dates(lo, hi, which) do
    case {Compare.compare_days(lo, hi), which} do
      {:eq, _which} ->
        [lo]

      {_before, :whole} ->
        lo |> each_day_from() |> Enum.take_while(&(Compare.compare_days(&1, hi) == :lt))

      {_before, :touched} ->
        lo |> each_day_from() |> Enum.take_while(&(Compare.compare_days(&1, hi) != :gt))
    end
  end

  defp each_day_from(date), do: Stream.iterate(date, &Calendrical.next(&1, :day))

  # The days a part picks among in a weekly or a monthly candidate. A
  # candidate that is a whole week or month (a selection made in one, a
  # recurrence that starts at one) is its own days. One that is a day, as a
  # rule read from an RRULE has it, stands for the week or the month that
  # holds it: the days of that week from `wkst`, or of that month.
  defp days_of_period(candidate, scope, wkst) do
    case endpoint_shift(candidate) do
      days when is_integer(days) and days > 1 -> each_day(candidate)
      _a_day_or_less -> days_of_enclosing(candidate, scope, wkst)
    end
  end

  defp days_of_enclosing(candidate, :week, wkst) do
    case week_date_range(candidate, wkst) do
      nil ->
        [candidate]

      dates ->
        swap_dates(candidate, for({year, month, day, _weekday} <- dates, do: {year, month, day}))
    end
  end

  defp days_of_enclosing(%Interval{from: %Tempo{calendar: calendar}} = candidate, :month, _wkst) do
    with {year, month} <- enclosing_month(candidate),
         {:ok, days} <- UnitValues.in_period(:day, [year: year, month: month], calendar) do
      swap_dates(candidate, for(day <- each_value(days), do: {year, month, day}))
    else
      _no_month -> [candidate]
    end
  end

  # A candidate as each of its days: the days from the one it starts on up
  # to the one it ends on.
  defp each_day(%Interval{from: %Tempo{time: time, calendar: calendar}, to: to} = candidate) do
    with {:ok, first} <- date_of(time, calendar),
         {:ok, last} <- end_date_of(to, first, calendar) do
      days =
        for date <- window_dates(first, last, :whole), do: {date.year, date.month, date.day, date}

      swap_dates(candidate, days)
    else
      _no_one_date -> [candidate]
    end
  end

  defp end_date_of(%Tempo{time: time}, _first, calendar), do: date_of(time, calendar)
  defp end_date_of(_no_end, first, _calendar), do: {:ok, first}

  # Half-open `[lo, hi)`: `lo` is the earlier of start / shifted endpoint, `hi`
  # the later. A forward duration keeps the start; a backward one excludes it.
  defp window_bounds(%Date{} = start_date, %Date{} = shifted_date) do
    if Compare.compare_days(start_date, shifted_date) == :gt do
      {shifted_date, start_date}
    else
      {start_date, shifted_date}
    end
  end

  # The window `[start, start + duration)` as a single interval occurrence,
  # ordered so a backward duration gives `[start - duration, start)`. Its ends
  # are exact, so the four hours from 22:00 (`LT22HN/PT4H`) end at 02:00 the
  # next day.
  defp window_interval(%Interval{from: %Tempo{} = from} = start, %Tempo.Duration{} = duration) do
    case Tempo.shift(from, duration) do
      %Tempo{} = shifted ->
        {lo, hi} = window_ends(from, shifted)

        # Mark it windowed so the recurrence keeps its span instead of
        # resizing the occurrence down to one resolution unit.
        %{start | from: lo, to: hi, metadata: Map.put(start.metadata, :windowed, true)}

      _error ->
        start
    end
  end

  defp window_ends(%Tempo{time: from_time} = from, %Tempo{time: shifted_time} = shifted) do
    if Compare.compare_time(from_time, shifted_time) == :gt,
      do: {shifted, from},
      else: {from, shifted}
  end

  ## ------------------------------------------------------------
  ## The values a part names
  ## ------------------------------------------------------------

  # A part's value is a whole number, or a list of whole numbers and ranges:
  # a `{2..8}` set in the ISO 8601-2 grammar parses to a `Range` element
  # (`day: [2..8]`), where the RRULE adapter emits each number
  # (`day: [2, 3, …, 8]`). Either names the same values.
  #
  # What it names is read by `Tempo.UnitValues`, the one place where a count
  # from the end and a range are resolved: among the values the part's unit
  # takes in the candidate's period — the days of its month, the hours of a
  # day — in order and once each, so that the points an expansion makes come
  # in the order of time, as a position (`I`) and a recurrence's count take
  # them. A value the period lacks is passed over, as RFC 5545 §3.3.10
  # ignores an invalid date: the 31st of a month of thirty days, a
  # thirteenth month, hour 25.

  # The values a part names in the candidate's period, and none where the
  # candidate does not fix the period: an expansion makes no point it cannot
  # count, and a limit keeps none.
  defp counted_values(indices, unit, candidate) do
    case period_values(unit, candidate) do
      {:ok, valid} -> UnitValues.named(indices, valid)
      {:error, _reason} -> []
    end
  end

  # The values a part names in the candidate's period, or as they are
  # written where the candidate does not fix the period — a month with no
  # year to be in — among which a count from the end names none.
  defp values_named(indices, unit, candidate) do
    case period_values(unit, candidate) do
      {:ok, valid} -> UnitValues.named(indices, valid)
      {:error, _reason} -> indices |> List.wrap() |> Enum.flat_map(&expand_range_element/1)
    end
  end

  defp expand_range_element(%Range{} = range), do: Enum.to_list(range)
  defp expand_range_element(element), do: [element]

  # The values `unit` takes in the candidate's period, the units of its start
  # being the context. A calendar of weeks holds its week as the candidate's
  # month (see `in_calendar_terms/4`), so its months are counted as its weeks.
  defp period_values(:month, %Interval{from: %Tempo{time: time, calendar: calendar}}) do
    if week_calendar?(calendar),
      do: UnitValues.in_period(:week, time, calendar),
      else: UnitValues.in_period(:month, time, calendar)
  end

  defp period_values(unit, %Interval{from: %Tempo{time: time, calendar: calendar}}),
    do: UnitValues.in_period(unit, time, calendar)

  @application_order [
    :wkst,
    :skip,
    :month,
    :traditional_month,
    :week,
    :calendar_week,
    :week_of_month,
    :day_of_year,
    :event,
    :day,
    :nearest_weekday,
    :or_day,
    :day_of_week,
    :byday,
    :hour,
    :minute,
    :second,
    :year,
    :instance
  ]

  # Where each part comes in that order, and a token that is no part after
  # them all. It is read from a map: the order was searched for each part of
  # each candidate, which a walk asks of every period.
  @application_rank @application_order |> Enum.with_index() |> Map.new()
  @after_every_part length(@application_order)

  defp application_order_key({token, _value}),
    do: Map.get(@application_rank, token, @after_every_part)

  # Unit weight for the EXPAND-vs-LIMIT decision: rules whose
  # unit is FINER than FREQ (bigger weight) act as EXPAND; rules
  # whose unit is EQUAL or COARSER act as LIMIT. The weights only
  # need an ordering, not specific values.
  @unit_weight %{
    year: 1,
    month: 2,
    week: 3,
    day: 4,
    hour: 5,
    minute: 6,
    second: 7
  }

  # A part applies in the role its scope gives it, which `expands?/2` reads
  # too.
  defp apply_entry(entry, candidates, scope, selection, wkst) do
    apply_role(role(entry, scope, selection), entry, candidates, scope, selection, wkst)
  end

  # The role a part plays at a scope, per the table in the moduledoc:
  # `:expand` makes points within each candidate, `{:expand, period}` makes a
  # BYDAY's weekdays within the week, month or year, and `:limit` keeps or
  # drops whole candidates.
  defp role({token, _value}, :year, _selection)
       when token in [:month, :traditional_month, :day_of_year, :week, :calendar_week],
       do: :expand

  # In a yearly rule the parts that name a day all hold at once (RFC 5545
  # §3.3.10): the first of them to apply names the days, and each one after it
  # keeps those it names too. A day of the year applies before an event, and
  # a day of the month after both.
  #
  # An event is each of its days that falls in the period, a year, a month
  # or a week: the Easter of April 2026 and of its fourteenth week are both
  # 5 April. A day, and a period finer than one, is kept when it is the
  # event's day.
  defp role({:event, _name}, scope, selection) when scope in [:year, :month, :week] do
    if Keyword.has_key?(selection, :day_of_year), do: :limit, else: :expand
  end

  defp role({:day, _days}, :year, selection) do
    if day_named_before_day_of_month?(selection), do: :limit, else: :expand
  end

  defp role({:day, _days}, :month, selection) do
    if day_named_before_day_of_month?(selection), do: :limit, else: :expand
  end

  defp role({token, _value}, scope, _selection)
       when token in [:day, :nearest_weekday] and scope in [:month, :year],
       do: :expand

  # RFC 5545 gives a weekly rule no day of the month and no day of the year,
  # and a monthly rule no day of the year: its candidate there is a day, which
  # such a part could only keep or drop. A selection in a whole week or month
  # has that period for its candidate, and the first of these to apply is then
  # the days of the period it names (decided 2026-10-05): the 15th in a week
  # is each day of the week that is the 15th of its month. A part that names
  # a day after it keeps those it names too, as in a yearly rule.
  defp role({:day_of_year, _days}, scope, _selection) when scope in [:week, :month], do: :within

  defp role({:day, _days}, :week, selection) do
    if day_named_before_day_of_month?(selection), do: :limit, else: :within
  end

  defp role({:day_of_week, _days}, scope, selection), do: no_ordinal_byday_role(scope, selection)

  # A week of a month beside a part that picks within it makes the week's
  # days, which that part and those after it keep, drop or put times on, as
  # a week makes them in a year. With no such part it is the week itself.
  #
  # Selected from a day or a time of day it keeps or drops what it is asked
  # of, which is a day already: the week makes no days there.
  defp role({:week_of_month, _weeks}, scope, selection) do
    if scope in [:month, :year] and picks_within_a_week?(selection), do: :expand, else: :limit
  end

  # A numbered weekday beside a part that names the day keeps the day or
  # drops it (RFC 5545 §3.3.10, Notes 1 and 2), as a weekday with no number
  # does: the 15th that is a Wednesday, and never the 15th that is a first
  # Monday. With no such part it makes the days it names.
  defp role({:byday, _pairs}, scope, selection) when scope in [:month, :year] do
    if names_a_day?(selection), do: :limit, else: :expand
  end

  defp role({:byday, _pairs}, _scope, _selection), do: :expand

  defp role({unit, _values}, scope, _selection) when unit in [:hour, :minute, :second] do
    if Map.get(@unit_weight, scope, 0) < Map.get(@unit_weight, unit, 0),
      do: :expand,
      else: :limit
  end

  defp role(_entry, _scope, _selection), do: :limit

  # The unit a part that limits holds a candidate to, which is the same for
  # every candidate of that unit's period: a candidate's year, its month, its
  # date, its hour, its minute and its second. A week of the year is held to
  # the date too, every candidate of a day being in one week, though the
  # week runs across a month and a year: the walk goes on from it by days
  # (`goes_on_to_a_week/3`). A part whose days are worked out in another way
  # (an event, a nearest weekday) is none of them.
  @held_to %{
    year: :year,
    month: :month,
    traditional_month: :month,
    week: :day,
    day: :day,
    day_of_year: :day,
    day_of_week: :day,
    hour: :hour,
    minute: :minute,
    second: :second
  }

  # A part that limits by a unit coarser than the frequency drops every
  # candidate of that unit's period. One that limits by the unit the rule
  # steps by drops each candidate until the next value it names: an hour, a
  # minute or a second, and in a rule of days a day of the month, of the
  # year or of the week.
  defp limit_held_to({token, _value} = part, freq, selection) do
    with unit when not is_nil(unit) <- Map.get(@held_to, token),
         true <- held_above?(unit, freq),
         :limit <- role(part, freq, selection) do
      unit
    else
      _no_such_limit -> nil
    end
  end

  defp limit_held_to(_entry, _freq, _selection), do: nil

  defp held_above?(unit, unit), do: true

  defp held_above?(unit, freq),
    do: Map.fetch!(@unit_weight, unit) < Map.fetch!(@unit_weight, freq)

  defp coarsest_part_ruling_out(selection, candidate, freq) do
    wkst = Keyword.get(selection, :wkst, 1)

    selection
    |> Enum.flat_map(fn part ->
      case limit_held_to(part, freq, selection) do
        nil -> []
        unit -> [{Map.fetch!(@unit_weight, unit), part}]
      end
    end)
    |> Enum.sort_by(fn {weight, _part} -> weight end)
    |> Enum.find_value(fn {_weight, part} ->
      if drops?(part, candidate, freq, selection, wkst),
        do: further_than_a_step(goes_on(part, candidate, wkst), freq)
    end)
  end

  # The start of the next period of the frequency is the walk's own next
  # step, and no further.
  defp further_than_a_step({:next, freq}, freq), do: nil
  defp further_than_a_step(goes_on, _freq), do: goes_on

  # A year limits the periods a selection resolves in (`resolve_in_period/5`),
  # and every other part is asked as the walk asks it.
  defp drops?({:year, years}, candidate, _freq, _selection, _wkst),
    do: not period_selected?(candidate, years)

  defp drops?(part, candidate, freq, selection, wkst),
    do: apply_entry(part, [candidate], freq, selection, wkst) == []

  # A week of the year is counted from the day its weeks start on.
  defp goes_on({:week, weeks}, candidate, wkst), do: goes_on_to_a_week(weeks, candidate, wkst)
  defp goes_on(part, candidate, _wkst), do: goes_on_from(part, candidate)

  # Where the walk goes on from: the next value the part names in the period
  # the candidate is in, and the start of the next such period where it
  # names none. The values are the ones the part is asked by when it limits
  # (`apply_role/6`). A weekday is so many days on, and a day of the year is
  # the date Calendrical gives it.
  defp goes_on_from({:year, _years}, _candidate), do: {:next, :year}

  defp goes_on_from({:month, months}, candidate),
    do: next_named(values_named(months, :month, candidate), :month, month_of(candidate), :year)

  defp goes_on_from({:day, days}, candidate) do
    days
    |> List.wrap()
    |> counted_values(:day, candidate)
    |> next_named(:day, day_of(candidate), :month)
  end

  defp goes_on_from({:day_of_week, days}, candidate) do
    with weekday when is_integer(weekday) <- weekday_of(candidate),
         {:ok, %Range{} = week} <- period_values(:day_of_week, candidate),
         [_ | _] = named <- whole(values_named(days, :day_of_week, candidate)) do
      {:in_days, named |> Enum.map(&days_on(&1, weekday, Range.size(week))) |> Enum.min()}
    else
      _no_weekday_to_count_from -> {:next, :day}
    end
  end

  defp goes_on_from(
         {:day_of_year, days},
         %Interval{from: %Tempo{calendar: calendar}} = candidate
       ) do
    with today when is_integer(today) <- day_of_year_of(candidate),
         named = counted_values(List.wrap(days), :day_of_year, candidate),
         later when is_integer(later) <- next_after(named, today),
         {month, day} <- year_day_to_month_day(calendar, year_of(candidate), later) do
      {:on_day, month, day}
    else
      _none_later_in_the_year -> {:next, :year}
    end
  end

  defp goes_on_from({unit, values}, candidate) when unit in [:hour, :minute, :second] do
    values
    |> values_named(unit, candidate)
    |> next_named(unit, get_time_unit(candidate, unit), period_of(unit))
  end

  defp goes_on_from({token, _value}, _candidate), do: {:next, Map.fetch!(@held_to, token)}

  # The first day of the next week of the year the part names (RFC 5545's
  # `BYWEEKNO`, in a rule of days or less) is so many days on: of a later
  # week of the year the candidate's week is in, or of the first one named
  # in the year after, and of that year's first week where it names none of
  # its weeks (a week 53 in a year of 52), from which the walk is asked
  # again. Each day until then was asked which week it is in, so every
  # Monday of week 20 was 364 questions apart, and ninety of them were more
  # periods than a walk makes.
  defp goes_on_to_a_week(weeks, %Interval{from: %Tempo{time: time, calendar: calendar}}, wkst) do
    with {:ok, date} <- date_of(time, calendar),
         {week_start, week_year} <- week_and_its_year(date, calendar, wkst),
         {:ok, week, _weeks} <- UnitValues.week_number(calendar, week_year, wkst, week_start),
         %Date{} = named <- next_week_named(List.wrap(weeks), {week_year, week}, calendar, wkst),
         days when days > 0 <- Date.diff(named, date) do
      {:in_days, days}
    else
      _no_week_to_go_on_to -> {:next, :day}
    end
  end

  defp next_week_named(weeks, {year, week}, calendar, wkst) do
    starts = UnitValues.week_starts(calendar, year, wkst)

    case weeks |> weeks_named(starts) |> Enum.find(&(&1 > week)) do
      nil -> first_week_named(weeks, UnitValues.week_starts(calendar, year + 1, wkst))
      later -> Enum.at(starts, later - 1)
    end
  end

  defp first_week_named(_weeks, []), do: nil

  defp first_week_named(weeks, [first | _] = starts) do
    case weeks_named(weeks, starts) do
      [named | _] -> Enum.at(starts, named - 1)
      [] -> first
    end
  end

  defp weeks_named(weeks, starts), do: weeks |> UnitValues.named(1..length(starts)//1) |> whole()

  defp period_of(:hour), do: :day
  defp period_of(:minute), do: :hour
  defp period_of(:second), do: :minute

  defp whole(values), do: Enum.filter(values, &is_integer/1)

  # The days from one day of the week on to another, a week for the day
  # itself.
  defp days_on(named, weekday, days_in_week) do
    case Integer.mod(named - weekday, days_in_week) do
      0 -> days_in_week
      days -> days
    end
  end

  defp next_named(named, unit, current, period) when is_integer(current) do
    case next_after(named, current) do
      nil -> {:next, period}
      value -> {:on, unit, value}
    end
  end

  defp next_named(_named, _unit, _no_value, period), do: {:next, period}

  defp next_after(named, current),
    do: named |> whole() |> Enum.filter(&(&1 > current)) |> Enum.min(fn -> nil end)

  defp day_named_before_day_of_month?(selection),
    do: Keyword.has_key?(selection, :day_of_year) or Keyword.has_key?(selection, :event)

  # BYMONTH — EXPAND for FREQ=YEARLY, LIMIT otherwise. Per RFC
  # 5545 §3.3.10, a YEARLY rule with BYMONTH=6,7 produces an
  # occurrence in each listed month of each year; finer FREQs
  # already iterate at finer-than-year granularity, so they
  # just filter.
  defp apply_role(:expand, {:month, months}, candidates, _scope, selection, _wkst) do
    # RFC 5545 §3.3.10: the BY* parts apply in order BYMONTH,
    # BYWEEKNO, BYYEARDAY, BYMONTHDAY, BYDAY — so when any later
    # part determines the day, the day this expansion carries from
    # DTSTART is provisional and must not validity-filter the month
    # (a DTSTART on the 31st must still produce a November for
    # `BYDAY=4TH;BYMONTH=11` to select within).
    provisional_day? = day_determined_by_later_part?(selection)
    origin_day = Keyword.get(selection, :origin_day)

    Enum.flat_map(candidates, fn candidate ->
      expand_candidate_months(candidate, List.wrap(months), provisional_day?, origin_day)
    end)
  end

  defp apply_role(:limit, {:month, months}, candidates, _scope, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      month_of(candidate) in values_named(months, :month, candidate)
    end)
  end

  # A traditional month selector resolves to its ordinal position
  # per candidate year — a leap month shifts the numbering — then applies as an
  # ordinary BYMONTH. The traditional→ordinal step is Calendrical's, via
  # `Tempo.Validation.ordinal_month_from_traditional/3`. A leap month the candidate's
  # year does not carry resolves to nothing, so that year yields no occurrence.
  #
  # RFC 7529 §4.1: with a `SKIP` the leap month is not passed over there. It
  # is the month before it (`BACKWARD`), the month it follows, or the month
  # after it (`FORWARD`), and a month so reached twice is selected once.
  defp apply_role(_role, {:traditional_month, months}, candidates, scope, selection, wkst) do
    skip = Keyword.get(selection, :skip)

    Enum.flat_map(candidates, fn candidate ->
      months = months |> List.wrap() |> Enum.flat_map(&expand_range_element/1)
      ordinals = traditional_months_to_ordinals(candidate, months, skip)
      apply_entry({:month, ordinals}, [candidate], scope, selection, wkst)
    end)
  end

  # BYMONTHDAY — EXPAND for FREQ=MONTHLY or YEARLY, LIMIT
  # otherwise. RFC forbids it with FREQ=WEEKLY; we don't reject
  # (malformed rules are a parser concern). `-1` is the last
  # day of the enclosing month.
  defp apply_role(:expand, {:day, days}, candidates, _scope, selection, _wkst) do
    skip = Keyword.get(selection, :skip)

    Enum.flat_map(candidates, fn candidate ->
      expand_candidate_days(candidate, List.wrap(days), skip)
    end)
  end

  defp apply_role(:limit, {:day, days}, candidates, _scope, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_month_day_list?(candidate, List.wrap(days))
    end)
  end

  # A day of the month, in a weekly rule, and a day of the year, in a weekly
  # or a monthly one: the days of the candidate's week or month that the part
  # names (`days_of_period/3`).
  defp apply_role(:within, {:day, days}, candidates, scope, _selection, wkst) do
    Enum.flat_map(candidates, fn candidate ->
      candidate
      |> days_of_period(scope, wkst)
      |> Enum.filter(&in_month_day_list?(&1, List.wrap(days)))
    end)
  end

  defp apply_role(:within, {:day_of_year, days}, candidates, scope, _selection, wkst) do
    Enum.flat_map(candidates, &days_of_year_within(&1, List.wrap(days), scope, wkst))
  end

  # Nearest-weekday (`W`) — a non-standard cron modifier. EXPAND
  # for MONTHLY/YEARLY (project each enclosing month onto its
  # nearest-weekday date), LIMIT otherwise (keep candidates whose
  # day is a nearest-weekday for their month).
  defp apply_role(:expand, {:nearest_weekday, targets}, candidates, _scope, _selection, _wkst) do
    Enum.flat_map(candidates, fn candidate ->
      expand_nearest_weekdays(candidate, List.wrap(targets))
    end)
  end

  defp apply_role(:limit, {:nearest_weekday, targets}, candidates, _scope, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      day_of(candidate) in nearest_weekday_days(candidate, List.wrap(targets))
    end)
  end

  # POSIX day-of-month OR day-of-week — a non-standard cron union.
  # Always a LIMIT: keep a candidate whose day-of-month is in the
  # monthday list OR whose weekday matches a byday entry. The cron
  # builder pairs this with a DAILY cadence so every candidate day
  # is visited.
  defp apply_role(
         :limit,
         {:or_day, {monthdays, byday_entries}},
         candidates,
         _scope,
         _selection,
         _wkst
       ) do
    Enum.filter(candidates, fn candidate ->
      in_month_day_list?(candidate, monthdays) or weekday_matches?(candidate, byday_entries)
    end)
  end

  # BYYEARDAY — EXPAND for YEARLY, LIMIT otherwise. Signed
  # indexing: `-1` is the last day of the year.
  defp apply_role(:expand, {:day_of_year, days}, candidates, _scope, selection, _wkst) do
    Enum.flat_map(candidates, fn candidate ->
      candidate |> year_day_dates(List.wrap(days)) |> swap_in_selected_month(candidate, selection)
    end)
  end

  defp apply_role(:limit, {:day_of_year, days}, candidates, _scope, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_year_day_list?(candidate, List.wrap(days))
    end)
  end

  # Computed event (`(easter)e`, `(march-equinox)e`, …) — EXPAND for
  # FREQ=YEARLY, MONTHLY and WEEKLY: resolve the event via `Tempo.Event` and
  # emit each date it falls on in the candidate's year, month or week as a
  # day-resolution occurrence (one in a Gregorian year; one, none or two in a
  # year of another calendar; one or none in a month or a week). An unknown
  # event or a year the resolver cannot reach (an equinox outside Astro's
  # range) is the selection's error, a `Tempo.EventError`: no occurrence
  # would say the event did not happen. For finer FREQs it is a LIMIT: keep
  # candidates already sitting on the event's date.
  defp apply_role(:expand, {:event, name}, candidates, :year, selection, _wkst) do
    each_candidate(candidates, fn candidate ->
      with {:ok, dates} <- event_dates(candidate, name),
           do: {:ok, swap_in_selected_month(dates, candidate, selection)}
    end)
  end

  defp apply_role(:expand, {:event, name}, candidates, :month, _selection, _wkst) do
    each_candidate(candidates, fn candidate ->
      with {:ok, dates} <- event_dates(candidate, name),
           do: {:ok, swap_dates(candidate, in_month_of(dates, candidate))}
    end)
  end

  defp apply_role(:expand, {:event, name}, candidates, :week, _selection, wkst) do
    each_candidate(candidates, fn candidate ->
      with {:ok, dates} <- event_dates_in_week(candidate, name, wkst),
           do: {:ok, swap_dates(candidate, dates)}
    end)
  end

  defp apply_role(:limit, {:event, name}, candidates, _scope, _selection, _wkst) do
    each_candidate(candidates, fn candidate ->
      with {:ok, on_its_day?} <- on_event_date(candidate, name),
           do: {:ok, if(on_its_day?, do: [candidate], else: [])}
    end)
  end

  # BYWEEKNO — EXPAND for YEARLY (only valid FREQ per RFC).
  # Each listed week number expands to 7 occurrences (the
  # days of that week). Signed indexing: `-1` is the last week.
  # After a BYMONTH expansion only the days in the candidate's
  # month are kept.
  defp apply_role(:expand, {:week, weeks}, candidates, _scope, selection, wkst) do
    within_month? = month_selected?(selection)

    Enum.flat_map(candidates, fn candidate ->
      expand_candidate_week_numbers(candidate, List.wrap(weeks), wkst, within_month?)
    end)
  end

  # A week of a month, which the calendar numbers (decided 2026-10-07, and
  # written so by `read_in_its_period/1`): each week the part names in the
  # candidate's month. Alone it is the span of that week's dates, which is
  # not always within the month, and beside a part that picks within it,
  # each of those dates.
  #
  # A candidate written to a day, or to a time of one, is kept where a week
  # the part names holds its day (decided 2026-10-08): 10 June 2026 is in
  # the second week of its month.
  defp apply_role(:limit, {:week_of_month, weeks}, candidates, _scope, _selection, _wkst) do
    each_candidate(candidates, fn candidate ->
      with {:ok, named} <- weeks_of_month_named(candidate, weeks),
           do: {:ok, weeks_or_the_day_they_hold(named, candidate)}
    end)
  end

  defp apply_role(:expand, {:week_of_month, weeks}, candidates, _scope, _selection, _wkst) do
    each_candidate(candidates, fn candidate ->
      with {:ok, named} <- weeks_of_month_named(candidate, weeks),
           do: {:ok, Enum.flat_map(named, &week_of_month_days(&1, candidate))}
    end)
  end

  defp apply_role(:limit, {:week, weeks}, candidates, _scope, _selection, wkst) do
    Enum.filter(candidates, fn candidate ->
      in_week_no_list?(candidate, List.wrap(weeks), wkst)
    end)
  end

  # A calendar-week selection (`w`, Tempo's extension) — EXPAND for YEARLY
  # as BYWEEKNO is, LIMIT otherwise — in the weeks the calendar numbers
  # itself rather than ISO 8601's.
  defp apply_role(:expand, {:calendar_week, weeks}, candidates, _scope, selection, _wkst) do
    within_month? = month_selected?(selection)

    Enum.flat_map(candidates, fn candidate ->
      expand_candidate_calendar_weeks(candidate, List.wrap(weeks), within_month?)
    end)
  end

  defp apply_role(:limit, {:calendar_week, weeks}, candidates, _scope, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_calendar_week_list?(candidate, List.wrap(weeks))
    end)
  end

  # BYDAY without ordinal — filter/expander driven by FREQ and
  # by which other BY-rules are co-present. RFC 5545 §3.3.10
  # Note 1 / Note 2:
  #
  #   MONTHLY: LIMIT if BYMONTHDAY is present; else EXPAND
  #            within the month.
  #   YEARLY:  LIMIT if BYYEARDAY or BYMONTHDAY is present; else
  #            EXPAND within the year (or within BYMONTH-selected
  #            months when BYMONTH is also present).
  #
  # The `selection` list lets us detect the sibling tokens and
  # downgrade EXPAND → LIMIT per Notes 1/2.
  #
  # A weekday counted from the end is counted in the calendar's week: `-1`
  # is its last day.
  defp apply_role(:limit, {:day_of_week, days}, candidates, _scope, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      weekday_of(candidate) in values_named(days, :day_of_week, candidate)
    end)
  end

  defp apply_role({:expand, :week}, {:day_of_week, days}, candidates, _scope, _selection, wkst) do
    Enum.flat_map(candidates, fn candidate ->
      expand_weekdays_in_week(candidate, values_named(days, :day_of_week, candidate), wkst)
    end)
  end

  defp apply_role({:expand, :month}, {:day_of_week, days}, candidates, _scope, _selection, _wkst) do
    Enum.flat_map(candidates, fn candidate ->
      expand_weekdays_in_month(candidate, values_named(days, :day_of_week, candidate))
    end)
  end

  defp apply_role({:expand, :year}, {:day_of_week, days}, candidates, _scope, _selection, _wkst) do
    Enum.flat_map(candidates, fn candidate ->
      expand_weekdays_in_year(candidate, values_named(days, :day_of_week, candidate))
    end)
  end

  # BYDAY with ordinals — EXPAND. Each `{ordinal, weekday}` pair
  # picks one (or more) specific date within the enclosing
  # period. Backed by `Calendrical.Kday.nth_kday/3` which
  # handles both positive and negative ordinals.
  defp apply_role(:expand, {:byday, pairs}, candidates, scope, selection, wkst) do
    period = byday_ordinal_scope(scope, selection)

    Enum.flat_map(candidates, fn candidate ->
      expand_byday_pairs(candidate, pairs, period, wkst)
    end)
  end

  # BYDAY with ordinals beside a part that names the day — LIMIT: a day is
  # kept where it is one the pairs name in its month or its year.
  defp apply_role(:limit, {:byday, pairs}, candidates, scope, selection, wkst) do
    period = byday_ordinal_scope(scope, selection)

    Enum.filter(candidates, fn candidate ->
      candidate
      |> expand_byday_pairs(pairs, period, wkst)
      |> Enum.any?(&same_date?(&1, candidate))
    end)
  end

  # BYHOUR / BYMINUTE / BYSECOND — EXPAND when FREQ is coarser
  # than the unit, LIMIT when FREQ is the same unit or finer.
  defp apply_role(:expand, {unit, values}, candidates, _scope, selection, _wkst)
       when unit in [:hour, :minute, :second] do
    expand_time(candidates, unit, values, keep_span?(selection))
  end

  defp apply_role(:limit, {unit, values}, candidates, _scope, _selection, _wkst)
       when unit in [:hour, :minute, :second] do
    limit_time(candidates, unit, values)
  end

  # A year (`Y`) among a window's selectors — LIMIT: keep the window's days
  # in a listed year (a year number, a mask such as `202XY`, or `X*Y` for any
  # year). Anywhere else a year limits the period (`resolve_in_period/5`).
  defp apply_role(:limit, {:year, years}, candidates, _scope, _selection, _wkst) do
    Enum.filter(candidates, &year_selected?(year_of(&1), years))
  end

  # Position (ISO 8601-2 §12.9 `I`, = RFC 5545 BYSETPOS) — applied LAST. Treats
  # the accumulated `candidates` list as the resolved set and picks the Nth
  # element. Positive ordinals count from the start (1-based), negative from the
  # end (`-1` = last).
  defp apply_role(:limit, {:instance, positions}, candidates, _scope, _selection, _wkst) do
    pick_set_positions(candidates, List.wrap(positions))
  end

  # A weekday at a position (`weekday_with_its_position/1`): in one period
  # that the weekday makes days in, the days Calendrical gives for each
  # position, and otherwise the weekday's days with the position picked
  # among them, as the two parts apply apart.
  defp apply_role(_role, {:weekday_at, {day, positions}}, candidates, scope, selection, wkst) do
    with [candidate] <- candidates,
         {:expand, period} when period in [:month, :year] <-
           role({:day_of_week, day}, scope, selection),
         [_one | _] = made <- nth_weekdays(candidate, day, positions, period, wkst) do
      Enum.reject(made, &(&1 == :no_such_day))
    else
      _the_parts_apart ->
        {:day_of_week, day}
        |> apply_entry(candidates, scope, selection, wkst)
        |> pick_set_positions(positions)
    end
  end

  # WKST, a context-only token `apply_selection/4` has already read, and
  # unknown tokens pass through unchanged.
  defp apply_role(_role, _entry, candidates, _scope, _selection, _wkst), do: candidates

  defp keep_span?(selection), do: Keyword.get(selection, :keep_span, false)

  # BYDAY-no-ordinal role dispatcher (RFC §3.3.10 notes).
  defp day_determined_by_later_part?(selection) do
    Enum.any?(selection, fn
      {token, _value} ->
        token in [
          :week,
          :calendar_week,
          :day,
          :byday,
          :day_of_week,
          :day_of_year,
          :event,
          :nearest_weekday,
          :or_day
        ]

      _other ->
        false
    end)
  end

  # After a BYMONTH expansion a week keeps only its days in the month.
  defp month_selected?(selection) do
    Keyword.has_key?(selection, :month) or Keyword.has_key?(selection, :traditional_month)
  end

  # The dates a part names in a candidate's year, as occurrences. After a
  # BYMONTH expansion the candidate is one of the months selected, and of the
  # dates named those in that month alone are its own: a rule's parts all
  # hold at once, and a date is listed by the month it is in and no other.
  defp swap_in_selected_month(dates, candidate, selection) do
    if month_selected?(selection),
      do: swap_dates(candidate, in_month_of(dates, candidate)),
      else: swap_dates(candidate, dates)
  end

  # Those of some dates of a candidate's year that are in its month.
  defp in_month_of(dates, candidate),
    do: Enum.filter(dates, &(elem(&1, 1) == month_of(candidate)))

  # A computed event (`(easter)e`) names one day, as BYMONTHDAY does, so a
  # BYDAY beside it limits that day rather than expanding the period.
  defp no_ordinal_byday_role(:month, selection) do
    if names_a_day?(selection), do: :limit, else: {:expand, :month}
  end

  defp no_ordinal_byday_role(:year, selection) do
    cond do
      Keyword.has_key?(selection, :day) or Keyword.has_key?(selection, :day_of_year) or
          Keyword.has_key?(selection, :event) ->
        :limit

      # When BYMONTH is also present, BYMONTH's EXPAND has
      # already projected each candidate into a specific month.
      # BYDAY must then walk THAT month, not the whole year —
      # "every Thursday in March" ≠ "every Thursday in any month".
      Keyword.has_key?(selection, :month) ->
        {:expand, :month}

      true ->
        {:expand, :year}
    end
  end

  defp no_ordinal_byday_role(:week, selection) do
    if names_a_day?(selection), do: :limit, else: {:expand, :week}
  end

  defp no_ordinal_byday_role(_, _), do: :limit

  # Whether a part beside a weekday names the day already: a day of the
  # month, a day of the year or a computed event, which the weekday then
  # keeps or drops.
  defp names_a_day?(selection),
    do: Enum.any?([:day, :day_of_year, :event], &Keyword.has_key?(selection, &1))

  # BYDAY-with-ordinal period scope (for `nth_kday` counting):
  #
  # * FREQ=MONTHLY → `:month`.
  # * FREQ=YEARLY with BYMONTH present → `:month` (per RFC).
  # * FREQ=YEARLY without BYMONTH → `:year`.
  # * Otherwise BYDAY ordinals aren't meaningful per RFC; default
  #   widest (`:year`) so `nth_kday` operates relative to year
  #   boundaries.
  defp byday_ordinal_scope(:month, _selection), do: :month

  defp byday_ordinal_scope(:year, selection) do
    if Keyword.has_key?(selection, :month), do: :month, else: :year
  end

  defp byday_ordinal_scope(_, _), do: :year

  ## ------------------------------------------------------------
  ## BYMONTH
  ## ------------------------------------------------------------

  defp month_of(%Interval{from: %Tempo{time: time}}), do: Keyword.get(time, :month)

  defp year_of(%Interval{from: %Tempo{time: time}}), do: Keyword.get(time, :year)

  @doc false
  # Whether `year` is one a year selection lists: a year number, a range, a
  # mask matched digit by digit, any year (`X*Y`), or a list of them.
  def year_selected?(year, _years) when not is_integer(year), do: false
  def year_selected?(_year, :any), do: true
  def year_selected?(year, {:mask, mask}), do: Mask.matches_mask?(year, mask)
  def year_selected?(year, %Range{} = range), do: year in range

  def year_selected?(year, years) when is_list(years),
    do: Enum.any?(years, &year_selected?(year, &1))

  def year_selected?(year, selected), do: year == selected

  ## ------------------------------------------------------------
  ## BYMONTHDAY
  ## ------------------------------------------------------------

  defp in_month_day_list?(%Interval{} = candidate, days),
    do: day_of(candidate) in counted_values(days, :day, candidate)

  defp day_of(%Interval{from: %Tempo{time: time}}), do: Keyword.get(time, :day)

  ## ------------------------------------------------------------
  ## BYYEARDAY
  ## ------------------------------------------------------------

  defp in_year_day_list?(%Interval{} = candidate, target_days),
    do: day_of_year_of(candidate) in counted_values(target_days, :day_of_year, candidate)

  # The days of the year a part names that a period holds. In a period that
  # is a whole week or month each day named is placed in each year the
  # period touches, two at most, and kept where the period holds it. The
  # period's days were listed and each asked its day of the year, thirty
  # questions of the calendar to find one day of a month.
  defp days_of_year_within(
         %Interval{from: %Tempo{time: time, calendar: calendar}, to: to} = candidate,
         days,
         scope,
         wkst
       ) do
    with shift when is_integer(shift) and shift > 1 <- endpoint_shift(candidate),
         {:ok, first} <- date_of(time, calendar),
         {:ok, last} <- end_date_of(to, first, calendar) do
      held =
        for year <- first.year..last.year//1,
            date <- named_days_of_year(candidate, year, days),
            Compare.compare_days(date, first) != :lt and Compare.compare_days(date, last) == :lt,
            do: {date.year, date.month, date.day, date}

      swap_dates(candidate, held)
    else
      _a_day_or_less -> candidate |> days_of_period(scope, wkst) |> on_days_of_year(days)
    end
  end

  # The dates of the days of a year a part names, in the candidate's
  # calendar.
  defp named_days_of_year(
         %Interval{from: %Tempo{time: time, calendar: calendar} = from} = candidate,
         year,
         days
       ) do
    in_year = %{candidate | from: %{from | time: replace_unit_values(time, year: year)}}

    for day_of_year <- counted_values(days, :day_of_year, in_year),
        {month, day} <- [year_day_to_month_day(calendar, year, day_of_year)],
        {:ok, date} <- [Date.new(year, month, day, calendar)],
        do: date
  end

  # The days of a period that are days of the year a part names. What a
  # part names depends on the year a day is in (the last day of one is its
  # 365th or its 366th), and is found once for each year of the period, a
  # week holding the days of two at most. Found for each day, a range of
  # days of the year was looked for among the year's days thirty times over.
  defp on_days_of_year(period_days, target_days) do
    {on_them, _named_by_year} =
      Enum.flat_map_reduce(period_days, %{}, fn day, named_by_year ->
        named_by_year =
          Map.put_new_lazy(named_by_year, year_of(day), fn ->
            MapSet.new(counted_values(target_days, :day_of_year, day))
          end)

        if day_of_year_of(day) in Map.fetch!(named_by_year, year_of(day)),
          do: {[day], named_by_year},
          else: {[], named_by_year}
      end)

    on_them
  end

  defp day_of_year_of(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      calendar.day_of_year(year, month, day)
    else
      _ -> nil
    end
  end

  ## ------------------------------------------------------------
  ## BYWEEKNO
  ## ------------------------------------------------------------

  defp in_week_no_list?(%Interval{from: %Tempo{time: time, calendar: calendar}}, weeks, wkst) do
    with {:ok, date} <- date_of(time, calendar),
         {:ok, week, weeks_in_week_year} <- week_number_from_wkst(date, calendar, wkst) do
      week in UnitValues.named(weeks, 1..weeks_in_week_year//1)
    else
      _ -> false
    end
  end

  # RFC 5545 §3.3.10 numbers the weeks of a year from WKST: "A week is
  # defined as a seven day period, starting on the day of the week defined
  # to be the week start (see WKST). Week number one of the calendar year
  # is the first week that contains at least four (4) days in that
  # calendar year" — the week holding its fourth day, ISO 8601's week 1
  # when WKST is Monday. So a week belongs to the year that holds its own
  # fourth day: the first days of a year can be in the last week of the
  # year before, and its last days in week 1 of the next.
  #
  # The week is counted from the first day of its year's week 1
  # (`Tempo.UnitValues.week_number/4`), and its fourth day is three days on
  # from its first by the calendar's arithmetic: a rule of days or less asks
  # this of each of its periods, and the year's weeks, and the week's days,
  # were listed for each.
  defp week_number_from_wkst(date, calendar, wkst) do
    with {week_start, week_year} <- week_and_its_year(date, calendar, wkst),
         do: UnitValues.week_number(calendar, week_year, wkst, week_start)
  end

  # The first day of the week a date is in, and the year that week is of.
  defp week_and_its_year(date, calendar, wkst) do
    %Date{year: year, month: month, day: day} = week_start = Kday.kday_on_or_before(date, wkst)

    case calendar.plus(year, month, day, :days, 3, []) do
      {week_year, _month, _day} -> {week_start, week_year}
      _no_fourth_day -> :error
    end
  end

  # A calendar week (`w`) is one of the calendar's own weeks, numbered as
  # the calendar numbers them: the week `calendar.week_of_year/3` puts the
  # date in, counted among that week's year's weeks.
  defp in_calendar_week_list?(%Interval{from: %Tempo{time: time, calendar: calendar}}, weeks) do
    with {:ok, %Date{year: year, month: month, day: day}} <- date_of(time, calendar),
         true <- Code.ensure_loaded?(calendar) and function_exported?(calendar, :week_of_year, 3),
         {week_year, week} when is_integer(week_year) and is_integer(week) <-
           calendar.week_of_year(year, month, day) do
      week in calendar_weeks_named(weeks, week_year, calendar)
    else
      _ -> false
    end
  end

  ## ------------------------------------------------------------
  ## BYDAY (weekday filter / expander)
  ## ------------------------------------------------------------

  # The number `K` gives the candidate's day: its day of the week as the
  # selection's calendar counts it, which is the calendar's own week in a
  # calendar of weeks and ISO 8601's, from Monday, in a calendar of months
  # (`Tempo.UnitValues.week_counted_from/1`).
  defp weekday_of(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      day_of_week(calendar, year, month, day, UnitValues.week_counted_from(calendar))
    else
      _ -> nil
    end
  end

  defp day_of_week(calendar, year, month, day, counted_from),
    do: calendar.day_of_week(year, month, day, counted_from) |> normalise_day_of_week()

  # `Calendar.day_of_week/4` can return `:undefined` or a tuple
  # depending on the calendar implementation; coerce to the day's
  # number or `nil` when the calendar refuses.
  defp normalise_day_of_week(dow) when is_integer(dow) and dow >= 1, do: dow
  defp normalise_day_of_week({dow, _first, _last}) when is_integer(dow), do: dow
  defp normalise_day_of_week(_), do: nil

  # True when the candidate's weekday matches any `{ordinal, weekday}`
  # entry. Used by the POSIX OR filter, where the entries are plain
  # weekdays (the ordinal is `nil`), so only the weekday is compared.
  defp weekday_matches?(%Interval{} = candidate, byday_entries) do
    case named_weekday_of(candidate) do
      nil -> false
      weekday -> Enum.any?(byday_entries, fn {_ordinal, day} -> day == weekday end)
    end
  end

  # The weekday a BYDAY entry names is ISO 8601's, Monday the first, in
  # whatever calendar the candidate is.
  defp named_weekday_of(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      day_of_week(calendar, year, month, day, :monday)
    else
      _ -> nil
    end
  end

  # Walk every date in the candidate's enclosing week/month/year
  # and emit one new candidate per matching weekday. We preserve
  # the candidate's time-of-day and metadata; only the date
  # component changes. Every calendar op goes through the
  # candidate's own calendar.
  defp expand_weekdays_in_month(%Interval{} = candidate, weekdays) do
    case enclosing_month(candidate) do
      nil -> [candidate]
      {year, month} -> weekdays_of_month(candidate, year, month, weekdays)
    end
  end

  # The months of the candidate's year are those `period_values/2` gives,
  # which for a calendar of weeks are its weeks: a date of one holds its
  # week where a month is held, so a year's weekdays are those of each of
  # its weeks and not of its first twelve.
  defp expand_weekdays_in_year(%Interval{} = candidate, weekdays) do
    with year when is_integer(year) <- enclosing_year(candidate),
         {:ok, months} <- period_values(:month, candidate) do
      months |> each_value() |> Enum.flat_map(&weekdays_of_month(candidate, year, &1, weekdays))
    else
      nil -> [candidate]
      {:error, _cannot_count} -> []
    end
  end

  # The days of one month of the candidate's year that fall on the weekdays,
  # the month's days being those `Tempo.UnitValues` counts.
  #
  # A few weekdays are each found from the first of them in the month, a
  # week at a time, by Calendrical's arithmetic: five dates for a weekday,
  # where each of the month's thirty days was asked its day of the week.
  # More of them are as well asked of each day, the days being most of the
  # month.
  defp weekdays_of_month(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         year,
         month,
         weekdays
       )
       when length(weekdays) <= @weekdays_found_by_weeks do
    case month_bounds(year, month, month, calendar) do
      {first_day, last_day} ->
        swap_dates(candidate, weekdays_between(weekdays, first_day, last_day, calendar))

      nil ->
        []
    end
  end

  defp weekdays_of_month(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         year,
         month,
         weekdays
       ) do
    case UnitValues.in_period(:day, [year: year, month: month], calendar) do
      {:ok, days} -> emit_matching_days(candidate, year, month, days, weekdays)
      {:error, _no_such_month} -> []
    end
  end

  # The dates from one day to another on each of some days of the week, in
  # the order of time: the first of each on or after the first day, and the
  # dates a week on from it. A day of the week is numbered as the calendar
  # numbers it, and `Calendrical.Kday` takes ISO 8601's weekday.
  defp weekdays_between(weekdays, %Date{} = first_day, %Date{} = last_day, calendar) do
    weekdays
    |> Enum.uniq()
    |> Enum.flat_map(fn day ->
      weekday = UnitValues.iso_weekday_from_day_of_week(day, calendar)

      first_day
      |> Kday.kday_on_or_after(weekday)
      |> Stream.iterate(&Calendrical.next(&1, :week))
      |> Enum.take_while(&(Compare.compare_days(&1, last_day) != :gt))
    end)
    |> Enum.sort(&(Compare.compare_days(&1, &2) != :gt))
    |> Enum.map(&{&1.year, &1.month, &1.day, &1})
  end

  defp expand_weekdays_in_week(%Interval{} = candidate, weekdays, wkst) do
    case week_date_range(candidate, wkst) do
      nil ->
        [candidate]

      dates ->
        matching =
          for {year, month, day, dow} <- dates, dow in weekdays, do: {year, month, day}

        swap_dates(candidate, matching)
    end
  end

  defp enclosing_month(%Interval{from: %Tempo{time: time}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month) do
      {year, month}
    else
      _ -> nil
    end
  end

  defp enclosing_year(%Interval{from: %Tempo{time: time}}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> year
      _ -> nil
    end
  end

  defp emit_matching_days(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         year,
         month,
         days,
         weekdays
       ) do
    counted_from = UnitValues.week_counted_from(calendar)

    matching =
      for day <- each_value(days),
          day_of_week(calendar, year, month, day, counted_from) in weekdays,
          do: {year, month, day}

    swap_dates(candidate, matching)
  end

  # Each value of those a unit takes: a range's, or where a calendar lists
  # values apart from one another (a month with days missing) each range's.
  defp each_value(%Range{} = values), do: values
  defp each_value(ranges) when is_list(ranges), do: Enum.flat_map(ranges, &Enum.to_list/1)

  # Build the week around the candidate's date as seven
  # `{year, month, day, weekday}` tuples in chronological order,
  # with the week starting on `wkst` (1..7, Monday=1, default 1): the
  # `wkst` day on or before the candidate, from `Calendrical.Kday`, and
  # the six days Calendrical gives after it.
  defp week_date_range(%Interval{from: %Tempo{time: time, calendar: calendar}}, wkst) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day),
         {:ok, date} <- Date.new(year, month, day, calendar),
         %Date{} = week_start <- Kday.kday_on_or_before(date, wkst) do
      counted_from = UnitValues.week_counted_from(calendar)

      for d <- week_of_days_from(week_start) do
        {d.year, d.month, d.day, day_of_week(calendar, d.year, d.month, d.day, counted_from)}
      end
    else
      _ -> nil
    end
  end

  defp week_of_days_from(%Date{calendar: calendar} = date) do
    date
    |> Stream.iterate(&Calendrical.next(&1, :day))
    |> Enum.take(calendar.days_in_week())
  end

  # Rebuild a candidate with a new date, preserving the existing
  # time-of-day fields (hour/minute/second) and all other AST.
  # Calendar-aware — every `Date` operation is threaded through
  # the candidate's own calendar, so non-Gregorian recurrences
  # (Hebrew, Islamic, Coptic, …) expand correctly.
  #
  # NOTE: `Keyword.put/3` deletes-then-prepends, which reorders
  # the time list and breaks `Tempo.IntervalSet`'s positional
  # sort. We use `replace_unit_values/2` to preserve the original
  # [year, month, day, hour, …] ordering.
  #
  # `to` moves by the same number of days as `from`, keeping its
  # hour/minute/second so a 10:00–11:00 event stays 10:00–11:00 on
  # its new date. A swap onto the candidate's own date moves nothing.
  defp swap_date(%Interval{} = candidate, year, month, day) do
    {swapped, _shift} = swap_into(candidate, :pending, {year, month, day})
    swapped
  end

  # Swap each date — `{year, month, day}`, or `{year, month, day, date}`
  # for a date the calendar itself produced — into the same candidate, in
  # order. The days from the candidate's start to its end, which every
  # moved `to` keeps, are counted when a date first moves and shared by
  # the rest.
  defp swap_dates(%Interval{} = candidate, dates) do
    {swapped, _shift} = Enum.map_reduce(dates, :pending, &swap_into(candidate, &2, &1))
    swapped
  end

  defp swap_into(%Interval{from: %Tempo{time: time} = tempo, to: to} = candidate, shift, date) do
    case replace_unit_values(time, year: elem(date, 0), month: elem(date, 1), day: elem(date, 2)) do
      ^time ->
        {candidate, shift}

      new_from_time ->
        shift = known_shift(shift, candidate)
        new_to = shift_endpoint(to, shift, date, new_from_time, tempo.calendar)
        {%{candidate | from: %{tempo | time: new_from_time}, to: new_to}, shift}
    end
  end

  defp known_shift(:pending, candidate), do: endpoint_shift(candidate)
  defp known_shift(shift, _candidate), do: shift

  # The number of days from `from`'s date to `to`'s, which a moved `to`
  # keeps. `nil` when `to` is absent or either date is not a valid date in
  # the calendar, and `to` then stays put.
  defp endpoint_shift(%Interval{
         from: %Tempo{time: from_time, calendar: calendar},
         to: %Tempo{time: to_time}
       }) do
    with {:ok, from_date} <- date_of(from_time, calendar),
         {:ok, to_date} <- date_of(to_time, calendar) do
      Date.diff(to_date, from_date)
    else
      _invalid -> nil
    end
  end

  defp endpoint_shift(%Interval{}), do: nil

  defp shift_endpoint(%Tempo{time: to_time} = to, days_to_end, date, _new_from_time, calendar)
       when is_integer(days_to_end) do
    case new_from_date(date, calendar) do
      {:ok, new_from} ->
        {year, month, day} =
          calendar.plus(new_from.year, new_from.month, new_from.day, :days, days_to_end, [])

        %{to | time: replace_unit_values(to_time, year: year, month: month, day: day)}

      _invalid ->
        to
    end
  end

  defp shift_endpoint(to, _shift, _date, _new_from_time, _calendar), do: to

  # A date the calendar produced is carried with it; any other is checked.
  defp new_from_date({_year, _month, _day, %Date{} = date}, _calendar), do: {:ok, date}
  defp new_from_date({year, month, day}, calendar), do: Date.new(year, month, day, calendar)

  # Order-preserving replacement for keyword-list `time` values.
  # For each `{unit, value}` in `replacements`, if `unit` is
  # present in `time`, swap its value in place; otherwise leave
  # `time` alone (callers that need to ADD a unit use
  # `upsert_unit/3`).
  defp replace_unit_values(time, replacements) do
    Enum.map(time, fn {key, value} ->
      case Keyword.fetch(replacements, key) do
        {:ok, new_value} -> {key, new_value}
        :error -> {key, value}
      end
    end)
  end

  defp date_of(time, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      Date.new(year, month, day, calendar)
    else
      _ -> :error
    end
  end

  ## ------------------------------------------------------------
  ## EXPAND helpers — broaden per-FREQ candidates via BY* rules
  ## ------------------------------------------------------------

  # BYMONTH with FREQ=YEARLY: for each candidate, produce one
  # occurrence per listed month. When a later BY-part will set the
  # day, carry day 1 as a placeholder — valid in every month of
  # every calendar, and overwritten by the later expansion — so
  # DTSTART's day-of-month cannot drop a month it has no business
  # filtering. When no later part sets the day, DTSTART's day IS
  # the day (it fills the components the rule leaves unstated) and
  # a day past the month's end **clamps** to the month's last day,
  # per occurrence — the same clamping rule as Tempo's month
  # arithmetic, so February yields the 28th in common years and the
  # 29th in leap years. A month absent from the year entirely (a
  # leap month in a common year) drops — there is nothing to clamp
  # to.
  defp expand_candidate_months(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         months,
         provisional_day?,
         origin_day
       ) do
    year = candidate.from.time[:year]

    day =
      cond do
        provisional_day? -> 1
        is_integer(origin_day) -> origin_day
        true -> candidate.from.time[:day]
      end

    dates =
      for month <- values_named(months, :month, candidate) do
        {year, month, clamp_to_month(calendar, year, month, day)}
      end

    swap_dates(candidate, dates)
  end

  # A day clamps to the month's last day. A pure month selection (`L6M`)
  # on a month-resolution candidate names no day and carries none, so
  # the occurrence is the month itself: `swap_date` rewrites only the
  # units the candidate already has, so a dayless candidate stays at
  # month resolution.
  defp clamp_to_month(calendar, year, month, day) when is_integer(day) do
    case UnitValues.at_or_before(:day, day, [year: year, month: month], calendar) do
      {:ok, clamped} -> clamped
      {:error, _cannot_count} -> day
    end
  end

  defp clamp_to_month(_calendar, _year, _month, day), do: day

  # Resolve each traditional month spec (an integer, or `{n, :leap}`) to its
  # ordinal position in the candidate's year, dropping any the year does not
  # carry. The candidate walks the target calendar, so its year is the lunar
  # year against which the traditional numbering resolves.
  defp traditional_months_to_ordinals(
         %Interval{from: %Tempo{calendar: calendar, time: time}},
         months,
         skip
       ) do
    year = Keyword.get(time, :year)

    months
    |> Enum.flat_map(&ordinal_or_where_moved(&1, calendar, year, skip))
    |> Enum.uniq()
  end

  defp ordinal_or_where_moved(month, calendar, year, skip) do
    case Validation.ordinal_month_from_traditional(calendar, year, month) do
      {:ok, ordinal} when is_integer(ordinal) -> [ordinal]
      _the_year_lacks_it -> month_moved(month, calendar, year, skip)
    end
  end

  # A leap month the year lacks, moved by the rule's `SKIP`: to the month it
  # follows, or to the one after that. The numbers are the notation's, a
  # leap month being written by the month before it, and their places in the
  # year are the calendar's.
  defp month_moved({month, :leap}, calendar, year, :backward),
    do: ordinal_or_where_moved(month, calendar, year, nil)

  defp month_moved({month, :leap}, calendar, year, :forward),
    do: ordinal_or_where_moved(month + 1, calendar, year, nil)

  defp month_moved(_month, _calendar, _year, _omit), do: []

  # BYMONTHDAY with FREQ=MONTHLY or YEARLY: for each candidate,
  # produce one occurrence per listed day (signed: -1 = last day
  # of enclosing month). Invalid combinations skip.
  defp expand_candidate_days(%Interval{from: %Tempo{time: time}} = candidate, days, nil) do
    dates = for day <- counted_values(days, :day, candidate), do: {time[:year], time[:month], day}

    swap_dates(candidate, dates)
  end

  # RFC 7529's `SKIP` (and RFC 8984's `skip`): a day of the month that the
  # month lacks is moved to the month's last day (`BACKWARD`) or to the
  # first day of the month after (`FORWARD`), where `OMIT` passes over it.
  # Days moved to one date are one occurrence (RFC 8984 §4.3.3.1: "If any
  # valid date produced after applying the skip is already a candidate,
  # eliminate the duplicate"), and the dates are in the order of time.
  defp expand_candidate_days(
         %Interval{from: %Tempo{time: time, calendar: calendar}} = candidate,
         days,
         skip
       ) do
    month = {time[:year], time[:month]}

    case UnitValues.last(:day, [year: time[:year], month: time[:month]], calendar) do
      {:ok, last} ->
        dates =
          days
          |> Enum.flat_map(&expand_range_element/1)
          |> Enum.flat_map(&day_or_where_moved(&1, month, last, calendar, skip))
          |> Enum.uniq()
          |> Enum.sort()

        swap_dates(candidate, dates)

      {:error, _cannot_count} ->
        []
    end
  end

  # A day the month has, counted from either end, or where a day past its
  # end is moved to. The day after a month's last is Calendrical's.
  defp day_or_where_moved(day, {year, month}, last, _calendar, _skip) when day in 1..last//1,
    do: [{year, month, day}]

  defp day_or_where_moved(day, {year, month}, last, _calendar, _skip)
       when day < 0 and last + 1 + day >= 1,
       do: [{year, month, last + 1 + day}]

  defp day_or_where_moved(day, {year, month}, last, _calendar, :backward) when day > last,
    do: [{year, month, last}]

  defp day_or_where_moved(day, {year, month}, last, calendar, :forward) when day > last do
    case Date.new(year, month, last, calendar) do
      {:ok, last_day} ->
        %Date{year: year, month: month, day: day} = Calendrical.next(last_day, :day)
        [{year, month, day}]

      {:error, _no_such_date} ->
        []
    end
  end

  # A day counted from the end that the month lacks lies before its first
  # day (decided 2026-10-09, neither RFC 7529 nor RFC 8984 saying where it
  # is moved to): the 31st from the end of a month of thirty days is the
  # day before the 1st. Moved on it is the 1st, and moved back the last day
  # of the month before, which is Calendrical's.
  defp day_or_where_moved(day, {year, month}, last, _calendar, :forward)
       when day < 0 and last + 1 + day < 1,
       do: [{year, month, 1}]

  defp day_or_where_moved(day, {year, month}, last, calendar, :backward)
       when day < 0 and last + 1 + day < 1 do
    case Date.new(year, month, 1, calendar) do
      {:ok, first_day} ->
        %Date{year: year, month: month, day: day} = Calendrical.previous(first_day, :day)
        [{year, month, day}]

      {:error, _no_such_date} ->
        []
    end
  end

  defp day_or_where_moved(_day, _month, _last, _calendar, _skip), do: []

  ## ------------------------------------------------------------
  ## Nearest-weekday (cron `W`)
  ## ------------------------------------------------------------

  # Project each target (`15`, `1`, `:last`) onto the nearest
  # weekday within the candidate's own month, then emit one new
  # candidate per resolved date.
  defp expand_nearest_weekdays(%Interval{from: %Tempo{time: time}} = candidate, targets) do
    dates =
      for day <- nearest_weekday_days(candidate, targets),
          do: {time[:year], time[:month], day}

    swap_dates(candidate, dates)
  end

  # The concrete day-of-month each target resolves to in the
  # candidate's month (deduplicated; out-of-range targets dropped).
  defp nearest_weekday_days(%Interval{from: %Tempo{calendar: calendar, time: time}}, targets) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         {:ok, last_day} <- UnitValues.last(:day, [year: year, month: month], calendar) do
      targets
      |> Enum.map(&nearest_weekday(calendar, year, month, &1, last_day))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    else
      _no_one_month -> []
    end
  end

  # `LW` — the last weekday of the month: start at the last day and
  # step backwards over the weekend if need be.
  defp nearest_weekday(calendar, year, month, :last, dim) do
    snap_back_to_weekday(calendar, year, month, dim)
  end

  # `NW` — the nearest weekday to day N. Clamp N to the month length
  # (so `31W` in February lands on the 28th/29th), then shift off a
  # weekend without crossing into an adjacent month: a Saturday goes
  # back to Friday unless that leaves the month (then forward to
  # Monday), a Sunday goes forward to Monday unless that leaves the
  # month (then back to Friday).
  defp nearest_weekday(calendar, year, month, day, dim) when is_integer(day) and day >= 1 do
    target = min(day, dim)

    case weekday(calendar, year, month, target) do
      weekday when weekday in 1..5 -> target
      6 -> if target - 1 >= 1, do: target - 1, else: target + 2
      7 -> if target + 1 <= dim, do: target + 1, else: target - 2
      _ -> nil
    end
  end

  defp nearest_weekday(_calendar, _year, _month, _target, _dim), do: nil

  defp snap_back_to_weekday(calendar, year, month, day) do
    case weekday(calendar, year, month, day) do
      weekday when weekday in 1..5 -> day
      6 -> day - 1
      7 -> day - 2
      _ -> nil
    end
  end

  defp weekday(calendar, year, month, day) do
    calendar.day_of_week(year, month, day, :monday)
    |> normalise_day_of_week()
  end

  # BYYEARDAY with FREQ=YEARLY: one date per listed day-of-year
  # (signed). Convert ordinal → {month, day} via the calendar's
  # day-of-year axis.
  defp year_day_dates(%Interval{from: %Tempo{calendar: calendar}} = candidate, year_days) do
    year = candidate.from.time[:year]

    for day_of_year <- counted_values(year_days, :day_of_year, candidate),
        {m, day} <- [year_day_to_month_day(calendar, year, day_of_year)],
        do: {year, m, day}
  end

  # Resolve a computed event in the candidate's year: each date it falls on
  # there, in the candidate's own calendar, or the error of an event that has
  # no date in a year it is asked for.
  defp event_dates(%Interval{from: %Tempo{time: time, calendar: calendar}}, name) do
    case Keyword.get(time, :year) do
      year when is_integer(year) ->
        with {:ok, dates} <- event_dates_in_year(name, year, calendar),
             do: {:ok, Enum.map(dates, &date_units/1)}

      _no_year ->
        {:ok, []}
    end
  end

  defp date_units(%Date{year: year, month: month, day: day}), do: {year, month, day}

  # The days of an event that fall in the candidate's week, the seven days
  # from `wkst` that hold its date. The event is resolved in each year those
  # days are in, a week at the turn of a year being in two.
  defp event_dates_in_week(%Interval{from: %Tempo{calendar: calendar}} = candidate, name, wkst) do
    case week_date_range(candidate, wkst) do
      nil -> {:ok, []}
      days -> event_dates_among(days, name, calendar)
    end
  end

  defp event_dates_among(days, name, calendar) do
    in_week = MapSet.new(days, fn {year, month, day, _weekday} -> {year, month, day} end)

    days
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn year, {:ok, dates} ->
      case event_dates_in_year(name, year, calendar) do
        {:ok, more} -> {:cont, {:ok, dates ++ Enum.map(more, &date_units/1)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> kept(&MapSet.member?(in_week, &1))
  end

  defp kept({:ok, dates}, keep?), do: {:ok, Enum.filter(dates, keep?)}
  defp kept({:error, _reason} = error, _keep?), do: error

  # An event is computed for a year of the Gregorian calendar and falls in it
  # (`Tempo.Event.date/3`), so in the Gregorian calendar the event of a
  # candidate's year is the event of that year. A year of another calendar
  # runs through one, two or three Gregorian years, from the first of its
  # days to the last as Calendrical gives them: the event is asked for in
  # each, and the dates that fall in the candidate's year are the year's.
  # They are one Easter in a Hebrew year, and none or two September equinoxes
  # in a Hebrew year that begins after one or runs on to a second.
  defp event_dates_in_year(name, year, Calendrical.Gregorian) do
    with {:ok, date} <- event_date(name, year, Calendrical.Gregorian), do: {:ok, [date]}
  end

  defp event_dates_in_year(name, year, calendar) do
    year
    |> gregorian_years(calendar)
    |> Enum.reduce_while({:ok, []}, fn gregorian_year, {:ok, dates} ->
      case event_date(name, gregorian_year, calendar) do
        {:ok, %Date{year: ^year} = date} -> {:cont, {:ok, dates ++ [date]}}
        {:ok, _in_another_year} -> {:cont, {:ok, dates}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # The Gregorian years a year of `calendar` runs through, none for a year
  # the calendar does not have.
  defp gregorian_years(year, calendar) do
    with %Date{year: first} <- Calendrical.first_gregorian_day_of_year(year, calendar),
         %Date{year: last} <- Calendrical.last_gregorian_day_of_year(year, calendar) do
      first..last//1
    else
      _no_such_year -> []
    end
  end

  # The date an event falls on in a Gregorian year, as a date of `calendar`.
  # An event with none there is an error that names it and the year: no date
  # would say that the year has no equinox, or that a name no resolver
  # knows is an event that never happens.
  defp event_date(name, gregorian_year, calendar) do
    with {:ok, %Date{} = date} <- Event.date(name, gregorian_year, calendar),
         {:ok, %Date{} = date} <- Date.convert(date, calendar) do
      {:ok, date}
    else
      no_date -> {:error, event_error(name, gregorian_year, no_date)}
    end
  end

  defp event_error(name, _year, {:error, {:unknown_event, _name}}),
    do: EventError.exception(event: name, reason: :unknown_event)

  defp event_error(name, _year, {:error, {:unzoned_event, _event}}),
    do: EventError.exception(event: name, reason: :unzoned_event)

  # What a registered resolver gave that is no date is such an error too,
  # with the reason `{:not_a_date, given}` (`Tempo.Event.date/3`).
  defp event_error(name, year, {:error, reason}),
    do: EventError.exception(event: name, year: year, reason: reason)

  # LIMIT form (finer FREQs): does the candidate's date fall on the event? A
  # candidate that is no one date is on no event's day.
  defp on_event_date(%Interval{from: %Tempo{time: time, calendar: calendar}}, name) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day),
         {:ok, gregorian_year} <- gregorian_year_of(year, month, day, calendar),
         {:ok, %Date{} = date} <- event_date(name, gregorian_year, calendar) do
      {:ok, date_units(date) == {year, month, day}}
    else
      {:error, %EventError{}} = error -> error
      _no_one_date -> {:ok, false}
    end
  end

  # The Gregorian year a date of `calendar` falls in, which is the year an
  # event that falls on the date is computed for.
  defp gregorian_year_of(year, _month, _day, Calendrical.Gregorian), do: {:ok, year}

  defp gregorian_year_of(year, month, day, calendar) do
    with {:ok, %Date{} = date} <- Date.new(year, month, day, calendar),
         {:ok, %Date{year: gregorian_year}} <- Date.convert(date, Calendrical.Gregorian) do
      {:ok, gregorian_year}
    end
  end

  # BYWEEKNO with FREQ=YEARLY: one occurrence per listed week number
  # (signed), weeks numbered from WKST as RFC 5545 §3.3.10 defines them —
  # ISO 8601's weeks (`W`) for the default Monday. A single-week expansion
  # yields 7 occurrences (each day of the week). A week keeps all seven of
  # its days, even those in the calendar year before or after: with
  # WKST=MO, week 1 of 2026 starts on Monday 29 December 2025.
  defp expand_candidate_week_numbers(
         %Interval{from: %Tempo{calendar: calendar, time: time}} = candidate,
         weeks,
         wkst,
         within_month?
       ) do
    year = time[:year]

    if Keyword.has_key?(time, :day) do
      # RRULE `BYWEEKNO` carries `DTSTART`'s day, so it expands each week
      # to its seven days per RFC 5545 §3.3.10.
      week_starts = UnitValues.week_starts(calendar, year, wkst)
      month = if within_month?, do: month_of(candidate)

      weeks
      |> UnitValues.named(1..length(week_starts)//1)
      |> Enum.flat_map(&week_candidate_dates(&1, candidate, week_starts, month))
    else
      # A native week selection (`FL10WN`) names the week itself. The
      # occurrence is the `[year, week]` value; its span is resolved by
      # the calendar, so there is no week walk here.
      weeks
      |> counted_values(:week, candidate)
      |> Enum.map(&week_candidate_span(&1, candidate, year))
    end
  end

  # A calendar-week selection (`w`) with FREQ=YEARLY, in the weeks the
  # calendar numbers itself: each listed week's days for a candidate that
  # carries a day, or the week itself — the span of its days — for a native
  # selection (`FL10wN`). A week the calendar cuts short at the start or end
  # of its year holds fewer than seven days. A week-based calendar's own
  # weeks are its ISO 8601 weeks (`W`).
  defp expand_candidate_calendar_weeks(
         %Interval{from: %Tempo{calendar: calendar, time: time}} = candidate,
         weeks,
         within_month?
       ) do
    year = time[:year]

    cond do
      calendar.calendar_base() == :week ->
        expand_candidate_week_numbers(candidate, weeks, @monday, within_month?)

      Keyword.has_key?(time, :day) ->
        month = if within_month?, do: month_of(candidate)

        weeks
        |> calendar_weeks_named(year, calendar)
        |> Enum.flat_map(&calendar_week_dates(&1, candidate, year, calendar, month))

      true ->
        weeks
        |> calendar_weeks_named(year, calendar)
        |> Enum.flat_map(&calendar_week_span(&1, candidate, year, calendar))
    end
  end

  # The weeks a part names among those the calendar numbers in a year.
  defp calendar_weeks_named(weeks, year, calendar) do
    case UnitValues.in_period(:calendar_week, [year: year], calendar) do
      {:ok, valid} -> UnitValues.named(weeks, valid)
      {:error, _reason} -> []
    end
  end

  # `month` is the candidate's month after a BYMONTH expansion, and `nil`
  # when every day of the week is kept.
  defp week_candidate_dates(week, candidate, week_starts, month) do
    dates =
      for d <- week_of_days_from(Enum.at(week_starts, week - 1)),
          is_nil(month) or d.month == month,
          do: {d.year, d.month, d.day, d}

    swap_dates(candidate, dates)
  end

  # The days Calendrical gives calendar week `week` of `year`, fewer than
  # seven for a week the calendar cuts short at the start or end of its
  # year. `month` is as for `week_candidate_dates/4`.
  defp calendar_week_dates(week, candidate, year, calendar, month) do
    case UnitValues.calendar_week_range(year, week, calendar) do
      %Date.Range{} = days ->
        dates = for d <- days, is_nil(month) or d.month == month, do: {d.year, d.month, d.day, d}
        swap_dates(candidate, dates)

      {:error, _reason} ->
        []
    end
  end

  # `to` is sized from the `[year, week]` resolution by
  # `resize_to_resolution/1` back in the recurrence loop.
  defp week_candidate_span(week, %Interval{from: %Tempo{} = from} = candidate, year),
    do: %{candidate | from: %{from | time: [year: year, week: week]}, to: nil}

  # The {month, day} of a day of the year, from Calendrical. Returns
  # `nil` if the year has no such day.
  defp year_day_to_month_day(calendar, year, doy) when is_integer(doy) and doy >= 1 do
    case UnitValues.last(:day_of_year, [year: year], calendar) do
      {:ok, last} when doy <= last ->
        %{month: month, day: day} = Calendrical.date_from_day_of_year(year, doy, calendar)
        {month, day}

      _past_the_year ->
        nil
    end
  end

  defp weeks_or_the_day_they_hold(named, %Interval{from: %Tempo{time: time}} = candidate) do
    case Keyword.fetch(time, :day) do
      {:ok, day} when is_integer(day) -> kept_where_held(named, candidate, day)
      _a_month -> Enum.map(named, &week_of_month_span(&1, candidate))
    end
  end

  defp kept_where_held(named, candidate, day) do
    held? =
      Enum.any?(named, fn %Date.Range{} = week ->
        Enum.any?(
          week,
          &({&1.year, &1.month, &1.day} == {year_of(candidate), month_of(candidate), day})
        )
      end)

    if held?, do: [candidate], else: []
  end

  # The weeks a part names among those the calendar numbers in a candidate's
  # month, each the range of its dates.
  defp weeks_of_month_named(%Interval{from: %Tempo{calendar: calendar}} = candidate, weeks) do
    with year when is_integer(year) <- year_of(candidate),
         month when is_integer(month) <- month_of(candidate),
         {:ok, in_month} <- UnitValues.weeks_of_month(year, month, calendar) do
      named = weeks |> List.wrap() |> UnitValues.named(1..Enum.count(in_month)//1)
      {:ok, Enum.map(named, &Enum.at(in_month, &1 - 1))}
    else
      # A month the calendar numbers no weeks in selects none.
      _no_weeks_or_no_one_month -> {:ok, []}
    end
  end

  # The parts that go with a week of a month and pick nothing within it:
  # those that name the periods it is in, and what is no part at all, the
  # day its weeks start on and what a walk tells the resolver.
  @beside_a_week_of_month [
    :year,
    :month,
    :traditional_month,
    :week_of_month,
    :wkst,
    :skip,
    :origin_day,
    :keep_span
  ]

  defp picks_within_a_week?(selection),
    do: Enum.any?(selection, fn {part, _value} -> part not in @beside_a_week_of_month end)

  # The dates of a week of a month, each as a candidate that is its day. A
  # candidate written to a day or finer is moved onto each, keeping its
  # time of day, and one that is a month is each day of the week.
  defp week_of_month_days(%Date.Range{} = week, %Interval{from: %Tempo{time: time}} = candidate) do
    if Keyword.has_key?(time, :day),
      do: swap_dates(candidate, for(date <- week, do: {date.year, date.month, date.day, date})),
      else: Enum.map(week, &day_of_week_of_month(&1, candidate))
  end

  defp day_of_week_of_month(%Date{} = date, %Interval{from: %Tempo{} = from} = candidate) do
    next = Calendrical.next(date, :day)

    %{
      candidate
      | from: %{from | time: [year: date.year, month: date.month, day: date.day]},
        to: %{from | time: [year: next.year, month: next.month, day: next.day]}
    }
  end

  # A week of a month as one occurrence, from its first date to the day
  # after its last, marked to keep that span as a calendar week is.
  defp week_of_month_span(
         %Date.Range{first: first, last: last},
         %Interval{from: %Tempo{} = from, metadata: metadata} = candidate
       ) do
    next = Calendrical.next(last, :day)

    %{
      candidate
      | from: %{from | time: [year: first.year, month: first.month, day: first.day]},
        to: %{from | time: [year: next.year, month: next.month, day: next.day]},
        metadata: Map.put(metadata, :windowed, true)
    }
  end

  # A calendar week as one occurrence, from its first day to the day after
  # its last — a week the calendar cuts short at the start or end of its
  # year spans only its own days — marked to keep that span through the
  # recurrence loop's resizing.
  defp calendar_week_span(
         week,
         %Interval{from: %Tempo{} = from, metadata: metadata} = candidate,
         year,
         calendar
       ) do
    case UnitValues.calendar_week_range(year, week, calendar) do
      %Date.Range{first: first, last: last} ->
        next = Calendrical.next(last, :day)

        [
          %{
            candidate
            | from: %{from | time: [year: first.year, month: first.month, day: first.day]},
              to: %{from | time: [year: next.year, month: next.month, day: next.day]},
              metadata: Map.put(metadata, :windowed, true)
          }
        ]

      {:error, _reason} ->
        []
    end
  end

  ## ------------------------------------------------------------
  ## BYDAY with ordinals — "nth Kday" of the enclosing period
  ## ------------------------------------------------------------

  # For each `{ordinal, weekday}` pair, emit the matching date(s)
  # within the candidate's enclosing period. `scope` determines
  # whether "the period" is the candidate's month or year.
  # `wkst` is forwarded to the nil-ordinal fallback which
  # delegates to the weekly expander.
  defp expand_byday_pairs(%Interval{} = candidate, pairs, scope, wkst) do
    case period_bounds(candidate, scope) do
      nil ->
        # No clear period — pass through so the pipeline keeps
        # flowing. This shouldn't happen in well-formed rules.
        [candidate]

      {start_date, end_date} ->
        pairs
        |> Enum.flat_map(fn pair ->
          resolve_byday_pair(candidate, pair, start_date, end_date, scope, wkst)
        end)
        |> Enum.reject(&is_nil/1)
        |> in_order_of_time()
    end
  end

  # The pairs of a BYDAY are written in any order (`-1FR,1MO`), and two can
  # name one date. Their dates are taken in the order of time and once each,
  # as a position and a recurrence's count take them.
  defp in_order_of_time(candidates) do
    candidates
    |> Enum.uniq()
    |> Enum.sort(&(Compare.compare_time(&1.from.time, &2.from.time) != :gt))
  end

  # Compute the enclosing period's start and end `Date` values in
  # the candidate's own calendar. Month scope: 1st..last of the
  # candidate's month. Year scope: Jan 1..(Dec or last month) of
  # the candidate's year.
  defp period_bounds(%Interval{from: %Tempo{time: time, calendar: calendar}}, :month) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month) do
      month_bounds(year, month, month, calendar)
    else
      _ -> nil
    end
  end

  # A year runs from the first day of its first month to the last of its
  # last, the months being those `period_values/2` gives: for a calendar of
  # weeks, its weeks.
  defp period_bounds(%Interval{from: %Tempo{time: time, calendar: calendar}} = candidate, :year) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         {:ok, %Range{first: first_month, last: last_month}} <- period_values(:month, candidate) do
      month_bounds(year, first_month, last_month, calendar)
    else
      _ -> nil
    end
  end

  # The first day of one month of a year and the last day of another, which
  # `Tempo.UnitValues` gives.
  defp month_bounds(year, first_month, last_month, calendar) do
    with {:ok, first_day} <- UnitValues.first(:day, [year: year, month: first_month], calendar),
         {:ok, last_day} <- UnitValues.last(:day, [year: year, month: last_month], calendar),
         {:ok, start_date} <- Date.new(year, first_month, first_day, calendar),
         {:ok, end_date} <- Date.new(year, last_month, last_day, calendar) do
      {start_date, end_date}
    else
      _ -> nil
    end
  end

  # A single pair: with an ordinal, call `nth_kday` relative to
  # period start (positive) or end (negative). Without an
  # ordinal, expand to every matching weekday in the period (same
  # semantic as no-ordinal BYDAY at this scope) — matches the
  # RFC behaviour for mixed `BYDAY=MO,2TU` where `MO` is "every
  # Monday" and `2TU` is "2nd Tuesday".
  # `byday_ordinal_scope/2` only returns `:month` or `:year`
  # (BYDAY ordinals aren't meaningful under WEEKLY per RFC).
  # The nil-ordinal pair delegates to the matching period's
  # no-ordinal expander.
  defp resolve_byday_pair(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         {nil, weekday},
         _start,
         _end,
         scope,
         _wkst
       ) do
    # A BYDAY entry names its weekday, where the expanders take the day of
    # the week the candidate's calendar gives it.
    day_of_week = UnitValues.day_of_week_from_iso_weekday(weekday, calendar)

    case scope do
      :month -> expand_weekdays_in_month(candidate, [day_of_week])
      :year -> expand_weekdays_in_year(candidate, [day_of_week])
    end
  end

  defp resolve_byday_pair(
         %Interval{} = candidate,
         {ordinal, weekday},
         start_date,
         end_date,
         _scope,
         _wkst
       )
       when is_integer(ordinal) do
    origin = if ordinal >= 0, do: start_date, else: end_date

    case Kday.nth_kday(origin, ordinal, weekday) do
      %Date{year: y, month: m, day: d} = d_struct ->
        if date_in_period?(d_struct, start_date, end_date),
          do: [swap_date(candidate, y, m, d)],
          else: []

      _ ->
        []
    end
  end

  # The weekday at each position in the candidate's month or year, in the
  # order of time and once each, as a position picks them. `:no_such_day`
  # stands for a position the period lacks, so that a weekday the period
  # cannot be asked for (no dates to count from, a day of the week that is
  # no one day) is the empty list, and is resolved the long way.
  defp nth_weekdays(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         day,
         positions,
         period,
         wkst
       ) do
    with [named] <- values_named(day, :day_of_week, candidate),
         {start_date, end_date} <- period_bounds(candidate, period) do
      weekday = UnitValues.iso_weekday_from_day_of_week(named, calendar)

      case Enum.flat_map(
             positions,
             &resolve_byday_pair(candidate, {&1, weekday}, start_date, end_date, period, wkst)
           ) do
        [] -> [:no_such_day]
        made -> in_order_of_time(made)
      end
    else
      _not_one_weekday_of_a_dated_period -> []
    end
  end

  # Whether two candidates are on one date.
  defp same_date?(%Interval{from: %Tempo{time: time}}, %Interval{from: %Tempo{time: other}}),
    do: Keyword.take(time, [:year, :month, :day]) == Keyword.take(other, [:year, :month, :day])

  # `nth_kday` may return a date outside the intended period
  # when the ordinal exceeds the number of matching weekdays
  # (e.g. `5MO` in a month with only 4 Mondays). Clamp by
  # checking the period boundaries.
  defp date_in_period?(%Date{} = date, %Date{} = start_date, %Date{} = end_date) do
    Compare.compare_days(date, start_date) != :lt and Compare.compare_days(date, end_date) != :gt
  end

  ## ------------------------------------------------------------
  ## BYSETPOS — applied last, per-period
  ## ------------------------------------------------------------

  # Candidates arrive here in the order of time: each expansion before
  # this walks its period in order. A position counts among them from the
  # start, or from the end when it is negative, and a range of positions is
  # resolved end by end (`{2..-1}I` is every occurrence but the first). The
  # occurrences picked keep the order of time, and a position the period
  # lacks picks none.
  defp pick_set_positions(candidates, positions) do
    picked = UnitValues.named(positions, 1..length(candidates)//1)

    for {candidate, position} <- Enum.with_index(candidates, 1), position in picked do
      candidate
    end
  end

  ## ------------------------------------------------------------
  ## BYHOUR / BYMINUTE / BYSECOND
  ## ------------------------------------------------------------

  # An hour, a minute or a second counted from the end is counted in the
  # day, the hour or the minute: `-1H` is 23:00. A unit after a selection
  # comes here too, a day among them (`FL6MN-1D`), which is counted in the
  # month the selection picked.
  defp expand_time(candidates, unit, values, keep_span?) do
    Enum.flat_map(candidates, fn candidate ->
      for value <- values_named(values, unit, candidate) do
        set_time_unit(candidate, unit, value, keep_span?)
      end
    end)
  end

  defp limit_time(candidates, unit, values) do
    Enum.filter(candidates, fn candidate ->
      get_time_unit(candidate, unit) in values_named(values, unit, candidate)
    end)
  end

  defp get_time_unit(%Interval{from: %Tempo{time: time}}, unit), do: Keyword.get(time, unit)

  # A candidate moved to another hour, minute or second. With an explicit
  # span, `to` moves by as much as `from`, so a 09:00–10:00 event expanded
  # to 17:00 is 17:00–18:00, as a span moved to another date keeps its days
  # (`swap_into/3`). Without one, the occurrence is resized to its own
  # resolution afterwards, so `to` is left for that.
  defp set_time_unit(%Interval{from: %Tempo{time: time} = tempo} = candidate, unit, value, false) do
    %{candidate | from: %{tempo | time: upsert_unit(time, unit, value)}}
  end

  defp set_time_unit(
         %Interval{from: %Tempo{time: time} = tempo, to: to} = candidate,
         unit,
         value,
         true
       ) do
    shift = value - time_unit_value(time, unit)

    %{
      candidate
      | from: %{tempo | time: upsert_unit(time, unit, value)},
        to: shift_time(to, unit, shift)
    }
  end

  # A unit the start leaves out is at its start: hour, minute or second 0.
  defp time_unit_value(time, unit) do
    case Keyword.get(time, unit) do
      value when is_integer(value) -> value
      _absent -> 0
    end
  end

  defp shift_time(%Tempo{} = to, unit, shift) when shift != 0,
    do: Math.add(to, %Tempo.Duration{time: [{unit, shift}]})

  defp shift_time(to, _unit, _shift), do: to

  # Update a unit in an ordered `time` list. If the unit is
  # already present, replace its value in place. Otherwise
  # insert it in canonical position (year → month → week → day
  # → hour → minute → second) so `Tempo.IntervalSet`'s
  # position-dependent sort stays correct.
  defp upsert_unit(time, unit, value) do
    if Keyword.has_key?(time, unit) do
      Enum.map(time, fn
        {^unit, _} -> {unit, value}
        pair -> pair
      end)
    else
      time |> with_the_clock_units_before(unit) |> insert_unit_in_order(unit, value)
    end
  end

  # A time of day on a date names each unit down to its finest: a minute
  # placed on a day that has no hour is in the day's first (`T0H15M`), as it
  # is where the rule's start is filled down to the minute. A time with no
  # date is on a cycle, and is left as it is written.
  defp with_the_clock_units_before(time, unit) when unit in [:minute, :second] do
    if Keyword.has_key?(time, :day),
      do: Enum.reduce(clock_units_before(unit), time, &at_its_start/2),
      else: time
  end

  defp with_the_clock_units_before(time, _unit), do: time

  defp clock_units_before(:minute), do: [:hour]
  defp clock_units_before(:second), do: [:hour, :minute]

  defp at_its_start(unit, time) do
    if Keyword.has_key?(time, unit), do: time, else: insert_unit_in_order(time, unit, 0)
  end

  @unit_canonical_order [:year, :month, :week, :day, :hour, :minute, :second]

  defp insert_unit_in_order(time, unit, value) do
    target_idx =
      Enum.find_index(@unit_canonical_order, &(&1 == unit)) || length(@unit_canonical_order)

    {before, rest} =
      Enum.split_while(time, fn {k, _} ->
        idx = Enum.find_index(@unit_canonical_order, &(&1 == k))
        idx != nil and idx < target_idx
      end)

    before ++ [{unit, value}] ++ rest
  end
end
