defmodule Tempo.UnknownZoneError do
  @moduledoc """
  Exception returned, or raised by a bang function, when a time-zone
  identifier is not present in the configured time zone database, or is
  not the name of a zone at all.

  """

  defexception [:zone_id]

  @type t :: %__MODULE__{
          zone_id: term()
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{zone_id: zone_id}) when is_binary(zone_id) do
    "Unknown IANA time zone: #{inspect(zone_id)}"
  end

  def message(%__MODULE__{zone_id: nil}), do: "Unknown IANA time zone"

  def message(%__MODULE__{zone_id: zone_id}) do
    "Unknown IANA time zone: #{inspect(zone_id)}. A zone is named by a string, " <>
      "such as \"Europe/Paris\"."
  end
end
