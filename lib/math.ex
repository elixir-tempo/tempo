defmodule Tempo.Math do
  @moduledoc false

  alias Tempo.AbstractSeasonError
  alias Tempo.Calendars
  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Enumeration
  alias Tempo.Enumeration.Zone
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidUnitError
  alias Tempo.Iso8601.Parser
  alias Tempo.Iso8601.Unit
  alias Tempo.Mask
  alias Tempo.Qualification
  alias Tempo.ResolutionError
  alias Tempo.TimeZoneDatabase
  alias Tempo.UnanchoredError
  alias Tempo.UnitValues
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
  def add_unit(time, :year, calendar) when is_list(time), do: step_year(time, 1, calendar)

  def add_unit(time, :month, calendar) when is_list(time) do
    case forward(time, :month) do
      {:ok, month} -> add_month(time, month, calendar)
      # The value does not track months, so the carry lands on an axis it
      # never had — nothing to change.
      :untracked -> {:ok, time}
      :several -> no_one_value(time, :month)
    end
  end

  def add_unit(time, :day, calendar) when is_list(time) do
    case day_by_the_calendar(time, 1, calendar) do
      {:ok, _stepped} = stepped -> stepped
      :by_count -> add_day_by_count(time, calendar)
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
      :several -> no_one_value(time, :week)
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

  # ── A day's step ──────────────────────────────────────────────
  #
  # The day after a day is the next of its month's days, and the first of
  # the next month after the last, which `Tempo.UnitValues` counts. In a
  # year that does not begin with its first month the days do not run in
  # the order of their numbers (1 January follows 31 December of the same
  # year, and the year turns within a month), and in a composite calendar a
  # month or a year is cut short where its calendars change, so the day
  # after a date there, and the day before, are the calendar's to say.

  defp day_by_the_calendar([{:year, year}, {:month, month}, {:day, day} | rest], by, calendar)
       when is_integer(year) and is_integer(month) and month > 0 and is_integer(day) and day > 0 do
    with true <- UnitValues.stepped_by_calendar?(year, calendar),
         true <- calendar.valid_date?(year, month, day),
         {year, month, day} <- calendar.plus(year, month, day, :days, by, []) do
      {:ok, [{:year, year}, {:month, month}, {:day, day} | rest]}
    else
      _by_count -> :by_count
    end
  end

  defp day_by_the_calendar(_time, _by, _calendar), do: :by_count

  defp add_day_by_count(time, calendar) do
    case {forward(time, :day), forward(time, :month)} do
      # The value does not track days, so the carry lands on an axis it
      # never had — nothing to change.
      {:untracked, _month} -> {:ok, time}
      {{:ok, day}, {:ok, month}} when is_integer(month) -> add_day(time, month, day, calendar)
      {{:ok, day}, :untracked} -> advance_day_no_month(time, day, calendar)
      {{:ok, day}, _several_months} -> advance_day_in_any_month(time, day, calendar)
      # The day after depends on which of its days.
      {:several, _month} -> no_one_value(time, :day)
    end
  end

  defp subtract_day_by_count(time, calendar) do
    case {backward(time, :day), backward(time, :month)} do
      # The value does not track days, so the borrow comes from an axis it
      # never had — nothing to change.
      {:untracked, _month} -> {:ok, time}
      {{:ok, day}, {:ok, _month}} -> previous_day(time, day, calendar)
      # In several months, or in none, the day before a day past the first
      # is the same in whatever month.
      {{:ok, day}, _no_one_month} when day > 1 -> {:ok, put_component(time, :day, day - 1)}
      # Day-only value: the 1st's predecessor is the last day of an unknown
      # month, so it needs a year.
      {{:ok, _first_day}, :untracked} -> {:error, :unanchored}
      # The day before depends on which of its days, or on which of its months.
      _several -> {:error, :grouped_component}
    end
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

  # The refusal for a unit that holds no one number to count from. A count
  # from the end in a value with no year (`2M-1D`, the last day of a
  # February) cannot be counted until the value is placed on one, so the
  # step is unanchored; anything else holds several values.
  defp no_one_value(time, unit) do
    case {:lists.keyfind(unit, 1, time), year_of(time)} do
      {{_unit, count}, :none} when is_integer(count) and count < 0 -> {:error, :unanchored}
      _several -> {:error, :grouped_component}
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

  # The year so many on is the calendar's to say: the Julian calendar has no
  # year 0, and the year after its -1 is 1 (`Tempo.UnitValues.years_on/3`).
  defp step_year(time, by, calendar) do
    case year_of(time) do
      {:ok, year} -> {:ok, put_component(time, :year, UnitValues.years_on(year, by, calendar))}
      :none -> {:ok, time}
      :several -> {:error, :grouped_component}
    end
  end

  defp year_after(year, calendar), do: UnitValues.years_on(year, 1, calendar)
  defp year_before(year, calendar), do: UnitValues.years_on(year, -1, calendar)

  # ── A step among a unit's values ──────────────────────────────
  #
  # `Tempo.UnitValues` is asked what follows a value among those its unit
  # takes after the units before it, and answers with the next, with `:last`,
  # where the step carries into the unit above, or that the answer depends on
  # a year the value does not have. It is one question for a value with a
  # year and for one with none, and the one place a unit's values are known.
  # A step that carries puts the unit it leaves at its first value.

  defp next_day_of_year(time, year, day, calendar) do
    case UnitValues.following(:day_of_year, day, time, calendar) do
      {:ok, next} ->
        {:ok, put_component(time, :day_of_year, next)}

      :last ->
        time
        |> put_component(:year, year_after(year, calendar))
        |> at_first(:day_of_year, calendar)

      {:error, _reason} ->
        {:error, :unanchored}
    end
  end

  # The week after a week is what the one implementation says it is. With no
  # year it says nothing: a year's weeks are counted by no calendar without a
  # year, so which week is a year's last is not known, and a week with no
  # year has no next week and so no span (decided 2026-10-04). It counted to
  # 52, ISO 8601's count for a Gregorian year, in every calendar.
  defp add_week(time, week, calendar) do
    case UnitValues.following(:week, week, time, calendar) do
      {:ok, next} -> {:ok, put_component(time, :week, next)}
      :last -> first_week_of_the_next_year(time, calendar)
      {:error, _reason} -> {:error, :unanchored}
    end
  end

  defp first_week_of_the_next_year(time, calendar) do
    case year_of(time) do
      {:ok, year} ->
        time |> put_component(:year, year_after(year, calendar)) |> at_first(:week, calendar)

      _none_or_several ->
        {:error, :unanchored}
    end
  end

  defp add_day_of_week(time, day, calendar) do
    case UnitValues.following(:day_of_week, day, time, calendar) do
      {:ok, next} ->
        {:ok, put_component(time, :day_of_week, next)}

      :last ->
        with {:ok, first_day} <- at_first(time, :day_of_week, calendar) do
          add_unit(first_day, :week, calendar)
        end

      {:error, _reason} ->
        {:error, :unanchored}
    end
  end

  defp add_month(time, month, calendar) do
    case UnitValues.following(:month, month, time, calendar) do
      {:ok, next} -> {:ok, put_component(time, :month, next)}
      :last -> first_month_of_the_next_year(time, calendar)
      {:error, _reason} -> {:error, :unanchored}
    end
  end

  # The month after the last of a year is the first of the next. A value
  # with no year has no year to move to and stays on its months, and one that
  # names several years has no one year to move to.
  defp first_month_of_the_next_year(time, calendar) do
    case year_of(time) do
      {:ok, year} ->
        time |> put_component(:year, year_after(year, calendar)) |> at_first(:month, calendar)

      :none ->
        at_first(time, :month, calendar)

      :several ->
        {:error, :grouped_component}
    end
  end

  defp add_day(time, month, day, calendar) do
    case UnitValues.following(:day, day, time, calendar) do
      {:ok, next} -> {:ok, put_component(time, :day, next)}
      :last -> first_day_of_the_next_month(time, month, calendar)
      {:error, _reason} -> {:error, :unanchored}
    end
  end

  defp first_day_of_the_next_month(time, month, calendar) do
    with {:ok, advanced} <- add_month(time, month, calendar) do
      at_first(advanced, :day, calendar)
    end
  end

  # Puts a unit at the first, or at the last, value it takes after the units
  # before it. The stepper names two reasons a step cannot be taken, and a
  # unit whose values cannot be counted is short of a year.
  defp at_first(time, unit, calendar) do
    case UnitValues.first(unit, time, calendar) do
      {:ok, first} -> {:ok, put_component(time, unit, first)}
      {:error, _reason} -> {:error, :unanchored}
    end
  end

  defp at_last(time, unit, calendar) do
    case UnitValues.last(unit, time, calendar) do
      {:ok, last} -> {:ok, put_component(time, unit, last)}
      {:error, _reason} -> {:error, :unanchored}
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
  # The calendar answers without a year, and `Tempo.UnitValues` is where it
  # is asked: the values a unit takes in every year, and those of the year
  # that has the most. Its `following/4` reads a value against the two, for
  # a day and a month alike. Applying the principle (Gregorian examples):
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
    case UnitValues.in_any_year(:month, [], calendar) do
      {:ok, months, months} -> shortest_of_months(calendar, months)
      _by_the_year_or_cannot_say -> {:error, :unanchored}
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
    case UnitValues.in_any_year(:day, [month: month], calendar) do
      {:ok, %Range{last: fewest}, _longest} -> {:ok, fewest}
      {:error, _cannot_say} -> {:error, :unanchored}
    end
  end

  # Mirrors of the advance helpers for `subtract_unit/3`.

  # The month before the first of a year is the last of the year before,
  # which a value with no year has where every year has as many months.
  defp last_month_of_previous_year(time, calendar) do
    case year_of(time) do
      {:ok, year} ->
        time |> put_component(:year, year_before(year, calendar)) |> at_last(:month, calendar)

      :none ->
        at_last(time, :month, calendar)

      :several ->
        {:error, :grouped_component}
    end
  end

  # The day before the first of a month is the last of the month before,
  # which a value with no year has where that month is as long in every year.
  defp last_day_of_the_month_before(time, calendar) do
    with {:ok, stepped} <- subtract_unit(time, :month, calendar) do
      at_last(stepped, :day, calendar)
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
  def subtract_unit(time, :year, calendar) when is_list(time), do: step_year(time, -1, calendar)

  def subtract_unit(time, :month, calendar) when is_list(time) do
    case backward(time, :month) do
      {:ok, month} -> previous_month(time, month, calendar)
      # The value does not track months, so the borrow comes from an axis
      # it never had — nothing to change.
      :untracked -> {:ok, time}
      :several -> {:error, :grouped_component}
    end
  end

  def subtract_unit(time, :day, calendar) when is_list(time) do
    case day_by_the_calendar(time, -1, calendar) do
      {:ok, _stepped} = stepped -> stepped
      :by_count -> subtract_day_by_count(time, calendar)
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
      {:ok, week} -> previous_week(time, week, calendar)
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
      {:ok, day} -> previous_day_of_week(time, day, calendar)
      :untracked -> {:ok, time}
      :several -> {:error, :grouped_component}
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

  # ── A step back among a unit's values ────────────────────────
  #
  # `Tempo.UnitValues` is asked what comes before a value, and answers with
  # the one before or with `:first`, where the step borrows from the unit
  # above and puts the unit it leaves at its last value.

  defp previous_month(time, month, calendar) do
    case UnitValues.preceding(:month, month, time, calendar) do
      {:ok, previous} -> {:ok, put_component(time, :month, previous)}
      :first -> last_month_of_previous_year(time, calendar)
      {:error, _reason} -> {:error, :unanchored}
    end
  end

  defp previous_day(time, day, calendar) do
    case UnitValues.preceding(:day, day, time, calendar) do
      {:ok, previous} -> {:ok, put_component(time, :day, previous)}
      :first -> last_day_of_the_month_before(time, calendar)
      {:error, _reason} -> {:error, :unanchored}
    end
  end

  defp previous_week(time, week, calendar) do
    case UnitValues.preceding(:week, week, time, calendar) do
      {:ok, previous} -> {:ok, put_component(time, :week, previous)}
      :first -> last_week_of_previous_year(time, calendar)
      {:error, _reason} -> {:error, :unanchored}
    end
  end

  # Without a year, the week before week 1 is the 52nd or the 53rd of the
  # year before, so it needs a year; any later week steps back cleanly.
  defp last_week_of_previous_year(time, calendar) do
    case year_of(time) do
      {:ok, year} ->
        time |> put_component(:year, year_before(year, calendar)) |> at_last(:week, calendar)

      :none ->
        {:error, :unanchored}

      :several ->
        {:error, :grouped_component}
    end
  end

  defp previous_day_of_year(time, year, day, calendar) do
    case UnitValues.preceding(:day_of_year, day, time, calendar) do
      {:ok, previous} ->
        {:ok, put_component(time, :day_of_year, previous)}

      :first ->
        time
        |> put_component(:year, year_before(year, calendar))
        |> at_last(:day_of_year, calendar)

      {:error, _reason} ->
        {:error, :unanchored}
    end
  end

  defp previous_day_of_week(time, day, calendar) do
    case UnitValues.preceding(:day_of_week, day, time, calendar) do
      {:ok, previous} ->
        {:ok, put_component(time, :day_of_week, previous)}

      :first ->
        with {:ok, last_day} <- at_last(time, :day_of_week, calendar) do
          subtract_unit(last_day, :week, calendar)
        end

      {:error, _reason} ->
        {:error, :unanchored}
    end
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

  # A season of 21 to 24 has no dates until it has a hemisphere, so it steps
  # by whole years and by nothing else: the spring of the year after is a
  # season as this one is, where a month or a day on is counted from dates
  # it does not have.
  def add(
        %Tempo{time: [{:year, _year}, {:season, _season} | _units]} = tempo,
        %Tempo.Duration{time: duration_time} = duration
      ) do
    if Enum.all?(duration_time, &match?({:year, _years}, &1)),
      do: add_rule_or_value(tempo, duration),
      else: {:error, AbstractSeasonError.exception(value: tempo, operation: "shift")}
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
      nil -> stepped_value(tempo, duration)
      unit -> {:error, rule_unit_error(tempo, unit)}
    end
  end

  defp month_or_year_step?({unit, amount}), do: unit in [:year, :month] and amount != 0

  defp add_to_value(tempo, duration) do
    case wall_zone(tempo) do
      nil -> tempo |> add_wall(duration) |> landed_in_its_zone(duration)
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

  # A value coarser than a day in a zone (a month, a week, a year) is stepped
  # on the wall clock, and what a step of days or of hours from it lands on
  # is a date or a time in that zone: one the clock skips is moved as a step
  # from a date is (`settle/4`). Four days on from the last week of 2011 in
  # Samoa was 30 December, which the zone left out.
  defp landed_in_its_zone(
         %Tempo{extended: %{zone_id: zone}, shift: shift} = landed,
         %Tempo.Duration{time: step}
       )
       when is_binary(zone) and zone != "" and zone not in @fixed_zones do
    if zoned_datetime?(landed.time), do: settle(landed, zone, shift, step), else: landed
  end

  defp landed_in_its_zone(landed, _duration), do: landed

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
      %Tempo{} = stepped -> settle(stepped, zone, shift, calendar)
      other -> other
    end
  end

  # A day, a month or a year names no reading of the clock; only a value
  # with a time of day can land in a gap or a fold.
  #
  # A date lands in one gap: the day its zone leaves out (Samoa had no
  # 30 December 2011). It is then the day after, or the day before where the
  # step runs back, as the calendar there went from the 29th to the 31st. It
  # was left on the day, which no value is read as.
  #
  # A date written with an offset is at the offset its zone is at when the
  # day begins: the day after the clocks go forward begins at another than
  # the day they go forward on, and was given that day's.
  defp settle(%Tempo{time: time} = stepped, zone, shift, step) do
    cond do
      Keyword.has_key?(time, :hour) ->
        settle_time_of_day(stepped, zone, shift)

      on_a_day_left_out?(stepped) ->
        stepped |> add_wall(%Tempo.Duration{time: [day: direction(step)]}) |> at_its_offset()

      true ->
        at_its_offset(stepped)
    end
  end

  # A time of day written with no offset is moved only where the clock
  # skips it, so one nowhere near a change of its zone's clock is where it
  # landed, and the zone database is not asked: each step of a rule of days,
  # weeks or months in a zone asked it, at 130 µs a question past the years
  # the database holds a table for.
  defp settle_time_of_day(stepped, zone, shift) do
    if is_nil(shift) and Zone.clear_of_changes?(stepped, 0) do
      stepped
    else
      reading = TimeZoneDatabase.period_at_wall(zone, wall_reading(stepped))
      settle_reading(stepped, shift, reading)
    end
  end

  defp at_its_offset(%Tempo{} = landed), do: Zone.at_its_offset(landed)
  defp at_its_offset(other), do: other

  # A week stepped by days is a day of that week until the step is done
  # (`add_where_built/2`), and is asked as the calendar date it names: four
  # days on from the last week of 2011 in Samoa is its Friday, 30 December.
  defp on_a_day_left_out?(%Tempo{} = stepped),
    do: stepped |> Validation.calendar_date_from_week_date() |> Zone.on_a_day_left_out?()

  defp direction(step) do
    case Enum.find(step, fn {_unit, amount} -> amount != 0 end) do
      {_unit, amount} when amount < 0 -> -1
      _forward -> 1
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

  # A step by time passed from a value nowhere near a change of its zone's
  # clock lands on the reading its wall clock steps to, at the offset it
  # started at, and that reading is shown once: the step is the wall
  # clock's, and nothing is asked of the zone database, which the step was
  # asked three times for. A value written with an offset is stepped as it
  # was, its offset being read where it lands.
  defp step_elapsed(stepped, clock, zone, shift) do
    if is_nil(shift) and Zone.clear_of_changes?(stepped, clock_seconds(clock)),
      do: add_wall(stepped, %Tempo.Duration{time: clock}),
      else: step_on_the_time_line(stepped, clock, zone, shift)
  end

  # The step's start reads its offset as its wall reading less its instant,
  # the offset `Tempo.Compare.to_utc_seconds/1` resolved it with.
  defp step_on_the_time_line(stepped, clock, zone, shift) do
    from_utc = trunc(Compare.to_utc_seconds(stepped))
    before = wall_reading(stepped) - from_utc
    to_utc = from_utc + clock_seconds(clock)
    later = offset_at(zone, to_utc, before)

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

  defp offset_as_written(offset, shift), do: Zone.offset_as_written(offset, shift)

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

  # The offset a zone has at an instant. A zone the database does not know
  # has no change of its clock to land past, so the value keeps the offset
  # it is read by.
  defp offset_at(zone, utc_seconds, otherwise) do
    case TimeZoneDatabase.period_at_utc(zone, utc_seconds) do
      {:ok, period} -> total_offset(period)
      {:error, _reason} -> otherwise
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

  # A whole number of months or of years added to a plain date is as common,
  # the step of every rule of months and of years, and its prelude is as
  # empty: the value holds no mask and no annotation, is no week date and
  # no day of the year, and its calendar does not step its own dates, so the
  # general path comes down to the months counted on and the day brought
  # into the month they land in (`apply_duration/2`). It took four times a
  # step of days.
  defp fast_add(%Tempo{time: time} = tempo, [{unit, n}] = duration_time)
       when unit in [:month, :year] and is_integer(n) do
    if plain_datetime?(time) and not stepped_by_its_calendar?(tempo),
      do: fast_stepped(apply_duration(tempo, duration_time)),
      else: :fallback
  end

  defp fast_add(_tempo, _duration_time), do: :fallback

  defp fast_stepped({:ok, %Tempo{}} = stepped), do: stepped
  defp fast_stepped({:error, _reason}), do: :fallback

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

      # A mask no value matches, or one on a unit with no range to narrow to.
      {:error, {reason, _unit} = unreadable} when reason in [:no_candidates, :unmaskable] ->
        {:error, Mask.error(tempo, unreadable)}

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

  # A value's masks and unspecified units stand for several values. A step
  # coarser than every one of them never touches a masked unit, so the crisp
  # path shifts around them (`2020-XX` + `P1Y` → `2021-XX`), and they are
  # kept where they still stand for what the values land on
  # (`kept_where_the_masks_stand_for_it/3`): the mask path is for a step that
  # reaches one, and for one that does not leave the masks standing.
  #
  # That holds where the values a mask stands for take the step alike. They
  # do not in a named zone, where a step of hours, minutes or seconds is
  # time on the time line and differs across a change of the clock; in a
  # calendar whose dates are stepped by the calendar and not by counting on
  # through their numbers; or where a week and a day of it, which are the
  # date they name in a calendar of months, are stepped by months or years,
  # which that date takes and its week does not. There every mask is on the
  # mask path, and each value it stands for is stepped as the one value it
  # is.
  defp route_general(%Tempo{} = tempo, %Tempo.Duration{time: duration_time} = duration) do
    if elapsed_in_a_zone?(tempo, duration_time) or stepped_by_its_calendar?(tempo) or
         week_date_stepped_as_a_date?(tempo, duration_time),
       do: route_value_by_value(tempo, duration),
       else: route_on_wall_clock(tempo, duration)
  end

  defp route_on_wall_clock(tempo, %Tempo.Duration{time: duration_time} = duration) do
    masked = unspecified_as_masks(tempo, duration_time)
    masks = find_masks(masked.time)

    if Enum.any?(masks, fn {unit, _mask} -> duration_reaches?(duration_time, unit) end),
      do: shift_past_masks(tempo, masked, duration),
      else: shift_coarser_than_masks(tempo, duration)
  end

  defp shift_coarser_than_masks(tempo, duration) do
    tempo
    |> shift_each_or_crisp(duration)
    |> stepped_or_each_candidate(tempo, duration)
    |> kept_where_the_masks_stand_for_it(tempo, duration)
  end

  # A step coarser than a mask passes it by, and the mask is kept where it
  # still stands for what its values land on, and for nothing else (decided
  # 2026-10-06). A month on from some day of January is some day of
  # February, each of whose days one of them lands on. A month on from some
  # day of June is one of 1 to 30 July: no day of June lands on the 31st,
  # which the mask moved to July would name. There the values landed on are
  # the answer, as they are for a step that counts from the mask.
  #
  # Only a date's units are counted within the units before them (a month's
  # days, a year's weeks), so a mask on a time of day stands for what it did
  # wherever its date lands, and the dates alone are asked.
  defp kept_where_the_masks_stand_for_it({:ok, %Tempo{} = passed_by} = kept, tempo, duration) do
    masked = unspecified_as_masks(tempo, :every)
    dates = dates_of(masked)

    case stand_for_what_is_landed_on(dates, dates_of(passed_by), duration) do
      :stood_for -> kept
      # The value's own candidates were each stepped to find that the masks
      # do not stand for what they land on, and are the answer: they were
      # stepped a second time for it.
      {:stepped, landed} when dates == masked -> spans_landed_on(landed)
      _not_stood_for -> shift_masked(tempo, masked, duration)
    end
  end

  defp kept_where_the_masks_stand_for_it(answer, _tempo, _duration), do: answer

  defp dates_of(%Tempo{time: time} = value), do: %{value | time: dated(time)}

  # `from` is the dates of the value that is stepped, and `onto` those of the
  # value the stepper gives, its masks moved with it.
  #
  # Where each is one run of values, and the step keeps a run a run, they
  # are the same values where they begin and end on the same ones: two
  # steps answer. Otherwise each value `from` stands for is stepped, and
  # they are held to those `onto` stands for.
  #
  # `:stood_for` where the masks stand for what is landed on, and otherwise
  # `:not_stood_for`, or `{:stepped, landed}` with each value landed on, in
  # the order of the values stepped, where each was stepped to say so.
  defp stand_for_what_is_landed_on(%Tempo{time: time} = from, onto, duration) do
    cond do
      find_masks(time) == [] -> :stood_for
      same_values?(from, onto) -> :stood_for
      block_stays_whole?(from, duration) -> ends_stood_for(from, onto, duration)
      true -> each_stood_for(from, onto, duration)
    end
  end

  defp ends_stood_for(from, onto, duration) do
    if ends_landed_on(from, duration) == ends_of(onto), do: :stood_for, else: :not_stood_for
  end

  defp each_stood_for(from, onto, duration) do
    with {:ok, candidates} <- candidates_of(from),
         {:ok, landed} <- each_stepped(candidates, duration) do
      on = landed |> Enum.map(& &1.time) |> Enum.sort() |> Enum.dedup()
      if on == stood_for(onto), do: :stood_for, else: {:stepped, Enum.reverse(landed)}
    else
      _no_candidates_or_no_step -> :not_stood_for
    end
  end

  # The spans of values already stepped, as `shift_each_candidate/2` gives
  # those it steps.
  defp spans_landed_on(landed) do
    with {:ok, spans} <- each_span(landed),
         {:ok, set} <- IntervalSet.new(spans) do
      IntervalSet.coalesce(set)
    end
  end

  defp each_span(landed) do
    landed
    |> Enum.reduce_while({:ok, []}, fn stepped, {:ok, spans} ->
      case one_span(Tempo.to_interval(stepped)) do
        {:ok, span} -> {:cont, {:ok, [span | spans]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, spans} -> {:ok, Enum.reverse(spans)}
      {:error, _reason} = error -> error
    end
  end

  # Whether each masked unit takes the same values where the value is and
  # where the stepper puts it, under each value of a masked unit before it.
  # Every value a mask stands for then lands on its own number, and the mask
  # stands for them still: the days of June are the days of the June a year
  # on, and no value need be stepped to say so. A unit written after a mask
  # is held to being a value in both, or in neither: the 29th of some month
  # of 2027 is of eleven months, and of twelve in 2028.
  defp same_values?(%Tempo{time: from, calendar: calendar}, %Tempo{} = onto) do
    %Tempo{time: onto} = unspecified_as_masks(onto, :every)
    same_values?(from, onto, {[], []}, false, calendar)
  end

  defp same_values?([], [], _context, _under_a_mask?, _calendar), do: true

  defp same_values?(
         [{unit, value} | from],
         [{unit, landed} | onto],
         {before, landed_before},
         false,
         calendar
       )
       when is_integer(value) and is_integer(landed) do
    context = {before ++ [{unit, value}], landed_before ++ [{unit, landed}]}
    same_values?(from, onto, context, false, calendar)
  end

  defp same_values?([{unit, value} | from], [{unit, value} | onto], context, true, calendar)
       when is_integer(value) do
    {before, landed_before} = context

    if a_value_in_both_or_neither?(value, values_in_both(unit, context, calendar)) do
      context = {before ++ [{unit, value}], landed_before ++ [{unit, value}]}
      same_values?(from, onto, context, true, calendar)
    else
      false
    end
  end

  defp same_values?(
         [{unit, {:mask, mask}} | from],
         [{unit, {:mask, mask}} | onto],
         context,
         _under_a_mask?,
         calendar
       ) do
    case values_in_both(unit, context, calendar) do
      {values, values} -> under_each_value?(values, unit, from, onto, context, calendar)
      _other_values -> false
    end
  end

  defp same_values?(_from, _onto, _context, _under_a_mask?, _calendar), do: false

  defp a_value_in_both_or_neither?(value, {values, landed_values}),
    do: value in values == value in landed_values

  defp a_value_in_both_or_neither?(_value, :unknown), do: false

  defp under_each_value?(_values, _unit, [], [], _context, _calendar), do: true

  defp under_each_value?(values, unit, from, onto, {before, landed_before}, calendar) do
    Enum.all?(values, fn value ->
      context = {before ++ [{unit, value}], landed_before ++ [{unit, value}]}
      same_values?(from, onto, context, true, calendar)
    end)
  end

  # The values a unit takes where the value is and where it lands, as two
  # ranges, or `:unknown` where either depends on what the value does not
  # hold or is of a calendar that lists them.
  defp values_in_both(unit, {before, landed_before}, calendar) do
    with {:ok, %Range{} = values} <- UnitValues.in_period(unit, before, calendar),
         {:ok, %Range{} = landed_values} <- UnitValues.in_period(unit, landed_before, calendar) do
      {values, landed_values}
    else
      _not_known -> :unknown
    end
  end

  # The first and the last value of a run, stepped.
  defp ends_landed_on(%Tempo{time: time, calendar: calendar} = from, duration) do
    with {:ok, min_time} <- fill_masks(time, calendar, :min),
         {:ok, max_time} <- fill_masks(time, calendar, :max),
         {:ok, first} <- stepped_candidate(%{from | time: min_time}, duration),
         {:ok, last} <- stepped_candidate(%{from | time: max_time}, duration) do
      {first.time, last.time}
    end
  end

  # The first and the last value a masked value stands for, where they are
  # one run: a value that is no run, or stands for none (the thirties of
  # February), begins and ends nowhere.
  defp ends_of(%Tempo{calendar: calendar} = onto) do
    %Tempo{time: time} = masked = unspecified_as_masks(onto, :every)

    with true <- one_run?(time, [], calendar),
         {:ok, min_time} <- fill_masks(time, calendar, :min),
         {:ok, max_time} <- fill_masks(time, calendar, :max) do
      {as_answered(%{masked | time: min_time}).time, as_answered(%{masked | time: max_time}).time}
    else
      _no_run -> :no_run
    end
  end

  # A value as a step answers with it: a week and a day of it in a calendar
  # of months, and a day of the year, are the date they name.
  defp as_answered(%Tempo{} = value) do
    value
    |> Validation.calendar_date_from_week_date()
    |> Validation.calendar_date_from_ordinal_date()
  end

  defp each_stepped(candidates, duration) do
    Enum.reduce_while(candidates, {:ok, []}, fn candidate, {:ok, landed} ->
      case stepped_candidate(candidate, duration) do
        {:ok, stepped} -> {:cont, {:ok, [stepped | landed]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp stood_for(onto) do
    case candidates_of(onto) do
      {:ok, candidates} -> candidates |> Enum.map(&as_answered(&1).time) |> Enum.sort()
      {:error, _reason} -> :none
    end
  end

  # A step coarser than a mask can still depend on what the mask stands for:
  # a year on from the 31st of some month is the 31st of a month that has
  # one, which the stepper has no one value to say. Each candidate is then
  # stepped. A value with no mask keeps the refusal.
  defp stepped_or_each_candidate({:error, :grouped_component} = refused, tempo, duration) do
    masked = unspecified_as_masks(tempo, :every)

    case find_masks(masked.time) do
      [] -> refused
      _masks -> shift_masked(tempo, masked, duration)
    end
  end

  defp stepped_or_each_candidate(answer, _tempo, _duration), do: answer

  defp route_value_by_value(tempo, duration) do
    masked = unspecified_as_masks(tempo, :every)

    case find_masks(masked.time) do
      [] -> shift_each_or_crisp(tempo, duration)
      _masks -> shift_masked(tempo, masked, duration)
    end
  end

  defp week_date_stepped_as_a_date?(%Tempo{time: time, calendar: calendar}, duration_time) do
    List.keymember?(time, :week, 0) and List.keymember?(time, :day_of_week, 0) and
      Enum.any?(duration_time, &month_or_year_step?/1) and
      not Tempo.week_based_calendar?(Calendars.effective(calendar))
  end

  # Whether a date of the value's calendar is stepped by the calendar: a
  # composite calendar, and one whose year does not begin with its first
  # month (`Tempo.UnitValues.stepped_by_calendar?/2`).
  defp stepped_by_its_calendar?(%Tempo{time: time, calendar: calendar}) do
    years =
      case List.keyfind(time, :year, 0) do
        {:year, held} -> held
        _no_year -> nil
      end

    UnitValues.stepped_by_calendar?(years, Calendars.effective(calendar))
  end

  # Whether a step counts elapsed time for a value in a zone whose offset
  # changes (`wall_zone/1` is the zone of one whole date and time).
  defp elapsed_in_a_zone?(%Tempo{extended: %{zone_id: zone}}, duration_time)
       when is_binary(zone) and zone != "" and zone not in @fixed_zones do
    not String.starts_with?(zone, "Etc/GMT") and Enum.any?(duration_time, &clock_step?/1)
  end

  defp elapsed_in_a_zone?(%Tempo{}, _duration_time), do: false

  defp clock_step?({unit, amount}), do: unit in @clock_units and amount != 0

  # A step that reaches a mask need not count from it: an hour on from some
  # day of June is 01:00 of some day of June, and the day after the 15th of
  # some month is its 16th. The stepper refuses to count from a masked unit
  # and passes one by where every value it stands for takes the step alike,
  # so where it steps the masked value the masks are kept, and the value is
  # stepped as it is written. A day of the year is not a unit the stepper
  # counts in: a value that holds one is the dates it names, each stepped as
  # the date it is.
  #
  # The masks are kept only where they still stand for what the candidates
  # land on. The day before the 31st of some month is the 30th of a month
  # that has a 31st, and `XXM30D` is the 30th of four more.
  defp shift_past_masks(tempo, %Tempo{time: time} = masked, duration) do
    if List.keymember?(time, :day_of_year, 0) do
      shift_masked(tempo, masked, duration)
    else
      case add_crisp(masked, duration) do
        {:ok, passed_by} -> masks_kept_or_stepped(tempo, masked, passed_by, duration)
        {:error, reason} when is_atom(reason) -> shift_masked(tempo, masked, duration)
        {:error, _exception} = error -> error
      end
    end
  end

  defp masks_kept_or_stepped(tempo, masked, passed_by, duration) do
    if as_many_candidates?(masked, passed_by),
      do: add_crisp(tempo, duration),
      else: shift_masked(tempo, masked, duration)
  end

  # Every candidate takes the step alike, so each lands on a candidate of
  # the value the stepper gives, and the two stand for the same values where
  # they stand for as many. A step that changes the time of day alone leaves
  # the dates as they were, and needs no count.
  defp as_many_candidates?(%Tempo{time: time} = masked, %Tempo{time: stepped_time} = passed_by) do
    dated(time) == dated(stepped_time) or
      as_many?(candidate_count(masked), candidate_count(passed_by))
  end

  # More candidates than are listed at once are not counted, so nothing says
  # the two stand for as many: each candidate is stepped, which is refused
  # for as many as that (`candidates_of/1`).
  defp as_many?(:too_many, _count), do: false
  defp as_many?(count, count), do: true
  defp as_many?(_count, _another), do: false

  defp dated(time), do: Enum.reject(time, &clock_entry?/1)

  defp clock_entry?(entry), do: is_tuple(entry) and elem(entry, 0) in @clock_units

  defp candidate_count(masked) do
    case Enumeration.members(masked) do
      {:ok, candidates} -> Enum.count(candidates)
      {:error, %ConversionError{reason: :too_many_values}} -> :too_many
      {:error, _exception} -> :none
    end
  end

  # A value that holds a set or a range, and nothing else that names several
  # values, is the values it names, and each is stepped. Any other is stepped
  # as it stands: one value, or one whose mask or group the step passes by.
  #
  # A margin of error and significant digits ride on the unit they are
  # written on, as they do on one value (`add_crisp_units/2`), so the values
  # are those of the value without them.
  defp shift_each_or_crisp(%Tempo{time: time} = tempo, duration) do
    {crisp_time, annotations} = strip_component_annotations(time)

    case Enumeration.expand(%{tempo | time: crisp_time}) do
      {:ok, values} -> shift_each(values, tempo, duration, annotations)
      {:error, _exception} = error -> error
      :not_expandable -> add_crisp(tempo, duration)
    end
  end

  # Coarse → fine. A duration "reaches" a mask when it carries a
  # non-zero component at the masked unit or finer (which is where the
  # arithmetic reads or writes the masked value).
  @unit_depth [year: 0, month: 1, week: 2, day: 2, hour: 3, minute: 4, second: 5, microsecond: 6]

  # A day of the year is counted from the year's start, so a step by any
  # unit moves it: a month on from the hundredth day is another day of the
  # year, and a year on from the hundredth day of a leap year is the
  # ninety-ninth of the next.
  defp duration_reaches?(duration_time, :day_of_year),
    do: Enum.any?(duration_time, fn {_unit, amount} -> amount != 0 end)

  # A week keeps its days, so a step of whole weeks, or of years, passes a
  # day of the week by: the Wednesday of some week, a week on, is the
  # Wednesday of some week still. Days and the units of a time of day count
  # from it, and so does the part of a week that is no whole one.
  defp duration_reaches?(duration_time, :day_of_week),
    do: Enum.any?(duration_time, &counts_from_day_of_week?/1)

  defp duration_reaches?(duration_time, mask_unit) do
    mask_depth = Keyword.fetch!(@unit_depth, mask_unit)

    Enum.any?(duration_time, fn {unit, amount} ->
      amount != 0 and Keyword.get(@unit_depth, unit, 0) >= mask_depth
    end)
  end

  defp counts_from_day_of_week?({:week, weeks}), do: is_float(weeks) and weeks != trunc(weeks)
  defp counts_from_day_of_week?({unit, _amount}) when unit in [:year, :month], do: false
  defp counts_from_day_of_week?({_unit, amount}), do: amount != 0

  # The crisp arithmetic path. ISO 8601-2 margin-of-error (`±`) and
  # significant-digits (`S`) annotations ride on a component value as
  # `{integer, keyword}`; they are crisp-inert, so peel them off before
  # the duration is applied and re-attach each to its (shifted) component
  # afterwards — `Tempo.shift(~o"2018±2Y", ~o"P1Y") == ~o"2019±2Y"` rather
  # than crashing the integer arithmetic on the tuple.
  # A week date names a week and a day of it, and no month, so it has no
  # month to step; its weeks and days step on the week axis. A day of the
  # year is the date it names, and is stepped as that date.
  defp add_crisp(%Tempo{} = tempo, %Tempo.Duration{} = duration) do
    tempo
    |> Validation.calendar_date_from_ordinal_date()
    |> add_crisp_on_its_axis(duration)
  end

  defp add_crisp_on_its_axis(
         %Tempo{time: time} = tempo,
         %Tempo.Duration{time: duration_time} = duration
       ) do
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
      if week_axis?(crisp_time, tempo.calendar) do
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
  # (`7K`), and no day of a month. Every value of a calendar of weeks is on
  # it, a year alone included: its year is counted in weeks.
  defp week_axis?(time, calendar) do
    Tempo.week_based_calendar?(calendar) or Keyword.has_key?(time, :week) or
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
  # A mask (`195X`, `2020-XX`, `19XX-XX`) stands for candidate values, and a
  # step that counts from it moves each of them. Where the candidates are one
  # block, and the step keeps them one, the block's first and last candidate
  # bound what they land on: a block-aligned step of a year mask stays a mask
  # (`195X` + `P10Y` → `196X`), and any other is one of the values between
  # the two (`195X` + `P1Y` → `~o"[1951Y..1960Y]"`). Where they are not, each
  # candidate is stepped, and the answer is the set of their spans: the days
  # `2026Y6MX5D` stands for, a day on, are the 6th, the 16th and the 26th,
  # and not every day from the 6th to the 26th.

  # Masks are only resolved on units the arithmetic understands; a mask on
  # any other unit falls through to the crisp path unchanged.
  @maskable_units [
    :year,
    :month,
    :week,
    :day,
    :day_of_year,
    :day_of_week,
    :hour,
    :minute,
    :second
  ]

  # An unspecified unit other than the year (`X*D`, any day) is every value
  # the unit takes, as a mask of all its digits is (`XXD`), and a shift that
  # reaches it moves that block: `2026Y6MX*D` plus a day is one of 2 June to 1
  # July, where it was read as the unit's last value. A week and a day of
  # the week are blocks alike: `2026Y25WX*K` plus a day is one of the seven
  # days from the Tuesday of week 25. An unspecified year is any year, which
  # a step carries as it is.
  defp unspecified_as_masks(%Tempo{time: time} = tempo, reached) do
    %{tempo | time: Enum.map(time, &unspecified_as_mask(&1, reached))}
  end

  defp unspecified_as_mask({unit, :any} = component, reached)
       when unit in @maskable_units and unit != :year do
    if reached == :every or duration_reaches?(reached, unit),
      do: {unit, {:mask, every_digit(unit)}},
      else: component
  end

  defp unspecified_as_mask(component, _reached), do: component

  # A day of the year is written in three digits, a day of the week in one,
  # and every other unit a mask is read on in two.
  defp every_digit(:day_of_year), do: [:X, :X, :X]
  defp every_digit(:day_of_week), do: [:X]
  defp every_digit(_unit), do: [:X, :X]

  defp find_masks(time) do
    Enum.flat_map(time, fn
      {unit, {:mask, mask}} when is_list(mask) and unit in @maskable_units -> [{unit, mask}]
      _ -> []
    end)
  end

  # `written` is the value as it was written, and `masked` the same value
  # with each unspecified unit the step reaches as the mask of every digit
  # it is.
  defp shift_masked(written, masked, %Tempo.Duration{} = duration) do
    if block_stays_whole?(masked, duration),
      do: shift_block(written, masked, duration),
      else: shift_each_candidate(masked, duration)
  end

  # The block's first and last candidate, stepped as the values they are.
  # What they land on bounds the block where it is written to the unit the
  # masks are on; a step that writes a finer unit (25 hours on from some day
  # of June) lands each candidate apart from the next.
  defp shift_block(written, %Tempo{time: time, calendar: calendar} = masked, duration) do
    with {:ok, min_time} <- fill_masks(time, calendar, :min),
         {:ok, max_time} <- fill_masks(time, calendar, :max),
         {:ok, first} <- stepped_candidate(%{masked | time: min_time}, duration),
         {:ok, last} <- stepped_candidate(%{masked | time: max_time}, duration) do
      cond do
        finest_unit(first.time) != finest_unit(time) -> shift_each_candidate(masked, duration)
        not after?(first, last) -> remask_or_set(find_masks(time), first, last)
        every_value_of_its_axis?(time) -> {:ok, written}
        true -> shift_each_candidate(masked, duration)
      end
    end
  end

  # A value with no year lies on an axis that comes round again, so a block
  # of it can land across the axis's end: the hours from 22:00, two hours on,
  # are 00:00 to 01:59 after 23:59. Such a block is no range from a first
  # value up to a last, and is each of its candidates; one that was every
  # value of the axis is every value of it still (`X*K`, any day of the
  # week, a day on).
  defp after?(first, last), do: Compare.order(first, last) == {:ok, :later}

  defp every_value_of_its_axis?(time), do: Enum.all?(time, &every_value?/1)

  # The unit a time list is written to. A day of the year and a day of the
  # week are days, as the dates they name are.
  defp finest_unit(time) do
    case List.last(time) do
      {unit, _held} when unit in [:day_of_year, :day_of_week] -> :day
      {unit, _held} -> unit
      _group_of_a_set -> :group
    end
  end

  # A candidate stepped as the one value it is: in its zone, and read as the
  # answer of a step is.
  defp stepped_candidate(candidate, duration) do
    case stepped_value(candidate, duration) do
      %Tempo{} = stepped -> {:ok, stepped}
      {:error, _reason} = error -> error
      _several_values -> {:error, :grouped_component}
    end
  end

  # Whether the candidates are one run of values that a step keeps a run.
  #
  # They are one run where each unit before the first mask is one value,
  # every unit from that mask on is masked, its candidates are consecutive,
  # and each mask after it is every value of its unit: `2026Y1XMXXD` is the
  # days from 1 October to 31 December, where `2026YXXM1XD` is ten days of
  # each month.
  #
  # A step keeps them a run where it counts them as they are counted:
  # months and years for a run of months or years, and the units of fixed
  # length for any run. A run of days across months, stepped by months or
  # years, is not kept: each day is brought into the month it lands in, so
  # the 31st of October a month on is the 30th of November, and no day lands
  # on the 31st of December. The days of one month are kept, and the weeks
  # of one year (`of_one_period?/2`).
  #
  # In a calendar that steps its own dates a run of days by their numbers
  # need not be a run in time (the days of the month a year begins within
  # are not), so there each day is stepped; its years and its months are a
  # run as they are counted.
  defp block_stays_whole?(%Tempo{time: time, calendar: calendar} = masked, %Tempo.Duration{
         time: duration_time
       }) do
    (finest_unit(time) in [:year, :month] or not stepped_by_its_calendar?(masked)) and
      one_run?(time, duration_time, calendar)
  end

  defp one_run?(time, duration_time, calendar) do
    case Enum.split_while(time, &(not masked?(&1))) do
      {before, [{unit, {:mask, mask}} | finer]} ->
        Enum.all?(before, &one_value?/1) and Enum.all?(finer, &every_value?/1) and
          (counted_as_stepped?(time, duration_time) or of_one_period?(unit, before, finer)) and
          run_of_values?(unit, mask, before, calendar)

      _no_mask ->
        false
    end
  end

  # A unit before the masks that holds a set, a range or a group gives a
  # block for each of its values.
  defp one_value?({_unit, value}) when is_integer(value), do: true
  defp one_value?({_unit, {value, options}}) when is_integer(value) and is_list(options), do: true
  defp one_value?(_several_or_a_group), do: false

  defp masked?(entry), do: match?({_unit, {:mask, _mask}}, entry)

  defp every_value?({_unit, {:mask, mask}}), do: Enum.all?(mask, &(&1 == :X))
  defp every_value?(_not_masked), do: false

  defp counted_as_stepped?(time, duration_time) do
    {finest, _held} = List.last(time)

    finest in [:year, :month] or not Enum.any?(duration_time, &month_or_year_step?/1)
  end

  # The days of one month are a run a step of months or years keeps: each is
  # brought into the month it lands in, so they end on that month's last day
  # at most and are every day before it from the first. The weeks of one
  # year are a run alike, where no day of the week is written after them:
  # the fifty-third is the last week of a year that has fifty-two. A week
  # and a day of it are the date they name, which is stepped as that date.
  defp of_one_period?(:day, before, _finer), do: match?({:month, _month}, List.last(before))
  defp of_one_period?(:week, before, []), do: match?({:year, _year}, List.last(before))
  defp of_one_period?(_unit, _before, _finer), do: false

  defp run_of_values?(unit, mask, before, calendar) do
    case Mask.candidates(unit, mask, before, calendar) do
      {:ok, [_ | _] = candidates} -> consecutive?(Enum.sort(candidates))
      _none_or_cannot_say -> false
    end
  end

  defp consecutive?([first | _rest] = values),
    do: List.last(values) - first + 1 == Enum.count(values)

  # Each candidate the masks stand for, stepped, and the set of their spans.
  # The candidates are those the walk of the value yields, which returns as
  # an error what depends on a year the value does not carry.
  defp shift_each_candidate(masked, duration) do
    with {:ok, candidates} <- candidates_of(masked),
         {:ok, spans} <- shifted_spans(candidates, duration),
         {:ok, set} <- IntervalSet.new(spans) do
      IntervalSet.coalesce(set)
    end
  end

  # A value with no year to count its candidates in is unanchored, which
  # `add_general/2` says of the value as it was written.
  defp candidates_of(masked) do
    case Enumeration.members(masked) do
      {:error, %UnanchoredError{}} -> {:error, :unanchored}
      candidates_or_error -> candidates_or_error
    end
  end

  # The span of each candidate, shifted. The first candidate that cannot be
  # shifted is the answer for them all.
  defp shifted_spans(candidates, duration) do
    candidates
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
    with {:ok, shifted} <- stepped_candidate(candidate, duration) do
      one_span(Tempo.to_interval(shifted))
    end
  end

  # A candidate that still holds a set names several spans, not one.
  defp one_span({:ok, %Interval{} = span}), do: {:ok, span}
  defp one_span({:ok, _several_spans}), do: {:error, :grouped_component}
  defp one_span({:error, _reason} = error), do: error

  # ------------------------------------------------------------------
  # A value that holds several values
  #
  # A set or a range in a unit names a value for each of its members, and a
  # step reaches every one of them (decided 2026-10-04): each is stepped as
  # the one value it is, by any unit. What they land on is written again as
  # one value where the values its units then hold name those and no others
  # (a day on from `2026Y6M{1,15}D` is `2026Y6M{2,16}D`), and is the set of
  # their spans where they do not: a day on from the 15th and the 30th of
  # June is 16 June and 1 July, which no one month and set of days names.
  #
  # The set is never stepped as one value. Where every member takes a step
  # alike that would give the same answer, but the members of a value in a
  # zone do not: two hours on from 01:00 is 03:00 on most days and 04:00 on
  # the day the clocks go forward, and a month on from the 30th and the 31st
  # of January is the 28th of February once.
  #
  # A day of the year is the date it names (`2026Y100O` is read as 10 April)
  # and a week date in a calendar of months is too, so those are the values
  # stepped. They are written again on the axis the value was written on: as
  # years and days of the year, or as years, weeks and days of the week.

  # Each value stepped, as the walk yields it. The first that cannot be
  # stepped is the answer for them all.
  defp shift_each(values, %Tempo{} = tempo, duration, annotations),
    do: each_stepped(values, tempo, annotations, &stepped_value(&1, duration))

  defp each_stepped(values, %Tempo{} = tempo, annotations, step) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, landed} ->
      case step.(value) do
        %Tempo{} = stepped -> {:cont, {:ok, [stepped | landed]}}
        {:error, _reason} = error -> {:halt, error}
        _several_values -> {:halt, {:error, :grouped_component}}
      end
    end)
    |> case do
      {:ok, landed} -> landed |> Enum.reverse() |> Enum.uniq() |> gathered(tempo, annotations)
      {:error, _reason} = error -> error
    end
  end

  # One value of the set stepped, and read as the answer of a step is.
  defp stepped_value(value, duration) do
    value
    |> add_to_value(duration)
    |> Validation.calendar_date_from_week_date()
    |> Validation.calendar_date_from_ordinal_date()
  end

  # The values a step landed on, as one value where the product of what each
  # unit then holds is those values and no others, each alike in everything
  # but its units, and as the set of their spans otherwise.
  defp gathered(landed, %Tempo{time: time, calendar: calendar}, annotations) do
    axis = written_on(time, Calendars.effective(calendar))

    with [frame] <- landed |> Enum.map(&%{&1 | time: []}) |> Enum.uniq(),
         {:ok, time} <- landed |> Enum.map(&as_written(&1, axis)) |> one_value() do
      time = reapply_component_annotations(time, annotations)
      {:ok, %{requalified(frame, time, axis) | time: time}}
    else
      _in_no_one_value -> landed |> Enum.map(&annotated(&1, annotations)) |> spans_of()
    end
  end

  defp annotated(%Tempo{time: time} = value, annotations),
    do: %{value | time: reapply_component_annotations(time, annotations)}

  # A date written again in other units is qualified in each of them by
  # what qualified any unit of the date.
  defp requalified(frame, _time, :as_it_is), do: frame
  defp requalified(frame, time, _axis), do: Qualification.rewritten(frame, time)

  # The axis a value's dates are written on, where the walk yields them as
  # calendar dates: the days of a year, or the weeks of one in a calendar of
  # months.
  defp written_on([{:year, _years}, {:day_of_year, _days} | _rest], _calendar), do: :ordinal

  defp written_on(time, calendar) do
    if List.keymember?(time, :week, 0) and not Tempo.week_based_calendar?(calendar),
      do: :week,
      else: :as_it_is
  end

  # A date as its year and its day of that year.
  defp as_written(
         %Tempo{time: [{:year, year}, {:month, month}, {:day, day} | rest], calendar: calendar},
         :ordinal
       )
       when is_integer(year) and is_integer(month) and is_integer(day) do
    calendar = Calendars.effective(calendar)
    [{:year, year}, {:day_of_year, calendar.day_of_year(year, month, day)} | rest]
  end

  # A date as the week and the day of the week that name it, where the week
  # its calendar gives it is read back as that date
  # (`Validation.date_from_iso_week/4`), and as the date it is where it is
  # not: a calendar other than the Gregorian counts ISO 8601's weeks in its
  # own years, and its `iso_week_of_year/3` in the Gregorian year.
  defp as_written(
         %Tempo{time: [{:year, year}, {:month, month}, {:day, day} | rest] = time} = date,
         :week
       )
       when is_integer(year) and is_integer(month) and is_integer(day) do
    calendar = Calendars.effective(date.calendar)

    with {week_year, week} when is_integer(week) <- calendar.iso_week_of_year(year, month, day),
         {weekday, _first, _last} <- calendar.day_of_week(year, month, day, :monday),
         {:ok, %Date{year: ^year, month: ^month, day: ^day}} <-
           UnitValues.date_from_iso_week(week_year, week, weekday, calendar) do
      [{:year, week_year}, {:week, week}, {:day_of_week, weekday} | rest]
    else
      _no_week_reads_back_as_it -> time
    end
  end

  defp as_written(%Tempo{time: time}, _axis), do: time

  # Time lists of the same units as one, each unit holding the values the
  # lists give it, where every combination of those values is one of the
  # lists: `[day: 2]` and `[day: 16]` under one month are `[day: {2,16}]`.
  defp one_value([first | _rest] = times) do
    units = units_of(first)
    held = for unit <- units, do: {unit, values_of(times, unit)}

    if Enum.all?(times, &(units_of(&1) == units)) and Enum.all?(held, &whole_numbers?/1) and
         product_size(held) == Enum.count(times),
       do: {:ok, for({unit, values} <- held, do: {unit, one_or_set(values)})},
       else: :several
  end

  defp units_of(time), do: for(entry <- time, do: elem(entry, 0))

  defp values_of(times, unit) do
    times
    |> Enum.flat_map(fn time ->
      case List.keyfind(time, unit, 0) do
        {^unit, value} -> [value]
        _absent -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A unit that holds what is no whole number (a fraction of a second, a
  # margin of error) is one value's only where every list has the same.
  defp whole_numbers?({_unit, [_only]}), do: true
  defp whole_numbers?({_unit, values}), do: Enum.all?(values, &is_integer/1)

  defp product_size(held),
    do: held |> Enum.map(fn {_unit, values} -> Enum.count(values) end) |> Enum.product()

  defp one_or_set([one]), do: one
  defp one_or_set(several), do: Parser.consolidate_ranges(several)

  defp spans_of(landed) do
    landed
    |> Enum.reduce_while({:ok, []}, fn date, {:ok, spans} ->
      case one_span(Tempo.to_interval(date)) do
        {:ok, span} -> {:cont, {:ok, [span | spans]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, spans} -> IntervalSet.new(Enum.reverse(spans))
      {:error, _reason} = error -> error
    end
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
    case Mask.candidates(unit, mask, previous, calendar) do
      {:ok, []} -> {:error, {:no_candidates, unit}}
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

  # The ends are the dates they name where they are a week and a day of it
  # in a calendar of months, as a value's are when it is read.
  defp one_of_range(first, last) do
    %Tempo.Set{
      type: :one,
      set: [
        %Tempo.Range{
          first: Validation.calendar_date_from_week_date(first),
          last: Validation.calendar_date_from_week_date(last)
        }
      ]
    }
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
      case Tempo.extend_resolution_as_written(tempo, finest) do
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

  # Apply duration components largest-to-smallest. The years and months
  # are applied first and the day brought into the month they land in, and
  # then the units that are counted from that date: 29 July less five months
  # and a day is 27 February, the day before the 28th the months land on, as
  # `Date.shift/2` and every calendar library count it. `:week` appears only
  # for week-axis values (month-axis durations normalise weeks to days before
  # this runs).
  @calendar_units [:year, :month]
  @counted_units [:week, :day, :day_of_week, :hour, :minute, :second]

  defp apply_duration(%Tempo{time: time, calendar: calendar} = tempo, duration_time) do
    # Only a month/year step can leave the day past the new month's length
    # ("Jan 31 + 1 month = Feb 31"); day/week/time steps already carry into the
    # next month as they go. Clamping only when a month or year is present
    # avoids a spurious demand for a year from a value that already sits on an
    # ambiguous day — e.g. `~o"2M29D"` shifted by an hour keeps its 29th.
    stepped =
      {:ok, time}
      |> apply_units(@calendar_units, duration_time, calendar)
      |> maybe_clamp(duration_time, calendar)
      |> apply_units(@counted_units, duration_time, calendar)
      |> thread_microsecond(Keyword.get(duration_time, :microsecond), calendar)

    with {:ok, new_time} <- stepped do
      {:ok, %{tempo | time: new_time}}
    end
  end

  defp apply_units({:error, _reason} = error, _units, _duration_time, _calendar), do: error

  defp apply_units({:ok, time}, units, duration_time, calendar) do
    Enum.reduce_while(units, {:ok, time}, fn unit, {:ok, acc} ->
      case Keyword.get(duration_time, unit, 0) do
        0 -> {:cont, {:ok, acc}}
        n -> step_or_halt(apply_duration_component(acc, unit, n, calendar))
      end
    end)
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
         {next_year, next_month, next_day} <- calendar.plus(year, month, day, :months, 1, []),
         {:ok, month_later} <- Date.new(next_year, next_month, next_day, calendar) do
      {:ok, :day, whole_units(fraction, Date.diff(month_later, date))}
    else
      :several -> {:error, :grouped_component}
      _no_full_date -> {:error, :unanchored}
    end
  end

  defp maybe_clamp({:error, _reason} = error, _duration_time, _calendar), do: error

  defp maybe_clamp({:ok, time}, duration_time, calendar) do
    if Keyword.has_key?(duration_time, :month) or Keyword.has_key?(duration_time, :year) do
      with {:ok, time} <- clamp_day_to_month(time, calendar),
           do: clamp_week_to_year(time, calendar)
    else
      {:ok, time}
    end
  end

  # Sub-second durations are applied as a single signed shift of the
  # microsecond value rather than iterated `add_unit` calls (which
  # would be O(value)). A negative value (produced by `subtract/2`)
  # borrows from the second.
  defp apply_microsecond_duration(time, nil, _calendar), do: {:ok, time}
  defp apply_microsecond_duration(time, {0, _precision}, _calendar), do: {:ok, time}

  defp apply_microsecond_duration(time, {value, precision}, calendar) do
    shift_microseconds(time, value, precision, calendar)
  end

  # The result is written to the finer of the two fractions' digits: a tenth
  # of a second added to a whole second is a second and a tenth, not one to
  # six digits.
  @microseconds_per_second 1_000_000
  defp shift_microseconds(time, delta, delta_precision, calendar) do
    {current, precision} =
      case List.keyfind(time, :microsecond, 0) do
        {:microsecond, {value, precision}} -> {value, max(precision, delta_precision)}
        nil -> {0, delta_precision}
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
  # arithmetic with a whole-day carry through Calendrical's `plus/6`, versus the
  # O(N) single-unit stepping below. Without it a high-frequency
  # recurrence (`FREQ=MINUTELY;COUNT=1440`) is quadratic to
  # materialise — occurrence i adds an i-unit duration. Falls back to
  # stepping for anything without an integer `[year, month, day, hour]`
  # prefix (partials, masks, groups).
  defp apply_n_units(time, unit, n, calendar) when unit in [:hour, :minute, :second] do
    with :fallback <- fast_add_time_of_day(time, unit, n, calendar),
         :fallback <- fast_add_on_the_clock(time, unit, n) do
      step_n_units(time, unit, n, calendar)
    end
  end

  # Weeks and the days of a week are the calendar's to count on where the
  # value names a week of a year (`weeks_by_the_calendar/3`,
  # `days_of_week_by_the_calendar/3`), in one step where a week at a time
  # took as many as the count.
  defp apply_n_units(time, :week, n, calendar) do
    case weeks_by_the_calendar(time, n, calendar) do
      {:ok, new_time} -> {:ok, new_time}
      :by_count -> step_n_units(time, :week, n, calendar)
    end
  end

  defp apply_n_units(time, :day_of_week, n, calendar) do
    case days_of_week_by_the_calendar(time, n, calendar) do
      {:ok, new_time} -> {:ok, new_time}
      :by_count -> step_n_units(time, :day_of_week, n, calendar)
    end
  end

  # A calendar with a traditional month numbering (Hebrew, the lunisolar
  # calendars) places a month one later after a leap month, so a month's
  # number changes from year to year. A year shift keeps the traditional
  # month, as the calendar's own `plus/6` does it: Nisan stays Nisan, and a
  # leap month the new year lacks becomes the month it follows or precedes.
  #
  # A date in a composite calendar, or in a year that does not begin with
  # its first month, is a year on where its calendar says: 10 March 1750 in
  # `Calendrical.Reform.England` is in the year that ends on 24 March, and a
  # year after it is 10 March 1752.
  defp apply_n_units(time, :year, n, calendar) do
    case date_by_the_calendar(time, :years, n, calendar) do
      {:ok, new_time} -> {:ok, new_time}
      :by_count -> years_by_count(time, n, calendar)
    end
  end

  # A date's months are stepped in the order of their numbers, the last of
  # a year followed by the first of the next. In a year that does not begin
  # with its first month they are not in that order (the January after a
  # December is in the same year), and a composite calendar's years and
  # months are cut short where its calendars change, so the calendar steps
  # a date there.
  defp apply_n_units(time, :month, n, calendar) do
    case date_by_the_calendar(time, :months, n, calendar) do
      {:ok, new_time} -> {:ok, new_time}
      :by_count -> months_by_count(time, n, calendar)
    end
  end

  defp apply_n_units(time, unit, n, calendar), do: step_n_units(time, unit, n, calendar)

  defp date_by_the_calendar(
         [{:year, year}, {:month, month}, {:day, day} | rest],
         date_part,
         n,
         calendar
       )
       when is_integer(year) and is_integer(month) and month > 0 and is_integer(day) and day > 0 do
    with true <- UnitValues.stepped_by_calendar?(year, calendar),
         true <- calendar.valid_date?(year, month, day),
         {year, month, day} <- calendar.plus(year, month, day, date_part, n, []) do
      {:ok, [{:year, year}, {:month, month}, {:day, day} | rest]}
    else
      _by_count -> :by_count
    end
  end

  defp date_by_the_calendar(_time, _date_part, _n, _calendar), do: :by_count

  # A year counted on is its number and so many more, whatever else the
  # value holds (`step_year/2`, which a step of one year is too): the day is
  # clamped once, after every unit is applied.
  defp years_by_count(time, n, calendar) do
    case shift_years_by_calendar(time, n, calendar) do
      {:ok, new_time} -> {:ok, new_time}
      {:error, _reason} = error -> error
      :fallback -> step_year(time, n, calendar)
    end
  end

  # Months counted on through the years are the calendar's to count
  # (`plus/6`), which says in one step what a month at a time says in as
  # many as the count: it took time in proportion to the count, and a
  # recurrence that steps to its nth candidate by one shift the square of
  # it. Only the year and the month are taken from the answer, and the day
  # is clamped once every unit is applied. A value with no one year or no
  # one month, a month its year lacks, and a year whose months are not in
  # the order of their numbers (`Tempo.UnitValues.stepped_by_calendar?/2`,
  # where a value that is no date counts the months the calendar numbers)
  # are stepped a month at a time still, and so is a calendar of weeks,
  # which has no months.
  defp months_by_count(time, n, calendar) do
    with {:ok, year} <- year_of(time),
         {:ok, month} <- component(time, :month),
         false <- UnitValues.stepped_by_calendar?(year, calendar),
         false <- Tempo.week_based_calendar?(calendar),
         true <- calendar.valid_date?(year, month, 1),
         {new_year, new_month, _day} <- calendar.plus(year, month, 1, :months, n, []) do
      {:ok, time |> put_component(:year, new_year) |> put_component(:month, new_month)}
    else
      _a_month_at_a_time -> step_n_units(time, :month, n, calendar)
    end
  end

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
      function_exported?(calendar, :ordinal_month_from_traditional, 2)
  end

  # A valid date moves by the calendar's own `plus/6`; one that is not a
  # date (a day a month step has not yet clamped) steps instead.
  defp fast_add_days(time, n, calendar) do
    with {:ok, year} <- year_of(time),
         {:ok, month} <- component(time, :month),
         {:ok, day} <- component(time, :day),
         true <- calendar.valid_date?(year, month, day) do
      {year, month, day} = calendar.plus(year, month, day, :days, n, [])

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
  # `plus/6` (which rolls month/year in-calendar) and only the components
  # that were present are written back, preserving the value's
  # resolution. Wall clock, like the stepper — the zone rides on `shift`,
  # untouched.
  #
  # A date of a calendar of weeks is its year, its week and its day of the
  # week, which the calendar's `plus/6` takes as a month calendar's takes a
  # year, a month and a day.
  defp fast_add_time_of_day(time, unit, n, calendar) do
    {middle, day_unit} = units_of_a_date(time, calendar)

    with {:ok, year} <- year_of(time),
         {:ok, month} <- component(time, middle),
         {:ok, day} <- component(time, day_unit),
         {:ok, hour} <- component(time, :hour),
         {:ok, minute} <- clock_or_zero(time, :minute),
         {:ok, second} <- clock_or_zero(time, :second),
         {:ok, _date} <- Date.new(year, month, day, calendar) do
      total = hour * 3600 + minute * 60 + second + n * unit_seconds(unit)
      day_carry = Integer.floor_div(total, @seconds_in_day)

      {year, month, day} =
        calendar.plus(year, month, day, :days, day_carry, [])

      new_time =
        time
        |> put_component(:year, year)
        |> put_component(middle, month)
        |> put_component(day_unit, day)
        |> put_time_of_day(Integer.mod(total, @seconds_in_day))

      {:ok, new_time}
    else
      _ -> :fallback
    end
  end

  defp units_of_a_date(time, calendar) do
    if List.keymember?(time, :week, 0) and Tempo.week_based_calendar?(calendar),
      do: {:week, :day_of_week},
      else: {:month, :day}
  end

  # Writes a time of day, in seconds from midnight, into the clock units a
  # value tracks.
  defp put_time_of_day(time, seconds) do
    time
    |> put_component(:hour, div(seconds, 3600))
    |> put_component(:minute, div(rem(seconds, 3600), 60))
    |> put_component(:second, rem(seconds, 60))
  end

  # A time of day with no date comes round again each day: so many hours on
  # from 22:00 is the time the clock shows then, whatever the day. The clock
  # has twenty-four hours of sixty minutes of sixty seconds on every day a
  # value with no date could be of, so the count is one sum, where an hour
  # at a time took as many steps as the count.
  defp fast_add_on_the_clock([{:hour, hour} | _finer] = time, unit, n) when is_integer(hour) do
    with {:ok, minute} <- clock_or_zero(time, :minute),
         {:ok, second} <- clock_or_zero(time, :second) do
      total = hour * 3600 + minute * 60 + second + n * unit_seconds(unit)
      {:ok, put_time_of_day(time, Integer.mod(total, @seconds_in_day))}
    else
      _several_or_unspecified -> :fallback
    end
  end

  defp fast_add_on_the_clock(_time, _unit, _n), do: :fallback

  # A week of a calendar of weeks so many weeks on is the calendar's own
  # `plus/6`. A week of a Gregorian year is one of ISO 8601's, counted on
  # from its first day by the calendar and named again by its week
  # (`iso_week_of_year/3`). Any other value is counted a week at a time.
  defp weeks_by_the_calendar([{:year, year}, {:week, week} | rest], n, calendar)
       when is_integer(year) and is_integer(week) and week > 0 do
    cond do
      Tempo.week_based_calendar?(calendar) ->
        week_of_a_calendar_of_weeks(year, week, rest, n, calendar)

      calendar == Calendrical.Gregorian ->
        iso_week_on(year, week, rest, n, calendar)

      true ->
        :by_count
    end
  end

  defp weeks_by_the_calendar(_time, _n, _calendar), do: :by_count

  defp week_of_a_calendar_of_weeks(year, week, rest, n, calendar) do
    with true <- calendar.valid_date?(year, week, 1),
         {year, week, _day} <- calendar.plus(year, week, 1, :weeks, n, []) do
      {:ok, [{:year, year}, {:week, week} | rest]}
    else
      _by_count -> :by_count
    end
  end

  defp iso_week_on(year, week, rest, n, calendar) do
    with {:ok, %Date{} = first} <- UnitValues.date_from_iso_week(year, week, 1, calendar),
         {year, month, day} <- calendar.plus(first.year, first.month, first.day, :weeks, n, []),
         {week_year, week} when is_integer(week_year) and is_integer(week) <-
           calendar.iso_week_of_year(year, month, day) do
      {:ok, [{:year, week_year}, {:week, week} | rest]}
    else
      _by_count -> :by_count
    end
  end

  # A day of a week of a calendar of weeks so many days on is the calendar's
  # own `plus/6` too.
  defp days_of_week_by_the_calendar(
         [{:year, year}, {:week, week}, {:day_of_week, day} | rest],
         n,
         calendar
       )
       when is_integer(year) and is_integer(week) and is_integer(day) do
    with true <- Tempo.week_based_calendar?(calendar),
         true <- calendar.valid_date?(year, week, day),
         {year, week, day} <- calendar.plus(year, week, day, :days, n, []) do
      {:ok, [{:year, year}, {:week, week}, {:day_of_week, day} | rest]}
    else
      _by_count -> :by_count
    end
  end

  defp days_of_week_by_the_calendar(_time, _n, _calendar), do: :by_count

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

  # After a year step a week may be past the last of the year it lands in:
  # week 53, a year on from a year that has one, in a year that has 52. It
  # is that year's last week, as a day past the end of its month is the
  # month's last day, and as a calendar of weeks steps its own dates
  # (`Calendrical.ISOWeek.plus/6`). With no year a week is left as it is
  # written, and so is one that holds several values.
  defp clamp_week_to_year(time, calendar) do
    case {component(time, :week), year_of(time)} do
      {{:ok, week}, {:ok, _year}} -> clamp_integer_week(time, week, calendar)
      _no_week_or_no_one_year -> {:ok, time}
    end
  end

  defp clamp_integer_week(time, week, calendar) do
    case UnitValues.at_or_before(:week, week, time, calendar) do
      {:ok, ^week} -> {:ok, time}
      {:ok, last} -> {:ok, put_component(time, :week, last)}
      {:error, _cannot_count} -> {:ok, time}
    end
  end

  # After month arithmetic, the day field may exceed days-in-month
  # (e.g. Jan 31 + 1 month = "Feb 31"). Clamp once at the end.
  defp clamp_day_to_month(time, calendar) do
    case {component(time, :day), component(time, :month)} do
      {:untracked, _month} -> {:ok, time}
      # Day-only value (no month): there is nothing to clamp the day against.
      {_day, :untracked} -> {:ok, time}
      {{:ok, day}, {:ok, _month}} -> clamp_integer_day(time, day, calendar)
      {_day, month} -> keep_unclamped(time, largest_day(time), fewest_days(time, month, calendar))
    end
  end

  # A day past the last of its month is the month's last. With no year a day
  # that every year's month has is kept, one past a month of one length is
  # that month's last, and one whose place depends on the missing year (a
  # 29th or a 30th of February) is `{:error, :unanchored}`.
  defp clamp_integer_day(time, day, calendar) do
    case UnitValues.at_or_before(:day, day, time, calendar) do
      {:ok, ^day} -> {:ok, time}
      {:ok, last} -> {:ok, put_component(time, :day, last)}
      {:error, _reason} -> {:error, :unanchored}
    end
  end

  # The fewest days `month` has in any year, as the calendar answers with no
  # year; 0 when it cannot say.
  defp fewest_days_in_month(calendar, month) do
    case UnitValues.in_any_year(:day, [month: month], calendar) do
      {:ok, %Range{last: fewest}, _longest} -> fewest
      {:error, _cannot_say} -> 0
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
    case {year_of(time), UnitValues.last(:day, time, calendar)} do
      {{:ok, _year}, {:ok, last}} -> last
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
  #
  # A value that holds a set or a range is the values it names, and each is
  # walked from, as each is stepped by a shift that skips nothing
  # (`shift_each_or_crisp/2`): it was refused as a value with no one moment.
  def shift_skipping(%Tempo{time: time} = origin, %Tempo.Duration{} = duration, busy) do
    {crisp_time, annotations} = strip_component_annotations(time)

    case Enumeration.expand(%{origin | time: crisp_time}) do
      {:ok, values} -> each_shifted_skipping(values, origin, annotations, duration, busy)
      {:error, _exception} = error -> error
      :not_expandable -> shift_one_skipping(origin, duration, busy)
    end
  end

  defp each_shifted_skipping(values, origin, annotations, duration, busy) do
    case each_stepped(values, origin, annotations, &shift_one_skipping(&1, duration, busy)) do
      {:error, :grouped_component} ->
        {:error, ConversionError.exception(value: origin, reason: :grouped_component)}

      landed ->
        unwrap_shift(landed)
    end
  end

  defp shift_one_skipping(%Tempo{} = origin, %Tempo.Duration{} = duration, busy) do
    with :ok <- validate_anchored_origin(origin),
         :ok <- validate_one_moment(origin),
         :ok <- validate_exact_skipping(duration),
         {:ok, seconds} <- Duration.to_unit(duration, :second),
         {:ok, busy_set} <- normalize_busy(busy),
         :ok <- validate_busy_members(busy_set),
         :ok <- Interval.same_frame(origin, busy_set) do
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

  # Skipping walks free time from one moment. A value that holds several — a
  # set, a range, a group, unspecified digits, a selection — has no one moment
  # to walk from, and is the error a shift without `:skipping` gives it.
  defp validate_one_moment(%Tempo{time: time} = origin) do
    if Enum.all?(time, &one_number?/1),
      do: :ok,
      else: {:error, ConversionError.exception(value: origin, reason: :grouped_component)}
  end

  defp one_number?({:year, year}) when is_integer(year), do: true
  defp one_number?({_unit, value}) when is_integer(value) and value >= 0, do: true

  defp one_number?({:microsecond, {value, precision}})
       when is_integer(value) and is_integer(precision),
       do: true

  defp one_number?({_unit, {value, [margin_of_error: _margin]}}) when is_integer(value), do: true
  defp one_number?(_component), do: false

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
