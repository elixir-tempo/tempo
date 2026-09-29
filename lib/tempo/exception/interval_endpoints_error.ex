defmodule Tempo.IntervalEndpointsError do
  @moduledoc """
  Exception returned when an operation needs an interval whose
  endpoints are both concrete `%Tempo{}` values and is given one with
  an open or missing end, or a recurrence with no start.

  Convert a recurrence or a duration-only interval to its occurrences
  with `Tempo.to_interval/2` first, giving an open-ended one a
  `:within` window.

  """

  defexception [:operation, :interval, :reason]

  @type t :: %__MODULE__{
          operation: atom() | String.t() | nil,
          interval: Tempo.Interval.t() | nil,
          reason: atom() | String.t() | nil
        }

  @convert "Convert a recurrence or a duration-only interval to its occurrences with " <>
             "`Tempo.to_interval/2` first, giving an open-ended one a `:within` window."

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{operation: :select, reason: :open_start}) do
    "`Tempo.select/2` selects forward from a span's start, and a span with an open " <>
      "start has none. Give the span a start."
  end

  def message(%__MODULE__{reason: :open_start}) do
    "A recurrence with an open start has no first occurrence to count from. " <>
      "Give `Tempo.to_interval/2` a `:within` window, or give the rule a start."
  end

  def message(%__MODULE__{reason: :empty_selection}) do
    "A recurrence of one occurrence whose selection picks no date has no span."
  end

  def message(%__MODULE__{operation: op}) when is_binary(op) do
    "Cannot #{op}: it needs an interval whose endpoints are both concrete. " <> @convert
  end

  def message(%__MODULE__{operation: op}) when is_atom(op) and not is_nil(op) do
    "`#{op}` needs an interval whose endpoints are both concrete. " <> @convert
  end

  def message(%__MODULE__{}) do
    "This needs an interval whose endpoints are both concrete. " <> @convert
  end
end
