defmodule Tempo.Event do
  @moduledoc """
  Resolves a named computed event to its date in a given year.

  A computed event is a recurrence whose date is fixed by an algorithm rather
  than by the calendar. Three families are supported:

  * **Easter** — Western (Gregorian) and Orthodox (the same computus in the
    Julian calendar), from `Calendrical.Ecclesiastical`.

  * **Astronomical events** — the March/September equinoxes and June/December
    solstices, from `Astro`.

  * **The 24 solar terms** (jié-qì) — the fifteen-degree divisions of the solar
    year that anchor East Asian festivals such as Qīngmíng, computed for the
    Chinese meridian via `Calendrical`.

  ISO 8601-2 has no notation for such a recurrence, so Tempo carries it as a
  selection written `(name)E` (see the `E` designator in the
  [ISO 8601 conformance guide](iso8601-conformance.html)) and resolves it here,
  once per period, when a recurrence such as `~o"R/../P1Y/FL(easter)EN"` is
  materialised into a bound. The primary public API is `date/2`.

  """

  alias Calendrical.Chinese
  alias Calendrical.Ecclesiastical
  alias Calendrical.Lunisolar

  # The 24 solar terms (jié-qì) keyed by name, each at its solar ecliptic
  # longitude in degrees. The four cardinal terms coincide with the equinoxes
  # and solstices (`chunfen` = March equinox, `xiazhi` = June solstice, …).
  @solar_terms %{
    "lichun" => 315,
    "yushui" => 330,
    "jingzhe" => 345,
    "chunfen" => 0,
    "qingming" => 15,
    "guyu" => 30,
    "lixia" => 45,
    "xiaoman" => 60,
    "mangzhong" => 75,
    "xiazhi" => 90,
    "xiaoshu" => 105,
    "dashu" => 120,
    "liqiu" => 135,
    "chushu" => 150,
    "bailu" => 165,
    "qiufen" => 180,
    "hanlu" => 195,
    "shuangjiang" => 210,
    "lidong" => 225,
    "xiaoxue" => 240,
    "daxue" => 255,
    "dongzhi" => 270,
    "xiaohan" => 285,
    "dahan" => 300
  }

  @events Map.merge(
            %{
              "easter" => :easter,
              "orthodox-easter" => :orthodox_easter,
              "march-equinox" => {:equinox, :march},
              "june-solstice" => {:solstice, :june},
              "september-equinox" => {:equinox, :september},
              "december-solstice" => {:solstice, :december}
            },
            Map.new(@solar_terms, fn {name, longitude} -> {name, {:solar_term, longitude}} end)
          )

  @doc """
  Returns the names of the events `date/2` can resolve.

  ### Returns

  * A sorted list of the recognised event-name strings.

  ### Examples

      iex> length(Tempo.Event.known())
      30

      iex> "qingming" in Tempo.Event.known()
      true

  """
  @spec known() :: [String.t()]
  def known do
    @events |> Map.keys() |> Enum.sort()
  end

  @doc """
  Is `name` one of the 24 solar terms?

  ### Examples

      iex> Tempo.Event.solar_term?("qingming")
      true

      iex> Tempo.Event.solar_term?("easter")
      false

  """
  @spec solar_term?(String.t()) :: boolean()
  def solar_term?(name) when is_binary(name), do: Map.has_key?(@solar_terms, name)

  @doc """
  Resolves a named event to its `Date` in a given proleptic-Gregorian year.

  ### Arguments

  * `name` is the event name as a lowercase string — one of those `known/0`
    lists: `"easter"` or `"orthodox-easter"`, the astronomical `"march-equinox"`
    / `"june-solstice"` / `"september-equinox"` / `"december-solstice"`, or one
    of the 24 solar terms (`"qingming"`, `"lichun"`, `"dongzhi"`, …).

  * `year` is the Gregorian year the event falls in.

  ### Returns

  * `{:ok, date}` with the event's `Date` (in `Calendar.ISO`).

  * `{:error, {:unknown_event, name}}` when the name is not recognised.

  * `{:error, :year_out_of_range}` when an astronomical event is requested
    outside the range `Astro` supports (1000–3000 CE).

  ### Examples

      iex> Tempo.Event.date("easter", 2026)
      {:ok, ~D[2026-04-05]}

      iex> Tempo.Event.date("orthodox-easter", 2026)
      {:ok, ~D[2026-04-12]}

      iex> Tempo.Event.date("qingming", 2026)
      {:ok, ~D[2026-04-05]}

      iex> Tempo.Event.date("december-solstice", 2026)
      {:ok, ~D[2026-12-21]}

      iex> Tempo.Event.date("brigadoon", 2026)
      {:error, {:unknown_event, "brigadoon"}}

  """
  @spec date(String.t(), integer()) ::
          {:ok, Date.t()}
          | {:error, {:unknown_event | :uncomputable_event, term()} | :year_out_of_range}
  def date(name, year) when is_binary(name) and is_integer(year) do
    case Map.fetch(@events, name) do
      {:ok, spec} -> resolve(spec, year)
      :error -> {:error, {:unknown_event, name}}
    end
  end

  defp resolve(:easter, year), do: ecclesiastical_date(Ecclesiastical.easter_sunday(year))

  defp resolve(:orthodox_easter, year),
    do: ecclesiastical_date(Ecclesiastical.orthodox_easter_sunday(year))

  defp resolve({:equinox, event}, year), do: from_datetime(Astro.equinox(year, event))
  defp resolve({:solstice, event}, year), do: from_datetime(Astro.solstice(year, event))
  defp resolve({:solar_term, longitude}, year), do: solar_term_date(longitude, year)

  defp from_datetime({:ok, %DateTime{} = datetime}), do: {:ok, DateTime.to_date(datetime)}
  defp from_datetime({:error, _reason} = error), do: error

  # `Calendrical.Ecclesiastical` returns a `Calendrical.Gregorian` (Western) or
  # `Calendrical.Julian` (Orthodox) date; normalise both to `Calendar.ISO`.
  defp ecclesiastical_date(%Date{} = date) do
    case Date.convert(date, Calendar.ISO) do
      {:ok, %Date{} = iso} -> {:ok, iso}
      _error -> {:error, {:uncomputable_event, :easter}}
    end
  end

  # The day the sun first reaches `longitude` on or after the year's start, at
  # the Chinese meridian (via `Calendrical`), as a `Calendar.ISO` date.
  defp solar_term_date(longitude, year) do
    with {:ok, %Date{} = start} <- Date.new(year, 1, 1, Calendrical.Gregorian),
         moment when is_number(moment) <-
           Lunisolar.solar_longitude_on_or_after(
             longitude,
             Calendrical.date_to_iso_days(start),
             &Chinese.location/1
           ),
         %Date{} = date <- Calendrical.date_from_iso_days(floor(moment), Calendrical.Gregorian),
         {:ok, %Date{} = iso} <- Date.convert(date, Calendar.ISO) do
      {:ok, iso}
    else
      _other -> {:error, {:uncomputable_event, {:solar_term, longitude}}}
    end
  end
end
