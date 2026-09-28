defmodule Tempo.Interval.Steps do
  @moduledoc """
  Closed-form step arithmetic for interval enumeration.

  Backs the `Enumerable` protocol implementation for
  `t:Tempo.Interval.t/0` — specifically its `count/1`, `slice/1`,
  and `member?/2` callbacks — with O(1) (or near-O(1))
  implementations driven by the calendar's date algebra rather than
  walking the interval one step at a time.

  Each function takes the iteration unit and the calendar in addition
  to the endpoints:

  * `count_steps/4` — how many `unit`-wide steps fit in
    `[from, to)`.

  * `nth_step/4` — the `n`-th element from `from` at `unit`
    granularity.

  * `on_step?/4` — whether `element` falls on a `unit`-step
    boundary anchored at `from`.

  Phase 1 covers `:year`, `:month`, and `:day`. Sub-day units
  (`:hour`, `:minute`, `:second`, `:microsecond`) are added in
  subsequent phases.

  """

  alias Tempo.Compare
  alias Tempo.Enumeration.Zone
  alias Tempo.Iso8601.AST
  alias Tempo.Iso8601.Unit
  alias Tempo.TimeZoneDatabase

  @seconds_per_minute 60
  @seconds_per_hour 3_600
  @seconds_per_day 86_400
  @microseconds_per_second 1_000_000
  @max_precision 6

  @doc false
  # Extend `tempo` with next-finer units (at their minimum values) until
  # its resolution reaches `unit`. This is the walk-time counterpart of
  # the drill that materialisation used to persist into interval bounds:
  # an interval carrying an explicit iteration `:unit` finer than its
  # endpoint resolution fills the endpoint once at the start of the walk
  # (`2025-07-04` walked at `:hour` starts from `2025-07-04T0H`), leaving
  # the stored bounds at their stated resolution. A `nil` unit, or one
  # already at (or coarser than) the value's resolution, is a no-op.
  @spec fill_to_unit(Tempo.t(), atom() | nil, module()) :: Tempo.t()
  def fill_to_unit(%Tempo{} = tempo, nil, _calendar), do: tempo

  def fill_to_unit(%Tempo{time: time} = tempo, unit, calendar) do
    {resolution_unit, _span} = Tempo.resolution(tempo)

    with :lt <- Unit.compare(unit, resolution_unit),
         {next_unit, range} <- Unit.implicit_enumerator(resolution_unit, calendar) do
      filled = %Tempo{tempo | time: time ++ [{next_unit, range_first(range)}]}
      fill_to_unit(filled, unit, calendar)
    else
      # :eq / :gt — already at or finer than the requested unit; nil —
      # no finer unit exists to fill with (the chain bottoms out).
      _ -> tempo
    end
  end

  defp range_first(%Range{first: first}), do: first

  @doc """
  Count the number of `unit`-wide steps in the half-open span
  `[from, to)`.

  ### Arguments

  * `from` is the lower-bound `t:Tempo.t/0`.

  * `to` is the exclusive upper-bound `t:Tempo.t/0`.

  * `unit` is one of `:year`, `:month`, `:day` (Phase 1 scope).

  * `calendar` is the shared calendar module of both endpoints.

  ### Returns

  * A non-negative integer count, or

  * `:not_supported` when the unit / calendar combination has no
    closed-form path. Callers should fall back to walking.

  ### Examples

      iex> from = Tempo.from_iso8601!("2026Y")
      iex> to = Tempo.from_iso8601!("2030Y")
      iex> Tempo.Interval.Steps.count_steps(from, to, :year, Calendrical.Gregorian)
      4

      iex> from = Tempo.from_iso8601!("2026-01")
      iex> to = Tempo.from_iso8601!("2027-03")
      iex> Tempo.Interval.Steps.count_steps(from, to, :month, Calendrical.Gregorian)
      14

      iex> from = Tempo.from_iso8601!("2026-01-01")
      iex> to = Tempo.from_iso8601!("2026-02-01")
      iex> Tempo.Interval.Steps.count_steps(from, to, :day, Calendrical.Gregorian)
      31

  """
  @spec count_steps(Tempo.t(), Tempo.t(), atom(), module()) ::
          non_neg_integer() | :not_supported
  def count_steps(%Tempo{time: from_time} = from, %Tempo{time: to_time} = to, unit, calendar) do
    if date_axis?(from_time, unit) and date_axis?(to_time, unit) do
      count_date_steps(from, to, unit, calendar)
    else
      :not_supported
    end
  end

  defp count_date_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :year, _calendar) do
    fetch_integer!(to_time, :year) - fetch_integer!(from_time, :year)
  end

  defp count_date_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :month, calendar) do
    from_y = fetch_integer!(from_time, :year)
    from_m = fetch_integer!(from_time, :month)
    to_y = fetch_integer!(to_time, :year)
    to_m = fetch_integer!(to_time, :month)
    months_between(from_y, from_m, to_y, to_m, calendar)
  end

  defp count_date_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :day, calendar) do
    Date.diff(date_of!(to_time, calendar), date_of!(from_time, calendar))
  end

  defp count_date_steps(%Tempo{} = from, %Tempo{} = to, :hour, calendar) do
    div(elapsed_seconds(from, to, calendar), @seconds_per_hour)
  end

  defp count_date_steps(%Tempo{} = from, %Tempo{} = to, :minute, calendar) do
    div(elapsed_seconds(from, to, calendar), @seconds_per_minute)
  end

  defp count_date_steps(%Tempo{} = from, %Tempo{} = to, :second, calendar) do
    elapsed_seconds(from, to, calendar)
  end

  defp count_date_steps(%Tempo{time: from_time} = from, %Tempo{} = to, :microsecond, calendar) do
    precision = microsecond_precision!(from_time)
    step = Integer.pow(10, @max_precision - precision)
    div(elapsed_microseconds(from, to, calendar), step)
  end

  defp count_date_steps(_from, _to, _unit, _calendar), do: :not_supported

  # The closed forms step a calendar date — a year, a year and month, or
  # a year, month and day beneath days and clock units — so a value on
  # the week axis (a week's days) walks instead.
  defp date_axis?(time, :year), do: Keyword.has_key?(time, :year)

  defp date_axis?(time, :month),
    do: Keyword.has_key?(time, :year) and Keyword.has_key?(time, :month)

  defp date_axis?(time, _unit),
    do: Keyword.has_key?(time, :month) and Keyword.has_key?(time, :day)

  @doc """
  Return the Tempo at step `n` from `from` at `unit` granularity.

  ### Arguments

  * `from` is the anchor `t:Tempo.t/0`.

  * `n` is a non-negative integer step count (0 returns `from`).

  * `unit` is one of `:year`, `:month`, `:day` (Phase 1 scope).

  * `calendar` is the calendar module.

  ### Returns

  * The Tempo at step `n`, or

  * `:not_supported` for unhandled units.

  ### Examples

      iex> from = Tempo.from_iso8601!("2026-01-01")
      iex> Tempo.Interval.Steps.nth_step(from, 30, :day, Calendrical.Gregorian)
      ~o"2026Y1M31D"

      iex> from = Tempo.from_iso8601!("2026-01")
      iex> Tempo.Interval.Steps.nth_step(from, 14, :month, Calendrical.Gregorian)
      ~o"2027Y3M"

  """
  @spec nth_step(Tempo.t(), non_neg_integer(), atom(), module()) ::
          Tempo.t() | :not_supported
  def nth_step(%Tempo{time: time} = tempo, n, unit, calendar) do
    if date_axis?(time, unit), do: nth_date_step(tempo, n, unit, calendar), else: :not_supported
  end

  defp nth_date_step(%Tempo{time: time} = tempo, n, :year, _calendar) do
    year = Keyword.fetch!(time, :year)
    %{tempo | time: Keyword.replace(time, :year, year + n)}
  end

  defp nth_date_step(%Tempo{time: time} = tempo, n, :month, calendar) do
    year = Keyword.fetch!(time, :year)
    month = Keyword.fetch!(time, :month)
    {new_year, new_month, _day} = calendar.plus(year, month, 1, :months, n)

    %{
      tempo
      | time:
          time
          |> Keyword.replace(:year, new_year)
          |> Keyword.replace(:month, new_month)
    }
  end

  defp nth_date_step(%Tempo{time: time, calendar: calendar} = tempo, n, :day, calendar) do
    date = date_of!(time, calendar)
    {y, m, d} = calendar.plus(date.year, date.month, date.day, :days, n)

    %{
      tempo
      | time:
          time
          |> Keyword.replace(:year, y)
          |> Keyword.replace(:month, m)
          |> Keyword.replace(:day, d)
    }
  end

  defp nth_date_step(%Tempo{calendar: calendar} = tempo, n, :hour, calendar) do
    nth_subday_step(tempo, n * @seconds_per_hour, calendar)
  end

  defp nth_date_step(%Tempo{calendar: calendar} = tempo, n, :minute, calendar) do
    nth_subday_step(tempo, n * @seconds_per_minute, calendar)
  end

  defp nth_date_step(%Tempo{calendar: calendar} = tempo, n, :second, calendar) do
    nth_subday_step(tempo, n, calendar)
  end

  defp nth_date_step(%Tempo{time: time, calendar: calendar} = tempo, n, :microsecond, calendar) do
    {value, precision} = Keyword.fetch!(time, :microsecond)
    step = Integer.pow(10, @max_precision - precision)
    delta_micros = value + n * step
    delta_seconds = Integer.floor_div(delta_micros, @microseconds_per_second)
    new_us_value = Integer.mod(delta_micros, @microseconds_per_second)

    base = %{tempo | time: Keyword.replace(time, :microsecond, {0, precision})}
    shifted = nth_subday_step(base, delta_seconds, calendar)

    %{shifted | time: Keyword.replace(shifted.time, :microsecond, {new_us_value, precision})}
  end

  defp nth_date_step(_from, _n, _unit, _calendar), do: :not_supported

  @doc """
  Return `true` when `element` falls on a `unit`-step boundary
  anchored at `from`.

  ### Arguments

  * `element` is any `t:Tempo.t/0`.

  * `from` is the anchor `t:Tempo.t/0`.

  * `unit` is one of `:year`, `:month`, `:day` (Phase 1 scope).

  * `calendar` is the calendar module.

  ### Returns

  * `true` if `element` equals `from` advanced by some non-negative
    integer number of `unit` steps, `false` otherwise, or
    `:not_supported`.

  ### Examples

      iex> from = Tempo.from_iso8601!("2026-01-01")
      iex> elt = Tempo.from_iso8601!("2026-01-31")
      iex> Tempo.Interval.Steps.on_step?(elt, from, :day, Calendrical.Gregorian)
      true

  """
  @spec on_step?(Tempo.t(), Tempo.t(), atom(), module()) :: boolean() | :not_supported
  def on_step?(element, from, unit, calendar) do
    case count_steps(from, element, unit, calendar) do
      :not_supported -> :not_supported
      n when n >= 0 -> step_matches?(element, from, n, unit, calendar)
      _ -> false
    end
  end

  # Verify the candidate element exactly matches `nth_step(from, n, unit)`.
  # `count_steps` may produce a positive integer for an element that is
  # not on a step boundary (e.g. a finer-resolution element); the round-trip
  # check ensures element is precisely the n-th step.
  defp step_matches?(element, from, n, unit, calendar) do
    case nth_step(from, n, unit, calendar) do
      :not_supported -> :not_supported
      %Tempo{time: time} -> Keyword.equal?(time, element.time)
    end
  end

  ## ----------------------------------------------------------
  ## Helpers
  ## ----------------------------------------------------------

  # `Keyword.fetch!/2` is typed as returning `any()`, so arithmetic on
  # its result widens to `number()` and bubbles a stray `float()` into
  # the inferred return type of `count_steps/4`. Narrowing through a
  # guard-clause helper pins the type to `integer()` for Dialyzer.
  # No `@spec` — the success typing inferred from call sites is
  # tighter than any spec we'd write (`:month | :year` today), and
  # adding a wider spec triggers a supertype-contract warning.
  defp fetch_integer!(keyword, key) do
    case Keyword.fetch!(keyword, key) do
      value when is_integer(value) -> value
    end
  end

  # Calendar-aware month difference. For calendars with constant 12
  # months per year (Gregorian, Julian, Coptic, Ethiopic, Persian),
  # this is the pure modular formula. For varying-month calendars
  # (Hebrew/Metonic), we sum across the spanned years — bounded by
  # the 19-year Metonic cycle in practice.
  @spec months_between(integer(), integer(), integer(), integer(), module()) :: integer()
  defp months_between(from_y, from_m, to_y, to_m, calendar) do
    if constant_twelve_months?(calendar, from_y, to_y) do
      (to_y - from_y) * 12 + (to_m - from_m)
    else
      months_in_years_between(from_y, to_y, calendar) + (to_m - from_m)
    end
  end

  defp constant_twelve_months?(calendar, from_y, to_y) do
    calendar.months_in_year(from_y) == 12 and calendar.months_in_year(to_y) == 12
  end

  @spec months_in_years_between(integer(), integer(), module()) :: non_neg_integer()
  defp months_in_years_between(from_y, to_y, _calendar) when from_y == to_y, do: 0

  defp months_in_years_between(from_y, to_y, calendar) when from_y < to_y do
    # `calendar.months_in_year/1` is a dynamic dispatch, so Dialyzer
    # types its result as `any()`. The accumulator addition would
    # then widen to `number()` and bubble `float()` into the spec
    # of `count_steps/4`. The case-guard narrows back to integer.
    Enum.reduce(from_y..(to_y - 1)//1, 0, fn y, acc ->
      case calendar.months_in_year(y) do
        months when is_integer(months) -> acc + months
      end
    end)
  end

  # The date a stepped value's year, month and day name, which count and
  # step through Calendrical.
  defp date_of!(time, calendar) do
    {:ok, date} =
      Date.new(
        fetch_integer!(time, :year),
        fetch_integer!(time, :month),
        fetch_integer!(time, :day),
        calendar
      )

    date
  end

  @spec to_days_since_epoch(keyword(), module()) :: integer()
  defp to_days_since_epoch(time, calendar) do
    year = fetch_integer!(time, :year)
    month = fetch_integer!(time, :month)
    day = fetch_integer!(time, :day)
    # Calendrical's `date_to_iso_days/3` has no `@spec`, so Dialyzer
    # widens its inferred return to `number()`. Narrow at the call
    # site so the day-arithmetic chain stays in `integer()`.
    case calendar.date_to_iso_days(year, month, day) do
      days when is_integer(days) -> days
    end
  end

  defp from_days_since_epoch(days, calendar) do
    calendar.date_from_iso_days(days)
  end

  # Elapsed seconds between two endpoints, DST-aware when both share
  # the same named time zone on Gregorian (where the zone database applies).
  # For UTC, fixed-offset, unzoned, or non-Gregorian-calendar values,
  # the offset cancels in the wall-clock difference and the simpler
  # `wall_seconds` arithmetic is correct.
  #
  # `Tempo.Compare.to_utc_seconds/1` is typed as `integer() | float()`
  # because upstream zone-database field specs leak `number()` into its
  # success typing. We narrow at this call site via `trunc/1` so the
  # `count_steps/4` return type stays `non_neg_integer()`.
  @spec elapsed_seconds(Tempo.t(), Tempo.t(), module()) :: integer()
  defp elapsed_seconds(from, to, calendar) do
    if dst_correct?(from, to, calendar) do
      trunc(Compare.to_utc_seconds(to)) - trunc(Compare.to_utc_seconds(from))
    else
      wall_seconds(to.time, calendar) - wall_seconds(from.time, calendar)
    end
  end

  @spec elapsed_microseconds(Tempo.t(), Tempo.t(), module()) :: integer()
  defp elapsed_microseconds(from, to, calendar) do
    base = elapsed_seconds(from, to, calendar) * @microseconds_per_second
    base + microsecond_value(to.time) - microsecond_value(from.time)
  end

  @spec microsecond_value(keyword()) :: integer()
  defp microsecond_value(time) do
    case Keyword.get(time, :microsecond) do
      {value, _precision} when is_integer(value) -> value
      _ -> 0
    end
  end

  # Pull the precision (digit count) out of a microsecond keyword
  # entry as a narrowed integer — the value comes from `Keyword.fetch!`
  # whose `any()` return widens any arithmetic to `number()`.
  defp microsecond_precision!(time) do
    case Keyword.fetch!(time, :microsecond) do
      {_value, precision} when is_integer(precision) -> precision
    end
  end

  # Advance `from` by `delta_seconds` *elapsed* seconds. When `from`
  # is zoned on a Gregorian named zone, the resulting wall-clock time
  # is recomputed by adding the post-shift zone offset (handling DST
  # gaps and folds correctly). Otherwise wall-clock arithmetic.
  defp nth_subday_step(%Tempo{time: time, calendar: calendar} = tempo, delta_seconds, calendar) do
    cond do
      delta_seconds == 0 ->
        tempo

      zoned_gregorian?(tempo, calendar) ->
        new_utc = trunc(Compare.to_utc_seconds(tempo)) + delta_seconds
        new_offset = zone_offset_at_utc(tempo.extended.zone_id, new_utc)
        new_wall = new_utc + new_offset
        result = %{tempo | time: replace_date_time(time, new_wall, calendar)}
        disambiguate_fold(result, new_offset)

      true ->
        new_wall = wall_seconds(time, calendar) + delta_seconds
        %{tempo | time: replace_date_time(time, new_wall, calendar)}
    end
  end

  # When the stepped-to wall time occurs twice (a DST fall-back fold),
  # carry the explicit offset for *this* occurrence so the two folded
  # steps are distinct values, matching the reduce walk. Unambiguous
  # moments keep their original shift (a `nil` shift plus the zone id
  # resolves to a single instant). `offset_seconds` already pins which
  # side of the fold this step landed on.
  defp disambiguate_fold(%Tempo{} = result, offset_seconds) do
    case Zone.zone_status(result) do
      {:ambiguous, _first, _second} ->
        %{result | shift: Zone.offset_to_shift(offset_seconds)}

      _ ->
        result
    end
  end

  @spec wall_seconds(keyword(), module()) :: integer()
  defp wall_seconds(time, calendar) do
    day_seconds = to_days_since_epoch(time, calendar) * @seconds_per_day
    hour = get_integer(time, :hour, 0)
    minute = get_integer(time, :minute, 0)
    second = get_integer(time, :second, 0)
    day_seconds + hour * @seconds_per_hour + minute * @seconds_per_minute + second
  end

  # Sibling of `fetch_integer!/2` with a default. Same Dialyzer
  # rationale — `Keyword.get/3` returns `any()` and any arithmetic
  # on the result would widen to `number()`.
  defp get_integer(keyword, key, default) do
    case Keyword.get(keyword, key, default) do
      value when is_integer(value) -> value
    end
  end

  # DST correction needed when both endpoints carry the same named
  # IANA zone and the calendar is Gregorian (the universe where
  # the zone database applies).
  defp dst_correct?(%Tempo{} = from, %Tempo{} = to, Calendrical.Gregorian) do
    zone_id(from) != nil and zone_id(from) == zone_id(to)
  end

  defp dst_correct?(_from, _to, _calendar), do: false

  defp zoned_gregorian?(%Tempo{} = tempo, Calendrical.Gregorian), do: zone_id(tempo) != nil
  defp zoned_gregorian?(_tempo, _calendar), do: false

  defp zone_id(%Tempo{extended: %{zone_id: zone}}) when is_binary(zone) and zone != "", do: zone
  defp zone_id(_), do: nil

  defp zone_offset_at_utc(zone, utc_seconds) do
    # Pre-common-era instants are handled inside the adapter
    # (local-mean-time, zero offset).
    case TimeZoneDatabase.period_at_utc(zone, utc_seconds) do
      {:ok, period} -> TimeZoneDatabase.total_offset(period)
      {:error, _} -> 0
    end
  end

  # Convert a total wall-clock second count back into the date / time-
  # of-day components of `time`, preserving the original component
  # set: an hour-resolution endpoint stays hour-resolution (no minute
  # / second added), a minute-resolution endpoint stays minute-
  # resolution, and so on.
  defp replace_date_time(time, total_seconds, calendar) do
    days = Integer.floor_div(total_seconds, @seconds_per_day)
    time_of_day_seconds = Integer.mod(total_seconds, @seconds_per_day)
    hour = div(time_of_day_seconds, @seconds_per_hour)
    minute = div(rem(time_of_day_seconds, @seconds_per_hour), @seconds_per_minute)
    second = rem(time_of_day_seconds, @seconds_per_minute)
    {y, m, d} = from_days_since_epoch(days, calendar)

    time
    |> Keyword.replace(:year, y)
    |> Keyword.replace(:month, m)
    |> Keyword.replace(:day, d)
    |> maybe_replace(:hour, hour)
    |> maybe_replace(:minute, minute)
    |> maybe_replace(:second, second)
  end

  defp maybe_replace(time, key, value) do
    if Keyword.has_key?(time, key), do: Keyword.replace(time, key, value), else: time
  end

  # Suppress an unused-alias warning if `AST` ends up unreferenced in
  # later edits. Keeping the alias declaration documents the future
  # intent of using `AST.build/1,2` for reconstruction shortcuts.
  _ = AST
end
