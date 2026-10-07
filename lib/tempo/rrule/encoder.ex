defmodule Tempo.RRule.Encoder do
  @moduledoc false

  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.NotBuilt
  alias Tempo.RRule.Rule
  alias Tempo.RRule.Selection
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
    :wkst,
    :skip
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
    #
    # The rule is written as it is resolved: a day with no month, in a yearly
    # rule whose start gives it none, is a day of the year (`BYYEARDAY`).
    interval = Selection.read_in_its_period(interval)

    with {:ok, interval} <- keeping_last_day(interval),
         {:ok, freq_and_interval_parts} <- freq_and_interval(time, interval),
         {:ok, bound_part} <- bound_part(interval),
         {:ok, by_parts} <- by_parts(interval.repeat_rule, interval),
         :ok <- NotBuilt.rrule(interval) do
      parts =
        [rscale_part(interval.repeat_rule), bound_part, freq_and_interval_parts, by_parts]
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

  ## The start's day in a period that lacks it

  # The selection tokens that name the day of an occurrence, so that it is
  # not the start's.
  @names_the_day [
    :day,
    :day_of_week,
    :byday,
    :day_of_year,
    :week,
    :calendar_week,
    :event,
    :nearest_weekday,
    :or_day,
    :interval
  ]

  # The selection tokens that make several times of one day.
  @times [:hour, :minute, :second]

  # A recurrence that selects no day is its start and n cadences on, and
  # where a month or a year lacks the start's day it keeps the period's last:
  # 31 January, 28 February, 31 March. A reader of RFC 5545 passes over such
  # a period (§3.3.10), so the rule written for one says the days outright:
  # the last day of the month (`BYMONTHDAY=-1`) where the start's day is at
  # or past the end of every month the rule reaches, and otherwise the last
  # of the days up to the start's (`BYMONTHDAY=28,29,30;BYSETPOS=-1`). A
  # rule that names its day, a start whose day every month reached has, a
  # step of weeks or less and a recurrence of another calendar (refused by
  # name below) are written as they are.
  defp keeping_last_day(%Tempo.Interval{} = interval) do
    case day_left_to_start(interval) do
      {day, months, calendar} -> last_day_stated(interval, day, months, calendar)
      :none -> {:ok, interval}
    end
  end

  # The start's day of the month and the months the recurrence puts it in,
  # where it steps by months or years in the Gregorian calendar and its rule
  # names no day.
  defp day_left_to_start(%Tempo.Interval{
         from: %Tempo{time: time, calendar: calendar},
         duration: %Tempo.Duration{time: [{unit, _count}]},
         repeat_rule: rule
       })
       when unit in [:month, :year] and calendar in [Calendrical.Gregorian, Calendar.ISO, nil] do
    calendar = Compare.effective_calendar(calendar)

    with {:ok, selection} <- selection_of(rule),
         [year, month, day] when is_integer(year) and is_integer(month) and is_integer(day) <-
           Enum.map([:year, :month, :day], &Keyword.get(time, &1)),
         false <- Enum.any?(selection, fn {token, _value} -> token in @names_the_day end),
         [_ | _] = months <- months_reached(unit, month, selection, calendar) do
      {day, months, calendar}
    else
      _names_its_day_or_has_no_date -> :none
    end
  end

  defp day_left_to_start(_interval), do: :none

  # A rule's selection and the units after it, which are parts of it too. A
  # rule of another shape has no RRULE form, and is refused by its own name.
  defp selection_of(nil), do: {:ok, []}

  defp selection_of(%Tempo{time: [{:selection, selection} | units]}),
    do: {:ok, selection ++ units}

  defp selection_of(_another_shape), do: :error

  # The months a start's day is put in: those the rule names, and with none
  # named every month for a step of months and the start's for one of years.
  defp months_reached(unit, start_month, selection, calendar) do
    case UnitValues.in_any_year(:month, [], calendar) do
      {:ok, every_month, _longest} ->
        months_named(Keyword.get(selection, :month), unit, start_month, every_month)

      {:error, _cannot_say} ->
        []
    end
  end

  defp months_named(nil, :month, _start_month, every_month), do: Enum.to_list(every_month)
  defp months_named(nil, :year, start_month, _every_month), do: [start_month]

  defp months_named(named, _unit, _start_month, every_month),
    do: UnitValues.named(named, every_month)

  # The last day each month reached has in every year, and in its longest.
  defp month_ends(months, calendar) do
    for month <- months,
        {:ok, every, longest} <- [UnitValues.in_any_year(:day, [month: month], calendar)],
        do: {every.last, longest.last}
  end

  defp last_day_stated(interval, day, months, calendar) do
    ends = month_ends(months, calendar)
    shortest = ends |> Enum.map(&elem(&1, 0)) |> Enum.min(fn -> day end)

    cond do
      # Every month reached has the day in every year.
      day <= shortest ->
        {:ok, interval}

      # The day is at or past the end of every month reached: its last day.
      Enum.all?(ends, fn {_every, longest} -> day >= longest end) ->
        {:ok, with_days(interval, -1, [])}

      one_set_a_period?(interval, months) ->
        last_of_days(interval, shortest..day//1)

      true ->
        {:error,
         no_one_rule(
           interval,
           "its months are of different lengths, and a yearly rule has one BYMONTHDAY for them all"
         )}
    end
  end

  # BYSETPOS counts within a period of the rule's frequency: a month of a
  # monthly rule, and the year of a yearly one, which is one month's days
  # where the rule reaches one month.
  defp one_set_a_period?(%Tempo.Interval{duration: %Tempo.Duration{time: [{:month, _count}]}}, _),
    do: true

  defp one_set_a_period?(_yearly, months), do: match?([_], months)

  # The last of the days up to the start's is a position, which would count
  # a position the rule already holds and the several times of a day it names.
  defp last_of_days(interval, days) do
    {:ok, selection} = selection_of(interval.repeat_rule)

    if Keyword.has_key?(selection, :instance) or several_times?(selection) do
      {:error,
       no_one_rule(
         interval,
         "the last of the days up to its start's is a BYSETPOS, which would count " <>
           "the position or the times of day the rule holds"
       )}
    else
      {:ok, with_days(interval, [days], instance: -1)}
    end
  end

  defp several_times?(selection) do
    Enum.any?(selection, fn {token, value} ->
      token in @times and not is_integer(value)
    end)
  end

  defp no_one_rule(interval, why) do
    ConversionError.exception(
      reason:
        "RRULE has no one rule for #{inspect(interval)}, which keeps the last day of a month " <>
          "that lacks its start's day: #{why}.",
      value: interval,
      target: :rrule
    )
  end

  # The rule with the days stated: after its years and months, with the
  # start's month for a yearly rule that names none, and a position last.
  defp with_days(%Tempo.Interval{repeat_rule: rule} = interval, days, position) do
    {selection, units} = selection_and_units(rule)

    {coarser, finer} =
      Enum.split_with(selection, fn {token, _value} -> token in [:year, :month] end)

    stated = coarser ++ month_of_start(interval, coarser) ++ [{:day, days}] ++ finer ++ position

    %{
      interval
      | repeat_rule: %Tempo{
          time: [{:selection, stated} | units],
          calendar: Calendrical.Gregorian
        }
    }
  end

  defp selection_and_units(%Tempo{time: [{:selection, selection} | units]}),
    do: {selection, units}

  defp selection_and_units(nil), do: {[], []}

  # `BYMONTHDAY` with no `BYMONTH` in a yearly rule is read as a day of the
  # start's month by some and of every month by others, so the month is said.
  defp month_of_start(
         %Tempo.Interval{
           from: %Tempo{time: time},
           duration: %Tempo.Duration{time: [{:year, _count}]}
         },
         coarser
       ) do
    if Keyword.has_key?(coarser, :month), do: [], else: [month: Keyword.get(time, :month)]
  end

  defp month_of_start(_monthly, _coarser), do: []

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

  ## RSCALE

  # RFC 7529 §4.1: "The SKIP rule part MUST NOT be present unless the RSCALE
  # rule part is present." A rule that holds a skip is counted in the
  # Gregorian calendar, the one an RRULE is written for, and says so.
  defp rscale_part(%Tempo{time: [{:selection, selection} | _units]}) do
    if Keyword.has_key?(selection, :skip), do: "RSCALE=GREGORIAN"
  end

  defp rscale_part(_no_selection), do: nil

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
        with :ok <- numbers_alone(selection ++ units, interval),
             {:ok, selection} <- weekdays_named(selection, calendar, interval),
             {week_start, selection} = week_start(selection, interval),
             selection = recombine_ordinal_byday(selection, numbered_byday?(selection, interval)),
             :ok <- allowed_at_frequency(selection ++ units, interval) do
          {:ok, Enum.flat_map(selection ++ units ++ week_start, &encode_by_entry/1)}
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

  # RFC 5545 writes a part as the numbers it names. One written with
  # unspecified digits (`1XD`) stands for each value its digits match, which
  # the RFC has no way to say.
  defp numbers_alone(parts, interval) do
    if Enum.any?(parts, &match?({_unit, {:mask, _mask}}, &1)),
      do:
        {:error,
         not_allowed(
           "a part written with unspecified digits (X), which stands for each number they match",
           interval
         )},
      else: :ok
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
  #
  # RFC 5545 §3.3.10 allows a numbered `BYDAY` in a MONTHLY rule and in a
  # YEARLY rule with no `BYWEEKNO`, and nowhere else. Where it is not allowed
  # the pair is left as it is, the weekday and the position that say the same.
  #
  # It is left as it is, too, where a numbered `BYDAY` would say something
  # else (`Tempo.RRule.Rule.numbered_weekday_is_position?/3`): beside a day
  # of the month or of the year, which a position counts among and a number
  # does not (`L15D1K1IN` is the 15th when it is a Monday, and
  # `BYMONTHDAY=15;BYDAY=1MO` no day at all), and in a yearly rule of several
  # months, where a number counts in each.
  defp numbered_byday?(selection, interval) do
    frequency = frequency(interval)

    frequency in [:month, :year] and
      Rule.numbered_weekday_is_position?(
        frequency,
        Keyword.get(selection, :month),
        Enum.any?([:day, :day_of_year, :week], &Keyword.has_key?(selection, &1))
      )
  end

  defp frequency(%Tempo.Interval{duration: %Tempo.Duration{time: [{unit, _count}]}}), do: unit
  defp frequency(_interval), do: nil

  # Fuse a single-weekday `day_of_week` immediately followed by `instance`
  # back into an ordinal `:byday` entry (the inverse of the §12.9 lowering in
  # `Tempo.RRule.Rule.push_byday/2`). Adjacency is guaranteed: the lowering
  # emits the pair together, ahead of any time element. A list-valued
  # `day_of_week` is a real multi-weekday set-position and is not fused.
  defp recombine_ordinal_byday(selection, false), do: selection

  defp recombine_ordinal_byday([{:day_of_week, day}, {:instance, ordinals} | rest], true)
       when is_integer(day) do
    [{:byday, ordinal_byday_pairs(day, ordinals)} | recombine_ordinal_byday(rest, true)]
  end

  defp recombine_ordinal_byday([entry | rest], true),
    do: [entry | recombine_ordinal_byday(rest, true)]

  defp recombine_ordinal_byday([], true), do: []

  defp ordinal_byday_pairs(day, ordinals) do
    ordinals |> List.wrap() |> expand_ranges() |> Enum.map(&{&1, day})
  end

  # RFC 5545 §3.3.10: "The BYMONTHDAY rule part MUST NOT be specified when
  # the FREQ rule part is set to WEEKLY", "The BYYEARDAY rule part MUST NOT be
  # specified when the FREQ rule part is set to DAILY, WEEKLY, or MONTHLY" and
  # "The BYWEEKNO rule part MUST NOT be used when the FREQ rule part is set to
  # anything other than YEARLY".
  @forbidden_at %{
    day: [:week],
    day_of_year: [:day, :week, :month],
    week: [:second, :minute, :hour, :day, :week, :month]
  }

  # The parts beside which RFC 5545 allows a `BYSETPOS`: every other `BY`
  # part ("MUST only be used in conjunction with another BYxxx rule part").
  @by_parts [:month, :day, :day_of_year, :week, :day_of_week, :byday, :hour, :minute, :second]

  # A rule is written only as RFC 5545 allows its frequency. A part the RFC
  # forbids there is named with the frequency, and is never written for a
  # reader to reject or to read as another rule.
  defp allowed_at_frequency(parts, interval) do
    unit = frequency(interval)

    case Enum.find_value(parts, &forbidden(&1, unit, parts)) do
      nil -> :ok
      why -> {:error, not_allowed(why, interval)}
    end
  end

  defp forbidden({:byday, pairs}, unit, parts) do
    numbered? = Enum.any?(pairs, fn {ordinal, _day} -> ordinal != nil end)

    cond do
      not numbered? -> nil
      unit == :month -> nil
      unit == :year and not Keyword.has_key?(parts, :week) -> nil
      unit == :year -> "a numbered BYDAY beside BYWEEKNO"
      true -> "a numbered BYDAY in a #{Map.get(@freq_for, unit, inspect(unit))} rule"
    end
  end

  defp forbidden({:instance, _positions}, _unit, parts) do
    if Enum.any?(parts, fn {token, _value} -> token in @by_parts end),
      do: nil,
      else: "BYSETPOS with no other BY part"
  end

  defp forbidden({token, _value}, unit, _parts) do
    if unit in Map.get(@forbidden_at, token, []),
      do: "#{by_part_name(token)} in a #{Map.fetch!(@freq_for, unit)} rule"
  end

  defp by_part_name(:day), do: "BYMONTHDAY"
  defp by_part_name(:day_of_year), do: "BYYEARDAY"
  defp by_part_name(:week), do: "BYWEEKNO"

  defp not_allowed(why, interval) do
    ConversionError.exception(
      reason: "RFC 5545 does not allow #{why}: #{inspect(interval)}",
      value: interval,
      target: :rrule
    )
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

  defp encode_by_entry({:skip, :forward}), do: ["SKIP=FORWARD"]
  defp encode_by_entry({:skip, :backward}), do: ["SKIP=BACKWARD"]

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
