defmodule Tempo.Reader.DateRule.Plan do
  @moduledoc false

  # A date rule's tokens (`Tempo.Reader.DateRule`) as a plan: what the rule
  # says, part by part, before it is built (`Tempo.Reader.DateRule.Expression`).
  #
  # The plan is a map. `:kind` is what the base date is, with the fields it
  # takes: `:fixed` (`:month`, `:day`), `:weekday` (the `:count`-th `:weekday`
  # of `:month`), `:relative_weekday` (the `:count`-th `:weekday` `:direction`
  # a `:month` and `:day`), `:nested_weekday` and `:nested_after_date` (a
  # `:weekday` `:direction` the `:count`-th `:inner_weekday` of a month or
  # after a date), `:easter` and `:orthodox` (`:offset` days from it),
  # `:equinox` and `:solstice` (`:month`, `:offset`, `:timezone`),
  # `:islamic`, `:persian` and `:julian` (`:calendar`, `:month`, `:day`),
  # `:hebrew` (`:calendar`, the `:month_part` that selects its month, `:day`),
  # `:lunisolar` (`:calendar`, `:month`, `:day`, `:leap_month`, `:offset`)
  # and `:solar_term` (`:calendar`, the term as `:count`, `:day`). A date of
  # another calendar written with its year, or with a cycle and its year, has
  # `:calendar_year`, and a solar term so written `:lunisolar_year`, the
  # `{calendar, year}` it is in. `:steps` are
  # the steps from the base date no kind names, the nearest first, each a
  # count of `:days` or the `:count`-th `:weekday`, with its `:direction`.
  # Around it: `:span` (the days the date reaches into), `:substitute` (the
  # clauses of an observed day, as `{trigger_weekdays, direction, target,
  # mode, span}`), `:weekday_gate`,
  # `:from_year` and `:to_year` (exclusive), `:active` (date windows),
  # `:year_parity`, `:leap`, `:every_years` and `:conditional` (a bridge or
  # an `if is holiday` move).
  #
  # A part the reading does not take yet is `{:error, reason}`, the reason a
  # phrase saying which.

  @weekdays %{
    "monday" => 1,
    "tuesday" => 2,
    "wednesday" => 3,
    "thursday" => 4,
    "friday" => 5,
    "saturday" => 6,
    "sunday" => 7
  }

  @lunisolar_words ["chinese", "korean", "vietnamese"]

  # The parser numbers the Hebrew months by its list (Nisan 1 … Shvat 11,
  # Adar 12, AdarII 13); a plan holds the part that selects the same month.
  # Most are traditional months, which name the same month in every year
  # (Tishrei 1 … Elul 12). The parser's Adar is Adar I in a leap year and Adar
  # in an ordinary one: the sixth month of the year from Tishrei, in order.
  # Its AdarII is the Adar of Purim, traditional 6: Adar in an ordinary year
  # and Adar II in a leap year.
  @hebrew_months %{
    1 => {:traditional_month, 7},
    2 => {:traditional_month, 8},
    3 => {:traditional_month, 9},
    4 => {:traditional_month, 10},
    5 => {:traditional_month, 11},
    6 => {:traditional_month, 12},
    7 => {:traditional_month, 1},
    8 => {:traditional_month, 2},
    9 => {:traditional_month, 3},
    10 => {:traditional_month, 4},
    11 => {:traditional_month, 5},
    12 => {:month, 6},
    13 => {:traditional_month, 6}
  }

  # The directions a step or a move is written with, each to its atom by this
  # table rather than by the atom table, which holds an atom only once a
  # module naming it is loaded.
  @directions %{
    "before" => :before,
    "after" => :after,
    "next" => :next,
    "previous" => :previous
  }

  @types %{
    "public" => :public,
    "bank" => :bank,
    "school" => :school,
    "observance" => :observance,
    "optional" => :optional
  }

  # The weekday steps a weekday-in-month can be without overflowing its month.
  @in_month_instances 1..4

  # date-holidays measures a holiday in minutes from the time it starts, a
  # day being 24 hours: a date alone lasts a day, a time of day lasts to the
  # midnight after it, and a duration lasts as long as it says from the time.
  @day_minutes 24 * 60

  @doc false
  @spec plan([map()]) :: {:ok, map()} | {:error, String.t()}
  def plan([%{fn: _} = base | rest]) do
    {steps, rest} = Enum.split_while(rest, &match?(%{rule: "dateDir"}, &1))

    with {:ok, plan} <- base_plan(base, steps) do
      around(rest, plan, initial_state(rest))
    end
  end

  def plan(_tokens) do
    {:error, "a rule begins with a date"}
  end

  # A plan with its observed days read as `Tempo.DateRule.parse/2`'s
  # `:observed` asks: as written; each clause moving the date, an `and`
  # adding nothing; or none, which for a `substitutes` rule leaves the date
  # on the weekdays its clauses substitute for.
  @doc false
  @spec observed(map(), :as_written | :moved | :none) :: map()
  def observed(plan, :as_written) do
    plan
  end

  def observed(%{substitute: clauses} = plan, :moved) do
    %{plan | substitute: Enum.map(clauses, &moved_clause/1)}
  end

  def observed(%{substitute: clauses} = plan, :none) do
    if Enum.any?(clauses, &substitute_only?/1) do
      gate = {:only, substituted_weekdays(plan, clauses)}

      plan
      |> Map.delete(:substitute)
      |> Map.put(:weekday_gate, gate)
    else
      Map.delete(plan, :substitute)
    end
  end

  def observed(plan, _observed) do
    plan
  end

  # A plan with the windows a dataset says the rule is active in, beside its
  # own (a date counts in any of them, as the parser counts it), and the
  # dates an occurrence is moved from and to.
  @doc false
  @spec dated(map(), map()) :: map()
  def dated(plan, %{active: active, disable: disable, enable: enable}) do
    plan
    |> with_windows(active)
    |> with_dates(:disable, disable)
    |> with_dates(:enable, enable)
  end

  # A plan with the plans of the `substitutes` entries that may stand in for
  # its date, which the expression takes where one does.
  @doc false
  @spec replaced_by(map(), [map()]) :: map()
  def replaced_by(plan, []) do
    plan
  end

  def replaced_by(plan, entries) do
    Map.put(plan, :replaced_by, entries)
  end

  # ── the base date and its weekday steps ────────────────────────────────

  # A fixed date's steps are a named kind where one says them (a weekday
  # before or after it, the nth weekday of a month, a weekday from the nth
  # weekday after it); any other chain is kept as steps, applied in turn.
  defp base_plan(%{fn: "gregorian", year: year} = base, steps) do
    with {:ok, plan} <- base_plan(Map.delete(base, :year), steps) do
      {:ok, Map.merge(plan, %{from_year: year, to_year: year + 1})}
    end
  end

  defp base_plan(%{fn: "gregorian", month: month, day: day}, []) do
    {:ok, %{kind: :fixed, month: month, day: day}}
  end

  defp base_plan(%{fn: "gregorian", month: month, day: day}, steps) do
    case weekday_steps(month, day, steps) do
      {:ok, plan} -> {:ok, plan}
      :steps -> stepped(%{kind: :fixed, month: month, day: day}, steps)
    end
  end

  defp base_plan(%{fn: "julian", month: month, day: day} = base, steps) do
    plan = %{kind: :julian, calendar: calendar_of("julian"), month: month, day: day}
    stepped(in_own_year(plan, base), steps)
  end

  defp base_plan(%{fn: "easter", type: type, offset: offset}, steps) do
    stepped(%{kind: easter_kind(type), offset: offset}, steps)
  end

  defp base_plan(%{fn: "equinox", season: season, timezone: timezone}, steps) do
    {kind, month} = solar_event(season)
    stepped(%{kind: kind, month: month, offset: 0, timezone: event_zone(timezone)}, steps)
  end

  defp base_plan(%{fn: "islamic", month: month, day: day} = base, steps) do
    plan = %{kind: :islamic, calendar: calendar_of("islamic"), month: month, day: day}
    stepped(in_own_year(plan, base), steps)
  end

  defp base_plan(%{fn: "hebrew", month: month, day: day} = base, steps) do
    month_part = Map.fetch!(@hebrew_months, month)
    plan = %{kind: :hebrew, calendar: calendar_of("hebrew"), month_part: month_part, day: day}
    stepped(in_own_year(plan, base), steps)
  end

  defp base_plan(%{fn: "jalaali", month: month, day: day} = base, steps) do
    plan = %{kind: :persian, calendar: calendar_of("jalaali"), month: month, day: day}
    stepped(in_own_year(plan, base), steps)
  end

  # A cycle and a year of it name one year of the calendar: a date of the
  # calendar falls in that year, and a solar term, reckoned in Gregorian
  # years, in the Gregorian year it begins in.
  defp base_plan(%{fn: calendar, cycle: cycle, year: year} = base, steps)
       when calendar in @lunisolar_words do
    lunisolar = calendar_of(calendar)

    with {:ok, own_year} <- year_of_cycle(lunisolar, cycle, year),
         {:ok, plan} <- base_plan(Map.drop(base, [:cycle, :year]), steps) do
      {:ok, in_cycle_year(plan, base, lunisolar, own_year)}
    end
  end

  # A solar term's later day is a step of days from the term.
  defp base_plan(%{fn: "chinese", solarterm: term, day: day}, steps) do
    plan = %{kind: :solar_term, calendar: calendar_of("chinese"), count: term, day: 1}
    stepped(plan, later_day(day) ++ steps)
  end

  defp base_plan(%{fn: calendar, solarterm: _term}, _steps) when calendar in @lunisolar_words do
    {:error, "a solar term of this calendar is not read yet"}
  end

  # A lunisolar date folds a count of days into its day; a weekday step
  # from one is a step.
  defp base_plan(%{fn: calendar} = base, steps) when calendar in @lunisolar_words do
    {offset, steps} = folded_days(steps)

    plan = %{
      kind: :lunisolar,
      calendar: calendar_of(calendar),
      month: base.month,
      day: base.day,
      leap_month: base.leap_month,
      offset: offset
    }

    stepped(plan, steps)
  end

  defp base_plan(%{fn: "bengali-revised"}, _steps) do
    {:error, "the Bengali calendar is not one Calendrical has"}
  end

  # The steps of a plan, the one nearest its date first; none is none.
  defp stepped(plan, []) do
    {:ok, plan}
  end

  defp stepped(plan, steps) do
    with {:ok, steps} <- reduce_ok(steps, &step/1) do
      {:ok, Map.put(plan, :steps, steps)}
    end
  end

  defp step(%{weekday: "day", count: count, direction: direction}) do
    {:ok, %{days: count, direction: step_direction(direction)}}
  end

  defp step(%{weekday: weekday, count: count, direction: direction})
       when is_map_key(@weekdays, weekday) do
    {:ok, %{weekday: weekday_number(weekday), count: count, direction: step_direction(direction)}}
  end

  defp step(_step) do
    {:error, "this weekday step is not read yet"}
  end

  defp step_direction(direction) when is_map_key(@directions, direction) do
    Map.fetch!(@directions, direction)
  end

  # A date in a year of its own calendar (`31 Shahrivar 1401`).
  defp in_own_year(plan, %{year: year}) do
    Map.put(plan, :calendar_year, year)
  end

  defp in_own_year(plan, _base) do
    plan
  end

  defp year_of_cycle(calendar, cycle, year) do
    case Tempo.Calendar.year_of_cycle(calendar, cycle, year) do
      {:ok, own_year} -> {:ok, own_year}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp in_cycle_year(plan, %{solarterm: _term}, calendar, year) do
    Map.put(plan, :lunisolar_year, {calendar, year})
  end

  defp in_cycle_year(plan, _base, _calendar, year) do
    Map.put(plan, :calendar_year, year)
  end

  defp later_day(1) do
    []
  end

  defp later_day(day) do
    [%{weekday: "day", count: day - 1, direction: "after"}]
  end

  # A lunisolar date's leading count of days, before or after, is folded
  # into its day.
  defp folded_days([%{weekday: "day", count: count, direction: "before"} | rest]) do
    {-count, rest}
  end

  defp folded_days([%{weekday: "day", count: count, direction: "after"} | rest]) do
    {count, rest}
  end

  defp folded_days(steps) do
    {0, steps}
  end

  # A weekday step from a fixed date that a kind names; `:steps` for any
  # other chain.
  defp weekday_steps(month, 1, [%{direction: "after", count: count, weekday: weekday}])
       when count in @in_month_instances and is_map_key(@weekdays, weekday) do
    {:ok, %{kind: :weekday, month: month, count: count, weekday: weekday_number(weekday)}}
  end

  defp weekday_steps(month, day, [%{direction: direction, count: count, weekday: weekday}])
       when direction in ["before", "after"] and is_map_key(@weekdays, weekday) do
    {:ok,
     %{
       kind: :relative_weekday,
       month: month,
       day: day,
       count: count,
       weekday: weekday_number(weekday),
       direction: step_direction(direction)
     }}
  end

  defp weekday_steps(month, day, [
         %{direction: "after", count: count, weekday: inner},
         %{direction: direction, count: 1, weekday: outer}
       ])
       when direction in ["before", "after"] and is_map_key(@weekdays, inner) and
              is_map_key(@weekdays, outer) do
    {:ok,
     %{
       kind: nested_kind(day, count),
       month: month,
       day: day,
       count: count,
       inner_weekday: weekday_number(inner),
       weekday: weekday_number(outer),
       direction: step_direction(direction)
     }}
  end

  defp weekday_steps(_month, _day, _steps) do
    :steps
  end

  defp nested_kind(1, count) when count in @in_month_instances do
    :nested_weekday
  end

  defp nested_kind(_day, _count) do
    :nested_after_date
  end

  defp reduce_ok(items, fun) do
    items
    |> Enum.reduce_while([], &collect_ok(fun.(&1), &2))
    |> finish_ok()
  end

  defp collect_ok({:ok, value}, acc) do
    {:cont, [value | acc]}
  end

  defp collect_ok({:error, _reason} = error, _acc) do
    {:halt, error}
  end

  defp finish_ok({:error, _reason} = error) do
    error
  end

  defp finish_ok(acc) when is_list(acc) do
    {:ok, Enum.reverse(acc)}
  end

  # The grammar's calendar words are a fixed set, each of which names one.
  defp calendar_of(word) do
    {:ok, calendar} = Tempo.Calendar.date_rule_calendar(word)
    calendar
  end

  defp easter_kind("easter") do
    :easter
  end

  defp easter_kind("orthodox") do
    :orthodox
  end

  defp solar_event("march") do
    {:equinox, 3}
  end

  defp solar_event("september") do
    {:equinox, 9}
  end

  defp solar_event("june") do
    {:solstice, 6}
  end

  defp solar_event("december") do
    {:solstice, 12}
  end

  # GMT, the parser's zone where a rule names none, is UTC: no zone.
  defp event_zone("GMT") do
    nil
  end

  defp event_zone(zone) do
    zone
  end

  defp weekday_number(weekday) do
    Map.fetch!(@weekdays, weekday)
  end

  # ── what is around the base date ───────────────────────────────────────

  # A `substitutes` anywhere makes every clause give the observed day alone;
  # an `and` before a clause makes it, and every later one, add the observed
  # day to the date rather than move it. `:hours` is the date's start and
  # length in minutes, as the parser keeps them; each clause keeps its own,
  # and `:retimed` holds those of the clauses that change only the time.
  defp initial_state(tokens) do
    %{
      mode: initial_mode(tokens),
      pending_and: false,
      dates: [],
      clauses: [],
      hours: {0, @day_minutes},
      retimed: []
    }
  end

  defp initial_mode(tokens) do
    if Enum.any?(tokens, &match?(%{modifier: "substitutes"}, &1)) do
      :substitute_only
    else
      :shift
    end
  end

  # The date and each observed day span the days their hours reach into. A
  # clause that changes only the time is no change of the days unless it
  # moves the end into another day, which is not read yet.
  defp around([], plan, %{hours: hours} = state) do
    span = days_reached(hours)

    if Enum.all?(state.retimed, &(days_reached(&1) == span)) do
      clauses = Enum.map(state.clauses, &clause_span/1)
      {:ok, with_clauses(Map.put(plan, :span, span), clauses)}
    else
      {:error, "a clause that changes the time of a date into another day is not read yet"}
    end
  end

  defp around([token | rest], plan, state) do
    case part(token, plan, state) do
      {:ok, plan, state} -> around(rest, plan, state)
      {:error, _reason} = error -> error
    end
  end

  defp part(%{modifier: "substitutes"}, plan, state) do
    {:ok, plan, state}
  end

  defp part(%{modifier: "and"}, plan, state) do
    {:ok, plan, %{state | pending_and: true}}
  end

  defp part(%{modifier: modifier}, plan, state) when modifier in ["if", "then"] do
    {:ok, plan, %{state | pending_and: false}}
  end

  defp part(%{modifier: "if equal"}, _plan, _state) do
    {:error, "if equal is not read yet"}
  end

  # A time or a duration written after the date is that of every date the
  # rule has made so far, as the parser sets it on each.
  defp part(%{rule: rule} = token, plan, state) when rule in ["time", "duration"] do
    {:ok, plan, timed(state, token)}
  end

  defp part(
         %{rule: "dateIfThen", if: triggers, direction: direction, then: target} = token,
         plan,
         state
       )
       when direction in ["next", "previous"] and is_map_key(@weekdays, target) do
    mode = clause_mode(state)
    hours = clause_hours(state.hours, token)

    clause =
      {weekday_numbers(triggers), step_direction(direction), weekday_number(target), mode, hours}

    {:ok, plan, %{state | mode: mode, pending_and: false, clauses: state.clauses ++ [clause]}}
  end

  # A clause that changes only the time a holiday starts at.
  defp part(%{rule: "dateIfThen", rules: _times} = token, plan, state)
       when not is_map_key(token, :direction) do
    retimed = state.retimed ++ [clause_hours(state.hours, token)]
    {:ok, plan, %{state | pending_and: false, retimed: retimed}}
  end

  defp part(%{rule: "dateIfThen"}, _plan, _state) do
    {:error, "this observed-day clause is not read yet"}
  end

  defp part(%{rule: "weekday", not: negated, if: weekdays}, plan, state) do
    gate = if negated, do: :except, else: :only
    {:ok, Map.put(plan, :weekday_gate, {gate, weekday_numbers(weekdays)}), state}
  end

  defp part(%{rule: "year", cardinality: cardinality}, plan, state) do
    {:ok, Map.merge(plan, year_filter(cardinality)), state}
  end

  defp part(%{rule: "year", every: every, since: since}, plan, state) do
    {:ok, Map.merge(plan, %{every_years: every, from_year: since}), state}
  end

  defp part(%{rule: "ruleIfHoliday", direction: direction} = token, plan, state)
       when is_map_key(@directions, direction) do
    move = %{
      count: token.count,
      direction: step_direction(direction),
      target: move_target(token.weekday),
      omit: weekday_numbers(token.omit)
    }

    conditional = %{kind: :if_holiday, type: holiday_type(token), move: move}
    {:ok, Map.put(plan, :conditional, conditional), state}
  end

  defp part(%{rule: "ruleIfHoliday"}, _plan, _state) do
    {:error, "an if is holiday clause without a move is not read yet"}
  end

  defp part(%{rule: "bridge"} = token, plan, state) do
    on = Enum.map(state.dates, &{&1.month, &1.day})
    conditional = %{kind: :bridge, type: holiday_type(token), on: on}
    {:ok, bridged(plan, conditional), state}
  end

  defp part(%{fn: "gregorian"} = date, plan, state) do
    {:ok, plan, %{state | dates: state.dates ++ [date]}}
  end

  defp part(%{rule: "activeFrom"} = token, plan, state) do
    with {:ok, plan} <- active_from(plan, token), do: {:ok, plan, state}
  end

  defp part(%{rule: "activeTo"} = token, plan, state) do
    with {:ok, plan} <- active_to(plan, token), do: {:ok, plan, state}
  end

  defp part(_token, _plan, _state) do
    {:error, "this part of the rule is not read yet"}
  end

  # A bridge keeps an `if is holiday` move that came before it, and its base
  # date is the day of the year whatever year it is written with.
  defp bridged(%{conditional: _} = plan, _conditional) do
    plan
  end

  defp bridged(plan, conditional) do
    plan
    |> Map.put(:conditional, conditional)
    |> Map.drop([:from_year, :to_year])
  end

  defp clause_mode(%{pending_and: true}) do
    :add
  end

  defp clause_mode(%{mode: mode}) do
    mode
  end

  defp with_clauses(plan, []) do
    plan
  end

  defp with_clauses(plan, clauses) do
    Map.put(plan, :substitute, clauses)
  end

  # The start and length a time or a duration gives a date: a time lasts to
  # the midnight after it, a duration as long as it says from the time.
  defp hours_after({_start, _length}, %{rule: "time", hour: hour, minute: minute}) do
    start = hour * 60 + minute
    {start, @day_minutes - start}
  end

  defp hours_after({start, _length}, %{rule: "duration", duration: hours}) do
    {start, trunc(hours * 60)}
  end

  defp hours_after(hours, _token) do
    hours
  end

  defp timed(state, token) do
    %{
      state
      | hours: hours_after(state.hours, token),
        clauses: Enum.map(state.clauses, &clause_timed(&1, token)),
        retimed: Enum.map(state.retimed, &hours_after(&1, token))
    }
  end

  defp clause_timed({triggers, direction, target, mode, hours}, token) do
    {triggers, direction, target, mode, hours_after(hours, token)}
  end

  # An observed day starts as a copy of the date, its time and length with
  # it, and takes the time and the duration its clause writes.
  defp clause_hours(hours, token) do
    token
    |> Map.get(:rules, [])
    |> Enum.reduce(hours, &hours_after(&2, &1))
  end

  defp clause_span({triggers, direction, target, mode, hours}) do
    {triggers, direction, target, mode, days_reached(hours)}
  end

  defp with_windows(plan, []) do
    plan
  end

  defp with_windows(plan, windows) do
    Map.update(plan, :active, windows, &(&1 ++ windows))
  end

  defp with_dates(plan, _key, []) do
    plan
  end

  defp with_dates(plan, key, dates) do
    Map.put(plan, key, dates)
  end

  defp moved_clause({triggers, direction, target, :add, span}) do
    {triggers, direction, target, :shift, span}
  end

  defp moved_clause(clause) do
    clause
  end

  defp substitute_only?({_triggers, _direction, _target, mode, _span}) do
    mode == :substitute_only
  end

  # The weekdays a `substitutes` rule's clauses fire on, of those its
  # weekday gate allows.
  defp substituted_weekdays(plan, clauses) do
    triggers = Enum.flat_map(clauses, &elem(&1, 0))
    allowed = gate_allowed(Map.get(plan, :weekday_gate))

    @weekdays
    |> Map.values()
    |> Enum.sort()
    |> Enum.filter(&(&1 in triggers and &1 in allowed))
  end

  defp gate_allowed(nil) do
    Map.values(@weekdays)
  end

  defp gate_allowed({:only, weekdays}) do
    weekdays
  end

  defp gate_allowed({:except, weekdays}) do
    Map.values(@weekdays) -- weekdays
  end

  # The days from the date's start to the last minute before its end.
  defp days_reached({start, length}) do
    max(div(start + length + @day_minutes - 1, @day_minutes), 1)
  end

  defp year_filter("even") do
    %{year_parity: :even}
  end

  defp year_filter("odd") do
    %{year_parity: :odd}
  end

  defp year_filter("leap") do
    %{leap: :leap}
  end

  defp year_filter("non-leap") do
    %{leap: :non_leap}
  end

  # `since 2009` is the first of January 2009, a year; `since 2022-09-09` a
  # date, a window the occurrence must be in.
  defp active_from(plan, %{year: year, month: 1, day: 1}) do
    {:ok, Map.put(plan, :from_year, year)}
  end

  defp active_from(plan, token) do
    with {:ok, date} <- window_date(token), do: {:ok, windowed(plan, {date, :from})}
  end

  defp active_to(plan, %{year: year, month: 1, day: 1}) do
    {:ok, Map.put(plan, :to_year, year)}
  end

  defp active_to(plan, token) do
    with {:ok, date} <- window_date(token), do: {:ok, windowed(plan, {date, :to})}
  end

  defp window_date(%{year: year, month: month, day: day}) do
    case Date.new(year, month, day) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "since or prior to names no date"}
    end
  end

  defp windowed(plan, {date, :from}) do
    {_from, to} = window_of(plan)
    Map.put(plan, :active, [{date, to}])
  end

  defp windowed(plan, {date, :to}) do
    {from, _to} = window_of(plan)
    Map.put(plan, :active, [{from, date}])
  end

  defp window_of(%{active: [window]}) do
    window
  end

  defp window_of(_plan) do
    {nil, nil}
  end

  defp holiday_type(%{type: type}) do
    Map.fetch!(@types, type)
  end

  defp holiday_type(_token) do
    :public
  end

  defp move_target("day") do
    :day
  end

  defp move_target(weekday) do
    weekday_number(weekday)
  end

  defp weekday_numbers(weekdays) do
    for weekday <- weekdays, is_map_key(@weekdays, weekday), do: weekday_number(weekday)
  end
end
