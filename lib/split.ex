defmodule Tempo.Split do
  @moduledoc false

  # A value's units as those of its date and those of its time of day.
  #
  # A value's units run from the coarsest to the finest, so its time of day
  # is its first unit of the clock (an hour, a minute, a second) and every
  # unit after it, and its date is every unit before, in whichever units the
  # date is written: a year and a month, a week and a day of it, a day of
  # the year, a weekday alone, a unit that holds a group of a set.
  #
  # The shapes of a date were listed one by one, and a date in a shape that
  # was not listed was given as the time of day: `3K`, a Wednesday, had no
  # date, and the months of `2026Y{1,2}G3MU` were its time of day.
  #
  # A selection is of the date where it names a unit of one, a day, a
  # weekday, a month or a window from one: the Mondays of `2026Y6ML1KN` are
  # days of June, and the value has no time of day (decided 2026-10-07; the
  # selection was given as the time of day). One that names units of the
  # clock alone (`2018Y9MTLT8H20M3IN`, the third 08:20) is the time of day.

  @clock_units [:hour, :minute, :second, :microsecond]

  # A position among what a selection picks is of no unit of its own.
  @positions [:instance]

  @spec split(list()) :: {date :: list(), time_of_day :: list()}
  def split(time) when is_list(time), do: Enum.split_while(time, &of_the_date?/1)

  defp of_the_date?({:selection, parts}) when is_list(parts), do: not of_the_clock?(parts)
  defp of_the_date?(entry) when is_tuple(entry), do: elem(entry, 0) not in @clock_units
  defp of_the_date?(_entry), do: false

  defp of_the_clock?(parts) do
    units = for part <- parts, is_tuple(part), elem(part, 0) not in @positions, do: elem(part, 0)
    units != [] and Enum.all?(units, &(&1 in @clock_units))
  end
end
