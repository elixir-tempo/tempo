defmodule Tempo.Cron do
  @moduledoc """
  Parses cron expressions into recurring `t:Tempo.Interval.t/0`
  values — the same first-class recurrence that `Tempo.RRule.parse/2`
  and native ISO 8601 repeating intervals produce.

  Lets Tempo consume any cron-configured schedule (Oban, Quantum,
  system crontab) without rewriting it in another vocabulary. Once
  parsed, convert it to its occurrences like any other recurrence — `Tempo.to_interval/2`
  with a `:within` window — or supply `:from` to start the occurrences.

  ### Supported formats

  * **5-field POSIX**: `"minute hour day-of-month month day-of-week"`.

  * **6-field (seconds-first)**: `"second minute hour day-of-month month day-of-week"`.
    This is the variant used by Quantum and other Elixir
    schedulers.

  * **7-field (with year)**: `"second minute hour day-of-month month day-of-week year"`.
    A single concrete year is converted into an `UNTIL` limit; a
    year list or range (`2025,2027,2029`) becomes a `bymonthday`-style
    `byyear` filter bounded one past the last listed year.

  ### Field grammar

  Each field accepts:

  * `*` — every value in the field's range.

  * `N` — a single integer.

  * `N,M,O` — a list.

  * `N-M` — an inclusive range.

  * `*/S` — every `S` starting from the field's minimum.

  * `N-M/S` — every `S` within the range `N..M`.

  Day-of-week accepts `SUN`–`SAT` (case-insensitive) as synonyms for
  `0`–`6`. Sunday is both `0` and `7` (cron convention); internally
  converted to RFC 5545's `7` (Sunday last). A day-of-week step
  (`N/S`, `*/S`) is expanded in *cron* numbering — Sunday = 0, the
  week start — then mapped to RFC, so `0/3` is Sun, Wed, Sat and
  `*/2` is Sun, Tue, Thu, Sat. A bare-day step runs to the end of
  the week and does not wrap (`5/2` is Fri, Sun — not Tue).

  Month accepts `JAN`–`DEC` (case-insensitive) as synonyms for `1`–`12`.

  ### Shortcut aliases

  Standard cron aliases are supported:

  | Alias                       | Expands to      |
  | --------------------------- | --------------- |
  | `@yearly`, `@annually`      | `0 0 1 1 *`     |
  | `@monthly`                  | `0 0 1 * *`     |
  | `@weekly`                   | `0 0 * * 0`     |
  | `@daily`, `@midnight`       | `0 0 * * *`     |
  | `@hourly`                   | `0 * * * *`     |

  `@reboot` is not supported — it is a system-startup hook, not a
  time expression.

  ### Vixie-cron extensions

  * `L` as day-of-month — last day of the month → `bymonthday: [-1]`.

  * `NL` as day-of-week (e.g. `5L`) — last weekday-N of the month →
    `byday: [{-1, N}]`.

  * `N#K` as day-of-week (e.g. `5#2`) — Kth weekday-N of the month →
    `byday: [{K, N}]`.

  * `W` as day-of-month (e.g. `15W`, `LW`) — the nearest weekday to
    that day, never crossing a month boundary → `bymonthday_nearest`.
    A Saturday snaps back to Friday, a Sunday forward to Monday, and
    `1W` on a weekend clamps forward into the same month. Only valid
    on a single day, never a list or range.

  ### POSIX day-of-month OR day-of-week

  When both `dom` and `dow` are restricted to plain lists (`13 * 5` —
  "the 13th *or* any Friday"), POSIX cron matches the **union**, not
  the intersection. Tempo honours this via a daily cadence carrying a
  `bymonthday_or_byday` union filter, so `13 * 5` fires on every 13th
  and every Friday — not only Friday-the-13ths. A Quartz extension in
  either field (an ordinal day-of-week `5#2`/`5L`, or a nearest-weekday
  `15W`) opts out and keeps the AND-composing interpretation.

  ### Not supported (AST gaps)

  * **`@reboot`** — not a time expression.

  """

  alias Tempo.CronError
  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  @aliases %{
    "@yearly" => "0 0 1 1 *",
    "@annually" => "0 0 1 1 *",
    "@monthly" => "0 0 1 * *",
    "@weekly" => "0 0 * * 0",
    "@daily" => "0 0 * * *",
    "@midnight" => "0 0 * * *",
    "@hourly" => "0 * * * *"
  }

  @month_names %{
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "may" => 5,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12
  }

  @dow_names %{
    "sun" => 0,
    "mon" => 1,
    "tue" => 2,
    "wed" => 3,
    "thu" => 4,
    "fri" => 5,
    "sat" => 6
  }

  # Coarsest-to-finest cascade priority; the first specified field
  # sets FREQ, everything finer becomes a BY rule.
  @cascade_order [:year, :month, :day_of_week, :day_of_month, :hour, :minute, :second]

  @doc """
  Parse a cron expression into a recurring `t:Tempo.Interval.t/0`.

  A cron schedule, an RFC 5545 RRULE, and a native ISO 8601 repeating
  interval all become the same kind of first-class Tempo value, so a
  parsed cron entry composes and converts exactly like any other
  recurrence — no intermediate rule struct to manage.

  ### Arguments

  * `expression` is a cron string (5, 6, or 7 fields, or an alias).

  ### Options

  * `:from` — the recurrence's start, a `t:Tempo.t/0`. Optional;
    supply it to enumerate or list concrete occurrences.

  ### Returns

  * `{:ok, interval}` — a recurring `t:Tempo.Interval.t/0`, converted to its
    occurrences with `Tempo.to_interval/2` given a `:within` window.

  * `{:error, exception}` — typically a `t:Tempo.CronError.t/0`.

  ### Examples

      iex> {:ok, monthly} = Tempo.Cron.parse("0 0 15 * *", from: ~o"2025-01-15")
      iex> {:ok, occurrences} = Tempo.to_interval(monthly, within: ~o"2025")
      iex> Tempo.IntervalSet.count(occurrences)
      12

      iex> {:error, %Tempo.CronError{}} = Tempo.Cron.parse("not a cron")

  """
  @spec parse(String.t(), keyword()) :: {:ok, Tempo.Interval.t()} | {:error, Exception.t()}
  def parse(expression, options \\ []) when is_binary(expression) do
    with {:ok, rule} <- to_rule(expression) do
      Expander.to_ast(rule, Keyword.get(options, :from))
    end
  end

  @doc """
  Raising version of `parse/2`.

  ### Examples

      iex> Tempo.Cron.parse!("@hourly").recurrence
      :infinity

  """
  @spec parse!(String.t(), keyword()) :: Tempo.Interval.t()
  def parse!(expression, options \\ []) do
    case parse(expression, options) do
      {:ok, interval} -> interval
      {:error, exception} -> raise exception
    end
  end

  # Parse a cron expression into the intermediate RRULE `Rule` — the
  # detailed field mapping (freq/interval/by-rules). Internal: the public
  # `parse/2` wraps this and returns a recurring interval. Kept as a named
  # function so the field-level mapping stays directly testable.
  @doc false
  @spec to_rule(String.t()) :: {:ok, Rule.t()} | {:error, Exception.t()}
  def to_rule(expression) when is_binary(expression) do
    trimmed = String.trim(expression)

    case Map.get(@aliases, String.downcase(trimmed)) do
      nil -> parse_fields(trimmed, expression)
      expanded -> parse_fields(expanded, expression)
    end
  end

  ## ---------------------------------------------------------
  ## Field dispatch — normalise raw strings into a shared map
  ## ---------------------------------------------------------

  # The internal representation of a parsed expression. Every
  # field is one of:
  #
  #   * `nil`           — the field was `*` (no BY constraint)
  #   * `{:list, [..]}` — specific values; becomes a BY* list
  #   * `{:step, n}`    — the field was `*/n`; candidate for INTERVAL
  #
  # Keeping the raw form on `:step` lets `choose_freq/1` decide
  # whether to collapse into FREQ=unit,INTERVAL=n (when every
  # other field is `*`) or to expand into a BY list.

  defp parse_fields(string, original) do
    parts = String.split(string, ~r/\s+/, trim: true)

    case parts do
      [min, hr, dom, mon, dow] ->
        build(nil, min, hr, dom, mon, dow, nil, original)

      [sec, min, hr, dom, mon, dow] ->
        build(sec, min, hr, dom, mon, dow, nil, original)

      [sec, min, hr, dom, mon, dow, year] ->
        build(sec, min, hr, dom, mon, dow, year, original)

      _other ->
        {:error,
         CronError.exception(
           input: original,
           reason:
             "Cron expression must have 5, 6, or 7 fields (or be a supported @alias). " <>
               "Got #{length(parts)}."
         )}
    end
  end

  defp build(sec, min, hr, dom, mon, dow, year, _original) do
    with {:ok, n_sec} <- normalise(sec, :second, 0..59),
         {:ok, n_min} <- normalise(min, :minute, 0..59),
         {:ok, n_hr} <- normalise(hr, :hour, 0..23),
         {:ok, n_dom} <- normalise_monthday(dom),
         {:ok, n_mon} <- normalise_month(mon),
         {:ok, n_dow} <- normalise_dow(dow),
         {:ok, n_year} <- normalise(year, :year, 1970..9999) do
      fields = %{
        second: n_sec,
        minute: n_min,
        hour: n_hr,
        day_of_month: n_dom,
        month: n_mon,
        day_of_week: n_dow,
        year: n_year,
        has_seconds?: sec != nil
      }

      rule =
        case posix_or_case(n_dom, n_dow) do
          {:or, monthdays, byday_entries} -> build_or_rule(fields, monthdays, byday_entries)
          :no -> choose_freq(fields)
        end

      {:ok, apply_year_limit(rule, n_year)}
    end
  end

  # POSIX cron: when BOTH day-of-month and day-of-week are restricted
  # to plain lists, a date matches if EITHER is satisfied (the union),
  # not both. Quartz extensions opt out — an ordinal day-of-week
  # (`5#2`, `5L`) or a nearest-weekday day-of-month (`15W`, which is
  # not a `{:list, _}`) keeps the AND-composing interpretation.
  defp posix_or_case({:list, monthdays}, {:list, byday_entries}) do
    if Enum.all?(byday_entries, fn {ordinal, _day} -> is_nil(ordinal) end) do
      {:or, monthdays, byday_entries}
    else
      :no
    end
  end

  defp posix_or_case(_dom, _dow), do: :no

  # The POSIX OR case runs a DAILY cadence so every candidate day is
  # visited, carrying the time-of-day and month as ordinary BY filters
  # plus the day-of-month-OR-day-of-week union. (A wildcard sub-day
  # time field is the one case this under-serves; fixed times — the
  # common shape, e.g. `0 0 13 * 5` — are exact.)
  defp build_or_rule(fields, monthdays, byday_entries) do
    %Rule{freq: :day, interval: 1}
    |> put_by_list(:byhour, fields.hour)
    |> put_by_list(:byminute, fields.minute)
    |> put_by_list(:bysecond, fields.second)
    |> put_by_list(:bymonth, fields.month)
    |> Map.put(:bymonthday_or_byday, {monthdays, byday_entries})
  end

  ## ---------------------------------------------------------
  ## FREQ selection
  ## ---------------------------------------------------------

  # Build the final Rule. Two shapes of input:
  #
  #  (A) "Pure step" shortcut. The finest non-`*` field is a
  #      `{:step, n}` and every coarser field is `nil` (was `*`).
  #      Collapse to `FREQ=unit, INTERVAL=n`, no BY rules.
  #
  #  (B) Cascade. Pick FREQ from the *coarsest* non-`*` field; all
  #      finer non-`*` fields become BY rules. Step patterns at
  #      non-finest levels expand into BY lists.
  defp choose_freq(fields) do
    case pure_step(fields) do
      {:ok, freq, interval} -> %Rule{freq: freq, interval: interval}
      :no -> cascade(fields)
    end
  end

  defp pure_step(fields) do
    # Walk finest → coarsest looking for the first non-nil field.
    # If it's `{:step, n}` AND everything coarser is nil, we win.
    order = [:second, :minute, :hour, :day_of_month, :month, :day_of_week, :year]

    case Enum.find(order, fn k -> Map.get(fields, k) != nil end) do
      nil ->
        # Every field was `*`. FREQ is minute (or second if 6-field).
        if fields.has_seconds?, do: {:ok, :second, 1}, else: {:ok, :minute, 1}

      finest ->
        finest_step_freq(Map.get(fields, finest), finest, fields, order)
    end
  end

  defp finest_step_freq({:step, n}, finest, fields, order) do
    if coarser_all_nil?(fields, finest, order),
      do: {:ok, field_to_freq(finest), n},
      else: :no
  end

  defp finest_step_freq(_value, _finest, _fields, _order), do: :no

  defp coarser_all_nil?(fields, finest, order) do
    order
    |> Enum.drop_while(&(&1 != finest))
    |> Enum.drop(1)
    |> Enum.all?(fn k -> Map.get(fields, k) == nil end)
  end

  defp field_to_freq(:second), do: :second
  defp field_to_freq(:minute), do: :minute
  defp field_to_freq(:hour), do: :hour
  defp field_to_freq(:day_of_month), do: :month
  defp field_to_freq(:month), do: :year
  defp field_to_freq(:day_of_week), do: :week
  defp field_to_freq(:year), do: :year

  # Cascade: pick FREQ from coarsest specified field; everything
  # finer becomes a BY rule list.
  defp cascade(fields) do
    case Enum.find(@cascade_order, fn field -> not nil?(Map.fetch!(fields, field)) end) do
      nil -> default_cascade(fields)
      field -> build_cascade(field, fields)
    end
  end

  defp default_cascade(%{has_seconds?: true}), do: %Rule{freq: :second, interval: 1}
  defp default_cascade(_fields), do: %Rule{freq: :minute, interval: 1}

  defp build_cascade(field, fields) when field in [:year, :month] do
    %Rule{freq: :year, interval: 1}
    |> put_by_list(:bymonth, fields.month)
    |> add_finer_by(fields, :month)
  end

  defp build_cascade(:day_of_week, fields) do
    %Rule{freq: :week, interval: 1}
    |> put_by_list(:byday, fields.day_of_week)
    |> maybe_add_bymonthday(fields.day_of_month)
    |> add_finer_by(fields, :day_of_week)
  end

  defp build_cascade(:day_of_month, fields) do
    %Rule{freq: :month, interval: 1}
    |> put_by_list(:bymonthday, fields.day_of_month)
    |> add_finer_by(fields, :day_of_month)
  end

  defp build_cascade(:hour, fields) do
    %Rule{freq: :day, interval: 1}
    |> put_by_list(:byhour, fields.hour)
    |> add_finer_by(fields, :hour)
  end

  defp build_cascade(:minute, fields) do
    %Rule{freq: :hour, interval: 1}
    |> put_by_list(:byminute, fields.minute)
    |> add_finer_by(fields, :minute)
  end

  defp build_cascade(:second, fields) do
    %Rule{freq: :minute, interval: 1}
    |> put_by_list(:bysecond, fields.second)
  end

  defp nil?(nil), do: true
  defp nil?(_), do: false

  # Add BY rules for every field finer than `coarsest` that is not
  # nil.
  defp add_finer_by(rule, fields, coarsest) do
    order = [:year, :month, :day_of_week, :day_of_month, :hour, :minute, :second]

    order
    |> Enum.drop_while(&(&1 != coarsest))
    |> Enum.drop(1)
    |> Enum.reduce(rule, fn field, acc ->
      by_key = field_to_by_key(field)
      put_by_list(acc, by_key, Map.get(fields, field))
    end)
  end

  defp field_to_by_key(:month), do: :bymonth
  defp field_to_by_key(:day_of_month), do: :bymonthday
  defp field_to_by_key(:day_of_week), do: :byday
  defp field_to_by_key(:hour), do: :byhour
  defp field_to_by_key(:minute), do: :byminute
  defp field_to_by_key(:second), do: :bysecond
  defp field_to_by_key(:year), do: :__year__

  # Convert normalised form into a list of integers (or keep byday
  # tuples as-is). `nil` means "skip this BY rule".
  defp put_by_list(rule, :__year__, _), do: rule
  defp put_by_list(rule, _key, nil), do: rule

  defp put_by_list(rule, :bymonthday, {:nearest, targets}),
    do: %{rule | bymonthday_nearest: targets}

  defp put_by_list(rule, key, {:list, values}), do: Map.put(rule, key, values)
  defp put_by_list(rule, key, {:step, _n}), do: rule |> Map.put(key, step_expand(key, rule))

  # When dow is specified and dom is ALSO specified, add bymonthday.
  # POSIX OR semantics would need more; see module docs.
  defp maybe_add_bymonthday(rule, nil), do: rule
  defp maybe_add_bymonthday(rule, {:list, list}), do: Map.put(rule, :bymonthday, list)
  defp maybe_add_bymonthday(rule, {:nearest, targets}), do: %{rule | bymonthday_nearest: targets}
  defp maybe_add_bymonthday(rule, _), do: rule

  # Expand a `{:step, n}` into the relevant BY list. Rare case:
  # only hit when a step appears alongside other constraints.
  defp step_expand(:bymonth, _rule), do: Enum.to_list(1..12)
  defp step_expand(:bymonthday, _rule), do: Enum.to_list(1..31)
  defp step_expand(:byhour, _rule), do: Enum.to_list(0..23)
  defp step_expand(:byminute, _rule), do: Enum.to_list(0..59)
  defp step_expand(:bysecond, _rule), do: Enum.to_list(0..59)
  defp step_expand(:byday, _rule), do: Enum.map(1..7, &{nil, &1})

  # Year-as-UNTIL: a single concrete year becomes `until`.
  defp apply_year_limit(rule, nil), do: rule

  defp apply_year_limit(rule, {:list, [year]}) do
    %{rule | until: %Tempo{calendar: Calendrical.Gregorian, time: [year: year + 1]}}
  end

  # A multi-year list (`2025,2027,2029`, or a range/step that expands
  # to one) becomes a `:byyear` filter. The cadence is bounded by an
  # UNTIL one past the last listed year so the recurrence terminates;
  # the expander then keeps only occurrences whose year is listed.
  defp apply_year_limit(rule, {:list, [_ | _] = years}) do
    %{
      rule
      | byyear: years,
        until: %Tempo{calendar: Calendrical.Gregorian, time: [year: Enum.max(years) + 1]}
    }
  end

  defp apply_year_limit(rule, _multiple), do: rule

  ## ---------------------------------------------------------
  ## Field normalisers
  ## ---------------------------------------------------------

  defp normalise(nil, _field, _range), do: {:ok, nil}
  defp normalise("*", _field, _range), do: {:ok, nil}

  defp normalise("*/" <> step_str, field, range) do
    with {:ok, step} <- parse_int(step_str, field, 1..(range.last - range.first + 1)) do
      {:ok, {:step, step}}
    end
  end

  defp normalise(string, field, range) do
    with {:ok, values} <- parse_list(string, field, range) do
      {:ok, {:list, values}}
    end
  end

  defp normalise_month("*"), do: {:ok, nil}

  defp normalise_month(string) do
    with {:ok, values} <- parse_list_with_names(string, :month, 1..12, @month_names) do
      {:ok, {:list, values}}
    end
  end

  defp normalise_monthday("*"), do: {:ok, nil}
  defp normalise_monthday("L"), do: {:ok, {:list, [-1]}}

  # `LW` — the last weekday of the month.
  defp normalise_monthday("LW"), do: {:ok, {:nearest, [:last]}}

  defp normalise_monthday(string) do
    cond do
      # `<N>W` — the nearest weekday to day N. `W` is only valid on a
      # single day, never a list or range (per Quartz), so a prefix
      # carrying `,`, `-`, or `/` is rejected rather than guessed at.
      String.ends_with?(string, "W") and single_day?(String.trim_trailing(string, "W")) ->
        with {:ok, day} <- parse_int(String.trim_trailing(string, "W"), :day_of_month, 1..31) do
          {:ok, {:nearest, [day]}}
        end

      String.contains?(string, "W") ->
        {:error,
         CronError.exception(
           field: :day_of_month,
           value: string,
           reason: :unsupported_w
         )}

      true ->
        normalise(string, :day_of_month, 1..31)
    end
  end

  defp single_day?(string), do: not String.contains?(string, [",", "-", "/"])

  defp normalise_dow("*"), do: {:ok, nil}

  defp normalise_dow(string) do
    with {:ok, entries} <- parse_dow(string) do
      {:ok, {:list, entries}}
    end
  end

  ## ---------------------------------------------------------
  ## List / range / name parsers
  ## ---------------------------------------------------------

  defp parse_list(string, field, range) do
    string
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_part(part, field, range) do
        {:ok, list} -> {:cont, {:ok, acc ++ list}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, []} ->
        {:error, CronError.exception(field: field, value: string, reason: "empty field")}

      {:ok, list} ->
        {:ok, list |> Enum.uniq() |> Enum.sort()}

      err ->
        err
    end
  end

  defp parse_list_with_names(string, field, range, names) do
    string
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_part_with_names(part, field, range, names) do
        {:ok, list} -> {:cont, {:ok, acc ++ list}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, list |> Enum.uniq() |> Enum.sort()}
      err -> err
    end
  end

  defp parse_part_with_names(part, field, range, names) do
    cond do
      Map.has_key?(names, String.downcase(part)) ->
        {:ok, [Map.fetch!(names, String.downcase(part))]}

      String.contains?(part, "-") and not step?(part) ->
        parse_named_range(part, field, range, names)

      true ->
        parse_part(part, field, range)
    end
  end

  defp parse_named_range(part, field, range, names) do
    case String.split(part, "-", parts: 2) do
      [a, b] ->
        with {:ok, from} <- name_or_int(a, names, field, range),
             {:ok, to} <- name_or_int(b, names, field, range) do
          {:ok, Enum.to_list(from..to)}
        end

      _ ->
        parse_part(part, field, range)
    end
  end

  defp step?(part), do: String.contains?(part, "/")

  defp name_or_int(string, names, field, range) do
    down = String.downcase(string)

    case Map.fetch(names, down) do
      {:ok, int} -> {:ok, int}
      :error -> parse_int(string, field, range)
    end
  end

  # Parse one comma-separated part: `N`, `N-M`, `*/S`, `N-M/S`, `*`.
  defp parse_part(part, field, range) do
    case String.split(part, "/") do
      [spec] ->
        parse_range(spec, field, range)

      [spec, step_str] ->
        with {:ok, base} <- parse_step_lhs(spec, field, range),
             {:ok, step} <- parse_int(step_str, field, 1..(range.last - range.first + 1)) do
          {:ok, Enum.take_every(base, step)}
        end

      _other ->
        {:error,
         CronError.exception(
           field: field,
           value: part,
           reason: "Malformed field (multiple `/`): #{inspect(part)}"
         )}
    end
  end

  defp parse_step_lhs("*", _field, range), do: {:ok, Enum.to_list(range)}

  defp parse_step_lhs(spec, field, range) do
    if String.contains?(spec, "-") do
      parse_range(spec, field, range)
    else
      with {:ok, [n]} <- parse_range(spec, field, range) do
        {:ok, Enum.to_list(n..range.last)}
      end
    end
  end

  defp parse_range(spec, field, range) do
    case String.split(spec, "-", parts: 2) do
      [only] ->
        with {:ok, int} <- parse_int(only, field, range), do: {:ok, [int]}

      [a, b] ->
        with {:ok, from} <- parse_int(a, field, range),
             {:ok, to} <- parse_int(b, field, range) do
          {:ok, range_values(from, to, range)}
        end
    end
  end

  defp range_values(from, to, _range) when from <= to, do: Enum.to_list(from..to)

  # Wrap-around range — common cron dialect.
  defp range_values(from, to, range),
    do: Enum.to_list(from..range.last) ++ Enum.to_list(range.first..to)

  defp parse_int(string, field, range) do
    case Integer.parse(string) do
      {int, ""} ->
        if int in range do
          {:ok, int}
        else
          {:error,
           CronError.exception(
             field: field,
             value: string,
             reason: "Value #{int} is outside the valid range #{inspect(range)} for #{field}"
           )}
        end

      _ ->
        {:error,
         CronError.exception(
           field: field,
           value: string,
           reason: "Expected an integer for #{field}, got #{inspect(string)}"
         )}
    end
  end

  ## ---------------------------------------------------------
  ## Day-of-week parsing — names, L, #, ranges
  ## ---------------------------------------------------------

  defp parse_dow(string) do
    string
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_dow_part(part) do
        {:ok, entries} -> {:cont, {:ok, acc ++ entries}}
        err -> {:halt, err}
      end
    end)
  end

  defp parse_dow_part(part) do
    cond do
      # `5L` → last Friday
      String.ends_with?(part, "L") and part != "L" ->
        prefix = String.slice(part, 0..-2//1)

        with {:ok, day} <- dow_to_rfc(prefix, part), do: {:ok, [{-1, day}]}

      # `5#2` → second Friday
      String.contains?(part, "#") ->
        parse_dow_nth(part)

      # Step on day-of-week, e.g. `MON-FRI/2`, `5/2`, `0/3`, `*/2`.
      # The step iterates in *cron* numbering (Sunday = 0, the week
      # start) so a Sunday LHS participates correctly, then each
      # result is mapped to RFC (Sunday = 7, the week end), sorted,
      # and de-duplicated (0 and 7 both being Sunday).
      String.contains?(part, "/") ->
        [lhs, step_str] = String.split(part, "/", parts: 2)

        with {:ok, base} <- dow_step_cron_base(lhs),
             {:ok, step} <- parse_int(step_str, :day_of_week, 1..7) do
          entries =
            base
            |> Enum.take_every(step)
            |> Enum.map(&cron_to_rfc/1)
            |> Enum.uniq()
            |> Enum.sort()
            |> Enum.map(&{nil, &1})

          {:ok, entries}
        end

      # Range: `MON-FRI` or `1-5`
      String.contains?(part, "-") ->
        parse_dow_range(part)

      true ->
        with {:ok, day} <- dow_to_rfc(part, part), do: {:ok, [{nil, day}]}
    end
  end

  defp parse_dow_range(part) do
    [a, b] = String.split(part, "-", parts: 2)

    with {:ok, from} <- dow_to_rfc(a, part),
         {:ok, to} <- dow_to_rfc(b, part) do
      {:ok, Enum.map(dow_range_days(from, to), &{nil, &1})}
    end
  end

  defp dow_range_days(from, to) when from <= to, do: Enum.to_list(from..to)
  defp dow_range_days(from, _to), do: Enum.to_list(from..7)

  # `5#2` → the 2nd Friday: a {day, ordinal} pair.
  defp parse_dow_nth(part) do
    case String.split(part, "#") do
      [day_str, ord_str] ->
        with {:ok, day} <- dow_to_rfc(day_str, part),
             {:ok, ordinal} <- parse_int(ord_str, :day_of_week, -53..53) do
          {:ok, [{ordinal, day}]}
        end

      _ ->
        {:error,
         CronError.exception(
           field: :day_of_week,
           value: part,
           reason: "Malformed `#`: #{inspect(part)}"
         )}
    end
  end

  # The cron-numbered base list a day-of-week step iterates over.
  # `*` spans the whole week (0..7); a bare day spans from that day
  # to cron's inclusive max (7); a range spans its own bounds. Values
  # stay in cron numbering (0 = Sunday); the caller maps to RFC.
  defp dow_step_cron_base("*"), do: {:ok, Enum.to_list(0..7)}

  defp dow_step_cron_base(lhs) do
    if String.contains?(lhs, "-") do
      [a, b] = String.split(lhs, "-", parts: 2)

      with {:ok, from} <- dow_to_cron(a, lhs),
           {:ok, to} <- dow_to_cron(b, lhs) do
        {:ok, Enum.to_list(from..to)}
      end
    else
      with {:ok, day} <- dow_to_cron(lhs, lhs), do: {:ok, Enum.to_list(day..7)}
    end
  end

  # Parse a cron day-of-week token (name or number) to its cron
  # number (0 = Sunday .. 6 = Saturday, 7 = Sunday), without the RFC
  # conversion — used while expanding a step in cron space.
  defp dow_to_cron(string, orig) do
    down = String.downcase(string)

    if Map.has_key?(@dow_names, down) do
      {:ok, Map.fetch!(@dow_names, down)}
    else
      case Integer.parse(string) do
        {int, ""} when int in 0..7 ->
          {:ok, int}

        _ ->
          {:error,
           CronError.exception(
             field: :day_of_week,
             value: orig,
             reason: "Invalid day-of-week: #{inspect(orig)}"
           )}
      end
    end
  end

  # Cron: 0 = Sunday, 1..6 = Mon..Sat, 7 = Sunday. Also SUN..SAT.
  # RFC 5545: 1..7 = Mon..Sun.
  defp dow_to_rfc(string, orig) do
    down = String.downcase(string)

    if Map.has_key?(@dow_names, down) do
      {:ok, cron_to_rfc(Map.fetch!(@dow_names, down))}
    else
      case Integer.parse(string) do
        {int, ""} when int in 0..7 ->
          {:ok, cron_to_rfc(int)}

        _ ->
          {:error,
           CronError.exception(
             field: :day_of_week,
             value: orig,
             reason: "Invalid day-of-week: #{inspect(orig)}"
           )}
      end
    end
  end

  defp cron_to_rfc(0), do: 7
  defp cron_to_rfc(7), do: 7
  defp cron_to_rfc(n) when n in 1..6, do: n
end
