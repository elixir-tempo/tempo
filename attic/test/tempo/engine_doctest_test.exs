defmodule Tempo.EngineDocTest do
  @moduledoc """
  The examples in the documentation of the engine's modules.

  The engine is no part of the public API: its modules are hidden, and a
  public function gives them values as Tempo holds them inside a call, with
  the calendar of a value that names none replaced (`Tempo.Calendars`). Their
  examples are written with the sigil as every example is, so they are run
  here with `Tempo.Test.Inside`'s, which writes a value as it is held
  inside.

  """

  use ExUnit.Case, async: true

  import Tempo.Test.Inside

  doctest Tempo.Compare
  doctest Tempo.Inspect
  doctest Tempo.Interval.Cycle
  doctest Tempo.Interval.Steps
  doctest Tempo.Iso8601.Unit
  doctest Tempo.Mask
  doctest Tempo.Math, import: true
  doctest Tempo.Microsecond
  doctest Tempo.Network.Normalize
  doctest Tempo.Operations
  doctest Tempo.RRule.Expander
  doctest Tempo.RRule.Rule
  doctest Tempo.RRule.Selection
  doctest Tempo.Select
  doctest Tempo.UnitValues
end
