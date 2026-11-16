defmodule Tempo.ZoneError do
  @moduledoc """
  A time zone Tempo cannot use.

  * `:zone` is the zone name or offset as written.

  * `:reason` is `:unknown` for a name the database does not have,
    `:no_database` for a name given where the time zone database
    configured knows only UTC, `:gap` for a reading the zone's clock skips,
    `:fold` for one it shows twice where `disambiguation: :reject` refuses
    it, `:mixed` for an expression whose parts
    are in two zones, `:critical` for a critical suffix Tempo cannot act on, or
    `:inconsistent` for a time shift the zone does not have then, critical
    or not (decision 108), which the reader's `:offset` option resolves.

  * `:value` is the expression the zone could not be used with.

  * `:offsets` is, for `:gap` and `:fold`, the two time shifts the clock
    has either side of the change: `[[hour: -5, minute: 0], [hour: -4, minute: 0]]`.

  """

  defexception [:zone, :reason, :value, :offsets]

  @type t :: %__MODULE__{
          zone: term(),
          reason: :unknown | :no_database | :gap | :fold | :mixed | :critical | :inconsistent,
          value: term(),
          offsets: [keyword(integer())] | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{zone: zone, reason: :unknown}),
    do: "The time zone #{inspect(zone)} is not known to the time zone database"

  def message(%__MODULE__{zone: zone, reason: :no_database}) do
    "The time zone #{inspect(zone)} needs a time zone database that knows it, and the one " <>
      "configured knows only UTC; configure one with " <>
      "`config :elixir, :time_zone_database, Tz.TimeZoneDatabase` or " <>
      "`config :ex_tempo, :time_zone_database, ...`, or configure none and Tempo asks tz"
  end

  def message(%__MODULE__{zone: zone, reason: :gap, value: value, offsets: offsets}) do
    "#{inspect(value)} is a reading the clock of #{inspect(zone)} skips" <>
      change(offsets, "going from", "to") <>
      "; give disambiguation: :compatible or :later to read it after the change, " <>
      "or :earlier to read it before"
  end

  def message(%__MODULE__{zone: zone, reason: :fold, value: value, offsets: offsets}) do
    "#{inspect(value)} is a reading the clock of #{inspect(zone)} shows twice" <>
      change(offsets, "at", "and") <>
      "; give disambiguation: :earlier or :later, or a time shift, to say which"
  end

  def message(%__MODULE__{reason: :mixed, value: value}),
    do: "#{inspect(value)} has parts in two zones; an expression is in one zone"

  def message(%__MODULE__{zone: zone, reason: :inconsistent, value: value}) do
    "#{inspect(value)} has a time shift the clock of #{inspect(zone)} does not have then; " <>
      "give offset: :use to take the moment the shift gives, or offset: :prefer to take " <>
      "the reading on the zone's clock"
  end

  def message(%__MODULE__{zone: zone, reason: :critical}),
    do: "The critical suffix #{inspect(zone)} is not one Tempo can act on"

  defp change([before, later], opening, joining) do
    ", #{opening} #{written(before)} #{joining} #{written(later)}"
  end

  defp change(_none, _opening, _joining) do
    ""
  end

  # A time shift as RFC 3339 writes it: five hours behind UTC is -05:00.
  defp written(shift) do
    sign = if Enum.any?(shift, fn {_unit, value} -> value < 0 end), do: "-", else: "+"
    hours = shift |> Keyword.get(:hour, 0) |> abs()
    minutes = shift |> Keyword.get(:minute, 0) |> abs()
    sign <> two(hours) <> ":" <> two(minutes)
  end

  defp two(number) do
    number
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end
end
