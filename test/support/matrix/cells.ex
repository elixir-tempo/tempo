defmodule Tempo.Matrix.Cells do
  @moduledoc """
  Every operation of the library on every value of the corpus
  (`Tempo.Matrix.Corpus`), each as a cell that holds what was asked and what
  was answered: a value, an `{:ok, value}`, an error by its module, or what
  was raised. `Tempo.TotalTest` holds the cells to one rule: an answer or a
  named error, for every value.
  """

  alias Tempo.Duration
  alias Tempo.Matrix.Corpus

  @take 24

  # How many members of a set with no end a cell records.
  @lazy_members 20

  @type cell :: %{
          op: String.t(),
          group: atom(),
          input: String.t(),
          calendar: String.t() | nil,
          arg: String.t() | nil,
          out: term()
        }

  @doc "The groups of operations."
  @spec groups() :: [atom()]
  def groups,
    do: [:walk, :convert, :compare, :combine, :arithmetic, :measure, :parts, :select, :format]

  defp operations(:walk) do
    %{
      "Enum.take/2 24" => &Enum.take(&1, @take),
      "Enum.count/1" => &Enum.count/1
    }
  end

  defp operations(:compare) do
    %{
      "relation/2" => &Tempo.relation/2,
      "compare/2" => &Tempo.compare/2,
      "overlaps?/2" => &Tempo.overlaps?/2,
      "contains?/2" => &Tempo.contains?/2,
      "within?/2" => &Tempo.within?/2,
      "before?/2" => &Tempo.before?/2,
      "after?/2" => &Tempo.after?/2,
      "adjacent?/2" => &Tempo.adjacent?/2,
      "disjoint?/2" => &Tempo.disjoint?/2,
      "equal?/2" => &Tempo.equal?/2,
      "overlap_certainty/2" => &Tempo.certainty(:overlaps, &1, &2),
      "within_certainty/2" => &Tempo.certainty(:within, &1, &2),
      "certainly_before?/2" => &Tempo.certainly?(:before, &1, &2),
      "possibly_overlaps?/2" => &Tempo.possibly?(:overlaps, &1, &2),
      "Enum.member?/2" => &Enum.member?/2
    }
  end

  defp operations(:combine) do
    %{
      "union/2" => &Tempo.union/2,
      "intersection/2" => &Tempo.intersection/2,
      "difference/2" => &Tempo.difference/2,
      "symmetric_difference/2" => &Tempo.symmetric_difference/2,
      "complement/2 within" => &Tempo.complement(&1, within: &2),
      "members_overlapping/2" => &Tempo.members_overlapping/2,
      "members_outside/2" => &Tempo.members_outside/2,
      "members_in_exactly_one/2" => &Tempo.members_in_exactly_one/2,
      "at/2" => &Tempo.at/2,
      "on/2" => &Tempo.on/2
    }
  end

  defp operations(:arithmetic) do
    %{
      "shift/2 P1D" => &Tempo.shift(&1, day: 1),
      "shift/2 -P1D" => &Tempo.shift(&1, day: -1),
      "shift/2 P1M" => &Tempo.shift(&1, month: 1),
      "shift/2 P1Y" => &Tempo.shift(&1, year: 1),
      "shift/2 PT1H" => &Tempo.shift(&1, hour: 1),
      "trunc/2 month" => &Tempo.trunc(&1, :month),
      "round/2 day" => &Tempo.round(&1, :day),
      "extend/1" => &Tempo.extend/1,
      "at_resolution/2 hour" => &Tempo.at_resolution(&1, :hour),
      "split/1" => &Tempo.split/1
    }
  end

  defp operations(:measure) do
    %{
      "duration/1" => &Tempo.duration/1,
      "at_least?/2 P1D" => &Tempo.at_least?(&1, Duration.new!(day: 1)),
      "shorter_than?/2 P1M" => &Tempo.shorter_than?(&1, Duration.new!(month: 1)),
      "bounded?/1" => &Tempo.bounded?/1,
      "empty?/1" => &Tempo.empty?/1
    }
  end

  defp operations(:parts) do
    %{
      "year/1" => &Tempo.year/1,
      "month/1" => &Tempo.month/1,
      "day/1" => &Tempo.day/1,
      "hour/1" => &Tempo.hour/1,
      "week/1" => &Tempo.week/1,
      "day_of_week/1" => &Tempo.day_of_week/1,
      "day_of_year/1" => &Tempo.day_of_year/1,
      "quarter_of_year/1" => &Tempo.quarter_of_year/1,
      "leap_year?/1" => &Tempo.leap_year?/1,
      "days_in_month/1" => &Tempo.days_in_month/1,
      "resolution/1" => &Tempo.resolution/1,
      "anchored?/1" => &Tempo.anchored?/1,
      "floating?/1" => &Tempo.floating?/1,
      "zoned?/1" => &Tempo.zoned?/1,
      "metadata/1" => &Tempo.metadata/1
    }
  end

  defp operations(:format) do
    %{
      "to_iso8601/1" => &Tempo.to_iso8601/1,
      "inspect/1" => &inspect/1,
      "to_string/2 en" => &Tempo.to_string(&1, locale: "en"),
      "explain/1" => &Tempo.explain/1
    }
  end

  defp operations(:select) do
    %{
      "select/2 workdays" => &Tempo.select(&1, Tempo.workdays(:US)),
      "select/2 [1, 15]" => &Tempo.select(&1, [1, 15]),
      "select/2 T10:30" => &Tempo.select(&1, Tempo.from_iso8601!("T10:30")),
      "select/2 L5K-1IN" => &Tempo.select(&1, Tempo.from_iso8601!("L5K-1IN")),
      "select/2 L1K1IN" => &Tempo.select(&1, Tempo.from_iso8601!("L1K1IN")),
      "select/2 15D" => &Tempo.select(&1, Tempo.from_iso8601!("15D"))
    }
  end

  defp operations(:convert) do
    %{
      "to_interval/1" => &Tempo.to_interval/1,
      "to_interval/2 within 2026" => &Tempo.to_interval(&1, within: Tempo.from_iso8601!("2026"))
    }
  end

  @doc "The cells of a group of operations."
  @spec cells(atom()) :: [cell()]
  def cells(group) when group in [:compare, :combine] do
    partners = Corpus.partners()

    for entry <- Corpus.entries(),
        {name, fun} <- Enum.sort(operations(group)),
        {arg, partner} <- partners_of(entry, partners),
        {arg, pair} <- orders(entry, arg, partner) do
      %{
        op: name,
        group: group,
        input: entry.text,
        calendar: entry.calendar && inspect(entry.calendar),
        arg: arg,
        out: cell_out(Corpus.read(entry), pair_fun(fun, pair))
      }
    end
  end

  def cells(group) do
    for entry <- Corpus.entries(), {name, fun} <- Enum.sort(operations(group)) do
      out = cell_out(Corpus.read(entry), fun)

      %{
        op: name,
        group: group,
        input: entry.text,
        calendar: entry.calendar && inspect(entry.calendar),
        arg: nil,
        out: out
      }
    end
  end

  # The core values meet every partner in both orders and themselves; a
  # generated value meets one partner in its own frame, as the matrix does.
  defp partners_of(%{level: :core}, partners), do: partners

  defp partners_of(entry, partners) do
    zoned? = entry |> Corpus.read() |> zoned?()

    case Enum.filter(partners, fn {_text, value} -> zoned?({:ok, value}) == zoned? end) do
      [partner | _] -> [partner]
      [] -> Enum.take(partners, 1)
    end
  end

  # Whether a value is on the UTC line, in a zone or at a shift.
  defp zoned?({:ok, %Tempo{} = value}), do: Tempo.zoned?(value)
  defp zoned?(_no_expression), do: false

  defp orders(%{level: :core}, arg, partner),
    do: [{"self", :self}, {arg, {:with, partner}}, {"#{arg} |", {:after, partner}}]

  defp orders(_entry, arg, partner), do: [{arg, {:with, partner}}]

  defp pair_fun(fun, :self), do: fn value -> fun.(value, value) end
  defp pair_fun(fun, {:with, partner}), do: fn value -> fun.(value, partner) end
  defp pair_fun(fun, {:after, partner}), do: fn value -> fun.(partner, value) end

  defp cell_out({:ok, value}, fun), do: protected(fn -> fun.(value) end)
  defp cell_out({:error, exception}, _fun), do: %{"unread" => inspect(exception.__struct__)}

  # A raise is an answer too: the matrix records it as one, and so does this.
  defp protected(fun) do
    answer(fun.())
  rescue
    exception -> %{"raised" => inspect(exception.__struct__)}
  end

  defp answer({:ok, value}), do: %{"ok" => data(value)}

  defp answer({:error, %{__struct__: module} = exception}),
    do: %{"error" => inspect(module), "reason" => inspect(Map.get(exception, :reason))}

  defp answer(value), do: %{"value" => data(value)}

  defp data(%Tempo{form: {:all, members}}) when is_list(members),
    do: %{"set" => Enum.map(members, &data/1)}

  # A set with no end (a selection over a span with none) is its first members.
  defp data(%Tempo{form: {:all, members}}),
    do: %{"lazy_set" => members |> Enum.take(@lazy_members) |> Enum.map(&data/1)}

  defp data(%Tempo{} = value), do: written(value)
  defp data(%Duration{} = duration), do: written(duration)
  defp data(list) when is_list(list), do: Enum.map(list, &data/1)

  defp data(tuple) when is_tuple(tuple),
    do: "{" <> Enum.map_join(Tuple.to_list(tuple), ", ", &sigil_text/1) <> "}"

  defp data(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value

  defp data(value), do: inspect(value, limit: :infinity)

  defp sigil_text(%Tempo{} = value), do: ~s(~o"#{written(value)}")
  defp sigil_text(other), do: inspect(other)

  defp written(value) do
    case Tempo.to_iso8601(value) do
      {:ok, text} -> text
      {:error, _} -> inspect(value, limit: :infinity)
    end
  end
end
