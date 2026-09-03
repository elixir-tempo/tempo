defmodule Tempo.Iso8601.Unit do
  @moduledoc false

  # The field names are the same as those in
  # Elixir dates/times as far as possible making
  # interchange a little more obvious. Therefore
  # `:day` not `:day_of_month`.

  @sort_keys %{
    interval: 50,
    century: 40,
    decade: 35,
    year: 30,
    month: 25,
    week: 22,
    day_of_year: 20,
    # Represents day of month
    day: 19,
    day_of_week: 18,
    hour: 15,
    minute: 10,
    second: 5,
    # Sub-second fraction; finer than second, coarser than the
    # `:instance` selector index. No entry in `@unit_after` — it is
    # the finest clock unit, so it has no implicit enumerator.
    microsecond: 4,
    instance: 3
  }

  @unit_after %{
    year: {:month, 1..-1//-1},
    month: {:day, 1..-1//-1},
    week: {:day_of_week, 1..7},
    day: {:hour, 0..23},
    hour: {:minute, 0..59},
    minute: {:second, 0..59}
  }

  @units Map.keys(@sort_keys)

  def units do
    @units
  end

  @doc """
  Returns an implcit enumerator for a `t:Tempo.t/0`.

  When enumerating a t:Tempo.t/0 we check whether there
  is an explicit enumeration built it. Explicit enumerators
  are formed from selections, groups and sets.

  For all other cases, like a simple date such as
  `~o"2022-07-05` we add an additional time unit to
  act as the enumeration.

  The additional unit is the next smallest unit after
  the last unit in the struct.

  """
  def implicit_enumerator(:year = unit, calendar) do
    if calendar.calendar_base() == :month do
      Map.get(@unit_after, unit)
    else
      {:week, 1..-1//-1}
    end
  end

  def implicit_enumerator(unit, _calendar) when unit in @units do
    Map.get(@unit_after, unit)
  end

  @doc """
  The range of values a unit can take, where that range is fixed
  rather than calendar-dependent.

  Clock units and the day-of-week have the same extent in every
  context — an hour is always `0..23`, a minute `0..59` — so a
  negative bound on one of them (`{0..-1}M`, "every minute of the
  hour") resolves against this range. Units whose extent depends on
  the date (`:month`, `:day`, `:week`, `:day_of_year`) return
  `:unknown`; those resolve against a concrete year and month
  through `Tempo.Validation`, which is the only thing that knows the
  calendar's answer.

  ### Arguments

  * `unit` is a time unit atom.

  * `calendar` is the calendar module, consulted for the length of
    the week.

  ### Returns

  * `{:ok, range}` when the unit's extent is fixed.

  * `:unknown` when the extent depends on the date.

  ### Examples

      iex> Tempo.Iso8601.Unit.value_range(:minute, Calendrical.Gregorian)
      {:ok, 0..59}

      iex> Tempo.Iso8601.Unit.value_range(:month, Calendrical.Gregorian)
      :unknown

  """
  @spec value_range(atom(), module()) :: {:ok, Range.t()} | :unknown
  def value_range(:day_of_week, calendar), do: {:ok, 1..calendar.days_in_week()}

  def value_range(unit, _calendar) do
    Enum.find_value(@unit_after, :unknown, fn
      {_parent, {^unit, %Range{first: first, last: last} = range}}
      when first >= 0 and last >= 0 ->
        {:ok, range}

      _other ->
        false
    end)
  end

  @doc """
  Sorts a list of time units.

  A list of time units is the underlying representation
  of a `t:Tempo.t/0`.

  """
  def sort([{_unit, _value} | _rest] = units, direction \\ :desc) do
    Enum.sort_by(units, &sort_key(elem(&1, 0)), direction)
  end

  @doc """
  Returns the sort key for a given time unit.

  """
  def sort_key(time_unit) do
    Map.fetch!(@sort_keys, time_unit)
  end

  @doc """
  Non-raising variant of `sort_key/1`.

  ### Arguments

  * `time_unit` is the unit to look up.

  ### Returns

  * `{:ok, key}` when the unit is a known time unit.

  * `:error` when it is not, so a caller ordering a heterogeneous
    list can skip the entry rather than rescue a `KeyError`.

  ### Examples

      iex> Tempo.Iso8601.Unit.fetch_sort_key(:day)
      {:ok, 19}

      iex> Tempo.Iso8601.Unit.fetch_sort_key(:not_a_unit)
      :error

  """
  @spec fetch_sort_key(atom()) :: {:ok, integer()} | :error
  def fetch_sort_key(time_unit) do
    Map.fetch(@sort_keys, time_unit)
  end

  @doc """
  Compares two units or unit tuples returning an indicator
  of precedemce.

  """
  def compare(unit_1, unit_2) when is_atom(unit_1) and is_atom(unit_2) do
    u1 = sort_key(unit_1)
    u2 = sort_key(unit_2)

    cond do
      u1 < u2 -> :lt
      u1 > u2 -> :gt
      true -> :eq
    end
  end

  def compare({unit1, _value1}, {unit2, _value2}) do
    compare(unit1, unit2)
  end

  def compare({unit1, _value1}, unit2) when is_atom(unit1) and is_atom(unit2) do
    compare(unit1, unit2)
  end

  # Returns a boolean depending on whether the units are in an appropriate
  # order of increasing resolution. Two selection shapes need normalising
  # first: the non-scale selector tokens (`:instance`, the "Nth of" selector —
  # `2I1K` is "the 2nd Monday"; and the RRULE `:set_position`/`:wkst` filters)
  # are not time-scale units, so they are stripped; and a multi-weekday `BYDAY`
  # (`2I1K3K` = "the 2nd Monday and every Wednesday") lands as consecutive
  # `:day_of_week` entries at one resolution, so the run is collapsed first.
  def ordered?(units) when is_list(units) do
    units
    |> Enum.reject(&non_scale_token?/1)
    |> collapse_weekday_run()
    |> ordered_units?()
  end

  defp non_scale_token?(:instance), do: true
  defp non_scale_token?({unit, _value}) when unit in [:instance, :set_position, :wkst], do: true
  defp non_scale_token?(_other), do: false

  defp collapse_weekday_run([{:day_of_week, _} = weekday, {:day_of_week, _} | rest]),
    do: collapse_weekday_run([weekday | rest])

  defp collapse_weekday_run([entry | rest]), do: [entry | collapse_weekday_run(rest)]
  defp collapse_weekday_run([]), do: []

  defp ordered_units?([unit, :group | rest]) when is_atom(unit) do
    ordered_units?([unit | rest])
  end

  defp ordered_units?([unit, :select | rest]) when is_atom(unit) do
    ordered_units?([unit | rest])
  end

  defp ordered_units?([unit, {:group, _value} | rest]) do
    ordered_units?([unit | rest])
  end

  defp ordered_units?([unit, {:select, _value} | rest]) do
    ordered_units?([unit | rest])
  end

  defp ordered_units?([unit_1, unit_2 | rest]) when is_atom(unit_1) and is_atom(unit_2) do
    if compare(unit_1, unit_2) == :gt, do: ordered_units?([unit_2 | rest]), else: false
  end

  defp ordered_units?([{unit_1, _value_1}, {unit_2, _value_2} | rest]) do
    if compare(unit_1, unit_2) == :gt, do: ordered_units?([unit_2 | rest]), else: false
  end

  defp ordered_units?([unit_1, {unit_2, _value_2} | rest]) when is_atom(unit_1) do
    if compare(unit_1, unit_2) == :gt, do: ordered_units?([unit_2 | rest]), else: false
  end

  defp ordered_units?([_unit]), do: true
  defp ordered_units?([]), do: true
end
