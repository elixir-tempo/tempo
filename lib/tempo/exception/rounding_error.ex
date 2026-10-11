defmodule Tempo.RoundingError do
  @moduledoc """
  Exception raised when a rounding operation cannot be performed
  — typically because the target unit is not reachable from the
  value's current resolution under the active calendar.

  """

  alias Tempo.Calendars

  defexception [:unit, :value, :reason]

  @type t :: %__MODULE__{
          unit: atom() | nil,
          value: Tempo.t() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Calendars.outside(struct!(__MODULE__, bindings))
  end

  def exception(message) when is_binary(message) do
    %__MODULE__{reason: message}
  end

  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason) do
    reason
  end

  def message(%__MODULE__{unit: unit}) when not is_nil(unit) do
    "Cannot round to #{Calendars.inspect(unit)}"
  end

  def message(%__MODULE__{}) do
    "Rounding operation failed"
  end
end
