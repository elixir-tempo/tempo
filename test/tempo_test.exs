defmodule TempoTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  doctest Tempo
  doctest Tempo.Duration
  doctest Tempo.Interval
  doctest Tempo.IntervalSet
  doctest Tempo.Sigils
  doctest Tempo.Unit
  doctest Tempo.Calendar
end
