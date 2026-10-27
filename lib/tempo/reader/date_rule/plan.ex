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
  # `:islamic`, `:hebrew`, `:persian` and `:julian` (`:calendar`, `:month`,
  # `:day`, `:leap_month`), `:lunisolar` (`:calendar`, `:month`, `:day`,
  # `:leap_month`, `:offset`) and `:solar_term` (`:calendar`, the term as
  # `:count`, `:day`). Around it: `:span` (days), `:substitute` (the clauses
  # of an observed day, as `{trigger_weekdays, direction, target, mode}`),
  # `:weekday_gate`, `:from_year` and `:to_year` (exclusive), `:active`
  # (date windows), `:year_parity`, `:leap`, `:every_years` and
  # `:conditional` (a bridge or an `if is holiday` move).
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
  # Adar 12, AdarII 13); a plan holds the traditional numbers, which name the
  # same month in every year (Tishrei 1 … Elul 12). The Adar of Purim is 6,
  # Adar in an ordinary year and Adar II in a leap year, and date-holidays
  # writes it Adar or AdarII.
  @hebrew_traditional %{
    1 => 7,
    2 => 8,
    3 => 9,
    4 => 10,
    5 => 11,
    6 => 12,
    7 => 1,
    8 => 2,
    9 => 3,
    10 => 4,
    11 => 5,
    12 => 6,
    13 => 6
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

  @doc false
  @spec plan([map()]) :: {:ok, map()} | {:error, String.t()}
  def plan([%{fn: _} = base | rest]) do
    {steps, rest} = Enum.split_while(rest, &match?(%{rule: "dateDir"}, &1))

    with {:ok, plan} <- base_plan(base, steps),
         {:ok, plan} <- around(rest, plan, initial_state(rest)) do
      {:ok, finished(plan)}
    end
  end

  def plan(_tokens) do
    {:error, "a rule begins with a date"}
  end

  # ── the base date and its weekday steps ────────────────────────────────

  defp base_plan(%{fn: "gregorian", year: year} = base, []) do
    {:ok, %{kind: :fixed, month: base.month, day: base.day, from_year: year, to_year: year + 1}}
  end

  defp base_plan(%{fn: "gregorian", month: month, day: day}, []) do
    {:ok, %{kind: :fixed, month: month, day: day}}
  end

  defp base_plan(%{fn: "gregorian", year: _year}, _steps) do
    {:error, "a weekday step from a date in one year is not read yet"}
  end

  defp base_plan(%{fn: "gregorian", month: month, day: day}, steps) do
    weekday_steps(month, day, steps)
  end

  defp base_plan(%{fn: "julian", year: _year}, _steps) do
    {:error, "a Julian date in one year is not read yet"}
  end

  defp base_plan(%{fn: "julian", month: month, day: day}, []) do
    {:ok, %{kind: :julian, calendar: calendar_of("julian"), month: month, day: day}}
  end

  defp base_plan(%{fn: "easter", type: type, offset: offset}, []) do
    {:ok, %{kind: easter_kind(type), offset: offset}}
  end

  defp base_plan(%{fn: "equinox", season: season, timezone: timezone}, steps) do
    with {:ok, offset} <- day_offset(steps) do
      {kind, month} = solar_event(season)
      {:ok, %{kind: kind, month: month, offset: offset, timezone: event_zone(timezone)}}
    end
  end

  defp base_plan(%{fn: calendar, year: _year}, _steps)
       when calendar in ["islamic", "hebrew", "jalaali"] do
    {:error, "a date in one year of another calendar is not read yet"}
  end

  defp base_plan(%{fn: "islamic", month: month, day: day}, []) do
    {:ok, %{kind: :islamic, calendar: calendar_of("islamic"), month: month, day: day}}
  end

  defp base_plan(%{fn: "hebrew", month: month, day: day}, []) do
    traditional = Map.fetch!(@hebrew_traditional, month)
    {:ok, %{kind: :hebrew, calendar: calendar_of("hebrew"), month: traditional, day: day}}
  end

  defp base_plan(%{fn: "jalaali", month: month, day: day}, []) do
    {:ok, %{kind: :persian, calendar: calendar_of("jalaali"), month: month, day: day}}
  end

  defp base_plan(%{fn: calendar, solarterm: _term, cycle: _cycle}, _steps)
       when calendar in @lunisolar_words do
    {:error, "a solar term in one year of the cycle is not read yet"}
  end

  defp base_plan(%{fn: "chinese", solarterm: term, day: day}, []) do
    {:ok, %{kind: :solar_term, calendar: calendar_of("chinese"), count: term, day: day}}
  end

  defp base_plan(%{fn: calendar, solarterm: _term}, _steps)
       when calendar in @lunisolar_words do
    {:error, "a solar term of this calendar, or a step from one, is not read yet"}
  end

  defp base_plan(%{fn: calendar, cycle: _cycle}, _steps)
       when calendar in @lunisolar_words do
    {:error, "a lunisolar date in one year of the cycle is not read yet"}
  end

  defp base_plan(%{fn: calendar} = base, steps) when calendar in @lunisolar_words do
    with {:ok, offset} <- day_offset(steps) do
      {:ok,
       %{
         kind: :lunisolar,
         calendar: calendar_of(calendar),
         month: base.month,
         day: base.day,
         leap_month: base.leap_month,
         offset: offset
       }}
    end
  end

  defp base_plan(%{fn: "bengali-revised"}, _steps) do
    {:error, "the Bengali calendar is not one Calendrical has"}
  end

  defp base_plan(_base, _steps) do
    {:error, "a weekday step from this date is not read yet"}
  end

  # A weekday step from a fixed date: one is a relative weekday, after the
  # first of a month a weekday in it; two step from the nth weekday after a
  # date to the weekday before or after it.
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
       direction: String.to_existing_atom(direction)
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
       direction: String.to_existing_atom(direction)
     }}
  end

  defp weekday_steps(_month, _day, _steps) do
    {:error, "this chain of weekday steps is not read yet"}
  end

  defp nested_kind(1, count) when count in @in_month_instances do
    :nested_weekday
  end

  defp nested_kind(_day, _count) do
    :nested_after_date
  end

  # A count of days before or after a date (`5 days before september
  # equinox`) is its offset; no step is none.
  defp day_offset([]) do
    {:ok, 0}
  end

  defp day_offset([%{weekday: "day", count: count, direction: "before"}]) do
    {:ok, -count}
  end

  defp day_offset([%{weekday: "day", count: count, direction: "after"}]) do
    {:ok, count}
  end

  defp day_offset(_steps) do
    {:error, "a weekday step from this date is not read yet"}
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
  # day to the date rather than move it.
  defp initial_state(tokens) do
    %{mode: initial_mode(tokens), pending_and: false, dates: [], clauses: []}
  end

  defp initial_mode(tokens) do
    if Enum.any?(tokens, &match?(%{modifier: "substitutes"}, &1)) do
      :substitute_only
    else
      :shift
    end
  end

  defp around([], plan, state) do
    {:ok, with_clauses(plan, state.clauses)}
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

  defp part(%{rule: "time"}, plan, state) do
    {:ok, plan, state}
  end

  # A duration is in hours from the start of the day: the days it reaches
  # into are the span, `PT90H` four.
  defp part(%{rule: "duration", duration: hours}, plan, state) do
    days =
      (hours / 24)
      |> Float.ceil()
      |> trunc()

    {:ok, Map.put(plan, :span, max(days, 1)), state}
  end

  defp part(%{rule: "dateIfThen", if: triggers, direction: direction, then: target}, plan, state)
       when direction in ["next", "previous"] and is_map_key(@weekdays, target) do
    mode = clause_mode(state)
    direction = String.to_existing_atom(direction)
    clause = {weekday_numbers(triggers), direction, weekday_number(target), mode}
    {:ok, plan, %{state | mode: mode, pending_and: false, clauses: state.clauses ++ [clause]}}
  end

  # A clause that changes only the time a holiday starts at.
  defp part(%{rule: "dateIfThen", rules: _times} = token, plan, state)
       when not is_map_key(token, :direction) do
    {:ok, plan, %{state | pending_and: false}}
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
       when is_binary(direction) do
    move = %{
      count: token.count,
      direction: String.to_existing_atom(direction),
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

  # A span is a count of days for a date that has one; a weekday step's
  # count is its ordinal, and a span is not read on it.
  defp finished(plan) do
    Map.put_new(plan, :span, 1)
  end
end
