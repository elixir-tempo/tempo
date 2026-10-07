defmodule Tempo.ZoneOffsetMismatchError do
  @moduledoc """
  Exception raised (or returned) when a value's numeric offset disagrees
  with the zone beside it at the value's reading.

  An IXDTF string may carry both a numeric offset and a zone, for
  example `2022-11-20T10:37:00+05:00[Europe/Paris]`. Paris is `+01:00`
  in November, so the stated `+05:00` is inconsistent. RFC 9557 §3.4 has
  a reader act on that where the zone is critical (`[!Europe/Paris]`,
  `[!+08:45]`) and lets it where the zone is elective. Tempo returns
  this error for a critical zone and, with `strict: true`, for an
  elective one; otherwise the offset gives the moment, and the value is
  that moment as the zone's clock shows it. `Tempo.new/1` returns it for
  a `:shift` and a `:zone` that disagree, where no text says which of
  the two is meant, and `Tempo.validate_zone_offset/1` for a value that
  holds a disagreement.

  """

  defexception [:zone_id, :wall_time, :stated_offset, :zone_offsets]

  @type t :: %__MODULE__{
          zone_id: String.t() | nil,
          wall_time: String.t() | nil,
          stated_offset: integer() | nil,
          zone_offsets: [integer()]
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{
        zone_id: zone_id,
        wall_time: wall_time,
        stated_offset: stated,
        zone_offsets: zone_offsets
      }) do
    actual = Enum.map_join(zone_offsets, " or ", &format_offset/1)

    "Stated offset #{format_offset(stated)} disagrees with #{inspect(zone_id)} " <>
      "(#{actual})#{at_the_reading(wall_time)}."
  end

  # A value with no year is at no one reading to name.
  defp at_the_reading(nil), do: ""
  defp at_the_reading(wall_time), do: " at #{wall_time}"

  @doc """
  Format an offset in seconds as a signed `±HH:MM` string.

  ### Examples

      iex> Tempo.ZoneOffsetMismatchError.format_offset(3600)
      "+01:00"

      iex> Tempo.ZoneOffsetMismatchError.format_offset(-18000)
      "-05:00"

  """
  @spec format_offset(integer()) :: String.t()
  def format_offset(seconds) when is_integer(seconds) do
    sign = if seconds < 0, do: "-", else: "+"
    total_minutes = div(abs(seconds), 60)
    hours = div(total_minutes, 60)
    minutes = rem(total_minutes, 60)

    "#{sign}#{pad(hours)}:#{pad(minutes)}"
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")
end
