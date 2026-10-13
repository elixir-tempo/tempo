defmodule Tempo.Skip do
  @moduledoc false

  # The dates a selection is given where it names a day or a month its
  # year lacks, and says what to take for it (RFC 7529 section 4.1's
  # `SKIP`): `:forward` the next there is, `:backward` the last before it.
  #
  # A month the year lacks is a leap month in a year that has none, or a
  # month numbered past the year's last: it is changed to the month after
  # or the month before. A day the month lacks is changed to the first day
  # of the month after or to the month's last day. A month is changed
  # before a day is, so a day a changed month lacks is changed in its turn.
  #
  # With no skip a selection passes over what the year lacks, as RFC 5545
  # does; these dates are those it would pass over, moved. What a year has
  # and which month comes next are asked of the calendar.

  alias Tempo.Calendar

  @type direction :: :forward | :backward
  @type month :: pos_integer() | {pos_integer(), :leap}

  @doc """
  The dates a container, a year or a month of one, is given in place of
  those its parts name and it lacks: each the units of a date, or of a
  month where the parts name no day.
  """
  @spec replacements(module(), Tempo.Unit.units(), Tempo.Unit.selection(), direction()) ::
          [Tempo.Unit.units()]
  def replacements(calendar, container, parts, direction) do
    year = Keyword.fetch!(container, :year)
    days = for day <- listed(parts[:day]), is_integer(day) and day > 0, do: day

    for asked <- months(container, parts),
        month = month_in(calendar, year, asked, direction),
        month != nil,
        date <- dates(calendar, month, days, direction),
        do: date
  end

  # The months asked for: an ordinal month, a month by its name, or the
  # container's own where the parts name none.
  defp months(container, parts) do
    cond do
      Keyword.has_key?(parts, :traditional_month) ->
        for named <- listed(parts[:traditional_month]), month?(named), do: {:named, named}

      Keyword.has_key?(parts, :month) ->
        for month <- listed(parts[:month]), is_integer(month) and month > 0, do: {:ordinal, month}

      is_integer(container[:month]) ->
        [{:ordinal, container[:month]}]

      true ->
        []
    end
  end

  defp month?(month), do: is_integer(month) or match?({n, :leap} when is_integer(n), month)

  defp listed(nil), do: []
  defp listed(held) when is_list(held), do: held
  defp listed(held), do: [held]

  # A month of the year as `{moved?, year, month}`: where it is, or the
  # month taken for it where the year lacks it.
  defp month_in(calendar, year, {:ordinal, month}, direction) do
    last = Calendar.months_in_year(calendar, year)

    cond do
      month <= last -> {false, year, month}
      direction == :backward -> {true, year, last}
      true -> {true, year + 1, 1}
    end
  end

  defp month_in(calendar, year, {:named, named}, direction) do
    case Calendar.month_from_traditional(calendar, year, named) do
      month when is_integer(month) -> {false, year, month}
      _the_year_lacks_it -> moved_month(calendar, year, named, direction)
    end
  end

  # A leap month the year lacks is the month it would follow, or the month
  # it would come before.
  defp moved_month(calendar, year, {month, :leap}, :backward),
    do: named_month(calendar, year, month)

  defp moved_month(calendar, year, {month, :leap}, :forward),
    do: named_month(calendar, year, month + 1)

  defp moved_month(_calendar, _year, _no_month_of_the_calendar, _direction), do: nil

  defp named_month(calendar, year, named) do
    case Calendar.month_from_traditional(calendar, year, named) do
      month when is_integer(month) -> {true, year, month}
      _no_such_month -> nil
    end
  end

  # A month with no day asked for is itself where it was moved; a day is
  # given where the month was moved or lacks it.
  defp dates(_calendar, {true, year, month}, [], _direction), do: [[year: year, month: month]]
  defp dates(_calendar, {false, _year, _month}, [], _direction), do: []

  defp dates(calendar, {moved?, year, month}, days, direction) do
    last = Calendar.days_in_month(calendar, year, month)

    Enum.flat_map(days, fn
      day when day <= last and moved? -> [[year: year, month: month, day: day]]
      day when day <= last -> []
      _a_day_the_month_lacks -> [day_for(calendar, year, month, last, direction)]
    end)
  end

  defp day_for(_calendar, year, month, last, :backward), do: [year: year, month: month, day: last]

  defp day_for(calendar, year, month, _last, :forward) do
    if month < Calendar.months_in_year(calendar, year),
      do: [year: year, month: month + 1, day: 1],
      else: [year: year + 1, month: 1, day: 1]
  end
end
