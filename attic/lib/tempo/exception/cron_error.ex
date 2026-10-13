defmodule Tempo.CronError do
  @moduledoc """
  Exception raised when a cron expression cannot be parsed or
  when one of its fields is outside the valid range for that
  cron field.

  """

  alias Tempo.Calendars

  defexception [:input, :field, :value, :reason]

  @type t :: %__MODULE__{
          input: String.t() | nil,
          field: atom() | nil,
          value: String.t() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Calendars.outside(struct!(__MODULE__, bindings))
  end

  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason) do
    reason
  end

  def message(%__MODULE__{field: field, value: value}) when not is_nil(field) do
    "Invalid cron #{field} field: #{Calendars.inspect(value)}"
  end

  def message(%__MODULE__{input: input}) when is_binary(input) do
    "Could not parse cron expression #{Calendars.inspect(input)}"
  end

  def message(%__MODULE__{}) do
    "Invalid cron expression"
  end
end
