defmodule Tempo.Math do
  @moduledoc false

  alias Tempo.Compare
  alias Tempo.Duration
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidUnitError
  alias Tempo.Mask
  alias Tempo.NonAnchoredError
  alias Tempo.RequiresAnchorError

  @doc """
  Advance a `%Tempo{}` or a keyword-list time representation by
  exactly one unit at the given resolution.

  Uses `Keyword.replace!/3` (preserves position) rather than
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

  * The input with the unit advanced by 1, carrying into coarser
    units as needed. Shape matches the input — a `%Tempo{}` in
    yields a `%Tempo{}` out; a keyword list yields a keyword list.

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
      {:error, :requires_anchor}

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

  # On an un-anchored value (no `:year`) a whole-year step is a no-op: the
  # untracked year advances but the month/day/time axis is unchanged, so
  # "one year after January 31st" is January 31st. This is always unambiguous.
  def add_unit(time, :year, _calendar) when is_list(time) do
    if concrete_year?(time),
      do: {:ok, Keyword.update!(time, :year, &(&1 + 1))},
      else: {:ok, time}
  end

  def add_unit(time, :month, calendar) when is_list(time) do
    if scalar_component?(time, :month),
      do: add_month(time, calendar),
      else: {:error, :grouped_component}
  end

  def add_unit(time, :day, calendar) when is_list(time) do
    if concrete_year?(time) do
      year = Keyword.fetch!(time, :year)
      month = Keyword.fetch!(time, :month)
      day = Keyword.fetch!(time, :day)
      days_in_month = calendar.days_in_month(year, month)

      cond do
        day < days_in_month ->
          {:ok, Keyword.replace!(time, :day, day + 1)}

        month < calendar.months_in_year(year) ->
          {:ok,
           time
           |> Keyword.replace!(:month, month + 1)
           |> Keyword.replace!(:day, 1)}

        true ->
          {:ok,
           time
           |> Keyword.replace!(:year, year + 1)
           |> Keyword.replace!(:month, 1)
           |> Keyword.replace!(:day, 1)}
      end
    else
      advance_day_unanchored(time, calendar)
    end
  end

  def add_unit(time, :hour, calendar) when is_list(time) do
    case Keyword.fetch(time, :hour) do
      {:ok, value} -> add_hour(time, value, calendar)
      # The value does not track this unit, so the carry lands on an axis
      # it never had — nothing to change.
      :error -> {:ok, time}
    end
  end

  def add_unit(time, :minute, calendar) when is_list(time) do
    case Keyword.fetch(time, :minute) do
      {:ok, value} -> add_minute(time, value, calendar)
      # The value does not track this unit, so the carry lands on an axis
      # it never had — nothing to change.
      :error -> {:ok, time}
    end
  end

  def add_unit(time, :second, calendar) when is_list(time) do
    case Keyword.fetch(time, :second) do
      {:ok, value} -> add_second(time, value, calendar)
      # The value does not track this unit, so the carry lands on an axis
      # it never had — nothing to change.
      :error -> {:ok, time}
    end
  end

  # Step one unit-in-the-last-place at the microsecond's precision:
  # 10^(6 - precision) microseconds (1 ms for precision 3, 1 µs for
  # precision 6), carrying into the second at 1_000_000.
  def add_unit(time, :microsecond, calendar) when is_list(time) do
    {value, precision} = Keyword.fetch!(time, :microsecond)
    incremented = value + Integer.pow(10, 6 - precision)

    if incremented >= 1_000_000 do
      with {:ok, stepped} <-
             time |> Keyword.delete(:microsecond) |> add_unit(:second, calendar) do
        {:ok, stepped ++ [{:microsecond, {incremented - 1_000_000, precision}}]}
      end
    else
      {:ok, Keyword.replace(time, :microsecond, {incremented, precision})}
    end
  end

  def add_unit(time, :week, calendar) when is_list(time) do
    if concrete_year?(time) do
      add_week_anchored(time, calendar)
    else
      advance_week_unanchored(time)
    end
  end

  def add_unit(time, :day_of_year, calendar) when is_list(time) do
    year = Keyword.fetch!(time, :year)
    day_of_year = Keyword.fetch!(time, :day_of_year)
    days_in_year = calendar.days_in_year(year)

    if day_of_year < days_in_year do
      {:ok, Keyword.replace!(time, :day_of_year, day_of_year + 1)}
    else
      {:ok,
       time
       |> Keyword.replace!(:year, year + 1)
       |> Keyword.replace!(:day_of_year, 1)}
    end
  end

  def add_unit(time, :day_of_week, calendar) when is_list(time) do
    day_of_week = Keyword.fetch!(time, :day_of_week)
    days_in_week = calendar.days_in_week()

    if day_of_week < days_in_week do
      {:ok, Keyword.replace!(time, :day_of_week, day_of_week + 1)}
    else
      time
      |> Keyword.replace!(:day_of_week, 1)
      |> add_unit(:week, calendar)
    end
  end

  def add_unit(_time, unit, _calendar) do
    raise ArgumentError,
          "Cannot increment a Tempo at #{inspect(unit)} resolution — " <>
            "no increment rule is defined for this unit."
  end

  defp add_week_anchored(time, calendar) do
    year = Keyword.fetch!(time, :year)
    week = Keyword.fetch!(time, :week)
    {weeks_in_year, _days_in_last_week} = calendar.weeks_in_year(year)

    if week < weeks_in_year do
      {:ok, Keyword.replace!(time, :week, week + 1)}
    else
      {:ok,
       time
       |> Keyword.replace!(:year, year + 1)
       |> Keyword.replace!(:week, 1)}
    end
  end

  # Without a year the week count is 52 or 53 depending on the year, so a
  # week below 52 steps cleanly and the wrap needs an anchor.
  defp advance_week_unanchored(time) do
    week = Keyword.fetch!(time, :week)

    if week < 52,
      do: {:ok, Keyword.replace!(time, :week, week + 1)},
      else: {:error, :requires_anchor}
  end

  # A grouped component is `{unit, {:group, members}, size}` — a set of
  # blocks rather than one steppable value, and not even readable by
  # `Keyword.fetch!/2`. Report it instead of crashing four frames down.
  # `Keyword.*` needs every entry to be a 2-tuple; a grouped component is
  # a 3-tuple, so a list holding one cannot be read or updated that way.
  defp plain_keyword_list?(time), do: Enum.all?(time, &match?({_key, _value}, &1))

  defp scalar_component?(time, unit) do
    Enum.all?(time, fn
      {^unit, value} -> not is_tuple(value)
      {^unit, _value, _size} -> false
      _entry -> true
    end)
  end

  defp add_month(time, calendar) do
    if concrete_year?(time) do
      year = Keyword.fetch!(time, :year)
      month = Keyword.fetch!(time, :month)
      months_in_year = calendar.months_in_year(year)

      if month < months_in_year do
        {:ok, Keyword.replace!(time, :month, month + 1)}
      else
        {:ok,
         time
         |> Keyword.replace!(:year, year + 1)
         |> Keyword.replace!(:month, 1)}
      end
    else
      advance_month_unanchored(time, calendar)
    end
  end

  defp add_hour(time, hour, calendar) do
    if hour < 23 do
      {:ok, Keyword.replace!(time, :hour, hour + 1)}
    else
      time
      |> Keyword.replace!(:hour, 0)
      |> add_unit(:day, calendar)
    end
  end

  defp add_minute(time, minute, calendar) do
    if minute < 59 do
      {:ok, Keyword.replace!(time, :minute, minute + 1)}
    else
      time
      |> Keyword.replace!(:minute, 0)
      |> add_unit(:hour, calendar)
    end
  end

  defp add_second(time, second, calendar) do
    if second < 59 do
      {:ok, Keyword.replace!(time, :second, second + 1)}
    else
      time
      |> Keyword.replace!(:second, 0)
      |> add_unit(:minute, calendar)
    end
  end

  # ── Un-anchored arithmetic (no :year) ──────────────────────────
  #
  # A value with no `:year` lives on a repeating month/day axis. One principle
  # governs every case below, and any new case must be decided by it — not by
  # whatever the day-clamp happens to do:
  #
  #   Compute the shift when its result is invariant to the missing year;
  #   return `%Tempo.RequiresAnchorError{}` when the result would depend on the
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
  #     onto the new month can force an anchor (`1M31D` + `P1M` = "Feb 31").
  #   * A **day/week** step advances while the day stays within the month's
  #     *guaranteed* length; crossing a boundary whose position depends on the
  #     year errors (`2M28D` + `P1D` — Feb 29 or Mar 1?). A bare-day value
  #     (no month) advances while below the shortest month any month can be.
  #
  # `add/2` catches the internal `:requires_anchor` throw and converts it to the
  # error tuple, so callers see a value or a clean error, never a crash.

  # `Keyword.has_key?(time, :year)` is not the same question as "is this
  # value anchored". An unspecified year (`X*Y12M28D`, parsed as
  # `year: :any`) has the key but not a number, and every anchored branch
  # above either hands the year to a calendar function that guards
  # `is_integer/1` or does arithmetic on it. Asking for a concrete year
  # routes those values down the un-anchored path, which is what they are.
  # A grouped component is a 3-tuple (`{:year, {:group, …}, size}`), so the
  # time list is not always a valid keyword list and `Keyword.get/3` raises
  # on it. Match the pair shape directly instead.
  defp concrete_year?(time) do
    Enum.any?(time, fn
      {:year, value} -> is_integer(value)
      _entry -> false
    end)
  end

  defp advance_day_unanchored(time, calendar) do
    case Keyword.fetch(time, :day) do
      {:ok, day} -> advance_present_day(time, day, calendar)
      # No day component at all: the untracked day advances and the
      # value's own axis is unchanged.
      :error -> {:ok, time}
    end
  end

  defp advance_present_day(time, day, calendar) do
    case Keyword.fetch(time, :month) do
      {:ok, month} -> advance_day_in_month(time, day, calendar.days_in_month(month), calendar)
      # Day-only value (no month): the day advances while it stays valid in
      # *every* month; at the shortest month's length the roll-over depends on
      # the unknown month, so it needs an anchor.
      :error -> advance_day_no_month(time, day, calendar)
    end
  end

  defp advance_day_in_month(time, day, count, calendar) when is_integer(count) do
    if plain_keyword_list?(time) do
      advance_scalar_day_in_month(time, day, count, calendar)
    else
      {:error, :grouped_component}
    end
  end

  defp advance_day_in_month(time, day, {:ambiguous, range}, calendar) do
    cond do
      day < Enum.min(range) -> {:ok, Keyword.replace!(time, :day, day + 1)}
      day >= Enum.max(range) -> start_of_next_month_unanchored(time, calendar)
      true -> {:error, :requires_anchor}
    end
  end

  defp advance_day_in_month(_time, _day, _undefined, _calendar) do
    {:error, :requires_anchor}
  end

  defp advance_scalar_day_in_month(time, day, count, calendar) when is_integer(count) do
    if day < count,
      do: {:ok, Keyword.replace!(time, :day, day + 1)},
      else: start_of_next_month_unanchored(time, calendar)
  end

  defp advance_day_no_month(time, day, calendar) do
    case shortest_month(calendar) do
      {:ok, shortest} when day < shortest -> {:ok, Keyword.replace!(time, :day, day + 1)}
      {:ok, _shortest} -> {:error, :requires_anchor}
      {:error, _reason} = error -> error
    end
  end

  # The fewest days any month of the calendar can have. A day-only value's day
  # below this exists in every month (safe to advance); at or above it the
  # roll-over depends on which month, which the value doesn't carry.
  defp shortest_month(calendar) do
    case months_in_year_unanchored(calendar) do
      count when is_integer(count) -> shortest_of_months(calendar, 1..count)
      _undefined_or_ambiguous -> {:error, :requires_anchor}
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
      _undefined -> {:error, :requires_anchor}
    end
  end

  defp start_of_next_month_unanchored(time, calendar) do
    case advance_month_unanchored(time, calendar) do
      {:ok, advanced} -> {:ok, Keyword.replace!(advanced, :day, 1)}
      {:error, _reason} = error -> error
    end
  end

  defp advance_month_unanchored(time, calendar) do
    case Keyword.fetch(time, :month) do
      # No month field (a day-only value): a whole-month step leaves the day
      # axis unchanged — the untracked month simply advances.
      :error -> {:ok, time}
      {:ok, month} -> advance_month_present(time, month, months_in_year_unanchored(calendar))
    end
  end

  defp advance_month_present(time, month, count) when is_integer(count) do
    {:ok, Keyword.replace!(time, :month, if(month < count, do: month + 1, else: 1))}
  end

  defp advance_month_present(time, month, {:ambiguous, range}) do
    if month < Enum.min(range),
      do: {:ok, Keyword.replace!(time, :month, month + 1)},
      else: {:error, :requires_anchor}
  end

  defp advance_month_present(_time, _month, _undefined) do
    {:error, :requires_anchor}
  end

  # `months_in_year/0` is an optional calendar callback — a calendar
  # that can't state its month count without a year simply doesn't
  # implement it, so guard the call and treat its absence as "needs
  # an anchor".
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

  defp retreat_month_unanchored(time, calendar) do
    case Keyword.fetch(time, :month) do
      :error -> {:ok, time}
      {:ok, month} when month > 1 -> {:ok, Keyword.replace!(time, :month, month - 1)}
      {:ok, _month} -> retreat_to_last_month(time, calendar)
    end
  end

  defp retreat_to_last_month(time, calendar) do
    case months_in_year_unanchored(calendar) do
      count when is_integer(count) -> {:ok, Keyword.replace!(time, :month, count)}
      _undefined -> {:error, :requires_anchor}
    end
  end

  defp retreat_day_unanchored(time, calendar) do
    day = Keyword.fetch!(time, :day)

    case Keyword.fetch(time, :month) do
      {:ok, _month} when day > 1 ->
        {:ok, Keyword.replace!(time, :day, day - 1)}

      {:ok, month} when month > 1 ->
        end_of_previous_month_unanchored(time, month - 1, calendar)

      {:ok, _month} ->
        retreat_to_end_of_last_month(time, calendar)

      # Day-only value: retreating stays valid while the day is above the 1st;
      # the 1st's predecessor is the last day of an unknown month, so it needs
      # an anchor.
      :error ->
        if day > 1,
          do: {:ok, Keyword.replace!(time, :day, day - 1)},
          else: {:error, :requires_anchor}
    end
  end

  defp retreat_to_end_of_last_month(time, calendar) do
    case months_in_year_unanchored(calendar) do
      count when is_integer(count) -> end_of_previous_month_unanchored(time, count, calendar)
      _undefined -> {:error, :requires_anchor}
    end
  end

  defp end_of_previous_month_unanchored(time, previous_month, calendar) do
    case calendar.days_in_month(previous_month) do
      count when is_integer(count) ->
        {:ok,
         time
         |> Keyword.replace!(:month, previous_month)
         |> Keyword.replace!(:day, count)}

      _ambiguous_or_undefined ->
        {:error, :requires_anchor}
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

  * The input with the unit decremented by 1.

  ### Examples

      iex> Tempo.Math.subtract_unit(~o"2023Y1M1D", :day, Calendrical.Gregorian)
      {:ok, ~o"2022Y12M31D"}

      iex> Tempo.Math.subtract_unit(~o"2022Y1M", :month, Calendrical.Gregorian)
      {:ok, ~o"2021Y12M"}

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
  # un-anchored value leaves its month/day/time axis untouched.
  def subtract_unit(time, :year, _calendar) when is_list(time) do
    if concrete_year?(time),
      do: {:ok, Keyword.update!(time, :year, &(&1 - 1))},
      else: {:ok, time}
  end

  def subtract_unit(time, :month, calendar) when is_list(time) do
    if concrete_year?(time) do
      year = Keyword.fetch!(time, :year)
      month = Keyword.fetch!(time, :month)

      if month > 1 do
        {:ok, Keyword.replace!(time, :month, month - 1)}
      else
        prev_year = year - 1

        {:ok,
         time
         |> Keyword.replace!(:year, prev_year)
         |> Keyword.replace!(:month, calendar.months_in_year(prev_year))}
      end
    else
      retreat_month_unanchored(time, calendar)
    end
  end

  def subtract_unit(time, :day, calendar) when is_list(time) do
    if concrete_year?(time) do
      year = Keyword.fetch!(time, :year)
      month = Keyword.fetch!(time, :month)
      day = Keyword.fetch!(time, :day)

      cond do
        day > 1 ->
          {:ok, Keyword.replace!(time, :day, day - 1)}

        month > 1 ->
          prev_month = month - 1

          {:ok,
           time
           |> Keyword.replace!(:month, prev_month)
           |> Keyword.replace!(:day, calendar.days_in_month(year, prev_month))}

        true ->
          prev_year = year - 1
          prev_month = calendar.months_in_year(prev_year)

          {:ok,
           time
           |> Keyword.replace!(:year, prev_year)
           |> Keyword.replace!(:month, prev_month)
           |> Keyword.replace!(:day, calendar.days_in_month(prev_year, prev_month))}
      end
    else
      retreat_day_unanchored(time, calendar)
    end
  end

  def subtract_unit(time, :hour, calendar) when is_list(time) do
    hour = Keyword.fetch!(time, :hour)

    if hour > 0 do
      {:ok, Keyword.replace!(time, :hour, hour - 1)}
    else
      time
      |> Keyword.replace!(:hour, 23)
      |> subtract_unit(:day, calendar)
    end
  end

  def subtract_unit(time, :minute, calendar) when is_list(time) do
    minute = Keyword.fetch!(time, :minute)

    if minute > 0 do
      {:ok, Keyword.replace!(time, :minute, minute - 1)}
    else
      time
      |> Keyword.replace!(:minute, 59)
      |> subtract_unit(:hour, calendar)
    end
  end

  def subtract_unit(time, :second, calendar) when is_list(time) do
    second = Keyword.fetch!(time, :second)

    if second > 0 do
      {:ok, Keyword.replace!(time, :second, second - 1)}
    else
      time
      |> Keyword.replace!(:second, 59)
      |> subtract_unit(:minute, calendar)
    end
  end

  def subtract_unit(time, :week, calendar) when is_list(time) do
    year = Keyword.fetch!(time, :year)
    week = Keyword.fetch!(time, :week)

    if week > 1 do
      {:ok, Keyword.replace!(time, :week, week - 1)}
    else
      prev_year = year - 1
      {weeks, _} = calendar.weeks_in_year(prev_year)

      {:ok,
       time
       |> Keyword.replace!(:year, prev_year)
       |> Keyword.replace!(:week, weeks)}
    end
  end

  def subtract_unit(time, :day_of_year, calendar) when is_list(time) do
    year = Keyword.fetch!(time, :year)
    day_of_year = Keyword.fetch!(time, :day_of_year)

    if day_of_year > 1 do
      {:ok, Keyword.replace!(time, :day_of_year, day_of_year - 1)}
    else
      prev_year = year - 1

      {:ok,
       time
       |> Keyword.replace!(:year, prev_year)
       |> Keyword.replace!(:day_of_year, calendar.days_in_year(prev_year))}
    end
  end

  def subtract_unit(time, :day_of_week, calendar) when is_list(time) do
    day_of_week = Keyword.fetch!(time, :day_of_week)

    if day_of_week > 1 do
      {:ok, Keyword.replace!(time, :day_of_week, day_of_week - 1)}
    else
      time
      |> Keyword.replace!(:day_of_week, calendar.days_in_week())
      |> subtract_unit(:week, calendar)
    end
  end

  def subtract_unit(_time, unit, _calendar) do
    raise ArgumentError,
          "Cannot decrement a Tempo at #{inspect(unit)} resolution — " <>
            "no decrement rule is defined for this unit."
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

  The input Tempo must carry every unit referenced by the
  duration. If the duration has a `:hour` component but the Tempo
  is at year resolution, the Tempo is extended via
  `Tempo.extend_resolution/2` first.

  ### Arguments

  * `tempo` is any `t:Tempo.t/0`.
  * `duration` is any `t:Tempo.Duration.t/0`.

  ### Returns

  * A new `t:Tempo.t/0` with the duration applied.

  ### Examples

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
          | {:error, RequiresAnchorError.t() | :requires_anchor}
  def add(%Tempo{} = tempo, %Tempo.Duration{time: duration_time} = duration) do
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
      with {:ok, stepped} <- apply_n_units(time, unit, n, calendar) do
        {:ok, %{tempo | time: stepped}}
      end
    else
      :fallback
    end
  end

  defp fast_add(_tempo, _duration_time), do: :fallback

  # A plain crisp anchored datetime: an integer year/month/day prefix
  # with every remaining component a plain integer — no mask, no
  # `{value, opts}` annotation, no `{value, precision}` microsecond, no
  # range or group.
  defp plain_datetime?([{:year, y}, {:month, m}, {:day, d} | rest])
       when is_integer(y) and is_integer(m) and is_integer(d) do
    Enum.all?(rest, fn {_unit, value} -> is_integer(value) end)
  end

  defp plain_datetime?(_time), do: false

  # Un-anchored arithmetic that would depend on the missing year returns
  # `{:error, :requires_anchor}` from the stepper; name the value and the
  # duration here, where both are still in scope.
  defp add_general(%Tempo{} = tempo, %Tempo.Duration{} = duration) do
    case route_general(tempo, duration) do
      {:error, :requires_anchor} ->
        {:error, RequiresAnchorError.exception(value: tempo, duration: duration)}

      other ->
        other
    end
  end

  # Route to the mask path only when the shift actually reaches a mask.
  # A shift coarser than every mask (or a value with no masks) never
  # touches a masked component, so the crisp path shifts around them and
  # keeps the masks intact (`2020-XX` + `P1Y` → `2021-XX`).
  defp route_general(%Tempo{} = tempo, %Tempo.Duration{time: duration_time} = duration) do
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
  defp add_crisp(%Tempo{} = tempo, %Tempo.Duration{time: duration_time}) do
    {crisp_time, annotations} = strip_component_annotations(tempo.time)

    # Normalise weeks to days *before* extending resolution, so a `P1W` shift
    # extends the value to day resolution (not week) and the day arithmetic has
    # a `:day` slot to operate on — e.g. `~o"3M"` + `P1W` becomes `~o"3M8D"`.
    # A week-axis value (`[year, week]`) is the exception: it has a `:week`
    # slot and no `:day`, so weeks step natively via `add_unit(:week)` —
    # converting them to days would demand month/day keys the axis lacks.
    duration_time =
      if Keyword.has_key?(crisp_time, :week) do
        translate_week_axis_duration(duration_time)
      else
        normalise_duration(duration_time)
      end

    case ensure_resolution_for_duration(%{tempo | time: crisp_time}, duration_time) do
      {:error, _} = error ->
        error

      %Tempo{} = tempo ->
        with {:ok, shifted} <- apply_duration(tempo, duration_time) do
          {:ok, Map.update!(shifted, :time, &reapply_component_annotations(&1, annotations))}
        end
    end
  end

  # On the week axis a day of duration is a `:day_of_week` step —
  # `[year, week]` has no month/day slots, and `day_of_week` carries
  # into `:week` (and the week into the year) exactly as day-arithmetic
  # requires. `2026Y32W + P2D` is `2026Y32W3K`, and seven days later is
  # the next week's Monday.
  defp translate_week_axis_duration(duration_time) do
    case Keyword.pop(duration_time, :day, 0) do
      {0, rest} -> rest
      {days, rest} -> rest ++ [day_of_week: days]
    end
  end

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
      with {:ok, min_time} <- fill_masks(time, calendar, :min),
           {:ok, max_time} <- fill_masks(time, calendar, :max),
           {:ok, first} <- add_crisp(%{tempo | time: min_time}, duration),
           {:ok, last} <- add_crisp(%{tempo | time: max_time}, duration) do
        remask_or_set(masks, first, last)
      else
        {:error, :requires_anchor} ->
          {:error, RequiresAnchorError.exception(value: tempo, duration: duration)}
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
    |> Enum.drop_while(fn {_unit, value} -> not match?({:mask, _mask}, value) end)
    |> Enum.all?(fn {_unit, value} -> match?({:mask, _mask}, value) end)
  end

  defp shift_masked_disjoint(masked, duration) do
    intervals =
      Enum.map(masked, fn candidate ->
        {:ok, shifted} = add_crisp(candidate, duration)
        {:ok, interval} = Tempo.to_interval(shifted)
        interval
      end)

    {:ok, set} = IntervalSet.new(intervals)
    IntervalSet.coalesce(set)
  end

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
          | {:error, RequiresAnchorError.t()}
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

  # Weeks in a duration are unambiguously 7 days. Normalise to
  # days so the apply-duration loop doesn't need a `:week` clause.
  defp normalise_duration(duration_time) do
    {weeks, rest} = Keyword.pop(duration_time, :week, 0)

    case weeks do
      0 ->
        rest

      _ ->
        Keyword.update(rest, :day, weeks * 7, &(&1 + weeks * 7))
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
    duration_units = Keyword.keys(duration_time)

    @unit_order_coarse_to_fine
    |> Enum.reverse()
    |> Enum.find(&(&1 in duration_units))
  end

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
          n -> step_or_halt(apply_n_units(acc, unit, n, calendar))
        end
      end)
      |> thread_microsecond(Keyword.get(duration_time, :microsecond), calendar)

    # Only a month/year step can leave the day past the new month's length
    # ("Jan 31 + 1 month = Feb 31"); day/week/time steps already carry into the
    # next month as they go. Clamping only when a month or year is present
    # avoids a spurious anchor requirement for a value that already sits on an
    # ambiguous day — e.g. `~o"2M29D"` shifted by an hour keeps its 29th.
    with {:ok, new_time} <- maybe_clamp(stepped, duration_time, calendar) do
      {:ok, %{tempo | time: new_time}}
    end
  end

  defp step_or_halt({:ok, _time} = ok), do: {:cont, ok}
  defp step_or_halt({:error, _reason} = error), do: {:halt, error}

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
      case Keyword.get(time, :microsecond) do
        {v, p} -> {v, p}
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
    if Keyword.has_key?(time, :microsecond) do
      Keyword.replace(time, :microsecond, {value, precision})
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

  # Fast path: adding N days to a concrete date is O(1) via
  # absolute-day arithmetic (`Date.add/2`), versus O(N) single-day
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
  # arithmetic with a whole-day carry through `Date.add/2`, versus the
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

  defp apply_n_units(time, unit, n, calendar), do: step_n_units(time, unit, n, calendar)

  defp fast_add_days(time, n, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day),
         {:ok, date} <- Date.new(year, month, day, calendar) do
      shifted = Date.add(date, n)

      new_time =
        time
        |> Keyword.replace!(:year, shifted.year)
        |> Keyword.replace!(:month, shifted.month)
        |> Keyword.replace!(:day, shifted.day)

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
  # seconds are exact; whole days overflow through `Date.add/2` (which
  # rolls month/year in-calendar) and only the components that were
  # present are written back, preserving the value's resolution. Wall
  # clock, like the stepper — the zone rides on `shift`, untouched.
  defp fast_add_time_of_day(time, unit, n, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day),
         hour when is_integer(hour) <- Keyword.get(time, :hour),
         minute when is_integer(minute) <- Keyword.get(time, :minute, 0),
         second when is_integer(second) <- Keyword.get(time, :second, 0),
         {:ok, date} <- Date.new(year, month, day, calendar) do
      total = hour * 3600 + minute * 60 + second + n * unit_seconds(unit)
      day_carry = Integer.floor_div(total, @seconds_in_day)
      rem_tod = Integer.mod(total, @seconds_in_day)
      shifted = Date.add(date, day_carry)

      new_time =
        time
        |> Keyword.replace!(:year, shifted.year)
        |> Keyword.replace!(:month, shifted.month)
        |> Keyword.replace!(:day, shifted.day)
        |> Keyword.replace!(:hour, div(rem_tod, 3600))
        |> replace_if_present(:minute, div(rem(rem_tod, 3600), 60))
        |> replace_if_present(:second, rem(rem_tod, 60))

      {:ok, new_time}
    else
      _ -> :fallback
    end
  end

  defp replace_if_present(time, key, value) do
    if Keyword.has_key?(time, key), do: Keyword.replace!(time, key, value), else: time
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
    case Keyword.get(time, :day) do
      nil -> {:ok, time}
      day when is_integer(day) -> clamp_integer_day(time, day, calendar)
      _non_integer -> {:ok, time}
    end
  end

  defp clamp_integer_day(time, day, calendar) do
    cond do
      concrete_year?(time) -> {:ok, clamp_day_to_month_anchored(time, day, calendar)}
      Keyword.has_key?(time, :month) -> clamp_day_to_month_unanchored(time, day, calendar)
      # Day-only value (no month): there is nothing to clamp the day against.
      true -> {:ok, time}
    end
  end

  defp clamp_day_to_month_anchored(time, day, calendar) do
    year = Keyword.fetch!(time, :year)
    month = Keyword.fetch!(time, :month)
    days = calendar.days_in_month(year, month)

    if day > days, do: Keyword.replace!(time, :day, days), else: time
  end

  # Clamp without a year: a day that fits every possible length of the
  # month is kept; one that overflows an unambiguous month is clamped;
  # anything whose validity depends on the missing year (a 29th/30th of
  # a variable-length month) throws `:requires_anchor`.
  defp clamp_day_to_month_unanchored(time, day, calendar) do
    case calendar.days_in_month(Keyword.fetch!(time, :month)) do
      count when is_integer(count) ->
        {:ok, if(day > count, do: Keyword.replace!(time, :day, count), else: time)}

      {:ambiguous, range} ->
        if day <= Enum.min(range), do: {:ok, time}, else: {:error, :requires_anchor}

      _undefined ->
        {:error, :requires_anchor}
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
      walk_skipping(origin, seconds, busy_set)
    end
  end

  defp validate_anchored_origin(origin) do
    if Tempo.anchored?(origin) do
      :ok
    else
      {:error, RequiresAnchorError.exception(value: origin, reason: :shift_skipping)}
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
          {:cont, {:ok, Enum.reverse(IntervalSet.to_list(set)) ++ acc}}

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
      set |> IntervalSet.to_list() |> Enum.find_value(:ok, &busy_member_error/1)
    else
      :ok
    end
  end

  defp busy_member_error(%Interval{from: %Tempo{} = from, to: %Tempo{} = to}) do
    if Tempo.anchored?(from) and Tempo.anchored?(to) do
      nil
    else
      {:error,
       NonAnchoredError.exception(
         operation:
           "use a non-anchored interval as a busy span in `skipping:` " <>
             "(anchor it via `Tempo.anchor/2` first)"
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
