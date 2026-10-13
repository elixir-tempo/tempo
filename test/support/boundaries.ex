defmodule Tempo.Boundaries do
  @moduledoc """
  The two boundaries of a span, for tests that hold a span to a standard
  which states them: iCalendar's `DTEND` is "the non-inclusive end" of an
  event (RFC 5545 section 3.6.1), where Tempo writes an end to a date as
  the date it runs through.

  `from/1` is the units of where a span starts, and `to/1` the units of
  where what follows it starts.
  """

  alias Tempo.Interval

  @doc "The units of a span's start."
  @spec from(Tempo.t()) :: keyword()
  def from(span), do: span |> Interval.from() |> units()

  @doc "The units of the boundary a span ends at: the start of what follows it."
  @spec to(Tempo.t()) :: keyword()
  def to(span) do
    to = Interval.to(span)
    to |> following(Tempo.resolution(to)) |> units()
  end

  defp following(to, unit) when unit in [:hour, :minute, :second], do: to

  defp following(to, unit) when unit in [:year, :month, :week, :day],
    do: Tempo.shift!(to, [{unit, 1}])

  defp following(to, _day_label), do: Tempo.shift!(to, day: 1)

  defp units(%Tempo{form: {:value, units}}), do: units
end
