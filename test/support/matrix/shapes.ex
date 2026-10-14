defmodule Tempo.Matrix.Shapes do
  @moduledoc """
  The generated half of the matrix's corpus: each shape a unit can take,
  put in each position of each form a value is made of.

  `Tempo.Matrix.Corpus` lists values by hand, a few to a class. This module
  is systematic instead. A form is the units a value is made of (a year,
  month and day; a year, week and weekday; a time of day), and a shape is
  what one unit holds (a set, a range, a mask, an unspecified unit, a
  group). Each value is built from its parts with `Tempo.new/1`, never
  written as text and read: `values/0` puts one shape in one position at a
  time; `zoned/0` places the dated times among them in a zone and at UTC,
  and `in_calendar/0` the dates in another calendar. `intervals/0` puts a
  shaped value at an end of an interval and of a recurrence, and `pairs/0`
  two shapes in one value: the exhaustive run uses those two.

  A value the builders refuse is no value, and is left out: not every shape
  is defined for every unit.

  """

  alias Tempo.{Duration, Interval}

  @forms [
    [:year],
    [:year, :month],
    [:year, :month, :day],
    [:year, :month, :day, :hour],
    [:year, :month, :day, :hour, :minute],
    [:year, :month, :day, :hour, :minute, :second],
    [:year, :week],
    [:year, :week, :day_of_week],
    [:year, :day_of_year],
    [:month],
    [:month, :day],
    [:hour],
    [:hour, :minute],
    [:day_of_week]
  ]

  @plain [
    year: 2026,
    month: 6,
    day: 15,
    hour: 10,
    minute: 30,
    second: 45,
    week: 25,
    day_of_week: 3,
    day_of_year: 166
  ]

  # Each shape as what a unit holds in place of its plain value: the units
  # it stands as, and the qualifications it carries.
  @shapes [
    set: %{
      year: [2026, 2028],
      month: [6, 8],
      day: [1, 15],
      hour: [9, 17],
      minute: [0, 30],
      second: [0, 30],
      week: [25, 27],
      day_of_week: [1, 3],
      day_of_year: [100, 200]
    },
    range: %{
      year: [2026..2028],
      month: [6..8],
      day: [1..3],
      hour: [9..11],
      minute: [0..2],
      second: [0..2],
      week: [25..27],
      day_of_week: [1..3],
      day_of_year: [100..102]
    },
    range_to_end: %{
      month: [1..-1//1],
      day: [1..-1//1],
      hour: [0..-1//1],
      minute: [0..-1//1],
      second: [0..-1//1],
      week: [1..-1//1],
      day_of_week: [1..-1//1],
      day_of_year: [1..-1//1]
    },
    from_end: %{
      month: -1,
      day: -1,
      hour: -1,
      minute: -1,
      second: -1,
      week: -1,
      day_of_week: -1,
      day_of_year: -1
    },
    mask: %{
      year: {:mask, [2, 0, 2, :x]},
      month: {:mask, [1, :x]},
      day: {:mask, [1, :x]},
      hour: {:mask, [1, :x]},
      minute: {:mask, [3, :x]},
      second: {:mask, [3, :x]},
      week: {:mask, [2, :x]},
      day_of_year: {:mask, [1, :x, :x]}
    },
    full_mask: %{
      year: {:mask, [2, 0, :x, :x]},
      month: {:mask, [:x, :x]},
      day: {:mask, [:x, :x]},
      hour: {:mask, [:x, :x]},
      minute: {:mask, [:x, :x]},
      second: {:mask, [:x, :x]},
      week: {:mask, [:x, :x]},
      day_of_week: {:mask, [:x]},
      day_of_year: {:mask, [:x, :x, :x]}
    },
    narrow_mask: %{
      month: {:mask, [:x]},
      day: {:mask, [:x]},
      hour: {:mask, [:x]},
      minute: {:mask, [:x]},
      second: {:mask, [:x]},
      week: {:mask, [:x]},
      day_of_year: {:mask, [:x, :x]}
    },
    mask_from_end: %{
      month: {:mask, [:negative, :x]},
      day: {:mask, [:negative, :x]},
      hour: {:mask, [:negative, :x]},
      minute: {:mask, [:negative, :x]},
      second: {:mask, [:negative, :x]},
      week: {:mask, [:negative, :x]},
      day_of_year: {:mask, [:negative, :x, :x]}
    },
    unspecified: %{
      year: :any,
      month: :any,
      day: :any,
      hour: :any,
      minute: :any,
      second: :any,
      week: :any,
      day_of_week: :any,
      day_of_year: :any
    },
    group: %{
      month: {:group, {2, [month: 3]}},
      day: {:group, {2, [day: 10]}},
      hour: {:group, {2, [hour: 6]}},
      minute: {:group, {2, [minute: 15]}},
      second: {:group, {2, [second: 15]}},
      week: {:group, {2, [week: 4]}}
    },
    group_of_set: %{
      month: {:group, {[1, 2], [month: 3]}},
      day: {:group, {[1, 2], [day: 10]}},
      hour: {:group, {[1, 2], [hour: 6]}},
      week: {:group, {[1, 2], [week: 4]}}
    },
    margin: %{year: {2026, [margin: 2]}},
    significant_digits: %{year: {1950, [significant: 2]}},
    qualified: %{
      year: {:qualified, 2026, :uncertain},
      month: {:qualified, 6, :approximate},
      day: {:qualified, 15, :both}
    }
  ]

  @doc """
  Each form with one unit in one shape.

  ### Returns

  * A list of `{shape, value}`, with no value twice.

  """
  @spec values() :: [{atom(), Tempo.t()}]
  def values do
    for(
      form <- @forms,
      unit <- form,
      {shape, holdings} <- @shapes,
      Map.has_key?(holdings, unit),
      {:ok, value} <- [built(form, %{unit => holdings[unit]}, [])],
      do: {shape, value}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  @dated_times [
    [:year, :month, :day, :hour],
    [:year, :month, :day, :hour, :minute],
    [:year, :month, :day, :hour, :minute, :second]
  ]

  @doc """
  Each dated time with one unit in one shape, in a named zone and at UTC.

  ### Returns

  * A list of `{shape, value}`, with no value twice.

  """
  @spec zoned() :: [{atom(), Tempo.t()}]
  def zoned do
    for(
      form <- @dated_times,
      unit <- form,
      {shape, holdings} <- @shapes,
      Map.has_key?(holdings, unit),
      frame <- [[zone: "Europe/Paris"], [shift: [hour: 0]]],
      {:ok, value} <- [built(form, %{unit => holdings[unit]}, frame)],
      do: {shape, value}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  @hebrew_forms [[:year, :month], [:year, :month, :day]]

  @doc """
  Each date of the Hebrew calendar with its month or its day in one shape.

  ### Returns

  * A list of `{shape, value}`, with no value twice.

  """
  @spec in_calendar() :: [{atom(), Tempo.t()}]
  def in_calendar do
    for(
      form <- @hebrew_forms,
      unit <- form,
      unit != :year,
      {shape, holdings} <- @shapes,
      Map.has_key?(holdings, unit),
      shaped = %{:year => 5786, unit => holdings[unit]},
      {:ok, value} <- [built(form, shaped, calendar: Calendrical.Hebrew)],
      do: {shape, value}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  @interval_forms [
    [:year, :month, :day],
    [:year, :week, :day_of_week],
    [:year, :day_of_year]
  ]

  @doc """
  A shaped date at each end of an interval, before a duration, and as the
  start of a recurrence.

  ### Returns

  * A list of `{shape, expression}`, with no expression twice.

  """
  @spec intervals() :: [{atom(), Tempo.t()}]
  def intervals do
    for(
      form <- @interval_forms,
      unit <- form,
      {shape, holdings} <- @shapes,
      Map.has_key?(holdings, unit),
      {:ok, shaped} <- [built(form, %{unit => holdings[unit]}, [])],
      {:ok, expression} <- placed(shaped),
      do: {shape, expression}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  # A shaped value before the year 2030, after the year 2020, before a
  # month's length, and as the start of three daily repeats.
  defp placed(shaped) do
    [
      Interval.new(from: shaped, to: Tempo.new!(year: 2030)),
      Interval.new(from: Tempo.new!(year: 2020), to: shaped),
      Interval.new(from: shaped, to: Duration.new!(month: 1)),
      Tempo.every([day: 1], from: shaped, count: 3)
    ]
  end

  @doc """
  Each form with two of its units in a shape each.

  ### Returns

  * A list of `{{shape, shape}, value}`, with no value twice.

  """
  @spec pairs() :: [{{atom(), atom()}, Tempo.t()}]
  def pairs do
    for(
      form <- @forms,
      {first, at} <- Enum.with_index(form),
      second <- Enum.drop(form, at + 1),
      {first_shape, first_holdings} <- @shapes,
      Map.has_key?(first_holdings, first),
      {second_shape, second_holdings} <- @shapes,
      Map.has_key?(second_holdings, second),
      shaped = %{first => first_holdings[first], second => second_holdings[second]},
      {:ok, value} <- [built(form, shaped, [])],
      do: {{first_shape, second_shape}, value}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  # A form's units, each plain unless `shaped` holds another shape of it,
  # built with `Tempo.new/1` in the frame given.
  defp built(form, shaped, frame) do
    {units, qualifications} =
      Enum.reduce(form, {[], %{}}, fn unit, {units, qualifications} ->
        holding(unit, Map.get(shaped, unit, @plain[unit]), units, qualifications)
      end)

    Tempo.new(units ++ [qualifications: qualifications] ++ frame)
  end

  defp holding(_unit, {:group, group}, units, qualifications),
    do: {units ++ [group: group], qualifications}

  defp holding(unit, {:qualified, held, mark}, units, qualifications),
    do: {units ++ [{unit, held}], Map.put(qualifications, unit, mark)}

  defp holding(unit, held, units, qualifications),
    do: {units ++ [{unit, held}], qualifications}
end
