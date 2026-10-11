defmodule Tempo.ZoneGapError do
  @moduledoc """
  Exception raised when a wall-clock reading does not exist in
  the given time zone.

  Two causes:

  * **DST spring-forward** — the local clock jumps (e.g. New York
    2024-03-10 02:00 → 03:00, so 02:30 never existed).

  * **Calendar jump** — an entire calendar day is skipped when a
    territory changes its UTC offset (e.g. Samoa on 2011-12-30).

  """

  alias Tempo.Calendars

  defexception [:wall_time, :zone_id, :reason, :detail]

  @type t :: %__MODULE__{
          wall_time: String.t() | nil,
          zone_id: String.t() | nil,
          reason: :dst_gap | :calendar_jump | atom() | nil,
          detail: String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Calendars.outside(struct!(__MODULE__, bindings))
  end

  @impl true
  def message(%__MODULE__{wall_time: wall, zone_id: zone, detail: detail})
      when is_binary(wall) and is_binary(zone) and is_binary(detail) do
    "Wall time #{wall} does not exist in #{Calendars.inspect(zone)} (#{detail})."
  end

  def message(%__MODULE__{wall_time: wall, zone_id: zone})
      when is_binary(wall) and is_binary(zone) do
    "Wall time #{wall} does not exist in #{Calendars.inspect(zone)}"
  end

  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason
  def message(%__MODULE__{}), do: "Wall time does not exist in the given zone"
end
