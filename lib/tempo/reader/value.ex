defmodule Tempo.Reader.Value do
  @moduledoc false

  # A value in the explicit form (ISO 8601-2 clause 7 and its extensions):
  # components coarsest first, each a number and its designator, `T` before
  # the clock, a group (`2G3MU`), a selection (`L…N`), a qualifier between a
  # number and its designator (individual, §8.2.3) or after the designator
  # (for it and every component before it, §8.2.2), and a shift (`Z`,
  # `Z-5H`) at the end. The result is the units, the qualifications and the
  # shift. The implied formats (`2026-06-15`) are `Tempo.Reader.Implied`'s.

  alias Tempo.Reader.Duration
  alias Tempo.Reader.Number
  alias Tempo.Reader.Selection
  alias Tempo.Unit

  @type read :: %{units: Tempo.Unit.units(), qualifications: map() | nil, shift: keyword() | nil}

  @date_designators %{
    "C" => :century,
    "J" => :decade,
    "Y" => :year,
    "M" => :month,
    "W" => :week,
    "D" => :day,
    "O" => :day_of_year,
    "K" => :day_of_week,
    "m" => :traditional_month
  }
  @clock_designators %{"H" => :hour, "M" => :minute, "S" => :second}
  @qualifiers %{"?" => :uncertain, "~" => :approximate, "%" => :both}

  @doc "A value in the explicit form, and what follows it."
  @spec read(String.t()) :: {:ok, read(), String.t()} | :error
  def read(text) do
    case components(text, :date, []) do
      {:ok, [], _rest} -> :error
      {:ok, components, rest} -> finished(lift_fractions(components), shift(rest))
    end
  end

  defp finished(components, {:ok, shift, rest}) do
    units = Enum.map(components, fn {unit, held, _, _} -> {unit, held} end)
    {:ok, %{units: units, qualifications: qualifications(components), shift: shift}, rest}
  end

  defp finished(_components, :error), do: :error

  @doc "The designator of a clock unit."
  @spec clock_designator(String.t()) :: Tempo.Unit.t() | nil
  def clock_designator(designator), do: Map.get(@clock_designators, designator)

  @doc "A qualifier mark and the text after it, or `nil` and the text."
  @spec qualifier(String.t()) :: {atom() | nil, String.t()}
  def qualifier(<<mark::binary-size(1), rest::binary>>) when is_map_key(@qualifiers, mark),
    do: {Map.fetch!(@qualifiers, mark), rest}

  def qualifier(text), do: {nil, text}

  # ── Components ────────────────────────────────────────────────────────

  defp components(<<"T", rest::binary>>, :date, acc), do: components(rest, :clock, acc)

  defp components(<<"L", _::binary>> = text, context, acc) do
    case Selection.read(text) do
      {:ok, parts, rest} -> components(rest, context, [{:selection, parts, nil, nil} | acc])
      :error -> {:ok, Enum.reverse(acc), text}
    end
  end

  defp components(text, context, acc) do
    case component(text, context) do
      {:ok, component, rest} ->
        components(rest, context_after(component, context), [component | acc])

      :error ->
        {:ok, Enum.reverse(acc), text}
    end
  end

  # A group of clock units (`2GT6HU`) is of the clock, and so is what follows it.
  defp context_after({:group, {_nth, duration}, _, _}, context) do
    if Unit.clock?(Unit.resolution(duration)), do: :clock, else: context
  end

  defp context_after(_component, context), do: context

  # number [fraction] [individual mark] designator [group mark]
  defp component(text, context) do
    with {:ok, held, rest} <- Number.value(text),
         {:ok, held, rest} <- annotated(held, rest, context),
         {:ok, held, rest} <- fraction(held, rest, context),
         {individual, rest} <- qualifier(rest),
         {:ok, unit, held, rest} <- designated(held, rest, context),
         {group, rest} <- qualifier(rest) do
      {:ok, {unit, held, individual, group}, rest}
    end
  end

  # `E`, `S` and `±` are read after a number only where a year's `Y` follows them.
  defp annotated(held, rest, :date) when is_integer(held) do
    case Number.annotated(held, rest) do
      {:ok, {_, _} = annotated, <<"Y", _::binary>> = rest} ->
        {:ok, annotated, rest}

      {:ok, {_, _} = annotated, <<mark::binary-size(1), "Y", _::binary>> = rest}
      when is_map_key(@qualifiers, mark) ->
        {:ok, annotated, rest}

      _ ->
        {:ok, held, rest}
    end
  end

  defp annotated(held, rest, _context), do: {:ok, held, rest}

  defp fraction(held, rest, :clock) when is_integer(held) do
    case Number.fraction(rest) do
      {:ok, fraction, rest} -> {:ok, {:fraction, held, fraction}, rest}
      :error -> {:ok, held, rest}
    end
  end

  defp fraction(held, rest, _context), do: {:ok, held, rest}

  # A group: `nG`, duration units, `U`.
  # The size is read as a duration's units, with a `T` of its own before the clock's.
  defp designated(held, <<"G", rest::binary>>, _context) do
    case Duration.units(rest, :date) do
      {:ok, duration, <<"U", rest::binary>>} when duration != [] ->
        {:ok, :group, {held, duration}, rest}

      _ ->
        :error
    end
  end

  defp designated(
         {:fraction, whole, fraction},
         <<designator::binary-size(1), rest::binary>>,
         :clock
       )
       when is_map_key(@clock_designators, designator) do
    {:ok, :fraction_of, {Map.fetch!(@clock_designators, designator), whole, fraction}, rest}
  end

  defp designated({:fraction, _, _}, _rest, _context), do: :error

  defp designated(held, <<"+m", rest::binary>>, :date),
    do: {:ok, :traditional_month, {held, :leap}, rest}

  # A month of 21 to 41 is a season or a division of the year (ISO 8601-2 §4.8.3).
  defp designated(held, <<"M", rest::binary>>, :date) when is_integer(held) and held in 21..32,
    do: {:ok, :season, held, rest}

  defp designated(held, <<"M", rest::binary>>, :date) when is_integer(held) and held in 33..36,
    do: {:ok, :quarter, held - 32, rest}

  defp designated(held, <<"M", rest::binary>>, :date) when is_integer(held) and held in 37..39,
    do: {:ok, :group, {held - 36, [month: 4]}, rest}

  defp designated(held, <<"M", rest::binary>>, :date) when is_integer(held) and held in 40..41,
    do: {:ok, :group, {held - 39, [month: 6]}, rest}

  defp designated(held, <<designator::binary-size(1), rest::binary>>, :date)
       when is_map_key(@date_designators, designator) do
    {:ok, Map.fetch!(@date_designators, designator), held, rest}
  end

  defp designated(held, <<designator::binary-size(1), rest::binary>>, :clock)
       when is_map_key(@clock_designators, designator) do
    {:ok, Map.fetch!(@clock_designators, designator), held, rest}
  end

  defp designated(_held, _rest, _context), do: :error

  # A fraction of a clock unit is the units below it: half an hour is thirty
  # minutes, a tenth of a second a part of it.
  defp lift_fractions(components) do
    Enum.flat_map(components, fn
      {:fraction_of, {:second, whole, fraction}, individual, group} ->
        [{:second, whole, individual, nil}, {:microsecond, fraction, individual, group}]

      {:fraction_of, {:minute, whole, {microseconds, _}}, individual, group} ->
        total = div(microseconds * 60, 1_000_000)
        [{:minute, whole, individual, nil}, {:second, total, individual, group}]

      {:fraction_of, {:hour, whole, {microseconds, _}}, individual, group} ->
        total = div(microseconds * 3600, 1_000_000)
        minutes = [{:minute, div(total, 60), individual, nil}]

        seconds =
          if rem(total, 60) == 0, do: [], else: [{:second, rem(total, 60), individual, nil}]

        [{:hour, whole, individual, nil} | minutes ++ seconds] |> put_group(group)

      component ->
        [component]
    end)
  end

  defp put_group(components, nil), do: components

  defp put_group(components, group),
    do: List.update_at(components, -1, fn {u, h, i, _} -> {u, h, i, group} end)

  # A unit's qualifier is its own mark, else the mark of the first group
  # written at or after it; none is `nil`.
  defp qualifications(components) do
    groups = Enum.map(components, fn {_, _, _, group} -> group end)

    components
    |> Enum.with_index()
    |> Enum.flat_map(fn {{unit, _, individual, _}, index} ->
      case individual || groups |> Enum.drop(index) |> Enum.find(&(not is_nil(&1))) do
        nil -> []
        mark -> [{unit, mark}]
      end
    end)
    |> Map.new()
    |> then(fn map -> if map == %{}, do: nil, else: map end)
  end

  # ── The shift ─────────────────────────────────────────────────────────

  # `Z` alone is UTC; `Z8H`, `Z-5H`, `Z7H33M14S` are clock units after it, the sign on the first.
  defp shift(<<"Z", rest::binary>>) do
    {sign, rest} =
      case rest do
        <<"-", rest::binary>> -> {-1, rest}
        _ -> {1, rest}
      end

    case shift_units(rest, []) do
      {[], rest} when sign == 1 -> {:ok, [hour: 0], rest}
      {[], _rest} -> :error
      {[{first, value} | units], rest} -> {:ok, [{first, sign * value} | units], rest}
    end
  end

  defp shift(text), do: {:ok, nil, text}

  defp shift_units(text, acc) do
    case Number.digits(text) do
      {:ok, value, <<designator::binary-size(1), rest::binary>>}
      when is_map_key(@clock_designators, designator) ->
        shift_units(rest, [{Map.fetch!(@clock_designators, designator), value} | acc])

      _ ->
        {Enum.reverse(acc), text}
    end
  end
end
