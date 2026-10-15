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

  # A named time zone or a fixed offset, as an IXDTF suffix writes one. A
  # tick is a microsecond since 0000-01-01T00:00:00, which is Elixir's
  # ISO-day epoch and Erlang's Gregorian-seconds epoch alike.
  #
  # Every question of a named zone is answered from the table of its
  # changes (`Tempo.Zone.Table`), built once from the database and kept for
  # every process: the offset at a tick, the stretches of one offset about a
  # wall reading, the first change in a span. The database is read there and
  # nowhere else. Each question takes the table once, and the helpers that
  # answer it take the table from it.
  #
  # A wall reading has one offset; none, where the clock skips it going
  # forward; or two, where the clock shows it twice going back. A value is
  # placed by its written shift where it has one, else by the one offset,
  # else by the first of the two. A reading the clock skips is refused when
  # a value is built (`Tempo.Validate`); where a span's end falls in one,
  # the end is read on the clock before the change, as the hour it closes
  # was.

  alias Tempo.Zone.Table
  alias Tempo.ZoneError

  @enforce_keys []
  defstruct [:name, :offset, critical: false]

  @second 1_000_000
  @day 86_400 * @second

  # Gregorian seconds at 2020-01-01, a tick at which every zone the database
  # knows has a period: where a name is checked against the database.
  @probe_seconds :calendar.datetime_to_gregorian_seconds({{2020, 1, 1}, {0, 0, 0}})

  @typedoc "A zone: an IANA name, or a fixed offset in minutes from UTC (`[+05:30]`), never both."
  @type t :: Tempo.zone()

  @type tick :: integer()

  @type shift :: Tempo.shift()

  @doc """
  A named zone, checked against the zone database. A name is refused where
  no database is configured that has zones (Elixir's UTC-only default), as
  every reading in the zone needs its rules.
  """
  @spec named(String.t(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def named(name, options \\ []) when is_binary(name) do
    case known(name) do
      :ok -> {:ok, %__MODULE__{name: name, critical: Keyword.get(options, :critical, false)}}
      {:error, reason} -> {:error, ZoneError.exception(zone: name, reason: reason)}
    end
  end

  @doc """
  A zone as IXDTF writes one in a suffix: a name the database knows
  (`"Europe/Paris"`), or a fixed offset (`"+02:00"`).
  """
  @spec written(String.t()) :: {:ok, t()} | {:error, Exception.t()}
  def written(<<sign, hours::binary-size(2), ":", minutes::binary-size(2)>> = text)
      when sign in [?+, ?-] do
    case {Integer.parse(hours), Integer.parse(minutes)} do
      {{h, ""}, {m, ""}} when m < 60 ->
        {:ok, fixed(if(sign == ?-, do: -1, else: 1) * (h * 60 + m))}

      _not_an_offset ->
        named(text)
    end
  end

  def written(name) when is_binary(name), do: named(name)

  @doc "A zone of a fixed offset, in minutes from UTC."
  @spec fixed(integer()) :: %__MODULE__{name: nil, offset: integer(), critical: false}
  def fixed(minutes) when is_integer(minutes), do: %__MODULE__{offset: minutes}

  @doc "An offset in ticks as a written shift: five hours behind UTC is `[hour: -5, minute: 0]`."
  @spec shift_of(tick()) :: [
          {:hour, integer()} | {:minute, integer()} | {:second, integer()},
          ...
        ]
  # No shift from UTC is held as it is read from `Z`.
  def shift_of(0), do: [hour: 0]

  def shift_of(offset) do
    seconds = div(abs(offset), @second)
    units = [hour: div(seconds, 3600), minute: rem(div(seconds, 60), 60)]

    # An offset of a local mean time has seconds (`-07:52:58`), and keeps them.
    units = if rem(seconds, 60) == 0, do: units, else: units ++ [second: rem(seconds, 60)]
    signed(units, offset < 0)
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

  @doc """
  A shift written in numbers, as it is held. An offset of nothing ahead of
  UTC (`+00:00`, `Z0H`) says the local time is UTC's, and is held apart
  from `Z`, which says no local time: `[hour: 0, minute: 0]`. One of
  nothing behind (`-00:00`) is `Z`, as RFC 9557 section 2 has it.
  """
  @spec numeric(shift(), boolean()) :: shift()
  def numeric(units, behind?) do
    case {Enum.all?(units, fn {_unit, value} -> value == 0 end), behind?} do
      {true, true} -> [hour: 0]
      {true, false} -> [hour: 0, minute: 0]
      {false, _} -> signed(units, behind?)
    end
  end

  @doc "Whether a shift asserts a local time: any but `Z`, which names UTC and no offset of a place."
  @spec asserted?(shift() | nil) :: boolean()
  def asserted?(shift), do: shift not in [nil, [hour: 0]]

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

  # ── Wall readings ─────────────────────────────────────────────────────

  @doc "The offsets, in ticks, a wall reading has in a zone: one, none in a gap, two in a fold."
  @spec offsets_at_wall(t(), tick()) ::
          [tick()] | {:gap, before_change :: tick(), after_change :: tick()}
  def offsets_at_wall(%__MODULE__{offset: minutes}, _wall) when is_integer(minutes),
    do: [minutes * 60 * @second]

  def offsets_at_wall(%__MODULE__{name: name}, wall),
    do: offsets_at_wall_in(table(name, wall + @day), wall)

  # A wall reading is shown at the offset of each stretch of the clock
  # within a day either side of it (an offset is less than a day) in which
  # the moment it gives lies: one, both of two where the clock goes back,
  # or neither where it goes forward.
  defp offsets_at_wall_in(table, wall) do
    stretches = Table.stretches(table, wall - @day, wall + @day)

    case shown_in(stretches, wall) do
      [] -> skipped_by(stretches, wall, table.name)
      shown -> shown
    end
  end

  # The offsets at which the reading is shown, in the order of the moments
  # it is shown at.
  defp shown_in(stretches, wall) do
    for {start, stop, offset} <- stretches,
        moment = wall - offset,
        start == nil or moment >= start,
        stop == nil or moment < stop,
        do: offset
  end

  # The change that skips the reading: the one whose clock goes forward
  # over it.
  defp skipped_by(stretches, wall, name) do
    stretches
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [{_, change, before}, {change, _, later}] ->
      if before < later and change + before <= wall and wall < change + later,
        do: {:gap, before, later}
    end)
    |> case do
      nil -> raise ArgumentError, "the table of #{name} shows no reading at wall tick #{wall}"
      {:gap, before, later} -> {:gap, whole(before), whole(later)}
    end
  end

  @doc """
  Whether a zone's clock skips a whole day, as Samoa's skipped the 30th of
  December 2011: a day no reading of which is ever shown.
  """
  @spec day_skipped?(t() | nil, shift() | nil, integer()) :: boolean()
  def day_skipped?(%__MODULE__{name: name}, nil, day) when is_binary(name),
    do: days_skipped_in(table(name, (day + 2) * @day), day, day + 1) != []

  def day_skipped?(_zone, _shift, _day), do: false

  @doc """
  The days of a span of days, `[first, after_last)` on the day scale, that
  a zone's clock skips whole: those over which a change of the clock goes
  forward from before the day's first reading to after its last.
  """
  @spec days_skipped(t() | nil, shift() | nil, integer(), integer()) :: [integer()]
  def days_skipped(%__MODULE__{name: name}, nil, first, after_last) when is_binary(name),
    do: days_skipped_in(table(name, (after_last + 1) * @day), first, after_last)

  def days_skipped(_zone, _shift, _first, _after_last), do: []

  defp days_skipped_in(table, first, after_last) do
    table
    |> Table.stretches(first * @day - @day, after_last * @day + @day)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn
      # The days whose every reading, from the first to the last, the
      # change leaps over: from the day after the one the clock leaves to
      # the day before the one it lands in.
      [{_, change, before}, {change, _, later}] when before < later ->
        from = max(Integer.floor_div(change + before - 1, @day) + 1, first)
        to = min(Integer.floor_div(change + later, @day), after_last)
        Enum.to_list(from..(to - 1)//1)

      _back_or_none ->
        []
    end)
  end

  @doc "Whether a zone's clock skips a wall reading."
  @spec skipped?(t(), tick()) :: boolean()
  def skipped?(%__MODULE__{} = zone, wall), do: match?({:gap, _, _}, offsets_at_wall(zone, wall))

  # ── Offsets and moments ───────────────────────────────────────────────

  @doc "The offset, in ticks, a zone has at a UTC tick."
  @spec offset_at_utc(t(), tick()) :: tick()
  def offset_at_utc(%__MODULE__{offset: minutes}, _utc) when is_integer(minutes),
    do: minutes * 60 * @second

  def offset_at_utc(%__MODULE__{name: name}, utc), do: Table.offset_at(table(name, utc), utc)

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
  A value, a container or a frame at the showing the clock is at a UTC
  tick: with the shift the clock has there where the reading it shows is
  the second of two, as the clock goes back, and as it is where the reading
  is the first or only one. A reading written with no shift is read at its
  first showing, so the second carries the shift that says which it is.
  """
  @spec at_showing(shown, t() | nil, tick()) :: shown
        when shown: %{required(:shift) => term(), optional(atom()) => term()}
  def at_showing(%{shift: _} = term, %__MODULE__{name: name}, utc) when is_binary(name) do
    table = table(name, utc + 2 * @day)
    offset = Table.offset_at(table, utc)

    case offsets_at_wall_in(table, utc + offset) do
      [first, ^offset] when first != offset -> %{term | shift: shift_of(offset)}
      _first_or_only -> term
    end
  end

  def at_showing(term, _zone, _utc), do: term

  @doc """
  The shift of the second showing of a wall reading a zone's clock shows
  twice, as it goes back; `nil` for a reading it shows once or skips.
  """
  @spec second_showing_of(t(), tick()) :: shift() | nil
  def second_showing_of(%__MODULE__{name: name} = zone, wall) when is_binary(name) do
    case offsets_at_wall(zone, wall) do
      [_first, second] -> shift_of(second)
      _once_or_skipped -> nil
    end
  end

  def second_showing_of(_zone, _wall), do: nil

  @doc """
  The UTC tick at which a zone's clock first shows a reading or, where the
  clock skips it, the first reading after it: the moment the clock goes
  forward. An hour whose start is skipped is shown from there, where a part
  of it is shown at all.
  """
  @spec first_shown(t(), tick()) :: tick()
  def first_shown(%__MODULE__{name: name}, wall) when is_binary(name) and is_integer(wall) do
    table = table(name, wall + @day)

    case offsets_at_wall_in(table, wall) do
      {:gap, before, after_change} ->
        first_change_in(table, wall - after_change, wall - before)

      # A whole number of ticks, said so for the analysis of the types,
      # which does not carry a list's element type out of a comprehension.
      [offset | _] ->
        wall - whole(offset)
    end
  end

  def first_shown(zone, wall) when is_integer(wall), do: utc_of_wall(zone, nil, wall)

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
  def shown_from(%__MODULE__{name: name}, shift, wall, step) when is_binary(name) do
    offset = shift_ticks(shift)
    written = wall - offset
    table = table(name, written + step)
    before = Table.offset_at(table, written)

    cond do
      before == offset ->
        written

      Table.offset_at(table, written + step - 1) == offset ->
        first_change_in(table, written, written + step)

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
  def unit_end(%__MODULE__{name: name}, shift, utc, step) when is_binary(name) do
    table = table(name, utc + 2 * step + @day)
    offset = Table.offset_at(table, utc)

    if shift == nil or shift_ticks(shift) == offset,
      do: shown_until(table, offset, utc, step),
      else: utc + step
  end

  def unit_end(_zone, _shift, utc, step) when is_integer(utc) and is_integer(step),
    do: utc + step

  @doc """
  The offset a named zone's clock keeps through a span, where it keeps one:
  `{:ok, offset}`, or `:changes` where the clock changes within it. A shift
  that is not the zone's own says a moment the clock did not show so, and
  is answered as a change, as `unit_end/4` takes it.
  """
  @spec steady_offset(t(), shift() | nil, tick(), tick()) :: {:ok, tick()} | :changes
  def steady_offset(%__MODULE__{name: name}, shift, start, stop) when is_binary(name) do
    case Table.steady(table(name, stop), start, stop) do
      {:ok, offset} when shift == nil -> {:ok, offset}
      {:ok, offset} -> if shift_ticks(shift) == offset, do: {:ok, offset}, else: :changes
      :changes -> :changes
    end
  end

  def steady_offset(_zone, _shift, _start, _stop), do: :changes

  # A shift written beside a zone says which of two showings a reading is,
  # and is then the zone's offset there; one that is not the zone's gives a
  # moment the zone's clock did not show so, which is one unit long.
  defp shown_until(table, offset, utc, step) do
    unit_start = Integer.floor_div(utc + offset, step) * step
    whole = unit_start + step - offset

    if Table.offset_at(table, whole) == offset,
      do: whole,
      else: ended_by_a_change(table, first_change_in(table, utc, whole), unit_start, step)
  end

  # The clock changes at a tick within the unit, or as it would have ended:
  # the unit runs on where the clock then shows a later part of it.
  defp ended_by_a_change(table, change, unit_start, step) do
    offset = Table.offset_at(table, change)
    shown = change + offset

    if shown > unit_start and shown < unit_start + step,
      do: shown_until(table, offset, change, step),
      else: change
  end

  # The first tick after `from`, and no later than `to`, at which the zone's
  # offset changes; `to` where it does not change by then.
  defp first_change_in(table, from, to) do
    case Table.first_change(table, from, to) do
      nil -> to
      change -> change
    end
  end

  defp table(name, until), do: Table.of(name, database(), until)

  # ── The zone database ─────────────────────────────────────────────────
  #
  # Tempo asks the `Calendar.TimeZoneDatabase` the application configures
  # (`:ex_tempo, :time_zone_database`, else Elixir's own), through the table
  # of each zone's changes, and where neither names one it asks `tz`, which
  # comes with it (decision 77). A database configured that knows only UTC
  # refuses a zone name other than UTC's where it is given, as `:no_database`.

  @doc "The `Calendar.TimeZoneDatabase` Tempo asks: the one configured, else the `tz` package's."
  @spec database() :: Calendar.time_zone_database()
  # Read as Erlang reads it, on every question of a zone: Tempo's own
  # setting, else Elixir's where it is other than Elixir's own default
  # (`Calendar.put_time_zone_database/1`), else `tz`. Elixir sets its
  # UTC-only default in its application env, so that default is not read
  # as a choice; a UTC-only database chosen on purpose is set under
  # `:ex_tempo`.
  def database do
    case :application.get_env(:ex_tempo, :time_zone_database) do
      {:ok, database} when database != nil -> database
      _none -> elixirs_database()
    end
  end

  defp elixirs_database do
    case :application.get_env(:elixir, :time_zone_database) do
      {:ok, database} when database != Calendar.UTCOnlyTimeZoneDatabase -> database
      _default -> Tz.TimeZoneDatabase
    end
  end

  @doc "Whether the database knows a zone."
  @spec exists?(String.t()) :: boolean()
  def exists?(name) when is_binary(name), do: known(name) == :ok

  defp known(name) do
    case database().time_zone_period_from_utc_iso_days(iso_days(@probe_seconds), name) do
      {:ok, _period} -> :ok
      {:error, reason} -> {:error, Table.error_reason(reason)}
    end
  end

  defp iso_days(seconds),
    do: {div(seconds, 86_400), {rem(seconds, 86_400) * @second, 86_400 * @second}}

  defp whole(value) when is_integer(value), do: value
end
