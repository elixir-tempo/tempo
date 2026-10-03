defmodule Tempo.Rounding do
  @moduledoc false

  # Rounds a value to the nearest boundary of a unit: the start of the unit
  # the value is in, or the start of the next.
  #
  # A value is placed by where its span starts, measured in the unit it is
  # rounded to as that unit is there: 16 January is 15 days into a month of
  # 31, and noon on a day a clock goes forward is 11 hours into a day of 23.
  # Half way goes up, as `Kernel.round/1` rounds a half and as the halves of
  # every other date and time library do.
  #
  # The unit's start is `Tempo.trunc/2`'s and the next unit's start is one
  # step on from it by `Tempo.shift/2`, so a calendar's own lengths and a
  # zone's own days are read from where they are kept, and nothing here
  # counts a month or a year.

  alias Tempo.Compare
  alias Tempo.Iso8601.Unit
  alias Tempo.RoundingError
  alias Tempo.UnanchoredError

  @microseconds 1_000_000
  @day 86_400 * @microseconds

  # The units a day is written as, on each axis: one level of resolution.
  @day_units [:day, :day_of_year, :day_of_week]

  @spec round(Tempo.t(), atom()) :: Tempo.t() | {:error, Exception.t()}
  def round(%Tempo{} = tempo, unit) do
    {resolution, _span} = Tempo.resolution(tempo)

    case order(unit, resolution) do
      :finer -> {:error, finer_error(tempo, resolution, unit)}
      :same -> tempo
      :coarser -> nearest(tempo, unit)
    end
  end

  defp order(unit, resolution) when unit in @day_units and resolution in @day_units, do: :same

  defp order(unit, resolution) do
    case Unit.compare(unit, resolution) do
      :lt -> :finer
      :eq -> :same
      :gt -> :coarser
    end
  end

  # With a year a value has a place on a line, and the unit it is in and the
  # next are measured there. With none it is on a cycle (a time of day, a day
  # of a month), where each unit has the length it has anywhere.
  defp nearest(%Tempo{time: [{:year, year} | _rest] = time} = tempo, unit)
       when is_integer(year) do
    with %Tempo{} = floor <- Tempo.trunc(tempo, unit),
         %Tempo{} = next <- Tempo.shift(floor, [{step(unit), 1}]) do
      start = position(boundary(floor, time))

      if 2 * (position(tempo) - start) >= position(boundary(next, time)) - start,
        do: next,
        else: floor
    end
  end

  defp nearest(%Tempo{} = tempo, unit) do
    with %Tempo{} = floor <- Tempo.trunc(tempo, unit),
         {:ok, up?} <- half_way_or_more?(tempo, unit) do
      if up?, do: Tempo.shift(floor, [{step(unit), 1}]), else: floor
    end
  end

  # The unit a value steps by to the next boundary: a day, however the day
  # is written.
  defp step(unit) when unit in @day_units, do: :day
  defp step(unit), do: unit

  ## A value with a year

  # Where a unit starts for the value rounded to it. A year a week is counted
  # in starts with its first week, which is not 1 January: ISO 8601's 2026
  # runs from 29 December 2025.
  defp boundary(%Tempo{time: [year: year]} = point, time) do
    if List.keymember?(time, :week, 0),
      do: %{point | time: [year: year, week: 1]},
      else: point
  end

  defp boundary(point, _time), do: point

  # Microseconds along the line the value is on: the time line for a value in
  # a zone, the wall clock for one in none.
  defp position(%Tempo{time: time} = point) do
    {whole, fraction} = split_fraction(time)
    whole_point = %{point | time: whole}

    seconds =
      if Tempo.floating?(whole_point),
        do: Compare.to_wall_seconds(whole_point),
        else: Compare.to_utc_seconds(whole_point)

    seconds * @microseconds + fraction
  end

  defp split_fraction(time) do
    case List.keytake(time, :microsecond, 0) do
      {{:microsecond, {value, _precision}}, whole} -> {whole, value}
      nil -> {time, 0}
    end
  end

  ## A value with no year

  # Whether the units a value has below `unit` come to half of it or more.
  # A month's length may depend on the year the value has not got (February):
  # the answer is given when it is the same for every length, and is otherwise
  # the missing year's to give.
  defp half_way_or_more?(%Tempo{time: time, calendar: calendar} = tempo, unit) do
    elapsed = elapsed(below(time, unit), 0)

    case lengths(unit, time, Compare.effective_calendar(calendar)) do
      [] ->
        {:error, UnanchoredError.exception(value: tempo, operation: :round)}

      lengths ->
        lengths
        |> Enum.map(&(2 * elapsed >= &1))
        |> Enum.uniq()
        |> one_answer(tempo)
    end
  end

  defp one_answer([up?], _tempo), do: {:ok, up?}

  defp one_answer(_differing, tempo),
    do: {:error, UnanchoredError.exception(value: tempo, operation: :round)}

  # The units of a time list after `unit`.
  defp below(time, unit) do
    time
    |> Enum.drop_while(fn {present, _value} -> order(present, unit) != :finer end)
  end

  defp elapsed([{unit, value} | rest], total) when unit in @day_units,
    do: elapsed(rest, total + (value - 1) * @day)

  defp elapsed([{:hour, hour} | rest], total),
    do: elapsed(rest, total + hour * 3_600 * @microseconds)

  defp elapsed([{:minute, minute} | rest], total),
    do: elapsed(rest, total + minute * 60 * @microseconds)

  defp elapsed([{:second, second} | rest], total),
    do: elapsed(rest, total + second * @microseconds)

  defp elapsed([{:microsecond, {value, _precision}} | rest], total),
    do: elapsed(rest, total + value)

  defp elapsed([], total), do: total

  # The lengths a unit may have where the value is, in microseconds: one, or
  # the shortest and the longest of a month whose days depend on the year.
  defp lengths(:second, _time, _calendar), do: [@microseconds]
  defp lengths(:minute, _time, _calendar), do: [60 * @microseconds]
  defp lengths(:hour, _time, _calendar), do: [3_600 * @microseconds]
  defp lengths(unit, _time, _calendar) when unit in @day_units, do: [@day]
  defp lengths(:week, _time, calendar), do: [calendar.days_in_week() * @day]

  defp lengths(:month, time, calendar) do
    case List.keyfind(time, :month, 0) do
      {:month, month} when is_integer(month) -> month_lengths(calendar.days_in_month(month))
      _no_month -> []
    end
  end

  defp lengths(_unit, _time, _calendar), do: []

  defp month_lengths(days) when is_integer(days), do: [days * @day]

  defp month_lengths({:ambiguous, %Range{first: first, last: last}}),
    do: [min(first, last) * @day, max(first, last) * @day]

  defp month_lengths(_undefined), do: []

  defp finer_error(tempo, resolution, unit) do
    RoundingError.exception(
      unit: unit,
      value: tempo,
      reason:
        "#{inspect(tempo)} is written to the #{resolution}, so it cannot be rounded to " <>
          "the #{unit}, which is finer."
    )
  end
end
