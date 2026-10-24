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

  @doc """
  The changes of a zone's offset, earliest first, the first being the
  offset the zone began with; and the UTC second from which the database
  makes its periods from a rule rather than from its list, or nil where the
  list is whole.
  """
  @callback changes(Calendar.time_zone()) ::
              {:ok, [change(), ...], listed_until :: integer() | nil} | {:error, term()}

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
  # they are asked for. The module is tz's own and not public (TODO.md); a
  # `tz` without it lists nothing, and a zone's changes are sampled.

  @behaviour Tempo.Zone.Transitions

  # tz is not a dependency of the library: its generated module is called
  # through a capture made at run time, so that a build without tz compiles
  # with no warning of it.
  @provider Tz.PeriodsProvider

  @impl true
  def changes(zone) do
    if Code.ensure_loaded?(@provider) and function_exported?(@provider, :periods, 1),
      do: listed(Function.capture(@provider, :periods, 1).(zone)),
      else: {:error, :not_listed}
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
  defp listed({:ok, periods}) do
    {changes, _earliest} =
      Enum.flat_map_reduce(periods, nil, fn
        {from, {utc_offset, std_offset, _abbreviation}, _before, _rule}, earliest
        when is_nil(earliest) or from < earliest ->
          {[{from, utc_offset + std_offset}], from}

        _shadowed, earliest ->
          {[], earliest}
      end)

    {:ok, Enum.reverse(changes), rule_from(periods)}
  end

  defp listed({:error, _reason} = error), do: error

  # The latest period carries a rule where the zone's changes go on: from
  # its start the list is no longer whole.
  defp rule_from([{from, _period, _before, rule} | _earlier]) when not is_nil(rule) do
    from
  end

  defp rule_from(_periods), do: nil
end
