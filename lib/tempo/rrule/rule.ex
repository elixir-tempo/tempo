defmodule Tempo.RRule.Rule do
  @moduledoc """
  A canonical, typed representation of an RFC 5545 RRULE.

  This is the input to `Tempo.RRule.Expander.expand/3`. Every
  parser (`Tempo.RRule.parse/2`, the `ical` library's
  `%ICal.Recurrence{}`, hand-built rules for tests) converts to
  this shape before expansion runs. Keeping a single struct means
  the expander has one input vocabulary to match against, and all
  `BY*` fields carry their RFC-typed form: lists of integers with
  negative values permitted where the RFC allows.

  ### Fields

  * `:freq` — one of `:second`, `:minute`, `:hour`, `:day`,
    `:week`, `:month`, `:year`. Required.

  * `:interval` — positive integer multiplier for the frequency.
    Default `1`.

  * `:count` — terminate after this many occurrences. Mutually
    exclusive with `:until` per RFC 5545.

  * `:until` — terminate at or before this `t:Tempo.t/0`. Mutually
    exclusive with `:count`.

  * `:wkst` — week-start day as an integer 1–7 (Monday–Sunday, ISO
    convention). Default `1`. Affects `:byweekno` calculations.

  * `:skip` — what the rule does where a month or a year lacks its start's day, as RFC 7529's `SKIP` and JSCalendar's `skip` name it. `:omit`, the default and RFC 5545's rule, lists no occurrence there: the rule states its start's day (ISO 8601-2 Annex C.3), and a day a month lacks is passed over. `:backward` lists the period's last day, as an ISO 8601 recurrence does.

  * `:bymonth` — list of integers 1–12. Limit.

  * `:bymonthday` — list of integers -31..31 (negatives count from
    the end of the month). Limit or expand per FREQ.

  * `:byyearday` — list of integers -366..366. Limit or expand
    per FREQ.

  * `:byweekno` — list of integers -53..53. Used only with
    `:yearly` FREQ. Limit or expand.

  * `:byday` — list of `{ordinal_or_nil, weekday_1_to_7}` tuples.
    With MONTHLY / YEARLY and no BYWEEKNO, ordinals select the
    Nth/-Nth weekday within the period. With other FREQs,
    ordinals are ignored (filter only).

  * `:byhour` / `:byminute` / `:bysecond` — lists of integers.
    Limit or expand per FREQ.

  * `:bysetpos` — list of integers; applied last to pick the Nth
    element of the per-period candidate set.

  * `:byyear` — list of absolute years. A non-standard extension
    (RFC 5545 has no `BYYEAR`); used by `Tempo.Cron` to honour a
    cron year field such as `2025,2027,2029`. It becomes a year in
    the selection, which keeps only the periods in a listed year.

  * `:bymonthday_nearest` — list of `pos_integer()` days or the
    atom `:last`. A non-standard extension carrying the cron `W`
    (nearest-weekday) modifier: `15W` becomes `[15]`, `LW` becomes
    `[:last]`. Each target snaps to the nearest weekday within the
    same month (Saturday → Friday, Sunday → Monday), never crossing
    a month boundary, so `1W` on a Saturday lands on the 3rd.

  * `:bymonthday_or_byday` — a `{monthdays, byday_entries}` tuple. A
    non-standard extension carrying POSIX cron's day-of-month **OR**
    day-of-week union: when both fields are restricted (`13 * 5` —
    "the 13th *or* any Friday"), a candidate is kept if its day is in
    `monthdays` **or** its weekday matches `byday_entries`. Unlike the
    AND-composing `:bymonthday` + `:byday`, which would select only
    Friday-the-13ths.

  """

  alias Tempo.Iso8601.Parser

  @type frequency :: :second | :minute | :hour | :day | :week | :month | :year
  @type weekday :: 1..7
  @type byday_entry :: {integer() | nil, weekday()}

  @type t :: %__MODULE__{
          freq: frequency(),
          interval: pos_integer(),
          count: pos_integer() | nil,
          until: Tempo.t() | nil,
          wkst: weekday(),
          skip: :omit | :backward,
          bymonth: [integer()] | nil,
          bymonthday: [integer()] | nil,
          byyearday: [integer()] | nil,
          byweekno: [integer()] | nil,
          byday: [byday_entry()] | nil,
          byhour: [non_neg_integer()] | nil,
          byminute: [non_neg_integer()] | nil,
          bysecond: [non_neg_integer()] | nil,
          bysetpos: [integer()] | nil,
          byyear: [integer()] | nil,
          bymonthday_nearest: [pos_integer() | :last] | nil,
          bymonthday_or_byday: {[integer()], [byday_entry()]} | nil
        }

  defstruct freq: nil,
            interval: 1,
            count: nil,
            until: nil,
            wkst: 1,
            skip: :omit,
            bymonth: nil,
            bymonthday: nil,
            byyearday: nil,
            byweekno: nil,
            byday: nil,
            byhour: nil,
            byminute: nil,
            bysecond: nil,
            bysetpos: nil,
            byyear: nil,
            bymonthday_nearest: nil,
            bymonthday_or_byday: nil

  @doc """
  Does the rule include any `BY*` modifier?

  `true` when any `BY*` field is non-nil. Used by the expander to
  skip the BY-rule pipeline entirely for simple FREQ-only rules.

  ### Examples

      iex> Tempo.RRule.Rule.has_by_rules?(%Tempo.RRule.Rule{freq: :weekly})
      false

      iex> Tempo.RRule.Rule.has_by_rules?(%Tempo.RRule.Rule{freq: :weekly, byday: [{nil, 1}]})
      true

  """
  @spec has_by_rules?(t()) :: boolean()
  def has_by_rules?(%__MODULE__{} = rule) do
    Enum.any?(
      [
        rule.bymonth,
        rule.bymonthday,
        rule.byyearday,
        rule.byweekno,
        rule.byday,
        rule.byhour,
        rule.byminute,
        rule.bysecond,
        rule.bysetpos,
        rule.bymonthday_nearest,
        rule.bymonthday_or_byday,
        rule.byyear
      ],
      &(&1 != nil)
    )
  end

  @doc """
  Project a rule's `BY*` filters onto the `%Tempo{}` selection carried in a
  recurring interval's `:repeat_rule`.

  This is the single source of truth for the RRULE/cron → selection mapping:
  both `Tempo.RRule.parse/2` (over a parsed keyword list) and
  `Tempo.RRule.Expander` (over a `%Rule{}`) build their selection here, so the
  token vocabulary above cannot drift between the two paths.

  The `BY*` filters are pushed coarsest-to-finest and the list is consolidated
  (consecutive integers collapse to ranges) so the selection serialises to a
  re-parseable ISO 8601 form. `byday` precedes the time elements because a
  weekday after `T…H…M` is out of resolution order and will not round-trip.

  An ordinal weekday on one weekday (`BYDAY=2FR`) becomes a weekday and a position (`5K2I`), and a position applies last within a selection, so the hours, minutes and seconds the rule names follow the selection instead of joining it: `BYDAY=2FR;BYHOUR=9` is `L5K2INT9H`, as ISO 8601-2 §12.9 writes 09:00 on the second Tuesday. Beside a `BYSETPOS`, which takes the selection's one position, the ordinal stays an RRULE-only `:byday`.

  A rule takes from its start what it does not say, and ISO 8601-2 (Annex C.3 and C.4) has a conversion state each part explicitly. With a start that is a calendar date, a WEEKLY rule with no `BYDAY` selects its start's weekday, a MONTHLY rule with no `BYMONTHDAY` and no `BYDAY` its start's day of the month, and a YEARLY rule with no `BYYEARDAY` its start's month and day of the month, or with `BYWEEKNO` its start's weekday. A day so stated is passed over in a month that lacks it, as RFC 5545 §3.3.10 passes over an instance with an invalid date: a MONTHLY rule from 31 January lists the months of 31 days. The month is stated for a start in the Gregorian calendar alone, since the step from year to year keeps a month that a leap month renumbers. A rule whose `:skip` is `:backward` states no day of the month and no month, and keeps the last day of a period that lacks its start's. Without a start a rule states nothing: a `BYWEEKNO` rule keeps every day of its weeks.

  ### Arguments

  * `rule` is a `t:t/0`.

  * `dtstart` is the rule's start as a `t:Tempo.t/0`, or `nil` when it has
    none. The default is `nil`.

  ### Returns

  * A `%Tempo{}` carrying `[selection: …]`, followed by an ordinal weekday's times when it has them, or `nil` when the rule has no `BY*` filter, takes none from its start and has a default `WKST` (the simple recurrence needs no repeat rule).

  ### Examples

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :month, byday: [{2, 1}]})
      ~o"L1K2IN"

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :day})
      nil

      iex> rule = %Tempo.RRule.Rule{freq: :year, byweekno: [20]}
      iex> Tempo.RRule.Rule.to_selection(rule, ~o"1997-05-12")
      ~o"L20W1KN"

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :month}, ~o"2026-01-31")
      ~o"L31DN"

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :year}, ~o"2026-03-10")
      ~o"L3M10DN"

  """
  # No `@spec`: the result is a `%Tempo{}` carrying a `{:selection, …}` token,
  # which the `Tempo.t()` type's `token_list()` does not yet enumerate, so a
  # `Tempo.t()` spec would read as an incomplete return type to Dialyzer.
  def to_selection(%__MODULE__{} = rule, dtstart \\ nil) do
    rule = with_parts_of_start(rule, dtstart)

    if has_by_rules?(rule) or non_default_wkst?(rule) do
      selection =
        []
        |> push_by(rule.byyear, :year)
        |> push_by(rule.bymonth, :month)
        |> push_by(rule.bymonthday, :day)
        |> push_by(rule.bymonthday_nearest, :nearest_weekday)
        |> push_or_day(rule.bymonthday_or_byday)
        |> push_by(rule.byyearday, :day_of_year)
        |> push_by(rule.byweekno, :week)
        |> push_byday(rule.byday, rule.bysetpos)
        |> push_times(rule, not times_after_selection?(rule))
        |> push_by(rule.bysetpos, :instance)
        |> push_wkst(rule.wkst)
        |> Enum.reverse()
        |> Parser.consolidate_selection()

      units =
        []
        |> push_times(rule, times_after_selection?(rule))
        |> Enum.reverse()
        |> Parser.consolidate_selection()

      %Tempo{time: [{:selection, selection} | units], calendar: Calendrical.Gregorian}
    end
  end

  # Whether an ordinal weekday's position picks the day before its times
  # refine it, so the times follow the selection.
  defp times_after_selection?(%__MODULE__{byday: [_ | _] = byday, bysetpos: nil} = rule) do
    single_weekday_ordinals(byday) != nil and
      Enum.any?([rule.byhour, rule.byminute, rule.bysecond], &(&1 not in [nil, []]))
  end

  defp times_after_selection?(_rule), do: false

  defp push_times(acc, rule, true) do
    acc
    |> push_by(rule.byhour, :hour)
    |> push_by(rule.byminute, :minute)
    |> push_by(rule.bysecond, :second)
  end

  defp push_times(acc, _rule, false), do: acc

  defp non_default_wkst?(%__MODULE__{wkst: wkst}) when is_integer(wkst) and wkst != 1, do: true
  defp non_default_wkst?(_rule), do: false

  # ISO 8601-2 Annex C.3 lists what RFC 5545 takes from the start of a rule
  # that does not say it, and Annex C.4 has a conversion state each one: the
  # weekday of a WEEKLY rule with no BYDAY, the day of the month of a MONTHLY
  # rule with no BYMONTHDAY and no BYDAY, and for a YEARLY rule with no
  # BYYEARDAY its month, its day of the month and, with BYWEEKNO, its weekday.
  # A part so stated selects as one the rule wrote does, so a day of the
  # month that a month lacks is passed over, as RFC 5545 §3.3.10 passes over
  # an instance with an invalid date: FREQ=MONTHLY from 31 January lists the
  # months of 31 days. A start that is no one calendar date states nothing.
  defp with_parts_of_start(%__MODULE__{} = rule, %Tempo{time: time} = dtstart) do
    case Enum.map([:year, :month, :day], &Keyword.get(time, &1)) do
      [year, month, day] when is_integer(year) and is_integer(month) and is_integer(day) ->
        with_parts_of(rule, month, day, dtstart)

      _no_one_date ->
        rule
    end
  end

  defp with_parts_of_start(rule, _no_start), do: rule

  defp with_parts_of(%__MODULE__{freq: :week} = rule, _month, _day, dtstart) do
    if names_weekday?(rule), do: rule, else: with_weekday_of(rule, dtstart)
  end

  defp with_parts_of(%__MODULE__{freq: :month} = rule, _month, day, _dtstart) do
    if names_day_of_month?(rule) or names_weekday?(rule) or keeps_last_day?(rule),
      do: rule,
      else: %{rule | bymonthday: [day]}
  end

  defp with_parts_of(%__MODULE__{freq: :year, byyearday: days} = rule, month, day, dtstart)
       when days in [nil, []] do
    rule
    |> with_month_of_start(rule, month, dtstart)
    |> with_day_of_start(rule, day, dtstart)
  end

  defp with_parts_of(rule, _month, _day, _dtstart), do: rule

  # "If no BYMONTH or BYWEEKNO parameter is set: if the BYMONTHDAY parameter
  # is provided, then the BYMONTH selection is inherited from the calendar
  # month of year value from the initial start date; if the BYDAY parameter
  # is not set, then the BYMONTH selection is inherited" (Annex C.3). What
  # the rule wrote is asked of `written`, the rule before any part was added.
  #
  # The month is RFC 5545's, a month of the Gregorian calendar, and is
  # written for a start in that calendar alone. In another the step from year
  # to year keeps the start's month as the calendar does, and a BYMONTH,
  # which numbers a month by its place in the year, would not: Nisan is the
  # seventh month of a Hebrew year and the eighth of one with a leap month.
  defp with_month_of_start(rule, written, month, %Tempo{calendar: calendar})
       when calendar in [Calendrical.Gregorian, Calendar.ISO, nil] do
    if empty?(written.bymonth) and empty?(written.byweekno) and not keeps_last_day?(written) and
         (names_day_of_month?(written) or not names_weekday?(written)),
       do: %{rule | bymonth: [month]},
       else: rule
  end

  defp with_month_of_start(rule, _written, _month, _dtstart), do: rule

  # "If no BYMONTHDAY, BYWEEKNO or BYDAY parameter is set, the BYMONTHDAY
  # selection is inherited from the calendar day of month of the initial start
  # date. If there is a BYWEEKNO parameter set but no BYMONTHDAY or BYDAY, the
  # BYDAY selection is inherited from the calendar day of week" (Annex C.3).
  defp with_day_of_start(rule, written, day, dtstart) do
    cond do
      names_day_of_month?(written) or names_weekday?(written) -> rule
      not empty?(written.byweekno) -> with_weekday_of(rule, dtstart)
      keeps_last_day?(written) -> rule
      true -> %{rule | bymonthday: [day]}
    end
  end

  # A rule that keeps the last day of a period without its start's day
  # (`skip: :backward`) leaves the day, and the month it is in, to the step
  # from its start, which the calendar's own arithmetic takes to that day.
  defp keeps_last_day?(%__MODULE__{skip: skip}), do: skip == :backward

  # The weekday is Monday 1 to Sunday 7, as BYDAY numbers it.
  defp with_weekday_of(rule, dtstart),
    do: %{rule | byday: [{nil, Tempo.day_of_week(dtstart, :monday)}]}

  # A cron day of the month that is the nearest weekday, or a day of the
  # month or of the week, names its day as BYMONTHDAY and BYDAY do.
  defp names_day_of_month?(%__MODULE__{} = rule) do
    not (empty?(rule.bymonthday) and empty?(rule.bymonthday_nearest) and
           empty?(rule.bymonthday_or_byday))
  end

  defp names_weekday?(%__MODULE__{} = rule),
    do: not (empty?(rule.byday) and empty?(rule.bymonthday_or_byday))

  defp empty?(part), do: part in [nil, []]

  defp push_by(acc, nil, _unit), do: acc
  defp push_by(acc, [], _unit), do: acc
  defp push_by(acc, [single], unit), do: [{unit, single} | acc]
  defp push_by(acc, list, unit) when is_list(list), do: [{unit, list} | acc]

  defp push_or_day(acc, nil), do: acc

  defp push_or_day(acc, {monthdays, byday_entries}) do
    [{:or_day, {List.wrap(monthdays), List.wrap(byday_entries)}} | acc]
  end

  # BYDAY lowers to ISO 8601-2 §12.9 selection where it can:
  #
  #   * every entry a bare weekday → `{:day_of_week, …}`;
  #   * ordinals all on ONE weekday (`2MO`, `1MO,3MO`) → `{:day_of_week, d}` +
  #     `{:instance, ords}` (weekday then position, the ISO order — `day_of_week`
  #     is prepended after `:instance` so it lands first once the list reverses);
  #   * ordinals across DISTINCT weekdays (`2MO,2WE`, `1MO,-1FR`, mixed) have no
  #     single-position ISO form, so they stay `{:byday, entries}` (RRULE-only);
  #   * an ordinal beside a BYSETPOS, which takes the selection's one position,
  #     stays `{:byday, entries}` too.
  defp push_byday(acc, nil, _bysetpos), do: acc
  defp push_byday(acc, [], _bysetpos), do: acc

  defp push_byday(acc, entries, bysetpos) when is_list(entries) do
    cond do
      Enum.all?(entries, fn {ordinal, _day} -> is_nil(ordinal) end) ->
        push_day_of_week(acc, Enum.map(entries, fn {nil, day} -> day end))

      is_nil(bysetpos) and single_weekday_ordinals(entries) != nil ->
        {day, ordinals} = single_weekday_ordinals(entries)
        [{:instance, ordinals}, {:day_of_week, day} | acc]

      true ->
        [{:byday, entries} | acc]
    end
  end

  # `{day, ordinals}` when every entry carries a non-nil ordinal on a single
  # distinct weekday; `nil` otherwise. One ordinal collapses to an integer.
  defp single_weekday_ordinals(entries) do
    days = entries |> Enum.map(fn {_ordinal, day} -> day end) |> Enum.uniq()
    ordinals = Enum.map(entries, fn {ordinal, _day} -> ordinal end)

    if match?([_], days) and Enum.all?(ordinals, &(not is_nil(&1))) do
      {hd(days), collapse_single(ordinals)}
    end
  end

  defp collapse_single([one]), do: one
  defp collapse_single(many), do: many

  defp push_day_of_week(acc, [single]), do: [{:day_of_week, single} | acc]
  defp push_day_of_week(acc, days), do: [{:day_of_week, days} | acc]

  # Only emit `{:wkst, n}` for a non-default week start (WKST=MO is 1); the
  # common case keeps the AST identical and the token signals intent.
  defp push_wkst(acc, wkst) when is_integer(wkst) and wkst in 2..7, do: [{:wkst, wkst} | acc]
  defp push_wkst(acc, _wkst), do: acc
end
