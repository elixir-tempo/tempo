defmodule Tempo.ResolutionError do
  @moduledoc """
  Exception raised when a resolution operation cannot be performed
  — truncating to a finer unit than the current resolution,
  extending to a coarser unit, or following a unit-successor chain
  that terminates before the target under a particular calendar.

  """

  alias Tempo.Calendars

  defexception [:current, :target, :operation, :calendar, :reason]

  @type t :: %__MODULE__{
          current: atom() | nil,
          target: atom() | nil,
          operation: atom() | nil,
          calendar: module() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Calendars.outside(struct!(__MODULE__, bindings))
  end

  @impl true
  def message(%__MODULE__{operation: :trunc, reason: :empty_resolution}) do
    "Truncation would result in no time resolution"
  end

  def message(%__MODULE__{operation: :extend, current: current, target: target})
      when not is_nil(current) and not is_nil(target) do
    "Target resolution #{Calendars.inspect(target)} is coarser than the current " <>
      "resolution #{Calendars.inspect(current)}. Use `Tempo.trunc/2` to reduce resolution."
  end

  def message(%__MODULE__{reason: :no_path, current: current, target: target, calendar: cal})
      when not is_nil(current) and not is_nil(target) do
    "No path from #{Calendars.inspect(current)} to #{Calendars.inspect(target)} under " <>
      "calendar #{Calendars.name(cal)} — no finer unit is defined."
  end

  def message(%__MODULE__{reason: reason}) when is_binary(reason) do
    reason
  end

  def message(%__MODULE__{operation: op, current: current, target: target})
      when not is_nil(op) and not is_nil(current) and not is_nil(target) do
    "#{op} from #{Calendars.inspect(current)} to #{Calendars.inspect(target)} is not valid"
  end

  def message(%__MODULE__{}) do
    "Resolution operation failed"
  end
end
