defmodule Tempo.Iso8601EncodeError do
  @moduledoc """
  The error `Tempo.to_iso8601/1` returns, and `Tempo.to_iso8601!/1` raises,
  for a value with no ISO 8601 representation.

  That is a value of a type ISO 8601 has no form for — a
  `t:Tempo.IntervalSet.t/0` or a `t:Tempo.RecurrenceSet.t/0`, which are sets
  of intervals and of recurrences, a conditional member of a recurrence set,
  or anything that is not a Tempo value — or a Tempo value holding one of four
  constructs. A **nearest-weekday** recurrence — the cron `W`
  day-of-month modifier (`15W`, `LW`), parsed by `Tempo.Cron` into a
  `:nearest_weekday` token — has no ISO 8601 designator and, unlike RFC 5545
  `BYSETPOS`/`WKST`, no project-specific one (the equivalent day-level
  operation is `Tempo.nearest_workday/2`); it round-trips only through its
  cron string. An **ordinal BYDAY across distinct weekdays** (`BYDAY=2MO,2WE`)
  has no ISO form either — the §12.9 position designator `I` applies to one
  resolved set, so interleaved weekday/position cannot be written — and
  round-trips only through its RRULE string via `Tempo.RRule.to_string/1`.
  A cron **day-of-month OR day-of-week** union (`0 0 13 * 5`, the 13th or any Friday) fires when either field holds, where every part of an ISO 8601 selection holds at once; it round-trips only through its cron string. A recurrence's **end** (RFC 5545 `UNTIL`) has no form either: ISO 8601 bounds a recurrence only by its count, and its start/end form names the first occurrence's end; it round-trips through its RRULE string via `Tempo.RRule.to_string/1`.

  A value in a calendar ISO 8601 cannot name has no form either: IXDTF's `[u-ca=…]` names the CLDR calendars and Calendrical's registered ones, so a fiscal or composite calendar built at run time, or a consumer's own, would read back as another calendar. The error's `:calendar` is that calendar.

  """

  defexception [:construct, :value, :calendar]

  @type t :: %__MODULE__{
          construct: atom() | nil,
          value: term() | nil,
          calendar: module() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{construct: :nearest_weekday}) do
    "Cannot encode a nearest-weekday recurrence (cron `W`, e.g. `15W`) as " <>
      "ISO 8601 — it has no ISO 8601 designator. It is expressible only as a " <>
      "cron string; for the day-level operation use `Tempo.nearest_workday/2`."
  end

  def message(%__MODULE__{construct: :until}) do
    "Cannot encode a recurrence's end (RFC 5545 `UNTIL`) as ISO 8601 — ISO 8601 " <>
      "bounds a recurrence only by its count, and its start/end form names the " <>
      "first occurrence's end. Encode it as an RRULE with `Tempo.RRule.to_string/1`."
  end

  def message(%__MODULE__{construct: :or_day}) do
    "Cannot encode a cron day-of-month OR day-of-week union (e.g. `0 0 13 * 5`, " <>
      "the 13th or any Friday) as ISO 8601 — every part of an ISO 8601 selection " <>
      "holds at once. It is expressible only as a cron string."
  end

  def message(%__MODULE__{construct: :byday}) do
    "Cannot encode an ordinal BYDAY across distinct weekdays (e.g. " <>
      "`BYDAY=2MO,2WE`) as ISO 8601 — the §12.9 position designator `I` applies " <>
      "to one resolved set, so interleaved weekday/position has no ISO form. It " <>
      "is expressible only as an RFC 5545 RRULE string; use `Tempo.RRule.to_string/1`."
  end

  def message(%__MODULE__{construct: :recurrence_set}) do
    "Cannot encode a recurrence set as ISO 8601 — ISO 8601 has no form for a set " <>
      "of recurrences. Encode its members one by one (`Tempo.RecurrenceSet.members/1`)."
  end

  def message(%__MODULE__{construct: :interval_set}) do
    "Cannot encode an interval set as ISO 8601 — ISO 8601 has no form for a set " <>
      "of intervals. Encode its members one by one (`Tempo.IntervalSet.members/1`)."
  end

  def message(%__MODULE__{construct: :conditional}) do
    "Cannot encode a conditional member of a recurrence set as ISO 8601 — its " <>
      "condition has no ISO 8601 form. Its `member` can be encoded."
  end

  def message(%__MODULE__{construct: :calendar, calendar: calendar}) do
    "Cannot encode a value in #{inspect(calendar)} as ISO 8601 — IXDTF's " <>
      "`[u-ca=…]` names no such calendar, so the value would read back in another. " <>
      "Convert it with `Tempo.to_calendar/2` first."
  end

  def message(%__MODULE__{construct: :value, value: value}) do
    "Cannot encode #{inspect(value)} as ISO 8601 — `Tempo.to_iso8601/1` encodes " <>
      "a `Tempo`, a `Tempo.Interval`, a `Tempo.Duration` or a `Tempo.Set`."
  end

  def message(%__MODULE__{construct: construct}) do
    "Cannot encode #{inspect(construct)} as ISO 8601 — it has no ISO 8601 representation."
  end
end
