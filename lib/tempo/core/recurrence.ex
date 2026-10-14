defmodule Tempo.Recurrence do
  @moduledoc false

  # The occurrences of a recurrence, the `:every` form (law 1): its first
  # span moved by n cadences for each n, scaled rather than accumulated, and
  # bounded by a count, an until or a `:within` window. A recurrence with a
  # rule walks its cadence's periods and selects in each (`Tempo.Select`),
  # each period's extent reckoned once as it is made (decisions 37 and 56);
  # one with a domain steps only through the years the domain names.
  # `Tempo.Spans` gives a recurrence its spans through this module.

  alias Tempo.Calendar
  alias Tempo.Children
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Exclusions
  alias Tempo.Scale
  alias Tempo.Select
  alias Tempo.Shift
  alias Tempo.Spans
  alias Tempo.Unit

  @rule_units [
    :month,
    :traditional_month,
    :week,
    :day,
    :day_of_week,
    :day_of_year,
    :hour,
    :minute,
    :second
  ]

  @day Scale.ticks_per_day()

  # Where the start of a rule's next period is kept (`start_at/3`).
  @next_start {__MODULE__, :next_start}

  # The periods of a day or finer a rule tries one by one, selecting
  # nothing, before it looks ahead for where its parts next name a value.
  @quiet_periods 2

  # ── Repeat rules ──────────────────────────────────────────────────────

  @doc """
  The occurrences of a recurrence with a rule: each repeating interval is
  a period the rule selects within; the units of the start finer than the
  rule's finest unit are inherited (§13.6.3); a count counts the
  occurrences selected, an until bounds them.
  """
  @spec rule_occurrences(Tempo.t(), term(), term(), Tempo.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def rule_occurrences(
        %Tempo{form: {:span, from, _to}} = first,
        bound,
        rule,
        recurrence,
        options
      ) do
    with {:ok, periods} <- rule_periods(aligned(first), from, recurrence, options),
         {:ok, until} <- until_position(bound),
         {:ok, excluded} <- Exclusions.exclusions(from, options) do
      parts = with_inherited(rule, inherited_units(from, rule, first))
      stepped = stepped_first(first, range_start(from))
      walk = %{first: stepped, parts: parts, begins: start_of_rule(from), options: options}

      stream =
        periods
        |> selected_in(walk, first_period(periods, bound, parts, from, options))
        |> Exclusions.left_out(excluded)
        |> to_range_end(from)
        |> in_range_years(from, first.calendar)
        |> Stream.dedup_by(&landing/1)
        |> Stream.map(fn {occurrence, extent} ->
          {%{occurrence | metadata: Map.merge(recurrence.metadata, occurrence.metadata)}, extent}
        end)
        |> bounded(bound, until, options)
        |> Stream.map(&elem(&1, 0))

      {:ok, stream}
    end
  end

  # A domain's members are each selected in.
  defp selected_in({:each, periods}, walk, _first_step) do
    periods
    |> Stream.map(&eligible(&1, walk.first))
    |> Stream.flat_map(&picked_in(&1, period_extent(&1), walk))
  end

  # A cadence's periods are stepped through by number, so that a run of
  # periods the rule selects nothing in is passed over to the next value its
  # parts name, and a rule that selects nothing in a whole cycle of its
  # calendar's years comes to an end.
  defp selected_in({:steps, period_at}, walk, first_step) do
    walk = Map.merge(walk, %{period_at: period_at, horizon: horizon(walk)})

    {first_step, nil}
    |> Stream.unfold(fn {k, quiet_since} ->
      {period, extent} = eligible_at(period_at.({:with_extent, k}), walk.first)
      step(picked_in(period, extent, walk), {period, extent}, k, quiet_since, walk)
    end)
    |> Stream.flat_map(& &1)
  end

  # What a period selects, from where the rule begins: a period that begins
  # there or later selects only from there, and the first is filtered. Each
  # occurrence goes on with its extent, reckoned once as its span is made.
  defp picked_in(period, {start, _stop} = extent, %{parts: parts, begins: begins} = walk)
       when start >= begins,
       do: in_rule_period(period, parts, [extent: extent] ++ walk.options)

  defp picked_in(period, extent, %{parts: parts, begins: begins, options: options}) do
    options = if extent, do: [extent: extent] ++ options, else: options

    period
    |> in_rule_period(parts, options)
    |> Enum.filter(fn {_occurrence, {start, _stop}} -> start >= begins end)
  end

  defp period_extent(period) do
    case Spans.extent(period) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> {start, stop}
      _ -> nil
    end
  end

  defp step([_ | _] = picked, _period, k, _quiet_since, _walk), do: {picked, {k + 1, nil}}

  # A day or a finer period that selects nothing is followed by the next,
  # for a few: a weekend in a daily rule of weekdays is passed over a day at
  # a time, each day's weekday asked of it. A longer quiet, and a quiet of
  # coarser periods, is passed over to where the parts next name a value.
  defp step([], {period, extent}, k, quiet_since, walk) do
    {start, stop} = extent || {0, 0}
    {since, quiet_from} = quiet_since || {start, k}

    cond do
      start - since > walk.horizon -> nil
      k - quiet_from < quiet_periods(walk.first) -> {[], {k + 1, {since, quiet_from}}}
      true -> stepped_on(next_named(stop, period, walk), k, {since, quiet_from}, walk)
    end
  end

  defp stepped_on(nil, _k, _quiet_since, _walk), do: nil

  defp stepped_on(tick, k, quiet_since, walk),
    do: {[], {index_at(tick, walk.period_at, k, k + 1), quiet_since}}

  defp quiet_periods(first),
    do: if(cadence_unit(first) in [:day, :hour, :minute, :second], do: @quiet_periods, else: 0)

  defp ends_of(period) do
    case Spans.extent(period) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) -> {start, stop}
      _ -> {0, 0}
    end
  end

  # A count counts from the rule's start; any other bound's occurrences are
  # looked for from the period the window begins in.
  defp first_step({:steps, period_at}, bound, options) when not is_integer(bound) do
    case Spans.window_extent(options[:within]) do
      {:ok, {start, _}} when is_integer(start) -> index_at(start, period_at, 0, 0)
      _none -> 0
    end
  end

  defp first_step(_periods, _bound, _options), do: 0

  # The period a rule's occurrences are looked for from: the window's, or
  # the one before it where an occurrence may run on into the window, and
  # never one before a domain's first.
  defp first_period(periods, bound, parts, from, options) do
    first = first_step(periods, bound, options) - carried_back(bound, parts)
    if range_start(from), do: max(first, 0), else: first
  end

  # A selection that opens a window (a day observed on the Monday after, a
  # holiday of several days from 19 December) may carry an occurrence into
  # the next period: a window's occurrences are looked for from the period
  # before it, and those before it dropped. A count counts from the rule's
  # start, which no period before reaches.
  defp carried_back(count, _parts) when is_integer(count), do: 0

  defp carried_back(_bound, parts) do
    if Keyword.has_key?(with_nested(parts), :window), do: 1, else: 0
  end

  # The number of the last period that begins by a position, no less than a
  # least number: reckoned from the length of a period and then stepped to.
  defp index_at(tick, period_at, k, least) do
    start = Spans.start_position(period_at.(k))
    length = max(Spans.start_position(period_at.(k + 1)) - start, 1)

    (k + div(tick - start, length))
    |> max(least)
    |> back_to(tick, period_at, least)
    |> on_to(tick, period_at)
  end

  defp back_to(n, tick, period_at, least) when n > least do
    if Spans.start_position(period_at.(n)) > tick,
      do: back_to(n - 1, tick, period_at, least),
      else: n
  end

  defp back_to(n, _tick, _period_at, _least), do: n

  defp on_to(n, tick, period_at) do
    if Spans.start_position(period_at.(n + 1)) <= tick, do: on_to(n + 1, tick, period_at), else: n
  end

  # Where the rule's parts next name a value from a position on, whatever
  # the cadence: looked for a year, a month or a day at a time, as far as the
  # horizon. A nested selection, or a set of them, is made in the period as a whole (the fifth
  # Sunday of a month, at nine), so its parts are looked for in the next period.
  defp next_named(tick, period, walk) do
    parts = picking(walk.parts)

    # A skip gives a period that names nothing a day of its own, so no
    # period is passed over to the next that names one.
    every_period? = Enum.any?([:selection, :all, :skip], &Keyword.has_key?(parts, &1))

    case {every_period?, Select.probe(parts)} do
      {true, _probe} -> tick
      {false, nil} -> nil
      {false, probe} -> named_from(tick, tick, probe, period, walk)
    end
  end

  defp named_from(tick, from, {unit, search} = probe, period, walk) do
    span = %{period | form: {:value, Shift.period_units(tick, unit, Spans.frame_of(period))}}
    {_start, stop} = ends_of(span)

    cond do
      found = first_named(span, search, from, walk.options) -> found
      stop <= tick or stop - from > walk.horizon -> nil
      true -> named_from(stop, from, probe, period, walk)
    end
  end

  # A window may carry what it selects back out of its period, so where the
  # parts open one, a period in which anything is selected is the place.
  defp first_named(span, search, from, options) do
    case {Select.in_period(span, search, options), Keyword.has_key?(search, :selection)} do
      {{:ok, [_ | _]}, true} ->
        max(from, Spans.start_position(span))

      {{:ok, picked}, _windowed?} ->
        picked
        |> Enum.map(&Spans.start_position/1)
        |> Enum.filter(&(&1 >= from))
        |> Enum.min(fn -> nil end)

      {{:error, _}, _windowed?} ->
        nil
    end
  end

  # How long a rule may select nothing before it has no more to select. One
  # that names times of day alone has named them all in two years, a zone's
  # clock changing by the year. Any other has in a cycle of its calendar's
  # years, in which every date and weekday it could name comes round, or in
  # a thousand years in a calendar with no cycle.
  defp horizon(%{parts: parts, first: %Tempo{calendar: calendar}}) do
    if Enum.all?(Keyword.keys(picking(parts)), &(&1 in [:hour, :minute, :second, :instance])),
      do: 2 * 366 * @day,
      else: (Calendar.years_in_cycle(calendar) || 1000) * 366 * @day
  end

  # A rule's repeating intervals are whole periods of its cadence's unit, the
  # first the one its start is in (RFC 5545's weeks and months, ISO 8601-2's
  # eligible intervals); occurrences before the start are not counted.
  defp aligned(
         %Tempo{
           form:
             {:span, %Tempo{form: {:value, _}} = from, %Duration{units: [{unit, _}]} = cadence}
         } = first
       ) do
    case Shift.trunc(from, unit) do
      {:ok, truncated} -> %{first | form: {:span, truncated, cadence}}
      {:error, _} -> first
    end
  end

  defp aligned(first), do: first

  # Of a repeating interval of several units (every second week), the first
  # unit is the one the rule selects in, as RFC 5545's INTERVAL has it.
  defp eligible(
         %Tempo{form: {:span, %Tempo{} = from, _}} = period,
         %Tempo{form: {:span, %Tempo{form: {:value, _}}, %Duration{units: [{unit, n}]}}}
       )
       when n > 1,
       do: %{period | form: {:span, from, %Duration{units: [{unit, 1}]}}}

  defp eligible(period, _first), do: period

  # A period whose extent its building gave keeps it, unless the rule
  # selects in the first unit of a longer repeat.
  defp eligible_at({period, extent}, first) do
    case eligible(period, first) do
      ^period when extent != nil -> {period, extent}
      narrowed -> {narrowed, period_extent(narrowed)}
    end
  end

  defp start_of_rule(%Tempo{form: {:value, _}} = from) do
    case Spans.extent(from) do
      {:ok, {start, _}} when is_integer(start) -> start
      _ -> 0
    end
  end

  defp start_of_rule(_from), do: 0

  # The start's finer units join the parts that pick the occurrences: the
  # rule's own, or those of a selection whose windows are the occurrences.
  defp with_inherited(rule, []), do: rule

  defp with_inherited([selection: parts, window: window], inherited),
    do: [selection: with_inherited(parts, inherited), window: window]

  defp with_inherited(rule, inherited), do: rule ++ inherited

  defp picking(selection: parts, window: _window), do: picking(parts)
  defp picking(rule), do: rule

  # A domain (a set in the start's place) gives its members as the periods;
  # a start gives the cadence's repeating intervals.
  defp rule_periods(first, %Tempo{form: form} = domain, recurrence, options)
       when elem(form, 0) in [:all, :when] do
    cond do
      Exclusions.only_exclusions?(domain) or Exclusions.every_year?(domain) ->
        rule_periods(%{first | form: put_elem(first.form, 1, :open)}, :open, recurrence, options)

      match?(%Tempo{}, range_start(domain)) ->
        steps(aligned(stepped_first(first, range_start(domain))), recurrence)

      true ->
        each_member(domain, first, recurrence, options)
    end
  end

  # A rule with no start (`R/../P1Y/F…`) has the cadence's periods the window runs through.
  defp rule_periods(
         %Tempo{form: {:span, :open, %Duration{units: [{unit, n}]}}} = first,
         :open,
         recurrence,
         options
       ) do
    case Spans.window_extent(options[:within]) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
        # The window says where; the periods are of the rule's own calendar.
        frame = %{Spans.frame_of(options[:within]) | calendar: first.calendar}
        anchor = %{first | form: {:value, Shift.period_units(start, unit, frame)}}
        step = %Duration{units: [{unit, n}]}
        steps(%{first | form: {:span, anchor, step}}, recurrence)

      _none ->
        {:error, conversion(recurrence, :unbounded)}
    end
  end

  defp rule_periods(first, _from, recurrence, _options), do: steps(first, recurrence)

  # A domain that is one range (`{1848Y..}`) is stepped through from its
  # start by the cadence, to its end.
  defp stepped_first(first, nil), do: first
  defp stepped_first(first, %Tempo{} = start), do: %{first | form: put_elem(first.form, 1, start)}

  defp range_start(%Tempo{form: {:all, [%Tempo{form: {:span, %Tempo{} = from, _to}}]}}), do: from
  # A filter of years on a range (`{2000Y..}e`) is of the range's periods.
  defp range_start(%Tempo{form: {:when, %Tempo{} = inner, [years: _filter]}}),
    do: range_start(inner)

  defp range_start(_domain), do: nil

  defp in_range_years(stream, %Tempo{form: {:when, %Tempo{} = inner, [years: filter]}}, calendar) do
    if range_start(inner) != nil or Exclusions.every_year?(inner),
      do: Stream.filter(stream, &Exclusions.in_years?(elem(&1, 0), filter, calendar)),
      else: stream
  end

  defp in_range_years(stream, _from, _calendar), do: stream

  defp to_range_end(
         stream,
         %Tempo{form: {:all, [%Tempo{form: {:span, %Tempo{}, %Tempo{} = to}}]}}
       ) do
    case Spans.end_position(to) do
      {:ok, stop} when is_integer(stop) ->
        Stream.take_while(stream, fn {_occurrence, {start, _}} -> start < stop end)

      _ ->
        stream
    end
  end

  defp to_range_end(stream, %Tempo{form: {:when, %Tempo{} = inner, [years: _filter]}}),
    do: to_range_end(stream, inner)

  defp to_range_end(stream, _from), do: stream

  # A count counts from the domain's first member, so a counted recurrence
  # takes all of a domain that has an end, and the window the occurrences.
  defp each_member(domain, first, recurrence, options) do
    options = domain_window(options, recurrence)

    with {:ok, members} <- Spans.spans(domain, options) do
      periods = Stream.flat_map(members, &cadence_periods(&1, first, options))
      {:ok, {:each, on_steps(periods, domain_start(domain), first, recurrence)}}
    end
  end

  # A range in a domain (`{..2019Y,2021Y..}`) is each period of the cadence
  # it holds, from the first the window reaches, as a domain of one range is;
  # a year or a set of years is its periods already.
  defp cadence_periods(
         %Tempo{form: {:span, _from, _to}} = range,
         %Tempo{form: {:span, _domain, %Duration{units: [{unit, _n}]}}},
         options
       ) do
    case Children.walk(range, unit, []) do
      {:ok, periods} -> from_window(periods, options[:within])
      {:error, _} -> [range]
    end
  end

  defp cadence_periods(member, _first, _options), do: [member]

  defp from_window(periods, nil), do: periods

  defp from_window(periods, window) do
    case Spans.window_extent(window) do
      {:ok, {start, _stop}} when is_integer(start) ->
        Stream.drop_while(periods, &Spans.ends_by?(&1, start))

      _none ->
        periods
    end
  end

  # A cadence of several units steps through a domain from its first period:
  # `R/{1848Y..}/P4Y/F…` is every fourth year from 1848.
  defp on_steps(
         members,
         %Tempo{} = start,
         %Tempo{form: {:span, _domain, %Duration{units: [{_unit, n}]} = cadence}} = first,
         recurrence
       )
       when n > 1 do
    case steps(%{first | form: {:span, start, cadence}}, recurrence) do
      {:ok, {:steps, period_at}} -> Stream.filter(members, &on_step?(&1, period_at))
      _no_steps -> members
    end
  end

  defp on_steps(members, _start, _first, _recurrence), do: members

  # The domain's members a window reaches: every one where the rule is
  # counted, as the count counts from the first; and the year before the
  # window too where an occurrence may run on into it from the period before
  # (a holiday from 19 December into January).
  defp domain_window(options, %Tempo{form: {:every, _first, count, _rule}})
       when is_integer(count),
       do: Keyword.delete(options, :within)

  defp domain_window(options, %Tempo{form: {:every, _first, bound, rule}}) do
    if carried_back(bound, rule) == 1, do: Spans.widened(options), else: options
  end

  defp on_step?(member, period_at) do
    start = Spans.start_position(member)
    Spans.start_position(period_at.(index_at(start, period_at, 0, 0))) == start
  end

  # Where a domain's first period begins, if it has a first.
  defp domain_start(%Tempo{form: {:all, [first | _]}}), do: first_start(first)
  defp domain_start(_domain), do: nil

  defp first_start(%Tempo{form: {:span, %Tempo{} = from, _to}}), do: from

  defp first_start(%Tempo{form: {:value, _}} = value) do
    case Spans.spans(value, []) do
      {:ok, spans} -> spans |> Enum.take(1) |> Enum.map(&elem(&1.form, 1)) |> List.first()
      {:error, _} -> nil
    end
  end

  defp first_start(_member), do: nil

  # A domain of exclusions alone (`R/^2022Y/P1Y/F…`) names no period of its
  # own: the window gives the periods, and what the exclusions name is left out.
  # The cadence's periods by number: the first, and each a cadence on.
  defp steps(%Tempo{form: {:span, from, to}} = first, recurrence) do
    with {:ok, [base]} <- Spans.spans(first, []),
         {:ok, cadence} <- cadence(from, to, base, recurrence) do
      # `{:with_extent, k}` gives the period with the extent it was built
      # from, where that is known, so that a walk need not reckon it again;
      # the start of the period after it, which that needs, is kept for it.
      walk = make_ref()

      # Every period is the first moved by whole cadences, so where the
      # first starts is placed once for the walk and not at every step.
      first_start = start_extent(base)

      {:ok,
       {:steps,
        fn
          {:with_extent, k} ->
            occurrence_at(
              base,
              {from, to},
              cadences(cadence, k),
              {recurrence, walk, k, first_start}
            )

          k ->
            occurrence(base, {from, to}, cadences(cadence, k), recurrence)
        end}}
    end
  end

  defp inherited_units(%Tempo{form: {:value, units}} = from, rule, first) do
    rule = picking(rule)

    finest =
      case rule |> with_nested() |> Keyword.take(@rule_units) do
        [] -> :day
        parts -> parts |> Unit.resolution() |> Unit.grain() |> finer_of(cadence_unit(first))
      end

    units
    |> Enum.filter(fn {unit, _} ->
      Unit.compare(Unit.grain(unit), finest) == :gt and not Keyword.has_key?(rule, unit)
    end)
    |> weekday_of_week(rule, from)
  end

  defp inherited_units(_from, _rule, _first), do: []

  # What a rule names includes what a selection within it names: the last
  # Sunday of October names a day, and takes no day from the start.
  defp with_nested(rule) do
    Enum.flat_map(rule, fn
      {:selection, nested} -> with_nested(nested)
      {:all, each} -> Enum.flat_map(each, &with_nested/1)
      part -> [part]
    end)
  end

  # A rule whose parts are coarser than its cadence keeps the periods they
  # name (`FREQ=DAILY;BYMONTH=1` is each day of January), so its start gives
  # it only what is finer than a period.
  defp finer_of(unit, nil), do: unit

  defp finer_of(unit, cadence),
    do: if(Unit.compare(cadence, unit) == :gt, do: cadence, else: unit)

  defp cadence_unit(%Tempo{form: {:span, _from, %Duration{units: [{unit, _}]}}})
       when unit in [:year, :month, :day, :hour, :minute, :second],
       do: unit

  defp cadence_unit(_first), do: nil

  # A rule that names a week and no day of it takes the day of the week its
  # start falls on, where a rule of months takes the start's day of the month.
  defp weekday_of_week(inherited, rule, from) do
    weekday = Tempo.day_of_week(from)

    if Keyword.has_key?(rule, :week) and not Keyword.has_key?(rule, :day_of_week) and
         is_integer(weekday),
       do: [{:day_of_week, weekday} | Keyword.delete(inherited, :day)],
       else: inherited
  end

  defp in_rule_period(period, parts, options) do
    case Select.in_period(period, parts, options) do
      {:ok, picked} -> Enum.flat_map(picked, &with_extent(&1, period, options[:extent]))
      {:error, _} -> []
    end
  end

  # A span of two values picked whole is where the walk placed it.
  defp with_extent(%Tempo{form: {:span, %Tempo{}, %Tempo{}}} = period, period, {_, _} = extent),
    do: [{period, extent}]

  defp with_extent(picked, _period, _extent), do: with_extent(picked)

  # An occurrence and its extent: a value picked is the span it covers.
  defp with_extent(%Tempo{form: {:value, _}} = value) do
    case Spans.extent(value) do
      {:ok, {start, stop} = extent} when is_integer(start) and is_integer(stop) ->
        [{Spans.span_of(value, stop), extent}]

      {:error, exception} ->
        raise exception
    end
  end

  defp with_extent(picked) do
    occurrence = as_span_or_self(picked)

    case Spans.extent(occurrence) do
      {:ok, {start, stop} = extent} when is_integer(start) and is_integer(stop) ->
        [{occurrence, extent}]

      _open ->
        []
    end
  end

  # A window from a selected value, with its end written as a value.
  defp as_span_or_self(%Tempo{form: {:span, %Tempo{}, %Duration{}}} = span) do
    case Spans.resolved(span, []) do
      {:ok, resolved} -> resolved
      {:error, _} -> span
    end
  end

  defp as_span_or_self(other), do: other

  # ── Recurrences ───────────────────────────────────────────────────────

  @doc """
  The occurrences of a recurrence with no rule: the first span moved by n
  cadences for each n, scaled from the first so a month's cadence from the
  31st lands right on every occurrence; a count, an until value or a
  window bounds it, and with none it runs on.
  """
  @spec occurrences(Tempo.t(), term(), Tempo.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def occurrences(%Tempo{form: {:span, from, to}} = first, bound, recurrence, options) do
    with {:ok, [base]} <-
           Spans.spans(%{first | form: {:span, from, to}}, Keyword.delete(options, :within)),
         {:ok, cadence} <- cadence(from, to, base, recurrence),
         {:ok, indexes} <- indexes(from, bound, recurrence),
         {:ok, until} <- until_position(bound) do
      # Each occurrence is made with its extent, as a rule's periods are
      # (`occurrence_at/4`): where the first starts placed once, and where
      # each next starts kept for it. The extents bound and order the
      # occurrences, which are handed back without them.
      walk = make_ref()
      first_start = start_extent(base)

      stream =
        indexes
        |> Stream.map(fn n ->
          base
          |> occurrence_at({from, to}, cadences(cadence, n), {recurrence, walk, n, first_start})
          |> placed()
        end)
        |> Stream.dedup_by(&landing/1)
        |> Stream.map(fn {occurrence, extent} ->
          {%{occurrence | metadata: Map.merge(recurrence.metadata, occurrence.metadata)}, extent}
        end)
        |> bounded(bound, until, options)
        |> Stream.map(fn {occurrence, _extent} -> occurrence end)

      {:ok, stream}
    end
  end

  defp placed({occurrence, nil}), do: {occurrence, Spans.extent(occurrence) |> placed_extent()}
  defp placed(placed), do: placed

  # An extent on a line; on a cycle each occurrence is its own (`landing/1`).
  defp placed_extent({:ok, {start, stop} = extent}) when is_integer(start) and is_integer(stop),
    do: extent

  defp placed_extent(_cycle_or_none), do: nil

  # Where an occurrence starts on a line. Two steps that land on one start
  # (the second having stepped over a day the clock left out) are one
  # occurrence; on a cycle each is its own.
  defp landing({%Tempo{}, {start, _stop}}), do: start
  defp landing({%Tempo{} = occurrence, nil}), do: landing(occurrence)

  defp landing(occurrence) do
    case Spans.extent(occurrence) do
      {:ok, {start, _}} when is_integer(start) -> start
      _ -> make_ref()
    end
  end

  # The position occurrences start before to be kept. An until value bounds a
  # recurrence in an inclusive manner (RFC 5545 section 3.3.10): written to a
  # date it is read through, and written to a time of day an occurrence that
  # starts on it is the last, so the position is the tick after it. A count
  # or none has no position.
  defp until_position(%Tempo{} = until) do
    with {:ok, position} <- Spans.end_position(until) do
      if Spans.clock_resolution?(until), do: {:ok, position + 1}, else: {:ok, position}
    end
  end

  defp until_position(_count_or_infinity), do: {:ok, nil}

  # Forward from the start, or, when the start is a duration, back from the end in order.
  defp indexes(%Duration{}, bound, recurrence) do
    with {:ok, backwards} <- backward_indexes(bound, recurrence),
         do: {:ok, Enum.map(backwards, &(-&1))}
  end

  defp indexes(_from, _bound, _recurrence), do: {:ok, Stream.iterate(0, &(&1 + 1))}

  # The cadence scaled to the nth occurrence, to the one after it and to the one before.
  defp cadences(cadence, n),
    do: {Spans.scaled(cadence, n), Spans.scaled(cadence, n + 1), Spans.scaled(cadence, n - 1)}

  # The nth occurrence. A first span written with a length is one of a series
  # of consecutive spans (ISO 8601-1 3.1.1.11), each ending where the next
  # starts: both of its ends are the first's moved by whole cadences, so a
  # month from 31 January ends on 28 February and the next on 31 March. A
  # first span of two values is moved whole.
  defp occurrence(base, _ends, {%Duration{units: []}, _next, _previous}, _recurrence), do: base

  defp occurrence(
         %Tempo{form: {:span, from, to}} = base,
         {_, %Duration{} = duration},
         {step, next, _previous},
         recurrence
       ) do
    moved = moved_value(from, step, :start, base, recurrence)
    {:ok, {start, _}} = Spans.extent(moved)
    {:ok, {stop, _}} = Spans.extent(moved_value(from, next, :start, base, recurrence))
    stop = later(stop, start, duration, base, recurrence)
    %{base | form: {:span, moved, Spans.value_at(stop, to, :end, base)}}
  end

  defp occurrence(
         %Tempo{form: {:span, from, to}} = base,
         {%Duration{}, _},
         {step, _next, previous},
         recurrence
       ) do
    {:ok, start} = Spans.end_position(moved_value(to, previous, :end, base, recurrence))

    %{
      base
      | form:
          {:span, Spans.value_at(start, from, :start, base),
           moved_value(to, step, :end, base, recurrence)}
    }
  end

  defp occurrence(
         %Tempo{form: {:span, from, to}} = base,
         _ends,
         {step, _next, _previous},
         recurrence
       ) do
    %{
      base
      | form:
          {:span, moved_value(from, step, :start, base, recurrence),
           moved_value(to, step, :end, base, recurrence)}
    }
  end

  # A span written with a length knows its extent as it is built: where it
  # starts, and where the next starts.
  defp occurrence_at(
         %Tempo{form: {:span, from, to}} = base,
         {_, %Duration{} = duration},
         {%Duration{units: [_ | _]} = step, next, _previous},
         {recurrence, walk, k, first_start}
       ) do
    {moved, start} =
      start_at(walk, k, fn -> moved_from(first_start, from, step, :start, base, recurrence) end)

    stop =
      next_start_at(walk, k + 1, fn ->
        moved_from(first_start, from, next, :start, base, recurrence)
      end)

    stop = later(stop, start, duration, base, recurrence)
    {%{base | form: {:span, moved, Spans.value_at(stop, to, :end, base)}}, {start, stop}}
  end

  defp occurrence_at(base, ends, cadences, {recurrence, _walk, _k, _first_start}),
    do: {occurrence(base, ends, cadences, recurrence), nil}

  defp start_extent(%Tempo{form: {:span, %Tempo{} = from, _to}}), do: Spans.extent(from)
  defp start_extent(_base), do: nil

  # The start of the kth period and where it starts: the one the period
  # before it reckoned, where it is the next of the same walk, or reckoned
  # now. One is kept in the process, whichever walk last reckoned one.
  defp start_at(walk, k, moved) do
    case Process.get(@next_start) do
      {^walk, ^k, value, start} -> {value, start}
      _other -> reckoned(moved)
    end
  end

  defp next_start_at(walk, k, moved) do
    {value, start} = reckoned(moved)
    Process.put(@next_start, {walk, k, value, start})
    start
  end

  defp reckoned(moved) do
    value = moved.()
    {:ok, {start, _}} = Spans.extent(value)
    {value, start}
  end

  # Where the next occurrence starts, when that is later; where it is not (the
  # next step lands on the same start past a day a clock left out, or a cycle
  # comes round), the occurrence's own length from its start.
  defp later(stop, start, _duration, _base, _recurrence) when stop > start, do: stop

  defp later(_stop, start, duration, base, recurrence) do
    {:ok, stop} = Spans.shifted(start, duration, Spans.frame_of(base), recurrence)
    stop
  end

  defp backward_indexes(count, _recurrence) when is_integer(count),
    do: {:ok, Enum.to_list((count - 1)..0//-1)}

  defp backward_indexes(_bound, recurrence), do: {:error, conversion(recurrence, :unbounded)}

  # A count counts from the sequence's start and an until ends it; of the
  # occurrences either leaves, a window keeps those that overlap it.
  defp bounded(stream, count, _until, options) when is_integer(count),
    do: stream |> Stream.take(count) |> Spans.windowed(options)

  defp bounded(stream, %Tempo{}, until, options) do
    stream
    |> Stream.take_while(fn occurrence -> Spans.starts_before?(occurrence, until) end)
    |> Spans.windowed(options)
  end

  # With no end of its own a sequence is its occurrences that overlap the window.
  defp bounded(stream, :infinity, _until, options), do: Spans.windowed(stream, options)

  # The cadence of a recurrence: its written duration, else the length of its first span in days or ticks.
  defp cadence(%Duration{} = duration, _to, _base, _recurrence), do: {:ok, duration}
  defp cadence(_from, %Duration{} = duration, _base, _recurrence), do: {:ok, duration}

  defp cadence(from, to, base, recurrence) do
    with {:ok, {start, stop}} <- Spans.extent(base) do
      cond do
        start == nil or stop == nil ->
          {:error, conversion(recurrence, :open)}

        match?({:cycle, _}, Spans.frame(base)) ->
          {:ok, %Duration{units: [second: div(stop - start, Unit.ticks(:second))]}}

        Spans.clock_resolution?(from) or Spans.clock_resolution?(to) ->
          {:ok, %Duration{units: [second: div(stop - start, Unit.ticks(:second))]}}

        true ->
          {:ok, %Duration{units: [day: div(stop - start, @day)]}}
      end
    end
  end

  defp moved_value(%Tempo{} = value, duration, kind, span, recurrence),
    do: moved_from(Spans.extent(value), value, duration, kind, span, recurrence)

  # A value moved by a duration from where it is, its extent given.
  defp moved_from({:ok, {start, stop}}, value, duration, kind, span, recurrence) do
    position = if kind == :end and not Spans.clock_resolution?(value), do: stop, else: start
    {:ok, moved} = Spans.shifted(position, duration, Spans.frame_of(span), recurrence)
    Spans.value_at(moved, value, kind, span)
  end

  defp conversion(expression, reason),
    do: ConversionError.exception(value: expression, reason: reason)
end
