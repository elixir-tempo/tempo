defmodule Tempo.ZonedTempoError do
  @moduledoc """
  Exception returned when an operation needs a floating `Tempo` value
  and is given a zoned one — a value that already carries an
  `[IANA/Zone]` tag, a `Z`, or a numeric offset.

  `Tempo.in_zone/2` places a floating value in a zone. A value that is
  already zoned is moved to another zone with `Tempo.shift_zone/2`,
  which recomputes the wall clock to keep the instant. The opposite
  error, for an operation that needs a zone and is given a floating
  value, is `Tempo.FloatingTempoError`.

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
  def message(%__MODULE__{operation: :in_zone, value: %Tempo{} = value}) do
    "Cannot place #{inspect(value)} in a zone: it already has a zone or an offset. " <>
      "Use `Tempo.shift_zone/2` to move it to another zone."
  end

  def message(%__MODULE__{operation: op}) when not is_nil(op) do
    "Cannot #{describe_operation(op)} on a zoned Tempo (it already carries a " <>
      "zone or offset). Use `Tempo.shift_zone/2` to move it to another zone instead."
  end

  def message(%__MODULE__{}) do
    "Operation requires a floating Tempo (this value already carries a zone or offset)"
  end

  defp describe_operation(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp describe_operation(string) when is_binary(string), do: string
end
