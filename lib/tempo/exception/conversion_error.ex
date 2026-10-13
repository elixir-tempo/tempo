defmodule Tempo.ConversionError do
  @moduledoc """
  An expression that cannot be given the spans asked of it, with the
  reason: a duration has no place on the time line, a one-of set has
  readings and no spans, a value with no year needs one, a sequence with
  no end needs a `:within` window, or more values were asked for at once
  than the application's `:max_values_at_once` allows (10,000 unless it is set).

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
          | {:no_hemisphere, atom()}
          | {:season_moved, Tempo.Duration.t()}
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

  defp describe(:open),
    do: "has an open end, which has no place to walk from, relate or combine; give it both ends"

  defp describe(:too_many_values),
    do: "names more values than :max_values_at_once allows at once"

  defp describe(:season),
    do:
      "is a season with no dates here: a season of 21 to 24 has them in a territory on one side of the equator (Tempo.in_territory/2), and none is walked or has dates in a calendar that is not the Gregorian"

  defp describe({:season_moved, by}),
    do:
      "is a season, which is moved by whole years and not by #{inspect(by)}: give it its months first (Tempo.in_territory/2), or move its interval (Tempo.to_interval/2)"

  defp describe({:no_hemisphere, territory}),
    do:
      "is a season, and #{inspect(territory)} is on no one side of the equator: give a territory that is, or write the season of a hemisphere (25 to 32)"

  defp describe(:selection),
    do:
      "holds a selection, which names several values; list them with Tempo.to_interval/2 and ask of each"

  defp describe(:exclusion), do: "holds an exclusion, which this operation does not apply"
  defp describe(:repeat_rule), do: "has a repeat rule, which this operation does not apply"

  defp describe(:no_such_value), do: "names a value its calendar has no room for"
  defp describe(:group), do: "holds a group, which names a span of values and none to count from"
  defp describe(:several), do: "names several spans, where one is asked for"

  defp describe(:conditions),
    do:
      "has conditions on its members, which this operation does not apply; list its members with Tempo.to_interval/2 first"

  defp describe({:no_rrule, :not_a_recurrence}), do: "is no recurrence, and has no RRULE"

  defp describe({:no_rrule, {:cadence, cadence}}),
    do: "steps by #{inspect(cadence)}, which RFC 5545 has no FREQ for"

  defp describe({:no_rrule, {:part, part}}),
    do: "selects by #{inspect(part)}, which RFC 5545 has no BY part for"

  defp describe({:no_rrule, {:part_at, part, frequency}}),
    do:
      "selects by #{inspect(part)} in a rule that steps by the #{frequency}, which RFC 5545 does not allow"

  defp describe({:no_rrule, {:calendar, calendar}}),
    do:
      "counts in #{inspect(calendar)}, where RFC 5545 would read its months and years as Gregorian"

  defp describe({:no_rrule, :domain}),
    do: "recurs in the periods of a domain, which RFC 5545 has no part for"

  defp describe({:no_rrule, :month_end}),
    do:
      "steps to the last day of a month that lacks its start's day, where RFC 5545 would pass the month over"

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
