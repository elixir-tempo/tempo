defmodule Tempo.MaterialisationError do
  @moduledoc """
  Exception raised when a value cannot be materialised into an
  explicit `Tempo.Interval` or `Tempo.IntervalSet`.

  Reasons include a bare `Tempo.Duration` (no time-line anchor),
  a one-of `Tempo.Set` (epistemic disjunction, not an interval
  list), a `Tempo` already at its finest resolution (no finer unit
  to bound the implicit span), and an unanchored group (e.g.
  `5G10DU` — days 41..50 with no year/month to bound the span).

  """

  defexception [:value, :reason]

  @type reason ::
          :bare_duration
          | :one_of_set
          | :finest_resolution
          | :unanchored_group
          | :open_range
          | atom()
          | String.t()

  @type t :: %__MODULE__{
          value: any() | nil,
          reason: reason() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :bare_duration}) do
    "Cannot materialise a Tempo.Duration into an interval — a duration has no " <>
      "anchor on the time line."
  end

  def message(%__MODULE__{reason: :one_of_set}) do
    "Cannot materialise a one-of Tempo.Set into an interval — epistemic " <>
      "disjunction is not an interval list. Pick one member, handle the " <>
      "disjunction explicitly, or ask a certainty question " <>
      "(`Tempo.relation_certainty/3`, `Tempo.possibly_before?/2`, …)."
  end

  def message(%__MODULE__{reason: :recurring_interval}) do
    "A recurring interval is a rule generating occurrences, not a single span. " <>
      "Materialise it with `Tempo.to_interval/2` (pass `:bound` for an unbounded " <>
      "recurrence) and use the set-level API (`Tempo.overlaps?/2`, " <>
      "`Tempo.IntervalSet.relation_matrix/2`)."
  end

  def message(%__MODULE__{reason: :recurring_duration}) do
    "The duration of a finite recurring interval is the total across its " <>
      "occurrences — materialise with `Tempo.to_interval/1` and use " <>
      "`Tempo.IntervalSet.duration/1`."
  end

  def message(%__MODULE__{reason: :finest_resolution, value: value}) when not is_nil(value) do
    "Cannot materialise #{inspect(value)} at its finest resolution into an " <>
      "explicit interval — no finer unit exists to bound the span."
  end

  def message(%__MODULE__{reason: :finest_resolution}) do
    "Cannot materialise a Tempo at its finest resolution into an explicit interval"
  end

  def message(%__MODULE__{reason: :unanchored_group, value: value}) when not is_nil(value) do
    "Cannot materialise the group #{inspect(value)} into an interval — its unit " <>
      "needs coarser calendar context (year/month) to bound the span, which a " <>
      "non-anchored or ordinal-day group does not supply."
  end

  def message(%__MODULE__{reason: :unanchored_group}) do
    "Cannot materialise an unanchored group into an interval — no coarser " <>
      "calendar context to bound the span."
  end

  def message(%__MODULE__{reason: :open_range, value: value}) when not is_nil(value) do
    "Cannot materialise the open-ended range #{inspect(value)} into an interval — " <>
      "one endpoint is unbounded, so it spans no finite set of occurrences."
  end

  def message(%__MODULE__{reason: :open_range}) do
    "Cannot materialise an open-ended range into an interval — one endpoint is unbounded."
  end

  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{}), do: "Cannot materialise value into an interval"
end
