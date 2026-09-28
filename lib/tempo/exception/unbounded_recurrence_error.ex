defmodule Tempo.UnboundedRecurrenceError do
  @moduledoc """
  Exception raised when a caller attempts to materialise an
  unbounded recurrence (`recurrence: :infinity` with no `UNTIL`
  and no `:within` option) into a concrete `IntervalSet`.

  Supply a `:within` window — the Tempo value whose occurrences
  you want — or convert the rule to a finite count before
  materialising.

  """

  defexception [:interval, :reason]

  @type t :: %__MODULE__{
          interval: Tempo.Interval.t() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{}) do
    "Cannot materialise an unbounded recurrence (recurrence: :infinity, no UNTIL). " <>
      "Supply a :within option — the window whose occurrences you want."
  end
end
