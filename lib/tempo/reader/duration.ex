defmodule Tempo.Reader.Duration do
  @moduledoc false

  # A duration (ISO 8601-1 §5.5.2, ISO 8601-2 clause 11): `P` then units,
  # `T` before the clock's, a component negative where it runs backwards,
  # the whole negative with a `-` before the `P`, a fraction on the lowest
  # component. `units/2` reads the units alone, for a group's size.

  alias Tempo.Reader.Number

  @date_designators %{"Y" => :year, "M" => :month, "W" => :week, "D" => :day}
  @clock_designators %{"H" => :hour, "M" => :minute, "S" => :second}

  @doc "A duration and what follows it."
  @spec read(String.t()) :: {:ok, Tempo.Duration.t(), String.t()} | :error
  def read(<<"-P", rest::binary>>) do
    with {:ok, %Tempo.Duration{units: units}, rest} <- read("P" <> rest) do
      {:ok, %Tempo.Duration{units: Enum.map(units, &negated/1)}, rest}
    end
  end

  def read(<<"P", rest::binary>>) do
    case units(rest, :date) do
      {:ok, [], _rest} -> alternative(rest)
      {:ok, units, rest} -> {:ok, %Tempo.Duration{units: units}, rest}
    end
  end

  def read(_text), do: :error

  # The alternative format of ISO 8601-1 §5.5.2.4: a duration written as a
  # date and a time of day, by month or by day of the year, `P0002-01-10T22:33:55`.
  defp alternative(text) do
    Enum.find_value(alternatives(), :error, fn {pattern, units} ->
      case Regex.run(pattern, text) do
        [whole | numbers] ->
          held = Enum.zip(units, Enum.map(numbers, &String.to_integer/1))
          {:ok, %Tempo.Duration{units: held}, String.replace_prefix(text, whole, "")}

        nil ->
          nil
      end
    end)
  end

  defp alternatives do
    by_month = [:year, :month, :day, :hour, :minute, :second]
    by_day = [:year, :day, :hour, :minute, :second]

    [
      {~r/\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/, by_month},
      {~r/\A(\d{4})-(\d{3})T(\d{2}):(\d{2}):(\d{2})/, by_day},
      {~r/\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/, by_month},
      {~r/\A(\d{4})(\d{3})T(\d{2})(\d{2})(\d{2})/, by_day}
    ]
  end

  @doc "Duration units, `T` before the clock's, as far as they run; a group's size reads them after `G`."
  @spec units(String.t(), :date | :clock) :: {:ok, Tempo.Duration.units(), String.t()}
  def units(text, context), do: units(text, context, [])

  defp units(<<"T", rest::binary>>, :date, acc), do: units(rest, :clock, acc)

  defp units(text, context, acc) do
    case component(text, context) do
      {:ok, unit, value, rest} ->
        units(rest, context_after(unit, context), lifted(unit, value) ++ acc)

      :error ->
        {:ok, Enum.reverse(acc), text}
    end
  end

  # An hour or a second after the date units turns to the clock without a T,
  # as a set of durations is written (ISO 8601-2 §6.4, `{P1M2S..P1M5S}`).
  defp context_after(unit, _context) when unit in [:hour, :second], do: :clock
  defp context_after(_unit, context), do: context

  # One component: a signed number, a fraction and a designator.
  defp component(text, context) do
    with {:ok, value, rest} <- Number.signed(text),
         {:ok, value, rest} <- fraction(value, rest, String.starts_with?(text, "-")),
         {:ok, unit, rest} <- designator(rest, context) do
      {:ok, unit, value, rest}
    end
  end

  # A fraction has the sign written before its whole number: `-1.5` is a
  # second and a half back, and `-0.5` half a second back.
  defp fraction(value, rest, negative?) do
    case {Number.fraction(rest), negative?} do
      {{:ok, {microseconds, precision}, rest}, true} ->
        {:ok, {value, {-microseconds, precision}}, rest}

      {{:ok, fraction, rest}, false} ->
        {:ok, {value, fraction}, rest}

      {:error, _} ->
        {:ok, value, rest}
    end
  end

  defp designator(<<designator::binary-size(1), rest::binary>>, :date)
       when is_map_key(@date_designators, designator),
       do: {:ok, Map.fetch!(@date_designators, designator), rest}

  defp designator(<<"H", rest::binary>>, :date), do: {:ok, :hour, rest}
  defp designator(<<"S", rest::binary>>, :date), do: {:ok, :second, rest}

  defp designator(<<designator::binary-size(1), rest::binary>>, :clock)
       when is_map_key(@clock_designators, designator),
       do: {:ok, Map.fetch!(@clock_designators, designator), rest}

  defp designator(_rest, _context), do: :error

  # A fraction of a second is the microsecond unit; of any other unit it is
  # kept as a fraction of that unit (ISO 8601-2 §11.4).
  defp lifted(:second, {whole, fraction}), do: [{:microsecond, fraction}, {:second, whole}]

  defp lifted(unit, {whole, {microseconds, precision}}),
    do:
      [{unit, whole + microseconds / Integer.pow(10, 6)}]
      |> then(fn [{u, v}] -> [{u, Float.round(v, precision)}] end)

  defp lifted(unit, value), do: [{unit, value}]

  defp negated({:microsecond, {microseconds, precision}}),
    do: {:microsecond, {-microseconds, precision}}

  defp negated({unit, value}), do: {unit, -value}
end
