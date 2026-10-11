defmodule Tempo.Test.Engine do
  @moduledoc false

  alias Tempo.Border

  # The engine, as a public function calls it.
  #
  # A caller holds a value that names no calendar in `Calendar.ISO`. A
  # public function replaces that with the module Tempo works with as the
  # call comes in, and back as it returns (`Tempo.Border`), so the engine's
  # modules are only ever given values already entered. They are no part of
  # the public API and do not cross the border themselves.
  #
  # A test that calls one directly holds a caller's values, as every test
  # does. Each module below is the engine's module of the same name with
  # that one step added: its arguments are entered and its answer is left,
  # as the public function above it would have done. A test aliases
  # `Tempo.Test.Engine.Math` where it would alias `Tempo.Math`.

  engine = [
    Tempo.Compare,
    Tempo.Enumeration,
    Tempo.Enumeration.Zone,
    Tempo.Format,
    Tempo.Inspect,
    Tempo.Interval.Composition,
    Tempo.Interval.Cycle,
    Tempo.Interval.Steps,
    Tempo.Iso8601.AST,
    Tempo.Iso8601.Group,
    Tempo.Iso8601.Parser,
    Tempo.Iso8601.Unit,
    Tempo.Limit,
    Tempo.Mask,
    Tempo.Math,
    Tempo.Microsecond,
    Tempo.Network.Normalize,
    Tempo.NotBuilt,
    Tempo.Operations,
    Tempo.Qualification,
    Tempo.RRule.Encoder,
    Tempo.RRule.Expander,
    Tempo.RRule.Rule,
    Tempo.RRule.Selection,
    Tempo.Rounding,
    Tempo.Select,
    Tempo.Split,
    Tempo.UnitValues,
    Tempo.Validation
  ]

  for module <- engine do
    ["Tempo" | name] = Module.split(module)

    defmodule Module.concat([__MODULE__ | name]) do
      @moduledoc false

      for {function, arity} <- module.__info__(:functions),
          not String.starts_with?(Atom.to_string(function), "__") do
        arguments = Macro.generate_arguments(arity, __MODULE__)

        @doc false
        # `:erlang.apply/3`, since an engine function may have the name of
        # one that `Kernel` imports (`Tempo.RRule.Selection.apply/4`).
        def unquote(function)(unquote_splicing(arguments)) do
          Border.leave(
            :erlang.apply(
              unquote(module),
              unquote(function),
              Border.enter([unquote_splicing(arguments)])
            )
          )
        end
      end
    end
  end
end
