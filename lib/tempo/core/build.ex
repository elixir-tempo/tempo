defmodule Tempo.Build do
  @moduledoc false

  # Expressions built from parts: a selection, a recurrence, a one-of set.
  #
  # Each builds the form the reader builds for the text that writes it, and
  # is checked by the same pass (`Tempo.Validate`), so that a program holds
  # the parts of an expression as data and never writes text to be read
  # back. What `Tempo.new/1`, `Tempo.Interval.new/1`, `Tempo.Duration.new/1`
  # and `Tempo.IntervalSet.new/2` build are the parts these take.

  alias Tempo.{Duration, Options, Validate, Workdays}

  # The units a selection names, coarsest first, as a rule's parts are held.
  @units [:year, :month, :week, :day_of_year, :day, :day_of_week, :hour, :minute, :second]
  @clock [:hour, :minute, :second]
  @parts @units ++ [:instance, :event, :roll, :selection, :window]

  @every_options [:from, :count, :until, :select, :metadata]

  # ── A selection ───────────────────────────────────────────────────────

  @doc "A selection (`L…N`) from its parts, as a value with no year."
  @spec selection(keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def selection(parts) do
    with {:ok, parts} <- parts(parts),
         do: Validate.run(%Tempo{form: {:value, [selection: parts]}})
  end

  @doc "A selection's parts in the form a rule holds them: the units coarsest first, a position last."
  @spec parts(term()) :: {:ok, Tempo.selection()} | {:error, Exception.t()}
  def parts(%Tempo{form: {:value, [selection: parts]}}), do: {:ok, parts}

  def parts(parts) when is_list(parts) do
    with :ok <- known(parts),
         {:ok, held} <- each_part(parts) do
      {:ok, ordered(held)}
    end
  end

  def parts(other),
    do: {:error, argument("a selection is a keyword list of parts, not #{inspect(other)}")}

  defp known(parts) do
    cond do
      not Keyword.keyword?(parts) or parts == [] ->
        {:error, argument("a selection is a keyword list of parts, not #{inspect(parts)}")}

      unknown = Enum.find(Keyword.keys(parts), &(&1 not in @parts)) ->
        {:error, argument("#{inspect(unknown)} is not a part of a selection: it has #{listed()}")}

      Keyword.has_key?(parts, :window) and not Keyword.has_key?(parts, :selection) ->
        {:error, argument("a :window is the length of what a nested :selection selects")}

      true ->
        :ok
    end
  end

  defp listed, do: Enum.map_join(@parts, ", ", &inspect/1)

  defp each_part(parts) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, held} ->
      case part(part) do
        {:ok, part} -> {:cont, {:ok, held ++ [part]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp part({:event, name}) when is_binary(name), do: {:ok, {:event, {name, nil}}}
  defp part({:event, {name, _} = event}) when is_binary(name), do: {:ok, {:event, event}}
  defp part({:window, %Duration{} = length}), do: {:ok, {:window, length}}

  defp part({:roll, convention}) do
    if convention in Workdays.conventions(),
      do: {:ok, {:roll, convention}},
      else:
        {:error,
         argument(
           ":roll of a selection is one of #{inspect(Workdays.conventions())}, not #{inspect(convention)}"
         )}
  end

  defp part({:selection, nested}) do
    with {:ok, parts} <- parts(nested), do: {:ok, {:selection, parts}}
  end

  defp part({unit, %Range{} = range}) when unit in @units or unit == :instance,
    do: {:ok, {unit, [range]}}

  defp part({unit, held}) when (unit in @units or unit == :instance) and is_integer(held),
    do: {:ok, {unit, held}}

  defp part({unit, held}) when (unit in @units or unit == :instance) and is_list(held) do
    if Enum.all?(held, &(is_integer(&1) or is_struct(&1, Range))),
      do: {:ok, {unit, held}},
      else:
        {:error,
         argument("#{inspect(unit)} takes whole numbers and ranges, not #{inspect(held)}")}
  end

  defp part({key, held}),
    do: {:error, argument("#{inspect(key)} of a selection does not take #{inspect(held)}")}

  # A nested selection and its window stand first, where they are made; the
  # units follow coarsest first, and a position counts among them all.
  defp ordered(parts) do
    {nested, rest} = Keyword.split(parts, [:selection, :window])
    {last, units} = Keyword.split(rest, [:instance])
    {events, units} = Keyword.split(units, [:event])
    {rolls, units} = Keyword.split(units, [:roll])
    {before, later} = Enum.split_with(units, fn {unit, _} -> unit in [:year, :month] end)
    {times, days} = Enum.split_with(later, fn {unit, _} -> unit in @clock end)

    # A roll stands after the days it rolls and before a time of day on them.
    by_order(before) ++ nested ++ events ++ by_order(days) ++ rolls ++ by_order(times) ++ last
  end

  defp by_order(units),
    do: Enum.sort_by(units, fn {unit, _} -> Enum.find_index(@units, &(&1 == unit)) end)

  # ── A recurrence ──────────────────────────────────────────────────────

  @doc "A recurrence from its cadence, its start, its end and what it selects in each repeat."
  @spec every(Duration.t() | keyword(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def every(cadence, options) do
    with :ok <- Options.check(options, @every_options, "Tempo.every/2"),
         {:ok, cadence} <- cadence(cadence),
         {:ok, first} <- first(Keyword.get(options, :from), cadence),
         {:ok, bound} <- bound(Keyword.get(options, :count), Keyword.get(options, :until)),
         {:ok, rule} <- rule(Keyword.get(options, :select)) do
      Validate.run(%Tempo{
        form: {:every, first, bound, rule},
        calendar: first.calendar,
        zone: first.zone,
        metadata: Keyword.get(options, :metadata, %{})
      })
    end
  end

  defp cadence(%Duration{units: [_ | _]} = cadence), do: {:ok, cadence}
  defp cadence(units) when is_list(units) and units != [], do: Duration.new(units)

  defp cadence(other),
    do: {:error, argument("a cadence is a duration or its units, not #{inspect(other)}")}

  # The first repeat: from a value, from each member of a set (a domain), or with no start.
  defp first(nil, cadence),
    do: {:ok, %Tempo{form: {:span, :open, cadence}}}

  defp first(%Tempo{form: {kind, _}} = from, cadence) when kind in [:value, :all, :one],
    do: {:ok, %Tempo{form: {:span, from, cadence}, calendar: from.calendar, zone: from.zone}}

  defp first(%Tempo{form: {:when, _, _}} = from, cadence),
    do: {:ok, %Tempo{form: {:span, from, cadence}, calendar: from.calendar, zone: from.zone}}

  defp first(other, _cadence),
    do: {:error, argument(":from is a value, or a set as a domain, not #{inspect(other)}")}

  defp bound(nil, nil), do: {:ok, :infinity}
  defp bound(count, nil) when is_integer(count) and count > 0, do: {:ok, count}
  defp bound(nil, %Tempo{form: {:value, _}} = until), do: {:ok, until}

  defp bound(count, until) when count != nil and until != nil,
    do: {:error, argument("a recurrence ends by :count or by :until, not by both")}

  defp bound(count, nil),
    do: {:error, argument(":count is a whole number above zero, not #{inspect(count)}")}

  defp bound(nil, until), do: {:error, argument(":until is a value, not #{inspect(until)}")}

  defp rule(nil), do: {:ok, nil}
  defp rule(select), do: parts(select)

  # ── A one-of set ──────────────────────────────────────────────────────

  @doc "A set one of whose members is meant."
  @spec one_of([Tempo.t()]) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def one_of([%Tempo{} = first | _] = members) do
    cond do
      not Enum.all?(members, &is_struct(&1, Tempo)) ->
        {:error, argument("the members of a set are Tempo expressions, not #{inspect(members)}")}

      Enum.any?(members, &(&1.calendar != first.calendar or &1.zone != first.zone)) ->
        {:error, argument("the members of a set are in one calendar and one zone")}

      true ->
        Validate.run(%Tempo{form: {:one, members}, calendar: first.calendar, zone: first.zone})
    end
  end

  def one_of(other),
    do:
      {:error,
       argument("a one-of set has members, each a Tempo expression, not #{inspect(other)}")}

  defp argument(message), do: ArgumentError.exception(message)
end
