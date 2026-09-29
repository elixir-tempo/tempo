defmodule Tempo.Iso8601EncodeError do
  @moduledoc """
  The error `Tempo.to_iso8601/1` returns, and `Tempo.to_iso8601!/1` raises,
  for a value with no ISO 8601 representation.

  That is a value of a type ISO 8601 has no form for — a
  `t:Tempo.IntervalSet.t/0` or a `t:Tempo.RecurrenceSet.t/0`, which are sets
  of intervals and of recurrences, a conditional member of a recurrence set,
  or anything that is not a Tempo value — or a Tempo value holding one of two
  constructs. A **nearest-weekday** recurrence — the cron `W`
  day-of-month modifier (`15W`, `LW`), parsed by `Tempo.Cron` into a
  `:nearest_weekday` token — has no ISO 8601 designator and, unlike RFC 5545
  `BYSETPOS`/`WKST`, no project-specific one (the equivalent day-level
  operation is `Tempo.nearest_workday/2`); it round-trips only through its
  cron string. An **ordinal BYDAY across distinct weekdays** (`BYDAY=2MO,2WE`)
  has no ISO form either — the §12.9 position designator `I` applies to one
  resolved set, so interleaved weekday/position cannot be written — and
  round-trips only through its RRULE string via `Tempo.RRule.to_string/1`.

  """

  defexception [:construct, :value]

  @type t :: %__MODULE__{
          construct: atom() | nil,
          value: term() | nil
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

  def message(%__MODULE__{construct: :value, value: value}) do
    "Cannot encode #{inspect(value)} as ISO 8601 — `Tempo.to_iso8601/1` encodes " <>
      "a `Tempo`, a `Tempo.Interval`, a `Tempo.Duration` or a `Tempo.Set`."
  end

  def message(%__MODULE__{construct: construct}) do
    "Cannot encode #{inspect(construct)} as ISO 8601 — it has no ISO 8601 representation."
  end
end
