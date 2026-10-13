defmodule Tempo.InvalidDateError do
  @moduledoc """
  A value no date or time has: a unit outside the values its calendar gives
  it, a day a month lacks, a reading the clock skips.

  * `:value` is the value, as written or as built.

  * `:unit` is the unit at fault, where one is.

  * `:reason` says why: `:out_of_range`, `:no_such_date`, `:skipped_by_the_clock`,
    `:needs_a_year`, or a short description.

  """

  defexception [:value, :unit, :reason]

  @type t :: %__MODULE__{value: term(), unit: atom() | nil, reason: term()}

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{value: value, unit: nil, reason: reason}) do
    "#{inspect(value)} is no date or time: #{describe(reason)}"
  end

  def message(%__MODULE__{value: value, unit: unit, reason: reason}) do
    "#{inspect(value)} is no date or time: its #{unit} is #{describe(reason)}"
  end

  defp describe(:out_of_range), do: "outside the values its calendar gives it"

  defp describe({:out_of_range, value, low..high//_}),
    do: "#{value}, outside the #{low} to #{high} its calendar gives it"

  defp describe(:no_such_date), do: "a date the calendar does not have"

  defp describe({:no_such_date, day}),
    do: "#{day}, a day the calendar does not have in that month"

  defp describe({:week_start_not_monday, day}),
    do: "#{day}, where a week of a selection begins on Monday (1)"

  defp describe({:unknown_event, name}),
    do: "#{inspect(name)}, a name no event Tempo knows has (see Tempo.Event.known/0)"

  defp describe(:skipped_by_the_clock), do: "a reading the zone's clock skips"
  defp describe(:needs_a_year), do: "a value that cannot be told without a year"
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
