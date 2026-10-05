defmodule Tempo.TimeZoneDatabase do
  @moduledoc """
  Access to the time zone database Tempo uses for zone validation,
  offset resolution, and DST-aware arithmetic.

  Tempo is **time zone database agnostic**: it works against the
  standard `Calendar.TimeZoneDatabase` behaviour rather than any
  specific implementation. The database is resolved, in order, from:

  1. The `:ex_tempo, :time_zone_database` application environment.

  2. Elixir's own configured database, `Calendar.get_time_zone_database/0`
     (set with `config :elixir, :time_zone_database, ...` or
     `Calendar.put_time_zone_database/1`).

  Any implementation works — [`tz`](https://hex.pm/packages/tz),
  [`tzdata`](https://hex.pm/packages/tzdata),
  [`time_zone_info`](https://hex.pm/packages/time_zone_info), or
  [`zoneinfo`](https://hex.pm/packages/zoneinfo). Configure one at
  boot, for example:

      config :elixir, :time_zone_database, Tz.TimeZoneDatabase

  When no database is configured (Elixir's default is
  `Calendar.UTCOnlyTimeZoneDatabase`), parsing remains fully
  functional: zone names in IXDTF suffixes are accepted without
  registry validation, and only the operations that genuinely need
  zone rules — UTC projection, `shift_zone/2`, DST-aware walks —
  degrade or error.

  """

  @typedoc """
  A time zone period as returned by the `Calendar.TimeZoneDatabase`
  behaviour — at minimum `:utc_offset`, `:std_offset`, and
  `:zone_abbr`.
  """
  @type period :: Calendar.TimeZoneDatabase.time_zone_period()

  # Wall/UTC seconds at 0001-01-01T00:00:00 — the floor below which no
  # IANA rule exists (local-mean-time era). Pre-common-era instants
  # skip the database entirely: they precede every rule, and some
  # database internals crash on negative years.
  @gregorian_seconds_year_1 :calendar.datetime_to_gregorian_seconds({{1, 1, 1}, {0, 0, 0}})
  @pre_ce_period %{utc_offset: 0, std_offset: 0, zone_abbr: "LMT"}

  @seconds_per_day 86_400
  @microseconds_per_day 86_400_000_000
  @microseconds_per_second 1_000_000

  # A fixed modern instant used only to probe whether a zone name is
  # known to the database (any instant would do).
  @zone_probe_seconds :calendar.datetime_to_gregorian_seconds({{2020, 1, 1}, {0, 0, 0}})

  @doc """
  The `Calendar.TimeZoneDatabase` implementation Tempo resolves for
  this call — see the module doc for the resolution order.

  ### Returns

  * A module implementing `Calendar.TimeZoneDatabase`.

  """
  @spec database :: Calendar.time_zone_database()
  def database do
    Application.get_env(:ex_tempo, :time_zone_database) || Calendar.get_time_zone_database()
  end

  @doc """
  Return whether `zone` is a time zone known to the configured
  database.

  When no real database is configured (the resolver answers with
  Elixir's UTC-only default), any syntactically valid zone name is
  accepted — parsing must not depend on zone data being present;
  operations that need the zone's rules surface their own errors.

  ### Arguments

  * `zone` is an IANA zone name (`"Europe/Paris"`, …).

  ### Returns

  * `true` or `false`.

  """
  @spec zone_exists?(String.t()) :: boolean()
  def zone_exists?(zone) when is_binary(zone) do
    case database().time_zone_period_from_utc_iso_days(iso_days(@zone_probe_seconds), zone) do
      {:ok, _period} -> true
      {:error, :utc_only_time_zone_database} -> true
      {:error, _reason} -> false
    end
  end

  @doc """
  The period in effect in `zone` at a UTC instant given as gregorian
  seconds (seconds since year 0, `:calendar`'s epoch).

  Pre-common-era instants return a zero-offset local-mean-time
  period without consulting the database.

  ### Arguments

  * `zone` is an IANA zone name.

  * `utc_seconds` is the instant in gregorian seconds, UTC.

  ### Returns

  * `{:ok, period}` — a UTC instant is never ambiguous.

  * `{:error, reason}` from the database (unknown zone, or no real
    database configured).

  """
  @spec period_at_utc(String.t(), integer()) :: {:ok, period()} | {:error, term()}
  def period_at_utc(_zone, utc_seconds) when utc_seconds < @gregorian_seconds_year_1 do
    {:ok, @pre_ce_period}
  end

  def period_at_utc(zone, utc_seconds) do
    database().time_zone_period_from_utc_iso_days(iso_days(utc_seconds), zone)
  end

  @doc """
  The period(s) matching a wall-clock reading in `zone`, given as
  gregorian seconds.

  Returns the standard behaviour shapes: `{:ok, period}` for an
  unambiguous reading, `{:ambiguous, first, second}` for a DST
  fall-back, `{:gap, ...}` for a spring-forward reading that does
  not exist, or `{:error, reason}`. Pre-common-era readings return
  `{:ok, local-mean-time}` without consulting the database.

  ### Arguments

  * `zone` is an IANA zone name.

  * `wall_seconds` is the wall-clock reading in gregorian seconds.

  ### Returns

  * `{:ok, period}` | `{:ambiguous, period, period}` |
    `{:gap, {period, limit}, {period, limit}}` | `{:error, reason}`.

  """
  @spec period_at_wall(String.t(), integer()) ::
          {:ok, period()}
          | {:ambiguous, period(), period()}
          | {:gap, {period(), Calendar.naive_datetime()}, {period(), Calendar.naive_datetime()}}
          | {:error, term()}
  def period_at_wall(_zone, wall_seconds) when wall_seconds < @gregorian_seconds_year_1 do
    {:ok, @pre_ce_period}
  end

  def period_at_wall(zone, wall_seconds) do
    {{year, month, day}, {hour, minute, second}} =
      :calendar.gregorian_seconds_to_datetime(wall_seconds)

    naive = NaiveDateTime.new!(year, month, day, hour, minute, second)
    database().time_zone_periods_from_wall_datetime(naive, zone)
  end

  @doc """
  The calendar days a zone leaves out: the days its wall clock never
  showed, where the zone moved across the date line.

  Samoa had no 30 December 2011, and Manila no 31 December 1844. A
  value that names such a day names no time, and nothing steps onto
  it or walks through it.

  The days are found once for each zone and kept, since a zone has
  none or one and asking the database of every day walked would cost
  more than the walk. A zone's offset at the start of each decade
  from 1800 to 2100 shows the years it moved a day ahead, and the
  days of those years are asked of the database. They are kept for
  as long as the system runs, so a database that learns of a new
  move across the date line is asked again only when it restarts.

  ### Arguments

  * `zone` is an IANA zone name.

  ### Returns

  * A list of `{year, month, day}` Gregorian dates, empty for nearly
    every zone, and for an unknown zone or with no database
    configured.

  ### Examples

      iex> Tempo.TimeZoneDatabase.days_left_out("Etc/UTC")
      []

  """
  @spec days_left_out(String.t()) :: [:calendar.date()]
  def days_left_out(zone) when is_binary(zone) do
    key = {__MODULE__, :days_left_out, zone}

    case :persistent_term.get(key, nil) do
      nil -> found_days_left_out(key, zone, database())
      days -> days
    end
  end

  # With no database configured nothing is known of a zone, and nothing is
  # kept, so that one configured later is asked. Nor is anything kept for a
  # name the database does not know.
  defp found_days_left_out(_key, _zone, Calendar.UTCOnlyTimeZoneDatabase), do: []

  defp found_days_left_out(key, zone, _database) do
    if zone_exists?(zone), do: kept_days_left_out(key, zone), else: []
  end

  defp kept_days_left_out(key, zone) do
    days = find_days_left_out(zone)
    :persistent_term.put(key, days)
    days
  end

  # The decades a zone's offset is scanned over, and the least a move across
  # the date line changes it by: such a move is a whole day, and no change
  # for daylight saving or of a zone's standard time comes near half of one.
  # A move ahead stays in the zone's offset, so the decades are asked first
  # and then the years of a decade that holds one.
  @decades_scanned 1800..2090//10
  @half_a_day div(@seconds_per_day, 2)

  defp find_days_left_out(zone) do
    for decade <- @decades_scanned,
        moved_a_day_ahead?(zone, decade, decade + 10),
        year <- decade..(decade + 9),
        moved_a_day_ahead?(zone, year, year + 1),
        day <- days_of(year),
        left_out?(zone, day),
        do: day
  end

  defp moved_a_day_ahead?(zone, from_year, to_year),
    do: offset_at_start(zone, to_year) - offset_at_start(zone, from_year) >= @half_a_day

  defp offset_at_start(zone, year) do
    case period_at_utc(zone, :calendar.datetime_to_gregorian_seconds({{year, 1, 1}, {0, 0, 0}})) do
      {:ok, period} -> total_offset(period)
      {:error, _reason} -> 0
    end
  end

  defp days_of(year) do
    first = :calendar.datetime_to_gregorian_seconds({{year, 1, 1}, {0, 0, 0}})

    for day <- 0..365,
        {date, _midnight} =
          :calendar.gregorian_seconds_to_datetime(first + day * @seconds_per_day),
        elem(date, 0) == year,
        do: date
  end

  # A day is left out where one gap holds its first reading and its last.
  defp left_out?(zone, date) do
    case gap_at(zone, {date, {0, 0, 0}}) do
      nil -> false
      gap -> gap == gap_at(zone, {date, {23, 59, 59}})
    end
  end

  defp gap_at(zone, reading) do
    case period_at_wall(zone, :calendar.datetime_to_gregorian_seconds(reading)) do
      {:gap, {_before, starts}, {_after, ends}} -> {starts, ends}
      _shown_or_not_known -> nil
    end
  end

  @doc """
  The total UTC offset of a period in seconds — the standard offset
  plus any daylight-saving adjustment.

  ### Arguments

  * `period` is a `t:period/0`.

  ### Returns

  * An offset in seconds. Always an integer in practice; the spec is
    `number()` because the behaviour's period field specs admit floats.

  """
  @spec total_offset(period()) :: number()
  def total_offset(%{utc_offset: utc_offset, std_offset: std_offset}) do
    utc_offset + std_offset
  end

  defp iso_days(gregorian_seconds) do
    {Integer.floor_div(gregorian_seconds, @seconds_per_day),
     {Integer.mod(gregorian_seconds, @seconds_per_day) * @microseconds_per_second,
      @microseconds_per_day}}
  end
end
