defmodule Tempo.Iso8601EncodeError do
  @moduledoc """
  A value ISO 8601 has no text for: a struct built by hand with parts in two
  calendars or two zones, or a construct the notation does not write.

  """

  defexception [:value, :reason]

  @type t :: %__MODULE__{value: term(), reason: term()}

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{value: value, reason: reason}),
    do: "#{inspect(value)} cannot be written as ISO 8601: #{inspect(reason)}"
end
