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

  # The calls Tempo makes into Calendrical that are no question of a calendar
  # a value holds, each with why it stays (decision 89): every other question
  # is asked of the calendar, `calendar.callback(…)`.
  @calls_into_calendrical %{
    # A calendar's name, an IXDTF `u-ca` value or a CLDR type, resolved to its
    # module where it is read, and written back (global rule 10).
    {Calendrical, :calendar_from_cldr_calendar_type, 1} => :a_named_calendar,
    {Calendrical, :additional_calendars, 0} => :a_named_calendar,
    # The Easter event, which Calendrical computes as it does every event.
    {Calendrical.Ecclesiastical, :easter_sunday, 1} => :an_event,
    {Calendrical.Ecclesiastical, :orthodox_easter_sunday, 1} => :an_event,
    # The date rule grammar's words for the solar terms.
    {Calendrical.Lunisolar, :solar_term_name, 1} => :a_word_of_the_notation
  }

  # The Gregorian calendars of other week starts, which Calendrical builds.
  @built_by_calendrical "Elixir.Tempo.Calendar.WeeksFrom."

  test "no module but the adapter names a calendar module" do
    {:ok, modules} = :application.get_key(:ex_tempo, :modules)

    named =
      for module <- modules,
          not adapter?(module),
          library_module?(module),
          atom <- atoms(module),
          calendar_module?(atom),
          do: {module, atom}

    assert [] = named
  end

  test "a calendar is asked by its callbacks: no module calls Calendrical but as listed" do
    {:ok, modules} = :application.get_key(:ex_tempo, :modules)

    calls =
      for module <- modules,
          library_module?(module),
          not built_by_calendrical?(module),
          {callee, _function, _arity} = call <- imports(module),
          calendrical?(callee),
          not Map.has_key?(@calls_into_calendrical, call),
          do: {module, call}

    assert [] = calls
  end

  test "every call listed is still made, so the list holds nothing stale" do
    {:ok, modules} = :application.get_key(:ex_tempo, :modules)

    made =
      for module <- modules,
          library_module?(module),
          not built_by_calendrical?(module),
          call <- imports(module),
          into: MapSet.new(),
          do: call

    assert [] = Enum.reject(Map.keys(@calls_into_calendrical), &MapSet.member?(made, &1))
  end

  # The adapter, and the Gregorian calendars of other week starts it names,
  # which Calendrical builds.
  defp adapter?(module) do
    module == @adapter or String.starts_with?(Atom.to_string(module), "#{@adapter}.")
  end

  # A module compiled from `lib/`, not from the tests' support.
  defp library_module?(module) do
    module.module_info(:compile)
    |> Keyword.get(:source)
    |> to_string()
    |> String.contains?("/lib/")
  end

  defp atoms(module) do
    # The module's own compiled code, which a coverage run leaves on the path.
    {^module, compiled, _file} = :code.get_object_code(module)
    {:ok, {^module, [atoms: atoms]}} = :beam_lib.chunks(compiled, [:atoms])
    for {_index, atom} <- atoms, do: Atom.to_string(atom)
  end

  # The remote calls a module's compiled code makes.
  defp imports(module) do
    {^module, compiled, _file} = :code.get_object_code(module)
    {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(compiled, [:imports])
    imports
  end

  defp calendrical?(module) do
    name = Atom.to_string(module)
    name == "Elixir.Calendrical" or String.starts_with?(name, "Elixir.Calendrical.")
  end

  defp built_by_calendrical?(module) do
    String.starts_with?(Atom.to_string(module), @built_by_calendrical)
  end

  defp calendar_module?(atom) do
    Enum.any?(@calendar_modules, &(atom == &1 or String.starts_with?(atom, &1 <> ".")))
  end
end
