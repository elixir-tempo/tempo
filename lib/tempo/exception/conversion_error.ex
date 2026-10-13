defmodule Tempo.ConversionError do
  @moduledoc """
  An expression that cannot be given the spans asked of it, with the
  reason: a duration has no place on the time line, a one-of set has
  readings and no spans, a value with no year needs one, a sequence with
  no end needs a `:within` window, or more values were asked for at once
  than `Tempo.Limit.values/0` allows.

  """

  defexception [:value, :reason]

  @type reason ::
          :bare_duration
          | :one_of
          | :needs_a_year
          | :unbounded
          | :open
          | :too_many_values
          | :season
          | :selection
          | :exclusion
          | :repeat_rule
          | :no_such_value
          | :group
          | :several
          | :conditions
          | term()

  @type t :: %__MODULE__{value: term(), reason: reason()}

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{value: value, reason: reason}) do
    "#{inspect(value)} #{describe(reason)}"
  end

  defp describe(:bare_duration), do: "is a duration, which has no place on the time line"
  defp describe(:one_of), do: "is one of several values, which has readings and no spans"

  defp describe(:needs_a_year),
    do: "has no year, and cannot be placed without one or a :within window"

  defp describe(:unbounded), do: "has no end; give a :within window to bound it"
  defp describe(:open), do: "has an open start, which no walk can begin from"

  defp describe(:too_many_values),
    do: "names more values than Tempo.Limit.values/0 allows at once"

  defp describe(:season), do: "is a season, whose dates no calendar Tempo asks yet gives"

  defp describe(:selection),
    do: "holds a selection, which is read in a later phase of the redesign"

  defp describe(:exclusion),
    do: "holds an exclusion, which is read in a later phase of the redesign"

  defp describe(:repeat_rule),
    do: "has a repeat rule, which is read in a later phase of the redesign"

  defp describe(:no_such_value), do: "names a value its calendar has no room for"
  defp describe(:group), do: "holds a group, which names a span of values and none to count from"
  defp describe(:several), do: "names several spans, where one is asked for"

  defp describe(:conditions),
    do: "has conditions, which are read in a later phase of the redesign"

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
