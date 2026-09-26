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
  """
  @spec offset_to_shift(integer()) :: keyword()
  def offset_to_shift(total_seconds) do
    sign = if total_seconds < 0, do: -1, else: 1
    abs_total = abs(total_seconds)
    hours = div(abs_total, 3600)
    minutes = div(rem(abs_total, 3600), 60)

    case {hours, minutes} do
      {hours, 0} -> [hour: sign * hours]
      {0, minutes} -> [hour: 0, minute: sign * minutes]
      {hours, minutes} -> [hour: sign * hours, minute: minutes]
    end
  end

  # Extract `year, month, day, hour, minute, second` from a Tempo's
  # time keyword list and build a NaiveDateTime, filling missing
  # minute/second with 0. Returns `nil` if the value doesn't have
  # enough components to form a NaiveDateTime.
  defp naive_from_tempo(%Tempo{time: time}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day),
         hour when is_integer(hour) <- Keyword.get(time, :hour) do
      minute = Keyword.get(time, :minute, 0)
      second = Keyword.get(time, :second, 0)

      case NaiveDateTime.new(year, month, day, hour, minute, second) do
        {:ok, naive} -> naive
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  defp shift_from_datetime(%DateTime{utc_offset: utc, std_offset: std}),
    do: offset_to_shift(utc + std)
end
