defmodule Tempo.AmbiguousZoneError do
  @moduledoc """
  Exception raised when a wall-clock reading occurs twice in the
  given time zone — the DST fall-back ambiguity. The wall time
  exists, but with two different UTC offsets; the caller must
  disambiguate with an explicit offset.

  """

  alias Tempo.Calendars

  defexception [:wall_time, :zone_id, :options]

  @type t :: %__MODULE__{
          wall_time: String.t() | nil,
          zone_id: String.t() | nil,
          options: [integer()] | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Calendars.outside(struct!(__MODULE__, bindings))
  end

  @impl true
  def message(%__MODULE__{wall_time: wall, zone_id: zone, options: options})
      when is_binary(wall) and is_binary(zone) and is_list(options) do
    "Wall time #{wall} is ambiguous in #{Calendars.inspect(zone)} — occurs at offsets " <>
      "#{Calendars.inspect(options)}. Supply an explicit offset to disambiguate."
  end

  def message(%__MODULE__{wall_time: wall, zone_id: zone})
      when is_binary(wall) and is_binary(zone) do
    "Wall time #{wall} is ambiguous in #{Calendars.inspect(zone)}"
  end

  def message(%__MODULE__{}), do: "Wall time is ambiguous in the given zone"
end
