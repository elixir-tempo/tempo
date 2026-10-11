defmodule Tempo.InvalidTimeError do
  @moduledoc """
  Exception raised when time-of-day components do not form a valid
  time.

  """

  alias Tempo.Border

  defexception [:unit, :value, :valid_range, :hour, :minute, :second, :reason]

  @type t :: %__MODULE__{
          unit: atom() | nil,
          value: integer() | nil,
          valid_range: Range.t() | nil,
          hour: integer() | nil,
          minute: integer() | nil,
          second: integer() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Border.leave(struct!(__MODULE__, bindings))
  end

  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{unit: unit, value: value, valid_range: range})
      when not is_nil(unit) and not is_nil(value) and not is_nil(range) do
    "#{Border.inspect(value)} is not valid for #{unit} (valid range #{Border.inspect(range)})"
  end

  def message(%__MODULE__{unit: unit, value: value}) when not is_nil(unit) do
    "Invalid #{unit}: #{Border.inspect(value)}"
  end

  def message(%__MODULE__{}), do: "Invalid time"
end
