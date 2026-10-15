defmodule Tempo.InvalidDateError do
  @moduledoc """
  A value no date or time has: a unit outside the values its calendar gives
  it, a day a month lacks, a reading the clock skips.

  * `:value` is the value, as written or as built, or the units it was
    built from where one of them is no unit's value (`hour: "09"`).

  * `:unit` is the unit at fault, where one is.

  * `:reason` says why: `:out_of_range`, `:no_such_date`, `:skipped_by_the_clock`,
    `:needs_a_year`, `{:not_a_unit_value, held}`, `{:annotated, held}`, or a
    short description.

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

  defp describe({:no_such_month, {month, :leap}, year}),
    do: "the leap month after month #{month}, which the year #{year} does not have"

  defp describe({:no_such_month, month, year}),
    do: "#{month}, a month the year #{year} does not have"

  defp describe({:unknown_event, name}),
    do: "#{inspect(name)}, a name no event Tempo knows has (see Tempo.Event.known/0)"

  defp describe({:no_instant, name}),
    do: "#{inspect(name)}, an event that is a day and no instant, so has no date in a zone"

  defp describe({:no_solar_terms, calendar}),
    do: "a solar term, which #{inspect(calendar)} does not reckon"

  defp describe(:year_out_of_range), do: "in a year the astronomy does not reach"

  defp describe({:uncomputable_event, event}),
    do: "#{inspect(event)}, whose date the calendar cannot give that year"

  defp describe({:not_a_date, given}),
    do: "#{inspect(given)}, which its resolver answered where a date belongs"

  defp describe({:not_a_unit_value, held}),
    do: "#{inspect(held)}, where a unit holds an integer, a list or a range of them"

  defp describe({:annotated, held}),
    do:
      "#{inspect(held)}, where an exponent, significant digits or a margin is written on a year alone"

  defp describe(:skipped_by_the_clock), do: "a reading the zone's clock skips"
  defp describe(:needs_a_year), do: "a value that cannot be told without a year"
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
