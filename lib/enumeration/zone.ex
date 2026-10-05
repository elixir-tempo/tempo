defmodule Tempo.Enumeration.Zone do
  @moduledoc false

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
