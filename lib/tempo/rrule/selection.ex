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

  | Part         | Role and when                                     |
  | ------------ | ------------------------------------------------- |
  | `BYMONTH`    | LIMIT — always.                                   |
  | `BYMONTHDAY` | LIMIT — any FREQ except WEEKLY (forbidden).       |
  | `BYYEARDAY`  | LIMIT — any FREQ coarser than DAILY.              |
  | `BYWEEKNO`   | LIMIT — `YEARLY` only.                            |
  | `BYDAY` (no ordinal) | LIMIT for DAILY/HOURLY/MINUTELY/SECONDLY; |
  |              | EXPAND within the enclosing week/month/year for   |
  |              | WEEKLY, MONTHLY, YEARLY.                          |
  | `BYDAY` (with ordinal) | EXPAND — pairs `(ordinal, weekday)` like  |
  |              | `1MO` and `-1FR` pick the Nth / Nth-from-last     |
  |              | matching weekday within the enclosing period      |
  |              | (month for MONTHLY, year for YEARLY). Backed by   |
  |              | `Calendrical.Kday.nth_kday/3`.                    |
  | `BYHOUR`     | EXPAND when FREQ is coarser than hour; LIMIT      |
  |              | when FREQ is hour-or-finer.                       |
  | `BYMINUTE`   | Same pattern at the minute unit.                  |
  | `BYSECOND`   | Same pattern at the second unit.                  |
  | `BYSETPOS`   | LIMIT — applied last, across the post-filter      |
  |              | per-period candidate set. Negative values count   |
  |              | from the end (`-1` = last).                       |

  Tokens this module doesn't interpret pass through unchanged
  so partial support is correct for the partial inputs.

  """

  alias Calendrical.Kday
  alias Tempo.Interval

  @doc """
  Apply a `repeat_rule` to one candidate occurrence and return the
  resulting list of occurrences.

  ### Arguments

  * `candidate` is a `t:Tempo.Interval.t/0` — the current
    occurrence under consideration.

  * `repeat_rule` is either `nil` (no rule — passthrough) or a
    `%Tempo{}` whose `:time` holds `[selection: [...]]`.

  * `freq` is the enclosing `FREQ` atom (`:second`, `:minute`,
    `:hour`, `:day`, `:week`, `:month`, `:year`). Drives the
    EXPAND-vs-LIMIT dispatch for rules whose role depends on
    the enclosing frequency.

  ### Returns

  * A list of `t:Tempo.Interval.t/0` occurrences — `[]` on LIMIT
    rejection, `[candidate]` on passthrough or LIMIT accept,
    `[c1, c2, …]` on EXPAND.

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
  @spec apply(Interval.t(), Tempo.t() | nil, atom()) :: [Interval.t()]
  def apply(candidate, repeat_rule, freq, options \\ [])

  def apply(%Interval{} = candidate, nil, _freq, _options), do: [candidate]

  def apply(%Interval{} = candidate, %Tempo{time: [selection: selection]}, freq, options) do
    # The recurrence's *original* start day rides along as a tagged
    # entry: cadence stepping clamps the candidate's day (Feb 29 →
    # Feb 28 in a common year), and an expansion that repositions the
    # month must clamp from the day the rule was anchored on, per
    # occurrence — not from an intermediate clamp. Handlers that
    # don't consume the tag pass it through.
    selection =
      case Keyword.get(options, :origin_day) do
        day when is_integer(day) -> selection ++ [origin_day: day]
        _other -> selection
      end

    apply_selection(candidate, selection, freq)
  end

  # No selection shape we recognise — pass through rather than
  # crash. Future phases replace this catch-all with a specific
  # error once every shape is accounted for.
  def apply(%Interval{} = candidate, _, _freq, _options), do: [candidate]

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
  defp apply_selection(candidate, selection, freq) do
    selection = expand_index_ranges(selection)
    wkst = Keyword.get(selection, :wkst, 1)

    selection
    |> Enum.sort_by(&application_order_key/1)
    |> Enum.reduce([candidate], fn entry, candidates ->
      apply_entry(entry, candidates, freq, selection, wkst)
    end)
  end

  # A `{2..8}` set in the ISO 8601-2 sigil grammar parses to a `Range`
  # element in the selection value list (`day: [2..8]`), whereas the
  # RRULE adapter emits an explicit integer list (`day: [2, 3, …, 8]`).
  # The selection handlers expect integer indices, so expand any range
  # element to its members before applying — keeping the two spellings
  # equivalent so an inspected value round-trips. Non-list values (bare
  # `day_of_week: 2`) and non-range elements (`byday: [{2, 5}]`) pass
  # through unchanged.
  defp expand_index_ranges(selection) do
    Enum.map(selection, fn
      {key, value} when is_list(value) -> {key, Enum.flat_map(value, &expand_range_element/1)}
      {key, value} -> {key, value}
    end)
  end

  defp expand_range_element(%Range{} = range), do: Enum.to_list(range)
  defp expand_range_element(element), do: [element]

  @application_order [
    :wkst,
    :month,
    :week,
    :day_of_year,
    :day,
    :nearest_weekday,
    :or_day,
    :day_of_week,
    :byday,
    :hour,
    :minute,
    :second,
    :set_position
  ]

  defp application_order_key({token, _value}) do
    Enum.find_index(@application_order, &(&1 == token)) || length(@application_order)
  end

  # WKST — context-only token consumed by `apply_selection`.
  # Already extracted before the reduce fires, so by the time it
  # shows up here it's a no-op.
  defp apply_entry({:wkst, _}, candidates, _freq, _selection, _wkst), do: candidates

  # BYMONTH — EXPAND for FREQ=YEARLY, LIMIT otherwise. Per RFC
  # 5545 §3.3.10, a YEARLY rule with BYMONTH=6,7 produces an
  # occurrence in each listed month of each year; finer FREQs
  # already iterate at finer-than-year granularity, so they
  # just filter.
  defp apply_entry({:month, months}, candidates, :year, selection, _wkst) do
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

  defp apply_entry({:month, months}, candidates, _freq, _selection, _wkst) do
    limit(candidates, months, &month_of/1)
  end

  # BYMONTHDAY — EXPAND for FREQ=MONTHLY or YEARLY, LIMIT
  # otherwise. RFC forbids it with FREQ=WEEKLY; we don't reject
  # (malformed rules are a parser concern). `-1` is the last
  # day of the enclosing month.
  defp apply_entry({:day, days}, candidates, freq, _selection, _wkst)
       when freq in [:month, :year] do
    Enum.flat_map(candidates, fn candidate ->
      expand_candidate_days(candidate, List.wrap(days))
    end)
  end

  defp apply_entry({:day, days}, candidates, _freq, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_month_day_list?(candidate, List.wrap(days))
    end)
  end

  # Nearest-weekday (`W`) — a non-standard cron modifier. EXPAND
  # for MONTHLY/YEARLY (project each enclosing month onto its
  # nearest-weekday date), LIMIT otherwise (keep candidates whose
  # day is a nearest-weekday for their month).
  defp apply_entry({:nearest_weekday, targets}, candidates, freq, _selection, _wkst)
       when freq in [:month, :year] do
    Enum.flat_map(candidates, fn candidate ->
      expand_nearest_weekdays(candidate, List.wrap(targets))
    end)
  end

  defp apply_entry({:nearest_weekday, targets}, candidates, _freq, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      day_of(candidate) in nearest_weekday_days(candidate, List.wrap(targets))
    end)
  end

  # POSIX day-of-month OR day-of-week — a non-standard cron union.
  # Always a LIMIT: keep a candidate whose day-of-month is in the
  # monthday list OR whose weekday matches a byday entry. The cron
  # builder pairs this with a DAILY cadence so every candidate day
  # is visited.
  defp apply_entry({:or_day, {monthdays, byday_entries}}, candidates, _freq, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_month_day_list?(candidate, monthdays) or weekday_matches?(candidate, byday_entries)
    end)
  end

  # BYYEARDAY — EXPAND for YEARLY, LIMIT otherwise. Signed
  # indexing: `-1` is the last day of the year.
  defp apply_entry({:day_of_year, days}, candidates, :year, _selection, _wkst) do
    Enum.flat_map(candidates, fn candidate ->
      expand_candidate_year_days(candidate, List.wrap(days))
    end)
  end

  defp apply_entry({:day_of_year, days}, candidates, _freq, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_year_day_list?(candidate, List.wrap(days))
    end)
  end

  # BYWEEKNO — EXPAND for YEARLY (only valid FREQ per RFC).
  # Each listed ISO week number expands to 7 occurrences (the
  # days of that week). Signed indexing: `-1` is the last week.
  defp apply_entry({:week, weeks}, candidates, :year, _selection, _wkst) do
    Enum.flat_map(candidates, fn candidate ->
      expand_candidate_week_numbers(candidate, List.wrap(weeks))
    end)
  end

  defp apply_entry({:week, weeks}, candidates, _freq, _selection, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_week_no_list?(candidate, List.wrap(weeks))
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
  defp apply_entry({:day_of_week, days}, candidates, freq, selection, wkst) do
    case no_ordinal_byday_role(freq, selection) do
      :limit ->
        Enum.filter(candidates, fn candidate ->
          weekday_of(candidate) in List.wrap(days)
        end)

      {:expand, :week} ->
        Enum.flat_map(candidates, &expand_weekdays_in_week(&1, List.wrap(days), wkst))

      {:expand, :month} ->
        Enum.flat_map(candidates, &expand_weekdays_in_month(&1, List.wrap(days)))

      {:expand, :year} ->
        Enum.flat_map(candidates, &expand_weekdays_in_year(&1, List.wrap(days)))
    end
  end

  # BYDAY with ordinals — EXPAND. Each `{ordinal, weekday}` pair
  # picks one (or more) specific date within the enclosing
  # period. Backed by `Calendrical.Kday.nth_kday/3` which
  # handles both positive and negative ordinals.
  defp apply_entry({:byday, pairs}, candidates, freq, selection, wkst) do
    scope = byday_ordinal_scope(freq, selection)

    Enum.flat_map(candidates, fn candidate ->
      expand_byday_pairs(candidate, pairs, scope, wkst)
    end)
  end

  # BYHOUR / BYMINUTE / BYSECOND — EXPAND when FREQ is coarser
  # than the unit, LIMIT when FREQ is the same unit or finer.
  defp apply_entry({:hour, values}, candidates, freq, _selection, _wkst) do
    expand_or_limit_time(candidates, :hour, List.wrap(values), freq)
  end

  defp apply_entry({:minute, values}, candidates, freq, _selection, _wkst) do
    expand_or_limit_time(candidates, :minute, List.wrap(values), freq)
  end

  defp apply_entry({:second, values}, candidates, freq, _selection, _wkst) do
    expand_or_limit_time(candidates, :second, List.wrap(values), freq)
  end

  # BYSETPOS — applied LAST (per RFC 5545). Treats the
  # accumulated `candidates` list as the per-period set and
  # picks the Nth element. Positive ordinals count from the
  # start (1-based), negative from the end (`-1` = last).
  defp apply_entry({:set_position, positions}, candidates, _freq, _selection, _wkst) do
    pick_set_positions(candidates, List.wrap(positions))
  end

  # Unknown tokens pass through unchanged.
  defp apply_entry(_entry, candidates, _freq, _selection, _wkst), do: candidates

  # BYDAY-no-ordinal role dispatcher (RFC §3.3.10 notes).
  defp day_determined_by_later_part?(selection) do
    Enum.any?(selection, fn
      {token, _value} ->
        token in [:day, :byday, :day_of_week, :day_of_year, :nearest_weekday, :or_day]

      _other ->
        false
    end)
  end

  defp no_ordinal_byday_role(:month, selection) do
    if Keyword.has_key?(selection, :day), do: :limit, else: {:expand, :month}
  end

  defp no_ordinal_byday_role(:year, selection) do
    cond do
      Keyword.has_key?(selection, :day) or Keyword.has_key?(selection, :day_of_year) ->
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

  defp no_ordinal_byday_role(:week, _selection), do: {:expand, :week}
  defp no_ordinal_byday_role(_, _), do: :limit

  # BYDAY-with-ordinal period scope (for `nth_kday` anchoring):
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
  ## Generic LIMIT helper
  ## ------------------------------------------------------------

  # `extractor` pulls an integer (or nil) from a candidate. Keeps
  # candidates whose extracted value is in `targets` (a single
  # integer or a list). `nil` extractions drop the candidate.
  defp limit(candidates, targets, extractor) do
    values = List.wrap(targets)

    Enum.filter(candidates, fn candidate ->
      case extractor.(candidate) do
        nil -> false
        value when is_integer(value) -> value in values
      end
    end)
  end

  defp month_of(%Interval{from: %Tempo{time: time}}), do: Keyword.get(time, :month)

  ## ------------------------------------------------------------
  ## BYMONTHDAY
  ## ------------------------------------------------------------

  defp in_month_day_list?(%Interval{} = candidate, days) do
    case {day_of(candidate), days_in_enclosing_month(candidate)} do
      {nil, _} -> false
      {_, nil} -> false
      {day, dim} -> Enum.any?(days, &matches_signed_index?(&1, day, dim))
    end
  end

  defp day_of(%Interval{from: %Tempo{time: time}}), do: Keyword.get(time, :day)

  defp days_in_enclosing_month(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    year = Keyword.get(time, :year)
    month = Keyword.get(time, :month)

    if is_integer(year) and is_integer(month) do
      calendar.days_in_month(year, month)
    end
  end

  ## ------------------------------------------------------------
  ## BYYEARDAY
  ## ------------------------------------------------------------

  defp in_year_day_list?(%Interval{} = candidate, target_days) do
    case {day_of_year_of(candidate), days_in_enclosing_year(candidate)} do
      {nil, _} -> false
      {_, nil} -> false
      {doy, diy} -> Enum.any?(target_days, &matches_signed_index?(&1, doy, diy))
    end
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

  defp days_in_enclosing_year(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> calendar.days_in_year(year)
      _ -> nil
    end
  end

  ## ------------------------------------------------------------
  ## BYWEEKNO
  ## ------------------------------------------------------------

  defp in_week_no_list?(%Interval{} = candidate, weeks) do
    case {iso_week_of(candidate), weeks_in_enclosing_year(candidate)} do
      {nil, _} -> false
      {_, nil} -> false
      {wk, wiy} -> Enum.any?(weeks, &matches_signed_index?(&1, wk, wiy))
    end
  end

  # Dispatch to the candidate's calendar for its ISO-week number.
  # ISO weeks are Monday-first by definition and are what RFC
  # 5545 §3.3.10 specifies for BYWEEKNO ("Week numbers refer to
  # ISO week"). WKST does not shift ISO week numbering — the
  # two are orthogonal.
  defp iso_week_of(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      {_year, week} = calendar.iso_week_of_year(year, month, day)
      week
    else
      _ -> nil
    end
  end

  defp weeks_in_enclosing_year(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) ->
        # Some Calendar implementations (e.g. `Calendrical.Gregorian`)
        # return `{weeks, days_in_last_week}` from `weeks_in_year/1`;
        # others return just the integer. Accept either.
        case calendar.weeks_in_year(year) do
          {weeks, _days_in_last_week} when is_integer(weeks) -> weeks
          weeks when is_integer(weeks) -> weeks
          _ -> nil
        end

      _ ->
        nil
    end
  end

  ## ------------------------------------------------------------
  ## BYDAY (weekday filter / expander)
  ## ------------------------------------------------------------

  defp weekday_of(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      calendar.day_of_week(year, month, day, :monday)
      |> normalise_day_of_week()
    else
      _ -> nil
    end
  end

  # `Calendar.day_of_week/4` can return `:undefined` or a tuple
  # depending on the calendar implementation; coerce to a 1..7
  # integer (ISO, Monday=1) or `nil` when the calendar refuses.
  defp normalise_day_of_week(dow) when is_integer(dow) and dow in 1..7, do: dow
  defp normalise_day_of_week({dow, _first, _last}) when is_integer(dow), do: dow
  defp normalise_day_of_week(_), do: nil

  # True when the candidate's weekday matches any `{ordinal, weekday}`
  # entry. Used by the POSIX OR filter, where the entries are plain
  # weekdays (the ordinal is `nil`), so only the weekday is compared.
  defp weekday_matches?(%Interval{} = candidate, byday_entries) do
    case weekday_of(candidate) do
      nil -> false
      weekday -> Enum.any?(byday_entries, fn {_ordinal, day} -> day == weekday end)
    end
  end

  # Walk every date in the candidate's enclosing week/month/year
  # and emit one new candidate per matching weekday. We preserve
  # the candidate's time-of-day and metadata; only the date
  # component changes. Every calendar op goes through the
  # candidate's own calendar.
  defp expand_weekdays_in_month(%Interval{from: %Tempo{calendar: calendar}} = candidate, weekdays) do
    case enclosing_month(candidate) do
      nil ->
        [candidate]

      {year, month} ->
        emit_matching_days(
          candidate,
          year,
          month,
          1..calendar.days_in_month(year, month),
          weekdays
        )
    end
  end

  defp expand_weekdays_in_year(%Interval{from: %Tempo{calendar: calendar}} = candidate, weekdays) do
    case enclosing_year(candidate) do
      nil ->
        [candidate]

      year ->
        1..calendar.months_in_year(year)
        |> Enum.flat_map(fn month ->
          emit_matching_days(
            candidate,
            year,
            month,
            1..calendar.days_in_month(year, month),
            weekdays
          )
        end)
    end
  end

  defp expand_weekdays_in_week(%Interval{} = candidate, weekdays, wkst) do
    case week_date_range(candidate, wkst) do
      nil ->
        [candidate]

      dates ->
        dates
        |> Enum.filter(fn {_year, _month, _day, dow} -> dow in weekdays end)
        |> Enum.map(fn {year, month, day, _dow} ->
          swap_date(candidate, year, month, day)
        end)
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
    days
    |> Enum.filter(fn day ->
      dow = calendar.day_of_week(year, month, day, :monday) |> normalise_day_of_week()
      dow in weekdays
    end)
    |> Enum.map(fn day -> swap_date(candidate, year, month, day) end)
  end

  # Build the week around the candidate's date as seven
  # `{year, month, day, weekday}` tuples in chronological order,
  # with the week anchored on `wkst` (1..7, Monday=1, default 1).
  # For `wkst = k` the week starts on the `k`-th weekday
  # preceding-or-equal-to the candidate, computed via
  # `Integer.mod(candidate_dow - wkst, 7)`.
  defp week_date_range(%Interval{from: %Tempo{time: time, calendar: calendar}}, wkst) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day),
         dow when is_integer(dow) <-
           calendar.day_of_week(year, month, day, :monday) |> normalise_day_of_week(),
         {:ok, date} <- Date.new(year, month, day, calendar) do
      offset_back = Integer.mod(dow - wkst, 7)
      week_start = Date.add(date, -offset_back)

      for i <- 0..6 do
        d = Date.add(week_start, i)

        d_dow =
          calendar.day_of_week(d.year, d.month, d.day, :monday) |> normalise_day_of_week()

        {d.year, d.month, d.day, d_dow}
      end
    else
      _ -> nil
    end
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
  defp swap_date(
         %Interval{from: %Tempo{time: time, calendar: calendar} = tempo, to: to} = candidate,
         year,
         month,
         day
       ) do
    new_from_time = replace_unit_values(time, year: year, month: month, day: day)
    new_from = %{tempo | time: new_from_time}
    new_to = shift_to_endpoint(to, time, new_from_time, calendar)
    %{candidate | from: new_from, to: new_to}
  end

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

  defp shift_to_endpoint(nil, _old, _new, _calendar), do: nil
  defp shift_to_endpoint(:undefined, _old, _new, _calendar), do: :undefined

  defp shift_to_endpoint(%Tempo{time: to_time} = to_tempo, old_from_time, new_from_time, calendar) do
    # Shift `to`'s date component by the same calendar-aware
    # day-delta that took `from` to its new position. Preserves
    # hour/minute/second on `to` so a 10:00–11:00 event stays
    # 10:00–11:00 on its new date.
    case delta_days(old_from_time, new_from_time, calendar) do
      nil ->
        to_tempo

      delta ->
        case shift_date_fields(to_time, delta, calendar) do
          nil -> to_tempo
          shifted_time -> %{to_tempo | time: shifted_time}
        end
    end
  end

  defp delta_days(from_time, to_time, calendar) do
    with {:ok, a} <- date_of(from_time, calendar),
         {:ok, b} <- date_of(to_time, calendar) do
      Date.diff(b, a)
    else
      _ -> nil
    end
  end

  defp shift_date_fields(time, delta, calendar) do
    case date_of(time, calendar) do
      {:ok, date} ->
        new_date = Date.add(date, delta)
        replace_unit_values(time, year: new_date.year, month: new_date.month, day: new_date.day)

      _ ->
        nil
    end
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
    months_in_year = calendar.months_in_year(year)

    months
    |> Enum.map(fn month ->
      day =
        cond do
          provisional_day? -> 1
          is_integer(origin_day) -> origin_day
          true -> candidate.from.time[:day]
        end

      cond do
        not (is_integer(month) and month >= 1 and month <= months_in_year) ->
          nil

        not is_integer(day) ->
          nil

        true ->
          swap_date(candidate, year, month, min(day, calendar.days_in_month(year, month)))
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # BYMONTHDAY with FREQ=MONTHLY or YEARLY: for each candidate,
  # produce one occurrence per listed day (signed: -1 = last day
  # of enclosing month). Invalid combinations skip.
  defp expand_candidate_days(%Interval{from: %Tempo{calendar: calendar}} = candidate, days) do
    year = candidate.from.time[:year]
    month = candidate.from.time[:month]
    dim = calendar.days_in_month(year, month)

    days
    |> Enum.map(fn d ->
      resolved = signed_index_to_value(d, dim)

      if is_integer(resolved) and resolved >= 1 and resolved <= dim do
        swap_date(candidate, year, month, resolved)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  ## ------------------------------------------------------------
  ## Nearest-weekday (cron `W`)
  ## ------------------------------------------------------------

  # Project each target (`15`, `1`, `:last`) onto the nearest
  # weekday within the candidate's own month, then emit one new
  # candidate per resolved date.
  defp expand_nearest_weekdays(%Interval{} = candidate, targets) do
    candidate
    |> nearest_weekday_days(targets)
    |> Enum.map(fn day ->
      swap_date(candidate, candidate.from.time[:year], candidate.from.time[:month], day)
    end)
  end

  # The concrete day-of-month each target resolves to in the
  # candidate's month (deduplicated; out-of-range targets dropped).
  defp nearest_weekday_days(%Interval{from: %Tempo{calendar: calendar, time: time}}, targets) do
    year = Keyword.get(time, :year)
    month = Keyword.get(time, :month)

    if is_integer(year) and is_integer(month) do
      dim = calendar.days_in_month(year, month)

      targets
      |> Enum.map(&nearest_weekday(calendar, year, month, &1, dim))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    else
      []
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

  # BYYEARDAY with FREQ=YEARLY: one occurrence per listed
  # day-of-year (signed). Convert ordinal → {month, day} via
  # the calendar's day-of-year axis.
  defp expand_candidate_year_days(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         year_days
       ) do
    year = candidate.from.time[:year]
    diy = calendar.days_in_year(year)

    year_days
    |> Enum.map(fn d ->
      resolved = signed_index_to_value(d, diy)

      if is_integer(resolved) and resolved >= 1 and resolved <= diy do
        year_day_to_month_day(calendar, year, resolved)
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {m, day} -> swap_date(candidate, year, m, day) end)
  end

  # BYWEEKNO with FREQ=YEARLY: one occurrence per listed ISO
  # week number (signed). A single-week expansion yields 7
  # occurrences (each day of the week). Days outside the year
  # are dropped.
  defp expand_candidate_week_numbers(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         weeks
       ) do
    year = candidate.from.time[:year]
    wiy = weeks_in_year(calendar, year)

    Enum.flat_map(weeks, fn wk -> week_candidate_dates(wk, candidate, calendar, year, wiy) end)
  end

  defp week_candidate_dates(wk, candidate, calendar, year, wiy) do
    resolved = signed_index_to_value(wk, wiy)

    if is_integer(resolved) and resolved >= 1 and resolved <= wiy do
      week_dates_in_year(calendar, year, resolved)
      |> Enum.map(fn {m, day} -> swap_date(candidate, year, m, day) end)
    else
      []
    end
  end

  # Map a {month, day} pair back from a day-of-year ordinal by
  # walking the calendar's month lengths. Returns `nil` if out
  # of range.
  defp year_day_to_month_day(calendar, year, doy) when is_integer(doy) and doy >= 1 do
    months = 1..calendar.months_in_year(year)

    Enum.reduce_while(months, doy, fn month, remaining ->
      days_in_this_month = calendar.days_in_month(year, month)

      if remaining <= days_in_this_month do
        {:halt, {month, remaining}}
      else
        {:cont, remaining - days_in_this_month}
      end
    end)
    |> case do
      {m, d} when is_integer(m) and is_integer(d) -> {m, d}
      _ -> nil
    end
  end

  # Emit the (up to 7) {month, day} pairs that fall inside `year`
  # for the given ISO week number. Monday-first by construction.
  defp week_dates_in_year(calendar, year, week) do
    # Find the Monday of the requested ISO week. Walk from Jan 4
    # back to the Monday of its ISO week (week 1), then add
    # (week - 1) * 7 days.
    with {:ok, anchor} <- Date.new(year, 1, 4, calendar),
         anchor_dow when is_integer(anchor_dow) <-
           calendar.day_of_week(year, 1, 4, :monday) |> normalise_day_of_week() do
      week_1_monday = Date.add(anchor, -(anchor_dow - 1))
      week_start = Date.add(week_1_monday, (week - 1) * 7)

      for i <- 0..6,
          d = Date.add(week_start, i),
          d.year == year do
        {d.month, d.day}
      end
    else
      _ -> []
    end
  end

  defp weeks_in_year(calendar, year) do
    case calendar.weeks_in_year(year) do
      {weeks, _} when is_integer(weeks) -> weeks
      weeks when is_integer(weeks) -> weeks
      _ -> 52
    end
  end

  # Utility — resolve a signed index against an upper bound.
  # `3` in a range of 31 → 3. `-1` in 31 → 31. `-3` in 31 → 29.
  defp signed_index_to_value(n, max) when is_integer(n) and is_integer(max) do
    cond do
      n > 0 and n <= max -> n
      n < 0 and -n <= max -> max + n + 1
      true -> nil
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
    end
  end

  # Compute the enclosing period's start and end `Date` values in
  # the candidate's own calendar. Month scope: 1st..last of the
  # candidate's month. Year scope: Jan 1..(Dec or last month) of
  # the candidate's year.
  defp period_bounds(%Interval{from: %Tempo{time: time, calendar: calendar}}, :month) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         last_day when is_integer(last_day) <- calendar.days_in_month(year, month),
         {:ok, start_date} <- Date.new(year, month, 1, calendar),
         {:ok, end_date} <- Date.new(year, month, last_day, calendar) do
      {start_date, end_date}
    else
      _ -> nil
    end
  end

  defp period_bounds(%Interval{from: %Tempo{time: time, calendar: calendar}}, :year) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         last_month when is_integer(last_month) <- calendar.months_in_year(year),
         last_day when is_integer(last_day) <- calendar.days_in_month(year, last_month),
         {:ok, start_date} <- Date.new(year, 1, 1, calendar),
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
  defp resolve_byday_pair(%Interval{} = candidate, {nil, weekday}, _start, _end, scope, _wkst) do
    case scope do
      :month -> expand_weekdays_in_month(candidate, [weekday])
      :year -> expand_weekdays_in_year(candidate, [weekday])
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
    anchor = if ordinal >= 0, do: start_date, else: end_date

    case Kday.nth_kday(anchor, ordinal, weekday) do
      %Date{year: y, month: m, day: d} = d_struct ->
        if date_in_period?(d_struct, start_date, end_date),
          do: [swap_date(candidate, y, m, d)],
          else: []

      _ ->
        []
    end
  end

  # `nth_kday` may return a date outside the intended period
  # when the ordinal exceeds the number of matching weekdays
  # (e.g. `5MO` in a month with only 4 Mondays). Clamp by
  # checking the period boundaries.
  defp date_in_period?(%Date{} = date, %Date{} = start_date, %Date{} = end_date) do
    Date.compare(date, start_date) != :lt and Date.compare(date, end_date) != :gt
  end

  ## ------------------------------------------------------------
  ## BYSETPOS — applied last, per-period
  ## ------------------------------------------------------------

  # Candidates arrive here in chronological order (the earlier
  # BY-rule expanders walk periods in order). Positive positions
  # are 1-based from the start; negative from the end. We
  # preserve the caller's ordering of the positions list but
  # drop out-of-range picks.
  defp pick_set_positions([], _positions), do: []

  defp pick_set_positions(candidates, positions) do
    total = length(candidates)
    indexed = Enum.with_index(candidates, 1)

    positions
    |> Enum.map(fn pos -> nth_candidate(indexed, total, pos) end)
    |> Enum.reject(&is_nil/1)
  end

  defp nth_candidate(indexed, total, pos) do
    target = if pos > 0, do: pos, else: total + pos + 1

    case Enum.find(indexed, fn {_c, i} -> i == target end) do
      {candidate, _i} -> candidate
      nil -> nil
    end
  end

  ## ------------------------------------------------------------
  ## BYHOUR / BYMINUTE / BYSECOND
  ## ------------------------------------------------------------

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

  defp expand_or_limit_time(candidates, unit, values, freq) do
    if Map.get(@unit_weight, freq, 0) < Map.get(@unit_weight, unit, 0) do
      expand_time(candidates, unit, values)
    else
      limit_time(candidates, unit, values)
    end
  end

  defp expand_time(candidates, unit, values) do
    Enum.flat_map(candidates, fn candidate ->
      Enum.map(values, fn value -> set_time_unit(candidate, unit, value) end)
    end)
  end

  defp limit_time(candidates, unit, values) do
    Enum.filter(candidates, fn candidate ->
      current = get_time_unit(candidate, unit)
      is_integer(current) and current in values
    end)
  end

  defp get_time_unit(%Interval{from: %Tempo{time: time}}, unit), do: Keyword.get(time, unit)

  defp set_time_unit(%Interval{from: %Tempo{time: time} = tempo} = candidate, unit, value) do
    new_time = upsert_unit(time, unit, value)
    %{candidate | from: %{tempo | time: new_time}}
  end

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
      insert_unit_in_order(time, unit, value)
    end
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

  ## ------------------------------------------------------------
  ## Signed-index match helper
  ##
  ## RFC 5545 expresses "last day of month", "second to last week
  ## of year", etc. as negative integers. `matches_signed_index?`
  ## accepts both positive and negative targets against a value
  ## whose maximum-in-period is `max` (e.g. 31 for Jan, 366 for a
  ## leap year, 53 for ISO weeks).
  ## ------------------------------------------------------------

  defp matches_signed_index?(target, value, max)
       when is_integer(target) and is_integer(value) and is_integer(max) do
    cond do
      target > 0 -> target == value
      target < 0 -> max + target + 1 == value
      true -> false
    end
  end

  defp matches_signed_index?(_target, _value, _max), do: false
end
