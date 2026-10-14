defmodule Tempo.Zone do
  @moduledoc false

  # A time zone as a value carries it: a name the zone database knows
  # (`Europe/Paris`), or a fixed offset from UTC in minutes, with RFC 9557's
  # critical flag.
  #
  # A zone is the frame of an expression (law 4): every part of an expression
  # is in one zone. A written time shift (`+02:00`, `Z2H`) is not a zone; it is
  # held on each end as `t:shift/0`. This module answers the offsets a zone's
  # clock shows at a wall reading, the reading at an instant, and the gaps and
  # folds between them.

  # A named time zone or a fixed offset, as an IXDTF suffix writes one, and
  # the one place the core reads the zone database: the offsets a wall
  # reading can have, the offset at a UTC tick. A tick is a microsecond
  # since 0000-01-01T00:00:00, which is Elixir's ISO-day epoch and Erlang's
  # Gregorian-seconds epoch alike.
  #
  # A wall reading has one offset; none, where the clock skips it going
  # forward; or two, where the clock shows it twice going back. A value is
  # placed by its written shift where it has one, else by the one offset,
  # else by the first of the two. A reading the clock skips is refused when
  # a value is built (`Tempo.Validate`); where a span's end falls in one,
  # the end is read on the clock before the change, as the hour it closes
  # was.

  alias Tempo.ZoneError

  @enforce_keys []
  defstruct [:name, :offset, critical: false]

  @second 1_000_000
  @day 86_400 * @second

  @typedoc "A zone: an IANA name, or a fixed offset in minutes from UTC (`[+05:30]`), never both."
  @type t :: Tempo.zone()

  @type tick :: integer()

  @type shift :: Tempo.shift()

  @doc "A named zone, checked against the zone database."
  @spec named(String.t(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def named(name, options \\ []) when is_binary(name) do
    if exists?(name),
      do: {:ok, %__MODULE__{name: name, critical: Keyword.get(options, :critical, false)}},
      else: {:error, ZoneError.exception(zone: name, reason: :unknown)}
  end

  @doc "A zone of a fixed offset, in minutes from UTC."
  @spec fixed(integer()) :: %__MODULE__{name: nil, offset: integer(), critical: false}
  def fixed(minutes) when is_integer(minutes), do: %__MODULE__{offset: minutes}

  @doc "An offset in ticks as a written shift: five hours behind UTC is `[hour: -5, minute: 0]`."
  @spec shift_of(tick()) :: [{:hour, integer()} | {:minute, integer()}, ...]
  # No shift from UTC is held as it is read from `Z`.
  def shift_of(0), do: [hour: 0]

  def shift_of(offset) do
    behind? = offset < 0
    minutes = div(abs(offset), 60 * @second)
    signed([hour: div(minutes, 60), minute: rem(minutes, 60)], behind?)
  end

  @doc """
  The units of a shift with its sign: a shift behind UTC carries a minus on
  its first unit that is not zero, so half an hour behind is `[hour: 0,
  minute: -30]` and five and a half hours behind `[hour: -5, minute: 30]`.
  """
  @spec signed(keyword(non_neg_integer()), boolean()) :: shift()
  def signed(units, false), do: units

  def signed(units, true) do
    case Enum.split_while(units, fn {_unit, value} -> value == 0 end) do
      {_all_zero, []} -> units
      {zeros, [{unit, value} | rest]} -> zeros ++ [{unit, -value} | rest]
    end
  end

  @doc "A written shift as ticks: `[hour: -5, minute: 30]` is five and a half hours behind UTC."
  @spec shift_ticks(shift()) :: tick()
  def shift_ticks(shift) do
    magnitude =
      abs(whole(Keyword.get(shift, :hour, 0))) * 3600 +
        abs(whole(Keyword.get(shift, :minute, 0))) * 60 +
        abs(whole(Keyword.get(shift, :second, 0)))

    sign =
      shift |> Keyword.values() |> Enum.find(0, &(&1 != 0)) |> then(&if(&1 < 0, do: -1, else: 1))

    sign * magnitude * @second
  end

  @doc "The offsets, in ticks, a wall reading has in a zone: one, none in a gap, two in a fold."
  @spec offsets_at_wall(t(), tick()) ::
          [tick()] | {:gap, before_change :: tick(), after_change :: tick()}
  def offsets_at_wall(%__MODULE__{offset: minutes}, _wall) when is_integer(minutes),
    do: [minutes * 60 * @second]

  def offsets_at_wall(%__MODULE__{name: name}, wall) do
    case periods_at_wall(name, seconds(wall)) do
      {:ok, period} -> [offset(period)]
      {:ambiguous, first, second} -> [offset(first), offset(second)]
      {:gap, {before, _}, {after_change, _}} -> {:gap, offset(before), offset(after_change)}
    end
  end

  @doc """
  Whether a zone's clock skips a whole day, as Samoa's skipped the 30th of
  December 2011: a day no reading of which is ever shown.
  """
  @spec day_skipped?(t() | nil, shift() | nil, integer()) :: boolean()
  def day_skipped?(%__MODULE__{name: name} = zone, nil, day) when is_binary(name) do
    skipped?(zone, day * @day) and skipped?(zone, (day + 1) * @day - 1)
  end

  def day_skipped?(_zone, _shift, _day), do: false

  @doc "Whether a zone's clock skips a wall reading."
  @spec skipped?(t(), tick()) :: boolean()
  def skipped?(%__MODULE__{} = zone, wall), do: match?({:gap, _, _}, offsets_at_wall(zone, wall))

  @doc "The offset, in ticks, a zone has at a UTC tick."
  @spec offset_at_utc(t(), tick()) :: tick()
  def offset_at_utc(%__MODULE__{offset: minutes}, _utc) when is_integer(minutes),
    do: minutes * 60 * @second

  def offset_at_utc(%__MODULE__{name: name}, utc) do
    {:ok, period} = period_at_utc(name, seconds(utc))
    offset(period)
  end

  @doc """
  The offset a wall reading is placed by: the written shift where there is
  one; else the zone's one offset, the first of two, or the one before a
  change where the clock skips the reading. No zone and no shift is UTC.
  """
  @spec offset_at_wall(t() | nil, shift() | nil, tick()) :: tick()
  def offset_at_wall(_zone, shift, _wall) when is_list(shift), do: shift_ticks(shift)
  def offset_at_wall(nil, nil, _wall), do: 0

  def offset_at_wall(%__MODULE__{} = zone, nil, wall) do
    case offsets_at_wall(zone, wall) do
      [offset | _] -> offset
      {:gap, before, _after_change} -> before
    end
  end

  @doc "The UTC tick of a wall reading in a zone, placed as `offset_at_wall/3` places it."
  @spec utc_of_wall(t() | nil, shift() | nil, tick()) :: tick()
  def utc_of_wall(zone, shift, wall), do: wall - offset_at_wall(zone, shift, wall)

  @doc "The wall reading of a UTC tick in a zone, with the offset it has there."
  @spec wall_of_utc(t() | nil, shift() | nil, tick()) :: {tick(), tick()}
  def wall_of_utc(_zone, shift, utc) when is_list(shift),
    do: {utc + shift_ticks(shift), shift_ticks(shift)}

  def wall_of_utc(nil, nil, utc), do: {utc, 0}

  def wall_of_utc(%__MODULE__{} = zone, nil, utc) do
    offset = offset_at_utc(zone, utc)
    {utc + offset, offset}
  end

  @doc """
  The UTC tick at which a zone's clock first shows a reading or, where the
  clock skips it, the first reading after it: the moment the clock goes
  forward. An hour whose start is skipped is shown from there, where a part
  of it is shown at all.
  """
  @spec first_shown(t(), tick()) :: tick()
  def first_shown(%__MODULE__{name: name} = zone, wall) when is_binary(name) do
    case offsets_at_wall(zone, wall) do
      {:gap, before, after_change} ->
        first_change(zone, before, wall - after_change, wall - before)

      [offset | _] ->
        wall - offset
    end
  end

  def first_shown(zone, wall), do: utc_of_wall(zone, nil, wall)

  @doc """
  The UTC tick at which a zone's clock first shows a unit of `step` ticks
  that begins at a wall reading, at the offset a written shift names.

  A shift beside a zone says which of two showings is meant. Where the
  zone has that offset as the unit begins, the unit begins there. Where it
  comes to that offset within the unit (the clock going back from 03:45 to
  02:45 shows the hour from 02:00 again from 02:45) the unit begins where
  it does. Where it has it nowhere in the unit, the shift says a moment
  the zone's clock did not show so, and the unit begins at that moment.
  """
  @spec shown_from(t(), shift(), tick(), pos_integer()) :: tick()
  def shown_from(%__MODULE__{name: name} = zone, shift, wall, step) when is_binary(name) do
    offset = shift_ticks(shift)
    written = wall - offset
    before = offset_at_utc(zone, written)

    cond do
      before == offset ->
        written

      offset_at_utc(zone, written + step - 1) == offset ->
        first_change(zone, before, written, written + step)

      true ->
        written
    end
  end

  def shown_from(_zone, shift, wall, _step) when is_integer(wall), do: wall - shift_ticks(shift)

  @doc """
  Where the unit of the clock that is showing at a UTC tick ends: an hour,
  a minute or a second of `step` ticks, as the zone's clock shows it.

  With no change of the clock that is the next whole unit. Where the clock
  goes forward past the unit's end it ends there, having shown a part of
  the unit (the half hour from 23:00 where the clock goes from 23:30 to
  midnight). Where the clock goes back to within the unit without coming to
  its start again it runs on through the second showing (an hour and a half
  from 01:00 where the clock goes from 02:00 back to 01:30); where it goes
  back to the unit's start, the unit ends and is shown again. A fixed
  offset has no changes.
  """
  @spec unit_end(t() | nil, shift() | nil, tick(), pos_integer()) :: tick()
  def unit_end(%__MODULE__{name: name} = zone, shift, utc, step) when is_binary(name) do
    offset = offset_at_utc(zone, utc)

    if shift == nil or shift_ticks(shift) == offset,
      do: shown_until(zone, offset, utc, step),
      else: unit_end(nil, shift, utc, step)
  end

  def unit_end(_zone, _shift, utc, step) when is_integer(utc) and is_integer(step),
    do: utc + step

  # A shift written beside a zone says which of two showings a reading is,
  # and is then the zone's offset there; one that is not the zone's gives a
  # moment the zone's clock did not show so, which is one unit long.
  defp shown_until(zone, offset, utc, step) do
    unit_start = Integer.floor_div(utc + offset, step) * step
    whole = unit_start + step - offset

    if offset_at_utc(zone, whole) == offset,
      do: whole,
      else: ended_by_a_change(zone, first_change(zone, offset, utc, whole), unit_start, step)
  end

  # The clock changes at a tick within the unit, or as it would have ended:
  # the unit runs on where the clock then shows a later part of it.
  defp ended_by_a_change(zone, change, unit_start, step) do
    shown = change + offset_at_utc(zone, change)

    if shown > unit_start and shown < unit_start + step,
      do: unit_end(zone, nil, change, step),
      else: change
  end

  # The first tick after `from`, and no later than `to`, at which the zone's
  # offset is no longer what it was: found to the second by halving.
  defp first_change(zone, offset, from, to) do
    halve(zone, offset, seconds(from), Integer.floor_div(to + @second - 1, @second)) * @second
  end

  defp halve(_zone, _offset, same, changed) when changed - same <= 1, do: changed

  defp halve(zone, offset, same, changed) do
    middle = same + div(changed - same, 2)

    if offset_at_utc(zone, middle * @second) == offset,
      do: halve(zone, offset, middle, changed),
      else: halve(zone, offset, same, middle)
  end

  # ── The zone database ─────────────────────────────────────────────────
  #
  # Tempo is time zone database agnostic: it asks the `Calendar.TimeZoneDatabase`
  # the application configures (`:ex_tempo, :time_zone_database`, else Elixir's
  # own). Before 0001-01-01 no rule exists, and the database is not asked:
  # the offset is zero. With Elixir's UTC-only default, any zone name is
  # accepted at construction, and the operations that need the zone's rules
  # surface their own errors.

  # Gregorian seconds at 0001-01-01T00:00:00, the floor below which no IANA rule exists.
  @year_one_seconds :calendar.datetime_to_gregorian_seconds({{1, 1, 1}, {0, 0, 0}})
  @before_year_one %{utc_offset: 0, std_offset: 0, zone_abbr: "LMT"}
  @probe_seconds :calendar.datetime_to_gregorian_seconds({{2020, 1, 1}, {0, 0, 0}})

  @doc "The `Calendar.TimeZoneDatabase` Tempo asks."
  @spec database() :: Calendar.time_zone_database()
  def database do
    Application.get_env(:ex_tempo, :time_zone_database) || Calendar.get_time_zone_database()
  end

  @doc "Whether the database knows a zone; with no database configured, every name is accepted."
  @spec exists?(String.t()) :: boolean()
  def exists?(name) when is_binary(name) do
    case database().time_zone_period_from_utc_iso_days(iso_days(@probe_seconds), name) do
      {:ok, _period} -> true
      {:error, :utc_only_time_zone_database} -> true
      {:error, _reason} -> false
    end
  end

  defp period_at_utc(_name, utc_seconds) when utc_seconds < @year_one_seconds,
    do: {:ok, @before_year_one}

  defp period_at_utc(name, utc_seconds) do
    database().time_zone_period_from_utc_iso_days(iso_days(utc_seconds), name)
  end

  defp periods_at_wall(_name, wall_seconds) when wall_seconds < @year_one_seconds,
    do: {:ok, @before_year_one}

  defp periods_at_wall(name, wall_seconds) do
    {{year, month, day}, {hour, minute, second}} =
      :calendar.gregorian_seconds_to_datetime(wall_seconds)

    naive = NaiveDateTime.new!(year, month, day, hour, minute, second)
    database().time_zone_periods_from_wall_datetime(naive, name)
  end

  defp iso_days(seconds),
    do: {div(seconds, 86_400), {rem(seconds, 86_400) * @second, 86_400 * @second}}

  # The database answers an offset in whole seconds.
  defp offset(%{utc_offset: utc_offset, std_offset: std_offset}),
    do: whole(utc_offset + std_offset) * @second

  defp whole(value) when is_integer(value), do: value
  defp seconds(tick), do: Integer.floor_div(tick, @second)
end
