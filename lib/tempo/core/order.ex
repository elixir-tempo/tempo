defmodule Tempo.Order do
  @moduledoc false

  # Two values of the ISO calendar on one line, each written from its year
  # down to a unit no finer than the second, are ordered by their units as
  # written: placing each on the line (`Tempo.Spans.extent/1`) gives the same
  # order at several times the cost. A unit one value writes and the other
  # does not is read at its first, so `2026-06` begins with `2026-06-01T00`
  # and, beginning together, ends after it. The order is `{:ok, order}`;
  # anything else is `:unordered`, and is placed.

  @units [:year, :month, :day, :hour, :minute, :second]
  @first %{month: 1, day: 1, hour: 0, minute: 0, second: 0}

  @spec compare(Tempo.t(), Tempo.t(), :start_and_end | :start) ::
          {:ok, :lt | :eq | :gt} | :unordered
  def compare(
        %Tempo{
          form: {:value, a},
          calendar: Calendar.ISO,
          zone: nil,
          qualifications: nil,
          shift: shift
        },
        %Tempo{
          form: {:value, b},
          calendar: Calendar.ISO,
          zone: nil,
          qualifications: nil,
          shift: shift
        },
        by
      ) do
    if written?(a) and written?(b) do
      {:ok, units(a, b, by)}
    else
      :unordered
    end
  end

  def compare(_a, _b, _by) do
    :unordered
  end

  defp written?([{:year, _year} | _units] = units) do
    in_order?(units, @units)
  end

  defp written?(_units) do
    false
  end

  defp in_order?([{unit, value} | units], [unit | rest]) when is_integer(value) do
    in_order?(units, rest)
  end

  defp in_order?([], _rest) do
    true
  end

  defp in_order?(_units, _rest) do
    false
  end

  # Both are written in the units' order from the year, so the units at one
  # place are the same unit.
  defp units([{unit, value} | a], [{unit, value} | b], by) do
    units(a, b, by)
  end

  defp units([{_, value} | _a], [{_, other} | _b], _by) when value < other do
    :lt
  end

  defp units([_unit | _a], [_other | _b], _by) do
    :gt
  end

  defp units([], [], _by) do
    :eq
  end

  defp units([], finer, by) do
    finer
    |> finer_beside(by)
    |> inverse()
  end

  defp units(finer, [], by) do
    finer_beside(finer, by)
  end

  # Where the coarser value's units end, the finer one begins with it if
  # every unit it writes beyond them is its first, and ends first; otherwise
  # it begins after.
  defp finer_beside(units, by) do
    if Enum.all?(units, &first?/1) do
      together(by)
    else
      :gt
    end
  end

  defp first?({unit, value}) do
    Map.fetch!(@first, unit) == value
  end

  defp together(:start_and_end) do
    :lt
  end

  defp together(:start) do
    :eq
  end

  defp inverse(:lt) do
    :gt
  end

  defp inverse(:gt) do
    :lt
  end

  defp inverse(:eq) do
    :eq
  end
end
