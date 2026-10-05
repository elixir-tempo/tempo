defmodule Tempo.Qualification do
  @moduledoc false

  # A value's qualification (ISO 8601-2 §8) is held one way: per component,
  # in `qualifications`, a map from a unit to its qualifier. A qualifier
  # written after a whole value (`2026-06?`, §8.2.1) qualifies each of its
  # components and is recorded for each, so that `2026?` and `?2026`, which
  # the standard calls one meaning (§8.2.4), are one value. A value with no
  # qualified component holds `nil`.
  #
  # The map names only units the value holds: an operation that drops a unit
  # drops its qualifier (`only/2`), and a unit an operation adds is not
  # qualified.

  @units [
    :year,
    :month,
    :day,
    :day_of_year,
    :week,
    :day_of_week,
    :hour,
    :minute,
    :second
  ]

  @date_units [:year, :month, :day, :day_of_year, :week, :day_of_week]

  @doc false
  # The units a qualifier can be written for (§8.3).
  def units, do: @units

  @doc false
  # The qualifications of a value all of whose components are qualified
  # alike: a complete qualification (§8.2.1) of the units of `time`.
  def complete(_time, nil), do: nil

  def complete(time, qualification) when is_list(time) do
    time |> present() |> Map.new(&{&1, qualification}) |> compact()
  end

  def complete(_time, _qualification), do: nil

  @doc false
  # A complete qualification laid over the qualifications a value has, a
  # component qualified two ways taking both (`?` and `~` are `%`).
  def with_complete(%Tempo{time: time, qualifications: qualifications} = tempo, qualification) do
    %{tempo | qualifications: merge(qualifications, complete(time, qualification))}
  end

  @doc false
  # Two maps of qualifications as one.
  def merge(nil, other), do: other
  def merge(qualifications, nil), do: qualifications

  def merge(%{} = qualifications, %{} = other),
    do: Map.merge(qualifications, other, fn _unit, first, second -> combine(first, second) end)

  @doc false
  # `?` (uncertain) and `~` (approximate) on one component are `%`, uncertain
  # and approximate, and a qualifier given twice is itself.
  def combine(qualifier, qualifier), do: qualifier
  def combine(_first, _second), do: :uncertain_and_approximate

  @doc false
  # The qualifier every component of a value carries, when they carry one
  # and the same: what a qualifier written after the value says (§8.2.1).
  def whole(%Tempo{qualifications: nil}), do: nil

  def whole(%Tempo{time: time, qualifications: %{} = qualifications}) when is_list(time) do
    units = present(time)

    case units |> Enum.map(&Map.get(qualifications, &1)) |> Enum.uniq() do
      [qualification] when not is_nil(qualification) ->
        if map_size(qualifications) == length(units), do: qualification

      _none_or_several ->
        nil
    end
  end

  def whole(%Tempo{}), do: nil

  @doc false
  # A value's qualifications kept for the units it holds, as an operation
  # that drops a unit leaves them.
  def only(%Tempo{qualifications: nil} = tempo), do: tempo

  def only(%Tempo{time: time, qualifications: %{} = qualifications} = tempo) when is_list(time),
    do: %{tempo | qualifications: qualifications |> Map.take(present(time)) |> compact()}

  def only(%Tempo{} = tempo), do: tempo

  @doc false
  # The qualifications of a value whose date is written again in other
  # units (a week and a weekday as a month and a day, a day of the year as a
  # date, a date in another calendar). Each unit of the date it becomes is
  # worked out from all of the units it was written with, so a qualifier of
  # any of them qualifies every one: `2026-W25-1?` is `2026-06-15?`. A
  # qualified time of day is its own.
  def rewritten(%Tempo{qualifications: nil} = tempo, _resolved), do: tempo

  def rewritten(%Tempo{qualifications: %{} = qualifications} = tempo, resolved)
      when is_list(resolved) do
    {date, clock} = Map.split(qualifications, @date_units)

    case Map.values(date) do
      [] ->
        tempo

      [first | rest] ->
        qualification = Enum.reduce(rest, first, &combine/2)
        date_units = for unit <- present(resolved), unit in @date_units, do: unit
        requalified = Map.merge(clock, Map.new(date_units, &{&1, qualification}))
        %{tempo | qualifications: compact(requalified)}
    end
  end

  def rewritten(%Tempo{} = tempo, _resolved), do: tempo

  # The qualifiable units a time list holds. A group of a set is a 3-tuple
  # and a selection holds no unit of its own.
  #
  # A group is the unit it is counted in. Where a value is built it is still
  # as it is tokenized (`{:group, [nth: 20, year: 100]}`), and was taken to
  # hold no unit: `20G100YU?` lost its qualifier, and `2026Y1G3MU?` was
  # qualified in its year alone, where a qualifier after the whole value
  # qualifies each component (ISO 8601-2 §8.2.1).
  defp present(time) do
    for entry <- time, unit <- units_of(entry), uniq: true, do: unit
  end

  defp units_of({:group, [_ | _] = group}),
    do: for({unit, _size} <- group, unit in @units, do: unit)

  defp units_of(entry) when is_tuple(entry),
    do: if(elem(entry, 0) in @units, do: [elem(entry, 0)], else: [])

  defp units_of(_entry), do: []

  defp compact(qualifications) when map_size(qualifications) == 0, do: nil
  defp compact(qualifications), do: qualifications
end
