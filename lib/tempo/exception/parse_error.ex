defmodule Tempo.ParseError do
  @moduledoc """
  Text that is not an ISO 8601 expression Tempo reads.

  * `:text` is the text given.

  * `:rest` is the text from the place the reader stopped, which names the
    position.

  * `:reason` says what was expected or refused there.

  """

  defexception [:text, :rest, :reason]

  @type t :: %__MODULE__{text: String.t(), rest: String.t() | nil, reason: term()}

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{text: text, rest: rest, reason: reason}) do
    where = if is_binary(rest) and rest != "", do: " at #{inspect(rest)}", else: ""
    "Cannot read #{inspect(text)} as ISO 8601#{where}: #{describe(reason)}"
  end

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
