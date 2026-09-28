defmodule Tempo.FloatingTempoError do
  @moduledoc """
  Exception returned when an operation needs a zone or an offset and
  is given a floating `Tempo` value — no `[IANA/Zone]` tag, no `Z`,
  no numeric offset. A comparison between a floating value and a
  zoned one raises it.

  Floating values are deliberate (see the scheduling guide) but
  cannot be projected to UTC, so any operation that needs a
  universal instant rejects them. `Tempo.in_zone/2` places a
  floating value in a zone. The opposite error, for an operation
  that needs a floating value and is given a zoned one, is
  `Tempo.ZonedTempoError`.

  """

  defexception [:operation, :value]

  @type t :: %__MODULE__{
          operation: atom() | String.t() | nil,
          value: Tempo.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{operation: op}) when not is_nil(op) do
    "Cannot #{describe_operation(op)} on a floating Tempo (no zone or offset information). " <>
      "Place it in a zone with `Tempo.in_zone/2`, or write a zone (`[Europe/Paris]`) " <>
      "or an offset (`Z` or `+HH:MM`), first."
  end

  def message(%__MODULE__{}) do
    "Operation requires a zoned Tempo (floating values have no UTC projection)"
  end

  defp describe_operation(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp describe_operation(string) when is_binary(string), do: string
end
