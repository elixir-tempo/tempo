defmodule Tempo.Cron do
  @moduledoc """
  Reads cron expressions into Tempo recurrences: the firings a schedule
  names, as the recurrence an `RRULE` or an ISO 8601-2 repeat rule reads to.

  Five fields are `minute hour day-of-month month day-of-week`; six put a
  seconds field first; seven add a year last. A field is `*`, a number, a
  list `1,15`, a range `1-5`, or a step `*/15`, `1-5/2`; months and days of
  the week may be named (`JAN`, `MON`); Sunday is `0` or `7`. The aliases
  `@yearly`, `@annually`, `@monthly`, `@weekly`, `@daily`, `@midnight` and
  `@hourly` are read. Each restricted field is a part of the recurrence's
  rule, the cadence is the unit above the coarsest restricted field, and
  the finer fields left as `*` fire every value: `0 9 * * *` is daily at
  nine, `*/15 * * * *` is four times an hour. When both the day of the
  month and the day of the week are restricted, POSIX fires on either, so
  the result is a set of two recurrences.

  The extensions of Vixie cron and Quartz are read in the two day fields:

  * `L` as the day of the month is its last day, and `LW` its last weekday.

  * `15W` is the weekday nearest the 15th, in the same month: the Friday
    before a Saturday, the Monday after a Sunday. `1W` to `27W` are read;
    for a day a short month may not have, which is the nearest weekday
    depends on the month's length, and `28W` to `31W` are refused.

  * `5L` as the day of the week is the last Friday of the month, and `5#2`
    its second Friday.

  Each is one value, never a member of a list or a range.

  """

  alias Tempo.Options
  alias Tempo.RRule
  alias Tempo.Validate

  @aliases %{
    "@yearly" => "0 0 1 1 *",
    "@annually" => "0 0 1 1 *",
    "@monthly" => "0 0 1 * *",
    "@weekly" => "0 0 * * 0",
    "@daily" => "0 0 * * *",
    "@midnight" => "0 0 * * *",
    "@hourly" => "0 * * * *"
  }
  @months ~w(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC)
  @days ~w(SUN MON TUE WED THU FRI SAT)
  @fields [second: 0..59, minute: 0..59, hour: 0..23, day: 1..31, month: 1..12, day_of_week: 0..7]
  @weekdays [1, 2, 3, 4, 5]

  @doc """
  Reads a cron expression into a recurrence.

  ### Arguments

  * `expression` is the cron text, five to seven fields or an alias.

  * `options` is a keyword list of options.

  ### Options

  * `:from` is the first instant firings are counted from, a
    `t:Tempo.t/0` with a date. With none the rule has no start, as cron
    gives it none, and its firings are asked for in a window (`:within`).

  * `:metadata` is a map carried on the recurrence and every firing.

  ### Returns

  * `{:ok, recurrence}`, a `t:Tempo.t/0` of the `:every` form, or of the
    `:all` form holding two when both the day of the month and the day of
    the week are restricted.

  * `{:error, %ArgumentError{}}` for text that is not a cron expression.

  ### Examples

      iex> {:ok, nine} = Tempo.Cron.parse("0 9 * * 1-5", from: ~o"2026-06-01")
      iex> Tempo.to_iso8601(nine)
      {:ok, "R/2026Y6M1D/P1M/FL{1,2,3,4,5}KT9H0MN"}

      iex> {:ok, quarter_hours} = Tempo.Cron.parse("*/15 * * * *", from: ~o"2026-06-01T00:00:00")
      iex> quarter_hours |> Tempo.to_interval!(within: ~o"2026-06-01T00") |> Tempo.IntervalSet.count()
      4

      iex> {:ok, mondays} = Tempo.Cron.parse("0 9 * * 1")
      iex> Tempo.to_iso8601(mondays)
      {:ok, "R/../P1M/FL1KT9H0MN"}

      iex> {:error, %ArgumentError{}} = Tempo.Cron.parse("@reboot")

  """
  @spec parse(String.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def parse(expression, options \\ []) when is_binary(expression) do
    with :ok <- Options.check(options, [:from, :metadata], "Tempo.Cron.parse/2"),
         {:ok, fields} <- fields(String.trim(expression)),
         {:ok, parsed} <- parse_fields(fields) do
      recurrences(parsed, options)
    end
  end

  @doc """
  `parse/2`, returning the recurrence or raising.

  ### Examples

      iex> "0 0 1 1 *" |> Tempo.Cron.parse!(from: ~o"2026-01-01") |> Tempo.to_interval!(within: ~o"2026/2027") |> Tempo.IntervalSet.count()
      2

  """
  @spec parse!(String.t(), keyword()) :: Tempo.t()
  def parse!(expression, options \\ []) do
    case parse(expression, options) do
      {:ok, recurrence} -> recurrence
      {:error, exception} -> raise exception
    end
  end

  # ── Fields ────────────────────────────────────────────────────────────

  defp fields("@" <> _ = alias) do
    case Map.fetch(@aliases, String.downcase(alias)) do
      {:ok, expanded} -> fields(expanded)
      :error -> {:error, argument("#{inspect(alias)} is not a cron alias")}
    end
  end

  defp fields(expression) do
    case String.split(expression) do
      [mi, h, dom, mo, dow] ->
        {:ok, [minute: mi, hour: h, day: dom, month: mo, day_of_week: dow]}

      [s, mi, h, dom, mo, dow] ->
        {:ok, [second: s, minute: mi, hour: h, day: dom, month: mo, day_of_week: dow]}

      [s, mi, h, dom, mo, dow, y] ->
        {:ok, [second: s, minute: mi, hour: h, day: dom, month: mo, day_of_week: dow, year: y]}

      _ ->
        {:error,
         argument("a cron expression has five to seven fields, not #{inspect(expression)}")}
    end
  end

  defp parse_fields(fields) do
    Enum.reduce_while(fields, {:ok, []}, fn {name, text}, {:ok, acc} ->
      case field(name, text) do
        {:ok, values} -> {:cont, {:ok, acc ++ [{name, values}]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # A field's values, or :any for `*`.
  defp field(_name, "*"), do: {:ok, :any}
  defp field(_name, "?"), do: {:ok, :any}

  defp field(:year, text), do: listed(text, 1..9999, &named(:year, &1))

  # The last day of the month, its last weekday, and the weekday nearest a day.
  defp field(:day, "L"), do: {:ok, [-1]}
  defp field(:day, "LW"), do: {:ok, {:either, [%{byday: weekdays(), bysetpos: [-1]}]}}

  defp field(:day, text) when binary_part(text, byte_size(text), -1) == "W" do
    case Integer.parse(text) do
      {day, "W"} when day in 1..27 -> {:ok, {:either, nearest_weekday(day)}}
      {day, "W"} when day in 28..31 -> {:error, argument(not_in_every_month(text))}
      _ -> {:error, argument("#{inspect(text)} is not a cron field value")}
    end
  end

  # The last of a weekday in the month (`5L`), and the nth (`5#2`).
  defp field(:day_of_week, text) do
    case Regex.run(~r/\A([0-7]|[A-Za-z]{3})(L|#([1-5]))\z/, text) do
      [_, day, "L"] -> numbered(day, -1, text)
      [_, day, _, nth] -> numbered(day, String.to_integer(nth), text)
      nil -> plain_field(:day_of_week, text)
    end
  end

  defp field(name, text), do: plain_field(name, text)

  defp numbered(day, nth, text) do
    case named(:day_of_week, day) do
      {:ok, day} when day in 0..7 ->
        {:ok, {:either, [%{byday: [{nth, sunday(:day_of_week, day)}]}]}}

      _ ->
        {:error, argument("#{inspect(text)} is not a cron field value")}
    end
  end

  defp weekdays, do: Enum.map(@weekdays, &{nil, &1})

  # The weekday nearest a day of the month, which is one of three days: the
  # day itself when it is a weekday, the Friday before it when it is a
  # Saturday, the Monday after it when it is a Sunday. From the 1st there is
  # no Friday before in the month, so a Saturday the 1st gives Monday the 3rd.
  defp nearest_weekday(1) do
    [
      %{bymonthday: [1], byday: weekdays()},
      %{bymonthday: [2], byday: [{nil, 1}]},
      %{bymonthday: [3], byday: [{nil, 1}]}
    ]
  end

  defp nearest_weekday(day) do
    [
      %{bymonthday: [day], byday: weekdays()},
      %{bymonthday: [day - 1], byday: [{nil, 5}]},
      %{bymonthday: [day + 1], byday: [{nil, 1}]}
    ]
  end

  defp not_in_every_month(text) do
    "#{inspect(text)} is not read: the weekday nearest a day that a short month may not " <>
      "have depends on the month's length. 1W to 27W and LW are read"
  end

  defp plain_field(name, text) do
    range = Keyword.fetch!(@fields, name)

    with {:ok, values} <- listed(text, range, &named(name, &1)) do
      {:ok, values |> Enum.map(&sunday(name, &1)) |> Enum.uniq() |> Enum.sort()}
    end
  end

  defp listed(text, range, read) do
    text
    |> String.split(",")
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case item(item, range, read) do
        {:ok, values} -> {:cont, {:ok, acc ++ values}}
        :error -> {:halt, {:error, argument("#{inspect(item)} is not a cron field value")}}
      end
    end)
  end

  defp item(item, range, read) do
    {body, step} =
      case String.split(item, "/", parts: 2) do
        [body, step] -> {body, step}
        [body] -> {body, "1"}
      end

    case {Integer.parse(step), bounds(body, range, read)} do
      {{step, ""}, {:ok, first, last}} when step > 0 -> {:ok, Enum.to_list(first..last//step)}
      _ -> :error
    end
  end

  defp bounds("*", range, _read), do: {:ok, range.first, range.last}

  defp bounds(body, range, read) do
    case String.split(body, "-", parts: 2) do
      [one] ->
        with {:ok, n} <- read.(one), do: in_range(n, n, range)

      [a, b] ->
        with {:ok, first} <- read.(a), {:ok, last} <- read.(b), do: in_range(first, last, range)
    end
  end

  defp in_range(first, last, range) when first <= last,
    do: if(first in range and last in range, do: {:ok, first, last}, else: :error)

  defp in_range(_first, _last, _range), do: :error

  defp named(name, text) do
    case Integer.parse(text) do
      {n, ""} -> {:ok, n}
      _ -> name_index(name, String.upcase(text))
    end
  end

  defp name_index(:month, text) do
    case Enum.find_index(@months, &(&1 == text)) do
      nil -> :error
      index -> {:ok, index + 1}
    end
  end

  defp name_index(:day_of_week, text) do
    case Enum.find_index(@days, &(&1 == text)) do
      nil -> :error
      index -> {:ok, index}
    end
  end

  defp name_index(_name, _text), do: :error

  # Cron's Sunday, 0 or 7, as ISO 8601's 7.
  defp sunday(:day_of_week, 0), do: 7
  defp sunday(_name, value), do: value

  # ── Recurrences ───────────────────────────────────────────────────────

  # Restricted fields are the rule's parts and the finer unrestricted ones
  # fire every value; the cadence is one unit above the coarsest restricted
  # field. A day of the month and a day of the week both restricted fire on either.
  defp recurrences(fields, options) do
    {year, fields} = Keyword.pop(fields, :year)
    {dom, fields} = Keyword.pop(fields, :day)
    {dow, fields} = Keyword.pop(fields, :day_of_week)

    with {:ok, built} <- each_recurrence(days(dom, dow), fields, year, options) do
      one_or_all(built)
    end
  end

  # The ways a firing's day is named, each a recurrence of its own: one
  # where the two day fields agree on what they restrict, one for each field
  # where both are restricted (POSIX fires on either), and one for each day
  # an extension may fall on.
  defp days({:either, by_month}, {:either, by_week}), do: by_month ++ by_week
  defp days({:either, by_month}, :any), do: by_month
  defp days(:any, {:either, by_week}), do: by_week
  defp days({:either, by_month}, dow), do: by_month ++ [[day_of_week: dow]]
  defp days(dom, {:either, by_week}), do: [[day: dom]] ++ by_week
  defp days(dom, dow) when dom != :any and dow != :any, do: [[day: dom], [day_of_week: dow]]
  defp days(dom, dow), do: [[day: dom, day_of_week: dow]]

  defp each_recurrence(days, fields, year, options) do
    Enum.reduce_while(days, {:ok, []}, fn day, {:ok, built} ->
      case recurrence(fields, day, year, options) do
        {:ok, recurrence} -> {:cont, {:ok, built ++ [recurrence]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp one_or_all([one]), do: {:ok, one}

  defp one_or_all([first | _] = several),
    do: {:ok, %Tempo{form: {:all, several}, calendar: first.calendar, metadata: first.metadata}}

  # A day an extension names is a part of the rule as RFC 5545 writes it,
  # and stands as a restricted day of the month for the cadence.
  defp recurrence(fields, %{} = day, year, options) do
    rule(fields ++ [day: :extension], day, year, options)
  end

  defp recurrence(fields, day, year, options), do: rule(fields ++ day, %{}, year, options)

  defp rule(fields, day, year, options) do
    restricted = Enum.reject(fields, fn {_, values} -> values == :any end)
    finest = fields |> hd() |> elem(0)
    coarsest = restricted |> Enum.map(&elem(&1, 0)) |> Enum.max_by(&order/1, fn -> finest end)
    cadence = if restricted == [], do: finest, else: cadence_above(coarsest, restricted)

    parts =
      fields
      |> Enum.reject(&(unconstrained?(&1, restricted) or match?({:day, :extension}, &1)))
      |> Enum.filter(fn {name, _} -> order(name) <= order(coarsest) end)
      |> Enum.map(fn
        {name, :any} -> {name, Enum.to_list(Keyword.fetch!(@fields, name))}
        {name, values} -> {name, values}
      end)
      |> Enum.sort_by(fn {name, _} -> -order(name) end)
      |> Enum.map(fn {name, values} ->
        {name, if(match?([_], values), do: hd(values), else: values)}
      end)
      |> with_years(year)
      |> then(&if(restricted == [], do: [], else: &1))

    rule = %{freq: cadence} |> Map.merge(parts_as_rule(parts)) |> Map.merge(day)

    rule
    |> RRule.from_rule(options)
    |> day_before_times()
  end

  # The last weekday of a month is found among its days, and the times of
  # day are times on it: where a position would count among the times too,
  # the day is selected first.
  defp day_before_times({:ok, %Tempo{form: {:every, first, bound, parts}} = recurrence})
       when is_list(parts) do
    {times, days} = Enum.split_with(parts, fn {unit, _} -> unit in [:hour, :minute, :second] end)

    case {Keyword.pop(days, :instance), times} do
      {{nil, _days}, _times} ->
        {:ok, recurrence}

      {_positioned, []} ->
        {:ok, recurrence}

      {{position, days}, times} ->
        {before, [weekdays]} = Enum.split_with(days, fn {unit, _} -> unit != :day_of_week end)
        nested = [selection: [weekdays, instance: position]]
        Validate.run(%{recurrence | form: {:every, first, bound, before ++ nested ++ times}})
    end
  end

  defp day_before_times(read), do: read

  # A `*` day of the week constrains nothing, and a `*` day of the month
  # constrains nothing beside a restricted day of the week.
  defp unconstrained?({:day_of_week, :any}, _restricted), do: true
  defp unconstrained?({:day, :any}, restricted), do: Keyword.has_key?(restricted, :day_of_week)
  defp unconstrained?(_field, _restricted), do: false

  defp order(:second), do: 0
  defp order(:minute), do: 1
  defp order(:hour), do: 2
  defp order(:day), do: 3
  defp order(:day_of_week), do: 3
  defp order(:month), do: 4

  defp cadence_above(:second, _restricted), do: :minute
  defp cadence_above(:minute, _), do: :hour
  defp cadence_above(:hour, _), do: :day
  defp cadence_above(:day, _), do: :month
  defp cadence_above(:day_of_week, _), do: :month
  defp cadence_above(:month, _), do: :year

  defp with_years(parts, nil), do: parts
  defp with_years(parts, :any), do: parts
  defp with_years(parts, years), do: [{:year, years} | parts]

  # The parts in RRule's vocabulary, which lowers them with the same code.
  defp parts_as_rule(parts) do
    Map.new(parts, fn
      {:year, v} -> {:byyear, List.wrap(v)}
      {:month, v} -> {:bymonth, List.wrap(v)}
      {:day, v} -> {:bymonthday, List.wrap(v)}
      {:day_of_week, v} -> {:byday, Enum.map(List.wrap(v), &{nil, &1})}
      {:hour, v} -> {:byhour, List.wrap(v)}
      {:minute, v} -> {:byminute, List.wrap(v)}
      {:second, v} -> {:bysecond, List.wrap(v)}
    end)
  end

  defp argument(message), do: ArgumentError.exception(message)
end
