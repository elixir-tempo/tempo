defmodule Tempo.UnanchoredError do
  @moduledoc """
  Exception returned when an operation needs a value with a year — one
  anchored on the time line — and is given one without.

  A value with no year is unanchored: `~o"T17"` is five in the
  afternoon of no particular day, and `~o"1M31D"` is 31 January of no
  particular year. Some operations answer for such a value — `~o"1M31D"`
  shifted by a day is `~o"2M1D"` in every year — but one whose answer
  depends on the missing year (the same day shifted by a month lands in
  February), or that needs a place on the time line (a duration, a zone,
  a comparison with a dated value), returns this error. Place the value
  on a date first with `Tempo.at/2` or `Tempo.on/2`.

  ### Fields

  * `:operation` names what was asked — a function (`:duration`) or a
    phrase (`"use a value as the :within window"`) — or is `nil`.

  * `:value` is the unanchored value, when there is one to name.

  * `:duration` is the duration a shift could not apply without a year.

  * `:reason` is an atom naming the case, for matching on.

  """

  defexception [:operation, :value, :duration, :reason]

  @type t :: %__MODULE__{
          operation: atom() | String.t() | nil,
          value: term(),
          duration: Tempo.Duration.t() | nil,
          reason: atom() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{value: value, duration: %Tempo.Duration{} = duration})
      when not is_nil(value) do
    "Cannot shift #{inspect(value)} by #{inspect(duration)}: the answer depends on " <>
      "the year, and the value has none. " <> placement(value)
  end

  def message(%__MODULE__{operation: operation, value: value}) when is_binary(operation) do
    "Cannot #{operation}#{without_year(value)}. " <> placement(value)
  end

  def message(%__MODULE__{operation: operation, value: value})
      when is_atom(operation) and not is_nil(operation) do
    "`#{operation}` needs a value with a year#{named(value)}. " <> placement(value)
  end

  def message(%__MODULE__{value: value}) do
    "This needs a value with a year#{named(value)}. " <> placement(value)
  end

  defp named(nil), do: ""
  defp named(value), do: ": #{inspect(value)} has none"

  defp without_year(nil), do: ""
  defp without_year(value), do: ": #{inspect(value)} has no year"

  defp placement(nil),
    do: "Place a value without a year on a date first with `Tempo.at/2` or `Tempo.on/2`."

  defp placement(_value),
    do: "Place the value on a date first with `Tempo.at/2` or `Tempo.on/2`."
end
