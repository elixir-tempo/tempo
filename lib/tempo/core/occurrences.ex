defmodule Tempo.Occurrences do
  @moduledoc false
  # The occurrences of a calendar event, as iCalendar and JSCalendar both
  # describe one: a start, a length, rules that repeat it, extra dates, and
  # dates and rules that take occurrences away.
  #
  # Each rule is lowered by `Tempo.RRule.from_rule/2` to a recurrence and
  # given its spans by `Tempo.Spans`; the extras are spans of the same length
  # from their own starts; an exclusion removes the occurrence that starts
  # where it does. A rule with no end needs a `:within` window.

  alias Tempo.{ConversionError, Duration, Limit, RRule, Spans}

  @type event :: %{
          required(:from) => Tempo.t(),
          optional(:duration) => Duration.t() | nil,
          optional(:rules) => [RRule.rule()],
          optional(:excluded_rules) => [RRule.rule()],
          optional(:extra) => [Tempo.t()],
          optional(:excluded) => [Tempo.t()],
          optional(:metadata) => map()
        }

  @doc "The occurrences of an event as spans with value ends, in order of start."
  @spec of(event(), keyword()) :: {:ok, [Tempo.t()]} | {:error, Exception.t()}
  def of(%{from: %Tempo{} = from} = event, options \\ []) do
    event =
      Map.merge(
        %{duration: nil, rules: [], excluded_rules: [], extra: [], excluded: [], metadata: %{}},
        event
      )

    with {:ok, included} <- included(event, from, options),
         {:ok, extras} <- each(event.extra, &one(&1, event)),
         {:ok, removed} <- by_rules(event.excluded_rules, event, from, options) do
      excluded = starts(removed) ++ starts(event.excluded)

      {:ok,
       (included ++ extras)
       |> Enum.reject(&(start(&1) in excluded))
       |> Enum.uniq_by(&Spans.extent/1)
       |> Enum.sort_by(&start/1)}
    end
  end

  defp included(%{rules: []} = event, from, _options), do: each([from], &one(&1, event))
  defp included(%{rules: rules} = event, from, options), do: by_rules(rules, event, from, options)

  # One occurrence: the value's own span, or a span of the event's length from it.
  defp one(%Tempo{} = from, %{duration: nil, metadata: metadata}) do
    with {:ok, span} <- Spans.as_span(from), do: {:ok, %{span | metadata: metadata}}
  end

  defp one(%Tempo{} = from, %{duration: %Duration{} = duration, metadata: metadata}) do
    span = %Tempo{
      form: {:span, from, duration},
      calendar: from.calendar,
      zone: from.zone,
      metadata: metadata
    }

    with {:ok, spans} <- Spans.spans(span), do: {:ok, hd(Enum.to_list(spans))}
  end

  defp by_rules(rules, event, from, options) do
    Enum.reduce_while(rules, {:ok, []}, fn rule, {:ok, acc} ->
      case by_rule(rule, event, from, options) do
        {:ok, spans} -> {:cont, {:ok, acc ++ spans}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp by_rule(rule, event, from, options) do
    rule_options = [from: from, duration: event.duration, metadata: event.metadata]

    with {:ok, recurrence} <- RRule.from_rule(rule, rule_options),
         :ok <- bounded(recurrence, options),
         {:ok, spans} <- Spans.spans(recurrence, Keyword.take(options, [:within])),
         {:ok, spans} <- each(Enum.take(spans, Limit.values()), &resolved/1) do
      {:ok, Enum.map(spans, &%{&1 | metadata: event.metadata})}
    end
  end

  defp bounded(%Tempo{form: {:every, _, :infinity, _}} = recurrence, options) do
    if Keyword.has_key?(options, :within),
      do: :ok,
      else: {:error, ConversionError.exception(value: recurrence, reason: :unbounded)}
  end

  defp bounded(_recurrence, _options), do: :ok

  # A span with a duration end as one with value ends.
  defp resolved(%Tempo{form: {:span, _, %Duration{}}} = span) do
    with {:ok, spans} <- Spans.spans(span), do: {:ok, hd(Enum.to_list(spans))}
  end

  defp resolved(span), do: {:ok, span}

  defp each(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, result} -> {:cont, {:ok, acc ++ [result]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp starts(expressions), do: Enum.map(expressions, &start/1)

  defp start(%Tempo{} = expression) do
    case Spans.extent(expression) do
      {:ok, {start, _}} -> start
      _ -> nil
    end
  end

  @doc "The spans of a list that overlap a window, or all of them with no window."
  @spec within([Tempo.t()], Tempo.t() | nil) :: {:ok, [Tempo.t()]} | {:error, Exception.t()}
  def within(spans, nil), do: {:ok, spans}

  def within(spans, %Tempo{} = window) do
    {:ok, Enum.filter(spans, &(Tempo.overlaps?(&1, Spans.window_in(window, &1)) == true))}
  end
end
