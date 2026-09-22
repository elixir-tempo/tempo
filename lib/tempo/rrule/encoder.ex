defmodule Tempo.RRule.Encoder do
  @moduledoc false

  alias Tempo.ConversionError

  # Converts a `%Tempo.Interval{}` back into an RFC 5545 RRULE
  # string. Pure AST → text; no parsing. Called via
  # `Tempo.to_rrule/1`.

  @freq_for %{
    second: "SECONDLY",
    minute: "MINUTELY",
    hour: "HOURLY",
    day: "DAILY",
    week: "WEEKLY",
    month: "MONTHLY",
    year: "YEARLY"
  }

  @weekday_code %{
    1 => "MO",
    2 => "TU",
    3 => "WE",
    4 => "TH",
    5 => "FR",
    6 => "SA",
    7 => "SU"
  }

  @doc false
  def encode(%Tempo.Interval{duration: nil} = value) do
    {:error,
     ConversionError.exception(
       reason:
         "Cannot convert an interval without a duration to an RRULE. " <>
           "RFC 5545 requires a FREQ (recurrence cadence) on every rule.",
       value: value,
       target: :rrule
     )}
  end

  def encode(%Tempo.Interval{duration: %Tempo.Duration{time: time}} = interval) do
    # Rule-part ordering mirrors ISO 8601's textual order of the
    # equivalent concepts:
    #
    #   R<count> / from / ( to | P<dur> ) / F<rule>
    #
    # maps to:
    #
    #   COUNT | UNTIL ; FREQ ; INTERVAL ; BY*
    #
    # RFC 5545 does not require a specific ordering, so this is
    # valid — and keeps the mental model of an RRULE interval
    # aligned with an ISO 8601 recurring interval.

    with {:ok, freq_and_interval_parts} <- freq_and_interval(time, interval),
         {:ok, bound_part} <- bound_part(interval),
         {:ok, by_parts} <- by_parts(interval.repeat_rule, interval) do
      parts =
        [bound_part, freq_and_interval_parts, by_parts]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)

      {:ok, Enum.join(parts, ";")}
    end
  end

  def encode(other) do
    {:error,
     ConversionError.exception(
       reason:
         "Only a %Tempo.Interval{} with a duration can be converted to an RRULE. " <>
           "Got: #{inspect(other)}",
       value: other,
       target: :rrule
     )}
  end

  ## FREQ + INTERVAL

  defp freq_and_interval([{unit, n}], interval) when is_integer(n) and n >= 1 do
    case Map.get(@freq_for, unit) do
      nil ->
        {:error,
         ConversionError.exception(
           reason:
             "Duration unit #{inspect(unit)} has no RRULE equivalent. " <>
               "RRULE supports second/minute/hour/day/week/month/year.",
           value: interval,
           target: :rrule
         )}

      freq ->
        parts =
          if n == 1 do
            ["FREQ=#{freq}"]
          else
            ["FREQ=#{freq}", "INTERVAL=#{n}"]
          end

        {:ok, parts}
    end
  end

  defp freq_and_interval(time, interval) do
    {:error,
     ConversionError.exception(
       reason:
         "An RRULE duration must be a single {unit, count} pair; " <>
           "got: #{inspect(time)}",
       value: interval,
       target: :rrule
     )}
  end

  ## COUNT vs UNTIL vs neither

  defp bound_part(%Tempo.Interval{recurrence: 1, to: nil}), do: {:ok, nil}
  defp bound_part(%Tempo.Interval{recurrence: :infinity, to: nil}), do: {:ok, nil}

  defp bound_part(%Tempo.Interval{recurrence: n, to: nil}) when is_integer(n) and n > 1 do
    {:ok, "COUNT=#{n}"}
  end

  defp bound_part(%Tempo.Interval{recurrence: :infinity, to: %Tempo{} = to}) do
    with {:ok, encoded} <- encode_until(to), do: {:ok, "UNTIL=#{encoded}"}
  end

  defp bound_part(%Tempo.Interval{recurrence: 1, to: %Tempo{} = to}) do
    with {:ok, encoded} <- encode_until(to), do: {:ok, "UNTIL=#{encoded}"}
  end

  defp bound_part(%Tempo.Interval{recurrence: n, to: %Tempo{}} = v) when is_integer(n) do
    {:error,
     ConversionError.exception(
       reason:
         "RRULE cannot combine COUNT and UNTIL in the same rule " <>
           "(RFC 5545 §3.3.10 makes them mutually exclusive).",
       value: v,
       target: :rrule
     )}
  end

  defp bound_part(other) do
    {:error,
     ConversionError.exception(
       reason: "Interval bound shape is not expressible as an RRULE part.",
       value: other,
       target: :rrule
     )}
  end

  # RRULE UNTIL uses basic-format ISO 8601 — no separators.
  defp encode_until(%Tempo{time: time} = value) do
    case time do
      [year: y, month: m, day: d] ->
        {:ok, "#{pad(y, 4)}#{pad(m, 2)}#{pad(d, 2)}"}

      [year: y, month: m, day: d, hour: h, minute: mm, second: s] ->
        {:ok, "#{pad(y, 4)}#{pad(m, 2)}#{pad(d, 2)}T#{pad(h, 2)}#{pad(mm, 2)}#{pad(s, 2)}"}

      [year: y, month: m, day: d, hour: h, minute: mm, second: s, time_shift: [hour: 0]] ->
        {:ok, "#{pad(y, 4)}#{pad(m, 2)}#{pad(d, 2)}T#{pad(h, 2)}#{pad(mm, 2)}#{pad(s, 2)}Z"}

      _ ->
        {:error,
         ConversionError.exception(
           reason:
             "RRULE UNTIL requires a bare date or UTC datetime; " <>
               "got #{inspect(time)}.",
           value: value,
           target: :rrule
         )}
    end
  end

  ## BY* rules

  defp by_parts(nil, _interval), do: {:ok, []}

  defp by_parts(%Tempo{time: [selection: selection]}, _interval) do
    # Each selection token maps to one RRULE BY-part, with one recombination
    # first: ISO 8601-2 §12.9 lowers an ordinal `BYDAY` to a weekday followed
    # by a position (`2MO` → `day_of_week: 1, instance: 2`). Re-fusing that
    # adjacent pair lets `to_rrule/1` emit the compact, idiomatic `BYDAY=2MO`
    # rather than the equivalent-but-verbose `BYDAY=MO;BYSETPOS=2`. A genuine
    # set-position over several weekdays keeps `day_of_week` as a list and is
    # left untouched, so it still encodes as `BYDAY=…;BYSETPOS=…`.
    parts =
      selection
      |> recombine_ordinal_byday()
      |> Enum.flat_map(&encode_by_entry/1)

    {:ok, parts}
  end

  defp by_parts(%Tempo{} = rule, interval) do
    {:error,
     ConversionError.exception(
       reason:
         "Interval repeat_rule shape is not expressible as RRULE BY* parts: " <>
           "#{inspect(rule.time)}",
       value: interval,
       target: :rrule
     )}
  end

  defp by_parts(other, interval) do
    {:error,
     ConversionError.exception(
       reason:
         "Interval repeat_rule must be a %Tempo{} with a single :selection entry; " <>
           "got #{inspect(other)}",
       value: interval,
       target: :rrule
     )}
  end

  # Fuse a single-weekday `day_of_week` immediately followed by `instance`
  # back into an ordinal `:byday` entry (the inverse of the §12.9 lowering in
  # `Tempo.RRule.Rule.push_byday/2`). Adjacency is guaranteed: the lowering
  # emits the pair together, ahead of any time element. A list-valued
  # `day_of_week` is a real multi-weekday set-position and is not fused.
  defp recombine_ordinal_byday([{:day_of_week, day}, {:instance, ordinals} | rest])
       when is_integer(day) do
    [{:byday, ordinal_byday_pairs(day, ordinals)} | recombine_ordinal_byday(rest)]
  end

  defp recombine_ordinal_byday([entry | rest]), do: [entry | recombine_ordinal_byday(rest)]
  defp recombine_ordinal_byday([]), do: []

  defp ordinal_byday_pairs(day, ordinals) do
    ordinals |> List.wrap() |> expand_ranges() |> Enum.map(&{&1, day})
  end

  defp encode_by_entry({:month, v}), do: ["BYMONTH=#{list_csv(v)}"]
  defp encode_by_entry({:day, v}), do: ["BYMONTHDAY=#{list_csv(v)}"]
  defp encode_by_entry({:day_of_year, v}), do: ["BYYEARDAY=#{list_csv(v)}"]
  defp encode_by_entry({:week, v}), do: ["BYWEEKNO=#{list_csv(v)}"]
  defp encode_by_entry({:hour, v}), do: ["BYHOUR=#{list_csv(v)}"]
  defp encode_by_entry({:minute, v}), do: ["BYMINUTE=#{list_csv(v)}"]
  defp encode_by_entry({:second, v}), do: ["BYSECOND=#{list_csv(v)}"]
  defp encode_by_entry({:instance, v}), do: ["BYSETPOS=#{list_csv(v)}"]
  defp encode_by_entry({:day_of_week, v}), do: ["BYDAY=#{byday_csv(v)}"]

  defp encode_by_entry({:byday, pairs}) when is_list(pairs),
    do: ["BYDAY=#{byday_pairs_csv(pairs)}"]

  defp encode_by_entry({:wkst, w}) when is_integer(w),
    do: ["WKST=#{Map.fetch!(@weekday_code, w)}"]

  defp encode_by_entry(_unsupported), do: []

  ## BYDAY helpers

  defp byday_csv(day) when is_integer(day), do: Map.fetch!(@weekday_code, day)

  defp byday_csv(days) when is_list(days) do
    days |> expand_ranges() |> Enum.map_join(",", &Map.fetch!(@weekday_code, &1))
  end

  defp byday_pairs_csv(pairs) do
    Enum.map_join(pairs, ",", fn
      {nil, day} -> Map.fetch!(@weekday_code, day)
      {ord, day} when is_integer(ord) -> "#{ord}#{Map.fetch!(@weekday_code, day)}"
    end)
  end

  ## Small helpers

  defp list_csv(n) when is_integer(n), do: Integer.to_string(n)

  defp list_csv(list) when is_list(list),
    do: list |> expand_ranges() |> Enum.map_join(",", &Integer.to_string/1)

  # A selection value may carry consolidated ranges (`[1..5]`); RRULE `BY…`
  # parts are comma-separated integers, so expand them back before joining.
  defp expand_ranges(list) do
    Enum.flat_map(list, fn
      %Range{} = range -> Enum.to_list(range)
      integer -> [integer]
    end)
  end

  defp pad(n, width) when is_integer(n) and n >= 0 do
    n |> Integer.to_string() |> String.pad_leading(width, "0")
  end

  defp pad(n, _), do: Integer.to_string(n)
end
