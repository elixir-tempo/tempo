defmodule Tempo.Zone.Table do
  @moduledoc false

  # The changes of a named zone's offset as one table: the UTC ticks at which
  # the offset changes, ascending, with the offset in force from each. A
  # table is built once for a zone and kept in `:persistent_term`, where
  # every process reads it, and every question `Tempo.Zone` asks of a named
  # zone is a binary search in it (decision 73).
  #
  # The table is exact where the database lists its periods
  # (`Tempo.Zone.Transitions`). Where it does not, the changes are sampled:
  # the offset is asked of the database at points six days apart, and where
  # two neighbouring samples differ the change between them is found to the
  # second by halving. Sampling finds one change between two samples and not
  # two. A database's rule-made periods beyond its list change twice a year
  # at most, months apart; a database that lists nothing is held to the same
  # assumption, from 1800, before any zone's standard time. A table grows
  # forward as questions reach past what it knows, ten years at a time.

  alias Tempo.Zone.Transitions
  alias Tempo.ZoneError

  @enforce_keys [:name, :database, :ticks, :offsets, :initial, :known_until]
  defstruct [:name, :database, :ticks, :offsets, :initial, :known_until]

  @type tick :: integer()

  @typedoc "A stretch of one offset: where it begins and ends, nil for no end, and the offset."
  @type stretch :: {tick() | nil, tick() | nil, tick()}

  @type t :: %__MODULE__{
          name: String.t(),
          database: module(),
          ticks: tuple(),
          offsets: tuple(),
          initial: tick(),
          known_until: tick() | :infinity
        }

  @second 1_000_000
  @day 86_400 * @second

  # The spacing of the samples where a database lists nothing, within the
  # shortest time between two rule-made changes; how far a table grows at a
  # time; and where a sampled table begins.
  @sample_spacing 6 * @day
  @growth 10 * 366 * @day
  @sampled_from :calendar.datetime_to_gregorian_seconds({{1800, 1, 1}, {0, 0, 0}}) * @second

  # ── A zone's table ────────────────────────────────────────────────────

  @doc """
  The table of a zone from a database, known through a tick: built on the
  first question of the zone, grown where a question reaches past what it
  knows. A zone the database does not have raises the `Tempo.ZoneError` it
  would have been refused with.
  """
  @spec of(String.t(), module(), tick()) :: t()
  def of(name, database, until) do
    key = {__MODULE__, database, version(database), name}

    table =
      case :persistent_term.get(key, nil) do
        %__MODULE__{} = table -> table
        nil -> kept(key, built(name, database))
      end

    if known?(table, until), do: table, else: kept(key, grown(table, until + @growth))
  end

  defp known?(%__MODULE__{known_until: :infinity}, _until), do: true
  defp known?(%__MODULE__{known_until: known_until}, until), do: until < known_until

  defp kept(key, table) do
    :persistent_term.put(key, table)
    table
  end

  defp version(database) do
    case Transitions.for_database(database) do
      nil -> nil
      module -> module.version()
    end
  end

  defp built(name, database) do
    case changes(Transitions.for_database(database), name) do
      {:ok, changes, listed_until} -> from_changes(name, database, changes, listed_until)
      :none -> sampled_from_start(name, database)
    end
  end

  defp changes(nil, _name), do: :none

  defp changes(module, name) do
    case module.changes(name) do
      {:ok, _changes, _listed_until} = listed -> listed
      {:error, :not_listed} -> :none
      {:error, reason} -> raise ZoneError.exception(zone: name, reason: error_reason(reason))
    end
  end

  defp from_changes(name, database, [{_from, first} | _] = changes, listed_until) do
    %__MODULE__{
      name: name,
      database: database,
      ticks:
        changes |> Enum.map(fn {from, _offset} -> whole(from) * @second end) |> List.to_tuple(),
      offsets:
        changes |> Enum.map(fn {_from, offset} -> whole(offset) * @second end) |> List.to_tuple(),
      initial: whole(first) * @second,
      known_until: if(listed_until, do: listed_until * @second, else: :infinity)
    }
  end

  defp sampled_from_start(name, database) do
    %__MODULE__{
      name: name,
      database: database,
      ticks: {},
      offsets: {},
      initial: asked_at(name, database, @sampled_from),
      known_until: @sampled_from
    }
  end

  # The table grown by sampling from where it stops to a tick: the changes
  # found are added to it, and it then knows through the last sample.
  defp grown(%__MODULE__{known_until: from} = table, until) do
    {changes, sampled_until} =
      sampled(table.name, table.database, from, until, offset_at(table, from))

    %{
      table
      | ticks: List.to_tuple(Tuple.to_list(table.ticks) ++ Enum.map(changes, &elem(&1, 0))),
        offsets: List.to_tuple(Tuple.to_list(table.offsets) ++ Enum.map(changes, &elem(&1, 1))),
        known_until: sampled_until
    }
  end

  # The changes between two ticks, by samples six days apart: where a sample's
  # offset differs from the one before it, the change between the two is
  # found to the second.
  defp sampled(name, database, from, until, offset) do
    points = Stream.iterate(from + @sample_spacing, &(&1 + @sample_spacing))

    {changes, {last, _}} =
      points
      |> Enum.take_while(&(&1 - @sample_spacing < until))
      |> Enum.flat_map_reduce({from, offset}, fn point, {previous, before} ->
        case asked_at(name, database, point) do
          ^before ->
            {[], {point, before}}

          later ->
            {[{changed_at(name, database, before, previous, point), later}], {point, later}}
        end
      end)

    {changes, last}
  end

  # The first second after `same`, and no later than `changed`, at which the
  # offset is no longer `offset`, by halving.
  defp changed_at(name, database, offset, same, changed),
    do: halve(name, database, offset, div(same, @second), div(changed, @second)) * @second

  defp halve(_name, _database, _offset, same, changed) when changed - same <= 1, do: changed

  defp halve(name, database, offset, same, changed) do
    middle = same + div(changed - same, 2)

    if asked_at(name, database, middle * @second) == offset,
      do: halve(name, database, offset, middle, changed),
      else: halve(name, database, offset, same, middle)
  end

  @doc "The offset the database has at a UTC tick, in ticks; a zone it does not have raises."
  @spec asked_at(String.t(), module(), tick()) :: tick()
  def asked_at(name, database, tick) do
    seconds = Integer.floor_div(tick, @second)

    case database.time_zone_period_from_utc_iso_days(iso_days(seconds), name) do
      {:ok, %{utc_offset: utc_offset, std_offset: std_offset}} ->
        whole(utc_offset + std_offset) * @second

      {:error, reason} ->
        raise ZoneError.exception(zone: name, reason: error_reason(reason))
    end
  end

  defp iso_days(seconds),
    do: {div(seconds, 86_400), {rem(seconds, 86_400) * @second, 86_400 * @second}}

  # The database answers an offset in whole seconds, and the table holds
  # whole ticks: said so where one is read, for the analysis of the types.
  defp whole(number) when is_integer(number), do: number

  @doc "The reason of a `Tempo.ZoneError` for what a database answers of a zone it cannot."
  @spec error_reason(term()) :: :no_database | :unknown
  def error_reason(:utc_only_time_zone_database), do: :no_database
  def error_reason(_not_found), do: :unknown

  # ── Questions of a table ──────────────────────────────────────────────

  @doc "The offset in force at a UTC tick."
  @spec offset_at(t(), tick()) :: tick()
  def offset_at(%__MODULE__{ticks: ticks, offsets: offsets, initial: initial}, tick) do
    case last_at_or_before(ticks, tick) do
      -1 -> whole(initial)
      index -> whole(elem(offsets, index))
    end
  end

  @doc """
  The stretches of one offset that overlap `[from, to)`, in order: each
  from the change that begins it, or nil for the offset the zone began
  with, to the change that ends it, or nil where none has.
  """
  @spec stretches(t(), tick(), tick()) :: [stretch(), ...]
  def stretches(%__MODULE__{ticks: ticks} = table, from, to),
    do: stretches_from(table, last_at_or_before(ticks, from), to)

  # The stretch at an index and each next one that begins before `to`: a
  # walk from the one found, the changes about a reading being few.
  defp stretches_from(%__MODULE__{ticks: ticks} = table, index, to) do
    if index + 1 < tuple_size(ticks) and elem(ticks, index + 1) < to,
      do: [stretch(table, index) | stretches_from(table, index + 1, to)],
      else: [stretch(table, index)]
  end

  defp stretch(%__MODULE__{ticks: ticks, offsets: offsets, initial: initial}, index) do
    start = if index == -1, do: nil, else: whole(elem(ticks, index))
    stop = if index + 1 < tuple_size(ticks), do: whole(elem(ticks, index + 1)), else: nil
    offset = if index == -1, do: whole(initial), else: whole(elem(offsets, index))
    {start, stop, offset}
  end

  @doc """
  The offset in force at `start` where it keeps through to `stop`:
  `{:ok, offset}`, or `:changes` where the offset changes between the two.
  """
  @spec steady(t(), tick(), tick()) :: {:ok, tick()} | :changes
  def steady(%__MODULE__{ticks: ticks, offsets: offsets, initial: initial}, start, stop) do
    index = last_at_or_before(ticks, start)

    cond do
      index + 1 < tuple_size(ticks) and elem(ticks, index + 1) < stop -> :changes
      index == -1 -> {:ok, whole(initial)}
      true -> {:ok, whole(elem(offsets, index))}
    end
  end

  @doc "The first change after `from` and no later than `to`, or nil where the offset keeps through."
  @spec first_change(t(), tick(), tick()) :: tick() | nil
  def first_change(%__MODULE__{ticks: ticks}, from, to) do
    index = last_at_or_before(ticks, from) + 1

    if index < tuple_size(ticks) and elem(ticks, index) <= to,
      do: whole(elem(ticks, index)),
      else: nil
  end

  # The index of the last change at or before a tick, by halving; -1 where
  # the tick is before every change.
  defp last_at_or_before(ticks, tick), do: search(ticks, tick, 0, tuple_size(ticks) - 1)

  defp search(_ticks, _tick, low, high) when low > high, do: high

  defp search(ticks, tick, low, high) do
    middle = div(low + high, 2)

    if elem(ticks, middle) <= tick,
      do: search(ticks, tick, middle + 1, high),
      else: search(ticks, tick, low, middle - 1)
  end
end
