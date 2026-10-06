defmodule Tempo.RRule do
  @moduledoc """
  Reads and writes [iCalendar RFC 5545](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10)
  `RRULE` strings. `parse/2` turns a rule into Tempo's AST — a
  `%Tempo.Interval{}` with a `%Tempo.Duration{}` cadence and, where
  needed, a `repeat_rule` built from selection tokens — and
  `to_string/1` writes one back.

  The AST is the one ISO 8601-2 recurrences parse to, so a rule read
  here and a recurrence read by `Tempo.from_iso8601/1` expand and
  compare alike; the shared AST guide describes the mapping.

  ## Supported rule parts

  * `FREQ` — `SECONDLY` | `MINUTELY` | `HOURLY` | `DAILY` | `WEEKLY`
    | `MONTHLY` | `YEARLY`

  * `INTERVAL` — positive integer, default `1`

  * `COUNT` — positive integer (mutually exclusive with `UNTIL`)

  * `UNTIL` — basic-format ISO 8601 date or date-time

  * `BYMONTH`, `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO`, `BYHOUR`,
    `BYMINUTE`, `BYSECOND` — comma-separated (optionally negative)
    integer list

  * `BYDAY` — comma-separated list where each entry is
    `[<sign><ordinal>]<weekday>` (e.g. `MO`, `-1FR`, `4TH`)

  * `BYSETPOS` — comma-separated integer list

  * `WKST` — weekday code

  ## Returns

  `{:ok, %Tempo.Interval{}}` on success.

  ## Examples

      iex> {:ok, %Tempo.Interval{} = i} = Tempo.RRule.parse("FREQ=DAILY;COUNT=10")
      iex> {i.recurrence, i.duration.time}
      {10, [day: 1]}

      iex> {:ok, i} = Tempo.RRule.parse("FREQ=WEEKLY;INTERVAL=2;UNTIL=20221231")
      iex> i.duration.time
      [week: 2]

  """

  import Kernel, except: [to_string: 1]

  alias Tempo.ConversionError
  alias Tempo.RRule.Encoder
  alias Tempo.RRule.Rule
  alias Tempo.RRule.Selection

  @weekdays %{
    "MO" => 1,
    "TU" => 2,
    "WE" => 3,
    "TH" => 4,
    "FR" => 5,
    "SA" => 6,
    "SU" => 7
  }

  @freq_to_unit %{
    "SECONDLY" => :second,
    "MINUTELY" => :minute,
    "HOURLY" => :hour,
    "DAILY" => :day,
    "WEEKLY" => :week,
    "MONTHLY" => :month,
    "YEARLY" => :year
  }

  @doc """
  Parse an RRULE string into a `%Tempo.Interval{}` AST node.

  ### Arguments

  * `rrule` is a string in RRULE form (with or without the
    leading `RRULE:` prefix).

  ### Options

  * `:from` — the recurrence's start, a `%Tempo{}` (DTSTART). Sets `Interval.from`
    so occurrence enumeration has a starting point. Optional;
    callers that intend to enumerate must supply this. A rule read with a start that is a calendar date states what RFC 5545 takes from it (ISO 8601-2 Annex C.3): a weekly rule its weekday, a monthly rule its day of the month, a yearly rule its month and day. `FREQ=MONTHLY` from 31 January is `~o"R/2026-01-31/P1M/FL31DN"`, which lists the months of 31 days, and each occurrence is as long as the start is precise, a day for a date.

  * `:duration` — a `%Tempo.Duration{}` span for each occurrence,
    the RRULE echo of iCalendar's `DURATION`. Each occurrence spans
    this rather than the span the rule gives it (one unit of its own
    resolution for a day the rule picks), so a
    `FREQ=MONTHLY;BYDAY=1WE` rule starting at 18:00 with a two-hour
    duration emits `18:00/20:00` occurrences.

  * `:base_to` — a `%Tempo{}` upper endpoint for occurrence #0, the
    `DTEND`-style span used by `Tempo.ICal`. Shifted by one cadence
    per iteration so every occurrence preserves the event's span.

  * `:metadata` — a map merged into the interval's metadata.

  ### Returns

  * `{:ok, %Tempo.Interval{}}` on success.

  * `{:error, reason}` on a malformed rule or unknown keyword, and for what RFC 7529's `RSCALE` and `SKIP` say that Tempo does not build: `{:unsupported_rscale, name}` for a calendar other than the Gregorian, `{:unsupported_skip, {skip, part}}` for `BACKWARD` or `FORWARD` beside a day counted from the end of a month that a month can lack (`BYMONTHDAY=-31`), `{:unsupported_skip, value}` for a `SKIP` that is none of the three, and `{:skip_without_rscale, skip}`.

  ### Examples

      iex> {:ok, i} = Tempo.RRule.parse("FREQ=DAILY;COUNT=10")
      iex> i.recurrence
      10

      iex> {:ok, i} =
      ...>   Tempo.RRule.parse("FREQ=DAILY;COUNT=3",
      ...>     duration: %Tempo.Duration{time: [hour: 2]}
      ...>   )
      iex> Tempo.Interval.metadata(i).occurrence_duration.time
      [hour: 2]

      iex> Tempo.RRule.parse("FREQ=MONTHLY;COUNT=3", from: ~o"2026-01-31")
      {:ok, ~o"R3/2026-01-31/P1M/FL31DN"}

      iex> Tempo.RRule.parse("RSCALE=HEBREW;FREQ=YEARLY")
      {:error, {:unsupported_rscale, "HEBREW"}}

      iex> {:error, _} = Tempo.RRule.parse("FREQ=NOPE")

  """
  @spec parse(binary(), keyword()) :: {:ok, Tempo.Interval.t()} | {:error, term()}
  def parse(rrule, options \\ [])

  def parse("RRULE:" <> rest, options), do: parse(rest, options)

  def parse(rrule, options) when is_binary(rrule) do
    with {:ok, parts} <- parse_parts(rrule),
         :ok <- skip_with_rscale(parts) do
      build_interval(parts, options)
    end
  end

  # RFC 7529 §4.1: "The SKIP rule part MUST NOT be present unless the RSCALE
  # rule part is present."
  defp skip_with_rscale(parts) do
    if Keyword.has_key?(parts, :skip) and not Keyword.has_key?(parts, :rscale),
      do: {:error, {:skip_without_rscale, Keyword.fetch!(parts, :skip)}},
      else: :ok
  end

  @doc """
  Bang variant of `parse/2`.
  """
  @spec parse!(binary(), keyword()) :: Tempo.Interval.t()
  def parse!(rrule, options \\ []) do
    case parse(rrule, options) do
      {:ok, interval} -> interval
      {:error, reason} -> raise ArgumentError, "Invalid RRULE: #{inspect(reason)}"
    end
  end

  @doc """
  Write a `t:Tempo.Interval.t/0` as an RRULE string — the inverse of `parse/2`.

  The output has no leading `RRULE:` prefix and no `DTSTART`: an RRULE is a recurrence pattern, not a full iCalendar record, so a caller writing the full record adds `DTSTART` from the interval's start.

  A recurrence that steps by months or years and names no day keeps the last day of a month that lacks its start's, where a reader of RFC 5545 passes over that month, so the rule written for one says the days outright: `~o"R5/2026-01-31/P1M"` is `COUNT=5;FREQ=MONTHLY;BYMONTHDAY=-1`, the last day of each month, and one from the 30th is the last of the days up to it, `BYMONTHDAY=28,29,30;BYSETPOS=-1`. A rule read from an RRULE states its start's day and is written with it.

  A rule is written only as RFC 5545 allows its frequency. A numbered weekday is a numbered `BYDAY` in a monthly rule and in a yearly rule (`BYDAY=2WE`), and the weekday and its position (`BYDAY=WE;BYSETPOS=2`) wherever a numbered `BYDAY` is not allowed or would count something else: at any other frequency, beside a `BYWEEKNO`, a `BYMONTHDAY` or a `BYYEARDAY`, and in a yearly rule of several months, where a number counts in each month and a position across them. A part the RFC forbids at the rule's frequency is an error that names both. A rule with times of day is for a `DTSTART` with a time: RFC 5545 has a reader ignore `BYHOUR`, `BYMINUTE` and `BYSECOND` beside a start that is a date.

  An RRULE is read in the Gregorian calendar (RFC 5545), and RFC 7529's `RSCALE`, which names another, is not written. A recurrence of another calendar is written where an RFC 5545 reader finds the days it selects: one that steps by weeks, days or less and selects by weekday and time of day. Its end is written as the Gregorian date it is, in a calendar of weeks `WKST` is the day the calendar's weeks begin, and the `DTSTART` a caller adds is the Gregorian date of its start (`Tempo.to_calendar/2`).

  ### Arguments

  * `interval` is a recurring `t:Tempo.Interval.t/0`. Its cadence is one unit — `:second`, `:minute`, `:hour`, `:day`, `:week`, `:month` or `:year` — and its recurrence is `:infinity` (no `COUNT`), a positive integer (`COUNT`), or `1` with an end (`UNTIL`). Its repeat rule is `nil` or a selection whose entries for `:month`, `:day` (`BYMONTHDAY`), `:day_of_year`, `:week`, `:hour`, `:minute`, `:second` and the paired `:day_of_week` and `:instance` (`BYDAY`, with ordinals) have RRULE parts.

  ### Returns

  * `{:ok, rrule}` with the rule as a string.

  * `{:error, %Tempo.ConversionError{}}` when the value has no RRULE form — it is not an interval, its cadence has more than one unit, or its selection has an entry RRULE cannot express.

  * `{:error, %Tempo.ConversionError{}}` for a part RFC 5545 forbids at the rule's frequency: `BYMONTHDAY` in a weekly rule, `BYYEARDAY` in a daily, weekly or monthly one, `BYWEEKNO` in any but a yearly one, a numbered `BYDAY` on several weekdays outside a monthly or yearly rule, and a `BYSETPOS` with no other `BY` part.

  * `{:error, %Tempo.ConversionError{}}` when no one rule says a recurrence that keeps the last day of a month without its start's day: its rule holds a position or several times of day, which the `BYSETPOS` of the last of several days would count, or it names months of a year that are of different lengths about that day.

  * `{:error, %Tempo.ConversionError{}}` whose `:reason` is `:not_built` for a recurrence of another calendar than the Gregorian that steps or selects by a month, a year, a week of the year or a day of one, which an RFC 5545 reader would count in the Gregorian calendar.

  ### Examples

      iex> {:ok, interval} = Tempo.RRule.parse("FREQ=DAILY;COUNT=10")
      iex> Tempo.RRule.to_string(interval)
      {:ok, "COUNT=10;FREQ=DAILY"}

      iex> {:ok, interval} = Tempo.RRule.parse("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH")
      iex> Tempo.RRule.to_string(interval)
      {:ok, "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH"}

      iex> {:ok, weekly} = Tempo.from_iso8601("R/2026Y25W/P1W/FL3KN", Calendrical.NRF)
      iex> Tempo.RRule.to_string(weekly)
      {:ok, "FREQ=WEEKLY;BYDAY=TU;WKST=SU"}

      iex> Tempo.RRule.to_string(~o"R5/2026-01-31/P1M")
      {:ok, "COUNT=5;FREQ=MONTHLY;BYMONTHDAY=-1"}

      iex> {:error, %Tempo.ConversionError{}} = Tempo.RRule.to_string(~o"2022-06-15")

  """
  @spec to_string(Tempo.Interval.t() | term()) ::
          {:ok, String.t()} | {:error, ConversionError.t()}
  def to_string(value), do: Encoder.encode(value)

  @doc """
  Bang variant of `to_string/1`: the RRULE string, or a raised
  `Tempo.ConversionError`.

  ### Arguments

  * `interval` is a recurring `t:Tempo.Interval.t/0`; see
    `to_string/1`.

  ### Returns

  * The RRULE string.

  ### Examples

      iex> Tempo.RRule.to_string!(~o"R12/2026-01-05/P1D")
      "COUNT=12;FREQ=DAILY"

  """
  @spec to_string!(Tempo.Interval.t()) :: String.t() | no_return()
  def to_string!(interval) do
    case to_string(interval) do
      {:ok, rrule} -> rrule
      {:error, %ConversionError{} = error} -> raise error
    end
  end

  ## Parsing: text → intermediate keyword list

  defp parse_parts(rrule) do
    rrule
    |> String.trim()
    |> String.split(";", trim: true)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_part(part) do
        {:ok, tuple} -> {:cont, {:ok, [tuple | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp parse_part(part) do
    case String.split(part, "=", parts: 2) do
      [key, value] -> parse_kv(String.upcase(key), value)
      _ -> {:error, {:malformed_part, part}}
    end
  end

  defp parse_kv("FREQ", value) do
    case Map.get(@freq_to_unit, String.upcase(value)) do
      nil -> {:error, {:unknown_freq, value}}
      unit -> {:ok, {:freq, unit}}
    end
  end

  defp parse_kv("INTERVAL", value), do: with_int(value, :interval)
  defp parse_kv("COUNT", value), do: with_int(value, :count)
  defp parse_kv("UNTIL", value), do: parse_until(value)

  defp parse_kv("BYMONTH", value), do: with_int_list(value, :bymonth)
  defp parse_kv("BYMONTHDAY", value), do: with_int_list(value, :bymonthday)
  defp parse_kv("BYYEARDAY", value), do: with_int_list(value, :byyearday)
  defp parse_kv("BYWEEKNO", value), do: with_int_list(value, :byweekno)
  defp parse_kv("BYHOUR", value), do: with_int_list(value, :byhour)
  defp parse_kv("BYMINUTE", value), do: with_int_list(value, :byminute)
  defp parse_kv("BYSECOND", value), do: with_int_list(value, :bysecond)
  defp parse_kv("BYSETPOS", value), do: with_int_list(value, :bysetpos)

  defp parse_kv("BYDAY", value) do
    parts =
      value
      |> String.split(",", trim: true)
      |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
        case parse_byday_entry(entry) do
          {:ok, tuple} -> {:cont, {:ok, [tuple | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case parts do
      {:ok, list} -> {:ok, {:byday, Enum.reverse(list)}}
      error -> error
    end
  end

  defp parse_kv("WKST", value) do
    case Map.get(@weekdays, String.upcase(value)) do
      nil -> {:error, {:unknown_wkst, value}}
      day -> {:ok, {:wkst, day}}
    end
  end

  # RFC 7529: `RSCALE` names the calendar a rule counts its months and its
  # days in, and `SKIP` what it does with a date that does not exist, the
  # 31st of a month of thirty days: `OMIT`, the default and RFC 5545's rule,
  # passes over it, `BACKWARD` takes the month's last day and `FORWARD` the
  # first day of the month after. A rule of another calendar than the
  # Gregorian is not built, and is reported rather than read as another, as
  # `Tempo.JSCalendar` reports it.
  defp parse_kv("RSCALE", value) do
    if String.upcase(value) in ["GREGORIAN", "GREGORY"],
      do: {:ok, {:rscale, :gregorian}},
      else: {:error, {:unsupported_rscale, value}}
  end

  defp parse_kv("SKIP", value) do
    case String.upcase(value) do
      "OMIT" -> {:ok, {:skip, :omit}}
      "BACKWARD" -> {:ok, {:skip, :backward}}
      "FORWARD" -> {:ok, {:skip, :forward}}
      _unknown -> {:error, {:unsupported_skip, value}}
    end
  end

  defp parse_kv(key, _value), do: {:error, {:unknown_rule_part, key}}

  defp parse_byday_entry(entry) do
    with {ordinal, weekday} <- split_byday(entry),
         {:ok, day} <- lookup_weekday(weekday) do
      {:ok, {ordinal, day}}
    else
      :error -> {:error, {:invalid_byday, entry}}
    end
  end

  # Split "-1FR" into {-1, "FR"}, "MO" into {nil, "MO"}.
  defp split_byday(entry) do
    case Regex.run(~r/^(-?\d+)?([A-Za-z]{2})$/, entry) do
      [_, "", day] -> {nil, day}
      [_, ord, day] -> {String.to_integer(ord), day}
      _ -> :error
    end
  end

  defp lookup_weekday(code) do
    case Map.get(@weekdays, String.upcase(code)) do
      nil -> :error
      day -> {:ok, day}
    end
  end

  defp with_int(value, key) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, {key, n}}
      _ -> {:error, {:invalid_integer, value, key}}
    end
  end

  defp with_int_list(value, key) do
    parsed =
      value
      |> String.split(",", trim: true)
      |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
        case Integer.parse(item) do
          {n, ""} -> {:cont, {:ok, [n | acc]}}
          _ -> {:halt, {:error, {:invalid_integer_in_list, item, key}}}
        end
      end)

    case parsed do
      {:ok, list} -> {:ok, {key, Enum.reverse(list)}}
      error -> error
    end
  end

  # UNTIL is basic-format ISO 8601: YYYYMMDD or YYYYMMDDTHHMMSSZ.
  # We round-trip it through `Tempo.from_iso8601/1` to get a proper
  # `%Tempo{}` struct.
  defp parse_until(value) do
    case Tempo.from_iso8601(value) do
      {:ok, tempo} -> {:ok, {:until, tempo}}
      {:error, reason} -> {:error, {:invalid_until, value, reason}}
    end
  end

  ## Building: intermediate list → %Tempo.Interval{}

  defp build_interval(parts, options) do
    case Keyword.fetch(parts, :freq) do
      {:ok, freq_unit} ->
        with :ok <- Rule.skip_built(struct(Rule, parts)),
             do: {:ok, do_build(freq_unit, parts, options)}

      :error ->
        {:error, :missing_freq}
    end
  end

  defp do_build(freq_unit, parts, options) do
    interval = Keyword.get(parts, :interval, 1)
    count = Keyword.get(parts, :count)
    until = Keyword.get(parts, :until)
    from = Keyword.get(options, :from)

    cadence = %Tempo.Duration{time: [{freq_unit, interval}]}

    recurrence = if is_integer(count), do: count, else: :infinity

    repeat_rule = build_repeat_rule(parts, from)

    %Tempo.Interval{
      from: from,
      to: until,
      duration: cadence,
      recurrence: recurrence,
      repeat_rule: repeat_rule,
      metadata:
        options
        |> occurrence_metadata()
        |> as_long_as_its_start(parts, from, Selection.expands?(repeat_rule, freq_unit))
    }
  end

  # An occurrence of a rule is as long as its start is precise, a day for a
  # date. A rule that makes points in its period (a day it states, a time of
  # day) is given their length where it is resolved. One whose `SKIP` is
  # `BACKWARD` states no day, so that the step from its start keeps the last
  # day of a short month, and where it makes no points it is given the length
  # here: without it each occurrence would run a whole cadence, as an ISO
  # 8601 recurrence's does.
  defp as_long_as_its_start(metadata, parts, %Tempo{} = from, false)
       when not is_map_key(metadata, :occurrence_duration) and
              not is_map_key(metadata, :occurrence_base_to) do
    with :backward <- Keyword.get(parts, :skip),
         {unit, _span} when is_atom(unit) <- Tempo.resolution(from) do
      Map.put(metadata, :occurrence_duration, %Tempo.Duration{time: [{unit, 1}]})
    else
      _as_it_is -> metadata
    end
  end

  defp as_long_as_its_start(metadata, _parts, _from, _makes_points?), do: metadata

  # Build the recurring interval's metadata from the parse options,
  # mirroring `Tempo.RRule.Expander.to_ast/3` so the string-parsing
  # and struct-building RRULE paths accept the same span controls:
  #
  #   * `:metadata` — a base map, merged first.
  #
  #   * `:duration` — a `%Tempo.Duration{}` occurrence span, attached
  #     as `occurrence_duration` (the iCalendar `DURATION` echo: each
  #     occurrence spans this rather than the span its rule gives it).
  #
  #   * `:base_to` — a `%Tempo{}` occurrence-0 upper endpoint, attached
  #     as `occurrence_base_to` (the `DTEND`-style span).
  #
  # The materialiser consumes these directives to span each occurrence
  # and strips them from the emitted occurrences.
  defp occurrence_metadata(options) do
    options
    |> Keyword.get(:metadata, %{})
    |> put_if_given(
      :occurrence_duration,
      Keyword.get(options, :duration),
      &match?(%Tempo.Duration{}, &1)
    )
    |> put_if_given(
      :occurrence_base_to,
      Keyword.get(options, :base_to),
      &match?(%Tempo{}, &1)
    )
  end

  defp put_if_given(metadata, key, value, valid?) do
    if valid?.(value), do: Map.put(metadata, key, value), else: metadata
  end

  # The parsed `BY*` parts become the `%Tempo{}` selection carried in the
  # recurring interval's `:repeat_rule`. Both this path and `Tempo.RRule.Expander`
  # build that selection through `Tempo.RRule.Rule.to_selection/1` — the single
  # source of truth for the RRULE → selection token vocabulary (documented there)
  # — so the two paths cannot drift.
  defp build_repeat_rule(parts, from), do: Rule.to_selection(struct(Rule, parts), from)
end
