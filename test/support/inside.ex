defmodule Tempo.Test.Inside do
  @moduledoc false

  alias Tempo.Border
  alias Tempo.Sigils

  # A test of the engine gives it values as Tempo holds them inside a call.
  #
  # A caller holds a value that names no calendar in `Calendar.ISO`, and a
  # public function replaces that with the module Tempo works with as the
  # call comes in, and back as it returns (`Tempo.Border`). The engine's
  # functions are no part of the public API: they are called from inside,
  # with values already entered, and a test that calls one directly gives it
  # such a value. `import Tempo.Test.Inside` in place of `import
  # Tempo.Sigils` makes `~o` write one, and a public function given one
  # answers in kind, so the expected values of a test are written the same
  # way.

  @doc false
  # `~o"…"` as the value is held inside a call: the value or the pattern the
  # public sigil writes, with the calendar a caller holds replaced by the
  # one Tempo works with.
  defmacro sigil_o(string, modifiers) do
    environment = %{__CALLER__ | requires: [Sigils | __CALLER__.requires]}

    quote do
      unquote(Sigils).sigil_o(unquote(string), unquote(modifiers))
    end
    |> Macro.expand_once(environment)
    |> Macro.prewalk(&entered/1)
  end

  defp entered(term) do
    if term == Border.outside(), do: Border.inside(), else: term
  end

  @doc false
  # A value a public function answered a caller with, as it is held inside.
  def inside(value), do: Border.enter(value)

  @doc false
  # A value held inside, as a caller holds it.
  def outside(value), do: Border.leave(value)
end
