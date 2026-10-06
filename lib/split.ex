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
  # A selection ends the date as a unit of the clock does, which is what it
  # did: the Mondays of `2026Y6ML1KN` are what `Tempo.at/2` places on June.

  @after_the_date [:hour, :minute, :second, :microsecond, :selection]

  @spec split(list()) :: {date :: list(), time_of_day :: list()}
  def split(time) when is_list(time), do: Enum.split_while(time, &of_the_date?/1)

  defp of_the_date?(entry) when is_tuple(entry), do: elem(entry, 0) not in @after_the_date
  defp of_the_date?(_entry), do: false
end
