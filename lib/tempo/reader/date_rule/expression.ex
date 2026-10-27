defmodule Tempo.Reader.DateRule.Expression do
  @moduledoc false

  # A date rule's plan (`Tempo.Reader.DateRule.Plan`) built as the Tempo
  # expression it means: a yearly recurrence selecting the rule's date, or a
  # recurrence set of the date and its observed days, or a conditional member
  # for a rule that depends on the other members of a set.
  #
  # What a recurrence selects in each year is a shape, its parts and the
  # calendar they are in, tagged `:base` (the date, which a span extends) or
  # `:observed` (a day an observed-day clause gives). A weekday step is an
  # ISO 8601-2 §12.10 window off the date it steps from, so Tempo resolves
  # month ends and leap years; Easter and its feasts, an equinox, a solstice
  # and a solar term are `Tempo.Event`'s events. The years a rule is kept in
  # (`since`, `prior to`, a year filter, every N years) are the recurrence's
  # domain, and a domain written in Gregorian years is brought to the years
  # of a rule of another calendar.

  alias Tempo.{Duration, Interval, IntervalSet, RecurrenceSet}

  # ISO 8601's days of the week, Monday first: the plan numbers weekdays so,
  # and a selection names them, as a weekday number is counted from the day
  # the expression's weeks begin on.
  @weekday_names [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]
  @all_weekdays 1..7

  # The parts of a plan that say which years and days a date is kept in or
  # moved from, rather than which date it is.
  @gate_keys [
    :substitute,
    :weekday_gate,
    :from_year,
    :to_year,
    :active,
    :year_parity,
    :leap,
    :every_years,
    :conditional,
    :disable,
    :enable,
    :replaced_by,
    :replacements
  ]

  # The parts of a plan that name the years a date falls in, which a date
  # written in one year of its calendar has none of.
  @year_gates [:from_year, :to_year, :active, :year_parity, :leap, :every_years]

  # The gates a `substitutes` entry may have and still stand in for a date:
  # those of its years alone.
  @entry_gates [
    :year_parity,
    :leap,
    :every_years,
    :weekday_gate,
    :conditional,
    :disable,
    :enable,
    :steps,
    :calendar_year
  ]

  @doc false
  @spec build(map(), keyword()) :: {:ok, Tempo.t()} | {:error, String.t() | Exception.t()}
  def build(%{no_date: true}, _options) do
    RecurrenceSet.new([])
  end

  def build(%{conditional: conditional} = plan, options) do
    falls_on = Keyword.get(options, :falls_on, %{type: conditional.type})

    with {:ok, base} <- build(Map.delete(plan, :conditional), []) do
      conditional(base, conditional, plan, falls_on)
    end
  end

  def build(plan, _options) do
    plan = replacing(plan)

    with {:ok, shapes} <- occurrence_shapes(plan),
         {:ok, domain} <- year_domain(plan),
         {:ok, members} <- moved(planned_members(shapes, domain, plan), plan),
         {:ok, recurrences} <- reduce_ok(members, &member_recurrence/1) do
      assembled(Enum.reject(recurrences, &is_nil/1))
    end
  end

  defp assembled([]) do
    {:error, "the rule falls on no day"}
  end

  defp assembled([recurrence]) do
    {:ok, recurrence}
  end

  defp assembled(recurrences) do
    RecurrenceSet.new(recurrences)
  end

  # ── conditional members ───────────────────────────────────────────────

  # A bridge keeps its day when every named date is a member of its type
  # that year; the dates are offsets from it, exact when in its month.
  defp conditional(
         base,
         %{kind: :bridge, on: on},
         %{kind: :fixed, month: month, day: day},
         falls_on
       ) do
    if Enum.all?(on, fn {on_month, _on_day} -> on_month == month end) do
      with {:ok, offsets} <-
             reduce_ok(on, fn {_month, on_day} -> Duration.new(day: on_day - day) end) do
        {:ok, RecurrenceSet.keep_when(base, at: offsets, falls_on: falls_on)}
      end
    else
      {:error, "a bridge to a date in another month is not read yet"}
    end
  end

  # `if is holiday then next <weekday>`: an occurrence on a member of its type
  # moves to the next such weekday.
  defp conditional(
         base,
         %{kind: :if_holiday, move: %{count: 1, direction: :next, target: weekday, omit: []}},
         _plan,
         falls_on
       )
       when weekday in @all_weekdays do
    with {:ok, selector} <- Tempo.new(day_of_week: weekday_name(weekday)) do
      {:ok, RecurrenceSet.move_when(base, falls_on: falls_on, to_next: selector)}
    end
  end

  # `if is holiday then next day omit sunday`: to the next day that is not
  # one of the omitted weekdays.
  defp conditional(
         base,
         %{kind: :if_holiday, move: %{count: 1, direction: :next, target: :day, omit: omit}},
         _plan,
         falls_on
       ) do
    allowed = Enum.reject(@all_weekdays, &(&1 in omit))

    with {:ok, selector} <- Tempo.new(day_of_week: weekday_names(allowed)) do
      {:ok, RecurrenceSet.move_when(base, falls_on: falls_on, to_next: selector)}
    end
  end

  defp conditional(_base, _conditional, _plan, _falls_on) do
    {:error, "this if is holiday move is not read yet"}
  end

  # ── occurrence shapes ─────────────────────────────────────────────────

  # A date stepped from another is a window off it for each step, the one
  # nearest the date first.
  defp occurrence_shapes(%{steps: steps} = plan) do
    if gated?(plan) do
      {:error, "an observed day or weekday gate on a stepped date is not read yet"}
    else
      with {:ok, anchor} <- unstepped_shape(Map.delete(plan, :steps)) do
        {:ok, [{:base, Enum.reduce(steps, anchor, &stepped_shape/2)}]}
      end
    end
  end

  defp occurrence_shapes(%{kind: kind} = plan) when kind in [:easter, :orthodox] do
    {:ok, easter_gated_shapes(plan)}
  end

  defp occurrence_shapes(plan) do
    if gated?(plan) do
      gated_shapes(plan)
    else
      with {:ok, shape} <- base_shape(plan) do
        {:ok, [{:base, shape}]}
      end
    end
  end

  defp gated?(plan) do
    match?([_ | _], Map.get(plan, :substitute)) or Map.has_key?(plan, :weekday_gate) or
      Map.has_key?(plan, :replacements)
  end

  defp unstepped_shape(%{kind: kind, offset: offset}) when kind in [:easter, :orthodox] do
    {:ok, easter_shape(kind, offset)}
  end

  defp unstepped_shape(plan) do
    base_shape(plan)
  end

  defp stepped_shape(step, %{parts: parts, calendar: calendar}) do
    shape([selection: parts] ++ step_window(step, calendar), calendar)
  end

  # date-holidays steps a count of days either way; a weekday after a date is
  # on or after it, one next after it is strictly after, and one before or
  # previous to it is strictly before.
  defp step_window(%{days: count, direction: direction}, _calendar)
       when direction in [:after, :next] do
    [window: days(count + 1), day_of_week: @all_weekdays, instance: -1]
  end

  defp step_window(%{days: count}, _calendar) do
    [window: days(-count), day_of_week: @all_weekdays, instance: 1]
  end

  defp step_window(%{weekday: weekday, count: count, direction: :after}, calendar) do
    [window: days(week(calendar) * count), day_of_week: weekday, instance: -1]
  end

  defp step_window(%{weekday: weekday, count: count, direction: :next}, calendar) do
    [window: days(week(calendar) * count + 1), day_of_week: weekday, instance: -1]
  end

  defp step_window(%{weekday: weekday, count: count}, calendar) do
    [window: days(-week(calendar) * count), day_of_week: weekday, instance: 1]
  end

  defp shape(parts, calendar \\ Tempo.Calendar.default()) do
    %{parts: parts, calendar: calendar}
  end

  defp days(count) do
    Duration.new!(day: count)
  end

  defp week(calendar) do
    Tempo.Calendar.days_in_week(calendar)
  end

  defp base_shape(%{kind: :weekday} = plan) do
    {:ok, weekday_shape(plan)}
  end

  defp base_shape(%{kind: :relative_weekday} = plan) do
    window = relative_weekday_window(plan.direction, plan.count, plan.weekday)
    {:ok, shape([selection: [month: plan.month, day: plan.day]] ++ window)}
  end

  defp base_shape(%{kind: :nested_weekday} = plan) do
    inner = [month: plan.month, day_of_week: plan.inner_weekday, instance: plan.count]
    {:ok, shape([selection: inner] ++ relative_weekday_window(plan.direction, 1, plan.weekday))}
  end

  defp base_shape(%{kind: :nested_after_date} = plan) do
    inner =
      [selection: [month: plan.month, day: plan.day]] ++
        relative_weekday_window(:after, plan.count, plan.inner_weekday)

    {:ok, shape([selection: inner] ++ relative_weekday_window(plan.direction, 1, plan.weekday))}
  end

  defp base_shape(plan) do
    case plain_anchor(plan) do
      {:ok, anchor, calendar} -> {:ok, shape(anchor, calendar)}
      :none -> offset_base_shape(plan)
    end
  end

  # The nth weekday of a month, the first to the fourth (a fifth is a window
  # from the first of the month, which runs on into the next).
  defp weekday_shape(%{month: month, count: count, weekday: weekday}) do
    shape(month: month, day_of_week: weekday, instance: count)
  end

  # A day at or past the end of an Islamic month (date-holidays' `30
  # Ramadan`) is the first of the month and `day - 1` days on: the last day
  # of the `day`-long window from the first.
  defp offset_base_shape(%{kind: :islamic, calendar: calendar, month: month, day: day})
       when day >= 30 do
    window = [window: days(day), day_of_week: 1..7, instance: -1]
    {:ok, shape([selection: [month: month, day: 1]] ++ window, calendar)}
  end

  # A lunisolar day and its offset fold into one day of the month; at or
  # before the eve (`day 0`, the day before the first) it is a window back
  # from the traditional month's first day.
  defp offset_base_shape(%{kind: :lunisolar, calendar: calendar} = plan) do
    case plan.day + plan.offset do
      net_day when net_day <= 0 ->
        first_day = [traditional_month: traditional_month(plan), day: 1]
        window = [window: days(-(1 - net_day)), day_of_week: 1..7, instance: 1]
        {:ok, shape([selection: first_day] ++ window, calendar)}

      _later_day ->
        {:error, "a lunisolar date shifted past its month is not read yet"}
    end
  end

  defp offset_base_shape(_plan) do
    {:error, "this date is not read yet"}
  end

  # The plain date a rule falls on: the anchor a weekday gate limits and an
  # observed day's window opens from. `:none` for a date that is a window off
  # another, which `offset_base_shape/1` builds.
  defp plain_anchor(%{kind: :fixed, month: month, day: day}) do
    {:ok, [month: month, day: day], Tempo.Calendar.default()}
  end

  defp plain_anchor(%{kind: :hebrew, calendar: calendar, month_part: month_part, day: day}) do
    {:ok, [month_part, day: day], calendar}
  end

  defp plain_anchor(%{kind: kind, calendar: calendar, month: month, day: day})
       when kind in [:persian, :julian] do
    {:ok, [month: month, day: day], calendar}
  end

  defp plain_anchor(%{kind: :islamic, calendar: calendar, month: month, day: day})
       when day <= 29 do
    {:ok, [month: month, day: day], calendar}
  end

  defp plain_anchor(%{kind: kind, month: month, offset: 0, timezone: timezone})
       when kind in [:equinox, :solstice] do
    {:ok, [event: event_with_zone(solar_event_name(kind, month), timezone)],
     Tempo.Calendar.default()}
  end

  defp plain_anchor(%{kind: :solar_term, count: term, day: 1}) do
    case solar_term_name(term) do
      {:ok, name} -> {:ok, [event: name], Tempo.Calendar.default()}
      :error -> :none
    end
  end

  defp plain_anchor(%{kind: :lunisolar, calendar: calendar, day: day, offset: offset} = plan)
       when day + offset >= 1 do
    {:ok, [traditional_month: traditional_month(plan), day: day + offset], calendar}
  end

  defp plain_anchor(_plan) do
    :none
  end

  defp traditional_month(%{month: month, leap_month: true}) do
    {month, :leap}
  end

  defp traditional_month(%{month: month}) do
    month
  end

  defp solar_event_name(:equinox, 3) do
    "march-equinox"
  end

  defp solar_event_name(:equinox, 9) do
    "september-equinox"
  end

  defp solar_event_name(:solstice, 6) do
    "june-solstice"
  end

  defp solar_event_name(:solstice, 12) do
    "december-solstice"
  end

  defp event_with_zone(name, nil) do
    name
  end

  defp event_with_zone(name, zone) do
    {name, zone}
  end

  defp solar_term_name(term) do
    names = Tempo.Calendar.solar_term_names()

    case Enum.find(names, fn {_name, number} -> number == term end) do
      {name, _number} -> {:ok, name}
      nil -> :error
    end
  end

  # ── Easter and its feasts ─────────────────────────────────────────────

  defp easter_event(:orthodox) do
    "orthodox-easter"
  end

  defp easter_event(:easter) do
    "easter"
  end

  defp easter_shape(kind, 0) do
    shape(event: easter_event(kind))
  end

  defp easter_shape(kind, offset) do
    shape([selection: [event: easter_event(kind)]] ++ easter_offset_window(offset))
  end

  # The window that picks `easter + offset` off `(easter)e`: forward, the last
  # of its weekday, for a positive offset; back, the first, for a negative.
  defp easter_offset_window(offset) when offset > 0 do
    [window: days(offset + 1), day_of_week: easter_offset_weekday(offset), instance: -1]
  end

  defp easter_offset_window(offset) do
    [window: days(offset - 1), day_of_week: easter_offset_weekday(offset), instance: 1]
  end

  # Easter is a Sunday, the seventh day of ISO 8601's week.
  defp easter_offset_weekday(offset) do
    Integer.mod(offset - 1, week(Tempo.Calendar.default())) + 1
  end

  # The window that picks the count-th weekday from a date: back, the
  # earliest, for "before"; forward, the latest, for "after", which is on or
  # after the date.
  defp relative_weekday_window(:before, count, target) do
    [window: days(-week(Tempo.Calendar.default()) * count), day_of_week: target, instance: 1]
  end

  defp relative_weekday_window(:after, count, target) do
    [window: days(week(Tempo.Calendar.default()) * count), day_of_week: target, instance: -1]
  end

  # ── weekday gates and observed days ───────────────────────────────────

  # The date is kept on the weekdays that keep it, those of its gate less the
  # ones a clause moves it from (unless the clause adds the observed day), and
  # none where a `substitutes` clause did not fire; each clause that fires is
  # a window off the date, limited to its weekdays.
  defp gated_shapes(plan) do
    case plain_anchor(plan) do
      {:ok, anchor, calendar} -> gated_pieces(plan, anchor, calendar)
      :none -> {:error, "an observed day or weekday gate on this date is not read yet"}
    end
  end

  defp gated_pieces(plan, anchor, calendar) do
    with {:ok, pieces} <- replacement_pieces(plan) do
      {:ok, gated_shapes(plan, anchor, calendar, pieces)}
    end
  end

  # The date is a member for each run of years that keeps the same weekdays,
  # a substitute entry taking its weekdays away in the years it stands in.
  defp gated_shapes(plan, anchor, calendar, pieces) do
    gate = gate_weekdays(Map.get(plan, :weekday_gate))
    {kept, observed} = substitution_plan(Map.get(plan, :substitute, []), gate)

    base =
      for {ranges, replaced} <- pieces,
          weekdays = kept -- replaced,
          match?([_ | _], weekdays) do
        {:base, limited_shape(anchor, calendar, weekdays), ranges}
      end

    windows =
      for {weekdays, direction, target, span} <- observed, match?([_ | _], weekdays) do
        {:observed, spanned(observed_shape(anchor, calendar, weekdays, direction, target), span)}
      end

    base ++ windows
  end

  defp gate_weekdays(nil) do
    Enum.to_list(@all_weekdays)
  end

  defp gate_weekdays({:only, weekdays}) do
    Enum.filter(@all_weekdays, &(&1 in weekdays))
  end

  defp gate_weekdays({:except, weekdays}) do
    Enum.reject(@all_weekdays, &(&1 in weekdays))
  end

  # The clauses in order: each fires on the allowed weekdays no earlier
  # clause claimed. The weekdays that keep the date, and each clause's
  # `{weekdays, direction, target, span}`.
  defp substitution_plan(clauses, allowed) do
    {observed, claimed, added} =
      Enum.reduce(clauses, {[], [], []}, fn {triggers, direction, target, mode, span},
                                            {observed, claimed, added} ->
        fires = Enum.filter(allowed, &(&1 in triggers and &1 not in claimed))
        observed = observed ++ [{fires, direction, target, span}]
        {observed, claimed ++ triggers, added(added, fires, mode)}
      end)

    untriggered = untriggered(clauses, allowed, claimed)
    {Enum.sort(untriggered ++ added), observed}
  end

  defp added(added, fires, :add) do
    added ++ fires
  end

  defp added(added, _fires, _mode) do
    added
  end

  defp untriggered(clauses, allowed, claimed) do
    if substitute_only?(clauses) do
      []
    else
      Enum.reject(allowed, &(&1 in claimed))
    end
  end

  defp substitute_only?(clauses) do
    Enum.any?(clauses, &(elem(&1, 3) == :substitute_only))
  end

  defp limited_shape(anchor, calendar, weekdays) do
    if weekdays == Enum.to_list(@all_weekdays) do
      shape(anchor, calendar)
    else
      shape(anchor ++ [day_of_week: weekday_set(weekdays)], calendar)
    end
  end

  defp observed_shape(anchor, calendar, weekdays, direction, target) do
    limit =
      if weekdays == Enum.to_list(@all_weekdays) do
        []
      else
        [day_of_week: weekday_set(weekdays)]
      end

    shape([selection: anchor ++ limit] ++ observed_window(direction, target, calendar), calendar)
  end

  # date-holidays observes a clause's weekday strictly after or before the
  # date, a full week on when it is the date's own weekday: the last in the
  # week and a day from the date, or the first in the week before it.
  defp observed_window(:next, target, calendar) do
    [window: days(week(calendar) + 1), day_of_week: target, instance: -1]
  end

  defp observed_window(:previous, target, calendar) do
    [window: days(-week(calendar)), day_of_week: target, instance: 1]
  end

  # A set of weekdays as a selection holds it: one bare, runs as ranges.
  defp weekday_set([weekday]) do
    weekday
  end

  defp weekday_set(weekdays) do
    weekdays
    |> Enum.chunk_while([], &extend_run/2, &close_run/1)
    |> Enum.map(&weekday_run/1)
  end

  defp extend_run(weekday, [previous | _] = run) when weekday == previous + 1 do
    {:cont, [weekday | run]}
  end

  defp extend_run(weekday, []) do
    {:cont, [weekday]}
  end

  defp extend_run(weekday, run) do
    {:cont, Enum.reverse(run), [weekday]}
  end

  defp close_run([]) do
    {:cont, []}
  end

  defp close_run(run) do
    {:cont, Enum.reverse(run), []}
  end

  defp weekday_run([first, _second | _rest] = run) do
    first..List.last(run)
  end

  defp weekday_run([weekday]) do
    weekday
  end

  # Easter is a Sunday, so a feast's weekday is fixed: a gate always or never
  # admits it, and the first clause that fires on it moves it to another
  # fixed offset.
  defp easter_gated_shapes(%{kind: kind, offset: offset} = plan) do
    weekday = easter_offset_weekday(offset)
    clauses = Map.get(plan, :substitute, [])

    if weekday in gate_weekdays(Map.get(plan, :weekday_gate)) do
      clauses
      |> Enum.find(fn {triggers, _direction, _target, _mode, _span} -> weekday in triggers end)
      |> easter_observed(kind, offset, weekday, clauses)
    else
      []
    end
  end

  defp easter_observed(nil, kind, offset, _weekday, clauses) do
    if substitute_only?(clauses) do
      []
    else
      [{:base, easter_shape(kind, offset)}]
    end
  end

  defp easter_observed(
         {_triggers, direction, target, mode, span},
         kind,
         offset,
         weekday,
         _clauses
       ) do
    shift = observed_shift(weekday, direction, target)
    observed = {:observed, spanned(easter_shape(kind, offset + shift), span)}

    if mode == :add do
      [{:base, easter_shape(kind, offset)}, observed]
    else
      [observed]
    end
  end

  defp observed_shift(weekday, :next, target) do
    week = week(Tempo.Calendar.default())
    nonzero(Integer.mod(target - weekday, week), week)
  end

  defp observed_shift(weekday, :previous, target) do
    week = week(Tempo.Calendar.default())
    nonzero(-Integer.mod(weekday - target, week), -week)
  end

  defp nonzero(0, fallback) do
    fallback
  end

  defp nonzero(shift, _fallback) do
    shift
  end

  # ── the years a rule is kept in ───────────────────────────────────────

  # A date written in a year of its own calendar (`31 Shahrivar 1401`) is in
  # that one year of it, and a solar term in a lunisolar year named by its
  # cycle (`chinese 78-32-8-15 solarterm`) in the Gregorian year that year
  # begins in.
  defp year_domain(%{lunisolar_year: {calendar, year}} = plan) do
    with :ok <- one_year_only(plan),
         {:ok, gregorian} <- gregorian_year_begun(calendar, year) do
      {:ok, %{ranges: [{gregorian, gregorian}], filter: nil, cadence: 1}}
    end
  end

  defp year_domain(%{calendar_year: year} = plan) do
    with :ok <- one_year_only(plan) do
      {:ok, %{ranges: [{year, year}], filter: nil, cadence: 1, own_years: true}}
    end
  end

  defp year_domain(plan) do
    with {:ok, filter} <- domain_filter(plan),
         {:ok, ranges} <- active_ranges(plan),
         {:ok, cadence} <- domain_cadence(plan, ranges) do
      {:ok, %{ranges: ranges, filter: filter, cadence: cadence}}
    end
  end

  defp one_year_only(plan) do
    if Enum.any?(@year_gates, &is_map_key(plan, &1)) do
      {:error, "a date in a year of its own calendar is in no other years"}
    else
      :ok
    end
  end

  defp gregorian_year_begun(calendar, year) do
    with {:ok, new_year} <- Tempo.new(year: year, month: 1, day: 1, calendar: calendar),
         {:ok, there} <- Tempo.to_calendar(new_year, Tempo.Calendar.default()) do
      {:ok, Tempo.year(there)}
    end
  end

  defp domain_filter(%{year_parity: _parity, leap: _leap}) do
    {:error, "a year both even or odd and leap or not is not read yet"}
  end

  defp domain_filter(%{year_parity: :even}) do
    {:ok, :even}
  end

  defp domain_filter(%{year_parity: :odd}) do
    {:ok, :odd}
  end

  defp domain_filter(%{leap: :leap}) do
    {:ok, :leap}
  end

  defp domain_filter(%{leap: :non_leap}) do
    {:ok, :common}
  end

  defp domain_filter(_plan) do
    {:ok, nil}
  end

  # Every N years counts from the `since` year, where the domain starts.
  defp domain_cadence(%{every_years: every, from_year: from}, [{from, _to}]) do
    {:ok, every}
  end

  defp domain_cadence(%{every_years: _every}, _ranges) do
    {:error, "every N years without since is not read yet"}
  end

  defp domain_cadence(_plan, _ranges) do
    {:ok, 1}
  end

  # `since` and `prior to` are an inclusive range of years (`to_year` is
  # exclusive). A date-precise window keeps the years whose occurrence is in
  # it, found by asking for the occurrence in its first and last years; a
  # rule is in the years of any of its windows, each within `since` and
  # `prior to`.
  defp active_ranges(%{active: [_ | _] = windows} = plan) do
    with {:ok, ranges} <- reduce_ok(windows, &window_years(plan, &1)) do
      {:ok, Enum.flat_map(ranges, &List.wrap(intersect_ranges(&1, since_until(plan))))}
    end
  end

  defp active_ranges(plan) do
    {:ok, [since_until(plan)]}
  end

  defp window_years(plan, {from, to}) do
    with {:ok, first} <- first_active_year(plan, from),
         {:ok, last} <- last_active_year(plan, to) do
      {:ok, {first, last}}
    end
  end

  defp since_until(plan) do
    {Map.get(plan, :from_year), last_year(Map.get(plan, :to_year))}
  end

  defp last_year(nil) do
    nil
  end

  defp last_year(to_year) do
    to_year - 1
  end

  defp first_active_year(_plan, nil) do
    {:ok, nil}
  end

  defp first_active_year(plan, %Date{year: year} = from) do
    with {:ok, days} <- base_days_in(plan, year) do
      if Enum.any?(days, &(&1 >= Date.to_gregorian_days(from))) do
        {:ok, year}
      else
        {:ok, year + 1}
      end
    end
  end

  defp last_active_year(_plan, nil) do
    {:ok, nil}
  end

  defp last_active_year(plan, %Date{year: year} = to) do
    with {:ok, days} <- base_days_in(plan, year) do
      if Enum.any?(days, &(&1 < Date.to_gregorian_days(to))) do
        {:ok, year}
      else
        {:ok, year - 1}
      end
    end
  end

  # The Gregorian day numbers of the rule's occurrences in a Gregorian year.
  defp base_days_in(plan, year) do
    base =
      Map.drop(plan, [
        :active,
        :from_year,
        :to_year,
        :substitute,
        :weekday_gate,
        :disable,
        :enable,
        :replacements
      ])

    with {:ok, recurrence} <- build(base, []),
         {:ok, within} <- Tempo.new(year: year),
         {:ok, occurrences} <- Tempo.to_interval(recurrence, within: within) do
      occurrences
      |> IntervalSet.members()
      |> reduce_ok(&first_day/1)
    end
  end

  defp first_day(occurrence) do
    with {:ok, date} <- Tempo.to_date(Interval.from(occurrence)),
         {:ok, gregorian} <- Date.convert(date, Calendar.ISO) do
      {:ok, Date.to_gregorian_days(gregorian)}
    end
  end

  defp intersect_ranges({from_1, to_1}, {from_2, to_2}) do
    from = later(from_1, from_2)
    to = earlier(to_1, to_2)

    if is_integer(from) and is_integer(to) and from > to do
      nil
    else
      {from, to}
    end
  end

  defp later(nil, year) do
    year
  end

  defp later(year, nil) do
    year
  end

  defp later(year_1, year_2) do
    max(year_1, year_2)
  end

  defp earlier(nil, year) do
    year
  end

  defp earlier(year, nil) do
    year
  end

  defp earlier(year_1, year_2) do
    min(year_1, year_2)
  end

  # ── substitute entries ────────────────────────────────────────────────

  # The `substitutes` entries that stand in for the rule's date: those of
  # the same date, gated by their years alone, for a rule that is a plain
  # date with no observed day of its own. Each takes its trigger weekdays
  # from the date in the years it is in force; the others are passed over.
  defp replacing(%{replaced_by: entries} = plan) do
    plan = Map.delete(plan, :replaced_by)
    replacements = for entry <- entries, substitutes?(entry, plan), do: replacement(entry)
    with_replacements(plan, replacements)
  end

  defp replacing(plan) do
    plan
  end

  defp with_replacements(plan, []) do
    plan
  end

  defp with_replacements(plan, [_ | _] = replacements) do
    Map.put(plan, :replacements, replacements)
  end

  defp substitutes?(entry, plan) do
    substitute_entry?(entry) and plain_date?(plan) and years_only?(entry) and
      date_of(entry) == date_of(plan)
  end

  defp substitute_entry?(%{substitute: [_ | _] = clauses}) do
    Enum.all?(clauses, &(elem(&1, 3) == :substitute_only))
  end

  defp substitute_entry?(_plan) do
    false
  end

  defp plain_date?(plan) do
    not Enum.any?([:substitute, :conditional, :steps], &is_map_key(plan, &1)) and
      match?({:ok, _anchor, _calendar}, plain_anchor(plan))
  end

  defp years_only?(entry) do
    not Enum.any?(@entry_gates, &is_map_key(entry, &1))
  end

  defp date_of(plan) do
    plan
    |> Map.drop(@gate_keys)
    |> Map.put(:one_year, one_year?(plan))
  end

  defp one_year?(%{from_year: from, to_year: to}) do
    is_integer(from) and to == from + 1
  end

  defp one_year?(_plan) do
    false
  end

  defp replacement(%{substitute: clauses} = entry) do
    triggers =
      clauses
      |> Enum.flat_map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.sort()

    %{
      triggers: triggers,
      from_year: Map.get(entry, :from_year),
      to_year: Map.get(entry, :to_year),
      active: Map.get(entry, :active, [])
    }
  end

  # The runs of years the date keeps different weekdays in, each with the
  # weekdays taken from it, the entries' years decided on the rule's own
  # date as its `active` windows are. With no entry, every year keeps every
  # weekday.
  defp replacement_pieces(%{replacements: replacements} = plan) do
    with {:ok, spans} <- reduce_ok(replacements, &replacement_span(plan, &1)) do
      pieces =
        spans
        |> year_runs()
        |> Enum.map(&{&1, replaced_in(&1, spans)})
        |> Enum.chunk_by(&elem(&1, 1))
        |> Enum.map(&joined_runs/1)

      {:ok, pieces}
    end
  end

  defp replacement_pieces(_plan) do
    {:ok, [{[{nil, nil}], []}]}
  end

  defp replacement_span(plan, %{triggers: triggers} = entry) do
    in_force =
      plan
      |> Map.drop([:from_year, :to_year, :active])
      |> put_present(:from_year, entry.from_year)
      |> put_present(:to_year, entry.to_year)
      |> put_present(:active, entry.active)

    with {:ok, ranges} <- active_ranges(in_force) do
      {:ok, {ranges, triggers}}
    end
  end

  defp put_present(plan, _key, value) when value in [nil, []] do
    plan
  end

  defp put_present(plan, key, value) do
    Map.put(plan, key, value)
  end

  # The runs of years between every bound the entries' years name.
  defp year_runs(spans) do
    bounds =
      spans
      |> Enum.flat_map(fn {ranges, _triggers} -> Enum.flat_map(ranges, &range_bounds/1) end)
      |> Enum.uniq()
      |> Enum.sort()

    Enum.zip([nil | bounds], Enum.map(bounds, &(&1 - 1)) ++ [nil])
  end

  defp range_bounds({from, to}) do
    Enum.reject([from, year_after(to)], &is_nil/1)
  end

  # The weekdays the entries in force through a run take from it. The runs
  # split at every bound, so each lies wholly inside an entry's years or
  # wholly outside them.
  defp replaced_in(run, spans) do
    spans
    |> Enum.filter(fn {ranges, _triggers} -> Enum.any?(ranges, &covers?(&1, run)) end)
    |> Enum.flat_map(fn {_ranges, triggers} -> triggers end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Consecutive runs that keep the same weekdays are one run of years.
  defp joined_runs([{{from, _to}, weekdays} | _rest] = runs) do
    {{_from, to}, _weekdays} = List.last(runs)
    {[{from, to}], weekdays}
  end

  defp covers?({from, to}, {run_from, run_to}) do
    not_before?(run_from, from) and not_after?(run_to, to)
  end

  defp not_before?(_year, nil) do
    true
  end

  defp not_before?(nil, _from) do
    false
  end

  defp not_before?(year, from) do
    year >= from
  end

  defp not_after?(_year, nil) do
    true
  end

  defp not_after?(nil, _to) do
    false
  end

  defp not_after?(year, to) do
    year <= to
  end

  # ── a disabled date moved to the enabled ones ─────────────────────────

  # date-holidays' `disable` and `enable` move an occurrence: where a
  # disabled date is one of the rule's occurrences in its year, it is
  # dropped and that year's enabled dates are added in its place. The
  # member that gives the disabled date leaves out the year of its own
  # calendar the date is in, so its other occurrences in that Gregorian year
  # stay, and each enabled date is a member of that one year. A disabled date
  # the rule does not fall on moves nothing, and an enabled date is added
  # only for a disabled one.
  defp moved(members, %{disable: disable} = plan) do
    blocked = MapSet.new(disable, &Date.to_gregorian_days/1)
    years = Enum.uniq(Enum.map(disable, & &1.year))

    moved_years(years, members, blocked, Map.get(plan, :enable, []))
  end

  defp moved(members, _plan) do
    {:ok, members}
  end

  defp moved_years([], members, _blocked, _enable) do
    {:ok, members}
  end

  defp moved_years([year | years], members, blocked, enable) do
    with {:ok, matches} <- reduce_ok(members, &member_match(&1, year, blocked)) do
      members
      |> moved_in(matches, year, enable)
      |> then(&moved_years(years, &1, blocked, enable))
    end
  end

  defp moved_in(members, matches, year, enable) do
    if Enum.any?(matches, &match?({:matched, _date}, &1)) do
      moved =
        members
        |> Enum.zip(matches)
        |> Enum.map(&moved_member/1)

      moved ++ enabled_members(enable, year)
    else
      members
    end
  end

  # Whether one of a member's occurrences in a Gregorian year is a disabled
  # date, and which.
  defp member_match(member, year, blocked) do
    with {:ok, days} <- member_days_in(member, year) do
      {:ok, matched(Enum.find(days, &MapSet.member?(blocked, &1)))}
    end
  end

  defp matched(nil) do
    :none
  end

  defp matched(disabled) do
    {:matched, Date.from_gregorian_days(disabled)}
  end

  defp member_days_in(%{shape: shape, domain: domain}, year) do
    case built_member(shape, domain) do
      {:ok, recurrence} -> days_in(recurrence, year)
      :never -> {:ok, []}
      {:error, _reason} = error -> error
    end
  end

  defp days_in(recurrence, year) do
    with {:ok, within} <- Tempo.new(year: year),
         {:ok, occurrences} <- Tempo.to_interval(recurrence, within: within) do
      occurrences
      |> IntervalSet.members()
      |> reduce_ok(&first_day/1)
    end
  end

  defp moved_member({member, :none}) do
    member
  end

  defp moved_member({%{domain: domain} = member, {:matched, disabled}}) do
    %{member | domain: Map.update(domain, :exclusions, [disabled], &[disabled | &1])}
  end

  defp enabled_members(enable, year) do
    for %Date{year: ^year} = date <- enable do
      enabled_member(date)
    end
  end

  defp enabled_member(%Date{year: year, month: month, day: day}) do
    domain = %{ranges: [{year, year}], filter: nil, cadence: 1}
    %{role: :enabled, shape: shape(month: month, day: day), domain: domain}
  end

  # A member's domain less the years of its disabled dates, each the year of
  # the member's calendar the date is in.
  defp without_excluded(%{exclusions: [_ | _] = disabled} = domain, %{calendar: calendar}) do
    with {:ok, years} <- reduce_ok(disabled, &year_in_calendar(&1, calendar)) do
      {:ok, %{domain | ranges: Enum.reduce(years, domain.ranges, &without_year/2)}}
    end
  end

  defp without_excluded(domain, _shape) do
    {:ok, domain}
  end

  defp without_year(year, ranges) do
    Enum.flat_map(ranges, &range_without(&1, year))
  end

  defp range_without({from, to} = range, year) do
    if in_range?(range, year) do
      Enum.reject([{from, year - 1}, {year + 1, to}], &empty_range?/1)
    else
      [range]
    end
  end

  defp in_range?({from, to}, year) do
    (is_nil(from) or from <= year) and (is_nil(to) or year <= to)
  end

  # ── members ───────────────────────────────────────────────────────────

  # Each shape a member in its role, over the rule's years or those of them
  # its run of years has.
  defp planned_members(shapes, domain, plan) do
    for shape <- shapes do
      planned_member(shape, domain, plan)
    end
  end

  defp planned_member({role, shape}, domain, plan) do
    %{role: role, shape: role_shape(role, shape, plan), domain: domain}
  end

  defp planned_member({role, shape, ranges}, %{ranges: domain_ranges} = domain, plan) do
    domain = %{domain | ranges: intersect_range_lists(domain_ranges, ranges)}
    %{role: role, shape: role_shape(role, shape, plan), domain: domain}
  end

  defp intersect_range_lists(ranges, others) do
    for range <- ranges,
        other <- others,
        overlap = intersect_ranges(range, other),
        not is_nil(overlap) do
      overlap
    end
  end

  defp member_recurrence(%{role: role, shape: shape, domain: domain}) do
    case built_member(shape, domain) do
      {:ok, recurrence} -> {:ok, role_metadata(recurrence, role)}
      :never -> {:ok, nil}
      {:error, _reason} = error -> error
    end
  end

  # The base carries the rule's span, an observed day its clause's (given it
  # where it is made); an observed day is marked.
  defp role_shape(:base, shape, %{span: span}) do
    spanned(shape, span)
  end

  defp role_shape(_role, shape, _plan) do
    shape
  end

  # A date that lasts more than a day is a window of its days from it.
  defp spanned(%{parts: parts} = shape, span) when span > 1 do
    %{shape | parts: [selection: parts, window: days(span)]}
  end

  defp spanned(shape, _span) do
    shape
  end

  defp role_metadata(recurrence, :observed) do
    Tempo.put_metadata(recurrence, %{substitute: true})
  end

  defp role_metadata(recurrence, _role) do
    recurrence
  end

  defp built_member(%{ranges: []}, _domain) do
    :never
  end

  defp built_member(shape, domain) do
    with {:ok, domain} <- domain_in_calendar(domain, shape),
         {:ok, domain} <- without_excluded(domain, shape) do
      every_year(domain, shape)
    end
  end

  defp every_year(%{ranges: []}, _shape) do
    :never
  end

  defp every_year(domain, %{parts: parts, calendar: calendar}) do
    with {:ok, from} <- domain_set(domain, calendar) do
      options =
        [select: named_weekdays(parts), calendar: calendar]
        |> with_option(:from, from)
        |> with_option(:years, domain.filter)

      Tempo.every(Duration.new!(year: domain.cadence), options)
    end
  end

  defp with_option(options, _key, nil) do
    options
  end

  defp with_option(options, key, value) do
    Keyword.put(options, key, value)
  end

  defp named_weekdays(parts) when is_list(parts) do
    Enum.map(parts, &named_weekday_part/1)
  end

  defp named_weekday_part({:day_of_week, held}) do
    {:day_of_week, weekday_names(held)}
  end

  defp named_weekday_part({:selection, parts}) do
    {:selection, named_weekdays(parts)}
  end

  defp named_weekday_part(part) do
    part
  end

  defp weekday_names(day) when day in @all_weekdays do
    weekday_name(day)
  end

  defp weekday_names(%Range{} = days) do
    Enum.map(days, &weekday_name/1)
  end

  defp weekday_names(days) when is_list(days) do
    Enum.flat_map(days, &List.wrap(weekday_names(&1)))
  end

  defp weekday_name(day) do
    Enum.at(@weekday_names, day - 1)
  end

  # ── a Gregorian domain in another calendar ────────────────────────────

  # A rule's years are Gregorian years, as date-holidays reckons them; a
  # recurrence in another calendar has its domain in that calendar's years,
  # the years whose occurrence starts in the Gregorian ones.
  defp domain_in_calendar(%{ranges: [{nil, nil}], filter: nil, cadence: 1} = domain, _shape) do
    {:ok, domain}
  end

  defp domain_in_calendar(%{own_years: true} = domain, _shape) do
    {:ok, domain}
  end

  defp domain_in_calendar(domain, %{calendar: calendar} = shape) do
    if Tempo.Calendar.gregorian?(calendar) do
      {:ok, domain}
    else
      domain_of_calendar(domain, shape, calendar)
    end
  end

  defp domain_of_calendar(%{filter: filter, cadence: cadence}, _shape, _calendar)
       when not is_nil(filter) or cadence != 1 do
    {:error, "a year filter on a date of another calendar is not read yet"}
  end

  defp domain_of_calendar(%{ranges: ranges} = domain, shape, calendar) do
    with {:ok, ranges} <- reduce_ok(ranges, &range_in(&1, shape, calendar)) do
      {:ok, %{domain | ranges: Enum.reject(ranges, &empty_range?/1)}}
    end
  end

  defp range_in({from, to}, shape, calendar) do
    with {:ok, first} <- first_year_on_or_after(from, shape, calendar),
         {:ok, next} <- first_year_on_or_after(year_after(to), shape, calendar) do
      {:ok, {first, year_before(next)}}
    end
  end

  defp year_after(nil) do
    nil
  end

  defp year_after(year) do
    year + 1
  end

  defp year_before(nil) do
    nil
  end

  defp year_before(year) do
    year - 1
  end

  defp empty_range?({from, to}) when is_integer(from) and is_integer(to) do
    from > to
  end

  defp empty_range?(_open) do
    false
  end

  # The first year of the calendar whose occurrence starts on or after the
  # first of January of a Gregorian year.
  defp first_year_on_or_after(nil, _shape, _calendar) do
    {:ok, nil}
  end

  defp first_year_on_or_after(year, shape, calendar) do
    with {:ok, new_year} <- Date.new(year, 1, 1),
         {:ok, there} <- year_in_calendar(new_year, calendar) do
      years = [there - 1, there, there + 1]

      with {:ok, sides} <- reduce_ok(years, &side_of(&1, shape, Date.to_gregorian_days(new_year))) do
        first_after(Enum.zip(years, sides))
      end
    end
  end

  defp year_in_calendar(date, calendar) do
    with {:ok, day} <- Tempo.from_elixir(date),
         {:ok, there} <- Tempo.to_calendar(day, calendar) do
      {:ok, Tempo.year(there)}
    end
  end

  defp side_of(year, shape, boundary) do
    with {:ok, starts} <- starts_in(year, shape) do
      starts
      |> Enum.split_with(&(&1 < boundary))
      |> side()
    end
  end

  defp side({[], []}) do
    {:ok, :none}
  end

  defp side({[_ | _], []}) do
    {:ok, :before}
  end

  defp side({[], [_ | _]}) do
    {:ok, :after}
  end

  defp side(_both) do
    {:error, "a date of another calendar falls twice in a year"}
  end

  defp starts_in(year, shape) do
    domain = %{ranges: [{year, year}], filter: nil, cadence: 1}

    with {:ok, recurrence} <- every_year(domain, shape),
         {:ok, set} <- Tempo.to_interval(recurrence) do
      set
      |> IntervalSet.members()
      |> reduce_ok(&first_day/1)
    end
  end

  defp first_after([{earliest, _side} | _rest] = sides) do
    on_or_after = for {year, :after} <- sides, do: year
    before = for {year, :before} <- sides, do: year
    first_of(on_or_after, before, earliest)
  end

  defp first_of([_ | _] = on_or_after, _before, _earliest) do
    {:ok, Enum.min(on_or_after)}
  end

  defp first_of([], [_ | _] = before, _earliest) do
    {:ok, Enum.max(before) + 1}
  end

  defp first_of([], [], earliest) do
    {:ok, earliest}
  end

  # A domain as the set of years a recurrence starts in: none for every year.
  defp domain_set(%{ranges: [{nil, nil}]}, _calendar) do
    {:ok, nil}
  end

  defp domain_set(%{ranges: ranges}, calendar) do
    with {:ok, members} <- reduce_ok(ranges, &range_member(&1, calendar)) do
      IntervalSet.new(members)
    end
  end

  defp range_member({nil, to}, calendar) do
    with {:ok, last} <- Tempo.new(year: to, calendar: calendar) do
      Interval.new(from: :open, to: last)
    end
  end

  defp range_member({from, nil}, calendar) do
    with {:ok, first} <- Tempo.new(year: from, calendar: calendar) do
      Interval.new(from: first, to: :open)
    end
  end

  defp range_member({year, year}, calendar) do
    Tempo.new(year: year, calendar: calendar)
  end

  defp range_member({from, to}, calendar) do
    Tempo.new(year: from..to, calendar: calendar)
  end

  defp reduce_ok(items, fun) do
    items
    |> Enum.reduce_while([], &collect_ok(fun.(&1), &2))
    |> finish_ok()
  end

  defp collect_ok({:ok, value}, acc) do
    {:cont, [value | acc]}
  end

  defp collect_ok({:error, _} = error, _acc) do
    {:halt, error}
  end

  defp finish_ok({:error, _} = error) do
    error
  end

  defp finish_ok(acc) when is_list(acc) do
    {:ok, Enum.reverse(acc)}
  end
end
