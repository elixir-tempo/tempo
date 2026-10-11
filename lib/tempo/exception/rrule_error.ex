defmodule Tempo.RRuleError do
  @moduledoc """
  Exception raised when an RFC 5545 RRULE cannot be parsed,
  validated, or encoded. Reasons include a missing `FREQ`,
  mutually exclusive `UNTIL`/`COUNT`, and invalid BY-rule
  combinations.

  """

  alias Tempo.Calendars

  defexception [:reason, :rule, :detail]

  @type t :: %__MODULE__{
          reason: atom() | String.t() | nil,
          rule: any() | nil,
          detail: String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Calendars.outside(struct!(__MODULE__, bindings))
  end

  @impl true
  def message(%__MODULE__{reason: :missing_freq}) do
    "RRULE is missing the required FREQ component"
  end

  def message(%__MODULE__{reason: :until_and_count}) do
    "RRULE may not specify both UNTIL and COUNT"
  end

  def message(%__MODULE__{reason: reason, detail: detail})
      when is_binary(reason) and is_binary(detail) do
    "#{reason} — #{detail}"
  end

  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{reason: reason}) when is_atom(reason) and not is_nil(reason) do
    "RRULE error: #{reason}"
  end

  def message(%__MODULE__{}), do: "RRULE error"
end
