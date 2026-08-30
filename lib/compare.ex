defmodule Tempo.Compare do
  @moduledoc """
  Shared comparison primitives for Tempo values.

  Set operations, enumeration, and IntervalSet construction all
  need to compare two time keyword lists as start-moments on the
  time line. This module is the single place that definition
  lives. The comparison treats missing trailing units as their
  unit minimum — so `[year: 2022]` (which means "start of 2022")
  compares correctly against `[year: 2022, month: 6]` (which
  means "start of June 2022") without ambiguity.

  For set operations that span timezones, `to_utc_seconds/1`
  projects a zoned `%Tempo{}` into gregorian-seconds-since-UTC
  epoch so operands in different zones can share a total order.
  The projection is computed on demand and never cached — that
  policy decision was made in the implicit-to-explicit plan and
  revisited in the set-operations plan.

  The same projection makes comparison calendar-independent:
  when two values are in different calendars, each is routed
  through its calendar's date→absolute-day conversion (the
  `date_to_iso_days` round-trip) before comparison, so a Hebrew
  and a Gregorian date order by their true instants rather than
  by their raw numeric components. Same-calendar comparison keeps
  the fast structural path on the `:time` lists.

  """

  alias Calendar.ISO
  alias Tempo.Duration
  alias Tempo.TimeZoneDatabase
  alias Tempo.ZoneOffsetMismatchError

  @doc """
  Compare two time keyword lists as start-moments on the time
  line.

  Missing trailing units are filled with their unit minimum
  (`:month` / `:day` / `:week` / `:day_of_year` / `:day_of_week`
  count from 1; everything else counts from 0). Both lists must
  be sorted descending-by-unit — the invariant the tokenizer and
  `Unit.sort/2` maintain.

  Mismatched units at the same position (e.g. `:week` vs
  `:month`) fall through to `:eq` as a conservative bailout. A
  well-formed comparison has operands using the same unit
  vocabulary.

  ### Arguments

  * `a` and `b` are keyword lists like `[year: 2022, month: 6]`.

  ### Returns

  * `:lt` when `a` is earlier than `b`.

  * `:gt` when `a` is later than `b`.

  * `:eq` when they are the same start-moment, or when mismatched
    unit vocabularies prevent a meaningful order.

  ### Examples

      iex> Tempo.Compare.compare_time([year: 2022], [year: 2022, month: 6])
      :lt

      iex> Tempo.Compare.compare_time([year: 2022, month: 6, day: 15], [year: 2022, month: 6, day: 15])
      :eq

      iex> Tempo.Compare.compare_time([year: 2023], [year: 2022, month: 12])
      :gt

  """
  @spec compare_time(keyword(), keyword()) :: :lt | :eq | :gt
  def compare_time([], []), do: :eq

  # Microseconds compare by VALUE only. Precision (digit count) sets
  # the interval width, not the instant ordering: `{120000, 2}` (.12)
  # and `{120000, 3}` (.120) denote the same start moment, so they
  # compare equal here. Generic tuple comparison would (wrongly) order
  # them by precision, so these clauses precede the generic ones.
  def compare_time([{:microsecond, {v1, _p1}} | t1], [{:microsecond, {v2, _p2}} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  def compare_time([{:microsecond, {v, _p}} | rest], []) do
    if v > 0, do: :gt, else: compare_time(rest, [])
  end

  def compare_time([], [{:microsecond, {v, _p}} | rest]) do
    if v > 0, do: :lt, else: compare_time([], rest)
  end

  def compare_time([{unit, v} | rest], []) do
    min = unit_minimum(unit)

    cond do
      v < min -> :lt
      v > min -> :gt
      true -> compare_time(rest, [])
    end
  end

  def compare_time([], [{unit, v} | rest]) do
    min = unit_minimum(unit)

    cond do
      min < v -> :lt
      min > v -> :gt
      true -> compare_time([], rest)
    end
  end

  def compare_time([{unit, v1} | t1], [{unit, v2} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  def compare_time(_, _), do: :eq

  @doc """
  The start-of-unit minimum — 1 for `:month`, `:day`, `:week`,
  `:day_of_year`, `:day_of_week`; 0 for everything else.

  Exposed on `Tempo.Compare` and `Tempo.Math` as the same
  definition (both modules re-export via delegation).

  """
  @spec unit_minimum(atom()) :: integer()
  def unit_minimum(:month), do: 1
  def unit_minimum(:day), do: 1
  def unit_minimum(:week), do: 1
  def unit_minimum(:day_of_year), do: 1
  def unit_minimum(:day_of_week), do: 1
  def unit_minimum(_), do: 0

  @doc """
  Return `:earlier`, `:later`, or `:same` for two `%Tempo{}`
  endpoints comparing by their UTC-projected start-moments.

  When both Tempos share a zone (or both have `nil` zone info),
  this reduces to `compare_time/2` on their `:time` lists with a
  renamed return. When zones differ, both sides are projected to
  UTC via `to_utc_seconds/1` for a common reference frame.

  ### Arguments

  * `a` and `b` are `%Tempo{}` structs, typically interval
    endpoints.

  ### Returns

  * `:earlier`, `:later`, or `:same`.

  """
  @spec compare_endpoints(Tempo.t(), Tempo.t()) :: :earlier | :later | :same
  def compare_endpoints(%Tempo{} = a, %Tempo{} = b) do
    a = %{a | time: drop_margin_of_error(a.time)}
    b = %{b | time: drop_margin_of_error(b.time)}

    # Structural comparison of the time lists is calendar-blind — `5786`
    # (Hebrew) would read as later than `2025` (Gregorian) — so it is only
    # valid within a single calendar. It is also axis-blind: a week-axis
    # list (`[year, week]`) and a month-axis list (`[year, month, day]`)
    # share only the `:year` head, so the structural walk degenerates to
    # comparing years alone and mixed-axis endpoints all read `:same`.
    # Values in different calendars, or anchored values on different
    # sub-year axes, are compared by projecting both to the shared
    # absolute UTC frame, which resolves each axis to a real date.
    if a.calendar == b.calendar and zones_compatible?(a, b) and
         comparable_axes?(a.time, b.time) do
      case compare_time(a.time, b.time) do
        :lt -> :earlier
        :gt -> :later
        :eq -> :same
      end
    else
      compare_via_utc(a, b)
    end
  end

  # Two anchored time lists on different sub-year axes (week vs month vs
  # ordinal day) cannot be compared structurally — route them through the
  # UTC projection instead. Non-anchored lists stay on the structural
  # path: they have no year to project through, and the set-operations
  # layer already rejects cross-axis non-anchored operands upstream.
  defp comparable_axes?(time_a, time_b) do
    cond do
      not (Keyword.has_key?(time_a, :year) and Keyword.has_key?(time_b, :year)) -> true
      date_axis(time_a) == :none or date_axis(time_b) == :none -> true
      true -> date_axis(time_a) == date_axis(time_b)
    end
  end

  # `:week` marks the week-of-year axis only when no `:month` qualifies
  # it — `[year, month, week]` is a week *of the month*, which lives on
  # the month axis and compares structurally against month-axis dates.
  defp date_axis(time) do
    cond do
      Keyword.has_key?(time, :month) -> :month
      Keyword.has_key?(time, :week) -> :week
      Keyword.has_key?(time, :day) or Keyword.has_key?(time, :day_of_year) -> :ordinal
      true -> :none
    end
  end

  @doc """
  Compare two Tempo values, returning stdlib's ternary
  `:lt | :eq | :gt`.

  This is the sorter-module callback Elixir's `Enum` and `List`
  functions look for, so `Tempo` can be passed wherever `Date`,
  `Time`, or `DateTime` would be:

      Enum.sort_by(sessions, & &1.starts_at, Tempo)
      Enum.max_by(bookings, & &1.window.from, Tempo)

  Use `Tempo.relation/2` instead when the question is *how* two
  intervals relate — this function collapses Allen's 13 relations to
  a total order, which is what sorting needs and reasoning does not.

  ### Comparison is crisp

  A total order cannot express doubt, so uncertainty is dropped before
  comparing: `~o"1984?"` and `~o"1984"` compare `:eq`, and a margin of
  error is discarded the same way `compare_endpoints/2` discards it.
  When the uncertainty is the point, reach for `Tempo.certainly_before?/2`
  or `Tempo.possibly_before?/2` rather than this function.

  ### Arguments

  * `a` and `b` are two values of the same kind — both `t:Tempo.t/0`,
    both `t:Tempo.Duration.t/0`, or both `t:Tempo.Interval.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:relative_to` is a `t:Tempo.t/0` used to resolve
    calendar-dependent durations. `P1M` has no fixed length, so
    comparing it requires a date to measure that month against.

  ### Returns

  * `:lt`, `:eq`, or `:gt`.

  * Raises `ArgumentError` when the two values are of different kinds,
    or when a duration cannot be resolved to a fixed length and no
    `:relative_to` was given.

  ### Examples

  Tempo values compare as start-moments on the time line:

      iex> Tempo.compare(~o"2026-06-15", ~o"2026-06-16")
      :lt

      iex> Tempo.compare(~o"2026Y", ~o"2026-06")
      :lt

  Zones are resolved, so the same instant compares equal:

      iex> Tempo.compare(~o"2026-06-15T09:00:00Z", ~o"2026-06-15T10:00:00+01:00")
      :eq

  Which makes `Tempo` usable directly as a sorter:

      iex> [~o"2026-06-16", ~o"2026-06-15"]
      ...> |> Enum.sort(Tempo)
      [~o"2026Y6M15D", ~o"2026Y6M16D"]

  Durations compare by length:

      iex> Tempo.compare(~o"PT1H", ~o"PT90M")
      :lt

  Intervals compare by start, ties broken by end:

      iex> morning = Tempo.Interval.new!(from: ~o"2026-06-15T09:00", to: ~o"2026-06-15T10:00")
      iex> longer = Tempo.Interval.new!(from: ~o"2026-06-15T09:00", to: ~o"2026-06-15T11:00")
      iex> Tempo.compare(morning, longer)
      :lt

  """
  @spec compare(
          Tempo.t() | Tempo.Duration.t() | Tempo.Interval.t(),
          Tempo.t() | Tempo.Duration.t() | Tempo.Interval.t(),
          keyword()
        ) :: :lt | :eq | :gt
  def compare(a, b, options \\ [])

  def compare(%Tempo{} = a, %Tempo{} = b, _options) do
    a |> compare_endpoints(b) |> from_endpoint_order()
  end

  def compare(%Tempo.Duration{} = a, %Tempo.Duration{} = b, options) do
    with {:ok, a_seconds} <- Duration.to_unit(a, :second, options),
         {:ok, b_seconds} <- Duration.to_unit(b, :second, options) do
      from_magnitudes(a_seconds, b_seconds)
    else
      {:error, exception} -> raise exception
    end
  end

  def compare(%Tempo.Interval{} = a, %Tempo.Interval{} = b, options) do
    case compare_bound(a.from, b.from, :from, options) do
      :eq -> compare_bound(a.to, b.to, :to, options)
      order -> order
    end
  end

  def compare(a, b, _options) do
    raise ArgumentError,
          "cannot compare #{kind_of(a)} with #{kind_of(b)} — " <>
            "both values must be of the same kind"
  end

  defp from_endpoint_order(:earlier), do: :lt
  defp from_endpoint_order(:same), do: :eq
  defp from_endpoint_order(:later), do: :gt

  defp from_magnitudes(a, b) when a < b, do: :lt
  defp from_magnitudes(a, b) when a > b, do: :gt
  defp from_magnitudes(_a, _b), do: :eq

  # An unbounded `from` starts before every stated instant; an
  # unbounded `to` ends after every stated instant. Two unbounded
  # endpoints on the same side are indistinguishable.
  defp compare_bound(same, same, _side, _options), do: :eq
  defp compare_bound(:undefined, _b, :from, _options), do: :lt
  defp compare_bound(_a, :undefined, :from, _options), do: :gt
  defp compare_bound(:undefined, _b, :to, _options), do: :gt
  defp compare_bound(_a, :undefined, :to, _options), do: :lt
  defp compare_bound(nil, _b, :to, _options), do: :gt
  defp compare_bound(_a, nil, :to, _options), do: :lt
  defp compare_bound(a, b, _side, options), do: compare(a, b, options)

  defp kind_of(%Tempo{}), do: "a Tempo"
  defp kind_of(%Tempo.Duration{}), do: "a Tempo.Duration"
  defp kind_of(%Tempo.Interval{}), do: "a Tempo.Interval"
  defp kind_of(%Tempo.IntervalSet{}), do: "a Tempo.IntervalSet"
  defp kind_of(other), do: inspect(other)

  @doc """
  Drop the `margin_of_error` annotation from every component of a time
  keyword list.

  A margin of error (`2018±2`) is a crisp-inert uncertainty annotation
  stored as `{value, [margin_of_error: n]}`. Crisp comparison and
  materialisation operate on plain integers, so the annotation is dropped
  before those operations (leaving any other annotation, e.g.
  `significant_digits`, untouched). The margin is preserved on the caller's
  original value — only the comparison/materialisation copy is reduced to
  its crisp core. Graded, margin-aware relations are a future step.
  """
  def drop_margin_of_error(time) do
    Enum.map(time, fn
      {unit, {value, options}} when is_list(options) ->
        case Keyword.delete(options, :margin_of_error) do
          [] -> {unit, value}
          remaining -> {unit, {value, remaining}}
        end

      other ->
        other
    end)
  end

  # Two Tempos compare structurally (by wall clock) only when they share
  # the same frame — the same zone id AND the same numeric UTC offset. A
  # zoned value (`[Europe/Paris]`) resolves its offset on demand and
  # holds `shift: nil`, so two same-zone values stay structural. But two
  # fixed-offset values with different offsets (`+05:30` vs `+09:00`)
  # read one wall clock as two different instants, so they must project
  # to UTC; comparing their wall-clock lists directly would wrongly
  # report them equal.
  defp zones_compatible?(a, b), do: same_zone_id?(a, b) and same_offset?(a, b)

  defp same_zone_id?(%Tempo{extended: a}, %Tempo{extended: b}), do: zone_id(a) == zone_id(b)

  defp zone_id(nil), do: nil
  defp zone_id(%{zone_id: zone_id}), do: zone_id

  defp same_offset?(%Tempo{shift: a}, %Tempo{shift: b}),
    do: offset_minutes(a) == offset_minutes(b)

  defp offset_minutes(nil), do: nil

  defp offset_minutes(shift),
    do: Keyword.get(shift, :hour, 0) * 60 + Keyword.get(shift, :minute, 0)

  defp compare_via_utc(a, b) do
    a_secs = to_utc_seconds(a)
    b_secs = to_utc_seconds(b)

    cond do
      a_secs < b_secs -> :earlier
      a_secs > b_secs -> :later
      # Whole UTC seconds tie — break on the sub-second value. Zone
      # offsets are whole-minute, so the microsecond value is the same
      # in wall-clock and UTC frames; comparing the raw values is exact.
      true -> compare_microsecond_values(a, b)
    end
  end

  defp compare_microsecond_values(a, b) do
    case {microsecond_value(a), microsecond_value(b)} do
      {x, y} when x < y -> :earlier
      {x, y} when x > y -> :later
      _ -> :same
    end
  end

  defp microsecond_value(%Tempo{time: time}) do
    case Keyword.get(time, :microsecond) do
      {value, _precision} -> value
      nil -> 0
    end
  end

  @doc """
  Project a zoned `%Tempo{}` to UTC gregorian seconds since
  year 0 (matching Erlang's `:calendar.datetime_to_gregorian_seconds/1`
  epoch).

  The projection is per-call, never cached. When the configured
  time zone database is updated with new zone rules, the next call
  automatically uses them. Stored IntervalSet endpoints carry wall-clock + zone as
  authoritative — see `plans/set-operations.md` for the full
  rationale on why no UTC cache exists.

  ### Arguments

  * `tempo` is a `%Tempo{}` with at minimum year/month/day/hour/
    minute/second components. Missing components are padded with
    their unit minimum.

  ### Returns

  * `integer` — gregorian seconds since year 0 in UTC.

  ### Raises

  * `ArgumentError` when the Tempo has no `:year` component
    (non-anchored values can't be projected to a universal
    instant).

  """
  @spec to_utc_seconds(Tempo.t()) :: integer() | float()
  def to_utc_seconds(%Tempo{time: time, extended: extended, shift: shift, calendar: calendar}) do
    calendar = effective_calendar(calendar)
    year = Keyword.get(time, :year)

    if year == nil do
      raise ArgumentError,
            "Cannot project a non-anchored Tempo (no :year component) to a UTC " <>
              "instant. Non-anchored values live on the time-of-day axis; anchor " <>
              "them first via `Tempo.anchor/2` or supply a `bound:` option to the " <>
              "calling operation."
    end

    wall = wall_seconds(time, year, calendar)
    wall - resolve_offset_seconds(extended, shift, wall)
  end

  # The wall-clock instant as gregorian seconds (before any offset is
  # applied). Shared by `to_utc_seconds/1` and `validate_zone_offset/1`.
  # A non-Gregorian value's calendar components are converted to the
  # proleptic Gregorian frame first, so the projection lands on a true
  # absolute instant (and cross-calendar comparisons and durations are
  # correct); Gregorian values take the fast path unchanged.
  defp wall_seconds(time, year, calendar) do
    {year, month, day} = resolve_ymd(time, year, calendar)
    hour = Keyword.get(time, :hour, 0)
    minute = Keyword.get(time, :minute, 0)
    second = Keyword.get(time, :second, 0)

    # `Calendar.ISO.date_to_iso_days/3` shares Erlang's gregorian-days
    # epoch (0000-01-01 = day 0) but, unlike OTP ≤ 28's
    # `:calendar.datetime_to_gregorian_seconds/1`, accepts negative
    # (pre-common-era) years on every OTP — e.g. a value whose units
    # read as Hebrew year 2022 resolves to proleptic Gregorian −1738.
    ISO.date_to_iso_days(year, month, day) * 86_400 +
      hour * 3_600 + minute * 60 + second
  end

  @doc """
  Check that an IXDTF value's explicit numeric offset agrees with its
  IANA time zone at the value's wall instant.

  When a value carries both a numeric offset and a zone identifier (e.g.
  `2022-11-20T10:37:00+05:00[Europe/Paris]`), the offset is normally
  consulted only to disambiguate a DST fall-back — the zone otherwise
  wins. This check (RFC 9557 §4.2) flags the case where the stated
  offset matches no offset the zone actually uses at that instant.

  ### Arguments

  * `tempo` is a `t:Tempo.t/0`.

  ### Returns

  * `:ok` when the offset agrees with the zone, when there is nothing to
    check (no zone, or no explicit offset), or when the value is not
    anchored (no wall instant to evaluate against).

  * `{:error, t:Tempo.ZoneOffsetMismatchError.t/0}` when the stated
    offset disagrees with the zone.

  See `Tempo.validate_zone_offset/1`, which delegates here, for worked
  examples.

  """
  @spec validate_zone_offset(Tempo.t()) ::
          :ok | {:error, Tempo.ZoneOffsetMismatchError.t()}
  def validate_zone_offset(%Tempo{time: time, extended: extended, shift: shift} = tempo) do
    zone_id = extended && Map.get(extended, :zone_id)
    stated = explicit_offset_seconds(extended, shift)

    cond do
      is_nil(zone_id) or zone_id == "" -> :ok
      is_nil(stated) -> :ok
      not Tempo.anchored?(tempo) -> :ok
      true -> check_zone_offset(time, tempo.calendar, zone_id, stated)
    end
  end

  # Wall seconds at 0001-01-01T00:00:00 — the floor below which no
  # IANA rule exists (local mean time era) and below which some databases'
  # internals crash on OTP ≤ 28 (`:calendar.last_day_of_the_month/2`
  # rejects negative years). Pre-common-era instants skip the database
  # lookups entirely.
  @gregorian_seconds_year_1 :calendar.datetime_to_gregorian_seconds({{1, 1, 1}, {0, 0, 0}})

  defp check_zone_offset(time, calendar, zone_id, stated) do
    wall = wall_seconds(time, Keyword.get(time, :year), calendar)

    if wall < @gregorian_seconds_year_1 do
      # Pre-common-era: the IANA data has no rules to confirm or refute
      # the stated offset, so accept it rather than consult the database.
      :ok
    else
      do_check_zone_offset(wall, zone_id, stated)
    end
  end

  defp do_check_zone_offset(wall, zone_id, stated) do
    # A gap reading names no instant in the zone, so no offset can
    # agree with it — the empty candidate list falls through to the
    # mismatch error, preserving the pre-behaviour semantics.
    offsets =
      case TimeZoneDatabase.period_at_wall(zone_id, wall) do
        {:ok, period} ->
          [TimeZoneDatabase.total_offset(period)]

        {:ambiguous, first, second} ->
          [first, second] |> Enum.map(&TimeZoneDatabase.total_offset/1)

        _gap_or_error ->
          []
      end

    if stated in offsets do
      :ok
    else
      {:error,
       ZoneOffsetMismatchError.exception(
         zone_id: zone_id,
         stated_offset: stated,
         zone_offsets: offsets,
         wall_time: wall_seconds_to_iso(wall)
       )}
    end
  end

  defp wall_seconds_to_iso(wall) do
    {{y, mo, d}, {h, mi, s}} = :calendar.gregorian_seconds_to_datetime(wall)

    [y, mo, d, h, mi, s]
    |> then(&:io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", &1))
    |> IO.iodata_to_binary()
  end

  # Resolve the calendar `{year, month, day}` from the time list,
  # handling the three date representations Tempo stores:
  #
  #   * ISO week date — `[year, week, day_of_week]`. Week 01 is the
  #     week containing Jan 4 (ISO 8601-1 §5.2.3).
  #   * Ordinal date — `[year, day]` with `:day` holding the
  #     day-of-year and no `:month` (the absence of `:month` is the
  #     disambiguator, matching `Tempo.to_date/1`).
  #   * Standard date — `[year, month, day]` (month/day default to 1).
  #
  # Without this, week and ordinal dates projected via the
  # month/day defaults (1, 1) and collapsed to Jan 1 — making every
  # week interval report a zero-second duration.
  defp resolve_ymd(time, year, calendar) do
    cond do
      Keyword.has_key?(time, :week) ->
        week = Keyword.get(time, :week)
        dow = Keyword.get(time, :day_of_week, 1)
        {:ok, jan_4} = Date.new(year, 1, 4)
        jan_4_dow = Date.day_of_week(jan_4)
        week_1_monday = Date.add(jan_4, -(jan_4_dow - 1))
        date = Date.add(week_1_monday, (week - 1) * 7 + (dow - 1))
        {date.year, date.month, date.day}

      not Keyword.has_key?(time, :month) and Keyword.has_key?(time, :day) ->
        {:ok, jan_1} = Date.new(year, 1, 1)
        date = Date.add(jan_1, Keyword.get(time, :day) - 1)
        {date.year, date.month, date.day}

      true ->
        to_gregorian_ymd(
          {year, Keyword.get(time, :month, 1), Keyword.get(time, :day, 1)},
          calendar
        )
    end
  end

  @doc false
  # A hand-built `%Tempo{}` may carry `calendar: nil` (the struct default)
  # rather than the resolved calendar a parsed or `Tempo.new/1`-built value
  # has. Calendar dispatch (`calendar.calendar_base/0`, `Date.new/4`, …)
  # assumes a real calendar module, so a boundary resolves `nil` to the
  # default Gregorian implementation — the internal form of `Calendar.ISO`,
  # which unlike `Calendar.ISO` carries the `Calendrical` behaviour callbacks
  # — before any dispatch. Applied at the comparison, materialisation, and
  # network-ingest choke points every public operation funnels through.
  def effective_calendar(nil), do: Calendrical.Gregorian
  def effective_calendar(calendar), do: calendar

  # Convert calendar-native `{year, month, day}` to the proleptic Gregorian
  # frame the projection assumes. Gregorian passes through untouched (fast
  # path); any other calendar routes through `Date.convert/2`, which is the
  # `date_to_iso_days` round-trip. Falls back to the raw components rather
  # than raising if the date can't be built (a defensive best-effort). The
  # `nil` default is resolved to `Calendrical.Gregorian` at the boundary
  # (`to_utc_seconds/1`), so it never reaches here.
  defp to_gregorian_ymd(ymd, calendar) when calendar in [Calendrical.Gregorian, Calendar.ISO],
    do: ymd

  defp to_gregorian_ymd({year, month, day}, calendar) do
    with {:ok, date} <- Date.new(year, month, day, calendar),
         {:ok, gregorian} <- Date.convert(date, Calendar.ISO) do
      {gregorian.year, gregorian.month, gregorian.day}
    else
      _error -> {year, month, day}
    end
  end

  # The offset to subtract from wall-clock to get UTC. Priority:
  #
  # 1. An IANA zone on `extended.zone_id` — look up via the configured
  #    time zone database at
  #    the given wall instant (DST-era-correct). When the database
  #    returns multiple periods (DST fall-back ambiguity), an
  #    explicit numeric offset from `extended.zone_offset` or
  #    from the ISO 8601 `shift` disambiguates — we pick the
  #    period whose total offset matches. This is the mechanism
  #    RFC 9557 §4.5 describes for resolving fall-back ambiguity
  #    in IXDTF strings like `01:30:00-04:00[America/New_York]`.
  # 2. A numeric offset on `extended.zone_offset` (minutes) — use
  #    directly.
  # 3. A `shift` keyword list (legacy-style) — convert to seconds.
  # 4. No info → 0 (treat as UTC).
  # Pre-common-era wall instants precede every IANA rule — local-mean-
  # time era, so treat as
  # UTC exactly like the no-info fallback below.
  defp resolve_offset_seconds(%{zone_id: zone_id}, _shift, wall_seconds)
       when is_binary(zone_id) and zone_id != "" and
              wall_seconds < @gregorian_seconds_year_1 do
    0
  end

  defp resolve_offset_seconds(%{zone_id: zone_id} = extended, shift, wall_seconds)
       when is_binary(zone_id) and zone_id != "" do
    case TimeZoneDatabase.period_at_wall(zone_id, wall_seconds) do
      {:ok, period} ->
        TimeZoneDatabase.total_offset(period)

      {:ambiguous, first, second} ->
        ambiguous_offset([first, second], explicit_offset_seconds(extended, shift))

      _gap_or_error ->
        # Gap (spring-forward), unknown zone, or no configured
        # database. Fall back to UTC; zone validation at parse time
        # rejects the gap case, so this branch is unreachable in
        # practice.
        0
    end
  end

  defp resolve_offset_seconds(%{zone_offset: minutes}, _shift, _wall)
       when is_integer(minutes) do
    minutes * 60
  end

  defp resolve_offset_seconds(_extended, shift, _wall) when is_list(shift) do
    shift_to_seconds(shift)
  end

  defp resolve_offset_seconds(_extended, _shift, _wall), do: 0

  # Ambiguous wall time (DST fall-back): prefer the period whose
  # offset matches the explicit disambiguator, else the first period.
  defp ambiguous_offset(periods, preferred) do
    case Enum.find(periods, &(TimeZoneDatabase.total_offset(&1) == preferred)) do
      nil -> TimeZoneDatabase.total_offset(hd(periods))
      period -> TimeZoneDatabase.total_offset(period)
    end
  end

  # Extract an explicit offset in seconds from either the extended
  # `zone_offset` (minutes) or the ISO 8601 `shift` (keyword list).
  # Returns `nil` when no explicit offset is supplied — the caller
  # then falls back to the database's unambiguous period.
  defp explicit_offset_seconds(%{zone_offset: minutes}, _shift) when is_integer(minutes) do
    minutes * 60
  end

  defp explicit_offset_seconds(_extended, shift) when is_list(shift) do
    shift_to_seconds(shift)
  end

  defp explicit_offset_seconds(_extended, _shift), do: nil

  @doc false
  # The signed offset in seconds denoted by a parsed ISO 8601 shift
  # list. Shared with `Tempo.to_date_time/1`'s offset-grounded
  # conversion.
  def offset_seconds(shift) when is_list(shift), do: shift_to_seconds(shift)

  # The parsed shift carries its sign on the hour alone
  # (`-05:30` is `[hour: -5, minute: 30]`), so the finer components
  # inherit it: −05:30 is −(5 h 30 m), not −5 h + 30 m — the
  # difference is real for half-hour zones (Newfoundland −03:30).
  defp shift_to_seconds(shift) do
    hour = shift_component(shift, :hour)
    minute = shift_component(shift, :minute)
    second = shift_component(shift, :second)
    sign = if hour < 0, do: -1, else: 1
    sign * (abs(hour) * 3600 + minute * 60 + second)
  end

  # `Keyword.get/3` returns `any()`, so any arithmetic on its result
  # widens to `number()` and propagates a stray `float()` into the
  # spec of `to_utc_seconds/1`. Narrowing through a guarded helper
  # pins the result to `integer()` for Dialyzer. No `@spec` — the
  # success typing inferred from call sites (`:hour | :minute |
  # :second`) is tighter than any spec we'd write, and a broader
  # spec triggers a supertype-contract warning.
  defp shift_component(shift, key) do
    case Keyword.get(shift, key, 0) do
      value when is_integer(value) -> value
    end
  end
end
