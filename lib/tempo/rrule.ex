defmodule Tempo.RRule do
  @moduledoc """
  Reads and writes RFC 5545 `RRULE` text: `parse/2` turns a rule into a
  Tempo recurrence, the `%Tempo{}` an ISO 8601-2 repeat rule reads to, and
  `to_string/1` writes one back.

  A rule's `FREQ` and `INTERVAL` are the recurrence's cadence; its `BY*`
  parts are the parts of the selection applied in each repeating interval
  (`BYDAY=2MO` in a monthly rule is `L1K2IN`), `BYSETPOS` its positions,
  `COUNT` and `UNTIL` its bound. What a rule leaves to `DTSTART` (the day of
  the month of a monthly rule, the month and day of a yearly one, the
  weekday of a weekly one, the time of day of any) is taken from the start,
  as RFC 5545 §3.3.10 has it. The same lowering serves `Tempo.Cron` and
  `Tempo.JSCalendar`, which build the rule from their own vocabularies.

  Not read: RFC 7529's `RSCALE` and `SKIP`, and a `WKST` other than Monday,
  each an error naming what is unsupported.

  """

  import Kernel, except: [to_string: 1]

  alias Tempo.{ConversionError, Duration, Options, Unit, Validate}

  @weekdays %{"MO" => 1, "TU" => 2, "WE" => 3, "TH" => 4, "FR" => 5, "SA" => 6, "SU" => 7}
  @weekday_codes Map.new(@weekdays, fn {code, n} -> {n, code} end)
  @frequencies %{
    "SECONDLY" => :second,
    "MINUTELY" => :minute,
    "HOURLY" => :hour,
    "DAILY" => :day,
    "WEEKLY" => :week,
    "MONTHLY" => :month,
    "YEARLY" => :year
  }
  @frequency_names Map.new(@frequencies, fn {name, unit} -> {unit, name} end)

  # What a calendar counts in its own way: a cadence of these, or a part of
  # those, is of the recurrence's calendar and no other.
  @calendar_cadences [:year, :month]
  @calendar_parts [:year, :month, :traditional_month, :week, :day, :day_of_year]
  @by_parts %{
    "BYMONTH" => :bymonth,
    "BYMONTHDAY" => :bymonthday,
    "BYYEARDAY" => :byyearday,
    "BYWEEKNO" => :byweekno,
    "BYHOUR" => :byhour,
    "BYMINUTE" => :byminute,
    "BYSECOND" => :bysecond,
    "BYSETPOS" => :bysetpos
  }
  @part_units [
    bymonth: :month,
    byweekno: :week,
    byyearday: :day_of_year,
    bymonthday: :day,
    byhour: :hour,
    byminute: :minute,
    bysecond: :second
  ]

  @below [day: {:byhour, :hour}, hour: {:byminute, :minute}, minute: {:bysecond, :second}]

  @typedoc "A rule as the vocabularies share it: the keys RFC 5545 names, lower-cased."
  @type rule :: %{
          optional(:freq) => Unit.t(),
          optional(:interval) => pos_integer(),
          optional(:count) => pos_integer(),
          optional(:until) => Tempo.t(),
          optional(:bymonth) => [integer()],
          optional(:bymonthday) => [integer()],
          optional(:byyearday) => [integer()],
          optional(:byweekno) => [integer()],
          optional(:byday) => [{integer() | nil, 1..7}],
          optional(:byhour) => [integer()],
          optional(:byminute) => [integer()],
          optional(:bysecond) => [integer()],
          optional(:bysetpos) => [integer()],
          optional(:wkst) => 1..7
        }

  @doc """
  Reads an `RRULE` into a recurrence.

  ### Arguments

  * `text` is the rule, with or without a leading `RRULE:`.

  * `options` is a keyword list of options.

  ### Options

  * `:from` is the recurrence's start (`DTSTART`), a `t:Tempo.t/0`. Without
    one the recurrence has an open start, which writes back to text but
    gives no occurrences.

  * `:duration` is each occurrence's length, a `t:Tempo.Duration.t/0`
    (iCalendar's `DURATION`, or `DTEND` less `DTSTART`); without one an
    occurrence is one unit of the resolution the rule selects at.

  * `:metadata` is a map carried on the recurrence and every occurrence.

  ### Returns

  * `{:ok, recurrence}`, a `t:Tempo.t/0` of the `:every` form.

  * `{:error, %ArgumentError{}}` for text that is not a rule: no `FREQ`, an
    unknown frequency or part, a malformed value, both `COUNT` and `UNTIL`,
    an `RSCALE` or `SKIP`, or a `WKST` other than `MO`.

  ### Examples

      iex> {:ok, rule} = Tempo.RRule.parse("FREQ=MONTHLY;BYDAY=2MO", from: ~o"2025-01-01")
      iex> Tempo.to_iso8601(rule)
      {:ok, "R/2025Y1M1D/P1M/FL1K2IN"}

      iex> {:ok, rule} = Tempo.RRule.parse("FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25;COUNT=3", from: ~o"2026-01-01")
      iex> rule |> Tempo.to_interval!() |> Tempo.IntervalSet.map(&Tempo.year/1)
      [2026, 2027, 2028]

      iex> {:ok, rule} = Tempo.RRule.parse("FREQ=WEEKLY;INTERVAL=2;UNTIL=20221231", from: ~o"2022-12-05")
      iex> Tempo.to_iso8601(rule)
      {:ok, "R/2022Y12M5D/P2W/2022Y12M31D/FL1KN"}

      iex> {:error, %ArgumentError{}} = Tempo.RRule.parse("BYMONTH=6")

  """
  @spec parse(String.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def parse(text, options \\ [])

  def parse("RRULE:" <> rest, options), do: parse(rest, options)

  def parse(text, options) when is_binary(text) do
    with :ok <- Options.check(options, [:from, :duration, :metadata], "Tempo.RRule.parse/2"),
         {:ok, rule} <- rule_of(text),
         do: from_rule(rule, options)
  end

  def parse(other, _options), do: {:error, argument("an RRULE is text, not #{inspect(other)}")}

  @doc """
  `parse/2`, returning the recurrence or raising.

  ### Examples

      iex> Tempo.RRule.parse!("FREQ=DAILY;COUNT=10", from: ~o"2026-06-01") |> Enum.count()
      10

  """
  @spec parse!(String.t(), keyword()) :: Tempo.t()
  def parse!(text, options \\ []) do
    case parse(text, options) do
      {:ok, recurrence} -> recurrence
      {:error, exception} -> raise exception
    end
  end

  # ── Text to rule ──────────────────────────────────────────────────────

  defp rule_of(text) do
    text
    |> String.trim()
    |> String.split(";", trim: true)
    |> Enum.reduce_while({:ok, %{}}, fn pair, {:ok, rule} ->
      case part(pair) do
        {:ok, key, value} -> {:cont, {:ok, Map.put(rule, key, value)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> checked()
  end

  defp part(pair) do
    case String.split(pair, "=", parts: 2) do
      [key, value] -> part(String.upcase(key), value)
      _ -> {:error, argument("#{inspect(pair)} is not a KEY=VALUE rule part")}
    end
  end

  defp part("FREQ", value) do
    case Map.fetch(@frequencies, String.upcase(value)) do
      {:ok, unit} -> {:ok, :freq, unit}
      :error -> {:error, argument("#{inspect(value)} is not a FREQ")}
    end
  end

  defp part("INTERVAL", value), do: positive(:interval, value)
  defp part("COUNT", value), do: positive(:count, value)

  defp part("UNTIL", value) do
    case Tempo.from_iso8601(value) do
      {:ok, %Tempo{form: {:value, _}} = until} -> {:ok, :until, until}
      _ -> {:error, argument("#{inspect(value)} is not an UNTIL date or time")}
    end
  end

  defp part("BYDAY", value) do
    entries = value |> String.split(",") |> Enum.map(&byday_entry/1)

    if Enum.all?(entries, &match?({_, day} when is_integer(day), &1)),
      do: {:ok, :byday, entries},
      else: {:error, argument("#{inspect(value)} is not a BYDAY list")}
  end

  defp part("WKST", value) do
    case Map.fetch(@weekdays, String.upcase(value)) do
      {:ok, 1} -> {:ok, :wkst, 1}
      {:ok, _} -> {:error, argument("a WKST other than MO is not supported")}
      :error -> {:error, argument("#{inspect(value)} is not a WKST")}
    end
  end

  defp part(key, _value) when key in ["RSCALE", "SKIP"],
    do: {:error, argument("#{key} (RFC 7529) is not supported")}

  defp part(key, value) do
    case Map.fetch(@by_parts, key) do
      {:ok, name} -> integers(name, value)
      :error -> {:error, argument("#{inspect(key)} is not an RRULE part")}
    end
  end

  defp positive(name, value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 ->
        {:ok, name, n}

      _ ->
        {:error,
         argument(
           "#{name |> Atom.to_string() |> String.upcase()} wants a positive integer, not #{inspect(value)}"
         )}
    end
  end

  defp integers(name, value) do
    parsed = value |> String.split(",") |> Enum.map(&Integer.parse/1)

    if Enum.all?(parsed, &match?({_, ""}, &1)),
      do: {:ok, name, Enum.map(parsed, &elem(&1, 0))},
      else: {:error, argument("#{inspect(value)} is not a list of integers")}
  end

  defp byday_entry(entry) do
    entry = String.upcase(String.trim(entry))
    {ordinal, code} = String.split_at(entry, -2)

    case {Map.fetch(@weekdays, code), ordinal_of(ordinal)} do
      {{:ok, day}, {:ok, n}} -> {n, day}
      _ -> {nil, nil}
    end
  end

  defp ordinal_of(""), do: {:ok, nil}

  defp ordinal_of(text) do
    case Integer.parse(text) do
      {n, ""} when n != 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp checked({:ok, rule}) do
    cond do
      not Map.has_key?(rule, :freq) ->
        {:error, argument("an RRULE needs a FREQ")}

      Map.has_key?(rule, :count) and Map.has_key?(rule, :until) ->
        {:error, argument("COUNT and UNTIL exclude each other")}

      true ->
        {:ok, rule}
    end
  end

  defp checked(error), do: error

  # ── Rule to recurrence ────────────────────────────────────────────────

  @doc """
  A recurrence from a rule in the shared vocabulary (`t:rule/0`), as
  `Tempo.Cron` and `Tempo.JSCalendar` build one; options as for `parse/2`.
  """
  @spec from_rule(rule(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def from_rule(%{freq: freq} = rule, options) do
    from = Keyword.get(options, :from)
    rule = with_start(rule, from)
    cadence = %Duration{units: [{freq, Map.get(rule, :interval, 1)}]}
    {cadence, parts} = lowered(rule, cadence, Keyword.get(options, :duration))
    bound = bound(rule)

    with {:ok, parts} <- parts,
         {:ok, first} <- first_span(from, cadence) do
      recurrence = %Tempo{
        form: {:every, first, bound, parts},
        calendar: first.calendar,
        zone: first.zone,
        metadata: Keyword.get(options, :metadata, %{})
      }

      Validate.run(recurrence)
    end
  end

  def from_rule(_rule, _options), do: {:error, argument("a rule needs a frequency")}

  defp first_span(nil, cadence),
    do: {:ok, %Tempo{form: {:span, :open, cadence}, calendar: Calendar.ISO}}

  defp first_span(%Tempo{form: {:value, _}} = from, cadence),
    do: {:ok, %Tempo{form: {:span, from, cadence}, calendar: from.calendar, zone: from.zone}}

  defp first_span(other, _cadence),
    do: {:error, argument("the :from of a rule is a Tempo value, not #{inspect(other)}")}

  defp bound(%{count: count}), do: count
  defp bound(%{until: until}), do: until
  defp bound(_rule), do: :infinity

  # What RFC 5545 §3.3.10 takes from DTSTART where the rule says nothing: the
  # weekday of a weekly rule, the day of a monthly one, the month and day of
  # a yearly one. A day of the month a month lacks is then passed over.
  defp with_start(rule, %Tempo{form: {:value, units}}) do
    case Enum.map([:year, :month, :day], &Keyword.get(units, &1)) do
      [y, m, d] when is_integer(y) and is_integer(m) and is_integer(d) ->
        with_date_of_start(rule.freq, rule, m, d, units)

      _ ->
        with_clock_of_start(rule, units)
    end
  end

  defp with_start(rule, _from), do: rule

  defp with_date_of_start(:week, rule, _month, _day, units) do
    if Map.has_key?(rule, :byday),
      do: rule,
      else: Map.put(rule, :byday, [{nil, weekday_of(units)}])
  end

  defp with_date_of_start(:month, rule, _month, day, _units) do
    if names_a_day?(rule), do: rule, else: Map.put(rule, :bymonthday, [day])
  end

  defp with_date_of_start(:year, rule, month, day, _units) do
    if names_a_day?(rule) or Map.has_key?(rule, :byweekno),
      do: rule,
      else: rule |> Map.put_new(:bymonth, [month]) |> Map.put(:bymonthday, [day])
  end

  defp with_date_of_start(_finer, rule, _month, _day, units), do: with_clock_of_start(rule, units)

  # A rule finer than a week fires at the start's own reading of the unit
  # below its frequency: a daily rule at the start's hour, an hourly one at
  # its minute. The units below that are inherited when the rule is applied.
  defp with_clock_of_start(%{freq: freq} = rule, units) do
    case Keyword.fetch(@below, freq) do
      {:ok, {key, unit}} ->
        case {Map.has_key?(rule, key), Keyword.fetch(units, unit)} do
          {false, {:ok, value}} when is_integer(value) -> Map.put(rule, key, [value])
          _ -> rule
        end

      :error ->
        rule
    end
  end

  defp names_a_day?(rule),
    do: Enum.any?([:bymonthday, :byday, :byyearday], &Map.has_key?(rule, &1))

  defp weekday_of(units) do
    Tempo.day_of_week(%Tempo{form: {:value, units}, calendar: Calendar.ISO})
  end

  # The selection's parts, and the cadence: a yearly rule with a numbered
  # weekday in named months counts it in each month, so its cadence is the month.
  defp lowered(rule, cadence, duration) do
    numbered = numbered_weekday(rule)
    monthly_count? = rule.freq == :year and numbered != nil and Map.has_key?(rule, :bymonth)
    cadence = if monthly_count?, do: %Duration{units: [month: 1]}, else: cadence

    parts =
      []
      |> push_years(rule)
      |> push(rule, :bymonth)
      |> push(rule, :byweekno)
      |> push(rule, :bymonthday)
      |> push(rule, :byyearday)
      |> push_byday(rule, numbered)
      |> push(rule, :byhour)
      |> push(rule, :byminute)
      |> push(rule, :bysecond)
      |> push_instance(rule, numbered)
      |> Enum.reverse()
      |> windowed(duration)

    cond do
      Keyword.has_key?(parts, :unsupported) ->
        {cadence,
         {:error, argument("BYDAY with numbered weekdays of several days is not supported")}}

      parts == [] ->
        {cadence, {:ok, nil}}

      true ->
        {cadence, {:ok, parts}}
    end
  end

  defp push_years(acc, %{byyear: years}), do: [{:year, years} | acc]
  defp push_years(acc, _rule), do: acc

  defp push(acc, rule, key) do
    case Map.get(rule, key) do
      nil -> acc
      [] -> acc
      [one] -> [{Keyword.fetch!(@part_units, key), one} | acc]
      list -> [{Keyword.fetch!(@part_units, key), list} | acc]
    end
  end

  # A rule's numbered weekdays (`2MO`, `1MO,3MO`) as one weekday with positions,
  # where no BYSETPOS counts instead; nil for plain weekdays.
  defp numbered_weekday(%{byday: [{n, _} | _] = entries} = rule)
       when is_integer(n) and not is_map_key(rule, :bysetpos) do
    case entries |> Enum.map(&elem(&1, 1)) |> Enum.uniq() do
      [day] -> {day, one_or_list(Enum.map(entries, &elem(&1, 0)))}
      _several -> nil
    end
  end

  defp numbered_weekday(_rule), do: nil

  defp push_byday(acc, %{byday: entries}, nil) do
    if Enum.any?(entries, fn {n, _} -> is_integer(n) end) do
      [{:unsupported, :byday} | acc]
    else
      case Enum.map(entries, &elem(&1, 1)) do
        [one] -> [{:day_of_week, one} | acc]
        days -> [{:day_of_week, days} | acc]
      end
    end
  end

  defp push_byday(acc, _rule, {day, _n}), do: [{:day_of_week, day} | acc]
  defp push_byday(acc, _rule, nil), do: acc

  defp push_instance(acc, %{bysetpos: positions}, _numbered),
    do: [{:instance, one_or_list(positions)} | acc]

  defp push_instance(acc, _rule, {_day, n}), do: [{:instance, n} | acc]
  defp push_instance(acc, _rule, nil), do: acc

  # An occurrence's length is a window from each element the parts select,
  # ISO 8601-2 §12.10's `L…N/PT1H`.
  defp windowed(parts, nil), do: parts

  defp windowed(parts, %Duration{} = duration) do
    if Keyword.has_key?(parts, :unsupported),
      do: parts,
      else: [selection: parts, window: duration]
  end

  defp one_or_list([one]), do: one
  defp one_or_list(list), do: list

  # ── Recurrence to text ────────────────────────────────────────────────

  @doc """
  Writes a recurrence as an `RRULE`.

  ### Arguments

  * `recurrence` is a `t:Tempo.t/0` of the `:every` form whose cadence is
    one unit and whose rule names only what RFC 5545 can: months, weeks,
    days of the year or month, weekdays, hours, minutes, seconds and
    positions.

  ### Returns

  * `{:ok, text}`.

  * `{:error, %Tempo.ConversionError{reason: {:no_rrule, what}}}` for a
    cadence of several units, an event or a selection within a window, or
    an expression that is no recurrence. It is also the error for a
    recurrence RFC 5545 would read as another: one of a calendar other than
    the Gregorian that counts in months, years or their days (`{:calendar,
    module}`), and one with no rule that steps by months from the 29th, 30th
    or 31st, or by years from the 29th of February (`:month_end`).

  An occurrence's length (the `:duration` of `parse/2`) is no part of an
  `RRULE` and is not written: iCalendar carries it beside the rule, as
  `DURATION` or `DTEND`.

  ### Examples

      iex> Tempo.RRule.to_string(~o"R/2025Y1M1D/P1M/FL1K2IN")
      {:ok, "FREQ=MONTHLY;BYDAY=2MO"}

      iex> Tempo.RRule.to_string(~o"R3/2026-01-01/P1Y/FL12M25DN")
      {:ok, "FREQ=YEARLY;COUNT=3;BYMONTH=12;BYMONTHDAY=25"}

      iex> Tempo.RRule.to_string(~o"R/2026-06-01/P2W")
      {:ok, "FREQ=WEEKLY;INTERVAL=2"}

  """
  @spec to_string(Tempo.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(%Tempo{form: {:every, %Tempo{form: {:span, from, cadence}}, bound, parts}} = r) do
    with :ok <- no_domain(from, r),
         :ok <- gregorian(r, cadence, parts || []),
         :ok <- in_every_period(from, cadence, parts, r),
         {:ok, frequency} <- frequency_part(cadence, r),
         {:ok, by_parts} <- by_parts(parts || [], r) do
      {:ok,
       Enum.join([frequency | Enum.reject([bound_part(bound) | by_parts], &(&1 == ""))], ";")}
    end
  end

  def to_string(other), do: {:error, no_rrule(other, :not_a_recurrence)}

  @doc """
  `to_string/1`, returning the text or raising.

  ### Examples

      iex> Tempo.RRule.to_string!(~o"R10/2026-06-01/P1D")
      "FREQ=DAILY;COUNT=10"

  """
  @spec to_string!(Tempo.t()) :: String.t()
  def to_string!(recurrence) do
    case to_string(recurrence) do
      {:ok, text} -> text
      {:error, exception} -> raise exception
    end
  end

  # RFC 5545 counts months, years and their days in the Gregorian calendar,
  # so a recurrence of another calendar is an RRULE only where it reads there
  # as itself: stepping by weeks, days or the clock, selecting by weekday and
  # time of day. (RFC 7529's RSCALE, which names another calendar, is not written.)
  defp gregorian(%Tempo{calendar: calendar}, _cadence, _parts)
       when calendar in [Calendrical.Gregorian, Calendar.ISO],
       do: :ok

  defp gregorian(r, %Duration{units: units}, parts) do
    if Enum.any?(Keyword.keys(units), &(&1 in @calendar_cadences)) or
         Enum.any?(Keyword.keys(picked(parts)), &(&1 in @calendar_parts)),
       do: {:error, no_rrule(r, {:calendar, r.calendar})},
       else: :ok
  end

  # A domain says which periods a rule recurs in, and RFC 5545 has no part for it.
  defp no_domain(%Tempo{form: form}, r) when elem(form, 0) in [:all, :one, :when],
    do: {:error, no_rrule(r, :domain)}

  defp no_domain(_from, _r), do: :ok

  defp picked(selection: parts, window: %Duration{}), do: parts
  defp picked(parts), do: parts

  # A recurrence with no rule steps from its start by its cadence, and lands
  # on the last day of a month that lacks the start's day. RFC 5545 passes
  # such a month over, so the two are different recurrences and no one rule
  # says the first.
  defp in_every_period(%Tempo{form: {:value, units}}, %Duration{units: [{unit, _}]}, nil, r)
       when unit in [:month, :year] do
    case {unit, Keyword.get(units, :month), Keyword.get(units, :day)} do
      {:month, _month, day} when is_integer(day) and day > 28 -> {:error, no_rrule(r, :month_end)}
      {:year, 2, 29} -> {:error, no_rrule(r, :month_end)}
      _in_every_period -> :ok
    end
  end

  defp in_every_period(_from, _cadence, _parts, _r), do: :ok

  defp frequency_part(%Duration{units: [{unit, 1}]}, _r) when is_map_key(@frequency_names, unit),
    do: {:ok, "FREQ=#{@frequency_names[unit]}"}

  defp frequency_part(%Duration{units: [{unit, n}]}, _r)
       when is_map_key(@frequency_names, unit) and n > 1,
       do: {:ok, "FREQ=#{@frequency_names[unit]};INTERVAL=#{n}"}

  defp frequency_part(cadence, r), do: {:error, no_rrule(r, {:cadence, cadence})}

  defp bound_part(count) when is_integer(count), do: "COUNT=#{count}"
  defp bound_part(:infinity), do: ""
  defp bound_part(%Tempo{} = until), do: "UNTIL=#{until_text(until)}"

  defp until_text(%Tempo{form: {:value, units}}), do: Enum.map_join(units, &until_unit/1)

  defp until_unit({:year, y}), do: padded(y, 4)
  defp until_unit({unit, n}) when unit in [:month, :day, :minute, :second], do: padded(n, 2)
  defp until_unit({:hour, h}), do: "T" <> padded(h, 2)
  defp until_unit(_other), do: ""

  defp padded(n, width), do: String.pad_leading(Integer.to_string(n), width, "0")

  defp by_parts([selection: parts, window: %Duration{}], r), do: by_parts(parts, r)

  defp by_parts(parts, r) do
    frequency = frequency_of(r)
    {weekday, parts} = Keyword.pop(parts, :day_of_week)
    {instance, parts} = Keyword.pop(parts, :instance)

    with :ok <- expressible(parts, r),
         :ok <- allowed(parts, frequency, r),
         :ok <- positioned(weekday, instance, parts, frequency, r) do
      named = Enum.map(parts, fn {unit, held} -> "#{by_name(unit)}=#{listed(held)}" end)
      {:ok, named ++ byday_parts(weekday, instance)}
    end
  end

  defp frequency_of(%Tempo{
         form: {:every, %Tempo{form: {:span, _, %Duration{units: [{unit, _}]}}}, _, _}
       }),
       do: unit

  defp frequency_of(_recurrence), do: nil

  # RFC 5545 §3.3.10 gives each frequency the parts it may have: no day of
  # the month in a weekly rule, no day of the year in a daily, weekly or
  # monthly one, a week of the year in a yearly one alone.
  defp allowed(parts, frequency, r) do
    forbidden =
      Enum.find(Keyword.keys(parts), fn part ->
        {part, frequency} in [
          {:day, :week},
          {:day_of_year, :day},
          {:day_of_year, :week},
          {:day_of_year, :month}
        ] or (part == :week and frequency != :year)
      end)

    if forbidden, do: {:error, no_rrule(r, {:part_at, forbidden, frequency})}, else: :ok
  end

  # A numbered weekday is of a monthly rule, or a yearly one with no week of
  # the year; a position alone, with no part to count among, is of none.
  defp positioned(nil, instance, [], frequency, r) when instance != nil,
    do: {:error, no_rrule(r, {:part_at, :instance, frequency})}

  defp positioned(weekday, instance, parts, frequency, r)
       when is_integer(weekday) and instance != nil do
    if frequency == :month or (frequency == :year and not Keyword.has_key?(parts, :week)),
      do: :ok,
      else: {:error, no_rrule(r, {:part_at, :instance, frequency})}
  end

  defp positioned(_weekday, _instance, _parts, _frequency, _r), do: :ok

  defp expressible(parts, r) do
    units = Keyword.values(@part_units)

    case Enum.find(parts, fn {unit, _} -> unit not in units end) do
      nil -> :ok
      {unit, _} -> {:error, no_rrule(r, {:part, unit})}
    end
  end

  defp by_name(unit) do
    @part_units
    |> Enum.find(fn {_, u} -> u == unit end)
    |> elem(0)
    |> Atom.to_string()
    |> String.upcase()
  end

  defp listed(held) when is_list(held),
    do:
      held
      |> Enum.flat_map(fn
        %Range{} = r -> Enum.to_list(r)
        n -> [n]
      end)
      |> Enum.join(",")

  defp listed(held), do: Kernel.to_string(held)

  # One weekday with one position is a numbered weekday; otherwise the
  # weekdays are plain and the positions BYSETPOS.
  defp byday_parts(nil, nil), do: []
  defp byday_parts(nil, instance), do: ["BYSETPOS=#{listed(instance)}"]

  defp byday_parts(day, instance) when is_integer(day) and is_integer(instance),
    do: ["BYDAY=#{instance}#{@weekday_codes[day]}"]

  defp byday_parts(day, instances) when is_integer(day) and is_list(instances),
    do: ["BYDAY=" <> Enum.map_join(instances, ",", &"#{&1}#{@weekday_codes[day]}")]

  defp byday_parts(days, instance) do
    codes =
      days
      |> List.wrap()
      |> Enum.flat_map(fn
        %Range{} = r -> Enum.to_list(r)
        d -> [d]
      end)
      |> Enum.map_join(",", &@weekday_codes[&1])

    ["BYDAY=#{codes}"] ++ byday_parts(nil, instance)
  end

  defp no_rrule(expression, what),
    do: ConversionError.exception(value: expression, reason: {:no_rrule, what})

  defp argument(message), do: ArgumentError.exception(message)
end
