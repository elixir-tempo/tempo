defmodule Tempo.CalendarSurfaceTest do
  @moduledoc """
  Every question Tempo puts to a calendar goes through `Tempo.Calendar`,
  the one module that names a calendar module. This holds the rest of the
  library to it: no other compiled module refers to a calendar by name.
  """

  use ExUnit.Case, async: true

  @adapter Tempo.Calendar

  # The modules that answer for a calendar. `Calendar.ISO` is not among
  # them: it is the default a value holds, which answers nothing itself.
  @calendar_modules ["Elixir.Calendrical", "Elixir.Localize.Calendar.ISO"]

  test "no module but the adapter names a calendar module" do
    {:ok, modules} = :application.get_key(:ex_tempo, :modules)

    named =
      for module <- modules,
          module != @adapter,
          library_module?(module),
          atom <- atoms(module),
          calendar_module?(atom),
          do: {module, atom}

    assert named == []
  end

  # A module compiled from `lib/`, not from the tests' support.
  defp library_module?(module) do
    module.module_info(:compile)
    |> Keyword.get(:source)
    |> to_string()
    |> String.contains?("/lib/")
  end

  defp atoms(module) do
    {:ok, {^module, [atoms: atoms]}} = :beam_lib.chunks(:code.which(module), [:atoms])
    for {_index, atom} <- atoms, do: Atom.to_string(atom)
  end

  defp calendar_module?(atom) do
    Enum.any?(@calendar_modules, &(atom == &1 or String.starts_with?(atom, &1 <> ".")))
  end
end
