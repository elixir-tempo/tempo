defmodule Tempo.Matrix.Shapes do
  @moduledoc """
  The generated half of the matrix's corpus: each shape a unit can take,
  put in each position of each form a value is written in.

  `Tempo.Matrix.Corpus` lists values by hand, a few to a class. This module
  is systematic instead. A form is the units a value is written with (a
  year, month and day; a year, week and weekday; a time of day), and a
  shape is a way of writing one unit (a set, a range, a mask, an
  unspecified unit, a group). `texts/0` puts one shape in one position at a
  time; `zoned/0` writes the dated times among them in a zone and in UTC,
  and `in_calendar/0` the dates in another calendar. `intervals/0` puts a
  shaped value at an end of an interval and of a recurrence, and `pairs/0`
  two shapes in one value: the exhaustive run uses those two.

  A text the parser refuses is not a value, and is left out when the
  corpus is read: not every shape is defined for every unit.

  """

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

  @time_units [:hour, :minute, :second]

  @plain %{
    year: "2026Y",
    month: "6M",
    day: "15D",
    hour: "10H",
    minute: "30M",
    second: "45S",
    week: "25W",
    day_of_week: "3K",
    day_of_year: "166O"
  }

  @shapes [
    set: %{
      year: "{2026,2028}Y",
      month: "{6,8}M",
      day: "{1,15}D",
      hour: "{9,17}H",
      minute: "{0,30}M",
      second: "{0,30}S",
      week: "{25,27}W",
      day_of_week: "{1,3}K",
      day_of_year: "{100,200}O"
    },
    range: %{
      year: "{2026..2028}Y",
      month: "{6..8}M",
      day: "{1..3}D",
      hour: "{9..11}H",
      minute: "{0..2}M",
      second: "{0..2}S",
      week: "{25..27}W",
      day_of_week: "{1..3}K",
      day_of_year: "{100..102}O"
    },
    range_to_end: %{
      month: "{1..-1}M",
      day: "{1..-1}D",
      hour: "{0..-1}H",
      minute: "{0..-1}M",
      second: "{0..-1}S",
      week: "{1..-1}W",
      day_of_week: "{1..-1}K",
      day_of_year: "{1..-1}O"
    },
    from_end: %{
      month: "-1M",
      day: "-1D",
      hour: "-1H",
      minute: "-1M",
      second: "-1S",
      week: "-1W",
      day_of_week: "-1K",
      day_of_year: "-1O"
    },
    mask: %{
      year: "202XY",
      month: "1XM",
      day: "1XD",
      hour: "1XH",
      minute: "3XM",
      second: "3XS",
      week: "2XW",
      day_of_year: "1XXO"
    },
    full_mask: %{
      year: "20XXY",
      month: "XXM",
      day: "XXD",
      hour: "XXH",
      minute: "XXM",
      second: "XXS",
      week: "XXW",
      day_of_week: "XK",
      day_of_year: "XXXO"
    },
    narrow_mask: %{
      month: "XM",
      day: "XD",
      hour: "XH",
      minute: "XM",
      second: "XS",
      week: "XW",
      day_of_year: "XXO"
    },
    mask_from_end: %{
      month: "-XM",
      day: "-XD",
      hour: "-XH",
      minute: "-XM",
      second: "-XS",
      week: "-XW",
      day_of_year: "-XXO"
    },
    unspecified: %{
      year: "X*Y",
      month: "X*M",
      day: "X*D",
      hour: "X*H",
      minute: "X*M",
      second: "X*S",
      week: "X*W",
      day_of_week: "X*K",
      day_of_year: "X*O"
    },
    group: %{
      month: "2G3MU",
      day: "2G10DU",
      hour: "2GT6HU",
      minute: "2GT15MU",
      second: "2GT15SU",
      week: "2G4WU"
    },
    group_of_set: %{
      month: "{1,2}G3MU",
      day: "{1,2}G10DU",
      hour: "{1,2}GT6HU",
      week: "{1,2}G4WU"
    },
    margin: %{year: "2026±2Y"},
    significant_digits: %{year: "1950S2Y"},
    qualified: %{
      year: "2026?Y",
      month: "6~M",
      day: "15%D"
    }
  ]

  @doc """
  Each form with one unit written in one shape.

  ### Returns

  * A list of `{shape, text}`, with no text twice.

  """
  @spec texts() :: [{atom(), String.t()}]
  def texts do
    for(
      form <- @forms,
      unit <- form,
      {shape, spellings} <- @shapes,
      Map.has_key?(spellings, unit),
      do: {shape, write(form, %{unit => spellings[unit]})}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  @dated_times [
    [:year, :month, :day, :hour],
    [:year, :month, :day, :hour, :minute],
    [:year, :month, :day, :hour, :minute, :second]
  ]

  @doc """
  Each dated time with one unit written in one shape, in a named zone and
  in UTC.

  ### Returns

  * A list of `{shape, text}`, with no text twice.

  """
  @spec zoned() :: [{atom(), String.t()}]
  def zoned do
    for(
      form <- @dated_times,
      unit <- form,
      {shape, spellings} <- @shapes,
      Map.has_key?(spellings, unit),
      suffix <- ["[Europe/Paris]", "Z"],
      do: {shape, write(form, %{unit => spellings[unit]}) <> suffix}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  @hebrew_forms [[:year, :month], [:year, :month, :day]]

  @doc """
  Each date of the Hebrew calendar with its month or its day written in one
  shape.

  ### Returns

  * A list of `{shape, text}`, with no text twice.

  """
  @spec in_calendar() :: [{atom(), String.t()}]
  def in_calendar do
    for(
      form <- @hebrew_forms,
      unit <- form,
      unit != :year,
      {shape, spellings} <- @shapes,
      Map.has_key?(spellings, unit),
      do: {shape, write(form, %{:year => "5786Y", unit => spellings[unit]}) <> "[u-ca=hebrew]"}
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

  * A list of `{shape, text}`, with no text twice.

  """
  @spec intervals() :: [{atom(), String.t()}]
  def intervals do
    for(
      form <- @interval_forms,
      unit <- form,
      {shape, spellings} <- @shapes,
      Map.has_key?(spellings, unit),
      shaped = write(form, %{unit => spellings[unit]}),
      text <- ["#{shaped}/2030Y", "2020Y/#{shaped}", "#{shaped}/P1M", "R3/#{shaped}/P1D"],
      do: {shape, text}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  @doc """
  Each form with two of its units written in a shape each.

  ### Returns

  * A list of `{{shape, shape}, text}`, with no text twice.

  """
  @spec pairs() :: [{{atom(), atom()}, String.t()}]
  def pairs do
    for(
      form <- @forms,
      {first, at} <- Enum.with_index(form),
      second <- Enum.drop(form, at + 1),
      {first_shape, first_spellings} <- @shapes,
      Map.has_key?(first_spellings, first),
      {second_shape, second_spellings} <- @shapes,
      Map.has_key?(second_spellings, second),
      do:
        {{first_shape, second_shape},
         write(form, %{first => first_spellings[first], second => second_spellings[second]})}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  # A form's units in order, each as it is written plainly unless `shaped`
  # holds another spelling, with the time designator before the first unit
  # of a time of day that does not carry its own (a group of hours does).
  defp write(form, shaped) do
    {date_units, time_units} = Enum.split_while(form, &(&1 not in @time_units))
    date = Enum.map_join(date_units, &spelling(&1, shaped))

    case Enum.map(time_units, &spelling(&1, shaped)) do
      [] -> date
      [first | rest] -> date <> designator(first) <> first <> Enum.join(rest)
    end
  end

  defp spelling(unit, shaped), do: Map.get(shaped, unit, @plain[unit])

  defp designator(first), do: if(String.contains?(first, "GT"), do: "", else: "T")
end
