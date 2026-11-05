defmodule Tempo.Zone.Transitions do
  @moduledoc false

  # The changes of a zone's offset as a database lists them: the one
  # question Tempo asks beside `Calendar.TimeZoneDatabase`, which answers an
  # offset at a point and lists nothing. A database that lists its periods
  # gives `Tempo.Zone.Table` an exact table of a zone's changes; one that
  # does not has its changes found by sampling, which finds one change
  # between two samples six days apart and not two (decision 73).
  #
  # The module that lists a database's changes is known for `tz`, and is
  # configured for another:
  #
  #     config :ex_tempo, :zone_transitions, %{My.Database => My.Transitions}

  @typedoc "A change of the offset: the UTC second it takes effect, and the offset in seconds from then."
  @type change :: {utc_seconds :: integer(), offset_seconds :: integer()}

  @typedoc """
  The changes of a zone's offset, earliest first, the first being the
  offset the zone began with; and the UTC second past which they are not
  listed, the database making its periods from a rule, or nil where the
  list is whole.
  """
  @type listed :: {:ok, [change(), ...], listed_until :: integer() | nil} | {:error, term()}

  @doc """
  The changes of each of a list of zones, in its order: asked of all the
  zones Tempo builds a table of as it starts, so that a database can share
  what zones have in common.
  """
  @callback changes([Calendar.time_zone()]) :: [{Calendar.time_zone(), listed()}]

  @doc "What identifies the database's data, so that a table is built again when the data changes: its IANA version."
  @callback version() :: term()

  @known %{Tz.TimeZoneDatabase => Tempo.Zone.Transitions.Tz}
  @configured Application.compile_env(:ex_tempo, :zone_transitions, %{})

  @doc "The module that lists a database's changes, or nil for a database that lists none."
  @spec for_database(module()) :: module() | nil
  def for_database(database), do: @known |> Map.merge(@configured) |> Map.get(database)
end

defmodule Tempo.Zone.Transitions.Tz do
  @moduledoc false

  # `tz` compiles its periods into `Tz.PeriodsProvider`, latest first, each
  # `{from, {utc_offset, std_offset, abbreviation}, the period before, rule}`
  # with `from` in Gregorian seconds (0 for the first) and a rule on the
  # latest period alone, the periods after it being made from the rule as
  # they are asked for, a few years at a time, by
  # `Tz.TimeZoneDatabase.generate_dynamic_periods/3`. The list is extended
  # with those periods through 2100, so that a zone's table is exact and
  # read once for any date a calendar is likely to be asked of. Both
  # functions are tz's own and not public (TODO.md): a `tz` without the
  # first lists nothing, and a zone's changes are sampled; one without the
  # second lists what it compiles, and the changes past it are sampled.

  @behaviour Tempo.Zone.Transitions

  # tz is not a dependency of the library: its modules are called through
  # captures made at run time, so that a build without tz compiles with no
  # warning of it.
  @provider Tz.PeriodsProvider
  @database Tz.TimeZoneDatabase

  # Where the list is extended to: the start of 2101, in Gregorian seconds.
  @extended_until :calendar.datetime_to_gregorian_seconds({{2101, 1, 1}, {0, 0, 0}})

  # The changes a rule makes are generated once for each rule, start and
  # offset, which many zones and every alias of a zone share.
  @impl true
  def changes(zones) do
    if Code.ensure_loaded?(@provider) and function_exported?(@provider, :periods, 1) do
      periods = Function.capture(@provider, :periods, 1)

      {listed, _generated} =
        Enum.map_reduce(zones, %{}, fn zone, generated ->
          {result, generated} = listed(periods.(zone), generated)
          {{zone, result}, generated}
        end)

      listed
    else
      Enum.map(zones, &{&1, {:error, :not_listed}})
    end
  end

  # The version is asked on every question of a zone, and the module that
  # answers it is loaded by then where a table was built from it: a module
  # not yet loaded has no version, and the table built from it is keyed so.
  @impl true
  def version do
    if function_exported?(@provider, :iana_version, 0),
      do: Function.capture(@provider, :iana_version, 0).(),
      else: nil
  end

  # tz answers a tick with the first period in its list, latest first, that
  # begins at or before the tick. A period listed after one that begins no
  # later than it is never the answer (the list is not always in order:
  # America/Scoresbysund has three periods for 2024-03-31, and the one that
  # begins at 01:00 after the one at 00:00 answers nothing), and is left out,
  # so that the table says what the database says at every tick.
  defp listed({:ok, periods}, generated) do
    {changes, _earliest} =
      Enum.flat_map_reduce(periods, nil, fn
        {from, {utc_offset, std_offset, _abbreviation}, _before, _rule}, earliest
        when is_nil(earliest) or from < earliest ->
          {[{from, utc_offset + std_offset}], from}

        _shadowed, earliest ->
          {[], earliest}
      end)

    extended(Enum.reverse(changes), periods, generated)
  end

  defp listed({:error, _reason} = error, generated), do: {error, generated}

  # The latest period carries a rule where the zone's changes go on: the
  # changes it makes are listed through `@extended_until`, past which the
  # list is no longer whole; from the rule's start where tz cannot make them.
  defp extended(changes, [{from, {utc_offset, _std, _abbr}, _before, rule} | _earlier], generated)
       when not is_nil(rule) do
    key = {from, utc_offset, rule}

    generated =
      Map.put_new_lazy(generated, key, fn -> generated(from, utc_offset, rule) end)

    case Map.fetch!(generated, key) do
      {:ok, more} -> {{:ok, changes ++ more, @extended_until}, generated}
      :error -> {{:ok, changes, from}, generated}
    end
  end

  defp extended(changes, _periods, generated) do
    {{:ok, changes, nil}, generated}
  end

  # The changes tz makes from a rule after `from` and before
  # `@extended_until`, asked of every second year from the rule's first:
  # each answer holds the year asked and the next whole, and of the year
  # before only its last change. tz's function is not public, so a failure
  # of it is read as a tz that cannot make them.
  defp generated(from, utc_offset, rule) do
    if Code.ensure_loaded?(@database) and
         function_exported?(@database, :generate_dynamic_periods, 3) do
      generate = Function.capture(@database, :generate_dynamic_periods, 3)
      {:ok, generated_years(generate, from, utc_offset, rule)}
    else
      :error
    end
  rescue
    _exception -> :error
  end

  defp generated_years(generate, from, utc_offset, rule) do
    {{first_year, _month, _day}, _time} = :calendar.gregorian_seconds_to_datetime(from)
    {{last_year, _month, _day}, _time} = :calendar.gregorian_seconds_to_datetime(@extended_until)

    first_year
    |> Range.new(last_year, 2)
    |> Enum.flat_map(&generate.(mid_year(&1), utc_offset, rule))
    |> Enum.flat_map(&change_within(&1, from))
    |> Enum.sort()
    |> Enum.dedup()
  end

  defp mid_year(year) do
    :calendar.datetime_to_gregorian_seconds({{year, 7, 1}, {0, 0, 0}})
  end

  defp change_within({start, {utc_offset, std_offset, _abbreviation}, _before, _rule}, from)
       when start > from and start < @extended_until do
    [{start, utc_offset + std_offset}]
  end

  defp change_within(_period, _from) do
    []
  end
end
