defmodule Tempo.UnboundedRecurrenceError do
  @moduledoc """
  Exception returned when a caller asks for the occurrences of an
  unbounded recurrence (`recurrence: :infinity` with no `UNTIL`)
  with no `:within` window: they never end.

  Supply a `:within` window — the Tempo value whose occurrences you
  want — or give the rule a count or an end.

  It is also returned for a recurrence that has an end and does not
  come to it in the 10,000 periods a walk takes, or has more than
  10,000 occurrences before it: `:reason` says which, and a narrower
  `:within` window is the remedy there too.

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
    "Cannot list the occurrences of an unbounded recurrence (recurrence: :infinity, no UNTIL). " <>
      "Supply a :within option — the window whose occurrences you want."
  end
end
