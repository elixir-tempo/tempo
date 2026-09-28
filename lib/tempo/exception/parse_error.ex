defmodule Tempo.ParseError do
  @moduledoc """
  Exception returned when a string cannot be parsed: it is not ISO
  8601 or IXDTF, or — from a typed parser such as
  `Tempo.parse_date/2` — it is not a value of the kind asked for.

  Carries the raw input, a short reason atom or phrase identifying
  the parse failure, and the byte offset into `input` at which the
  parser stopped (when available).

  """

  defexception [:input, :reason, :offset]

  @type t :: %__MODULE__{
          input: String.t() | nil,
          reason: atom() | String.t() | nil,
          offset: non_neg_integer() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  def exception(message) when is_binary(message) do
    %__MODULE__{reason: message}
  end

  @impl true
  def message(%__MODULE__{reason: "Could not parse " <> _rest = reason}), do: reason

  def message(%__MODULE__{input: nil, reason: reason}) when is_binary(reason) do
    reason
  end

  def message(%__MODULE__{input: input, reason: reason, offset: offset})
      when is_binary(input) and is_integer(offset) do
    "Could not parse #{inspect(input)} at offset #{offset}: #{format_reason(reason)}"
  end

  def message(%__MODULE__{input: input, reason: reason}) when is_binary(input) do
    "Could not parse #{inspect(input)}: #{format_reason(reason)}"
  end

  def message(%__MODULE__{reason: reason}) do
    format_reason(reason)
  end

  defp format_reason(nil), do: "parse failed"
  defp format_reason(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp format_reason(string) when is_binary(string), do: string
end
