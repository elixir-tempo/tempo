defmodule Tempo.FrameError do
  @moduledoc """
  Two expressions that share no frame to be related or combined on (law 4):
  one with a zone or a shift and one with neither, one with a year and one
  without and no `:within` window to place it by, or two with no year on
  different cycles. Or one expression in the wrong frame for what was asked
  of it: a zoned one to be placed in a zone, a floating one to be moved to
  another.

  """

  defexception [:a, :b, :reason]

  @type reason ::
          :floating_and_zoned | :needs_a_year | :cycles | :open | :several | :zoned | :floating
  @type t :: %__MODULE__{a: term(), b: term(), reason: reason()}

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{a: a, reason: :zoned}),
    do: "#{inspect(a)} is in a zone already; Tempo.shift_zone/2 moves it to another"

  def message(%__MODULE__{a: a, reason: :floating}),
    do: "#{inspect(a)} has no zone to be moved from; Tempo.in_zone/2 places it in one"

  def message(%__MODULE__{a: a, b: b, reason: reason}) do
    "#{inspect(a)} and #{inspect(b)} #{describe(reason)}"
  end

  defp describe(:floating_and_zoned),
    do:
      "share no frame: one has a zone or a shift and the other neither; place the floating one with Tempo.in_zone/2"

  defp describe(:needs_a_year),
    do:
      "share no frame: one has a year and the other none; give a :within window, or place the one with no year with Tempo.at/2"

  defp describe(:cycles), do: "share no frame: they recur on different cycles"
  defp describe(:open), do: "cannot be related: an open end has no position"

  defp describe(:several),
    do:
      "cannot be related: a plural expression has several spans; use the set operations or Tempo.IntervalSet.relation_matrix/2"

  defp describe(reason), do: inspect(reason)
end
