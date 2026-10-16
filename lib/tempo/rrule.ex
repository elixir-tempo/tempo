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

  RFC 7529 is read with it. `RSCALE` names the calendar a rule counts in,
  which is then the calendar of the recurrence and of its occurrences;
  `BYMONTH` may name a leap month of it (`5L`); and `SKIP` says what is
  taken for a day or a month a year lacks, the next there is (`FORWARD`) or
  the last before it (`BACKWARD`). A `WKST` other than Monday is the day
  the recurrence's weeks begin on where it changes the weeks counted.

  """

  import Kernel, except: [to_string: 1]

  alias Tempo.Build
  alias Tempo.Calendar, as: Calendars
  alias Tempo.{ConversionError, Duration, Options, Validate}

  @skips %{"OMIT" => :omit, "BACKWARD" => :backward, "FORWARD" => :forward}
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
          optional(:freq) => Tempo.unit(),
          optional(:interval) => pos_integer(),
          optional(:count) => pos_integer(),
          optional(:until) => Tempo.t(),
          optional(:bymonth) => [integer() | {integer(), :leap}],
          optional(:bymonthday) => [integer()],
          optional(:byyearday) => [integer()],
          optional(:byweekno) => [integer()],
          optional(:byday) => [{integer() | nil, 1..7}],
          optional(:byhour) => [integer()],
          optional(:byminute) => [integer()],
          optional(:bysecond) => [integer()],
          optional(:bysetpos) => [integer()],
          optional(:wkst) => 1..7,
          optional(:rscale) => String.t(),
          optional(:skip) => :omit | :forward | :backward
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
    an `RSCALE` that names no calendar, a `SKIP` or a leap month with no
    `RSCALE`.

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

  ### Arguments

  * `text` and `options` are as for `parse/2`.

  ### Returns

  * The recurrence, a `t:Tempo.t/0`, or raises the error `parse/2` returns.

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
      {:ok, day} -> {:ok, :wkst, day}
      :error -> {:error, argument("#{inspect(value)} is not a WKST")}
    end
  end

  # RFC 7529: the calendar a rule counts in, what is taken for a day or a
  # month a year lacks, and a month number that may name a leap month (`5L`).
  defp part("RSCALE", value), do: {:ok, :rscale, String.downcase(value)}

  defp part("SKIP", value) do
    case Map.fetch(@skips, String.upcase(value)) do
      {:ok, skip} ->
        {:ok, :skip, skip}

      :error ->
        {:error, argument("#{inspect(value)} is not a SKIP: it is OMIT, BACKWARD or FORWARD")}
    end
  end

  defp part("BYMONTH", value) do
    months = value |> String.split(",") |> Enum.map(&month_number/1)

    if :error in months,
      do: {:error, argument("#{inspect(value)} is not a list of months")},
      else: {:ok, :bymonth, months}
  end

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

  defp month_number(text) do
    case Integer.parse(String.trim(text)) do
      {month, ""} -> month
      {month, leap} when leap in ["L", "l"] -> {month, :leap}
      _ -> :error
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

      Map.has_key?(rule, :skip) and not Map.has_key?(rule, :rscale) ->
        {:error, argument("SKIP is given with RSCALE (RFC 7529), and this rule has none")}

      true ->
        {:ok, rule}
    end
  end

  defp checked(error), do: error

  # A leap month is of a calendar that has one, which a rule names.
  defp leap_months_named(rule) do
    leap? = Enum.any?(Map.get(rule, :bymonth, []), &match?({_month, :leap}, &1))

    if leap? and Map.get(rule, :rscale, "gregorian") in ["gregorian", "gregory"],
      do:
        {:error,
         argument("a leap month (5L) is of a calendar that has one, named with RSCALE (RFC 7529)")},
      else: :ok
  end

  # RFC 5545 section 3.3.10: the day a week starts on is significant in a
  # weekly rule of every second week or more that names weekdays, and in a
  # yearly rule that names weeks of the year. There the recurrence is of the
  # calendar whose weeks begin on that day (`[u-fw=sun]`); where the day
  # changes nothing it is read and not kept.
  defp week_start_counts?(%{wkst: day} = rule) when day != 1 do
    (rule.freq == :week and Map.get(rule, :interval, 1) > 1 and Map.has_key?(rule, :byday)) or
      (rule.freq == :year and Map.has_key?(rule, :byweekno))
  end

  defp week_start_counts?(_rule), do: false

  # ── Rule to recurrence ────────────────────────────────────────────────

  @doc """
  A recurrence from a rule in the shared vocabulary (`t:rule/0`), as
  `Tempo.Cron` and `Tempo.JSCalendar` build one.

  ### Arguments

  * `rule` is a `t:rule/0` with a frequency.

  * `options` is a keyword list of options.

  ### Options

  * `:from`, `:duration` and `:metadata` are as for `parse/2`.

  ### Returns

  * `{:ok, recurrence}` or `{:error, exception}`, as for `parse/2`.

  ### Examples

      iex> Tempo.RRule.from_rule(%{freq: :week, count: 3}, from: ~o"2026-06-01")
      {:ok, ~o"R3/2026-06-01/P1W/FL1KN"}

  """
  @spec from_rule(rule(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def from_rule(%{freq: _freq} = rule, options) do
    with :ok <- leap_months_named(rule),
         {:ok, from} <- in_scale(rule, Keyword.get(options, :from)),
         {:ok, from} <- in_weeks_of(rule, from) do
      from_rule(Map.drop(rule, [:wkst, :rscale]), from, options)
    end
  end

  def from_rule(_rule, _options), do: {:error, argument("a rule needs a frequency")}

  @doc """
  `from_rule/2`, returning its answer or raising the error.

  ### Arguments

  * The arguments are those of `from_rule/2`.

  ### Returns

  * What `from_rule/2` returns as `{:ok, answer}`, the answer alone.
    The error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.RRule.from_rule!(%{freq: :week, count: 3}, from: ~o"2026-06-01")
      ~o"R3/2026-06-01/P1W/FL1KN"

  """
  @spec from_rule!(rule(), keyword()) :: Tempo.t()
  def from_rule!(rule, options) do
    case from_rule(rule, options) do
      {:ok, answer} -> answer
      {:error, exception} -> raise exception
    end
  end

  # The start a rule counts from, in the calendar its `RSCALE` names: its
  # months, its years and their days are that calendar's, and so are its
  # occurrences. `GREGORIAN` is the calendar a rule is in with none.
  defp in_scale(%{rscale: name}, from) when name not in ["gregorian", "gregory"] do
    case Calendars.from_type(name) do
      {:ok, calendar} ->
        scaled(from, calendar)

      {:error, _} ->
        {:error, argument("RSCALE=#{String.upcase(name)} names no calendar Tempo has")}
    end
  end

  defp in_scale(_rule, from), do: {:ok, from}

  defp scaled(nil, calendar), do: {:ok, {:calendar, calendar}}
  defp scaled(%Tempo{} = from, calendar), do: Tempo.to_calendar(from, calendar)
  defp scaled(other, _calendar), do: {:ok, other}

  # The start a rule counts from, in the calendar whose weeks begin on the
  # rule's `WKST` where that day counts; with no start, the calendar alone.
  defp in_weeks_of(rule, from) do
    if week_start_counts?(rule),
      do: weeks_from(rule.wkst, from),
      else: {:ok, from}
  end

  defp weeks_from(day, nil) do
    with {:ok, calendar} <- Calendars.with_week_start(Calendars.default(), day),
         do: {:ok, {:calendar, calendar}}
  end

  defp weeks_from(day, {:calendar, calendar}) do
    with {:ok, calendar} <- Calendars.with_week_start(calendar, day),
         do: {:ok, {:calendar, calendar}}
  end

  defp weeks_from(day, %Tempo{calendar: calendar} = from) do
    with {:ok, calendar} <- Calendars.with_week_start(calendar, day),
         do: Tempo.to_calendar(from, calendar)
  end

  defp weeks_from(_day, other), do: {:ok, other}

  defp from_rule(%{freq: freq} = rule, from, options) do
    rule = with_start(rule, from)
    cadence = %Duration{units: [{freq, Map.get(rule, :interval, 1)}]}
    {cadence, parts} = lowered(rule, cadence, Keyword.get(options, :duration))
    bound = bound(rule)

    with {:ok, parts} <- parts,
         {:ok, first} <- first_span(from, cadence),
         {:ok, bound} <- Build.bound_in_frame(bound, first) do
      recurrence = %Tempo{
        form: {:every, first, bound, in_calendar(parts, first.calendar, rule)},
        calendar: first.calendar,
        zone: first.zone,
        metadata: Keyword.get(options, :metadata, %{})
      }

      Validate.run(recurrence)
    end
  end

  # A rule's parts as its calendar counts them: a month by its name where
  # the calendar is not the Gregorian (a lunisolar year's months are named,
  # and its leap month is `5L`), a day of a numbered week counted from the
  # day the week begins on, and what is taken for a day the year lacks.
  # Where each occurrence has a length the days are selected first and a
  # window opened from each, and it is the days that are so counted.
  defp in_calendar([selection: selected, window: %Duration{} = length], calendar, rule),
    do: [selection: in_calendar(selected, calendar, rule), window: length]

  defp in_calendar(parts, calendar, rule) do
    parts
    |> months_named(Calendars.gregorian?(calendar))
    |> days_of_week(calendar, &Calendars.day_of_week_from_iso/2)
    |> with_skip(Map.get(rule, :skip))
  end

  defp months_named(nil, _gregorian?), do: nil
  defp months_named(parts, true), do: parts

  defp months_named(parts, false) do
    Enum.map(parts, fn
      {:month, held} -> {:traditional_month, held}
      part -> part
    end)
  end

  # A skip stands after the days it moves and before a time of day on them
  # and a position among them.
  defp with_skip(parts, skip) when skip in [:forward, :backward] and is_list(parts) do
    {days, later} =
      Enum.split_while(parts, fn {unit, _} -> unit not in [:hour, :minute, :second, :instance] end)

    days ++ [skip: skip] ++ later
  end

  defp with_skip(parts, _omit_or_none), do: parts

  # RFC 5545 names a weekday as ISO 8601 numbers it, Monday 1; the rule's
  # calendar numbers the days of its week from the day its weeks begin on
  # (decision 80), so `BYDAY=MO` is day 2 where weeks begin on Sunday, with
  # a numbered week (`BYWEEKNO=20;BYDAY=MO`) or without. A rule's parts are
  # numbered so when it is read, and named back when it is written, in a
  # selection nested in them as at their top.
  defp days_of_week(nil, _calendar, _numbered) do
    nil
  end

  defp days_of_week(parts, calendar, numbered) do
    Enum.map(parts, &day_of_week_part(&1, calendar, numbered))
  end

  defp day_of_week_part({:day_of_week, held}, calendar, numbered) do
    {:day_of_week, each_day(held, &numbered.(calendar, &1))}
  end

  defp day_of_week_part({:selection, parts}, calendar, numbered) do
    {:selection, days_of_week(parts, calendar, numbered)}
  end

  defp day_of_week_part({:all, selections}, calendar, numbered) do
    {:all, Enum.map(selections, &days_of_week(&1, calendar, numbered))}
  end

  defp day_of_week_part(part, _calendar, _numbered) do
    part
  end

  defp each_day(held, numbered) when is_list(held), do: Enum.map(held, numbered)
  defp each_day(held, numbered) when is_integer(held), do: numbered.(held)
  defp each_day(held, _numbered), do: held

  defp first_span(nil, cadence),
    do: {:ok, %Tempo{form: {:span, :open, cadence}}}

  defp first_span({:calendar, calendar}, cadence),
    do: {:ok, %Tempo{form: {:span, :open, cadence}, calendar: calendar}}

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
  defp with_start(rule, %Tempo{form: {:value, units}, calendar: calendar}) do
    case Enum.map([:year, :month, :day], &Keyword.get(units, &1)) do
      [y, m, d] when is_integer(y) and is_integer(m) and is_integer(d) ->
        with_date_of_start(rule.freq, rule, m, d, {units, calendar})

      _ ->
        with_clock_of_start(rule, units)
    end
  end

  defp with_start(rule, _from), do: rule

  defp with_date_of_start(:week, rule, _month, _day, {units, calendar}) do
    if Map.has_key?(rule, :byday),
      do: rule,
      else: Map.put(rule, :byday, [{nil, weekday_of(units, calendar)}])
  end

  defp with_date_of_start(:month, rule, _month, day, _start) do
    if names_a_day?(rule), do: rule, else: Map.put(rule, :bymonthday, [day])
  end

  defp with_date_of_start(:year, rule, month, day, {units, calendar}) do
    if names_a_day?(rule) or Map.has_key?(rule, :byweekno),
      do: rule,
      else:
        rule
        |> Map.put_new(:bymonth, [month_of_start(calendar, units[:year], month)])
        |> Map.put(:bymonthday, [day])
  end

  defp with_date_of_start(_finer, rule, _month, _day, {units, _calendar}),
    do: with_clock_of_start(rule, units)

  # The month of a start as a rule names it: its number, and in a calendar
  # that is not the Gregorian the month as it is named, a leap month as one.
  defp month_of_start(calendar, year, month) do
    if Calendars.gregorian?(calendar),
      do: month,
      else: named_month(Calendars.traditional_month(calendar, year, month), month)
  end

  defp named_month({:error, _}, month), do: month
  defp named_month(named, _month), do: named

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

  defp weekday_of(units, calendar) do
    Tempo.day_of_week(%Tempo{form: {:value, units}, calendar: calendar}, :monday)
  end

  # The selection's parts, and the cadence: a yearly rule with a numbered
  # weekday in named months keeps its years, and selects the weekday in each
  # month it names, one period a year as RFC 5545 counts it.
  defp lowered(rule, cadence, duration) do
    numbered = numbered_weekday(rule)
    in_months? = rule.freq == :year and numbered != nil and Map.has_key?(rule, :bymonth)

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
      |> numbered_before_times(numbered, in_months?)
      |> windowed(duration)

    if parts == [], do: {cadence, {:ok, nil}}, else: {cadence, {:ok, parts}}
  end

  # A numbered weekday (`2MO`) is the nth of its weekday in the period, and
  # the times of day beside it are times on that day (RFC 5545 section
  # 3.3.10): it is selected first, where a position after the times would
  # count among the times too, as BYSETPOS does.
  defp numbered_before_times(parts, {day, n}, in_each_month?) do
    if in_each_month? or Enum.any?(parts, fn {unit, _} -> unit in [:hour, :minute, :second] end) do
      {before, times} =
        parts
        |> Keyword.drop([:day_of_week, :instance])
        |> Enum.split_while(fn {unit, _} -> unit not in [:hour, :minute, :second] end)

      before ++ [selection: [day_of_week: day, instance: n]] ++ times
    else
      parts
    end
  end

  defp numbered_before_times(parts, nil, _in_each_month?), do: parts

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
      [{:all, weekday_selections(entries)} | acc]
    else
      case Enum.map(entries, &elem(&1, 1)) do
        [one] -> [{:day_of_week, one} | acc]
        days -> [{:day_of_week, days} | acc]
      end
    end
  end

  defp push_byday(acc, _rule, {day, _n}), do: [{:day_of_week, day} | acc]

  defp push_byday(acc, _rule, nil), do: acc

  # Numbered weekdays of several days (`2MO,2WE`), or beside a BYSETPOS
  # that counts among them all: a set of selections, one for each weekday,
  # whose days are taken together. A weekday written plain beside a
  # numbered one (`MO,1MO`) is every one of them.
  defp weekday_selections(entries) do
    entries
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.sort_by(fn {day, _} -> Enum.find_index(entries, &(elem(&1, 1) == day)) end)
    |> Enum.map(fn {day, numbers} ->
      if nil in numbers,
        do: [day_of_week: day],
        else: [day_of_week: day, instance: one_or_list(numbers)]
    end)
  end

  defp push_instance(acc, %{bysetpos: positions}, _numbered),
    do: [{:instance, one_or_list(positions)} | acc]

  defp push_instance(acc, _rule, {_day, n}), do: [{:instance, n} | acc]
  defp push_instance(acc, _rule, nil), do: acc

  # An occurrence's length is a window from each element the parts select,
  # ISO 8601-2 §12.10's `L…N/PT1H`.
  defp windowed(parts, nil), do: parts

  defp windowed(parts, %Duration{} = duration) do
    [selection: parts, window: duration]
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
    {skip, selected} = skip_and_parts(parts || [])

    with :ok <- no_domain(from, r),
         {:ok, scale} <- scale_part(counted_in(r.calendar, cadence, selected), skip, r),
         :ok <- in_every_period(from, cadence, parts, r),
         {:ok, frequency} <- frequency_part(cadence, r),
         {:ok, bound} <- bound_part(bound, r),
         {:ok, by_parts} <- by_parts(selected, r) do
      parts =
        [scale, frequency, bound] ++
          by_parts ++ [skip_part(skip), week_start_part(r.calendar)]

      {:ok, parts |> Enum.reject(&(&1 == "")) |> Enum.join(";")}
    end
  end

  def to_string(other), do: {:error, no_rrule(other, :not_a_recurrence)}

  # A recurrence whose weeks begin on another day than Monday says so.
  defp week_start_part(calendar) do
    case Calendars.week_start(calendar) do
      nil -> ""
      day -> "WKST=" <> Map.fetch!(@weekday_codes, day)
    end
  end

  @doc """
  `to_string/1`, returning the text or raising.

  ### Arguments

  * `recurrence` is as for `to_string/1`.

  ### Returns

  * The RRULE text, or raises the error `to_string/1` returns.

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

  # RFC 5545 counts months, years and their days in the Gregorian calendar.
  # A recurrence of another calendar names it with RFC 7529's `RSCALE`, by
  # the name CLDR gives it; one of the Gregorian calendar names it only
  # where it has a `SKIP`, which is given with an `RSCALE` and not without.
  defp scale_part(:gregorian, nil, _r), do: {:ok, ""}
  defp scale_part(:gregorian, _skip, _r), do: {:ok, "RSCALE=GREGORIAN"}

  defp scale_part(calendar, _skip, r) do
    case Calendars.identifier(calendar) do
      {:ok, name} when is_binary(name) -> {:ok, "RSCALE=" <> String.upcase(name)}
      _no_name -> {:error, no_rrule(r, {:calendar, calendar})}
    end
  end

  # The calendar a rule counts in. A recurrence of another calendar than
  # the Gregorian that steps by weeks, days or the clock and selects by
  # weekday and time of day reads in the Gregorian as itself, and is
  # written as a rule of it.
  defp counted_in(calendar, %Duration{units: units}, parts) do
    calendar_counts? =
      Enum.any?(Keyword.keys(units), &(&1 in @calendar_cadences)) or
        Enum.any?(Keyword.keys(picked(parts)), &(&1 in @calendar_parts))

    if Calendars.gregorian?(calendar) or not calendar_counts?, do: :gregorian, else: calendar
  end

  defp skip_and_parts(selection: selected, window: %Duration{} = length) do
    {skip, selected} = Keyword.pop(selected, :skip)
    {skip, [selection: selected, window: length]}
  end

  defp skip_and_parts(parts), do: Keyword.pop(parts, :skip)

  defp skip_part(nil), do: ""
  defp skip_part(skip), do: "SKIP=" <> String.upcase(Atom.to_string(skip))

  # A month by its name is `BYMONTH`'s number, a leap month with its `L`.
  defp months_numbered(parts) do
    Enum.map(parts, fn
      {:traditional_month, held} -> {:month, month_numbers(held)}
      part -> part
    end)
  end

  defp month_numbers(held) when is_list(held), do: Enum.map(held, &month_numbers/1)
  defp month_numbers({month, :leap}), do: "#{month}L"
  defp month_numbers(month), do: month

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

  defp bound_part(count, _r) when is_integer(count), do: {:ok, "COUNT=#{count}"}
  defp bound_part(:infinity, _r), do: {:ok, ""}

  defp bound_part(%Tempo{} = until, r) do
    with {:ok, text} <- until_text(%{until | zone: until.zone || r.zone}),
         do: {:ok, "UNTIL=" <> text}
  end

  # RFC 5545 section 3.3.10: an `UNTIL` of a rule in a zone or at UTC is a
  # date with UTC time; one of a floating rule is a local time, and a date
  # is a date.
  defp until_text(%Tempo{form: {:value, units}, zone: nil, shift: nil}),
    do: {:ok, Enum.map_join(units, &until_unit/1)}

  defp until_text(%Tempo{form: {:value, units}} = until) do
    if Keyword.has_key?(units, :hour) do
      with {:ok, %Tempo{form: {:value, utc}}} <- Tempo.shift_zone(until, "Etc/UTC"),
           do: {:ok, Enum.map_join(utc, &until_unit/1) <> "Z"}
    else
      {:ok, Enum.map_join(units, &until_unit/1)}
    end
  end

  defp until_unit({:year, y}), do: padded(y, 4)
  defp until_unit({unit, n}) when unit in [:month, :day, :minute, :second], do: padded(n, 2)
  defp until_unit({:hour, h}), do: "T" <> padded(h, 2)
  defp until_unit(_other), do: ""

  defp padded(n, width), do: String.pad_leading(Integer.to_string(n), width, "0")

  defp by_parts([selection: parts, window: %Duration{}], r), do: by_parts(parts, r)

  defp by_parts(parts, r) do
    frequency = frequency_of(r)

    parts =
      parts
      |> months_numbered()
      |> days_of_week(r.calendar, &Calendars.iso_weekday_from_day_of_week/2)

    {weekday, instance, parts} = weekday_and_position(parts)

    with :ok <- expressible(parts, r),
         :ok <- allowed(parts, frequency, r),
         :ok <- positioned(weekday, instance, parts, frequency, r) do
      named = Enum.map(parts, fn {unit, held} -> "#{by_name(unit)}=#{listed(held)}" end)
      {:ok, named ++ byday_parts(weekday, instance)}
    end
  end

  # A numbered weekday selected before the times of day is BYDAY's `2MO`.
  defp weekday_and_position(parts) do
    case {Keyword.pop(parts, :all), Keyword.pop(parts, :selection)} do
      {{[_ | _] = each, rest}, _selection} ->
        {instance, rest} = Keyword.pop(rest, :instance)
        {{:all, each}, instance, rest}

      {_no_set, selection} ->
        weekday_and_position(selection, parts)
    end
  end

  defp weekday_and_position({[day_of_week: day, instance: n], rest}, _parts) when is_integer(day),
    do: {day, n, rest}

  defp weekday_and_position(_no_numbered_weekday, parts) do
    {weekday, parts} = Keyword.pop(parts, :day_of_week)
    {instance, parts} = Keyword.pop(parts, :instance)
    {weekday, instance, parts}
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

  defp byday_parts({:all, each}, instance),
    do: ["BYDAY=" <> Enum.map_join(each, ",", &weekday_codes/1)] ++ byday_parts(nil, instance)

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

  defp weekday_codes(day_of_week: day), do: @weekday_codes[day]

  defp weekday_codes(day_of_week: day, instance: numbers),
    do: numbers |> List.wrap() |> Enum.map_join(",", &"#{&1}#{@weekday_codes[day]}")

  defp no_rrule(expression, what),
    do: ConversionError.exception(value: expression, reason: {:no_rrule, what})

  defp argument(message), do: ArgumentError.exception(message)
end
