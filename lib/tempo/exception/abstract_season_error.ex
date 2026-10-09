defmodule Tempo.AbstractSeasonError do
  @moduledoc """
  Exception returned when an operation needs the dates of a season that
  has no hemisphere, or is given a territory that has no one hemisphere.

  ISO 8601-2 numbers four seasons "independent of location": 21 is
  spring, 22 summer, 23 autumn and 24 winter, wherever they are read.
  Spring is March to May north of the equator and September to November
  south of it, so `~o"2026-21"` names a season and no dates until it is
  given a hemisphere. `Tempo.in_territory/2` gives it one, and so do
  `Tempo.to_interval/2` and what is built on it (the comparisons, the
  relations, the set operations), by a `:territory` or `:locale` option
  or by the application's default territory and the current locale.
  Anything else that needs its dates returns or raises this error: a
  walk, a step of anything but years, a time of day placed on it, a finer
  unit or a rounding.

  A territory the equator runs through, such as Brazil or Indonesia, and
  a region that holds territories on both sides of it, have no one
  hemisphere, and a season given one of them has no dates either. The
  season of a hemisphere is written with its own number: 25 to 28 are the
  northern seasons and 29 to 32 the southern.

  """

  defexception [:value, :operation, :territory]

  @type t :: %__MODULE__{
          value: term(),
          operation: String.t() | nil,
          territory: atom() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{territory: territory, value: value}) when not is_nil(territory) do
    "The season in #{inspect(value)} has no one span of dates in #{inspect(territory)}, which " <>
      "lies on both sides of the equator. Write the season of a hemisphere (25 to 28 are the " <>
      "northern seasons, 29 to 32 the southern), or give a territory on one side of the equator."
  end

  def message(%__MODULE__{operation: operation, value: value}) when not is_nil(operation) do
    "Cannot #{operation} #{inspect(value)}: a season of 21 to 24 is " <>
      "spring, summer, autumn or winter wherever it is read, and has no dates until it is " <>
      how_it_is_given_one()
  end

  def message(%__MODULE__{value: value}) do
    "#{inspect(value)} holds a season of 21 to 24, which has no dates until it is " <>
      how_it_is_given_one()
  end

  defp how_it_is_given_one do
    "given a hemisphere. Give it a territory or a locale with `Tempo.in_territory/2`, or " <>
      "convert it with `Tempo.to_interval/2`, which takes `:territory` and `:locale`."
  end
end
