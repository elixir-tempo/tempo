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
    multi-year cron field such as `2025,2027,2029`. The expander
    materialises the cadence up to the last listed year and keeps
    only occurrences whose year is in the list.

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
        rule.bymonthday_or_byday
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

  ### Arguments

  * `rule` is a `t:t/0`.

  ### Returns

  * A `%Tempo{}` carrying `[selection: …]`, or `nil` when the rule has no
    `BY*` filter and a default `WKST` (the simple recurrence needs no
    repeat rule).

  ### Examples

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :monthly, byday: [{2, 1}]})
      ~o"L1K2IN"

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :daily})
      nil

  """
  # No `@spec`: the result is a `%Tempo{}` carrying a `{:selection, …}` token,
  # which the `Tempo.t()` type's `token_list()` does not yet enumerate, so a
  # `Tempo.t()` spec would read as an incomplete return type to Dialyzer.
  def to_selection(%__MODULE__{} = rule) do
    if has_by_rules?(rule) or non_default_wkst?(rule) do
      selection =
        []
        |> push_by(rule.bymonth, :month)
        |> push_by(rule.bymonthday, :day)
        |> push_by(rule.bymonthday_nearest, :nearest_weekday)
        |> push_or_day(rule.bymonthday_or_byday)
        |> push_by(rule.byyearday, :day_of_year)
        |> push_by(rule.byweekno, :week)
        |> push_byday(rule.byday)
        |> push_by(rule.byhour, :hour)
        |> push_by(rule.byminute, :minute)
        |> push_by(rule.bysecond, :second)
        |> push_by(rule.bysetpos, :instance)
        |> push_wkst(rule.wkst)
        |> Enum.reverse()
        |> Parser.consolidate_selection()

      %Tempo{time: [selection: selection], calendar: Calendrical.Gregorian}
    end
  end

  defp non_default_wkst?(%__MODULE__{wkst: wkst}) when is_integer(wkst) and wkst != 1, do: true
  defp non_default_wkst?(_rule), do: false

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
  #     single-position ISO form, so they stay `{:byday, entries}` (RRULE-only).
  defp push_byday(acc, nil), do: acc
  defp push_byday(acc, []), do: acc

  defp push_byday(acc, entries) when is_list(entries) do
    cond do
      Enum.all?(entries, fn {ordinal, _day} -> is_nil(ordinal) end) ->
        push_day_of_week(acc, Enum.map(entries, fn {nil, day} -> day end))

      single_weekday_ordinals(entries) ->
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
