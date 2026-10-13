defmodule Tempo.Reader.Selection do
  @moduledoc false

  # A selection (ISO 8601-2 clause 12): `L`, rules, `N`. A rule is a number
  # and a designator (a month, week, day, weekday, day of the year; after
  # `T` an hour, minute or second), a position `nI`, a week start `nq`, an
  # event `(name[@zone])e`, a roll to a weekday `(convention)r` (Tempo's own,
  # as the event is), or a nested selection, which `/duration` may
  # follow to open a window from each date it selects (§12.10). The result
  # is the parts in the order written.

  alias Tempo.Reader.Duration
  alias Tempo.Reader.Number
  alias Tempo.Workdays

  @date_designators %{
    "Y" => :year,
    "M" => :month,
    "W" => :week,
    "D" => :day,
    "O" => :day_of_year,
    "K" => :day_of_week,
    "m" => :traditional_month
  }
  @clock_designators %{"H" => :hour, "M" => :minute, "S" => :second}

  @doc "A selection and what follows its `N`."
  @spec read(String.t()) :: {:ok, Tempo.Unit.selection(), String.t()} | :error
  def read(<<"L", rest::binary>>) do
    case parts(rest, :date, []) do
      {:ok, parts, <<"N", rest::binary>>} -> {:ok, parts, rest}
      _ -> :error
    end
  end

  def read(_text), do: :error

  defp parts(<<"N", _::binary>> = rest, _context, acc), do: {:ok, Enum.reverse(acc), rest}
  defp parts(<<"T", rest::binary>>, :date, acc), do: parts(rest, :clock, acc)

  defp parts(<<"L", _::binary>> = text, context, acc) do
    with {:ok, inner, rest} <- read(text),
         {:ok, window, rest} <- window(rest) do
      parts(rest, context, window ++ [{:selection, inner} | acc])
    end
  end

  defp parts(<<"(", rest::binary>>, context, acc) do
    case Number.split_while(rest, &(&1 != ?))) do
      {name, <<")e", rest::binary>>} -> event_part(event(name), rest, context, acc)
      {name, <<")r", rest::binary>>} -> roll_part(roll(name), rest, context, acc)
      _ -> :error
    end
  end

  defp parts(text, context, acc) do
    case Number.value(text) do
      {:ok, held, rest} -> part_read(part(held, rest, context), context, acc)
      :error -> :error
    end
  end

  defp event_part({:ok, event}, rest, context, acc),
    do: parts(rest, context, [{:event, event} | acc])

  defp event_part(:error, _rest, _context, _acc), do: :error

  defp roll_part({:ok, convention}, rest, context, acc),
    do: parts(rest, context, [{:roll, convention} | acc])

  defp roll_part(:error, _rest, _context, _acc), do: :error

  # `modified-nearest`: one of the conventions a day is rolled to a weekday by.
  defp roll(name) do
    Enum.find_value(Workdays.conventions(), :error, fn convention ->
      if written(convention) == name, do: {:ok, convention}
    end)
  end

  defp written(convention), do: convention |> Atom.to_string() |> String.replace("_", "-")

  defp part_read({:ok, part, rest}, context, acc), do: parts(rest, context, [part | acc])
  defp part_read(:error, _context, _acc), do: :error

  defp window(<<"/", rest::binary>>) do
    with {:ok, duration, rest} <- Duration.read(rest), do: {:ok, [{:window, duration}], rest}
  end

  defp window(rest), do: {:ok, [], rest}

  defp part(held, <<"I", rest::binary>>, _context), do: {:ok, {:instance, held}, rest}

  defp part(held, <<"q", rest::binary>>, _context) when is_integer(held),
    do: {:ok, {:week_start, held}, rest}

  defp part(held, <<"+m", rest::binary>>, :date),
    do: {:ok, {:traditional_month, {held, :leap}}, rest}

  defp part(held, <<designator::binary-size(1), rest::binary>>, :date)
       when is_map_key(@date_designators, designator) do
    {:ok, {Map.fetch!(@date_designators, designator), held}, rest}
  end

  defp part(held, <<designator::binary-size(1), rest::binary>>, :clock)
       when is_map_key(@clock_designators, designator) do
    {:ok, {Map.fetch!(@clock_designators, designator), held}, rest}
  end

  defp part(_held, _rest, _context), do: :error

  # `easter`, `march-equinox@+09:00`: a lowercase name, and the zone its date is read in.
  defp event(text) do
    case String.split(text, "@", parts: 2) do
      [name] -> if name?(name), do: {:ok, {name, nil}}, else: :error
      [name, zone] -> if name?(name) and zone != "", do: {:ok, {name, zone}}, else: :error
    end
  end

  defp name?(name), do: String.match?(name, ~r/\A[a-z][a-z0-9-]*\z/)
end
