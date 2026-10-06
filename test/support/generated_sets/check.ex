defmodule Tempo.GeneratedSets.Check do
  @moduledoc false

  # What a generated text is held to (`Tempo.GeneratedSets`). Each finding is
  # `{property, text, detail}`, the property one of:
  #
  # * `:raises` — reading the text, `inspect/1` or `Tempo.to_iso8601/1`
  #   raised. Each text is checked in a task of its own and a raise is that
  #   task's exit, so nothing is rescued;
  #
  # * `:form` — the text is read where it is built to be refused, or refused
  #   where it is built to be read;
  #
  # * `:member` — a member of the set is not its own text read alone;
  #
  # * `:written` — what `inspect/1` or `Tempo.to_iso8601/1` writes does not
  #   read back as the same value.

  alias Tempo.Compare
  alias Tempo.Enumeration
  alias Tempo.Interval
  alias Tempo.IntervalSet

  @spec findings([map()]) :: [{atom(), String.t(), term()}]
  def findings(texts) do
    {:ok, supervisor} = Task.Supervisor.start_link()

    supervisor
    |> Task.Supervisor.async_stream_nolink(texts, &found/1,
      timeout: 30_000,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(texts)
    |> Enum.flat_map(&reported/1)
  end

  defp reported({{:ok, findings}, %{text: text}}),
    do: Enum.map(findings, fn {property, detail} -> {property, text, detail} end)

  defp reported({{:exit, reason}, %{text: text}}), do: [{:raises, text, raised(reason)}]

  # The exception and where it was raised, for a report a reader can act on.
  defp raised({%{__exception__: true} = exception, [_ | _] = stack}),
    do: {exception.__struct__, stack |> Enum.take(3) |> Enum.map(&frame/1)}

  defp raised(reason), do: reason

  defp frame({module, function, arity, location}) when is_list(arity),
    do: frame({module, function, Enum.count(arity), location})

  defp frame({module, function, arity, location}),
    do: "#{inspect(module)}.#{function}/#{arity}:#{location[:line]}"

  ## The form: read, or refused

  defp found(%{text: text, expect: expect} = generated) do
    case {Tempo.from_iso8601(text), expect} do
      {{:ok, value}, :read} -> written(value) ++ members(generated, value)
      {{:error, %kind{}}, {:refused, kind}} -> []
      {{:ok, value}, {:refused, _kind}} -> [{:form, {:read, shown(value)}}]
      {{:error, error}, _read_or_another_error} -> [{:form, {:refused, error.__struct__}}]
    end
  end

  defp shown(value), do: inspect(value, limit: :infinity)

  ## What is written reads back as the same value

  defp written(value) do
    by_to_iso8601 =
      case Tempo.to_iso8601(value) do
        {:ok, text} -> reads_back(text, value, :to_iso8601)
        {:error, error} -> [{:written, {:not_written, error.__struct__}}]
      end

    by_to_iso8601 ++ shown_reads_back(shown(value), value)
  end

  # `inspect/1` writes the sigil, whose text is what is read, or a call
  # where the sigil cannot hold the value's calendar.
  defp shown_reads_back("~o\"" <> rest, value),
    do: rest |> String.trim_trailing("\"") |> reads_back(value, :inspect)

  defp shown_reads_back(_a_call, _value), do: []

  defp reads_back(text, value, by) do
    case Tempo.from_iso8601(text) do
      {:ok, ^value} -> []
      {:ok, other} -> [{:written, {by, text, :reads_as, shown(other)}}]
      {:error, error} -> [{:written, {by, text, :is_not_read, error.__struct__}}]
    end
  end

  ## A member of a set is its own text read alone

  # A set in one unit of a value: the values with each member written there.
  defp members(%{members: members, type: type}, value) do
    case each_alone(members, &Tempo.from_iso8601/1) do
      {:ok, alone} -> unit_members(type, value, alone)
      {:error, error} -> [{:member, {:not_read_alone, error.__struct__}}]
    end
  end

  # A set of whole values: each entry a member, or a range of two.
  defp members(%{entries: entries}, value) do
    case each_alone(entries, &entry_alone/1) do
      {:ok, alone} -> set_members(value, alone)
      {:error, error} -> [{:member, {:not_read_alone, error.__struct__}}]
    end
  end

  defp members(_no_members, _value), do: []

  defp each_alone(texts, read) do
    Enum.reduce_while(texts, {:ok, []}, fn text, {:ok, alone} ->
      case read.(text) do
        {:ok, value} -> {:cont, {:ok, alone ++ [value]}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp entry_alone({:member, text}), do: Tempo.from_iso8601(text)

  defp entry_alone({:range, first, last}) do
    with {:ok, first} <- Tempo.from_iso8601(first),
         {:ok, last} <- Tempo.from_iso8601(last) do
      {:ok, %Tempo.Range{first: first, last: last}}
    end
  end

  defp entry_alone({:to, last}) do
    with {:ok, last} <- Tempo.from_iso8601(last),
         do: {:ok, %Tempo.Range{first: :undefined, last: last}}
  end

  defp entry_alone({:from, first}) do
    with {:ok, first} <- Tempo.from_iso8601(first),
         do: {:ok, %Tempo.Range{first: first, last: :undefined}}
  end

  # A set of whole values holds its members as they are read alone, in any
  # order. A set of years is read into the year of one value, which names
  # the members' spans.
  defp set_members(%Tempo.Set{set: held}, alone), do: same_members(held, alone)
  defp set_members(%Tempo{} = value, alone), do: same_spans(value, alone)
  defp set_members(other, _alone), do: [{:member, {:no_set, shown(other)}}]

  # One of the values a set in a unit names is a set of the values; all of
  # them is one value that holds them, which names their spans.
  defp unit_members(:one, %Tempo.Set{type: :one, set: held}, alone),
    do: same_members(held, alone)

  defp unit_members(:all, %Tempo{} = value, alone), do: same_spans(value, alone)
  defp unit_members(_type, other, _alone), do: [{:member, {:no_set, shown(other)}}]

  defp same_members(held, alone) do
    if in_order(held) == in_order(alone),
      do: [],
      else: [{:member, {:members, shown(held), :alone, shown(alone)}}]
  end

  defp in_order(values), do: values |> Enum.map(&shown/1) |> Enum.sort()

  defp same_spans(value, alone) do
    with {:ok, spans} <- spans(value),
         {:ok, expected} <- spans_of_each(alone) do
      if merged(spans) == merged(expected),
        do: [],
        else: [{:member, {:spans, shown(value), merged(spans), :alone, merged(expected)}}]
    else
      :unanchored -> same_values(value, alone)
      {:error, reason} -> [{:member, {:no_span, shown(value), reason}}]
    end
  end

  # A value with no year has no place on the time line, so the values it
  # names are held to its members instead.
  defp same_values(value, alone) do
    named =
      case Enumeration.expand(value) do
        {:ok, values} -> values
        _one_value -> [value]
      end

    same_members(named, alone)
  end

  defp spans_of_each(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, spans} ->
      case spans(value) do
        {:ok, more} -> {:cont, {:ok, spans ++ more}}
        not_spans -> {:halt, not_spans}
      end
    end)
  end

  # The spans a value names, each as the instants it starts and ends at.
  defp spans(%Tempo{time: [{:year, _year} | _units]} = value) do
    case Tempo.to_interval(value) do
      {:ok, %Interval{} = span} -> {:ok, [bounds(span)]}
      {:ok, %IntervalSet{} = set} -> {:ok, Enum.map(IntervalSet.members(set), &bounds/1)}
      {:error, error} -> {:error, error.__struct__}
    end
  end

  defp spans(%Tempo{}), do: :unanchored

  # A range of years runs from the start of its first to the end of its last.
  defp spans(%Tempo.Range{first: %Tempo{} = first, last: %Tempo{} = last}) do
    with {:ok, [{from, _first_ends} | _rest]} <- spans(first),
         {:ok, [_ | _] = last_spans} <- spans(last) do
      {_last_starts, to} = List.last(last_spans)
      {:ok, [{from, to}]}
    end
  end

  defp spans(other), do: {:error, {:no_value, shown(other)}}

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  # Spans in order, those that touch or overlap made one, so that a value
  # that holds a range and one that lists its members name the same spans.
  defp merged(spans) do
    spans
    |> Enum.sort()
    |> Enum.reduce([], &merge/2)
    |> Enum.reverse()
  end

  defp merge({from, to}, [{last_from, last_to} | rest]) when from <= last_to,
    do: [{last_from, max(to, last_to)} | rest]

  defp merge(span, merged), do: [span | merged]
end
