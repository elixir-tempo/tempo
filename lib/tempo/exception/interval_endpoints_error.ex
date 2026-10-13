defmodule Tempo.IntervalEndpointsError do
  @moduledoc """
  An interval whose ends do not make a span.

  * `:reason` is `:order` for an end before its start, `:calendars` for two
    ends in two calendars, `:zones` for two ends in two zones, `:open` for an
    end that is not there, `:duration` for two durations, or a description.

  """

  defexception [:from, :to, :reason]

  @type t :: %__MODULE__{from: term(), to: term(), reason: term()}

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{from: from, to: to, reason: reason}) do
    "The interval from #{inspect(from)} to #{inspect(to)} #{describe(reason)}"
  end

  defp describe(:order), do: "ends before it starts"

  defp describe(:calendars),
    do:
      "has its ends in two calendars; an interval is in one calendar, so convert one end with Tempo.to_calendar/2"

  defp describe(:zones),
    do:
      "has its ends in two zones; an interval is in one zone, so convert one end with Tempo.shift_zone/2"

  defp describe(:open), do: "has no end to measure from"
  defp describe(:duration), do: "has a duration at both ends"
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
