defmodule Tempo.ConversionError do
  @moduledoc """
  Exception returned, or raised by a bang function, when a value
  cannot be converted to what was asked for: a standard-library
  `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or
  `t:DateTime.t/0`, an ISO 8601 or RRULE string, or — from
  `Tempo.to_interval/2` and `Tempo.to_interval_set/2` — the interval
  or occurrences a value spans.

  A value with no interval of its own says why in `:reason`:

  * `:bare_duration` — a duration has no place on the time line.

  * `:one_of_set` — a one-of set is an epistemic disjunction, not a
    list of intervals.

  * `:finest_resolution` — no finer unit exists to bound the span.

  * `:unanchored_group` — a group with no year or month to bound it,
    such as `5G10DU`, days 41 to 50 of no particular year.

  * `:open_range` — one end of the range is unbounded.

  * `:recurring_interval` and `:recurring_duration` — a recurrence
    is a rule for its occurrences, not one span.

  * `:recurrence_set_member` and `:conditional_member` — a
    `Tempo.RecurrenceSet` member of a shape it cannot hold.

  """

  defexception [:value, :target, :reason]

  @type t :: %__MODULE__{
          value: any() | nil,
          target: atom() | module() | String.t() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{reason: :bare_duration}) do
    "Cannot convert a Tempo.Duration to an interval — a duration has no " <>
      "place on the time line."
  end

  def message(%__MODULE__{reason: :one_of_set}) do
    "Cannot convert a one-of Tempo.Set to an interval — epistemic " <>
      "disjunction is not an interval list. Pick one member, handle the " <>
      "disjunction explicitly, or ask a certainty question " <>
      "(`Tempo.relation_certainty/3`, `Tempo.possibly_before?/2`, …)."
  end

  def message(%__MODULE__{reason: :recurrence_set_member, value: value}) do
    "Cannot read #{inspect(value)} as a Tempo.RecurrenceSet member — a " <>
      "member is a Tempo.Interval (a recurrence or a concrete interval), a Tempo value, " <>
      "or a nested Tempo.RecurrenceSet."
  end

  def message(%__MODULE__{reason: :conditional_member, value: value}) do
    "Cannot resolve #{inspect(value)} as a conditional Tempo.RecurrenceSet member — it " <>
      "needs :falls_on, a metadata map or a recurrence set, and either :at, a list of durations " <>
      "(Tempo.RecurrenceSet.keep_when/2), or :to_next, a selector " <>
      "(Tempo.RecurrenceSet.move_when/2)."
  end

  def message(%__MODULE__{reason: :recurring_interval}) do
    "A recurring interval is a rule generating occurrences, not a single span. " <>
      "Convert it to its occurrences with `Tempo.to_interval/2` (pass `:within` for an " <>
      "unbounded recurrence) and use the set-level API (`Tempo.overlaps?/2`, " <>
      "`Tempo.IntervalSet.relation_matrix/2`)."
  end

  def message(%__MODULE__{reason: :recurring_duration}) do
    "The duration of a finite recurring interval is the total across its " <>
      "occurrences — convert it with `Tempo.to_interval/1` and use " <>
      "`Tempo.IntervalSet.duration/1`."
  end

  def message(%__MODULE__{reason: :finest_resolution, value: value}) when not is_nil(value) do
    "Cannot convert #{inspect(value)} at its finest resolution to an " <>
      "explicit interval — no finer unit exists to bound the span."
  end

  def message(%__MODULE__{reason: :finest_resolution}) do
    "Cannot convert a Tempo at its finest resolution to an explicit interval."
  end

  def message(%__MODULE__{reason: :unanchored_group, value: value}) when not is_nil(value) do
    "Cannot convert the group #{inspect(value)} to an interval — its unit " <>
      "needs coarser calendar context (year/month) to bound the span, which an " <>
      "unanchored or ordinal-day group does not supply."
  end

  def message(%__MODULE__{reason: :unanchored_group}) do
    "Cannot convert an unanchored group to an interval — no coarser " <>
      "calendar context to bound the span."
  end

  def message(%__MODULE__{reason: :open_range, value: value}) when not is_nil(value) do
    "Cannot convert the open-ended range #{inspect(value)} to an interval — " <>
      "one endpoint is unbounded, so it spans no finite set of occurrences."
  end

  def message(%__MODULE__{reason: :open_range}) do
    "Cannot convert an open-ended range to an interval — one endpoint is unbounded."
  end

  def message(%__MODULE__{value: value, target: target})
      when not is_nil(value) and not is_nil(target) do
    "Cannot convert #{inspect(value)} to #{describe_target(target)}"
  end

  def message(%__MODULE__{target: target}) when not is_nil(target) do
    "Invalid #{describe_target(target)}"
  end

  def message(%__MODULE__{}), do: "Conversion failed"

  defp describe_target(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp describe_target(other), do: inspect(other)
end
