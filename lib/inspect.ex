defmodule Tempo.Inspect do
  @moduledoc false

  import Kernel, except: [inspect: 1]

  alias Calendrical.Gregorian
  alias Localize.Validity.U
  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Iso8601EncodeError
  alias Tempo.Math
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
  def to_iodata(value), do: to_iodata(value, Gregorian)

  # The encoding with a value in `implied` left unnamed: the Gregorian
  # calendar a bare ISO 8601 string reads as, or the ISO week calendar the
  # `W` sigil modifier gives.
  defp to_iodata(value, implied) do
    case value |> with_calendar_names(implied) |> hoist_calendar_name(implied) do
      {value, []} -> inspect_value(value)
      {value, calendar} -> [inspect_value(value), calendar]
    end
  end

  @doc """
  The calendar in a Tempo value that ISO 8601 cannot write: one with no IXDTF
  identifier that reads back as it — a fiscal or composite calendar built at
  run time, or a consumer's own — whose dates the Gregorian calendar numbers
  differently, so the unnamed form would read back as other days. `nil` when
  the value has none.
  """
  @spec unnamed_calendar(term()) :: module() | nil
  def unnamed_calendar(value) do
    value
    |> unnamed_values()
    |> Enum.find_value(fn tempo -> if not reads_as_gregorian?(tempo), do: tempo.calendar end)
  end

  defp unnamed_values(value),
    do: value |> named_values() |> Enum.filter(&(calendar_name(&1) == :unnamed))

  # A value in a calendar without a name reads back as Gregorian, which names
  # the same days when the two number them alike from where its span starts —
  # a calendar that differs only in its week, say. A value without a year
  # names no days in any calendar, and a week-based calendar's weeks are not
  # Gregorian months.
  defp reads_as_gregorian?(%Tempo{calendar: calendar} = tempo) do
    cond do
      not Tempo.anchored?(tempo) -> true
      week_based?(calendar) -> false
      true -> same_start_in_gregorian?(tempo)
    end
  end

  defp same_start_in_gregorian?(tempo) do
    with %Tempo{time: time} = start <- Interval.from(tempo),
         true <- gregorian_date?(time) do
      Compare.to_wall_seconds(start) ==
        Compare.to_wall_seconds(%{start | calendar: Calendrical.Gregorian})
    else
      _other -> false
    end
  end

  defp gregorian_date?(time) do
    case {Keyword.get(time, :year), Keyword.get(time, :month, 1), Keyword.get(time, :day, 1)} do
      {year, month, day} when is_integer(year) and is_integer(month) and is_integer(day) ->
        Gregorian.valid_date?(year, month, day)

      _not_a_date ->
        false
    end
  end

  # Every value's calendar is written as the IXDTF identifier that reads back
  # as it, so a value in another calendar round-trips however it was made:
  # parsed with `[u-ca=…]`, converted with `Tempo.to_calendar/2`, or built
  # from an Elixir date. The top-level value, an interval's endpoints and a
  # set's members, the ends of its ranges and the members it excludes carry
  # it; a selection's own values and a recurrence's rule take theirs from the
  # value around them.
  defp with_calendar_names(value, implied),
    do: map_named(value, &with_calendar_name(&1, implied))

  defp map_named(%Tempo{} = tempo, fun), do: fun.(tempo)

  defp map_named(%Tempo.Interval{from: from, to: to} = interval, fun),
    do: %{interval | from: map_named(from, fun), to: map_named(to, fun)}

  defp map_named(%Tempo.Set{set: members, except: except} = set, fun) do
    %{
      set
      | set: Enum.map(members, &map_named(&1, fun)),
        except: Enum.map(except, &map_named(&1, fun))
    }
  end

  defp map_named(%Tempo.Range{first: first, last: last} = range, fun),
    do: %{range | first: map_named(first, fun), last: map_named(last, fun)}

  defp map_named(value, _fun), do: value

  defp named_values(%Tempo{} = tempo), do: [tempo]

  defp named_values(%Tempo.Interval{from: from, to: to}),
    do: named_values(from) ++ named_values(to)

  defp named_values(%Tempo.Set{set: members, except: except}),
    do: Enum.flat_map(members ++ except, &named_values/1)

  defp named_values(%Tempo.Range{first: first, last: last}),
    do: named_values(first) ++ named_values(last)

  defp named_values(_value), do: []

  # A suffix inside a set's braces does not parse, so the calendar a set's
  # members share is written once, after the set, where it reads back as the
  # calendar of each. A recurrence's rule takes its calendar from the suffix
  # after the whole recurrence, which a start in the same calendar shares; its
  # domain counts Gregorian years whatever the rule's calendar, and is written
  # without one. Parts in different calendars keep their own names.
  defp hoist_calendar_name(%Tempo.Set{} = set, _implied),
    do: hoist_shared_name(set, written_names(set))

  defp hoist_calendar_name(%Tempo.Interval{from: nil} = interval, _implied), do: {interval, []}

  defp hoist_calendar_name(
         %Tempo.Interval{from: %Tempo.Set{} = domain, repeat_rule: rule} = interval,
         implied
       ) do
    if Enum.all?(written_names(domain), &is_nil/1),
      do: {interval, rule_trailer(rule, implied)},
      else: {interval, []}
  end

  defp hoist_calendar_name(%Tempo.Interval{repeat_rule: %Tempo{} = rule} = interval, implied),
    do: hoist_shared_name(interval, written_names(interval) ++ rule_names(rule, implied))

  defp hoist_calendar_name(value, _implied), do: {value, []}

  defp rule_trailer(rule, implied) do
    case rule_names(rule, implied) do
      [name] when name not in [nil, :unnamed] -> calendar_trailer(%{calendar: name})
      _no_rule_or_no_name -> []
    end
  end

  defp hoist_shared_name(value, names) do
    case Enum.uniq(names) do
      [name] when name not in [nil, :unnamed] ->
        {map_named(value, &put_calendar_name(&1, nil)), calendar_trailer(%{calendar: name})}

      _none_or_several ->
        {value, []}
    end
  end

  defp written_names(value),
    do: value |> named_values() |> Enum.map(&written_name/1)

  defp written_name(%Tempo{extended: %{calendar: name}}), do: name
  defp written_name(%Tempo{}), do: nil

  defp rule_names(%Tempo{} = rule, implied), do: [calendar_name(%{rule | extended: nil}, implied)]
  defp rule_names(_no_rule, _implied), do: []

  defp with_calendar_name(%Tempo{} = tempo, implied) do
    case calendar_name(tempo, implied) do
      :unnamed -> put_calendar_name(tempo, nil)
      name -> put_calendar_name(tempo, name)
    end
  end

  # The identifier a value's calendar is written as: the one it was parsed
  # with when that names the same calendar, none for the Gregorian calendar
  # or the one the rendering implies, or else the name in Calendrical's
  # registry or the CLDR calendar type — whichever reads back as this
  # calendar, since several calendars share a CLDR type.
  defp calendar_name(%Tempo{calendar: calendar, extended: extended}, implied \\ Gregorian) do
    calendar = calendar || Gregorian
    parsed = extended && Map.get(extended, :calendar)

    cond do
      is_atom(parsed) and not is_nil(parsed) and names?(parsed, calendar) -> parsed
      calendar in [Gregorian, implied] -> nil
      true -> faithful_name(calendar)
    end
  end

  defp week_based?(calendar) do
    Code.ensure_loaded?(calendar) and function_exported?(calendar, :calendar_base, 0) and
      calendar.calendar_base() == :week
  end

  defp faithful_name(calendar) do
    [additional_calendar_module_name(calendar), cldr_calendar_type(calendar)]
    |> Enum.find_value(:unnamed, fn
      {:ok, name} -> if names?(name, calendar), do: name
      :error -> nil
    end)
  end

  defp names?(name, calendar),
    do: Calendrical.calendar_from_cldr_calendar_type(name) == {:ok, calendar}

  defp cldr_calendar_type(calendar) do
    if Code.ensure_loaded?(calendar) and function_exported?(calendar, :cldr_calendar_type, 0),
      do: {:ok, calendar.cldr_calendar_type()},
      else: :error
  end

  defp put_calendar_name(%Tempo{extended: nil} = tempo, nil), do: tempo

  defp put_calendar_name(%Tempo{extended: nil} = tempo, name) do
    %{
      tempo
      | extended: %{
          zone_id: nil,
          zone_offset: nil,
          calendar: name,
          zone_critical: false,
          tags: %{}
        }
    }
  end

  defp put_calendar_name(%Tempo{extended: extended} = tempo, name),
    do: %{tempo | extended: Map.put(extended, :calendar, name)}

  @doc """
  The construct in a Tempo value that has no ISO 8601 form, found before
  the value is encoded: an ordinal BYDAY across distinct weekdays
  (`:byday`), a cron nearest-weekday (`:nearest_weekday`) or a cron
  day-of-month OR day-of-week union (`:or_day`), anywhere in its
  selections, or a recurrence's end (RFC 5545 `UNTIL`, `:until`). `nil`
  when the value has none.
  """
  @spec unencodable(term()) :: :byday | :nearest_weekday | :or_day | :until | nil
  def unencodable(%Tempo{time: time}), do: unencodable_in(time)

  # An end beside a cadence is RFC 5545's `UNTIL`. ISO 8601's own
  # duration/end form leaves the start undefined rather than absent.
  def unencodable(%Tempo.Interval{from: from, to: %Tempo{}, duration: %Tempo.Duration{}})
      when is_nil(from) or is_struct(from, Tempo),
      do: :until

  def unencodable(%Tempo.Interval{} = interval),
    do: Enum.find_value([interval.from, interval.to, interval.repeat_rule], &unencodable/1)

  def unencodable(%Tempo.Set{set: members}), do: Enum.find_value(members, &unencodable/1)
  def unencodable(_value), do: nil

  defp unencodable_in({construct, _value})
       when construct in [:byday, :nearest_weekday, :or_day],
       do: construct

  defp unencodable_in({_key, value}), do: unencodable_in(value)
  defp unencodable_in(list) when is_list(list), do: Enum.find_value(list, &unencodable_in/1)
  defp unencodable_in(%Tempo.Interval{} = interval), do: unencodable(interval)
  defp unencodable_in(%Tempo{} = tempo), do: unencodable(tempo)
  defp unencodable_in(_value), do: nil

  # Inspect wraps the encoding `Tempo.to_iso8601/1` writes in sigil
  # syntax. Keeping encoding in one place — `to_iodata/1` — means the
  # Inspect output is guaranteed to round-trip through
  # `Tempo.from_iso8601/1` for the Gregorian and ISO-week cases,
  # and through the equivalent `Tempo.from_iso8601!/2` call for
  # non-default calendars, which also covers a calendar ISO 8601
  # cannot name and `Tempo.to_iso8601/1` refuses.

  # Metadata is not part of the ISO 8601 form, so — as for an interval — it
  # shows as a decoration outside the sigil body, which still re-parses.
  def inspect(%Tempo{metadata: metadata} = tempo) when map_size(metadata) > 0 do
    "#Tempo<" <>
      inspect(%{tempo | metadata: %{}}) <> " " <> interval_metadata_tag(metadata) <> ">"
  end

  def inspect(%Tempo{calendar: Calendrical.Gregorian} = tempo) do
    # `to_iso8601/1` (via `inspect_value/1`) already appends the
    # IXDTF extended trailer; don't add it again here.
    encoded(tempo, "Tempo", &(@sigil_o <> &1 <> "\""))
  end

  def inspect(%Tempo{calendar: Calendrical.ISOWeek} = tempo) do
    encoded(tempo, "Tempo", &(@sigil_o <> &1 <> "\"W"), Calendrical.ISOWeek)
  end

  def inspect(%Tempo{calendar: calendar} = tempo) do
    # `to_iso8601/1` (via `inspect_value/1`) already appends the
    # IXDTF extended trailer for any zone / calendar / tags present
    # on the Tempo, so we don't add it again here.
    encoded(tempo, "Tempo", &(@from_iso8601 <> &1 <> "\", " <> Kernel.inspect(calendar) <> ")"))
  end

  def inspect(%Tempo.Interval{} = interval) do
    rendering = calendar_rendering(interval)

    encoded(interval, "Tempo.Interval", fn iso8601 ->
      body = rendering.(iso8601)

      case interval_tags(interval) do
        "" -> body
        tags -> "#Tempo.Interval<" <> body <> " " <> tags <> ">"
      end
    end)
  end

  def inspect(%Tempo.Duration{} = duration) do
    encoded(duration, "Tempo.Duration", &(@sigil_o <> &1 <> "\""))
  end

  def inspect(%Tempo.Set{} = set) do
    encoded(set, "Tempo.Set", calendar_rendering(set))
  end

  # A value with no ISO 8601 form (a cron nearest-weekday recurrence) cannot be
  # rendered as a sigil that parses back, so it shows as a labelled struct view.
  # A calendar ISO 8601 cannot name is no obstacle here: the rendering names
  # its module.
  defp encoded(value, tag, render, implied \\ Gregorian) do
    case unencodable(value) do
      nil -> value |> to_iodata(implied) |> IO.iodata_to_binary() |> render.()
      _construct -> "#" <> tag <> "<not ISO 8601 expressible>"
    end
  end

  # An interval or a set in a calendar ISO 8601 cannot name reads back only
  # with that calendar given, as a value in any calendar but the defaults is
  # shown.
  defp calendar_rendering(value) do
    case unnamed_values(value) do
      [] ->
        &(@sigil_o <> &1 <> "\"")

      [%Tempo{calendar: calendar} | _rest] ->
        &(@from_iso8601 <> &1 <> "\", " <> Kernel.inspect(calendar) <> ")")
    end
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
  # render it back in the bracketed `[±HH:MM]` form so it round-trips. It is a
  # time zone annotation, and RFC 9557 gives a value one, so beside a zone
  # name it is not written: the value's offset is its shift.
  defp zone_offset_trailer(%{zone_id: zone_id}) when is_binary(zone_id) and zone_id != "",
    do: []

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

  # `U.encode/2` raises on an atom that is not a CLDR calendar; guard it so
  # inspect/`to_iso8601` never crash on an unexpected value. A non-CLDR calendar
  # Calendrical resolves (e.g. `:julian`) is not a CLDR identifier, so Localize
  # will not encode it — its IXDTF value is the atom's own spelling.
  defp encode_calendar(cal) do
    {"ca", value} = U.encode(:ca, cal)
    {:ok, value}
  rescue
    _error -> additional_calendar_identifier(cal)
  end

  defp additional_calendar_identifier(cal) do
    if Map.has_key?(Calendrical.additional_calendars(), cal) do
      {:ok, ixdtf_identifier(cal)}
    else
      :error
    end
  end

  # The `[u-ca=…]` suffix for a recurrence whose selection resolves in a
  # non-default calendar, carried on its `repeat_rule`. The calendar is a
  # module here (not the parsed identifier atom), so it is mapped back to its
  # IXDTF identifier: a non-CLDR calendar (`Calendrical.Julian`) through
  # Calendrical's additional-calendar registry, a CLDR one through its calendar
  # type. Gregorian and the ISO week calendar are the defaults and add nothing.
  defp repeat_rule_calendar_trailer(%Tempo{calendar: Calendrical.Gregorian}), do: []
  defp repeat_rule_calendar_trailer(%Tempo{calendar: Calendrical.ISOWeek}), do: []

  defp repeat_rule_calendar_trailer(%Tempo{calendar: calendar}) when is_atom(calendar) do
    case calendar_module_identifier(calendar) do
      {:ok, value} -> ["[u-ca=", value, "]"]
      :error -> []
    end
  end

  defp repeat_rule_calendar_trailer(_), do: []

  defp calendar_module_identifier(calendar) do
    case additional_calendar_module_name(calendar) do
      {:ok, name} -> {:ok, ixdtf_identifier(name)}
      :error -> cldr_calendar_identifier(calendar)
    end
  end

  # A Calendrical additional-calendar identifier as the IXDTF suffix writes
  # it, with hyphens for its underscores (`julian_march25` is
  # `julian-march25`), as CLDR's `islamic_civil` is `islamic-civil`.
  defp ixdtf_identifier(identifier) do
    identifier |> Atom.to_string() |> String.replace("_", "-")
  end

  defp additional_calendar_module_name(calendar) do
    Enum.find_value(Calendrical.additional_calendars(), :error, fn {name, module} ->
      if module == calendar, do: {:ok, name}
    end)
  end

  defp cldr_calendar_identifier(calendar) do
    if function_exported?(calendar, :cldr_calendar_type, 0) do
      encode_calendar(calendar.cldr_calendar_type())
    else
      :error
    end
  end

  # Render a recurrence's written start with its IXDTF `[u-ca=…]` calendar
  # lifted off into a separate trailing suffix, so a whole-value calendar reads
  # as `R/5787Y3M25D/P1Y[u-ca=hebrew]` — one trailer on the recurrence — rather
  # than mid-string on the start date. Any zone/tags stay on the endpoint,
  # where they belong; only the calendar, which qualifies the whole value,
  # hoists. Returns `{endpoint_iodata, calendar_suffix_iodata}`.
  defp hoist_calendar_suffix(%Tempo{extended: %{calendar: calendar} = extended} = tempo)
       when is_atom(calendar) and not is_nil(calendar) do
    {inspect_value(%{tempo | extended: %{extended | calendar: nil}}), calendar_trailer(extended)}
  end

  defp hoist_calendar_suffix(endpoint), do: {inspect_value(endpoint), []}

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
  # taken from the walk, never `members/1`, so a lazy set inspects safely.
  defp take_within_limit(set, :infinity) do
    if IntervalSet.bounded?(set) do
      {IntervalSet.members(set), false}
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

  # A group renders as the `nGsizeU` it was declared as. Its values count
  # from the unit's first (month 1, hour 0), so the nth group of `size`
  # starts `(n - 1) * size` past it. A time unit's size is written as a
  # duration writes it, after `T`: `3GT8HU` is the third eight hours.
  defp inspect_value({unit, {:group, %Range{first: first, last: last}}}) do
    group_size = last - first + 1
    nth = div(first - Math.unit_minimum(unit), group_size) + 1

    [_, unit_key] = inspect_value({unit, 1})
    [inspect_value(nth), ?G, group_time_designator(unit), inspect_value(group_size), unit_key, ?U]
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

  # An open, filtered domain (`..e`) has no members and no exclusions — only a
  # year filter — so it renders as `..` plus the marker, not empty braces `{}e`
  # (which would not re-parse).
  defp inspect_value(%Tempo.Set{set: [], except: [], filter: filter}) when not is_nil(filter) do
    ["..", filter_marker(filter)]
  end

  defp inspect_value(%Tempo.Set{set: set, type: type, except: except} = value) do
    plain = Enum.map(set, &inspect_value/1)
    excluded = Enum.map(except, fn member -> ["^", inspect_value(member)] end)
    elements = Enum.intersperse(plain ++ excluded, ",")

    [open(type), elements, close(type), filter_marker(Map.get(value, :filter))]
  end

  # Intervals with a nil `from` are produced by callers that build
  # the struct directly without a start (e.g. the RRule parser
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

  # An end beside a cadence is RFC 5545's `UNTIL`, which ISO 8601 has no
  # form for: it bounds a recurrence only by its count, and its start/end
  # form names the first occurrence's end. Raise a clear error, as for the
  # other constructs ISO 8601 cannot express.
  defp inspect_value(%Tempo.Interval{from: from, to: %Tempo{}, duration: %Tempo.Duration{}})
       when is_nil(from) or is_struct(from, Tempo) do
    raise Iso8601EncodeError.exception(construct: :until)
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: nil,
         to: nil,
         duration: %Tempo.Duration{} = duration,
         repeat_rule: %Tempo{time: rule_time} = repeat_rule
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
      inspect_value(rule_time),
      repeat_rule_calendar_trailer(repeat_rule)
    ]
  end

  # ISO 8601's duration/end form with a repeat rule (`R/P1D/2026Y12M31D/F…`).
  defp inspect_value(%Tempo.Interval{
         recurrence: recurrence,
         from: :undefined,
         to: %Tempo{} = to,
         duration: %Tempo.Duration{} = duration,
         repeat_rule: %Tempo{} = repeat_rule
       }) do
    [
      ?R,
      recurrence(recurrence),
      ?/,
      inspect_value(duration),
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
    {from_body, calendar_suffix} = hoist_calendar_suffix(from)
    [?R, recurrence(recurrence), ?/, from_body, ?/, inspect_value(duration), calendar_suffix]
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

  # A traditional month renders with the lowercase `m` extension
  # designator — `<n>m`, and `<n>+m` for the intercalary month. It survives only
  # in a selection frame (a recurrence has no year to resolve against); a
  # concrete traditional month is lowered to its ordinal `M` during validation.
  defp inspect_value({:traditional_month, {month, :leap}}), do: [inspect_list(month), ?+, ?m]
  defp inspect_value({:traditional_month, month}), do: [inspect_list(month), ?m]

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
  defp inspect_value({:calendar_week, week}), do: [inspect_list(week), ?w]
  defp inspect_value({:instance, instance}), do: [inspect_list(instance), ?I]

  # A computed-event selection renders as `(name)e` — the project-specific
  # designator for an algorithmically resolved recurrence (Easter, an
  # astronomical event). The name is a plain lowercase identifier, so it
  # round-trips through the grammar's `selection_event/0`.
  defp inspect_value({:event, name}) when is_binary(name), do: [?(, name, ?), ?e]

  # A `:byday` selection survives only for the one shape ISO 8601-2 cannot
  # express: ordinals spread across *distinct* weekdays (`BYDAY=2MO,2WE`,
  # `BYDAY=1MO,-1FR`, the mixed `BYDAY=2MO,WE`). A single-weekday ordinal
  # lowers to `day_of_week` + `instance` (the §12.9 position form) before it
  # ever reaches here, so the only cases left interleave weekday and position
  # (`1K2I3K2I`), which the resolution-order rule rejects on re-parse. There
  # is no round-trippable ISO form, so — like `:nearest_weekday` below — raise
  # and let the value round-trip through its RRULE string via
  # `Tempo.RRule.to_string/1`.
  defp inspect_value({:byday, _entries}) do
    raise Iso8601EncodeError.exception(construct: :byday)
  end

  # WKST has no ISO 8601 designator — it is an RFC 5545 extension. Tempo renders
  # it with the project-specific lowercase selection designator `q` (week start)
  # so a recurrence carrying it round-trips through `inspect/1`/`to_iso8601/1`
  # rather than crashing; the canonical external form remains the RRULE string.
  # (Set position is the ISO 8601-2 §12.9 `I` — see the `:instance` clause above.)
  defp inspect_value({:wkst, weekday}), do: [inspect_list(weekday), ?q]

  # A nearest-weekday selection (cron `W`, parsed to `:nearest_weekday`) has
  # no ISO 8601 designator and — unlike the `q` week-start above — was
  # deliberately not given a project-specific one (the day-level operation is
  # `Tempo.nearest_workday/2`). Raise a clear error instead of a
  # `FunctionClauseError`; the Inspect protocol catches it and falls back.
  defp inspect_value({:nearest_weekday, _targets}) do
    raise Iso8601EncodeError.exception(construct: :nearest_weekday)
  end

  # A cron day-of-month OR day-of-week union fires when either field holds,
  # where every part of an ISO 8601 selection holds at once.
  defp inspect_value({:or_day, _days}) do
    raise Iso8601EncodeError.exception(construct: :or_day)
  end

  defp inspect_value({:interval, interval}), do: inspect_value(interval)
  defp inspect_value({:duration, duration}), do: inspect_value(duration)
  defp inspect_value(:undefined), do: ".."

  defp group_time_designator(unit) when unit in [:hour, :minute, :second], do: ?T
  defp group_time_designator(_unit), do: []

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

  # A negative offset under an hour carries its sign on the minute.
  defp inspect_shift(hour: 0, minute: minute) when minute < 0,
    do: [?Z, ?-, inspect_value(0), ?H, inspect_value(-minute), ?M]

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

  # The `e`/`o`/`l`/`c` year filter a recurrence domain may carry after its
  # closing brace (`{2000Y..2020Y}e`).
  defp filter_marker(:even), do: ?e
  defp filter_marker(:odd), do: ?o
  defp filter_marker(:leap), do: ?l
  defp filter_marker(:common), do: ?c
  defp filter_marker(_none), do: []

  defp recurrence(:infinity), do: <<>>
  defp recurrence(recurrence), do: Integer.to_string(recurrence)

  # IXDTF binds an interval's extended suffix to its *end*, and
  # `Tempo.Interval.propagate_endpoint_frame/2` flows a zone between the
  # endpoints (either way) and a calendar backward onto a floating `from`.
  # So when both endpoints carry the same *zone*, writing it twice is
  # redundant — the single-suffix form re-parses to the same value.
  #
  # Both the zone and a `u-ca` calendar reach `from` from the end, so
  # either may be written once. Arbitrary IXDTF tags do not propagate — they are
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
  #
  # A fraction of a second belongs to its second, so the two are compared
  # as one component: the shared prefix never ends between them, and an
  # end that differs only in the fraction is written from its second
  # (`…T10H0M0.123S/T0.456S`).
  defp abbreviate(%Tempo{time: to_units} = to, %Tempo{time: from_units} = from)
       when is_list(to_units) and is_list(from_units) do
    to_units = fold_microsecond(to_units)

    if implied_by?(to, from) do
      case shared_prefix(to_units, fold_microsecond(from_units)) do
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
