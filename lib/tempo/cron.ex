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

  The Vixie extensions `L`, `W` and `#` are not read.

  """

  alias Tempo.RRule

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
  @reference "2000-01-01T00:00"

  @doc """
  Reads a cron expression into a recurrence.

  ### Arguments

  * `expression` is the cron text, five to seven fields or an alias.

  * `options` is a keyword list of options.

  ### Options

  * `:from` is the first instant firings are counted from, a
    `t:Tempo.t/0` with a date; the default is the first minute of 2000.

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

      iex> {:error, %ArgumentError{}} = Tempo.Cron.parse("@reboot")

  """
  @spec parse(String.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def parse(expression, options \\ []) when is_binary(expression) do
    with {:ok, fields} <- fields(String.trim(expression)),
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

  defp field(name, text) do
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

    case {dom, dow} do
      {dom, dow} when dom != :any and dow != :any ->
        with {:ok, a} <- recurrence(fields ++ [day: dom], year, options),
             {:ok, b} <- recurrence(fields ++ [day_of_week: dow], year, options) do
          {:ok, %Tempo{form: {:all, [a, b]}, calendar: a.calendar, metadata: a.metadata}}
        end

      _ ->
        recurrence(fields ++ [day: dom, day_of_week: dow], year, options)
    end
  end

  defp recurrence(fields, year, options) do
    restricted = Enum.reject(fields, fn {_, values} -> values == :any end)
    finest = fields |> hd() |> elem(0)
    coarsest = restricted |> Enum.map(&elem(&1, 0)) |> Enum.max_by(&order/1, fn -> finest end)
    cadence = if restricted == [], do: finest, else: cadence_above(coarsest, restricted)

    parts =
      fields
      |> Enum.reject(&unconstrained?(&1, restricted))
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

    rule = Map.merge(%{freq: cadence}, parts_as_rule(parts))

    RRule.from_rule(rule, Keyword.put_new(options, :from, Tempo.from_iso8601!(@reference)))
  end

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
