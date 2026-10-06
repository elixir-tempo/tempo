defmodule Tempo.Enumeration.Zone do
  @moduledoc false

  alias Tempo.Math
  alias Tempo.TimeZoneDatabase
  alias Tempo.Validation

  # Shared DST classification for enumeration. Both `Enumerable.Tempo`
  # (implicit-span walk) and `Enumerable.Tempo.Interval` (explicit
  # forward-stepping walk) classify each emitted moment against its
  # configured zone so the two walks — and the `Tempo.Interval.Steps`
  # fast paths for `count/1`/`slice/1` — agree under daylight saving.

  @doc """
  Classify a Tempo value against its configured zone:

    * `:ok` — no zone, not enough components to form a wall instant,
      or the wall time resolves to a single unambiguous UTC instant.

    * `:gap` — wall time falls in a DST spring-forward gap; the clock
      never shows it, so the walk skips it.

    * `{:ambiguous, first_shift, second_shift}` — wall time happens
      twice (DST fall-back). The shifts are `:shift` keyword lists
      derived from the pre- and post-transition total UTC offset; the
      walk emits the moment twice, once with each.
  """
  @spec zone_status(Tempo.t()) :: :ok | :gap | {:ambiguous, keyword(), keyword()}

  # A date is a gap where its zone leaves the day out (Samoa had no
  # 30 December 2011): the walk skips it as it skips an hour the clock
  # skips.
  def zone_status(%Tempo{extended: %{zone_id: zone}, time: [year: _, month: _, day: _]} = date)
      when is_binary(zone) do
    if on_a_day_left_out?(date), do: :gap, else: :ok
  end

  def zone_status(%Tempo{extended: %{zone_id: zone}} = tempo) when is_binary(zone) do
    with %NaiveDateTime{} = naive <- naive_from_tempo(tempo),
         db when is_atom(db) <- Calendar.get_time_zone_database() do
      case DateTime.from_naive(naive, zone, db) do
        {:gap, _before, _after} ->
          :gap

        {:ambiguous, first, second} ->
          {:ambiguous, shift_from_datetime(first), shift_from_datetime(second)}

        _ ->
          :ok
      end
    else
      _ -> :ok
    end
  end

  def zone_status(_tempo), do: :ok

  @doc """
  Whether a value is on a day its zone leaves out: a date, or a time of day
  on one, that the zone's wall clock never showed (Samoa had no 30 December
  2011).

  The days a zone leaves out are kept
  (`Tempo.TimeZoneDatabase.days_left_out/1`), so this asks nothing of the
  zone database. The units of a value are read as Gregorian ones, so a
  value of another calendar is on no such day.
  """
  @spec on_a_day_left_out?(Tempo.t()) :: boolean()
  def on_a_day_left_out?(%Tempo{
        extended: %{zone_id: zone},
        time: [{:year, year}, {:month, month}, {:day, day} | _clock],
        calendar: calendar
      })
      when is_binary(zone) and is_integer(year) and is_integer(month) and is_integer(day) and
             calendar in [Calendrical.Gregorian, Calendar.ISO] do
    case TimeZoneDatabase.days_left_out(zone) do
      [] -> false
      days -> {year, month, day} in days
    end
  end

  def on_a_day_left_out?(_value), do: false

  @doc """
  Whether a value is one its zone's clock shows: any value but one the clock
  skips the whole of, which is the hour a spring-forward skips, a minute or
  a second inside one, and a day its zone leaves out
  (`Tempo.Validation.validate_zone_existence/1`).

  One written is refused when it is read, so this is asked of a value an
  operation has made: a member of a set in a unit, a value a mask stands
  for, the first value of a finer unit. A value the clock skips part of (a
  day whose first hour is skipped, the hour of a half-hour change) is shown.
  """
  @spec shown?(Tempo.t()) :: boolean()
  def shown?(%Tempo{} = value), do: Validation.validate_zone_existence(value) == :ok

  @doc """
  A value as its zone's clock shows it: the value, or where the clock skips
  the whole of it, the reading the clock shows at that moment.

  Midnight in Cairo on 28 April 2023, when the clocks went from 00:00 to
  01:00, is 01:00, and 02:00 on Lord Howe Island on the morning its clocks
  go to 02:30 is 02:30. It is where a value that starts on such a reading
  is compared from already (`Tempo.Compare.to_utc_seconds/1`), and what a
  step of nothing from it lands on (`Tempo.Math.add/2`).
  """
  @spec shown_by_the_clock(Tempo.t()) :: Tempo.t()
  def shown_by_the_clock(%Tempo{extended: %{zone_id: zone}} = value) when is_binary(zone) do
    if shown?(value), do: value, else: moved_on(value)
  end

  def shown_by_the_clock(%Tempo{} = value), do: value

  @no_step %Tempo.Duration{time: [day: 0]}

  defp moved_on(value) do
    case Math.add(value, @no_step) do
      %Tempo{} = shown -> shown
      _no_one_reading -> value
    end
  end

  @doc """
  Convert a total UTC offset in seconds to a `%Tempo{}` `:shift`
  keyword list, dropping the `:minute` element for a whole-hour
  offset (matching the IXDTF `+HH` vs `+HH:MM` shapes).

  The sign is carried on the first non-zero component, as the ISO 8601
  parser writes it: −03:30 is `[hour: -3, minute: 30]` and −00:30 is
  `[hour: 0, minute: -30]`.

  An offset that is not a whole number of minutes keeps its seconds, as
  a zone's local mean time has them: New York's until 1883 is
  `[hour: -4, minute: 56, second: 2]`. They were dropped, so the shift
  written beside such a zone was not its offset.
  """
  @spec offset_to_shift(integer()) :: keyword()
  def offset_to_shift(total_seconds) do
    sign = if total_seconds < 0, do: -1, else: 1
    abs_total = abs(total_seconds)
    hours = div(abs_total, 3600)
    minutes = div(rem(abs_total, 3600), 60)

    signed_units(sign, hours, minutes, rem(abs_total, 60))
  end

  defp signed_units(sign, hours, 0, 0), do: [hour: sign * hours]
  defp signed_units(sign, 0, minutes, 0), do: [hour: 0, minute: sign * minutes]
  defp signed_units(sign, hours, minutes, 0), do: [hour: sign * hours, minute: minutes]

  defp signed_units(sign, 0, 0, seconds), do: [hour: 0, minute: 0, second: sign * seconds]

  defp signed_units(sign, 0, minutes, seconds),
    do: [hour: 0, minute: sign * minutes, second: seconds]

  defp signed_units(sign, hours, minutes, seconds),
    do: [hour: sign * hours, minute: minutes, second: seconds]

  # Extract `year, month, day, hour, minute, second` from a Tempo's
  # time keyword list and build a NaiveDateTime, filling missing
  # minute/second with 0. Returns `nil` if the value doesn't have
  # enough components to form a NaiveDateTime.
  defp naive_from_tempo(%Tempo{time: time}) do
    with year when is_integer(year) <- whole(time, :year, nil),
         month when is_integer(month) <- whole(time, :month, nil),
         day when is_integer(day) <- whole(time, :day, nil),
         hour when is_integer(hour) <- whole(time, :hour, nil),
         minute when is_integer(minute) <- whole(time, :minute, 0),
         second when is_integer(second) <- whole(time, :second, 0),
         {:ok, naive} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
      naive
    else
      _ -> nil
    end
  end

  # A unit's whole number, `default` where the unit is absent, and `nil` where
  # it holds anything else: a set, a mask, or a group of a set, which is held
  # as three elements that `Keyword.get/3` raises on. A value with such a
  # unit is no one wall time to place in its zone.
  defp whole(time, unit, default) do
    case List.keyfind(time, unit, 0) do
      {^unit, value} when is_integer(value) -> value
      nil -> default
      _several -> nil
    end
  end

  defp shift_from_datetime(%DateTime{utc_offset: utc, std_offset: std}),
    do: offset_to_shift(utc + std)
end
