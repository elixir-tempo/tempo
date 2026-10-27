defmodule Tempo.DateRule do
  @moduledoc """
  Reads date rules: the yearly dates people write, `2nd Monday in June`,
  `Friday after 4th Thursday in November`, `easter -2`, `15 Nisan`, `chinese
  01-0-01`, `march equinox in Asia/Tokyo`, into the Tempo recurrences they
  mean.

  The grammar is the one [date-holidays](https://github.com/commenthol/date-holidays)
  writes its holidays in, read as its parser,
  [date-holidays-parser](https://github.com/commenthol/date-holidays-parser),
  reads it: a fixed date, a weekday step from one, Easter, an equinox or a
  solstice, a date in the Islamic, Hebrew, Persian, Julian, Chinese, Korean
  or Vietnamese calendar, with a span, an observed day (`and if sunday then
  next monday`), year and weekday filters, `since` and `prior to`. ISO 8601-2
  and RFC 5545's `RRULE` (`Tempo.RRule`) say the same things in forms made
  for machines to exchange; a date rule is the form people write.

  `parse/2` reads a rule, and `parse!/2` raises its error. The
  [date rules guide](date-rules.md) takes the grammar part by part, with the
  dates each part falls on.

  A part of the grammar the reading does not take returns an error naming
  it: the Bengali calendar, a year of the sexagenary cycle, `if equal`, and
  an `if is holiday` move by more than one or back.

  """

  alias Tempo.{Options, ParseError}
  alias Tempo.Reader.DateRule
  alias Tempo.Reader.DateRule.{Expression, Plan}

  @options [:falls_on, :observed, :active, :disable, :enable, :replaced_by]
  @observed [:as_written, :moved, :none]

  @doc """
  Reads a date rule into the Tempo recurrence it means.

  ### Arguments

  * `rule` is a date rule, such as `"2nd Monday in June"`.

  * `options` is a keyword list of options.

  ### Options

  * `:falls_on` is what a rule that depends on other dates is decided
    against (a bridge, `09-22 if 09-21 is holiday`, or a move, `if is holiday
    then next monday`): a map the metadata of another member of a set holds.
    The default is `%{type: type}`, the type the rule names, `:public` where
    it names none.

  * `:observed` is how a rule's observed days are read: `:as_written` (the
    default); `:moved`, each clause moving the date, so that `and if sunday
    then next monday` gives the Monday in place of a Sunday rather than
    beside it; or `:none`, the date with no observed day, which for a rule
    that begins `substitutes` is the date on the weekdays it substitutes for.

  * `:active` is a list of `{from, to}` windows of `t:Date.t/0`, `from`
    included and `to` not, either `nil` for an open end: the rule falls in
    the years whose date is in one of them, and within its own `since` and
    `prior to`, as date-holidays' `active` periods say.

  * `:disable` is a list of `t:Date.t/0` the rule's date is moved from:
    where one is the rule's date in its year, that year's date is left out.

  * `:enable` is a list of `t:Date.t/0` added in the year of a disabled
    date, the day a holiday is moved to.

  * `:replaced_by` is a list of rules that begin `substitutes`, each alone
    or as `{rule, active: windows}`, that may stand in for the rule's date:
    one of the same date, gated by its years alone, takes its trigger
    weekdays from a rule that is a plain date with no observed day of its
    own, in the years it is in force. The others are passed over, so the
    `substitutes` entries of a dataset may be given to each of its rules.

  ### Returns

  * `{:ok, expression}`, a `t:Tempo.t/0`: a yearly recurrence, a recurrence
    set of a date and its observed days, or a conditional member for a rule
    that depends on other dates. An observed day carries
    `%{substitute: true}` in its metadata.

  * `{:error, %Tempo.ParseError{}}` for a rule that cannot be read, naming
    where reading stopped or which part is not read, or

  * `{:error, exception}` for a date the rule names that its calendar does
    not have, such as a `Tempo.InvalidDateError` for the month of `13-01`.

  ### Examples

      iex> {:ok, rule} = Tempo.DateRule.parse("12-25")
      iex> Tempo.to_iso8601(rule)
      {:ok, "R/../P1Y/FL12M25DN"}

      iex> {:ok, rule} = Tempo.DateRule.parse("2nd Monday in June")
      iex> Tempo.to_iso8601(rule)
      {:ok, "R/../P1Y/FL6M1K2IN"}

      iex> {:ok, new_years_day} = Tempo.DateRule.parse("01-01 and if sunday then next monday", observed: :none)
      iex> Tempo.to_iso8601(new_years_day)
      {:ok, "R/../P1Y/FL1M1DN"}

      iex> {:error, %Tempo.ParseError{rest: "a full moon"}} = Tempo.DateRule.parse("12-25 on a full moon")

  """
  @spec parse(String.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def parse(rule, options \\ [])

  def parse(rule, options) when is_binary(rule) do
    with :ok <- Options.check(options, @options, "Tempo.DateRule.parse/2"),
         {:ok, observed} <- observed(options),
         {:ok, dated} <- dated(options),
         {:ok, replaced_by} <- replaced_by(Keyword.get(options, :replaced_by, [])),
         {:ok, tokens} <- tokens(rule),
         {:ok, plan} <- part(Plan.plan(tokens), rule) do
      plan =
        plan
        |> Plan.observed(observed)
        |> Plan.dated(dated)
        |> Plan.replaced_by(replaced_by)

      part(Expression.build(plan, options), rule)
    end
  end

  def parse(rule, _options) do
    {:error,
     ParseError.exception(text: inspect(rule), reason: "a date rule is text", as: "a date rule")}
  end

  @doc """
  `parse/2`, returning its answer or raising the error.

  ### Arguments

  * The arguments are those of `parse/2`.

  ### Returns

  * What `parse/2` returns as `{:ok, answer}`, the answer alone. The error it
    returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.DateRule.parse!("easter -2")
      ...> |> Tempo.to_iso8601!()
      "R/../P1Y/FLL(easter)eN/P-3D5K1IN"

  """
  @spec parse!(String.t(), keyword()) :: Tempo.t()
  def parse!(rule, options \\ []) do
    case parse(rule, options) do
      {:ok, expression} -> expression
      {:error, exception} -> raise exception
    end
  end

  defp observed(options) do
    observed = Keyword.get(options, :observed, :as_written)

    if observed in @observed do
      {:ok, observed}
    else
      message = ":observed is :as_written, :moved or :none, not #{inspect(observed)}"
      {:error, ArgumentError.exception(message)}
    end
  end

  # The windows a rule is active in and the dates it is moved from and to,
  # each date in the ISO calendar.
  defp dated(options) do
    with {:ok, active} <- windows(Keyword.get(options, :active, [])),
         {:ok, disable} <- dates(:disable, Keyword.get(options, :disable, [])),
         {:ok, enable} <- dates(:enable, Keyword.get(options, :enable, [])) do
      {:ok, %{active: active, disable: disable, enable: enable}}
    end
  end

  # The plans of the `substitutes` entries that may stand in for the rule,
  # each with the windows it is active in.
  defp replaced_by(entries) when is_list(entries) do
    reduce_ok(entries, &replacing_entry/1)
  end

  defp replaced_by(other) do
    {:error, ArgumentError.exception(":replaced_by is a list of rules, not #{inspect(other)}")}
  end

  defp replacing_entry(entry) when is_binary(entry) do
    replacing_entry({entry, []})
  end

  defp replacing_entry({entry, entry_options}) when is_binary(entry) do
    with :ok <- Options.check(entry_options, [:active], "a :replaced_by entry"),
         {:ok, active} <- windows(Keyword.get(entry_options, :active, [])),
         {:ok, tokens} <- tokens(entry),
         {:ok, plan} <- part(Plan.plan(tokens), entry) do
      {:ok, Plan.dated(plan, %{active: active, disable: [], enable: []})}
    end
  end

  defp replacing_entry(other) do
    message = ":replaced_by takes rules, or {rule, active: windows}, not #{inspect(other)}"
    {:error, ArgumentError.exception(message)}
  end

  defp windows(windows) when is_list(windows) do
    reduce_ok(windows, &window/1)
  end

  defp windows(other) do
    {:error, ArgumentError.exception(":active is a list of windows, not #{inspect(other)}")}
  end

  defp window({from, to} = window) do
    with {:ok, from} <- bound(from, window),
         {:ok, to} <- bound(to, window) do
      {:ok, {from, to}}
    end
  end

  defp window(other) do
    {:error, ArgumentError.exception(":active takes {from, to} windows, not #{inspect(other)}")}
  end

  defp bound(nil, _window) do
    {:ok, nil}
  end

  defp bound(%Date{} = date, window) do
    iso_date(date, window)
  end

  defp bound(_other, window) do
    message = "an :active window's ends are dates or nil, not #{inspect(window)}"
    {:error, ArgumentError.exception(message)}
  end

  defp dates(option, dates) when is_list(dates) do
    reduce_ok(dates, &option_date(option, &1))
  end

  defp dates(option, other) do
    {:error,
     ArgumentError.exception("#{inspect(option)} is a list of dates, not #{inspect(other)}")}
  end

  defp option_date(_option, %Date{} = date) do
    iso_date(date, date)
  end

  defp option_date(option, other) do
    {:error, ArgumentError.exception("#{inspect(option)} takes dates, not #{inspect(other)}")}
  end

  defp iso_date(date, given) do
    case Date.convert(date, Calendar.ISO) do
      {:ok, iso} ->
        {:ok, iso}

      {:error, _reason} ->
        {:error, ArgumentError.exception("#{inspect(given)} has no ISO date")}
    end
  end

  defp reduce_ok(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, &collected(fun.(&1), &2))
    |> reversed()
  end

  defp collected({:ok, item}, {:ok, items}) do
    {:cont, {:ok, [item | items]}}
  end

  defp collected({:error, _exception} = error, _acc) do
    {:halt, error}
  end

  defp reversed({:ok, items}) do
    {:ok, Enum.reverse(items)}
  end

  defp reversed(error) do
    error
  end

  defp tokens(rule) do
    case DateRule.tokens(rule) do
      {:ok, tokens} ->
        {:ok, tokens}

      {:error, {:unread, rest}} ->
        {:error,
         ParseError.exception(
           text: rule,
           rest: rest,
           reason: "not a part of a date rule",
           as: "a date rule"
         )}
    end
  end

  defp part({:ok, value}, _rule) do
    {:ok, value}
  end

  defp part({:error, reason}, rule) when is_binary(reason) do
    {:error, ParseError.exception(text: rule, reason: reason, as: "a date rule")}
  end

  defp part({:error, %{__exception__: true} = exception}, _rule) do
    {:error, exception}
  end
end
