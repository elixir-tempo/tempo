defmodule Tempo.RRule.Encoder do
  @moduledoc false

  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.NotBuilt
  alias Tempo.UnitValues

  # Converts a `%Tempo.Interval{}` back into an RFC 5545 RRULE
  # string. Pure AST → text; no parsing. Called via
  # `Tempo.RRule.to_string/1`.

  @freq_for %{
    second: "SECONDLY",
    minute: "MINUTELY",
    hour: "HOURLY",
    day: "DAILY",
    week: "WEEKLY",
    month: "MONTHLY",
    year: "YEARLY"
  }

  # The selection tokens with an RRULE BY-part (and WKST).
  @rrule_tokens [
    :month,
    :day,
    :day_of_year,
    :week,
    :day_of_week,
    :byday,
    :hour,
    :minute,
    :second,
    :instance,
    :wkst
  ]

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
  # A recurrence written with a start and an end (`R5/2026-06-15/2026-06-20`)
  # steps by the length of its first occurrence, as `Tempo.to_interval/2` walks
  # it, so its rule is that of the recurrence written with that duration.
  def encode(
        %Tempo.Interval{
          recurrence: recurrence,
          from: %Tempo{} = from,
          to: %Tempo{} = to,
          duration: nil
        } =
          interval
      )
      when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    with {:ok, duration} <- Tempo.duration(from, to) do
      encode(%{interval | to: nil, duration: duration})
    end
  end

  # A recurrence written with a duration and an end (`R5/P1D/2026-06-20`) ends
  # with its last occurrence, which is no UNTIL: its rule is its count and
  # cadence, from its first occurrence. Without a count it runs back without
  # end and has no first occurrence, which an RRULE needs.
  def encode(%Tempo.Interval{recurrence: count, from: :undefined, to: %Tempo{}} = interval)
      when is_integer(count) and count > 1 do
    encode(%{interval | to: nil})
  end

  def encode(%Tempo.Interval{recurrence: :infinity, from: :undefined, to: %Tempo{}} = interval) do
    {:error,
     ConversionError.exception(
       reason:
         "An RRULE runs forward from its first occurrence, and #{inspect(interval)} runs " <>
           "back from its end without one.",
       value: interval,
       target: :rrule
     )}
  end

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

    # What RRULE has no form for in any calendar is refused first, each by
    # its own name. What is left would be written, and is refused where it
    # would be read in the Gregorian calendar as another rule.
    with {:ok, freq_and_interval_parts} <- freq_and_interval(time, interval),
         {:ok, bound_part} <- bound_part(interval),
         {:ok, by_parts} <- by_parts(interval.repeat_rule, interval),
         :ok <- NotBuilt.rrule(interval) do
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

  # RRULE UNTIL uses basic-format ISO 8601 — no separators — and is a date
  # of the Gregorian calendar, so an end in another calendar is written as
  # the Gregorian date it is.
  defp encode_until(%Tempo{calendar: calendar} = value)
       when calendar not in [Calendrical.Gregorian, Calendar.ISO, nil] do
    with {:ok, %Tempo{} = gregorian} <- Tempo.to_calendar(value, Calendrical.Gregorian),
         do: encode_until(gregorian)
  end

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

  # A selection encodes only when every token has an RRULE BY-part; one
  # that has none is an error naming it, never a part silently dropped. The
  # units after a selection (`L5K2INT9H`) are BY-parts too.
  defp by_parts(%Tempo{time: [{:selection, selection} | units], calendar: calendar}, interval) do
    case (selection ++ units)
         |> Keyword.keys()
         |> Enum.reject(&(&1 in @rrule_tokens))
         |> Enum.uniq() do
      [] ->
        with {:ok, selection} <- weekdays_named(selection, calendar, interval) do
          {week_start, selection} = week_start(selection, interval)

          {:ok,
           encode_selection(selection) ++ Enum.flat_map(units ++ week_start, &encode_by_entry/1)}
        end

      tokens ->
        {:error,
         ConversionError.exception(
           reason:
             "RRULE has no form for #{Enum.map_join(tokens, ", ", &token_description/1)}: " <>
               inspect(selection),
           value: interval,
           target: :rrule
         )}
    end
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

  # WKST says the day a rule's weeks begin, which is Monday where none is
  # written, and is always the last part written. A recurrence in a calendar
  # of weeks counts its weeks as the calendar does, whatever week start its
  # rule holds, so the one written for it is the calendar's: the day its weeks
  # begin where the rule steps by weeks and that day is not Monday, and
  # otherwise none.
  defp week_start(selection, interval) do
    {held, selection} = Enum.split_with(selection, &match?({:wkst, _day}, &1))
    {week_start_in(counted_in(interval), held, interval), selection}
  end

  defp week_start_in(calendar, held, %Tempo.Interval{duration: %Tempo.Duration{time: time}}) do
    cond do
      not Tempo.week_based_calendar?(calendar) -> held
      Keyword.has_key?(time, :week) -> calendar_week_start(calendar)
      true -> []
    end
  end

  defp calendar_week_start(calendar) do
    case UnitValues.iso_weekday_from_day_of_week(1, calendar) do
      1 -> []
      weekday -> [wkst: weekday]
    end
  end

  # The calendar a recurrence's occurrences are counted in: that of its
  # start, and with no start that of its rule.
  defp counted_in(%Tempo.Interval{from: %Tempo{calendar: calendar}}),
    do: Compare.effective_calendar(calendar)

  defp counted_in(%Tempo.Interval{repeat_rule: %Tempo{calendar: calendar}}),
    do: Compare.effective_calendar(calendar)

  # BYDAY names weekdays, and a selection holds days of the week of its
  # rule's calendar, the last of them written `-1K`. Each is written as the
  # weekday it is there (`Tempo.UnitValues.iso_weekday_from_day_of_week/2`):
  # the third day is Wednesday in a calendar of months and Tuesday in a
  # calendar of weeks that start on Sunday. A day no week has is no weekday
  # for a BYDAY to name.
  defp weekdays_named(selection, calendar, interval) do
    calendar = Compare.effective_calendar(calendar)

    Enum.reduce_while(selection, {:ok, []}, fn entry, {:ok, named} ->
      case weekday_named(entry, calendar) do
        {:day_of_week, []} -> {:halt, {:error, no_such_weekday(entry, interval)}}
        entry -> {:cont, {:ok, named ++ [entry]}}
      end
    end)
  end

  defp weekday_named({:day_of_week, days}, calendar) do
    case UnitValues.in_period(:day_of_week, [], calendar) do
      {:ok, week} -> {:day_of_week, days |> UnitValues.named(week) |> weekdays(calendar)}
      {:error, _cannot_count} -> {:day_of_week, days}
    end
  end

  defp weekday_named(entry, _calendar), do: entry

  # One weekday is written as a number, so that with a position after it it
  # is an ordinal weekday again (`2MO`).
  defp weekdays([day], calendar), do: UnitValues.iso_weekday_from_day_of_week(day, calendar)

  defp weekdays(days, calendar),
    do: Enum.map(days, &UnitValues.iso_weekday_from_day_of_week(&1, calendar))

  defp no_such_weekday({:day_of_week, days}, interval) do
    ConversionError.exception(
      reason: "RRULE has no form for a day of the week that no week has: #{inspect(days)}",
      value: interval,
      target: :rrule
    )
  end

  # Each selection token maps to one RRULE BY-part, with one recombination
  # first: ISO 8601-2 §12.9 lowers an ordinal `BYDAY` to a weekday followed
  # by a position (`2MO` → `day_of_week: 1, instance: 2`). Re-fusing that
  # adjacent pair lets `Tempo.RRule.to_string/1` emit the compact, idiomatic `BYDAY=2MO`
  # rather than the equivalent-but-verbose `BYDAY=MO;BYSETPOS=2`. A genuine
  # set-position over several weekdays keeps `day_of_week` as a list and is
  # left untouched, so it still encodes as `BYDAY=…;BYSETPOS=…`.
  defp encode_selection(selection) do
    selection
    |> recombine_ordinal_byday()
    |> Enum.flat_map(&encode_by_entry/1)
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

  # What a selection token with no RRULE BY-part selects, and why RFC 5545
  # cannot say it.
  defp token_description(:calendar_week),
    do: "a calendar week (w), since BYWEEKNO counts ISO 8601 weeks"

  defp token_description(:traditional_month),
    do: "a traditional month (m), since BYMONTH numbers a month by its position"

  defp token_description(:event), do: "a computed event (e)"
  defp token_description(:year), do: "a year (Y)"
  defp token_description(:interval), do: "a selection window (ISO 8601-2 §12.10)"
  defp token_description(:nearest_weekday), do: "a nearest weekday (cron W)"

  defp token_description(:or_day),
    do: "a day of the month or of the week (cron), since RRULE BY-parts all hold at once"

  defp token_description(token), do: inspect(token)

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
