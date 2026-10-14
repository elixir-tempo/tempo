defmodule Tempo.Conditions do
  @moduledoc false
  # Members of a set whose occurrences depend on the other members': a
  # bridge day kept only when the days around it are holidays, a holiday
  # moved to the next Monday when it falls on another.
  #
  # A conditional member is a `%Tempo{}` of the `:when` form: its member,
  # and `keep: [at: offsets, falls_on: what]` or `move: [falls_on: what,
  # to_next: selector]`. `what` is a map an other occurrence's metadata must
  # hold, or an expression whose spans are read instead. The set gives its
  # plain members' spans first, and the conditional members are judged
  # against those.

  alias Tempo.{Duration, Limit, Scale, Select, Spans}

  @doc "Whether a set member is conditional on the others."
  @spec conditional?(term()) :: boolean()
  def conditional?(%Tempo{form: {:when, _member, [{kind, _}]}}) when kind in [:keep, :move],
    do: true

  def conditional?(_member), do: false

  @doc "The spans of conditional members, judged against the other members' spans."
  @spec resolve([Tempo.t()], [Tempo.t()], keyword()) ::
          {:ok, [Tempo.t()]} | {:error, Exception.t()}
  def resolve(conditionals, others, options) do
    with {:ok, unmoved} <- unmoved(conditionals, options) do
      conditionals
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, &resolved_beside(&1, &2, others, unmoved, options))
    end
  end

  # Each reads the plain members, and the other conditionals where they
  # stand before they are judged, never where one is moved, nor itself.
  defp resolved_beside({conditional, index}, {:ok, acc}, others, unmoved, options) do
    beside = others ++ (unmoved |> List.delete_at(index) |> List.flatten())

    case resolved(conditional, beside, options) do
      {:ok, spans} -> {:cont, {:ok, acc ++ spans}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp unmoved(conditionals, options) do
    Enum.reduce_while(conditionals, {:ok, []}, fn conditional, {:ok, acc} ->
      case unmoved_spans(conditional, options) do
        {:ok, spans} -> {:cont, {:ok, acc ++ [spans]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp unmoved_spans(%Tempo{form: {:when, member, _}, metadata: metadata}, options) do
    with {:ok, spans} <- Spans.spans(member, options),
         {:ok, spans} <- Limit.take(spans, member),
         do: {:ok, Enum.map(spans, &%{&1 | metadata: Map.merge(metadata, &1.metadata)})}
  end

  defp resolved(
         %Tempo{form: {:when, member, [{kind, conditions}]}, metadata: metadata},
         others,
         options
       ) do
    with {:ok, spans} <- Spans.spans(member, options),
         {:ok, spans} <- Limit.take(spans, member),
         {:ok, falls_on} <- falls_on(conditions[:falls_on], others, options) do
      spans
      |> Enum.flat_map(&judged(kind, &1, conditions, falls_on))
      |> Enum.map(&%{&1 | metadata: Map.merge(metadata, &1.metadata)})
      |> then(&{:ok, &1})
    end
  end

  # The extents an occurrence may fall on: the other occurrences whose
  # metadata holds the map, or the spans of the expression given.
  defp falls_on(%Tempo{} = expression, _others, options) do
    with {:ok, spans} <- Spans.spans(expression, options),
         {:ok, spans} <- Limit.take(spans, expression),
         do: {:ok, extents(spans)}
  end

  defp falls_on(%{} = wanted, others, _options) do
    {:ok, others |> Enum.filter(&holds?(&1.metadata, wanted)) |> extents()}
  end

  defp falls_on(_none, _others, _options), do: {:ok, []}

  defp holds?(metadata, wanted),
    do: Enum.all?(wanted, fn {key, value} -> Map.get(metadata, key) == value end)

  defp extents(spans) do
    for span <- spans,
        {:ok, {start, stop}} <- [Spans.extent(span)],
        is_integer(start),
        is_integer(stop),
        do: {start, stop}
  end

  # Kept when the span at each offset from the occurrence falls on one.
  defp judged(:keep, span, conditions, falls_on) do
    if Enum.all?(conditions[:at] || [], &offset_falls_on?(span, &1, falls_on)),
      do: [span],
      else: []
  end

  # Moved, when it falls on one, to the first span the selector gives after it.
  defp judged(:move, span, conditions, falls_on) do
    case Spans.extent(span) do
      {:ok, {start, stop}} ->
        if overlaps?({start, stop}, falls_on),
          do: moved(span, stop, conditions[:to_next]),
          else: [span]

      _ ->
        [span]
    end
  end

  defp offset_falls_on?(span, %Duration{} = offset, falls_on) do
    case Spans.extent(span) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
        moved_falls_on?(
          Spans.shifted(start, offset, Spans.frame_of(span), span),
          stop - start,
          falls_on
        )

      _ ->
        false
    end
  end

  defp moved_falls_on?({:ok, start}, length, falls_on),
    do: overlaps?({start, start + length}, falls_on)

  defp moved_falls_on?({:error, _}, _length, _falls_on), do: false

  defp overlaps?(extent, extents), do: Enum.any?(extents, &Scale.overlap?(extent, &1))

  defp moved(%Tempo{form: {:span, from, _}} = span, stop, selector) do
    after_it = Spans.at_position(stop, from, :start, span.calendar, span.zone)
    period = %{span | form: {:span, after_it, %Duration{units: [year: 1]}}}

    case Select.select(period, selector) do
      {:ok, [first | _]} -> spans_of(first, span)
      _ -> []
    end
  end

  defp spans_of(value, span) do
    case Spans.spans(%{value | metadata: span.metadata}) do
      {:ok, spans} -> Enum.take(spans, 1)
      _ -> []
    end
  end
end
