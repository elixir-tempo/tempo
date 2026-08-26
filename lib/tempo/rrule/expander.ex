defmodule Tempo.RRule.Expander do
  @moduledoc """
  Materialise an RFC 5545 RRULE into concrete occurrences by
  forming the right AST and handing it to Tempo's interpreter.

  ## Design — adapter, not engine

  The iCalendar `RRULE`, ISO 8601-2 recurring intervals
  (`R5/DTSTART/P1D`), and hand-built `Tempo.RRule.Rule` structs
  all express the same thing: a recurrence anchored at a point
  in time, repeated at a cadence, optionally filtered by BY-rule
  selections. Tempo's `%Tempo.Interval{}` struct already has
  every field needed to represent this shape: `recurrence`,
  `duration`, `from`, `to` (for UNTIL), and `repeat_rule`
  (carrying BY-rule filters as selection tokens).

  Rather than build a parallel engine, this module is a thin
  adapter:

  1. **Input normalisation** — any of `%Tempo.RRule.Rule{}`,
     `%ICal.Recurrence{}`, or (in future) parsed AST get
     canonicalised into `%Tempo.RRule.Rule{}`.

  2. **AST projection** — `to_ast/3` builds the canonical
     `%Tempo.Interval{}` that Tempo's interpreter understands.

  3. **Delegation** — `Tempo.to_interval/2` materialises the
     AST into the occurrence set.

  Extending RRULE support (BY* rules, BYSETPOS, RDATE, EXDATE)
  happens by extending the interpreter — selection-resolution
  in the enumeration module and `Tempo.to_interval/2` — never by
  adding expansion logic here.

  See `plans/rrule-full-expansion.md` for the roadmap.

  """

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule.Rule

  @doc """
  Expand a rule into a list of concrete `%Tempo.Interval{}`
  occurrences.

  ### Arguments

  * `rule` is any of:

    * `%Tempo.RRule.Rule{}` — the canonical form.

    * `%ICal.Recurrence{}` — mapped via `from_ical_recurrence/1`
      (only when the `ical` library is loadable).

  * `dtstart` is a `t:Tempo.t/0` anchor for the first occurrence.

  ### Options

  * `:duration` is a `%Tempo.Duration{}` giving each occurrence's
    span. Defaults to the natural span of `dtstart` (a day for
    day-resolution, an hour for hour-resolution, etc.).

  * `:bound` is any Tempo value whose upper endpoint limits the
    expansion. Required when the rule has neither `COUNT` nor
    `UNTIL`. The expansion stops when an occurrence would start
    at or after the bound's upper edge.

  * `:metadata` is a map of per-occurrence metadata attached to
    every materialised interval.

  ### Returns

  * `{:ok, [%Tempo.Interval{}]}` on success.

  * `{:error, reason}` when the rule is unbounded and no bound
    is supplied, or the input cannot be converted to the
    canonical AST.

  ### Examples

      iex> rule = %Tempo.RRule.Rule{freq: :day, interval: 1, count: 3}
      iex> {:ok, occurrences} = Tempo.RRule.Expander.expand(rule, ~o"2022-06-01")
      iex> length(occurrences)
      3
      iex> Enum.map(occurrences, &Tempo.day(Tempo.Interval.from(&1)))
      [1, 2, 3]

  """
  @spec expand(Rule.t() | term(), Tempo.t(), keyword()) ::
          {:ok, [Interval.t()]} | {:error, term()}
  def expand(rule, dtstart, options \\ [])

  def expand(%Rule{} = rule, %Tempo{} = dtstart, options) do
    with {:ok, ast} <- to_ast(rule, dtstart, options),
         {:ok, occurrences} <- materialise(ast, options) do
      {:ok, filter_byyear(occurrences, rule.byyear)}
    end
  end

  # The `ical` library is optional — guard the clause so Tempo
  # compiles when it isn't present.
  if Code.ensure_loaded?(ICal.Recurrence) do
    def expand(%ICal.Recurrence{} = ical_rule, %Tempo{} = dtstart, options) do
      case from_ical_recurrence(ical_rule) do
        {:ok, rule} -> expand(rule, dtstart, options)
        {:error, _} = err -> err
      end
    end
  end

  @doc """
  Convert a `%Tempo.RRule.Rule{}` (plus an anchor) to the
  canonical `%Tempo.Interval{}` AST.

  The AST has the same shape as `Tempo.RRule.parse/2`'s output
  and as the ISO 8601-2 `R<n>/DTSTART/P…` interval grammar, so
  `Tempo.to_interval/2` handles all three inputs uniformly.

  ### Arguments

  * `rule` is a `%Tempo.RRule.Rule{}`.

  * `dtstart` is a `%Tempo{}` anchor for the first occurrence.

  ### Options

  * `:duration` is a `%Tempo.Duration{}` override for each
    occurrence's span. When supplied, it is attached to the AST
    via `metadata.occurrence_duration` so the interpreter can
    emit occurrences whose span differs from the cadence.

  * `:base_to` is a `%Tempo{}` representing occurrence #0's upper
    endpoint. The interpreter shifts it by one cadence per
    iteration so each occurrence preserves the original event's
    span. Used by `Tempo.ICal` where `DTEND − DTSTART` defines
    the event span independently of the RRULE cadence.

  * `:metadata` is a map merged into the interval's metadata.

  ### Returns

  * `{:ok, %Tempo.Interval{}}`.

  ### Examples

      iex> rule = %Tempo.RRule.Rule{freq: :week, interval: 1, count: 5}
      iex> {:ok, ast} = Tempo.RRule.Expander.to_ast(rule, ~o"2022-06-01")
      iex> {ast.recurrence, ast.duration.time}
      {5, [week: 1]}

  """
  @spec to_ast(Rule.t(), Tempo.t(), keyword()) :: {:ok, Interval.t()}
  def to_ast(%Rule{} = rule, dtstart, options \\ [])
      when is_nil(dtstart) or is_struct(dtstart, Tempo) do
    cadence = %Tempo.Duration{time: [{rule.freq, rule.interval}]}

    recurrence = if is_integer(rule.count) and rule.count > 0, do: rule.count, else: :infinity

    base_metadata = Keyword.get(options, :metadata, %{})

    metadata =
      base_metadata
      |> put_if_given(
        :occurrence_duration,
        Keyword.get(options, :duration),
        &match?(%Tempo.Duration{}, &1)
      )
      |> put_if_given(:occurrence_base_to, Keyword.get(options, :base_to), &match?(%Tempo{}, &1))

    {:ok,
     %Interval{
       from: dtstart,
       to: rule.until,
       duration: cadence,
       recurrence: recurrence,
       repeat_rule: repeat_rule(rule),
       metadata: metadata
     }}
  end

  # The BY-rule filters become the `%Tempo{}` selection carried in the recurring
  # interval's `:repeat_rule`, built through the shared
  # `Tempo.RRule.Rule.to_selection/1` — the single source of truth for the
  # RRULE/cron → selection mapping — so this path and `Tempo.RRule.parse/2`
  # cannot diverge. Returns nil for the simple recurrence with no BY-rules.
  defp repeat_rule(%Rule{} = rule), do: Rule.to_selection(rule)

  defp put_if_given(map, _key, nil, _pred), do: map

  defp put_if_given(map, key, value, pred) do
    if pred.(value), do: Map.put(map, key, value), else: map
  end

  ## ------------------------------------------------------------
  ## Delegation to the interpreter
  ## ------------------------------------------------------------

  defp materialise(%Interval{} = ast, options) do
    # Each expanded occurrence is a distinct event — coalescing
    # would collapse adjacent occurrences into a single span and
    # silently lose event identity. Force `coalesce: false`
    # regardless of what the caller passed.
    case Tempo.to_interval(ast, Keyword.put(options, :coalesce, false)) do
      {:ok, %Tempo.IntervalSet{} = set} -> {:ok, IntervalSet.to_list(set)}
      {:ok, %Interval{} = single} -> {:ok, [single]}
      {:error, _} = err -> err
    end
  end

  # Honour a `:byyear` filter (a non-standard cron extension for a
  # multi-year field like `2025,2027,2029`). The cadence is already
  # bounded by UNTIL = last-year + 1, so we only need to drop the
  # in-between years the list omits.
  defp filter_byyear(occurrences, nil), do: occurrences

  defp filter_byyear(occurrences, years) when is_list(years) do
    Enum.filter(occurrences, fn %Interval{from: %Tempo{time: time}} ->
      Keyword.get(time, :year) in years
    end)
  end

  ## ------------------------------------------------------------
  ## Input normalisation — `%ICal.Recurrence{}` → `%Rule{}`
  ## ------------------------------------------------------------

  # The `ical` library is optional — guard the clauses so Tempo
  # compiles when it isn't present.
  if Code.ensure_loaded?(ICal.Recurrence) do
    # Aliased inside the `ical`-conditional block: `RRuleError` is only
    # referenced by the ical→rule mapping below, so a module-level alias
    # would be unused when `ical` is absent (e.g. a downstream that does
    # not depend on it), emitting an unused-alias warning.
    alias Tempo.RRuleError

    @doc """
    Convert an `%ICal.Recurrence{}` into a `%Tempo.RRule.Rule{}`.

    Used by `Tempo.ICal` and the polymorphic `expand/3` above.
    Requires the `ical` dependency at compile time; the function
    is only defined when `ical` is loadable.

    ### Arguments

    * `ical_rule` is an `%ICal.Recurrence{}`.

    ### Returns

    * `{:ok, %Tempo.RRule.Rule{}}` on success.

    * `{:error, reason}` when a field cannot be mapped.

    """
    @spec from_ical_recurrence(ICal.Recurrence.t()) :: {:ok, Rule.t()} | {:error, term()}
    def from_ical_recurrence(%ICal.Recurrence{} = r) do
      case map_freq(r.frequency) do
        {:ok, freq} ->
          {:ok,
           %Rule{
             freq: freq,
             interval: r.interval || 1,
             count: r.count,
             until: convert_until(r.until),
             wkst: map_weekday(r.week_start_day) || 1,
             bymonth: r.by_month,
             bymonthday: r.by_month_day,
             byyearday: r.by_year_day,
             byweekno: r.by_week_number,
             byday: map_byday(r.by_day),
             byhour: r.by_hour,
             byminute: r.by_minute,
             bysecond: r.by_second,
             bysetpos: r.by_set_position
           }}

        :error ->
          {:error,
           RRuleError.exception(
             reason: "Unsupported ical frequency: #{inspect(r.frequency)}",
             rule: r
           )}
      end
    end

    defp map_freq(:secondly), do: {:ok, :second}
    defp map_freq(:minutely), do: {:ok, :minute}
    defp map_freq(:hourly), do: {:ok, :hour}
    defp map_freq(:daily), do: {:ok, :day}
    defp map_freq(:weekly), do: {:ok, :week}
    defp map_freq(:monthly), do: {:ok, :month}
    defp map_freq(:yearly), do: {:ok, :year}
    defp map_freq(_), do: :error

    defp convert_until(nil), do: nil
    defp convert_until(%DateTime{} = dt), do: Tempo.from_elixir(dt)
    defp convert_until(%Date{} = d), do: Tempo.from_elixir(d)
    defp convert_until(%NaiveDateTime{} = ndt), do: Tempo.from_elixir(ndt)
    defp convert_until(_), do: nil

    defp map_weekday(nil), do: nil
    defp map_weekday(:monday), do: 1
    defp map_weekday(:tuesday), do: 2
    defp map_weekday(:wednesday), do: 3
    defp map_weekday(:thursday), do: 4
    defp map_weekday(:friday), do: 5
    defp map_weekday(:saturday), do: 6
    defp map_weekday(:sunday), do: 7
    defp map_weekday(_), do: nil

    defp map_byday(nil), do: nil
    defp map_byday([]), do: nil

    defp map_byday(entries) when is_list(entries) do
      Enum.map(entries, &map_byday_entry/1)
    end

    # The ical library's BYDAY entry shape is
    # `{ordinal_or_zero_for_none, weekday_atom}` — e.g. `{1, :monday}`
    # for "1MO" and `{0, :monday}` for a plain "MO" (no ordinal).
    # Normalise to our AST form, which uses `nil` for the
    # "no ordinal" case.
    defp map_byday_entry({0, day_atom}) do
      {nil, map_weekday(day_atom) || 1}
    end

    defp map_byday_entry({ord, day_atom}) do
      {ord, map_weekday(day_atom) || 1}
    end

    defp map_byday_entry(day_atom) when is_atom(day_atom) do
      {nil, map_weekday(day_atom) || 1}
    end
  end
end
