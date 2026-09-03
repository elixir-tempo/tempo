defmodule Tempo.Inspect do
  @moduledoc false

  import Kernel, except: [inspect: 1]

  alias Localize.Validity.U
  alias Tempo.IntervalSet
  alias Tempo.Iso8601EncodeError
  alias Tempo.Microsecond

  @from_iso8601 "Tempo.from_iso8601!(\""
  @sigil_o "~o\""

  @doc """
  Encode any Tempo value as ISO 8601-2 **explicit-form** iodata.

  The public entry point shared by `Tempo.to_iso8601/1` and the
  Inspect protocol implementation. Returns iodata so callers can
  compose the result before binary conversion.

  ### Examples

      iex> Tempo.from_iso8601!("2022-11-20") |> Tempo.Inspect.to_iodata() |> IO.iodata_to_binary()
      "2022Y11M20D"

  """
  @spec to_iodata(term()) :: iodata()
  def to_iodata(value), do: inspect_value(value)

  # Inspect wraps `Tempo.to_iso8601/1` in sigil syntax. Keeping
  # encoding in one place — `Tempo.to_iso8601/1` — means the
  # Inspect output is guaranteed to round-trip through
  # `Tempo.from_iso8601/1` for the Gregorian and ISO-week cases,
  # and through the equivalent `Tempo.from_iso8601!/2` call for
  # non-default calendars.

  def inspect(%Tempo{calendar: Calendrical.Gregorian} = tempo) do
    # `to_iso8601/1` (via `inspect_value/1`) already appends the
    # IXDTF extended trailer; don't add it again here.
    @sigil_o <> Tempo.to_iso8601(tempo) <> "\""
  end

  def inspect(%Tempo{calendar: Calendrical.ISOWeek} = tempo) do
    @sigil_o <> Tempo.to_iso8601(tempo) <> "\"W"
  end

  def inspect(%Tempo{calendar: calendar} = tempo) do
    # `to_iso8601/1` (via `inspect_value/1`) already appends the
    # IXDTF extended trailer for any zone / calendar / tags present
    # on the Tempo, so we don't add it again here.
    @from_iso8601 <>
      Tempo.to_iso8601(tempo) <>
      "\", " <> Kernel.inspect(calendar) <> ")"
  end

  def inspect(%Tempo.Interval{} = interval) do
    body = @sigil_o <> Tempo.to_iso8601(interval) <> "\""

    case interval_tags(interval) do
      "" -> body
      tags -> "#Tempo.Interval<" <> body <> " " <> tags <> ">"
    end
  end

  def inspect(%Tempo.Duration{} = duration) do
    @sigil_o <> Tempo.to_iso8601(duration) <> "\""
  end

  def inspect(%Tempo.Set{} = set) do
    @sigil_o <> Tempo.to_iso8601(set) <> "\""
  end

  # Non-syntactic interval state renders as a decoration outside the
  # sigil body: the sigil shows the extent, which re-parses without
  # this state, and the decoration signals the difference. `unit` is
  # the explicit iteration granularity a materialised implicit span
  # carries (see `Tempo.Interval` `:unit`); metadata is e.g. iCal
  # event data.
  defp interval_tags(%Tempo.Interval{unit: unit, metadata: metadata}) do
    [unit_tag(unit), interval_metadata_tag(metadata)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp unit_tag(nil), do: ""
  defp unit_tag(unit), do: "unit: " <> Atom.to_string(unit)

  # --------------------------------------------------------------
  # IXDTF trailer helpers — used by the Tempo clauses above to
  # append `[zone]`, `[u-ca=cal]`, and `[key=val]` tags to the
  # sigil body so round-trip through `Tempo.from_iso8601/1` is
  # faithful.
  # --------------------------------------------------------------

  defp extended_trailer(%Tempo{extended: nil}), do: ""

  defp extended_trailer(%Tempo{extended: extended}) do
    [
      zone_id_trailer(extended),
      zone_offset_trailer(extended),
      calendar_trailer(extended),
      tags_trailer(extended)
    ]
    |> IO.iodata_to_binary()
  end

  defp zone_id_trailer(%{zone_id: zone_id} = extended)
       when is_binary(zone_id) and zone_id != "" do
    # Re-emit the RFC 9557 critical flag so a `[!zone]` round-trips.
    critical = if Map.get(extended, :zone_critical, false), do: "!", else: ""
    ["[", critical, zone_id, "]"]
  end

  defp zone_id_trailer(_), do: []

  # An IXDTF numeric offset (`[+08:45]`) is stored as signed minutes from UTC;
  # render it back in the bracketed `[±HH:MM]` form so it round-trips.
  defp zone_offset_trailer(%{zone_offset: minutes}) when is_integer(minutes) do
    sign = if minutes < 0, do: "-", else: "+"
    absolute = abs(minutes)
    ["[", sign, pad_two(div(absolute, 60)), ":", pad_two(rem(absolute, 60)), "]"]
  end

  defp zone_offset_trailer(_), do: []

  defp pad_two(number), do: String.pad_leading(Integer.to_string(number), 2, "0")

  defp calendar_trailer(%{calendar: cal}) when is_atom(cal) and not is_nil(cal) do
    # Emit the IXDTF `[u-ca=value]` form (the `=` separator, borrowed from
    # Temporal), with the value produced by `Localize.Validity.U.encode/2`
    # so it is the preferred BCP 47 identifier (`:gregorian` → `"gregory"`,
    # `:islamic_civil` → `"islamic-civil"`), not a naive atom spelling.
    case encode_calendar(cal) do
      {:ok, value} -> ["[u-ca=", value, "]"]
      :error -> []
    end
  end

  defp calendar_trailer(_), do: []

  # `U.encode/2` raises on an atom that is not a calendar; guard it so
  # inspect/`to_iso8601` never crash on an unexpected value.
  defp encode_calendar(cal) do
    {"ca", value} = U.encode(:ca, cal)
    {:ok, value}
  rescue
    _error -> :error
  end

  defp tags_trailer(%{tags: tags}) when is_map(tags) and map_size(tags) > 0 do
    Enum.map(tags, fn {k, v} ->
      ["[", k, "=", format_tag_value(v), "]"]
    end)
  end

  defp tags_trailer(_), do: []

  defp format_tag_value(values) when is_list(values), do: Enum.join(values, "-")
  defp format_tag_value(value), do: to_string(value)

  # --------------------------------------------------------------
  # Interval metadata compact label. Shown as the trailing tag
  # inside `#Tempo.Interval<...>` when metadata is non-empty.
  # --------------------------------------------------------------

  defp interval_metadata_tag(metadata) when map_size(metadata) == 0, do: ""

  defp interval_metadata_tag(%{summary: s} = metadata) when is_binary(s) do
    location = Map.get(metadata, :location)

    if is_binary(location) and location != "" do
      "· " <> s <> " @ " <> location
    else
      "· " <> s
    end
  end

  defp interval_metadata_tag(%{uid: uid}) when is_binary(uid), do: "· uid=" <> uid

  defp interval_metadata_tag(metadata) do
    "· " <> Integer.to_string(map_size(metadata)) <> " metadata key(s)"
  end

  @doc """
  Inspect a `t:Tempo.IntervalSet.t/0`.

  Renders as `#Tempo.IntervalSet<[...]>` with each interval
  inspected via its own protocol implementation. At most
  `opts.limit` members are shown (the `Inspect.Opts` default is
  `50`); when the set is larger, the shown members are followed by
  the current locale's ellipsis via `Localize.ellipsis/1`. Set-level
  metadata appears as a trailing label when present. Empty sets
  render as `#Tempo.IntervalSet<[]>`.

  """
  def inspect_interval_set(%Tempo.IntervalSet{metadata: metadata} = set, opts) do
    if IntervalSet.empty?(set) do
      "#Tempo.IntervalSet<[]" <> set_metadata_tag(metadata) <> ">"
    else
      inspect_interval_set_members(set, metadata, opts)
    end
  end

  defp inspect_interval_set_members(set, metadata, opts) do
    {shown, truncated?} = take_within_limit(set, opts.limit)

    rendered =
      Enum.map(shown, fn iv ->
        Kernel.inspect(iv, opts |> Map.from_struct() |> Enum.into([]))
      end)

    # Emit the ellipsis as a trailing element so it joins with the same
    # `", "` separator — `[a, b, …]`, matching how Elixir truncates a list.
    elements = if truncated?, do: rendered ++ [ellipsis()], else: rendered

    "#Tempo.IntervalSet<[" <>
      Enum.join(elements, ", ") <> "]" <> set_metadata_tag(metadata) <> ">"
  end

  # `Inspect.Opts.limit` bounds how many members are rendered; `:infinity`
  # shows them all — except on an unbounded (lazy) set, where "all" would
  # walk forever, so the default limit of 50 applies instead. Members are
  # taken from the walk, never `to_list/1`, so a lazy set inspects safely.
  defp take_within_limit(set, :infinity) do
    if IntervalSet.bounded?(set) do
      {IntervalSet.to_list(set), false}
    else
      take_within_limit(set, 50)
    end
  end

  defp take_within_limit(set, limit) when is_integer(limit) and limit >= 0 do
    {shown, rest} = set |> IntervalSet.walk() |> Enum.take(limit + 1) |> Enum.split(limit)
    {shown, rest != []}
  end

  # The current locale's ellipsis mark, from the CLDR ellipsis pattern via
  # `Localize.ellipsis/1`. Inspect sits on the render path and must never
  # raise, so fall back to U+2026 if the locale data cannot be loaded.
  defp ellipsis do
    case Localize.ellipsis("") do
      {:ok, mark} -> mark
      {:error, _reason} -> "…"
    end
  end

  # Set-level metadata tag. For a calendar import the most
  # interesting fields are the calendar name and the prodid; show
  # those verbatim when present.
  defp set_metadata_tag(nil), do: ""

  defp set_metadata_tag(metadata) when map_size(metadata) == 0, do: ""

  defp set_metadata_tag(%{name: name}) when is_binary(name) do
    " · " <> name
  end

  defp set_metadata_tag(%{prodid: prodid}) when is_binary(prodid) do
    " · " <> prodid
  end

  defp set_metadata_tag(metadata) do
    " · " <> Integer.to_string(map_size(metadata)) <> " metadata key(s)"
  end

  # inspect_value/1 for everything else

  defp inspect_value([{unit, _value1} = first, {time, _value2} = second | t])
       when unit in [:year, :month, :day, :day_of_year, :week, :day_of_week] and
              time in [:hour, :minute, :second] do
    [inspect_value(first), inspect_value([second | t])]
  end

  # The next three clauses are to ensure we only put one "T"
  # in the output. Three because :hour, :minute, :second

  defp inspect_value([{unit, _value1} = first, second, third])
       when unit in [:hour, :minute, :second] do
    [?T, inspect_value(first), inspect_value(second), inspect_value(third)]
  end

  defp inspect_value([{unit, _value1} = first, second])
       when unit in [:hour, :minute, :second] do
    [?T, inspect_value(first) | inspect_value(second)]
  end

  defp inspect_value([{unit, _value1} = first])
       when unit in [:hour, :minute, :second] do
    [?T, inspect_value(first)]
  end

  # Making sure the ?T time marker is inserted the
  # first time we encounter a time unit of :hour, :minute
  # or :second

  defp inspect_value([{:selection, selection} | rest]) do
    selection =
      Enum.reduce(selection, {[], nil}, fn
        {:interval, interval}, {acc, time_marker} ->
          {[[?L, inspect_value(interval), ?N] | acc], time_marker}

        {unit_2, value_2}, {acc, nil} when unit_2 in [:hour, :minute, :second] ->
          {[inspect_value({unit_2, value_2}), ?T | acc], true}

        other, {acc, time_marker} ->
          {[inspect_value(other) | acc], time_marker}
      end)
      |> elem(0)
      |> Enum.reverse()

    [?L, selection, ?N | inspect_value(rest)]
  end

  defp inspect_value([h | t]) do
    [inspect_value(h) | inspect_value(t)]
  end

  defp inspect_value([]) do
    []
  end

  defp inspect_value(%Range{first: first, last: last, step: 1}) do
    [inspect_value(first), "..", inspect_value(last)]
  end

  defp inspect_value(%Range{first: first, last: last, step: step}) do
    [inspect_value(first), "..", inspect_value(last), ?/, ?/, inspect_value(step)]
  end

  defp inspect_value(number) when is_number(number) do
    Kernel.inspect(number)
  end

  defp inspect_value(:any) do
    [?X, ?*]
  end

  defp inspect_value({number, [margin_of_error: margin]}) do
    Kernel.inspect(number) <> "±" <> Kernel.inspect(margin)
  end

  defp inspect_value({number, [significant_digits: digits]}) when is_integer(number) do
    Kernel.inspect(number) <> "S" <> Integer.to_string(digits)
  end

  defp inspect_value({number, [significant_digits: digits, margin_of_error: margin]})
       when is_integer(number) do
    Kernel.inspect(number) <> "S" <> Integer.to_string(digits) <> "±" <> Kernel.inspect(margin)
  end

  defp inspect_value({:mask, [:negative | rest]}) do
    [?-, inspect_value({:mask, rest})]
  end

  defp inspect_value({:mask, mask}) do
    Enum.reduce(mask, [], fn
      :X, acc ->
        [?X | acc]

      int, acc when is_integer(int) ->
        [Integer.to_string(int) | acc]

      list, acc when is_list(list) ->
        [?}, Enum.map_join(list, ",", &inspect_value/1), ?{ | acc]
    end)
    |> Enum.reverse()
  end

  defp inspect_value({value, continuation}) when is_function(continuation) do
    Kernel.inspect(value)
  end

  defp inspect_value({unit, {:group, %Range{first: first, last: last}}}) do
    group_size = last - first + 1
    nth = div(last, group_size)

    [_, unit_key] = inspect_value({unit, 1})
    [inspect_value(nth), ?G, inspect_value(group_size), unit_key, ?U]
  end

  defp inspect_value({unit, {:group, {set_type, set_values}}, value}) do
    [_, unit_key] = inspect_value({unit, value})
    elements = Enum.map_join(set_values, ",", &inspect_value/1)
    [open(set_type), elements, close(set_type), ?G, inspect_value(value), unit_key, ?U]
  end

  defp inspect_value(%Tempo{} = tempo) do
    {qualification, qualifications} = canonical_qualifications(tempo)

    time =
      tempo.time
      |> fold_microsecond()
      |> apply_qualifications(qualifications)

    [
      inspect_value(time),
      inspect_shift(tempo.shift),
      inspect_qualification(qualification),
      extended_trailer(tempo)
    ]
  end

  defp inspect_value(%Tempo.Set{set: set, type: type}) do
    elements = Enum.map_join(set, ",", &inspect_value/1)

    [open(type), elements, close(type)]
  end

  # Intervals with a nil `from` are produced by callers that build
  # the struct directly without an anchor (e.g. the RRule parser
  # for a rule without DTSTART). These clauses come *before* the
  # generic repeat-rule clauses below so the nil case is matched
  # first — otherwise those clauses would bind `from: from` to
  # `nil` and then crash on `from.time`.
  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: nil,
         to: nil,
         duration: %Tempo.Duration{} = duration,
         repeat_rule: nil
       }) do
    [?R, recurrence(recurrence), ?/, "..", ?/, inspect_value(duration)]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: nil,
         to: %Tempo{} = to,
         duration: %Tempo.Duration{} = duration,
         repeat_rule: nil
       }) do
    [
      ?R,
      recurrence(recurrence),
      ?/,
      "..",
      ?/,
      inspect_value(to),
      ?/,
      inspect_value(duration)
    ]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: nil,
         to: nil,
         duration: %Tempo.Duration{} = duration,
         repeat_rule: %Tempo{time: rule_time}
       }) do
    [
      ?R,
      recurrence(recurrence),
      ?/,
      "..",
      ?/,
      inspect_value(duration),
      ?/,
      ?F,
      inspect_value(rule_time)
    ]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: nil,
         to: %Tempo{} = to,
         duration: %Tempo.Duration{} = duration,
         repeat_rule: %Tempo{time: rule_time}
       }) do
    [
      ?R,
      recurrence(recurrence),
      ?/,
      "..",
      ?/,
      inspect_value(to),
      ?/,
      inspect_value(duration),
      ?/,
      ?F,
      inspect_value(rule_time)
    ]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: from,
         to: to,
         repeat_rule: repeat_rule
       })
       when not is_nil(to) and not is_nil(repeat_rule) do
    [
      ?R,
      recurrence(recurrence),
      ?/,
      inspect_value(from),
      ?/,
      inspect_value(to),
      ?/,
      ?F,
      inspect_value(repeat_rule)
    ]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: from,
         duration: duration,
         repeat_rule: repeat_rule
       })
       when not is_nil(duration) and not is_nil(repeat_rule) do
    [
      ?R,
      recurrence(recurrence),
      ?/,
      inspect_value(from),
      ?/,
      inspect_value(duration),
      ?/,
      ?F,
      inspect_value(repeat_rule)
    ]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: 1,
         from: :undefined,
         to: :undefined,
         duration: nil
       }) do
    [?., ?., ?/, ?., ?.]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: 1,
         from: from,
         to: :undefined = to,
         duration: nil
       }) do
    [inspect_value(from), ?/, inspect_value(to)]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: 1,
         from: :undefined = from,
         to: to,
         duration: nil
       }) do
    [inspect_value(from), ?/, inspect_value(to)]
  end

  defp inspect_value(%Tempo.Interval{recurrence: 1, from: from, to: to, duration: nil}) do
    [inspect_value(drop_shared_suffix(from, to)), ?/, inspect_value(abbreviate(to, from))]
  end

  defp inspect_value(%Tempo.Interval{recurrence: 1, from: from, to: nil, duration: duration}) do
    [inspect_value(from), ?/, inspect_value(duration)]
  end

  # An interval that takes its extent from a duration has no end
  # endpoint, so an explicitly open `to` says the same thing as an
  # absent one. Render them alike rather than matching neither.
  defp inspect_value(%Tempo.Interval{to: :undefined, duration: %Tempo.Duration{}} = interval) do
    inspect_value(%{interval | to: nil})
  end

  # Duration-first: `P1D/2022-01-01` — a bounded-end interval
  # whose start is derived from the duration. The tokenizer
  # models this with `from: :undefined` so the endpoint is shown
  # as `..` for consistency with half-open notation.
  defp inspect_value(%Tempo.Interval{
         recurrence: 1,
         from: :undefined,
         to: %Tempo{} = to,
         duration: %Tempo.Duration{} = duration
       }) do
    [inspect_value(duration), ?/, inspect_value(to)]
  end

  # The same shape repeated — `R3/P1D/2022-01-01`. The tokenizer
  # parses this, so it must render too.
  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: :undefined,
         to: %Tempo{} = to,
         duration: %Tempo.Duration{} = duration
       }) do
    [?R, recurrence(recurrence), ?/, inspect_value(duration), ?/, inspect_value(to)]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: from,
         to: :undefined = to,
         duration: nil
       }) do
    [?R, recurrence(recurrence), ?/, inspect_value(from), ?/, inspect_value(to)]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: :undefined = from,
         to: to,
         duration: nil
       }) do
    [?R, recurrence(recurrence), ?/, inspect_value(from), ?/, inspect_value(to)]
  end

  defp inspect_value(%Tempo.Interval{recurrence: recurrence, from: from, to: to, duration: nil}) do
    [?R, recurrence(recurrence), ?/, inspect_value(from), ?/, inspect_value(abbreviate(to, from))]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: from,
         to: nil,
         duration: duration
       }) do
    [?R, recurrence(recurrence), ?/, inspect_value(from), ?/, inspect_value(duration)]
  end

  # The zero duration has no components to imply the `T`/units, and a
  # bare `P` does not re-parse; ISO 8601's zero duration is `PT0S`.
  defp inspect_value(%Tempo.Duration{time: []}), do: "PT0S"

  defp inspect_value(%Tempo.Duration{time: time}) do
    [?P, inspect_value(fold_microsecond(time))]
  end

  defp inspect_value(%Tempo.Range{first: first, last: :undefined}) do
    [inspect_value(first), inspect_value(:undefined)]
  end

  defp inspect_value(%Tempo.Range{first: :undefined, last: last}) do
    [inspect_value(:undefined), inspect_value(last)]
  end

  defp inspect_value(%Tempo.Range{first: first, last: last}) do
    [inspect_value(first), "..", inspect_value(last)]
  end

  # Qualified components (ISO 8601-2 §8.3) — the qualifier symbol sits
  # between the value and its designator.
  defp inspect_value({:second, {:q, {:micro, second, microsecond}, qualifier}}) do
    [
      inspect_list(second),
      ?.,
      Microsecond.to_digits_string(microsecond),
      inspect_qualification(qualifier),
      ?S
    ]
  end

  defp inspect_value({unit, {:q, value, qualifier}}) do
    [inspect_list(value), inspect_qualification(qualifier), unit_designator(unit)]
  end

  defp inspect_value({:year, year}), do: [inspect_list(year), ?Y]
  defp inspect_value({:month, month}), do: [inspect_list(month), ?M]
  defp inspect_value({:day, day}), do: [inspect_list(day), ?D]
  defp inspect_value({:day_of_year, day}), do: [inspect_list(day), ?O]
  defp inspect_value({:hour, hour}), do: [inspect_list(hour), ?H]
  defp inspect_value({:minute, minute}), do: [inspect_list(minute), ?M]

  # A negative fractional second is a sign-consistent pair
  # (`[second: -1, microsecond: {-500000, 1}]` is −1.5 s); render one
  # leading sign with the fraction's absolute digits — `-1.5S`, never
  # `-1.-5S`. A zero second still needs the explicit sign: `-0.2S`.
  defp inspect_value({:second, {:micro, second, {value, precision}}}) when value < 0 do
    digits = Microsecond.to_digits_string({-value, precision})
    leading = if second == 0, do: "-0", else: inspect_list(second)
    [leading, ?., digits, ?S]
  end

  defp inspect_value({:second, {:micro, second, microsecond}}),
    do: [inspect_list(second), ?., Microsecond.to_digits_string(microsecond), ?S]

  defp inspect_value({:second, second}), do: [inspect_list(second), ?S]
  defp inspect_value({:day_of_week, day}), do: [inspect_list(day), ?K]
  defp inspect_value({:week, week}), do: [inspect_list(week), ?W]
  defp inspect_value({:instance, instance}), do: [inspect_value(instance), ?I]

  # RRULE BYDAY carrying an ordinal (`2MO` = the 2nd Monday, `-1FR` = the
  # last Friday, `1MO,3MO` = the 1st and 3rd) has no native ISO 8601 unit,
  # so it is held as a `:byday` selection of `{ordinal, day_of_week}`
  # pairs. Render each pair in the instance (`I`) + day-of-week (`K`)
  # notation the selection grammar already uses; a `nil` ordinal is a
  # plain day-of-week. The parser folds that same notation back into a
  # `:byday` selection, so this inspection form round-trips.
  defp inspect_value({:byday, entries}) when is_list(entries) do
    Enum.map(entries, fn
      {nil, day} -> [inspect_list(day), ?K]
      {ordinal, day} -> [inspect_value(ordinal), ?I, inspect_list(day), ?K]
    end)
  end

  # RRULE BYSETPOS and WKST have no ISO 8601 designator — they are RFC 5545
  # extensions. Tempo renders them with the project-specific selection
  # designators `V` (set position) and `Q` (week start) so a recurrence
  # carrying them round-trips through `inspect/1`/`to_iso8601/1` rather than
  # crashing; the canonical external form remains the RRULE string.
  defp inspect_value({:set_position, position}), do: [inspect_list(position), ?V]
  defp inspect_value({:wkst, weekday}), do: [inspect_list(weekday), ?Q]

  # A nearest-weekday selection (cron `W`, parsed to `:nearest_weekday`) has
  # no ISO 8601 designator and — unlike `V`/`Q` above — was deliberately not
  # given a project-specific one (the day-level operation is
  # `Tempo.nearest_working_day/2`). Raise a clear error instead of a
  # `FunctionClauseError`; the Inspect protocol catches it and falls back.
  defp inspect_value({:nearest_weekday, _targets}) do
    raise Iso8601EncodeError.exception(construct: :nearest_weekday)
  end

  defp inspect_value({:interval, interval}), do: inspect_value(interval)
  defp inspect_value({:duration, duration}), do: inspect_value(duration)
  defp inspect_value(:undefined), do: ".."

  @qualifiable_units [
    :year,
    :month,
    :day,
    :day_of_year,
    :week,
    :day_of_week,
    :hour,
    :minute,
    :second
  ]

  # ISO 8601-2 §8.2.4: when every present component carries the same
  # qualifier, prefer the compact *complete* form (one trailing
  # qualifier) over per-component qualifiers — `2004%Y6%M11%D` reduces
  # to `2004Y6M11D%`. The explicit (designator) output form has no
  # *group* representation, so complete is the only available collapse.
  defp canonical_qualifications(%Tempo{
         qualification: nil,
         qualifications: qualifications,
         time: time
       })
       when is_map(qualifications) and map_size(qualifications) > 0 do
    present = for {unit, _value} <- time, unit in @qualifiable_units, do: unit
    values = Enum.map(present, &Map.get(qualifications, &1))

    if present != [] and map_size(qualifications) == length(present) and
         match?([_single], Enum.uniq(values)) and hd(values) != nil do
      {hd(values), nil}
    else
      {nil, qualifications}
    end
  end

  defp canonical_qualifications(%Tempo{
         qualification: qualification,
         qualifications: qualifications
       }) do
    {qualification, qualifications}
  end

  # ISO 8601-2 §8.3 explicit component qualification: tag each unit
  # that carries a per-component qualifier with a `{:q, value, q}`
  # marker so the leaf renderer can emit the qualifier between the
  # value and its designator (`2004~Y`). The `{unit, _}` shape is
  # preserved so the list-walking clauses still route correctly.
  defp apply_qualifications(time, nil), do: time
  defp apply_qualifications(time, qualifications) when qualifications == %{}, do: time

  defp apply_qualifications(time, qualifications) do
    Enum.map(time, fn
      {unit, value} when is_map_key(qualifications, unit) ->
        {unit, {:q, value, Map.fetch!(qualifications, unit)}}

      other ->
        other
    end)
  end

  defp inspect_shift(nil),
    do: ""

  defp inspect_shift(hour: 0),
    do: ?Z

  defp inspect_shift(hour: hour) when hour > 0,
    do: [?Z, ?+, inspect_value(hour), ?H]

  defp inspect_shift(hour: hour),
    do: [?Z, inspect_value(hour), ?H]

  defp inspect_shift(hour: hour, minute: minute) when hour > 0,
    do: [?Z, ?+, inspect_value(hour), ?H, inspect_value(minute), ?M]

  defp inspect_shift(hour: hour, minute: minute),
    do: [?Z, inspect_value(hour), ?H, inspect_value(minute), ?M]

  defp inspect_qualification(nil), do: []
  defp inspect_qualification(:uncertain), do: "?"
  defp inspect_qualification(:approximate), do: "~"
  defp inspect_qualification(:uncertain_and_approximate), do: "%"

  defp unit_designator(:year), do: ?Y
  defp unit_designator(:month), do: ?M
  defp unit_designator(:day), do: ?D
  defp unit_designator(:day_of_year), do: ?O
  defp unit_designator(:hour), do: ?H
  defp unit_designator(:minute), do: ?M
  defp unit_designator(:second), do: ?S
  defp unit_designator(:day_of_week), do: ?K
  defp unit_designator(:week), do: ?W

  # Fold a trailing `:microsecond` component into the preceding
  # `:second` so the per-unit renderer and the T-marker arity logic
  # (which counts up to three time units and assumes one 2-tuple per
  # unit) see a single second token that renders as "45.123S".
  defp fold_microsecond([{:second, second}, {:microsecond, microsecond} | rest]) do
    [{:second, {:micro, second, microsecond}} | fold_microsecond(rest)]
  end

  defp fold_microsecond([head | rest]), do: [head | fold_microsecond(rest)]
  defp fold_microsecond([]), do: []
  defp fold_microsecond(other), do: other

  defp inspect_list(list) when is_list(list) do
    elements = Enum.map_join(list, ",", &inspect_value/1)
    [open(:all), elements, close(:all)]
  end

  defp inspect_list(value) do
    inspect_value(value)
  end

  defp open(:all), do: ?{
  defp open(:one), do: ?[
  defp close(:all), do: ?}
  defp close(:one), do: ?]

  defp recurrence(:infinity), do: <<>>
  defp recurrence(recurrence), do: Integer.to_string(recurrence)

  # IXDTF binds an interval's extended suffix to its *end*, and
  # `Tempo.Interval.propagate_endpoint_frame/2` flows a grounded `to`
  # frame backward onto a floating `from`. So when both endpoints carry
  # the same *zone*, writing it twice is redundant — the single-suffix
  # form re-parses to the same value.
  #
  # Both the zone and a `u-ca` calendar propagate backward, so either may
  # be written once. Arbitrary IXDTF tags do not propagate — they are
  # per-endpoint metadata — so a suffix carrying any is kept on both ends.
  defp drop_shared_suffix(%Tempo{extended: same} = from, %Tempo{extended: same})
       when not is_nil(same) do
    if propagating_suffix?(same), do: %{from | extended: nil}, else: from
  end

  defp drop_shared_suffix(from, _to), do: from

  defp propagating_suffix?(%{} = extended) do
    Map.get(extended, :tags, %{}) == %{} and
      (is_binary(Map.get(extended, :zone_id)) or
         not is_nil(Map.get(extended, :zone_offset)) or
         not is_nil(Map.get(extended, :calendar)))
  end

  # ISO 8601-1 §5.5.1 lets an interval omit from its end the higher
  # order components it shares with its start, and that is how people
  # write one: `2025-08-28T09:00/T10:15` rather than repeating the
  # date. Rendering it back the same way keeps the printed form as
  # short as the written one, and the parser expands it again, so the
  # value round-trips unchanged.
  #
  # The shared prefix must be a true prefix — the first component that
  # differs stops it — because only leading components can be implied
  # by the start. Anything that changes how a component is *read* has
  # to match too: a different zone, calendar or qualification on the
  # end is not implied by the start and would be lost.
  defp abbreviate(%Tempo{time: to_units} = to, %Tempo{time: from_units} = from)
       when is_list(to_units) and is_list(from_units) do
    if implied_by?(to, from) do
      case shared_prefix(to_units, from_units) do
        # Identical endpoints, or nothing in common: there is no
        # shorter form that still says the same thing.
        [] -> to
        ^to_units -> to
        remaining -> %{to | time: remaining}
      end
    else
      to
    end
  end

  defp abbreviate(to, _from), do: to

  defp implied_by?(%Tempo{} = to, %Tempo{} = from) do
    to.shift == from.shift and to.calendar == from.calendar and
      to.qualification == from.qualification and to.qualifications == from.qualifications
  end

  defp shared_prefix([same | to_rest], [same | from_rest]), do: shared_prefix(to_rest, from_rest)
  defp shared_prefix(to_units, _from_units), do: to_units
end
