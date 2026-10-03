defmodule Tempo.Math do
  @moduledoc false

  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Enumeration.Zone
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidUnitError
  alias Tempo.Iso8601.Unit
  alias Tempo.Mask
  alias Tempo.ResolutionError
  alias Tempo.TimeZoneDatabase
  alias Tempo.UnanchoredError
  alias Tempo.Validation

  @doc """
  Advance a `%Tempo{}` or a keyword-list time representation by
  exactly one unit at the given resolution.

  Writes a unit where it stands (preserves position) rather than with
  `Keyword.put/3` (removes + prepends). Keyword-list order is an
  invariant maintained elsewhere in Tempo: `compare_time/2`,
  `inspect`, and `to_iso8601` all depend on it.

  ### Arguments

  * `tempo_or_time` is either a `t:Tempo.t/0` or the keyword list
    stored in its `:time` field.

  * `unit` is the unit at which to increment. Supported units:
    `:year`, `:month`, `:day`, `:hour`, `:minute`, `:second`,
    `:week`, `:day_of_year`, `:day_of_week`.

  * `calendar` is the calendar module used for calendar-sensitive
    carry (months per year, days per month, weeks per year).

  ### Returns

  * `{:ok, stepped}`, the input with the unit advanced by 1, carrying
    into coarser units as needed. Shape matches the input — a
    `%Tempo{}` in yields a `%Tempo{}` out; a keyword list yields a
    keyword list. A unit the value does not track is left as it is.

  * `{:error, :unanchored}` when the step depends on a year the value
    does not carry.

  * `{:error, :grouped_component}` when the step would count from a
    unit that holds several values: a set, a range, a group or a mask.

  ### Raises

  * `ArgumentError` when no increment rule is defined for the
    requested unit.

  ### Examples

      iex> Tempo.Math.add_unit(~o"2022Y12M31D", :day, Calendrical.Gregorian)
      {:ok, ~o"2023Y1M1D"}

      iex> Tempo.Math.add_unit(~o"2022Y6M", :month, Calendrical.Gregorian)
      {:ok, ~o"2022Y7M"}

  A step whose result would depend on a year the value does not carry
  reports that rather than guessing:

      iex> Tempo.Math.add_unit(~o"2M28D", :day, Calendrical.Gregorian)
      {:error, :unanchored}

  A step that would count from a unit holding several values has no one
  value to count from:

      iex> Tempo.Math.add_unit(~o"2026Y6M{1,15}D", :day, Calendrical.Gregorian)
      {:error, :grouped_component}

  A unit the value does not track is left alone, so the day after the
  last day of a week that names no week is the first day of the next:

      iex> Tempo.Math.add_unit(~o"7K", :day_of_week, Calendrical.Gregorian)
      {:ok, ~o"1K"}

  """
  def add_unit(%Tempo{time: time, calendar: calendar} = tempo, unit, calendar) do
    with {:ok, stepped} <- add_unit(time, unit, calendar), do: {:ok, %{tempo | time: stepped}}
  end

  def add_unit(%Tempo{time: time, calendar: struct_calendar} = tempo, unit, calendar)
      when struct_calendar != calendar do
    # If caller explicitly passes a calendar that differs from the
    # struct's own, honour the explicit one but keep the struct
    # shape. (Normal callers pass the struct's calendar.)
    with {:ok, stepped} <- add_unit(time, unit, calendar), do: {:ok, %{tempo | time: stepped}}
  end

  # On an unanchored value (no `:year`) a whole-year step is a no-op: the
  # untracked year advances but the month/day/time axis is unchanged, so
  # "one year after January 31st" is January 31st. This is always unambiguous.
  def add_unit(time, :year, _calendar) when is_list(time), do: step_year(time, 1)

  def add_unit(time, :month, calendar) when is_list(time) do
    case forward(time, :month) do
      {:ok, month} -> add_month(time, month, calendar)
      # The value does not track months, so the carry lands on an axis it
      # never had — nothing to change.
      :untracked -> {:ok, time}
      :several -> {:error, :grouped_component}
    end
  end

  def add_unit(time, :day, calendar) when is_list(time) do
    case {forward(time, :day), forward(time, :month)} do
      # The value does not track days, so the carry lands on an axis it
      # never had — nothing to change.
      {:untracked, _month} -> {:ok, time}
      {{:ok, day}, {:ok, month}} when is_integer(month) -> add_day(time, month, day, calendar)
      {{:ok, day}, :untracked} -> advance_day_no_month(time, day, calendar)
      {{:ok, day}, _several_months} -> advance_day_in_any_month(time, day, calendar)
      # The day after depends on which of its days.
      {:several, _month} -> {:error, :grouped_component}
    end
  end

  def add_unit(time, :hour, calendar) when is_list(time),
    do: step_clock(time, :hour, 23, day_unit(time), calendar)

  def add_unit(time, :minute, calendar) when is_list(time),
    do: step_clock(time, :minute, 59, :hour, calendar)

  def add_unit(time, :second, calendar) when is_list(time),
    do: step_clock(time, :second, 59, :minute, calendar)

  # Step one unit-in-the-last-place at the microsecond's precision:
  # 10^(6 - precision) microseconds (1 ms for precision 3, 1 µs for
  # precision 6), carrying into the second at 1_000_000.
  def add_unit(time, :microsecond, calendar) when is_list(time) do
    case List.keyfind(time, :microsecond, 0) do
      {:microsecond, {value, precision}} when is_integer(value) and is_integer(precision) ->
        add_microsecond(time, value + Integer.pow(10, 6 - precision), precision, calendar)

      nil ->
        {:ok, time}

      _several ->
        {:error, :grouped_component}
    end
  end

  def add_unit(time, :week, calendar) when is_list(time) do
    case forward(time, :week) do
      {:ok, week} -> add_week(time, week, calendar)
      # A value that does not track weeks (a bare day of the week, `7K`)
      # carries into an axis it never had: the day after its Sunday is a
      # Monday, of a week it does not name, and nothing else changes.
      :untracked -> {:ok, time}
      :several -> {:error, :grouped_component}
    end
  end

  # The day after a day of the year depends on how long its year is, so one
  # with no year cannot step.
  def add_unit(time, :day_of_year, calendar) when is_list(time) do
    case {year_of(time), forward(time, :day_of_year)} do
      {_year, :untracked} -> {:ok, time}
      {:none, _day} -> {:error, :unanchored}
      {{:ok, year}, {:ok, day}} -> next_day_of_year(time, year, day, calendar)
      _several -> {:error, :grouped_component}
    end
  end

  def add_unit(time, :day_of_week, calendar) when is_list(time) do
    case forward(time, :day_of_week) do
      {:ok, day} -> add_day_of_week(time, day, calendar)
      :untracked -> {:ok, time}
      :several -> {:error, :grouped_component}
    end
  end

  # A traditional month (`3m`) is resolved to its place in a year when a value
  # is read, so one still on a value has no year to place it in, and the month
  # after it depends on that year.
  def add_unit(time, :traditional_month, _calendar) when is_list(time),
    do: {:error, :unanchored}

  def add_unit(_time, unit, _calendar) do
    raise ArgumentError,
          "Cannot increment a Tempo at #{inspect(unit)} resolution — " <>
            "no increment rule is defined for this unit."
  end

  # ── What a unit holds ─────────────────────────────────────────
  #
  # A step counts from one whole number, and a unit can hold other things, so
  # every step asks what its unit holds before it counts:
  #
  #   * `{:ok, n}` — one whole number.
  #   * `:untracked` — nothing: the value has no such unit.
  #   * `:unspecified` — `X*`, any value the unit can take.
  #   * `:several` — no one number: a set or a range (`{1,15}D`), a group
  #     (`2G3MU`), a mask (`1XD`), a margin of error (`15±2D`), or a count
  #     from the end of a month the value does not name (`-1D`).
  #
  # A step that has to count from several returns `{:error,
  # :grouped_component}`, never a value with the set collapsed and never a
  # raise. A step that every value the unit names takes alike is computed: the
  # day before `2026Y{6,7}M15D` is the 14th in both months, where the day
  # after the 30th is a different day in each.
  #
  # `:lists.keyfind/3` reads a time list that holds a group of a set, which
  # is a 3-tuple the `Keyword` functions cannot pass over, and
  # `put_component/3` writes one. The readers call it directly, and repeat
  # the one `case` rather than share it: a step is on the walk of every
  # recurrence and every enumeration.
  defp component(time, unit) do
    case :lists.keyfind(unit, 1, time) do
      {_unit, value} when is_integer(value) and value >= 0 -> {:ok, value}
      false -> :untracked
      {_unit, :any} -> :unspecified
      _several -> :several
    end
  end

  # Forward, an unspecified unit counts as its last value, so the step
  # carries: the span of `2026Y6MX*D`, some day of June, ends where July
  # starts.
  defp forward(time, unit) do
    case :lists.keyfind(unit, 1, time) do
      {_unit, value} when is_integer(value) and value >= 0 -> {:ok, value}
      false -> :untracked
      {_unit, :any} -> {:ok, :any}
      _several -> :several
    end
  end

  # Backward, an unspecified unit has no one value to count back from.
  defp backward(time, unit) do
    case :lists.keyfind(unit, 1, time) do
      {_unit, value} when is_integer(value) and value >= 0 -> {:ok, value}
      false -> :untracked
      _several -> :several
    end
  end

  # Whether a step forward from `value` stays short of `count`. An
  # unspecified unit never does.
  defp before?(value, count), do: is_integer(value) and value < count

  # Writes a unit where it stands, keeping the list's order.
  defp put_component([{unit, _held} | rest], unit, value), do: [{unit, value} | rest]
  defp put_component([entry | rest], unit, value), do: [entry | put_component(rest, unit, value)]
  defp put_component([], _unit, _value), do: []

  # The year a value is anchored on: one whole number, none, or several (a
  # set of years, a group of them, a mask).
  #
  # Having a `:year` key is not the same question as being anchored. An
  # unspecified year (`X*Y12M28D`, parsed as `year: :any`) has the key but not
  # a number, and every anchored branch either hands the year to a calendar
  # function that guards `is_integer/1` or does arithmetic on it. Such a value
  # has no year, and goes down the unanchored path, which is what it is.
  defp year_of(time) do
    case :lists.keyfind(:year, 1, time) do
      {:year, year} when is_integer(year) -> {:ok, year}
      false -> :none
      {:year, :any} -> :none
      _several -> :several
    end
  end

  defp step_year(time, by) do
    case year_of(time) do
      {:ok, year} -> {:ok, put_component(time, :year, year + by)}
      :none -> {:ok, time}
      :several -> {:error, :grouped_component}
    end
  end

  defp next_day_of_year(time, year, day, calendar) do
    if before?(day, calendar.days_in_year(year)) do
      {:ok, put_component(time, :day_of_year, day + 1)}
    else
      {:ok,
       time
       |> put_component(:year, year + 1)
       |> put_component(:day_of_year, 1)}
    end
  end

  defp add_week(time, week, calendar) do
    case year_of(time) do
      {:ok, year} -> add_week_anchored(time, year, week, calendar)
      _none_or_several -> advance_week_unanchored(time, week)
    end
  end

  defp add_week_anchored(time, year, week, calendar) do
    if before?(week, Validation.iso_weeks_in_year(year, calendar)) do
      {:ok, put_component(time, :week, week + 1)}
    else
      {:ok,
       time
       |> put_component(:year, year + 1)
       |> put_component(:week, 1)}
    end
  end

  # Without a year the week count is 52 or 53 depending on the year, so a
  # week below 52 steps cleanly and the wrap needs a year.
  defp advance_week_unanchored(time, week) do
    if before?(week, 52),
      do: {:ok, put_component(time, :week, week + 1)},
      else: {:error, :unanchored}
  end

  defp add_day_of_week(time, day, calendar) do
    if before?(day, calendar.days_in_week()) do
      {:ok, put_component(time, :day_of_week, day + 1)}
    else
      time
      |> put_component(:day_of_week, 1)
      |> add_unit(:week, calendar)
    end
  end

  defp add_month(time, month, calendar) do
    case year_of(time) do
      {:ok, year} ->
        add_month_anchored(time, year, month, calendar)

      _none_or_several ->
        advance_month_present(time, month, months_in_year_unanchored(calendar))
    end
  end

  defp add_month_anchored(time, year, month, calendar) do
    if before?(month, calendar.months_in_year(year)) do
      {:ok, put_component(time, :month, month + 1)}
    else
      {:ok,
       time
       |> put_component(:year, year + 1)
       |> put_component(:month, 1)}
    end
  end

  defp add_day(time, month, day, calendar) do
    case year_of(time) do
      {:ok, year} ->
        add_day_anchored(time, year, month, day, calendar)

      _none_or_several ->
        advance_day_in_month(time, month, day, calendar.days_in_month(month), calendar)
    end
  end

  defp add_day_anchored(time, year, month, day, calendar) do
    cond do
      before?(day, calendar.days_in_month(year, month)) ->
        {:ok, put_component(time, :day, day + 1)}

      month < calendar.months_in_year(year) ->
        {:ok,
         time
         |> put_component(:month, month + 1)
         |> put_component(:day, 1)}

      true ->
        {:ok,
         time
         |> put_component(:year, year + 1)
         |> put_component(:month, 1)
         |> put_component(:day, 1)}
    end
  end

  # A clock unit steps up to its last value, then starts again and carries
  # into the unit above it.
  defp step_clock(time, unit, last, coarser, calendar) do
    case forward(time, unit) do
      {:ok, value} when is_integer(value) and value < last ->
        {:ok, put_component(time, unit, value + 1)}

      {:ok, _last_or_unspecified} ->
        time
        |> put_component(unit, 0)
        |> add_unit(coarser, calendar)

      # The value does not track this unit, so the carry lands on an axis
      # it never had — nothing to change.
      :untracked ->
        {:ok, time}

      :several ->
        {:error, :grouped_component}
    end
  end

  # The day an hour carries into: the day of the month, or the day of the
  # week or of the year that a value on those axes names.
  defp day_unit(time) do
    cond do
      Keyword.has_key?(time, :day) -> :day
      Keyword.has_key?(time, :day_of_week) -> :day_of_week
      Keyword.has_key?(time, :day_of_year) -> :day_of_year
      true -> :day
    end
  end

  defp add_microsecond(time, incremented, precision, calendar)
       when incremented >= 1_000_000 do
    with {:ok, stepped} <-
           time |> List.keydelete(:microsecond, 0) |> add_unit(:second, calendar) do
      {:ok, stepped ++ [{:microsecond, {incremented - 1_000_000, precision}}]}
    end
  end

  defp add_microsecond(time, incremented, precision, _calendar),
    do: {:ok, put_component(time, :microsecond, {incremented, precision})}

  # ── Unanchored arithmetic (no :year) ──────────────────────────
  #
  # A value with no `:year` lives on a repeating month/day axis. One principle
  # governs every case below, and any new case must be decided by it — not by
  # whatever the day-clamp happens to do:
  #
  #   Compute the shift when its result is invariant to the missing year;
  #   return `%Tempo.UnanchoredError{}` when the result would depend on the
  #   year. Never raise.
  #
  # The calendar answers via the year-less `days_in_month/1` and
  # `months_in_year/0`, which return `{:ambiguous, range}` where a count varies
  # with the year. Applying the principle (Gregorian examples):
  #
  #   * A whole-year step is a **no-op** — the untracked year moves, the
  #     month/day/time does not (`1M31D` + `P1Y` = `1M31D`). Exception: a value
  #     already sitting on a year-dependent day (`2M29D` + `P1Y`) errors,
  #     because whether Feb 29 exists next year depends on the year.
  #   * A **month** step is answerable (12 months is invariant) and wraps
  #     December to January (`12M31D` + `P1M` = `1M31D`); only clamping the day
  #     onto the new month can force a year (`1M31D` + `P1M` = "Feb 31").
  #   * A **day/week** step advances while the day stays within the month's
  #     *guaranteed* length; crossing a boundary whose position depends on the
  #     year errors (`2M28D` + `P1D` — Feb 29 or Mar 1?). A bare-day value
  #     (no month) advances while below the shortest month any month can be.
  #
  # A value that names several years (`{2026,2027}Y6M15D`) steps the same way
  # while the step stays within its year, where every one of its years gives
  # the same answer. A step off the end or the start of the year has no one
  # year to move to, and is `{:error, :grouped_component}`.
  #
  # `add/2` turns the internal `{:error, :unanchored}` into an
  # `UnanchoredError` naming the value and the duration, so callers see a
  # value or a clean error, never a crash.

  defp advance_day_in_month(time, month, day, count, calendar) when is_integer(count) do
    if before?(day, count),
      do: {:ok, put_component(time, :day, day + 1)},
      else: start_of_next_month_unanchored(time, month, calendar)
  end

  defp advance_day_in_month(time, month, day, {:ambiguous, range}, calendar) do
    cond do
      before?(day, Enum.min(range)) ->
        {:ok, put_component(time, :day, day + 1)}

      day == :any or day >= Enum.max(range) ->
        start_of_next_month_unanchored(time, month, calendar)

      true ->
        {:error, :unanchored}
    end
  end

  defp advance_day_in_month(_time, _month, _day, _undefined, _calendar) do
    {:error, :unanchored}
  end

  # Day-only value (no month): the day advances while it stays valid in
  # *every* month; at the shortest month's length the roll-over depends on
  # the unknown month, so it needs a year.
  defp advance_day_no_month(time, day, calendar) do
    case shortest_month(calendar) do
      {:ok, shortest} ->
        if before?(day, shortest),
          do: {:ok, put_component(time, :day, day + 1)},
          else: {:error, :unanchored}

      {:error, _reason} = error ->
        error
    end
  end

  # A day in several months (`2026Y{6,7}M15D`), or in an unspecified one: the
  # day after is the same in each while it comes before the end of the
  # calendar's shortest month, and past that it depends on which month.
  defp advance_day_in_any_month(time, day, calendar) do
    case shortest_month(calendar) do
      {:ok, shortest} when is_integer(day) and day < shortest ->
        {:ok, put_component(time, :day, day + 1)}

      _past_the_shortest_month ->
        {:error, :grouped_component}
    end
  end

  # The fewest days any month of the calendar can have. A day-only value's day
  # below this exists in every month (safe to advance); at or above it the
  # roll-over depends on which month, which the value doesn't carry.
  defp shortest_month(calendar) do
    case months_in_year_unanchored(calendar) do
      count when is_integer(count) -> shortest_of_months(calendar, 1..count)
      _undefined_or_ambiguous -> {:error, :unanchored}
    end
  end

  defp shortest_of_months(calendar, months) do
    Enum.reduce_while(months, {:ok, nil}, fn month, {:ok, shortest} ->
      case shortest_month_length(calendar, month) do
        {:ok, length} -> {:cont, {:ok, min_length(shortest, length)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp min_length(nil, length), do: length
  defp min_length(shortest, length), do: min(shortest, length)

  defp shortest_month_length(calendar, month) do
    case calendar.days_in_month(month) do
      count when is_integer(count) -> {:ok, count}
      {:ambiguous, range} -> {:ok, Enum.min(range)}
      _undefined -> {:error, :unanchored}
    end
  end

  defp start_of_next_month_unanchored(time, month, calendar) do
    with {:ok, advanced} <-
           advance_month_present(time, month, months_in_year_unanchored(calendar)) do
      {:ok, put_component(advanced, :day, 1)}
    end
  end

  defp advance_month_present(time, month, count) when is_integer(count) do
    cond do
      before?(month, count) -> {:ok, put_component(time, :month, month + 1)}
      year_of(time) == :several -> {:error, :grouped_component}
      true -> {:ok, put_component(time, :month, 1)}
    end
  end

  defp advance_month_present(time, month, {:ambiguous, range}) do
    if before?(month, Enum.min(range)),
      do: {:ok, put_component(time, :month, month + 1)},
      else: {:error, :unanchored}
  end

  defp advance_month_present(_time, _month, _undefined) do
    {:error, :unanchored}
  end

  # `months_in_year/0` is an optional calendar callback — a calendar
  # that can't state its month count without a year simply doesn't
  # implement it, so guard the call and treat its absence as "needs
  # a year".
  defp months_in_year_unanchored(calendar) do
    # `function_exported?/3` returns false for a module that has not been loaded
    # yet, so force a load first — otherwise the result is non-deterministic
    # (the year-less month count would appear absent on a cold module).
    if Code.ensure_loaded?(calendar) and function_exported?(calendar, :months_in_year, 0) do
      calendar.months_in_year()
    else
      {:error, :undefined}
    end
  end

  # Mirrors of the advance helpers for `subtract_unit/3`.

  defp last_month_of_previous_year(time, calendar) do
    case year_of(time) do
      {:ok, year} ->
        {:ok,
         time
         |> put_component(:year, year - 1)
         |> put_component(:month, calendar.months_in_year(year - 1))}

      :none ->
        last_month_unanchored(time, calendar)

      :several ->
        {:error, :grouped_component}
    end
  end

  defp last_month_unanchored(time, calendar) do
    case months_in_year_unanchored(calendar) do
      count when is_integer(count) -> {:ok, put_component(time, :month, count)}
      _undefined -> {:error, :unanchored}
    end
  end

  defp end_of_month_before(time, month, calendar) do
    case year_of(time) do
      {:ok, year} -> end_of_previous_month(time, year, month, calendar)
      _none_or_several -> end_of_previous_month_unanchored(time, month, calendar)
    end
  end

  defp end_of_previous_month(time, year, month, calendar) when month > 1 do
    {:ok,
     time
     |> put_component(:month, month - 1)
     |> put_component(:day, calendar.days_in_month(year, month - 1))}
  end

  defp end_of_previous_month(time, year, _first_month, calendar) do
    previous_year = year - 1
    last_month = calendar.months_in_year(previous_year)

    {:ok,
     time
     |> put_component(:year, previous_year)
     |> put_component(:month, last_month)
     |> put_component(:day, calendar.days_in_month(previous_year, last_month))}
  end

  defp end_of_previous_month_unanchored(time, month, calendar) when month > 1,
    do: last_day_of_month_unanchored(time, month - 1, calendar)

  defp end_of_previous_month_unanchored(time, _first_month, calendar) do
    case {year_of(time), months_in_year_unanchored(calendar)} do
      {:several, _count} -> {:error, :grouped_component}
      {_none, count} when is_integer(count) -> last_day_of_month_unanchored(time, count, calendar)
      _undefined -> {:error, :unanchored}
    end
  end

  defp last_day_of_month_unanchored(time, month, calendar) do
    case calendar.days_in_month(month) do
      count when is_integer(count) ->
        {:ok,
         time
         |> put_component(:month, month)
         |> put_component(:day, count)}

      _ambiguous_or_undefined ->
        {:error, :unanchored}
    end
  end

  @doc """
  The mirror of `add_unit/3`: advance a `%Tempo{}` or keyword-list
  time representation backward by exactly one unit at the given
  resolution, borrowing from coarser units as needed.

  Used internally by `subtract/2` and by any future
  backward-walking iteration.

  ### Arguments

  * `tempo_or_time` is a `t:Tempo.t/0` or its time keyword list.
  * `unit` is the unit to decrement. Same vocabulary as `add_unit/3`.
  * `calendar` is the calendar module used for borrow lookups.

  ### Returns

  * `{:ok, stepped}`, the input with the unit decremented by 1. A unit
    the value does not track is left as it is.

  * `{:error, :unanchored}` when the step depends on a year the value
    does not carry.

  * `{:error, :grouped_component}` when the step would count from a
    unit that holds several values, or an unspecified one.

  ### Examples

      iex> Tempo.Math.subtract_unit(~o"2023Y1M1D", :day, Calendrical.Gregorian)
      {:ok, ~o"2022Y12M31D"}

      iex> Tempo.Math.subtract_unit(~o"2022Y1M", :month, Calendrical.Gregorian)
      {:ok, ~o"2021Y12M"}

      iex> Tempo.Math.subtract_unit(~o"1W", :week, Calendrical.Gregorian)
      {:error, :unanchored}

      iex> Tempo.Math.subtract_unit(~o"T0H", :hour, Calendrical.Gregorian)
      {:ok, ~o"T23H"}

  """
  def subtract_unit(%Tempo{time: time, calendar: calendar} = tempo, unit, calendar) do
    with {:ok, stepped} <- subtract_unit(time, unit, calendar),
         do: {:ok, %{tempo | time: stepped}}
  end

  def subtract_unit(%Tempo{time: time} = tempo, unit, calendar) do
    with {:ok, stepped} <- subtract_unit(time, unit, calendar),
         do: {:ok, %{tempo | time: stepped}}
  end

  # Mirror of the year no-op in `add_unit/3`: a whole-year step on an
  # unanchored value leaves its month/day/time axis untouched.
  def subtract_unit(time, :year, _calendar) when is_list(time), do: step_year(time, -1)

  def subtract_unit(time, :month, calendar) when is_list(time) do
    case backward(time, :month) do
      {:ok, month} when month > 1 -> {:ok, put_component(time, :month, month - 1)}
      {:ok, _first_month} -> last_month_of_previous_year(time, calendar)
      # The value does not track months, so the borrow comes from an axis
      # it never had — nothing to change.
      :untracked -> {:ok, time}
      :several -> {:error, :grouped_component}
    end
  end

  def subtract_unit(time, :day, calendar) when is_list(time) do
    case {backward(time, :day), backward(time, :month)} do
      # The value does not track days, so the borrow comes from an axis it
      # never had — nothing to change.
      {:untracked, _month} -> {:ok, time}
      # The day before a day past the first is the same in whatever month.
      {{:ok, day}, _month} when day > 1 -> {:ok, put_component(time, :day, day - 1)}
      {{:ok, _first_day}, {:ok, month}} -> end_of_month_before(time, month, calendar)
      # Day-only value: the 1st's predecessor is the last day of an unknown
      # month, so it needs a year.
      {{:ok, _first_day}, :untracked} -> {:error, :unanchored}
      # The day before depends on which of its days, or on which of its months.
      _several -> {:error, :grouped_component}
    end
  end

  def subtract_unit(time, :hour, calendar) when is_list(time),
    do: unstep_clock(time, :hour, 23, day_unit(time), calendar)

  def subtract_unit(time, :minute, calendar) when is_list(time),
    do: unstep_clock(time, :minute, 59, :hour, calendar)

  def subtract_unit(time, :second, calendar) when is_list(time),
    do: unstep_clock(time, :second, 59, :minute, calendar)

  # Mirror of the week step in `add_unit/3`: a value that does not track
  # weeks keeps its own axis.
  def subtract_unit(time, :week, calendar) when is_list(time) do
    case backward(time, :week) do
      {:ok, week} when week > 1 -> {:ok, put_component(time, :week, week - 1)}
      {:ok, _first_week} -> last_week_of_previous_year(time, calendar)
      :untracked -> {:ok, time}
      :several -> {:error, :grouped_component}
    end
  end

  # The day before a day of the year depends on how long the year before is
  # at day 1, and a day of the year with no year cannot step forward either.
  def subtract_unit(time, :day_of_year, calendar) when is_list(time) do
    case {year_of(time), backward(time, :day_of_year)} do
      {_year, :untracked} -> {:ok, time}
      {:none, _day} -> {:error, :unanchored}
      {{:ok, year}, {:ok, day}} -> previous_day_of_year(time, year, day, calendar)
      _several -> {:error, :grouped_component}
    end
  end

  def subtract_unit(time, :day_of_week, calendar) when is_list(time) do
    case backward(time, :day_of_week) do
      {:ok, day} when day > 1 ->
        {:ok, put_component(time, :day_of_week, day - 1)}

      {:ok, _first_day} ->
        time
        |> put_component(:day_of_week, calendar.days_in_week())
        |> subtract_unit(:week, calendar)

      :untracked ->
        {:ok, time}

      :several ->
        {:error, :grouped_component}
    end
  end

  def subtract_unit(_time, unit, _calendar) do
    raise ArgumentError,
          "Cannot decrement a Tempo at #{inspect(unit)} resolution — " <>
            "no decrement rule is defined for this unit."
  end

  # A clock unit steps down to zero, then starts again at its last value and
  # borrows from the unit above it.
  defp unstep_clock(time, unit, last, coarser, calendar) do
    case backward(time, unit) do
      {:ok, value} when value > 0 ->
        {:ok, put_component(time, unit, value - 1)}

      {:ok, _zero} ->
        time
        |> put_component(unit, last)
        |> subtract_unit(coarser, calendar)

      # The value does not track this unit, so the borrow comes from an axis
      # it never had — nothing to change.
      :untracked ->
        {:ok, time}

      :several ->
        {:error, :grouped_component}
    end
  end

  # Without a year, the week before week 1 is the 52nd or the 53rd of the
  # year before, so it needs a year; any later week steps back cleanly.
  defp last_week_of_previous_year(time, calendar) do
    case year_of(time) do
      {:ok, year} ->
        {:ok,
         time
         |> put_component(:year, year - 1)
         |> put_component(:week, Validation.iso_weeks_in_year(year - 1, calendar))}

      :none ->
        {:error, :unanchored}

      :several ->
        {:error, :grouped_component}
    end
  end

  defp previous_day_of_year(time, _year, day, _calendar) when day > 1,
    do: {:ok, put_component(time, :day_of_year, day - 1)}

  defp previous_day_of_year(time, year, _first_day, calendar) do
    {:ok,
     time
     |> put_component(:year, year - 1)
     |> put_component(:day_of_year, calendar.days_in_year(year - 1))}
  end

  @doc """
  Add a `t:Tempo.Duration.t/0` to a `t:Tempo.t/0`.

  The duration's components are applied largest-unit-first
  (year → month → day → hour → minute → second), with week
  components expanded to days (`P2W` = 14 days). After the
  month-level arithmetic, the day field is clamped to the valid
  range for the resulting month — so `2022-01-31 + P1M` yields
  `2022-02-28`, matching the semantics used by
  `java.time.LocalDate.plus/2`.

  Single add operations are atomic: `Jan 31 + P1M = Feb 28`, but
  `Jan 31 + P1M + P1M` is not the same as `Jan 31 + P2M` — date
  arithmetic is not associative. If you need the "absorb" chained
  semantic, do the add in one call with a single `P2M` duration.

  Negative duration components subtract. `~o"P-100D"` added to
  `~o"2022Y1M10D"` yields a date 100 days earlier.

  A value in a named zone reads a wall clock that daylight saving
  moves. Years, months, weeks and days step that wall clock — a day
  after noon is noon the next day — while hours, minutes and seconds
  step the time line and land on the reading the wall clock shows
  there: five hours after 23:00 on the night New York springs forward
  is 05:00. Days go before hours (RFC 5545 §3.3.6).

  The input Tempo must carry every unit referenced by the
  duration. If the duration has a `:hour` component but the Tempo
  is at year resolution, the Tempo is extended via
  `Tempo.extend_resolution/2` first.

  ### Arguments

  * `tempo` is any `t:Tempo.t/0`.
  * `duration` is any `t:Tempo.Duration.t/0`.

  ### Returns

  * A new `t:Tempo.t/0` with the duration applied.

  * `{:error, reason}` when the value holds a selection and the duration
    steps a unit it does not carry: a month on `~o"2027Y4ML1K1IN"`, the
    first Monday of April 2027, is the first Monday of May, but it has no
    day to add a day to. Also when the arguments are not a Tempo value and
    a duration.

  ### Examples

      iex> Tempo.Math.add(~o"2027Y4ML1K1IN", ~o"P1M")
      ~o"2027Y5ML1K1IN"

      iex> Tempo.Math.add(~o"2022Y1M1D", ~o"P1M")
      ~o"2022Y2M1D"

      iex> Tempo.Math.add(~o"2022Y1M31D", ~o"P1M")
      ~o"2022Y2M28D"

      iex> Tempo.Math.add(~o"2022Y12M31D", ~o"P1D")
      ~o"2023Y1M1D"

      iex> Tempo.Math.add(~o"2022Y1M1D", ~o"P2W")
      ~o"2022Y1M15D"

  """
  @spec add(Tempo.t(), Tempo.Duration.t()) ::
          Tempo.t()
          | Tempo.Set.t()
          | Tempo.IntervalSet.t()
          | {:error, Exception.t()}
  # A day of the year with no year has no day to count to: that depends on how
  # long its year is.
  def add(%Tempo{time: [{:day_of_year, _day} | _units]} = tempo, %Tempo.Duration{} = duration),
    do: {:error, UnanchoredError.exception(value: tempo, duration: duration)}

  # A day of the week that names no week (`7K`) steps on its own axis by
  # weeks, days and the time of day, but the day of the week a month or a
  # year on falls on depends on the date it has none of.
  def add(
        %Tempo{time: [{:day_of_week, _day} | _units]} = tempo,
        %Tempo.Duration{time: duration_time} = duration
      ) do
    if Enum.any?(duration_time, &month_or_year_step?/1),
      do: {:error, UnanchoredError.exception(value: tempo, duration: duration)},
      else: add_rule_or_value(tempo, duration)
  end

  def add(%Tempo{} = tempo, %Tempo.Duration{} = duration), do: add_rule_or_value(tempo, duration)

  def add(tempo, duration) do
    {:error,
     ArgumentError.exception(
       "Tempo.Math.add/2 adds a Tempo.Duration to a Tempo value, not " <>
         "#{inspect(duration)} to #{inspect(tempo)}."
     )}
  end

  defp add_rule_or_value(
         %Tempo{time: time} = tempo,
         %Tempo.Duration{time: duration_time} = duration
       ) do
    case unit_the_rule_lacks(time, duration_time) do
      nil -> add_to_value(tempo, duration)
      unit -> {:error, rule_unit_error(tempo, unit)}
    end
  end

  defp month_or_year_step?({unit, amount}), do: unit in [:year, :month] and amount != 0

  defp add_to_value(tempo, duration) do
    case wall_zone(tempo) do
      nil -> add_wall(tempo, duration)
      zone -> add_zoned(tempo, duration, zone)
    end
  end

  # A value holding a selection is a rule — `2027Y4ML1K1IN`, the first Monday
  # of April 2027 — and a duration steps the units it carries: a month on is
  # the first Monday of May. A unit it does not carry, and that is not coarser
  # than every unit it does, has nothing to step; the day after the Monday it
  # names is the day `Tempo.Interval.from/1` gives, shifted.
  defp unit_the_rule_lacks(time, duration_time) do
    if List.keymember?(time, :selection, 0) do
      carried = for entry <- time, elem(entry, 0) != :selection, do: elem(entry, 0)
      Enum.find_value(duration_time, &lacked_unit(&1, carried))
    end
  end

  defp lacked_unit({unit, _amount}, carried) do
    stepped = if unit == :week, do: :day, else: unit

    if stepped not in carried and not Enum.all?(carried, &(Unit.compare(stepped, &1) == :gt)),
      do: unit
  end

  defp rule_unit_error(tempo, unit) do
    ArgumentError.exception(
      "#{inspect(tempo)} is a rule that selects within the units it carries, and has no " <>
        "#{unit} to step: shift the span it names, Tempo.Interval.from/1 of it, instead."
    )
  end

  # Arithmetic on the wall-clock fields alone, as a floating value takes it.
  defp add_wall(%Tempo{} = tempo, %Tempo.Duration{time: duration_time} = duration) do
    case fast_add(tempo, duration_time) do
      {:ok, shifted} -> shifted
      :fallback -> unwrap_shift(add_general(tempo, duration))
    end
  end

  # The stepper threads `{:ok, tempo}`; `add/2` and `subtract/2` are
  # public and documented to return the value itself, so unwrap at that
  # boundary and let an error pass straight through.
  defp unwrap_shift({:ok, value}), do: value
  defp unwrap_shift({:error, _reason} = error), do: error
  defp unwrap_shift(other), do: other

  # ------------------------------------------------------------------
  # A zoned value's wall clock
  #
  # Calendar units step the wall clock and clock units the time line
  # (see `add/2`). A calendar step that lands in a spring-forward gap is
  # read with the offset before the gap, so it moves on by the gap; one
  # that lands on a reading the fall-back repeats is its first occurrence
  # (RFC 5545 §3.3.5). A clock step that lands on a repeated reading
  # carries its offset, as the enumeration's steps do, so it names its
  # own side of the fold, and an offset the value carried is kept to the
  # reading it lands on.

  @clock_units [:hour, :minute, :second, :microsecond]

  # UTC and the `Etc/GMT` zones keep one offset for ever, so their wall
  # clock is the time line and needs no lookup.
  @fixed_zones ["Etc/UTC", "UTC", "Etc/UCT", "UCT", "Etc/Universal", "Universal", "Etc/Zulu"]

  defp wall_zone(%Tempo{extended: %{zone_id: zone}, time: time})
       when is_binary(zone) and zone != "" and zone not in @fixed_zones do
    if zoned_datetime?(time) and not String.starts_with?(zone, "Etc/GMT"), do: zone, else: nil
  end

  defp wall_zone(%Tempo{}), do: nil

  defp zoned_datetime?([{:year, year}, {:month, month}, {:day, day} | clock])
       when is_integer(year) and is_integer(month) and is_integer(day),
       do: Enum.all?(clock, &clock_component?/1)

  defp zoned_datetime?([{:year, year}, {:week, week}, {:day_of_week, day} | clock])
       when is_integer(year) and is_integer(week) and is_integer(day),
       do: Enum.all?(clock, &clock_component?/1)

  defp zoned_datetime?(_time), do: false

  defp clock_component?({unit, value}) when unit in [:hour, :minute, :second],
    do: is_integer(value)

  defp clock_component?({:microsecond, {value, precision}}),
    do: is_integer(value) and is_integer(precision)

  defp clock_component?(_component), do: false

  defp add_zoned(%Tempo{shift: shift} = tempo, %Tempo.Duration{time: duration_time}, zone) do
    {clock, calendar} =
      duration_time
      |> exact_fractions_to_next_unit()
      |> Keyword.split(@clock_units)

    with %Tempo{} = stepped <- step_wall(tempo, calendar, zone, shift) do
      step_elapsed(stepped, clock, zone, shift)
    end
  end

  defp step_wall(tempo, [], _zone, _shift), do: tempo

  defp step_wall(tempo, calendar, zone, shift) do
    case add_wall(tempo, %Tempo.Duration{time: calendar}) do
      %Tempo{} = stepped -> settle(stepped, zone, shift)
      other -> other
    end
  end

  # A day, a month or a year names no reading of the clock; only a value
  # with a time of day can land in a gap or a fold.
  defp settle(%Tempo{time: time} = stepped, zone, shift) do
    if Keyword.has_key?(time, :hour) do
      reading = TimeZoneDatabase.period_at_wall(zone, wall_reading(stepped))
      settle_reading(stepped, shift, reading)
    else
      stepped
    end
  end

  defp settle_reading(stepped, shift, {:ok, period}),
    do: keep_offset(stepped, total_offset(period), shift)

  defp settle_reading(stepped, shift, {:ambiguous, first, second}) do
    first_offset = total_offset(first)

    cond do
      is_nil(shift) -> stepped
      Compare.offset_seconds(shift) in [first_offset, total_offset(second)] -> stepped
      true -> %{stepped | shift: offset_as_written(first_offset, shift)}
    end
  end

  # 02:30 on the night New York moves from 02:00 to 03:00 is 03:30.
  defp settle_reading(stepped, shift, {:gap, {before, _before_limit}, {later, _later_limit}}) do
    later_offset = total_offset(later)

    stepped
    |> move_wall(later_offset - total_offset(before))
    |> keep_offset(later_offset, shift)
  end

  defp settle_reading(stepped, _shift, {:error, _reason}), do: stepped

  defp step_elapsed(stepped, [], _zone, _shift), do: stepped

  # The step's start reads its offset as its wall reading less its instant,
  # the offset `Tempo.Compare.to_utc_seconds/1` resolved it with.
  defp step_elapsed(stepped, clock, zone, shift) do
    from_utc = trunc(Compare.to_utc_seconds(stepped))
    before = wall_reading(stepped) - from_utc
    to_utc = from_utc + clock_seconds(clock)
    later = offset_at(zone, to_utc)

    with %Tempo{} = walled <- add_wall(stepped, %Tempo.Duration{time: clock}),
         %Tempo{} = moved <- move_wall(walled, later - before) do
      mark_reading(moved, zone, to_utc + later, later, shift)
    end
  end

  defp mark_reading(moved, zone, wall, offset, shift) do
    case TimeZoneDatabase.period_at_wall(zone, wall) do
      {:ambiguous, _first, _second} -> %{moved | shift: offset_as_written(offset, shift)}
      _single_or_none -> keep_offset(moved, offset, shift)
    end
  end

  defp keep_offset(%Tempo{} = tempo, _offset, nil), do: tempo

  defp keep_offset(%Tempo{} = tempo, offset, shift),
    do: %{tempo | shift: offset_as_written(offset, shift)}

  defp keep_offset(other, _offset, _shift), do: other

  # An offset in the shape the value wrote its own: one given as `-05:00`
  # keeps its minutes when it becomes `-04:00`.
  defp offset_as_written(offset, shift) do
    written = Zone.offset_to_shift(offset)

    if is_list(shift) and Keyword.has_key?(shift, :minute) and
         not Keyword.has_key?(written, :minute),
       do: written ++ [minute: 0],
       else: written
  end

  # Moves the wall clock by whole offsets, in the coarsest clock unit that
  # counts them whole, so an hour does not add minutes to a value that has
  # none.
  defp move_wall(tempo, 0), do: tempo
  defp move_wall(tempo, seconds), do: add_wall(tempo, %Tempo.Duration{time: wall_units(seconds)})

  defp wall_units(seconds) when rem(seconds, 3600) == 0, do: [hour: div(seconds, 3600)]
  defp wall_units(seconds) when rem(seconds, 60) == 0, do: [minute: div(seconds, 60)]
  defp wall_units(seconds), do: [second: seconds]

  # The clock part's length in whole seconds; a fraction of a second never
  # decides which side of a transition a step lands on.
  defp clock_seconds(clock) do
    Enum.reduce(clock, 0, fn
      {:hour, hours}, total -> total + trunc(hours * 3600)
      {:minute, minutes}, total -> total + trunc(minutes * 60)
      {:second, seconds}, total -> total + trunc(seconds)
      {:microsecond, _fraction}, total -> total
    end)
  end

  defp offset_at(zone, utc_seconds) do
    case TimeZoneDatabase.period_at_utc(zone, utc_seconds) do
      {:ok, period} -> total_offset(period)
      {:error, _reason} -> 0
    end
  end

  defp wall_reading(tempo), do: trunc(Compare.to_wall_seconds(tempo))

  # `TimeZoneDatabase.total_offset/1` is typed `number()`; an offset is a
  # whole number of seconds.
  defp total_offset(period) do
    case TimeZoneDatabase.total_offset(period) do
      offset when is_integer(offset) -> offset
    end
  end

  # Fast path for the overwhelmingly common shift: a single fixed-length
  # unit (day or finer) added to a plain crisp anchored datetime. Such a
  # value carries no masks and no ±/significant-digit annotations, the
  # duration needs no week-normalisation, and its resolution already
  # covers the unit — so every step of the `add_general/2` prelude (mask
  # scan, annotation strip, resolution extend, re-annotate) is a no-op.
  # Going straight to the arithmetic the general path ends in is ~4×
  # faster and returns byte-identical values.
  defp fast_add(%Tempo{time: time, calendar: calendar} = tempo, [{unit, n}])
       when unit in [:day, :hour, :minute, :second] and is_integer(n) do
    if plain_datetime?(time) and Keyword.has_key?(time, unit) do
      fast_step(tempo, apply_n_units(time, unit, n, calendar))
    else
      :fallback
    end
  end

  defp fast_add(_tempo, _duration_time), do: :fallback

  # A step the fast path cannot take is left to the general path, which
  # names the value in its error.
  defp fast_step(tempo, {:ok, stepped}), do: {:ok, %{tempo | time: stepped}}
  defp fast_step(_tempo, {:error, _reason}), do: :fallback

  # A plain crisp anchored datetime: an integer year/month/day prefix
  # with every remaining component a plain integer — no mask, no
  # `{value, opts}` annotation, no `{value, precision}` microsecond, no
  # range or group.
  defp plain_datetime?([{:year, y}, {:month, m}, {:day, d} | rest])
       when is_integer(y) and is_integer(m) and is_integer(d) do
    Enum.all?(rest, &match?({_unit, value} when is_integer(value), &1))
  end

  defp plain_datetime?(_time), do: false

  # The stepper names what it cannot step by an atom, where it has no value
  # to name: `:unanchored` for a step whose answer depends on a year the
  # value does not carry, and `:grouped_component` for one that would count
  # from a unit holding several values. Name the value and the duration
  # here, where both are still in scope.
  defp add_general(%Tempo{} = tempo, %Tempo.Duration{} = duration) do
    case route_general(tempo, duration) do
      {:error, :unanchored} ->
        {:error, unanchored_error(tempo, duration)}

      {:error, :grouped_component} ->
        {:error, ConversionError.exception(value: tempo, reason: :grouped_component)}

      other ->
        other
    end
  end

  # A value that names several years (`{2026,2027}Y2M28D`) steps as one with
  # no year does, and where the answer depends on the year it is not short of
  # a year: it holds several.
  defp unanchored_error(%Tempo{time: time} = tempo, duration) do
    case year_of(time) do
      :several -> ConversionError.exception(value: tempo, reason: :grouped_component)
      _no_year -> UnanchoredError.exception(value: tempo, duration: duration)
    end
  end

  # Route to the mask path only when the shift actually reaches a mask.
  # A shift coarser than every mask (or a value with no masks) never
  # touches a masked component, so the crisp path shifts around them and
  # keeps the masks intact (`2020-XX` + `P1Y` → `2021-XX`).
  defp route_general(%Tempo{} = tempo, %Tempo.Duration{time: duration_time} = duration) do
    tempo = unspecified_as_masks(tempo, duration_time)
    masks = find_masks(tempo.time)

    if Enum.any?(masks, fn {unit, _mask} -> duration_reaches?(duration_time, unit) end) do
      shift_masked(tempo, masks, duration)
    else
      add_crisp(tempo, duration)
    end
  end

  # Coarse → fine. A duration "reaches" a mask when it carries a
  # non-zero component at the masked unit or finer (which is where the
  # arithmetic reads or writes the masked value).
  @unit_depth [year: 0, month: 1, week: 2, day: 2, hour: 3, minute: 4, second: 5, microsecond: 6]

  defp duration_reaches?(duration_time, mask_unit) do
    mask_depth = Keyword.fetch!(@unit_depth, mask_unit)

    Enum.any?(duration_time, fn {unit, amount} ->
      amount != 0 and Keyword.get(@unit_depth, unit, 0) >= mask_depth
    end)
  end

  # The crisp arithmetic path. ISO 8601-2 margin-of-error (`±`) and
  # significant-digits (`S`) annotations ride on a component value as
  # `{integer, keyword}`; they are crisp-inert, so peel them off before
  # the duration is applied and re-attach each to its (shifted) component
  # afterwards — `Tempo.shift(~o"2018±2Y", ~o"P1Y") == ~o"2019±2Y"` rather
  # than crashing the integer arithmetic on the tuple.
  # A week date names a week and a day of it, and no month, so it has no
  # month to step; its weeks and days step on the week axis.
  defp add_crisp(%Tempo{time: time} = tempo, %Tempo.Duration{time: duration_time} = duration) do
    if Keyword.has_key?(time, :week) and not Keyword.has_key?(time, :month) and
         Keyword.get(duration_time, :month, 0) != 0 do
      {:error,
       ResolutionError.exception(
         current: :week,
         target: :month,
         operation: :shift,
         calendar: tempo.calendar,
         reason: "#{inspect(tempo)} is a week date, with no month to add months to"
       )}
    else
      add_crisp_units(tempo, duration)
    end
  end

  defp add_crisp_units(%Tempo{} = tempo, %Tempo.Duration{time: duration_time}) do
    {crisp_time, annotations} = strip_component_annotations(tempo.time)

    # Normalise weeks to days *before* extending resolution, so a `P1W` shift
    # extends the value to day resolution (not week) and the day arithmetic has
    # a `:day` slot to operate on — e.g. `~o"3M"` + `P1W` becomes `~o"3M8D"`.
    # A week-axis value (`[year, week]`) is the exception: it has a `:week`
    # slot and no `:day`, so weeks step natively via `add_unit(:week)` —
    # converting them to days would demand month/day keys the axis lacks.
    # A day of the week of no week (`7K`) is on that axis too: the day after
    # it is the next day of the week, and a week after it is the same one.
    duration_time =
      if week_axis?(crisp_time) do
        translate_week_axis_duration(duration_time)
      else
        normalise_duration(duration_time)
      end
      |> exact_fractions_to_next_unit()

    case ensure_resolution_for_duration(%{tempo | time: crisp_time}, duration_time) do
      {:error, _} = error ->
        error

      %Tempo{} = tempo ->
        with {:ok, shifted} <- apply_duration(tempo, duration_time) do
          {:ok, Map.update!(shifted, :time, &reapply_component_annotations(&1, annotations))}
        end
    end
  end

  # A value on the week axis names a week, or a day of the week of no week
  # (`7K`), and no day of a month.
  defp week_axis?(time) do
    Keyword.has_key?(time, :week) or
      (Keyword.has_key?(time, :day_of_week) and not Keyword.has_key?(time, :month))
  end

  # On the week axis a day of duration is a `:day_of_week` step —
  # `[year, week]` has no month/day slots, and `day_of_week` carries
  # into `:week` (and the week into the year) exactly as day-arithmetic
  # requires. `2026Y32W + P2D` is `2026Y32W3K`, and seven days later is
  # the next week's Monday.
  defp translate_week_axis_duration(duration_time) do
    duration_time
    |> week_fraction_to_days()
    |> Keyword.pop(:day, 0)
    |> case do
      {0, rest} -> rest
      {days, rest} -> rest ++ [day_of_week: days]
    end
  end

  # A fractional week keeps its whole weeks on the week axis and adds the
  # days `Calendrical.weeks_to_days/1` makes of its fraction.
  defp week_fraction_to_days(duration_time) do
    case Keyword.get(duration_time, :week) do
      weeks when is_float(weeks) ->
        whole = trunc(weeks)

        duration_time
        |> Keyword.replace!(:week, whole)
        |> add_duration_amount(:day, Calendrical.weeks_to_days(weeks - whole))

      _integer_or_absent ->
        duration_time
    end
  end

  @hours_per_day 24
  @minutes_per_hour 60
  @seconds_per_minute 60
  @duration_units_coarse_to_fine [
    :year,
    :month,
    :week,
    :day,
    :day_of_week,
    :hour,
    :minute,
    :second,
    :microsecond
  ]

  # A fractional amount (ISO 8601-2 §11.4) becomes whole units of the next
  # smaller unit, truncated toward zero: `P1.3D` is one day and seven hours.
  # Days, hours and minutes have fixed lengths, so they expand before the
  # duration is applied; a fractional year or month depends on the date and
  # resolves as it is applied (`apply_duration_component/4`).
  defp exact_fractions_to_next_unit(duration_time) do
    duration_time
    |> fraction_to_next_unit(:day, :hour, @hours_per_day)
    |> fraction_to_next_unit(:day_of_week, :hour, @hours_per_day)
    |> fraction_to_next_unit(:hour, :minute, @minutes_per_hour)
    |> fraction_to_next_unit(:minute, :second, @seconds_per_minute)
  end

  defp fraction_to_next_unit(duration_time, unit, next_unit, next_units_per_unit) do
    case Keyword.get(duration_time, unit) do
      amount when is_float(amount) ->
        whole = trunc(amount)
        next_amount = whole_units(amount - whole, next_units_per_unit)

        duration_time
        |> Keyword.replace!(unit, whole)
        |> add_duration_amount(next_unit, next_amount)

      _integer_or_absent ->
        duration_time
    end
  end

  # Adds to a unit's amount, or places the unit in its coarse-to-fine
  # position when the duration has none.
  defp add_duration_amount(duration_time, _unit, 0), do: duration_time

  defp add_duration_amount(duration_time, unit, amount) do
    if Keyword.has_key?(duration_time, unit) do
      Keyword.update!(duration_time, unit, &(&1 + amount))
    else
      Enum.sort_by([{unit, amount} | duration_time], &duration_unit_rank/1)
    end
  end

  defp duration_unit_rank({unit, _amount}),
    do: Enum.find_index(@duration_units_coarse_to_fine, &(&1 == unit))

  # A fraction of `units_per_unit` whole units, truncated toward zero. The
  # product is rounded to ten places first, so a decimal fraction that
  # binary floating point cannot hold exactly (0.7 × 60 = 41.999…) gives
  # the whole number it means.
  defp whole_units(fraction, units_per_unit),
    do: fraction |> Kernel.*(units_per_unit) |> Float.round(10) |> trunc()

  # ------------------------------------------------------------------
  # Unspecified-digit mask arithmetic
  #
  # A mask (`195X`, `2020-XX`, `19XX-XX`) denotes a *block* of candidate
  # values. A shift moves the block: fill *every* mask to its min and max
  # candidate, shift both crisply, then re-express the result. A
  # block-aligned single-year shift stays a mask (`195X` + `P10Y` →
  # `196X`); anything else becomes a one-of set spanning the shifted block
  # (`195X` + `P1Y` → `~o"[1951Y..1960Y]"`).

  # Masks are only resolved on units the arithmetic understands; a mask on
  # any other unit falls through to the crisp path unchanged.
  @maskable_units [:year, :month, :day, :hour, :minute, :second]

  # An unspecified unit other than the year (`X*D`, any day) is every value
  # the unit takes, as a mask of all its digits is (`XXD`), and a shift that
  # reaches it moves that block: `2026Y6MX*D` plus a day is one of 2 June to 1
  # July, where it was read as the unit's last value. An unspecified year is
  # any year, which a step carries as it is.
  defp unspecified_as_masks(%Tempo{time: time} = tempo, duration_time) do
    %{tempo | time: Enum.map(time, &unspecified_as_mask(&1, duration_time))}
  end

  defp unspecified_as_mask({unit, :any} = component, duration_time)
       when unit in @maskable_units and unit != :year do
    if duration_reaches?(duration_time, unit),
      do: {unit, {:mask, [:X, :X]}},
      else: component
  end

  defp unspecified_as_mask(component, _duration_time), do: component

  defp find_masks(time) do
    Enum.flat_map(time, fn
      {unit, {:mask, mask}} when is_list(mask) and unit in @maskable_units -> [{unit, mask}]
      _ -> []
    end)
  end

  defp shift_masked(%Tempo{time: time, calendar: calendar} = tempo, masks, duration) do
    if trailing_masks?(time) do
      # A contiguous (trailing) block shifts as a whole, so its min and
      # max candidate bound it exactly.
      # A step either end cannot take is the stepper's error, which
      # `add_general/2` names.
      with {:ok, min_time} <- fill_masks(time, calendar, :min),
           {:ok, max_time} <- fill_masks(time, calendar, :max),
           {:ok, first} <- add_crisp(%{tempo | time: min_time}, duration),
           {:ok, last} <- add_crisp(%{tempo | time: max_time}, duration) do
        remask_or_set(masks, first, last)
      end
    else
      # A mask with a concrete component after it denotes *disjoint*
      # blocks (`19XX-06-XX` is only the Junes), which a single range
      # can't represent — shift each candidate and collect the exact
      # spans into a coalesced IntervalSet.
      shift_masked_disjoint(tempo, duration)
    end
  end

  # Masks form a contiguous suffix — every component from the first mask
  # onward is also masked. Such a value is a single block; a mask with a
  # concrete component after it (`19XX-06-XX`) is not.
  defp trailing_masks?(time) do
    time
    |> Enum.drop_while(&(not masked?(&1)))
    |> Enum.all?(&masked?/1)
  end

  defp masked?(entry), do: match?({_unit, {:mask, _mask}}, entry)

  # The candidates are walked by the enumeration, which has no way to return
  # an error and raises where a mask's candidates depend on a year the value
  # does not carry. `Tempo.to_interval/1` resolves the same candidates and
  # returns that as an error, so it is asked first.
  defp shift_masked_disjoint(masked, duration) do
    with {:ok, _candidates} <- Tempo.to_interval(masked),
         {:ok, spans} <- shifted_spans(masked, duration),
         {:ok, set} <- IntervalSet.new(spans) do
      IntervalSet.coalesce(set)
    end
  end

  # The span of each candidate the masks stand for, shifted. The first
  # candidate that cannot be shifted is the answer for them all.
  defp shifted_spans(masked, duration) do
    masked
    |> Enum.reduce_while({:ok, []}, fn candidate, {:ok, spans} ->
      case shifted_span(candidate, duration) do
        {:ok, span} -> {:cont, {:ok, [span | spans]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, spans} -> {:ok, Enum.reverse(spans)}
      {:error, _reason} = error -> error
    end
  end

  defp shifted_span(candidate, duration) do
    with {:ok, shifted} <- add_crisp(candidate, duration) do
      one_span(Tempo.to_interval(shifted))
    end
  end

  # A candidate that still holds a set names several spans, not one.
  defp one_span({:ok, %Interval{} = span}), do: {:ok, span}
  defp one_span({:ok, _several_spans}), do: {:error, :grouped_component}
  defp one_span({:error, _reason} = error), do: error

  # Replace every masked component with its minimum (or maximum) candidate,
  # coarse to fine so a sub-year mask sees the concrete coarser values it
  # depends on (a month's valid range needs its year).
  defp fill_masks(time, calendar, which) do
    time
    |> Enum.reduce_while({:ok, []}, fn
      {unit, {:mask, mask}}, {:ok, filled} ->
        case mask_candidate_bounds(unit, mask, Enum.reverse(filled), calendar) do
          {:ok, {min_value, max_value}} ->
            {:cont, {:ok, [{unit, if(which == :min, do: min_value, else: max_value)} | filled]}}

          {:error, _reason} = error ->
            {:halt, error}
        end

      entry, {:ok, filled} ->
        {:cont, {:ok, [entry | filled]}}
    end)
    |> case do
      {:ok, filled} -> {:ok, Enum.reverse(filled)}
      {:error, _reason} = error -> error
    end
  end

  # Year masks are digit-bounded; sub-year masks are calendar-bounded by
  # the already-filled coarser components.
  defp mask_candidate_bounds(:year, [:negative | rest], _previous, _calendar) do
    {min, max} = Mask.mask_bounds(rest)
    {:ok, {-max, -min}}
  end

  defp mask_candidate_bounds(:year, mask, _previous, _calendar) do
    {:ok, Mask.mask_bounds(mask)}
  end

  defp mask_candidate_bounds(unit, mask, previous, calendar) do
    case Mask.valid_values(unit, mask, previous, calendar) do
      {:ok, candidates} -> {:ok, {Enum.min(candidates), Enum.max(candidates)}}
      {:error, _reason} = error -> error
    end
  end

  # A single, same-width, block-aligned year mask re-masks; everything
  # else (misaligned, negative, or multi-component) is a one-of set
  # spanning the shifted candidates.
  defp remask_or_set(
         [{:year, mask}],
         %Tempo{time: [year: lo]} = first,
         %Tempo{time: [year: hi]} = last
       )
       when is_integer(lo) and is_integer(hi) and lo >= 0 do
    unspecified = Enum.count(mask, &(&1 == :X))
    block = Integer.pow(10, unspecified)
    digits = Integer.digits(lo)

    if hi - lo + 1 == block and rem(lo, block) == 0 and length(digits) == length(mask) do
      remasked =
        Enum.take(digits, length(digits) - unspecified) ++ List.duplicate(:X, unspecified)

      %{first | time: [year: {:mask, remasked}]}
    else
      one_of_range(first, last)
    end
  end

  defp remask_or_set(_masks, first, last), do: one_of_range(first, last)

  defp one_of_range(first, last) do
    %Tempo.Set{type: :one, set: [%Tempo.Range{first: first, last: last}]}
  end

  # Peel `{integer, keyword}` value annotations (margin-of-error,
  # significant-digits) into a `%{unit => keyword}` map, leaving the
  # crisp integer in the time. Masks (`{:mask, list}`) and microsecond
  # `{value, precision}` values are untouched — only an integer value
  # with a keyword-list tail is an annotation.
  defp strip_component_annotations(time) do
    Enum.map_reduce(time, %{}, fn
      {unit, {value, opts}}, annotations when is_integer(value) and is_list(opts) ->
        {{unit, value}, Map.put(annotations, unit, opts)}

      entry, annotations ->
        {entry, annotations}
    end)
  end

  defp reapply_component_annotations(time, annotations) when annotations == %{}, do: time

  defp reapply_component_annotations(time, annotations) do
    Enum.map(time, fn
      {unit, value} = entry when is_integer(value) ->
        case annotations do
          %{^unit => opts} -> {unit, {value, opts}}
          _ -> entry
        end

      entry ->
        entry
    end)
  end

  @doc """
  Subtract a `t:Tempo.Duration.t/0` from a `t:Tempo.t/0`.

  Equivalent to `add/2` with every duration component negated.
  Month arithmetic still clamps day-of-month at the end.

  ### Arguments

  * `tempo` is any `t:Tempo.t/0`.
  * `duration` is any `t:Tempo.Duration.t/0`.

  ### Returns

  * A new `t:Tempo.t/0` with the duration subtracted.

  * `{:error, reason}` as for `add/2`.

  ### Examples

      iex> Tempo.Math.subtract(~o"2022Y3M1D", ~o"P1M")
      ~o"2022Y2M1D"

      iex> Tempo.Math.subtract(~o"2022Y3M31D", ~o"P1M")
      ~o"2022Y2M28D"

      iex> Tempo.Math.subtract(~o"2022Y1M1D", ~o"P1D")
      ~o"2021Y12M31D"

  """
  @spec subtract(Tempo.t(), Tempo.Duration.t()) ::
          Tempo.t()
          | Tempo.Set.t()
          | Tempo.IntervalSet.t()
          | {:error, Exception.t()}
  def subtract(%Tempo{} = tempo, %Tempo.Duration{time: duration_time}) do
    negated =
      Enum.map(duration_time, fn
        # Negate the microsecond amount by sign of the value; the
        # `{value, precision}` shape is preserved (a transient negative
        # value drives the borrow in `shift_microseconds/3`).
        {:microsecond, {value, precision}} -> {:microsecond, {-value, precision}}
        {unit, amount} -> {unit, -amount}
      end)

    add(tempo, %Tempo.Duration{time: negated})
  end

  def subtract(tempo, duration) do
    {:error,
     ArgumentError.exception(
       "Tempo.Math.subtract/2 takes a Tempo.Duration from a Tempo value, not " <>
         "#{inspect(duration)} from #{inspect(tempo)}."
     )}
  end

  # Weeks in a duration are whole days, as `Calendrical.weeks_to_days/1`
  # counts them (a fractional week truncates). Normalise to days so the
  # apply-duration loop doesn't need a `:week` clause.
  defp normalise_duration(duration_time) do
    {weeks, rest} = Keyword.pop(duration_time, :week, 0)

    case weeks do
      0 ->
        rest

      _ ->
        days = Calendrical.weeks_to_days(weeks)
        Keyword.update(rest, :day, days, &(&1 + days))
    end
  end

  # If the duration references a unit finer than the tempo's
  # current resolution, extend the tempo with minimums so the
  # add/subtract_unit calls have a slot to operate on.
  defp ensure_resolution_for_duration(%Tempo{} = tempo, duration_time) do
    # A microsecond component needs a `:second` slot to carry into, so
    # force at least second resolution when one is present.
    finest =
      if Keyword.has_key?(duration_time, :microsecond) do
        :second
      else
        finest_duration_unit(duration_time)
      end

    if finest == nil do
      tempo
    else
      case Tempo.extend_resolution(tempo, finest) do
        %Tempo{} = extended ->
          extended

        # An axis with no path to the duration's unit (an hour under a
        # week-axis value) cannot take the shift — refuse with the
        # resolution error rather than marching into key errors below.
        # Any other extension failure (the value is already finer than
        # the duration's unit) keeps the value as-is; the arithmetic
        # handles it.
        {:error, %Tempo.ResolutionError{reason: :no_path} = error} ->
          {:error, error}

        _other ->
          tempo
      end
    end
  end

  @unit_order_coarse_to_fine [:year, :month, :week, :day, :day_of_week, :hour, :minute, :second]

  defp finest_duration_unit(duration_time) do
    duration_units = Enum.flat_map(duration_time, &units_reached/1)

    @unit_order_coarse_to_fine
    |> Enum.reverse()
    |> Enum.find(&(&1 in duration_units))
  end

  # A fractional year also reaches months, and a fractional month days.
  defp units_reached({:year, amount}) when is_float(amount) and amount != trunc(amount),
    do: [:year, :month]

  defp units_reached({:month, amount}) when is_float(amount) and amount != trunc(amount),
    do: [:month, :day]

  defp units_reached({unit, _amount}), do: [unit]

  # Apply duration components largest-to-smallest, then clamp day
  # to the valid range for the resulting month. `:week` appears only
  # for week-axis values (month-axis durations normalise weeks to
  # days before this loop runs).
  @duration_apply_order [:year, :month, :week, :day, :day_of_week, :hour, :minute, :second]

  defp apply_duration(%Tempo{time: time, calendar: calendar} = tempo, duration_time) do
    stepped =
      @duration_apply_order
      |> Enum.reduce_while({:ok, time}, fn unit, {:ok, acc} ->
        case Keyword.get(duration_time, unit, 0) do
          0 -> {:cont, {:ok, acc}}
          n -> step_or_halt(apply_duration_component(acc, unit, n, calendar))
        end
      end)
      |> thread_microsecond(Keyword.get(duration_time, :microsecond), calendar)

    # Only a month/year step can leave the day past the new month's length
    # ("Jan 31 + 1 month = Feb 31"); day/week/time steps already carry into the
    # next month as they go. Clamping only when a month or year is present
    # avoids a spurious demand for a year from a value that already sits on an
    # ambiguous day — e.g. `~o"2M29D"` shifted by an hour keeps its 29th.
    with {:ok, new_time} <- maybe_clamp(stepped, duration_time, calendar) do
      {:ok, %{tempo | time: new_time}}
    end
  end

  defp step_or_halt({:ok, _time} = ok), do: {:cont, ok}
  defp step_or_halt({:error, _reason} = error), do: {:halt, error}

  # A fractional year or month resolves against the date it is applied to
  # (ISO 8601-2 D.4.4): its whole units step as usual, and its fraction
  # becomes whole units of the next smaller unit, truncated — a fraction of
  # the year's months, or of the days from the date to one month later.
  defp apply_duration_component(time, unit, amount, calendar)
       when unit in [:year, :month] and is_float(amount) do
    whole = trunc(amount)

    with {:ok, next_unit, next_amount} <-
           fraction_in_next_unit(time, unit, amount - whole, calendar),
         {:ok, time} <- apply_n_units(time, unit, whole, calendar) do
      apply_n_units(time, next_unit, next_amount, calendar)
    end
  end

  defp apply_duration_component(time, unit, amount, calendar),
    do: apply_n_units(time, unit, amount, calendar)

  defp fraction_in_next_unit(time, :year, fraction, calendar) do
    case year_of(time) do
      {:ok, year} -> {:ok, :month, whole_units(fraction, calendar.months_in_year(year))}
      :none -> {:error, :unanchored}
      :several -> {:error, :grouped_component}
    end
  end

  defp fraction_in_next_unit(time, :month, fraction, calendar) do
    with {:ok, year} <- year_of(time),
         {:ok, month} <- component(time, :month),
         {:ok, day} <- component(time, :day),
         {:ok, date} <- Date.new(year, month, day, calendar),
         {next_year, next_month, next_day} <- calendar.plus(year, month, day, :months, 1),
         {:ok, month_later} <- Date.new(next_year, next_month, next_day, calendar) do
      {:ok, :day, whole_units(fraction, Date.diff(month_later, date))}
    else
      :several -> {:error, :grouped_component}
      _no_full_date -> {:error, :unanchored}
    end
  end

  defp maybe_clamp({:error, _reason} = error, _duration_time, _calendar), do: error

  defp maybe_clamp({:ok, time}, duration_time, calendar) do
    if Keyword.has_key?(duration_time, :month) or Keyword.has_key?(duration_time, :year),
      do: clamp_day_to_month(time, calendar),
      else: {:ok, time}
  end

  # Sub-second durations are applied as a single signed shift of the
  # microsecond value rather than iterated `add_unit` calls (which
  # would be O(value)). A negative value (produced by `subtract/2`)
  # borrows from the second.
  defp apply_microsecond_duration(time, nil, _calendar), do: {:ok, time}
  defp apply_microsecond_duration(time, {0, _precision}, _calendar), do: {:ok, time}

  defp apply_microsecond_duration(time, {value, _precision}, calendar) do
    shift_microseconds(time, value, calendar)
  end

  @microseconds_per_second 1_000_000
  defp shift_microseconds(time, delta, calendar) do
    {current, precision} =
      case List.keyfind(time, :microsecond, 0) do
        {:microsecond, {value, precision}} -> {value, precision}
        nil -> {0, 6}
      end

    total = current + delta
    whole_seconds = Integer.floor_div(total, @microseconds_per_second)
    remainder = Integer.mod(total, @microseconds_per_second)

    time
    |> put_microsecond(remainder, precision)
    |> apply_n_units(:second, whole_seconds, calendar)
  end

  # The microsecond shift runs after the coarse units, so it receives an
  # already-wrapped time. Kept separate from `apply_microsecond_duration/3`
  # so a `{:ok, time}` first argument cannot match one of its clauses.
  defp thread_microsecond({:ok, time}, microsecond, calendar),
    do: apply_microsecond_duration(time, microsecond, calendar)

  defp thread_microsecond({:error, _reason} = error, _microsecond, _calendar), do: error

  # Set the microsecond component, preserving position if present and
  # appending (after the second) if absent.
  defp put_microsecond(time, value, precision) do
    if List.keymember?(time, :microsecond, 0) do
      put_component(time, :microsecond, {value, precision})
    else
      time ++ [{:microsecond, {value, precision}}]
    end
  end

  # Apply N steps of `add_unit` (or `subtract_unit` for negative N).
  # Simple iteration — correct for any calendar at the cost of
  # O(N) calls. For the durations we see in practice (months,
  # days, hours), this is fine; we can switch to calendar-specific
  # arithmetic if profiling demands it.
  defp apply_n_units(time, _unit, 0, _calendar), do: {:ok, time}

  # Fast path: adding N days to a concrete date is O(1) via its
  # Calendrical day number (`Calendrical.iso_days/4`), versus O(N) single-day
  # stepping. This is what keeps a large recurrence (`R10000/…/P1D`)
  # from being quadratic to materialise. Falls back to stepping for
  # anything that isn't a plain integer `[year, month, day]` prefix
  # (masks, groups, ranges, or a coarser shape).
  defp apply_n_units(time, :day, n, calendar) do
    case fast_add_days(time, n, calendar) do
      {:ok, new_time} -> {:ok, new_time}
      :fallback -> step_n_units(time, :day, n, calendar)
    end
  end

  # Fast path: adding N of a fixed-length sub-day unit (hour, minute,
  # second) to a concrete datetime is O(1) via seconds-of-day
  # arithmetic with a whole-day carry through Calendrical's `plus/5`, versus the
  # O(N) single-unit stepping below. Without it a high-frequency
  # recurrence (`FREQ=MINUTELY;COUNT=1440`) is quadratic to
  # materialise — occurrence i adds an i-unit duration. Falls back to
  # stepping for anything without an integer `[year, month, day, hour]`
  # prefix (partials, masks, groups).
  defp apply_n_units(time, unit, n, calendar) when unit in [:hour, :minute, :second] do
    case fast_add_time_of_day(time, unit, n, calendar) do
      {:ok, new_time} -> {:ok, new_time}
      :fallback -> step_n_units(time, unit, n, calendar)
    end
  end

  # A calendar with a traditional month numbering (Hebrew, the lunisolar
  # calendars) places a month one later after a leap month, so a month's
  # number changes from year to year. A year shift keeps the traditional
  # month, as the calendar's own `plus/6` does it: Nisan stays Nisan, and a
  # leap month the new year lacks becomes the month it follows or precedes.
  defp apply_n_units(time, :year, n, calendar) do
    case shift_years_by_calendar(time, n, calendar) do
      {:ok, new_time} -> {:ok, new_time}
      {:error, _reason} = error -> error
      :fallback -> step_n_units(time, :year, n, calendar)
    end
  end

  defp apply_n_units(time, unit, n, calendar), do: step_n_units(time, unit, n, calendar)

  # Only the year and month change; the day is clamped to the new month
  # once every unit has been applied (`maybe_clamp/3`).
  defp shift_years_by_calendar(time, n, calendar) do
    with true <- traditional_months?(calendar),
         {:ok, year} <- year_of(time),
         {:ok, month} <- component(time, :month),
         {new_year, new_month, _day} <- calendar.plus(year, month, 1, :years, n, []) do
      {:ok, time |> put_component(:year, new_year) |> put_component(:month, new_month)}
    else
      # A month's number depends on its year in these calendars, so a unit
      # that holds several months has no one numbering in the new year.
      :several -> {:error, :grouped_component}
      _other -> :fallback
    end
  end

  defp traditional_months?(calendar) do
    Code.ensure_loaded?(calendar) and
      function_exported?(calendar, :ordinal_month_from_traditional, 2) and
      function_exported?(calendar, :plus, 6)
  end

  # A valid date moves by the calendar's own `plus/5`; one that is not a
  # date (a day a month step has not yet clamped) steps instead.
  defp fast_add_days(time, n, calendar) do
    with {:ok, year} <- year_of(time),
         {:ok, month} <- component(time, :month),
         {:ok, day} <- component(time, :day),
         true <- calendar.valid_date?(year, month, day) do
      {year, month, day} = calendar.plus(year, month, day, :days, n)

      new_time =
        time
        |> put_component(:year, year)
        |> put_component(:month, month)
        |> put_component(:day, day)

      {:ok, new_time}
    else
      _ -> :fallback
    end
  end

  @seconds_in_day 86_400
  defp unit_seconds(:hour), do: 3600
  defp unit_seconds(:minute), do: 60
  defp unit_seconds(:second), do: 1

  # Add `n` sub-day units by seconds-of-day arithmetic. The time-of-day
  # is a resolution prefix (`hour` present, `minute`/`second` optional
  # and already extended by `ensure_resolution_for_duration/2`), so its
  # seconds are exact; whole days overflow through Calendrical's
  # `plus/5` (which rolls month/year in-calendar) and only the components
  # that were present are written back, preserving the value's
  # resolution. Wall clock, like the stepper — the zone rides on `shift`,
  # untouched.
  defp fast_add_time_of_day(time, unit, n, calendar) do
    with {:ok, year} <- year_of(time),
         {:ok, month} <- component(time, :month),
         {:ok, day} <- component(time, :day),
         {:ok, hour} <- component(time, :hour),
         {:ok, minute} <- clock_or_zero(time, :minute),
         {:ok, second} <- clock_or_zero(time, :second),
         {:ok, _date} <- Date.new(year, month, day, calendar) do
      total = hour * 3600 + minute * 60 + second + n * unit_seconds(unit)
      day_carry = Integer.floor_div(total, @seconds_in_day)
      rem_tod = Integer.mod(total, @seconds_in_day)

      {year, month, day} =
        calendar.plus(year, month, day, :days, day_carry)

      new_time =
        time
        |> put_component(:year, year)
        |> put_component(:month, month)
        |> put_component(:day, day)
        |> put_component(:hour, div(rem_tod, 3600))
        |> put_component(:minute, div(rem(rem_tod, 3600), 60))
        |> put_component(:second, rem(rem_tod, 60))

      {:ok, new_time}
    else
      _ -> :fallback
    end
  end

  # A clock unit the value does not track counts from zero, and is not
  # written back.
  defp clock_or_zero(time, unit) do
    case component(time, unit) do
      :untracked -> {:ok, 0}
      other -> other
    end
  end

  defp step_n_units(time, _unit, 0, _calendar), do: {:ok, time}

  defp step_n_units(time, unit, n, calendar) when n > 0 do
    with {:ok, stepped} <- add_unit(time, unit, calendar) do
      step_n_units(stepped, unit, n - 1, calendar)
    end
  end

  defp step_n_units(time, unit, n, calendar) when n < 0 do
    with {:ok, stepped} <- subtract_unit(time, unit, calendar) do
      step_n_units(stepped, unit, n + 1, calendar)
    end
  end

  # After month arithmetic, the day field may exceed days-in-month
  # (e.g. Jan 31 + 1 month = "Feb 31"). Clamp once at the end.
  defp clamp_day_to_month(time, calendar) do
    case {component(time, :day), component(time, :month)} do
      {:untracked, _month} -> {:ok, time}
      # Day-only value (no month): there is nothing to clamp the day against.
      {_day, :untracked} -> {:ok, time}
      {{:ok, day}, {:ok, month}} -> clamp_integer_day(time, month, day, calendar)
      {_day, month} -> keep_unclamped(time, largest_day(time), fewest_days(time, month, calendar))
    end
  end

  defp clamp_integer_day(time, month, day, calendar) do
    case year_of(time) do
      {:ok, year} -> {:ok, clamp_day_to_month_anchored(time, year, month, day, calendar)}
      _none_or_several -> clamp_day_to_month_unanchored(time, month, day, calendar)
    end
  end

  # A day no later than the fewest days the month has in any year needs no
  # year to confirm it, so the calendar is asked for the year's month length
  # only for a day past that.
  defp clamp_day_to_month_anchored(time, year, month, day, calendar) do
    if day <= fewest_days_in_month(calendar, month) do
      time
    else
      days = calendar.days_in_month(year, month)
      if day > days, do: put_component(time, :day, days), else: time
    end
  end

  # The fewest days `month` has in any year, as the calendar's yearless
  # `days_in_month/1` reports it; 0 when it cannot say.
  defp fewest_days_in_month(calendar, month) do
    if function_exported?(calendar, :days_in_month, 1) do
      case calendar.days_in_month(month) do
        days when is_integer(days) -> days
        {:ambiguous, first..last//_step} -> min(first, last)
        {:ambiguous, [_ | _] = lengths} -> Enum.min(lengths)
        _unbounded -> 0
      end
    else
      0
    end
  end

  # Clamp without a year: a day that fits every possible length of the
  # month is kept; one that overflows an unambiguous month is clamped;
  # anything whose validity depends on the missing year (a 29th/30th of
  # a variable-length month) is `{:error, :unanchored}`.
  defp clamp_day_to_month_unanchored(time, month, day, calendar) do
    case calendar.days_in_month(month) do
      count when is_integer(count) ->
        {:ok, if(day > count, do: put_component(time, :day, count), else: time)}

      {:ambiguous, range} ->
        if day <= Enum.min(range), do: {:ok, time}, else: {:error, :unanchored}

      _undefined ->
        {:error, :unanchored}
    end
  end

  # A day or a month that holds several — `{1,15}D`, `{6,7}M` — would be
  # clamped member by member, which no one value can show. The value stands
  # when no member needs clamping: the last day it names is in the shortest
  # month it could fall in. A masked or unspecified day (`XXD`, `X*D`) names
  # whatever days its month has, so it is never clamped.
  defp keep_unclamped(time, :every, _fewest), do: {:ok, time}

  defp keep_unclamped(time, largest, fewest) when is_integer(largest) and largest <= fewest,
    do: {:ok, time}

  defp keep_unclamped(_time, _largest, _fewest), do: {:error, :grouped_component}

  # The last day a value names, counted from either end of its month.
  defp largest_day(time) do
    case List.keyfind(time, :day, 0) do
      {:day, day} when is_integer(day) -> abs(day)
      {:day, days} when is_list(days) -> largest_listed(days)
      {:day, {:group, first..last//_step}} -> max(abs(first), abs(last))
      {:day, {:mask, _mask}} -> :every
      {:day, :any} -> :every
      _other -> :unknown
    end
  end

  defp largest_listed(days) do
    Enum.reduce_while(days, 0, fn
      day, largest when is_integer(day) ->
        {:cont, max(largest, abs(day))}

      first..last//_step, largest when is_integer(first) and is_integer(last) ->
        {:cont, Enum.max([largest, abs(first), abs(last)])}

      _other, _largest ->
        {:halt, :unknown}
    end)
  end

  # The fewest days the month a value names can have: the one month's days
  # in its year, or in any year when it names no one year; and for a month
  # that holds several, the days of the shortest month its calendar has.
  defp fewest_days(time, {:ok, month}, calendar) do
    case year_of(time) do
      {:ok, year} -> calendar.days_in_month(year, month)
      _none_or_several -> fewest_days_in_month(calendar, month)
    end
  end

  defp fewest_days(_time, _several, calendar) do
    case shortest_month(calendar) do
      {:ok, shortest} -> shortest
      {:error, _reason} -> 0
    end
  end

  @doc """
  Return the start-of-unit minimum value — used when a trailing
  unit is unspecified in a mixed-resolution comparison or when
  constructing the lower bound of an implicit span.

  ### Arguments

  * `unit` is any time unit atom.

  ### Returns

  * `1` for `:month`, `:day`, `:week`, `:day_of_year`, and
    `:day_of_week` — these count from 1.

  * `0` for every other unit (including `:hour`, `:minute`,
    `:second`, `:year`, and any unrecognised atom).

  ### Examples

      iex> Tempo.Math.unit_minimum(:month)
      1

      iex> Tempo.Math.unit_minimum(:hour)
      0

  """
  def unit_minimum(:month), do: 1
  def unit_minimum(:day), do: 1
  def unit_minimum(:week), do: 1
  def unit_minimum(:day_of_year), do: 1
  def unit_minimum(:day_of_week), do: 1
  def unit_minimum(_), do: 0

  ## ---------------------------------------------------------
  ## shift_skipping/3 — engine for `Tempo.shift/3` with `skipping:`
  ## ---------------------------------------------------------

  @doc false
  # Walks the origin through free time only: the gaps between busy
  # intervals consume the duration, busy spans are jumped at no cost,
  # and an origin inside a busy span is first ejected to its edge
  # (forward: the span's end; backward: its start). The duration must
  # be exact (week/day/hour/minute/second) — a month or year of "free
  # time" has no fixed length to consume.
  def shift_skipping(%Tempo{} = origin, %Tempo.Duration{} = duration, busy) do
    with :ok <- validate_anchored_origin(origin),
         :ok <- validate_exact_skipping(duration),
         {:ok, seconds} <- Duration.to_unit(duration, :second),
         {:ok, busy_set} <- normalize_busy(busy),
         :ok <- validate_busy_members(busy_set) do
      Interval.reject_mixed_frame!(origin, busy_set)

      case free_days(origin, duration) do
        {:ok, days} -> walk_days(origin, days, busy_set)
        :error -> walk_skipping(origin, seconds, busy_set)
      end
    end
  end

  # A day shifted by days, or by weeks of the days `Calendrical.weeks_to_days/1`
  # counts, steps from free day to free day, a calendar day at a time, and
  # lands on a day. Anything finer walks free time.
  defp free_days(origin, %Tempo.Duration{time: time}) do
    case normalise_duration(time) do
      [day: days] when is_integer(days) ->
        if day_resolution?(origin), do: {:ok, days}, else: :error

      _finer_units ->
        :error
    end
  end

  defp day_resolution?(origin) do
    {unit, _precision} = Tempo.resolution(origin)
    unit in [:day, :day_of_week, :day_of_year]
  end

  defp validate_anchored_origin(origin) do
    if Tempo.anchored?(origin) do
      :ok
    else
      {:error,
       UnanchoredError.exception(
         operation: "shift skipping busy time",
         value: origin,
         reason: :shift_skipping
       )}
    end
  end

  defp validate_exact_skipping(%Tempo.Duration{time: time}) do
    case Enum.find(time, fn {unit, amount} -> unit in [:year, :month] and amount != 0 end) do
      nil ->
        :ok

      {unit, _amount} ->
        {:error,
         InvalidUnitError.exception(
           unit: unit,
           valid_units: [:week, :day, :hour, :minute, :second]
         )}
    end
  end

  defp normalize_busy(busy) when is_list(busy) do
    busy
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case Tempo.to_interval(member) do
        {:ok, %Interval{} = interval} ->
          {:cont, {:ok, [interval | acc]}}

        {:ok, %IntervalSet{} = set} ->
          {:cont, {:ok, Enum.reverse(IntervalSet.members(set)) ++ acc}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, intervals} -> intervals |> Enum.reverse() |> IntervalSet.new() |> coalesce_busy()
      {:error, _} = error -> error
    end
  end

  defp normalize_busy(busy) do
    busy |> Tempo.to_interval_set() |> coalesce_busy()
  end

  defp coalesce_busy({:ok, %IntervalSet{} = set}) do
    if IntervalSet.bounded?(set), do: {:ok, IntervalSet.coalesce(set)}, else: {:ok, set}
  end

  defp coalesce_busy({:error, _} = error), do: error

  # A lazy busy set cannot be validated up front — its members are
  # checked as the walk consumes them (`span_payload/1`).
  defp validate_busy_members(%IntervalSet{} = set) do
    if IntervalSet.bounded?(set) do
      set |> IntervalSet.members() |> Enum.find_value(:ok, &busy_member_error/1)
    else
      :ok
    end
  end

  defp busy_member_error(%Interval{from: %Tempo{} = from, to: %Tempo{} = to}) do
    case Enum.reject([from, to], &Tempo.anchored?/1) do
      [] ->
        nil

      [endpoint | _rest] ->
        {:error,
         UnanchoredError.exception(
           operation: "use an interval as a `skipping:` busy span",
           value: endpoint
         )}
    end
  end

  defp busy_member_error(%Interval{} = interval) do
    {:error,
     IntervalEndpointsError.exception(
       operation: :shift_skipping,
       interval: interval,
       reason: :open_endpoint
     )}
  end

  # The walk runs on gregorian UTC seconds so gaps compare exactly
  # across calendars and zones. Spans stream off the busy set's walk —
  # sorted, disjoint, half-open `[from, to)` — so an unbounded lazy
  # busy set works: the forward walk only ever consumes successive
  # spans until it lands, and the backward walk materialises only the
  # finite prefix at or before the origin.
  defp walk_skipping(origin, seconds, %IntervalSet{} = busy_set) do
    origin_s = Compare.to_utc_seconds(origin)
    spans = busy_set |> IntervalSet.walk() |> Stream.map(&span_payload/1)

    if seconds >= 0 do
      walk_forward(origin, origin_s, seconds, spans)
    else
      prefix =
        spans
        |> Stream.take_while(fn {from_s, _to_s, _from, _to} -> from_s <= origin_s end)
        |> Enum.reverse()

      walk_backward(origin, origin_s, -seconds, prefix)
    end
  end

  # Days of free time from a day, as free time is walked: a busy origin first
  # moves out of its busy time, so a day forward from a busy day is the second
  # free day after it and a day back the first free day before it. Each step
  # is the calendar's next or previous day; a day busy time covers is passed.
  defp walk_days(origin, days, %IntervalSet{} = busy_set) do
    spans = busy_set |> IntervalSet.walk() |> Stream.map(&span_payload/1)
    step = if days < 0, do: -1, else: 1

    free_steps =
      cond do
        not busy_day?(origin, spans) -> abs(days)
        step == 1 -> days + 1
        true -> max(-days, 1)
      end

    nth_free_day(origin, free_steps, step, spans)
  end

  defp nth_free_day(day, 0, _step, _spans), do: day

  defp nth_free_day(day, count, step, spans) do
    case free_day_from(add(day, Duration.build(day: step)), step, spans) do
      %Tempo{} = free_day -> nth_free_day(free_day, count - 1, step, spans)
      error -> error
    end
  end

  defp free_day_from(%Tempo{} = day, step, spans) do
    if busy_day?(day, spans),
      do: free_day_from(add(day, Duration.build(day: step)), step, spans),
      else: day
  end

  defp free_day_from(error, _step, _spans), do: error

  # A day is busy when busy time covers the whole of it.
  defp busy_day?(day, spans) do
    day_from = Compare.to_utc_seconds(day)
    day_to = day |> Interval.to() |> Compare.to_utc_seconds()

    spans
    |> Stream.take_while(fn {from_s, _to_s, _from, _to} -> from_s <= day_from end)
    |> Enum.any?(fn {_from_s, to_s, _from, _to} -> day_to <= to_s end)
  end

  # A bounded busy set was validated up front; a lazy one is checked
  # member-by-member as the walk consumes it, raising the same
  # exceptions the eager validation returns.
  defp span_payload(%Interval{from: %Tempo{} = from, to: %Tempo{} = to} = interval) do
    if Tempo.anchored?(from) and Tempo.anchored?(to) do
      {Compare.to_utc_seconds(from), Compare.to_utc_seconds(to), from, to}
    else
      raise_busy_member!(interval)
    end
  end

  defp span_payload(%Interval{} = interval), do: raise_busy_member!(interval)

  @spec raise_busy_member!(Interval.t()) :: no_return()
  defp raise_busy_member!(interval) do
    {:error, exception} = busy_member_error(interval)
    raise exception
  end

  defp walk_forward(pos, pos_s, remaining, spans) do
    spans
    |> Enum.reduce_while({pos, pos_s, remaining}, fn
      {from_s, to_s, _from, to}, {pos, pos_s, remaining} ->
        cond do
          # Busy span entirely behind the position (its exclusive end
          # at or before us) — irrelevant.
          to_s <= pos_s ->
            {:cont, {pos, pos_s, remaining}}

          # Position inside `[from, to)` — eject to the span's end at
          # no cost, then keep walking.
          pos_s >= from_s ->
            {:cont, {to, to_s, remaining}}

          # The free run before this span satisfies what remains.
          # Equality lands exactly on the span's start: the duration is
          # fully consumed at the instant the busy time begins.
          remaining <= from_s - pos_s ->
            {:halt, {:landed, land(pos, remaining)}}

          true ->
            {:cont, {to, to_s, remaining - (from_s - pos_s)}}
        end
    end)
    |> case do
      {:landed, result} -> result
      {pos, _pos_s, remaining} -> land(pos, remaining)
    end
  end

  defp walk_backward(pos, _pos_s, remaining, []), do: land(pos, -remaining)

  defp walk_backward(pos, pos_s, remaining, [{from_s, to_s, from, _to} | rest]) do
    cond do
      # Busy span entirely ahead of the position.
      from_s > pos_s ->
        walk_backward(pos, pos_s, remaining, rest)

      # Position inside `[from, to)` — eject backward to the span's
      # start at no cost. The exclusive end (`pos_s == to_s`) is
      # already free, so it does not eject.
      pos_s < to_s ->
        walk_backward(from, from_s, remaining, rest)

      remaining <= pos_s - to_s ->
        land(pos, -remaining)

      true ->
        walk_backward(from, from_s, remaining - (pos_s - to_s), rest)
    end
  end

  defp land(pos, seconds) when seconds == 0, do: pos

  defp land(pos, seconds) do
    add(pos, Duration.build(second: integer_seconds(seconds)))
  end

  # `Duration.to_unit/2` returns a float magnitude; the walk's gap
  # arithmetic preserves integral values exactly, so an integral
  # float converts losslessly.
  defp integer_seconds(seconds), do: trunc(seconds)
end
