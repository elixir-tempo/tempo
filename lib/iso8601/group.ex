defmodule Tempo.Iso8601.Group do
  @moduledoc false

  alias Tempo.Iso8601.Group
  alias Tempo.Iso8601.Parser
  alias Tempo.ParseError

  # This module expands groups into base time units.
  # For example, it exapands:
  #  * quarters
  #  * quadrimester
  #  * semestrals
  #  * seasons (meterological, not astronomical)

  @quarters_in_year 4
  @quadrimesters_in_year 3
  @semestrals_in_year 2

  def expand_groups(tempo, calendar \\ Calendrical.Gregorian)

  def expand_groups(%Tempo{time: time} = tempo, calendar) do
    case expand_groups(time, calendar) do
      {:error, reason} -> {:error, reason}
      %Tempo.Interval{} = interval -> {:ok, interval}
      time -> {:ok, %{tempo | time: time}}
    end
  end

  def expand_groups(%Tempo.Duration{time: time} = tempo, calendar) do
    case expand_groups(time, calendar) do
      {:error, reason} -> {:error, reason}
      time -> {:ok, %{tempo | time: time}}
    end
  end

  def expand_groups(%Tempo.Interval{} = tempo, calendar) do
    with {:ok, from} <- expand_groups(tempo.from, calendar),
         {:ok, to} <- expand_groups(tempo.to, calendar),
         {:ok, duration} <- expand_groups(tempo.duration, calendar) do
      {:ok, %{tempo | from: from, to: to, duration: duration}}
    end
  end

  def expand_groups(%Tempo.Set{set: set} = tempo, calendar) do
    expanded =
      Enum.reduce_while(set, [], fn elem, acc ->
        case expand_groups(elem, calendar) do
          {:error, reason} -> {:halt, {:error, reason}}
          {:ok, tempo} -> {:cont, [tempo | acc]}
        end
      end)

    case expanded do
      {:error, reason} -> {:error, reason}
      expanded -> {:ok, %{tempo | set: Enum.reverse(expanded)}}
    end
  end

  def expand_groups(nil, _calendar) do
    {:ok, nil}
  end

  def expand_groups(:undefined, _calendar) do
    {:ok, :undefined}
  end

  def expand_groups(%Tempo.Range{first: first, last: last}, calendar) do
    with {:ok, first} <- expand_groups(first, calendar),
         {:ok, last} <- expand_groups(last, calendar) do
      {:ok, %Tempo.Range{first: first, last: last}}
    end
  end

  # Seasons (ISO 8601-2 Part 2, Table 2)
  #
  # Codes 25-32 are **astronomical** seasons: the boundaries are the
  # March and September equinoxes and the June and December solstices
  # as computed by the `Astro` library (accurate to ~2 minutes for
  # years 1000..3000 CE).
  #
  # * 25 = Spring (Northern) / 31 = Autumn (Southern) — March equinox → June solstice
  # * 26 = Summer (Northern) / 32 = Winter (Southern) — June solstice → September equinox
  # * 27 = Autumn (Northern) / 29 = Spring (Southern) — September equinox → December solstice
  # * 28 = Winter (Northern) / 30 = Summer (Southern) — December solstice (year Y) → March equinox (year Y+1)
  #
  # Codes 21-24 are generic (hemisphere-unspecified) seasons and are
  # handled separately as meteorological approximations; see the
  # clauses below.

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in [25, 31] do
    astronomical_season(year, rest, calendar, :march, :june)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in [26, 32] do
    astronomical_season(year, rest, calendar, :june, :september)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in [27, 29] do
    astronomical_season(year, rest, calendar, :september, :december)
  end

  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in [28, 30] do
    astronomical_season(year, rest, calendar, :december, :march_next)
  end

  # Meteorological seasons 21-24 (hemisphere-unspecified — we default to
  # Northern hemisphere meteorological boundaries as a conventional
  # interpretation).

  def expand_groups([{:year, year}, {:month, 21} | rest], calendar) do
    meteorological_season(year, rest, calendar, 3, 5)
  end

  def expand_groups([{:year, year}, {:month, 22} | rest], calendar) do
    meteorological_season(year, rest, calendar, 6, 8)
  end

  def expand_groups([{:year, year}, {:month, 23} | rest], calendar) do
    meteorological_season(year, rest, calendar, 9, 11)
  end

  def expand_groups([{:year, year}, {:month, 24} | rest], calendar) do
    # Winter: December of previous year through February of this year.
    season_interval(
      [{:year, year - 1}, {:month, 12} | rest],
      [{:year, year}, {:month, 2} | rest],
      calendar
    )
  end

  # Reformat quarters as groups of months
  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 33..36 do
    months_in_year = calendar.months_in_year(year)
    months_in_quarter = div(months_in_year, @quarters_in_year)

    quarter = month - 32
    start = (quarter - 1) * months_in_quarter + 1

    finish =
      if quarter == @quarters_in_year, do: months_in_year, else: start + months_in_quarter - 1

    expand_groups([{:year, year}, {:month, {:group, start..finish}} | rest], calendar)
  end

  # Reformat quadrimester (third of a year) as groups of months
  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 37..39 do
    months_in_year = calendar.months_in_year(year)
    months_in_quadrimester = div(months_in_year, @quadrimesters_in_year)

    quadrimester = month - 36
    start = (quadrimester - 1) * months_in_quadrimester + 1

    finish =
      if quadrimester == @quadrimesters_in_year,
        do: months_in_year,
        else: start + months_in_quadrimester - 1

    expand_groups([{:year, year}, {:month, {:group, start..finish}} | rest], calendar)
  end

  # Reformat semestrals (half a year) as groups of months
  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 40..41 do
    months_in_year = calendar.months_in_year(year)
    months_in_semestral = div(months_in_year, @semestrals_in_year)

    semestral = month - 39
    start = (semestral - 1) * months_in_semestral + 1

    finish =
      if semestral == @semestrals_in_year,
        do: months_in_year,
        else: start + months_in_semestral - 1

    expand_groups([{:year, year}, {:month, {:group, start..finish}} | rest], calendar)
  end

  def expand_groups([{:group, [{:nth, nth}, {unit, value}]} | rest], calendar) do
    first = (nth - 1) * value + 1
    last = nth * value

    expand_groups([{unit, {:group, first..last//1}} | rest], calendar)
  end

  def expand_groups([{:group, [{:all_of, set}, {unit, value}]} | rest], calendar) do
    prepend({unit, {:group, {:all, set}}, value}, expand_groups(rest, calendar))
  end

  def expand_groups([{:group, [{:one_of, set}, {unit, value}]} | rest], calendar) do
    prepend({unit, {:group, {:one, set}}, value}, expand_groups(rest, calendar))
  end

  # TODO implement complex groups
  def expand_groups([{:group, group} | _rest], _calendar) do
    {:error,
     ParseError.exception(reason: "Complex groupings not yet supported. Found #{inspect(group)}")}
  end

  def expand_groups([first | rest], calendar) do
    prepend(first, expand_groups(rest, calendar))
  end

  def expand_groups(other, _calendar) do
    other
  end

  # An error expanding the rest of the list is the list's error.
  defp prepend(_first, {:error, _reason} = error), do: error
  defp prepend(first, time), do: [first | time]

  ## Season helpers

  # Expand an astronomical season into an interval whose boundaries
  # are the relevant equinox or solstice dates. The boundaries are
  # inclusive on the lower end and exclusive on the upper end
  # (matching the half-open `[first, last)` convention).
  defp astronomical_season(year, rest, calendar, start_event, :march_next) do
    with {:ok, start_date} <- season_boundary_date(year, start_event),
         {:ok, end_date} <- season_boundary_date(year + 1, :march) do
      build_season_interval(start_date, end_date, rest, calendar)
    end
  end

  defp astronomical_season(year, rest, calendar, start_event, end_event) do
    with {:ok, start_date} <- season_boundary_date(year, start_event),
         {:ok, end_date} <- season_boundary_date(year, end_event) do
      build_season_interval(start_date, end_date, rest, calendar)
    end
  end

  defp season_boundary_date(year, event) when event in [:march, :september] do
    year |> Astro.equinox(event) |> season_boundary(year, event)
  end

  defp season_boundary_date(year, event) when event in [:june, :december] do
    year |> Astro.solstice(event) |> season_boundary(year, event)
  end

  defp season_boundary({:ok, %DateTime{} = datetime}, _year, _event) do
    {:ok, DateTime.to_date(datetime)}
  end

  # Astro computes equinoxes and solstices for a bounded span of years
  # and returns `{:error, :year_out_of_range}` beyond it.
  defp season_boundary({:error, reason}, year, event) do
    {:error,
     ParseError.exception(
       reason:
         "The #{boundary_name(event)} of #{year}, which bounds this season, " <>
           "cannot be computed (#{inspect(reason)})"
     )}
  end

  defp boundary_name(:march), do: "March equinox"
  defp boundary_name(:june), do: "June solstice"
  defp boundary_name(:september), do: "September equinox"
  defp boundary_name(:december), do: "December solstice"

  defp build_season_interval(%Date{} = start_date, %Date{} = end_date, rest, calendar) do
    season_interval(
      [{:year, start_date.year}, {:month, start_date.month}, {:day, start_date.day} | rest],
      [{:year, end_date.year}, {:month, end_date.month}, {:day, end_date.day} | rest],
      calendar
    )
  end

  defp meteorological_season(year, rest, calendar, start_month, end_month) do
    season_interval(
      [{:year, year}, {:month, start_month} | rest],
      [{:year, year}, {:month, end_month} | rest],
      calendar
    )
  end

  # The interval between a season's boundaries, or the error building
  # it returns.
  defp season_interval(from, to, calendar) do
    [interval: [datetime: from, datetime: to]]
    |> Parser.parse()
    |> Group.expand_groups(calendar)
    |> season_interval_result()
  end

  defp season_interval_result({:ok, interval}), do: interval
  defp season_interval_result({:error, _reason} = error), do: error
end
