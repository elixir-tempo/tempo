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

  `parse/2` reads a rule.

  """

  alias Tempo.ParseError
  alias Tempo.Reader.DateRule
  alias Tempo.Reader.DateRule.{Expression, Plan}

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

  ### Returns

  * `{:ok, expression}`, a `t:Tempo.t/0`: a yearly recurrence, a recurrence
    set of a date and its observed days, or a conditional member for a rule
    that depends on other dates. An observed day carries
    `%{substitute: true}` in its metadata.

  * `{:error, %Tempo.ParseError{}}` for a rule that cannot be read, naming
    where reading stopped or which part is not read.

  ### Examples

      iex> {:ok, rule} = Tempo.DateRule.parse("12-25")
      iex> Tempo.to_iso8601(rule)
      {:ok, "R/../P1Y/FL12M25DN"}

      iex> {:ok, rule} = Tempo.DateRule.parse("2nd Monday in June")
      iex> Tempo.to_iso8601(rule)
      {:ok, "R/../P1Y/FL6M1K2IN"}

      iex> {:error, %Tempo.ParseError{rest: "a full moon"}} = Tempo.DateRule.parse("12-25 on a full moon")

  """
  @spec parse(String.t(), keyword()) :: {:ok, Tempo.t()} | {:error, ParseError.t()}
  def parse(rule, options \\ [])

  def parse(rule, options) when is_binary(rule) and is_list(options) do
    with {:ok, tokens} <- tokens(rule),
         {:ok, plan} <- part(Plan.plan(tokens), rule) do
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
