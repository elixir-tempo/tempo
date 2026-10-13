defmodule Tempo.Season do
  @moduledoc false

  # The dates of a season (ISO 8601-2 §4.8.1), as decided on 8 and 9 October
  # 2026 (`plans/seasons-by-locale.md`) and carried into the engine on 14
  # October (`plans/decisions.md`, 19 and 20).
  #
  # The seasons 21 to 24 are meteorological: whole months, three to a
  # season, and which three is the hemisphere's to say, so one of them has
  # dates in a territory and none without. The seasons 25 to 28 are the
  # northern hemisphere's and 29 to 32 the southern's, astronomical: each
  # from an equinox or a solstice to the next, as Astro reckons them, and
  # each names its hemisphere.
  #
  # The months of a meteorological season are a convention and are held
  # here; the hemisphere of a territory is Localize's, and the day of an
  # equinox or a solstice Astro's.

  alias Localize.Territory.Hemisphere
  alias Tempo.Calendar
  alias Tempo.ConversionError
  alias Tempo.Territory

  # The first month of each meteorological season, by hemisphere. A season
  # is that month and the two after it, into the next year where they run.
  @first_month %{
    northern: %{21 => 3, 22 => 6, 23 => 9, 24 => 12},
    southern: %{21 => 9, 22 => 12, 23 => 3, 24 => 6}
  }

  @months_in_season 3

  # What each astronomical season begins at, and how many seasons on it ends.
  @turns [{:equinox, :march}, {:solstice, :june}, {:equinox, :september}, {:solstice, :december}]
  @begins_at %{25 => 0, 26 => 1, 27 => 2, 28 => 3, 29 => 2, 30 => 3, 31 => 0, 32 => 1}

  @meteorological 21..24
  @astronomical 25..32

  @doc "Whether a season is one of the four that have dates only in a hemisphere."
  @spec abstract?(term()) :: boolean()
  def abstract?(season), do: season in @meteorological

  @doc """
  The first and the last month of a meteorological season of a year in a
  territory, each with its year: `{{year, month}, {year, month}}`.
  """
  @spec months(integer(), 21..24, atom()) ::
          {:ok, {{integer(), 1..12}, {integer(), 1..12}}} | {:error, {:no_hemisphere, atom()}}
  def months(year, season, territory) when season in @meteorological do
    case Hemisphere.hemisphere(territory) do
      {:ok, hemisphere} when hemisphere in [:northern, :southern] ->
        first = @first_month |> Map.fetch!(hemisphere) |> Map.fetch!(season)
        {:ok, {{year, first}, months_on(year, first, @months_in_season - 1)}}

      _ambiguous_or_unknown ->
        {:error, {:no_hemisphere, territory}}
    end
  end

  @doc """
  An expression with each meteorological season in it given its months in a
  territory: a value is the interval of its three months, an end of an
  interval the first or the last of them, and a set each of its members. A
  season of a hemisphere, and what is no season, is as it was. The result
  is not yet held to the order of its ends.
  """
  @spec in_territory(Tempo.t(), atom()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def in_territory(%Tempo{form: {:value, [year: year, season: season]}} = value, territory)
      when is_integer(year) and season in @meteorological do
    with {:ok, {first, last}} <- months_of(value, territory) do
      {:ok, %{value | form: {:span, month(value, first), month(value, last)}}}
    end
  end

  def in_territory(%Tempo{form: {:span, from, to}} = span, territory) do
    with {:ok, from} <- an_end(from, territory, :first),
         {:ok, to} <- an_end(to, territory, :last) do
      {:ok, %{span | form: {:span, from, to}}}
    end
  end

  def in_territory(%Tempo{form: {kind, members}} = set, territory)
      when kind in [:all, :one] and is_list(members) do
    members
    |> Enum.reduce_while({:ok, []}, &member_in(&1, &2, territory))
    |> in_order(set, kind)
  end

  def in_territory(%Tempo{} = other, _territory), do: {:ok, other}

  defp member_in(member, {:ok, done}, territory) do
    case in_territory(member, territory) do
      {:ok, member} -> {:cont, {:ok, [member | done]}}
      {:error, _exception} = error -> {:halt, error}
    end
  end

  defp in_order({:ok, members}, set, kind),
    do: {:ok, %{set | form: {kind, Enum.reverse(members)}}}

  defp in_order({:error, _exception} = error, _set, _kind), do: error

  # An end of an interval that is a meteorological season is the first of
  # its months where the interval begins, and the last where it ends.
  defp an_end(%Tempo{form: {:value, [year: year, season: season]}} = value, territory, which)
       when is_integer(year) and season in @meteorological do
    with {:ok, {first, last}} <- months_of(value, territory) do
      {:ok, month(value, if(which == :first, do: first, else: last))}
    end
  end

  defp an_end(other, _territory, _which), do: {:ok, other}

  defp months_of(%Tempo{form: {:value, [year: year, season: season]}} = value, territory) do
    case months(year, season, territory) do
      {:ok, months} -> {:ok, months}
      {:error, reason} -> {:error, ConversionError.exception(value: value, reason: reason)}
    end
  end

  defp month(%Tempo{} = value, {year, month}),
    do: %{value | form: {:value, [year: year, month: month]}}

  @doc """
  The span of days a season of a year is, on the day scale. An astronomical
  season runs from the day of its equinox or solstice to the day before the
  next. A meteorological season is its months in the hemisphere of the
  territory in force: the application's `:default_territory`, then the
  current locale's. `{:error, :season}` where it has none, and in a calendar
  whose years are not the Gregorian calendar's.
  """
  @spec day_span(module(), integer(), 21..32) :: {:ok, Calendar.span()} | {:error, term()}
  def day_span(calendar, year, season) when is_integer(year) and season in 21..32 do
    if Calendar.gregorian?(calendar),
      do: days(calendar, year, season),
      else: {:error, :season}
  end

  def day_span(_calendar, _year, _season), do: {:error, :season}

  defp days(calendar, year, season) when season in @astronomical do
    first = Map.fetch!(@begins_at, season)

    with {:ok, start} <- turn(calendar, year, first),
         {:ok, stop} <- turn(calendar, year, first + 1) do
      {:ok, {start, stop}}
    end
  end

  defp days(calendar, year, season) when season in @meteorological do
    with {:ok, territory} <- Territory.resolve(nil),
         {:ok, {{first_year, first}, {last_year, last}}} <- months(year, season, territory),
         {:ok, {start, _}} <- Calendar.period(calendar, :month, first_year, first),
         {:ok, {_, stop}} <- Calendar.period(calendar, :month, last_year, last) do
      {:ok, {start, stop}}
    end
    |> a_span()
  end

  defp a_span({:ok, _span} = span), do: span
  defp a_span({:error, {:no_hemisphere, _territory}} = error), do: error
  defp a_span(_no_territory), do: {:error, :season}

  # The day an equinox or a solstice falls on, the turns counted from the
  # March equinox of a year and on into the next.
  defp turn(calendar, year, index) do
    {kind, event} = Enum.at(@turns, rem(index, length(@turns)))
    year = year + div(index, length(@turns))

    case instant(kind, year, event) do
      {:ok, %DateTime{year: y, month: m, day: d}} -> {:ok, Calendar.iso_days(calendar, y, m, d)}
      _uncomputed -> {:error, :season}
    end
  end

  defp instant(:equinox, year, event), do: Astro.equinox(year, event)
  defp instant(:solstice, year, event), do: Astro.solstice(year, event)

  defp months_on(year, month, more) when month + more > 12, do: {year + 1, month + more - 12}
  defp months_on(year, month, more), do: {year, month + more}
end
