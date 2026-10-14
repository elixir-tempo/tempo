defmodule TempoTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  doctest Tempo
  doctest Tempo.Duration
  doctest Tempo.Interval
  doctest Tempo.IntervalSet
  doctest Tempo.Event
  doctest Tempo.RRule
  doctest Tempo.Cron
  doctest Tempo.ICal
  doctest Tempo.JSCalendar
  doctest Tempo.RecurrenceSet
  doctest Tempo.Explain
  doctest Tempo.Clock
  doctest Tempo.Workdays
  doctest Tempo.Territory
  doctest Tempo.Sigils
  doctest Tempo.Allen
  doctest Tempo.Builder
  doctest Tempo.LeapSeconds
  doctest Tempo.Unit
  doctest Tempo.Calendar
end
