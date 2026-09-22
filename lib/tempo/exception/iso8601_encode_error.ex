defmodule Tempo.Iso8601EncodeError do
  @moduledoc """
  Exception raised when a `Tempo` value cannot be rendered as an ISO 8601
  string because it contains a construct with no ISO 8601 representation.

  Two constructs raise it. A **nearest-weekday** recurrence — the cron `W`
  day-of-month modifier (`15W`, `LW`), parsed by `Tempo.Cron` into a
  `:nearest_weekday` token — has no ISO 8601 designator and, unlike RFC 5545
  `BYSETPOS`/`WKST`, no project-specific one (the equivalent day-level
  operation is `Tempo.nearest_working_day/2`); it round-trips only through its
  cron string. An **ordinal BYDAY across distinct weekdays** (`BYDAY=2MO,2WE`)
  has no ISO form either — the §12.9 position designator `I` applies to one
  resolved set, so interleaved weekday/position cannot be written — and
  round-trips only through its RRULE string via `Tempo.to_rrule/1`.

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
      "cron string; for the day-level operation use `Tempo.nearest_working_day/2`."
  end

  def message(%__MODULE__{construct: :byday}) do
    "Cannot encode an ordinal BYDAY across distinct weekdays (e.g. " <>
      "`BYDAY=2MO,2WE`) as ISO 8601 — the §12.9 position designator `I` applies " <>
      "to one resolved set, so interleaved weekday/position has no ISO form. It " <>
      "is expressible only as an RFC 5545 RRULE string; use `Tempo.to_rrule/1`."
  end

  def message(%__MODULE__{construct: construct}) do
    "Cannot encode #{inspect(construct)} as ISO 8601 — it has no ISO 8601 representation."
  end
end
