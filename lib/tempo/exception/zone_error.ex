defmodule Tempo.ZoneError do
  @moduledoc """
  A time zone Tempo cannot use.

  * `:zone` is the zone name or offset as written.

  * `:reason` is `:unknown` for a name the database does not have, `:gap` for
    a reading the zone's clock skips, `:mixed` for an expression whose parts
    are in two zones, `:critical` for a critical suffix Tempo cannot act on, or
    `:inconsistent` for a time shift a critical zone does not have then.

  """

  defexception [:zone, :reason, :value]

  @type t :: %__MODULE__{
          zone: term(),
          reason: :unknown | :gap | :mixed | :critical | :inconsistent,
          value: term()
        }

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{zone: zone, reason: :unknown}),
    do: "The time zone #{inspect(zone)} is not known to the time zone database"

  def message(%__MODULE__{zone: zone, reason: :gap, value: value}),
    do: "#{inspect(value)} is a reading the clock of #{inspect(zone)} skips"

  def message(%__MODULE__{reason: :mixed, value: value}),
    do: "#{inspect(value)} has parts in two zones; an expression is in one zone"

  def message(%__MODULE__{zone: zone, reason: :inconsistent, value: value}) do
    "#{inspect(value)} has a time shift the clock of #{inspect(zone)} does not have then, " <>
      "and the zone is critical"
  end

  def message(%__MODULE__{zone: zone, reason: :critical}),
    do: "The critical suffix #{inspect(zone)} is not one Tempo can act on"
end
